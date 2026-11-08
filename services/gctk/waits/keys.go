// Package waits holds what gctk's bead read asks to tell what holds a bead
// (docs/gctk-architecture.md, "The bead holds contract"). Here it declares the
// keys that read uses to tell work in flight, by steering.md's definition (In
// flight): a bead carrying branch, merge_result or rejection_reason. A bead a
// workflow poured for it is working is in flight too, and
// assets/scripts/run-lib.sh is the one definition of how a run links to the
// bead it works.
//
// None of these keys' writers has moved into gctk, so each is declared
// read-only here, and its definition stays in lifecycle/lifecycle.toml. The
// change that moves a writer takes its key's declaration over.
//
// The package sits outside internal/ so the helm board, a separate module, can
// import it.
package waits

import "github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"

var (
	branchKey = ledger.ReadOnly("branch", ledger.String,
		"The source branch a work bead's change is on, which the work formula's workspace-setup writes "+
			"(lifecycle/lifecycle.toml, [metadata.merge_identity]). A bead carrying it is in flight.")
	mergeResultKey = ledger.ReadOnly("merge_result", ledger.String,
		"The anchor's lifecycle state, which lifecycle.sh, through gctk lifecycle, writes on every transition "+
			"(lifecycle/lifecycle.toml, [machine] and [states]). A bead carrying it is in flight.")
	rejectionReasonKey = ledger.ReadOnly("rejection_reason", ledger.String,
		"Why the bead's last attempt bounced, which the refinery writes "+
			"(lifecycle/lifecycle.toml, [metadata.merge_identity]). A bead carrying it is in flight.")
)
