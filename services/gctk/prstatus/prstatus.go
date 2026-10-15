// Package prstatus is a PR anchor's status: vocabulary — the one dimension that
// names where a PR stands. It has two halves. The live tri-state — working,
// needs-review, needs-attention — names what stands between an open PR and
// landing, and [Derive] computes it from the facts the city records about the
// anchor. The terminal states — merged, closed — name how a resolved PR ended.
// They are stamped by the helm board off the anchor's close and its
// merge_result, not returned by [Derive]: a resolved anchor freezes its live
// facts at their last pre-merge values (a merged PR keeps posture=approved,
// merge_state=CLEAN, and is never restamped), so the facts [Derive] reads carry
// no merged-or-closed signal.
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
// Derive reads only state the city records: the anchor's holds
// (merge_hold/rebase_hold), whether an open visit covers it, the pr-facts.sh
// posture and merge state, the draft-stage markers pr-open.sh records
// (opened_as_draft, draft_readied), and the anchor's in-flight set — any live
// bead carrying anchor_bead, the same membership test pr-facts.sh applies in
// its own arms. It does not consult GitHub's review posture directly — the
// working -> needs-review flip rests on that live work, which closes as it
// hands back, so a sticky changes_requested never traps the value in working
// after the set empties. Nor does it read GitHub's draft flag: a draft the
// city opened is known by its markers, and a draft someone else made reads
// like any other PR.
package prstatus

import "strings"

// State is a PR anchor's status value: the live, mutually-exclusive `status:`
// label group (working, needs-review, needs-attention) plus the board-only
// terminal states (merged, closed) a resolved anchor shows.
type State string

const (
	// Working: only the city has work left before the PR lands — live work is
	// anchored to it (a rework or fix child, a validation pass, a review, a
	// finding), a draft the city opened still waits on the checks that flip it
	// ready, or an approved PR is merging. No human input is needed.
	Working State = "working"
	// NeedsReview: the only thing left before the PR lands is a human's review
	// verdict on its settled head.
	NeedsReview State = "needs-review"
	// NeedsAttention: something only a human can clear blocks the merge — a
	// merge or rebase hold, an open visit on the anchor, or an approved PR wedged
	// at merge state BLOCKED with no rework in flight. Any hold only a human can
	// release is one of these inputs, whatever work is in flight beside it.
	NeedsAttention State = "needs-attention"

	// Merged and Closed are terminal: the PR round-trip has ended, so nothing
	// stands between it and landing any more. Merged is a landed PR — the refinery closes its anchor carrying
	// merge_result=merged. Closed is a merge anchor that closed without merging, a
	// supersede or disposal. The board stamps these on a closed anchor; [Derive]
	// never returns them, because the live facts it reads carry no terminal signal.
	Merged State = "merged"
	Closed State = "closed"
)

// Facts is the state the city records about the anchor, as stored. Each string
// field carries the raw metadata value; Derive splits the dated posture and
// merge state and applies the truthiness rule, so both consumers pass what the
// bead holds and read it identically.
type Facts struct {
	// MergeHold is metadata.merge_hold: any truthy value is an operator freeze or
	// other merge hold.
	MergeHold string
	// RebaseHold is metadata.rebase_hold: any truthy value is a rebase hold.
	RebaseHold string
	// OpenVisit is whether an open visit covers the anchor: a task_kind=visit
	// bead, open or in_progress, whose subject is the anchor by the shared visit
	// identity (assets/scripts/visit-identity.sh). That subject is the bead the
	// visit's tracks edge names, or its gc.continuation_group stamp when it has
	// no tracks edge. Only a person closes a visit, and the merge pass refuses
	// the merge while one covers the anchor: its finalize gate
	// (assets/scripts/finalize-gate.sh) reads visits by the same identity. So it
	// reads as a hold, as merge_hold and rebase_hold do, whatever work is in
	// flight.
	OpenVisit bool
	// PRPosture is metadata.pr_posture, stored value@oid@instant; only the value
	// before the first '@' is read.
	PRPosture string
	// PRMergeState is metadata.pr_merge_state, stored value@oid; only the value
	// before the first '@' is read.
	PRMergeState string
	// OpenedAsDraft is metadata.opened_as_draft: the head oid pr-open.sh opened
	// or adopted the PR as a draft at, recorded only on a draft whose ready flip
	// the refinery owns.
	OpenedAsDraft string
	// DraftReadied is metadata.draft_readied: the head oid pr-open.sh read that
	// draft ready at, either the head it flipped it at or the head it found it
	// already ready at.
	DraftReadied string
	// InFlightCount is the size of the anchor's in-flight set: every live bead
	// carrying anchor_bead, any task_kind, over the live statuses pr-facts.sh
	// counts (a rework or fix child, a validation pass, a review, a finding).
	// Non-zero means the city is acting on the PR.
	InFlightCount int
}

// Derive returns the state the anchor projects. Precedence:
// needs-attention > working > needs-review. The order follows from what each
// value says stands between the PR and landing: a block only a human can clear
// holds the PR whatever work is in flight beside it, live city work comes before
// the review verdict it leads to, and the verdict is what remains when neither
// stands.
func Derive(f Facts) State {
	posture := before(f.PRPosture, "@")
	mstate := before(f.PRMergeState, "@")

	// needs-attention: something only a human can clear blocks the merge.
	if isSet(f.MergeHold) || isSet(f.RebaseHold) || f.OpenVisit {
		return NeedsAttention
	}
	if posture == "approved" && mstate == "BLOCKED" && f.InFlightCount == 0 {
		return NeedsAttention
	}

	// working: only the city has work left.
	if f.InFlightCount > 0 {
		return Working
	}
	if inDraftStage(f.OpenedAsDraft, f.DraftReadied) {
		return Working
	}
	if posture == "approved" {
		return Working
	}

	// needs-review: only a human's verdict on the settled head is left.
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

// inDraftStage is the open-as-draft stage: the city opened the PR as a draft and
// has not yet read it ready, so it still owes the checks that flip it and the
// flip itself. The test is presence, not truthiness, because both markers are
// oids: it is the prefilter pr-open.sh's draft-to-ready arm runs and the stage
// test gate-ensure.sh dispatches on.
func inDraftStage(openedAsDraft, draftReadied string) bool {
	return openedAsDraft != "" && draftReadied == ""
}

// before returns the part of s before the first sep, or all of s when sep is
// absent — the split("@")[0] the dated posture and merge-state values need.
func before(s, sep string) string {
	if i := strings.Index(s, sep); i >= 0 {
		return s[:i]
	}
	return s
}
