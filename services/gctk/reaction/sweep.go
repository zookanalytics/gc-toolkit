package reaction

import (
	"fmt"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// sweepRule is the ready read of the sweep and of the unmarked list:
// unassigned beads, and no epic.
var sweepRule = ledger.ServeRule{Unassigned: true, ExcludeTypes: []string{"epic"}}

// stringKey is a String key, or its reading face, as the candidate rule reads
// one.
type stringKey interface {
	Get(*ledger.Record) (string, bool, error)
}

// isCandidate reports whether a ready bead takes a fresh first reaction: its
// filer marked it for one (marked), no first reaction or sitting has concluded
// on it, which a headline would show, and its own row carries no refusal. A
// bead with no mark is never a candidate, whatever else it lacks, and the po's
// backlog refinement lists it instead (Unmarked). The sling reads its refusals
// again, since a bead can change while the sweep runs.
func isCandidate(r *ledger.Record) bool {
	return marked(r) && !concluded(r) && rowRefusal(r, "") == nil
}

// marked reports whether the bead carries a mark its filer wrote for a first
// reaction: hold:mayor, in any spelling Gas City reads as the hold, which
// files new work into the placement queue, or the finding.scope that
// patrol-finding.sh writes in the create that files a patrol finding, so a
// finding whose first sling failed gets its reaction on the next sweep.
func marked(r *ledger.Record) bool {
	return gascity.HasHold(r.Labels(), gascity.HoldMayor) || strings.TrimSpace(raw(findingScopeKey, r)) != ""
}

// The outcome each candidate of a sweep comes to.
const (
	Slung      = "slung"       // a first reaction slung on it
	Refused    = "refused"     // a refusal held at its sling
	Failed     = "failed"      // not slung, for an error
	Left       = "left"        // left for the next sweep, at the deadline
	WouldSling = "would-sling" // a dry run's candidate
)

// Swept is what a sweep did, or would do, with one candidate: the bead, its
// title and priority, and its outcome, with the refusal's code and why it was
// refused or not slung.
type Swept struct {
	ID       string `json:"id"`
	Title    string `json:"title"`
	Priority int    `json:"priority"`
	Outcome  string `json:"outcome"`
	Code     int    `json:"code,omitempty"`
	Why      string `json:"why,omitempty"`
}

// SweepTimeout is the deadline a sweep keeps when GC_PROACTIVE_SWEEP_TIMEOUT
// names none.
const SweepTimeout = "300s"

// SweepDeadline reads a sweep's deadline as an order's timeout is written: a
// whole number of seconds, alone or with an s, m or h suffix.
func SweepDeadline(text string) (time.Duration, error) {
	n, unit := text, time.Second
	if cut, ok := strings.CutSuffix(text, "h"); ok {
		n, unit = cut, time.Hour
	} else if cut, ok := strings.CutSuffix(text, "m"); ok {
		n, unit = cut, time.Minute
	} else if cut, ok := strings.CutSuffix(text, "s"); ok {
		n = cut
	}
	v, err := strconv.Atoi(n)
	if n == "" || strings.Trim(n, "0123456789") != "" || err != nil {
		return 0, fmt.Errorf("GC_PROACTIVE_SWEEP_TIMEOUT must be a duration in seconds, minutes or hours, such as 300s or 5m (got %q)", text)
	}
	return time.Duration(v) * unit, nil
}

// SweepError is a sweep that slung nothing because a read it needed failed.
type SweepError struct{ Msg string }

func (e *SweepError) Error() string { return e.Msg }

// Sweep slings a first reaction at each candidate in the rig's store, highest
// priority first, and passes each candidate to emit with what it came to. Its
// one ready read is unassigned beads that are not epics, by priority, and the
// candidate rule keeps the beads among them marked for a first reaction
// (isCandidate). It then drops every bead a live run works, by waits' run
// link, and a run map that does not read drops nothing, which it says. Each reaction goes to the rig's proactive
// pool whether or not the pool runs, and a sling gc sling refuses, such as to a
// pool the city does not configure, fails that candidate alone. A slung run
// waits for a pool slot at no cost, so the sweep has no cap. It has a deadline,
// since the order's timeout stops a pour in progress: it starts no sling once
// less of the deadline is left than its slowest sling took, each figure taken
// in whole seconds as its upper bound, and leaves the rest for the next sweep.
// With dryRun it slings nothing and passes each candidate as one it would
// sling, whose refusals its sling would read again. It returns the summary,
// which counts each skip by its cause. A *SweepError is a ready read that
// failed, with nothing slung, and any other error a sweep in no rig.
func (r *Reactions) Sweep(dryRun bool, deadline time.Duration, emit func(Swept)) (string, error) {
	start := r.now()
	if _, err := r.proactiveTarget(); err != nil {
		return "", err
	}
	ready, err := r.Ledger.ReadyByPriority(sweepRule)
	if err != nil {
		return "", &SweepError{Msg: fmt.Sprintf("the ready read failed (%v). A failed read is not an empty ready set, so the sweep fails and slings nothing; it reads again once the store answers", err)}
	}
	cands := slices.DeleteFunc(ready, func(rec *ledger.Record) bool { return !isCandidate(rec) })
	cands, dropped, err := r.dropInFlight(cands)
	switch {
	case err != nil:
		r.say("could not read the live runs (%v), so beads a live workflow drives are not filtered out of this sweep (the sling still refuses them)", err)
	case dropped > 0:
		r.say("%d candidate(s) already have a live workflow, so the sweep does not offer them (the sling would refuse them)", dropped)
	}

	if dryRun {
		for _, c := range cands {
			emit(Swept{ID: c.ID, Title: c.Title(), Priority: c.Priority(), Outcome: WouldSling})
		}
		return fmt.Sprintf("%d candidate(s) a sweep would sling; --dry-run slung none", len(cands)), nil
	}

	slung, failed, left := 0, 0, 0
	refused := map[int]int{}
	limit, slowest := int(deadline/time.Second), 0
	for _, c := range cands {
		line := Swept{ID: c.ID, Title: c.Title(), Priority: c.Priority()}
		if limit-upper(r.now().Sub(start)) < slowest {
			left++
			line.Outcome = Left
			emit(line)
			continue
		}
		t0 := r.now()
		refusal, err := r.Sling(c.ID)
		slowest = max(slowest, upper(r.now().Sub(t0)))
		switch {
		case err != nil:
			failed++
			line.Outcome, line.Why = Failed, err.Error()
		case refusal != nil:
			refused[refusal.Code]++
			line.Outcome, line.Code, line.Why = Refused, refusal.Code, refusal.Why
		default:
			slung++
			line.Outcome = Slung
		}
		emit(line)
	}
	var skips []string
	for _, s := range []struct {
		n    int
		what string
	}{
		{refused[Reacting], "already reacting or in a conversation"},
		{refused[Driven], "driven by a live workflow"},
		{refused[Decided], "already routed, armed, held, assigned or waiting on a person"},
		{refused[Excluded], "a standing record or a feedback pattern"},
		{failed, "not slung for an error"},
	} {
		if s.n > 0 {
			skips = append(skips, fmt.Sprintf("%d %s", s.n, s.what))
		}
	}
	summary := fmt.Sprintf("slung %d first reaction(s)", slung)
	if len(skips) > 0 {
		summary += " (" + strings.Join(skips, ", ") + ")"
	}
	if left > 0 {
		summary += fmt.Sprintf("; %d candidate(s) left for the next sweep, since less of the sweep's %ds (GC_PROACTIVE_SWEEP_TIMEOUT) was left than its slowest sling took", left, limit)
	}
	return summary, nil
}

// upper is d in whole seconds, rounded up past any part of a second, the upper
// bound the sweep's deadline takes each figure as.
func upper(d time.Duration) int { return int(d/time.Second) + 1 }

// dropInFlight is the beads no live run works, by the run link's map of the
// store's live runs, and how many it dropped. A pour moves a bead's route to
// its execution route, which is no dispatch path, so a rule over the bead's
// row cannot see a run. A map that does not read drops nothing, and its error
// says why.
func (r *Reactions) dropInFlight(beads []*ledger.Record) ([]*ledger.Record, int, error) {
	if len(beads) == 0 {
		return beads, 0, nil
	}
	runs, err := waits.LiveRuns(r.Ledger)
	if err != nil {
		return beads, 0, err
	}
	worked := map[string]bool{}
	for _, w := range runs {
		if w.Bead != "" {
			worked[w.Bead] = true
		}
	}
	kept := slices.DeleteFunc(slices.Clone(beads), func(c *ledger.Record) bool { return worked[c.ID] })
	return kept, len(beads) - len(kept), nil
}

// now is the reaction's clock.
func (r *Reactions) now() time.Time {
	if r.Now != nil {
		return r.Now()
	}
	return time.Now()
}
