// Package prstatus is a PR anchor's status: vocabulary — the one dimension that
// names where a PR stands. It has two halves. The live states — working,
// merging, needs-review, needs-attention — say whose move it is on an open PR,
// and [Derive] computes them from the facts the city records about the anchor.
// The terminal states — merged, closed — name how a resolved PR ended. They are
// stamped by the helm board off the anchor's close and its merge_result, not
// returned by [Derive]: a resolved anchor freezes its live facts at their last
// pre-merge values (a merged PR keeps posture=approved and is never restamped),
// so the facts [Derive] reads carry no merged-or-closed signal.
//
// The `status:` PR label writer (assets/scripts/pr-status-label.sh) computes the
// live state through `gctk pr-status`, and the package is exported — not
// internal — so the helm board (services/helm) derives the same per-bead state
// from the same code rather than its own. One code path, so a bead's board
// liveness and its PR label cannot disagree. The label writer takes the label
// off a PR that merged or closed, where GitHub's own state takes over, so it
// never reaches for the terminal states; the board, which alone shows a
// resolved row, is their only consumer.
//
// The rule is Derive's; gathering the facts is the caller's. The label path
// reads them by shelling out to `gc bd`; a caller that already holds the bead,
// such as the board through the beads library, hands Derive the same raw
// metadata instead. Derive itself does no I/O.
//
// Derive reads only state the city records: the anchor's holds
// (merge_hold/rebase_hold), whether an open visit covers it, the pr-facts.sh
// posture, the merge cadence's machine verdict and its blocked cause, the
// draft-stage markers pr-open.sh records (opened_as_draft, draft_readied), and
// the anchor's in-flight set — any live bead carrying anchor_bead, the same
// membership test pr-facts.sh applies in its own arms. It does not read GitHub's
// merge state: GitHub reports BLOCKED for a required check still running as it
// does for a wedge, and the merge pass, which reads the branch's rules, is what
// tells the two apart. It does not consult GitHub's review posture directly —
// the working -> needs-review flip rests on that live work, which closes as it
// hands back, so a sticky changes_requested never traps the value in working
// after the set empties. Nor does it read GitHub's draft flag: a draft the city
// opened is known by its markers, and a draft someone else made reads like any
// other PR.
package prstatus

import "strings"

// State is a PR anchor's status value: the live, mutually-exclusive `status:`
// label group (working, merging, needs-review, needs-attention) plus the
// board-only terminal states (merged, closed) a resolved anchor shows.
type State string

const (
	// Working: an unapproved PR the city is changing. Live work is anchored to
	// it (a rework or fix child, a validation pass, a review, a finding), or a
	// draft the city opened still waits on the checks that flip it ready. No
	// human input is needed.
	Working State = "working"
	// Merging: an approved PR with no known blocker. The city has it and
	// believes its next state is merged: required checks may still be running,
	// a merge-in rework or other city work may be in flight, or it waits for the
	// merge pass.
	Merging State = "merging"
	// NeedsReview: an unapproved PR with nothing in flight and nothing holding
	// it. The only thing left before it lands is a human's review verdict on its
	// settled head.
	NeedsReview State = "needs-review"
	// NeedsAttention: a blocker stands that the city will not clear on its own:
	// a merge or rebase hold, an open visit on the anchor, a blocked verdict the
	// merge pass recorded at the current head, or a recorded value the
	// derivation has no word for.
	NeedsAttention State = "needs-attention"

	// Merged and Closed are terminal: the PR round-trip has ended, so nothing
	// stands between it and landing any more. Merged is a landed PR — the refinery closes its anchor carrying
	// merge_result=merged. Closed is a merge anchor that closed without merging, a
	// supersede or disposal. The board stamps these on a closed anchor; [Derive]
	// never returns them, because the live facts it reads carry no terminal signal.
	Merged State = "merged"
	Closed State = "closed"
)

// The blocked causes: the value pr.machine_cause carries beside a blocked
// machine verdict, declared as [machine_axis] causes in lifecycle/lifecycle.toml.
// gctk merge writes them, and the status: label and the helm board read them
// here rather than parsing the pr.machine_reason sentence.
const (
	CauseReviewThreads = "review-threads" // a required review thread is unresolved
	CauseCheckFailed   = "check-failed"   // a required check failed at the head
	CauseConflict      = "conflict"       // the branch conflicts and its merge-in is deferred
	CauseBehind        = "behind"         // the base moved ahead and nothing brings the branch current
	CauseBlocker       = "blocker"        // a live blocker no automated actor holds
	CauseRule          = "rule"           // a branch rule the merge pass cannot name
)

