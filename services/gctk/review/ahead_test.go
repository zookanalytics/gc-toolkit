package review_test

import (
	"errors"
	"reflect"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/arm"
	armrecord "github.com/zookanalytics/gc-toolkit/services/gctk/arm/record"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	gcfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
)

const (
	aheadTitle = "docs: add the architecture document"
	aheadPool  = "rig/gc-toolkit.polecat"
	aheadOn    = "mol-polecat-work"
)

// archIndex is a check index that declares arch, read at the validated head.
func archIndex(t *testing.T) func(string) (review.Index, error) {
	return func(at string) (review.Index, error) {
		if at != h1 {
			t.Fatalf("the index was read at %s; want the validated head", at)
		}
		return review.Index{Source: "idx", Checks: review.Parse("[checks.arch]\nphase = \"pre-open\"\n")}, nil
	}
}

func aheadReq(bead string) review.AheadRequest {
	return review.AheadRequest{Bead: bead, Title: aheadTitle, Description: "Cover the orders the change moves.",
		Pool: aheadPool, Formula: aheadOn, Checks: []string{"arch"}}
}

// routes is a runtime whose sling routes the bead it sends, as gc sling stamps
// gc.routed_to, so a later call finds the fix on its way.
func routes(w *world) *gcfake.Runtime {
	return &gcfake.Runtime{OnSling: func(s gascity.Sling) gascity.SlingResult {
		row, _ := w.store.Row(s.Bead)
		row.Metadata["gc.routed_to"] = s.Target
		w.store.Put(row)
		return gascity.SlingResult{}
	}}
}

// A fix ahead of a PR is filed with the PR's target and priority, slung to the
// pool at once, and waited on by an ask that blocks the PR's bead and sends the
// check back, the ask's wait written in its own create.
func TestAFixAheadOfAPRIsFiledSentAndWaitedOn(t *testing.T) {
	w := newWorld(t)
	pr, _ := w.store.Row(prBead)
	pr.Priority = 1
	pr.Metadata["pr_url"] = "https://github.com/o/r/pull/7"
	w.store.Put(pr)
	rt := routes(w)
	got, err := review.SendAhead(w.ledger(), t.TempDir(), time.Second, rt, aheadReq(prBead), archIndex(t))
	if err != nil {
		t.Fatal(err)
	}
	if !got.FixFiled || !got.Sent || !got.AskFiled || got.Fix == "" || got.Ask == "" {
		t.Fatalf("SendAhead = %+v; want the fix filed and slung, and the ask filed", got)
	}
	fixRow, _ := w.store.Row(got.Fix)
	if fixRow.Title != aheadTitle || fixRow.IssueType != "task" || fixRow.Priority != 1 || fixRow.Metadata["target"] != target ||
		!strings.Contains(fixRow.Description, "Cover the orders the change moves.") ||
		!strings.Contains(fixRow.Description, "Ahead of tk-pr's PR https://github.com/o/r/pull/7") {
		t.Fatalf("the fix reads %+v", fixRow)
	}
	if !slices.ContainsFunc(fixRow.Edges, func(e gcbd.Edge) bool { return e.Type == "discovered-from" && e.ID == prBead }) {
		t.Fatalf("the fix's edges are %+v, without its discovered-from edge onto the PR's bead", fixRow.Edges)
	}
	if s := rt.Slings(); len(s) != 1 || s[0].Target != aheadPool || s[0].Bead != got.Fix || s[0].Formula != aheadOn {
		t.Fatalf("slings = %+v; want the fix slung to %s on %s", s, aheadPool, aheadOn)
	}
	creates := w.store.Creates()
	askCreate := creates[len(creates)-1]
	if askCreate.ID != got.Ask || !slices.Contains(askCreate.Args, "blocks:"+prBead+",blocked-by:"+got.Fix) {
		t.Fatalf("the ask's create carried %q; want its blocks edge on the PR's bead and its wait on the fix in one --deps", askCreate.Args)
	}
	askRow, _ := w.store.Row(got.Ask)
	if askRow.Metadata["branch"] != branch || askRow.Metadata["review_checks"] != "arch" ||
		!strings.Contains(askRow.Description, got.Fix) {
		t.Fatalf("the ask reads %+v", askRow)
	}
	asks, err := review.AsksOn(w.ledger(), prBead)
	if err != nil || len(asks) != 1 || asks[0].ID != got.Ask {
		t.Fatalf("AsksOn = %+v, %v; want the one ask", asks, err)
	}

	again, err := review.SendAhead(w.ledger(), t.TempDir(), time.Second, rt, aheadReq(prBead), archIndex(t))
	if err != nil || again.FixFiled || again.Sent || again.AskFiled || again.Fix != got.Fix || again.Ask != got.Ask {
		t.Fatalf("a second call = %+v, %v; want the fix and the ask found, and nothing slung", again, err)
	}
	if n := len(rt.Slings()); n != 1 {
		t.Fatalf("the fix was slung %d times; want once", n)
	}
}

// A call that runs again after the fix it filed has landed, as a rule-and-repair
// step does when its first call's answer was lost, finds that fix through the
// ask that still waits on it, and files and sends nothing new.
func TestACallAfterItsFixLandedFindsThatFix(t *testing.T) {
	w := newWorld(t)
	rt := routes(w)
	first, err := review.SendAhead(w.ledger(), t.TempDir(), time.Second, rt, aheadReq(prBead), archIndex(t))
	if err != nil {
		t.Fatal(err)
	}
	row, _ := w.store.Row(first.Fix)
	row.Status, row.ClosedAt = "closed", "2026-11-18T20:00:00Z"
	w.store.Put(row)
	again, err := review.SendAhead(w.ledger(), t.TempDir(), time.Second, rt, aheadReq(prBead), archIndex(t))
	if err != nil || again.Fix != first.Fix || again.FixFiled || again.Sent || again.Ask != first.Ask || again.AskFiled {
		t.Fatalf("the call after the fix landed = %+v, %v; want the landed fix and its ask found, and nothing filed or slung", again, err)
	}
	if n := len(rt.Slings()); n != 1 {
		t.Fatalf("the fix was slung %d times; want once", n)
	}
}

