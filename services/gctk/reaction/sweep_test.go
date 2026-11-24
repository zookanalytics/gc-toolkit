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

// arrival is a bead filed into the placement queue, held with hold:mayor and
// concluded on by no first reaction or sitting, its fields as f sets them.
func arrival(id string, f func(*fake.Bead)) fake.Bead {
	return input(id, func(b *fake.Bead) {
		b.Labels = append(b.Labels, "hold:mayor")
		if f != nil {
			f(b)
		}
	})
}

// meta sets each key to its value on a bead.
func meta(kv ...string) func(*fake.Bead) {
	return func(b *fake.Bead) {
		for i := 0; i+1 < len(kv); i += 2 {
			b.Metadata[kv[i]] = kv[i+1]
		}
	}
}

// The candidate rule takes a bead its filer marked for a first reaction and
// nothing else: hold:mayor in any spelling, whatever else the bead lacks or
// carries, and a patrol finding's finding.scope. A bead with no mark is never a
// candidate, however raw it looks, a withdrawal the landing order files and
// carries out itself among them, and neither is a marked bead whose headline
// shows a first reaction or a sitting concluded on it, or whose row the sling
// refuses: hold:external, a route, an arm, a standing kind or a feedback
// pattern.
func TestTheSweepTakesOnlyAMarkedBead(t *testing.T) {
	finding := meta("finding.key", "doctor-check-x", "finding.scope", "deacon-findings")
	keep := map[string]fake.Bead{
		"tk-held":             arrival("tk-held", nil),
		"tk-held-spelled":     input("tk-held-spelled", func(b *fake.Bead) { b.Labels = []string{" Hold:Mayor "} }),
		"tk-held-bug":         arrival("tk-held-bug", func(b *fake.Bead) { b.IssueType = "bug" }),
		"tk-held-chore":       arrival("tk-held-chore", func(b *fake.Bead) { b.IssueType = "chore" }),
		"tk-held-silent":      arrival("tk-held-silent", func(b *fake.Bead) { b.Description = "" }),
		"tk-held-member":      arrival("tk-held-member", func(b *fake.Bead) { b.Edges = []gcbd.Edge{{Type: gcbd.EdgeParentChild, ID: "tk-epic"}} }),
		"tk-held-branch":      arrival("tk-held-branch", meta("branch", "polecat/tk-held-branch")),
		"tk-held-blank":       arrival("tk-held-blank", meta("gc.takeaway", " ", "gc.routed_to", " ")),
		"tk-finding":          input("tk-finding", finding),
		"tk-finding-unscoped": input("tk-finding-unscoped", meta("finding.key", "doctor-check-y", "finding.scope", "unscoped")),
	}
	drop := map[string]fake.Bead{
		"tk-raw":            input("tk-raw", nil),
		"tk-raw-bug":        input("tk-raw-bug", func(b *fake.Bead) { b.IssueType = "bug" }),
		"tk-review-finding": input("tk-review-finding", meta("finding.key", "correctness:x", "task_kind", "finding", "anchor_bead", "tk-anchor")),
		"tk-withdrawal":     input("tk-withdrawal", func(b *fake.Bead) { b.Title = "Withdraw the approvals of PR #1600 at its new head" }),
		"tk-held-read":      arrival("tk-held-read", meta("gc.takeaway", "ready to build once placed", "gc.takeaway_by", "proactive")),
		"tk-held-read-by":   arrival("tk-held-read-by", meta("gc.takeaway_by", "converse")),
		"tk-finding-read":   input("tk-finding-read", func(b *fake.Bead) { finding(b); b.Metadata["gc.takeaway"] = "blocked on tk-blocker" }),
		"tk-held-external":  arrival("tk-held-external", func(b *fake.Bead) { b.Labels = append(b.Labels, "Hold:External") }),
		"tk-external":       input("tk-external", func(b *fake.Bead) { b.Labels = []string{"hold:external"} }),
		"tk-held-routed":    arrival("tk-held-routed", meta("gc.routed_to", "gc-toolkit/gc-toolkit.polecat")),
		"tk-held-armed":     arrival("tk-held-armed", meta("gc.dispatch_when_ready", "gc-toolkit/gc-toolkit.polecat", "gc.dispatch_when_ready_args", "[]")),
		"tk-finding-routed": input("tk-finding-routed", func(b *fake.Bead) { finding(b); b.Metadata["gc.routed_to"] = "gc-toolkit/gc-toolkit.polecat" }),
		"tk-held-pattern":   arrival("tk-held-pattern", meta("task_kind", feedbackPattern)),
	}
	for _, k := range standingKinds {
		drop["tk-held-standing-"+k] = arrival("tk-held-standing-"+k, meta("task_kind", k))
	}
	w := newWorld(t)
	for _, b := range keep {
		w.ready(b)
	}
	for _, b := range drop {
		w.ready(b)
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

// A headline, gc.takeaway or gc.takeaway_by, shows that a first reaction or a
// sitting concluded on a bead, since each of their exits writes one, so no
// later sweep offers it, held or a finding. Each key drops a bead alone.
func TestTheCandidateRuleDropsAHeadline(t *testing.T) {
	w := newWorld(t)
	w.ready(arrival("tk-fresh", nil),
		arrival("tk-headline", meta("gc.takeaway", "blocked on tk-blocker")),
		arrival("tk-headline-by", meta("gc.takeaway_by", "proactive")),
		input("tk-finding-read", meta("finding.scope", "witness-findings", "gc.takeaway", "close: fixed upstream")))
	lines, _, err := w.sweep(true, time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	if got := ids(lines, WouldSling); !slices.Equal(got, []string{"tk-fresh"}) {
		t.Errorf("(HEADLINE) the candidates are %v; want tk-fresh alone", got)
	}
}

// A sweep slings every candidate, highest priority first, with no cap, and
// counts the slings alone. A bead decided since the ready read, which the
// read's rows do not show, is refused at its sling and counted under its
// cause: one routed, and one a sitting read, which left it a headline.
func TestTheSweepSlingsEveryCandidateWithNoCap(t *testing.T) {
	w := newWorld(t)
	for _, id := range []string{"tk-many-1", "tk-many-2", "tk-many-3", "tk-many-4", "tk-many-5"} {
		w.ready(arrival(id, func(b *fake.Bead) { b.Priority = 1 }))
	}
	w.ready(arrival("tk-late-routed", func(b *fake.Bead) { b.Priority = 2 }), arrival("tk-late-read", func(b *fake.Bead) { b.Priority = 2 }),
		arrival("tk-urgent", func(b *fake.Bead) { b.Priority = 0 }))
	sling, once := w.rt.OnSling, sync.Once{}
	w.rt.OnSling = func(s gascity.Sling) gascity.SlingResult {
		once.Do(func() {
			routed, _ := w.store.Row("tk-late-routed")
			routed.Metadata = map[string]string{"gc.routed_to": "gc-toolkit/gc-toolkit.polecat"}
			w.store.Put(routed)
			read, _ := w.store.Row("tk-late-read")
			read.Metadata = map[string]string{"gc.takeaway": "leave held: an epic for it is coming", "gc.takeaway_by": "converse"}
			w.store.Put(read)
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
	if got := ids(lines, Refused); !slices.Equal(got, []string{"tk-late-read", "tk-late-routed"}) {
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
	w.ready(arrival("tk-free", nil), arrival("tk-talked", nil), arrival("tk-raced", nil), arrival("tk-broke", nil))
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
	w.ready(arrival("tk-a", nil), arrival("tk-b", nil), arrival("tk-c", nil))
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
	w.ready(arrival("tk-a", nil), arrival("tk-b", nil), arrival("tk-c", nil))
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

// The sweep asks nothing about the rig's proactive pool: it reads no roster,
// with a candidate or without, and slings each candidate to the pool whether
// or not the pool runs. A sling gc sling refuses, as it
// refuses a pool the city does not configure, is that candidate's failure, and
// the sweep goes on to the next. A sweep in no rig fails before anything is
// read.
func TestTheSweepSlingsToItsPoolWhetherOrNotItRuns(t *testing.T) {
	w := newWorld(t)
	asked := func(what string) {
		t.Helper()
		if slices.Contains(w.rt.Reads(), "roster") {
			t.Errorf("(SWEEP-NOASK) %s: the reads were %v", what, w.rt.Reads())
		}
	}
	for _, dryRun := range []bool{false, true} {
		if lines, summary, err := w.sweep(dryRun, time.Minute); err != nil || len(lines) > 0 || summary == "" {
			t.Errorf("(SWEEP-NOCANDIDATE) dry run %v: %v, %q, %v", dryRun, lines, summary, err)
		}
	}
	asked("a pass with no candidate")

	w = newWorld(t)
	w.ready(arrival("tk-a", func(b *fake.Bead) { b.Priority = 0 }), arrival("tk-b", func(b *fake.Bead) { b.Priority = 1 }))
	for i := range w.rt.Roster {
		w.rt.Roster[i].Suspended = true
	}
	if _, summary, err := w.sweep(false, time.Minute); err != nil || summary != "slung 2 first reaction(s)" || !slices.Equal(w.slings(), []string{"tk-a", "tk-b"}) {
		t.Errorf("(SWEEP-STOPPED) a pool that does not run: %q, %v, slinging %v; want both slung to it", summary, err, w.slings())
	}
	asked("a pool that does not run")

	w = newWorld(t)
	w.ready(arrival("tk-a", func(b *fake.Bead) { b.Priority = 0 }), arrival("tk-b", func(b *fake.Bead) { b.Priority = 1 }))
	w.rt.OnSling = func(s gascity.Sling) gascity.SlingResult {
		w.add("SLING " + s.Target + " " + s.Bead + " --on " + s.Formula)
		return gascity.SlingResult{Result: gascity.Result{Code: 1, Output: `gc sling: agent "gc-toolkit/gc-toolkit.proactive" not found in city.toml; did you mean "gc-toolkit/gc-toolkit.po"?`}}
	}
	lines, summary, err := w.sweep(false, time.Minute)
	if err != nil || summary != "slung 0 first reaction(s) (2 not slung for an error)" || !slices.Equal(w.slings(), []string{"tk-a", "tk-b"}) {
		t.Errorf("(SWEEP-REFUSED) a pool the city does not configure: %q, %v, slinging %v; want each tried and counted", summary, err, w.slings())
	}
	for _, l := range lines {
		if l.Outcome != Failed || !strings.Contains(l.Why, `agent "gc-toolkit/gc-toolkit.proactive" not found in city.toml`) {
			t.Errorf("(SWEEP-REFUSED) %s's line is %+v; want it failed with gc sling's reason", l.ID, l)
		}
	}
	asked("a pool the city does not configure")

	w = newWorld(t)
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
		w.ready(arrival(id, nil))
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
		w.ready(arrival(id, nil))
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
