package waits_test

import (
	"encoding/json"
	"errors"
	"reflect"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// The fake holds none of the store's rules: each test sets what the store's
// blocked listing names and which beads it marks blocked, as the bd the city
// runs answers the case (specs/tk-ssm8qns.2/blocked-census.md, "The store's
// rules"), and checks what waits makes of that answer.

type bead = fake.Bead

func edge(typ, id, status string) gcbd.Edge { return gcbd.Edge{Type: typ, ID: id, Status: status} }

func landed(typ, id, at string) gcbd.Edge {
	return gcbd.Edge{Type: typ, ID: id, Status: "closed", ClosedAt: at}
}

// parked is a store with an epic its own gate holds, the shape a park takes:
// the epic blocks on an open gate, and the store holds each bead under the epic
// through it.
func parked() *fake.Store {
	s := fake.New()
	s.Put(bead{ID: "gate", Status: "open", IssueType: "gate"})
	s.Put(bead{ID: "epic", Status: "open", IssueType: "epic", Edges: []gcbd.Edge{edge(gcbd.EdgeBlocks, "gate", "open")}})
	s.List("epic", "gate")
	s.Mark("epic")
	return s
}

// under puts b under the parked epic, which the store holds it through.
func under(s *fake.Store, b bead) {
	b.Edges = append(b.Edges, edge(gcbd.EdgeParentChild, "epic", "open"))
	s.Put(b)
	s.List(b.ID, "epic")
	s.Mark(b.ID)
}

func holdsOf(t *testing.T, s *fake.Store, id string) waits.Holds {
	t.Helper()
	snap, err := waits.Read(ledger.New(s), id)
	if err != nil {
		t.Fatalf("Read(%s): %v", id, err)
	}
	h, err := snap.Holds(id)
	if err != nil {
		t.Fatalf("Holds(%s): %v", id, err)
	}
	return h
}

func waitIDs(ws []waits.Wait) []string {
	out := []string{}
	for _, w := range ws {
		out = append(out, w.ID)
	}
	return out
}

// Each status the bead read answers with.
func TestEachStatus(t *testing.T) {
	s := parked()
	s.Put(bead{ID: "blocker", Status: "open", Title: "the work it waits on"})
	s.Put(bead{ID: "own", Status: "open", Edges: []gcbd.Edge{edge(gcbd.EdgeBlocks, "blocker", "open")}})
	s.List("own", "blocker")
	s.Mark("own")
	under(s, bead{ID: "member", Status: "open"})
	s.Put(bead{ID: "spawner", Status: "closed"})
	s.Put(bead{ID: "waiter", Status: "open", Edges: []gcbd.Edge{landed(gcbd.EdgeWaitsFor, "spawner", "2026-11-08T10:00:00Z")}})
	s.Mark("waiter")
	s.Put(bead{ID: "free", Status: "open"})

	for _, tc := range []struct {
		id     string
		status waits.Status
		waits  []waits.Wait
	}{
		{"own", waits.Blocked, []waits.Wait{{ID: "blocker", Type: "blocks", Title: "the work it waits on", Status: "open"}}},
		{"member", waits.Held, []waits.Wait{{ID: "gate", Type: "blocks", Status: "open", IssueType: "gate", Ancestor: "epic"}}},
		{"waiter", waits.Unjudged, []waits.Wait{{ID: "spawner", Type: "waits-for", Status: "closed"}}},
		{"free", waits.Clear, []waits.Wait{}},
	} {
		h := holdsOf(t, s, tc.id)
		if h.Status != tc.status || !reflect.DeepEqual(h.Waits, tc.waits) {
			t.Errorf("%s = %s on %+v; want %s on %+v", tc.id, h.Status, h.Waits, tc.status, tc.waits)
		}
	}
}

// Every row of the census's disagreement table, "Where the copies disagree, and
// the one rule's answer", against the store's answer for the case.
func TestTheCensusDisagreements(t *testing.T) {
	type check struct {
		status  waits.Status
		waits   []string
		pending []string
	}
	for _, tc := range []struct {
		name  string
		setup func(*fake.Store)
		id    string
		want  check
	}{
		{
			// bd resolves a pinned blocker, so it neither lists nor marks the
			// bead, though the bead's own edge reads a status that is not closed.
			name: "a pinned blocker is resolved",
			setup: func(s *fake.Store) {
				s.Put(bead{ID: "pinned", Status: "pinned"})
				s.Put(bead{ID: "b", Status: "open", Edges: []gcbd.Edge{edge(gcbd.EdgeBlocks, "pinned", "pinned")}})
			},
			id: "b", want: check{waits.Clear, []string{}, []string{}},
		},
		{
			name:  "a blocker on an ancestor holds work that has not started",
			setup: func(s *fake.Store) { under(s, bead{ID: "b", Status: "open"}) },
			id:    "b", want: check{waits.Held, []string{"gate"}, []string{}},
		},
		{
			name:  "work in flight is held only by its own waits",
			setup: func(s *fake.Store) { under(s, bead{ID: "b", Status: "in_progress"}) },
			id:    "b", want: check{waits.Clear, []string{}, []string{}},
		},
		{
			// The gate is a demand on the epic, a question put to a person. It
			// holds the epic's unstarted work as every gate does.
			name: "a demand gate on an ancestor holds work that has not started",
			setup: func(s *fake.Store) {
				s.Put(bead{ID: "demand", Status: "open", IssueType: "gate", Metadata: map[string]string{"await_type": "human"}})
				s.Put(bead{ID: "asked", Status: "open", IssueType: "epic", Edges: []gcbd.Edge{edge(gcbd.EdgeBlocks, "demand", "open")}})
				s.List("asked", "demand")
				s.Mark("asked")
				s.Put(bead{ID: "b", Status: "open", Metadata: map[string]string{"gc.dispatch_when_ready": "rig/rig.polecat"},
					Edges: []gcbd.Edge{edge(gcbd.EdgeParentChild, "asked", "open")}})
				s.List("b", "asked")
				s.Mark("b")
			},
			id: "b", want: check{waits.Held, []string{"demand"}, []string{}},
		},
		{
			// bd's edge rule joins on the far bead's row, so an edge onto an id
			// the store does not hold blocks nothing.
			name: "an edge onto a bead in another store holds nothing",
			setup: func(s *fake.Store) {
				s.Put(bead{ID: "b", Status: "open", Edges: []gcbd.Edge{edge(gcbd.EdgeBlocks, "xx-1", "open")}})
			},
			id: "b", want: check{waits.Clear, []string{}, []string{}},
		},
		{
			name: "a blocker at hooked holds",
			setup: func(s *fake.Store) {
				s.Put(bead{ID: "hooked-blocker", Status: "hooked"})
				s.Put(bead{ID: "b", Status: "open", Edges: []gcbd.Edge{edge(gcbd.EdgeBlocks, "hooked-blocker", "hooked")}})
				s.List("b", "hooked-blocker")
				s.Mark("b")
			},
			id: "b", want: check{waits.Blocked, []string{"hooked-blocker"}, []string{"hooked-blocker"}},
		},
		{
			name: "a blocker at in_progress holds",
			setup: func(s *fake.Store) {
				s.Put(bead{ID: "running", Status: "in_progress"})
				s.Put(bead{ID: "b", Status: "open", Edges: []gcbd.Edge{edge(gcbd.EdgeBlocks, "running", "in_progress")}})
				s.List("b", "running")
				s.Mark("b")
			},
			id: "b", want: check{waits.Blocked, []string{"running"}, []string{"running"}},
		},
		{
			name:  "a bead whose own status is hooked is in flight, so an ancestor's wait does not hold it",
			setup: func(s *fake.Store) { under(s, bead{ID: "b", Status: "hooked"}) },
			id:    "b", want: check{waits.Clear, []string{}, []string{}},
		},
		{
			name: "a bead whose own status is hooked is held by its own waits",
			setup: func(s *fake.Store) {
				s.Put(bead{ID: "blocker", Status: "open"})
				s.Put(bead{ID: "b", Status: "hooked", Edges: []gcbd.Edge{edge(gcbd.EdgeBlocks, "blocker", "open")}})
				s.List("b", "blocker")
				s.Mark("b")
			},
			id: "b", want: check{waits.Blocked, []string{"blocker"}, []string{"blocker"}},
		},
		{
			// Only closed and pinned resolve a blocker, so a blocker at a status
			// outside the live set still holds.
			name: "a blocker at a custom status holds",
			setup: func(s *fake.Store) {
				s.Put(bead{ID: "custom", Status: "review"})
				s.Put(bead{ID: "b", Status: "open", Edges: []gcbd.Edge{edge(gcbd.EdgeBlocks, "custom", "review")}})
				s.List("b", "custom")
				s.Mark("b")
			},
			id: "b", want: check{waits.Blocked, []string{"custom"}, []string{"custom"}},
		},
		{
			name: "a closed blocker is resolved",
			setup: func(s *fake.Store) {
				s.Put(bead{ID: "done", Status: "closed"})
				s.Put(bead{ID: "b", Status: "open", Edges: []gcbd.Edge{landed(gcbd.EdgeBlocks, "done", "2026-11-01T00:00:00Z")}})
			},
			id: "b", want: check{waits.Clear, []string{}, []string{}},
		},
		{
			name: "a conditional-blocks edge holds where the store says it does",
			setup: func(s *fake.Store) {
				s.Put(bead{ID: "first", Status: "open"})
				s.Put(bead{ID: "b", Status: "open", Edges: []gcbd.Edge{edge(gcbd.EdgeConditionalBlocks, "first", "open")}})
				s.List("b", "first")
				s.Mark("b")
			},
			id: "b", want: check{waits.Blocked, []string{"first"}, []string{"first"}},
		},
		{
			// An open child holds its parent's merge, which is the merge's own
			// rule, not a wait.
			name: "an open child is no wait of its parent",
			setup: func(s *fake.Store) {
				s.Put(bead{ID: "b", Status: "open"})
				s.Put(bead{ID: "kid", Status: "open", Edges: []gcbd.Edge{edge(gcbd.EdgeParentChild, "b", "open")}})
			},
			id: "b", want: check{waits.Clear, []string{}, []string{}},
		},
		{
			name: "an until edge is no wait",
			setup: func(s *fake.Store) {
				s.Put(bead{ID: "target", Status: "open"})
				s.Put(bead{ID: "b", Status: "open", Edges: []gcbd.Edge{edge("until", "target", "open")}})
			},
			id: "b", want: check{waits.Clear, []string{}, []string{}},
		},
		{
			// The listing judges the edge by the spawner's status and names the
			// bead's parent, which holds nothing.
			name: "a waits-for edge of its own reads unjudged, whatever the listing names",
			setup: func(s *fake.Store) {
				s.Put(bead{ID: "free-parent", Status: "open"})
				s.Put(bead{ID: "spawner", Status: "closed"})
				s.Put(bead{ID: "b", Status: "open", Edges: []gcbd.Edge{
					edge(gcbd.EdgeParentChild, "free-parent", "open"),
					landed(gcbd.EdgeWaitsFor, "spawner", "2026-11-08T09:00:00Z"),
				}})
				s.List("b", "free-parent")
				s.Mark("b")
			},
			id: "b", want: check{waits.Unjudged, []string{"spawner"}, []string{"spawner"}},
		},
		{
			name: "a waits-for edge of its own reads unjudged when the listing leaves the bead out",
			setup: func(s *fake.Store) {
				s.Put(bead{ID: "spawner", Status: "closed"})
				s.Put(bead{ID: "b", Status: "open", Edges: []gcbd.Edge{landed(gcbd.EdgeWaitsFor, "spawner", "2026-11-08T09:00:00Z")}})
				s.Mark("b")
			},
			id: "b", want: check{waits.Unjudged, []string{"spawner"}, []string{"spawner"}},
		},
		{
			name: "an unjudged bead's own blocks waits the listing names are pending beside its gate",
			setup: func(s *fake.Store) {
				s.Put(bead{ID: "spawner", Status: "open"})
				s.Put(bead{ID: "blocker", Status: "open"})
				s.Put(bead{ID: "b", Status: "open", Edges: []gcbd.Edge{
					edge(gcbd.EdgeWaitsFor, "spawner", "open"),
					edge(gcbd.EdgeBlocks, "blocker", "open"),
				}})
				s.List("b", "spawner", "blocker")
				s.Mark("b")
			},
			id: "b", want: check{waits.Unjudged, []string{"spawner", "blocker"}, []string{"spawner", "blocker"}},
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s := parked()
			tc.setup(s)
			h := holdsOf(t, s, tc.id)
			got := check{h.Status, waitIDs(h.Waits), waitIDs(h.Pending)}
			if !reflect.DeepEqual(got, tc.want) {
				t.Errorf("%s = %+v; want %+v", tc.id, got, tc.want)
			}
		})
	}
}

