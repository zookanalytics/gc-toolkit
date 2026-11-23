package pr_test

import (
	"encoding/json"
	"fmt"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	ghfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
)

// Triage's answer (specs/tk-1tfzr71.161/design.md, section 3, "The cheap
// answer"), each case one of section 11's for unit 6, on the world of a
// review round's post: triage answers a person's post that asks for no change
// to the branch and no person's decision, posts that answer as any answer is
// posted, and the ruling step's read leaves the post out, so a round triage
// answers whole leaves rule-and-repair nothing and its step closes at once.

// answers writes triage's output for iteration n, judging h, with the checks
// given and a ruling for each ask it answers.
func (d *rounds) answers(t *testing.T, n int, h string, checks []string, rs ...review.Ruling) {
	t.Helper()
	tr := review.Triage{Review: "triage", Iteration: n, Head: h, Checks: []review.Pick{}, Rulings: rs}
	for _, c := range checks {
		tr.Checks = append(tr.Checks, review.Pick{Check: c, Head: h})
	}
	raw, err := json.Marshal(tr)
	if err != nil {
		t.Fatal(err)
	}
	d.store.Put(fake.Bead{ID: fmt.Sprintf("tk-run-triage-%d", n), Status: "closed",
		Metadata: map[string]string{"gc.root_bead_id": "tk-run", "gc.output_json": string(raw)}})
}

// verdict is the pass rule's verdict on iteration n of the run.
func (d *rounds) verdict(t *testing.T, n int) *review.Verdict {
	t.Helper()
	v, err := review.Passed(ledger.New(d.store), "tk-run", n)
	if err != nil {
		t.Fatal(err)
	}
	return v
}

// record runs the loop's record of the verdict, which must end the loop.
func (d *rounds) record(t *testing.T, v *review.Verdict) *review.Recorded {
	t.Helper()
	got, err := review.Record(ledger.New(d.store), d.l.Dir, time.Second, v, nil)
	if err != nil {
		t.Fatalf("the record: %v", err)
	}
	return got
}

// approval puts the operator's approval of the head on the PR, its message
// "looks good", marked with the city's EYES as the take leaves it.
func (d *rounds) approval() string {
	const url = prURL + "#pullrequestreview-220"
	d.pr.Reviews = append(d.pr.Reviews, gh.Review{ID: 220, NodeID: "PRR_220", URL: url, State: "APPROVED",
		Author: "operator", AuthorCanPush: true, Body: "looks good", SubmittedAt: "2026-11-12T02:30:00Z",
		Commit: head, ViewerReactions: []string{"EYES"}})
	return url
}

func answered(ask, reason string) review.Ruling {
	return review.Ruling{Ask: ask, Ruling: review.RulingAnswered, Reason: reason}
}

func thumbsUp(ask, reason string) review.Ruling {
	r := answered(ask, reason)
	r.Wordless = true
	return r
}

// closed reports whether the store holds the bead id closed.
func (d *rounds) closed(id string) bool {
	b, ok := d.store.Row(id)
	return ok && b.Status == "closed"
}

