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

// TestReadPlacesWorkUnderEveryEpicItSitsUnder reads work whose parent-child
// edges name more than one parent, which bd allows. tk-w sits under two open
// epics and waits on a human gate, so each epic lists it, counts it as waiting
// on you and carries its question, and Needs you counts the question once.
// tk-w2's first parent, as the stub store orders a row's edges by id, is a
// closed task the read does not gather, which costs it nothing under the epic
// it also names. tk-w3 reaches tk-e1 both directly and through tk-x, and tk-e1
// lists and counts it once.
func TestReadPlacesWorkUnderEveryEpicItSitsUnder(t *testing.T) {
	rows := []json.RawMessage{
		json.RawMessage(`{"id":"tk-e1","title":"Epic one","status":"open","priority":1,"issue_type":"epic","metadata":{"epic_hypothesis":"one works"},"created_at":"2026-01-01"}`),
		json.RawMessage(`{"id":"tk-e2","title":"Epic two","status":"open","priority":2,"issue_type":"epic","metadata":{"epic_hypothesis":"two works"},"created_at":"2026-01-02"}`),
		json.RawMessage(`{"id":"tk-q","title":"which way?","status":"open","priority":1,"issue_type":"gate","await_type":"human","created_at":"2026-01-03"}`),
		json.RawMessage(`{"id":"tk-w","title":"work under both","status":"open","priority":2,"issue_type":"task","dependencies":[{"issue_id":"tk-w","depends_on_id":"tk-e1","type":"parent-child"},{"issue_id":"tk-w","depends_on_id":"tk-e2","type":"parent-child"},{"issue_id":"tk-w","depends_on_id":"tk-q","type":"blocks"}],"created_at":"2026-01-04"}`),
		json.RawMessage(`{"id":"tk-done","title":"landed story","status":"closed","priority":2,"issue_type":"task","created_at":"2026-01-05"}`),
		json.RawMessage(`{"id":"tk-w2","title":"follow-up","status":"open","priority":2,"issue_type":"task","dependencies":[{"issue_id":"tk-w2","depends_on_id":"tk-done","type":"parent-child"},{"issue_id":"tk-w2","depends_on_id":"tk-e2","type":"parent-child"}],"created_at":"2026-01-06"}`),
		json.RawMessage(`{"id":"tk-x","title":"story","status":"open","priority":2,"issue_type":"task","dependencies":[{"issue_id":"tk-x","depends_on_id":"tk-e1","type":"parent-child"}],"created_at":"2026-01-07"}`),
		json.RawMessage(`{"id":"tk-w3","title":"part of the story","status":"open","priority":2,"issue_type":"task","dependencies":[{"issue_id":"tk-w3","depends_on_id":"tk-e1","type":"parent-child"},{"issue_id":"tk-w3","depends_on_id":"tk-x","type":"parent-child"}],"created_at":"2026-01-08"}`),
	}
	doc, err := Read(context.Background(), stubStore(t, rows))
	if err != nil {
		t.Fatalf("Read: %v", err)
	}
	if _, ok := doc.Rows["tk-done"]; ok {
		t.Fatal("the read gathered tk-done, so it does not stand for a parent the read leaves out")
	}
	listed := map[string][]string{}
	for _, e := range doc.Epics {
		for _, g := range e.Groups {
			listed[e.ID] = append(listed[e.ID], g.IDs...)
		}
		listed[e.ID] = append(listed[e.ID], e.Unread...)
		slices.Sort(listed[e.ID])
	}
	for epic, want := range map[string][]string{"tk-e1": {"tk-w", "tk-w3", "tk-x"}, "tk-e2": {"tk-w", "tk-w2"}} {
		if !slices.Equal(listed[epic], want) {
			t.Errorf("%s lists %v, want %v, each once", epic, listed[epic], want)
		}
		c := doc.Rows[epic].Counts
		if c == nil || c.WaitingOnYou != 1 || c.WaitingOnYou+c.Queued+c.NotMoving+c.Closed != len(want) {
			t.Errorf("%s counts %+v, want tk-w waiting on you and %d rows in all", epic, c, len(want))
		}
	}
	if got := doc.Rows["tk-w"].Group; got != GroupWaitingOnYou {
		t.Errorf("tk-w is in %q, want waiting on you", got)
	}
	n := doc.NeedsYou
	var under []string
	for _, e := range n.NoConversationYet {
		if slices.Contains(e.Asks, "tk-q") {
			under = append(under, e.Epic)
		}
	}
	if n.Count != 1 || !slices.Equal(under, []string{"tk-e1", "tk-e2"}) {
		t.Errorf("Needs you counts %d and lists tk-q under %v, want 1 and both epics", n.Count, under)
	}
}
