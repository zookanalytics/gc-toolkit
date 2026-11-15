package pr_test

import (
	"errors"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	ghfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
)

// The draft cycle and the approval withdrawal (specs/tk-1tfzr71.108/design.md,
// sections 4 and 5), each case one of section 12's for its unit, on the
// landing order's world: a bead on the pending record whose PR the evaluator
// reads ready, and the branch's commits older, then head, then later, each
// descending from the one before.

const (
	older    = "0000000000000000000000000000000000000001"
	later    = "3333333333333333333333333333333333333333"
	rewrite  = "4444444444444444444444444444444444444444"
	cityMark = "<!-- gc:city -->"
	material = "Triage ruled head 1111111 a material change: it inferred which side of the merge wins. Look at the merge commit."
)

func newCycle(t *testing.T) *land {
	t.Helper()
	d := newLand(t)
	d.l.Mark = func() (string, error) { return cityMark, nil }
	d.store.CloseTime = "2026-11-12T09:00:00Z"
	d.github.Descends[head] = []string{older}
	d.github.Descends[later] = []string{head, older}
	return d
}

// approved is an approval of commit from an account that can push.
func approved(id int64, login, commit string) gh.Review {
	v := approve(id, login, "2026-11-12T01:00:00Z")
	v.Commit = commit
	return v
}

// edit changes the bead's row as it stands in the store.
func (d *land) edit(t *testing.T, change func(*fake.Bead)) {
	t.Helper()
	b := d.row(t)
	change(&b)
	d.store.Put(b)
}

// withdraw files a withdrawal for h on the bead, and makes the store's blocked
// listing hold the bead on it, as bd's blocked rule does.
func (d *land) withdraw(t *testing.T, h string) string {
	t.Helper()
	w, err := d.l.Withdraw(bead, h, material)
	if err != nil || !w.Filed {
		t.Fatalf("Withdraw: %+v, %v", w, err)
	}
	d.store.List(bead, w.ID)
	return w.ID
}

// states is each review's id and state, in order.
func states(p *ghfake.PR) []string {
	var out []string
	for _, v := range p.Reviews {
		out = append(out, strings.ToLower(v.State))
	}
	return out
}

func status(t *testing.T, d *land, id string) string {
	t.Helper()
	b, ok := d.store.Row(id)
	if !ok {
		t.Fatalf("the store holds no %s", id)
	}
	return b.Status
}

// --- the draft cycle ---------------------------------------------------------

// A round's first push returns a ready PR to draft, and a later push of the
// round finds it a draft and changes nothing. A return to draft dismisses no
// approval.
func TestARoundsFirstPushReturnsAReadyPRToDraftAndLaterPushesChangeNothing(t *testing.T) {
	d := newCycle(t)
	first, err := d.l.Draft(bead, "")
	if err != nil || !first.Converted || first.URL != prURL {
		t.Fatalf("the round's first push read %+v, %v", first, err)
	}
	second, err := d.l.Draft(bead, "")
	if err != nil || second.Converted {
		t.Fatalf("a later push read %+v, %v", second, err)
	}
	if got := asks(d.github); !slices.Equal(got, []string{"ConvertToDraft PR_7 "}) {
		t.Fatalf("asked %v, want one conversion", got)
	}
	if !d.pr.Facts.IsDraft || !slices.Equal(states(d.pr), []string{"approved"}) {
		t.Fatalf("the PR reads draft %v with reviews %v", d.pr.Facts.IsDraft, states(d.pr))
	}
}

