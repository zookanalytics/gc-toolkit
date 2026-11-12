package waits

import "github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"

// The keys the bead read reads that no domain owns: the runtime writes the run
// link's, and shell writes the rest, so each is declared read-only here and its
// definition stays in lifecycle/lifecycle.toml. The change that moves a shell
// writer into a domain takes its key's declaration over. merge_result and
// rejection_reason are the pr domain's record's, read through its reading faces.

// The branch a work bead's change is on, one of the keys that show a bead in
// flight (steering.md, In flight).
var branchKey = ledger.ReadOnly("branch", ledger.String,
	"The source branch a work bead's change is on, which the work formula's workspace-setup writes "+
		"(lifecycle/lifecycle.toml, [metadata.merge_identity]). A bead carrying it is in flight.")

// The run link Gas City keeps, which assets/scripts/run-lib.sh defines and
// run.go copies under its fixture test. The runtime writes each at the pour
// (lifecycle/lifecycle.toml, [metadata.runtime_owned]).
var (
	inputConvoyKey = ledger.ReadOnly("gc.input_convoy_id", ledger.String,
		"The input convoy a graph.v2 workflow root was poured over. The convoy tracks the bead the run works, "+
			"and the bead a live run works is in flight once the run has passed load-context. A root without it "+
			"works the bead its gc.var.issue names.")
	issueVarKey = ledger.ReadOnly("gc.var.issue", ledger.String,
		"The bead a classic molecule's issue variable names, which a root that names no input convoy works. "+
			"A root whose input convoy tracks another bead works none.")
	kindKey = ledger.ReadOnly("gc.kind", ledger.String,
		"The runtime's kind of a bead. A root reading workflow is a run's root.")
	formulaContractKey = ledger.ReadOnly("gc.formula_contract", ledger.String,
		"The formula contract a root was poured under. A root reading graph.v2 is a run's root.")
	rootBeadKey = ledger.ReadOnly("gc.root_bead_id", ledger.String,
		"The workflow root a step was poured under.")
	stepRefKey = ledger.ReadOnly("gc.step_ref", ledger.String,
		"The formula step a step bead carries out, as <formula>.<step>. A live run with an open step whose "+
			"ref ends in .load-context has not passed load-context.")
)

// The arm on a bead armed to start by itself, which deferred-dispatch.sh writes
// and clears as one family (lifecycle/lifecycle.toml,
// [metadata.deferred_dispatch]). The bead read carries each as the store holds
// it.
var (
	armTargetKey = ledger.ReadOnly("gc.dispatch_when_ready", ledger.String,
		"The pool or agent an armed bead is slung to once nothing holds it. Its presence is the arm.")
	armArgsKey = ledger.ReadOnly("gc.dispatch_when_ready_args", ledger.String,
		"The arm's extra sling arguments, as a JSON array.")
	armReasonKey = ledger.ReadOnly("gc.dispatch_when_ready_reason", ledger.String,
		"Why the bead was armed, as free text.")
	armedByKey = ledger.ReadOnly("gc.dispatch_when_ready_armed_by", ledger.String,
		"Who armed the bead.")
	armedAtKey = ledger.ReadOnly("gc.dispatch_when_ready_armed_at", ledger.String,
		"When the bead was armed, in RFC 3339 UTC.")
	armSlungKey = ledger.ReadOnly("gc.dispatch_when_ready_slung", ledger.String,
		"The arm's sling marker: slinging@<time> while an attempt is in flight, slung@<time> once it is proven.")
	armFailCountKey = ledger.ReadOnly("gc.dispatch_when_ready_fail_count", ledger.String,
		"The sling attempts made on the arm, as an integer string.")
	noticeKey = ledger.ReadOnly("gc.notify_when_ready", ledger.String,
		"The named agent a notice is owed to once nothing holds the bead assigned to it. Its presence is the arm.")
)