// Each condition that puts a bead in flight, by steering.md's test, takes it out
// of its ancestor's hold, and each near miss leaves it held.
func TestInFlight(t *testing.T) {
	run := func(s *fake.Store, root, convoy, rootStatus string, rootMeta map[string]string) {
		meta := map[string]string{"gc.kind": "workflow", "gc.formula_contract": "graph.v2", "gc.input_convoy_id": convoy}
		for k, v := range rootMeta {
			meta[k] = v
		}
		s.Put(bead{ID: root, Status: rootStatus, Metadata: meta})
	}
	step := func(s *fake.Store, id, root, ref, status string) {
		s.Put(bead{ID: id, Status: status, Metadata: map[string]string{"gc.root_bead_id": root, "gc.step_ref": ref}})
	}
	convoy := func(s *fake.Store, id string, tracks ...string) {
		var edges []gcbd.Edge
		for _, b := range tracks {
			edges = append(edges, edge("tracks", b, "open"))
		}
		s.Put(bead{ID: id, Status: "open", IssueType: "convoy", Edges: edges})
	}
	for _, tc := range []struct {
		name   string
		member bead
		setup  func(*fake.Store)
		flight string
	}{
		{name: "claimed, in progress", member: bead{ID: "m", Status: "in_progress"}, flight: "status in_progress"},
		{name: "claimed, hooked", member: bead{ID: "m", Status: "hooked"}, flight: "status hooked"},
		{name: "carries a branch", member: bead{ID: "m", Status: "open", Metadata: map[string]string{"branch": "polecat/m"}}, flight: "carries branch"},
		{name: "carries a merge_result", member: bead{ID: "m", Status: "open", Metadata: map[string]string{"merge_result": "merging"}}, flight: "carries merge_result"},
		{name: "carries a rejection_reason", member: bead{ID: "m", Status: "open", Metadata: map[string]string{"rejection_reason": "conflict"}}, flight: "carries rejection_reason"},
		{
			name: "a live workflow poured for it has passed load-context", member: bead{ID: "m", Status: "open"},
			setup: func(s *fake.Store) {
				convoy(s, "cv", "m")
				run(s, "root", "cv", "in_progress", nil)
				step(s, "lc", "root", "mol-polecat-work.load-context", "closed")
				step(s, "impl", "root", "mol-polecat-work.implement", "in_progress")
			},
			flight: "workflow root past load-context",
		},
		{
			name: "a live classic molecule that records it as its issue, with no load-context step", member: bead{ID: "m", Status: "open"},
			setup: func(s *fake.Store) {
				s.Put(bead{ID: "mol", Status: "open", IssueType: "molecule", Metadata: map[string]string{"gc.var.issue": "m"}})
			},
			flight: "workflow mol past load-context",
		},
		{
			name: "a live workflow still at load-context", member: bead{ID: "m", Status: "open"},
			setup: func(s *fake.Store) {
				convoy(s, "cv", "m")
				run(s, "root", "cv", "in_progress", nil)
				step(s, "lc", "root", "mol-polecat-work.load-context", "in_progress")
			},
		},
		{
			name: "a finished workflow", member: bead{ID: "m", Status: "open"},
			setup: func(s *fake.Store) {
				convoy(s, "cv", "m")
				run(s, "root", "cv", "closed", nil)
			},
		},
		{
			name: "a workflow whose convoy tracks two beads works neither", member: bead{ID: "m", Status: "open"},
			setup: func(s *fake.Store) {
				convoy(s, "cv", "m", "other")
				run(s, "root", "cv", "in_progress", nil)
			},
		},
		{
			name: "a workflow whose issue variable names another bead works none", member: bead{ID: "m", Status: "open"},
			setup: func(s *fake.Store) {
				convoy(s, "cv", "m")
				run(s, "root", "cv", "in_progress", map[string]string{"gc.var.issue": "other"})
			},
		},
		{name: "an armed bead that has not started", member: bead{ID: "m", Status: "open", Metadata: map[string]string{"gc.dispatch_when_ready": "rig/rig.polecat"}}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s := parked()
			under(s, tc.member)
			if tc.setup != nil {
				tc.setup(s)
			}
			snap, err := waits.Read(ledger.New(s), "m")
			if err != nil {
				t.Fatal(err)
			}
			why, err := snap.InFlight("m")
			if err != nil || why != tc.flight {
				t.Errorf("InFlight = %q, %v; want %q", why, err, tc.flight)
			}
			h, err := snap.Holds("m")
			want := waits.Held
			if tc.flight != "" {
				want = waits.Clear
			}
			if err != nil || h.Status != want || h.InFlight != tc.flight {
				t.Errorf("Holds = %s (in flight %q), %v; want %s", h.Status, h.InFlight, err, want)
			}
		})
	}
}

