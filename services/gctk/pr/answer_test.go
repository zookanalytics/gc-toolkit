package pr_test

import (
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	ghfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
)

// A review round's post (specs/tk-1tfzr71.161/design.md, sections 3 and 6),
// each case one of section 11's for unit 4, on the landing order's world: a
// review run attached to the bead, whose round the store holds, the posts it
// rules on the fake GitHub, each marked with the city's EYES as the take leaves
// it, and a writer of the city's posts that puts each post on the PR as GitHub
// shows it.

// posts is the writer of the city's posts as a test runs it: each post lands on
// the PR under the city's login, carrying the city's mark, and fail fails a
// verb (comment, edit or reply) with its error.
type posts struct {
	pr   *ghfake.PR
	fail map[string]error
	made []string
	next int64
}

func (p *posts) take(verb string) error {
	p.made = append(p.made, verb)
	return p.fail[verb]
}

func (p *posts) Comment(_, _ string, _ int, body string) error {
	if err := p.take("comment"); err != nil {
		return err
	}
	p.next++
	id := 9000 + p.next
	p.pr.Comments = append(slices.Clone(p.pr.Comments), gh.IssueComment{ID: id, NodeID: fmt.Sprintf("IC_%d", id),
		URL: fmt.Sprintf("%s#issuecomment-%d", prURL, id), Author: self, Body: body + "\n\n" + cityMark})
	return nil
}

func (p *posts) Edit(_, _ string, id int64, body string) error {
	if err := p.take("edit"); err != nil {
		return err
	}
	for i := range p.pr.Comments {
		if p.pr.Comments[i].ID == id {
			p.pr.Comments[i].Body = body + "\n\n" + cityMark
			return nil
		}
	}
	return errors.New("gh: Not Found (HTTP 404)")
}

func (p *posts) Reply(_, thread, body string) error {
	if err := p.take("reply"); err != nil {
		return err
	}
	for i := range p.pr.Threads {
		if p.pr.Threads[i].ID == thread {
			p.next++
			id := 9000 + p.next
			p.pr.Threads[i].Comments = append(slices.Clone(p.pr.Threads[i].Comments), gh.Comment{ID: id,
				NodeID: fmt.Sprintf("PRRC_%d", id), URL: fmt.Sprintf("%s#discussion_r%d", prURL, id), Author: self,
				Body: body + "\n\n" + cityMark})
			return nil
		}
	}
	return fmt.Errorf("github: no review thread %s", thread)
}

// rounds is the landing order's world with review run tk-run attached to the
// bead, whose first iteration triage judged at the head, and the writer of the
// city's posts.
type rounds struct {
	*land
	posts *posts
}

func newRounds(t *testing.T) *rounds {
	t.Helper()
	d := newCycle(t)
	p := &posts{pr: d.pr, fail: map[string]error{}}
	d.l.Posts = p
	d.store.Put(fake.Bead{ID: "tk-run", Title: "mol-pr-review", Status: "open", CreatedAt: "2026-11-12T02:00:00Z",
		Metadata: map[string]string{"gc.kind": "workflow", "gc.formula_name": "mol-pr-review", "gc.var.pr_bead": bead,
			"gc.var.head": head, "gc.var.target": "main", "gc.var.max_attempts": "3"}})
	d.edit(t, func(b *fake.Bead) {
		b.Edges = append(b.Edges, gcbd.Edge{Type: gcbd.EdgeBlocks, ID: "tk-run", Title: "mol-pr-review", Status: "open"})
	})
	r := &rounds{land: d, posts: p}
	r.triage(1, head)
	return r
}

// triage writes triage's output for iteration n, judging h.
func (d *rounds) triage(n int, h string) {
	d.store.Put(fake.Bead{ID: fmt.Sprintf("tk-run-triage-%d", n), Status: "closed", Metadata: map[string]string{
		"gc.root_bead_id": "tk-run",
		"gc.output_json":  fmt.Sprintf(`{"review":"triage","iteration":%d,"head":"%s","checks":[],"material":false}`, n, h)}})
}

