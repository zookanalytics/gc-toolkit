// Package arm is gctk's bead arm: a bead armed to start by itself once nothing
// holds it, on a formula, through a pool (docs/deferred-dispatch.md). It holds
// the verbs `gctk bead arm`, `gctk bead disarm` and `gctk bead start-armed`,
// what arm refuses, the dispatch lock all three hold on a bead, and the steps
// the start takes on each armed bead. It asks waits what holds a bead and the
// arm's record (arm/record) for its arm, and no domain asks it.
//
// The arm is the one part of deferred dispatch Gas City cannot express: no
// order or command of its pours a formula on a bead once its blockers close
// (docs/warrants.md, "Deferred dispatch residual").
package arm

import (
	"errors"
	"fmt"
	"slices"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/arm/record"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// The keys the arm reads and does not write. No domain owns any of them: the
// runtime writes the pour's and the route, and lifecycle.sh, through gctk
// lifecycle, writes merge_result, so each is declared read-only here and its
// definition stays in lifecycle/lifecycle.toml or with Gas City.
var (
	routedToKey = ledger.ReadOnly("gc.routed_to", ledger.String,
		"gctk bead arm refuses a routed bead, which is dispatched already.")
	mergeResultKey = ledger.ReadOnly("merge_result", ledger.String,
		"Another path has delivered the work of a bead that carries it, so the start retires its arm without a sling.")
	rootBeadKey = ledger.ReadOnly("gc.root_bead_id", ledger.String,
		"The start reads the fence of each bead poured under a root to tell a pour Gas City left unfinished.")
	moleculeFailedKey = ledger.ReadOnly("molecule_failed", ledger.String,
		"Gas City's stamp on each bead of a pour that failed part way (markFailed in internal/molecule). "+
			"A root that carries true is an unfinished pour.")
	instantiatingKey = ledger.ReadOnly("gc.instantiating", ledger.String,
		"Gas City's fence on a bead it is still pouring, true until it lifts it to empty "+
			"(fenceGraphWorkflowBead in internal/molecule). A root that it, or a bead under it, still fences "+
			"is an unfinished pour.")
)

// Arms is the arm's verbs and its start over one store: the store's ledger,
// the Gas City a start slings through, the directory the dispatch locks live
// in, the clock, and who the records it writes name as their actor.
type Arms struct {
	Ledger  *ledger.Ledger
	Runtime gascity.Runtime
	Locks   string
	Now     func() time.Time
	Actor   string
	// Wait is how long arm and disarm wait for a start that holds the bead's
	// lock, lockWait when zero.
	Wait time.Duration

	formulas map[string]string
}

// LockDir is the directory the dispatch locks live in: the city's
// .gc/runtime/packs/gc-toolkit, where Accept's lock lives too, named from the
// city's root so every caller in the city reaches the same file.
func LockDir(rt gascity.Runtime) (string, error) {
	root, err := rt.CityRoot()
	if err != nil {
		return "", fmt.Errorf("%v, and a lock two callers could name as two files excludes nothing", err)
	}
	return root + "/.gc/runtime/packs/gc-toolkit", nil
}

// Request is one arm: the bead, the pool or agent a start slings it to, the
// formula it pours, empty for the target's default, and why.
type Request struct {
	ID, Target, Formula, Reason string
}

// errRefused marks an arm refused for what the bead or the request is. A
// refused arm writes nothing.
var errRefused = errors.New("refused")

func refuse(format string, args ...any) error {
	return fmt.Errorf("%w: "+format, append([]any{errRefused}, args...)...)
}

// Refused reports whether err is an arm refused for what the bead or the
// request is, rather than a read, a lock or a write that failed.
func Refused(err error) bool { return errors.Is(err, errRefused) }

// Arm records the arm, under the bead's dispatch lock, in one write that
// carries its note. It refuses a closed bead, one already armed for another
// target or formula, one already dispatched (in progress, or routed), one at a
// status other than open, a target that names no formula to pour, and a bead
// with a wait edge into another store, which nothing in the store holds the
// bead on. An arm already on the bead for the same target and formula is a
// success that writes nothing. It returns what it did, and a sentence on what
// holds the bead now.
func (a *Arms) Arm(req Request) (string, error) {
	req.ID, req.Target, req.Formula = strings.TrimSpace(req.ID), strings.TrimSpace(req.Target), strings.TrimSpace(req.Formula)
	if req.Target == "" {
		return "", refuse("an arm names the pool or agent a start slings the bead to, and none was named")
	}
	release, err := a.lockWaiting(req.ID)
	if err != nil {
		return "", err
	}
	defer release()
	r, err := a.read(req.ID)
	if err != nil {
		return "", err
	}
	status := r.Status()
	if status == "closed" {
		return "", refuse("%s is closed, so no dispatch is owed", req.ID)
	}
	if have := record.Of(r); have != nil {
		return a.armedAlready(req, have)
	}
	routed, _, _ := routedToKey.Get(r)
	if status == "in_progress" || strings.TrimSpace(routed) != "" {
		return "", refuse("%s is dispatched already (status %s, routed to %q). Disarm and arm again only if you mean to dispatch it again", req.ID, status, routed)
	}
	if status != "open" {
		return "", refuse("%s is at status %s, and the start sends an open bead alone, so this arm could never fire. Return it to open, then arm it", req.ID, status)
	}
	formula, err := a.formulaFor(req.ID, req.Target, req.Formula)
	if err != nil {
		return "", err
	}
	snap, err := waits.Read(a.Ledger, req.ID)
	if err != nil {
		return "", fmt.Errorf("could not read what holds %s, so whether a wait of its own reaches into another store is unknown, and nothing was written: %w", req.ID, err)
	}
	h, err := snap.Holds(req.ID)
	if err != nil {
		return "", fmt.Errorf("could not read what holds %s, so whether a wait of its own reaches into another store is unknown, and nothing was written: %w", req.ID, err)
	}
	if len(h.Foreign) > 0 {
		return "", refuse("%s has a wait edge onto %s, which its store does not hold, so the store holds nothing on it and the start would send %s while that bead is still open. Move the wait into this store, or sequence the two by hand", req.ID, foreignIDs(h.Foreign), req.ID)
	}
	at := record.ArmedAt(a.Now())
	w := a.Ledger.Write(req.ID)
	record.Set(w, req.Target, formula, req.Reason, a.Actor, at)
	w.Note(fmt.Sprintf("deferred-dispatch: dispatch armed by %s at %s, for %s on %s%s. The deferred-dispatch order starts it once nothing holds this bead, and no agent keeps it in context.",
		a.Actor, at, req.Target, formula, reasonClause(req.Reason)))
	if err := a.Ledger.Commit(w); err != nil {
		return "", fmt.Errorf("the arm on %s was not written: %w", req.ID, err)
	}
	return fmt.Sprintf("armed %s for %s on %s. %s", req.ID, req.Target, formula, holdsNow(r, h)), nil
}

// armedAlready answers an arm on a bead that carries one: a success when it is
// the same arm, and a refusal otherwise.
func (a *Arms) armedAlready(req Request, have *record.Arm) (string, error) {
	if have.Malformed() != "" {
		return "", refuse("%s carries an arm the start cannot read (%s). Disarm it, then arm it again", req.ID, have.Malformed())
	}
	want, err := a.formulaFor(req.ID, req.Target, req.Formula)
	if err != nil {
		return "", err
	}
	// An arm that names no formula pours its target's default at each start.
	had := have.Formula()
	if had == "" {
		had, _ = a.defaultFormula(gascity.Sling{Target: have.Target, Bead: req.ID})
	}
	if have.Target == req.Target && had != "" && had == want {
		return fmt.Sprintf("%s is already armed for %s on %s, so nothing was written", req.ID, req.Target, want), nil
	}
	return "", refuse("%s is already armed for %s on %s. Disarm it first if you mean to change where it goes", req.ID, have.Target, nonEmpty(have.Formula(), "its default formula"))
}

// formulaFor is the formula an arm of bead id for target pours: named, or else
// the target's default, which a target with none refuses.
func (a *Arms) formulaFor(id, target, named string) (string, error) {
	if named != "" {
		return named, nil
	}
	f, err := a.defaultFormula(gascity.Sling{Target: target, Bead: id})
	if err != nil {
		return "", refuse("%s's default formula could not be read (%v), so name one with --on", target, err)
	}
	if f == "" {
		return "", refuse("%s names no formula to pour, so an arm has nothing to start. A bead that waits for a pool to take it as it is needs no arm: route it with gc sling %s <bead> --no-formula --no-convoy, and the pool serves it once bd reports it ready", target, target)
	}
	return f, nil
}

// defaultFormula reads the default formula sling s pours, once per Arms for
// each rig and target it reads. An answer that did not read is asked again for
// the next bead, since the dry run that resolves a pack's default reads the
// bead too.
func (a *Arms) defaultFormula(s gascity.Sling) (string, error) {
	key := s.Rig + " " + s.Target
	if f, ok := a.formulas[key]; ok {
		return f, nil
	}
	f, err := a.Runtime.DefaultFormula(s)
	if err != nil {
		return "", err
	}
	if a.formulas == nil {
		a.formulas = map[string]string{}
	}
	a.formulas[key] = f
	return f, nil
}

// Disarm removes the arm, under the bead's dispatch lock, in one write that
// carries its note. A start already sending the bead finishes before the lock
// is taken, so once Disarm returns no start has the bead in flight and none
// will send it. A bead with no arm left is a success that writes nothing.
func (a *Arms) Disarm(id, reason string) (string, error) {
	id = strings.TrimSpace(id)
	release, err := a.lockWaiting(id)
	if err != nil {
		return "", err
	}
	defer release()
	r, err := a.read(id)
	if err != nil {
		return "", err
	}
	if !record.Present(r) {
		return fmt.Sprintf("%s carries no arm, so nothing was written", id), nil
	}
	if err := a.clear(id, reason); err != nil {
		return "", err
	}
	return "disarmed " + id, nil
}

// clear removes the whole arm in one write, with the note a cleared arm leaves.
func (a *Arms) clear(id, why string) error {
	w := a.Ledger.Write(id)
	record.Clear(w)
	w.Note(fmt.Sprintf("deferred-dispatch: dispatch record cleared at %s: %s", a.Now().UTC().Format(time.RFC3339), why))
	if err := a.Ledger.Commit(w); err != nil {
		return fmt.Errorf("the arm on %s was not cleared: %w", id, err)
	}
	return nil
}

// read reads the bead from the store as it stands now. A bead the store does
// not hold is an error that says so.
func (a *Arms) read(id string) (*ledger.Record, error) {
	rows, err := a.Ledger.Find(ledger.ByID(id).WithClosed())
	if err != nil {
		return nil, fmt.Errorf("could not read %s: %w", id, err)
	}
	for _, r := range rows {
		if r.ID == id {
			return r, nil
		}
	}
	return nil, fmt.Errorf("%s does not resolve in this store", id)
}

// holdsNow says what holds an armed bead now, as the start reads it.
func holdsNow(r *ledger.Record, h waits.Holds) string {
	if l := holdLabel(r.Labels()); l != "" {
		return fmt.Sprintf("Its %s label holds it, so the start sends it once that label is lifted and nothing else holds it.", l)
	}
	if as := r.Assignee(); as != "" {
		return fmt.Sprintf("It is assigned to %s, and the start sends no assigned bead: clear the assignee, or disarm it.", as)
	}
	switch h.Status {
	case waits.Clear:
		return "Nothing holds it now, so the next pass of the deferred-dispatch order sends it."
	case waits.Unjudged:
		return fmt.Sprintf("Its waits-for edge onto %s holds it until the store can judge the edge.", waitIDs(h.Waits))
	}
	return fmt.Sprintf("%s holds it, so the start sends it once nothing holds it.", describeWaits(h.Waits))
}

// holdLabel is the label on a bead that holds it from any pool: Gas City's
// human label, compared as bd's ready read compares it, or one of its dispatch
// holds, hold:mayor and hold:external, compared trimmed and in any case, as
// its hook's HasDispatchHold compares them. It is empty when none does.
func holdLabel(labels []string) string {
	for _, l := range labels {
		if l == humanLabel {
			return l
		}
		for _, hold := range dispatchHolds {
			if strings.EqualFold(strings.TrimSpace(l), hold) {
				return strings.TrimSpace(l)
			}
		}
	}
	return ""
}

// Gas City's labels a pool's serve rule leaves out (beadmeta.DispatchHoldLabels
// and beadmeta.HumanLabel, read at gastownhall/gascity 8d2fb3120c).
var (
	dispatchHolds = []string{"hold:mayor", "hold:external"}
	humanLabel    = "human"
)

// serveRule is the pool's serve rule over armed beads, the flags Gas City
// renders for a pool's routed demand (PoolDemandServeRulesForQuery in
// internal/config/workquery.go): unassigned beads, no epic, and none of its
// hold labels or its human label.
var serveRule = ledger.ServeRule{
	Unassigned:    true,
	ExcludeTypes:  []string{"epic"},
	ExcludeLabels: append(slices.Clone(dispatchHolds), humanLabel),
}

func describeWaits(ws []waits.Wait) string {
	if len(ws) == 0 {
		return "A wait"
	}
	w := ws[0]
	s := w.ID
	if w.Title != "" {
		s += fmt.Sprintf(" %q", w.Title)
	}
	if w.Ancestor != "" {
		s += " on its ancestor " + w.Ancestor
	}
	if len(ws) > 1 {
		s += fmt.Sprintf(" (and %d more)", len(ws)-1)
	}
	return s
}

func waitIDs(ws []waits.Wait) string {
	var ids []string
	for _, w := range ws {
		ids = append(ids, w.ID)
	}
	return strings.Join(ids, ", ")
}

func foreignIDs(fs []waits.Foreign) string {
	var ids []string
	for _, f := range fs {
		ids = append(ids, f.ID)
	}
	return strings.Join(ids, ", ")
}

func reasonClause(reason string) string {
	if reason = strings.TrimSpace(reason); reason == "" {
		return ""
	}
	return ": " + reason
}

func nonEmpty(s, otherwise string) string {
	if s == "" {
		return otherwise
	}
	return s
}
