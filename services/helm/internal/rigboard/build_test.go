package rigboard

import (
	"slices"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/listing"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// graph is a small rig: two epics, a Delivery, the work under them, a human
// gate holding work under both epics, a park gate, and the Product Owner's
// desk.
func graph() *gathered {
	parent := func(p string) []listing.Edge { return []listing.Edge{{ID: p, Type: "parent-child"}} }
	blocks := func(id string) listing.Edge { return listing.Edge{ID: id, Type: "blocks"} }
	open := []bead{
		{ID: "tk-a", Title: "Epic A", Status: "open", Priority: 1, IssueType: "epic", Epic: listing.Epic{Hypothesis: "A works"}, CreatedAt: "2026-01-01"},
		{ID: "tk-b", Title: "Epic B", Status: "open", Priority: 2, IssueType: "epic", Epic: listing.Epic{Hypothesis: "B works"}, CreatedAt: "2026-01-02"},
		{ID: "tk-a.1", Title: "Delivery: one", Status: "open", Priority: 1, IssueType: "epic", Description: "Aim: land one\nDone when: it lands", Edges: parent("tk-a"), CreatedAt: "2026-01-03"},
		{ID: "tk-a.1.1", Title: "story under the delivery", Status: "open", Priority: 2, IssueType: "task", Edges: append(parent("tk-a.1"), blocks("tk-q")), CreatedAt: "2026-01-04"},
		{ID: "tk-b.1", Title: "story under B", Status: "open", Priority: 2, IssueType: "task", Edges: append(parent("tk-b"), blocks("tk-q")), CreatedAt: "2026-01-05"},
		{ID: "tk-b.2", Title: "behind B's story", Status: "open", Priority: 2, IssueType: "task", Edges: append(parent("tk-b"), blocks("tk-b.1")), CreatedAt: "2026-01-06"},
		{ID: "tk-loose", Title: "parked work", Status: "open", Priority: 3, IssueType: "bug", Edges: []listing.Edge{blocks("tk-park")}, CreatedAt: "2026-01-07"},
		{ID: "tk-loose2", Title: "more parked work", Status: "open", Priority: 2, IssueType: "bug", Edges: []listing.Edge{blocks("tk-park")}, CreatedAt: "2026-01-08"},
		{ID: "tk-desk1", Title: "new idea", Status: "open", Priority: 2, IssueType: "task", Labels: []string{" Hold:Mayor "}, CreatedAt: "2026-01-09"},
		{ID: "tk-desk2", Title: "newer idea", Status: "open", Priority: 2, IssueType: "task", Labels: []string{"hold:mayor"}, CreatedAt: "2026-01-10"},
		{ID: "tk-q", Title: "which way?", Description: "which way?\nthe whole question", Status: "open", Priority: 1, IssueType: "gate", AwaitType: "human", CreatedAt: "2026-01-02"},
		{ID: "tk-park", Title: "parked", Status: "open", Priority: 2, IssueType: "gate", CreatedAt: "2026-01-02"},
		{ID: "tk-review", Title: "review", Status: "open", IssueType: "task", Anchor: "tk-b.1", CreatedAt: "2026-01-02"},
	}
	closed := []bead{
		{ID: "tk-b.0", Title: "done under B", Status: "closed", Priority: 2, IssueType: "task", Edges: parent("tk-b"), WorkOutcome: "shipped"},
	}
	wq := waits.Wait{ID: "tk-q", Type: "blocks", Title: "which way?", Status: "open", IssueType: "gate", AwaitType: "human"}
	wpark := waits.Wait{ID: "tk-park", Type: "blocks", Title: "parked", Status: "open", IssueType: "gate"}
	q := prstatus.Blocker{ID: "tk-q", Title: "which way?", Status: "open", IssueType: "gate", AwaitType: "human"}
	clear := func(id string) waits.Holds { return waits.Holds{ID: id, Status: waits.Clear} }
	return &gathered{
		rig: "gc-toolkit", open: open, closed: closed,
		holds: map[string]waits.Holds{
			"tk-a": clear("tk-a"), "tk-b": clear("tk-b"), "tk-a.1": clear("tk-a.1"),
			"tk-a.1.1":  {ID: "tk-a.1.1", Status: waits.Blocked, Waits: []waits.Wait{wq}},
			"tk-b.1":    {ID: "tk-b.1", Status: waits.Blocked, Waits: []waits.Wait{wq}},
			"tk-b.2":    {ID: "tk-b.2", Status: waits.Blocked, Waits: []waits.Wait{{ID: "tk-b.1", Type: "blocks", Title: "story under B", Status: "open", IssueType: "task"}}},
			"tk-loose":  {ID: "tk-loose", Status: waits.Blocked, Waits: []waits.Wait{wpark}},
			"tk-loose2": {ID: "tk-loose2", Status: waits.Blocked, Waits: []waits.Wait{wpark}},
			"tk-desk1":  clear("tk-desk1"), "tk-desk2": clear("tk-desk2"),
			"tk-q": clear("tk-q"), "tk-park": clear("tk-park"),
		},
		unread: map[string]error{},
		holding: map[string]prstatus.Holds{
			"tk-a.1.1":  {Gates: []prstatus.Blocker{q}},
			"tk-b.1":    {Gates: []prstatus.Blocker{q}},
			"tk-b.2":    {Gates: []prstatus.Blocker{q}},
			"tk-loose":  {},
			"tk-loose2": {},
		},
		unwalked: map[string]bool{}, facts: map[string]prstatus.Facts{}, noFacts: map[string]bool{},
	}
}

func TestPages(t *testing.T) {
	doc := build(graph())

	t.Run("an ask under two epics is listed under each and counted once", func(t *testing.T) {
		n := doc.NeedsYou
		if n.Count != 1 {
			t.Errorf("count = %d, want 1", n.Count)
		}
		var under []string
		for _, e := range n.NoConversationYet {
			if slices.Contains(e.Asks, "tk-q") {
				under = append(under, e.Epic)
			}
		}
		if !slices.Equal(under, []string{"tk-a", "tk-b"}) {
			t.Errorf("tk-q is listed under %v, want both epics in priority order", under)
		}
		if got := doc.Rows["tk-q"].Holds; !slices.Equal(got, []string{"tk-a.1.1", "tk-b.1", "tk-b.2"}) {
			t.Errorf("tk-q holds %v", got)
		}
	})

	t.Run("the count reaches zero once nothing under an epic waits on a person", func(t *testing.T) {
		g := graph()
		for _, id := range []string{"tk-a.1.1", "tk-b.1", "tk-b.2"} {
			delete(g.holding, id)
			g.holds[id] = waits.Holds{ID: id, Status: waits.Clear}
		}
		if n := build(g).NeedsYou; n.Count != 0 || !slices.Equal(n.NoEpic, []string{"tk-q"}) {
			t.Errorf("count = %d, no epic = %v; want 0 and the gate listed under no epic", n.Count, n.NoEpic)
		}
	})

	t.Run("the epics page nests a Delivery and groups the work", func(t *testing.T) {
		if len(doc.Epics) != 2 || doc.Epics[0].ID != "tk-a" || doc.Epics[1].ID != "tk-b" {
			t.Fatalf("epics = %+v", doc.Epics)
		}
		a := doc.Epics[0]
		if len(a.Deliveries) != 1 || a.Deliveries[0].ID != "tk-a.1" {
			t.Fatalf("deliveries = %+v", a.Deliveries)
		}
		if got := a.Deliveries[0].Groups; len(got) != 1 || got[0].Group != GroupWaitingOnYou || !slices.Equal(got[0].IDs, []string{"tk-a.1.1"}) {
			t.Errorf("delivery groups = %+v", got)
		}
		if c := doc.Rows["tk-a"].Counts; c == nil || c.WaitingOnYou != 1 {
			t.Errorf("tk-a counts the Delivery's work at depth: %+v", c)
		}
		if got := doc.Rows["tk-a.1"].Line2; got != "Aim: land one" {
			t.Errorf("a Delivery's line 2 is its aim, got %q", got)
		}
		b := doc.Epics[1]
		want := []GroupList{{Group: GroupWaitingOnYou, IDs: []string{"tk-b.1", "tk-b.2"}}, {Group: GroupClosed, IDs: []string{"tk-b.0"}}}
		if !slices.EqualFunc(b.Groups, want, func(x, y GroupList) bool { return x.Group == y.Group && slices.Equal(x.IDs, y.IDs) }) {
			t.Errorf("tk-b groups = %+v, want %+v", b.Groups, want)
		}
		if got := doc.Rows["tk-b.1"].Asks; !slices.Equal(got, []string{"tk-q"}) {
			t.Errorf("tk-b.1's asks = %v, want the gate it waits on", got)
		}
		if got := doc.Rows["tk-b.1"].Anchored; len(got) != 1 || got[0].ID != "tk-review" {
			t.Errorf("tk-b.1 lists its review in Details: %+v", got)
		}
		if _, ok := doc.Rows["tk-review"]; ok {
			t.Error("a bead that carries anchor_bead has no row of its own")
		}
	})

	t.Run("the work queue leaves out the desk and work waiting on you directly", func(t *testing.T) {
		var listed []string
		var held *Section
		for i, s := range doc.WorkQueue {
			for _, e := range s.Rows {
				listed = append(listed, e.ID)
			}
			for _, p := range s.Parts {
				for _, e := range p.Rows {
					listed = append(listed, e.ID)
				}
			}
			if s.Name == sectionHeldByGate {
				held = &doc.WorkQueue[i]
			}
		}
		for _, id := range []string{"tk-desk1", "tk-desk2", "tk-a.1.1", "tk-b.1"} {
			if slices.Contains(listed, id) {
				t.Errorf("%s is on the work queue", id)
			}
		}
		if !slices.Contains(listed, "tk-b.2") {
			t.Error("work that ends on you further along is on the work queue")
		}
		if held == nil || len(held.Rows) != 1 || held.Rows[0].ID != "tk-park" || !slices.Equal(held.Rows[0].Children, []string{"tk-loose2", "tk-loose"}) {
			t.Errorf("held by a gate = %+v, want the gate once with its work beneath in priority order", held)
		}
	})

	t.Run("unprioritized lists the desk newest first, any spelling", func(t *testing.T) {
		if got := doc.Unprioritized; len(got) != 1 || got[0].Priority != 2 || !slices.Equal(got[0].IDs, []string{"tk-desk2", "tk-desk1"}) {
			t.Errorf("unprioritized = %+v", got)
		}
	})

	t.Run("a gate's line 2 drops its first line when that is the title", func(t *testing.T) {
		if got := doc.Rows["tk-q"].Line2; got != "the whole question" {
			t.Errorf("line 2 = %q", got)
		}
	})
}

// TestAConversationAnsweringTwoQuestions holds one store to one document: a
// conversation that answers two questions stands in the first of them.
func TestAConversationAnsweringTwoQuestions(t *testing.T) {
	g := graph()
	g.open = append(g.open,
		bead{ID: "tk-b.3", Title: "talked about", Status: "open", Priority: 2, IssueType: "task",
			Edges: []listing.Edge{{ID: "tk-b", Type: "parent-child"}}, CreatedAt: "2026-01-11"},
		bead{ID: "tk-q2", Title: "and which?", Status: "open", Priority: 1, IssueType: "gate", AwaitType: "human", CreatedAt: "2026-01-11"},
		bead{ID: "tk-c", Title: "talk it through", Status: "open", Priority: 1, IssueType: "task", Assignee: "human", CreatedAt: "2026-01-11",
			Edges: []listing.Edge{{ID: "tk-b.3", Type: "tracks"}, {ID: "tk-q2", Type: "replies-to"}, {ID: "tk-q", Type: "replies-to"}}},
	)
	for _, id := range []string{"tk-b.3", "tk-q2", "tk-c"} {
		g.holds[id] = waits.Holds{ID: id, Status: waits.Clear}
	}
	for range 20 {
		if got := build(g).Rows["tk-b.3"].Asks; !slices.Equal(got, []string{"tk-q"}) {
			t.Fatalf("tk-b.3's asks = %v, want the first question its conversation answers", got)
		}
	}
}
