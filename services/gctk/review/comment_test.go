package review_test

import (
	"fmt"
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

// A demo verdict's visual reads on the head's comment as the PR carries it:
// its modality linked to the comment that delivered it, with a repo-artifact
// read as author-committed and a fallback naming what stopped the one that
// fits, or, for a visual the PR does not carry, that none was delivered and
// what stopped it. A visual with neither a comment nor a stop, as a lane
// output stored before the write required one can hold, reads that its
// delivery is not recorded. What the check covered follows in a block of its
// own.
func TestTheHeadsCommentOnADemoVisual(t *testing.T) {
	const at = "https://github.com/o/r/pull/7#issuecomment-42"
	for _, c := range []struct {
		name                           string
		visual, from, comment, stopped string
		want                           string
	}{
		{"delivered", "video", "", at, "", "demo Visual: [video](" + at + ")\n"},
		{"a fallback", "repo-artifact", "video", at, "no app runs on this host",
			"demo Visual: [repo-artifact](" + at + ") (author-committed; fallback from video: no app runs on this host)\n"},
		{"not delivered", "video", "", "", "the capture toolchain does not\n resolve on this host",
			"demo Visual: video warranted, none delivered: the capture toolchain does not resolve on this host\n"},
		{"no visual needed", "none", "", "", "", "demo Visual: none\n"},
		{"stored with neither a comment nor a stop", "video", "", "", "", "demo Visual: video (delivery not recorded)\n"},
	} {
		t.Run(c.name, func(t *testing.T) {
			w := newWorld(t)
			w.output(triage(1, h1, "demo"))
			demo := lane(1, "demo", h1, review.VerdictApprove)
			demo.Visual, demo.VisualFallbackFrom, demo.VisualComment, demo.VisualStoppedBy = c.visual, c.from, c.comment, c.stopped
			demo.Covered = "- the list page, with two items\n- not shown: the empty list"
			w.output(demo)
			w.output(repair(1, h1, ""))
			run, err := review.ReadRun(w.ledger(), root)
			if err != nil {
				t.Fatal(err)
			}
			got := review.Comment(run, 1, nil)
			if !strings.Contains(got, c.want) {
				t.Errorf("the comment lacks %q:\n%s", c.want, got)
			}
			covered := "<details><summary>demo: what the check covered</summary>\n\n- the list page, with two items\n- not shown: the empty list\n\n</details>"
			if !strings.Contains(got, covered) {
				t.Errorf("the comment lacks what the check covered:\n%s", got)
			}
		})
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

// The head's comment is whole however long. The post cuts one past the size
// GitHub allows (Fit) at the last line that ends within it, keeps its mark
// first, and says under the mark that it is cut and which call prints it
// whole. One that fits is posted whole.
func TestAHeadsCommentPastTheSizeGitHubAllowsIsCut(t *testing.T) {
	long := strings.TrimSpace(strings.Repeat("the reason in words ", 90))
	comment := func(t *testing.T, n int) string {
		t.Helper()
		w := newWorld(t)
		var rs []review.Ruling
		for i := range n {
			id := fmt.Sprintf("tk-ask%d", i)
			w.ask(id, "")
			rs = append(rs, review.Ruling{Ask: id, Ruling: review.RulingMustFix, Reason: long, Commit: fix})
		}
		w.output(triage(1, h1))
		w.output(repair(1, h1, h2, rs...))
		run, err := review.ReadRun(w.ledger(), root)
		if err != nil {
			t.Fatal(err)
		}
		asks, err := review.AsksOn(w.ledger(), prBead)
		if err != nil {
			t.Fatal(err)
		}
		return review.Comment(run, 1, asks)
	}
	short := comment(t, 20)
	if got := review.Fit(short, root, 1); got != short || len(got) > 60000 || strings.Count(got, long) != 20 {
		t.Errorf("a comment that fits is posted as %d bytes with %d whole reasons, changed: %v", len(got),
			strings.Count(got, long), got != short)
	}
	whole := comment(t, 40)
	if strings.Count(whole, long) != 40 || strings.Contains(whole, "is cut") {
		t.Errorf("40 long answers render %d whole reasons, and say they are cut: %v", strings.Count(whole, long),
			strings.Contains(whole, "is cut"))
	}
	got := review.Fit(whole, root, 1)
	want := review.Mark(root, h1) + "\n**This comment is cut at the size GitHub allows.** `gctk review comment " + root +
		" --iteration 1` prints it whole.\n\n**Review at "
	if len(got) > 60000 || !strings.HasPrefix(got, want) || !strings.HasSuffix(got, "\n") || strings.Count(got, long) >= 40 {
		t.Errorf("40 long answers are posted as %d bytes with %d whole reasons, opening:\n%s", len(got),
			strings.Count(got, long), got[:min(len(got), 400)])
	}
}
