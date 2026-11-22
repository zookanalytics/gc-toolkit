package distiller

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	gcfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

const homePool = "tools/gc-toolkit.polecat"

// sling is one formula sling the start made: the target, the formula, and how
// long its context had left when it was asked.
type sling struct {
	target, formula string
	left            time.Duration
}

// city is the runtime and the stores a start reads: an HQ whose checkout holds
// the city's own pack, the home rig tools, whose checkout holds the gc-toolkit
// pack, and the rig web, whose checkout holds no pack.toml.
type city struct {
	*gcfake.Roster
	hq, home, web gascity.Rig
	stores        map[string]*fake.Store
	openErr       error
	opened        []time.Duration
	slings        []sling
	answer        gascity.FormulaSling
}

func newCity(t *testing.T) *city {
	t.Helper()
	base := t.TempDir()
	c := &city{
		hq:     gascity.Rig{Name: "city", Path: base, Prefix: "hq", HQ: true},
		home:   gascity.Rig{Name: "tools", Path: filepath.Join(base, "rigs", "tools"), Prefix: "tk"},
		web:    gascity.Rig{Name: "web", Path: filepath.Join(base, "rigs", "web"), Prefix: "wb"},
		answer: gascity.FormulaSling{Root: "tk-run"},
	}
	writePack(t, c.hq.Path, "[pack]\nname = \"city\"\nschema = 2\n")
	writePack(t, c.home.Path, "[pack]\nname = \"gc-toolkit\"\nschema = 2\n\n[imports.core]\nsource = \"core\"\n")
	if err := os.MkdirAll(c.web.Path, 0o755); err != nil {
		t.Fatal(err)
	}
	c.Roster = &gcfake.Roster{
		RigList: []gascity.Rig{c.hq, c.home, c.web},
		AgentList: []gascity.Agent{
			{Name: "polecat", QualifiedName: homePool, Dir: "tools"},
			{Name: "polecat-codex", QualifiedName: "tools/gc-toolkit.polecat-codex", Dir: "tools"},
			{Name: "refinery", QualifiedName: "tools/gc-toolkit.refinery", Dir: "tools"},
			{Name: "polecat", QualifiedName: "web/gc-toolkit.polecat", Dir: "web"},
			{Name: "mechanik", QualifiedName: "gc-toolkit.mechanik"},
		},
	}
	c.stores = map[string]*fake.Store{c.hq.Store(): fake.New(), c.home.Store(): fake.New(), c.web.Store(): fake.New()}
	return c
}

// writePack writes a pack.toml with text into dir.
func writePack(t *testing.T, dir, text string) {
	t.Helper()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "pack.toml"), []byte(text), 0o644); err != nil {
		t.Fatal(err)
	}
}

func (c *city) SlingFormula(ctx context.Context, target, formula string) gascity.FormulaSling {
	deadline, _ := ctx.Deadline()
	c.slings = append(c.slings, sling{target: target, formula: formula, left: time.Until(deadline)})
	return c.answer
}

func (c *city) open(ctx context.Context, db string) (*ledger.Ledger, error) {
	deadline, _ := ctx.Deadline()
	c.opened = append(c.opened, time.Until(deadline))
	if c.openErr != nil {
		return nil, c.openErr
	}
	s, ok := c.stores[db]
	if !ok {
		return nil, fmt.Errorf("no store at %s", db)
	}
	return ledger.New(s), nil
}

func (c *city) start() Outcome {
	return (&Starter{City: c, Open: c.open}).Run(context.Background())
}

// root puts a run's root in rig's store: a bead Gas City stamped with kind and
// the formula it was poured from, in status.
func (c *city) root(rig gascity.Rig, id, formula, kind, status string) {
	c.stores[rig.Store()].Put(fake.Bead{ID: id, Title: formula, Status: status, IssueType: "task",
		Metadata: map[string]string{"gc.kind": kind, "gc.formula_name": formula}})
}

