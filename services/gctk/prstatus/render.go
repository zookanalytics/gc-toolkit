package prstatus

import "github.com/zookanalytics/gc-toolkit/services/gctk/pr"

// Render returns where a PR on Gas Town's pending record stands, in the status
// vocabulary, from the evaluator's answer for its anchor ([pr.Ready]) and the
// facts [Read] gathers about the anchor, whose walk names the human gates and
// the beads a person owes the next move on. The precedence is Derive's:
// needs-attention > merging > working > needs-review.
//
//   - needs-attention: something only a person clears holds the PR. It is a
//     gate or a bead a person owes, as [Held] names them, a hold set by hand, a
//     PR that is not open or not the one the record names, a required check
//     that failed, or a merge state GitHub reports that nothing else the
//     evaluator names explains, a conflict or a rule it does not read, on an
//     approved PR.
//   - merging: the PR is ready, or approved with only the city's work left,
//     such as a check still running, the review loop's result or a wait on
//     work on its branch.
//   - working: the PR waits on the city's work and on an approval.
//   - needs-review: only an approval is left, or a request for changes that
//     the account that made it has to lift.
func Render(a pr.Answer, f Facts) State {
	if a.Ready {
		return Merging
	}
	if len(Held(f)) > 0 {
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
	case !approval && !city && (mergeState == "DIRTY" || mergeState == "BLOCKED"):
		return NeedsAttention
	case !approval:
		return Merging
	case city:
		return Working
	}
	return NeedsReview
}
