package review_test

import (
	"encoding/json"
	"errors"
	"reflect"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
)

// Each test starts from one review run on the bead that owns a PR, whose one
// iteration passes, and changes the one fact it is about. The store is the
// store adapter's fake.

const (
	prBead = "tk-pr"
	root   = "tk-run"
	loopID = "tk-loop"
	branch = "polecat/tk-pr"
	target = "main"
	h1     = "1111111111111111111111111111111111111111"
	h2     = "2222222222222222222222222222222222222222"
	fix    = "3333333333333333333333333333333333333333"
)

type bead = fake.Bead

// world is a store holding a PR's bead, a run attached to it and the run's
// loop, and the outputs a test adds.
type world struct {
	t     *testing.T
	store *fake.Store
	steps int
}

func newWorld(t *testing.T) *world {
	t.Helper()
	s := fake.New()
	s.Put(bead{ID: prBead, Status: "blocked", IssueType: "task", Metadata: map[string]string{
		"merge_result": "pull_request_pending", "branch": branch, "pr_head_sha": h1, "merged_target": target,
	}, Edges: []gcbd.Edge{{ID: root, Type: gcbd.EdgeBlocks}}})
	s.Put(bead{ID: root, Status: "open", IssueType: "task", Metadata: map[string]string{
		"gc.kind": "workflow", "gc.var.pr_bead": prBead, "gc.var.head": h1, "gc.var.target": target,
	}})
	s.Put(bead{ID: loopID, Status: "open", IssueType: "task", Metadata: map[string]string{
		"gc.kind": "ralph", "gc.root_bead_id": root,
	}})
	return &world{t: t, store: s}
}

func (w *world) ledger() *ledger.Ledger { return ledger.New(w.store) }

// output puts a closed step under the run that wrote v as its output.
func (w *world) output(v any) {
	w.t.Helper()
	raw, err := json.Marshal(v)
	if err != nil {
		w.t.Fatal(err)
	}
	w.steps++
	id := "tk-step" + string(rune('a'+w.steps))
	w.store.Put(bead{ID: id, Status: "closed", IssueType: "task", Metadata: map[string]string{
		"gc.root_bead_id": root, "gc.output_json": string(raw),
	}})
}

func triage(n int, head string, checks ...string) review.Triage {
	t := review.Triage{Review: review.OutputTriage, Iteration: n, Head: head}
	for _, c := range checks {
		t.Checks = append(t.Checks, review.Pick{Check: c, Head: head})
	}
	return t
}

func lane(n int, check, head, verdict string, findings ...string) review.Lane {
	ln := review.Lane{Review: review.OutputLane, Iteration: n, Check: check, Head: head, Verdict: verdict}
	for _, f := range findings {
		ln.Findings = append(ln.Findings, review.Finding{ID: f, Severity: "P1", Locus: "a.go:f", Message: "m",
			Category: "c", FailureScenario: "s", Verification: "CONFIRMED: x"})
	}
	return ln
}

func repair(n int, head, pushed string, rulings ...review.Ruling) review.Repair {
	return review.Repair{Review: review.OutputRepair, Iteration: n, Head: head, Pushed: pushed, Rulings: rulings}
}

func finding(check, id, ruling string) review.Ruling {
	return review.Ruling{Check: check, Finding: id, Ruling: ruling, Reason: "r"}
}

// passing writes one iteration at h1 that passes: correctness approves with a
// finding its lane's own rule declines.
func (w *world) passing() {
	w.output(triage(1, h1, "correctness"))
	w.output(lane(1, "correctness", h1, review.VerdictApprove, "F1"))
	w.output(repair(1, h1, "", finding("correctness", "F1", review.RulingDeclined)))
}

// ask puts an open ask on the PR's bead.
func (w *world) ask(id string, checks string, edges ...gcbd.Edge) {
	meta := map[string]string{"branch": branch}
	if checks != "" {
		meta["review_checks"] = checks
	}
	w.store.Put(bead{ID: id, Status: "open", IssueType: "task", Description: "change it", Metadata: meta, Edges: edges})
	pr, _ := w.store.Row(prBead)
	pr.Edges = append(pr.Edges, gcbd.Edge{ID: id, Type: gcbd.EdgeBlocks})
	w.store.Put(pr)
}

