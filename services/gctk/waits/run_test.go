package waits

import (
	"encoding/json"
	"errors"
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
		Runs []Run  `json:"runs"`
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

// The Go copy reads every live run, as run-lib.sh's map verb does, and every
// run that works one bead, live or not, as its runs verb does, so over the
// fixture's store LiveRuns names the runs each map case names and RunsOf the
// runs each runs case names for its bead, each with its convoy, its bead, its
// formula and its liveness.
func TestRunsAgreeWithRunLibFixture(t *testing.T) {
	s, fx := fixtureStore(t)
	l := ledger.New(s)
	checked := 0
	for _, c := range fx.Cases {
		var got []Run
		var err error
		switch c.Verb {
		case "map":
			got, err = LiveRuns(l)
		case "runs":
			if c.Arg == "" {
				t.Fatalf("%s: a runs case names no bead", c.Name)
			}
			got, err = RunsOf(l, c.Arg)
		default:
			continue
		}
		if err != nil {
			t.Fatalf("%s: %v", c.Name, err)
		}
		if !slices.Equal(got, c.Runs) && !(len(got) == 0 && len(c.Runs) == 0) {
			t.Errorf("%s: the Go copy reads %+v, the fixture names %+v", c.Name, got, c.Runs)
		}
		checked++
	}
	if checked < 2 {
		t.Fatalf("the fixture carries %d map and runs cases; the copy agreed with none worth the name", checked)
	}
}

// A bead the store does not hold has no runs to read: RunsOf fails, as
// run-lib.sh's runs verb fails on bd's refusal to resolve it, rather than
// answer none.
func TestRunsOfFailsForABeadTheStoreDoesNotHold(t *testing.T) {
	s, _ := fixtureStore(t)
	if runs, err := RunsOf(ledger.New(s), "ghost-1"); err == nil {
		t.Errorf("RunsOf(ghost-1) = %+v, want the store's refusal", runs)
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

// A run's holders are the assignees of its members that are not closed, the
// root's own among them, each once, and a closed member's assignee is none.
func TestRunHoldersAreTheAssigneesOfItsLiveMembers(t *testing.T) {
	s := fake.New()
	s.Put(fake.Bead{ID: "root-1", Status: "in_progress", Assignee: "rig/control", Metadata: map[string]string{"gc.kind": "workflow"}})
	s.Put(fake.Bead{ID: "st-load", Status: "closed", Assignee: "polecat-done", Metadata: map[string]string{"gc.root_bead_id": "root-1"}})
	s.Put(fake.Bead{ID: "st-impl", Status: "in_progress", Assignee: "polecat-2", Metadata: map[string]string{"gc.root_bead_id": "root-1"}})
	s.Put(fake.Bead{ID: "st-rev", Status: "open", Metadata: map[string]string{"gc.root_bead_id": "root-1"}})
	s.Put(fake.Bead{ID: "st-sub", Status: "blocked", Assignee: "polecat-2", Metadata: map[string]string{"gc.root_bead_id": "root-1"}})
	s.Put(fake.Bead{ID: "st-other", Status: "in_progress", Assignee: "polecat-9", Metadata: map[string]string{"gc.root_bead_id": "root-2"}})
	got, err := RunHolders(ledger.New(s), "root-1")
	if err != nil || !slices.Equal(got, []string{"rig/control", "polecat-2"}) {
		t.Fatalf("RunHolders = %q, %v; want the root's and the live step's assignees, each once", got, err)
	}
	s.FindErr = errors.New("the store did not answer")
	if _, err := RunHolders(ledger.New(s), "root-1"); err == nil {
		t.Fatal("a read that fails answered holders")
	}
}
