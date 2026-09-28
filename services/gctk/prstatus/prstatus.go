// Package prstatus derives the workflow-owned tri-state a PR anchor projects:
// working, needs-review, or needs-attention — the one dimension that answers
// who must act on the PR next. The `status:` PR label writer
// (assets/scripts/pr-status-label.sh) computes it through `gctk pr-status`, and
// the package is exported — not internal — so the helm board (services/helm)
// derives the same per-bead state from the same code rather than its own. One
// code path, so a bead's board liveness and its PR label cannot disagree.
//
// The rule is Derive's; gathering the facts is the caller's. The label path
// reads them by shelling out to `gc bd`; a caller that already holds the bead,
// such as the board through the beads library, hands Derive the same raw
// metadata instead. Derive itself does no I/O.
//
// Derive reads only refinery-computed state off the anchor: the holds
// (merge_hold/rebase_hold and the signoff-cap park), the pr-facts.sh posture
// and merge state, and the anchor's in-flight set — the live beads carrying
// anchor_bead, the same membership test pr-facts.sh applies in its own arms,
// split by whether each is progressing or blocked. A frontier whose live work
// is entirely blocked is not the city holding the ball: a human must unstick it,
// so it derives needs-attention, not working. Derive does not consult GitHub's
// review posture directly — the working -> needs-review flip rests on live work,
// which closes as it hands back, so a sticky changes_requested never traps the
// value in working after the set empties.
//
// Alongside the state, Derive returns the Reason naming the needs-attention
// cause, so a consumer can render why a person is needed without re-deriving it.
package prstatus

import "strings"

// State is one value of the mutually-exclusive `status:` label group.
type State string

const (
	// Working: the city holds the ball — live work is progressing on the PR (a
	// rework or fix child, a validation pass, a review, a finding), or an
	// approved PR is merging. No human input is needed.
	Working State = "working"
	// NeedsReview: settled at the head; the only thing left is a human's review
	// verdict.
	NeedsReview State = "needs-review"
	// NeedsAttention: stopped without settling — a human must weigh in before the
	// city can settle it (a signoff-cap park, a merge or rebase hold, an approved
	// PR wedged at merge state BLOCKED with no live work, or a frontier whose only
	// live work is blocked).
	NeedsAttention State = "needs-attention"
)

// Reason names the needs-attention cause. It is empty for working and
// needs-review, and for a needs-attention that outran every named cause. The
// value is coarse enough to render as a chip and specific enough to tell a visit
// awaiting engagement from a frontier that has simply stalled.
type Reason string

const (
	ReasonNone           Reason = ""
	ReasonCapPark        Reason = "cap-park"
	ReasonMergeHold      Reason = "merge-hold"
	ReasonRebaseHold     Reason = "rebase-hold"
	ReasonApprovedWedged Reason = "approved-wedged"
	// ReasonVisitEngage: the live frontier is blocked and an open human visit
	// holds the anchor — a conversation awaits engagement.
	ReasonVisitEngage Reason = "visit-engage"
	// ReasonStall: the live frontier is blocked with no human visit on it — work
	// that stopped, with nothing moving it.
	ReasonStall Reason = "stall"
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
	// InFlightActive is how much of the anchor's in-flight set is progressing:
	// the live beads carrying anchor_bead, any task_kind, whose status is not
	// blocked (a rework or fix child, a validation pass, a review, a finding).
	// Non-zero means the city is acting on the PR.
	InFlightActive int
	// InFlightBlocked is how much of that same set is blocked. A set that is all
	// blocked, with nothing progressing, is a frontier a human must unstick.
	InFlightBlocked int
	// HumanVisitAwaits reports that an open human visit is holding the anchor. It
	// only distinguishes the reason a blocked frontier carries (visit-engage vs
	// stall); it does not by itself change the state.
	HumanVisitAwaits bool
}

// Derive returns the state the anchor projects and the reason behind a
// needs-attention. Precedence: needs-attention > working > needs-review.
func Derive(f Facts) (State, Reason) {
	posture := before(f.PRPosture, "@")
	mstate := before(f.PRMergeState, "@")

	// needs-attention: the city stopped without settling; a human must unstick it.
	if isCapPark(f.MergeHold, f.SignoffCap) {
		return NeedsAttention, ReasonCapPark
	}
	if isSet(f.MergeHold) {
		return NeedsAttention, ReasonMergeHold
	}
	if isSet(f.RebaseHold) {
		return NeedsAttention, ReasonRebaseHold
	}
	// A live frontier with nothing progressing and something blocked is not
	// working — ordered above the working arm so a blocked-only set never reads
	// working, and above the approved wedge so the blocked frontier names its own
	// cause. An open human visit on it means a conversation awaits engagement;
	// without one the work has stalled.
	if f.InFlightActive == 0 && f.InFlightBlocked > 0 {
		if f.HumanVisitAwaits {
			return NeedsAttention, ReasonVisitEngage
		}
		return NeedsAttention, ReasonStall
	}
	// Reached only with the in-flight set empty (a blocked-only set returned
	// above), so this is an approved PR wedged at BLOCKED with no live work.
	if posture == "approved" && mstate == "BLOCKED" && f.InFlightActive == 0 {
		return NeedsAttention, ReasonApprovedWedged
	}

	// working: the city holds the ball; no human input needed.
	if f.InFlightActive > 0 {
		return Working, ReasonNone
	}
	if posture == "approved" {
		return Working, ReasonNone
	}

	// needs-review: settled at the head, a human review or re-review is next.
	return NeedsReview, ReasonNone
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