func (w *world) passed(n int) *review.Verdict {
	w.t.Helper()
	v, err := review.Passed(w.ledger(), loopID, n)
	if err != nil {
		w.t.Fatal(err)
	}
	return v
}

func mustPass(t *testing.T, v *review.Verdict) {
	t.Helper()
	if !v.Passed {
		t.Fatalf("iteration %d did not pass: %q", v.Iteration, v.Reasons)
	}
}

func mustFail(t *testing.T, v *review.Verdict, reason string) {
	t.Helper()
	if v.Passed {
		t.Fatalf("iteration %d passed; want it held on %q", v.Iteration, reason)
	}
	if !slices.ContainsFunc(v.Reasons, func(r string) bool { return strings.Contains(r, reason) }) {
		t.Fatalf("iteration %d did not pass for %q; want %q among them", v.Iteration, v.Reasons, reason)
	}
}

// A lane's finding declined by its lane's own rule counts as ruled, and the
// iteration passes. The same finding ruled must-fix does not pass.
func TestAFindingRuledMustFixAndOneDeclined(t *testing.T) {
	w := newWorld(t)
	w.passing()
	mustPass(t, w.passed(0))

	w = newWorld(t)
	w.output(triage(1, h1, "correctness"))
	w.output(lane(1, "correctness", h1, review.VerdictRequestChanges, "F1", "F2"))
	w.output(repair(1, h1, "", finding("correctness", "F1", review.RulingDeclined),
		review.Ruling{Check: "correctness", Finding: "F2", Ruling: review.RulingMustFix, Commit: fix}))
	mustFail(t, w.passed(0), "correctness finding F2 was ruled must-fix")

	w = newWorld(t)
	w.output(triage(1, h1, "correctness"))
	w.output(lane(1, "correctness", h1, review.VerdictRequestChanges, "F1"))
	w.output(repair(1, h1, ""))
	mustFail(t, w.passed(0), "correctness finding F1 is not ruled")
}

// Gas City copies an iteration's output onto the beads that settle it: the
// iteration's scope bead, and the loop's control bead once its check passes.
// A copy is not a second output of its step, so the iteration still passes. A
// step bead whose kind reads task, as a later iteration's steps do, writes its
// own.
func TestTheCopiesOnAnIterationsSettlingBeadsAreNotOutputs(t *testing.T) {
	w := newWorld(t)
	w.passing()
	copied, err := json.Marshal(repair(1, h1, "", finding("correctness", "F1", review.RulingDeclined)))
	if err != nil {
		t.Fatal(err)
	}
	w.store.Put(bead{ID: "tk-scope", Status: "closed", IssueType: "task", Metadata: map[string]string{
		"gc.kind": "scope", "gc.root_bead_id": root, "gc.output_json": string(copied),
	}})
	lp, _ := w.store.Row(loopID)
	lp.Metadata["gc.output_json"] = string(copied)
	w.store.Put(lp)
	mustPass(t, w.passed(1))

	w = newWorld(t)
	w.passing()
	raw, err := json.Marshal(triage(1, h1, "correctness"))
	if err != nil {
		t.Fatal(err)
	}
	w.store.Put(bead{ID: "tk-task", Status: "closed", IssueType: "task", Metadata: map[string]string{
		"gc.kind": "task", "gc.root_bead_id": root, "gc.output_json": string(raw),
	}})
	mustFail(t, w.passed(1), "iteration 1 has a second triage output")
}

// A question put to a person through a gate counts as ruled, so the loop stops
// there rather than spend its attempts. One that names no gate does not.
func TestAQuestionPutToAPerson(t *testing.T) {
	w := newWorld(t)
	w.output(triage(1, h1, "correctness"))
	w.output(lane(1, "correctness", h1, review.VerdictRequestChanges, "F1"))
	w.output(repair(1, h1, "", review.Ruling{Check: "correctness", Finding: "F1", Ruling: review.RulingQuestion, Gate: "tk-gate"}))
	mustPass(t, w.passed(0))

	w = newWorld(t)
	w.output(triage(1, h1, "correctness"))
	w.output(lane(1, "correctness", h1, review.VerdictRequestChanges, "F1"))
	w.output(repair(1, h1, "", review.Ruling{Check: "correctness", Finding: "F1", Ruling: review.RulingQuestion}))
	mustFail(t, w.passed(0), "was put to a person and names no gate")
}