// rule writes rule-and-repair's output for iteration n: its rulings, at the
// head triage judged there, and the head its push made.
func (d *rounds) rule(t *testing.T, n int, at, pushed string, rs ...review.Ruling) {
	t.Helper()
	raw, err := json.Marshal(review.Repair{Review: "repair", Iteration: n, Head: at, Rulings: rs, Pushed: pushed})
	if err != nil {
		t.Fatal(err)
	}
	d.store.Put(fake.Bead{ID: fmt.Sprintf("tk-run-repair-%d", n), Status: "closed",
		Metadata: map[string]string{"gc.root_bead_id": "tk-run", "gc.output_json": string(raw)}})
}

// ask files the ask the take files for the post at url, of the kind named, as
// filed at the instant given.
func (d *rounds) ask(t *testing.T, kind, url, filed string) string {
	t.Helper()
	id, ok, err := review.FileAsk(ledger.New(d.store), review.AskRequest{Bead: bead,
		Reason: fmt.Sprintf("%s by operator on PR #7: %s", kind, url)}, nil)
	if err != nil || !ok {
		t.Fatalf("the ask for %s did not file: %v", url, err)
	}
	b, _ := d.store.Row(id)
	b.CreatedAt = filed
	d.store.Put(b)
	return id
}

// question files an open human gate on the bead under a question's key, at the
// instant given, as review-run.sh question files it.
func (d *rounds) question(t *testing.T, id, slug, title, filed string) {
	t.Helper()
	d.store.Put(fake.Bead{ID: id, Title: title, Status: "open", IssueType: "gate", AwaitType: "human",
		AwaitID: review.QuestionKey + slug, CreatedAt: filed})
	d.edit(t, func(b *fake.Bead) {
		b.Edges = append(b.Edges, gcbd.Edge{Type: gcbd.EdgeBlocks, ID: id, Title: title, Status: "open", IssueType: "gate",
			AwaitType: "human"})
	})
}

// post runs the round's post over the run, at the latest iteration with
// rulings.
func (d *rounds) post(t *testing.T) (pr.Answered, error) {
	t.Helper()
	return d.l.AnswerRound("tk-run", 0)
}

// posted runs the round's post and fails unless it landed whole.
func (d *rounds) posted(t *testing.T) pr.Answered {
	t.Helper()
	got, err := d.post(t)
	if err != nil {
		t.Fatalf("the round's post: %v (%+v)", err, got)
	}
	return got
}

const (
	inlineURL = prURL + "#discussion_r260"
	reviewURL = prURL + "#pullrequestreview-200"
	convoURL  = prURL + "#issuecomment-5"
)

// person is one post of the operator's on the PR, of the kind named, which the
// take has marked with the city's EYES: inline comment 260 in thread T1, the
// message of review 200, or conversation comment 5.
func (d *rounds) person(kind string) string {
	taken := []string{"EYES"}
	switch kind {
	case pr.PostInline:
		d.pr.Threads = append(d.pr.Threads, gh.Thread{ID: "T1", Comments: []gh.Comment{{ID: 260, NodeID: "PRRC_260",
			URL: inlineURL, Author: "operator", Body: "rename this flag", ViewerReactions: taken,
			Review: &gh.CommentReview{ID: 199, State: "COMMENTED"}}}})
		return inlineURL
	case pr.PostReview:
		d.pr.Reviews = append(d.pr.Reviews, gh.Review{ID: 200, NodeID: "PRR_200", URL: reviewURL, State: "COMMENTED",
			Author: "operator", AuthorCanPush: true, Body: "the cap reads too low", SubmittedAt: "2026-11-12T02:00:00Z",
			ViewerReactions: taken})
		return reviewURL
	}
	d.pr.Comments = append(d.pr.Comments, gh.IssueComment{ID: 5, NodeID: "IC_5", URL: convoURL, Author: "operator",
		Body: "is the cap right?", ViewerReactions: taken})
	return convoURL
}

