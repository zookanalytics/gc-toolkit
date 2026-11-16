package review

import (
	"fmt"
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// A run that ends without a result is poured again by the landing order, and
// the second at one head asks a person (specs/tk-1tfzr71.108/design.md,
// section 7). Ended says which a closed run was, from the store alone. The
// loop's check records the run's result before it closes the loop, at a pass
// or at the loop's last attempt, as an entry of review_results that names the
// run. So a run recorded its result when its loop closed passed, or exhausted
// at a head it judged, and the bead that owns the PR holds the run's own entry
// for that head and its target. The entry is the evidence, and the loop's
// outcome is not: Gas City re-runs a check whose write did not land without
// spending an attempt only up to a bound (maxCheckInfraRetries in
// internal/dispatch/ralph.go), then grades the next one an ordinary failure,
// which closes the loop exhausted exactly as a check that recorded and failed
// does. A cancel, a loop a step's hard failure ended, which runs no check, and a
// run that judged no head each leave the run with no result. A later run's
// entry for the same head and target replaces an earlier run's, so the earlier
// run then reads as one with no result. The landing order's count is not moved
// by that: it reads the last two runs, and the later one reads as recorded.

// Ending is how a closed review run ended: its root, whether it recorded its
// result, and how it ended, in one clause.
type Ending struct {
	Root   string
	Result bool
	How    string
}

// Ended reads how the run whose root is root ended. A read that fails returns
// its error, and a root that is no review run's returns a *NotARun.
func Ended(l *ledger.Ledger, root string) (Ending, error) {
	r, err := one(l, root)
	if err != nil {
		return Ending{}, err
	}
	out := Ending{Root: r.ID}
	outcome := str(outcomeKey, r)
	closed := fmt.Sprintf("closed with gc.outcome %q", outcome)
	if strings.EqualFold(outcome, "canceled") {
		out.How = "it was cancelled before it recorded a result (" + closed + ")"
		return out, nil
	}
	run, err := ReadRun(l, r.ID)
	if err != nil {
		return Ending{}, err
	}
	loop := run.Loop
	switch {
	case loop == nil:
		out.How = "its loop never started (" + closed + ")"
		return out, nil
	case loop.Status() != "closed":
		out.How = fmt.Sprintf("its loop %s never closed (%s)", loop.ID, closed)
		return out, nil
	}
	loopOutcome, disposition := str(outcomeKey, loop), str(dispositionKey, loop)
	switch {
	case disposition == "hard_fail":
		out.How = fmt.Sprintf("a step's hard failure ended its loop %s (%s)", loop.ID, closed)
		return out, nil
	case loopOutcome == "pass", loopOutcome == "fail" && disposition == "":
	default:
		out.How = fmt.Sprintf("its loop %s ended with outcome %q and disposition %q (%s)", loop.ID, loopOutcome, disposition, closed)
		return out, nil
	}
	last := run.Last()
	if last == 0 {
		out.How = "it judged no head (" + closed + ")"
		return out, nil
	}
	head := run.Iterations[last].Triage.Head
	if loopOutcome != "pass" && run.MaxAttempts == 0 {
		out.How = fmt.Sprintf("its loop exhausted at %s while its max_attempts var named no bound, so its check "+
			"could not know its last attempt and recorded nothing (%s)", head, closed)
		return out, nil
	}
	owner, err := one(l, run.PRBead)
	if err != nil {
		return Ending{}, err
	}
	results, _, err := resultsKey.Get(owner)
	if err != nil {
		return Ending{}, err
	}
	if !slices.ContainsFunc(results, func(e Result) bool {
		return e.Head == head && e.Target == run.Target && e.Run == run.Root
	}) {
		out.How = fmt.Sprintf("its loop closed at %s with gc.outcome %q, and %s holds no result of its own for %s "+
			"into %s, so its check's record never landed (%s)", head, loopOutcome, run.PRBead, head, run.Target, closed)
		return out, nil
	}
	out.Result = true
	out.How = fmt.Sprintf("its loop's check recorded its result at %s (%s)", head, closed)
	return out, nil
}
