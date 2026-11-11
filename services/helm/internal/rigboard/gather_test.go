package rigboard

import (
	"context"
	"slices"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// TestReadGathersALandedDelivery reads, through the read's own gather, a
// Delivery that landed while its epic stays open, the lifecycle docs/epics.md
// gives under "How a Delivery ends". The story under the Delivery is read, the
// Epics page lists it in the Delivery's closed group, and it counts as closed
// in both the Delivery and the epic.
func TestReadGathersALandedDelivery(t *testing.T) {
	parent := func(p string) []edge { return []edge{{DependsOnID: p, Type: "parent-child"}} }
	gc := &fakeGC{rows: []bead{
		{ID: "tk-e", Title: "Epic", Status: "open", Priority: 1, IssueType: "epic", Metadata: md("epic_hypothesis", "it works"), CreatedAt: "2026-01-01"},
		{ID: "tk-e.1", Title: "Delivery: one", Status: "closed", Priority: 1, IssueType: "epic", Description: "Aim: land one", Dependencies: parent("tk-e"), CreatedAt: "2026-01-02"},
		{ID: "tk-e.1.1", Title: "story under the delivery", Status: "closed", Priority: 2, IssueType: "task", Dependencies: parent("tk-e.1"), CreatedAt: "2026-01-03"},
	}}
	noHolds := func(context.Context, string, []string) (map[string]waits.Holds, map[string]error, error) {
		return map[string]waits.Holds{}, map[string]error{}, nil
	}
	doc, err := Read(context.Background(), gc, Rig{Name: "gc-toolkit", Store: "/fixture/gc-toolkit/.beads"}, noHolds)
	if err != nil {
		t.Fatalf("Read: %v", err)
	}
	if k := doc.Rows["tk-e.1"].Kind; k != KindDelivery {
		t.Fatalf("tk-e.1 reads as %q, want a Delivery", k)
	}
	if r, ok := doc.Rows["tk-e.1.1"]; !ok || r.Group != GroupClosed {
		t.Errorf("the story under the landed Delivery reads as %+v (read: %v), want a closed row", r, ok)
	}
	if len(doc.Epics) != 1 || len(doc.Epics[0].Deliveries) != 1 ||
		!slices.EqualFunc(doc.Epics[0].Deliveries[0].Groups, []GroupList{{Group: GroupClosed, IDs: []string{"tk-e.1.1"}}},
			func(a, b GroupList) bool { return a.Group == b.Group && slices.Equal(a.IDs, b.IDs) }) {
		t.Errorf("the Epics page reads %+v, want the story in the Delivery's closed group", doc.Epics)
	}
	for _, id := range []string{"tk-e.1", "tk-e"} {
		if c := doc.Rows[id].Counts; c == nil || c.Closed != 1 {
			t.Errorf("%s counts %+v, want 1 closed", id, c)
		}
	}
}