// A conversion GitHub did not answer leaves the PR where it stands, and the
// next try reads the flag again and converts it. A PR a person returned to
// draft already is left alone.
func TestADraftStoppedBetweenItsStepsFinishesFromWhereThePRStands(t *testing.T) {
	d := newCycle(t)
	d.github.Fail["ConvertToDraft"] = errors.New("gh: error connecting to api.github.com")
	if _, err := d.l.Draft(bead, ""); err == nil || d.pr.Facts.IsDraft {
		t.Fatalf("an unanswered conversion read as %v, the PR a draft %v", err, d.pr.Facts.IsDraft)
	}
	delete(d.github.Fail, "ConvertToDraft")
	if got, err := d.l.Draft(bead, ""); err != nil || !got.Converted {
		t.Fatalf("the retry read %+v, %v", got, err)
	}
	e := newCycle(t)
	e.pr.Facts.IsDraft = true
	if got, err := e.l.Draft(bead, ""); err != nil || got.Converted || len(e.github.Asks()) != 0 {
		t.Fatalf("a PR a person drafted read %+v, %v, with asks %v", got, err, asks(e.github))
	}
}

// The PR is the one the caller names when the bead's record names none yet, as
// for a PR the refinery adopts. A bead that names no PR, a PR that is not
// open, one open from another branch and one outside the rig's origin are
// left as they stand.
func TestADraftTakesOnlyAnOpenPRTheBeadOwns(t *testing.T) {
	d := newCycle(t)
	d.edit(t, func(b *fake.Bead) { delete(b.Metadata, "pr_url"); delete(b.Metadata, "existing_pr") })
	var refused *pr.DraftRefusal
	if _, err := d.l.Draft(bead, ""); !errors.As(err, &refused) {
		t.Fatalf("a bead that names no PR read as %v", err)
	}
	if got, err := d.l.Draft(bead, prURL); err != nil || !got.Converted {
		t.Fatalf("the PR the caller named read as %+v, %v", got, err)
	}
	for name, change := range map[string]func(p *ghfake.PR){
		"closed":  func(p *ghfake.PR) { p.Facts.State = "CLOSED" },
		"another": func(p *ghfake.PR) { p.Facts.HeadRefName = "polecat/tk-2" },
	} {
		e := newCycle(t)
		change(e.pr)
		if _, err := e.l.Draft(bead, ""); !errors.As(err, &refused) || len(e.github.Asks()) != 0 {
			t.Fatalf("a %s PR read as %v, with asks %v", name, err, asks(e.github))
		}
	}
	e := newCycle(t)
	var origin *pr.OriginError
	if _, err := e.l.Draft(bead, "https://github.com/acme/other/pull/7"); !errors.As(err, &origin) {
		t.Fatalf("a PR outside the rig's origin read as %v", err)
	}
}

// The order readies a draft whose passed result names its validated head and
// target, with no review run attached, whoever returned it to draft, and does
// not wait for CI: the next run reads the PR again and merges it once it is
// ready.
func TestTheOrderReadiesADraftWhoseResultPassedAtItsValidatedHead(t *testing.T) {
	d := newCycle(t)
	d.pr.Facts.IsDraft = true
	d.pr.Suites = map[string][]gh.CheckSuite{head: {{ID: 1, Runs: []gh.CheckRun{run("test", "QUEUED", "")}}}}
	is(t, d.once(t), pr.ActReadied)
	if got := asks(d.github); !slices.Equal(got, []string{"MarkReady PR_7 "}) || d.pr.Facts.IsDraft {
		t.Fatalf("asked %v, the PR a draft %v", got, d.pr.Facts.IsDraft)
	}
	if !ofRead(t, d, head).Draft {
		t.Fatal("the ready transition saved a read made after it, not the draft the run read")
	}
	o := d.once(t)
	is(t, o, pr.ActChecked)
	if !strings.Contains(o.Detail, "check-pending") {
		t.Fatalf("the PR merged before its checks reported: %s", o.Detail)
	}
	if ofRead(t, d, head).Draft {
		t.Fatal("the check after the ready transition saved the PR as a draft")
	}
	d.pr.Suites = map[string][]gh.CheckSuite{head: {{ID: 1, Runs: []gh.CheckRun{passed("test")}}}}
	is(t, d.once(t), pr.ActRequested)
}

