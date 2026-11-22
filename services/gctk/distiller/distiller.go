// Package distiller is the feedback distiller's domain: where the city's one
// run of the distiller starts (docs/feedback-learning.md). Its start, `gctk
// distiller start`, finds the pack's home rig, the one rig whose checkout holds
// the pack, and the polecat pool Gas City's roster names there, and slings a
// run of the distiller's formula to that pool unless a run of it is open in the
// rig's store. It owns nothing but the start's lock, which keeps overlapping
// starts apart. It reads the rig list, the roster, each rig's pack.toml and the
// roots Gas City stamps at a pour, and its one write is the sling.
package distiller

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/pelletier/go-toml/v2"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// Formula is the distiller's formula, the name Gas City stamps on the root of
// each run poured from it.
const Formula = "mol-feedback-distiller"

// Pack is the name the home rig's pack.toml gives the pack. A prompt update is
// an edit to the pack, so the distiller runs in the rig whose checkout is the
// pack's.
const Pack = "gc-toolkit"

// Role is the name of the agent whose pool runs the distiller, the template's
// name whatever binding imports it.
const Role = "polecat"

const (
	// StoreWait bounds the read of the home rig's store for an open run, and
	// SlingWait the sling. The rig list and the roster keep the runtime
	// adapter's own bounds (gascity.RigListWait, gascity.RosterWait), so a
	// start ends inside the sum of the four, which the order's timeout is
	// above.
	StoreWait = 60 * time.Second
	SlingWait = 90 * time.Second
)

// City is Gas City as the start reaches it: the rig list, the roster and the
// formula sling.
type City interface {
	Rigs() ([]gascity.Rig, error)
	Agents() ([]gascity.Agent, error)
	SlingFormula(ctx context.Context, target, formula string) gascity.FormulaSling
}

// Starter starts the city's distiller run. Locks is the directory the start's
// lock lives in, the city's .gc/runtime/packs/gc-toolkit (arm.LockDir).
type Starter struct {
	City  City
	Open  ledger.Opener
	Locks string
}

// Outcome is what a start did: the home rig and its pool as far as it found
// them, the open runs that held it, whether it slung a run and the root the
// sling named, and why it stopped short. A Failure is a read or a sling that
// did not answer, or a city whose home rig or pool is not one, and makes the
// run's exit non-zero. Without one, Held says why nothing was slung, when
// nothing was.
type Outcome struct {
	Home    string
	Pool    string
	Open    []string
	Slung   bool
	Root    string
	Held    string
	Failure string
}

// Summary is the outcome in one line, for the start's output.
func (o Outcome) Summary() string {
	switch {
	case o.Failure != "":
		return "started nothing: " + o.Failure
	case o.Slung && o.Root != "":
		return fmt.Sprintf("started %s, a run of %s, in rig %s through %s", o.Root, Formula, o.Home, o.Pool)
	case o.Slung:
		return fmt.Sprintf("slung a run of %s to %s in rig %s; gc sling named no root", Formula, o.Pool, o.Home)
	}
	return "started nothing: " + o.Held
}

