package pr_test

import (
	"context"
	"errors"
	"maps"
	"slices"
	"strconv"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
)

// The conversion of pr-facts.sh's receipts (specs/tk-1tfzr71.161/design.md,
// section 2's "The old receipts on a moved bead" and section 11's tests for
// unit 3), on the landing order's world: a bead on the pending record that
// carries the old path's watermarks, answered marks and batch ledgers has the
// posts they reach marked with the city's EYES, the threads that hold only the
// city's own posts resolved and its open human findings filed as the asks of
// their posts, before any take, and then the receipts unset.

// receipts are pr-facts.sh's receipts as the cases put them on the bead: they
// reach review 200, inline comment 600, past a watermark of 550, and
// conversation comment 900, and the inline batch went to the ask tk-9.
var receipts = map[string]string{
	"pr_review_watermark": "200", "pr_comment_watermark": "550", "pr_comment_answered": "600",
	"pr_issue_comment_watermark": "900", "pr_review_batch": "rework:tk-9|0|200",
	"pr_comment_batch": "rework:tk-9|0|550", "pr_issue_comment_batch": "rework:tk-9|0|900",
	"pr_comment_disposition": "rework:tk-9", "pr_review_answered": "200",
}

// converting is the landing order's world whose bead carries the receipts and
// whose PR holds, besides the approval the world starts with, posts on both
// sides of them: below the marks a review's message, an approval's message, a
// review pr-facts.sh marked when it routed it, two inline comments and a
// conversation comment, and above them a review, an inline comment and a
// conversation comment. One thread holds only the city's own finding, and in
// another a person answered the city's finding.
func converting(t *testing.T) *land {
	t.Helper()
	d := newLand(t)
	d.l.Mark = func() (string, error) { return cityMark, nil }
	at := "2026-11-12T05:00:00Z"
	review := func(id int64, state, author, body string, reactions ...string) gh.Review {
		n := strconv.FormatInt(id, 10)
		return gh.Review{ID: id, NodeID: "PRR_" + n, URL: prURL + "#pullrequestreview-" + n, State: state,
			Author: author, Body: body, SubmittedAt: at, ViewerReactions: reactions}
	}
	inline := func(id, carrier int64, author string) gh.Comment {
		n := strconv.FormatInt(id, 10)
		return gh.Comment{ID: id, NodeID: "PRRC_" + n, URL: prURL + "#discussion_r" + n, Author: author,
			Body: "on this line", CreatedAt: at, Path: "a/b.go", OriginalLine: 42,
			Review: &gh.CommentReview{ID: carrier, State: "COMMENTED", SubmittedAt: at}}
	}
	conversation := func(id int64, author string) gh.IssueComment {
		n := strconv.FormatInt(id, 10)
		return gh.IssueComment{ID: id, NodeID: "IC_" + n, URL: prURL + "#issuecomment-" + n, Author: author,
			Body: "a point", CreatedAt: at}
	}
	d.pr.Reviews = append(d.pr.Reviews,
		review(150, "COMMENTED", "visitor", "a few points"),
		review(160, "APPROVED", "reviewer", "approved, but rename X"),
		review(180, "COMMENTED", "visitor", "routed already", "EYES"),
		review(250, "COMMENTED", "visitor", "one more point"))
	d.pr.Threads = []gh.Thread{
		{ID: "T1", Comments: []gh.Comment{inline(500, 150, "visitor")}},
		{ID: "T2", Comments: []gh.Comment{inline(510, 150, self)}},
		{ID: "T3", Comments: []gh.Comment{inline(520, 150, self), inline(530, 150, "operator")}},
		{ID: "T4", Comments: []gh.Comment{inline(700, 250, "visitor")}},
	}
	d.rule.notFeedback[510], d.rule.notFeedback[520] = true, true
	d.pr.Comments = []gh.IssueComment{conversation(800, "operator"), conversation(950, "operator")}
	maps.Copy(d.md, receipts)
	d.put("blocked", "")
	d.holdOnAsks()
	return d
}

// conversionOf splits a run's outcomes into the conversion's and the rest. A
// run that made no conversion gives a zero outcome for it.
func conversionOf(t *testing.T, out []pr.RunOutcome) (pr.RunOutcome, []pr.RunOutcome) {
	t.Helper()
	var c pr.RunOutcome
	var rest []pr.RunOutcome
	for _, o := range out {
		if strings.Contains(o.Detail, "the conversion of pr-facts.sh's receipts on "+bead) {
			if c.Action != "" {
				t.Fatalf("two conversions in one run: %+v", out)
			}
			c = o
			continue
		}
		rest = append(rest, o)
	}
	return c, rest
}

