package listing

import "github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"

// The keys a listing decodes onto a Bead that no domain owns: shell and the
// runtime write them, so each is declared read-only here and its definition
// stays in lifecycle/lifecycle.toml. The change that moves a writer into a
// domain takes its key's declaration over. merge_result, pr_number and pr_url
// are the pr domain's record's, read through its reading faces.
var (
	anchorKey = ledger.ReadOnly("anchor_bead", ledger.String,
		"The merge anchor a review, rework, finding or validation child names (lifecycle/lifecycle.toml, "+
			"[metadata.gates]). A listing names it on each bead, and prstatus's in-flight set reads it.")
	routedToKey = ledger.ReadOnly("gc.routed_to", ledger.String,
		"The pool, agent or person a bead is routed to, written by lifecycle.sh's --route and by the script or "+
			"formula that owns the bead's dispatch (lifecycle/lifecycle.toml, ROUTE and [metadata.runtime_owned]).")
	workOutcomeKey = ledger.ReadOnly("gc.work_outcome", ledger.String,
		"A work bead's self-reported disposition, no-op or shipped, whose meaning is the runtime's "+
			"(lifecycle/lifecycle.toml, [metadata.runtime_owned]).", ledger.Alias("work_outcome"))
)

// An epic's contract and its latest ruling (lifecycle/lifecycle.toml,
// [metadata.epic_stewardship]). `gctk epic create` writes the contract into
// the create that files an epic, and the operator's ruling stamps the rest.
var (
	epicHandleKey = ledger.ReadOnly("epic_handle", ledger.String,
		"An epic's 3-5 word handle (docs/epics.md).")
	epicHypothesisKey = ledger.ReadOnly("epic_hypothesis", ledger.String,
		"An epic's one-sentence hypothesis (docs/epics.md). An epic under an epic that carries none is a Delivery.")
	epicBoundariesKey = ledger.ReadOnly("epic_boundaries", ledger.String,
		"What an epic's work is not (docs/epics.md).")
	epicClosureKey = ledger.ReadOnly("epic_closure_condition", ledger.String,
		"An epic's closure checks (docs/epics.md).")
	epicIndicatorsKey = ledger.ReadOnly("epic_indicators", ledger.String,
		"An epic's leading indicators (docs/epics.md).")
	epicRulingKey = ledger.ReadOnly("epic_ruling", ledger.String,
		"The latest ruling on an epic's hypothesis: continue, shift or close (docs/epics.md).")
	epicRulingReasonKey = ledger.ReadOnly("epic_ruling_reason", ledger.String,
		"Why the latest ruling on an epic was made, written with it.")
	epicRulingAtKey = ledger.ReadOnly("epic_ruling_at", ledger.String,
		"When the operator made the latest ruling on an epic.")
)