// cityPosts is each post of the city's on the PR that carries mark: the
// replies in each thread, then the conversation's comments.
func (d *rounds) cityPosts(mark string) []string {
	var out []string
	for _, th := range d.pr.Threads {
		for _, c := range th.Comments {
			if c.Author == self && strings.Contains(c.Body, mark) {
				out = append(out, c.Body)
			}
		}
	}
	for _, c := range d.pr.Comments {
		if c.Author == self && strings.Contains(c.Body, mark) {
			out = append(out, c.Body)
		}
	}
	return out
}

// reacted reports whether the post whose node id is node carries the city's
// reaction content.
func (d *rounds) reacted(node, content string) bool {
	for _, v := range d.pr.Reviews {
		if v.NodeID == node {
			return slices.Contains(v.ViewerReactions, content)
		}
	}
	for _, th := range d.pr.Threads {
		for _, c := range th.Comments {
			if c.NodeID == node {
				return slices.Contains(c.ViewerReactions, content)
			}
		}
	}
	for _, c := range d.pr.Comments {
		if c.NodeID == node {
			return slices.Contains(c.ViewerReactions, content)
		}
	}
	return false
}

func (d *rounds) resolved(thread string) bool {
	for _, th := range d.pr.Threads {
		if th.ID == thread {
			return th.Resolved
		}
	}
	return false
}

// Each ruling's answer by the kind of post: a reply in an inline comment's
// thread, which is then resolved, and for a review's message or a conversation
// comment a comment that links it where its ruling owes words, which a
// must-fix point's does not; the city's THUMBS_UP on each, but a question's,
// whose reply names its gate and whose thread stays open.
func TestEachRulingIsAnsweredWhereThePostWasMade(t *testing.T) {
	nodes := map[string]string{pr.PostInline: "PRRC_260", pr.PostReview: "PRR_200", pr.PostConversation: "IC_5"}
	called := map[string]string{pr.PostInline: "Inline comment", pr.PostReview: "Review", pr.PostConversation: "Conversation comment"}
	for _, kind := range []string{pr.PostInline, pr.PostReview, pr.PostConversation} {
		for _, ruling := range []string{review.RulingMustFix, review.RulingDeclined, review.RulingDeferred, review.RulingAnswered, review.RulingQuestion} {
			t.Run(kind+" "+ruling, func(t *testing.T) {
				d := newRounds(t)
				url := d.person(kind)
				ask := d.ask(t, called[kind], url, "2026-11-12T03:00:00Z")
				r := review.Ruling{Ask: ask, Ruling: ruling, Reason: "P2 at most, and the reason says why."}
				pushed := ""
				switch ruling {
				case review.RulingMustFix:
					r.Commit, pushed = later, later
				case review.RulingQuestion:
					r.Gate = "tk-q1"
				}
				d.rule(t, 1, head, pushed, r)
				got := d.posted(t)
				if got.Comment != "posted" {
					t.Fatalf("the head's comment was %q, want posted", got.Comment)
				}
				final := ruling != review.RulingQuestion
				mark := "<!-- gc:answer " + ask + " -->"
				if !final {
					mark = "<!-- gc:answer " + ask + " question tk-q1 -->"
				}
				replies := d.cityPosts(mark)
				owed := kind == pr.PostInline || ruling != review.RulingMustFix
				switch {
				case owed && len(replies) != 1:
					t.Fatalf("the post got %d replies naming its ask, want one: %q", len(replies), replies)
				case !owed && len(replies) != 0:
					t.Fatalf("a must-fix point on a post with no thread got words: %q", replies)
				}
				if owed {
					reply := replies[0]
					if kind != pr.PostInline && !strings.Contains(reply, "]("+url+"): ") {
						t.Fatalf("the reply to a post with no thread does not link it: %q", reply)
					}
					if want := r.Answer(pushed); !strings.Contains(reply, want) {
						t.Fatalf("the reply %q does not carry the ruling's answer %q", reply, want)
					}
					if !final && !strings.Contains(reply, "waits for your answer on the board") {
						t.Fatalf("a question's reply %q does not say it waits on the board", reply)
					}
				}
				if d.reacted(nodes[kind], "THUMBS_UP") != final {
					t.Fatalf("the post carries the city's THUMBS_UP: %v, want %v", !final, final)
				}
				if kind == pr.PostInline && d.resolved("T1") != final {
					t.Fatalf("the thread is resolved: %v, want %v", !final, final)
				}
			})
		}
	}
}

