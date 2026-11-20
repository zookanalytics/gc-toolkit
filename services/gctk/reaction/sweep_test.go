package reaction

import (
	"errors"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
)

// ready puts each bead in the store as one bd reports ready.
func (w *world) ready(beads ...fake.Bead) {
	w.t.Helper()
	w.put(beads...)
	for _, b := range beads {
		w.store.MakeReady(b.ID)
	}
}

// sweep runs one sweep, and returns the line each candidate got, its summary
// and its error.
func (w *world) sweep(dryRun bool, deadline time.Duration) ([]Swept, string, error) {
	w.t.Helper()
	var lines []Swept
	summary, err := w.r.Sweep(dryRun, deadline, func(s Swept) { lines = append(lines, s) })
	return lines, summary, err
}

// ids is the beads among lines with the outcome named, every bead when it is
// empty, in the sweep's order.
func ids(lines []Swept, outcome string) []string {
	var out []string
	for _, l := range lines {
		if outcome == "" || l.Outcome == outcome {
			out = append(out, l.ID)
		}
	}
	return out
}

// The candidate rule keeps the raw input among the ready beads and drops each
// bead that is no input: a standing record, a feedback pattern, a review lane,
// a route or an arm, a capped one included, a dispatch hold in any case, a
// topology root, a step of any formula, a reaction's own included, a type the
// allowlist leaves out, no description, a work marker and a parent. Keys left
// blank, a step key left empty and the retired placement marker decide
// nothing.
func TestTheSweepKeepsOnlyRawInput(t *testing.T) {
	meta := func(kv ...string) func(*fake.Bead) {
		return func(b *fake.Bead) {
			for i := 0; i+1 < len(kv); i += 2 {
				b.Metadata[kv[i]] = kv[i+1]
			}
		}
	}
	keep := map[string]func(*fake.Bead){
		"tk-raw":        nil,
		"tk-blank":      meta("gc.routed_to", " ", "gc.dispatch_when_ready", " "),
		"tk-step-blank": meta("gc.step_ref", ""),
		"tk-old-marker": meta("placement", "pending"),
		"tk-bug":        func(b *fake.Bead) { b.IssueType = "bug" },
		"tk-feature":    func(b *fake.Bead) { b.IssueType = "feature" },
		"tk-spike":      func(b *fake.Bead) { b.IssueType = "spike" },
		"tk-exec-only":  meta("gc.execution_routed_to", "gc-toolkit/gc-toolkit.polecat"),
	}
	drop := map[string]func(*fake.Bead){
		"tk-pattern":       meta("task_kind", feedbackPattern),
		"tk-review":        meta("task_kind", "review"),
		"tk-routed":        meta("gc.routed_to", "gc-toolkit/gc-toolkit.polecat"),
		"tk-armed":         meta("gc.dispatch_when_ready", "gc-toolkit/gc-toolkit.polecat", "gc.dispatch_when_ready_args", "[]"),
		"tk-capped":        meta("gc.dispatch_when_ready", "gc-toolkit/gc-toolkit.polecat", "gc.dispatch_when_ready_fail_count", "3"),
		"tk-held-bug":      func(b *fake.Bead) { b.IssueType = "bug"; b.Labels = []string{"hold:mayor"} },
		"tk-held-proposal": func(b *fake.Bead) { b.Labels = []string{"learning", "prompt-update", "hold:mayor"} },
		"tk-held-external": func(b *fake.Bead) { b.Labels = []string{"Hold:External"} },
		"tk-workflow":      meta("gc.kind", "workflow"),
		"tk-scope":         meta("gc.kind", "scope"),
		"tk-spec-root":     meta("gc.kind", "spec"),
		"tk-step-validate": meta("gc.step_ref", "mol-validate.rule-convergence", "gc.step_id", "rule-convergence", "gc.root_bead_id", "tk-root-validate"),
		"tk-step-react":    meta("gc.step_ref", "mol-first-reaction.react", "gc.step_id", "react", "gc.root_bead_id", "tk-root-reaction"),
		"tk-step-finalize": meta("gc.kind", "workflow-finalize", "gc.root_bead_id", "tk-root-work"),
		"tk-step-id":       meta("gc.step_id", "react"),
		"tk-step-ref":      meta("gc.step_ref", "mol-polecat-work.implement"),
		"tk-decision":      func(b *fake.Bead) { b.IssueType = "decision" },
		"tk-convoy":        func(b *fake.Bead) { b.IssueType = "convoy" },
		"tk-silent":        func(b *fake.Bead) { b.Description = "" },
		"tk-branch":        meta("branch", "polecat/tk-branch"),
		"tk-merge":         meta("merge_result", "pending"),
		"tk-workdir":       meta("work_dir", "/tmp/tree"),
		"tk-pr-url":        meta("pr_url", "https://github.com/zook/repo/pull/1"),
		"tk-pr-number":     meta("pr_number", "1"),
		"tk-lane":          meta("check_name", "correctness"),
		"tk-anchored":      meta("anchor_bead", "tk-anchor"),
		"tk-member":        func(b *fake.Bead) { b.Edges = []gcbd.Edge{{Type: gcbd.EdgeParentChild, ID: "tk-epic"}} },
	}
	for _, k := range standingKinds {
		drop["tk-standing-"+k] = meta("task_kind", k)
	}
	w := newWorld(t)
	for id, edit := range keep {
		w.ready(input(id, edit))
	}
	for id, edit := range drop {
		w.ready(input(id, edit))
	}
	lines, summary, err := w.sweep(true, time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	got := ids(lines, WouldSling)
	for id := range keep {
		if !slices.Contains(got, id) {
			t.Errorf("(KEEP) %s is no candidate", id)
		}
	}
	for id := range drop {
		if slices.Contains(got, id) {
			t.Errorf("(DROP) %s is a candidate", id)
		}
	}
	if len(got) != len(keep) || !strings.Contains(summary, "--dry-run slung none") || len(w.slings()) > 0 {
		t.Errorf("(DRY-RUN) the dry run listed %v, said %q, and slung %v", got, summary, w.slings())
	}
}

// A bead that carries a headline, gc.takeaway or gc.takeaway_by, has been
// triaged: every exit of a first reaction writes one, a blocker a blocked exit
// filed among the beads it lands on, so no later sweep offers it. Each key
// drops a bead alone.
func TestTheCandidateRuleDropsAHeadline(t *testing.T) {
	w := newWorld(t)
	w.ready(input("tk-fresh", nil),
		input("tk-headline", func(b *fake.Bead) { b.Metadata["gc.takeaway"] = "blocked on tk-blocker" }),
		input("tk-headline-by", func(b *fake.Bead) { b.Metadata["gc.takeaway_by"] = "proactive" }))
	lines, _, err := w.sweep(true, time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	if got := ids(lines, WouldSling); !slices.Equal(got, []string{"tk-fresh"}) {
		t.Errorf("(HEADLINE) the candidates are %v; want tk-fresh alone", got)
	}
}

// A sweep slings every candidate nobody has decided on, highest priority
// first, with no cap, and counts the slings alone. A bead decided since the
// ready read, which the read's rows do not show, is refused at its sling and
// counted under its cause.
func TestTheSweepSlingsEveryCandidateWithNoCap(t *testing.T) {
	w := newWorld(t)
	for _, id := range []string{"tk-many-1", "tk-many-2", "tk-many-3", "tk-many-4", "tk-many-5"} {
		w.ready(input(id, func(b *fake.Bead) { b.Priority = 1 }))
	}
	w.ready(input("tk-late-routed", func(b *fake.Bead) { b.Priority = 2 }), input("tk-late-held", func(b *fake.Bead) { b.Priority = 2 }),
		input("tk-urgent", func(b *fake.Bead) { b.Priority = 0 }))
	sling, once := w.rt.OnSling, sync.Once{}
	w.rt.OnSling = func(s gascity.Sling) gascity.SlingResult {
		once.Do(func() {
			routed, _ := w.store.Row("tk-late-routed")
			routed.Metadata = map[string]string{"gc.routed_to": "gc-toolkit/gc-toolkit.polecat"}
			w.store.Put(routed)
			held, _ := w.store.Row("tk-late-held")
			held.Labels = []string{"hold:mayor"}
			w.store.Put(held)
		})
		return sling(s)
	}
	lines, summary, err := w.sweep(false, 5*time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"tk-urgent", "tk-many-1", "tk-many-2", "tk-many-3", "tk-many-4", "tk-many-5"}
	if got := w.slings(); !slices.Equal(got, want) {
		t.Errorf("(SWEEP-NOCAP) the sweep slung %v; want %v, highest priority first", got, want)
	}
	if want := "slung 6 first reaction(s) (2 already routed, armed, held, assigned or waiting on a person)"; summary != want {
		t.Errorf("(SWEEP-COUNT) the summary is %q; want %q", summary, want)
	}
	if got := ids(lines, Refused); !slices.Equal(got, []string{"tk-late-held", "tk-late-routed"}) {
		t.Errorf("(SWEEP-COUNT) the refused lines are %v", got)
	}
	for _, l := range lines {
		if l.Outcome == Refused && (l.Code != Decided || l.Why == "") {
			t.Errorf("(SWEEP-COUNT) %s's line %+v names no refusal", l.ID, l)
		}
	}
}

// A sweep counts each refusal under its cause and each failure as one, in its
// summary and in each candidate's line.
func TestASweepCountsEachSkipByItsCause(t *testing.T) {
	w := newWorld(t)
	w.ready(input("tk-free", nil), input("tk-talked", nil), input("tk-raced", nil), input("tk-broke", nil))
	w.put(fake.Bead{ID: "tk-conv", Status: "open", IssueType: "task", Assignee: "human", Edges: []gcbd.Edge{{Type: "tracks", ID: "tk-talked"}}})
	sling := w.rt.OnSling
	w.rt.OnSling = func(s gascity.Sling) gascity.SlingResult {
		switch s.Bead {
		case "tk-raced":
			return gascity.SlingResult{Result: gascity.Result{Code: 3, Output: "gc sling: source bead tk-raced already has live workflow(s): tk-root-raced"}, Live: []string{"tk-root-raced"}}
		case "tk-broke":
			return gascity.SlingResult{Result: gascity.Result{Code: 1, Output: "gc sling: fake refusal"}}
		}
		return sling(s)
	}
	lines, summary, err := w.sweep(false, 5*time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	if want := "slung 1 first reaction(s) (2 already reacting or in a conversation, 1 not slung for an error)"; summary != want {
		t.Errorf("(SWEEP-LIVE) the summary is %q; want %q", summary, want)
	}
	byID := map[string]Swept{}
	for _, l := range lines {
		byID[l.ID] = l
	}
	if l := byID["tk-free"]; l.Outcome != Slung {
		t.Errorf("tk-free's line is %+v", l)
	}
	if l := byID["tk-talked"]; l.Outcome != Refused || l.Code != Reacting || !strings.Contains(l.Why, "tk-conv") {
		t.Errorf("tk-talked's line is %+v", l)
	}
	if l := byID["tk-raced"]; l.Outcome != Refused || l.Code != Reacting || !strings.Contains(l.Why, "tk-root-raced") {
		t.Errorf("tk-raced's line is %+v", l)
	}
	if l := byID["tk-broke"]; l.Outcome != Failed || !strings.Contains(l.Why, "gc sling refused or failed on tk-broke") {
		t.Errorf("tk-broke's line is %+v", l)
	}
}

// The sweep starts no sling once less of its deadline is left than its slowest
// sling took, each figure taken in whole seconds as its upper bound, and leaves
// the rest for the next sweep, naming the deadline it kept. Each sling here
// takes five seconds and the sweep has eight: the first starts with time to
// spare, and once it has taken five, less than that is left.
func TestTheSweepStopsBeforeItsDeadline(t *testing.T) {
	w := newWorld(t)
	w.ready(input("tk-a", nil), input("tk-b", nil), input("tk-c", nil))
	clock := time.Date(2026, 11, 17, 0, 0, 0, 0, time.UTC)
	w.r.Now = func() time.Time { return clock }
	sling := w.rt.OnSling
	w.rt.OnSling = func(s gascity.Sling) gascity.SlingResult {
		clock = clock.Add(5 * time.Second)
		return sling(s)
	}
	lines, summary, err := w.sweep(false, 8*time.Second)
	if err != nil {
		t.Fatal(err)
	}
	if got := w.slings(); !slices.Equal(got, []string{"tk-a"}) {
		t.Errorf("(SWEEP-DEADLINE) the sweep slung %v; want tk-a alone", got)
	}
	if got := ids(lines, Left); !slices.Equal(got, []string{"tk-b", "tk-c"}) {
		t.Errorf("(SWEEP-DEADLINE) the sweep left %v", got)
	}
	if !strings.Contains(summary, "slung 1 first reaction(s); 2 candidate(s) left for the next sweep") || !strings.Contains(summary, "8s (GC_PROACTIVE_SWEEP_TIMEOUT)") {
		t.Errorf("(SWEEP-DEADLINE) the summary is %q", summary)
	}
	w.reset()
	if _, summary, _ = w.sweep(false, 30*time.Second); summary != "slung 3 first reaction(s)" {
		t.Errorf("(SWEEP-DEADLINE) a deadline that fits every sling: %q", summary)
	}
}

// Each figure of the deadline is its upper bound in whole seconds: a sling that
// took four seconds counts as five, and four seconds used count as five, so a
// sweep of nine seconds whose slings take four each starts one, though two
// would have fit.
func TestTheSweepsDeadlineTakesEachFigureAsItsUpperBound(t *testing.T) {
	w := newWorld(t)
	w.ready(input("tk-a", nil), input("tk-b", nil), input("tk-c", nil))
	clock := time.Date(2026, 11, 17, 0, 0, 0, 0, time.UTC)
	w.r.Now = func() time.Time { return clock }
	sling := w.rt.OnSling
	w.rt.OnSling = func(s gascity.Sling) gascity.SlingResult {
		clock = clock.Add(4 * time.Second)
		return sling(s)
	}
	if _, summary, err := w.sweep(false, 9*time.Second); err != nil || !slices.Equal(w.slings(), []string{"tk-a"}) {
		t.Errorf("(SWEEP-DEADLINE) the sweep slung %v (%q, %v); want tk-a alone", w.slings(), summary, err)
	}
}

// A sweep's deadline is written as an order's timeout is: seconds alone or
// with an s, m or h suffix. Anything else does not read.
func TestASweepsDeadlineReadsAsAnOrdersTimeout(t *testing.T) {
	for text, want := range map[string]time.Duration{"300s": 300 * time.Second, "5m": 5 * time.Minute, "1h": time.Hour, "300": 300 * time.Second} {
		if got, err := SweepDeadline(text); err != nil || got != want {
			t.Errorf("SweepDeadline(%q) = %v, %v; want %v", text, got, err, want)
		}
	}
	if got, err := SweepDeadline(SweepTimeout); err != nil || got != 300*time.Second {
		t.Errorf("the default deadline %q reads as %v, %v", SweepTimeout, got, err)
	}
	for _, text := range []string{"soon", "", "5ms", "s", "-5s", " 300s", "5 m", "1.5h"} {
		if got, err := SweepDeadline(text); err == nil || !strings.Contains(err.Error(), "GC_PROACTIVE_SWEEP_TIMEOUT must be a duration") {
			t.Errorf("SweepDeadline(%q) = %v, %v; want it refused, naming the variable", text, got, err)
		}
	}
}

// The sweep asks whether the rig's proactive pool can take a reaction only once
// a candidate remains, by Gas City's preview of the first candidate's sling. A
// pass that finds none previews nothing, reads no roster and says it slung
// none. A target the city does not resolve, or a warning about the target,
// skips the rig. A refusal or a warning about the candidate alone says nothing
// of the pool, and neither does a preview that does not answer, which the sweep
// says, so the sweep goes on. A sweep in no rig fails before anything is read.
func TestTheSweepAsksAboutItsPoolOnlyOnceACandidateRemains(t *testing.T) {
	w := newWorld(t)
	w.rt.OnPreview = func(gascity.Sling) gascity.SlingPreview {
		return gascity.SlingPreview{Answered: true, Unresolved: true, Refused: `gc sling: agent "gc-toolkit/gc-toolkit.proactive" not found in city.toml`}
	}
	for _, dryRun := range []bool{false, true} {
		lines, summary, err := w.sweep(dryRun, time.Minute)
		if err != nil || len(lines) > 0 || strings.Contains(summary, "no sweep") || len(w.rt.Previews()) > 0 || slices.Contains(w.rt.Reads(), "roster") {
			t.Errorf("(SWEEP-NOCANDIDATE) dry run %v: %v, %q, %v, previewing %v, with the reads %v", dryRun, lines, summary, err, w.rt.Previews(), w.rt.Reads())
		}
	}
	w.ready(input("tk-a", nil))
	lines, summary, err := w.sweep(false, time.Minute)
	if err != nil || len(lines) > 0 || len(w.slings()) > 0 || !strings.Contains(summary, "no sweep in this rig: the city resolves no agent at gc-toolkit/gc-toolkit.proactive") {
		t.Errorf("(SWEEP-DELIVERABLE) %v, %q, %v", lines, summary, err)
	}
	if asked, want := w.rt.Previews(), (gascity.Sling{Rig: "gc-toolkit", Target: "gc-toolkit/gc-toolkit.proactive", Bead: "tk-a", Formula: Formula}); len(asked) != 1 || asked[0] != want {
		t.Errorf("(SWEEP-DELIVERABLE) previewed %+v; want the first candidate's sling, %+v", asked, want)
	}
	for name, c := range map[string]struct {
		preview gascity.SlingPreview
		skips   string
	}{
		"a suspended pool": {gascity.SlingPreview{Answered: true, Warnings: []string{gascity.AgentSuspended}},
			"no sweep in this rig: Gas City's preview of a first reaction's sling warns that gc-toolkit/gc-toolkit.proactive is suspended"},
		"a suspended city":               {gascity.SlingPreview{Answered: true, Warnings: []string{gascity.CitySuspended}}, "the city is suspended"},
		"a refusal of the candidate":     {gascity.SlingPreview{Answered: true, Refused: "gc sling: bead tk-a already has attached workflow tk-9"}, ""},
		"a warning about the candidate":  {gascity.SlingPreview{Answered: true, Warnings: []string{"bead tk-a is claimed by gc-toolkit/gc-toolkit.polecat-2"}}, ""},
		"a preview that does not answer": {gascity.SlingPreview{Bounded: gascity.Bounded{Code: -1, Err: gascity.ErrDeadline}}, ""},
	} {
		w.rt.OnPreview = func(gascity.Sling) gascity.SlingPreview { return c.preview }
		lines, summary, err := w.sweep(true, time.Minute)
		switch {
		case err != nil:
			t.Errorf("(SWEEP-POOL) %s: %v", name, err)
		case c.skips != "" && (len(lines) > 0 || !strings.Contains(summary, c.skips)):
			t.Errorf("(SWEEP-POOL) %s: %v, %q; want the rig skipped, saying %q", name, lines, summary, c.skips)
		case c.skips == "" && (!slices.Equal(ids(lines, WouldSling), []string{"tk-a"}) || strings.Contains(summary, "no sweep")):
			t.Errorf("(SWEEP-POOL) %s: %v, %q; want tk-a offered", name, lines, summary)
		}
	}
	w.saidHas("Gas City's preview of the sling of tk-a to gc-toolkit/gc-toolkit.proactive did not answer (ended at its deadline), so the sweep goes on",
		"(SWEEP-POOL) saying a preview that did not answer let the sweep go on")
	w.r.Rig = ""
	w.store.ReadyErr = errors.New("the ready read was made")
	if _, _, err := w.sweep(false, time.Minute); !errors.Is(err, ErrNoRig) || len(w.slings()) > 0 {
		t.Errorf("(SWEEP-FAILCLOSED) a sweep in no rig: %v", err)
	}
}

// A ready read that fails is no empty ready set: the sweep fails, and slings
// nothing.
func TestAReadyReadThatFailsFailsTheSweep(t *testing.T) {
	w := newWorld(t)
	w.store.ReadyErr = errors.New("gc bd ready exited 1: database is locked")
	_, summary, err := w.sweep(false, time.Minute)
	var se *SweepError
	if !errors.As(err, &se) || !strings.Contains(err.Error(), "the ready read failed (gc bd ready exited 1: database is locked)") || summary != "" || len(w.slings()) > 0 {
		t.Errorf("(READ-FAILCLOSED) %q, %v", summary, err)
	}
}

// The sweep drops every bead a live run works, a first reaction's among them,
// and keeps one whose root closed, one whose convoy no root names and one no
// convoy tracks, saying how many it dropped. A map of the runs that does not
// read drops nothing, and says so.
func TestTheSweepDropsWhatALiveRunWorks(t *testing.T) {
	w := newWorld(t)
	for _, id := range []string{"tk-building", "tk-reacting", "tk-built", "tk-retired", "tk-fresh"} {
		w.ready(input(id, nil))
	}
	w.run("tk-root-building", "mol-polecat-work", "tk-building", "in_progress")
	w.run("tk-root-reacting", Formula, "tk-reacting", "in_progress")
	w.run("tk-root-built", "mol-polecat-work", "tk-built", "closed")
	w.put(fake.Bead{ID: "tk-cv-retired", Status: "closed", IssueType: "convoy", Edges: []gcbd.Edge{{Type: "tracks", ID: "tk-retired"}}})
	lines, _, err := w.sweep(true, time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	if got := ids(lines, WouldSling); !slices.Equal(got, []string{"tk-built", "tk-fresh", "tk-retired"}) {
		t.Errorf("(INFLIGHT) the candidates are %v", got)
	}
	w.saidHas("2 candidate(s) already have a live workflow", "(INFLIGHT-DROP) saying how many it dropped")
	w.failFind(func(q gcbd.Query) bool { return q.HasKey == "gc.input_convoy_id" })
	lines, _, err = w.sweep(true, time.Minute)
	if err != nil || !slices.Contains(ids(lines, WouldSling), "tk-building") {
		t.Errorf("(INFLIGHT-FAILOPEN) with the map unread the candidates are %v (%v)", ids(lines, ""), err)
	}
	w.saidHas("could not read the live runs", "(INFLIGHT-FAILOPEN) saying the sweep went unfiltered")
}

// On one store state, the beads the sweep drops for a live run are exactly the
// beads the sling refuses for one, 3 or 4, since both read waits' run link.
func TestTheSweepsDropAndTheSlingsRefusalAgree(t *testing.T) {
	w := newWorld(t)
	all := []string{"tk-building", "tk-built", "tk-fresh", "tk-reacting", "tk-retired"}
	for _, id := range all {
		w.ready(input(id, nil))
	}
	w.run("tk-root-building", "mol-polecat-work", "tk-building", "in_progress")
	w.run("tk-root-reacting", Formula, "tk-reacting", "in_progress")
	w.run("tk-root-built", "mol-polecat-work", "tk-built", "closed")
	w.put(fake.Bead{ID: "tk-cv-retired", Status: "closed", IssueType: "convoy", Edges: []gcbd.Edge{{Type: "tracks", ID: "tk-retired"}}})
	lines, _, err := w.sweep(true, time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	var dropped, refused []string
	for _, id := range all {
		if !slices.Contains(ids(lines, WouldSling), id) {
			dropped = append(dropped, id)
		}
		if code, _ := w.sling(id); code == Reacting || code == Driven {
			refused = append(refused, id)
		}
	}
	if want := []string{"tk-building", "tk-reacting"}; !slices.Equal(dropped, want) || !slices.Equal(refused, want) {
		t.Errorf("(AGREE) the sweep drops %v and the sling refuses %v; want %v", dropped, refused, want)
	}
}
