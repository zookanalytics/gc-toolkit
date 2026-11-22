package review_test

import (
	"encoding/json"
	"errors"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
)

// output checks what a step wrote and decodes what it printed into v.
func (w *world) check(step string, wrote any, v any, repos ...string) error {
	w.t.Helper()
	raw, ok := wrote.([]byte)
	if !ok {
		raw = jsonOf(w.t, wrote)
	}
	l := w.ledger()
	out, err := review.Output(l, review.OutputRequest{Step: step, Raw: raw, Repos: repos,
		Withdrawal: func(bead, head string) (string, error) { return pr.WithdrawalFor(l, bead, head) }})
	if err != nil {
		return err
	}
	if v != nil {
		if err := json.Unmarshal(out, v); err != nil {
			w.t.Fatalf("the printed output does not decode: %v: %s", err, out)
		}
	}
	return nil
}

func mustRefuse(t *testing.T, err error, why string) {
	t.Helper()
	var r *review.Refused
	if !errors.As(err, &r) {
		t.Fatalf("the output stood or failed otherwise (%v); want it refused for %q", err, why)
	}
	if !strings.Contains(r.Why, why) {
		t.Fatalf("refused for %q; want %q", r.Why, why)
	}
}

// A triage output gets its step's iteration and an empty list of picks, which
// its fan-out reads as an array. One naming another iteration, another head,
// another step's shape, a field the shape does not name, or a check twice is
// refused.
func TestATriageOutput(t *testing.T) {
	w := newWorld(t)
	st := w.step(1, "triage")
	var got map[string]any
	if err := w.check(st, map[string]any{"review": "triage", "head": h1, "material": false}, &got); err != nil {
		t.Fatal(err)
	}
	if got["iteration"] != float64(1) {
		t.Errorf("the iteration printed reads %v; want 1", got["iteration"])
	}
	if picks, ok := got["checks"].([]any); !ok || len(picks) != 0 {
		t.Errorf("an output with no picks prints checks %v; want an empty array", got["checks"])
	}
	mustRefuse(t, w.check(st, map[string]any{"review": "triage", "iteration": 2, "head": h1}, nil), "names iteration 2")
	mustRefuse(t, w.check(st, map[string]any{"review": "triage", "head": h2}, nil), "iteration 1 judges "+h1)
	mustRefuse(t, w.check(st, map[string]any{"review": "lane", "head": h1}, nil), `review field reads "triage"`)
	mustRefuse(t, w.check(st, map[string]any{"review": "triage", "head": h1, "picks": []any{}}, nil), "does not read in its shape")
	mustRefuse(t, w.check(st, triage(1, h1, "correctness", "Correctness"), nil), "picked twice")
	mustRefuse(t, w.check(st, []byte("not json"), nil), "not one JSON object")
}

// A triage that rules its head material stands only once the withdrawal for
// that head is filed on the bead that owns the PR, open or carried out, and
// one for another head does not count. A read of the withdrawals that fails is
// no refusal: the step writes nothing until the store answers.
func TestATriageThatRulesItsHeadMaterialNeedsItsWithdrawal(t *testing.T) {
	w := newWorld(t)
	st := w.step(1, "triage")
	material := map[string]any{"review": "triage", "head": h1, "material": true}
	mustRefuse(t, w.check(st, material, nil), "no withdrawal for it is filed on "+prBead)

	w.withdrawal("tk-wd2", h2, "open")
	mustRefuse(t, w.check(st, material, nil), "no withdrawal for it is filed on "+prBead)

	w.withdrawal("tk-wd1", h1, "open")
	if err := w.check(st, material, nil); err != nil {
		t.Fatalf("a material head with its withdrawal filed is refused: %v", err)
	}
	w.withdrawal("tk-wd1", h1, "closed")
	if err := w.check(st, material, nil); err != nil {
		t.Fatalf("a material head whose withdrawal was carried out is refused: %v", err)
	}

	broken := newWorld(t)
	_, err := review.Output(broken.ledger(), review.OutputRequest{Step: broken.step(1, "triage"), Raw: jsonOf(t, material),
		Withdrawal: func(string, string) (string, error) { return "", errors.New("the store did not answer") }})
	var refused *review.Refused
	if err == nil || errors.As(err, &refused) {
		t.Fatalf("a withdrawal read that failed returns %v; want the read's error, not a refusal", err)
	}
}

