package rigboard

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"os/exec"
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
		if c := doc.Rows[epic].Counts; c == nil || *c != (Counts{Needs: 1, Queue: 1, NotScheduled: len(want) - 1}) {
			t.Errorf("%s counts %+v, want its question, tk-w queued behind it and %d ready rows nothing sends", epic, c, len(want)-1)
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
// carries no await type, as gctk bead park files one, and its only member has
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

// TestReadGathersADecisionsHandBack reads, through the read itself, the
// hand-backs on the conversations about a decision: one on a conversation
// whose sitting ended at its hand-off, so it has closed, and an older one on a
// conversation a sitting holds. The decision's row carries the newer, and its
// question reads the open conversation's state.
func TestReadGathersADecisionsHandBack(t *testing.T) {
	rows := []json.RawMessage{
		json.RawMessage(`{"id":"tk-d","title":"keep the old flag?","status":"open","priority":1,"issue_type":"decision","created_at":"2026-01-01"}`),
		json.RawMessage(`{"id":"tk-c1","title":"talk it over","status":"closed","priority":2,"issue_type":"task","assignee":"gc-toolkit/gc-toolkit.tk-c1","metadata":{"gc.handback":"tk-d — ruled\nkeep it","gc.handback_at":"2026-01-03T00:00:00Z"},"dependencies":[{"issue_id":"tk-c1","depends_on_id":"tk-d","type":"tracks"}],"created_at":"2026-01-02"}`),
		json.RawMessage(`{"id":"tk-c2","title":"talk it over again","status":"in_progress","priority":2,"issue_type":"task","assignee":"gc-toolkit/gc-toolkit.tk-c2","metadata":{"gc.handback":"tk-d — still open","gc.handback_at":"2026-01-02T12:00:00Z"},"dependencies":[{"issue_id":"tk-c2","depends_on_id":"tk-d","type":"tracks"}],"created_at":"2026-01-02"}`),
	}
	doc, err := Read(context.Background(), stubStore(t, rows))
	if err != nil {
		t.Fatalf("Read: %v", err)
	}
	r := doc.Rows["tk-d"]
	if r.Handback == nil || *r.Handback != (Handback{Conversation: "tk-c1", At: "2026-01-03T00:00:00Z", Text: "tk-d — ruled\nkeep it"}) {
		t.Errorf("tk-d's hand-back = %+v, want the closed conversation's", r.Handback)
	}
	if r.Signal != "In conversation" || r.Conversation != "tk-c2" {
		t.Errorf("tk-d reads %q with conversation %q, want In conversation with tk-c2", r.Signal, r.Conversation)
	}
	if _, listed := doc.Rows["tk-c1"]; listed {
		t.Error("the closed conversation has a row, want it read for its hand-back alone")
	}
}

// TestReadListsHandBacksOnlyWhileADecisionIsOpen holds the read's list of
// hand-backs, which reads every one the store holds, to the rigs that can show
// one: only an open decision's Details opens with a hand-back, so a read with
// no open decision makes no call for them, and a read with one makes one.
func TestReadListsHandBacksOnlyWhileADecisionIsOpen(t *testing.T) {
	conversation := json.RawMessage(`{"id":"tk-c1","title":"talk it over","status":"closed","priority":2,"issue_type":"task","assignee":"gc-toolkit/gc-toolkit.tk-c1","metadata":{"gc.handback":"tk-d — ruled\nkeep it","gc.handback_at":"2026-01-03T00:00:00Z"},"dependencies":[{"issue_id":"tk-c1","depends_on_id":"tk-d","type":"tracks"}],"created_at":"2026-01-02"}`)
	for _, c := range []struct {
		status string
		lists  int
	}{
		{"closed", 0},
		{"open", 1},
	} {
		t.Run("a decision "+c.status, func(t *testing.T) {
			decision := json.RawMessage(`{"id":"tk-d","title":"keep the old flag?","status":"` + c.status + `","priority":1,"issue_type":"decision","created_at":"2026-01-01"}`)
			rig := stubStore(t, []json.RawMessage{decision, conversation})
			stub, err := exec.LookPath("gc")
			if err != nil {
				t.Fatal(err)
			}
			dir := t.TempDir()
			calls := filepath.Join(dir, "calls")
			logged := "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$GC_CALLS\"\nexec \"$STUB_GC\" \"$@\"\n"
			if err := os.WriteFile(filepath.Join(dir, "gc"), []byte(logged), 0o755); err != nil {
				t.Fatal(err)
			}
			t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
			t.Setenv("GC_CALLS", calls)
			t.Setenv("STUB_GC", stub)
			if _, err := Read(context.Background(), rig); err != nil {
				t.Fatalf("Read: %v", err)
			}
			raw, err := os.ReadFile(calls)
			if err != nil {
				t.Fatal(err)
			}
			lists := 0
			for _, line := range strings.Split(string(raw), "\n") {
				f := strings.Fields(line)
				for i := 0; i+1 < len(f); i++ {
					if f[i] == "--has-metadata-key" && f[i+1] == "gc.handback" {
						lists++
					}
				}
			}
			if lists != c.lists {
				t.Errorf("the read listed the store's hand-backs %d times, want %d", lists, c.lists)
			}
		})
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

// TestReadListsTheReadyWorkNothingSends reads a store through the read itself
// and holds the Not scheduled list to the work queue's answer, item by item.
// Each member is listed by its title on every read, from the store as it then
// stands, with nothing carried from an earlier read. A row reads "Not
// scheduled" exactly when the list holds it, so the two never disagree. A bead
// counts as worked only while a live run works it: tk-ended keeps the route
// its pour stamped and the branch its run cut, and tk-poured's run has not yet
// passed load-context. hold:external waits outside the city, and hold:mayor,
// in any spelling, waits for the Product Owner on the Unprioritized page.
// Whether a bead waits comes from the store, through its ready set and waits:
// tk-behind waits on tk-idle, and tk-c is held through its parent.
func TestReadListsTheReadyWorkNothingSends(t *testing.T) {
	stamp := `"gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"`
	run := func(convoy string) string {
		return `"metadata":{"gc.kind":"workflow","gc.formula_contract":"graph.v2","gc.input_convoy_id":"` + convoy + `"}`
	}
	tracks := func(convoy, bead string) string {
		return `"dependencies":[{"issue_id":"` + convoy + `","depends_on_id":"` + bead + `","type":"tracks"}]`
	}
	rows := func(idleRoute string) []json.RawMessage {
		return []json.RawMessage{
			json.RawMessage(`{"id":"tk-idle","title":"nothing sends it","status":"open","priority":2,"issue_type":"task","metadata":{"gc.routed_to":"` + idleRoute + `"},"created_at":"2026-01-01"}`),
			json.RawMessage(`{"id":"tk-ended","title":"its run ended","status":"open","priority":2,"issue_type":"task","metadata":{` + stamp + `,"branch":"polecat/tk-ended"},"created_at":"2026-01-02"}`),
			json.RawMessage(`{"id":"tk-ended-root","title":"mol-polecat-work","status":"closed","priority":2,"issue_type":"task",` + run("tk-ended-cv") + `,"created_at":"2026-01-02"}`),
			json.RawMessage(`{"id":"tk-ended-cv","title":"convoy","status":"closed","priority":2,"issue_type":"convoy",` + tracks("tk-ended-cv", "tk-ended") + `,"created_at":"2026-01-02"}`),
			json.RawMessage(`{"id":"tk-poured","title":"just poured","status":"open","priority":2,"issue_type":"task","metadata":{` + stamp + `},"created_at":"2026-01-03"}`),
			json.RawMessage(`{"id":"tk-poured-root","title":"mol-polecat-work","status":"open","priority":2,"issue_type":"task",` + run("tk-poured-cv") + `,"created_at":"2026-01-03"}`),
			json.RawMessage(`{"id":"tk-poured-step","title":"Load context","status":"open","priority":2,"issue_type":"task","metadata":{"gc.root_bead_id":"tk-poured-root","gc.step_ref":"mol-polecat-work.load-context"},"created_at":"2026-01-03"}`),
			json.RawMessage(`{"id":"tk-poured-cv","title":"convoy","status":"open","priority":2,"issue_type":"convoy",` + tracks("tk-poured-cv", "tk-poured") + `,"created_at":"2026-01-03"}`),
			json.RawMessage(`{"id":"tk-vendor","title":"waits on a vendor","status":"open","priority":2,"issue_type":"task","labels":[" Hold:External "],"created_at":"2026-01-04"}`),
			json.RawMessage(`{"id":"tk-desk","title":"a new idea","status":"open","priority":2,"issue_type":"task","labels":["HOLD:MAYOR"],"created_at":"2026-01-05"}`),
			json.RawMessage(`{"id":"tk-behind","title":"behind the idle work","status":"open","priority":2,"issue_type":"task","dependencies":[{"issue_id":"tk-behind","depends_on_id":"tk-idle","type":"blocks"}],"created_at":"2026-01-06"}`),
			json.RawMessage(`{"id":"tk-first","title":"first piece","status":"open","priority":2,"issue_type":"task","assignee":"gc-toolkit/gc-toolkit.mechanik","created_at":"2026-01-07"}`),
			json.RawMessage(`{"id":"tk-p","title":"parent work","status":"open","priority":2,"issue_type":"task","assignee":"gc-toolkit/gc-toolkit.mechanik","dependencies":[{"issue_id":"tk-p","depends_on_id":"tk-first","type":"blocks"}],"created_at":"2026-01-08"}`),
			json.RawMessage(`{"id":"tk-c","title":"child of held work","status":"open","priority":2,"issue_type":"task","dependencies":[{"issue_id":"tk-c","depends_on_id":"tk-p","type":"parent-child"}],"created_at":"2026-01-09"}`),
		}
	}
	rig := stubStore(t, rows(""))
	read := func() Document {
		t.Helper()
		doc, err := Read(context.Background(), rig)
		if err != nil {
			t.Fatalf("Read: %v", err)
		}
		return doc
	}
	oneAnswer := func(doc Document) {
		t.Helper()
		for id, r := range doc.Rows {
			if listed := slices.Contains(doc.WorkQueue.NotScheduled, id); (r.Signal == "Not scheduled") != listed {
				t.Errorf("%s reads %q, and the Not scheduled list holds it: %v; want one answer", id, r.Signal, listed)
			}
		}
		for _, id := range doc.WorkQueue.NotScheduled {
			if doc.Rows[id].Title == "" {
				t.Errorf("%s is listed with no title", id)
			}
		}
	}

	doc := read()
	if got, want := doc.WorkQueue.NotScheduled, []string{"tk-idle", "tk-ended"}; !slices.Equal(got, want) {
		t.Errorf("not scheduled = %v, want %v", got, want)
	}
	oneAnswer(doc)
	for id, want := range map[string]string{
		"tk-ended":  "Not scheduled",
		"tk-poured": "Queued",
		"tk-vendor": "Waits outside the city",
		"tk-desk":   "Waits for the Product Owner",
		"tk-behind": "Waits on tk-idle",
		"tk-c":      "Waits on tk-first",
	} {
		if got := doc.Rows[id].Signal; got != want {
			t.Errorf("%s reads %q, want %q", id, got, want)
		}
	}
	for _, id := range []string{"tk-vendor", "tk-behind", "tk-c", "tk-poured"} {
		if !slices.Contains(doc.WorkQueue.Queue, id) {
			t.Errorf("%s is not in the queue %v", id, doc.WorkQueue.Queue)
		}
	}
	if u := doc.Unprioritized; len(u) != 1 || !slices.Equal(u[0].IDs, []string{"tk-desk"}) ||
		slices.Contains(doc.WorkQueue.Queue, "tk-desk") || slices.Contains(doc.WorkQueue.NotScheduled, "tk-desk") {
		t.Errorf("unprioritized = %+v and work queue = %+v; want tk-desk on the Unprioritized page alone", u, doc.WorkQueue)
	}

	if again := read(); !slices.Equal(again.WorkQueue.NotScheduled, doc.WorkQueue.NotScheduled) {
		t.Errorf("a second read lists %v, want the same %v", again.WorkQueue.NotScheduled, doc.WorkQueue.NotScheduled)
	}
	routed, err := json.Marshal(rows("gc-toolkit/gc-toolkit.polecat"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(os.Getenv("HOLDS_STORE"), routed, 0o644); err != nil {
		t.Fatal(err)
	}
	sent := read()
	if got, want := sent.WorkQueue.NotScheduled, []string{"tk-ended"}; !slices.Equal(got, want) {
		t.Errorf("once tk-idle is routed, not scheduled = %v, want %v: the list is the store's answer at each read", got, want)
	}
	oneAnswer(sent)
}
