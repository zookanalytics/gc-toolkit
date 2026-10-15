package board

import "strings"

// The review shape a lane's green derives from: a review bead names its lane in
// check_name (absent reads as correctness), the commit it read in reviewed_oid,
// its verdict in signoff_verdict, and a retirement in gc.outcome=superseded.
const (
	mdTaskKind       = "task_kind"
	mdCheckName      = "check_name"
	mdReviewedOID    = "reviewed_oid"
	mdSignoffVerdict = "signoff_verdict"
	mdGCOutcome      = "gc.outcome"

	taskKindReview   = "review"
	defaultCheckName = "correctness"
	verdictApprove   = "approve"
	outcomeSupersede = "superseded"
	statusClosed     = "closed"
)

// laneGreen reports whether lane derives green from reviews, an anchor's review
// beads ([Anchor.Reviews]). A lane is green when a closed review for it carries
// a reviewed_oid and signoff_verdict=approve and is not superseded, and no
// review for it is open. This is lane-state.sh's local backing
// (assets/scripts/lane-state.sh), the derivation merge.sh, pr-open.sh and
// gate-ensure.sh read, mirrored because the board derives every anchor in one
// render and cannot run a script per lane. Its GitHub-approval fallback is not
// mirrored: the one reader here is the pre-open stall, and an anchor at
// pre_open_gate has no PR to approve, which is how pr-open.sh reads it too.
func laneGreen(reviews []Child, lane string) bool {
	backed := false
	for _, r := range reviews {
		md := r.Metadata
		if md[mdTaskKind] != taskKindReview {
			continue
		}
		name := md[mdCheckName]
		if name == "" {
			name = defaultCheckName
		}
		if name != lane {
			continue
		}
		if !strings.EqualFold(r.Status, statusClosed) {
			return false
		}
		if md[mdReviewedOID] != "" && md[mdSignoffVerdict] == verdictApprove && md[mdGCOutcome] != outcomeSupersede {
			backed = true
		}
	}
	return backed
}
