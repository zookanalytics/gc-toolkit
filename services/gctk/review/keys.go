package review

import "github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"

// The keys the review domain owns: the results its runs record on the bead
// that owns a PR, and the checks an ask sends back.
var (
	resultsKey = ledger.Declare("review_results", ledger.JSON[[]Result](),
		"The review loop's results on the bead that owns a PR, a JSON array of {head, target, passed}, one for "+
			"each head and target a run judged, which the loop's check writes through gctk review passed --record "+
			"under the store's record lock, replacing the entry for the same head and target. The pr evaluator "+
			"counts only a result for the PR's live head and target, and reads none while the key is absent.")
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
		"A review run's shadow var. Reading true, the run writes nothing outside itself, so the loop's check "+
			"records no result, closes no ask and files no gate.")
	maxAttemptsVar = ledger.ReadOnly("gc.var.max_attempts", ledger.String,
		"A review run's max_attempts var: the loop's bound, which Gas City compiles the loop's check from, so the "+
			"iteration that reaches it is the loop's last and its check records the run's result when it does not pass.")
)

// The keys a review run's step carries that say which step it is: the
// iteration it runs in and its place in the formula, and the branch var a run
// is poured with, all written by the runtime.
var (
	attemptKey = ledger.ReadOnly("gc.attempt", ledger.String,
		"The iteration a review run's step runs in, from 1, which Gas City writes on every step of a check loop's "+
			"iteration, a lane bonded there included. A step's output names the same iteration.")
	stepRefKey = ledger.ReadOnly("gc.step_ref", ledger.String,
		"A review run's step's place in its formula. Its last part names the step, triage, rule-and-repair or lane, "+
			"which says the output the step writes.")
	branchVar = ledger.ReadOnly("gc.var.branch", ledger.String,
		"A review run's branch var: the PR's branch, read when the bead that owns the PR names none.")
)
