package place

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	rtfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

var (
	hqRig   = gascity.Rig{Name: "city", Path: "/city", Prefix: "hq", HQ: true}
	toolRig = gascity.Rig{Name: "gc-toolkit", Path: "/rigs/gc-toolkit", Prefix: "tk"}
	napRig  = gascity.Rig{Name: "sleepy", Path: "/rigs/sleepy", Prefix: "zz", Suspended: true}
)

// moveCity is a city of three stores, the last of a suspended rig, and the
// opener over them, which fails a store openErr names.
type moveCity struct {
	*rtfake.Roster
	stores  map[string]*fake.Store
	openErr map[string]error
}

func newMoveCity() *moveCity {
	return &moveCity{
		Roster:  &rtfake.Roster{RigList: []gascity.Rig{hqRig, toolRig, napRig}},
		stores:  map[string]*fake.Store{hqRig.Store(): fake.New(), toolRig.Store(): fake.New(), napRig.Store(): fake.New()},
		openErr: map[string]error{},
	}
}

func (c *moveCity) open(_ context.Context, db string) (*ledger.Ledger, error) {
	if err := c.openErr[db]; err != nil {
		return nil, err
	}
	s, ok := c.stores[db]
	if !ok {
		return nil, fmt.Errorf("no store at %s", db)
	}
	return ledger.New(s), nil
}

func (c *moveCity) run(t *testing.T, dry bool) Moved {
	t.Helper()
	out, err := (&Move{City: c, Open: c.open, DryRun: dry}).Run(context.Background())
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	return out
}

func (c *moveCity) labels(db, id string) []string {
	b, _ := c.stores[db].Row(id)
	return b.Labels
}

func storeOf(out Moved, rig string) StoreMove {
	for _, s := range out.Stores {
		if s.Rig == rig {
			return s
		}
	}
	return StoreMove{}
}

func leftIDs(s StoreMove) []string {
	var ids []string
	for _, l := range s.Left {
		ids = append(ids, l.ID)
	}
	return ids
}