// A bead whose row shows it in flight needs no read of the runs.
func TestARowInFlightReadsNoRuns(t *testing.T) {
	s := parked()
	under(s, bead{ID: "m", Status: "open", Metadata: map[string]string{"branch": "polecat/m"}})
	if _, err := waits.Read(ledger.New(s), "m"); err != nil {
		t.Fatal(err)
	}
	for _, q := range s.Finds() {
		if q.HasKey != "" || q.Key != "" {
			t.Errorf("a bead its row shows in flight read the runs: %+v", q)
		}
	}
}

// A read that fails returns an error and never a status, and so does a bead the
// store marks blocked that its listing lost, which is never unjudged.
func TestAReadThatFailsIsAnError(t *testing.T) {
	failed := &gcbd.ReadError{Reason: "gc bd exited 1"}
	for _, tc := range []struct {
		name string
		fail func(*fake.Store)
	}{
		{"the blocked read", func(s *fake.Store) { s.BlockedErr = failed }},
		{"the listing read", func(s *fake.Store) { s.FindErr = failed }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s := parked()
			under(s, bead{ID: "m", Status: "open"})
			tc.fail(s)
			var re *ledger.ReadError
			if snap, err := waits.Read(ledger.New(s), "m"); !errors.As(err, &re) || snap != nil {
				t.Errorf("Read = %v, %v; want the read error", snap, err)
			}
		})
	}

	s := parked()
	s.Put(bead{ID: "lost", Status: "open", Edges: []gcbd.Edge{edge(gcbd.EdgeParentChild, "epic", "open")}})
	s.Mark("lost")
	s.Put(bead{ID: "free", Status: "open"})
	snap, err := waits.Read(ledger.New(s), "lost", "ghost", "free")
	if err != nil {
		t.Fatal(err)
	}
	for _, id := range []string{"lost", "ghost"} {
		var re *ledger.ReadError
		var wf *ledger.WaitsForError
		h, err := snap.Holds(id)
		if !errors.As(err, &re) || errors.As(err, &wf) || h.Status != "" {
			t.Errorf("%s = %+v, %v; want a read error and no status", id, h, err)
		}
	}
	if h, err := snap.Holds("free"); err != nil || h.Status != waits.Clear {
		t.Errorf("free, read beside them = %+v, %v; want clear", h, err)
	}
}