// With no run open, a start slings one run of the distiller's formula to the
// polecat pool of the home rig, the one whose checkout holds the gc-toolkit
// pack, and its context bounds the sling by SlingWait.
func TestAStartSlingsOneRunToTheHomeRigsPool(t *testing.T) {
	c := newCity(t)
	out := c.start()
	want := Outcome{Home: "tools", Pool: homePool, Slung: true, Root: "tk-run"}
	if !reflect.DeepEqual(out, want) {
		t.Fatalf("the start answered %+v, want %+v", out, want)
	}
	if len(c.slings) != 1 || c.slings[0].target != homePool || c.slings[0].formula != Formula {
		t.Fatalf("the start slung %+v", c.slings)
	}
	if left := c.slings[0].left; left <= 0 || left > SlingWait {
		t.Errorf("the sling had %s left, want a bound no longer than %s", left, SlingWait)
	}
	if len(c.opened) != 1 || c.opened[0] <= 0 || c.opened[0] > StoreWait {
		t.Errorf("the store was opened with %v left, want once, bounded by %s", c.opened, StoreWait)
	}
	if got := out.Summary(); got != "started tk-run, a run of mol-feedback-distiller, in rig tools through "+homePool {
		t.Errorf("the summary reads %q", got)
	}
}

// A live root of a run of the formula in the home rig's store holds the start,
// whatever its status short of closed. A closed run, another formula's run, a
// live bead of the formula that is not a run's root, and a run open in another
// rig's store hold nothing.
func TestAnOpenRunHoldsTheStart(t *testing.T) {
	for _, status := range []string{"open", "in_progress", "blocked"} {
		t.Run(status, func(t *testing.T) {
			c := newCity(t)
			c.root(c.home, "tk-live", Formula, "workflow", status)
			out := c.start()
			if out.Failure != "" || out.Slung || !slices.Equal(out.Open, []string{"tk-live"}) || len(c.slings) != 0 {
				t.Fatalf("a run %s answered %+v and slung %+v", status, out, c.slings)
			}
			if !strings.Contains(out.Summary(), "tk-live, a run of mol-feedback-distiller, is open in rig tools") {
				t.Errorf("the summary reads %q", out.Summary())
			}
		})
	}
	c := newCity(t)
	c.root(c.home, "tk-done", Formula, "workflow", "closed")
	c.root(c.home, "tk-miner", "mol-feedback-miner", "workflow", "open")
	c.root(c.home, "tk-step", Formula, "", "open")
	c.root(c.web, "tk-elsewhere", Formula, "workflow", "open")
	if out := c.start(); !out.Slung || len(out.Open) != 0 || len(c.slings) != 1 {
		t.Fatalf("roots that hold nothing held the start: %+v, slung %+v", out, c.slings)
	}
}

// A city where no rig's checkout holds the pack has no home rig: the start
// reads no roster and no store and slings nothing, and it does not fail. The
// HQ's checkout is not a rig's, even when its pack.toml names the pack, and a
// rig bound to no path has no checkout.
func TestACityWithNoHomeRigStartsNothing(t *testing.T) {
	c := newCity(t)
	writePack(t, c.home.Path, "[pack]\nname = \"other\"\n")
	writePack(t, c.hq.Path, "[pack]\nname = \"gc-toolkit\"\n")
	c.RigList = append(c.RigList, gascity.Rig{Name: "unbound", Prefix: "ub"})
	out := c.start()
	if out.Failure != "" || out.Slung || out.Home != "" || len(c.slings) != 0 || len(c.opened) != 0 {
		t.Fatalf("a city with no home rig answered %+v, slung %+v, opened %v", out, c.slings, c.opened)
	}
	if !slices.Equal(c.Reads(), []string{"rigs"}) {
		t.Errorf("the start read %v, want the rig list alone", c.Reads())
	}
	if got := out.Summary(); got != "started nothing: no rig's checkout holds the gc-toolkit pack, so the city has no home rig to distill in" {
		t.Errorf("the summary reads %q", got)
	}
}

// Gas City dispatches no order of a suspended rig, and a suspended home rig
// takes no run from the start either.
func TestASuspendedHomeRigStartsNothing(t *testing.T) {
	c := newCity(t)
	c.RigList[1].Suspended = true
	out := c.start()
	if out.Failure != "" || out.Slung || len(c.slings) != 0 || !strings.Contains(out.Held, "the home rig tools is suspended") {
		t.Fatalf("a suspended home rig answered %+v and slung %+v", out, c.slings)
	}
}

