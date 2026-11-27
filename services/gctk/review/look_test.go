package review_test

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
)

// bound sets the run's max_attempts var.
func (w *world) bound(n string) {
	r, _ := w.store.Row(root)
	r.Metadata["gc.var.max_attempts"] = n
	w.store.Put(r)
}

// mustFixRound writes round n at head: a correctness lane that raised each
// finding and a repair that ruled each must-fix by a commit and pushed it,
// calling for look when there is one.
func (w *world) mustFixRound(n int, head string, look []review.LookDue, ids ...string) {
	w.output(triage(n, head, "correctness"))
	w.output(lane(n, "correctness", head, review.VerdictRequestChanges, ids...))
	var rs []review.Ruling
	for _, id := range ids {
		rs = append(rs, review.Ruling{Check: "correctness", Finding: id, Ruling: review.RulingMustFix, Reason: "it holds", Commit: fix})
	}
	rp := repair(n, head, fix, rs...)
	rp.Look = look
	w.output(rp)
}

// looked writes a round for each must-fix count in counts, the last calling
// for a fresh look at h1, and returns that look's open step.
func (w *world) looked(counts ...int) string {
	w.t.Helper()
	w.bound("30")
	for i, c := range counts {
		var ids []string
		for k := 1; k <= c; k++ {
			ids = append(ids, fmt.Sprintf("F%d", k))
		}
		var look []review.LookDue
		if i == len(counts)-1 {
			look = []review.LookDue{{Head: h1}}
		}
		w.mustFixRound(i+1, h1, look, ids...)
	}
	return w.step(len(counts), "look")
}

// A repair's output carries the fresh look its round calls for, one item at
// the head it judged, and an empty list otherwise, whatever the step wrote.
func TestARepairOutputCallsForTheLookItsRoundIsDue(t *testing.T) {
	w := newWorld(t)
	w.bound("30")
	w.mustFixRound(1, h1, nil, "F1", "F2", "F3")
	w.mustFixRound(2, h1, nil, "F1", "F2")
	w.output(triage(3, h1, "correctness"))
	w.output(lane(3, "correctness", h1, review.VerdictRequestChanges, "F1"))
	must := review.Ruling{Check: "correctness", Finding: "F1", Ruling: review.RulingMustFix, Reason: "it holds", Commit: fix}
	var got review.Repair
	if err := w.check(w.step(3, "rule-and-repair"), repair(3, h1, fix, must), &got); err != nil {
		t.Fatal(err)
	}
	if len(got.Look) != 1 || got.Look[0].Head != h1 {
		t.Errorf("round 3's repair calls for the look %+v; want one at %s", got.Look, h1)
	}

	w = newWorld(t)
	w.bound("30")
	w.output(triage(1, h1, "correctness"))
	w.output(lane(1, "correctness", h1, review.VerdictRequestChanges, "F1"))
	wrote := repair(1, h1, fix, must)
	wrote.Look = []review.LookDue{{Head: h1}}
	if err := w.check(w.step(1, "rule-and-repair"), wrote, &got); err != nil {
		t.Fatal(err)
	}
	if got.Look == nil || len(got.Look) != 0 {
		t.Errorf("round 1's repair calls for the look %+v; want an empty list, whatever the step wrote", got.Look)
	}
}