// pausing is a store whose reads of the fix's title each say on entered that
// they have read, and return what they read once release closes.
type pausing struct {
	gcbd.Store
	entered, release chan struct{}
}

func (s *pausing) Find(q gcbd.Query) ([]gcbd.Bead, error) {
	rows, err := s.Store.Find(q)
	if q.TitleContains == aheadTitle {
		s.entered <- struct{}{}
		<-s.release
	}
	return rows, err
}

// Two PRs whose review runs ask for one fix at once share it: the store's
// record lock keeps the second call from reading the fix's title until the
// first has filed the fix, so the second finds that fix and files none.
func TestTwoPRsAskingForOneFixAtOnceShareIt(t *testing.T) {
	w := newWorld(t)
	w.store.Put(bead{ID: "tk-pr2", Status: "blocked", IssueType: "task", Metadata: map[string]string{
		"merge_result": "pull_request_pending", "branch": "polecat/tk-pr2", "pr_head_sha": h1, "merged_target": target,
	}})
	store := &pausing{Store: w.store, entered: make(chan struct{}, 2), release: make(chan struct{})}
	dir, rt := t.TempDir(), routes(w)
	type sent struct {
		got review.Ahead
		err error
	}
	done := make(chan sent, 2)
	send := func(bead string) {
		got, err := review.SendAhead(ledger.New(store), dir, 10*time.Second, rt, aheadReq(bead), archIndex(t))
		done <- sent{got, err}
	}
	go send(prBead)
	<-store.entered
	go send("tk-pr2")
	// Without the lock the second call reads the title while the first waits.
	select {
	case <-store.entered:
	case <-time.After(500 * time.Millisecond):
	}
	close(store.release)
	a, b := <-done, <-done
	if a.err != nil || b.err != nil {
		t.Fatalf("the two calls returned %v and %v", a.err, b.err)
	}
	if a.got.Fix != b.got.Fix || a.got.FixFiled == b.got.FixFiled || a.got.Ask == b.got.Ask {
		t.Fatalf("the two calls = %+v and %+v; want one fix, filed by one of them, and an ask for each PR", a.got, b.got)
	}
	if n := len(rt.Slings()); n != 1 {
		t.Fatalf("the fix was slung %d times; want once", n)
	}
}

// A second PR that needs the same fix waits on the open bead of its title: its
// case joins the fix's notes once, a fix on its way is not slung again, and the
// ask is the second PR's own.
func TestASecondPRWaitsOnTheSameFix(t *testing.T) {
	w := newWorld(t)
	rt := routes(w)
	first, err := review.SendAhead(w.ledger(), t.TempDir(), time.Second, rt, aheadReq(prBead), archIndex(t))
	if err != nil {
		t.Fatal(err)
	}
	w.store.Put(bead{ID: "tk-pr2", Status: "blocked", IssueType: "task", Metadata: map[string]string{
		"merge_result": "pull_request_pending", "branch": "polecat/tk-pr2", "pr_head_sha": h1, "merged_target": target,
	}})
	second := aheadReq("tk-pr2")
	second.Description = "Cover the sessions the change moves."
	got, err := review.SendAhead(w.ledger(), t.TempDir(), time.Second, rt, second, archIndex(t))
	if err != nil {
		t.Fatal(err)
	}
	if got.Fix != first.Fix || got.FixFiled || got.Sent || !got.AskFiled || got.Ask == first.Ask {
		t.Fatalf("the second PR's call = %+v; want the first fix found, not slung again, and an ask of its own", got)
	}
	fixRow, _ := w.store.Row(first.Fix)
	if !strings.Contains(fixRow.Notes, "Ahead of tk-pr2's PR") || !strings.Contains(fixRow.Notes, "Cover the sessions the change moves.") {
		t.Fatalf("the fix's notes read %q; want the second PR's case", fixRow.Notes)
	}
	writes := len(w.store.Writes())
	if _, err := review.SendAhead(w.ledger(), t.TempDir(), time.Second, rt, second, archIndex(t)); err != nil {
		t.Fatal(err)
	}
	if n := len(w.store.Writes()); n != writes {
		t.Fatalf("a repeated call wrote %d more updates; want the case noted once", n-writes)
	}
	if n := len(rt.Slings()); n != 1 {
		t.Fatalf("the fix was slung %d times; want once", n)
	}
}

// A fix lands only on its target, so a PR into another branch that needs the
// same fix gets one of its own, on its own target, and the open fix of the
// other branch takes no note of its case.
func TestAPRIntoAnotherBranchGetsAFixOfItsOwn(t *testing.T) {
	w := newWorld(t)
	rt := routes(w)
	first, err := review.SendAhead(w.ledger(), t.TempDir(), time.Second, rt, aheadReq(prBead), archIndex(t))
	if err != nil {
		t.Fatal(err)
	}
	w.store.Put(bead{ID: "tk-pr2", Status: "blocked", IssueType: "task", Metadata: map[string]string{
		"merge_result": "pull_request_pending", "branch": "polecat/tk-pr2", "pr_head_sha": h1, "merged_target": "integration/tk-x",
	}})
	got, err := review.SendAhead(w.ledger(), t.TempDir(), time.Second, rt, aheadReq("tk-pr2"), archIndex(t))
	if err != nil {
		t.Fatal(err)
	}
	fixRow, _ := w.store.Row(got.Fix)
	if got.Fix == first.Fix || !got.FixFiled || !got.Sent || !got.AskFiled || fixRow.Metadata["target"] != "integration/tk-x" {
		t.Fatalf("the PR into another branch = %+v, its fix reading %+v; want a fix of its own on its target, filed and slung", got, fixRow)
	}
	firstRow, _ := w.store.Row(first.Fix)
	if strings.Contains(firstRow.Notes, "tk-pr2") {
		t.Fatalf("the other branch's fix took the PR's case: %q", firstRow.Notes)
	}
}