// Run starts the distiller once. The home rig is the one rig, the HQ aside,
// whose checkout holds a pack.toml that names Pack. A city with no such rig has
// nowhere to distill, and the start slings nothing. Gas City dispatches no
// order of a suspended rig, so a suspended home rig takes no run either. The
// pool is the one agent named Role the roster places in the home rig. From
// there to the sling's end the start holds the start's lock, and a start that
// finds another holding it starts nothing, since that start reads and slings. A
// run is open while the home rig's store holds a live root Gas City stamped as
// a workflow poured from Formula, and an open run, whichever path poured it,
// holds the start, so a day whose run is still going starts no second one.
// Otherwise it slings Formula to the pool, which gc pours in the home rig's
// store, the store of the rig the pool serves. Two rigs that each hold the
// pack, a pack.toml that does not read, a pool that is not one, a lock that
// cannot be taken, and a read or a sling that does not answer each fail the
// run with nothing slung. The store's read and the sling end when ctx does.
func (s *Starter) Run(ctx context.Context) Outcome {
	rigs, err := s.City.Rigs()
	if err != nil {
		return Outcome{Failure: "the rig list did not read, so the home rig was not found: " + err.Error()}
	}
	home, err := homeRig(rigs)
	if err != nil {
		return Outcome{Failure: err.Error()}
	}
	if home == nil {
		return Outcome{Held: "no rig's checkout holds the " + Pack + " pack, so the city has no home rig to distill in"}
	}
	out := Outcome{Home: home.Name}
	if home.Suspended {
		out.Held = "the home rig " + home.Name + " is suspended"
		return out
	}
	agents, err := s.City.Agents()
	if err != nil {
		out.Failure = "the agent list did not read, so the home rig's pool was not found: " + err.Error()
		return out
	}
	if out.Pool, err = pool(agents, home.Name); err != nil {
		out.Failure = err.Error()
		return out
	}
	release, holder, err := s.lock()
	if err != nil {
		out.Failure = err.Error()
		return out
	}
	if release == nil {
		out.Held = fmt.Sprintf("another start holds the start's lock (%s), so that start decides whether a run starts in rig %s", holder, home.Name)
		return out
	}
	defer release()
	if out.Open, err = s.openRuns(ctx, *home); err != nil {
		out.Failure = "the store of rig " + home.Name + " did not read, so whether a run is open there is not known: " + err.Error()
		return out
	}
	if len(out.Open) > 0 {
		out.Held = fmt.Sprintf("%s, a run of %s, is open in rig %s", strings.Join(out.Open, ", "), Formula, home.Name)
		return out
	}
	sling, cancel := context.WithTimeout(ctx, SlingWait)
	defer cancel()
	res := s.City.SlingFormula(sling, out.Pool, Formula)
	if f := res.Failure(); f != "" {
		out.Failure = fmt.Sprintf("gc sling did not start a run of %s through %s: %s", Formula, out.Pool, f)
		return out
	}
	out.Slung, out.Root = true, res.Root
	return out
}

// homeRig is the one rig, the HQ aside, whose checkout holds a pack.toml that
// names Pack, nil when no rig's does. A rig bound to no path has no checkout.
func homeRig(rigs []gascity.Rig) (*gascity.Rig, error) {
	var homes []gascity.Rig
	for _, r := range rigs {
		if r.HQ || r.Path == "" {
			continue
		}
		name, err := packName(filepath.Join(r.Path, "pack.toml"))
		if err != nil {
			return nil, fmt.Errorf("the pack.toml of rig %s did not read, so the home rig is not known: %w", r.Name, err)
		}
		if name == Pack {
			homes = append(homes, r)
		}
	}
	switch len(homes) {
	case 0:
		return nil, nil
	case 1:
		return &homes[0], nil
	}
	names := make([]string, len(homes))
	for i, h := range homes {
		names[i] = h.Name
	}
	return nil, fmt.Errorf("the checkouts of rigs %s each hold the %s pack, so which one is home is not known", strings.Join(names, ", "), Pack)
}

// packName is the name the pack.toml at path gives its pack, "" when there is
// no file there.
func packName(path string) (string, error) {
	raw, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	var f struct {
		Pack struct {
			Name string `toml:"name"`
		} `toml:"pack"`
	}
	if err := toml.Unmarshal(raw, &f); err != nil {
		return "", err
	}
	return f.Pack.Name, nil
}

// pool is the qualified name of the one agent named Role the roster places in
// rig.
func pool(agents []gascity.Agent, rig string) (string, error) {
	var pools []string
	for _, a := range agents {
		if a.Dir == rig && a.Name == Role {
			pools = append(pools, a.QualifiedName)
		}
	}
	switch len(pools) {
	case 1:
		return pools[0], nil
	case 0:
		return "", fmt.Errorf("gc agent list names no agent %s in the home rig %s, so a run has no pool to go to", Role, rig)
	}
	return "", fmt.Errorf("gc agent list names %d agents %s in the home rig %s (%s), so which pool runs the distiller is not known",
		len(pools), Role, rig, strings.Join(pools, ", "))
}

// openRuns is the id of each live root in rig's store that Gas City stamped as
// a workflow poured from Formula.
func (s *Starter) openRuns(ctx context.Context, rig gascity.Rig) ([]string, error) {
	read, cancel := context.WithTimeout(ctx, StoreWait)
	defer cancel()
	l, err := s.Open(read, rig.Store())
	if err != nil {
		return nil, err
	}
	recs, err := l.Find(ledger.Matching(formulaNameKey, Formula))
	if err != nil {
		return nil, err
	}
	var open []string
	for _, r := range recs {
		kind, _, err := kindKey.Get(r)
		if err != nil {
			return nil, err
		}
		if kind == workflowKind {
			open = append(open, r.ID)
		}
	}
	return open, nil
}