// A post run again posts nothing twice: the head's comment is kept as the PR
// holds it, each reply is found by the line that names its ask, each mark by
// the city's reaction and each resolve by the thread's state.
func TestAPostRunAgainPostsNothingTwice(t *testing.T) {
	d := newRounds(t)
	inline := d.person(pr.PostInline)
	convo := d.person(pr.PostConversation)
	a1 := d.ask(t, "Inline comment", inline, "2026-11-12T03:00:00Z")
	a2 := d.ask(t, "Conversation comment", convo, "2026-11-12T03:00:00Z")
	d.rule(t, 1, head, "", review.Ruling{Ask: a1, Ruling: review.RulingDeclined, Reason: "A nit."},
		review.Ruling{Ask: a2, Ruling: review.RulingAnswered, Reason: "Five is the cap the design sets."})
	d.posted(t)
	made, asks := len(d.posts.made), len(d.github.Asks())
	got := d.posted(t)
	if got.Comment != "kept" || len(d.posts.made) != made || len(d.github.Asks()) != asks {
		t.Fatalf("the post run again wrote %v posts and %v requests of GitHub, the head's comment %q",
			d.posts.made[made:], d.github.Asks()[asks:], got.Comment)
	}
	// A head's comment that changed since is edited, not posted again.
	d.rule(t, 1, head, "", review.Ruling{Ask: a1, Ruling: review.RulingDeclined, Reason: "A nit, and the name stands."},
		review.Ruling{Ask: a2, Ruling: review.RulingAnswered, Reason: "Five is the cap the design sets."})
	if got := d.posted(t); got.Comment != "edited" || !slices.Equal(d.posts.made[made:], []string{"edit"}) {
		t.Fatalf("a changed head's comment was %q, with posts %v", got.Comment, d.posts.made[made:])
	}
}

// An answer that does not land exits non-zero and leaves its ask open: no mark
// and no resolve stand without the reply, and the post run again makes them.
func TestAnAnswerThatDoesNotLandLeavesItsAskOpen(t *testing.T) {
	d := newRounds(t)
	url := d.person(pr.PostInline)
	ask := d.ask(t, "Inline comment", url, "2026-11-12T03:00:00Z")
	d.rule(t, 1, head, "", review.Ruling{Ask: ask, Ruling: review.RulingDeclined, Reason: "A nit."})
	d.posts.fail["reply"] = errors.New("pr-post.sh reply: exit 1: gh: error connecting to api.github.com")
	_, err := d.post(t)
	var unanswered *pr.Unanswered
	if !errors.As(err, &unanswered) {
		t.Fatalf("a reply that did not land returned %v, want an *Unanswered", err)
	}
	if row, _ := d.store.Row(ask); row.Status != "open" || d.reacted("PRRC_260", "THUMBS_UP") || d.resolved("T1") {
		t.Fatalf("after a reply that did not land, ask %s is %s, the post marked %v, the thread resolved %v",
			ask, row.Status, d.reacted("PRRC_260", "THUMBS_UP"), d.resolved("T1"))
	}
	delete(d.posts.fail, "reply")
	d.posted(t)
	if len(d.cityPosts("<!-- gc:answer "+ask+" -->")) != 1 || !d.reacted("PRRC_260", "THUMBS_UP") || !d.resolved("T1") {
		t.Fatal("the post run again did not make the reply, the mark and the resolve")
	}
}