// withdrawal files a withdrawal for head on the PR's bead, as gctk pr withdraw
// does: a bead naming the head that the PR's bead waits on.
func (w *world) withdrawal(id, head, status string) {
	w.store.Put(bead{ID: id, Status: status, IssueType: "task", Description: "the call", Metadata: map[string]string{
		"withdraw_head": head,
	}})
	pr, _ := w.store.Row(prBead)
	if !slices.ContainsFunc(pr.Edges, func(e gcbd.Edge) bool { return e.ID == id }) {
		pr.Edges = append(pr.Edges, gcbd.Edge{ID: id, Type: gcbd.EdgeBlocks})
		w.store.Put(pr)
	}
}

// A lane writes for a check triage picked, at the head triage judged, with a
// verdict and findings that each name an id, a locus and a message.
func TestALaneOutput(t *testing.T) {
	w := newWorld(t)
	w.output(triage(1, h1, "arch"))
	st := w.step(1, "lane")
	if err := w.check(st, lane(1, "arch", h1, review.VerdictRequestChanges, "A1"), nil); err != nil {
		t.Fatal(err)
	}
	mustRefuse(t, w.check(st, lane(1, "pm", h1, review.VerdictApprove), nil), `did not pick "pm"`)
	mustRefuse(t, w.check(st, lane(1, "arch", h2, review.VerdictApprove), nil), "reviews "+h1)
	mustRefuse(t, w.check(st, lane(1, "arch", h1, "comment"), nil), `verdict reads "comment"`)
	mustRefuse(t, w.check(st, lane(1, "arch", h1, review.VerdictRequestChanges, "A1", "A1"), nil), "used twice")
	ln := lane(1, "arch", h1, review.VerdictRequestChanges, "A1")
	ln.Findings[0].Locus = ""
	mustRefuse(t, w.check(st, ln, nil), "needs its locus and its message")
}

// A lane's findings keep the finding contract: a grade of P0, P1 or P2, which
// every correctness finding carries, and with it a category and a failure
// scenario; a P0 or P1 verified CONFIRMED or PLAUSIBLE; no REFUTED candidate.
// An approve carries no blocking finding, and request-changes at least one.
func TestALanesFindingContract(t *testing.T) {
	w := newWorld(t)
	w.output(triage(1, h1, "correctness", "arch"))
	st := w.step(1, "lane")
	with := func(check, verdict string, edit func(*review.Finding)) review.Lane {
		ln := lane(1, check, h1, verdict, "F1")
		edit(&ln.Findings[0])
		return ln
	}
	keep := func(*review.Finding) {}
	var got review.Lane
	if err := w.check(st, with("correctness", review.VerdictRequestChanges, func(f *review.Finding) { f.Severity = "p1" }), &got); err != nil ||
		got.Findings[0].Severity != "P1" {
		t.Errorf("a lower-case grade = %v, %q; want it to stand, upper-cased", err, got.Findings[0].Severity)
	}
	p2 := func(f *review.Finding) { f.Severity = "P2"; f.Verification = "" }
	if err := w.check(st, with("correctness", review.VerdictApprove, p2), nil); err != nil {
		t.Errorf("an approve carrying a P2 is refused: %v", err)
	}
	if err := w.check(st, with("arch", review.VerdictRequestChanges, func(f *review.Finding) {
		f.Severity, f.Category, f.FailureScenario, f.Verification = "", "", "", ""
	}), nil); err != nil {
		t.Errorf("another check's ungraded finding, which blocks, is refused: %v", err)
	}
	for _, c := range []struct {
		name    string
		check   string
		verdict string
		edit    func(*review.Finding)
		why     string
	}{
		{"an approve with a P1", "correctness", review.VerdictApprove, keep, "an approve carries no blocking finding"},
		{"request-changes with only a P2", "correctness", review.VerdictRequestChanges, p2, "request-changes needs a blocking finding"},
		{"an ungraded correctness finding", "correctness", review.VerdictRequestChanges, func(f *review.Finding) { f.Severity = "" },
			"every correctness finding is graded"},
		{"a grade outside the set", "arch", review.VerdictRequestChanges, func(f *review.Finding) { f.Severity = "high" }, "not P0, P1 or P2"},
		{"a graded finding with no category", "arch", review.VerdictRequestChanges, func(f *review.Finding) { f.Category = "" },
			"names its category and its failure_scenario"},
		{"a refuted candidate", "correctness", review.VerdictRequestChanges, func(f *review.Finding) { f.Verification = "REFUTED: no" },
			"a refuted candidate is not a finding"},
		{"a P1 with no evidence", "correctness", review.VerdictRequestChanges, func(f *review.Finding) { f.Verification = "I think so" },
			"opens CONFIRMED or PLAUSIBLE"},
	} {
		mustRefuse(t, w.check(st, with(c.check, c.verdict, c.edit), nil), c.why)
	}
}