// A ruling restates a finding of an earlier round of the run that a lane
// raised and that round ruled must-fix; any other is refused.
func TestAFindingThatRestatesAnEarlierOne(t *testing.T) {
	setup := func() (*world, string) {
		w := newWorld(t)
		w.bound("30")
		w.output(triage(1, h1, "correctness"))
		w.output(lane(1, "correctness", h1, review.VerdictRequestChanges, "F1", "F2"))
		w.output(repair(1, h1, fix, review.Ruling{Check: "correctness", Finding: "F1", Ruling: review.RulingMustFix,
			Reason: "it holds", Commit: fix}, finding("correctness", "F2", review.RulingDeclined)))
		w.output(triage(2, h1, "correctness"))
		w.output(lane(2, "correctness", h1, review.VerdictRequestChanges, "G1"))
		return w, w.step(2, "rule-and-repair")
	}
	back := func(ref review.FindingRef) review.Ruling {
		return review.Ruling{Check: "correctness", Finding: "G1", Ruling: review.RulingMustFix, Reason: "again", Commit: fix,
			Restates: &ref}
	}
	w, st := setup()
	if err := w.check(st, repair(2, h1, fix, back(review.FindingRef{Iteration: 1, Check: "Correctness", Finding: "F1"})), nil); err != nil {
		t.Fatalf("a finding that restates a fixed one: %v", err)
	}
	for _, c := range []struct {
		name string
		ref  review.FindingRef
		why  string
	}{
		{"a declined finding", review.FindingRef{Iteration: 1, Check: "correctness", Finding: "F2"}, "ruled declined, not must-fix"},
		{"a finding no lane raised", review.FindingRef{Iteration: 1, Check: "correctness", Finding: "F9"}, "which no lane of that round raised"},
		{"its own round", review.FindingRef{Iteration: 2, Check: "correctness", Finding: "G1"}, "only a finding of an earlier round"},
		{"a round that wrote nothing", review.FindingRef{Iteration: 0, Check: "correctness", Finding: "F1"}, "only a finding of an earlier round"},
	} {
		w, st := setup()
		mustRefuse(t, w.check(st, repair(2, h1, fix, back(c.ref)), nil), c.why)
	}
	w, st = setup()
	w.ask("tk-ask", "")
	ref := review.FindingRef{Iteration: 1, Check: "correctness", Finding: "F1"}
	mustRefuse(t, w.check(st, repair(2, h1, fix, back(ref), review.Ruling{Ask: "tk-ask", Ruling: review.RulingDeclined,
		Reason: "r", Restates: &ref}), nil), "only a lane's finding restates one")
}

// A look's output is the round's own look at the head the round judged, with a
// verdict and a reading. A stop carries its question and its recommendation,
// a continue at a forced round names the rules that caused the counts, a
// continue at the run's last round is refused, and the gate is the record's.
func TestALooksOutput(t *testing.T) {
	cont := review.Look{Review: review.OutputLook, Head: h1, Verdict: review.LookContinue, Reading: "each fix is narrower than the last"}
	stop := review.Look{Review: review.OutputLook, Head: h1, Verdict: review.LookStop, Reading: "the design moved under the text",
		Recommendation: "rewrite section 1", Question: "Rewrite section 1, or go on fixing it point by point?"}
	w := newWorld(t)
	st := w.looked(5, 2, 1)
	var got review.Look
	if err := w.check(st, cont, &got); err != nil {
		t.Fatal(err)
	}
	if got.Iteration != 3 || got.Gate != "" {
		t.Errorf("the look prints iteration %d and gate %q; want 3 and none", got.Iteration, got.Gate)
	}
	if err := w.check(st, stop, nil); err != nil {
		t.Errorf("a stop with its question: %v", err)
	}
	noQuestion := stop
	noQuestion.Question = ""
	mustRefuse(t, w.check(st, noQuestion, nil), "carries no question")
	noReading := cont
	noReading.Reading = " "
	mustRefuse(t, w.check(st, noReading, nil), "writes its reading")
	gated := stop
	gated.Gate = "tk-gate"
	mustRefuse(t, w.check(st, gated, nil), "its record files and fills in")
	other := cont
	other.Head = h2
	mustRefuse(t, w.check(st, other, nil), "round 3 judged "+h1)
	verdict := cont
	verdict.Verdict = "maybe"
	mustRefuse(t, w.check(st, verdict, nil), `the verdict reads "maybe"`)

	w = newWorld(t)
	st = w.looked(3, 3, 3)
	mustRefuse(t, w.check(st, cont, nil), "the account forces a question")
	byRules := cont
	byRules.Rules = []string{fix}
	if err := w.check(st, byRules, nil); err != nil {
		t.Errorf("a continue that names the rule that caused the counts: %v", err)
	}
	byRules.Rules = []string{"abc"}
	mustRefuse(t, w.check(st, byRules, nil), "not a full object name")

	w = newWorld(t)
	st = w.looked(5, 2, 1)
	w.bound("3")
	mustRefuse(t, w.check(st, cont, nil), "last by its bound")

	w = newWorld(t)
	w.bound("30")
	w.mustFixRound(1, h1, nil, "F1", "F2")
	mustRefuse(t, w.check(w.step(1, "look"), cont, nil), "called for no fresh look")
}

