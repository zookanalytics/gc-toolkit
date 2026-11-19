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
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
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

// world is a store holding a PR's bead, a run attached to it, whose loop's
// bound is two attempts, and the run's loop, the outputs a test adds, and the
// gates the loop's check files.
type world struct {
	t     *testing.T
	store *fake.Store
	steps int
	gates filed
}

// filed is a gate filer that keeps each gate it is asked for, by subject and
// key, and fails when err is set.
type filed struct {
	calls []string
	text  []string
	err   error
}

func (f *filed) File(subject, key, message string) error {
	if f.err != nil {
		return f.err
	}
	f.calls = append(f.calls, subject+" "+key)
	f.text = append(f.text, message)
	return nil
}

func newWorld(t *testing.T) *world {
	t.Helper()
	s := fake.New()
	s.IDPrefix = "tk"
	s.Put(bead{ID: prBead, Status: "blocked", IssueType: "task", Metadata: map[string]string{
		"merge_result": "pull_request_pending", "branch": branch, "pr_head_sha": h1, "merged_target": target,
	}, Edges: []gcbd.Edge{{ID: root, Type: gcbd.EdgeBlocks}}})
	s.Put(bead{ID: root, Status: "open", IssueType: "task", Metadata: map[string]string{
		"gc.kind": "workflow", "gc.var.pr_bead": prBead, "gc.var.head": h1, "gc.var.target": target,
		"gc.var.max_attempts": "2",
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

// record runs the loop's check over iteration n and records what it ends,
// failing the test on an error.
func (w *world) record(n int) *review.Recorded {
	w.t.Helper()
	got, err := w.recordErr(n)
	if err != nil {
		w.t.Fatal(err)
	}
	return got
}

func (w *world) recordErr(n int) (*review.Recorded, error) {
	w.t.Helper()
	return review.Record(w.ledger(), w.t.TempDir(), time.Second, w.passed(n), &w.gates)
}

// The result replaces the entry for the same head and target and keeps every
// other, and a passed iteration's result passes. The check run again leaves
// the same entries, and asks no person.
func TestTheResultIsReplacedAtTheSameHeadAndTarget(t *testing.T) {
	w := newWorld(t)
	w.passing()
	pr, _ := w.store.Row(prBead)
	pr.Metadata["review_results"] = `[{"head":"` + h1 + `","target":"main","passed":false},` +
		`{"head":"` + h2 + `","target":"main","passed":true},{"head":"` + h1 + `","target":"other","passed":false}]`
	w.store.Put(pr)
	w.record(1)
	want := []review.Result{{Head: h2, Target: "main", Passed: true}, {Head: h1, Target: "other"}, {Head: h1, Target: "main", Passed: true, Run: root}}
	if got := w.results(); !reflect.DeepEqual(got, want) {
		t.Fatalf("review_results = %+v; want %+v", got, want)
	}
	w.record(1)
	if got := w.results(); !reflect.DeepEqual(got, want) {
		t.Fatalf("the check run again leaves review_results %+v; want %+v", got, want)
	}
	if len(w.gates.calls) != 0 {
		t.Fatalf("a passed iteration asked a person: %v", w.gates.calls)
	}
}

// A passed iteration records once, as the check that passes it, and only
// there: an iteration that does not pass and is not the loop's last ends
// nothing, so its record is refused and nothing is written. The check run
// again at the passed iteration closes no ask a second time.
func TestARoundThatPassesRecordsOnceAndOnlyOnce(t *testing.T) {
	w := newWorld(t)
	w.ask("tk-nit", "")
	w.output(triage(1, h1, "correctness"))
	w.output(lane(1, "correctness", h1, review.VerdictRequestChanges, "F1"))
	w.output(repair(1, h1, h2, review.Ruling{Check: "correctness", Finding: "F1", Ruling: review.RulingMustFix, Commit: fix},
		review.Ruling{Ask: "tk-nit", Ruling: review.RulingDeclined}))
	if v := w.passed(1); v.Ends() {
		t.Fatalf("iteration 1 of 2, which pushed, ends the loop: %+v", v)
	}
	if _, err := w.recordErr(1); err == nil || len(w.store.Writes()) != 0 {
		t.Fatalf("a record at an iteration that ends nothing = %v, wrote %+v; want it refused with nothing written", err, w.store.Writes())
	}
	w.output(triage(2, h2, "correctness"))
	w.output(lane(2, "correctness", h2, review.VerdictApprove))
	w.output(repair(2, h2, "", review.Ruling{Ask: "tk-nit", Ruling: review.RulingDeclined}))
	if got := w.record(2); got.Exhausted || len(got.Closed) != 1 {
		t.Fatalf("the passed round recorded %+v; want a pass that closes the one ask", got)
	}
	if again := w.record(2); len(again.Closed) != 0 {
		t.Fatalf("the check run again closed %+v again", again.Closed)
	}
	if got := w.results(); !reflect.DeepEqual(got, []review.Result{{Head: h2, Target: target, Passed: true, Run: root}}) {
		t.Fatalf("review_results = %+v; want one passed entry at the head the round judged", got)
	}
}

// An exhausted loop, its last attempt not passing, gets a result that does not
// pass at its last judged head and a review-loop-exhausted gate naming it; a
// loop that stopped on a question gets one that does not pass while the gate
// is open, and once the gate closes the result passes.
func TestARecordThatDoesNotPass(t *testing.T) {
	w := newWorld(t)
	w.output(triage(1, h1, "correctness"))
	w.output(lane(1, "correctness", h1, review.VerdictRequestChanges, "F1"))
	w.output(repair(1, h1, h2, review.Ruling{Check: "correctness", Finding: "F1", Ruling: review.RulingMustFix, Commit: fix}))
	w.output(triage(2, h2, "correctness"))
	got := w.record(2)
	if !got.Exhausted || !got.Gated || !reflect.DeepEqual(w.results(), []review.Result{{Head: h2, Target: target, Run: root}}) {
		t.Fatalf("an exhausted loop recorded %+v, %+v; want a result at its last judged head that does not pass, gated", got, w.results())
	}
	if !slices.Equal(w.gates.calls, []string{prBead + " " + review.LoopExhaustedKey}) ||
		!strings.Contains(w.gates.text[0], "exhausted its attempts at "+h2) {
		t.Fatalf("the exhausted loop filed %v %q; want one %s gate on %s naming %s", w.gates.calls, w.gates.text,
			review.LoopExhaustedKey, prBead, h2)
	}

	for _, gate := range []string{"open", "closed"} {
		w = newWorld(t)
		w.output(triage(1, h1, "correctness"))
		w.output(lane(1, "correctness", h1, review.VerdictRequestChanges, "F1"))
		w.output(repair(1, h1, "", review.Ruling{Check: "correctness", Finding: "F1", Ruling: review.RulingQuestion, Gate: "tk-gate"}))
		w.store.Put(bead{ID: "tk-gate", Status: gate, IssueType: "gate"})
		w.record(1)
		want := []review.Result{{Head: h1, Target: target, Passed: gate == "closed", Run: root}}
		if got := w.results(); !reflect.DeepEqual(got, want) {
			t.Fatalf("with the question's gate %s, review_results = %+v; want %+v", gate, got, want)
		}
	}
}

// A record that does not land, at the bead's write, the gate or the lock,
// returns its error, which the check turns into a re-run that spends no
// attempt, and the retry lands the same result and files the gate once.
func TestARecordThatFailsSpendsNoRound(t *testing.T) {
	w := newWorld(t)
	w.passing()
	w.store.UpdateErr = errors.New("the store did not take the write")
	if _, err := w.recordErr(1); err == nil {
		t.Fatal("a record whose write did not land returned no error")
	}
	w.store.UpdateErr = nil
	w.record(1)
	if got := w.results(); !reflect.DeepEqual(got, []review.Result{{Head: h1, Target: target, Passed: true, Run: root}}) {
		t.Fatalf("the retry recorded %+v", got)
	}

	w = newWorld(t)
	w.output(triage(1, h1, "correctness"))
	w.output(triage(2, h1, "correctness"))
	w.gates.err = errors.New("human-gate.sh exited 1")
	if _, err := w.recordErr(2); err == nil || !strings.Contains(err.Error(), "the result landed") {
		t.Fatalf("a gate that did not file = %v; want the error, saying the result landed", err)
	}
	w.gates.err = nil
	if got := w.record(2); !got.Gated || len(w.gates.calls) != 1 {
		t.Fatalf("the retry filed %v; want the one gate", w.gates.calls)
	}

	w = newWorld(t)
	w.passing()
	dir := t.TempDir()
	release, err := record.Lock(dir, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	_, err = review.Record(w.ledger(), dir, 50*time.Millisecond, w.passed(1), &w.gates)
	release()
	if !errors.Is(err, record.ErrLockWait) || len(w.store.Writes()) != 0 {
		t.Fatalf("a record lock held elsewhere = %v, wrote %+v; want the lock's wait error and nothing written", err, w.store.Writes())
	}
}

// A run that judged no head records nothing, even at its last attempt.
func TestNoResultForARunThatJudgedNoHead(t *testing.T) {
	w := newWorld(t)
	w.output(map[string]any{"review": "triage", "iteration": 2, "head": ""})
	got := w.record(2)
	if got.Result != nil || got.NoResult == "" || len(w.store.Writes()) != 0 || len(w.gates.calls) != 0 {
		t.Fatalf("a run that judged no head recorded %+v, wrote %+v, filed %v; want nothing", got, w.store.Writes(), w.gates.calls)
	}
}

// The asks the last round answered close with their work record, which the
// runtime's enforced work-record gate takes: an ask fixed at an earlier head
// as shipped with its commit on the PR's branch, any other as no-op; a shadow
// run writes nothing and files no gate.
func TestRecordClosesTheAsksTheRunAnswered(t *testing.T) {
	setup := func(shadow bool) *world {
		w := newWorld(t)
		w.store.WorkRecordGate = true
		if shadow {
			w.shadowRun()
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
		return w
	}
	w := setup(false)
	got := w.record(2)
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
	if row, _ := w.store.Row("tk-fixed"); row.Metadata["gc.work_commit"] != fix || row.Metadata["gc.work_branch"] != branch {
		t.Fatalf("the fixed ask's work record names commit %q on branch %q; want %s on %s",
			row.Metadata["gc.work_commit"], row.Metadata["gc.work_branch"], fix, branch)
	}
	if row, _ := w.store.Row("tk-nit"); row.Metadata["gc.work_outcome"] != "no-op" || row.Metadata["gc.work_branch"] != "" {
		t.Fatalf("the declined ask's work record reads %+v; want no-op, naming no branch", row.Metadata)
	}
	if row, _ := w.store.Row("tk-asked"); row.Status != "open" {
		t.Fatalf("the ask put to a person closed")
	}
	if !reflect.DeepEqual(w.results(), []review.Result{{Head: h2, Target: target, Run: root}}) {
		t.Fatalf("with the question's gate open, review_results = %+v", w.results())
	}

	w = setup(true)
	if got := w.record(2); !got.Shadow || len(w.store.Writes()) != 0 || len(w.gates.calls) != 0 {
		t.Fatalf("a shadow run recorded %+v, wrote %+v and filed %v; want nothing written", got, w.store.Writes(), w.gates.calls)
	}
}

// A closed run recorded its result when its loop closed passed, or exhausted
// at a head it judged while its bound reads, and the bead holds its check's
// entry for that head and target, naming the run. A loop that closed either
// way with no such entry, as when Gas City grades a check whose write kept
// failing as an ordinary failure, leaves it with no result, and so does
// another run's entry at the head, a cancel, a hard failure, a loop that never
// closed, an exhausted loop with no bound to read and a run that judged no
// head.
func TestHowARunEnded(t *testing.T) {
	closeRoot := func(w *world, outcome string) {
		r, _ := w.store.Row(root)
		r.Status = "closed"
		r.Metadata["gc.outcome"] = outcome
		w.store.Put(r)
	}
	exhausted := func(w *world) {
		w.output(triage(1, h1, "correctness"))
		w.output(triage(2, h1, "correctness"))
	}
	for _, c := range []struct {
		name   string
		setup  func(*world)
		result bool
	}{
		{"its loop passed", func(w *world) {
			w.passing()
			w.record(1)
			w.closeLoop(map[string]string{"gc.outcome": "pass"})
			closeRoot(w, "pass")
		}, true},
		{"its loop exhausted", func(w *world) {
			exhausted(w)
			w.record(2)
			w.closeLoop(map[string]string{"gc.outcome": "fail", "gc.failed_attempt": "2"})
			closeRoot(w, "fail")
		}, true},
		{"its loop passed and its check's record never landed", func(w *world) {
			w.passing()
			w.closeLoop(map[string]string{"gc.outcome": "pass"})
			closeRoot(w, "pass")
		}, false},
		{"its loop exhausted and its check's record never landed", func(w *world) {
			exhausted(w)
			w.closeLoop(map[string]string{"gc.outcome": "fail", "gc.failed_attempt": "2"})
			closeRoot(w, "fail")
		}, false},
		{"its loop exhausted, and the entry at its head is another run's", func(w *world) {
			exhausted(w)
			pr, _ := w.store.Row(prBead)
			pr.Metadata["review_results"] = `[{"head":"` + h1 + `","target":"` + target + `","passed":false,"run":"tk-other"}]`
			w.store.Put(pr)
			w.closeLoop(map[string]string{"gc.outcome": "fail", "gc.failed_attempt": "2"})
			closeRoot(w, "fail")
		}, false},
		{"its loop exhausted with no bound to read", func(w *world) {
			r, _ := w.store.Row(root)
			delete(r.Metadata, "gc.var.max_attempts")
			w.store.Put(r)
			w.output(triage(1, h1, "correctness"))
			w.closeLoop(map[string]string{"gc.outcome": "fail", "gc.failed_attempt": "2"})
			closeRoot(w, "fail")
		}, false},
		{"a hard failure ended its loop", func(w *world) {
			w.passing()
			w.closeLoop(map[string]string{"gc.outcome": "fail", "gc.final_disposition": "hard_fail"})
			closeRoot(w, "fail")
		}, false},
		{"it was cancelled at triage's read", func(w *world) {
			closeRoot(w, "canceled")
		}, false},
		{"its loop never closed", func(w *world) {
			w.passing()
			closeRoot(w, "fail")
		}, false},
		{"it judged no head", func(w *world) {
			w.closeLoop(map[string]string{"gc.outcome": "fail", "gc.failed_attempt": "2"})
			closeRoot(w, "fail")
		}, false},
	} {
		w := newWorld(t)
		c.setup(w)
		e, err := review.Ended(w.ledger(), root)
		if err != nil {
			t.Fatalf("%s: %v", c.name, err)
		}
		if e.Result != c.result || e.How == "" {
			t.Errorf("%s: the run ended %+v; want a result %t", c.name, e, c.result)
		}
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

// An ask filed to wait on another bead carries the wait in the create that
// files it, as its own blocks edge beside its edge onto the PR's bead, and no
// write follows, so no read finds the ask without its wait.
func TestAnAskThatWaitsLandsWithItsWaitInOneCreate(t *testing.T) {
	w := newWorld(t)
	w.store.Put(bead{ID: "tk-ruling", Status: "closed", IssueType: "task"})
	w.store.Put(bead{ID: "tk-other", Status: "open", IssueType: "task"})
	req := review.AskRequest{Bead: prBead, Reason: "Fix the cap.", Source: "tk-ruling", WaitingOn: []string{"tk-other", " tk-other "}}
	id, filed, err := review.FileAsk(w.ledger(), req, nil)
	if err != nil || !filed {
		t.Fatalf("FileAsk = %q, %t, %v", id, filed, err)
	}
	creates := w.store.Creates()
	if deps := "blocks:" + prBead + ",blocked-by:tk-other,discovered-from:tk-ruling"; len(creates) != 1 || !slices.Contains(creates[0].Args, deps) {
		t.Fatalf("the store took the creates %+v; want one whose --deps are %s", creates, deps)
	}
	if writes := w.store.Writes(); len(writes) != 0 {
		t.Fatalf("filing the ask wrote %+v after its create; want no write", writes)
	}
	asks, err := review.AsksOn(w.ledger(), prBead)
	if err != nil || len(asks) != 1 || asks[0].ID != id || !slices.Equal(asks[0].WaitingOn, []string{"tk-other"}) {
		t.Fatalf("AsksOn = %+v, %v; want the one ask, waiting on tk-other", asks, err)
	}
}

// A wait whose edge would hold nothing is refused by name with nothing filed,
// by the ledger's rule for every wait edge, which FileAsk returns as its own
// refusal. bd keeps an edge between beads of two id prefixes as one into
// another rig's store, so a bead of another prefix is refused whether another
// rig's store holds it or the PR's store does. A bead of the PR bead's prefix
// is refused when the store does not hold it.
func TestAnAskThatWaitsOnABeadItsEdgeWouldNotHoldIsRefused(t *testing.T) {
	for _, c := range []struct{ name, wait, why string }{
		{"a bead in another rig's store", "rb-other", "rb-other does not carry the id prefix tk,"},
		{"a bead of another prefix that the PR's store holds", "rb-held", "rb-held does not carry the id prefix tk,"},
		{"a bead of the PR's prefix that the store does not hold", "tk-gone", "the store holds no bead tk-gone"},
	} {
		t.Run(c.name, func(t *testing.T) {
			w := newWorld(t)
			w.store.Put(bead{ID: "tk-other", Status: "open", IssueType: "task"})
			w.store.Put(bead{ID: "rb-held", Status: "open", IssueType: "task"})
			_, _, err := review.FileAsk(w.ledger(), review.AskRequest{Bead: prBead, Reason: "Fix the cap.", WaitingOn: []string{"tk-other", c.wait}}, nil)
			var refused *review.Refusal
			if !errors.As(err, &refused) || !strings.Contains(err.Error(), c.wait) || !strings.Contains(err.Error(), c.why) || strings.Contains(err.Error(), "tk-other") {
				t.Fatalf("a wait on %s: %v; want a refusal that names %s alone, saying %q", c.wait, err, c.wait, c.why)
			}
			if n := len(w.store.Creates()); n != 0 {
				t.Fatalf("the refused ask reached the store in %d creates", n)
			}
		})
	}
}

// A store can hold a bead of another id prefix than the one it gives a bead it
// files, which bd allows under --force or allowed_prefixes. An ask on such a
// PR's bead is refused with nothing filed, with or without a wait of the
// bead's prefix, since bd keeps both the ask's edge onto the bead and its wait
// as edges into another rig's store, and the ledger refuses both.
func TestAnAskOnABeadOfAnotherPrefixThanItsStoreIsRefused(t *testing.T) {
	w := newWorld(t)
	pr, _ := w.store.Row(prBead)
	pr.ID = "rb-pr"
	w.store.Put(pr)
	w.store.Put(bead{ID: "rb-other", Status: "open", IssueType: "task"})
	for _, waits := range [][]string{nil, {"rb-other"}} {
		_, _, err := review.FileAsk(w.ledger(), review.AskRequest{Bead: "rb-pr", Reason: "Fix the cap.", WaitingOn: waits}, nil)
		var refused *review.Refusal
		if !errors.As(err, &refused) || !strings.Contains(err.Error(), "rb-pr") || !strings.Contains(err.Error(), "does not carry the id prefix tk,") {
			t.Fatalf("an ask on rb-pr in a store of prefix tk, waiting on %v: %v; want a refusal naming rb-pr and the prefix tk", waits, err)
		}
	}
	if n := len(w.store.Creates()); n != 0 {
		t.Fatalf("the refused asks reached the store in %d creates", n)
	}
}

// A re-run finds the ask of its source and reason and files nothing. One that
// names a wait the ask it finds does not carry is refused, naming the ask and
// that wait, so it never answers with an ask that a run can take first. One
// that names the waits the ask carries, or none, finds it.
func TestARerunNamingAWaitTheAskLacksIsRefused(t *testing.T) {
	w := newWorld(t)
	for _, id := range []string{"tk-ruling", "tk-later"} {
		w.store.Put(bead{ID: id, Status: "closed", IssueType: "task"})
	}
	for _, id := range []string{"tk-other", "tk-third"} {
		w.store.Put(bead{ID: id, Status: "open", IssueType: "task"})
	}
	bare := review.AskRequest{Bead: prBead, Reason: "Fix the cap.", Source: "tk-ruling"}
	first, _, err := review.FileAsk(w.ledger(), bare, nil)
	if err != nil {
		t.Fatal(err)
	}
	waiting := bare
	waiting.WaitingOn = []string{"tk-other"}
	_, _, err = review.FileAsk(w.ledger(), waiting, nil)
	var refused *review.Refusal
	if !errors.As(err, &refused) || !strings.Contains(err.Error(), first) || !strings.Contains(err.Error(), "tk-other") || !strings.Contains(err.Error(), "can take it") {
		t.Fatalf("a re-run waiting on tk-other, beside an open ask that does not wait: %v; want a refusal naming %s and tk-other, which a run can take", err, first)
	}
	row, _ := w.store.Row(first)
	row.Status = "closed"
	w.store.Put(row)
	_, _, err = review.FileAsk(w.ledger(), waiting, nil)
	if !errors.As(err, &refused) || !strings.Contains(err.Error(), first) || !strings.Contains(err.Error(), "closed without waiting on tk-other") || strings.Contains(err.Error(), "can take it") {
		t.Fatalf("a re-run waiting on tk-other, beside a closed ask that did not wait: %v; want a refusal saying %s closed without that wait", err, first)
	}

	later := review.AskRequest{Bead: prBead, Reason: "Fix the cap.", Source: "tk-later", WaitingOn: []string{"tk-other"}}
	second, _, err := review.FileAsk(w.ledger(), later, nil)
	if err != nil {
		t.Fatal(err)
	}
	for _, waits := range [][]string{{"tk-other"}, nil} {
		later.WaitingOn = waits
		if id, filed, err := review.FileAsk(w.ledger(), later, nil); err != nil || filed || id != second {
			t.Fatalf("a re-run waiting on %v = %q, %t, %v; want %s found", waits, id, filed, err, second)
		}
	}
	later.WaitingOn = []string{"tk-other", "tk-third"}
	_, _, err = review.FileAsk(w.ledger(), later, nil)
	if !errors.As(err, &refused) || !strings.Contains(err.Error(), "tk-third") || strings.Contains(err.Error(), "tk-other") {
		t.Fatalf("a re-run that adds tk-third: %v; want a refusal that names tk-third alone", err)
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
