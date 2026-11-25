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
	w2 := newWorld(t)
	w2.output(triage(1, h1, "demo"))
	demo := lane(1, "demo", h1, review.VerdictApprove)
	demo.Visual, demo.VisualFallbackFrom = "repo-artifact", "video"
	w2.output(demo)
	w2.output(repair(1, h1, ""))
	run2, err := review.ReadRun(w2.ledger(), root)
	if err != nil {
		t.Fatal(err)
	}
	if got := review.Comment(run2, 1, nil); !strings.Contains(got, "demo Visual: repo-artifact (author-committed; fallback from video)") {
		t.Errorf("a demo verdict's comment does not name its visual:\n%s", got)
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

	// An ask whose post settles a question, or makes it moot, says so.
	w = newWorld(t)
	w.ask("tk-ask", "")
	w.ask("tk-ask2", "")
	w.output(triage(1, h1))
	w.output(repair(1, h1, "",
		review.Ruling{Ask: "tk-ask", Ruling: review.RulingAnswered, Reason: "it answers the question", Settles: "tk-q1"},
		review.Ruling{Ask: "tk-ask2", Ruling: review.RulingAnswered, Reason: "the cap is gone", Settles: "tk-q2", Moot: true}))
	run, err = review.ReadRun(w.ledger(), root)
	if err != nil {
		t.Fatal(err)
	}
	got = review.Comment(run, 1, nil)
	for _, want := range []string{
		"Answered: it answers the question. The post settles the question at tk-q1.",
		"Answered: the cap is gone. The post makes the question at tk-q2 moot.",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("the comment lacks %q:\n%s", want, got)
		}
	}
}

// A point the round fixed in the PR's summary is answered as fixed there, with
// its commit and the head that carries it when it has one too, and the
// comment's first sentence counts the fixes in the summary apart from the
// ones the push carries.
func TestTheHeadsCommentOnAFixInThePRsSummary(t *testing.T) {
	w := newWorld(t)
	w.output(triage(1, h1, "pm", "arch"))
	w.output(lane(1, "pm", h1, review.VerdictRequestChanges, "PM1"))
	w.output(lane(1, "arch", h1, review.VerdictRequestChanges, "A1"))
	w.output(repair(1, h1, h2,
		review.Ruling{Check: "pm", Finding: "PM1", Ruling: review.RulingMustFix, Reason: "it names the answered ask no more", Summary: true},
		review.Ruling{Check: "arch", Finding: "A1", Ruling: review.RulingMustFix, Reason: "the seam and its account", Commit: fix, Summary: true}))
	run, err := review.ReadRun(w.ledger(), root)
	if err != nil {
		t.Fatal(err)
	}
	got := review.Comment(run, 1, nil)
	for _, want := range []string{
		"pm requested changes, arch requested changes. The round fixed 1 in `" + h2[:12] + "`, fixed 1 in the PR's summary.",
		"Fixed in the PR's summary: it names the answered ask no more",
		"Fixed by `" + fix[:12] + "`, which `" + h2[:12] + "` carries, and in the PR's summary: the seam and its account",
		"| pm | request-changes | 1 P1 | 1 must-fix |",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("the comment lacks %q:\n%s", want, got)
		}
	}

	w = newWorld(t)
	w.output(triage(1, h1, "pm"))
	w.output(lane(1, "pm", h1, review.VerdictRequestChanges, "PM1"))
	w.output(repair(1, h1, "", review.Ruling{Check: "pm", Finding: "PM1", Ruling: review.RulingMustFix, Reason: "r", Summary: true}))
	if run, err = review.ReadRun(w.ledger(), root); err != nil {
		t.Fatal(err)
	}
	if got := review.Comment(run, 1, nil); !strings.Contains(got, "pm requested changes. The round fixed 1 in the PR's summary.") {
		t.Errorf("a round that fixed only the summary reads:\n%s", got)
	}
}