// resolved is each review thread the run asked GitHub to resolve.
func (d *land) resolved() []string {
	var out []string
	for _, a := range d.github.Asks()[d.asked:] {
		if a.Method == "ResolveThread" {
			out = append(out, a.ID)
		}
	}
	return out
}

// carriesNoReceipt fails unless the bead carries none of the receipts.
func carriesNoReceipt(t *testing.T, d *land) {
	t.Helper()
	md := d.row(t).Metadata
	for k := range receipts {
		if v, ok := md[k]; ok {
			t.Errorf("the bead still carries %s=%q", k, v)
		}
	}
}

// The conversion marks with the city's EYES each post the receipts reach that
// carries neither of the city's marks, and files nothing for them: the review
// message, the inline comments at or below the answered mark and the
// conversation comment. It leaves the review pr-facts.sh marked as it is, and
// an approval's message, which no receipt reaches, since pr-facts.sh routed
// none. It resolves the thread that holds only the city's own finding and
// leaves the one a person answered. Once the one-PR update has read the
// conversation again, it unsets the receipts, and the run makes no take. The
// next run takes the posts no receipt reaches, the approval's message among
// them.
func TestTheConversionMarksThePostsTheReceiptsReachAndFilesNothing(t *testing.T) {
	d := converting(t)
	d.refresh(t)
	d.asked = len(d.github.Asks())
	out := d.reconcile(t, pr.Options{})
	c, rest := conversionOf(t, out)
	is(t, c, pr.ActConverted)
	says(t, c, "resolved thread T2", "unset pr_review_watermark, pr_comment_watermark")
	if take, _ := takeOf(t, rest); take.Action != "" {
		t.Fatalf("the run that converted the receipts took %+v", take)
	}
	if got, want := d.marked(), []string{"PRR_150 EYES", "PRRC_500 EYES", "PRRC_530 EYES", "IC_800 EYES"}; !slices.Equal(got, want) {
		t.Fatalf("the conversion marked %q, want %q", got, want)
	}
	if got := d.resolved(); !slices.Equal(got, []string{"T2"}) {
		t.Fatalf("the conversion resolved %q, want the city's own thread T2 alone", got)
	}
	if got := d.asksFiled(); len(got) != 0 {
		t.Fatalf("the conversion filed %q for posts the old path routed", got)
	}
	carriesNoReceipt(t, d)
	var left []int64
	for _, p := range d.savedConversation(t).Untaken {
		left = append(left, p.ID)
	}
	if want := []int64{160, 250, 700, 950}; !slices.Equal(left, want) {
		t.Fatalf("after the conversion the saved read holds %v untaken, want %v", left, want)
	}

	d.asked = len(d.github.Asks())
	take, _ := takeOf(t, d.reconcile(t, pr.Options{}))
	is(t, take, pr.ActTaken)
	want := []string{
		"Approval message by reviewer on PR #7: " + prURL + "#pullrequestreview-160",
		"Review by visitor on PR #7: " + prURL + "#pullrequestreview-250",
		"Inline comment by visitor on PR #7 at a/b.go line 42: " + prURL + "#discussion_r700",
		"Conversation comment by operator on PR #7: " + prURL + "#issuecomment-950",
	}
	if got := d.asksFiled(); !slices.Equal(got, want) {
		t.Fatalf("the take after the conversion filed\n%q\nwant\n%q", got, want)
	}
}