// A mixed store moves each bead whose placement hold is hold:mayor alone, or
// hold:mayor beside hold:po, onto hold:po in one update that names both labels,
// and counts a bead on hold:po already. It leaves each other bead the queue
// holds on hold:mayor as it stands, with why and the write a person makes, and
// writes no bead that is not in the queue, no closed bead and no other hold.
func TestAMoveTakesTheQueueOntoHoldPO(t *testing.T) {
	c := newMoveCity()
	s := c.stores[toolRig.Store()]
	for _, b := range []fake.Bead{
		{ID: "tk-old", Status: "open", Labels: []string{"hold:mayor", "learning"}},
		{ID: "tk-both", Status: "open", Labels: []string{"hold:mayor", "hold:po"}},
		{ID: "tk-new", Status: "open", Labels: []string{"hold:po"}},
		{ID: "tk-blocked", Status: "blocked", Labels: []string{"hold:mayor"}},
		{ID: "tk-ext", Status: "open", Labels: []string{"hold:external", "hold:mayor"}},
		{ID: "tk-cleared", Status: "open", Labels: []string{"hold:cleared", "hold:mayor"}},
		{ID: "tk-case", Status: "open", Labels: []string{"Hold:Mayor"}},
		{ID: "tk-mine", Status: "open", Labels: []string{"hold:mayor"}, Assignee: "gc-toolkit/gc-toolkit.polecat-1"},
		{ID: "tk-repair", Status: "open", Labels: []string{"hold:mayor"}, Metadata: map[string]string{"gc.routed_to": "gc-toolkit.mayor"}},
		{ID: "tk-routed", Status: "open", Labels: []string{"hold:mayor"}, Metadata: map[string]string{"gc.routed_to": "gc-toolkit/gc-toolkit.polecat"}},
		{ID: "tk-chosen", Status: "open", Labels: []string{"hold:mayor"}, Metadata: map[string]string{"gc.routed_to": "gc-toolkit/core.mayor"}},
		{ID: "tk-blank", Status: "open", Labels: []string{"hold:mayor"}, Metadata: map[string]string{"gc.routed_to": " "}},
		{ID: "tk-closed", Status: "closed", Labels: []string{"hold:mayor"}},
		{ID: "tk-train", Status: "open", Labels: []string{"hold:release-train"}},
		{ID: "tk-free", Status: "open"},
	} {
		s.Put(b)
	}
	c.stores[hqRig.Store()].Put(fake.Bead{ID: "hq-old", Status: "open", Labels: []string{"hold:mayor"}})
	c.stores[napRig.Store()].Put(fake.Bead{ID: "zz-old", Status: "deferred", Labels: []string{"hold:mayor"}})

	out := c.run(t, false)
	tk := storeOf(out, "gc-toolkit")
	if want := []string{"tk-blank", "tk-blocked", "tk-both", "tk-old"}; !slices.Equal(tk.Moved, want) {
		t.Errorf("moved %v, want %v", tk.Moved, want)
	}
	if want := []string{"tk-new"}; !slices.Equal(tk.OnPO, want) {
		t.Errorf("on hold:po already %v, want %v", tk.OnPO, want)
	}
	if want := []string{"tk-case", "tk-chosen", "tk-cleared", "tk-ext", "tk-mine", "tk-repair", "tk-routed"}; !slices.Equal(leftIDs(tk), want) {
		t.Errorf("left %v, want %v", leftIDs(tk), want)
	}
	for id, want := range map[string][]string{
		"tk-old": {"learning", "hold:po"}, "tk-both": {"hold:po"}, "tk-blocked": {"hold:po"}, "tk-new": {"hold:po"},
		"tk-ext": {"hold:external", "hold:mayor"}, "tk-cleared": {"hold:cleared", "hold:mayor"}, "tk-case": {"Hold:Mayor"},
		"tk-mine": {"hold:mayor"}, "tk-repair": {"hold:mayor"}, "tk-routed": {"hold:mayor"}, "tk-chosen": {"hold:mayor"},
		"tk-closed": {"hold:mayor"}, "tk-train": {"hold:release-train"}, "tk-free": nil,
	} {
		if got := c.labels(toolRig.Store(), id); !slices.Equal(got, want) {
			t.Errorf("%s carries %v, want %v", id, got, want)
		}
	}
	if st := s.States(); len(st) != 0 {
		t.Errorf("set-states %+v, want none: set-state swaps the first hold: label it reads, not the one the move names", st)
	}
	swap := []string{"--add-label", "hold:po", "--remove-label", "hold:mayor"}
	for _, wr := range s.Writes() {
		if !slices.Equal(wr.Args, swap) {
			t.Errorf("the write to %s was %q, want %q", wr.ID, wr.Args, swap)
		}
	}
	if b, _ := s.Row("tk-blocked"); b.Status != "blocked" {
		t.Errorf("tk-blocked is %s, want its status kept", b.Status)
	}
	why := map[string]string{}
	for _, l := range tk.Left {
		why[l.ID] = l.Why + " | " + l.Fix
	}
	for id, want := range map[string][]string{
		"tk-ext":     {"also carries hold:external", "gc bd update tk-ext --add-label hold:po --remove-label hold:mayor --db '/rigs/gc-toolkit/.beads'"},
		"tk-cleared": {"also carries hold:cleared"},
		"tk-case":    {"carries hold:mayor as Hold:Mayor", "--add-label hold:po --remove-label 'Hold:Mayor'"},
		"tk-mine":    {"assigned to gc-toolkit/gc-toolkit.polecat-1", "--assignee ''"},
		"tk-repair": {"routed to gc-toolkit.mayor, a route Gas City's doctor repair hold-label-routed-to wrote from hold:mayor and a writer can choose as well",
			"Read who set the route: gc bd history tk-repair --events --db '/rigs/gc-toolkit/.beads'. When gc doctor --fix set it, clear it; otherwise place the bead with gctk bead place",
			"gc bd update tk-repair --unset-metadata gc.routed_to --db '/rigs/gc-toolkit/.beads'"},
		"tk-routed": {"routed to gc-toolkit/gc-toolkit.polecat, which a writer chose", "Place it with gctk bead place"},
		"tk-chosen": {"routed to gc-toolkit/core.mayor, which a writer chose", "Place it with gctk bead place"},
	} {
		for _, w := range want {
			if !strings.Contains(why[id], w) {
				t.Errorf("%s is left with %q, want it to name %q", id, why[id], w)
			}
		}
	}
	if strings.Contains(why["tk-chosen"], "doctor") {
		t.Errorf("tk-chosen is left with %q: a rig-qualified route is no shape the doctor repair wrote", why["tk-chosen"])
	}
	for rig, id := range map[string]string{"city": "hq-old", "sleepy": "zz-old"} {
		if got := storeOf(out, rig); !slices.Equal(got.Moved, []string{id}) || got.Unread != "" {
			t.Errorf("%s moved %v (unread %q), want %s: the HQ and a suspended rig are stores of the city", rig, got.Moved, got.Unread, id)
		}
	}
	if out.AnyUnread() || !out.AnyLeft() {
		t.Errorf("unread %v, left %v; want every store read and beads left", out.AnyUnread(), out.AnyLeft())
	}
}