// The fix an open ask on the PR waits on stands for the PR's fix only while it
// lands on the PR's target, so a landed fix of another branch, which an ask
// filed while the PR's record named that branch waits on, is not taken for it:
// the call files a fix on the PR's target and an ask that waits on that one.
func TestALandedFixOfAnotherBranchIsNotThePRs(t *testing.T) {
	w := newWorld(t)
	rt := routes(w)
	first, err := review.SendAhead(w.ledger(), t.TempDir(), time.Second, rt, aheadReq(prBead), archIndex(t))
	if err != nil {
		t.Fatal(err)
	}
	row, _ := w.store.Row(first.Fix)
	row.Status, row.ClosedAt = "closed", "2026-11-18T20:00:00Z"
	w.store.Put(row)
	pr, _ := w.store.Row(prBead)
	pr.Metadata["merged_target"] = "integration/tk-x"
	w.store.Put(pr)
	got, err := review.SendAhead(w.ledger(), t.TempDir(), time.Second, rt, aheadReq(prBead), archIndex(t))
	if err != nil {
		t.Fatal(err)
	}
	fixRow, _ := w.store.Row(got.Fix)
	if got.Fix == first.Fix || !got.FixFiled || !got.Sent || got.Ask == first.Ask || !got.AskFiled ||
		fixRow.Metadata["target"] != "integration/tk-x" {
		t.Fatalf("the call = %+v, its fix reading %+v; want a fix on the PR's target and an ask that waits on it", got, fixRow)
	}
}

// A sling that does not land leaves the fix and the ask that waits on it filed,
// and the next call finds the fix through that ask, on no way to a pool, slings
// it and finds the ask.
func TestAFixWhoseSlingFailedIsSentByTheNextCall(t *testing.T) {
	w := newWorld(t)
	rt := &gcfake.Runtime{OnSling: func(gascity.Sling) gascity.SlingResult {
		return gascity.SlingResult{Result: gascity.Result{Code: 1, Output: "no such pool"}}
	}}
	got, err := review.SendAhead(w.ledger(), t.TempDir(), time.Second, rt, aheadReq(prBead), archIndex(t))
	if err == nil || !strings.Contains(err.Error(), "no such pool") || !got.FixFiled || got.Sent || !got.AskFiled {
		t.Fatalf("SendAhead = %+v, %v; want the fix and its ask filed, and the sling's failure", got, err)
	}
	retry := routes(w)
	again, err := review.SendAhead(w.ledger(), t.TempDir(), time.Second, retry, aheadReq(prBead), archIndex(t))
	if err != nil || again.Fix != got.Fix || again.FixFiled || !again.Sent || again.Ask != got.Ask || again.AskFiled {
		t.Fatalf("the next call = %+v, %v; want the fix found and slung, and the ask found", again, err)
	}
}

// A sling that finds a live workflow on the fix, gc sling's exit 3, does not
// show the fix on its way, since the workflow can be a pour Gas City left
// unfinished, which cannot finish and beside which gc sling pours no other. The
// call arms the fix for the pool and the formula, a call that runs again sends
// nothing more, and the deferred-dispatch order's start reads the pour when it
// sends the fix and asks a person about it, keeping the arm.
func TestAFixWhoseSlingFindsALiveWorkflowIsArmed(t *testing.T) {
	w := newWorld(t)
	w.store.Put(bead{ID: "tk-wf", Status: "open", IssueType: "task", Metadata: map[string]string{"molecule_failed": "true"}})
	rt := &gcfake.Runtime{Root: t.TempDir(), OnSling: func(gascity.Sling) gascity.SlingResult {
		return gascity.SlingResult{Result: gascity.Result{Code: 3}, Live: []string{"tk-wf"}}
	}}
	req := aheadReq(prBead)
	req.Actor = "repair"
	got, err := review.SendAhead(w.ledger(), t.TempDir(), time.Second, rt, req, archIndex(t))
	if err != nil || !got.FixFiled || !got.AskFiled || got.Sent || !got.Armed || !slices.Equal(got.Live, []string{"tk-wf"}) {
		t.Fatalf("SendAhead = %+v, %v; want the fix filed and armed over tk-wf, and the ask filed", got, err)
	}
	rows, err := w.ledger().Find(ledger.ByID(got.Fix))
	if err != nil || len(rows) != 1 {
		t.Fatalf("the fix read %v, %v", rows, err)
	}
	if a := armrecord.Of(rows[0]); a == nil || a.Target != aheadPool || a.Formula() != aheadOn || a.ArmedBy != "repair" ||
		!strings.Contains(a.Reason, "tk-wf") {
		t.Fatalf("the fix's arm reads %+v; want it armed for %s on %s by repair, naming tk-wf", a, aheadPool, aheadOn)
	}

	again, err := review.SendAhead(w.ledger(), t.TempDir(), time.Second, rt, req, archIndex(t))
	if err != nil || again.Fix != got.Fix || again.FixFiled || again.Sent || again.Armed || again.Ask != got.Ask {
		t.Fatalf("a second call = %+v, %v; want the armed fix and the ask found, and nothing sent", again, err)
	}
	if n := len(rt.Slings()); n != 1 {
		t.Fatalf("the fix was slung %d times by the calls; want once", n)
	}

	w.store.MakeReady(got.Fix)
	arms := &arm.Arms{Ledger: w.ledger(), Runtime: rt, Locks: t.TempDir(), Now: time.Now, Actor: "start", Wait: time.Second}
	var line arm.Line
	if _, err := arms.StartArmed(arm.StartOptions{}, func(l arm.Line) {
		if l.ID == got.Fix {
			line = l
		}
	}); err != nil {
		t.Fatal(err)
	}
	if line.Start.Action != arm.ActAsk || line.Start.Case != "unfinished" || !strings.Contains(line.Start.Why, "tk-wf") {
		t.Fatalf("the start's act on the fix = %+v; want a person asked about the unfinished pour tk-wf", line.Start)
	}
	if calls := rt.Scripts(); len(calls) != 1 || calls[0].Name != "human-gate.sh" || !slices.Contains(calls[0].Args, got.Fix) {
		t.Fatalf("the start ran %+v; want one human gate on %s", calls, got.Fix)
	}
	if rows, _ := w.ledger().Find(ledger.ByID(got.Fix)); len(rows) != 1 || armrecord.Of(rows[0]) == nil {
		t.Fatal("the start asked a person and left the fix unarmed")
	}
}