// A demo lane's verdict carries its visual decision, none only with an
// approve, and a fallback cheaper than the modality it stands in for. No other
// lane records one.
func TestADemoLanesVisual(t *testing.T) {
	w := newWorld(t)
	w.output(triage(1, h1, "demo", "arch"))
	st := w.step(1, "lane")
	demo := func(verdict, visual, from string) review.Lane {
		ln := lane(1, "demo", h1, verdict)
		if verdict == review.VerdictRequestChanges {
			ln = lane(1, "demo", h1, verdict, "D1")
		}
		ln.Visual, ln.VisualFallbackFrom = visual, from
		return ln
	}
	var got review.Lane
	if err := w.check(st, demo(review.VerdictApprove, "Screenshot", "video"), &got); err != nil ||
		got.Visual != "screenshot" || got.VisualFallbackFrom != "video" {
		t.Errorf("a screenshot standing in for a video = %v, %q from %q", err, got.Visual, got.VisualFallbackFrom)
	}
	for _, c := range []struct {
		ln  review.Lane
		why string
	}{
		{demo(review.VerdictApprove, "", ""), "records its visual decision on every verdict"},
		{demo(review.VerdictApprove, "gif", ""), "not none, repo-artifact, screenshot or video"},
		{demo(review.VerdictRequestChanges, "none", ""), "goes with an approve only"},
		{demo(review.VerdictApprove, "video", "screenshot"), "a fallback is cheaper"},
		{demo(review.VerdictApprove, "none", "video"), "a visual of none delivers none"},
		{demo(review.VerdictApprove, "screenshot", "repo-artifact"), "not screenshot or video"},
	} {
		mustRefuse(t, w.check(st, c.ln, nil), c.why)
	}
	arch := lane(1, "arch", h1, review.VerdictApprove)
	arch.Visual = "screenshot"
	mustRefuse(t, w.check(st, arch, nil), "only the demo check records a visual decision")
}