// A held bead's waits are those of the ancestor whose own waits hold it, at any
// depth, and an ancestor the store could not answer leaves the bead unread.
func TestAHeldBeadsWaitsAreItsAncestors(t *testing.T) {
	s := parked()
	under(s, bead{ID: "story", Status: "open"})
	s.Put(bead{ID: "task", Status: "open", Edges: []gcbd.Edge{edge(gcbd.EdgeParentChild, "story", "open")}})
	s.List("task", "story")
	s.Mark("task")
	h := holdsOf(t, s, "task")
	if want := []waits.Wait{{ID: "gate", Type: "blocks", Status: "open", IssueType: "gate", Ancestor: "epic"}}; h.Status != waits.Held || !reflect.DeepEqual(h.Waits, want) {
		t.Errorf("task = %s on %+v; want held on %+v", h.Status, h.Waits, want)
	}

	// The ancestor's own waits-for edge is unjudged, and the bead below it is
	// still held, since the store marks it blocked through its parent.
	s = fake.New()
	s.Put(bead{ID: "spawner", Status: "closed"})
	s.Put(bead{ID: "gated", Status: "open", Edges: []gcbd.Edge{landed(gcbd.EdgeWaitsFor, "spawner", "2026-11-08T09:00:00Z")}})
	s.Mark("gated")
	s.Put(bead{ID: "kid", Status: "open", Edges: []gcbd.Edge{edge(gcbd.EdgeParentChild, "gated", "open")}})
	s.List("kid", "gated")
	s.Mark("kid")
	h = holdsOf(t, s, "kid")
	if want := []waits.Wait{{ID: "spawner", Type: "waits-for", Status: "closed", Ancestor: "gated"}}; h.Status != waits.Held || !reflect.DeepEqual(h.Waits, want) {
		t.Errorf("kid = %s on %+v; want held on %+v", h.Status, h.Waits, want)
	}

	// The listing holds a bead through a parent it does not hold.
	s = fake.New()
	s.Put(bead{ID: "idle", Status: "open"})
	s.Put(bead{ID: "kid", Status: "open", Edges: []gcbd.Edge{edge(gcbd.EdgeParentChild, "idle", "open")}})
	s.List("kid", "idle")
	s.Mark("kid")
	snap, err := waits.Read(ledger.New(s), "kid")
	if err != nil {
		t.Fatal(err)
	}
	var re *ledger.ReadError
	if h, err := snap.Holds("kid"); !errors.As(err, &re) || h.Status != "" {
		t.Errorf("kid, held through a parent the listing does not hold = %+v, %v; want a read error", h, err)
	}
}