// gateFiler files a stop's question as a human gate that holds the PR's bead,
// as human-gate.sh does, keeping the message.
type gateFiler struct {
	w    *world
	text []string
	err  error
}

func (g *gateFiler) File(subject, key, message string) error {
	if g.err != nil {
		return g.err
	}
	g.text = append(g.text, message)
	g.w.question("tk-gate", key, "open", true)
	return nil
}

// A stop's record files its question on the PR's bead, gives its step the
// look with the gate and Gas City's hard failure record, and notes the look on
// the PR's bead. A continue files nothing and marks no failure.
func TestALooksRecord(t *testing.T) {
	at := time.Date(2026, 11, 27, 19, 0, 0, 0, time.UTC)
	stop := review.Look{Review: review.OutputLook, Head: h1, Verdict: review.LookStop, Reading: "the design moved under the text",
		Recommendation: "rewrite section 1", Question: "Rewrite section 1, or go on fixing it point by point?"}
	w := newWorld(t)
	st := w.looked(3, 3, 3)
	g := &gateFiler{w: w}
	got, err := review.RecordLook(w.ledger(), review.OutputRequest{Step: st, Raw: jsonOf(t, stop)}, nil, g, at)
	if err != nil {
		t.Fatal(err)
	}
	if got.Gate != "tk-gate" || len(g.text) != 1 {
		t.Fatalf("the record filed %v with the gate %q; want one question at tk-gate", g.text, got.Gate)
	}
	for _, want := range []string{"stopped at round 3 for your answer", "not converging, as its must-fix findings have not fallen",
		stop.Question, "Recommendation: rewrite section 1.", "Must-fix findings by round: 3, 3, 3."} {
		if !strings.Contains(g.text[0], want) {
			t.Errorf("the question's message lacks %q:\n%s", want, g.text[0])
		}
	}
	row, _ := w.store.Row(st)
	var kept review.Look
	if err := json.Unmarshal([]byte(row.Metadata["gc.output_json"]), &kept); err != nil || kept.Gate != "tk-gate" || kept.Iteration != 3 {
		t.Errorf("the step keeps %q (%v); want the look with its gate", row.Metadata["gc.output_json"], err)
	}
	if row.Metadata["gc.failure_class"] != "hard" || !strings.Contains(row.Metadata["gc.failure_reason"], "through tk-gate") {
		t.Errorf("the step's failure record reads %q, %q; want hard, naming the gate", row.Metadata["gc.failure_class"],
			row.Metadata["gc.failure_reason"])
	}
	pr, _ := w.store.Row(prBead)
	if !strings.Contains(pr.Notes, "## Fresh look at round 3 of review run "+root+" (2026-11-27T19:00:00Z)") ||
		!strings.Contains(pr.Notes, "Stopped for a person's answer through tk-gate") {
		t.Errorf("the PR's bead is noted %q", pr.Notes)
	}

	w = newWorld(t)
	st = w.looked(5, 2, 1)
	g = &gateFiler{w: w}
	cont := review.Look{Review: review.OutputLook, Head: h1, Verdict: review.LookContinue, Reading: "each fix is narrower than the last"}
	if got, err = review.RecordLook(w.ledger(), review.OutputRequest{Step: st, Raw: jsonOf(t, cont)}, nil, g, at); err != nil {
		t.Fatal(err)
	}
	row, _ = w.store.Row(st)
	if len(g.text) != 0 || got.Gate != "" || row.Metadata["gc.failure_class"] != "" {
		t.Errorf("a continue filed %v and marked %q; want nothing filed and no failure", g.text, row.Metadata["gc.failure_class"])
	}

	w = newWorld(t)
	st = w.looked(3, 3, 3)
	_, err = review.RecordLook(w.ledger(), review.OutputRequest{Step: st, Raw: jsonOf(t, stop)}, nil,
		&gateFiler{w: w, err: errors.New("down")}, at)
	var unrecorded *review.LookUnrecorded
	if !errors.As(err, &unrecorded) {
		t.Errorf("a question that did not land returns %v; want a record to run again", err)
	}

	// A continue the account forced a question at goes on by naming a rule the
	// look's read printed among the review's rules that changed, and no other.
	w = newWorld(t)
	st = w.looked(3, 3, 3)
	byRules := cont
	byRules.Rules = []string{fix}
	_, err = review.RecordLook(w.ledger(), review.OutputRequest{Step: st, Raw: jsonOf(t, byRules)}, nil, &gateFiler{w: w}, at)
	mustRefuse(t, err, "none of the review's rules that changed")
	changed := []review.RuleChange{{Commit: fix, Date: "2026-11-26", Subject: "docs(review): a new rule", Paths: []string{"AGENTS.md"}}}
	if _, err = review.RecordLook(w.ledger(), review.OutputRequest{Step: st, Raw: jsonOf(t, byRules)}, changed,
		&gateFiler{w: w}, at); err != nil {
		t.Errorf("a continue that names a rule the read printed: %v", err)
	}
}

