package rigboard

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/standing"
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

// TestReadLeavesOutStandingRecords reads two standing records of each kind the
// one definition names (services/gctk/standing): one that waits on nothing,
// which the Work queue would list as not scheduled, and one that waits on a
// park gate, as a triage subject waits on the beads in its pile. Beside them
// are work that is not scheduled, work of a kind that only resembles a
// standing kind, and work the gate holds. No standing record is a row: the
// Work queue lists the work and not the records, and the gate holds and is
// waited on by the work alone.
func TestReadLeavesOutStandingRecords(t *testing.T) {
	row := func(id, kind, edges string) json.RawMessage {
		meta := ""
		if kind != "" {
			meta = `,"metadata":{"task_kind":` + strconv.Quote(kind) + `}`
		}
		return json.RawMessage(`{"id":"` + id + `","title":"` + id + `","status":"open","priority":2,"issue_type":"task","created_at":"2026-01-02"` +
			meta + `,"dependencies":[` + edges + `]}`)
	}
	onPark := func(id string) string {
		return `{"issue_id":"` + id + `","depends_on_id":"tk-park","type":"blocks"}`
	}
	rows := []json.RawMessage{
		json.RawMessage(`{"id":"tk-park","title":"parked","status":"open","priority":2,"issue_type":"gate","created_at":"2026-01-01"}`),
		row("tk-work", "", ""),
		row("tk-held", "", onPark("tk-held")),
	}
	var records, notScheduled []string
	for i, k := range standing.Kinds() {
		n := strconv.Itoa(i)
		records = append(records, "tk-s"+n, "tk-sp"+n)
		notScheduled = append(notScheduled, "tk-near"+n)
		rows = append(rows, row("tk-s"+n, k, ""), row("tk-sp"+n, k, onPark("tk-sp"+n)), row("tk-near"+n, k+"s", ""))
	}
	if len(records) == 0 {
		t.Fatal("the definition names no standing kind")
	}
	doc, err := Read(context.Background(), stubStore(t, rows))
	if err != nil {
		t.Fatalf("Read: %v", err)
	}
	for _, id := range records {
		if _, ok := doc.Rows[id]; ok {
			t.Errorf("standing record %s is a row", id)
		}
	}
	listed, holds := map[string][]string{}, map[string][]string{}
	for _, s := range doc.WorkQueue {
		for _, e := range s.Rows {
			listed[s.Name] = append(listed[s.Name], e.ID)
			holds[e.ID] = e.Children
		}
	}
	notScheduled = append(notScheduled, "tk-work")
	slices.Sort(notScheduled)
	slices.Sort(listed[sectionNotScheduled])
	if !slices.Equal(listed[sectionNotScheduled], notScheduled) {
		t.Errorf("not scheduled lists %v, want %v", listed[sectionNotScheduled], notScheduled)
	}
	if !slices.Equal(listed[sectionHeldByGate], []string{"tk-park"}) || !slices.Equal(holds["tk-park"], []string{"tk-held"}) {
		t.Errorf("held by a gate lists %v holding %v, want tk-park holding tk-held alone", listed[sectionHeldByGate], holds["tk-park"])
	}
	if got := doc.Rows["tk-park"].WaitedOnBy; len(got) != 1 || got[0].ID != "tk-held" {
		t.Errorf("tk-park is waited on by %+v, want tk-held alone", got)
	}
}

// TestReadThatRunsOutStopsItsStoreCalls reads through a gc that does what
// `gc bd` does when the store hangs: it starts a child that holds the call's
// output, as gc runs bd, and waits on it. Read returns the deadline's error
// soon after the deadline, the stub gc has ended by the time it does, and the
// call's whole process group, the child among it, is gone, so the next read
// starts beside nothing.
func TestReadThatRunsOutStopsItsStoreCalls(t *testing.T) {
	dir := t.TempDir()
	group := filepath.Join(dir, "group")
	stub := "#!/bin/sh\nsleep 30 &\necho $$ > \"$STUB_GROUP\"\nwait\n"
	if err := os.WriteFile(filepath.Join(dir, "gc"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STUB_GROUP", group)
	t.Setenv("GC_NO_API", "1")

	const deadline = 500 * time.Millisecond
	ctx, cancel := context.WithTimeout(context.Background(), deadline)
	defer cancel()
	start := time.Now()
	_, err := Read(ctx, Rig{Name: "gc-toolkit", Store: "/fixture/gc-toolkit/.beads"})
	took := time.Since(start)
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Errorf("Read = %v, want the deadline's error", err)
	}
	// A stop that killed gc alone would leave the child holding the call's
	// output, and the read would wait out the store client's grace for it.
	if took > deadline+1500*time.Millisecond {
		t.Errorf("Read returned %s after it began, past its %s deadline", took, deadline)
	}
	raw, err := os.ReadFile(group)
	if err != nil {
		return // the deadline came before the stub started, so no call ran
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(raw)))
	if err != nil {
		t.Fatalf("the stub wrote %q as its process group", raw)
	}
	// Read waits on the call it made, so the stub gc has ended and been waited
	// on by the time Read returns. A Read that returned at the deadline while
	// its call was still being stopped would find it there.
	if err := syscall.Kill(pid, 0); !errors.Is(err, syscall.ESRCH) {
		t.Errorf("the stub gc %d had not ended when Read returned (signal 0: %v)", pid, err)
	}
	// The child it started stays in the group until it is reaped.
	gone := time.Now().Add(5 * time.Second)
	for syscall.Kill(-pid, 0) == nil {
		if time.Now().After(gone) {
			_ = syscall.Kill(-pid, syscall.SIGKILL)
			t.Fatalf("the call's process group %d outlived the read", pid)
		}
		time.Sleep(20 * time.Millisecond)
	}
}
