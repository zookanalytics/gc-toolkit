package review_test

import (
	"fmt"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
)

// rounds is a run with bound as its max_attempts whose round n raised
// counts[n-1] correctness findings and ruled each must-fix by a commit, and
// pushed when it ruled any.
func rounds(bound int, counts ...int) *review.Run {
	run := &review.Run{Root: root, PRBead: prBead, Head: h1, Target: target, MaxAttempts: bound,
		Iterations: map[int]*review.Iteration{}}
	for i, c := range counts {
		n := i + 1
		ln := review.Lane{Review: review.OutputLane, Iteration: n, Check: "correctness", Head: h1,
			Verdict: review.VerdictApprove}
		rp := &review.Repair{Review: review.OutputRepair, Iteration: n, Head: h1}
		for k := 1; k <= c; k++ {
			id := fmt.Sprintf("F%d", k)
			ln.Findings = append(ln.Findings, review.Finding{ID: id, Severity: "P1", Locus: "a.go:f", Message: "m"})
			rp.Rulings = append(rp.Rulings, review.Ruling{Check: "correctness", Finding: id, Ruling: review.RulingMustFix,
				Reason: "r", Commit: fix})
			ln.Verdict = review.VerdictRequestChanges
		}
		if c > 0 {
			rp.Pushed = fix
		}
		run.Iterations[n] = &review.Iteration{N: n, Triage: &review.Triage{Review: review.OutputTriage, Iteration: n, Head: h1},
			Lanes: []review.Lane{ln}, Repair: rp}
	}
	return run
}

// A round's account counts the lane findings it ruled must-fix and not a
// person's ask, and its line says how the count moved and what happens next:
// the next round, a fresh look at every third round, and nothing more at a
// round that pushed nothing.
func TestTheAccountOfARunsRounds(t *testing.T) {
	run := rounds(30, 5, 2)
	ask := review.Ruling{Ask: "tk-ask", Ruling: review.RulingMustFix, Reason: "r", Commit: fix}
	run.Iterations[2].Repair.Rulings = append(run.Iterations[2].Repair.Rulings, ask)
	a := review.Converge(run, 2)
	if got := a.Counts(); got != "5, 2" {
		t.Errorf("the counts read %q; want 5, 2, the ask counting for nothing", got)
	}
	if a.Forced != "" || a.Due {
		t.Errorf("round 2 of 5, 2 is forced %q, due %t; want neither", a.Forced, a.Due)
	}
	want := "Round 2: 2 must-fix findings (5, 2 by round), falling, so the review goes on to round 3."
	if got := a.Line(); got != want {
		t.Errorf("the line reads\n  %s\nwant\n  %s", got, want)
	}

	run = rounds(30, 5, 2, 1)
	if a := review.Converge(run, 3); !a.Due || a.Forced != "" ||
		a.Line() != "Round 3: 1 must-fix finding (5, 2, 1 by round), falling. A fresh look at the whole review decides whether it goes on." {
		t.Errorf("round 3 of 5, 2, 1 is due %t, forced %q, line %q; want a look the rule does not force", a.Due, a.Forced, a.Line())
	}
	if a := review.Converge(rounds(30, 5, 2, 1, 1), 4); a.Due || !strings.HasSuffix(a.Line(), "level, so the review goes on to round 5.") {
		t.Errorf("round 4 of 5, 2, 1, 1 is due %t with the line %q; want it to go on with no look", a.Due, a.Line())
	}
	if a := review.Converge(rounds(30, 5, 2, 0), 3); a.Due ||
		a.Line() != "Round 3: no must-fix finding (5, 2, 0 by round), falling, and the round pushed nothing." {
		t.Errorf("a round that pushed nothing is due %t with the line %q; want no look", a.Due, a.Line())
	}
	if a := review.Converge(rounds(30, 4, 14), 2); !strings.Contains(a.Line(), "rising") {
		t.Errorf("a count that rose reads %q; want rising", a.Line())
	}
}

// The rule forces a question when a round's must-fix findings are no fewer
// than two rounds before, while that round had some, and a fresh look is due
// there. A round two back with none, an ask's round, is no baseline.
func TestTheRuleForcesAQuestionWhenTheCountStopsFalling(t *testing.T) {
	for _, c := range []struct {
		counts []int
		forced bool
	}{
		{[]int{3, 3, 3}, true},
		{[]int{1, 2, 1}, true},
		{[]int{3, 2, 3}, true},
		{[]int{2, 3, 2}, true},
		{[]int{3, 3, 2}, false},
		{[]int{2, 2, 1}, false},
		{[]int{0, 3, 1}, false},
		{[]int{0, 1, 1}, false},
		{[]int{5, 2, 1, 1}, false},
		{[]int{5, 2, 1, 1, 1}, true},
		{[]int{5, 9, 5, 9}, true},
	} {
		n := len(c.counts)
		a := review.Converge(rounds(30, c.counts...), n)
		if (a.Forced != "") != c.forced {
			t.Errorf("%v: forced %q; want forced %t", c.counts, a.Forced, c.forced)
		}
		if c.forced && !a.Due {
			t.Errorf("%v: a forced question with no look due", c.counts)
		}
	}
	a := review.Converge(rounds(30, 3, 3, 3), 3)
	if want := "its must-fix findings have not fallen over two rounds: 3 at round 1, 3 at round 3"; a.Forced != want {
		t.Errorf("the reason reads %q; want %q", a.Forced, want)
	}
}