// refusing is a store that lets left creates land and refuses each one after
// them, as a store can refuse an ask's create after the fix's create landed.
type refusing struct {
	gcbd.Store
	left int
}

func (s *refusing) Create(title string, args ...string) (string, error) {
	if s.left == 0 {
		return "", errors.New("the store refused the create")
	}
	s.left--
	return s.Store.Create(title, args...)
}

// The ask is filed before the fix is sent, so an ask that does not file leaves
// the fix sent nowhere, and nothing works the fix before an ask waits on it.
// The next call finds the fix by its title, files the ask and then sends the
// fix.
func TestAFixIsSentOnlyAfterItsAskStands(t *testing.T) {
	w := newWorld(t)
	rt := routes(w)
	got, err := review.SendAhead(ledger.New(&refusing{Store: w.store, left: 1}), t.TempDir(), time.Second, rt, aheadReq(prBead), archIndex(t))
	if err == nil || !got.FixFiled || got.Sent || got.Ask != "" || len(rt.Slings()) != 0 {
		t.Fatalf("SendAhead = %+v, %v, slings %+v; want the fix filed, the ask's failure, and nothing slung", got, err, rt.Slings())
	}
	again, err := review.SendAhead(w.ledger(), t.TempDir(), time.Second, rt, aheadReq(prBead), archIndex(t))
	if err != nil || again.Fix != got.Fix || again.FixFiled || !again.Sent || !again.AskFiled {
		t.Fatalf("the next call = %+v, %v; want the fix found and slung, and the ask filed", again, err)
	}
	if n := len(rt.Slings()); n != 1 {
		t.Fatalf("the fix was slung %d times; want once", n)
	}
}

// A found fix that a label holds from every pool, as hold:mayor holds work that
// waits for the operator's placement, is sent nowhere, because gc sling reads
// no hold, and the ask waits on it while the hold stands.
func TestAFoundFixThatALabelHoldsIsSentNowhere(t *testing.T) {
	w := newWorld(t)
	w.store.Put(bead{ID: "tk-held", Title: aheadTitle, Status: "open", IssueType: "task", Labels: []string{"Hold:Mayor "},
		Metadata: map[string]string{"target": target}})
	rt := routes(w)
	got, err := review.SendAhead(w.ledger(), t.TempDir(), time.Second, rt, aheadReq(prBead), archIndex(t))
	if err != nil {
		t.Fatal(err)
	}
	if got.Fix != "tk-held" || got.FixFiled || got.Sent || got.Held != "Hold:Mayor" || !got.AskFiled {
		t.Fatalf("SendAhead = %+v; want the held fix found and sent nowhere, and the ask filed", got)
	}
	if n := len(rt.Slings()); n != 0 {
		t.Fatalf("the held fix was slung %d times; want none", n)
	}
	askRow, _ := w.store.Row(got.Ask)
	if !slices.ContainsFunc(askRow.Edges, func(e gcbd.Edge) bool { return e.Type == gcbd.EdgeBlocks && e.ID == "tk-held" }) {
		t.Fatalf("the ask's edges are %+v, without its wait on the held fix", askRow.Edges)
	}
}

// waitingFix puts in w's store an open fix of the request's title and the PR's
// target, tk-document, and the prerequisite it waits on, tk-prerequisite,
// which the store's blocked listing names as its wait.
func waitingFix(w *world) {
	w.store.Put(bead{ID: "tk-prerequisite", Title: "the prerequisite", Status: "open", IssueType: "task"})
	w.store.Put(bead{ID: "tk-document", Title: aheadTitle, Status: "open", IssueType: "task",
		Metadata: map[string]string{"target": target},
		Edges:    []gcbd.Edge{{ID: "tk-prerequisite", Type: gcbd.EdgeBlocks, Status: "open"}}})
	w.store.List("tk-document", "tk-prerequisite")
}

