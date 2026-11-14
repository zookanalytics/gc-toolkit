package gcbd

import (
	"errors"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/gcbdtest"
)

// The adapter's acceptance test runs the bd the city runs against a scratch
// store (gcbdtest), so it pins the answer that bd gives for each kind of wait,
// each gate included, and the beads it marks blocked
// (docs/gctk-architecture.md, "The adapters"). It runs only when
// GCTK_STORE_ACCEPTANCE=1 asks for it:
//
//	GCTK_STORE_ACCEPTANCE=1 go test ./internal/gcbd -run TestStoreAcceptance -v
//
// Each case builds its beads, then compares the adapter's answer with what the
// store does.

func TestStoreAcceptance(t *testing.T) {
	if !gcbdtest.Asked() {
		t.Skip("the store acceptance test runs the city's bd on a scratch store; GCTK_STORE_ACCEPTANCE=1 runs it")
	}
	s := gcbdtest.New(t, "pb")

	// A bead with a blocks edge onto an open bead.
	own, blocker := s.Create("own"), s.Create("blocker")
	s.Edge(own, blocker, EdgeBlocks, "")
	// A bead held only through its blocked parent.
	parent, parentBlocker, child := s.Create("parent"), s.Create("parent's blocker"), s.Create("child")
	s.Edge(parent, parentBlocker, EdgeBlocks, "")
	s.Edge(child, parent, EdgeParentChild, "")
	// A parentless bead on an all-children gate whose spawner closed and then
	// gained a child that is still open.
	spawner, waiter := s.Create("spawner"), s.Create("waiter")
	s.Edge(waiter, spawner, EdgeWaitsFor, "")
	s.Run("close", spawner)
	s.Edge(s.Create("spawner's child"), spawner, EdgeParentChild, "")
	// The same gate on a bead whose parent is not blocked.
	openParent, parented := s.Create("open parent"), s.Create("parented waiter")
	s.Edge(parented, openParent, EdgeParentChild, "")
	s.Edge(parented, spawner, EdgeWaitsFor, "")
	// An any-children gate one closed child has opened, on a bead held only
	// through its blocked parent.
	anySpawner, closedChild, openChild := s.Create("any spawner"), s.Create("closed child"), s.Create("open child")
	s.Edge(closedChild, anySpawner, EdgeParentChild, "")
	s.Edge(openChild, anySpawner, EdgeParentChild, "")
	s.Run("close", closedChild)
	anyWaiter := s.Create("any waiter")
	s.Edge(anyWaiter, parent, EdgeParentChild, "")
	s.Edge(anyWaiter, anySpawner, EdgeWaitsFor, `{"gate":"any-children"}`)
	// An also_blocks edge on an open spawner with no open child.
	alsoSpawner, alsoWaiter := s.Create("also spawner"), s.Create("also waiter")
	s.Edge(alsoWaiter, alsoSpawner, EdgeWaitsFor, `{"also_blocks":"true"}`)
	// Two beads with two parents each, a blocked one and one that holds nothing.
	// bd's listing names the parent its own query for a bead's parents returns
	// last, so the blocked parent is that one under the first bead, and the
	// other one under the second.
	type twoParented struct{ id, blocked, free, names string }
	var twoParents []twoParented
	for _, blockedLast := range []bool{true, false} {
		kid := s.Create("two parents")
		s.Edge(kid, s.Create("a parent"), EdgeParentChild, "")
		s.Edge(kid, s.Create("another parent"), EdgeParentChild, "")
		rows := s.ParentRows(kid)
		if len(rows) != 2 {
			t.Fatalf("bd's parent query for %s returned %v, want its two parents", kid, rows)
		}
		x := twoParented{id: kid, blocked: rows[1], free: rows[0], names: rows[1]}
		if !blockedLast {
			x.blocked, x.free = rows[0], rows[1]
		}
		s.Edge(x.blocked, s.Create("a parent's blocker"), EdgeBlocks, "")
		twoParents = append(twoParents, x)
	}

	// What the store itself answers.
	listed, ready := s.Listing(), s.Ready()
	for _, tc := range []struct {
		name, id string
		listed   []string // nil: the listing leaves the bead out
	}{
		{"a blocks edge names its blocker", own, []string{blocker}},
		{"a bead held through its parent names the parent", child, []string{parent}},
		{"a parentless waiter on a closed spawner's gate is left out", waiter, nil},
		{"the same gate under an open parent names that parent", parented, []string{openParent}},
		{"an opened any-children gate under a blocked parent names the open spawner", anyWaiter, []string{anySpawner}},
		{"an also_blocks edge names its open spawner", alsoWaiter, []string{alsoSpawner}},
	} {
		if got, ok := listed[tc.id]; !slices.Equal(got, tc.listed) || ok != (tc.listed != nil) {
			t.Errorf("bd blocked: %s: got %v (listed %v), want %v", tc.name, got, ok, tc.listed)
		}
		if slices.Contains(ready, tc.id) {
			t.Errorf("bd ready offers %s (%s)", tc.id, tc.name)
		}
	}
	for _, x := range twoParents {
		if got := listed[x.id]; !slices.Equal(got, []string{x.names}) {
			t.Errorf("bd blocked: a bead with two parents, %s blocked and %s holding nothing: got %v, want %s, the parent its query returns last", x.blocked, x.free, got, x.names)
		}
		if slices.Contains(ready, x.id) {
			t.Errorf("bd ready offers %s, which its blocked parent %s holds", x.id, x.blocked)
		}
	}

	// What the adapter answers, through the same gc bd seam the city's reads
	// take: a gc on PATH that hands bd its arguments.
	s.Enter(t, "")
	c := &Client{bin: "gc"}
	ids := []string{own, child, waiter, parented, anyWaiter, alsoWaiter, parent}
	for _, x := range twoParents {
		ids = append(ids, x.id, x.blocked)
	}
	rows, err := c.Rows(ids)
	if err != nil {
		t.Fatal(err)
	}
	set, err := c.Blocked()
	if err != nil {
		t.Fatal(err)
	}
	byID := map[string]*Bead{}
	for i := range rows {
		byID[rows[i].ID] = &rows[i]
	}
	if b, err := set.Answer(byID[own]); err != nil || !slices.Equal(b.On, []string{blocker}) {
		t.Errorf("adapter: a blocks edge = %+v, %v; want blocked on %s", b, err, blocker)
	}
	if b, err := set.Answer(byID[child]); err != nil || b.Through != parent {
		t.Errorf("adapter: held through a parent = %+v, %v; want held through %s", b, err, parent)
	}
	for _, x := range twoParents {
		if b, err := set.Answer(byID[x.id]); err != nil || b.Through != x.blocked {
			t.Errorf("adapter: a bead with two parents = %+v, %v; want held through %s, its blocked parent", b, err, x.blocked)
		}
		if set.marked[x.free] {
			t.Errorf("the marks read names %s, a parent that holds nothing", x.free)
		}
	}
	for _, id := range []string{waiter, parented, anyWaiter, alsoWaiter} {
		_, err := set.Answer(byID[id])
		var wf *WaitsForError
		var re *ReadError
		if !errors.As(err, &wf) || errors.As(err, &re) {
			t.Errorf("adapter: %s = %v; want the waits-for error and not a read error", id, err)
		}
	}
	// The marks read names every bead a case holds, the one the listing leaves
	// out among them.
	for _, id := range ids {
		if !set.marked[id] {
			t.Errorf("the marks read does not name %s", id)
		}
	}
	// bd's show leaves out a bead the store does not hold and exits 0 beside one
	// it holds, and fails when it holds none named, so the adapter's row read
	// fails either way, naming the bead in the first case and bd's error in the
	// second.
	if out, err := s.Try("show", own, "pb-gone", "--json"); err != nil || strings.Contains(out, `"id": "pb-gone"`) {
		t.Errorf("bd show of a held bead beside one it does not hold = %v: %s; want exit 0 and no row for pb-gone", err, out)
	}
	var re *ReadError
	if _, err := c.Rows([]string{own, "pb-gone"}); !errors.As(err, &re) || re.ID != "pb-gone" {
		t.Errorf("adapter: rows with a bead the store does not hold = %v; want a read error naming pb-gone", err)
	}
	if _, err := c.Rows([]string{"pb-gone"}); !errors.As(err, &re) || !strings.Contains(err.Error(), "no issues found") {
		t.Errorf("adapter: rows of only a bead the store does not hold = %v; want a read error carrying bd's error", err)
	}

	// bd's close rule: a blocker of a bead's own refuses the close, and a bead
	// held only through its parent closes.
	if _, err := s.Try("close", own); err == nil {
		t.Errorf("bd closed %s, which an open blocker of its own holds", own)
	}
	if out, err := s.Try("close", child); err != nil {
		t.Errorf("bd refused to close %s, held only through its parent: %s", child, out)
	}
}
