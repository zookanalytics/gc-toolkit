package listing

import (
	"slices"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

func parent(p string) gcbd.Edge  { return gcbd.Edge{Type: gcbd.EdgeParentChild, ID: p} }
func blocks(id string) gcbd.Edge { return gcbd.Edge{Type: gcbd.EdgeBlocks, ID: id} }

// rig is a small store: an epic with a story, a landed Delivery under it with
// a closed story of its own, a story held by an open human gate, a run that
// works the story, a review child, and a closed bead the gate's question
// waited on.
func rig() *fake.Store {
	s := fake.New()
	for _, b := range []fake.Bead{
		{ID: "tk-e", Title: "Epic", Status: "open", IssueType: "epic", Priority: 1, CreatedAt: "2026-01-01T00:00:00Z",
			Metadata: map[string]string{"epic_hypothesis": "it works", "epic_handle": "the board", "epic_ruling": "continue"}},
		{ID: "tk-e.1", Title: "Delivery: one", Status: "closed", IssueType: "epic", Description: "Aim: land one",
			Edges: []gcbd.Edge{parent("tk-e")}},
		{ID: "tk-e.1.1", Title: "story under the delivery", Status: "closed", IssueType: "task",
			Metadata: map[string]string{"gc.work_outcome": "shipped"}, Edges: []gcbd.Edge{parent("tk-e.1")}},
		{ID: "tk-e.2", Title: "story", Status: "open", IssueType: "task", Priority: 2, Labels: []string{"hold:mayor"},
			Metadata: map[string]string{"merge_result": "pull_request", "pr_number": "12", "pr_url": "https://example.test/pull/12",
				"gc.routed_to": "gc-toolkit/gc-toolkit.polecat"},
			Edges: []gcbd.Edge{parent("tk-e"), blocks("tk-q")}},
		{ID: "tk-q", Title: "which way?", Status: "open", IssueType: "gate", AwaitType: "human", Assignee: "human",
			Description: "which way?\nthe whole question", Edges: []gcbd.Edge{blocks("tk-old")}},
		{ID: "tk-old", Title: "an old answer", Status: "closed", IssueType: "task", ClosedAt: "2026-01-02T00:00:00Z"},
		{ID: "tk-review", Title: "review", Status: "open", IssueType: "task", Metadata: map[string]string{"anchor_bead": "tk-e.2"}},
		{ID: "tk-ask", Title: "routed to a person", Status: "open", IssueType: "task", Metadata: map[string]string{"gc.routed_to": "human"}},
		{ID: "tk-decide", Title: "which rig owns it?", Status: "open", IssueType: "decision"},
		{ID: "tk-root", Title: "mol-polecat-work", Status: "open", IssueType: "task",
			Metadata: map[string]string{"gc.kind": "workflow", "gc.formula_contract": "graph.v2", "gc.input_convoy_id": "tk-cv"}},
		{ID: "tk-step", Title: "Implement the solution", Status: "open", IssueType: "task",
			Metadata: map[string]string{"gc.root_bead_id": "tk-root", "gc.step_ref": "mol-polecat-work.implement"}},
		{ID: "tk-cv", Title: "convoy", Status: "open", IssueType: "convoy", Edges: []gcbd.Edge{{Type: "tracks", ID: "tk-e.2"}}},
		{ID: "tk-wisp-1", Title: "order:reconcile", Status: "open", IssueType: "task", Ephemeral: true},
	} {
		s.Put(b)
	}
	s.List("tk-e.2", "tk-q")
	s.Mark("tk-e.2")
	return s
}

func ids(bs []Bead) []string {
	var out []string
	for _, b := range bs {
		out = append(out, b.ID)
	}
	return out
}

// A listing reads every live bead once, each with its row's fields, its edges
// and the keys a reader takes from it, decoded through the declarations, and
// with the domains' answers that are the bead's own.
func TestListingDecodesEachLiveBead(t *testing.T) {
	ls, err := read(ledger.New(rig()))
	if err != nil {
		t.Fatal(err)
	}
	live := ls.Live()
	want := []string{"tk-ask", "tk-cv", "tk-decide", "tk-e", "tk-e.2", "tk-q", "tk-review", "tk-root", "tk-step", "tk-wisp-1"}
	if !slices.Equal(ids(live), want) {
		t.Fatalf("live = %v, want %v", ids(live), want)
	}
	by := map[string]Bead{}
	for _, b := range live {
		by[b.ID] = b
	}
	story := by["tk-e.2"]
	if story.MergeResult != "pull_request" || story.PRNumber != "12" || story.PRURL != "https://example.test/pull/12" ||
		story.RoutedTo != "gc-toolkit/gc-toolkit.polecat" || story.Priority != 2 || !slices.Equal(story.Labels, []string{"hold:mayor"}) ||
		!slices.Equal(story.Edges, []Edge{{ID: "tk-e", Type: "parent-child"}, {ID: "tk-q", Type: "blocks"}}) || story.Run || story.PersonBlocker {
		t.Errorf("the story reads %+v", story)
	}
	if e := by["tk-e"].Epic; e.Hypothesis != "it works" || e.Handle != "the board" || e.Ruling != "continue" {
		t.Errorf("the epic's contract reads %+v", e)
	}
	if by["tk-review"].Anchor != "tk-e.2" {
		t.Errorf("the review's anchor reads %q", by["tk-review"].Anchor)
	}
	if !by["tk-root"].Run || !by["tk-step"].Run || by["tk-cv"].Run {
		t.Errorf("a run's own beads read root %v, step %v, convoy %v", by["tk-root"].Run, by["tk-step"].Run, by["tk-cv"].Run)
	}
	if !by["tk-wisp-1"].EphemeralPlane || by["tk-e.2"].EphemeralPlane {
		t.Errorf("the ephemeral plane reads %v for the wisp and %v for the story", by["tk-wisp-1"].EphemeralPlane, by["tk-e.2"].EphemeralPlane)
	}
	if !by["tk-decide"].PersonBlocker || by["tk-ask"].PersonBlocker || by["tk-q"].PersonBlocker {
		t.Errorf("a person's to clear reads %v for a decision, %v for work routed to human and %v for a human gate",
			by["tk-decide"].PersonBlocker, by["tk-ask"].PersonBlocker, by["tk-q"].PersonBlocker)
	}
	if q := by["tk-q"]; q.AwaitType != "human" || q.Assignee != "human" || q.Description != "which way?\nthe whole question" {
		t.Errorf("the gate reads %+v", q)
	}
}

// The closed beads under a parent are the ones whose own edge names it, the
// work outcome among their keys, and a closed epic's beads read the same way.
func TestListingReadsTheClosedBeadsUnderAParent(t *testing.T) {
	s := rig()
	// The store's --parent filter can return a bead whose own edge names
	// another parent.
	s.Put(fake.Bead{ID: "tk-stray", Title: "elsewhere", Status: "closed", IssueType: "task", Edges: []gcbd.Edge{parent("tk-other")}})
	ls, err := read(ledger.New(s))
	if err != nil {
		t.Fatal(err)
	}
	closed, err := ls.ClosedUnder([]string{"tk-e", "tk-e.1"})
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(ids(closed), []string{"tk-e.1", "tk-e.1.1"}) {
		t.Fatalf("closed = %v, want the Delivery and its story", ids(closed))
	}
	if closed[1].WorkOutcome != "shipped" || closed[0].Description != "Aim: land one" {
		t.Errorf("closed = %+v", closed)
	}
}

// What holds a bead and what prstatus reads come from the listing's rows: a
// write that lands after the listing changes none of them, and the store is
// read again only for the beads the listing does not hold.
func TestListingAnswersTheDomainsFromItsRows(t *testing.T) {
	s := rig()
	ls, err := read(ledger.New(s))
	if err != nil {
		t.Fatal(err)
	}
	listed := len(s.Finds())
	s.Put(fake.Bead{ID: "tk-q", Title: "which way?", Status: "closed", IssueType: "gate", AwaitType: "human"})
	s.Put(fake.Bead{ID: "tk-e.2", Title: "story", Status: "open", IssueType: "task"})

	holds, failed, err := ls.Holds([]string{"tk-e.2", "tk-ask"})
	if err != nil || len(failed) != 0 {
		t.Fatalf("Holds = %v, %v", failed, err)
	}
	if h := holds["tk-e.2"]; h.Status != waits.Blocked || len(h.Waits) != 1 || h.Waits[0].ID != "tk-q" || h.Waits[0].Status != "open" {
		t.Errorf("the story's holds = %+v; want blocked on the open gate the listing read", h)
	}
	if h := holds["tk-e.2"]; h.InFlight != "carries merge_result" {
		t.Errorf("the story is in flight for %q, want the merge_result the listing read", h.InFlight)
	}
	if holds["tk-ask"].Status != waits.Clear {
		t.Errorf("the routed task's holds = %+v", holds["tk-ask"])
	}

	held, err := prstatus.Holding([]string{"tk-e.2"}, ls.Blockers)
	if err != nil {
		t.Fatal(err)
	}
	if g := held["tk-e.2"].Gates; len(g) != 1 || g[0].ID != "tk-q" {
		t.Errorf("Holding = %+v; want the gate the listing read open", held)
	}
	facts, err := prstatus.Read([]string{"tk-e.2"}, ls)
	if err != nil {
		t.Fatal(err)
	}
	if f := facts["tk-e.2"]; f.InFlightCount != 1 || len(f.Gates) != 1 {
		t.Errorf("facts = %+v; want the review in flight and the gate", f)
	}
	for _, q := range s.Finds()[listed:] {
		for _, id := range q.IDs {
			if slices.Contains([]string{"tk-e.2", "tk-q", "tk-ask", "tk-review"}, id) {
				t.Errorf("a question read %s again, which the listing holds: %+v", id, q)
			}
		}
		if q.HasKey != "" || q.Key != "" || q.Every {
			t.Errorf("a question read the store by a key or whole: %+v", q)
		}
	}
}

// prstatus's in-flight set reads live beads alone, and a listing refuses a
// closed status rather than answer it with nothing.
func TestListingRefusesAClosedAnchoredSet(t *testing.T) {
	ls, err := read(ledger.New(rig()))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := ls.Anchored([]string{"tk-e.2"}, []string{"open", "closed"}); err == nil {
		t.Error("a closed in-flight set read as an answer")
	}
	got, err := ls.Anchored([]string{"tk-e.2"}, prstatus.InFlightStatuses)
	if err != nil || len(got["tk-e.2"]) != 1 || got["tk-e.2"][0].ID != "tk-review" {
		t.Errorf("Anchored = %+v, %v; want the review", got, err)
	}
}

// A bead named that the store does not hold fails a read of its blockers, and
// an edge onto a bead the store does not hold is one into another store.
func TestListingBlockersReadTheStoreOnce(t *testing.T) {
	s := rig()
	s.Put(fake.Bead{ID: "tk-far", Title: "far", Status: "open", IssueType: "task", Edges: []gcbd.Edge{blocks("xx-1"), blocks("tk-old")}})
	ls, err := read(ledger.New(s))
	if err != nil {
		t.Fatal(err)
	}
	got, err := ls.Blockers([]string{"tk-far"})
	if err != nil || len(got["tk-far"]) != 1 || got["tk-far"][0].ID != "tk-old" || got["tk-far"][0].Status != "closed" {
		t.Errorf("Blockers = %+v, %v; want the closed bead in this store alone", got, err)
	}
	if _, err := ls.Blockers([]string{"tk-gone"}); err == nil {
		t.Error("a bead the store does not hold read as one with no blockers")
	}
}