// A bead can have several parents. The store holds one whose work has not
// started through each parent it marks blocked, whichever parent its listing
// names and in either order of the bead's edges, and work in flight is held only
// by its own waits, so the same bead carrying a branch is clear.
func TestABeadWithTwoParents(t *testing.T) {
	for _, tc := range []struct {
		name    string
		parents []string // in the order of the bead's edges
		names   string   // the parent the listing names
	}{
		{"the listing names the parked parent", []string{"epic", "other"}, "epic"},
		{"the listing names the parked parent, the edges reversed", []string{"other", "epic"}, "epic"},
		{"the listing names the parent that holds nothing", []string{"epic", "other"}, "other"},
		{"the listing names the parent that holds nothing, the edges reversed", []string{"other", "epic"}, "other"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s := parked()
			s.Put(bead{ID: "other", Status: "open", IssueType: "epic"})
			for _, b := range []bead{
				{ID: "b", Status: "open"},
				{ID: "retry", Status: "open", Metadata: map[string]string{"branch": "polecat/retry"}},
			} {
				for _, p := range tc.parents {
					b.Edges = append(b.Edges, edge(gcbd.EdgeParentChild, p, "open"))
				}
				s.Put(b)
				s.List(b.ID, tc.names)
				s.Mark(b.ID)
			}
			if h := holdsOf(t, s, "retry"); h.Status != waits.Clear || h.InFlight != "carries branch" || len(h.Waits) != 0 {
				t.Errorf("retry = %s on %+v, in flight %q; want clear, in flight since it carries branch", h.Status, h.Waits, h.InFlight)
			}
			want := []waits.Wait{{ID: "gate", Type: "blocks", Status: "open", IssueType: "gate", Ancestor: "epic"}}
			if h := holdsOf(t, s, "b"); h.Status != waits.Held || !reflect.DeepEqual(h.Waits, want) || len(h.Pending) != 0 {
				t.Errorf("b = %s on %+v, pending %+v; want held on %+v", h.Status, h.Waits, h.Pending, want)
			}
		})
	}

	// The park is two levels up the line of the parent the listing does not name.
	s := parked()
	under(s, bead{ID: "story", Status: "open"})
	s.Put(bead{ID: "other", Status: "open", IssueType: "epic"})
	s.Put(bead{ID: "deep", Status: "open", Edges: []gcbd.Edge{edge(gcbd.EdgeParentChild, "other", "open"), edge(gcbd.EdgeParentChild, "story", "open")}})
	s.List("deep", "other")
	s.Mark("deep")
	want := []waits.Wait{{ID: "gate", Type: "blocks", Status: "open", IssueType: "gate", Ancestor: "epic"}}
	if h := holdsOf(t, s, "deep"); h.Status != waits.Held || !reflect.DeepEqual(h.Waits, want) {
		t.Errorf("deep = %s on %+v; want held on %+v", h.Status, h.Waits, want)
	}
}

