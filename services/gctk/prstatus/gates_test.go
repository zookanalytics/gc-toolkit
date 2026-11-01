package prstatus

import (
	"errors"
	"fmt"
	"slices"
	"testing"
)

func gate(id string) Blocker {
	return Blocker{ID: id, Title: "ask " + id, Status: "open", IssueType: "gate", AwaitType: "human"}
}

func task(id string) Blocker {
	return Blocker{ID: id, Status: "open", IssueType: "task"}
}

func closed(b Blocker) Blocker {
	b.Status = "closed"
	return b
}

// graph is a store's `blocks` edges, as a read answers them. Each read is
// recorded, so a test can tell what the walk asked for and how often.
type graph struct {
	edges map[string][]Blocker
	reads [][]string
}

func (g *graph) read(ids []string) (map[string][]Blocker, error) {
	g.reads = append(g.reads, slices.Clone(ids))
	out := make(map[string][]Blocker, len(ids))
	for _, id := range ids {
		out[id] = g.edges[id]
	}
	return out, nil
}

func gateIDs(gates []Blocker) []string {
	out := []string{}
	for _, g := range gates {
		out = append(out, g.ID)
	}
	return out
}

func TestHoldingGates(t *testing.T) {
	for _, tc := range []struct {
		name  string
		edges map[string][]Blocker
		want  []string
	}{
		{"nothing blocks the bead", nil, []string{}},
		{"a gate on the bead", map[string][]Blocker{"a": {gate("g")}}, []string{"g"}},
		{"a gate on a rework the bead waits on",
			map[string][]Blocker{"a": {task("rw")}, "rw": {gate("g")}}, []string{"g"}},
		{"a gate two beads away",
			map[string][]Blocker{"a": {task("rw")}, "rw": {task("t")}, "t": {gate("g")}}, []string{"g"}},
		{"gates nearest first",
			map[string][]Blocker{"a": {task("rw"), gate("near")}, "rw": {gate("far")}}, []string{"near", "far"}},
		{"a gate reached by two paths reads once",
			map[string][]Blocker{"a": {task("x"), task("y")}, "x": {gate("g")}, "y": {gate("g")}}, []string{"g"}},
		{"a closed gate holds nothing", map[string][]Blocker{"a": {closed(gate("g"))}}, []string{}},
		{"a gate behind a closed blocker holds nothing",
			map[string][]Blocker{"a": {closed(task("rw"))}, "rw": {gate("g")}}, []string{}},
		{"a gate that awaits no person holds nothing itself",
			map[string][]Blocker{"a": {{ID: "t", Status: "open", IssueType: "gate", AwaitType: "timer"}}}, []string{}},
		{"an open gate that awaits no person is still walked through",
			map[string][]Blocker{"a": {{ID: "t", Status: "open", IssueType: "gate", AwaitType: "timer"}}, "t": {gate("g")}}, []string{"g"}},
		{"what a human gate waits on is named beside it",
			map[string][]Blocker{"a": {gate("g")}, "g": {task("t")}, "t": {gate("behind")}}, []string{"g", "behind"}},
		{"a blocker with no status reads open",
			map[string][]Blocker{"a": {{ID: "rw"}}, "rw": {{ID: "g", IssueType: "gate", AwaitType: "human"}}}, []string{"g"}},
		{"status and issue type read in any case",
			map[string][]Blocker{"a": {{ID: "g", Status: "IN_PROGRESS", IssueType: "GATE", AwaitType: "human"},
				{ID: "c", Status: "CLOSED", IssueType: "gate", AwaitType: "human"}}}, []string{"g"}},
		{"a cycle ends",
			map[string][]Blocker{"a": {task("b")}, "b": {task("a"), gate("g")}}, []string{"g"}},
		{"a bead that blocks itself ends", map[string][]Blocker{"a": {task("a")}}, []string{}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			g := &graph{edges: tc.edges}
			got, err := HoldingGates([]string{"a"}, g.read)
			if err != nil {
				t.Fatal(err)
			}
			if ids := gateIDs(got["a"]); !slices.Equal(ids, tc.want) {
				t.Errorf("gates of a = %v, want %v", ids, tc.want)
			}
		})
	}
}

// The gate comes back with the fields a caller names it by.
func TestHoldingGatesKeepTheTitle(t *testing.T) {
	g := &graph{edges: map[string][]Blocker{"a": {task("rw")}, "rw": {gate("g")}}}
	got, err := HoldingGates([]string{"a"}, g.read)
	if err != nil {
		t.Fatal(err)
	}
	if len(got["a"]) != 1 || got["a"][0].Title != "ask g" {
		t.Errorf("gates of a = %+v, want the one titled %q", got["a"], "ask g")
	}
}