// Each receipt alone makes the bead's conversion due, reaches as far as its
// value says in its own id space, and is unset by it: a watermark and an
// answered mark by their id, a batch ledger by its records' inclusive marks,
// and the last batch's disposition by naming the bead the batch went to.
func TestEachReceiptIsConverted(t *testing.T) {
	for _, c := range []struct {
		key, value string
		marks      []string
	}{
		{"pr_review_watermark", "150", []string{"PRR_150 EYES"}},
		{"pr_review_answered", "150", []string{"PRR_150 EYES"}},
		{"pr_review_batch", "rework:tk-9|0|150", []string{"PRR_150 EYES"}},
		{"pr_comment_watermark", "500", []string{"PRRC_500 EYES"}},
		{"pr_comment_answered", "530", []string{"PRRC_500 EYES", "PRRC_530 EYES"}},
		{"pr_comment_batch", "rework:tk-8|0|500;rework:tk-9|500|530", []string{"PRRC_500 EYES", "PRRC_530 EYES"}},
		{"pr_issue_comment_watermark", "800", []string{"IC_800 EYES"}},
		{"pr_issue_comment_batch", "rework:tk-9|0|800", []string{"IC_800 EYES"}},
		{"pr_comment_disposition", "rework:tk-9", nil},
	} {
		t.Run(c.key, func(t *testing.T) {
			d := converting(t)
			for k := range receipts {
				delete(d.md, k)
			}
			d.md[c.key] = c.value
			d.put("blocked", "")
			d.refresh(t)
			d.asked = len(d.github.Asks())
			conv, _ := conversionOf(t, d.reconcile(t, pr.Options{}))
			is(t, conv, pr.ActConverted)
			says(t, conv, "unset "+c.key)
			if got := d.marked(); !slices.Equal(got, c.marks) {
				t.Fatalf("the conversion marked %q, want %q", got, c.marks)
			}
			if v, ok := d.row(t).Metadata[c.key]; ok {
				t.Fatalf("the bead still carries %s=%q", c.key, v)
			}
		})
	}
}

// No take is made on a bead that still carries the receipts. A conversion that
// does not complete, here because GitHub did not answer a thread's resolution,
// leaves them on the bead, so the run exits non-zero and takes nothing, though
// the saved read holds posts the city has not taken. The marks that landed
// stand, and the next run completes the conversion, which leaves them as they
// are, and the take follows.
func TestNoTakeOnABeadThatStillCarriesTheReceipts(t *testing.T) {
	d := converting(t)
	d.github.Fail["ResolveThread"] = errors.New("gh: error connecting to api.github.com")
	d.refresh(t)
	d.asked = len(d.github.Asks())
	c, rest := conversionOf(t, d.reconcile(t, pr.Options{}))
	is(t, c, pr.ActRetry)
	says(t, c, "thread T2", "did not resolve", "the receipts stay")
	if take, _ := takeOf(t, rest); take.Action != "" || len(d.asksFiled()) != 0 {
		t.Fatalf("a run on a bead that carries the receipts took %+v and filed %q", take, d.asksFiled())
	}
	if v := d.row(t).Metadata["pr_comment_watermark"]; v != "550" {
		t.Fatalf("a conversion that did not complete left pr_comment_watermark=%q", v)
	}
	if len(d.savedConversation(t).Untaken) == 0 {
		t.Fatal("the case wants untaken posts in the saved read that a take would file")
	}
	delete(d.github.Fail, "ResolveThread")
	d.asked = len(d.github.Asks())
	c, _ = conversionOf(t, d.reconcile(t, pr.Options{}))
	is(t, c, pr.ActConverted)
	if got := d.marked(); len(got) != 0 {
		t.Fatalf("the conversion marked %q again", got)
	}
	carriesNoReceipt(t, d)
	take, _ := takeOf(t, d.reconcile(t, pr.Options{}))
	is(t, take, pr.ActTaken)
}

// A conversion unsets the receipts only once the saved read shows the marks it
// left, so the take, which decides from the saved read, never files a post the
// old path routed: when the one-PR update's read of the conversation does not
// save, the receipts stay and the run takes nothing, and the next run reads
// the conversation again and unsets them.
func TestTheReceiptsStayUntilTheSavedReadShowsTheMarks(t *testing.T) {
	d := converting(t)
	refresh := d.l.RefreshConversation
	d.l.RefreshConversation = func(context.Context, string) error {
		return errors.New("the PR's conversation did not read: gh: error connecting to api.github.com")
	}
	d.refresh(t)
	c, rest := conversionOf(t, d.reconcile(t, pr.Options{}))
	is(t, c, pr.ActRetry)
	says(t, c, "did not save", "marked")
	if take, _ := takeOf(t, rest); take.Action != "" {
		t.Fatalf("the run took %+v over a saved read that shows the old path's posts untaken", take)
	}
	if _, ok := d.row(t).Metadata["pr_review_watermark"]; !ok {
		t.Fatal("the receipts were unset before the saved read showed the marks")
	}
	d.l.RefreshConversation = refresh
	c, _ = conversionOf(t, d.reconcile(t, pr.Options{}))
	is(t, c, pr.ActConverted)
	carriesNoReceipt(t, d)
	if got := d.asksFiled(); len(got) != 0 {
		t.Fatalf("the conversion filed %q", got)
	}
}