// A must-fix point is answered once the round has pushed its fix, so a round
// that pushed nothing answers it nowhere.
func TestAMustFixPointIsAnsweredOnceItsFixIsOnThePR(t *testing.T) {
	d := newRounds(t)
	url := d.person(pr.PostInline)
	ask := d.ask(t, "Inline comment", url, "2026-11-12T03:00:00Z")
	d.rule(t, 1, head, "", review.Ruling{Ask: ask, Ruling: review.RulingMustFix, Reason: "P1.", Commit: later})
	got := d.posted(t)
	if len(d.cityPosts("gc:answer")) != 0 || d.reacted("PRRC_260", "THUMBS_UP") || len(got.Left) != 1 {
		t.Fatalf("a must-fix point whose fix the round did not push was answered: left %q", got.Left)
	}
}

// A thread holds more than the post the round ruled: it is resolved only once
// every post in it carries the city's THUMBS_UP, the city's own aside, so a
// person's later post the city has not answered keeps it open.
func TestAThreadStaysOpenWhileAPostInItIsOwed(t *testing.T) {
	d := newRounds(t)
	url := d.person(pr.PostInline)
	d.pr.Threads[0].Comments = append(d.pr.Threads[0].Comments, gh.Comment{ID: 263, NodeID: "PRRC_263",
		URL: prURL + "#discussion_r263", Author: "operator", Body: "and one more thing"})
	ask := d.ask(t, "Inline comment", url, "2026-11-12T03:00:00Z")
	d.rule(t, 1, head, "", review.Ruling{Ask: ask, Ruling: review.RulingDeclined, Reason: "A nit."})
	d.posted(t)
	if !d.reacted("PRRC_260", "THUMBS_UP") || d.resolved("T1") {
		t.Fatalf("the ruled post is marked %v and the thread with an unanswered post resolved %v",
			d.reacted("PRRC_260", "THUMBS_UP"), d.resolved("T1"))
	}
}

// A person's request for changes is dismissed once its last point is answered
// on the PR, and not before, with its author asked to review again first and a
// one-line note that counts what became of the points.
func TestARequestForChangesIsDismissedOnceItsLastPointIsAnswered(t *testing.T) {
	d := newRounds(t)
	const cr = prURL + "#pullrequestreview-210"
	d.pr.Reviews = append(d.pr.Reviews, gh.Review{ID: 210, NodeID: "PRR_210", URL: cr, State: "CHANGES_REQUESTED",
		Author: "operator", AuthorCanPush: true, Body: "two things", SubmittedAt: "2026-11-12T02:00:00Z",
		ViewerReactions: []string{"EYES"}})
	point := func(thread string, id int64) string {
		u := fmt.Sprintf("%s#discussion_r%d", prURL, id)
		d.pr.Threads = append(d.pr.Threads, gh.Thread{ID: thread, Comments: []gh.Comment{{ID: id,
			NodeID: fmt.Sprintf("PRRC_%d", id), URL: u, Author: "operator", Body: "fix this",
			ViewerReactions: []string{"EYES"}, Review: &gh.CommentReview{ID: 210, State: "CHANGES_REQUESTED"}}}})
		return u
	}
	p1, p2 := point("T2", 261), point("T3", 262)
	message := d.ask(t, "Request for changes", cr, "2026-11-12T03:00:00Z")
	a1 := d.ask(t, "Inline comment", p1, "2026-11-12T03:00:00Z")
	a2 := d.ask(t, "Inline comment", p2, "2026-11-12T03:00:00Z")
	d.question(t, "tk-q2", "naming", "Which name does the flag take?", "2026-11-12T03:30:00Z")
	d.rule(t, 1, head, later,
		review.Ruling{Ask: message, Ruling: review.RulingDeclined, Reason: "The two things are the inline points."},
		review.Ruling{Ask: a1, Ruling: review.RulingMustFix, Reason: "P1.", Commit: later},
		review.Ruling{Ask: a2, Ruling: review.RulingQuestion, Reason: "Which name?", Gate: "tk-q2"})
	got := d.posted(t)
	if len(got.Dismissed)+len(got.Requested) != 0 || slices.ContainsFunc(d.github.Asks(), func(a ghfake.Ask) bool {
		return a.Method == "DismissReview" || a.Method == "RequestReview"
	}) {
		t.Fatalf("a request for changes with a point still put to a person was dismissed: %+v", got)
	}

	// The question is answered on the board, and the next round rules its
	// point, which answers the last point.
	g, _ := d.store.Row("tk-q2")
	g.Status, g.CloseReason = "closed", "ruled: keep the name"
	d.store.Put(g)
	d.triage(2, later)
	d.rule(t, 2, later, "",
		review.Ruling{Ask: message, Ruling: review.RulingAnswered, Reason: "Answered at the first head."},
		review.Ruling{Ask: a1, Ruling: review.RulingAnswered, Reason: "The head carries its fix."},
		review.Ruling{Ask: a2, Ruling: review.RulingDeclined, Reason: "The operator ruled the name stays."})
	got = d.posted(t)
	if !slices.Equal(got.Dismissed, []string{cr}) || !slices.Equal(got.Requested, []string{"operator"}) {
		t.Fatalf("the request for changes whose last point is answered: dismissed %v, asked %v", got.Dismissed, got.Requested)
	}
	var order []string
	note := ""
	for _, a := range d.github.Asks() {
		if a.Method == "RequestReview" || a.Method == "DismissReview" {
			order = append(order, a.Method)
		}
		if a.Method == "DismissReview" {
			note = a.Message
		}
	}
	if !slices.Equal(order, []string{"RequestReview", "DismissReview"}) {
		t.Fatalf("the requests were %v, want the review asked again before the dismissal", order)
	}
	if want := "Every point of this request for changes has its answer beside it on the PR: 1 fixed, 2 declined.\n\n" + cityMark; note != want {
		t.Fatalf("the dismissal's note reads %q, want %q", note, want)
	}
	if d.pr.Reviews[1].State != "DISMISSED" || !slices.Contains(d.pr.Requested, "operator") {
		t.Fatalf("the review reads %s and the requested reviewers %v", d.pr.Reviews[1].State, d.pr.Requested)
	}
	// Run again, the dismissed review asks for nothing more.
	asks := len(d.github.Asks())
	if got := d.posted(t); len(got.Dismissed)+len(got.Requested) != 0 || len(d.github.Asks()) != asks {
		t.Fatalf("the post run again dismissed %v and asked %v", got.Dismissed, d.github.Asks()[asks:])
	}
}