// A round that pushed made a head triage has not judged, so the iteration
// does not pass, and the next one triages the head it pushed.
func TestARepairThatPushed(t *testing.T) {
	w := newWorld(t)
	w.output(triage(1, h1, "correctness"))
	w.output(lane(1, "correctness", h1, review.VerdictApprove))
	w.output(repair(1, h1, h2))
	mustFail(t, w.passed(0), "the round pushed "+h2)
}

// A finding ruled must-fix at an earlier head must name the commit that fixes
// it, or the iteration that judged the fixed head does not pass.
func TestAMustFixOfAnEarlierHeadWithNoFixingCommit(t *testing.T) {
	for _, tc := range []struct {
		commit string
		pass   bool
	}{{"", false}, {"abc", false}, {fix, true}} {
		w := newWorld(t)
		w.output(triage(1, h1, "correctness"))
		w.output(lane(1, "correctness", h1, review.VerdictRequestChanges, "F1"))
		w.output(repair(1, h1, h2, review.Ruling{Check: "correctness", Finding: "F1", Ruling: review.RulingMustFix, Commit: tc.commit}))
		w.output(triage(2, h2))
		w.output(repair(2, h2, ""))
		v := w.passed(0)
		if v.Iteration != 2 {
			t.Fatalf("the check judged iteration %d; want the latest, 2", v.Iteration)
		}
		if tc.pass {
			mustPass(t, v)
		} else {
			mustFail(t, v, "names no commit that fixes it")
		}
		if v := w.passed(1); v.Passed {
			t.Fatalf("iteration 1, which ruled a must-fix and pushed, passed")
		}
	}
}

// An open ask that nothing holds and the round did not take fails the check.
// An ask an open bead holds is neither taken nor counted against the pass.
func TestAnAskNothingHoldsAndOneAnOpenBeadHolds(t *testing.T) {
	w := newWorld(t)
	w.passing()
	w.ask("tk-ask", "")
	mustFail(t, w.passed(0), "ask tk-ask is open and nothing holds it, and the round did not take it")

	w = newWorld(t)
	w.passing()
	w.store.Put(bead{ID: "tk-other", Status: "open", IssueType: "task"})
	w.ask("tk-ask", "arch", gcbd.Edge{ID: "tk-other", Type: gcbd.EdgeBlocks})
	w.store.List("tk-ask", "tk-other")
	w.store.Mark("tk-ask")
	v := w.passed(0)
	mustPass(t, v)
	if len(v.Asks) != 1 || v.Asks[0].Takeable() {
		t.Fatalf("the held ask read %+v; want it open and not takeable", v.Asks)
	}

	w = newWorld(t)
	w.output(triage(1, h1, "correctness"))
	w.output(lane(1, "correctness", h1, review.VerdictApprove))
	w.output(repair(1, h1, "", review.Ruling{Ask: "tk-ask", Ruling: review.RulingDeclined, Reason: "nit"}))
	w.ask("tk-ask", "")
	mustPass(t, w.passed(0))
}

// A check an ask sends back must run at the head before the head passes.
func TestAnAsksCheckNotRunAtTheHead(t *testing.T) {
	w := newWorld(t)
	w.output(triage(1, h1, "correctness"))
	w.output(lane(1, "correctness", h1, review.VerdictApprove))
	w.output(repair(1, h1, "", review.Ruling{Ask: "tk-ask", Ruling: review.RulingAnswered}))
	w.ask("tk-ask", "arch")
	mustFail(t, w.passed(0), "ask tk-ask sends back arch, which did not run at "+h1)

	w = newWorld(t)
	w.output(triage(1, h1, "correctness", "arch"))
	w.output(lane(1, "correctness", h1, review.VerdictApprove))
	w.output(lane(1, "arch", h1, review.VerdictApprove))
	w.output(repair(1, h1, "", review.Ruling{Ask: "tk-ask", Ruling: review.RulingAnswered}))
	w.ask("tk-ask", "arch")
	mustPass(t, w.passed(0))
}

// A lane triage bonded that wrote no verdict, and a step's output that does not
// read, hold the iteration.
func TestAnUnwrittenLaneOrABrokenOutput(t *testing.T) {
	w := newWorld(t)
	w.output(triage(1, h1, "correctness", "arch"))
	w.output(lane(1, "correctness", h1, review.VerdictApprove))
	w.output(repair(1, h1, ""))
	mustFail(t, w.passed(0), "the arch lane wrote no verdict in iteration 1")

	w = newWorld(t)
	w.passing()
	w.output(map[string]any{"review": "lane", "iteration": 1, "check": "arch", "verdik": "approve"})
	mustFail(t, w.passed(0), "an output does not read")
}

