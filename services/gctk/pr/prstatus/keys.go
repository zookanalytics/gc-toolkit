package prstatus

import "github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"

// The keys prstatus reads that no domain owns: shell and the runtime write
// them, so each is declared read-only here and its definition stays in
// lifecycle/lifecycle.toml. The change that moves a writer into a domain takes
// its key's declaration over. merge_result is the record's, read through its
// reading face record.Result, and pr.AwaitsReview reads a merge anchor's
// validated head and the read the one-PR update saved on it, which package
// record and the pr domain own.

// The holds a person sets by hand (lifecycle/lifecycle.toml, [holds] and
// [metadata.holds]).
var (
	mergeHoldKey = ledger.ReadOnly("merge_hold", ledger.String,
		"prstatus reads a PR whose bead holds a merge hold as needs-attention, with no held: value of its own.")
	rebaseHoldKey = ledger.ReadOnly("rebase_hold", ledger.String,
		"prstatus reads a PR whose bead holds a rebase hold as needs-attention, with no held: value of its own.")
)

// anchorKey is the link from work on a PR's branch to the bead that owns the
// PR, which the review lanes and the intake write (lifecycle/lifecycle.toml,
// [metadata.gates]).
var anchorKey = ledger.ReadOnly("anchor_bead", ledger.String,
	"prstatus counts each live bead that names a PR's bead, at a live status and shown by bd's listing, "+
		"in the PR's in-flight set.")

// The runtime's stamps on a workflow root, which tell a review run among the
// beads a PR's bead waits on, and the head and the target it was poured at
// (lifecycle/lifecycle.toml, [metadata.runtime_owned]).
var (
	kindKey = ledger.ReadOnly("gc.kind", ledger.String,
		"prstatus reads a blocker of a PR's bead whose kind is workflow, of the review formula, as a review run "+
			"attached to it.")
	formulaNameKey = ledger.ReadOnly("gc.formula_name", ledger.String,
		"prstatus reads a workflow root of mol-pr-review that a PR's bead waits on as a review run attached to it.")
	runHeadVar = ledger.ReadOnly("gc.var.head", ledger.String,
		"prstatus names a closed review run at the head the pr evaluator judged when the run ended without a "+
			"result there.")
	runTargetVar = ledger.ReadOnly("gc.var.target", ledger.String,
		"prstatus reads a review run's result as one for the target it was poured for.")
)

// keyText is the value a String key holds on r, as the row holds it, and empty
// when r is nil or does not carry the key. A String key's stored text always
// decodes.
func keyText(k interface {
	Get(*ledger.Record) (string, bool, error)
}, r *ledger.Record) string {
	if r == nil {
		return ""
	}
	v, _, _ := k.Get(r)
	return v
}
