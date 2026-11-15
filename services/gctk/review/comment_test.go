package review_test

import (
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
)

// The head's comment carries every lane's verdict, approvals included, each
// finding with how the round ruled it and what the head carries for it, and
// each ask the round took, under a mark that names the run and the head. An
// iteration where no lane ran and the round took no ask has nothing to answer.
func TestTheHeadsComment(t *testing.T) {
	w := newWorld(t)
	w.ask("tk-ask", "")
	w.output(triage(1, h1, "correctness", "arch"))
	w.output(lane(1, "correctness", h1, review.VerdictApprove, "C1"))
	w.output(lane(1, "arch", h1, review.VerdictRequestChanges, "A1"))
	w.output(repair(1, h1, h2,
		review.Ruling{Check: "correctness", Finding: "C1", Ruling: review.RulingDeclined, Reason: "a nit"},
		review.Ruling{Check: "arch", Finding: "A1", Ruling: review.RulingMustFix, Reason: "the boundary leaks", Commit: fix},
		review.Ruling{Ask: "tk-ask", Ruling: review.RulingAnswered, Reason: "the head already does it"}))
	run, err := review.ReadRun(w.ledger(), root)
	if err != nil {
		t.Fatal(err)
	}
	asks, err := review.AsksOn(w.ledger(), prBead)
	if err != nil {
		t.Fatal(err)
	}
	got := review.Comment(run, 1, asks)
	for _, want := range []string{
		review.Mark(root, h1),
		"| correctness | approve | 1 P1 | 1 declined |",
		"| arch | request-changes | 1 P1 | 1 must-fix |",
		"correctness approved, arch requested changes",
		"Declined, and the head carries no change for it: a nit",
		"Fixed by `" + fix[:12] + "`, which `" + h2[:12] + "` carries: the boundary leaks",
		"change it (tk-ask): Answered: the head already does it",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("the comment lacks %q:\n%s", want, got)
		}
	}
	if !strings.HasPrefix(got, review.Mark(root, h1)+"\n") {
		t.Errorf("the comment does not open with its mark:\n%s", got)
	}

	w = newWorld(t)
	w.output(triage(1, h1))
	w.output(repair(1, h1, ""))
	run, err = review.ReadRun(w.ledger(), root)
	if err != nil {
		t.Fatal(err)
	}
	if got := review.Comment(run, 1, nil); got != "" {
		t.Errorf("an iteration with nothing to answer renders %q", got)
	}
}