// The order readies no draft whose record is not pending at its head: a result
// that passed at another head, a head the refinery has not validated, or a
// review run still attached to the bead.
func TestTheOrderReadiesNoDraftWhoseRecordIsNotPendingAtItsPassedHead(t *testing.T) {
	d := newCycle(t)
	d.pr.Facts.IsDraft = true
	d.edit(t, func(b *fake.Bead) {
		b.Metadata["review_results"] = `[{"head":"` + other + `","target":"main","passed":true}]`
	})
	is(t, d.once(t), pr.ActChecked)

	e := newCycle(t)
	e.pr.Facts.IsDraft = true
	e.pr.Facts.HeadRefOid = other
	e.edit(t, func(b *fake.Bead) {
		b.Metadata["review_results"] = `[{"head":"` + other + `","target":"main","passed":true}]`
	})
	is(t, e.once(t), pr.ActRequeued)

	f := newCycle(t)
	f.pr.Facts.IsDraft = true
	f.store.Put(fake.Bead{ID: "tk-run", Title: "mol-pr-review", Status: "in_progress",
		Metadata: map[string]string{"gc.kind": "workflow", "gc.formula_name": "mol-pr-review"}})
	f.edit(t, func(b *fake.Bead) {
		b.Edges = append(b.Edges, gcbd.Edge{Type: gcbd.EdgeBlocks, ID: "tk-run", Status: "in_progress"})
	})
	f.store.List(bead, "tk-run")
	is(t, f.once(t), pr.ActChecked)
	for _, w := range []*land{d, e, f} {
		if slices.ContainsFunc(w.github.Asks(), func(a ghfake.Ask) bool { return a.Method == "MarkReady" }) {
			t.Fatalf("a draft not pending at its passed head was marked ready: %v", asks(w.github))
		}
	}
	// Once the run ends, its closed root holds nothing, and the order readies it.
	f.edit(t, func(b *fake.Bead) {})
	f.store.Put(fake.Bead{ID: "tk-run", Title: "mol-pr-review", Status: "closed",
		Metadata: map[string]string{"gc.kind": "workflow", "gc.formula_name": "mol-pr-review"}})
	f.store.Unlist(bead)
	is(t, f.once(t), pr.ActReadied)
}

// A ready transition GitHub did not answer is read again by the next run, which
// reads the flag first, so a PR a person marked ready meanwhile is left as it
// stands.
func TestAReadyTransitionStoppedBetweenItsStepsFinishesFromWhereThePRStands(t *testing.T) {
	d := newCycle(t)
	d.pr.Facts.IsDraft = true
	d.github.Fail["MarkReady"] = errors.New("gh: error connecting to api.github.com")
	is(t, d.once(t), pr.ActRetry)
	ofRead(t, d, head)
	delete(d.github.Fail, "MarkReady")
	is(t, d.once(t), pr.ActReadied)
	e := newCycle(t)
	e.pr.Facts.IsDraft = true
	e.github.Fail["MarkReady"] = errors.New("gh: error connecting to api.github.com")
	is(t, e.once(t), pr.ActRetry)
	delete(e.github.Fail, "MarkReady")
	e.pr.Facts.IsDraft = false
	is(t, e.once(t), pr.ActRequested)
	if n := len(e.github.Asks()); n != 2 {
		t.Fatalf("asked %v, want the failed transition and the merge alone", asks(e.github))
	}
}