// A correctness approve on a change that edits its own review guidance is
// refused until needs_you names the edit. Paths that cannot be listed leave
// the edit unchecked, and needs_you says so. Another check's approve, and a
// change that edits no guidance, need nothing.
func TestTheGuidanceEditGuard(t *testing.T) {
	r := newHeadRepo(t)
	setup := func(head string, check string) (*world, string) {
		w := newWorld(t)
		root2, _ := w.store.Row(root)
		root2.Metadata["gc.var.head"] = head
		w.store.Put(root2)
		w.output(triage(1, head, check))
		return w, w.step(1, "lane")
	}
	w, st := setup(r.h2, "correctness")
	mustRefuse(t, w.check(st, lane(1, "correctness", r.h2, review.VerdictApprove), nil, r.dir), "docs/review-arch.md")
	named := lane(1, "correctness", r.h2, review.VerdictApprove)
	named.NeedsYou = "This change edits the arch guidance, which its own arch review read."
	var got review.Lane
	if err := w.check(st, named, &got, r.dir); err != nil || got.NeedsYou != named.NeedsYou {
		t.Errorf("an approve that names the edit = %v, needs_you %q", err, got.NeedsYou)
	}
	if err := w.check(st, lane(1, "correctness", r.h2, review.VerdictRequestChanges, "C1"), nil, r.dir); err != nil {
		t.Errorf("a request-changes on the same change is refused: %v", err)
	}
	w, st = setup(r.h1, "correctness")
	got = review.Lane{}
	if err := w.check(st, lane(1, "correctness", r.h1, review.VerdictApprove), &got, r.dir); err != nil || got.NeedsYou != "" {
		t.Errorf("an approve of a change that edits no guidance = %v, needs_you %q", err, got.NeedsYou)
	}
	got = review.Lane{}
	if err := w.check(st, lane(1, "correctness", r.h1, review.VerdictApprove), &got); err != nil ||
		!strings.Contains(got.NeedsYou, "unchecked") {
		t.Errorf("with no repository to list the paths in, the approve = %v, needs_you %q; want it to say the edit is unchecked", err, got.NeedsYou)
	}
	w, st = setup(r.h2, "arch")
	if err := w.check(st, lane(1, "arch", r.h2, review.VerdictApprove), nil, r.dir); err != nil {
		t.Errorf("an arch approve of a change that edits guidance is refused: %v", err)
	}
}

// A round rules each finding its iteration's lanes raised and each ask it can
// take, once each, by a ruling in the set and with a reason. A must-fix names
// the commit that fixes it, and a ruling that changes no code names none; a
// question names its gate. An ask an earlier round of the run declined takes
// no fix.
func TestARepairOutput(t *testing.T) {
	setup := func() (*world, string) {
		w := newWorld(t)
		w.output(triage(1, h1, "correctness"))
		w.output(lane(1, "correctness", h1, review.VerdictRequestChanges, "F1"))
		return w, w.step(1, "rule-and-repair")
	}
	must := review.Ruling{Check: "correctness", Finding: "F1", Ruling: review.RulingMustFix, Reason: "it holds", Commit: fix}
	w, st := setup()
	if err := w.check(st, repair(1, h1, fix, must), nil); err != nil {
		t.Fatal(err)
	}
	for _, c := range []struct {
		name string
		rp   review.Repair
		why  string
	}{
		{"an unruled finding", repair(1, h1, ""), "finding F1 is not ruled"},
		{"a finding no lane raised", repair(1, h1, "", finding("correctness", "F1", review.RulingDeclined),
			finding("correctness", "F9", review.RulingDeclined)), "no lane of this iteration raised correctness finding F9"},
		{"a finding ruled twice", repair(1, h1, "", finding("correctness", "F1", review.RulingDeclined),
			finding("correctness", "F1", review.RulingAnswered)), "ruled twice"},
		{"a ruling outside the set", repair(1, h1, "", finding("correctness", "F1", "fixed")), "not a ruling"},
		{"a must-fix with no commit", repair(1, h1, "", review.Ruling{Check: "correctness", Finding: "F1",
			Ruling: review.RulingMustFix, Reason: "r"}), "names no commit"},
		{"a decline with a commit", repair(1, h1, "", review.Ruling{Check: "correctness", Finding: "F1",
			Ruling: review.RulingDeclined, Reason: "r", Commit: fix}), "changes no code"},
		{"a question with no gate", repair(1, h1, "", review.Ruling{Check: "correctness", Finding: "F1",
			Ruling: review.RulingQuestion, Reason: "r"}), "names no gate"},
		{"a ruling with no reason", repair(1, h1, "", review.Ruling{Check: "correctness", Finding: "F1",
			Ruling: review.RulingDeclined}), "with no reason"},
		{"another head", repair(1, h2, "", finding("correctness", "F1", review.RulingDeclined)), "judged " + h1},
		{"a push that is no commit", repair(1, h1, "abc", must), "not a full object name"},
	} {
		w, st := setup()
		mustRefuse(t, w.check(st, c.rp, nil), c.why)
	}

	w, st = setup()
	w.ask("tk-ask", "")
	mustRefuse(t, w.check(st, repair(1, h1, fix, must), nil), "ask tk-ask is open and nothing holds it")
	if err := w.check(st, repair(1, h1, fix, must, review.Ruling{Ask: "tk-ask", Ruling: review.RulingDeclined,
		Reason: "a nit, answered and not fixed"}), nil); err != nil {
		t.Errorf("a round that rules the ask: %v", err)
	}
	w.store.Put(bead{ID: "tk-other", Status: "open", IssueType: "task"})
	w.ask("tk-held", "", gcbd.Edge{ID: "tk-other", Type: gcbd.EdgeBlocks})
	w.store.List("tk-held", "tk-other")
	w.store.Mark("tk-held")
	mustRefuse(t, w.check(st, repair(1, h1, fix, must, review.Ruling{Ask: "tk-ask", Ruling: review.RulingDeclined, Reason: "r"},
		review.Ruling{Ask: "tk-held", Ruling: review.RulingAnswered, Reason: "r"}), nil), "not an ask the round can take")

	// The ask declined at iteration 1 takes no fix at iteration 2.
	w = newWorld(t)
	w.ask("tk-ask", "")
	w.output(triage(1, h1))
	w.output(repair(1, h1, "", review.Ruling{Ask: "tk-ask", Ruling: review.RulingDeclined, Reason: "a nit"}))
	w.output(triage(2, h1))
	st = w.step(2, "rule-and-repair")
	mustRefuse(t, w.check(st, repair(2, h1, fix, review.Ruling{Ask: "tk-ask", Ruling: review.RulingMustFix, Reason: "r",
		Commit: fix}), nil), "an earlier round of this run ruled ask tk-ask declined")
}