// A found fix that a wait holds, as gctk bead holds reads it, its own such as
// a prerequisite or a person's gate, or an ancestor's, or one the store cannot
// judge yet, is armed for the pool and the formula in place of its sling,
// because gc sling reads no wait, and the ask waits on it.
func TestAFoundFixThatAWaitHoldsIsArmedInPlaceOfItsSling(t *testing.T) {
	for _, c := range []struct {
		name    string
		put     func(*world)
		waiting string
	}{
		{"a prerequisite", waitingFix, "blocked on tk-prerequisite"},
		{"a person's gate", func(w *world) {
			w.store.Put(bead{ID: "tk-gate", Title: "decide the route", Status: "open", IssueType: "gate", AwaitType: "human"})
			w.store.Put(bead{ID: "tk-document", Title: aheadTitle, Status: "open", IssueType: "task",
				Metadata: map[string]string{"target": target},
				Edges:    []gcbd.Edge{{ID: "tk-gate", Type: gcbd.EdgeBlocks, Status: "open", IssueType: "gate", AwaitType: "human"}}})
			w.store.List("tk-document", "tk-gate")
		}, "blocked on tk-gate"},
		{"an ancestor's prerequisite", func(w *world) {
			w.store.Put(bead{ID: "tk-prerequisite", Title: "the prerequisite", Status: "open", IssueType: "task"})
			w.store.Put(bead{ID: "tk-epic", Title: "the epic", Status: "open", IssueType: "epic",
				Edges: []gcbd.Edge{{ID: "tk-prerequisite", Type: gcbd.EdgeBlocks, Status: "open"}}})
			w.store.Put(bead{ID: "tk-document", Title: aheadTitle, Status: "open", IssueType: "task",
				Metadata: map[string]string{"target": target},
				Edges:    []gcbd.Edge{{ID: "tk-epic", Type: gcbd.EdgeParentChild, Status: "open"}}})
			w.store.List("tk-epic", "tk-prerequisite")
			w.store.Mark("tk-epic")
			w.store.List("tk-document", "tk-epic")
		}, "held on tk-prerequisite through tk-epic"},
		{"a waits-for edge", func(w *world) {
			w.store.Put(bead{ID: "tk-spawner", Title: "the spawner", Status: "open", IssueType: "task"})
			w.store.Put(bead{ID: "tk-document", Title: aheadTitle, Status: "open", IssueType: "task",
				Metadata: map[string]string{"target": target},
				Edges:    []gcbd.Edge{{ID: "tk-spawner", Type: gcbd.EdgeWaitsFor, Status: "open"}}})
		}, "unjudged on tk-spawner"},
	} {
		w := newWorld(t)
		c.put(w)
		rt := routes(w)
		rt.Root = t.TempDir()
		req := aheadReq(prBead)
		req.Actor = "repair"
		got, err := review.SendAhead(w.ledger(), t.TempDir(), time.Second, rt, req, archIndex(t))
		if err != nil || got.Fix != "tk-document" || got.FixFiled || !got.AskFiled || got.Sent || !got.Armed ||
			got.Waiting != c.waiting || len(got.Live) != 0 || got.Held != "" {
			t.Fatalf("%s: SendAhead = %+v, %v; want tk-document found and armed while it is %s, and the ask filed", c.name, got, err, c.waiting)
		}
		if s := rt.Slings(); len(s) != 0 {
			t.Fatalf("%s: slings = %+v; want the waiting fix slung nowhere", c.name, s)
		}
		rows, err := w.ledger().Find(ledger.ByID(got.Fix))
		if err != nil || len(rows) != 1 {
			t.Fatalf("%s: the fix read %v, %v", c.name, rows, err)
		}
		if a := armrecord.Of(rows[0]); a == nil || a.Target != aheadPool || a.Formula() != aheadOn || a.ArmedBy != "repair" ||
			!strings.Contains(a.Reason, c.waiting) {
			t.Fatalf("%s: the fix's arm reads %+v; want it armed for %s on %s by repair, naming what holds it", c.name, a, aheadPool, aheadOn)
		}
		askRow, _ := w.store.Row(got.Ask)
		if !slices.ContainsFunc(askRow.Edges, func(e gcbd.Edge) bool { return e.Type == gcbd.EdgeBlocks && e.ID == got.Fix }) {
			t.Fatalf("%s: the ask's edges are %+v, without its wait on the fix", c.name, askRow.Edges)
		}
	}
}

// A fix armed while a wait holds it is sent once the wait lands: a call that
// runs again meanwhile sends nothing, the deferred-dispatch order's start holds
// the fix while its prerequisite is open, and once the prerequisite has landed
// the start slings the fix to the pool on the formula.
func TestAFixArmedBehindAWaitIsSentOnceTheWaitLands(t *testing.T) {
	w := newWorld(t)
	waitingFix(w)
	rt := routes(w)
	rt.Root = t.TempDir()
	got, err := review.SendAhead(w.ledger(), t.TempDir(), time.Second, rt, aheadReq(prBead), archIndex(t))
	if err != nil || got.Fix != "tk-document" || !got.Armed || got.Sent {
		t.Fatalf("SendAhead = %+v, %v; want tk-document found and armed", got, err)
	}
	again, err := review.SendAhead(w.ledger(), t.TempDir(), time.Second, rt, aheadReq(prBead), archIndex(t))
	if err != nil || again.Fix != got.Fix || again.Armed || again.Sent || again.Ask != got.Ask || again.AskFiled {
		t.Fatalf("a second call = %+v, %v; want the armed fix and its ask found, and nothing sent", again, err)
	}

	arms := &arm.Arms{Ledger: w.ledger(), Runtime: rt, Locks: t.TempDir(), Now: time.Now, Actor: "start", Wait: time.Second}
	start := func() arm.Act {
		var act arm.Act
		if _, err := arms.StartArmed(arm.StartOptions{}, func(l arm.Line) {
			if l.ID == got.Fix {
				act = l.Start
			}
		}); err != nil {
			t.Fatal(err)
		}
		return act
	}
	if act := start(); act.Action != arm.ActHold || act.Case != "blocked" || len(rt.Slings()) != 0 {
		t.Fatalf("the start's act while the prerequisite is open = %+v, slings %+v; want the fix held and nothing slung", act, rt.Slings())
	}

	const landed = "2026-11-19T03:00:00Z"
	w.store.Put(bead{ID: "tk-prerequisite", Title: "the prerequisite", Status: "closed", IssueType: "task", ClosedAt: landed})
	row, _ := w.store.Row(got.Fix)
	for i := range row.Edges {
		if row.Edges[i].ID == "tk-prerequisite" {
			row.Edges[i].Status, row.Edges[i].ClosedAt = "closed", landed
		}
	}
	w.store.Put(row)
	w.store.Unlist(got.Fix)
	w.store.MakeReady(got.Fix)
	if act := start(); act.Action != arm.ActStart {
		t.Fatalf("the start's act once the prerequisite landed = %+v; want the fix sent", act)
	}
	if s := rt.Slings(); len(s) != 1 || s[0].Target != aheadPool || s[0].Bead != got.Fix || s[0].Formula != aheadOn {
		t.Fatalf("slings = %+v; want the fix slung once to %s on %s", s, aheadPool, aheadOn)
	}
}

