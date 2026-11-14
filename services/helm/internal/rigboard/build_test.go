package rigboard

import (
	"errors"
	"slices"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/listing"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus/fixture"
	"github.com/zookanalytics/gc-toolkit/services/gctk/queue"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// graph is a small rig: two epics, a Delivery, the work under them, a human
// gate holding work under both epics, a park gate, and the Product Owner's
// desk. tk-b.1 and tk-b.2 are armed and tk-loose is routed to a pool, so the
// city takes them, and nobody has scheduled tk-a.1.1 or tk-loose2.
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
		{ID: "tk-loose", Title: "parked work", Status: "open", Priority: 3, IssueType: "bug", Edges: []listing.Edge{blocks("tk-park")}, RoutedTo: "gc-toolkit/gc-toolkit.polecat", CreatedAt: "2026-01-07"},
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
	armed := &waits.Arm{Target: "gc-toolkit/gc-toolkit.polecat"}
	return &gathered{
		rig: "gc-toolkit", open: open, closed: closed,
		holds: map[string]waits.Holds{
			"tk-a": clear("tk-a"), "tk-b": clear("tk-b"), "tk-a.1": clear("tk-a.1"),
			"tk-a.1.1":  {ID: "tk-a.1.1", Status: waits.Blocked, Waits: []waits.Wait{wq}},
			"tk-b.1":    {ID: "tk-b.1", Status: waits.Blocked, Waits: []waits.Wait{wq}, Arm: armed},
			"tk-b.2":    {ID: "tk-b.2", Status: waits.Blocked, Waits: []waits.Wait{{ID: "tk-b.1", Type: "blocks", Title: "story under B", Status: "open", IssueType: "task"}}, Arm: armed},
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

// readOf is queue's read of a test's beads and what holds them, as the listing
// gives it from its rows: a bead with no answer about what holds it is one
// waits could not answer.
type readOf struct{ g *gathered }

func (r readOf) Rows(ids []string) (map[string]queue.Row, error) {
	out := map[string]queue.Row{}
	for _, b := range append(slices.Clone(r.g.open), r.g.closed...) {
		if _, dup := out[b.ID]; !dup && slices.Contains(ids, b.ID) {
			out[b.ID] = queue.Row{ID: b.ID, Status: b.Status, Priority: b.Priority, CreatedAt: b.CreatedAt,
				RoutedTo: b.RoutedTo, Assignee: b.Assignee, Labels: b.Labels, Anchor: b.Anchor}
		}
	}
	return out, nil
}

func (r readOf) Holds(ids []string) (map[string]waits.Holds, map[string]error, error) {
	holds, failed := map[string]waits.Holds{}, map[string]error{}
	for _, id := range ids {
		if h, ok := r.g.holds[id]; ok {
			holds[id] = h
		} else {
			failed[id] = errors.New("waits could not answer it")
		}
	}
	return holds, failed, nil
}

// boardOf builds the document from a test's read, with the order the read asks
// queue for.
func boardOf(t *testing.T, g *gathered) Document {
	t.Helper()
	o, err := queue.Order(openWork(g.open), readOf{g})
	if err != nil {
		t.Fatal(err)
	}
	g.order = o
	return build(g)
}

func sameNeed(a, b Need) bool {
	return a.ID == b.ID && a.Kind == b.Kind && slices.Equal(a.Holds, b.Holds)
}

func sameQueue(a, b WorkQueue) bool {
	return slices.Equal(a.Queue, b.Queue) && slices.Equal(a.NotScheduled, b.NotScheduled) && slices.Equal(a.Unread, b.Unread)
}

func TestPages(t *testing.T) {
	doc := boardOf(t, graph())

	t.Run("the work queue lists the rig's work but the desk, the queue first and in layers", func(t *testing.T) {
		want := WorkQueue{Queue: []string{"tk-b.1", "tk-loose", "tk-b.2"}, NotScheduled: []string{"tk-a.1.1", "tk-loose2"}, Unread: []string{}}
		if !sameQueue(doc.WorkQueue, want) {
			t.Errorf("work queue = %+v, want %+v", doc.WorkQueue, want)
		}
	})

	t.Run("a need lists every bead it holds, in the Work queue's order", func(t *testing.T) {
		if got := doc.Rows["tk-q"].Holds; !slices.Equal(got, []string{"tk-b.1", "tk-b.2", "tk-a.1.1"}) {
			t.Errorf("tk-q holds %v, want the queued work first and in its order", got)
		}
		n := doc.NeedsYou
		if n.Count != 1 || !slices.EqualFunc(n.Counted, []Need{{ID: "tk-q", Kind: NeedKindQuestion, Holds: []string{"tk-b.1", "tk-b.2", "tk-a.1.1"}}}, sameNeed) ||
			len(n.NotCounted) != 0 {
			t.Errorf("Needs you counts %d, lists %+v and folds %+v", n.Count, n.Counted, n.NotCounted)
		}
	})

	t.Run("a question about nothing else counts, and the count reaches zero once it is answered", func(t *testing.T) {
		g := graph()
		for _, id := range []string{"tk-a.1.1", "tk-b.1", "tk-b.2"} {
			delete(g.holding, id)
			h := g.holds[id]
			h.Status, h.Waits = waits.Clear, nil
			g.holds[id] = h
		}
		n := boardOf(t, g).NeedsYou
		if n.Count != 1 || !slices.EqualFunc(n.Counted, []Need{{ID: "tk-q", Kind: NeedKindQuestion, Holds: []string{}}}, sameNeed) {
			t.Errorf("count = %d, needs = %+v; want the gate counted, holding nothing", n.Count, n.Counted)
		}
		for i := range g.open {
			if g.open[i].ID == "tk-q" {
				g.open[i].Status = "closed"
			}
		}
		if n := boardOf(t, g).NeedsYou; n.Count != 0 || len(n.Counted) != 0 || len(n.NotCounted) != 0 {
			t.Errorf("once answered, Needs you counts %d and lists %+v and %+v; want nothing", n.Count, n.Counted, n.NotCounted)
		}
	})

	t.Run("each epic and Delivery shows the two views of the work it holds nearest, and its closed work", func(t *testing.T) {
		if len(doc.Epics) != 2 || doc.Epics[0].ID != "tk-a" || doc.Epics[1].ID != "tk-b" {
			t.Fatalf("epics = %+v", doc.Epics)
		}
		a := doc.Epics[0]
		if a.Needs.Count != 0 || len(a.Needs.Counted)+len(a.Needs.NotCounted) != 0 ||
			!sameQueue(a.Queue, WorkQueue{Queue: []string{}, NotScheduled: []string{}, Unread: []string{}}) {
			t.Errorf("tk-a lists %+v and %+v of its own, want nothing: its work sits under its Delivery", a.Needs, a.Queue)
		}
		if len(a.Deliveries) != 1 || a.Deliveries[0].ID != "tk-a.1" {
			t.Fatalf("deliveries = %+v", a.Deliveries)
		}
		d := a.Deliveries[0]
		if d.Needs.Count != 1 || !slices.EqualFunc(d.Needs.Counted, []Need{{ID: "tk-q", Kind: NeedKindQuestion, Holds: []string{"tk-a.1.1"}}}, sameNeed) ||
			!sameQueue(d.Queue, WorkQueue{Queue: []string{}, NotScheduled: []string{"tk-a.1.1"}, Unread: []string{}}) {
			t.Errorf("the Delivery lists %+v and %+v", d.Needs, d.Queue)
		}
		b := doc.Epics[1]
		if !slices.EqualFunc(b.Needs.Counted, []Need{{ID: "tk-q", Kind: NeedKindQuestion, Holds: []string{"tk-b.1", "tk-b.2"}}}, sameNeed) {
			t.Errorf("tk-b's Needs you = %+v, want the question with its own work beneath it", b.Needs)
		}
		if !sameQueue(b.Queue, WorkQueue{Queue: []string{"tk-b.1", "tk-b.2"}, NotScheduled: []string{}, Unread: []string{}}) {
			t.Errorf("tk-b's Work queue = %+v", b.Queue)
		}
		if !slices.Equal(b.Closed, []string{"tk-b.0"}) {
			t.Errorf("tk-b's closed work = %v", b.Closed)
		}
		for id, want := range map[string]Counts{
			"tk-a":   {Needs: 1, NotScheduled: 1},
			"tk-a.1": {Needs: 1, NotScheduled: 1},
			"tk-b":   {Needs: 1, Queue: 2, Closed: 1},
		} {
			if c := doc.Rows[id].Counts; c == nil || *c != want {
				t.Errorf("%s counts %+v, want %+v", id, c, want)
			}
		}
		if got := doc.Rows["tk-a.1"].Line2; got != "Aim: land one" {
			t.Errorf("a Delivery's line 2 is its aim, got %q", got)
		}
		if got := doc.Rows["tk-b.1"].Anchored; len(got) != 1 || got[0].ID != "tk-review" {
			t.Errorf("tk-b.1 lists its review in Details: %+v", got)
		}
		if _, ok := doc.Rows["tk-review"]; ok {
			t.Error("a bead that carries anchor_bead has no row of its own")
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

// TestWorkAReaderCouldNotAnswer lists work whose pull request prstatus could
// not answer apart from the order, while the work behind it is placed as queue
// places it, behind that work. In graph, armed tk-b.2 waits on armed tk-b.1,
// which waits on question tk-q, and routed tk-loose waits on a park gate.
func TestWorkAReaderCouldNotAnswer(t *testing.T) {
	g := graph()
	for i := range g.open {
		if g.open[i].ID == "tk-b.1" {
			g.open[i].MergeResult, g.open[i].PRNumber = "pull_request", "12"
		}
	}
	g.noFacts["tk-b.1"] = true
	doc := boardOf(t, g)
	want := WorkQueue{Queue: []string{"tk-loose", "tk-b.2"}, NotScheduled: []string{"tk-a.1.1", "tk-loose2"}, Unread: []string{"tk-b.1"}}
	if !sameQueue(doc.WorkQueue, want) {
		t.Errorf("work queue = %+v, want %+v: tk-b.2 sits a layer past tk-b.1, which is listed apart", doc.WorkQueue, want)
	}
	if got := doc.Rows["tk-b.1"].Signal; got != signalUnread {
		t.Errorf("tk-b.1 reads %q, want %q", got, signalUnread)
	}
}

// TestWorkWhoseWaitsAreUnread lists apart work whose waits could not be
// answered, which queue places nowhere, even when its row reads as an ask. In
// graph, tk-loose is routed to a pool and waits on a park gate.
func TestWorkWhoseWaitsAreUnread(t *testing.T) {
	routedToYou := func(answered bool) Document {
		g := graph()
		for i := range g.open {
			if g.open[i].ID == "tk-loose" {
				g.open[i].PersonBlocker = true
			}
		}
		if !answered {
			delete(g.holds, "tk-loose")
			delete(g.holding, "tk-loose")
			g.unread["tk-loose"] = errors.New("its edges did not decode")
		}
		return boardOf(t, g)
	}
	if doc := routedToYou(true); doc.Rows["tk-loose"].Ask != AskRoutedToYou || !slices.Contains(doc.WorkQueue.Queue, "tk-loose") {
		t.Fatalf("answered, tk-loose asks %q in queue %v; want %q and queued, so the case is not built",
			doc.Rows["tk-loose"].Ask, doc.WorkQueue.Queue, AskRoutedToYou)
	}
	doc := routedToYou(false)
	want := WorkQueue{Queue: []string{"tk-b.1", "tk-b.2"}, NotScheduled: []string{"tk-a.1.1", "tk-loose2"}, Unread: []string{"tk-loose"}}
	if !sameQueue(doc.WorkQueue, want) {
		t.Errorf("work queue = %+v, want %+v: tk-loose has no place, so it is listed apart", doc.WorkQueue, want)
	}
	if a := doc.Rows["tk-loose"].Ask; a != AskRoutedToYou {
		t.Errorf("tk-loose asks %q, want %q", a, AskRoutedToYou)
	}
}

// TestWorkForTheProductOwner holds work that carries hold:mayor to the
// Unprioritized page while the work behind it still waits on it. In graph,
// tk-b.1 is armed and waits on question tk-q, and armed tk-b.2 waits on tk-b.1.
func TestWorkForTheProductOwner(t *testing.T) {
	hold := func(g *gathered, id string) {
		for i := range g.open {
			if g.open[i].ID == id {
				g.open[i].Labels = append(g.open[i].Labels, "hold:mayor")
			}
		}
	}
	entry := func(doc Document, e string) EpicEntry {
		for _, x := range doc.Epics {
			if x.ID == e {
				return x
			}
		}
		t.Fatalf("no epic %s", e)
		return EpicEntry{}
	}

	t.Run("work behind it comes after the queue, though it and the work are armed", func(t *testing.T) {
		g := graph()
		hold(g, "tk-b.1")
		doc := boardOf(t, g)
		want := WorkQueue{Queue: []string{"tk-loose"}, NotScheduled: []string{"tk-a.1.1", "tk-loose2", "tk-b.2"}, Unread: []string{}}
		if !sameQueue(doc.WorkQueue, want) {
			t.Errorf("work queue = %+v, want %+v: tk-b.2 waits on work the city takes only once it is placed", doc.WorkQueue, want)
		}
		if q := entry(doc, "tk-b").Queue; !sameQueue(q, WorkQueue{Queue: []string{}, NotScheduled: []string{"tk-b.2"}, Unread: []string{}}) {
			t.Errorf("tk-b's Work queue = %+v, want tk-b.2 alone, after the queue", q)
		}
		if c := doc.Rows["tk-b"].Counts; c == nil || *c != (Counts{Needs: 1, NotScheduled: 1, Closed: 1}) {
			t.Errorf("tk-b counts %+v, want its question, tk-b.2 after the queue and its closed work", c)
		}
		if got := doc.Unprioritized; len(got) != 1 || !slices.Equal(got[0].IDs, []string{"tk-desk2", "tk-desk1", "tk-b.1"}) {
			t.Errorf("unprioritized = %+v, want tk-b.1 with the desk", got)
		}
	})

	t.Run("a need reaches an epic only through work that is not held", func(t *testing.T) {
		g := graph()
		hold(g, "tk-b.1")
		g.open = slices.DeleteFunc(g.open, func(b bead) bool { return b.ID == "tk-b.2" })
		delete(g.holds, "tk-b.2")
		delete(g.holding, "tk-b.2")
		g.open = append(g.open, bead{ID: "tk-c", Title: "talk about B's story", Status: "open", Priority: 1, IssueType: "task",
			Assignee: "human", Edges: []listing.Edge{{ID: "tk-b.1", Type: "tracks"}}, CreatedAt: "2026-01-11"})
		g.holds["tk-c"] = waits.Holds{ID: "tk-c", Status: waits.Clear}
		doc := boardOf(t, g)
		if got := doc.Rows["tk-q"].Holds; !slices.Equal(got, []string{"tk-a.1.1"}) {
			t.Errorf("tk-q holds %v, want tk-a.1.1 alone", got)
		}
		if b := entry(doc, "tk-b"); len(b.Needs.Counted)+len(b.Needs.NotCounted) != 0 {
			t.Errorf("tk-b's Needs you = %+v, want none: its only open work is held for the Product Owner", b.Needs)
		}
		if c := doc.Rows["tk-b"].Counts; c == nil || *c != (Counts{Closed: 1}) {
			t.Errorf("tk-b counts %+v, want its closed work alone", c)
		}
		// tk-c is about held work alone, so it is listed and does not count.
		n := doc.NeedsYou
		if n.Count != 1 || !slices.EqualFunc(n.Counted, []Need{{ID: "tk-q", Kind: NeedKindQuestion, Holds: []string{"tk-a.1.1"}}}, sameNeed) ||
			!slices.EqualFunc(n.NotCounted, []Need{{ID: "tk-c", Kind: NeedKindWaitsForYou, Holds: []string{}}}, sameNeed) {
			t.Errorf("Needs you counts %d, lists %+v and folds %+v; want tk-q counted and tk-c folded", n.Count, n.Counted, n.NotCounted)
		}
	})

	t.Run("held work is no need, whatever it would ask of a person", func(t *testing.T) {
		routedToYou := func(held bool) Document {
			g := graph()
			if held {
				hold(g, "tk-b.1")
			}
			for i := range g.open {
				if g.open[i].ID == "tk-b.1" {
					g.open[i].PersonBlocker = true
				}
			}
			return boardOf(t, g)
		}
		if a := routedToYou(false).Rows["tk-b.1"].Ask; a != AskRoutedToYou {
			t.Fatalf("unheld, tk-b.1 asks %q, want %q, so the case is not built", a, AskRoutedToYou)
		}
		doc := routedToYou(true)
		if a := doc.Rows["tk-b.1"].Ask; a != "" {
			t.Errorf("held tk-b.1 asks %q, want no ask", a)
		}
		want := []Need{{ID: "tk-q", Kind: NeedKindQuestion, Holds: []string{"tk-a.1.1", "tk-b.2"}}}
		if n := doc.NeedsYou; n.Count != 1 || !slices.EqualFunc(n.Counted, want, sameNeed) {
			t.Errorf("Needs you counts %d and lists %+v, want 1 and %+v", n.Count, n.Counted, want)
		}
		if b := entry(doc, "tk-b"); !slices.EqualFunc(b.Needs.Counted, []Need{{ID: "tk-q", Kind: NeedKindQuestion, Holds: []string{"tk-b.2"}}}, sameNeed) {
			t.Errorf("tk-b's Needs you = %+v, want tk-q alone, holding tk-b.2", b.Needs)
		}
		if c := doc.Rows["tk-b"].Counts; c == nil || *c != (Counts{Needs: 1, NotScheduled: 1, Closed: 1}) {
			t.Errorf("tk-b counts %+v, want its question, tk-b.2 after the queue and its closed work", c)
		}
	})
}

// TestNeedOrder holds a view's needs to the order of the first bead each holds
// in the Work queue. tk-pr's pull request waits on the operator's review, and
// it is queued work itself, at the front of the queue. tk-g1 holds queued work,
// tk-g2 holds only work nobody scheduled, and decision tk-d holds nothing.
func TestNeedOrder(t *testing.T) {
	parent := listing.Edge{ID: "tk-e", Type: "parent-child"}
	blocks := func(id string) listing.Edge { return listing.Edge{ID: id, Type: "blocks"} }
	armed := &waits.Arm{Target: "gc-toolkit/gc-toolkit.polecat"}
	wait := func(id, issueType, awaitType string) waits.Wait {
		return waits.Wait{ID: id, Type: "blocks", Status: "open", IssueType: issueType, AwaitType: awaitType}
	}
	gate := func(id string) prstatus.Blocker {
		return prstatus.Blocker{ID: id, Status: "open", IssueType: "gate", AwaitType: "human"}
	}
	pr := prstatus.Blocker{ID: "tk-pr", Status: "open", IssueType: "task", Metadata: map[string]string{"merge_result": "pull_request"}}
	g := &gathered{rig: "gc-toolkit",
		open: []bead{
			{ID: "tk-e", Title: "Epic", Status: "open", Priority: 1, IssueType: "epic", Epic: listing.Epic{Hypothesis: "it works"}, CreatedAt: "2026-01-01"},
			{ID: "tk-g1", Title: "first question", Status: "open", Priority: 2, IssueType: "gate", AwaitType: "human", CreatedAt: "2026-01-01"},
			{ID: "tk-g2", Title: "second question", Status: "open", Priority: 0, IssueType: "gate", AwaitType: "human", CreatedAt: "2026-01-01"},
			{ID: "tk-d", Title: "a decision", Status: "open", Priority: 0, IssueType: "decision", Edges: []listing.Edge{parent}, CreatedAt: "2026-01-01"},
			{ID: "tk-pr", Title: "the change", Status: "open", Priority: 2, IssueType: "task", Edges: []listing.Edge{parent, blocks("tk-rework")},
				MergeResult: "pull_request", PRNumber: "9", CreatedAt: "2026-01-09"},
			{ID: "tk-rework", Title: "Rework the change", Status: "open", IssueType: "task", Anchor: "tk-pr", CreatedAt: "2026-01-10"},
			{ID: "tk-w1", Title: "behind the change", Status: "open", Priority: 2, IssueType: "task", Edges: []listing.Edge{parent, blocks("tk-pr")}, CreatedAt: "2026-01-02"},
			{ID: "tk-w2", Title: "behind the first question", Status: "open", Priority: 1, IssueType: "task", Edges: []listing.Edge{parent, blocks("tk-g1")}, CreatedAt: "2026-01-03"},
			{ID: "tk-w3", Title: "nobody scheduled", Status: "open", Priority: 0, IssueType: "task", Edges: []listing.Edge{parent, blocks("tk-g2")}, CreatedAt: "2026-01-04"},
		},
		holds: map[string]waits.Holds{
			"tk-e": {ID: "tk-e", Status: waits.Clear}, "tk-g1": {ID: "tk-g1", Status: waits.Clear}, "tk-g2": {ID: "tk-g2", Status: waits.Clear},
			"tk-d":  {ID: "tk-d", Status: waits.Clear},
			"tk-pr": {ID: "tk-pr", Status: waits.Blocked, Waits: []waits.Wait{wait("tk-rework", "task", "")}, InFlight: "carries merge_result"},
			"tk-w1": {ID: "tk-w1", Status: waits.Blocked, Waits: []waits.Wait{wait("tk-pr", "task", "")}, Arm: armed},
			"tk-w2": {ID: "tk-w2", Status: waits.Blocked, Waits: []waits.Wait{wait("tk-g1", "gate", "human")}, Arm: armed},
			"tk-w3": {ID: "tk-w3", Status: waits.Blocked, Waits: []waits.Wait{wait("tk-g2", "gate", "human")}},
		},
		unread: map[string]error{},
		holding: map[string]prstatus.Holds{
			"tk-pr": {},
			"tk-w1": {Owed: []prstatus.Blocker{pr}},
			"tk-w2": {Gates: []prstatus.Blocker{gate("tk-g1")}},
			"tk-w3": {Gates: []prstatus.Blocker{gate("tk-g2")}},
		},
		unwalked: map[string]bool{}, facts: map[string]prstatus.Facts{"tk-pr": {}}, noFacts: map[string]bool{},
	}
	doc := boardOf(t, g)

	if got := doc.WorkQueue.Queue; !slices.Equal(got, []string{"tk-pr", "tk-w2", "tk-w1"}) {
		t.Errorf("queue = %v, want the pull request first: its own rework puts nothing ahead of it", got)
	}
	want := []Need{
		{ID: "tk-pr", Kind: NeedKindPullRequest, Holds: []string{"tk-w1"}},
		{ID: "tk-g1", Kind: NeedKindQuestion, Holds: []string{"tk-w2"}},
		{ID: "tk-g2", Kind: NeedKindQuestion, Holds: []string{"tk-w3"}},
		{ID: "tk-d", Kind: NeedKindQuestion, Holds: []string{}},
	}
	if got := doc.Epics[0].Needs.Counted; !slices.EqualFunc(got, want, sameNeed) {
		t.Errorf("tk-e's Needs you = %+v, want %+v", got, want)
	}
	if got := doc.NeedsYou.Counted; !slices.EqualFunc(got, want, sameNeed) {
		t.Errorf("Needs you = %+v, want %+v, the same order as the epic's", got, want)
	}
	if r := doc.Rows["tk-pr"]; r.Ask != AskPullRequest || r.Signal != "needs-review" || !slices.Contains(doc.Epics[0].Queue.Queue, "tk-pr") {
		t.Errorf("tk-pr reads ask %q, signal %q, and the epic's queue is %v; want one row, a need in its queue", r.Ask, r.Signal, doc.Epics[0].Queue.Queue)
	}
	if got := doc.Rows["tk-w1"].Signal; got != "Waits on tk-pr" {
		t.Errorf("tk-w1 reads %q, want it to name the bead whose pull request it waits on", got)
	}
	if c := doc.Rows["tk-e"].Counts; c == nil || *c != (Counts{Needs: 4, Queue: 3, NotScheduled: 1}) {
		t.Errorf("tk-e counts %+v", c)
	}
}

// TestWorkUnderTwoParents builds work whose parent-child edges name two
// parents, in the order the row gives them, and holds each epic to the work it
// sits under, listed and counted once.
func TestWorkUnderTwoParents(t *testing.T) {
	parent := func(p string) listing.Edge { return listing.Edge{ID: p, Type: "parent-child"} }
	epic := func(id string, p int) bead {
		return bead{ID: id, Title: "Epic " + id, Status: "open", Priority: p, IssueType: "epic", Epic: listing.Epic{Hypothesis: "it works"}, CreatedAt: "2026-01-01"}
	}
	clear := func(id string) waits.Holds { return waits.Holds{ID: id, Status: waits.Clear} }
	empty := func(open, closed []bead, holds map[string]waits.Holds) *gathered {
		return &gathered{rig: "gc-toolkit", open: open, closed: closed, holds: holds, unread: map[string]error{},
			holding: map[string]prstatus.Holds{}, unwalked: map[string]bool{}, facts: map[string]prstatus.Facts{}, noFacts: map[string]bool{}}
	}
	entry := func(doc Document, e string) EpicEntry {
		for _, x := range doc.Epics {
			if x.ID == e {
				return x
			}
		}
		return EpicEntry{}
	}

	t.Run("a member whose first parent is a convoy sits under its epic", func(t *testing.T) {
		g := empty([]bead{epic("tk-e", 1)}, []bead{
			{ID: "tk-cv", Title: "input convoy", Status: "closed", IssueType: "convoy"},
			{ID: "tk-e.1", Title: "landed", Status: "closed", Priority: 2, IssueType: "task", Edges: []listing.Edge{parent("tk-cv"), parent("tk-e")}, CreatedAt: "2026-01-02"},
		}, map[string]waits.Holds{"tk-e": clear("tk-e")})
		doc := boardOf(t, g)
		if got := entry(doc, "tk-e").Closed; !slices.Equal(got, []string{"tk-e.1"}) {
			t.Errorf("tk-e lists closed %v, want tk-e.1", got)
		}
		if c := doc.Rows["tk-e"].Counts; c == nil || *c != (Counts{Closed: 1}) {
			t.Errorf("tk-e counts %+v, want 1 closed", c)
		}
	})

	t.Run("work under two epics that waits on a person is counted and asked under each", func(t *testing.T) {
		wq := waits.Wait{ID: "tk-q", Type: "blocks", Title: "which way?", Status: "open", IssueType: "gate", AwaitType: "human"}
		g := empty([]bead{
			epic("tk-e1", 1), epic("tk-e2", 2),
			{ID: "tk-q", Title: "which way?", Status: "open", Priority: 1, IssueType: "gate", AwaitType: "human", CreatedAt: "2026-01-02"},
			{ID: "tk-w", Title: "work under both", Status: "open", Priority: 2, IssueType: "task",
				Edges: []listing.Edge{parent("tk-e1"), parent("tk-e2"), {ID: "tk-q", Type: "blocks"}}, CreatedAt: "2026-01-03"},
		}, nil, map[string]waits.Holds{"tk-e1": clear("tk-e1"), "tk-e2": clear("tk-e2"), "tk-q": clear("tk-q"),
			"tk-w": {ID: "tk-w", Status: waits.Blocked, Waits: []waits.Wait{wq}}})
		g.holding["tk-w"] = prstatus.Holds{Gates: []prstatus.Blocker{{ID: "tk-q", Title: "which way?", Status: "open", IssueType: "gate", AwaitType: "human"}}}
		doc := boardOf(t, g)
		for _, e := range []string{"tk-e1", "tk-e2"} {
			x := entry(doc, e)
			if !slices.Equal(x.Queue.NotScheduled, []string{"tk-w"}) || !slices.EqualFunc(x.Needs.Counted, []Need{{ID: "tk-q", Kind: NeedKindQuestion, Holds: []string{"tk-w"}}}, sameNeed) {
				t.Errorf("%s lists %+v and %+v, want tk-w and its question", e, x.Queue, x.Needs)
			}
			if c := doc.Rows[e].Counts; c == nil || *c != (Counts{Needs: 1, NotScheduled: 1}) {
				t.Errorf("%s counts %+v, want its question and tk-w", e, c)
			}
		}
		if n := doc.NeedsYou; n.Count != 1 || !slices.EqualFunc(n.Counted, []Need{{ID: "tk-q", Kind: NeedKindQuestion, Holds: []string{"tk-w"}}}, sameNeed) {
			t.Errorf("Needs you counts %d and lists %+v, want 1 and the question once", n.Count, n.Counted)
		}
	})
}

// TestAChildEpicIsAMember holds an epic's ruling to a child epic that carries
// a hypothesis of its own. It reads as an epic, not a Delivery, and it is a
// member all the same: its parent asks for no ruling while it is open, and
// asks for one once it has closed with the rest.
func TestAChildEpicIsAMember(t *testing.T) {
	under := []listing.Edge{{ID: "tk-e", Type: "parent-child"}}
	epic := bead{ID: "tk-e", Title: "Epic", Status: "open", Priority: 1, IssueType: "epic", Epic: listing.Epic{Hypothesis: "it works"}, CreatedAt: "2026-01-01"}
	done := bead{ID: "tk-e.1", Title: "done", Status: "closed", Priority: 2, IssueType: "task", Edges: under, CreatedAt: "2026-01-02"}
	childEpic := func(status string) bead {
		return bead{ID: "tk-e.2", Title: "Child epic", Status: status, Priority: 2, IssueType: "epic",
			Epic: listing.Epic{Hypothesis: "its part works"}, Edges: under, CreatedAt: "2026-01-03"}
	}
	read := func(members ...bead) Document {
		g := &gathered{rig: "gc-toolkit", holds: map[string]waits.Holds{}, unread: map[string]error{},
			holding: map[string]prstatus.Holds{}, unwalked: map[string]bool{}, facts: map[string]prstatus.Facts{}, noFacts: map[string]bool{}}
		for _, b := range append([]bead{epic}, members...) {
			if !isOpen(b) {
				g.closed = append(g.closed, b)
				continue
			}
			g.open = append(g.open, b)
			g.holds[b.ID] = waits.Holds{ID: b.ID, Status: waits.Clear}
		}
		return boardOf(t, g)
	}

	t.Run("an open child epic keeps its parent from a ruling", func(t *testing.T) {
		doc := read(done, childEpic("open"))
		if k := doc.Rows["tk-e.2"].Kind; k != KindEpic {
			t.Fatalf("the child epic reads as %q, want an epic", k)
		}
		if r := doc.Rows["tk-e"]; r.Ask != "" || r.Group == GroupWaitingOnYou {
			t.Errorf("tk-e asks %q in group %q while its child epic is open, want no ask", r.Ask, r.Group)
		}
		if n := doc.NeedsYou.Count; n != 0 {
			t.Errorf("Needs you counts %d while the child epic is open, want 0", n)
		}
	})

	t.Run("a closed child epic is a closed member", func(t *testing.T) {
		if r := read(childEpic("closed")).Rows["tk-e"]; r.Ask != AskRuling || r.Signal != signalNeedsRuling {
			t.Errorf("tk-e asks %q and reads %q once its only member closed, want a ruling", r.Ask, r.Signal)
		}
	})
}

// TestAParentCycleEndsItsPath walks parent-child edges that come back to a
// bead the walk has passed: tk-c1 and tk-c2 name each other as parents, and
// tk-c2 also names epic tk-a. The walk ends, and tk-a lists each of them once.
func TestAParentCycleEndsItsPath(t *testing.T) {
	g := graph()
	parent := func(p string) listing.Edge { return listing.Edge{ID: p, Type: "parent-child"} }
	g.open = append(g.open,
		bead{ID: "tk-c1", Title: "one half", Status: "open", Priority: 2, IssueType: "task",
			Edges: []listing.Edge{parent("tk-c2")}, CreatedAt: "2026-01-11"},
		bead{ID: "tk-c2", Title: "other half", Status: "open", Priority: 2, IssueType: "task",
			Edges: []listing.Edge{parent("tk-c1"), parent("tk-a")}, CreatedAt: "2026-01-12"},
	)
	for _, id := range []string{"tk-c1", "tk-c2"} {
		g.holds[id] = waits.Holds{ID: id, Status: waits.Clear}
	}
	doc := boardOf(t, g)
	q := doc.Epics[0].Queue
	listed := append(append(append([]string{}, q.Queue...), q.NotScheduled...), q.Unread...)
	for _, id := range []string{"tk-c1", "tk-c2"} {
		if n := len(slices.DeleteFunc(slices.Clone(listed), func(x string) bool { return x != id })); n != 1 {
			t.Errorf("tk-a lists %s %d times, want once: %v", id, n, listed)
		}
	}
}

// TestAConversationAnsweringTwoQuestions holds one store to one document: a
// conversation that answers two questions stands in the first of them, so the
// work it holds up is held by that question on every build.
func TestAConversationAnsweringTwoQuestions(t *testing.T) {
	g := graph()
	g.open = append(g.open,
		bead{ID: "tk-b.3", Title: "talked about", Status: "open", Priority: 2, IssueType: "task",
			Edges: []listing.Edge{{ID: "tk-b", Type: "parent-child"}}, CreatedAt: "2026-01-11"},
		bead{ID: "tk-q2", Title: "and which?", Status: "open", Priority: 1, IssueType: "gate", AwaitType: "human", CreatedAt: "2026-01-11"},
		bead{ID: "tk-c", Title: "talk it through", Status: "open", Priority: 1, IssueType: "task", Assignee: "human", CreatedAt: "2026-01-11",
			Edges: []listing.Edge{{ID: "tk-b.3", Type: "tracks"}, {ID: "tk-q2", Type: "replies-to"}, {ID: "tk-q", Type: "replies-to"}}},
	)
	for _, id := range []string{"tk-q2", "tk-c"} {
		g.holds[id] = waits.Holds{ID: id, Status: waits.Clear}
	}
	conv := prstatus.Blocker{ID: "tk-c", Status: "open", IssueType: "task", Assignee: "human"}
	g.holds["tk-b.3"] = waits.Holds{ID: "tk-b.3", Status: waits.Blocked, Waits: []waits.Wait{{ID: "tk-c", Type: "blocks", Status: "open", IssueType: "task"}}}
	g.holding["tk-b.3"] = prstatus.Holds{Owed: []prstatus.Blocker{conv}}
	for range 20 {
		doc := boardOf(t, g)
		if !slices.Contains(doc.Rows["tk-q"].Holds, "tk-b.3") || slices.Contains(doc.Rows["tk-q2"].Holds, "tk-b.3") {
			t.Fatalf("tk-q holds %v and tk-q2 holds %v, want tk-b.3 under the first question its conversation answers",
				doc.Rows["tk-q"].Holds, doc.Rows["tk-q2"].Holds)
		}
	}
}

// TestAConversationThatStaysAndOneThatHolds holds the board to the stay's
// record. A conversation left open under its sitting over the work it sent
// waits for that work and is no need. One its sitting claimed back to hold,
// keeping the edge an earlier stay left onto work still out, owes the operator
// an answer, so Needs you counts it.
func TestAConversationThatStaysAndOneThatHolds(t *testing.T) {
	for _, c := range []struct {
		name, status string
		need         bool
		group        Group
		signal       string
	}{
		{name: "a stay", status: "open", group: GroupQueued, signal: "Waits on tk-w"},
		{name: "a hold over an earlier stay's work", status: "in_progress", need: true, group: GroupWaitingOnYou, signal: "In conversation"},
	} {
		t.Run(c.name, func(t *testing.T) {
			g := graph()
			g.open = append(g.open,
				bead{ID: "tk-w", Title: "the work it sent", Status: "open", Priority: 2, IssueType: "task", CreatedAt: "2026-01-11"},
				bead{ID: "tk-c", Title: "talk it through", Status: c.status, Priority: 1, IssueType: "task",
					Assignee: "gc-toolkit/gc-toolkit.tk-c", CreatedAt: "2026-01-11",
					Edges: []listing.Edge{{ID: "tk-b.1", Type: "tracks"}, {ID: "tk-w", Type: "blocks"}}},
			)
			g.holds["tk-w"] = waits.Holds{ID: "tk-w", Status: waits.Clear}
			g.holds["tk-c"] = waits.Holds{ID: "tk-c", Status: waits.Blocked,
				Waits: []waits.Wait{{ID: "tk-w", Type: "blocks", Title: "the work it sent", Status: "open", IssueType: "task"}}}
			doc := boardOf(t, g)
			on := func(ns []Need) bool { return slices.ContainsFunc(ns, func(n Need) bool { return n.ID == "tk-c" }) }
			if counted, uncounted := on(doc.NeedsYou.Counted), on(doc.NeedsYou.NotCounted); counted != c.need || uncounted {
				t.Errorf("Needs you counts tk-c: %v, and lists it uncounted: %v, want %v and false", counted, uncounted, c.need)
			}
			if r := doc.Rows["tk-c"]; r.Group != c.group || r.Signal != c.signal {
				t.Errorf("tk-c reads %q in %q, want %q in %q", r.Signal, r.Group, c.signal, c.group)
			}
		})
	}
}

// TestAPullRequestThatWaitsOnAStay holds a pull request whose merge its
// conversation holds to the stay that conversation keeps: the conversation
// waits on the rework it sent, so neither it nor its pull request is the
// operator's move until that rework closes, and then both are. The pull
// request's facts and what holds each row come from prstatus over the same
// beads, as gather reads them.
func TestAPullRequestThatWaitsOnAStay(t *testing.T) {
	sitting := "gc-toolkit/gc-toolkit.tk-c"
	for _, c := range []struct {
		name, rework      string
		counted           []string
		prGroup, cGroup   Group
		prSignal, cSignal string
	}{
		{name: "while the rework is out", rework: "in_progress",
			prGroup: GroupQueued, prSignal: "Pull request #7", cGroup: GroupQueued, cSignal: "Waits on tk-rw"},
		{name: "once the rework has closed", rework: "closed", counted: []string{"tk-c", "tk-pr"},
			prGroup: GroupWaitingOnYou, prSignal: "needs-attention", cGroup: GroupWaitingOnYou, cSignal: "In conversation"},
	} {
		t.Run(c.name, func(t *testing.T) {
			prMeta := map[string]string{"merge_result": "pull_request",
				"pr_posture": "review_required@abc@2026-10-27T00:00:00Z", "pr.machine": "settled@abc@2026-10-27T00:00:00Z"}
			store := fixture.NewStore([]fixture.Bead{
				{ID: "tk-pr", Title: "the change", Status: "open", IssueType: "task", WaitsOn: []string{"tk-c", "tk-rw"}, Metadata: prMeta},
				{ID: "tk-c", Title: "should this land as built?", Status: "open", IssueType: "task", Assignee: sitting,
					Tracks: []string{"tk-pr"}, WaitsOn: []string{"tk-rw"}},
				{ID: "tk-rw", Title: "rework the change", Status: c.rework, IssueType: "task",
					Metadata: map[string]string{"task_kind": "rework", "anchor_bead": "tk-pr", "source_ruling_bead": "tk-c"}},
			})
			wait := func(id, title, status string) waits.Wait {
				return waits.Wait{ID: id, Type: "blocks", Title: title, Status: status, IssueType: "task"}
			}
			conv := wait("tk-c", "should this land as built?", "open")
			rework := wait("tk-rw", "rework the change", c.rework)
			pr := bead{ID: "tk-pr", Title: "the change", Status: "open", Priority: 2, IssueType: "task", MergeResult: "pull_request", PRNumber: "7",
				Assignee: "gc-toolkit/refinery", CreatedAt: "2026-01-01",
				Edges: []listing.Edge{{ID: "tk-c", Type: "blocks"}, {ID: "tk-rw", Type: "blocks"}}}
			cb := bead{ID: "tk-c", Title: "should this land as built?", Status: "open", Priority: 2, IssueType: "task", Assignee: sitting,
				CreatedAt: "2026-01-02", Edges: []listing.Edge{{ID: "tk-pr", Type: "tracks"}, {ID: "tk-rw", Type: "blocks"}}}
			g := &gathered{rig: "gc-toolkit", open: []bead{pr, cb},
				holds: map[string]waits.Holds{
					"tk-pr": {ID: "tk-pr", Status: waits.Blocked, Waits: []waits.Wait{conv}, InFlight: "carries merge_result"},
					"tk-c":  {ID: "tk-c", Status: waits.Clear},
				},
				unread: map[string]error{}, unwalked: map[string]bool{}, noFacts: map[string]bool{}}
			if c.rework != "closed" {
				g.open = append(g.open, bead{ID: "tk-rw", Title: "rework the change", Status: c.rework, Priority: 2, IssueType: "task",
					Assignee: "gc-toolkit/gc-toolkit.polecat-1", Anchor: "tk-pr", CreatedAt: "2026-01-03"})
				g.holds["tk-pr"] = waits.Holds{ID: "tk-pr", Status: waits.Blocked, Waits: []waits.Wait{conv, rework}, InFlight: "carries merge_result"}
				g.holds["tk-c"] = waits.Holds{ID: "tk-c", Status: waits.Blocked, Waits: []waits.Wait{rework}}
				g.holds["tk-rw"] = waits.Holds{ID: "tk-rw", Status: waits.Clear, InFlight: "claimed"}
			}
			var ids []string
			for _, b := range g.open {
				ids = append(ids, b.ID)
			}
			var err error
			if g.holding, err = prstatus.Holding(holdingRoots(ids, g.holds), store.Blockers); err != nil {
				t.Fatal(err)
			}
			if g.facts, err = prstatus.Read([]string{"tk-pr"}, store); err != nil {
				t.Fatal(err)
			}
			doc := boardOf(t, g)
			var counted []string
			for _, n := range doc.NeedsYou.Counted {
				counted = append(counted, n.ID)
			}
			slices.Sort(counted)
			if !slices.Equal(counted, c.counted) {
				t.Errorf("Needs you counts %v, want %v", counted, c.counted)
			}
			if r := doc.Rows["tk-pr"]; r.Group != c.prGroup || r.Signal != c.prSignal {
				t.Errorf("tk-pr reads %q in %q, want %q in %q", r.Signal, r.Group, c.prSignal, c.prGroup)
			}
			if r := doc.Rows["tk-c"]; r.Group != c.cGroup || r.Signal != c.cSignal {
				t.Errorf("tk-c reads %q in %q, want %q in %q", r.Signal, r.Group, c.cSignal, c.cGroup)
			}
		})
	}
}

// TestNeedsThatCount holds each view to the needs that count. Gate tk-park
// parks epics tk-pe, whose members have all closed so it asks for a ruling, and
// tk-pf, which holds pull request tk-pr in flight. Question tk-pq waits on the
// park itself. Question tk-qp holds only work the park holds, question tk-qd
// only work held for the Product Owner, and question tk-qf one of each beside
// work under epic tk-e. Pull request tk-pr2 holds only parked work. Decision
// tk-d stands alone. Conversation tk-c1 waits for you about tk-e's work, a
// sitting holds conversation tk-c2 about the parked work, and a sitting holds
// conversation tk-cs, which answers question tk-qs.
func TestNeedsThatCount(t *testing.T) {
	parent := func(p string) listing.Edge { return listing.Edge{ID: p, Type: "parent-child"} }
	blocks := func(id string) listing.Edge { return listing.Edge{ID: id, Type: "blocks"} }
	tracks := func(id string) listing.Edge { return listing.Edge{ID: id, Type: "tracks"} }
	park := waits.Wait{ID: "tk-park", Type: "blocks", Title: "parked", Status: "open", IssueType: "gate"}
	question := func(id string) waits.Wait {
		return waits.Wait{ID: id, Type: "blocks", Status: "open", IssueType: "gate", AwaitType: "human"}
	}
	gate := func(id string) prstatus.Blocker {
		return prstatus.Blocker{ID: id, Status: "open", IssueType: "gate", AwaitType: "human"}
	}
	blocked := func(id string, ws ...waits.Wait) waits.Holds {
		return waits.Holds{ID: id, Status: waits.Blocked, Waits: ws}
	}
	clear := func(id string) waits.Holds { return waits.Holds{ID: id, Status: waits.Clear} }
	inFlight := waits.Holds{Status: waits.Clear, InFlight: "carries merge_result"}
	epic := func(id string, edges ...listing.Edge) bead {
		return bead{ID: id, Title: "Epic " + id, Status: "open", Priority: 1, IssueType: "epic", Epic: listing.Epic{Hypothesis: "it works"},
			Edges: edges, CreatedAt: "2026-01-01"}
	}
	task := func(id string, edges ...listing.Edge) bead {
		return bead{ID: id, Title: "work " + id, Status: "open", Priority: 2, IssueType: "task", Edges: edges, CreatedAt: "2026-01-02"}
	}
	human := func(id string) bead {
		return bead{ID: id, Title: "question " + id, Status: "open", Priority: 2, IssueType: "gate", AwaitType: "human", CreatedAt: "2026-01-03"}
	}
	conv := func(id, assignee string, edges ...listing.Edge) bead {
		return bead{ID: id, Title: "talk " + id, Status: "open", Priority: 2, IssueType: "task", Assignee: assignee, Edges: edges, CreatedAt: "2026-01-04"}
	}
	pr := func(id string, edges ...listing.Edge) bead {
		b := task(id, edges...)
		b.MergeResult, b.PRNumber = "pull_request", "1"
		return b
	}
	pq := human("tk-pq")
	pq.Edges = []listing.Edge{blocks("tk-park")}
	desk, desk2 := task("tk-desk", blocks("tk-qd")), task("tk-desk2", blocks("tk-qf"))
	desk.Labels, desk2.Labels = []string{"hold:mayor"}, []string{"hold:mayor"}
	g := &gathered{rig: "gc-toolkit",
		open: []bead{
			epic("tk-e"), epic("tk-pe", blocks("tk-park")), epic("tk-pf", blocks("tk-park")),
			{ID: "tk-park", Title: "parked", Status: "open", Priority: 2, IssueType: "gate", CreatedAt: "2026-01-01"},
			pr("tk-pr", parent("tk-pf")), pr("tk-pr2"), task("tk-wb", blocks("tk-pr2"), blocks("tk-park")),
			pq, human("tk-qp"), task("tk-wp", blocks("tk-qp"), blocks("tk-park")),
			human("tk-qd"), desk,
			human("tk-qf"), task("tk-wf", parent("tk-e"), blocks("tk-qf")), desk2,
			{ID: "tk-d", Title: "a decision", Status: "open", Priority: 2, IssueType: "decision", CreatedAt: "2026-01-05"},
			conv("tk-c1", "human", tracks("tk-wf")),
			conv("tk-c2", "gc-toolkit/gc-toolkit.tk-c2", tracks("tk-wp")),
			human("tk-qs"), task("tk-ws", blocks("tk-qs")),
			conv("tk-cs", "gc-toolkit/gc-toolkit.tk-cs", tracks("tk-ws"), listing.Edge{ID: "tk-qs", Type: "replies-to"}),
		},
		closed: []bead{{ID: "tk-pe.1", Title: "landed", Status: "closed", Priority: 2, IssueType: "task", Edges: []listing.Edge{parent("tk-pe")}}},
		holds: map[string]waits.Holds{
			"tk-e": clear("tk-e"), "tk-pe": blocked("tk-pe", park), "tk-pf": blocked("tk-pf", park), "tk-park": clear("tk-park"),
			"tk-pr": inFlight, "tk-pr2": inFlight,
			"tk-wb": blocked("tk-wb", waits.Wait{ID: "tk-pr2", Type: "blocks", Status: "open", IssueType: "task"}, park),
			"tk-pq": blocked("tk-pq", park), "tk-qp": clear("tk-qp"), "tk-wp": blocked("tk-wp", question("tk-qp"), park),
			"tk-qd": clear("tk-qd"), "tk-desk": blocked("tk-desk", question("tk-qd")),
			"tk-qf": clear("tk-qf"), "tk-wf": blocked("tk-wf", question("tk-qf")), "tk-desk2": blocked("tk-desk2", question("tk-qf")),
			"tk-d": clear("tk-d"), "tk-c1": clear("tk-c1"), "tk-c2": clear("tk-c2"),
			"tk-qs": clear("tk-qs"), "tk-ws": blocked("tk-ws", question("tk-qs")), "tk-cs": clear("tk-cs"),
		},
		unread: map[string]error{},
		holding: map[string]prstatus.Holds{
			"tk-pe": {}, "tk-pf": {}, "tk-pq": {},
			"tk-wb":    {Owed: []prstatus.Blocker{{ID: "tk-pr2", Status: "open", IssueType: "task", Metadata: map[string]string{"merge_result": "pull_request"}}}},
			"tk-wp":    {Gates: []prstatus.Blocker{gate("tk-qp")}},
			"tk-desk":  {Gates: []prstatus.Blocker{gate("tk-qd")}},
			"tk-wf":    {Gates: []prstatus.Blocker{gate("tk-qf")}},
			"tk-desk2": {Gates: []prstatus.Blocker{gate("tk-qf")}},
			"tk-ws":    {Gates: []prstatus.Blocker{gate("tk-qs")}},
		},
		unwalked: map[string]bool{}, facts: map[string]prstatus.Facts{"tk-pr": {}, "tk-pr2": {}}, noFacts: map[string]bool{},
	}
	doc := boardOf(t, g)
	ids := func(needs []Need) []string {
		var out []string
		for _, n := range needs {
			out = append(out, n.ID)
		}
		slices.Sort(out)
		return out
	}
	kindOf := func(v NeedsYou, id string) NeedKind {
		for _, n := range append(slices.Clone(v.Counted), v.NotCounted...) {
			if n.ID == id {
				return n.Kind
			}
		}
		return ""
	}
	entry := func(e string) EpicEntry {
		for _, x := range doc.Epics {
			if x.ID == e {
				return x
			}
		}
		t.Fatalf("no epic %s", e)
		return EpicEntry{}
	}

	n := doc.NeedsYou
	t.Run("the rig counts every need that counts, under an epic or not", func(t *testing.T) {
		if got, want := ids(n.Counted), []string{"tk-c1", "tk-d", "tk-pr2", "tk-qf", "tk-qs"}; n.Count != len(want) || !slices.Equal(got, want) {
			t.Errorf("Needs you counts %d: %v, want %v", n.Count, got, want)
		}
	})
	t.Run("a need about parked or held work, or parked itself, is listed apart", func(t *testing.T) {
		if got, want := ids(n.NotCounted), []string{"tk-c2", "tk-pe", "tk-pq", "tk-pr", "tk-qd", "tk-qp"}; !slices.Equal(got, want) {
			t.Errorf("Needs you folds %v, want %v", got, want)
		}
		if r := doc.Rows["tk-pe"]; r.Ask != AskRuling {
			t.Errorf("the parked epic asks %q, want a ruling, so the case is not built", r.Ask)
		}
		if got := doc.Rows["tk-qd"].Holds; len(got) != 0 {
			t.Errorf("tk-qd holds %v, want none listed: its work is held for the Product Owner", got)
		}
	})
	t.Run("each need is of its kind, and the view counts each kind that counts", func(t *testing.T) {
		for id, want := range map[string]NeedKind{
			"tk-pr2": NeedKindPullRequest, "tk-qf": NeedKindQuestion, "tk-d": NeedKindQuestion, "tk-c1": NeedKindWaitsForYou,
			"tk-qs": NeedKindInConversation, "tk-c2": NeedKindInConversation, "tk-pe": NeedKindRuling,
		} {
			if got := kindOf(n, id); got != want {
				t.Errorf("%s is of kind %q, want %q", id, got, want)
			}
		}
		want := []KindCount{{NeedKindPullRequest, 1}, {NeedKindQuestion, 2}, {NeedKindWaitsForYou, 1}, {NeedKindInConversation, 1}, {NeedKindRuling, 0}}
		if !slices.Equal(n.Kinds, want) {
			t.Errorf("kinds = %+v, want %+v: the five kinds, a zero among them, and no Routed to you", n.Kinds, want)
		}
	})
	t.Run("an epic's view counts its own needs by the same rule", func(t *testing.T) {
		e := entry("tk-e").Needs
		if got := ids(e.Counted); e.Count != 2 || !slices.Equal(got, []string{"tk-c1", "tk-qf"}) || len(e.NotCounted) != 0 {
			t.Errorf("tk-e's Needs you counts %d: %v, folds %v", e.Count, got, ids(e.NotCounted))
		}
		if want := []KindCount{{NeedKindPullRequest, 0}, {NeedKindQuestion, 1}, {NeedKindWaitsForYou, 1}, {NeedKindInConversation, 0}, {NeedKindRuling, 0}}; !slices.Equal(e.Kinds, want) {
			t.Errorf("tk-e's kinds = %+v, want %+v", e.Kinds, want)
		}
		f := entry("tk-pf").Needs
		if f.Count != 0 || len(f.Counted) != 0 || !slices.Equal(ids(f.NotCounted), []string{"tk-pr"}) {
			t.Errorf("the parked epic's Needs you counts %d and folds %v, want 0 and its pull request", f.Count, ids(f.NotCounted))
		}
		for id, want := range map[string]int{"tk-e": 2, "tk-pf": 0, "tk-pe": 0} {
			if c := doc.Rows[id].Counts; c == nil || c.Needs != want {
				t.Errorf("%s counts %+v needs, want %d", id, c, want)
			}
		}
	})
	t.Run("routed to you is a kind only where one counts", func(t *testing.T) {
		routed := func(id string) NeedsYou {
			g := graph()
			for i := range g.open {
				if g.open[i].ID == id {
					g.open[i].PersonBlocker = true
				}
			}
			return boardOf(t, g).NeedsYou
		}
		// tk-loose waits on a park, so it is listed apart and its kind is not counted.
		if v := routed("tk-loose"); len(v.Kinds) != 5 || !slices.Contains(ids(v.NotCounted), "tk-loose") {
			t.Errorf("a parked routed need gives kinds %+v and folds %v", v.Kinds, ids(v.NotCounted))
		}
		if v := routed("tk-b.1"); len(v.Kinds) != 6 || v.Kinds[5] != (KindCount{NeedKindRoutedToYou, 1}) {
			t.Errorf("a routed need that counts gives kinds %+v, want Routed to you last", v.Kinds)
		}
	})
}
