// Package prstatus is a PR anchor's status: vocabulary — the one dimension that
// names where a PR stands. It has two halves. The live tri-state — working,
// needs-review, needs-attention — answers who must act on an open PR next, and
// [Derive] computes it from the anchor's refinery-recorded facts. The terminal
// states — merged, closed — name how a resolved PR ended. They are stamped by
// the helm board off the anchor's close and its merge_result, not returned by
// [Derive]: a resolved anchor freezes its live facts at their last pre-merge
// values (a merged PR keeps posture=approved, merge_state=CLEAN, and is never
// restamped), so the facts [Derive] reads carry no merged-or-closed signal.
//
// The `status:` PR label writer (assets/scripts/pr-status-label.sh) computes the
// live tri-state through `gctk pr-status`, and the package is exported — not
// internal — so the helm board (services/helm) derives the same per-bead state
// from the same code rather than its own. One code path, so a bead's board
// liveness and its PR label cannot disagree. The label path reconciles only open
// PRs, so it never reaches for the terminal states; the board, which alone shows
// a resolved row, is their only consumer.
//
// The rule is Derive's; gathering the facts is the caller's. The label path
// reads them by shelling out to `gc bd`; a caller that already holds the bead,
// such as the board through the beads library, hands Derive the same raw
// metadata instead. Derive itself does no I/O.
//
// Derive reads only refinery-computed state off the anchor: the holds
// (merge_hold/rebase_hold and the signoff-cap park), the pr-facts.sh posture
// and merge state, and the anchor's in-flight set — any live bead carrying
// anchor_bead, the same membership test pr-facts.sh applies in its own arms. It
// does not consult GitHub's review posture directly — the working -> needs-review
// flip rests on that live work, which closes as it hands back, so a sticky
// changes_requested never traps the value in working after the set empties.
package prstatus

import "strings"

// State is one value of the mutually-exclusive `status:` label group.
type State string

const (
	// Working: the city holds the ball — live work is anchored to the PR (a
	// rework or fix child, a validation pass, a review, a finding), or an
	// approved PR is merging. No human input is needed.
	Working State = "working"
	// NeedsReview: settled at the head; the only thing left is a human's review
	// verdict.
	NeedsReview State = "needs-review"
	// NeedsAttention: stopped without settling — a human must weigh in before the
	// city can settle it (a signoff-cap park, a merge or rebase hold, or an
	// approved PR wedged at merge state BLOCKED with no rework in flight).
	NeedsAttention State = "needs-attention"

	// Merged and Closed are terminal: the PR round-trip has ended, so nobody acts
	// on it next. Merged is a landed PR — the refinery closes its anchor carrying
	// merge_result=merged. Closed is a merge anchor that closed without merging, a
	// supersede or disposal. The board stamps these on a closed anchor; [Derive]
	// never returns them, because the live facts it reads carry no terminal signal.
	Merged State = "merged"
	Closed State = "closed"
)

// Facts is the anchor's refinery-computed state as stored. Each string field
// carries the raw metadata value; Derive splits the dated posture and merge
// state and applies the truthiness rule, so both consumers pass what the bead
// holds and read it identically.
type Facts struct {
	// MergeHold is metadata.merge_hold: any truthy value is an operator freeze or
	// other merge hold, except the signoff-cap park (MergeHold == "signoff_cap"
	// paired with a SignoffCap), which is its own case.
	MergeHold string
	// SignoffCap is metadata.signoff_cap: the round cap that, paired with
	// MergeHold == "signoff_cap", is the cap park.
	SignoffCap string
	// RebaseHold is metadata.rebase_hold: any truthy value is a rebase hold.
	RebaseHold string
	// PRPosture is metadata.pr_posture, stored value@oid@instant; only the value
	// before the first '@' is read.
	PRPosture string
	// PRMergeState is metadata.pr_merge_state, stored value@oid; only the value
	// before the first '@' is read.
	PRMergeState string
	// InFlightCount is the size of the anchor's in-flight set: every live bead
	// carrying anchor_bead, any task_kind, over the live statuses pr-facts.sh
	// counts (a rework or fix child, a validation pass, a review, a finding).
	// Non-zero means the city is acting on the PR.
	InFlightCount int
}

// Derive returns the state the anchor projects. Precedence:
// needs-attention > working > needs-review.
func Derive(f Facts) State {
	posture := before(f.PRPosture, "@")
	mstate := before(f.PRMergeState, "@")

	// needs-attention: the city stopped without settling; a human must unstick it.
	if isCapPark(f.MergeHold, f.SignoffCap) {
		return NeedsAttention
	}
	if isSet(f.MergeHold) || isSet(f.RebaseHold) {
		return NeedsAttention
	}
	if posture == "approved" && mstate == "BLOCKED" && f.InFlightCount == 0 {
		return NeedsAttention
	}

	// working: the city holds the ball; no human input needed.
	if f.InFlightCount > 0 {
		return Working
	}
	if posture == "approved" {
		return Working
	}

	// needs-review: settled at the head, a human review or re-review is next.
	return NeedsReview
}

// isSet is the truthiness rule pr-facts.sh, pr-open.sh and pr-status-label.sh
// share, applied to the value as `(v // "") | tostring` renders it: null and
// false already arrive empty, and the string spellings of an unset flag are
// treated as unset too, so a hold means the same thing everywhere.
func isSet(v string) bool {
	switch v {
	case "", "false", "False", "FALSE", "0", "null":
		return false
	}
	return true
}

// isCapPark is the signoff round cap's park: merge_hold names the cap and a cap
// value stands with it. That one pairing is distinct from an operator freeze
// (merge_hold=true), which isSet catches as a plain hold.
func isCapPark(hold, signoffCap string) bool {
	return hold == "signoff_cap" && signoffCap != ""
}

// before returns the part of s before the first sep, or all of s when sep is
// absent — the split("@")[0] the dated posture and merge-state values need.
func before(s, sep string) string {
	if i := strings.Index(s, sep); i >= 0 {
		return s[:i]
	}
	return s
}