// A question about the change is answered by triage with a reply that links
// it, and the city's THUMBS_UP. Triage left rule-and-repair nothing, so the
// head's comment is triage's post's to make, the ruling step's read says it
// has nothing to rule or post, the round passes without it, and the loop's
// record closes the ask.
func TestTriageAnswersAQuestionWithAReply(t *testing.T) {
	d := newRounds(t)
	url := d.person(pr.PostConversation)
	ask := d.ask(t, "Conversation comment", url, "2026-11-12T03:00:00Z")
	d.answers(t, 1, head, nil, answered(ask, "Yes: five is the cap the design sets."))
	got := d.posted(t)
	replies := d.cityPosts("<!-- gc:answer " + ask + " -->")
	if len(replies) != 1 || !strings.Contains(replies[0], "]("+url+"): Answered: Yes: five is the cap the design sets.") {
		t.Fatalf("triage's answer posted %q; want one reply that links the post and carries the answer", replies)
	}
	if !d.reacted("IC_5", "THUMBS_UP") {
		t.Fatalf("the question does not carry the city's THUMBS_UP")
	}
	if got.Comment != "posted" {
		t.Fatalf("the head's comment was %q; want posted by triage's post, which leaves rule-and-repair nothing", got.Comment)
	}
	if c := d.cityPosts(review.Mark("tk-run", head)); len(c) != 1 || !strings.Contains(c[0], "The round answered 1.") {
		t.Fatalf("the head's comment reads %q; want it to carry triage's answer", c)
	}

	v := d.verdict(t, 1)
	if left := v.Run.Left(1, v.Asks); len(left) != 0 {
		t.Fatalf("triage left rule-and-repair %q; want nothing", left)
	}
	if !strings.Contains(v.Explain(), "triage left it nothing") || !v.Passed {
		t.Fatalf("the ruling step's read does not say nothing is left, or the round does not pass (%q):\n%s", v.Reasons, v.Explain())
	}
	rec := d.record(t, v)
	if len(rec.Closed) != 1 || rec.Closed[0].ID != ask || !d.closed(ask) {
		t.Fatalf("the record closed %+v; want the question's ask closed", rec.Closed)
	}
}

// An approval's "looks good" is answered by triage with the city's THUMBS_UP alone:
// no words, and the approval stands.
func TestTriageAnswersAnApprovalsLooksGoodWithAThumbsUp(t *testing.T) {
	d := newRounds(t)
	url := d.approval()
	ask := d.ask(t, "Approval message", url, "2026-11-12T03:00:00Z")
	d.answers(t, 1, head, nil, thumbsUp(ask, "An approval that asks for nothing."))
	got := d.posted(t)
	if replies := d.cityPosts("<!-- gc:answer " + ask); len(replies) != 0 || len(got.Replied) != 0 {
		t.Fatalf("a wordless answer got words: %q", replies)
	}
	if !d.reacted("PRR_220", "THUMBS_UP") || !slices.Equal(got.Marked, []string{url}) {
		t.Fatalf("the approval's message is marked %v (%v); want the city's THUMBS_UP on it", d.reacted("PRR_220", "THUMBS_UP"), got.Marked)
	}
	if slices.ContainsFunc(d.github.Asks(), func(a ghfake.Ask) bool { return a.Method == "DismissReview" }) {
		t.Fatalf("the approval was dismissed")
	}
	if v := d.verdict(t, 1); !v.Passed {
		t.Fatalf("the round triage answered whole does not pass: %q", v.Reasons)
	}
}

// A post that asks for a change is left to rule-and-repair: triage answers
// nothing, so its post has nothing to make, the ruling step's read names the
// ask, the round waits on its rulings, and its ruling answers the post in its
// thread.
func TestAPostThatAsksForAChangeIsLeftToRuleAndRepair(t *testing.T) {
	d := newRounds(t)
	url := d.person(pr.PostInline)
	ask := d.ask(t, "Inline comment", url, "2026-11-12T03:00:00Z")
	if _, err := d.l.AnswerRound("tk-run", 1); err == nil || !strings.Contains(err.Error(), "iteration 1 has no rulings yet") {
		t.Fatalf("the post of a round triage answered nothing in: %v; want it refused as having no rulings", err)
	}
	v := d.verdict(t, 1)
	if left := v.Run.Left(1, v.Asks); !slices.Equal(left, []string{"ask " + ask}) {
		t.Fatalf("triage left rule-and-repair %q; want the ask", left)
	}
	if v.Passed || !slices.ContainsFunc(v.Reasons, func(r string) bool { return strings.Contains(r, "triage left it ask "+ask) }) {
		t.Fatalf("the round passed or does not name what triage left: %q", v.Reasons)
	}
	d.rule(t, 1, head, later, review.Ruling{Ask: ask, Ruling: review.RulingMustFix, Reason: "P2 and low-risk: renamed.", Commit: later})
	d.posted(t)
	replies := d.cityPosts("<!-- gc:answer " + ask + " -->")
	if len(replies) != 1 || !strings.Contains(replies[0], "Fixed by `"+later[:12]+"`") || !d.resolved("T1") {
		t.Fatalf("rule-and-repair's answer reads %q, resolved %v; want its fix named in the thread, resolved", replies, d.resolved("T1"))
	}
}

