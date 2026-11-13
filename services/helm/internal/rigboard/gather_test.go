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
)

// TestReadGathersALandedDelivery reads, through the read itself, a Delivery
// that landed while its epic stays open, the lifecycle docs/epics.md gives
// under "How a Delivery ends". The story under the Delivery is read, the Epics
// page lists it in the Delivery's closed work, and it counts as closed in both
// the Delivery and the epic.
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
		!slices.Equal(doc.Epics[0].Deliveries[0].Closed, []string{"tk-e.1.1"}) || len(doc.Epics[0].Closed) != 0 {
		t.Errorf("the Epics page reads %+v, want the story in the Delivery's closed work alone", doc.Epics)
	}
	for _, id := range []string{"tk-e.1", "tk-e"} {
		if c := doc.Rows[id].Counts; c == nil || c.Closed != 1 {
			t.Errorf("%s counts %+v, want 1 closed", id, c)
		}
	}
}

// TestReadPlacesWorkUnderEveryEpicItSitsUnder reads work whose parent-child
// edges name more than one parent, which bd allows. tk-w sits under two open
// epics and waits on a human gate, so each epic lists it, counts its question
// and lists the question with tk-w beneath it, and Needs you counts the
// question once.
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
		for _, ids := range [][]string{e.Queue.Queue, e.Queue.NotScheduled, e.Queue.Unread, e.Closed} {
			listed[e.ID] = append(listed[e.ID], ids...)
		}
		slices.Sort(listed[e.ID])
		if want := []Need{{ID: "tk-q", Kind: NeedKindQuestion, Holds: []string{"tk-w"}}}; !slices.EqualFunc(e.Needs.Counted, want, sameNeed) {
			t.Errorf("%s's Needs you is %+v, want %+v", e.ID, e.Needs, want)
		}
	}
	for epic, want := range map[string][]string{"tk-e1": {"tk-w", "tk-w3", "tk-x"}, "tk-e2": {"tk-w", "tk-w2"}} {
		if !slices.Equal(listed[epic], want) {
			t.Errorf("%s lists %v, want %v, each once", epic, listed[epic], want)
		}
		if c := doc.Rows[epic].Counts; c == nil || *c != (Counts{Needs: 1, NotScheduled: len(want)}) {
			t.Errorf("%s counts %+v, want its question and %d rows nobody scheduled", epic, c, len(want))
		}
	}
	if got := doc.Rows["tk-w"].Group; got != GroupWaitingOnYou {
		t.Errorf("tk-w is in %q, want waiting on you", got)
	}
	if n := doc.NeedsYou; n.Count != 1 || !slices.EqualFunc(n.Counted, []Need{{ID: "tk-q", Kind: NeedKindQuestion, Holds: []string{"tk-w"}}}, sameNeed) {
		t.Errorf("Needs you counts %d and lists %+v, want 1 and the question with tk-w beneath it", n.Count, n.Counted)
	}
}