// Facts is the state the city records about the anchor, as stored. Each string
// field carries the raw metadata value; Derive splits the dated posture and
// machine verdict and applies the truthiness rule, so both consumers pass what
// the bead holds and read it identically.
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
	// PRPosture is metadata.pr_posture, stored value@oid@instant. The value is
	// read before the first '@', and the oid after it is the head the posture
	// was read at, the current head as far as the city knows.
	PRPosture string
	// PRMachine is metadata.pr.machine, stored value@oid@instant: what the merge
	// cadence can do with the anchor on its next pass (progressing, settled or
	// blocked). Only blocked moves the state, and only at the posture's head,
	// since a verdict at another head was reached about a different commit.
	PRMachine string
	// PRMachineCause is metadata.pr.machine_cause, one of the Cause values,
	// recorded beside a blocked verdict and read only while the verdict is
	// blocked.
	PRMachineCause string
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
// needs-attention > merging > working > needs-review. A blocker the city will
// not clear holds the PR whatever else stands. An approved PR with nothing
// blocking it is the city's to land, whatever work is in flight on the way.
// Live city work on an unapproved PR comes before the review verdict it leads
// to, and the verdict is what remains when neither stands.
func Derive(f Facts) State {
	posture, postureHead := splitDated(f.PRPosture)
	machine, machineHead := splitDated(f.PRMachine)

	// needs-attention: a blocker the city will not clear on its own.
	if isSet(f.MergeHold) || isSet(f.RebaseHold) || f.OpenVisit {
		return NeedsAttention
	}
	// A recorded value outside the vocabulary its writer declares is a state
	// the derivation cannot name.
	if !knownPosture(posture) || !knownMachine(machine) || (machine == "blocked" && !knownCause(f.PRMachineCause)) {
		return NeedsAttention
	}
	// The merge pass's blocked verdict, at the head the posture was read at.
	// The pass records most causes only with nothing in flight, so live work
	// that arrives afterwards is the city acting on the cause, and the next pass
	// replaces the verdict. The blocker cause is the exception: the pass records
	// it only once no automated actor holds any live blocker
	// (assets/scripts/blocker-holder.sh), and the blocker itself is often in
	// the in-flight set, such as a must-fix finding nothing answers.
	if machine == "blocked" && (postureHead == "" || machineHead == postureHead) &&
		(f.InFlightCount == 0 || f.PRMachineCause == CauseBlocker) {
		return NeedsAttention
	}

	// merging: approved, and nothing known blocks the merge.
	if posture == "approved" {
		return Merging
	}

	// working: the city is changing an unapproved PR.
	if f.InFlightCount > 0 || inDraftStage(f.OpenedAsDraft, f.DraftReadied) {
		return Working
	}

	// needs-review: only a human's verdict on the settled head is left.
	return NeedsReview
}

// knownPosture is the posture vocabulary pr-facts.sh records ([posture]
// postures in lifecycle/lifecycle.toml), plus no posture recorded yet.
func knownPosture(v string) bool {
	switch v {
	case "", "approved", "changes_requested", "commented", "review_required", "none":
		return true
	}
	return false
}

// knownMachine is the machine vocabulary ([machine_axis] machines), plus no
// verdict recorded yet.
func knownMachine(v string) bool {
	switch v {
	case "", "progressing", "settled", "blocked":
		return true
	}
	return false
}

// knownCause is the blocked cause vocabulary, plus a blocked verdict recorded
// without one.
func knownCause(v string) bool {
	switch v {
	case "", CauseReviewThreads, CauseCheckFailed, CauseConflict, CauseBehind, CauseBlocker, CauseRule:
		return true
	}
	return false
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

// splitDated splits a dated value, value@oid@instant, into its value and its
// oid. A bare value with no '@' reads whole with no oid.
func splitDated(s string) (value, oid string) {
	value = before(s, "@")
	if len(value) < len(s) {
		oid = before(s[len(value)+1:], "@")
	}
	return value, oid
}

// before returns the part of s before the first sep, or all of s when sep is
// absent — the split("@")[0] the dated posture and machine values need.
func before(s, sep string) string {
	if i := strings.Index(s, sep); i >= 0 {
		return s[:i]
	}
	return s
}