// A round with one of each: triage answers a question with a reply and an
// approval's "looks good" with the city's THUMBS_UP, and leaves a post that asks for a
// change. Its post answers its two and leaves the head's comment to
// rule-and-repair, whose read names the one left. Rule-and-repair's round
// rules it, and its post answers it and posts the head's comment with all
// three, answering triage's two nowhere again. The loop's record closes each
// ask.
func TestARoundWithOneOfEach(t *testing.T) {
	d := newRounds(t)
	inline := d.person(pr.PostInline)
	question := d.person(pr.PostConversation)
	approval := d.approval()
	change := d.ask(t, "Inline comment", inline, "2026-11-12T03:00:00Z")
	q := d.ask(t, "Conversation comment", question, "2026-11-12T03:00:00Z")
	lgtm := d.ask(t, "Approval message", approval, "2026-11-12T03:00:00Z")
	d.answers(t, 1, head, nil, answered(q, "Yes: five is the cap the design sets."),
		thumbsUp(lgtm, "An approval that asks for nothing."))

	got := d.posted(t)
	if got.Comment != "" || len(d.cityPosts(review.Mark("tk-run", head))) != 0 {
		t.Fatalf("triage's post made the head's comment (%q) while rule-and-repair has an ask to rule", got.Comment)
	}
	if !slices.Equal(got.Replied, []string{question}) || !d.reacted("IC_5", "THUMBS_UP") || !d.reacted("PRR_220", "THUMBS_UP") {
		t.Fatalf("triage's post replied to %v and marked %v; want a reply to the question and both marked", got.Replied, got.Marked)
	}
	if d.reacted("PRRC_260", "THUMBS_UP") || len(d.cityPosts("<!-- gc:answer "+change)) != 0 {
		t.Fatalf("triage's post answered the post it left")
	}
	v := d.verdict(t, 1)
	if left := v.Run.Left(1, v.Asks); !slices.Equal(left, []string{"ask " + change}) {
		t.Fatalf("triage left rule-and-repair %q; want the change alone", left)
	}
	if account := v.Explain(); !strings.Contains(account, "ask "+change+" (open") || strings.Contains(account, "ask "+q+" (open") {
		t.Fatalf("the ruling step's read does not list only the ask triage left:\n%s", account)
	}

	d.rule(t, 1, head, "", review.Ruling{Ask: change, Ruling: review.RulingDeclined, Reason: "A nit: the flag's name follows its siblings."})
	made := len(d.posts.made)
	got = d.posted(t)
	if got.Comment != "posted" {
		t.Fatalf("rule-and-repair's post made the head's comment %q; want posted", got.Comment)
	}
	comment := d.cityPosts(review.Mark("tk-run", head))
	for _, want := range []string{"The round declined 1, answered 2.", "(" + change + "): Declined", "(" + q + "): Answered", "(" + lgtm + "): Answered"} {
		if len(comment) != 1 || !strings.Contains(comment[0], want) {
			t.Fatalf("the head's comment lacks %q: %q", want, comment)
		}
	}
	if !slices.Equal(got.Replied, []string{inline}) || len(d.cityPosts("<!-- gc:answer "+q+" -->")) != 1 || !d.resolved("T1") {
		t.Fatalf("rule-and-repair's post replied to %v (%v made), the question has %d replies, T1 resolved %v",
			got.Replied, d.posts.made[made:], len(d.cityPosts("<!-- gc:answer "+q+" -->")), d.resolved("T1"))
	}

	v = d.verdict(t, 1)
	if !v.Passed {
		t.Fatalf("the round does not pass: %q", v.Reasons)
	}
	rec := d.record(t, v)
	var ids []string
	for _, c := range rec.Closed {
		ids = append(ids, c.ID)
	}
	slices.Sort(ids)
	want := []string{change, q, lgtm}
	slices.Sort(want)
	if !slices.Equal(ids, want) {
		t.Fatalf("the record closed %v; want every ask: %v", ids, want)
	}
}

