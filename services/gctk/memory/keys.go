package memory

import "github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"

// The keys a settle reads on the bead a note waits on. The distiller writes
// them in shell, so each is declared read-only and stays in
// lifecycle/lifecycle.toml.
var (
	roleKey = ledger.ReadOnly("task_kind", ledger.String,
		"A memory note that waits on a bead whose task_kind is feedback-pattern waits on the pattern's "+
			"follow-ups.")
	proposalKey = ledger.ReadOnly("proposal_bead", ledger.String,
		"The prompt-update the distiller filed for a feedback pattern ([metadata.learning]), one of the "+
			"pattern's follow-ups whose landing ends a memory note's wait on the pattern.")
	engKey = ledger.ReadOnly("eng_bead", ledger.String,
		"The engineering bead a feedback pattern's structural remedy was filed as ([metadata.learning]), one "+
			"of the pattern's follow-ups whose landing ends a memory note's wait on the pattern.")
)

// pattern is the task_kind of a feedback pattern.
const pattern = "feedback-pattern"