// question puts a human gate on the store under key, open or closed, which
// holds the bead that owns the PR by its blocks edge when holds says so.
func (w *world) question(id, key, status string, holds bool) {
	w.store.Put(bead{ID: id, Title: "Is the cap the operator's to set?", Status: status, IssueType: "gate",
		AwaitType: "human", AwaitID: key})
	if holds {
		pr, _ := w.store.Row(prBead)
		pr.Edges = append(pr.Edges, gcbd.Edge{ID: id, Type: gcbd.EdgeBlocks, Status: status, IssueType: "gate", AwaitType: "human"})
		w.store.Put(pr)
	}
}

// A ruling of an ask names the gate of a question the ask's post settles, an
// open human gate under a question's key that holds the bead that owns the PR,
// with moot when the post makes the question moot. Moot with no gate, a
// finding's ruling or a question's that settles a gate, two rulings that
// settle one, a gate the round also puts a question to, and a gate that is
// closed, keyed as no question, missing or not holding the bead are refused.
func TestARulingThatSettlesAQuestion(t *testing.T) {
	setup := func() (*world, string) {
		w := newWorld(t)
		w.ask("tk-ask", "")
		w.ask("tk-ask2", "")
		w.output(triage(1, h1))
		w.question("tk-q1", review.QuestionKey+"scope", "open", true)
		return w, w.step(1, "rule-and-repair")
	}
	settles := func(ask, gate string, moot bool) review.Ruling {
		return review.Ruling{Ask: ask, Ruling: review.RulingAnswered, Reason: "it answers the question", Settles: gate, Moot: moot}
	}
	other := review.Ruling{Ask: "tk-ask2", Ruling: review.RulingDeclined, Reason: "a nit"}
	w, st := setup()
	var got review.Repair
	if err := w.check(st, repair(1, h1, "", settles("tk-ask", "tk-q1", true), other), &got); err != nil {
		t.Fatal(err)
	}
	if r := got.Rulings[0]; r.Settles != "tk-q1" || !r.Moot {
		t.Fatalf("the printed output keeps the ruling as %+v", r)
	}
	for _, c := range []struct {
		name  string
		rs    []review.Ruling
		setup func(w *world)
		why   string
	}{
		{"moot with no gate", []review.Ruling{{Ask: "tk-ask", Ruling: review.RulingAnswered, Reason: "r", Moot: true}, other},
			nil, "names no gate"},
		{"a question that settles a gate", []review.Ruling{{Ask: "tk-ask", Ruling: review.RulingQuestion, Reason: "r",
			Gate: "tk-q9", Settles: "tk-q1"}, other}, nil, "a question settles none"},
		{"two rulings that settle one gate", []review.Ruling{settles("tk-ask", "tk-q1", false),
			settles("tk-ask2", "tk-q1", false)}, nil, "both settle the gate tk-q1"},
		{"a gate the round puts a question to", []review.Ruling{settles("tk-ask", "tk-q1", false),
			{Ask: "tk-ask2", Ruling: review.RulingQuestion, Reason: "r", Gate: "tk-q1"}}, nil, "puts a question to"},
		{"a closed gate", []review.Ruling{settles("tk-ask", "tk-q2", false), other},
			func(w *world) { w.question("tk-q2", review.QuestionKey+"other", "closed", true) }, "closed already"},
		{"a gate keyed as no question", []review.Ruling{settles("tk-ask", "tk-q2", false), other},
			func(w *world) { w.question("tk-q2", "review-run-failed", "open", true) }, "no question's key"},
		{"a gate the store does not hold", []review.Ruling{settles("tk-ask", "tk-q9", false), other}, nil, "the store does not hold"},
		{"a gate that does not hold the bead", []review.Ruling{settles("tk-ask", "tk-q2", false), other},
			func(w *world) { w.question("tk-q2", review.QuestionKey+"other", "open", false) }, "does not hold " + prBead},
	} {
		t.Run(c.name, func(t *testing.T) {
			w, st := setup()
			if c.setup != nil {
				c.setup(w)
			}
			mustRefuse(t, w.check(st, repair(1, h1, "", c.rs...), nil), c.why)
		})
	}
	w = newWorld(t)
	w.output(triage(1, h1, "correctness"))
	w.output(lane(1, "correctness", h1, review.VerdictApprove, "F1"))
	w.question("tk-q1", review.QuestionKey+"scope", "open", true)
	st = w.step(1, "rule-and-repair")
	mustRefuse(t, w.check(st, repair(1, h1, "", review.Ruling{Check: "correctness", Finding: "F1",
		Ruling: review.RulingDeclined, Reason: "r", Settles: "tk-q1"}), nil), "only the ruling of an ask")
}