// One finding that comes back a second time after fixes forces a question at
// the round of its second return, whether the later finding restates the first
// or the one that came back before it, and a finding restated once does not.
func TestTheRuleForcesAQuestionWhenAFindingComesBackTwice(t *testing.T) {
	back := func(run *review.Run, n int, ref review.FindingRef) {
		run.Iterations[n].Repair.Rulings[0].Restates = &ref
	}
	run := rounds(30, 4, 3, 2)
	back(run, 2, review.FindingRef{Iteration: 1, Check: "correctness", Finding: "F1"})
	if a := review.Converge(run, 2); a.Forced != "" || len(a.Rounds[1].Returns) != 1 {
		t.Errorf("one return forces %q with returns %v; want nothing forced and one return", a.Forced, a.Rounds[1].Returns)
	}
	back(run, 3, review.FindingRef{Iteration: 2, Check: "Correctness", Finding: "F1"})
	a := review.Converge(run, 3)
	if want := "correctness finding F1 of round 1 has come back a second time after fixes"; a.Forced != want {
		t.Errorf("a second return through the first forces %q; want %q", a.Forced, want)
	}
	if !strings.Contains(a.Line(), "1 back after a fix") {
		t.Errorf("the line %q does not name the finding that came back", a.Line())
	}
	run = rounds(30, 4, 3, 2)
	back(run, 2, review.FindingRef{Iteration: 1, Check: "correctness", Finding: "F1"})
	back(run, 3, review.FindingRef{Iteration: 1, Check: "correctness", Finding: "F1"})
	if a := review.Converge(run, 3); a.Forced == "" {
		t.Error("two findings that restate the first force nothing; want a question")
	}
}

// The run's last round by its bound calls for a look, which stops the review.
func TestTheLastRoundByTheBoundCallsForALook(t *testing.T) {
	a := review.Converge(rounds(4, 5, 4, 3, 2), 4)
	if !a.Last || !a.Due || !strings.Contains(a.Line(), "last round by its bound") {
		t.Errorf("round 4 of a bound of 4 is last %t, due %t, line %q; want the look that stops it", a.Last, a.Due, a.Line())
	}
}

// The rule replayed on the review-loop-exhausted stops in the record, each by
// its lane must-fix findings per round, at the third round where each stopped
// (specs/tk-vdyedm5/design.md, "The record"). Every run's third round went on,
// so a fresh look is due at each; the rule forces the question at the ones
// whose count did not fall over two rounds.
func TestTheRuleOnTheRecordedStops(t *testing.T) {
	for _, c := range []struct {
		stop   string
		counts []int
		forced bool
	}{
		// The stops the team classified on 2026-11-25: six not converging...
		{"tk-6mpj3cl, #1563", []int{1, 2, 1}, true},
		{"tk-yt62pij, #1584", []int{1, 1, 1}, true},
		{"tk-nju0cqr, #1588", []int{2, 3, 3}, true},
		{"tk-wb6wf46, #1559 run 1", []int{3, 2, 3}, true},
		{"tk-r8aaxk5, #1559 run 2", []int{2, 3, 2}, true},
		{"tk-0gqb484, #1559 run 3", []int{3, 3, 2}, false},
		// ...and eight converging.
		{"tk-gwoys0n, #1595", []int{2, 1, 1}, false},
		{"tk-tj88b69, #1606", []int{2, 1, 1}, false},
		{"tk-kayrfpy, #1641 run 1", []int{5, 2, 1}, false},
		{"tk-w2qbipl, #1647", []int{2, 1, 1}, false},
		{"tk-s1rwuvu, #1660", []int{3, 2, 1}, false},
		{"tk-sgq8w7m, #1653", []int{2, 2, 1}, false},
		{"tk-ety7vxv, #1699", []int{7, 3, 1}, false},
		{"tk-vj35xmv, #1641 run 2", []int{4, 14, 3}, false},
		// The stops recorded after that census, to 2026-11-27.
		{"tk-pmzj6kb", []int{5, 3, 1}, false},
		{"tk-52xbn98", []int{0, 1, 1}, false},
		{"tk-967x60p", []int{3, 1, 1}, false},
		{"tk-t6o6tex, #1641 run 3", []int{5, 3, 1}, false},
		{"tk-zafqctw", []int{5, 2, 1}, false},
		{"tk-mt06mrz", []int{7, 2, 4}, false},
		{"tk-s4o15xk", []int{1, 1, 2}, true},
		{"tk-k0hmxim", []int{1, 2, 1}, true},
		{"tk-n31dr90", []int{0, 3, 1}, false},
		{"tk-cp8ajd0", []int{2, 1, 1}, false},
	} {
		a := review.Converge(rounds(30, c.counts...), 3)
		if !a.Due {
			t.Errorf("%s %v: no look due at round 3", c.stop, c.counts)
		}
		if (a.Forced != "") != c.forced {
			t.Errorf("%s %v: forced %q; want forced %t", c.stop, c.counts, a.Forced, c.forced)
		}
	}
}
