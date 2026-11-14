package pr

import "github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"

// The keys the evaluator reads beside Gas Town's pending record, which the
// record package owns. No domain owns any of these yet, so each is declared
// read-only here: shell writes the branch, the holds, the feedback receipts and
// the anchor link, and their definitions stay in lifecycle/lifecycle.toml.

// reading is a key's read, through its own declaration or through the reading
// face the key's owner exports.
type reading interface {
	Get(*ledger.Record) (string, bool, error)
}

// The branch the work is on, which the work formula's workspace-setup writes
// (lifecycle/lifecycle.toml, [metadata.merge_identity]).
var branchKey = ledger.ReadOnly("branch", ledger.String,
	"The pr evaluator and the landing order hold a PR whose head branch is not this one. A composition reads "+
		"it for the PR's source branch, and finds the beads whose work the branch carries by it.")

// The holds a person sets by hand (lifecycle/lifecycle.toml, [holds] and
// [metadata.holds]).
var (
	mergeHoldKey = ledger.ReadOnly("merge_hold", ledger.String,
		"A hold on the bead's merge, set by hand. Any value but an unset spelling holds the PR.")
	rebaseHoldKey = ledger.ReadOnly("rebase_hold", ledger.String,
		"A hold on bringing the bead's branch current, set by hand. Any value but an unset spelling "+
			"holds the PR.")
)

// The receipts of the feedback the intake has handled, which pr-facts.sh
// writes (lifecycle/lifecycle.toml, [posture] and [metadata.pr_posture]). Each
// watermark is the highest id it routed in its own id space, and each answered
// mark how far the review threads have answered past its watermark.
var (
	reviewWatermarkKey = ledger.ReadOnly("pr_review_watermark", ledger.String,
		"The highest review id the intake has routed. A value that is not a whole number reads as 0.")
	commentWatermarkKey = ledger.ReadOnly("pr_comment_watermark", ledger.String,
		"The highest inline comment id the intake has routed. A value that is not a whole number reads as 0.")
	issueCommentWatermarkKey = ledger.ReadOnly("pr_issue_comment_watermark", ledger.String,
		"The highest conversation comment id the intake has routed. A value that is not a whole number "+
			"reads as 0.")
	reviewAnsweredKey = ledger.ReadOnly("pr_review_answered", ledger.String,
		"The review id through which the review threads have answered the reviews past the review "+
			"watermark. A value that is not a whole number reads as 0.")
	commentAnsweredKey = ledger.ReadOnly("pr_comment_answered", ledger.String,
		"The inline comment id through which the review threads have answered the comments past the "+
			"comment watermark. A value that is not a whole number reads as 0.")
	provenanceKey = ledger.ReadOnly("pr_provenance_since", ledger.String,
		"The instant from which a post under the city's login is feedback unless it carries the city's "+
			"mark. A value that is not an instant in GitHub's form makes every such post the city's own.")
)

// The link from work on a PR's branch to the bead that owns the PR, which the
// review lanes and the intake write until they file that work with a blocks
// edge (lifecycle/lifecycle.toml, [metadata.gates]).
var anchorKey = ledger.ReadOnly("anchor_bead", ledger.String,
	"The pr evaluator holds the PR of the bead an open bead names, until that work is filed with a blocks edge.")

// The review loop's results, which the review lanes write once their loop
// records a result for each head and target it judges. Until then nothing
// writes it, and a PR on the pending record reads no review result.
var reviewResultsKey = ledger.ReadOnly("review_results", ledger.JSON[[]ReviewResult](),
	"The review loop's results on the bead that owns a PR, a JSON array of {head, target, passed}, "+
		"one for each head and target the loop judged. The evaluator counts only a result for the PR's "+
		"live head and target.")