// The unset reads the saved read itself: a read of the conversation that
// answers but leaves the saved read as it was, showing a post the receipts
// reach untaken, unsets nothing.
func TestTheUnsetReadsTheSavedRead(t *testing.T) {
	d := converting(t)
	d.l.RefreshConversation = func(context.Context, string) error { return nil }
	d.refresh(t)
	c, rest := conversionOf(t, d.reconcile(t, pr.Options{}))
	is(t, c, pr.ActRetry)
	says(t, c, "the saved read shows the message of review 150, which they reach, untaken")
	if take, _ := takeOf(t, rest); take.Action != "" {
		t.Fatalf("the run took %+v", take)
	}
	if _, ok := d.row(t).Metadata["pr_review_watermark"]; !ok {
		t.Fatal("the receipts were unset over a saved read that shows a post they reach untaken")
	}
}

// The conversion acts only on a bead the order may work, while the saved read
// shows its PR open: a bead someone else is assigned and a PR that closed are
// converted nothing, and their receipts stay.
func TestTheConversionConvertsNothingOnABeadItMayNotWork(t *testing.T) {
	for name, edit := range map[string]func(*land){
		"assigned to someone else": func(d *land) { d.put("blocked", "rig/gc-toolkit.polecat-1") },
		"closed":                   func(d *land) { d.pr.Facts.State = "CLOSED" },
	} {
		t.Run(name, func(t *testing.T) {
			d := converting(t)
			edit(d)
			d.refresh(t)
			d.asked = len(d.github.Asks())
			out := d.reconcile(t, pr.Options{})
			if c, _ := conversionOf(t, out); c.Action != "" || len(d.marked()) != 0 || len(d.resolved()) != 0 ||
				len(d.asksFiled()) != 0 {
				t.Fatalf("the run converted %+v, marked %q, resolved %q and filed %q over %+v", c, d.marked(),
					d.resolved(), d.asksFiled(), out)
			}
			if v := d.row(t).Metadata["pr_comment_watermark"]; v != "550" {
				t.Fatalf("the run left pr_comment_watermark=%q", v)
			}
		})
	}
}

// The unset is guarded on the status and assignee the act read under the
// record lock: a bead another writer reached between that read and the write,
// here assigning it to an agent, keeps its receipts.
func TestTheUnsetIsGuardedOnTheBeadItRead(t *testing.T) {
	d := converting(t)
	d.refresh(t)
	once := false
	d.store.BeforeUpdate = func(id string, args []string) error {
		if id == bead && slices.Contains(args, "pr_review_watermark") && !once {
			once = true
			d.edit(t, func(b *fake.Bead) { b.Assignee = "rig/gc-toolkit.polecat-1" })
		}
		return nil
	}
	c, _ := conversionOf(t, d.reconcile(t, pr.Options{}))
	is(t, c, pr.ActMoved)
	if v := d.row(t).Metadata["pr_review_watermark"]; v != "200" {
		t.Fatalf("an unset the guard refused left pr_review_watermark=%q", v)
	}
}

// A bead that carries none of the receipts is not converted: the run makes no
// conversion and resolves no thread, even one that holds only the city's own
// posts, and the take files each post the saved read holds untaken.
func TestABeadWithNoReceiptsIsNotConverted(t *testing.T) {
	d := converting(t)
	for k := range receipts {
		delete(d.md, k)
	}
	d.put("blocked", "")
	d.refresh(t)
	d.asked = len(d.github.Asks())
	out := d.reconcile(t, pr.Options{})
	if c, _ := conversionOf(t, out); c.Action != "" {
		t.Fatalf("a bead with no receipts was converted: %+v", c)
	}
	if got := d.resolved(); len(got) != 0 {
		t.Fatalf("the run resolved %q on a bead with no receipts", got)
	}
	take, _ := takeOf(t, out)
	is(t, take, pr.ActTaken)
	if n := len(d.asksFiled()); n != 8 {
		t.Fatalf("the take filed %d asks, want one for each of the eight untaken posts", n)
	}
}

