package waits

import (
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// runLibFixture is assets/scripts/run-lib.fixture.json: a store in the shape
// `bd list --json` prints, and the cases every copy of the run rule must agree
// with.
type runLibFixture struct {
	Beads []struct {
		ID           string            `json:"id"`
		Title        string            `json:"title"`
		Status       string            `json:"status"`
		IssueType    string            `json:"issue_type"`
		Metadata     map[string]string `json:"metadata"`
		Dependencies []struct {
			DependsOnID string `json:"depends_on_id"`
			Type        string `json:"type"`
		} `json:"dependencies"`
	} `json:"beads"`
	Cases []struct {
		Name string `json:"name"`
		Verb string `json:"verb"`
		Arg  string `json:"arg"`
		Runs []struct {
			Root   string `json:"root"`
			Convoy string `json:"convoy"`
			Bead   string `json:"bead"`
			Live   bool   `json:"live"`
		} `json:"runs"`
	} `json:"cases"`
}

// fixtureStore puts the run-lib fixture's store in a fake.
func fixtureStore(t *testing.T) (*fake.Store, runLibFixture) {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join("..", "..", "..", "assets", "scripts", "run-lib.fixture.json"))
	if err != nil {
		t.Fatalf("read the run-lib fixture: %v", err)
	}
	var fx runLibFixture
	if err := json.Unmarshal(raw, &fx); err != nil {
		t.Fatalf("parse the run-lib fixture: %v", err)
	}
	s := fake.New()
	for _, b := range fx.Beads {
		var edges []gcbd.Edge
		for _, d := range b.Dependencies {
			edges = append(edges, gcbd.Edge{Type: d.Type, ID: d.DependsOnID})
		}
		s.Put(fake.Bead{ID: b.ID, Title: b.Title, Status: b.Status, IssueType: b.IssueType, Metadata: b.Metadata, Edges: edges})
	}
	return s, fx
}

// The Go copy reads every live run, as run-lib.sh's map verb does, so over the
// fixture's store it names the runs the map case names, and for each runs case
// the live runs the case names for its bead.
func TestLiveRunsAgreeWithRunLibFixture(t *testing.T) {
	s, fx := fixtureStore(t)
	runs, err := liveRuns(ledger.New(s))
	if err != nil {
		t.Fatal(err)
	}
	got := func(bead string) []string {
		var out []string
		for _, r := range runs {
			if bead == "" || r.bead == bead {
				out = append(out, r.root+"/"+r.convoy+"/"+r.bead)
			}
		}
		return out
	}
	checked := 0
	for _, c := range fx.Cases {
		if c.Verb != "map" && c.Verb != "runs" {
			continue
		}
		var want []string
		for _, r := range c.Runs {
			if r.Live {
				want = append(want, r.Root+"/"+r.Convoy+"/"+r.Bead)
			}
		}
		slices.Sort(want)
		if c.Verb == "runs" && c.Arg == "" {
			t.Fatalf("%s: a runs case names no bead", c.Name)
		}
		if g := got(c.Arg); !slices.Equal(g, want) {
			t.Errorf("%s: the Go copy reads %v, the fixture names %v", c.Name, g, want)
		}
		checked++
	}
	if checked < 2 {
		t.Fatalf("the fixture carries %d map and runs cases; the copy agreed with none worth the name", checked)
	}
}

// A live run has passed load-context once none of its open steps is at
// load-context, so the fixture's root-a1, whose load-context step is still in
// progress, has not, and a root with no such step has.
func TestPastLoadContextReadsTheRunsOpenSteps(t *testing.T) {
	s, _ := fixtureStore(t)
	l := ledger.New(s)
	if past, err := pastLoadContext(l, "root-a1"); err != nil || past {
		t.Errorf("root-a1, its load-context step in progress = %v, %v; want not past", past, err)
	}
	if past, err := pastLoadContext(l, "root-x"); err != nil || !past {
		t.Errorf("root-x, with no step at load-context = %v, %v; want past", past, err)
	}
	s.Put(fake.Bead{ID: "step-a1", Status: "closed", Metadata: map[string]string{"gc.root_bead_id": "root-a1", "gc.step_ref": "mol-polecat-work.load-context"}})
	if past, err := pastLoadContext(l, "root-a1"); err != nil || !past {
		t.Errorf("root-a1, its load-context step closed = %v, %v; want past", past, err)
	}
	for _, q := range s.Finds() {
		if q.Key == "gc.root_bead_id" && q.Closed {
			t.Errorf("the steps read %+v reads closed steps, which say nothing about where the run is", q)
		}
	}
}

// IsRootOrStep reads a run's root, as isRoot reads one, and a step poured
// under a root as a run's own beads, and no other bead.
func TestIsRootOrStepReadsARunsOwnBeads(t *testing.T) {
	s := fake.New()
	for _, b := range []fake.Bead{
		{ID: "graph", Status: "open", IssueType: "task", Metadata: map[string]string{"gc.formula_contract": "graph.v2"}},
		{ID: "flow", Status: "open", IssueType: "task", Metadata: map[string]string{"gc.kind": "workflow"}},
		{ID: "mol", Status: "open", IssueType: "molecule"},
		{ID: "step", Status: "open", IssueType: "task", Metadata: map[string]string{"gc.root_bead_id": "graph"}},
		{ID: "work", Status: "open", IssueType: "task", Metadata: map[string]string{"gc.routed_to": "human"}},
		{ID: "convoy", Status: "open", IssueType: "convoy"},
	} {
		s.Put(b)
	}
	recs, err := ledger.New(s).Find(ledger.Every())
	if err != nil {
		t.Fatal(err)
	}
	var own []string
	for _, r := range recs {
		if IsRootOrStep(r) {
			own = append(own, r.ID)
		}
	}
	if want := []string{"flow", "graph", "mol", "step"}; !slices.Equal(own, want) {
		t.Errorf("a run's own beads = %v, want %v", own, want)
	}
}
