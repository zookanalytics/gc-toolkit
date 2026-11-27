package pr

import "github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"

// The keys the evaluator reads beside Gas Town's pending record and the PR's
// branch, which the record package owns, the review loop's results, which the
// review domain owns and the evaluator reads through review.Results, and the
// saved read and the provenance instant, which this domain owns (read.go). No
// domain owns any of these yet, so each is declared read-only here: shell
// writes the holds and the anchor link, and their definitions stay in
// lifecycle/lifecycle.toml.

// reading is a key's read, through its own declaration or through the reading
// face the key's owner exports.
type reading interface {
	Get(*ledger.Record) (string, bool, error)
}

// The holds a person sets by hand (lifecycle/lifecycle.toml, [holds] and
// [metadata.holds]).
var (
	mergeHoldKey = ledger.ReadOnly("merge_hold", ledger.String,
		"A hold on the bead's merge, set by hand. Any value but an unset spelling holds the PR.")
	rebaseHoldKey = ledger.ReadOnly("rebase_hold", ledger.String,
		"A hold on bringing the bead's branch current, set by hand. Any value but an unset spelling "+
			"holds the PR.")
)

// The link from work on a PR's branch to the bead that owns the PR, which the
// review lanes and the intake write until they file that work with a blocks
// edge (lifecycle/lifecycle.toml, [metadata.gates]).
var anchorKey = ledger.ReadOnly("anchor_bead", ledger.String,
	"The pr evaluator holds the PR of the bead an open bead names, until that work is filed with a blocks edge.")