// findings puts the old path's open batch on the bead: the ask tk-9 its
// batches went to, which blocks the bead, and an open human finding for each
// kind of post, which names it as the fix unit it waits on, as a must-fix one
// does: the message of review 150, inline comment 500, conversation comment
// 800, and a conversation comment that is no longer on the PR. finding.sh
// files a finding as the bead's child, related to it, and a must-fix one blocks
// the bead.
func (d *land) findings(t *testing.T) []string {
	t.Helper()
	d.store.Put(fake.Bead{ID: "tk-9", Title: "Review ask: Review feedback on PR#7 is unanswered", Status: "open",
		IssueType: "task", Description: "Review feedback on PR#7 is unanswered at head " + head,
		Metadata: map[string]string{"branch": branch}})
	edges := []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "tk-9", Status: "open"}}
	ids := []string{"tk-f1", "tk-f2", "tk-f3", "tk-f4"}
	for i, f := range []struct{ comment, review string }{{"150", "150"}, {"500", "150"}, {"800", ""}, {"990", ""}} {
		md := map[string]string{"task_kind": "finding", "anchor_bead": bead, "finding.lane": "human",
			"finding.source": "human:visitor", "finding.disposition": "must-fix", "finding.fix_unit": "tk-9",
			"finding.comment_id": f.comment}
		if f.review != "" {
			md["finding.review_id"] = f.review
		}
		d.store.Put(fake.Bead{ID: ids[i], Title: "finding[human]: a point", Status: "open", IssueType: "task",
			Metadata: md, Edges: []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "tk-9", Status: "open"}}})
		edges = append(edges, gcbd.Edge{Type: gcbd.EdgeBlocks, ID: ids[i], Status: "open"})
	}
	d.edit(t, func(b *fake.Bead) { b.Edges = append(b.Edges, edges...) })
	d.holdOnAsks(append([]string{"tk-9"}, ids...)...)
	return ids
}

// Each open human finding's post becomes its own ask, filed under the reason
// the take would file it under and marked once the ask stands, and the
// finding closes onto that ask through the disposition writer. The ask the
// batch went to closes, so no review run takes the batch, and a finding whose
// post is gone closes with nothing owed. The receipts go once no finding and
// no batch ask is left open.
func TestAHumanFindingIsSupersededByItsPostsAsk(t *testing.T) {
	d := converting(t)
	r := &rehome{store: d.store}
	d.l.Dispositions = r
	ids := d.findings(t)
	d.refresh(t)
	d.asked = len(d.github.Asks())
	c, _ := conversionOf(t, d.reconcile(t, pr.Options{}))
	is(t, c, pr.ActConverted)
	want := []string{
		"Review by visitor on PR #7: " + prURL + "#pullrequestreview-150",
		"Inline comment by visitor on PR #7 at a/b.go line 42: " + prURL + "#discussion_r500",
		"Conversation comment by operator on PR #7: " + prURL + "#issuecomment-800",
	}
	if got := d.asksFiled(); !slices.Equal(got, want) {
		t.Fatalf("the conversion filed\n%q\nwant\n%q", got, want)
	}
	if got, want := d.marked(), []string{"PRR_150 EYES", "PRRC_500 EYES", "IC_800 EYES", "PRRC_530 EYES"}; !slices.Equal(got, want) {
		t.Fatalf("the conversion marked %q, want %q", got, want)
	}
	var closes []string
	for _, call := range r.calls {
		f, rest, _ := strings.Cut(call, " ")
		kind, ask, _ := strings.Cut(rest, " ")
		a, ok := d.store.Row(ask)
		if kind != "re-homed" || !ok || !slices.Contains(want, a.Description) {
			t.Fatalf("the writer was asked %q, which names no ask the conversion filed", call)
		}
		closes = append(closes, f)
	}
	if !slices.Equal(closes, ids[:3]) {
		t.Fatalf("the writer closed %v onto their posts' asks, want %v", closes, ids[:3])
	}
	for _, id := range append([]string{"tk-9"}, ids...) {
		if b, _ := d.store.Row(id); b.Status != "closed" {
			t.Errorf("%s is %s after the conversion, want closed", id, b.Status)
		}
	}
	if b, _ := d.store.Row(ids[3]); !strings.Contains(b.Notes, "no longer on the PR") {
		t.Errorf("the finding whose post is gone closed with the notes %q", b.Notes)
	}
	carriesNoReceipt(t, d)
}