// A store that does not answer gives no verdict: the error, never a pass or a
// fail.
func TestAStoreThatDoesNotAnswer(t *testing.T) {
	w := newWorld(t)
	w.passing()
	w.store.FindErr = &gcbd.ReadError{Reason: "the store is down"}
	if v, err := review.Passed(w.ledger(), loopID, 0); err == nil {
		t.Fatalf("a store that does not answer gave a verdict: %+v", v)
	}
}

func (w *world) closeLoop(meta map[string]string) {
	loop, _ := w.store.Row(loopID)
	loop.Status = "closed"
	for k, v := range meta {
		loop.Metadata[k] = v
	}
	w.store.Put(loop)
}

func (w *world) results() []review.Result {
	w.t.Helper()
	row, _ := w.store.Row(prBead)
	raw := row.Metadata["review_results"]
	if raw == "" {
		return nil
	}
	var out []review.Result
	if err := json.Unmarshal([]byte(raw), &out); err != nil {
		w.t.Fatal(err)
	}
	return out
}

func (w *world) record() *review.Recorded {
	w.t.Helper()
	got, err := review.Record(w.ledger(), w.t.TempDir(), time.Second, root)
	if err != nil {
		w.t.Fatal(err)
	}
	return got
}

// The result replaces the entry for the same head and target, keeps every
// other, and passes when the loop passed and no gate the run filed is open.
func TestTheResultIsReplacedAtTheSameHeadAndTarget(t *testing.T) {
	w := newWorld(t)
	w.passing()
	w.closeLoop(map[string]string{"gc.outcome": "pass"})
	pr, _ := w.store.Row(prBead)
	pr.Metadata["review_results"] = `[{"head":"` + h1 + `","target":"main","passed":false},` +
		`{"head":"` + h2 + `","target":"main","passed":true},{"head":"` + h1 + `","target":"other","passed":false}]`
	w.store.Put(pr)
	w.record()
	want := []review.Result{{Head: h2, Target: "main", Passed: true}, {Head: h1, Target: "other"}, {Head: h1, Target: "main", Passed: true}}
	if got := w.results(); !reflect.DeepEqual(got, want) {
		t.Fatalf("review_results = %+v; want %+v", got, want)
	}
}

// An exhausted loop gets a result that does not pass, and so does a loop that
// stopped on a question while its gate is open; once the gate closes, the
// result passes.
func TestARecordThatDoesNotPass(t *testing.T) {
	w := newWorld(t)
	w.output(triage(1, h1, "correctness"))
	w.output(lane(1, "correctness", h1, review.VerdictRequestChanges, "F1"))
	w.output(repair(1, h1, h2, review.Ruling{Check: "correctness", Finding: "F1", Ruling: review.RulingMustFix, Commit: fix}))
	w.output(triage(2, h2, "correctness"))
	w.closeLoop(map[string]string{"gc.outcome": "fail", "gc.failed_attempt": "2"})
	got := w.record()
	if !got.Exhausted || !reflect.DeepEqual(w.results(), []review.Result{{Head: h2, Target: target}}) {
		t.Fatalf("an exhausted loop recorded %+v, %+v; want a result at its last judged head that does not pass", got, w.results())
	}

	for _, gate := range []string{"open", "closed"} {
		w = newWorld(t)
		w.output(triage(1, h1, "correctness"))
		w.output(lane(1, "correctness", h1, review.VerdictRequestChanges, "F1"))
		w.output(repair(1, h1, "", review.Ruling{Check: "correctness", Finding: "F1", Ruling: review.RulingQuestion, Gate: "tk-gate"}))
		w.store.Put(bead{ID: "tk-gate", Status: gate, IssueType: "gate"})
		w.closeLoop(map[string]string{"gc.outcome": "pass"})
		w.record()
		want := []review.Result{{Head: h1, Target: target, Passed: gate == "closed"}}
		if got := w.results(); !reflect.DeepEqual(got, want) {
			t.Fatalf("with the question's gate %s, review_results = %+v; want %+v", gate, got, want)
		}
	}
}

