package reaction

import (
	"errors"
	"fmt"
	"regexp"
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/arm/record"
	"github.com/zookanalytics/gc-toolkit/services/gctk/conversation"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// Formula is the formula a first reaction is a run of.
const Formula = "mol-first-reaction"

// proactivePool is the pool, in the caller's rig, a first reaction is slung
// through (agents/proactive/agent.toml).
const proactivePool = "gc-toolkit.proactive"

// The codes of the refusals, which three callers branch on: operator-intake.sh
// names the cause of each in the conversation it files instead, the reaction's
// check text in the proactive prompt names them, and the sweep counts its skips
// by them.
const (
	// Reacting is a subject a first reaction already runs on, or one an open
	// conversation tracks.
	Reacting = 3
	// Driven is a subject a live run of another formula works.
	Driven = 4
	// Decided is a subject whose next move is decided already.
	Decided = 5
	// Excluded is a subject whose kind takes no first reaction.
	Excluded = 6
)

// Refusal is why a bead takes no first reaction: its code and the reason.
type Refusal struct {
	Code int
	Why  string
}

// The keys the refusals and the sweep's candidate rule read and no domain owns
// yet, each declared read-only, its definition in lifecycle/lifecycle.toml.
var (
	routedToKey = ledger.ReadOnly("gc.routed_to", ledger.String,
		"A first reaction takes no bead routed anywhere, which has a dispatch path.")
	kindKey = ledger.ReadOnly("gc.kind", ledger.String,
		"A first reaction takes no bead whose kind is workflow, scope or spec, a topology root.")
	rootBeadKey = ledger.ReadOnly("gc.root_bead_id", ledger.String,
		"A first reaction takes no bead that names a root, which is a step.")
	stepRefKey = ledger.ReadOnly("gc.step_ref", ledger.String,
		"A first reaction takes no bead that names the step it carries out.")
	stepIDKey = ledger.ReadOnly("gc.step_id", ledger.String,
		"The id of the formula step a step bead carries out, which Gas City writes at the pour. A first reaction "+
			"takes no step.")
	taskKindKey = ledger.ReadOnly("task_kind", ledger.String,
		"A standing kind and a feedback pattern take no first reaction, and the sweep passes over a review lane.")
	workDirKey = ledger.ReadOnly("work_dir", ledger.String,
		"The worktree a bead's work is built in, which work-setup.sh writes. The sweep passes over a bead that "+
			"carries one, as work in flight.")
	checkNameKey = ledger.ReadOnly("check_name", ledger.String,
		"The check a review lane of the old review path runs. The sweep passes over a bead that carries one, as "+
			"work in flight.")
)

// standingKinds are the task kinds of a standing record, open by design and
// never closed, on which a first reaction has no disposition to make. They copy
// the kinds assets/scripts/standing-kinds.sh defines for the scripts, which
// TestTheStandingKindsAreTheOnesTheScriptsDefine holds them to, and they leave
// with those kinds.
var standingKinds = []string{"triage-subject"}

// feedbackPattern is the task kind of a feedback pattern, which the feedback
// distiller dispatches.
const feedbackPattern = "feedback-pattern"

// raw is k's stored text on r, untrimmed, and empty when r holds none, as
// ledger.String reads a key. A String key's stored text always decodes.
func raw(k stringKey, r *ledger.Record) string {
	v, _, _ := k.Get(r)
	return v
}

// Check is the first act of the reaction whose run is run: whether bead takes
// it. It applies the refusals a sling applies and writes nothing, and passes
// over the asking run, so that run is no second reaction, and over a gate filed
// under the reaction's key whose message names the run, which is the run's own,
// so a reaction re-offered after it filed its gate goes on to finish its exit.
// It returns nil when bead takes the reaction. An error is a read that did not
// answer, which decides nothing.
func (r *Reactions) Check(bead, run string) (*Refusal, error) {
	if err := CheckRun(run); err != nil {
		return nil, err
	}
	return r.refusal(bead, run)
}

// CheckRun refuses, as a *UsageError, a check that names no asking run or one
// that is no bead id.
func CheckRun(run string) error {
	if run == "" {
		return usage("the check names the asking reaction's run, --run <root>, so its own run is not taken for a second reaction")
	}
	if !runID.MatchString(run) {
		return usage("--run needs the root of the reaction's run, one bead id of [A-Za-z0-9._-] (got %q)", run)
	}
	return nil
}

// Sling slings a first reaction on bead through the rig's proactive pool, as
// `gc sling --rig <rig> <rig>/gc-toolkit.proactive <bead> --on
// mol-first-reaction`, unless a refusal holds. gc sling refuses a second live
// run of the formula on a bead, and its refusal is the Reacting refusal. It
// returns nil once the sling has landed. An error is a read that did not
// answer, an unset rig or a sling that failed, and nothing is slung.
func (r *Reactions) Sling(bead string) (*Refusal, error) {
	target, err := r.proactiveTarget()
	if err != nil {
		return nil, err
	}
	refused, err := r.refusal(bead, "")
	if refused != nil || err != nil {
		return refused, err
	}
	res := r.Runtime.Sling(gascity.Sling{Rig: r.Rig, Target: target, Bead: bead, Formula: Formula})
	switch {
	case res.Code == 3 && len(res.Live) > 0:
		return &Refusal{Code: Reacting, Why: "gc sling found a first reaction already running on it (" + strings.Join(res.Live, ", ") + ")"}, nil
	case res.Code == 3:
		return &Refusal{Code: Reacting, Why: "gc sling refused a second live " + Formula + " run on it"}, nil
	case res.Err != nil || res.Code != 0:
		return nil, fmt.Errorf("gc sling refused or failed on %s (%s)", bead, res.Failure())
	}
	r.say("slung a first reaction on %s (%s to %s)", bead, Formula, target)
	return nil, nil
}

// ErrNoRig is a sling or a sweep in no rig, whose proactive pool cannot be
// named.
var ErrNoRig = errors.New("cannot rig-qualify the proactive pool: set GC_RIG. The pool is rig-scoped (agents/proactive/agent.toml serves <rig>/" + proactivePool + "), and a bare route matches nobody")

// proactiveTarget is the rig's proactive pool, rig-qualified.
func (r *Reactions) proactiveTarget() (string, error) {
	if r.Rig == "" {
		return "", ErrNoRig
	}
	return r.Rig + "/" + proactivePool, nil
}

// refusal is the first refusal that holds on bead, in their order: the kind,
// then the row's status, assignee, dispatch path and dispatch hold, then an open
// conversation, a live reaction, a live run of another formula and an open
// human gate. run is the asking reaction's run under the check, passed over,
// and empty for a sling. It reads bead's row and the beads that track it once
// each, for every question it asks of them. A read that does not answer decides
// nothing, so it returns an error and no refusal.
func (r *Reactions) refusal(bead, run string) (*Refusal, error) {
	rows, err := r.Ledger.Find(ledger.ByID(bead).WithClosed())
	if err != nil {
		return nil, fmt.Errorf("could not read %s's own row (%v)", bead, err)
	}
	i := slices.IndexFunc(rows, func(row *ledger.Record) bool { return row.ID == bead })
	if i < 0 {
		return nil, fmt.Errorf("could not read %s's own row: its store does not hold it", bead)
	}
	if refused := rowRefusal(rows[i]); refused != nil {
		return refused, nil
	}

	up, err := r.Ledger.Dependents(bead, "tracks")
	if err != nil {
		return nil, fmt.Errorf("could not read whether an open conversation tracks %s (%v)", bead, err)
	}
	convs, err := r.conversations(bead, up)
	if err != nil {
		return nil, fmt.Errorf("could not read whether an open conversation tracks %s (%v)", bead, err)
	}
	if len(convs) > 0 {
		return &Refusal{Code: Reacting, Why: "an open conversation tracks it (" + strings.Join(convs, ", ") + "), which puts it to the operator already"}, nil
	}

	runs, err := waits.LiveRunsOf(r.Ledger, bead, up)
	if err != nil {
		return nil, fmt.Errorf("could not read the runs that work %s (%v), and a reaction that raced one could dispose of work in flight", bead, err)
	}
	var reacting, driven []string
	for _, w := range runs {
		switch {
		case w.Formula == Formula && w.Root != run:
			reacting = append(reacting, w.Root)
		case w.Formula != Formula:
			formula := w.Formula
			if formula == "" {
				formula = "unknown formula"
			}
			driven = append(driven, w.Root+" ("+formula+")")
		}
	}
	if len(reacting) > 0 {
		return &Refusal{Code: Reacting, Why: "a first reaction already runs on it (" + strings.Join(reacting, ", ") + ")"}, nil
	}
	if len(driven) > 0 {
		return &Refusal{Code: Driven, Why: "a live workflow already works it (" + strings.Join(driven, ", ") + "), and a reaction would race work in flight"}, nil
	}

	gates, err := r.personsGates(bead, run, rows)
	if err != nil {
		return nil, err
	}
	if len(gates) > 0 {
		return &Refusal{Code: Decided, Why: "it waits on a person's answer (" + strings.Join(gates, ", ") + "), which decides what happens to it"}, nil
	}
	return nil, nil
}

// rowRefusal is the refusal bead's own row carries, nil when it carries none:
// its kind first, since a standing record and a feedback pattern take no first
// reaction in any state, then its status, its assignee, its dispatch path and
// its dispatch hold. A dispatch path is a route a pool queue serves or an arm
// (assets/scripts/dispatch-path.sh), either one not blank, and each is named
// on its own.
func rowRefusal(row *ledger.Record) *Refusal {
	kind := raw(taskKindKey, row)
	switch {
	case slices.Contains(standingKinds, kind):
		return &Refusal{Code: Excluded, Why: fmt.Sprintf("it is a standing record (%s=%s), open by design, so a first reaction has no disposition to make on it", taskKindKey.Name(), kind)}
	case kind == feedbackPattern:
		return &Refusal{Code: Excluded, Why: "it is a feedback pattern, which the feedback distiller dispatches"}
	}
	if st := row.Status(); st != "" && st != "open" {
		return &Refusal{Code: Decided, Why: "its status is " + st + ", and a first reaction takes only an open bead"}
	}
	if as := row.Assignee(); strings.TrimSpace(as) != "" {
		return &Refusal{Code: Decided, Why: "it is assigned to " + as + ", whose next move it is"}
	}
	if paths := dispatchPaths(row); len(paths) > 0 {
		return &Refusal{Code: Decided, Why: "it already has a dispatch path (" + strings.Join(paths, ", ") + "), so whoever routed or armed it already decided its dispatch"}
	}
	var held []string
	for _, l := range row.Labels() {
		if gascity.IsDispatchHold(l) {
			held = append(held, l)
		}
	}
	if len(held) > 0 {
		return &Refusal{Code: Decided, Why: "it is held (" + strings.Join(held, ", ") + "): hold:mayor keeps it for the operator's placement sitting, and hold:external for an actor outside this store"}
	}
	return nil
}

// dispatchPaths names each dispatch path the bead carries, none when it carries
// neither: its route, and its arm.
func dispatchPaths(row *ledger.Record) []string {
	var out []string
	if v := raw(routedToKey, row); strings.TrimSpace(v) != "" {
		out = append(out, routedToKey.Name()+"="+v)
	}
	if a := record.Of(row); a != nil && strings.TrimSpace(a.Target) != "" {
		out = append(out, "an arm to "+a.Target)
	}
	return out
}

// conversations is the open conversations about bead, by the conversation
// domain's shape. The tasks among up, the beads that track it, are the
// candidates, open and assigned as a conversation is. That proves only that
// each one tracks the bead, not that the bead is all it tracks, so the
// candidates' own rows are read with their edges, and the shape decides. A
// candidate whose row does not read fails the read.
func (r *Reactions) conversations(bead string, up []*ledger.Record) ([]string, error) {
	var cands []string
	for _, d := range up {
		if t := d.IssueType(); t != "" && t != conversation.IssueType {
			continue
		}
		if d.Status() == "closed" || !conversation.IsAssignee(d.Assignee(), d.ID) || slices.Contains(cands, d.ID) {
			continue
		}
		cands = append(cands, d.ID)
	}
	if len(cands) == 0 {
		return nil, nil
	}
	own, err := r.Ledger.Find(ledger.ByID(cands...).WithClosed())
	if err != nil {
		return nil, err
	}
	var out []string
	for _, id := range cands {
		i := slices.IndexFunc(own, func(row *ledger.Record) bool { return row.ID == id })
		if i < 0 {
			return nil, fmt.Errorf("the row of %s, which tracks it, did not read", id)
		}
		c := own[i]
		if c.Status() == "closed" || !conversation.IsCandidate(c.IssueType(), c.Assignee(), c.ID) {
			continue
		}
		edges, err := c.Edges()
		if err != nil {
			return nil, fmt.Errorf("%s's edges did not decode: %v", c.ID, err)
		}
		shaped := make([]conversation.Edge, 0, len(edges))
		for _, e := range edges {
			shaped = append(shaped, conversation.Edge{Type: e.Type, DependsOnID: e.ID})
		}
		if subject, _, ok := conversation.Shape(shaped); ok && subject == bead {
			out = append(out, c.ID)
		}
	}
	return out, nil
}

// personsGates names each open human gate among what waits says holds bead,
// with the ancestor it is on, if any, over listed, bead's row as the refusal
// read it. Under the check, run names the asking reaction's run, and a gate
// filed under the reaction's key whose message names the run among its words
// is that run's own and passed over.
func (r *Reactions) personsGates(bead, run string, listed []*ledger.Record) ([]string, error) {
	snap, err := waits.ReadFrom(r.Ledger, listed, bead)
	var h waits.Holds
	if err == nil {
		h, err = snap.Holds(bead)
	}
	if err != nil {
		return nil, fmt.Errorf("could not read what holds %s (%v), and a person's answer may decide it", bead, err)
	}
	var open []waits.Wait
	for _, w := range h.Waits {
		if prstatus.IsHumanGate(w.IssueType, w.AwaitType) && !strings.EqualFold(w.Status, "closed") &&
			!slices.ContainsFunc(open, func(o waits.Wait) bool { return o.ID == w.ID }) {
			open = append(open, w)
		}
	}
	if run != "" && len(open) > 0 {
		own, err := r.ownGates(open, run)
		if err != nil {
			return nil, fmt.Errorf("could not read the human gates that hold %s, to pass over its own run's (%v)", bead, err)
		}
		open = slices.DeleteFunc(open, func(w waits.Wait) bool { return own[w.ID] })
	}
	var out []string
	for _, w := range open {
		g := "open human gate " + w.ID
		if w.Ancestor != "" {
			g += " on " + w.Ancestor
		}
		out = append(out, g)
	}
	return out, nil
}

// word is a word of a gate's message, as the check reads one: a run of the
// characters a bead id is made of.
var word = regexp.MustCompile(`[A-Za-z0-9._-]+`)

// ownGates is which of the gates are run's own: each one's row, read whole,
// is an open human gate filed under the reaction's key whose message names run
// among its words, each with its trailing dots trimmed, as a sentence ends on
// one. Every gate's row must read.
func (r *Reactions) ownGates(gates []waits.Wait, run string) (map[string]bool, error) {
	ids := make([]string, 0, len(gates))
	for _, g := range gates {
		ids = append(ids, g.ID)
	}
	rows, err := r.Ledger.Find(ledger.ByID(ids...).WithClosed())
	if err != nil {
		return nil, err
	}
	own := map[string]bool{}
	for _, id := range ids {
		i := slices.IndexFunc(rows, func(row *ledger.Record) bool { return row.ID == id })
		if i < 0 {
			return nil, fmt.Errorf("the gate %s did not read", id)
		}
		g := rows[i]
		if !prstatus.IsHumanGate(g.IssueType(), g.AwaitType()) || g.Status() == "closed" || g.AwaitID() != GateKey {
			continue
		}
		for _, w := range word.FindAllString(g.Description(), -1) {
			if strings.TrimRight(w, ".") == run {
				own[id] = true
				break
			}
		}
	}
	return own, nil
}
