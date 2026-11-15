package review

import (
	"fmt"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// A run that ends without a result is poured again by the landing order, and
// the second at one head asks a person (specs/tk-1tfzr71.108/design.md,
// section 7). Ended says which a closed run was, from the store alone: a run
// recorded its result when its loop closed passed or exhausted at a head it
// judged and its record step closed passed. A cancel, a loop a step's hard
// failure ended, a run that judged no head and a record step that did not
// finish each leave the run with no result.

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
	if st := run.RecordStep; st == nil || st.Status() != "closed" || str(outcomeKey, st) != "pass" {
		out.How = fmt.Sprintf("its record step did not finish, so no result was written at %s (%s)", head, closed)
		return out, nil
	}
	out.Result = true
	out.How = fmt.Sprintf("it recorded its result at %s (%s)", head, closed)
	return out, nil
}