// TestReadFoldsNeedsAboutParkedWork reads, through the read itself, the needs
// a park leaves out of the count. Epic tk-pe waits on park gate tk-park, which
// carries no await type, as gc-helm.sh park files one, and its only member has
// closed, so it asks for a ruling. Question tk-q2 waits on the park itself, and
// question tk-q holds only tk-w, which waits on the park too. Question tk-q3
// holds only decision tk-d2, which waits on the park too, so both fold, and the
// decision is not drawn beneath the question, whose list draws work, epics and
// Deliveries. Question tk-q5 holds decision tk-d4, which holds only tk-w2,
// which waits on the park, so the decision leaves the count and the question,
// about nothing but the decision and tk-w2, leaves with it. The question is
// listed first, so it is read while the decision still counts. Decision tk-d
// stands alone and counts, and question tk-q4 holds only decision tk-d3, which
// nothing parks, so both count.
func TestReadFoldsNeedsAboutParkedWork(t *testing.T) {
	rows := []json.RawMessage{
		json.RawMessage(`{"id":"tk-pe","title":"Parked epic","status":"open","priority":1,"issue_type":"epic","metadata":{"epic_hypothesis":"it works later"},"dependencies":[{"issue_id":"tk-pe","depends_on_id":"tk-park","type":"blocks"}],"created_at":"2026-01-01"}`),
		json.RawMessage(`{"id":"tk-pe.1","title":"landed","status":"closed","priority":2,"issue_type":"task","dependencies":[{"issue_id":"tk-pe.1","depends_on_id":"tk-pe","type":"parent-child"}],"created_at":"2026-01-02"}`),
		json.RawMessage(`{"id":"tk-park","title":"Parked while the steer lands","status":"open","priority":2,"issue_type":"gate","created_at":"2026-01-02"}`),
		json.RawMessage(`{"id":"tk-q","title":"which way?","status":"open","priority":1,"issue_type":"gate","await_type":"human","created_at":"2026-01-03"}`),
		json.RawMessage(`{"id":"tk-w","title":"behind the question and the park","status":"open","priority":2,"issue_type":"task","dependencies":[{"issue_id":"tk-w","depends_on_id":"tk-q","type":"blocks"},{"issue_id":"tk-w","depends_on_id":"tk-park","type":"blocks"}],"created_at":"2026-01-04"}`),
		json.RawMessage(`{"id":"tk-q2","title":"and which?","status":"open","priority":1,"issue_type":"gate","await_type":"human","dependencies":[{"issue_id":"tk-q2","depends_on_id":"tk-park","type":"blocks"}],"created_at":"2026-01-05"}`),
		json.RawMessage(`{"id":"tk-d","title":"pick one","status":"open","priority":2,"issue_type":"decision","created_at":"2026-01-06"}`),
		json.RawMessage(`{"id":"tk-q3","title":"before the parked pick?","status":"open","priority":1,"issue_type":"gate","await_type":"human","created_at":"2026-01-07"}`),
		json.RawMessage(`{"id":"tk-d2","title":"pick behind the question and the park","status":"open","priority":2,"issue_type":"decision","dependencies":[{"issue_id":"tk-d2","depends_on_id":"tk-park","type":"blocks"},{"issue_id":"tk-d2","depends_on_id":"tk-q3","type":"blocks"}],"created_at":"2026-01-08"}`),
		json.RawMessage(`{"id":"tk-q4","title":"before the live pick?","status":"open","priority":1,"issue_type":"gate","await_type":"human","created_at":"2026-01-09"}`),
		json.RawMessage(`{"id":"tk-d3","title":"pick behind the question","status":"open","priority":2,"issue_type":"decision","dependencies":[{"issue_id":"tk-d3","depends_on_id":"tk-q4","type":"blocks"}],"created_at":"2026-01-10"}`),
		json.RawMessage(`{"id":"tk-q5","title":"before the pick for parked work?","status":"open","priority":1,"issue_type":"gate","await_type":"human","created_at":"2026-01-11"}`),
		json.RawMessage(`{"id":"tk-d4","title":"pick for parked work","status":"open","priority":2,"issue_type":"decision","dependencies":[{"issue_id":"tk-d4","depends_on_id":"tk-q5","type":"blocks"}],"created_at":"2026-01-12"}`),
		json.RawMessage(`{"id":"tk-w2","title":"behind the pick and the park","status":"open","priority":2,"issue_type":"task","dependencies":[{"issue_id":"tk-w2","depends_on_id":"tk-d4","type":"blocks"},{"issue_id":"tk-w2","depends_on_id":"tk-park","type":"blocks"}],"created_at":"2026-01-13"}`),
	}
	doc, err := Read(context.Background(), stubStore(t, rows))
	if err != nil {
		t.Fatalf("Read: %v", err)
	}
	if r := doc.Rows["tk-pe"]; r.Ask != AskRuling {
		t.Fatalf("tk-pe asks %q, want a ruling, so the case is not built", r.Ask)
	}
	if r := doc.Rows["tk-w"]; r.Signal != "Waits on your answer" {
		t.Fatalf("tk-w reads %q, want it held by its question, so the case is not built", r.Signal)
	}
	ids := func(needs []Need) []string {
		var out []string
		for _, n := range needs {
			out = append(out, n.ID)
		}
		slices.Sort(out)
		return out
	}
	n := doc.NeedsYou
	if got, want := ids(n.Counted), []string{"tk-d", "tk-d3", "tk-q4"}; n.Count != len(want) || !slices.Equal(got, want) {
		t.Errorf("Needs you counts %d: %v, want %v", n.Count, got, want)
	}
	if got, want := ids(n.NotCounted), []string{"tk-d2", "tk-d4", "tk-pe", "tk-q", "tk-q2", "tk-q3", "tk-q5"}; !slices.Equal(got, want) {
		t.Errorf("Needs you folds %v, want %v", got, want)
	}
	for _, x := range append(slices.Clone(n.Counted), n.NotCounted...) {
		if (x.ID == "tk-q3" || x.ID == "tk-q4") && len(x.Holds) != 0 {
			t.Errorf("%s draws %v beneath it, want nothing, since it holds no work", x.ID, x.Holds)
		}
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

// TestAnOpenPullRequestOnEitherRecord: a bead owns an open pull request at
// pull_request, and at either value Gas Town's pending record gives one, and at
// no value that records a landing or an end without one.
func TestAnOpenPullRequestOnEitherRecord(t *testing.T) {
	for _, v := range []string{"pull_request", "pull_request_pending", "pull_request_head_changed"} {
		if !hasOpenPullRequest(bead{MergeResult: v}) {
			t.Errorf("merge_result %s owns an open pull request", v)
		}
	}
	for _, v := range []string{"", "pre_open_gate", "merged", "mr_merged", "pull_request_closed_unmerged"} {
		if hasOpenPullRequest(bead{MergeResult: v}) {
			t.Errorf("merge_result %q owns no open pull request", v)
		}
	}
}