// A bead's pending waits are its own that have not landed, and the last wait to
// land names when it did. An ancestor's open park is none of them, and an edge
// that is no wait never counts.
func TestPendingAndTheLastLanding(t *testing.T) {
	s := parked()
	s.Put(bead{ID: "early", Status: "closed"})
	s.Put(bead{ID: "mid", Status: "closed"})
	s.Put(bead{ID: "late", Status: "closed"})
	s.Put(bead{ID: "open-one", Status: "open"})
	s.Put(bead{ID: "goal", Status: "closed"})
	under(s, bead{ID: "m", Status: "open", Edges: []gcbd.Edge{
		landed(gcbd.EdgeBlocks, "early", "2026-11-01T12:00:00Z"),
		landed(gcbd.EdgeConditionalBlocks, "late", "2026-11-05T12:00:00Z"),
		landed(gcbd.EdgeBlocks, "mid", "2026-11-03T12:00:00Z"),
		landed("until", "goal", "2026-11-07T12:00:00Z"),
	}})
	h := holdsOf(t, s, "m")
	if h.Status != waits.Held || len(h.Pending) != 0 || h.LastLanded != "2026-11-05T12:00:00Z" {
		t.Errorf("m = %s, pending %+v, last landed %q; want held, nothing pending, last landed at the later blocker", h.Status, h.Pending, h.LastLanded)
	}

	s.Put(bead{ID: "w", Status: "open", Edges: []gcbd.Edge{
		landed(gcbd.EdgeBlocks, "early", "2026-11-01T12:00:00Z"),
		edge(gcbd.EdgeBlocks, "open-one", "open"),
	}})
	s.List("w", "open-one")
	s.Mark("w")
	h = holdsOf(t, s, "w")
	if want := []waits.Wait{{ID: "open-one", Type: "blocks", Status: "open"}}; !reflect.DeepEqual(h.Pending, want) || h.LastLanded != "2026-11-01T12:00:00Z" {
		t.Errorf("w = pending %+v, last landed %q; want %+v and the early landing", h.Pending, h.LastLanded, want)
	}
	if h := holdsOf(t, s, "open-one"); h.LastLanded != "" {
		t.Errorf("a bead none of whose waits landed reads last landed %q", h.LastLanded)
	}

	// A waits-for edge lands when its gate opens, so its spawner's close is no
	// landing.
	s.Put(bead{ID: "spawner", Status: "closed"})
	s.Put(bead{ID: "gated", Status: "open", Edges: []gcbd.Edge{landed(gcbd.EdgeWaitsFor, "spawner", "2026-11-06T12:00:00Z")}})
	s.Mark("gated")
	if h := holdsOf(t, s, "gated"); h.Status != waits.Unjudged || h.LastLanded != "" {
		t.Errorf("gated = %s, last landed %q; want unjudged with no landing", h.Status, h.LastLanded)
	}
}