// A human gate on the bead, or merge_hold, still holds a PR the order readied:
// a draft is no hold, and the ready transition leaves each hold in place.
func TestAGateOrAMergeHoldStillHoldsAPRTheOrderReadied(t *testing.T) {
	d := newCycle(t)
	d.pr.Facts.IsDraft = true
	d.edit(t, func(b *fake.Bead) { b.Metadata["merge_hold"] = "true" })
	is(t, d.once(t), pr.ActReadied)
	o := d.once(t)
	is(t, o, pr.ActChecked)
	if !strings.Contains(o.Detail, "hold") {
		t.Fatalf("a merge hold did not hold the readied PR: %s", o.Detail)
	}
	e := newCycle(t)
	e.pr.Facts.IsDraft = true
	e.store.Put(fake.Bead{ID: "tk-gate", Title: "a person decides", Status: "open", IssueType: "gate", AwaitType: "human"})
	e.edit(t, func(b *fake.Bead) {
		b.Edges = append(b.Edges, gcbd.Edge{Type: gcbd.EdgeBlocks, ID: "tk-gate", Status: "open"})
	})
	e.store.List(bead, "tk-gate")
	is(t, e.once(t), pr.ActReadied)
	o = e.once(t)
	is(t, o, pr.ActChecked)
	if !strings.Contains(o.Detail, "wait") {
		t.Fatalf("a human gate did not hold the readied PR: %s", o.Detail)
	}
	for _, w := range []*land{d, e} {
		if slices.ContainsFunc(w.github.Asks(), func(a ghfake.Ask) bool { return a.Method == "MergePullRequest" }) {
			t.Fatalf("a held PR was merged: %v", asks(w.github))
		}
	}
}

// A PR approved before a round merges on that approval after the round, which
// returned it to draft and dismissed nothing, unless triage ruled the round's
// head material, which withdraws the approval until a person approves again.
func TestAnApprovalCarriesAcrossARoundUnlessTriageRuledItsHeadMaterial(t *testing.T) {
	for _, ruled := range []bool{false, true} {
		d := newCycle(t)
		d.pr.Reviews = []gh.Review{approved(100, "operator", older)}
		if _, err := d.l.Draft(bead, ""); err != nil {
			t.Fatal(err)
		}
		if ruled {
			d.withdraw(t, head)
		}
		o := d.once(t)
		if !ruled {
			is(t, o, pr.ActReadied)
			is(t, d.once(t), pr.ActRequested)
			continue
		}
		is(t, o, pr.ActReadied)
		if !slices.Equal(states(d.pr), []string{"dismissed"}) || !strings.Contains(o.Detail, "dismissed the approval review 100") {
			t.Fatalf("the material head left reviews %v: %s", states(d.pr), o.Detail)
		}
		d.store.Unlist(bead)
		o = d.once(t)
		if o.Action == pr.ActRequested || !strings.Contains(o.Detail, "approval") {
			t.Fatalf("the PR merged with its approval withdrawn: %+v", o)
		}
		d.pr.Reviews = append(d.pr.Reviews, approved(101, "operator", head))
		is(t, d.once(t), pr.ActRequested)
	}
}

// --- the withdrawal --------------------------------------------------------

// A withdrawal is a task bead that blocks the bead that owns the PR and names
// the head, filed once for a head: a second filing finds the first.
func TestAWithdrawalBlocksTheBeadAndNamesItsHead(t *testing.T) {
	d := newCycle(t)
	id := d.withdraw(t, head)
	w, ok := d.store.Row(id)
	if !ok || w.Status != "open" || w.IssueType != "task" || w.Metadata["withdraw_head"] != head || w.Description != material {
		t.Fatalf("the withdrawal reads %+v", w)
	}
	if !slices.ContainsFunc(d.row(t).Edges, func(e gcbd.Edge) bool { return e.Type == gcbd.EdgeBlocks && e.ID == id }) {
		t.Fatalf("the bead's edges %+v hold no blocks edge onto %s", d.row(t).Edges, id)
	}
	again, err := d.l.Withdraw(bead, head, "said again")
	if err != nil || again.Filed || again.ID != id || len(d.store.Creates()) != 1 {
		t.Fatalf("a second withdrawal for the head read %+v, %v, with creates %+v", again, err, d.store.Creates())
	}
	if len(d.store.Writes()) != 0 {
		t.Fatalf("a withdrawal on a marked record wrote the record: %+v", d.store.Writes())
	}
}