// Two rigs whose checkouts each hold the pack leave the home rig unknown, and a
// pack.toml that is there and does not read could be a second one, so each
// fails the start with nothing slung.
func TestAHomeRigThatIsNotOneFailsTheStart(t *testing.T) {
	c := newCity(t)
	writePack(t, c.web.Path, "[pack]\nname = \"gc-toolkit\"\n")
	out := c.start()
	if out.Slung || len(c.slings) != 0 || !strings.Contains(out.Failure, "rigs tools, web each hold the gc-toolkit pack") {
		t.Fatalf("two home rigs answered %+v and slung %+v", out, c.slings)
	}

	c = newCity(t)
	writePack(t, c.web.Path, "[pack\nname = ")
	out = c.start()
	if out.Slung || len(c.slings) != 0 || !strings.Contains(out.Failure, "the pack.toml of rig web did not read") {
		t.Fatalf("a pack.toml that does not decode answered %+v and slung %+v", out, c.slings)
	}

	c = newCity(t)
	if err := os.MkdirAll(filepath.Join(c.web.Path, "pack.toml"), 0o755); err != nil {
		t.Fatal(err)
	}
	if out := c.start(); out.Slung || !strings.Contains(out.Failure, "the pack.toml of rig web did not read") {
		t.Fatalf("a pack.toml that cannot be read answered %+v", out)
	}
}

// The pool is the one agent named polecat that the roster places in the home
// rig. A home rig with none, or with several, fails the start with nothing
// slung.
func TestThePoolIsTheHomeRigsOnePolecat(t *testing.T) {
	c := newCity(t)
	c.AgentList = slices.DeleteFunc(c.AgentList, func(a gascity.Agent) bool { return a.QualifiedName == homePool })
	out := c.start()
	if out.Slung || len(c.slings) != 0 || !strings.Contains(out.Failure, "names no agent polecat in the home rig tools") {
		t.Fatalf("a home rig with no polecat answered %+v and slung %+v", out, c.slings)
	}

	c = newCity(t)
	c.AgentList = append(c.AgentList, gascity.Agent{Name: "polecat", QualifiedName: "tools/other.polecat", Dir: "tools"})
	out = c.start()
	if out.Slung || len(c.slings) != 0 || !strings.Contains(out.Failure, "names 2 agents polecat in the home rig tools") {
		t.Fatalf("a home rig with two polecats answered %+v and slung %+v", out, c.slings)
	}
}

// A read that does not answer, and a sling that fails, fail the start, and a
// failed read slings nothing.
func TestAFailureFailsTheStart(t *testing.T) {
	boom := errors.New("boom")
	for name, set := range map[string]func(*city){
		"rig list":   func(c *city) { c.RigsErr = boom },
		"agent list": func(c *city) { c.AgentsErr = boom },
		"store open": func(c *city) { c.openErr = boom },
		"store read": func(c *city) { c.stores[c.home.Store()].FindErr = boom },
	} {
		t.Run(name, func(t *testing.T) {
			c := newCity(t)
			set(c)
			out := c.start()
			if out.Failure == "" || out.Slung || len(c.slings) != 0 || !strings.Contains(out.Failure, "boom") {
				t.Fatalf("a %s that did not answer gave %+v and slung %+v", name, out, c.slings)
			}
		})
	}
	c := newCity(t)
	c.answer = gascity.FormulaSling{Bounded: gascity.Bounded{Code: 1, Stderr: "gc sling: refused\n"}}
	out := c.start()
	if out.Slung || out.Failure != "gc sling did not start a run of mol-feedback-distiller through "+homePool+": exit 1: gc sling: refused" {
		t.Fatalf("a refused sling answered %+v", out)
	}
	if !strings.HasPrefix(out.Summary(), "started nothing: gc sling did not start") {
		t.Errorf("the summary reads %q", out.Summary())
	}
}

// The pack's own pack.toml names the pack the start looks for, so the checkout
// of this repository is a home rig.
func TestThePacksOwnPackTomlNamesThePack(t *testing.T) {
	name, err := packName("../../../pack.toml")
	if err != nil || name != Pack {
		t.Fatalf("the pack's pack.toml names %q (%v), want %q", name, err, Pack)
	}
}