// For work that has not started, an ancestor's waits hold it as its own do, so
// the last landing counts theirs too, on each line of its ancestry up to the
// first ancestor on that line that is closed or pinned. Work in flight counts
// its own waits alone.
func TestTheLastLandingCountsAnAncestorsForWorkNotStarted(t *testing.T) {
	s := fake.New()
	s.Put(bead{ID: "own-blocker", Status: "closed"})
	s.Put(bead{ID: "park", Status: "closed", IssueType: "gate"})
	s.Put(bead{ID: "old-park", Status: "closed", IssueType: "gate"})
	s.Put(bead{ID: "root", Status: "open", IssueType: "epic", Edges: []gcbd.Edge{landed(gcbd.EdgeBlocks, "park", "2026-11-08T12:00:00Z")}})
	s.Put(bead{ID: "feat", Status: "open", IssueType: "feature", Edges: []gcbd.Edge{edge(gcbd.EdgeParentChild, "root", "open")}})
	s.Put(bead{ID: "task", Status: "open", Edges: []gcbd.Edge{
		edge(gcbd.EdgeParentChild, "feat", "open"),
		landed(gcbd.EdgeBlocks, "own-blocker", "2026-11-02T12:00:00Z"),
	}})
	if h := holdsOf(t, s, "task"); h.Status != waits.Clear || h.LastLanded != "2026-11-08T12:00:00Z" {
		t.Errorf("task = %s, last landed %q; want clear, last landed when the park two levels up closed", h.Status, h.LastLanded)
	}

	s.Put(bead{ID: "flying", Status: "in_progress", Edges: []gcbd.Edge{
		edge(gcbd.EdgeParentChild, "feat", "open"),
		landed(gcbd.EdgeBlocks, "own-blocker", "2026-11-02T12:00:00Z"),
	}})
	if h := holdsOf(t, s, "flying"); h.LastLanded != "2026-11-02T12:00:00Z" {
		t.Errorf("flying last landed %q; want its own blocker's landing alone, since it is in flight", h.LastLanded)
	}

	s.Put(bead{ID: "done-epic", Status: "closed", IssueType: "epic", Edges: []gcbd.Edge{landed(gcbd.EdgeBlocks, "old-park", "2026-11-09T00:00:00Z")}})
	s.Put(bead{ID: "orphan", Status: "open", Edges: []gcbd.Edge{
		edge(gcbd.EdgeParentChild, "done-epic", "closed"),
		landed(gcbd.EdgeBlocks, "own-blocker", "2026-11-02T12:00:00Z"),
	}})
	if h := holdsOf(t, s, "orphan"); h.LastLanded != "2026-11-02T12:00:00Z" {
		t.Errorf("orphan last landed %q; want its own landing, since a closed ancestor's waits hold nothing below it", h.LastLanded)
	}

	// A bead with two parents counts the landings on each parent's line, in
	// either order of its edges, and a closed parent ends only its own line.
	s.Put(bead{ID: "late-park", Status: "closed", IssueType: "gate"})
	s.Put(bead{ID: "side", Status: "open", IssueType: "epic", Edges: []gcbd.Edge{landed(gcbd.EdgeBlocks, "late-park", "2026-11-09T06:00:00Z")}})
	for _, tc := range []struct {
		parents []string
		want    string
	}{
		{[]string{"feat", "side"}, "2026-11-09T06:00:00Z"},
		{[]string{"side", "feat"}, "2026-11-09T06:00:00Z"},
		{[]string{"done-epic", "feat"}, "2026-11-08T12:00:00Z"},
		{[]string{"feat", "done-epic"}, "2026-11-08T12:00:00Z"},
	} {
		edges := []gcbd.Edge{landed(gcbd.EdgeBlocks, "own-blocker", "2026-11-02T12:00:00Z")}
		for _, p := range tc.parents {
			edges = append(edges, edge(gcbd.EdgeParentChild, p, "open"))
		}
		s.Put(bead{ID: "twin", Status: "open", Edges: edges})
		if h := holdsOf(t, s, "twin"); h.LastLanded != tc.want {
			t.Errorf("twin under %v last landed %q; want %q", tc.parents, h.LastLanded, tc.want)
		}
	}
}

