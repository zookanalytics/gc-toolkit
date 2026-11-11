package rigboard

import (
	"context"
	"encoding/json"
	"slices"
	"testing"
)

// TestReadGathersALandedDelivery reads, through the read itself, a Delivery
// that landed while its epic stays open, the lifecycle docs/epics.md gives
// under "How a Delivery ends". The story under the Delivery is read, the Epics
// page lists it in the Delivery's closed group, and it counts as closed in
// both the Delivery and the epic.
func TestReadGathersALandedDelivery(t *testing.T) {
	rows := []json.RawMessage{
		json.RawMessage(`{"id":"tk-e","title":"Epic","status":"open","priority":1,"issue_type":"epic","metadata":{"epic_hypothesis":"it works"},"created_at":"2026-01-01"}`),
		json.RawMessage(`{"id":"tk-e.1","title":"Delivery: one","status":"closed","priority":1,"issue_type":"epic","description":"Aim: land one","dependencies":[{"issue_id":"tk-e.1","depends_on_id":"tk-e","type":"parent-child"}],"created_at":"2026-01-02"}`),
		json.RawMessage(`{"id":"tk-e.1.1","title":"story under the delivery","status":"closed","priority":2,"issue_type":"task","dependencies":[{"issue_id":"tk-e.1.1","depends_on_id":"tk-e.1","type":"parent-child"}],"created_at":"2026-01-03"}`),
	}
	doc, err := Read(context.Background(), stubStore(t, rows))
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
