package review

import "github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"

// The keys the review domain owns: the results its runs record on the bead
// that owns a PR, and the checks an ask sends back.
var (
	resultsKey = ledger.Declare("review_results", ledger.JSON[[]Result](),
		"The review loop's results on the bead that owns a PR, a JSON array of {head, target, passed}, one for "+
			"each head and target a run judged, which gctk review record writes under the store's record lock, "+
			"replacing the entry for the same head and target. The pr evaluator counts only a result for the PR's "+
			"live head and target, and reads none while the key is absent.")
	checksKey = ledger.Declare("review_checks", ledger.String,
		"On an ask, the checks it sends back, a comma list of names from the check index at the PR's validated "+
			"head, which gctk review ask writes as it files the ask. A review run picks each at the first head it "+
			"judges once it can take the ask. Absent, the ask sends back no check.")
)

// Results is review_results's reading face, for the pr evaluator, whose
// question is a result for the PR's live head and target.
var Results = resultsKey.View()

// The keys a review run's beads carry that the runtime writes, each declared
// read-only here, as no domain owns them (lifecycle/lifecycle.toml,
// [metadata.runtime_owned]). The PR's branch is the pr domain's record's, read
// through record.Branch and named on an ask through record.NameBranch.
var (
	rootBeadKey = ledger.ReadOnly("gc.root_bead_id", ledger.String,
		"A review run's outputs are on the beads that name its root.")
	kindKey = ledger.ReadOnly("gc.kind", ledger.String,
		"A review run's loop is the bead of its run that reads ralph, the control bead of its checked step.")
	outcomeKey = ledger.ReadOnly("gc.outcome", ledger.String,
		"The terminal disposition a step records. A review run's loop that closed reading pass passed its check.")
	dispositionKey = ledger.ReadOnly("gc.final_disposition", ledger.String,
		"How the runtime finally closed a control bead. A review run's loop that reads hard_fail was ended by a "+
			"step's hard failure, so the run records no result.")
	outputKey = ledger.ReadOnly("gc.output_json", ledger.String,
		"A step's structured output, one JSON object, which the step writes before it closes. A review run's "+
			"triage, lanes and rule-and-repair each write theirs in the shape the review domain declares.")
	routedKey = ledger.ReadOnly("gc.routed_to", ledger.String,
		"An ask carries none, so no pool claims it and the review run is the one that works it.")
	prBeadVar = ledger.ReadOnly("gc.var.pr_bead", ledger.String,
		"A review run's pr_bead var: the bead that owns the PR the run judges.")
	headVar = ledger.ReadOnly("gc.var.head", ledger.String,
		"A review run's head var: the head the refinery validated, the run's first head.")
	targetVar = ledger.ReadOnly("gc.var.target", ledger.String,
		"A review run's target var: the branch the PR merges into, the target its result is for.")
	shadowVar = ledger.ReadOnly("gc.var.shadow", ledger.String,
		"A review run's shadow var. Reading true, the run writes nothing outside itself, so gctk review record "+
			"writes no result and closes no ask.")
)
