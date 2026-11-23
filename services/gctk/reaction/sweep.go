package reaction

import (
	"fmt"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/takeaway"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// sweepRule is the sweep's one ready read: unassigned beads, and no epic.
var sweepRule = ledger.ServeRule{Unassigned: true, ExcludeTypes: []string{"epic"}}

// sweepTypes are the issue types a first reaction may take, an allowlist, so a
// new type takes reactions only once it is added here. It leaves out the
// convoy, epic, step and molecule types, which are machinery or work in flight,
// a decision, which is a person's choice already, and a spec, which is an
// output and not an input. A graph.v2 pour does not retype its steps, so a
// workflow root and most of its steps are tasks, which the candidate rule drops
// by their keys.
var sweepTypes = []string{"task", "bug", "feature", "spike"}

// topologyKinds are the gc.kind values of a topology root.
var topologyKinds = []string{"workflow", "scope", "spec"}

// reviewKind is the task kind of a review lane on the old review path, a
// dispatched sign-off and so work in flight. The sweep passes over such a lane
// while such beads exist, and the old path's retirement removes the clause.
const reviewKind = "review"

// stringKey is a String key, or its reading face, as the candidate rule reads
// one.
type stringKey interface {
	Get(*ledger.Record) (string, bool, error)
}

// isCandidate reports whether a ready bead is raw input a fresh first reaction
// may take, top-level and not already in motion. Each clause drops one kind of
// bead that is no input: one with a dispatch path or a dispatch hold, whose
// next move is decided; one with no description; one whose type the allowlist
// leaves out; a topology root, and a step, a reaction's own root and step among
// them, which advance only through their own run; a standing record and a
// feedback pattern; a review lane; one that carries a headline, which every
// exit of a first reaction and a sitting's ruling write, so it has been
// triaged; one that holds a key whose declaration puts its work in motion
// (ledger.InMotion), such as an anchor's branch or a withdrawal's head, since
// an anchor is a task or a bug with no task_kind, which its keys alone set
// apart from raw input; and a member of a parent, whose parent-child edge is
// its own. The sling's refusals are read again at
// its sling, since a bead can change while the sweep runs.
func isCandidate(r *ledger.Record) (bool, error) {
	if len(dispatchPaths(r)) > 0 || gascity.HasDispatchHold(r.Labels()) {
		return false, nil
	}
	if r.Description() == "" || !slices.Contains(sweepTypes, r.IssueType()) || slices.Contains(topologyKinds, raw(kindKey, r)) {
		return false, nil
	}
	for _, k := range []stringKey{stepRefKey, stepIDKey, rootBeadKey, takeaway.Text, takeaway.By} {
		if raw(k, r) != "" {
			return false, nil
		}
	}
	if kind := raw(taskKindKey, r); slices.Contains(standingKinds, kind) || kind == feedbackPattern || kind == reviewKind {
		return false, nil
	}
	if len(ledger.InMotionKeys(r)) > 0 {
		return false, nil
	}
	parents, err := r.Parents()
	if err != nil {
		return false, &ledger.ReadError{ID: r.ID, Reason: "its edges did not decode: " + err.Error()}
	}
	return len(parents) == 0, nil
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
// candidate rule keeps the raw input among them (isCandidate). It then drops
// every bead a live run works, by waits' run link, and a run map that does not
// read drops nothing, which it says. Each reaction goes to the rig's proactive
// pool whether or not the pool runs, and a sling gc sling refuses, such as to a
// pool the city does not configure, fails that candidate alone. A slung run
// waits for a pool slot at no cost, so the sweep has no cap. It has a deadline,
// since the order's timeout stops a pour in progress: it starts no sling once
// less of the deadline is left than its slowest sling took, each figure taken
// in whole seconds as its upper bound, and leaves the rest for the next sweep.
// With dryRun it slings nothing and passes each candidate as one it would
// sling, whose refusals its sling would read again. It returns the summary,
// which counts each skip by its cause. A *SweepError is a ready read or a
// candidate rule that failed, with nothing slung, and any other error a sweep
// in no rig.
func (r *Reactions) Sweep(dryRun bool, deadline time.Duration, emit func(Swept)) (string, error) {
	start := r.now()
	if _, err := r.proactiveTarget(); err != nil {
		return "", err
	}
	ready, err := r.Ledger.ReadyByPriority(sweepRule)
	if err != nil {
		return "", &SweepError{Msg: fmt.Sprintf("the ready read failed (%v). A failed read is not an empty ready set, so the sweep fails and slings nothing; it reads again once the store answers", err)}
	}
	var cands []*ledger.Record
	for _, rec := range ready {
		ok, err := isCandidate(rec)
		if err != nil {
			return "", &SweepError{Msg: fmt.Sprintf("the candidates could not be filtered (%v), so the sweep fails and slings nothing", err)}
		}
		if ok {
			cands = append(cands, rec)
		}
	}
	cands = r.dropInFlight(cands)

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

// dropInFlight is the candidates no live run works, by the run link's map of
// the store's live runs. A pour moves a bead's route to its execution route,
// which is no dispatch path, so the candidate rule cannot see a run, and the
// sling would refuse the bead. A map that does not read drops nothing, which it
// says, and the sling still refuses those beads.
func (r *Reactions) dropInFlight(cands []*ledger.Record) []*ledger.Record {
	if len(cands) == 0 {
		return cands
	}
	runs, err := waits.LiveRuns(r.Ledger)
	if err != nil {
		r.say("could not read the live runs (%v), so beads a live workflow drives are not filtered out of this sweep (the sling still refuses them)", err)
		return cands
	}
	worked := map[string]bool{}
	for _, w := range runs {
		if w.Bead != "" {
			worked[w.Bead] = true
		}
	}
	kept := slices.DeleteFunc(slices.Clone(cands), func(c *ledger.Record) bool { return worked[c.ID] })
	if n := len(cands) - len(kept); n > 0 {
		r.say("%d candidate(s) already have a live workflow, so the sweep does not offer them (the sling would refuse them)", n)
	}
	return kept
}

// now is the reaction's clock.
func (r *Reactions) now() time.Time {
	if r.Now != nil {
		return r.Now()
	}
	return time.Now()
}