// A second move writes nothing: each bead it moved is on hold:po already, and
// each it left is left again.
func TestAMoveAgainWritesNothing(t *testing.T) {
	c := newMoveCity()
	s := c.stores[toolRig.Store()]
	s.Put(fake.Bead{ID: "tk-old", Status: "open", Labels: []string{"hold:mayor"}})
	s.Put(fake.Bead{ID: "tk-ext", Status: "open", Labels: []string{"hold:external", "hold:mayor"}})
	c.run(t, false)
	before := len(s.Writes()) + len(s.States())
	again := storeOf(c.run(t, false), "gc-toolkit")
	if after := len(s.Writes()) + len(s.States()); after != before {
		t.Errorf("a second move wrote %d more times", after-before)
	}
	if len(again.Moved) != 0 || !slices.Equal(again.OnPO, []string{"tk-old"}) || !slices.Equal(leftIDs(again), []string{"tk-ext"}) {
		t.Errorf("a second move = %+v, want nothing moved, tk-old on hold:po and tk-ext left", again)
	}
}

// A dry run writes nothing and names each bead a move would move.
func TestADryRunWritesNothing(t *testing.T) {
	c := newMoveCity()
	s := c.stores[toolRig.Store()]
	s.Put(fake.Bead{ID: "tk-old", Status: "open", Labels: []string{"hold:mayor"}})
	out := storeOf(c.run(t, true), "gc-toolkit")
	if len(s.Writes())+len(s.States()) != 0 {
		t.Errorf("a dry run wrote: %v %v", s.Writes(), s.States())
	}
	if !slices.Equal(out.Moved, []string{"tk-old"}) || !slices.Equal(c.labels(toolRig.Store(), "tk-old"), []string{"hold:mayor"}) {
		t.Errorf("a dry run = %+v, want tk-old named and left on hold:mayor", out)
	}
}