// A review request GitHub refuses, as for an account that cannot review the
// repository, leaves the dismissal to go on, and one that is not answered
// holds it for the post run again.
func TestARefusedReviewRequestStillDismissesTheRequestForChanges(t *testing.T) {
	setup := func(t *testing.T) *rounds {
		d := newRounds(t)
		const cr = prURL + "#pullrequestreview-210"
		d.pr.Reviews = append(d.pr.Reviews, gh.Review{ID: 210, NodeID: "PRR_210", URL: cr, State: "CHANGES_REQUESTED",
			Author: "visitor", Body: "rename it", SubmittedAt: "2026-11-12T02:00:00Z", ViewerReactions: []string{"EYES"}})
		ask := d.ask(t, "Request for changes", cr, "2026-11-12T03:00:00Z")
		d.rule(t, 1, head, "", review.Ruling{Ask: ask, Ruling: review.RulingDeclined, Reason: "The name stands."})
		return d
	}
	d := setup(t)
	d.github.Fail["RequestReview"] = errors.New("gh: Reviews may only be requested from collaborators. (HTTP 422)")
	got := d.posted(t)
	if len(got.Dismissed) != 1 || len(got.Requested) != 0 || len(got.Left) != 1 {
		t.Fatalf("after a refused review request: dismissed %v, asked %v, left %q", got.Dismissed, got.Requested, got.Left)
	}
	e := setup(t)
	e.github.Fail["RequestReview"] = errors.New("gh: error connecting to api.github.com")
	if _, err := e.post(t); err == nil || slices.ContainsFunc(e.github.Asks(), func(a ghfake.Ask) bool { return a.Method == "DismissReview" }) {
		t.Fatalf("a review request with no answer returned %v and dismissed the review", err)
	}
}

