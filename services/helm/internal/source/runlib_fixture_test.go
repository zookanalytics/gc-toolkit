package source

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"testing"

	"github.com/steveyegge/beads"
)

// runLibFixture is assets/scripts/run-lib.fixture.json: a store in the shape
// `bd list --json` prints, and the cases every copy of the run rule must agree
// with.
type runLibFixture struct {
	Beads []struct {
		ID           string          `json:"id"`
		Title        string          `json:"title"`
		Status       string          `json:"status"`
		IssueType    string          `json:"issue_type"`
		Metadata     json.RawMessage `json:"metadata"`
		Dependencies []struct {
			DependsOnID string `json:"depends_on_id"`
			Type        string `json:"type"`
		} `json:"dependencies"`
	} `json:"beads"`
	Cases []struct {
		Name string      `json:"name"`
		Verb string      `json:"verb"`
		Arg  string      `json:"arg"`
		Runs []runLibRun `json:"runs"`
	} `json:"cases"`
}

// runLibRun is one run as the fixture names it. The board reads no formula, so
// a comparison leaves it out.
type runLibRun struct {
	Root   string `json:"root"`
	Convoy string `json:"convoy"`
	Bead   string `json:"bead"`
	Live   bool   `json:"live"`
}

// TestWorkflowRootsAgreeWithRunLibFixture runs the fixture's map of every live
// run through workflowRoots over the fixture's store. The Go copy reads the
// live roots, the same statuses the case holds, so each run it names must be one
// the case names, with the same convoy and bead, and none may be missing.
func TestWorkflowRootsAgreeWithRunLibFixture(t *testing.T) {
	raw, err := os.ReadFile(filepath.Join("..", "..", "..", "..", "assets", "scripts", "run-lib.fixture.json"))
	if err != nil {
		t.Fatalf("read the run-lib fixture: %v", err)
	}
	var fx runLibFixture
	if err := json.Unmarshal(raw, &fx); err != nil {
		t.Fatalf("parse the run-lib fixture: %v", err)
	}

	st := &fakeStore{
		issues:   map[string][]*beads.Issue{},
		depsDown: map[string][]*beads.IssueWithDependencyMetadata{},
	}
	for _, b := range fx.Beads {
		st.issues[b.IssueType] = append(st.issues[b.IssueType], &beads.Issue{
			ID:        b.ID,
			Title:     b.Title,
			Status:    beads.Status(b.Status),
			IssueType: beads.IssueType(b.IssueType),
			Metadata:  b.Metadata,
		})
		for _, d := range b.Dependencies {
			st.depsDown[b.ID] = append(st.depsDown[b.ID], withDepType(child(d.DependsOnID, "open", testNow, ""), d.Type))
		}
	}

	var want []runLibRun
	found := false
	for _, c := range fx.Cases {
		if c.Verb == "map" && c.Arg == "" {
			want, found = c.Runs, true
		}
	}
	if !found || len(want) == 0 {
		t.Fatalf("the run-lib fixture carries no map case of the live runs")
	}

	g := &gatherState{rigByPrefix: map[string]string{}}
	roots := (&BeadsSource{}).workflowRoots(context.Background(), st, rigRef{name: "fixture"}, g)
	if g.partial {
		t.Fatalf("the fixture gather went partial: %v", g.partialErrs)
	}
	got := make([]runLibRun, 0, len(roots))
	for _, r := range roots {
		got = append(got, runLibRun{Root: r.rootID, Convoy: r.convoyID, Bead: r.member, Live: true})
	}
	sort.Slice(got, func(i, j int) bool { return got[i].Root < got[j].Root })
	sort.Slice(want, func(i, j int) bool { return want[i].Root < want[j].Root })

	if len(got) != len(want) {
		t.Fatalf("the Go copy reads %d live runs, the fixture names %d:\n got  %+v\n want %+v", len(got), len(want), got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("run %d: the Go copy reads %+v, the fixture names %+v", i, got[i], want[i])
		}
	}
}