// A run its look stopped ends with no result, as any hard failure of its loop
// does, and reads as one that put the review to a person.
func TestARunItsLookStoppedEnds(t *testing.T) {
	w := newWorld(t)
	w.looked(3, 3, 3)
	stop := review.Look{Review: review.OutputLook, Iteration: 3, Head: h1, Verdict: review.LookStop, Reading: "r",
		Recommendation: "x", Question: "q?", Gate: "tk-gate"}
	w.output(stop)
	w.closeLoop(map[string]string{"gc.outcome": "fail", "gc.final_disposition": "hard_fail"})
	r, _ := w.store.Row(root)
	r.Status = "closed"
	r.Metadata["gc.outcome"] = "fail"
	w.store.Put(r)
	e, err := review.Ended(w.ledger(), root)
	if err != nil {
		t.Fatal(err)
	}
	if e.Result || !e.Asked || !strings.Contains(e.How, "fresh look at round 3 stopped it") || !strings.Contains(e.How, "tk-gate") {
		t.Errorf("the run ended %+v; want no result, asked, through tk-gate", e)
	}
}

// The round's comment carries the account's line, and the look's verdict once
// the look wrote one.
func TestTheHeadsCommentCarriesTheAccountAndTheLook(t *testing.T) {
	w := newWorld(t)
	w.looked(3, 3, 3)
	run, err := review.ReadRun(w.ledger(), root)
	if err != nil {
		t.Fatal(err)
	}
	body := review.Comment(run, 3, nil)
	if !strings.Contains(body, "Round 3: 3 must-fix findings (3, 3, 3 by round), level. The review is not converging") {
		t.Errorf("the comment lacks the account's line:\n%s", body)
	}
	if strings.Contains(body, "**Fresh look:**") {
		t.Errorf("the comment carries a look before the look wrote:\n%s", body)
	}
	w.output(review.Look{Review: review.OutputLook, Iteration: 3, Head: h1, Verdict: review.LookStop, Reading: "the design moved",
		Recommendation: "rewrite section 1", Question: "Rewrite section 1?", Gate: "tk-gate"})
	if run, err = review.ReadRun(w.ledger(), root); err != nil {
		t.Fatal(err)
	}
	body = review.Comment(run, 3, nil)
	if !strings.Contains(body, "**Fresh look:** the review stops for your answer at tk-gate. Rewrite section 1? "+
		"Recommendation: rewrite section 1. Why the findings keep coming: the design moved.") {
		t.Errorf("the comment lacks the look's verdict:\n%s", body)
	}
}

// The round's read lists each finding an earlier round ruled must-fix, which a
// finding of the round can restate, and a ruling that restates one says so.
func TestTheRoundsReadListsTheFindingsItCanRestate(t *testing.T) {
	w := newWorld(t)
	w.bound("30")
	w.mustFixRound(1, h1, nil, "F1")
	w.output(triage(2, h1, "correctness"))
	w.output(lane(2, "correctness", h1, review.VerdictRequestChanges, "G1"))
	ref := review.FindingRef{Iteration: 1, Check: "correctness", Finding: "F1"}
	w.output(repair(2, h1, fix, review.Ruling{Check: "correctness", Finding: "G1", Ruling: review.RulingMustFix,
		Reason: "again", Commit: fix, Restates: &ref}))
	v, err := review.Passed(w.ledger(), root, 2)
	if err != nil {
		t.Fatal(err)
	}
	got := v.Explain()
	for _, want := range []string{"earlier rounds' must-fix findings", "round 1 correctness F1 at a.go:f: m",
		"back after a fix of correctness finding F1 of round 1"} {
		if !strings.Contains(got, want) {
			t.Errorf("the account lacks %q:\n%s", want, got)
		}
	}
}
