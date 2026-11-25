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
// head and the target a run judged, whether the run passed there, and the run
// that recorded it, by its root.
type Result struct {
	Head   string `json:"head"`
	Target string `json:"target"`
	Passed bool   `json:"passed"`
	Run    string `json:"run"`
}

// The run's one write on the bead that owns the PR is its result for the last
// head it judged and its target, an entry that names the run, which the loop's
// check writes as it closes the loop, so no step of the run records it. The
// check records at the iteration that ends the loop: one that passed, or the
// loop's last attempt, which Gas City closes as exhausted when it does not
// pass. The result passes only when the iteration passed and no gate the run
// filed is open, so a loop that stopped on a question gets a result that does
// not pass while the question's gate stays open, and an exhausted loop gets one
// that does not pass and asks a person. A loop a step's hard failure ended runs
// no check and gets no result, as does a run cancelled before its loop ended
// and a run that judged no head.

// LoopExhaustedKey keys the human gate the loop's check files on the bead that
// owns the PR when the loop exhausts its attempts with no passed head.
const LoopExhaustedKey = "review-loop-exhausted"

// Gates files a human gate on a bead under a key, or finds the one open there.
type Gates interface {
	File(subject, key, message string) error
}

// Recorded is what Record did: the result it wrote on the bead, nil with
// NoResult saying why when the run has none, whether the loop exhausted, each
// gate of a question still open, each ask it closed, and the gate it filed
// when the loop exhausted.
type Recorded struct {
	Bead      string
	Result    *Result
	NoResult  string
	Exhausted bool
	Open      []string
	Closed    []ClosedAsk
	Gated     bool
}

// ClosedAsk is an ask Record closed: its ruling, and the work record its close
// carries.
type ClosedAsk struct {
	ID, Ruling, Outcome, Commit string
}

// Ends reports whether the iteration the verdict judged ends the run's loop:
// it passed, or it is the loop's last attempt by the run's bound. With no bound
// to read, only a pass ends it.
func (v *Verdict) Ends() bool {
	return v.Passed || (v.Run.MaxAttempts > 0 && v.Iteration >= v.Run.MaxAttempts)
}

// Record writes the result of the run the verdict judged, once its iteration
// ends the loop, into review_results on the bead that owns the PR, replacing
// the entry for the same head and target, and closes the asks the run answered
// at that head. When the loop exhausted it then files the review-loop-exhausted
// gate on the bead through filer, naming the head and the round's account. It
// holds the store's record lock, in the .beads directory dir, from its read of
// the bead to its last write on the bead, waiting up to wait for it, and files
// the gate once the lock is released. A verdict whose iteration does not end
// the loop is refused, and a read, the lock, a write or the gate that fails
// returns its error: a retry replaces the same entry, closes what is still
// open and finds the gate filed.
func Record(l *ledger.Ledger, dir string, wait time.Duration, v *Verdict, filer Gates) (*Recorded, error) {
	run := v.Run
	if !v.Ends() {
		return nil, fmt.Errorf("iteration %d of %s neither passed nor is its loop's last attempt, so the run has no result yet",
			v.Iteration, run.Root)
	}
	out := &Recorded{Bead: run.PRBead, Exhausted: !v.Passed}
	last := run.Last()
	if last == 0 {
		out.NoResult = "the run judged no head"
		return out, nil
	}
	head := run.Iterations[last].Triage.Head
	passed := v.Passed
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
	out.Result = &Result{Head: head, Target: run.Target, Passed: passed, Run: run.Root}
	answered := answeredAsks(run, last)
	url, err := out.write(l, dir, wait, run, head, answered)
	if err != nil {
		return out, err
	}
	if !out.Exhausted {
		return out, nil
	}
	if filer == nil {
		return out, errors.New("the loop exhausted and no gate filer was given, so no person is asked")
	}
	pr := run.PRBead + "'s PR"
	if url != "" {
		pr = url
	}
	message := fmt.Sprintf("Review run %s exhausted its attempts at %s without a passed head, so %s waits for you. "+
		"Clearing this gate has the landing order pour a fresh run.\n\n%s", run.Root, head, pr, v.Explain())
	if err := filer.File(run.PRBead, LoopExhaustedKey, message); err != nil {
		return out, fmt.Errorf("the result landed and the %s gate did not: %w", LoopExhaustedKey, err)
	}
	out.Gated = true
	return out, nil
}

// write lands the result and closes the answered asks under the record lock,
// and returns the PR's URL the bead's record names.
func (out *Recorded) write(l *ledger.Ledger, dir string, wait time.Duration, run *Run, head string, answered []ClosedAsk) (string, error) {
	release, err := record.Lock(dir, wait)
	if err != nil {
		return "", err
	}
	defer release()
	owner, err := one(l, run.PRBead)
	if err != nil {
		return "", err
	}
	rec, err := record.Read(owner)
	if err != nil {
		return "", err
	}
	results, _, err := resultsKey.Get(owner)
	if err != nil {
		return "", err
	}
	results = slices.DeleteFunc(results, func(r Result) bool { return r.Head == head && r.Target == run.Target })
	w := l.Write(owner.ID)
	resultsKey.Set(w, append(results, *out.Result))
	if err := l.Commit(w); err != nil {
		return "", err
	}

	asks, err := asksOf(l, owner)
	if err != nil {
		return "", err
	}
	// A fixed ask's commit is on the PR's branch, which the repair pushed it
	// onto from a worktree of the rig's checkout, so the checkout's origin ref
	// of the branch reaches it where the runtime's work-record gate asks.
	branch := view(record.Branch, owner)
	for _, a := range answered {
		i := slices.IndexFunc(asks, func(o Ask) bool { return o.ID == a.ID })
		if i < 0 || !asks[i].Open() {
			continue
		}
		w := l.Write(a.ID)
		w.Status("closed")
		w.WorkRecord(a.Outcome, a.Commit, branch)
		w.Note(fmt.Sprintf("Answered by review run %s at %s into %s: %s.", run.Root, head, run.Target, a.Ruling))
		if err := l.Commit(w); err != nil {
			return "", fmt.Errorf("the result landed and ask %s did not close: %w", a.ID, err)
		}
		out.Closed = append(out.Closed, a)
	}
	if rec.URL != "" {
		return rec.URL, nil
	}
	return rec.ExistingPR, nil
}

// gates is every human gate the run's rulings put a question to, each once.
func gates(run *Run) []string {
	var out []string
	for _, n := range slices.Sorted(maps.Keys(run.Iterations)) {
		for _, r := range run.Iterations[n].Rulings() {
			if r.Ruling == RulingQuestion && r.Gate != "" && !slices.Contains(out, r.Gate) {
				out = append(out, r.Gate)
			}
		}
	}
	return out
}

// answeredAsks is each ask the round of iteration last answered: ruled
// declined, deferred or answered there, by triage or by rule-and-repair. Its
// work record is shipped with the commit of the run's last must-fix ruling of
// it that names one, when an earlier round fixed it by a commit, and no-op
// otherwise, as for an ask fixed in the PR's summary alone, which put no work
// on the branch. An ask ruled must-fix there waits for a head that carries the
// fix to be judged, and a question waits for its answer.
func answeredAsks(run *Run, last int) []ClosedAsk {
	var out []ClosedAsk
	for _, r := range run.Iterations[last].Rulings() {
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

// String is the result as one line.
func (r Result) String() string {
	verdict := "did not pass"
	if r.Passed {
		verdict = "passed"
	}
	return fmt.Sprintf("%s at %s into %s", verdict, r.Head, strings.TrimSpace(r.Target))
}