// One walk over several anchors reads each level once and each bead once, and a
// gate holds only the roots that reach it.
func TestHoldingGatesOverManyRoots(t *testing.T) {
	g := &graph{edges: map[string][]Blocker{
		"a":  {task("rw")},
		"b":  {task("rw"), gate("own")},
		"c":  {task("other")},
		"rw": {gate("shared")},
	}}
	got, err := HoldingGates([]string{"a", "b", "c", "b"}, g.read)
	if err != nil {
		t.Fatal(err)
	}
	for root, want := range map[string][]string{"a": {"shared"}, "b": {"own", "shared"}, "c": {}} {
		if ids := gateIDs(got[root]); !slices.Equal(ids, want) {
			t.Errorf("gates of %s = %v, want %v", root, ids, want)
		}
	}
	read := map[string]int{}
	for _, ids := range g.reads {
		for _, id := range ids {
			read[id]++
		}
	}
	for id, n := range read {
		if n != 1 {
			t.Errorf("%s read %d times, want once: %v", id, n, g.reads)
		}
	}
	// a, b and c; then own, rw and other; then shared.
	if len(g.reads) != 3 {
		t.Errorf("%d reads, want one per level: %v", len(g.reads), g.reads)
	}
}

func TestHoldingGatesFailClosed(t *testing.T) {
	t.Run("a read that fails answers nothing", func(t *testing.T) {
		boom := errors.New("store down")
		calls := 0
		got, err := HoldingGates([]string{"a"}, func(ids []string) (map[string][]Blocker, error) {
			calls++
			if calls == 2 {
				return nil, boom
			}
			return map[string][]Blocker{"a": {gate("near"), task("rw")}}, nil
		})
		if !errors.Is(err, boom) || got != nil {
			t.Errorf("(%v, %v), want (nil, the read's error): the gates past it are unknown", got, err)
		}
	})

	t.Run("a chain past the bound reads as unresolved", func(t *testing.T) {
		g := &graph{edges: map[string][]Blocker{}}
		for i := 0; i <= walkDepth; i++ {
			g.edges[fmt.Sprintf("n%d", i)] = []Blocker{task(fmt.Sprintf("n%d", i+1))}
		}
		got, err := HoldingGates([]string{"n0"}, g.read)
		if !errors.Is(err, ErrWalkBound) || got != nil {
			t.Errorf("(%v, %v), want (nil, ErrWalkBound)", got, err)
		}
		if len(g.reads) != walkDepth {
			t.Errorf("%d reads, want the bound's %d", len(g.reads), walkDepth)
		}
	})

	t.Run("a chain at the bound reads whole", func(t *testing.T) {
		g := &graph{edges: map[string][]Blocker{}}
		for i := 0; i < walkDepth-1; i++ {
			g.edges[fmt.Sprintf("n%d", i)] = []Blocker{task(fmt.Sprintf("n%d", i+1))}
		}
		g.edges[fmt.Sprintf("n%d", walkDepth-1)] = nil
		if _, err := HoldingGates([]string{"n0"}, g.read); err != nil {
			t.Errorf("a walk of %d levels: %v", walkDepth, err)
		}
	})

	t.Run("a fan past the bound reads as unresolved", func(t *testing.T) {
		wide := make([]Blocker, 0, walkBeads+1)
		for i := 0; i <= walkBeads; i++ {
			wide = append(wide, task(fmt.Sprintf("t%d", i)))
		}
		g := &graph{edges: map[string][]Blocker{"a": wide}}
		if _, err := HoldingGates([]string{"a"}, g.read); !errors.Is(err, ErrWalkBound) {
			t.Errorf("err = %v, want ErrWalkBound", err)
		}
	})

	t.Run("the fan bound counts per root", func(t *testing.T) {
		wide := make([]Blocker, 0, walkBeads)
		for i := 0; i < walkBeads; i++ {
			wide = append(wide, task(fmt.Sprintf("t%d", i)))
		}
		other := make([]Blocker, 0, walkBeads)
		for i := 0; i < walkBeads-2; i++ {
			other = append(other, task(fmt.Sprintf("u%d", i)))
		}
		g := &graph{edges: map[string][]Blocker{"a": wide, "b": other}}
		if _, err := HoldingGates([]string{"a", "b"}, g.read); err != nil {
			t.Errorf("two roots inside their bound: %v", err)
		}
	})
}
