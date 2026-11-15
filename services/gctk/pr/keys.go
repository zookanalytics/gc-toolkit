package pr

import "github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"

// The keys a composition reads besides the PR summary, which this domain owns
// (summary.go). No domain owns any of them: shell writes each, so each is
// declared read-only here and its definition stays in
// lifecycle/lifecycle.toml. The change that moves a shell writer into a domain
// takes its key's declaration over. The branch, which the evaluator reads too,
// is declared once, with its keys, and merged_target and merge_result are the
// record's, read through what package record exports: the selection OnTarget
// and the reading face Result.

// The bead that owns the PR: which checks gate it.
var (
	checkSetKey = ledger.ReadOnly("check_set", ledger.String,
		"The review checks a bead's change is gated by, as a comma list (lifecycle/lifecycle.toml, "+
			"[metadata.gates]). A composition names it when no pre-open gate resolves from it.")
)

// The keys that say whether a bead's work is on a branch, which the branch-beads
// section reads.
var (
	foldTargetKey = ledger.ReadOnly("fold_target", ledger.String,
		"The branch a bead's work was folded onto by a polecat (lifecycle/lifecycle.toml, "+
			"[metadata.merge_identity]). A bead carrying it has its work on that branch.")
	routedToKey = ledger.ReadOnly("gc.routed_to", ledger.String,
		"The pool, agent or person a bead is routed to (lifecycle/lifecycle.toml, ROUTE and "+
			"[metadata.runtime_owned]). A bead on a branch that a pool still holds has not pushed its work.")
	workOutcomeKey = ledger.ReadOnly("gc.work_outcome", ledger.String,
		"A work bead's self-reported disposition (lifecycle/lifecycle.toml, [metadata.runtime_owned]). A bead "+
			"reading no-op put no work on its branch.",
		ledger.Alias("work_outcome"))
)

// The withdrawal of a PR's approvals, which this domain owns: gctk pr withdraw
// files it, and the landing order carries it out.
var withdrawHeadKey = ledger.Declare("withdraw_head", ledger.String,
	"The head a withdrawal of a PR's approvals names, on the bead `gctk pr withdraw` files, which blocks the bead "+
		"that owns the PR. The landing order dismisses each approval that stands on a commit that does not "+
		"contain this head, and closes the withdrawal once none stands. Written once, when the withdrawal is "+
		"filed, and never cleared.")

// The runtime's stamps on a workflow root, which tell the landing order that a
// review run is attached to the bead that owns a PR: a live root of the review
// formula that a blocks edge of the bead names.
var (
	kindKey = ledger.ReadOnly("gc.kind", ledger.String,
		"The runtime's kind of a bead. A root reading workflow is a run's root.")
	formulaNameKey = ledger.ReadOnly("gc.formula_name", ledger.String,
		"The formula a workflow root was poured from, which Gas City stamps at the pour (lifecycle/lifecycle.toml, "+
			"[metadata.runtime_owned]). A live root of mol-pr-review that a blocks edge of a PR's bead names is a "+
			"review run attached to the bead, and the landing order marks no PR ready while one is.")
)
