package review_test

import (
	"errors"
	"slices"
	"strings"
	"testing"
	"time"

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

// A sling that does not land leaves the fix filed and no ask, and the next call
// finds the fix on no way to a pool, slings it and files the ask.
func TestAFixWhoseSlingFailedIsSentByTheNextCall(t *testing.T) {
	w := newWorld(t)
	rt := &gcfake.Runtime{OnSling: func(gascity.Sling) gascity.SlingResult {
		return gascity.SlingResult{Result: gascity.Result{Code: 1, Output: "no such pool"}}
	}}
	got, err := review.SendAhead(w.ledger(), t.TempDir(), time.Second, rt, aheadReq(prBead), archIndex(t))
	if err == nil || !strings.Contains(err.Error(), "no such pool") || !got.FixFiled || got.Sent || got.Ask != "" {
		t.Fatalf("SendAhead = %+v, %v; want the fix filed, the sling's failure, and no ask", got, err)
	}
	retry := routes(w)
	again, err := review.SendAhead(w.ledger(), t.TempDir(), time.Second, retry, aheadReq(prBead), archIndex(t))
	if err != nil || again.Fix != got.Fix || again.FixFiled || !again.Sent || !again.AskFiled {
		t.Fatalf("the next call = %+v, %v; want the fix found and slung, and the ask filed", again, err)
	}
	live := &gcfake.Runtime{OnSling: func(gascity.Sling) gascity.SlingResult {
		return gascity.SlingResult{Result: gascity.Result{Code: 3}, Live: []string{"tk-wf"}}
	}}
	row, _ := w.store.Row(got.Fix)
	delete(row.Metadata, "gc.routed_to")
	w.store.Put(row)
	if third, err := review.SendAhead(w.ledger(), t.TempDir(), time.Second, live, aheadReq(prBead), archIndex(t)); err != nil || third.Sent {
		t.Fatalf("a call whose sling finds a live workflow on the fix = %+v, %v; want it standing, sent already", third, err)
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
// not pass.
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