// A loop a step's hard failure ended gets no result, as does one that ended
// any other way, and nothing is written; a loop still open is refused.
func TestNoResultForAHardFailure(t *testing.T) {
	for _, meta := range []map[string]string{
		{"gc.outcome": "fail", "gc.final_disposition": "hard_fail"},
		{"gc.outcome": "canceled"},
	} {
		w := newWorld(t)
		w.passing()
		w.closeLoop(meta)
		if got := w.record(); got.Result != nil || got.NoResult == "" {
			t.Fatalf("a loop that ended %v recorded %+v; want no result", meta, got)
		}
		if len(w.store.Writes()) != 0 {
			t.Fatalf("a loop that ended %v wrote %+v", meta, w.store.Writes())
		}
	}
	w := newWorld(t)
	w.passing()
	if _, err := review.Record(w.ledger(), t.TempDir(), time.Second, root); !review.IsUnfinished(err) {
		t.Fatalf("a loop still open recorded with %v; want it refused as unfinished", err)
	}
}

// The asks the last round answered close with their work record, an ask fixed
// at an earlier head as shipped with its commit; a shadow run writes nothing.
func TestRecordClosesTheAsksTheRunAnswered(t *testing.T) {
	setup := func(shadow bool) *world {
		w := newWorld(t)
		if shadow {
			r, _ := w.store.Row(root)
			r.Metadata["gc.var.shadow"] = "true"
			w.store.Put(r)
		}
		w.ask("tk-fixed", "")
		w.ask("tk-nit", "")
		w.ask("tk-asked", "")
		w.output(triage(1, h1, "correctness"))
		w.output(lane(1, "correctness", h1, review.VerdictApprove))
		w.output(repair(1, h1, h2, review.Ruling{Ask: "tk-fixed", Ruling: review.RulingMustFix, Commit: fix},
			review.Ruling{Ask: "tk-nit", Ruling: review.RulingDeclined}, review.Ruling{Ask: "tk-asked", Ruling: review.RulingDeclined}))
		w.output(triage(2, h2, "correctness"))
		w.output(lane(2, "correctness", h2, review.VerdictApprove))
		w.output(repair(2, h2, "", review.Ruling{Ask: "tk-fixed", Ruling: review.RulingAnswered},
			review.Ruling{Ask: "tk-nit", Ruling: review.RulingDeclined},
			review.Ruling{Ask: "tk-asked", Ruling: review.RulingQuestion, Gate: "tk-gate"}))
		w.store.Put(bead{ID: "tk-gate", Status: "open", IssueType: "gate"})
		w.closeLoop(map[string]string{"gc.outcome": "pass"})
		return w
	}
	w := setup(false)
	got := w.record()
	want := []review.ClosedAsk{{ID: "tk-fixed", Ruling: review.RulingAnswered, Outcome: "shipped", Commit: fix},
		{ID: "tk-nit", Ruling: review.RulingDeclined, Outcome: "no-op"}}
	if !reflect.DeepEqual(got.Closed, want) {
		t.Fatalf("Record closed %+v; want %+v", got.Closed, want)
	}
	for _, id := range []string{"tk-fixed", "tk-nit"} {
		row, _ := w.store.Row(id)
		if row.Status != "closed" || row.Metadata["gc.work_outcome"] == "" {
			t.Fatalf("%s reads %+v; want it closed with its work record", id, row)
		}
	}
	if row, _ := w.store.Row("tk-fixed"); row.Metadata["gc.work_commit"] != fix {
		t.Fatalf("the fixed ask's work commit reads %q", row.Metadata["gc.work_commit"])
	}
	if row, _ := w.store.Row("tk-asked"); row.Status != "open" {
		t.Fatalf("the ask put to a person closed")
	}
	if !reflect.DeepEqual(w.results(), []review.Result{{Head: h2, Target: target}}) {
		t.Fatalf("with the question's gate open, review_results = %+v", w.results())
	}

	w = setup(true)
	if got := w.record(); !got.Shadow || len(w.store.Writes()) != 0 {
		t.Fatalf("a shadow run recorded %+v and wrote %+v; want nothing written", got, w.store.Writes())
	}
}