// A bead's wait edges into another store are listed, and an edge the listing
// has onto a bead the store holds is not one of them.
func TestWaitEdgesIntoAnotherStore(t *testing.T) {
	s := fake.New()
	s.Put(bead{ID: "here", Status: "open"})
	s.Put(bead{ID: "b", Status: "open", Edges: []gcbd.Edge{
		edge(gcbd.EdgeBlocks, "xx-1", "open"),
		edge(gcbd.EdgeWaitsFor, "xx-2", "open"),
		edge("tracks", "xx-3", "open"),
		landed(gcbd.EdgeBlocks, "here", "2026-11-01T00:00:00Z"),
	}})
	h := holdsOf(t, s, "b")
	want := []waits.Foreign{{ID: "xx-1", Type: "blocks"}, {ID: "xx-2", Type: "waits-for"}}
	if h.Status != waits.Clear || !reflect.DeepEqual(h.Foreign, want) {
		t.Errorf("b = %s, foreign %+v; want clear, foreign %+v", h.Status, h.Foreign, want)
	}
	if h := holdsOf(t, s, "here"); len(h.Foreign) != 0 {
		t.Errorf("a bead with no edges reads foreign %+v", h.Foreign)
	}
}

// A bead's arm is the arm's record answer, each key as the store holds it: the
// target, the arguments that name its formula, why and by whom it was armed and
// when, and the attempts made on it. A bead that carries no target carries no
// arm, whatever else it holds.
func TestTheArm(t *testing.T) {
	s := fake.New()
	s.Put(bead{ID: "armed", Status: "open", Metadata: map[string]string{
		"gc.dispatch_when_ready":            "rig/rig.polecat",
		"gc.dispatch_when_ready_args":       `["--on","mol-polecat-work"]`,
		"gc.dispatch_when_ready_reason":     "waits for unit 1",
		"gc.dispatch_when_ready_armed_by":   "a-session",
		"gc.dispatch_when_ready_armed_at":   "2026-10-30T01:05:10Z",
		"gc.dispatch_when_ready_fail_count": "1",
	}})
	s.Put(bead{ID: "noticed", Status: "open", Metadata: map[string]string{"gc.notify_when_ready": "rig/mechanik"}})
	s.Put(bead{ID: "plain", Status: "open", Metadata: map[string]string{"gc.dispatch_when_ready_reason": "left behind"}})
	want := `{"target":"rig/rig.polecat","args":"[\"--on\",\"mol-polecat-work\"]","reason":"waits for unit 1",` +
		`"armed_by":"a-session","armed_at":"2026-10-30T01:05:10Z","fail_count":"1"}`
	if raw, err := json.Marshal(holdsOf(t, s, "armed").Arm); err != nil || string(raw) != want {
		t.Errorf("armed's arm prints %s, %v; want %s", raw, err, want)
	}
	for _, id := range []string{"noticed", "plain"} {
		if h := holdsOf(t, s, id); h.Arm != nil {
			t.Errorf("%s carries no target and reads arm %+v", id, h.Arm)
		}
	}
}
