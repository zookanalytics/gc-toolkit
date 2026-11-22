package listing

import (
	"slices"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/queue"
)

// queue reads each bead's row as the listing decoded it, closed or live, and a
// bead the store does not hold has no row.
func TestListingRowsForTheQueue(t *testing.T) {
	ls, err := read(ledger.New(rig()))
	if err != nil {
		t.Fatal(err)
	}
	rows, err := ls.Rows([]string{"tk-e.2", "tk-review", "tk-old", "tk-gone"})
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 3 {
		t.Errorf("rows = %+v, want the three beads the store holds", rows)
	}
	if r := rows["tk-e.2"]; r.Status != "open" || r.Priority != 2 || r.RoutedTo != "gc-toolkit/gc-toolkit.polecat" ||
		!slices.Equal(r.Labels, []string{"hold:mayor"}) || r.Anchor != "" {
		t.Errorf("the story reads %+v", r)
	}
	if r := rows["tk-review"]; r.Anchor != "tk-e.2" {
		t.Errorf("the review reads %+v, want its anchor", r)
	}
	if r := rows["tk-old"]; r.Status != "closed" {
		t.Errorf("the closed bead reads %+v", r)
	}
}

// The order work lands in comes from the listing's rows, as the other domains'
// answers do: a write that lands after the listing changes nothing in it, and
// the order reads none of the beads the listing holds again.
func TestListingAnswersTheQueueFromItsRows(t *testing.T) {
	s := rig()
	ls, err := read(ledger.New(s))
	if err != nil {
		t.Fatal(err)
	}
	listed := len(s.Finds())
	s.Put(fake.Bead{ID: "tk-q", Title: "which way?", Status: "closed", IssueType: "gate", AwaitType: "human"})
	s.Put(fake.Bead{ID: "tk-ask", Title: "routed to a person", Status: "open", IssueType: "task"})

	o, err := queue.Order([]string{"tk-e.2", "tk-ask"}, ls)
	if err != nil {
		t.Fatal(err)
	}
	want := []queue.Place{{ID: "tk-ask", Layer: 0, Scheduled: true}, {ID: "tk-e.2", Layer: 1, Scheduled: true}}
	if !slices.Equal(o.Queue, want) || len(o.NotScheduled)+len(o.Unread) != 0 {
		t.Errorf("order = %+v; want %+v: the story in flight behind the gate the listing read open, and the route it read", o, want)
	}
	for _, q := range s.Finds()[listed:] {
		for _, id := range q.IDs {
			if slices.Contains([]string{"tk-e.2", "tk-q", "tk-ask"}, id) {
				t.Errorf("the order read %s again, which the listing holds: %+v", id, q)
			}
		}
		if q.HasKey != "" || q.Key != "" || q.Every {
			t.Errorf("the order read the store by a key or whole: %+v", q)
		}
	}
}

// The ready work nothing sends comes from the store's ready set and the live
// runs the listing read. A bead whose run has ended is unsent, though its row
// keeps the route its pour stamped and the branch its run cut, and a bead a
// live run works is sent before that run has passed load-context. A bead held
// hold:external waits outside the city.
func TestListingAnswersTheReadyWorkNothingSends(t *testing.T) {
	s := rig()
	polecat := "gc-toolkit/gc-toolkit.polecat"
	run := func(convoy string) map[string]string {
		return map[string]string{"gc.kind": "workflow", "gc.formula_contract": "graph.v2", "gc.input_convoy_id": convoy}
	}
	for _, b := range []fake.Bead{
		{ID: "tk-ended", Title: "its run ended", Status: "open", IssueType: "task", Priority: 2,
			Metadata: map[string]string{"gc.execution_routed_to": polecat, "branch": "polecat/tk-ended"}},
		{ID: "tk-ended-root", Title: "mol-polecat-work", Status: "closed", IssueType: "task", Metadata: run("tk-ended-cv")},
		{ID: "tk-ended-cv", Title: "convoy", Status: "closed", IssueType: "convoy", Edges: []gcbd.Edge{{Type: "tracks", ID: "tk-ended"}}},
		{ID: "tk-poured", Title: "just poured", Status: "open", IssueType: "task", Priority: 2,
			Metadata: map[string]string{"gc.execution_routed_to": polecat}},
		{ID: "tk-poured-root", Title: "mol-polecat-work", Status: "open", IssueType: "task", Metadata: run("tk-poured-cv")},
		{ID: "tk-poured-step", Title: "Load context", Status: "open", IssueType: "task",
			Metadata: map[string]string{"gc.root_bead_id": "tk-poured-root", "gc.step_ref": "mol-polecat-work.load-context"}},
		{ID: "tk-poured-cv", Title: "convoy", Status: "open", IssueType: "convoy", Edges: []gcbd.Edge{{Type: "tracks", ID: "tk-poured"}}},
		{ID: "tk-away", Title: "waits on a vendor", Status: "open", IssueType: "task", Priority: 2, Labels: []string{"Hold:External"}},
	} {
		s.Put(b)
	}
	s.MakeReady("tk-ended", "tk-poured", "tk-away", "tk-ask")
	ls, err := read(ledger.New(s))
	if err != nil {
		t.Fatal(err)
	}
	holds, _, err := ls.Holds([]string{"tk-ended", "tk-poured"})
	if err != nil {
		t.Fatal(err)
	}
	if holds["tk-ended"].InFlight == "" || holds["tk-poured"].InFlight != "" {
		t.Fatalf("waits reads tk-ended in flight %q and tk-poured %q; want the branch to read as in flight and the fresh run not yet",
			holds["tk-ended"].InFlight, holds["tk-poured"].InFlight)
	}

	o, err := queue.Order([]string{"tk-ended", "tk-poured", "tk-away", "tk-ask"}, ls)
	if err != nil {
		t.Fatal(err)
	}
	if want := []queue.Place{{ID: "tk-ended", Layer: 0}}; !slices.Equal(o.NotScheduled, want) {
		t.Errorf("not scheduled = %+v, want %+v: the stamps an ended run left send nothing", o.NotScheduled, want)
	}
	want := []queue.Place{
		{ID: "tk-ask", Layer: 0, Scheduled: true},
		{ID: "tk-away", Layer: 0, Outside: true},
		{ID: "tk-poured", Layer: 0, Scheduled: true},
	}
	if !slices.Equal(o.Queue, want) || len(o.Unread) != 0 {
		t.Errorf("queue = %+v and unread %v; want %+v and none", o.Queue, o.Unread, want)
	}
}