// Triage's post in a round that bonds a lane answers the posts triage ruled
// and leaves the head's comment to rule-and-repair, which carries the lane's
// verdict and triage's answer once it posts.
func TestTriagesPostLeavesTheHeadsCommentToALanesRound(t *testing.T) {
	d := newRounds(t)
	url := d.person(pr.PostConversation)
	ask := d.ask(t, "Conversation comment", url, "2026-11-12T03:00:00Z")
	d.answers(t, 1, head, []string{"correctness"}, answered(ask, "Yes: five is the cap the design sets."))
	got := d.posted(t)
	if got.Comment != "" || !slices.Equal(got.Replied, []string{url}) {
		t.Fatalf("triage's post in a round with a lane made the head's comment %q, replied %v", got.Comment, got.Replied)
	}
	d.store.Put(fake.Bead{ID: "tk-run-lane-1", Status: "closed", Metadata: map[string]string{"gc.root_bead_id": "tk-run",
		"gc.output_json": `{"review":"lane","iteration":1,"check":"correctness","head":"` + head + `","verdict":"approve","findings":[]}`}})
	d.rule(t, 1, head, "")
	got = d.posted(t)
	comment := d.cityPosts(review.Mark("tk-run", head))
	if got.Comment != "posted" || len(comment) != 1 || !strings.Contains(comment[0], "correctness approved. The round answered 1.") {
		t.Fatalf("rule-and-repair's post made the head's comment %q: %q", got.Comment, comment)
	}
}

// A wordless answer of an inline comment puts the city's THUMBS_UP on it and resolves
// its thread with no reply. A wordless answer of a post made while a question
// it does not settle stands still gets the reply that says the question
// stands.
func TestAWordlessAnswerOwesWordsOnlyWhileAQuestionStands(t *testing.T) {
	d := newRounds(t)
	url := d.person(pr.PostInline)
	ask := d.ask(t, "Inline comment", url, "2026-11-12T03:00:00Z")
	d.answers(t, 1, head, nil, thumbsUp(ask, "A thank-you."))
	got := d.posted(t)
	if len(got.Replied) != 0 || !d.reacted("PRRC_260", "THUMBS_UP") || !d.resolved("T1") {
		t.Fatalf("a wordless answer in a thread replied %v, marked %v, resolved %v; want the THUMBS_UP and the resolve alone",
			got.Replied, d.reacted("PRRC_260", "THUMBS_UP"), d.resolved("T1"))
	}

	const title = "Is the cap the operator's to set?"
	d = newRounds(t)
	d.question(t, "tk-q1", "cap", title, "2026-11-12T03:00:00Z")
	url = d.person(pr.PostConversation)
	ask = d.ask(t, "Conversation comment", url, "2026-11-12T04:00:00Z")
	d.rule(t, 1, head, "", thumbsUp(ask, "A thank-you that settles nothing."))
	d.posted(t)
	replies := d.cityPosts("<!-- gc:answer " + ask + " -->")
	if len(replies) != 1 || !strings.Contains(replies[0], "The question at tk-q1, \""+title+"\", still stands") {
		t.Fatalf("a wordless answer made while a question stands got %q; want the reply that says it stands", replies)
	}
}
