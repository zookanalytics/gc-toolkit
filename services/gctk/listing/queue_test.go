package listing

import (
	"slices"
	"testing"

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