// A comment made while a question is open settles it: the post closes the
// question's gate with the comment's words and its URL as its answer, headed
// ruled:, or moot: for a comment that makes it moot, and its reply says so. A
// comment that settles nothing leaves the gate open, and its reply says the
// question still stands and waits on the board.
func TestACommentMadeWhileAQuestionIsOpenCanSettleIt(t *testing.T) {
	const title = "Is the cap the operator's to set?"
	for _, moot := range []bool{false, true} {
		d := newRounds(t)
		d.question(t, "tk-q1", "cap", title, "2026-11-12T03:00:00Z")
		url := d.person(pr.PostConversation)
		ask := d.ask(t, "Conversation comment", url, "2026-11-12T04:00:00Z")
		d.rule(t, 1, head, "", review.Ruling{Ask: ask, Ruling: review.RulingAnswered, Reason: "It answers the question.",
			Settles: "tk-q1", Moot: moot})
		got := d.posted(t)
		head, phrase := "ruled: ", "settles the question at tk-q1"
		if moot {
			head, phrase = "moot: ", "makes the question at tk-q1"
		}
		gate, _ := d.store.Row("tk-q1")
		if !slices.Equal(got.Settled, []string{"tk-q1"}) || gate.Status != "closed" ||
			gate.CloseReason != head+"is the cap right? ("+url+")" {
			t.Fatalf("the settling comment closed %v, the gate %s with %q", got.Settled, gate.Status, gate.CloseReason)
		}
		replies := d.cityPosts("<!-- gc:answer " + ask + " -->")
		if len(replies) != 1 || !strings.Contains(replies[0], phrase) || !strings.Contains(replies[0], title) {
			t.Fatalf("the settling comment's reply %q does not say it %s, naming the question", replies, phrase)
		}
	}

	d := newRounds(t)
	d.question(t, "tk-q1", "cap", title, "2026-11-12T03:00:00Z")
	url := d.person(pr.PostConversation)
	ask := d.ask(t, "Conversation comment", url, "2026-11-12T04:00:00Z")
	d.rule(t, 1, head, "", review.Ruling{Ask: ask, Ruling: review.RulingAnswered, Reason: "A question about the code."})
	got := d.posted(t)
	gate, _ := d.store.Row("tk-q1")
	replies := d.cityPosts("<!-- gc:answer " + ask + " -->")
	if len(got.Settled) != 0 || gate.Status != "open" || len(replies) != 1 ||
		!strings.Contains(replies[0], "The question at tk-q1, \""+title+"\", still stands and waits for your answer on the board.") {
		t.Fatalf("a comment that settles nothing closed %v, left the gate %s, and got the replies %q", got.Settled, gate.Status, replies)
	}
}

// A ruling that settles a question whose gate does not close is not answered,
// since its reply would say the gate closed: the post returns non-zero, and
// the post run again closes the gate and replies.
func TestASettlingCommentWhoseGateDidNotCloseIsAnsweredOnceItCloses(t *testing.T) {
	d := newRounds(t)
	d.question(t, "tk-q1", "cap", "Is the cap the operator's to set?", "2026-11-12T03:00:00Z")
	url := d.person(pr.PostConversation)
	ask := d.ask(t, "Conversation comment", url, "2026-11-12T04:00:00Z")
	d.rule(t, 1, head, "", review.Ruling{Ask: ask, Ruling: review.RulingAnswered, Reason: "It answers it.", Settles: "tk-q1"})
	d.store.ResolveErr = errors.New("bd: the store did not take the write")
	if _, err := d.post(t); err == nil || len(d.cityPosts("<!-- gc:answer "+ask+" -->")) != 0 || d.reacted("IC_5", "THUMBS_UP") {
		t.Fatalf("a gate that did not close returned %v and the comment was answered", err)
	}
	d.store.ResolveErr = nil
	d.posted(t)
	if len(d.cityPosts("<!-- gc:answer "+ask+" -->")) != 1 || !d.reacted("IC_5", "THUMBS_UP") {
		t.Fatal("the post run again did not answer the comment once its gate closed")
	}
}