// A withdrawal is filed only on a bead that owns a PR on the record.
func TestAWithdrawalIsFiledOnlyOnABeadThatOwnsAPROnTheRecord(t *testing.T) {
	var refused *pr.WithdrawRefusal
	for name, change := range map[string]func(b *fake.Bead){
		"closed":     func(b *fake.Bead) { b.Status = "closed" },
		"off record": func(b *fake.Bead) { b.Metadata["merge_result"] = "pull_request" },
	} {
		d := newCycle(t)
		d.edit(t, change)
		if _, err := d.l.Withdraw(bead, head, material); !errors.As(err, &refused) || len(d.store.Creates()) != 0 {
			t.Fatalf("a %s bead read as %v, with creates %+v", name, err, d.store.Creates())
		}
	}
	d := newCycle(t)
	if _, err := d.l.Withdraw("tk-none", head, material); !errors.As(err, &refused) {
		t.Fatalf("a bead the store does not hold read as %v", err)
	}
	if _, err := d.l.Withdraw(bead, "abc", material); err == nil {
		t.Fatal("a head that is no commit id was withdrawn")
	}
	if _, err := d.l.Withdraw(bead, head, " "); err == nil {
		t.Fatal("a withdrawal with no reason was filed")
	}
}

// A withdrawal for a head, carried out after a person approved a later head,
// keeps that approval, keeps an approval of the head itself, and dismisses an
// approval of a commit that does not contain the head, with the reason and the
// city's mark. A request for changes is no approval. The withdrawal closes once
// no approval stands on a commit without its head.
func TestAWithdrawalDismissesOnlyTheApprovalsOfACommitWithoutItsHead(t *testing.T) {
	d := newCycle(t)
	d.pr.Reviews = []gh.Review{
		approved(100, "operator", older),
		approved(101, "reviewer", head),
		approved(102, "operator", later),
		{ID: 103, State: "CHANGES_REQUESTED", Author: "visitor", AuthorCanPush: true, Commit: older},
		approved(104, "former", rewrite),
	}
	d.pr.Facts.HeadRefOid = later
	id := d.withdraw(t, head)
	o := d.once(t)
	is(t, o, pr.ActRequeued)
	if got := states(d.pr); !slices.Equal(got, []string{"dismissed", "approved", "approved", "changes_requested", "dismissed"}) {
		t.Fatalf("the reviews read %v", got)
	}
	for _, a := range d.github.Asks() {
		if a.Method == "DismissReview" && a.Message != material+"\n\n"+cityMark {
			t.Fatalf("a dismissal said %q", a.Message)
		}
	}
	if status(t, d, id) != "closed" {
		t.Fatalf("the withdrawal is %s after no approval without its head stood", status(t, d, id))
	}
	meta(t, d.row(t), map[string]string{"merge_result": record.HeadChanged, "pr_reconcile_pending": "<absent>"})
}

// A withdrawal waits while an approval it would dismiss carries an inline
// comment the intake has not routed, because a dismissal retires it unread, and
// dismisses once the intake routed it.
func TestAWithdrawalWaitsWhileAnApprovalItWouldDismissCarriesUnroutedComments(t *testing.T) {
	d := newCycle(t)
	d.pr.Reviews = []gh.Review{approved(100, "operator", older)}
	d.pr.Threads = []gh.Thread{{ID: "T1", Comments: []gh.Comment{{ID: 300, Author: "operator", Body: "rename this",
		CreatedAt: "2026-11-12T01:00:00Z", Review: &gh.CommentReview{ID: 100, State: "APPROVED", SubmittedAt: "2026-11-12T01:00:00Z"}}}}}
	id := d.withdraw(t, head)
	o := d.once(t)
	is(t, o, pr.ActChecked)
	if !strings.Contains(o.Detail, "inline comment 300") || slices.ContainsFunc(d.github.Asks(), func(a ghfake.Ask) bool { return a.Method == "DismissReview" }) {
		t.Fatalf("a withdrawal over an unrouted comment read %s, with asks %v", o.Detail, asks(d.github))
	}
	d.edit(t, func(b *fake.Bead) { b.Metadata["pr_comment_watermark"] = "300" })
	d.once(t)
	if status(t, d, id) != "closed" || !slices.Equal(states(d.pr), []string{"dismissed"}) {
		t.Fatalf("once routed, the withdrawal is %s and the reviews %v", status(t, d, id), states(d.pr))
	}
}