// A bead of the fix's title that waits on the PR's bead, by an edge of its own
// as a fix deferred behind the PR does, or through the beads it waits on,
// closed ones included, cannot also land ahead of the PR, because the ask that
// waited on it would close a cycle. The call passes it over and files a fix of
// its own, and a call that runs again, after the ask filed or after the ask's
// create failed, finds that fix and not the bead it passed over. A bead whose
// waits do not reach the PR's bead, such as one found from it, is the fix.
func TestABeadThatWaitsOnThePRIsNotSentAheadOfIt(t *testing.T) {
	for _, c := range []struct {
		name  string
		edges []gcbd.Edge
		taken bool
	}{
		{"deferred behind the PR", []gcbd.Edge{{ID: prBead, Type: gcbd.EdgeBlocks}}, false},
		{"behind a closed bead that waits on the PR", []gcbd.Edge{{ID: "tk-closed", Type: gcbd.EdgeBlocks}}, false},
		{"a child of the PR's bead", []gcbd.Edge{{ID: prBead, Type: gcbd.EdgeParentChild}}, false},
		{"found from the PR's bead", []gcbd.Edge{{ID: prBead, Type: "discovered-from"}}, true},
		{"behind a bead that does not wait on the PR", []gcbd.Edge{{ID: "tk-other", Type: gcbd.EdgeBlocks}}, true},
	} {
		// fk-0 sorts before the fk-1 a call files, so the lowest id alone would take it.
		setup := func() *world {
			w := newWorld(t)
			w.store.Put(bead{ID: "tk-closed", Status: "closed", IssueType: "task",
				Edges: []gcbd.Edge{{ID: prBead, Type: gcbd.EdgeConditionalBlocks}}})
			w.store.Put(bead{ID: "tk-other", Status: "open", IssueType: "task"})
			w.store.Put(bead{ID: "fk-0", Title: aheadTitle, Status: "open", IssueType: "task",
				Metadata: map[string]string{"target": target}, Edges: c.edges})
			return w
		}
		w := setup()
		rt := routes(w)
		got, err := review.SendAhead(w.ledger(), t.TempDir(), time.Second, rt, aheadReq(prBead), archIndex(t))
		if err != nil {
			t.Fatalf("%s: %v", c.name, err)
		}
		askRow, _ := w.store.Row(got.Ask)
		waited := slices.ContainsFunc(askRow.Edges, func(e gcbd.Edge) bool { return e.ID == "fk-0" })
		if c.taken {
			if got.Fix != "fk-0" || got.FixFiled || !got.AskFiled || !waited {
				t.Errorf("%s: SendAhead = %+v, the ask's edges %+v; want fk-0 found and waited on", c.name, got, askRow.Edges)
			}
			continue
		}
		if got.Fix == "fk-0" || !got.FixFiled || !got.Sent || !got.AskFiled || waited {
			t.Fatalf("%s: SendAhead = %+v, the ask's edges %+v; want a fix of its own filed, slung and waited on", c.name, got, askRow.Edges)
		}
		again, err := review.SendAhead(w.ledger(), t.TempDir(), time.Second, rt, aheadReq(prBead), archIndex(t))
		if err != nil || again.Fix != got.Fix || again.FixFiled || again.Sent || again.Ask != got.Ask || again.AskFiled {
			t.Fatalf("%s: a second call = %+v, %v; want the fix and the ask found, and nothing filed or slung", c.name, again, err)
		}

		w = setup()
		rt = routes(w)
		first, err := review.SendAhead(ledger.New(&refusing{Store: w.store, left: 1}), t.TempDir(), time.Second, rt, aheadReq(prBead), archIndex(t))
		if err == nil || first.Fix == "fk-0" || !first.FixFiled || first.Ask != "" {
			t.Fatalf("%s: SendAhead = %+v, %v; want a fix of its own filed, and the ask's failure", c.name, first, err)
		}
		retry, err := review.SendAhead(w.ledger(), t.TempDir(), time.Second, rt, aheadReq(prBead), archIndex(t))
		if err != nil || retry.Fix != first.Fix || retry.FixFiled || !retry.Sent || !retry.AskFiled {
			t.Fatalf("%s: the next call = %+v, %v; want the fix it filed found and slung, and the ask filed", c.name, retry, err)
		}
	}
}

