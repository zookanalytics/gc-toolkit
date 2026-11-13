package record

import (
	"regexp"
	"strconv"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// The record's keys, with the meanings Gas Town's pr-merge-reconcile gives
// them. `gctk pr record` and `gctk pr reconcile` write them through the writes
// in record.go. The keys the old path also writes (merge_result, pr_url,
// pr_number, merged_target, merged_sha, existing_pr, blocked_reason and
// rejection_reason) keep those shell writers, whose definitions stay in
// lifecycle/lifecycle.toml's [metadata.merge_identity], until the merge
// member's retirement removes them.
var (
	mergeResultKey = ledger.Declare("merge_result", ledger.String,
		"Where the work a bead carries stands on its way to its target. On Gas Town's pending record it reads "+
			Pending+", "+HeadChanged+", "+Merged+", "+Incomplete+" or one of the exceptions, "+Invalid+", "+
			ClosedUnmerged+", "+MergedUnvalidatedHead+", "+EvidenceContradiction+", "+LegacyClosed+" and "+CloseRefused+
			", each of which keeps the bead blocked behind a human gate keyed by its value. Absent, the bead "+
			"has not landed and owns no open PR. The old path's values are lifecycle/lifecycle.toml's [states]. "+
			"A PR's composition reads a bead on its branch that carries one as the branch's anchor, and one "+
			"that reads merged as having landed its work on its merged_target.")
	prURLKey = ledger.Declare("pr_url", ledger.String,
		"The URL of the PR the record names, https://<host>/<owner>/<repo>/pull/<number>.")
	prNumberKey = ledger.Declare("pr_number", ledger.String,
		"The number of the PR the record names, in decimal.")
	prRepoKey = ledger.Declare("pr_repo", ledger.String,
		"The repository of the PR the record names, owner/name, which matches the rig's origin and is "+
			"compared without case.")
	prHeadKey = ledger.Declare("pr_head_sha", ledger.String,
		"The head the refinery validated, the one head the bead's PR may merge at. A requeue keeps it.")
	observedHeadKey = ledger.Declare("observed_pr_head_sha", ledger.String,
		"The head the landing order found on a PR open at a head the refinery has not validated. The next "+
			"publication clears it.")
	prStateKey = ledger.Declare("pr_state", ledger.String,
		"The PR's state as the landing order last read it: open, merged, or the state a read that could not "+
			"decide or an exception left, such as lookup_failed, merge_unreachable or closed_unmerged.")
	checkedAtKey = ledger.Declare("pr_last_checked_at", ledger.String,
		"When the record was last written or read, RFC 3339 UTC to the second. The landing order reads the "+
			"records it checked least recently first.")
	mergedTargetKey = ledger.Declare("merged_target", ledger.String,
		"The branch the bead's PR is to merge into, the base its PR must name, and once it lands the branch "+
			"it landed on. A PR's composition names it as the PR's target.")
	mergedSHAKey = ledger.Declare("merged_sha", ledger.String,
		"The merge commit the landing order found on the target when it closed the bead.")
	mergedAtKey = ledger.Declare("pr_merged_at", ledger.String,
		"When GitHub says the PR merged, recorded with the merge commit.")
	existingPRKey = ledger.Declare("existing_pr", ledger.String,
		"The PR the refinery reuses rather than open another, a PR's URL: armed with the marker before the "+
			"record's second write, and set by a requeue. A publication clears it.")
	blockedReasonKey = ledger.Declare("blocked_reason", ledger.String,
		"Why a bead on the record is blocked: the merge it awaits, or the exception that holds it.")
	rejectionReasonKey = ledger.Declare("rejection_reason", ledger.String,
		"Why the work was sent back to the refinery: a head it has not validated, or a record left half "+
			"written. A publication clears it.")
	reconcileErrorKey = ledger.Declare("pr_reconcile_error", ledger.String,
		"Why the landing order's last read could not decide, such as a lookup that failed or a merge commit "+
			"not yet on the fetched target. The next run reads the record again, and a read that decides clears it.")
	pendingKey = ledger.Declare("pr_reconcile_pending", ledger.String,
		"true while a reconciliation of the record is still owed, the marker the landing order selects the "+
			"records it reads by. The record's first write sets it, and the order clears it when the bead "+
			"closes on a verified merge, goes back to the refinery, meets an exception or has been released "+
			"from the refinery. A disposition's close clears it in the same write, through bead-rehome.sh, "+
			"the one shell writer that spells it, because only that write closes the bead under the record lock.")
)

// The reading faces of the record's keys whose value is another domain's whole
// question: whether a bead carries a merge_result or a rejection_reason, which
// puts it in flight, the PR a listing names on each bead, and the target a
// composition names.
var (
	Result    = mergeResultKey.View()
	PRURL     = prURLKey.View()
	PRNumber  = prNumberKey.View()
	Rejection = rejectionReasonKey.View()
	Target    = mergedTargetKey.View()
)

// OnTarget selects the beads whose merged_target is branch: the ones whose PR
// is to merge into it, and the ones whose work landed on it.
func OnTarget(branch string) ledger.Selection { return ledger.Matching(mergedTargetKey, branch) }

// prURL is a PR's URL: https, its host, its repository and its number.
var prURL = regexp.MustCompile(`^https://([^/]+)/([^/]+/[^/]+)/pull/([0-9]+)$`)

// ParseURL reads a PR's URL into its host, its repository, owner/name, and its
// number. ok is false for anything else.
func ParseURL(u string) (host, repo string, number int, ok bool) {
	m := prURL.FindStringSubmatch(u)
	if m == nil {
		return "", "", 0, false
	}
	n, err := strconv.Atoi(m[3])
	if err != nil || n < 1 {
		return "", "", 0, false
	}
	return m[1], m[2], n, true
}

// objectID is a full git object name, SHA-1 or SHA-256, as GitHub writes one.
var objectID = regexp.MustCompile(`^[0-9a-f]{40}([0-9a-f]{24})?$`)

// IsObjectID reports whether s is a full git object name.
func IsObjectID(s string) bool { return objectID.MatchString(s) }