// A withdrawal holds the PR until no approval that stands was given on a commit
// without its head: a dismissal GitHub did not answer and a compare GitHub did
// not answer each leave the withdrawal open for the next run, and the PR waits
// on it.
func TestAWithdrawalHoldsThePRUntilNoApprovalWithoutItsHeadStands(t *testing.T) {
	d := newCycle(t)
	d.pr.Reviews = []gh.Review{approved(100, "operator", older), approved(101, "reviewer", head)}
	id := d.withdraw(t, head)
	d.github.Fail["Compare"] = errors.New("gh: gh: Bad Gateway (HTTP 502)")
	o := d.once(t)
	is(t, o, pr.ActChecked)
	if !strings.Contains(o.Detail, "wait") || status(t, d, id) != "open" {
		t.Fatalf("an unanswered compare read %s, the withdrawal %s", o.Detail, status(t, d, id))
	}
	delete(d.github.Fail, "Compare")
	d.github.Fail["DismissReview"] = errors.New("gh: error connecting to api.github.com")
	o = d.once(t)
	is(t, o, pr.ActChecked)
	if status(t, d, id) != "open" || len(d.gates.list()) != 0 {
		t.Fatalf("an unanswered dismissal left the withdrawal %s, with gates %v", status(t, d, id), d.gates.list())
	}
	delete(d.github.Fail, "DismissReview")
	d.once(t)
	if status(t, d, id) != "closed" || !slices.Equal(states(d.pr), []string{"dismissed", "approved"}) {
		t.Fatalf("the withdrawal is %s with reviews %v", status(t, d, id), states(d.pr))
	}
	d.store.Unlist(bead)
	is(t, d.once(t), pr.ActRequested)
}

// A compare GitHub refuses, as for a commit it no longer holds, does not show
// that the approved commit contains the head, so the approval is dismissed and
// the withdrawal closes, where waiting would hold the PR on every run with no
// one asked. An approval of the head itself stands, since it needs no compare.
func TestAnApprovalWhoseCompareGitHubRefusesIsDismissed(t *testing.T) {
	d := newCycle(t)
	d.pr.Reviews = []gh.Review{approved(100, "former", rewrite), approved(101, "reviewer", head)}
	d.github.Fail["Compare"] = errors.New("gh: gh: Not Found (HTTP 404)")
	id := d.withdraw(t, head)
	d.once(t)
	if status(t, d, id) != "closed" || !slices.Equal(states(d.pr), []string{"dismissed", "approved"}) {
		t.Fatalf("a refused compare left the withdrawal %s with reviews %v", status(t, d, id), states(d.pr))
	}
}

// A withdrawal is a plain task, so the runtime's work-record gate reads its
// close, and once enforced it refuses a close that names no outcome. A
// withdrawal carried out, with an approval to dismiss or none, closes with a
// no-op record the gate takes.
func TestACarriedOutWithdrawalClosesWithANoOpWorkRecord(t *testing.T) {
	for _, reviews := range [][]gh.Review{{approved(100, "operator", older)}, nil} {
		d := newCycle(t)
		d.store.WorkRecordGate = true
		d.pr.Reviews = reviews
		id := d.withdraw(t, head)
		d.once(t)
		b, _ := d.store.Row(id)
		if b.Status != "closed" || b.Metadata["gc.work_outcome"] != "no-op" {
			t.Fatalf("with %d approval(s) to dismiss, the withdrawal is %s with work outcome %q",
				len(reviews), b.Status, b.Metadata["gc.work_outcome"])
		}
	}
}