// What FileAsk refuses, and a fix that sends no check back, file nothing and
// sling nothing.
func TestAFixAheadIsRefusedBeforeAnythingIsFiled(t *testing.T) {
	for _, c := range []struct {
		name  string
		setup func(w *world)
		req   func() review.AheadRequest
	}{
		{"no check sent back", func(*world) {}, func() review.AheadRequest {
			r := aheadReq(prBead)
			r.Checks = nil
			return r
		}},
		{"a check the index does not declare", func(*world) {}, func() review.AheadRequest {
			r := aheadReq(prBead)
			r.Checks = []string{"nonesuch"}
			return r
		}},
		{"a bead with no PR on the record", func(w *world) {
			pr, _ := w.store.Row(prBead)
			pr.Metadata["merge_result"] = "mr_merged"
			w.store.Put(pr)
		}, func() review.AheadRequest { return aheadReq(prBead) }},
	} {
		w := newWorld(t)
		c.setup(w)
		rt := &gcfake.Runtime{}
		_, err := review.SendAhead(w.ledger(), t.TempDir(), time.Second, rt, c.req(), archIndex(t))
		var refused *review.Refusal
		if !errors.As(err, &refused) || len(w.store.Creates()) != 0 || len(rt.Slings()) != 0 {
			t.Errorf("%s: %v; want it refused with nothing filed or slung", c.name, err)
		}
	}
}

// An ask that waits on a bead names only one the store holds, so its wait
// holds it.
func TestAnAskWaitsOnlyOnABeadTheStoreHolds(t *testing.T) {
	w := newWorld(t)
	_, _, err := review.FileAsk(w.ledger(), review.AskRequest{Bead: prBead, Reason: "after it", WaitsOn: []string{"gc-elsewhere"}}, nil)
	var refused *review.Refusal
	if !errors.As(err, &refused) || len(w.store.Creates()) != 0 {
		t.Fatalf("an ask waiting on a bead the store does not hold: %v; want it refused with nothing filed", err)
	}
	w.store.Put(bead{ID: "tk-first", Status: "open", IssueType: "task"})
	id, filed, err := review.FileAsk(w.ledger(), review.AskRequest{Bead: prBead, Reason: "after it", WaitsOn: []string{"tk-first"}}, nil)
	if err != nil || !filed {
		t.Fatalf("FileAsk = %q, %t, %v", id, filed, err)
	}
	row, _ := w.store.Row(id)
	if !slices.ContainsFunc(row.Edges, func(e gcbd.Edge) bool { return e.Type == gcbd.EdgeBlocks && e.ID == "tk-first" }) {
		t.Fatalf("the ask's edges are %+v, without its wait on tk-first", row.Edges)
	}
}

// held puts the ask tk-wait on the PR's bead, sending arch back and held by
// its wait on the open fix tk-fix, as SendAhead leaves them.
func (w *world) held() {
	w.store.Put(bead{ID: "tk-fix", Status: "open", IssueType: "task"})
	w.ask("tk-wait", "arch", gcbd.Edge{ID: "tk-fix", Type: gcbd.EdgeBlocks})
	w.store.List("tk-wait", "tk-fix")
	w.store.Mark("tk-wait")
}

func aheadRuling(waits string) review.Ruling {
	return review.Ruling{Check: "arch", Finding: "A1", Ruling: review.RulingAhead,
		Reason: "the architecture document lands first, in tk-fix", Waits: waits}
}

// A lane's finding sent ahead names the open ask on the bead that its PR waits
// on, and changes no code. An ask is never sent ahead, no other ruling names an
// ask to wait on, and a shadow run, which files nothing, names none.
func TestAFindingSentAhead(t *testing.T) {
	setup := func() (*world, string) {
		w := newWorld(t)
		w.held()
		w.output(triage(1, h1, "arch"))
		w.output(lane(1, "arch", h1, review.VerdictRequestChanges, "A1"))
		return w, w.step(1, "rule-and-repair")
	}
	w, st := setup()
	if err := w.check(st, repair(1, h1, "", aheadRuling("tk-wait")), nil); err != nil {
		t.Fatalf("a finding sent ahead to wait on the held ask: %v", err)
	}
	withCommit := aheadRuling("tk-wait")
	withCommit.Commit = fix
	declinedWaiting := review.Ruling{Check: "arch", Finding: "A1", Ruling: review.RulingDeclined, Reason: "r", Waits: "tk-wait"}
	for _, c := range []struct {
		name string
		rp   review.Repair
		why  string
	}{
		{"one that names no ask", repair(1, h1, "", aheadRuling("")), "names no ask the PR waits on"},
		{"one that names a bead that is no ask", repair(1, h1, "", aheadRuling("tk-fix")), "which is no open ask on the bead"},
		{"one with a commit", repair(1, h1, fix, withCommit), "changes no code"},
		{"another ruling that names an ask to wait on", repair(1, h1, "", declinedWaiting), "only a finding sent ahead names"},
	} {
		w, st := setup()
		mustRefuse(t, w.check(st, c.rp, nil), c.why)
	}

	w, st = setup()
	row, _ := w.store.Row("tk-wait")
	row.Status = "closed"
	w.store.Put(row)
	mustRefuse(t, w.check(st, repair(1, h1, "", aheadRuling("tk-wait")), nil), "which is no open ask on the bead")

	w, st = setup()
	w.ask("tk-ask", "")
	mustRefuse(t, w.check(st, repair(1, h1, "", aheadRuling("tk-wait"),
		review.Ruling{Ask: "tk-ask", Ruling: review.RulingAhead, Reason: "r", Waits: "tk-wait"}), nil),
		"only a lane's finding is sent ahead")

	w, st = setup()
	w.shadowRun()
	if err := w.check(st, repair(1, h1, "", aheadRuling("")), nil); err != nil {
		t.Errorf("a shadow run's finding sent ahead with no ask: %v", err)
	}
	mustRefuse(t, w.check(st, repair(1, h1, "", aheadRuling("tk-wait")), nil), "a shadow run files nothing")
}