// A store that does not open or does not list is named with why, the others
// move, and the move reads as unfinished. A rig list that does not read moves
// nothing.
func TestAStoreThatDoesNotReadIsNamed(t *testing.T) {
	c := newMoveCity()
	c.stores[toolRig.Store()].Put(fake.Bead{ID: "tk-old", Status: "open", Labels: []string{"hold:mayor"}})
	c.openErr[hqRig.Store()] = errors.New("dolt is down")
	c.stores[napRig.Store()].FindErr = errors.New("bd timed out")
	out := c.run(t, false)
	if got := storeOf(out, "city").Unread; !strings.Contains(got, "dolt is down") {
		t.Errorf("the HQ reads %q, want it named unread with why", got)
	}
	if got := storeOf(out, "sleepy").Unread; !strings.Contains(got, "bd timed out") {
		t.Errorf("sleepy reads %q, want it named unread with why", got)
	}
	if got := storeOf(out, "gc-toolkit"); !slices.Equal(got.Moved, []string{"tk-old"}) {
		t.Errorf("gc-toolkit moved %v, want tk-old: a store that reads moves", got.Moved)
	}
	if !out.AnyUnread() {
		t.Error("a move with a store unread reads as finished")
	}
	c.RigsErr = errors.New("no city")
	if _, err := (&Move{City: c, Open: c.open}).Run(context.Background()); err == nil {
		t.Error("a rig list that did not read moved")
	}
}

// A bead is read again just before its write. One whose hold:mayor a placement
// lifted after the store's read takes no hold:po, and one whose write does not
// land is left on hold:mayor with why.
func TestAMoveWritesOnlyWhatItReadsAgain(t *testing.T) {
	c := newMoveCity()
	s := c.stores[toolRig.Store()]
	s.Put(fake.Bead{ID: "tk-placed", Status: "open", Labels: []string{"hold:mayor"}})
	s.OnFind = func(q gcbd.Query) {
		if slices.Equal(q.IDs, []string{"tk-placed"}) {
			s.Put(fake.Bead{ID: "tk-placed", Status: "open", Metadata: map[string]string{"gc.dispatch_when_ready": "gc-toolkit/gc-toolkit.polecat"}})
		}
	}
	out := storeOf(c.run(t, false), "gc-toolkit")
	if len(s.Writes()) != 0 || len(out.Moved) != 0 || !slices.Equal(leftIDs(out), []string{"tk-placed"}) ||
		!strings.Contains(out.Left[0].Why, "lifted after the store's read") || c.labels(toolRig.Store(), "tk-placed") != nil {
		t.Errorf("a bead placed under the move = %+v with labels %v, want it left with no hold written", out, c.labels(toolRig.Store(), "tk-placed"))
	}

	c = newMoveCity()
	s = c.stores[toolRig.Store()]
	s.Put(fake.Bead{ID: "tk-old", Status: "open", Labels: []string{"hold:mayor"}})
	s.UpdateErr = errors.New("bd refused")
	out = storeOf(c.run(t, false), "gc-toolkit")
	if len(out.Moved) != 0 || !slices.Equal(leftIDs(out), []string{"tk-old"}) || !strings.Contains(out.Left[0].Why, "did not land") || !strings.Contains(out.Left[0].Why, "bd refused") ||
		!slices.Equal(c.labels(toolRig.Store(), "tk-old"), []string{"hold:mayor"}) {
		t.Errorf("a refused write = %+v, want tk-old left on hold:mayor with why", out)
	}
}

// A hold another writer adds after the move read a bead again, and before its
// write lands, stays on, and the bead moves: the write removes hold:mayor by
// name, not the first hold: label the bead carries then.
func TestAMoveKeepsAHoldAddedBeforeItsWrite(t *testing.T) {
	c := newMoveCity()
	s := c.stores[toolRig.Store()]
	s.Put(fake.Bead{ID: "tk-old", Status: "open", Labels: []string{"hold:mayor"}})
	s.BeforeUpdate = func(id string, _ []string) error {
		b, _ := s.Row(id)
		b.Labels = append(slices.Clone(b.Labels), "hold:external")
		s.Put(b)
		return nil
	}
	out := storeOf(c.run(t, false), "gc-toolkit")
	if got := c.labels(toolRig.Store(), "tk-old"); !slices.Equal(got, []string{"hold:external", "hold:po"}) {
		t.Errorf("tk-old carries %v, want hold:external kept and hold:mayor swapped for hold:po", got)
	}
	if !slices.Equal(out.Moved, []string{"tk-old"}) || len(out.Left) != 0 {
		t.Errorf("the move = %+v, want tk-old moved", out)
	}
}
