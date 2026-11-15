package prstatus

import (
	"slices"

	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
)

// Render returns where a PR on Gas Town's pending record stands, in the status
// vocabulary, from the evaluator's answer for its anchor ([pr.Ready]) and the
// facts [Read] gathers about the anchor, whose walk names the human gates and
// the beads a person owes the next move on. The precedence is Derive's:
// needs-attention > merging > working > needs-review.
//
//   - needs-attention: something only a person clears holds the PR. It is one
//     of [RenderReasons], a hold set by hand, a PR that is not open or not the
//     one the record names, a required check that failed, or a merge state
//     GitHub reports that nothing else the evaluator names explains, such as a
//     conflict, a branch behind a base that requires it current or a rule it
//     does not read, on an approved PR, since nothing of the city's changes it.
//   - merging: the PR is ready, or approved with only the city's work left,
//     such as a check still running, the review loop's result, a wait on work
//     on its branch, or a review thread that work acts on, or with only the
//     merge state GitHub has yet to compute (UNKNOWN), which the next read
//     settles.
//   - working: the PR waits on the city's work and on an approval, or a
//     conversation whose sitting stays for work holds it, approved or not, as
//     Derive reads it ([Facts.Staying]).
//   - needs-review: only an approval is left, or a request for changes that
//     the account that made it has to lift.
func Render(a pr.Answer, f Facts) State {
	if a.Ready {
		return Merging
	}
	if len(RenderReasons(a, f)) > 0 {
		return NeedsAttention
	}
	var person, approval, city bool
	mergeState := ""
	for _, c := range a.Conditions {
		switch c.Kind {
		case pr.KindHold, pr.KindRecord, pr.KindOpen, pr.KindCheckFailed:
			person = true
		case pr.KindApproval, pr.KindChangesRequested:
			approval = true
		case pr.KindMergeState:
			mergeState = c.Value
		default:
			city = true
		}
	}
	switch {
	case person:
		return NeedsAttention
	case !approval && !city && mergeState != "" && mergeState != "UNKNOWN":
		return NeedsAttention
	case len(f.Staying) > 0:
		return Working
	case !approval:
		return Merging
	case city:
		return Working
	}
	return NeedsReview
}

// RenderReasons returns what holds a PR on Gas Town's pending record, in the
// order [Reasons] gives: each open human gate the walk names, the review
// threads the evaluator finds waiting on the city's answer, and each bead a
// person owes the next move on. The threads hold the PR only while nothing of
// the city's acts on them, the rule [unansweredFeedback] applies on the old
// record. The merge pass's blocked verdict and its count of threads are no
// reason here: that pass reads only the old record, so on a bead on this one
// they stand as it last wrote them.
func RenderReasons(a pr.Answer, f Facts) []Reason {
	var out []Reason
	for _, g := range f.Gates {
		out = append(out, Reason{Held: HeldGate, ID: g.ID, Title: g.Title})
	}
	if n := threadsHeld(a, f); n > 0 {
		out = append(out, Reason{Held: HeldReview, Title: threadsAwaiting(n)})
	}
	for _, b := range f.Owed {
		out = append(out, Reason{Held: HeldBlocked, ID: b.ID, Title: b.Title})
	}
	return out
}

// RenderHeld returns the held: value of each of [RenderReasons], once each, as
// [Held] does on the old record.
func RenderHeld(a pr.Answer, f Facts) []Hold { return holdsOf(RenderReasons(a, f)) }

// threadsHeld is how many review threads the answer names as waiting on the
// city's answer, or 0 while something of the city's acts on them: feedback the
// intake has yet to route, a bead that names the PR's bead as its anchor, or a
// wait of the bead's own that is neither a gate, a bead a person owes nor a
// conversation whose sitting stays for work, such as work on the PR's branch.
// A stay waits for its work to close, and acts on no thread.
func threadsHeld(a pr.Answer, f Facts) int {
	persons := slices.Concat(f.Gates, f.Owed, f.Staying)
	person := func(id string) bool {
		return slices.ContainsFunc(persons, func(b Blocker) bool { return b.ID == id })
	}
	n := 0
	for _, c := range a.Conditions {
		switch {
		case c.Kind == pr.KindThread:
			n++
		case c.Kind == pr.KindFeedback, c.Kind == pr.KindInFlight, c.Kind == pr.KindWait && !person(c.ID):
			return 0
		}
	}
	return n
}