// An iteration whose finding is sent ahead passes while the ask it names waits
// on the fix, which spends no attempt, and one whose ruling names no ask does
// not pass, unless the run is a shadow, which files no ask: the round the
// output check takes from it passes.
func TestAnIterationWhoseFindingIsSentAheadPasses(t *testing.T) {
	w := newWorld(t)
	w.held()
	w.output(triage(1, h1, "arch"))
	w.output(lane(1, "arch", h1, review.VerdictRequestChanges, "A1"))
	w.output(repair(1, h1, "", aheadRuling("tk-wait")))
	mustPass(t, w.passed(1))

	w = newWorld(t)
	w.held()
	w.output(triage(1, h1, "arch"))
	w.output(lane(1, "arch", h1, review.VerdictRequestChanges, "A1"))
	w.output(repair(1, h1, "", aheadRuling("")))
	mustFail(t, w.passed(1), "was sent ahead and names no ask the PR waits on")

	w = newWorld(t)
	w.shadowRun()
	w.output(triage(1, h1, "arch"))
	w.output(lane(1, "arch", h1, review.VerdictRequestChanges, "A1"))
	rp := repair(1, h1, "", aheadRuling(""))
	if err := w.check(w.step(1, "rule-and-repair"), rp, nil); err != nil {
		t.Fatalf("a shadow run's finding sent ahead with no ask: %v", err)
	}
	w.output(rp)
	mustPass(t, w.passed(1))
}

// A finding sent ahead stands only on an ask that holds the PR for its fix: one
// that a wait of its own holds, so no round takes it or closes it while the fix
// is open, and that sends the finding's check back. An ask a round can take,
// one that waits on nothing or on a fix that has closed, even one the same
// round answers, and a held ask that sends another check back are refused by
// the output check. Written all the same, such a round does not pass, and the
// loop's last attempt records a result that does not pass.
func TestOnlyAnAskThatHoldsThePRForTheFixStandsForAFindingSentAhead(t *testing.T) {
	answered := review.Ruling{Ask: "tk-other", Ruling: review.RulingAnswered, Reason: "its check ran at the head"}
	for _, c := range []struct {
		name string
		put  func(w *world)
		rp   review.Repair
		why  string
	}{
		{"an ask that waits on nothing and sends no check back, answered in the same round",
			func(w *world) { w.ask("tk-other", "") },
			repair(1, h1, "", aheadRuling("tk-other"), answered), "which no wait of its own holds"},
		{"an ask that sends the check back and waits on nothing",
			func(w *world) { w.ask("tk-other", "arch") },
			repair(1, h1, "", aheadRuling("tk-other"), answered), "which no wait of its own holds"},
		{"an ask whose fix has closed",
			func(w *world) {
				w.store.Put(bead{ID: "tk-fix", Status: "closed", IssueType: "task", ClosedAt: "2026-11-18T09:00:00Z"})
				w.ask("tk-other", "arch", gcbd.Edge{ID: "tk-fix", Type: gcbd.EdgeBlocks, Status: "closed", ClosedAt: "2026-11-18T09:00:00Z"})
			},
			repair(1, h1, "", aheadRuling("tk-other"), answered), "which no wait of its own holds"},
		{"a held ask that sends another check back",
			func(w *world) {
				w.store.Put(bead{ID: "tk-fix", Status: "open", IssueType: "task"})
				w.ask("tk-other", "pm", gcbd.Edge{ID: "tk-fix", Type: gcbd.EdgeBlocks})
				w.store.List("tk-other", "tk-fix")
				w.store.Mark("tk-other")
			},
			repair(1, h1, "", aheadRuling("tk-other")), "which does not send arch back"},
	} {
		t.Run(c.name, func(t *testing.T) {
			w := newWorld(t)
			run, _ := w.store.Row(root)
			run.Metadata["gc.var.max_attempts"] = "1"
			w.store.Put(run)
			c.put(w)
			w.output(triage(1, h1, "arch"))
			w.output(lane(1, "arch", h1, review.VerdictRequestChanges, "A1"))
			mustRefuse(t, w.check(w.step(1, "rule-and-repair"), c.rp, nil), c.why)
			w.output(c.rp)
			mustFail(t, w.passed(1), c.why)
			got := w.record(1)
			if !got.Exhausted || !reflect.DeepEqual(w.results(), []review.Result{{Head: h1, Target: target, Run: root}}) {
				t.Fatalf("the loop's last attempt recorded %+v, %+v; want a result that does not pass", got, w.results())
			}
		})
	}
}

// The head's comment answers a finding sent ahead with the ask its PR waits on,
// and counts it in the lane's row and the round's sentence.
func TestTheCommentAnswersAFindingSentAhead(t *testing.T) {
	w := newWorld(t)
	w.held()
	w.output(triage(1, h1, "arch"))
	w.output(lane(1, "arch", h1, review.VerdictRequestChanges, "A1"))
	w.output(repair(1, h1, "", aheadRuling("tk-wait")))
	run, err := review.ReadRun(w.ledger(), root)
	if err != nil {
		t.Fatal(err)
	}
	got := review.Comment(run, 1, nil)
	for _, want := range []string{
		"| arch | request-changes | 1 P1 | 1 ahead |",
		"The round sent ahead 1.",
		"Ahead of this PR, in work of its own, which this PR waits on through tk-wait: the architecture document lands first, in tk-fix",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("the comment lacks %q:\n%s", want, got)
		}
	}
}
