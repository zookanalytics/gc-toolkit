package distiller

import "github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"

// The runtime's stamps on a run's root, which Gas City writes at the pour
// (lifecycle/lifecycle.toml, [metadata.runtime_owned]), so each is declared
// read-only here.
var (
	kindKey = ledger.ReadOnly("gc.kind", ledger.String,
		"The runtime's kind of a bead. A root reading workflow is a run's root.")
	formulaNameKey = ledger.ReadOnly("gc.formula_name", ledger.String,
		"A live workflow root of mol-feedback-distiller in the home rig's store is a distiller run that is still "+
			"going, and gctk distiller start slings no other while one is.")
)

// workflowKind is the gc.kind of a run's root.
const workflowKind = "workflow"