// An ask is filed with no parent, no route and no assignee, blocking the PR's
// bead by its own edge, naming the PR's branch and the checks it sends back.
func TestAnAskIsFiledWithNoParent(t *testing.T) {
	w := newWorld(t)
	w.store.Put(bead{ID: "tk-ruling", Status: "closed", IssueType: "task"})
	index := func(at string) (review.Index, error) {
		if at != h1 {
			t.Fatalf("the index was read at %s; want the validated head", at)
		}
		return review.Index{Source: "idx", Checks: review.Parse("[checks.Arch]\nphase = \"pre-open\"\n")}, nil
	}
	id, filed, err := review.FileAsk(w.ledger(), review.AskRequest{Bead: prBead, Reason: "Fix the cap.", Source: "tk-ruling", Checks: []string{"arch"}}, index)
	if err != nil || !filed {
		t.Fatalf("FileAsk = %q, %t, %v", id, filed, err)
	}
	creates := w.store.Creates()
	if len(creates) != 1 || slices.Contains(creates[0].Args, "--parent") {
		t.Fatalf("the create carried %+v; want one create with no parent", creates)
	}
	row, _ := w.store.Row(id)
	if row.Assignee != "" || row.IssueType != "task" || row.Description != "Fix the cap." ||
		!reflect.DeepEqual(row.Metadata, map[string]string{"branch": branch, "review_checks": "Arch"}) {
		t.Fatalf("the ask reads %+v", row)
	}
	if !reflect.DeepEqual(row.Edges, []gcbd.Edge{{ID: "tk-ruling", Type: "discovered-from", Status: "closed"}}) {
		t.Fatalf("the ask's own edges are %+v; want only its discovered-from source", row.Edges)
	}
	asks, err := review.AsksOn(w.ledger(), prBead)
	if err != nil || len(asks) != 1 || asks[0].ID != id || !asks[0].Takeable() || asks[0].Source != "tk-ruling" {
		t.Fatalf("AsksOn = %+v, %v; want the one takeable ask", asks, err)
	}

	_, _, err = review.FileAsk(w.ledger(), review.AskRequest{Bead: prBead, Reason: "x", Checks: []string{"nonesuch"}}, index)
	var refused *review.Refusal
	if !errors.As(err, &refused) {
		t.Fatalf("an ask naming a check the index lacks: %v; want a refusal", err)
	}
}

// One source and reason files once: a second filing finds the ask while it is
// open and after it closed, and another source files its own.
func TestOneSourceAndReasonFiledTwice(t *testing.T) {
	w := newWorld(t)
	w.store.Put(bead{ID: "tk-ruling", Status: "closed", IssueType: "task"})
	w.store.Put(bead{ID: "tk-other", Status: "closed", IssueType: "task"})
	req := review.AskRequest{Bead: prBead, Reason: "Fix the cap.", Source: "tk-ruling"}
	first, _, err := review.FileAsk(w.ledger(), req, nil)
	if err != nil {
		t.Fatal(err)
	}
	for _, status := range []string{"open", "closed"} {
		row, _ := w.store.Row(first)
		row.Status = status
		w.store.Put(row)
		id, filed, err := review.FileAsk(w.ledger(), req, nil)
		if err != nil || filed || id != first {
			t.Fatalf("with the first ask %s, filing again = %q, %t, %v; want it found", status, id, filed, err)
		}
	}
	if id, filed, err := review.FileAsk(w.ledger(), review.AskRequest{Bead: prBead, Reason: "Fix the cap.", Source: "tk-other"}, nil); err != nil || !filed || id == first {
		t.Fatalf("another source's ask = %q, %t, %v; want one of its own", id, filed, err)
	}
	if n := len(w.store.Creates()); n != 2 {
		t.Fatalf("the store took %d creates; want 2", n)
	}
}

// A bead that owns no PR on the record gets no ask.
func TestAnAskOnABeadWithNoPRIsRefused(t *testing.T) {
	w := newWorld(t)
	pr, _ := w.store.Row(prBead)
	pr.Metadata["merge_result"] = "mr_merged"
	w.store.Put(pr)
	_, _, err := review.FileAsk(w.ledger(), review.AskRequest{Bead: prBead, Reason: "x"}, nil)
	var refused *review.Refusal
	if !errors.As(err, &refused) || len(w.store.Creates()) != 0 {
		t.Fatalf("an ask on a bead with no PR on the record: %v; want it refused with nothing filed", err)
	}
}
