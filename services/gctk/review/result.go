package review

import (
	"errors"
	"fmt"
	"maps"
	"slices"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
)

// Result is one result of the review loop, an entry of review_results: the
// head and the target a run judged, and whether the run passed there.
type Result struct {
	Head   string `json:"head"`
	Target string `json:"target"`
	Passed bool   `json:"passed"`
}

// The run's one write on the bead that owns the PR is its result for the last
// head it judged and its target. The result passes only when the loop's check
// passed at that head and no gate the run filed is open. A loop that exhausted
// its attempts gets a result that does not pass, and so does a loop that
// stopped on a question while the question's gate stays open. A loop a step's
// hard failure ended did not exhaust, and gets no result, as does a loop that
// ended any other way, such as a cancel, and a run that judged no head.

// Recorded is what Record did: the result it wrote on the bead, nil with
// NoResult saying why when the run has none, whether the loop exhausted, and
// each ask it closed. Shadow says it wrote nothing, because the run is a
// shadow, and what it would have written.
type Recorded struct {
	Bead      string
	Result    *Result
	NoResult  string
	Exhausted bool
	Open      []string
	Closed    []ClosedAsk
	Shadow    bool
}

// ClosedAsk is an ask Record closed: its ruling, and the work record its close
// carries.
type ClosedAsk struct {
	ID, Ruling, Outcome, Commit string
}

// Unfinished is the error of a run whose loop has not closed, which has no
// result yet.
type Unfinished struct{ Run, Loop string }

func (e *Unfinished) Error() string {
	if e.Loop == "" {
		return e.Run + " has no loop, so it has no result to record"
	}
	return fmt.Sprintf("%s's loop %s has not closed, so it has no result yet", e.Run, e.Loop)
}

// Record writes the result of the run id names, its root or any bead poured
// under it, into review_results on the bead that owns the PR, replacing the
// entry for the same head and target, and closes the asks the run answered at
// that head. It holds the store's record lock, in the .beads directory dir,
// from its read of the bead to its last write, waiting up to wait for it. A
// read, the lock or a write that fails returns its error, and a retry
// replaces the same entry and closes what is still open.
func Record(l *ledger.Ledger, dir string, wait time.Duration, id string) (*Recorded, error) {
	run, err := ReadRun(l, id)
	if err != nil {
		return nil, err
	}
	out := &Recorded{Bead: run.PRBead, Shadow: run.Shadow}
	loop := run.Loop
	if loop == nil || loop.Status() != "closed" {
		u := &Unfinished{Run: run.Root}
		if loop != nil {
			u.Loop = loop.ID
		}
		return nil, u
	}
	outcome, disposition := str(outcomeKey, loop), str(dispositionKey, loop)
	switch {
	case disposition == "hard_fail":
		out.NoResult = "a step's hard failure ended the loop"
		return out, nil
	case outcome == "pass":
	case outcome == "fail" && disposition == "":
		out.Exhausted = true
	default:
		out.NoResult = fmt.Sprintf("the loop ended with outcome %q and disposition %q", outcome, disposition)
		return out, nil
	}
	last := run.Last()
	if last == 0 {
		out.NoResult = "the run judged no head"
		return out, nil
	}
	head := run.Iterations[last].Triage.Head
	passed := !out.Exhausted
	for _, gate := range gates(run) {
		g, err := one(l, gate)
		if err != nil {
			return nil, err
		}
		if g.Status() != "closed" {
			passed = false
			out.Open = append(out.Open, gate)
		}
	}
	out.Result = &Result{Head: head, Target: run.Target, Passed: passed}
	answered := answeredAsks(run, last)
	if run.Shadow {
		out.Closed = answered
		return out, nil
	}

	release, err := record.Lock(dir, wait)
	if err != nil {
		return nil, err
	}
	defer release()
	owner, err := one(l, run.PRBead)
	if err != nil {
		return nil, err
	}
	results, _, err := resultsKey.Get(owner)
	if err != nil {
		return nil, err
	}
	results = slices.DeleteFunc(results, func(r Result) bool { return r.Head == head && r.Target == run.Target })
	w := l.Write(owner.ID)
	resultsKey.Set(w, append(results, *out.Result))
	if err := l.Commit(w); err != nil {
		return nil, err
	}

	asks, err := asksOf(l, owner)
	if err != nil {
		return out, err
	}
	for _, a := range answered {
		i := slices.IndexFunc(asks, func(o Ask) bool { return o.ID == a.ID })
		if i < 0 || !asks[i].Open() {
			continue
		}
		w := l.Write(a.ID)
		w.Status("closed")
		w.WorkRecord(a.Outcome, a.Commit)
		w.Note(fmt.Sprintf("Answered by review run %s at %s into %s: %s.", run.Root, head, run.Target, a.Ruling))
		if err := l.Commit(w); err != nil {
			return out, fmt.Errorf("the result landed and ask %s did not close: %w", a.ID, err)
		}
		out.Closed = append(out.Closed, a)
	}
	return out, nil
}

// gates is every human gate the run's rulings put a question to, each once.
func gates(run *Run) []string {
	var out []string
	for _, n := range slices.Sorted(maps.Keys(run.Iterations)) {
		rp := run.Iterations[n].Repair
		if rp == nil {
			continue
		}
		for _, r := range rp.Rulings {
			if r.Ruling == RulingQuestion && r.Gate != "" && !slices.Contains(out, r.Gate) {
				out = append(out, r.Gate)
			}
		}
	}
	return out
}

// answeredAsks is each ask the round of iteration last answered: ruled
// declined, deferred or answered there. Its work record is shipped with the
// commit of the run's last must-fix ruling of it, when an earlier round fixed
// it, and no-op otherwise. An ask ruled must-fix there waits for a head that
// carries the fix to be judged, and a question waits for its answer.
func answeredAsks(run *Run, last int) []ClosedAsk {
	rp := run.Iterations[last].Repair
	if rp == nil {
		return nil
	}
	var out []ClosedAsk
	for _, r := range rp.Rulings {
		if r.Ask == "" || slices.ContainsFunc(out, func(c ClosedAsk) bool { return c.ID == r.Ask }) {
			continue
		}
		switch r.Ruling {
		case RulingDeclined, RulingDeferred, RulingAnswered:
		default:
			continue
		}
		c := ClosedAsk{ID: r.Ask, Ruling: r.Ruling, Outcome: "no-op"}
		for _, n := range slices.Sorted(maps.Keys(run.Iterations)) {
			earlier := run.Iterations[n].Repair
			if n > last || earlier == nil {
				continue
			}
			for _, e := range earlier.Rulings {
				if e.Ask == r.Ask && e.Ruling == RulingMustFix && e.Commit != "" {
					c.Outcome, c.Commit = "shipped", e.Commit
				}
			}
		}
		out = append(out, c)
	}
	return out
}

// IsUnfinished reports whether err is a run with no result yet.
func IsUnfinished(err error) bool {
	var u *Unfinished
	return errors.As(err, &u)
}

// String is the result as one line.
func (r Result) String() string {
	verdict := "did not pass"
	if r.Passed {
		verdict = "passed"
	}
	return fmt.Sprintf("%s at %s into %s", verdict, r.Head, strings.TrimSpace(r.Target))
}