// While a review run is attached to a bead whose old path's findings are open,
// the conversion waits for the run to end, since the run may rule them, and
// reads nothing of GitHub; once the run has ended it converts them.
func TestTheConversionWaitsForAnAttachedReviewRun(t *testing.T) {
	d := converting(t)
	d.l.Dispositions = &rehome{store: d.store}
	d.findings(t)
	p := &pours{store: d.store}
	run, err := p.Pour("mol-pr-review", bead, map[string]string{"head": head, "target": "main"})
	if err != nil {
		t.Fatal(err)
	}
	d.refresh(t)
	d.asked, d.reads = len(d.github.Asks()), len(d.github.Reads())
	c, _ := conversionOf(t, d.reconcile(t, pr.Options{}))
	is(t, c, pr.ActChecked)
	says(t, c, "waits for review run "+run)
	if got := d.runReads(); len(got) != 0 || len(d.marked()) != 0 || len(d.asksFiled()) != 0 {
		t.Fatalf("a conversion waiting on a run read %v, marked %q and filed %q", got, d.marked(), d.asksFiled())
	}
	root, _ := d.store.Row(run)
	root.Status = "closed"
	d.store.Put(root)
	c, _ = conversionOf(t, d.reconcile(t, pr.Options{}))
	is(t, c, pr.ActConverted)
}

// While another open bead works the PR's branch, such as a rework child, the
// conversion of a bead whose old path's findings are open waits for it, since
// it may answer them, and reads nothing of GitHub; once that bead has closed it
// converts them.
func TestTheConversionWaitsWhileAnotherBeadWorksTheBranch(t *testing.T) {
	d := converting(t)
	d.l.Dispositions = &rehome{store: d.store}
	d.findings(t)
	kid := fake.Bead{ID: "tk-kid", Title: "Rework the branch", Status: "in_progress", IssueType: "task",
		Assignee: "rig/gc-toolkit.polecat-1", Metadata: map[string]string{"branch": branch, "task_kind": "rework"}}
	d.store.Put(kid)
	d.refresh(t)
	d.asked, d.reads = len(d.github.Asks()), len(d.github.Reads())
	c, _ := conversionOf(t, d.reconcile(t, pr.Options{}))
	is(t, c, pr.ActChecked)
	says(t, c, "waits while tk-kid works "+branch)
	if got := d.runReads(); len(got) != 0 || len(d.marked()) != 0 || len(d.asksFiled()) != 0 {
		t.Fatalf("a conversion waiting on another writer read %v, marked %q and filed %q", got, d.marked(), d.asksFiled())
	}
	kid.Status = "closed"
	d.store.Put(kid)
	c, _ = conversionOf(t, d.reconcile(t, pr.Options{}))
	is(t, c, pr.ActConverted)
}

// No review run is poured on a bead that still carries the receipts, since the
// conversion files the asks of the old path's findings and closes the ask its
// batches went to: a run poured first would rule the batch as well as the asks
// that replace it. A run decides each record from its one pass of the store, so
// the run that unsets the receipts pours nothing, and the next run pours it.
func TestNoReviewRunIsPouredWhileTheReceiptsStand(t *testing.T) {
	d := converting(t)
	p := &pours{store: d.store}
	d.l.Runs = p
	d.l.Refinery = boundRefinery
	d.edit(t, func(b *fake.Bead) { delete(b.Metadata, "review_results") })
	d.github.Fail["ResolveThread"] = errors.New("gh: error connecting to api.github.com")
	d.refresh(t)
	c, rest := conversionOf(t, d.reconcile(t, pr.Options{}))
	is(t, c, pr.ActRetry)
	if len(rest) != 1 || p.count() != 0 {
		t.Fatalf("over the receipts the record reported %+v and %d runs were poured", rest, p.count())
	}
	is(t, rest[0], pr.ActChecked)
	says(t, rest[0], "no review run is poured while the bead carries pr-facts.sh's receipts")
	delete(d.github.Fail, "ResolveThread")
	c, rest = conversionOf(t, d.reconcile(t, pr.Options{}))
	is(t, c, pr.ActConverted)
	if len(rest) != 1 || p.count() != 0 {
		t.Fatalf("the run that unset the receipts reported %+v and %d runs were poured", rest, p.count())
	}
	take, rest := takeOf(t, d.reconcile(t, pr.Options{}))
	is(t, take, pr.ActTaken)
	if len(rest) != 1 || rest[0].Action != pr.ActPoured || p.count() != 1 {
		t.Fatalf("once the receipts were gone the record reported %+v and %d runs were poured, want one", rest, p.count())
	}
}
