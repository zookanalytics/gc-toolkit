package pr

import "github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"

// The keys a composition reads besides the PR summary, which this domain owns
// (summary.go). No domain owns any of them: shell writes each, so each is
// declared read-only here and its definition stays in
// lifecycle/lifecycle.toml. The change that moves a shell writer into a domain
// takes its key's declaration over. The keys the evaluator reads too, branch,
// merged_target and merge_result, are declared once, with its keys.

// The bead that owns the PR: where it lands and which checks gate it.
var (
	targetKey = ledger.ReadOnly("target", ledger.String,
		"The branch a bead's work lands on, which the polecat records at submit and a caller can set first "+
			"(lifecycle/lifecycle.toml, [metadata.merge_identity]). A composition names it as the PR's target "+
			"when merged_target is absent.")
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