// When GitHub refuses a dismissal, the withdrawal files a human gate on the
// bead naming the reviews, and stays open until a person dismisses them.
func TestAWithdrawalFilesItsGateWhenGitHubRefuses(t *testing.T) {
	d := newCycle(t)
	d.pr.Reviews = []gh.Review{approved(100, "operator", older)}
	d.github.OnDismiss = func(*ghfake.PR, int64) error {
		return errors.New("gh: gh: Must have admin rights to Repository. (HTTP 403)")
	}
	id := d.withdraw(t, head)
	o := d.once(t)
	is(t, o, pr.ActChecked)
	if got := d.gates.list(); !slices.Equal(got, []string{bead + " approval-withdraw-refused"}) {
		t.Fatalf("gates %v, want the refusal's", got)
	}
	if msg := d.gates.messages[0]; !strings.Contains(msg, "review 100 (operator)") || !strings.Contains(msg, id) {
		t.Fatalf("the gate's message names neither the review nor the withdrawal: %s", msg)
	}
	if status(t, d, id) != "open" {
		t.Fatalf("a refused withdrawal is %s", status(t, d, id))
	}
	d.pr.Reviews[0].State = "DISMISSED"
	d.once(t)
	if status(t, d, id) != "closed" {
		t.Fatalf("once a person dismissed the review, the withdrawal is %s", status(t, d, id))
	}
}

// A withdrawal holds the bead from the refinery, so a changed head the order
// sends back keeps its record marked while the withdrawal is open, the order
// carries the withdrawal out on a later run, and then clears the marker.
func TestAWithdrawalOnAHeadSentBackToTheRefineryKeepsItsRecordMarked(t *testing.T) {
	d := newCycle(t)
	d.pr.Reviews = []gh.Review{approved(100, "operator", older)}
	d.pr.Threads = []gh.Thread{{ID: "T1", Comments: []gh.Comment{{ID: 300, Author: "operator", Body: "rename this",
		CreatedAt: "2026-11-12T01:00:00Z", Review: &gh.CommentReview{ID: 100, State: "APPROVED", SubmittedAt: "2026-11-12T01:00:00Z"}}}}}
	d.pr.Facts.HeadRefOid = later
	id := d.withdraw(t, head)
	is(t, d.once(t), pr.ActRequeued)
	meta(t, d.row(t), map[string]string{"merge_result": record.HeadChanged, "pr_reconcile_pending": "true"})
	ofRead(t, d, later)
	is(t, d.once(t), pr.ActChecked)
	ofRead(t, d, later)
	d.edit(t, func(b *fake.Bead) { b.Metadata["pr_comment_watermark"] = "300" })
	is(t, d.once(t), pr.ActSettled)
	if status(t, d, id) != "closed" || d.row(t).Status != "open" {
		t.Fatalf("the withdrawal is %s and the bead %s", status(t, d, id), d.row(t).Status)
	}
	meta(t, d.row(t), map[string]string{"merge_result": record.HeadChanged, "pr_reconcile_pending": "<absent>"})
}

// A withdrawal filed on a head the order already sent back, whose record has
// no marker, marks the record, so the order reads it until the withdrawal is
// carried out.
func TestAWithdrawalFiledOnAHeadSentBackMarksItsRecord(t *testing.T) {
	d := newCycle(t)
	d.pr.Reviews = []gh.Review{approved(100, "operator", older)}
	d.pr.Facts.HeadRefOid = later
	d.edit(t, func(b *fake.Bead) {
		b.Status = "open"
		b.Metadata["merge_result"] = record.HeadChanged
		b.Metadata["observed_pr_head_sha"] = later
		delete(b.Metadata, "pr_reconcile_pending")
	})
	id := d.withdraw(t, later)
	meta(t, d.row(t), map[string]string{"pr_reconcile_pending": "true"})
	is(t, d.once(t), pr.ActSettled)
	if status(t, d, id) != "closed" || !slices.Equal(states(d.pr), []string{"dismissed"}) {
		t.Fatalf("the withdrawal is %s with reviews %v", status(t, d, id), states(d.pr))
	}
}