// A finding is its lane's check, compared without case, and its id as the
// lane wrote it, in the round's output as in the pass rule: two findings whose
// ids differ only in case are two, each ruled once, and the round that rules
// both passes.
func TestAFindingsIDKeepsItsCase(t *testing.T) {
	lanes := func(w *world) {
		w.output(triage(1, h1, "correctness"))
		w.output(lane(1, "correctness", h1, review.VerdictRequestChanges, "F1", "f1"))
	}
	one := repair(1, h1, "", finding("correctness", "F1", review.RulingDeclined))
	both := repair(1, h1, "", finding("Correctness", "F1", review.RulingDeclined),
		finding("correctness", "f1", review.RulingDeclined))
	w := newWorld(t)
	lanes(w)
	st := w.step(1, "rule-and-repair")
	mustRefuse(t, w.check(st, one, nil), "correctness finding f1 is not ruled")
	if err := w.check(st, both, nil); err != nil {
		t.Fatalf("a round that rules F1 and f1 once each: %v", err)
	}
	w = newWorld(t)
	lanes(w)
	w.output(one)
	mustFail(t, w.passed(1), "correctness finding f1 is not ruled")
	w = newWorld(t)
	lanes(w)
	w.output(both)
	mustPass(t, w.passed(1))
}

// A bead of the run that writes no output, such as the loop's spec, is
// refused.
func TestAStepThatWritesNoOutput(t *testing.T) {
	w := newWorld(t)
	w.store.Put(bead{ID: "tk-spec", Status: "in_progress", IssueType: "task", Metadata: map[string]string{
		"gc.root_bead_id": root, "gc.step_ref": "mol-pr-review.review-loop.spec",
	}})
	mustRefuse(t, w.check("tk-spec", triage(1, h1), nil), "not a step that writes an output")
}
