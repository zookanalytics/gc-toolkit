package pr

import (
	"context"
	"errors"
	"fmt"
	"maps"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
	"github.com/zookanalytics/gc-toolkit/services/gctk/standing/person"
)

// A review round's post (specs/tk-1tfzr71.161/design.md, sections 3 and 6).
// The step that rules a person's post answers it where it was made, since it
// knows what became of the post, and the loop's check, which records the run's
// result, has no GitHub login. That step is triage for a post it answers, and
// rule-and-repair for the rest of the round. The post makes each write the
// round owes on GitHub, in this order:
//
//   - the head's one comment (review.Comment), posted, or edited where its mark
//     finds it, once the round has ruled all it will: rule-and-repair wrote
//     its rulings, or triage left it nothing (review.Run.Left). Triage's post
//     before then answers the posts triage ruled and leaves the comment to
//     rule-and-repair's;
//   - the gate of each question that a person's post settles or makes moot,
//     which the post's ruling names in settles, closed with the post's words
//     and its URL as the answer, headed ruled: or moot:;
//   - a reply to each post that an ask the round ruled carries: in an inline
//     comment's thread, and for a post with no thread a comment that links it,
//     where the ruling owes words. A must-fix point on a post with no thread
//     owes none, since the head's comment names its commit, and a wordless
//     answer owes none on any post, unless the post settles a question or was
//     made while one it does not settle was open. A must-fix point is answered
//     once the round has pushed its fix;
//   - the city's handled mark on each such post once its words are on the PR,
//     but on a post put to a person, which waits for the answer;
//   - the resolve of each thread such a post sits in, once nothing in it is
//     owed: every post in it that the definition of feedback reads as feedback
//     carries the handled mark;
//   - the dismissal of each person's standing request for changes once every
//     point it raised that the definition reads as feedback carries the
//     handled mark, after the review request that asks its author to review
//     again.
//
// A reply opens with a line naming its ask (answerMark), a handled mark is
// found by the city's own reaction, a resolve by the thread's state and a
// dismissal by the review's, so the post run again posts nothing twice. Each
// write is decided on the post's own read of the PR, which it reads again once
// a reply lands, so a mark and a resolve stand behind a reply that read shows.
// A write that does not land, or a reply that read does not show, leaves what
// it was for to the post run again (Unanswered), and a request GitHub refuses,
// which a run again would meet again, is left with why.

// Answered is what a round's post did: the head's comment, "posted", "edited",
// "kept" when the PR holds it as it stands, or "" when the round has nothing to
// answer, each gate it closed, each post it replied to and marked handled, each
// thread it resolved by the post the round ruled there, each author it asked to
// review again and each request for changes it dismissed, and each post or
// write it left, with why.
type Answered struct {
	Run, Bead, URL                                           string
	Iteration                                                int
	Comment                                                  string
	Settled, Replied, Marked, Resolved, Requested, Dismissed []string
	Left                                                     []string
}

// AnswerRefusal is a round's post the run's state refused, with why: the
// iteration has no rulings yet, or the bead that owns the PR names no PR.
// Nothing was posted.
type AnswerRefusal struct{ Run, Why string }

func (e *AnswerRefusal) Error() string { return e.Run + ": nothing posted: " + e.Why }

// Unanswered is a round's post whose writes did not all land: each that did
// not, by what it was for. What landed stands, and the post run again makes
// the rest.
type Unanswered struct{ Failed []string }

func (e *Unanswered) Error() string {
	return "not every answer landed, and the post run again makes the rest: " + strings.Join(e.Failed, "; ")
}

// AnswerRound posts the round of iteration n of the review run id names, its
// root or any bead poured under it, and with n 0 the round of the latest
// iteration whose round wrote its rulings, triage's answers among them. The PR
// is the one the bead that owns it names, and it must be in the rig's own
// repository. A read that fails returns its error, and a write that does not
// land an *Unanswered.
func (l Landing) AnswerRound(id string, n int) (Answered, error) {
	run, err := review.ReadRun(l.Ledger, id)
	if err != nil {
		return Answered{}, err
	}
	if n == 0 {
		for m, it := range run.Iterations {
			if it.Ruled() && m > n {
				n = m
			}
		}
	}
	out := Answered{Run: run.Root, Bead: run.PRBead, Iteration: n}
	it := run.Iterations[n]
	if n == 0 || it == nil || it.Triage == nil || !it.Ruled() {
		return out, &AnswerRefusal{Run: run.Root, Why: fmt.Sprintf("iteration %d has no rulings yet", n)}
	}
	owner, err := l.read(run.PRBead)
	if err != nil {
		return out, err
	}
	if owner == nil {
		return out, &AnswerRefusal{Run: run.Root, Why: "the store holds no bead " + run.PRBead}
	}
	rec, err := record.Read(owner)
	if err != nil {
		return out, err
	}
	out.URL = firstOf(rec.URL, rec.ExistingPR)
	host, repo, number, ok := record.ParseURL(out.URL)
	if !ok {
		return out, &AnswerRefusal{Run: run.Root, Why: fmt.Sprintf("%s names no PR's URL (it reads %q)", run.PRBead, out.URL)}
	}
	asks, err := review.AsksOn(l.Ledger, run.PRBead)
	if err != nil {
		return out, err
	}
	body := review.Comment(run, n, asks)
	if body == "" {
		return out, nil
	}
	if err := l.sameOrigin(host, repo); err != nil {
		return out, err
	}
	if l.Posts == nil {
		return out, errors.New("nothing posts the city's posts here, so nothing is answered")
	}
	a := &answering{l: l, hub: l.Hub(context.Background(), host), host: host, repo: repo, number: number,
		run: run, rulings: it.Rulings(), pushed: it.Pushed(), owner: owner, asks: asks, url: out.URL, out: &out,
		marked: map[string]bool{}}
	if err := a.read(); err != nil {
		return out, err
	}
	if it.Repair != nil || len(run.Left(n, asks)) == 0 {
		a.comment(body, review.Mark(run.Root, it.Triage.Head))
	}
	if err := a.answer(); err != nil {
		return out, err
	}
	if len(a.failed) > 0 {
		return out, &Unanswered{Failed: a.failed}
	}
	return out, nil
}

// answering is one round's post as it goes: the PR, the account the city's gh
// token acts as, the definition of feedback, the round's rulings and the head
// it pushed, the bead that owns the PR with its asks and the beads it waits on,
// the post's read of the PR, the reviews and the posts in that read's review
// threads that the definition of feedback reads as feedback and the posts this
// post marked handled, each by node id, the questions on the bead, and each
// write that did not land.
type answering struct {
	l          Landing
	hub        Hub
	host, repo string
	number     int
	self       string
	rule       Feedback
	run        *review.Run
	rulings    []review.Ruling
	pushed     string
	owner      *ledger.Record
	asks       []review.Ask
	url        string
	reviews    []gh.Review
	threads    []gh.Thread
	comments   []gh.IssueComment
	owed       map[string]bool
	blockers   []*ledger.Record
	questions  map[string]*question
	byAsk      map[string][]review.Ruling
	marked     map[string]bool
	out        *Answered
	failed     []string
}

// question is a gate on the bead that owns the PR through which a review run
// put a question to a person: its id, its title, when it was filed, whether it
// is closed and the answer it closed with.
type question struct {
	id, title, filed, reason string
	closed                   bool
}

func (a *answering) fail(format string, args ...any) {
	a.failed = append(a.failed, fmt.Sprintf(format, args...))
}

func (a *answering) leave(format string, args ...any) {
	a.out.Left = append(a.out.Left, fmt.Sprintf(format, args...))
}

// read reads the account the city acts as, the definition of feedback and the
// PR's reviews, review threads and conversation comments.
func (a *answering) read() error {
	self, err := a.hub.Login()
	if err != nil {
		return err
	}
	a.self = self
	if a.l.Feedback == nil {
		return errors.New("nothing applies the definition of feedback here, so no thread can be resolved")
	}
	if a.rule, err = a.l.Feedback(); err != nil {
		return err
	}
	if a.reviews, err = a.hub.Reviews(a.repo, a.number); err != nil {
		return err
	}
	return a.reread()
}

// reread reads the PR's review threads and conversation comments again, which
// a reply changes, and which reviews and posts in the threads the definition
// of feedback reads, from the bead's provenance instant, as feedback, whatever
// marks of the city's they carry: the posts the city owes an answer.
func (a *answering) reread() error {
	var err error
	if a.threads, err = a.hub.ReviewThreads(a.repo, a.number); err != nil {
		return err
	}
	if a.comments, err = a.hub.IssueComments(a.repo, a.number); err != nil {
		return err
	}
	since, _, err := provenanceKey.Get(a.owner)
	if err != nil {
		return err
	}
	// The definition reads a post as untaken when it is feedback and carries
	// neither of the city's marks, so over the posts with their reactions set
	// aside it names each post that is feedback.
	reviews := make([]gh.Review, 0, len(a.reviews))
	for _, v := range a.reviews {
		v.ViewerReactions = nil
		reviews = append(reviews, v)
	}
	threads := make([]gh.Thread, 0, len(a.threads))
	for _, t := range a.threads {
		cs := make([]gh.Comment, 0, len(t.Comments))
		for _, c := range t.Comments {
			c.ViewerReactions = nil
			cs = append(cs, c)
		}
		t.Comments = cs
		threads = append(threads, t)
	}
	posts, err := untakenOf(a.rule, a.self, strings.TrimSpace(since), reviews, threads, nil)
	if err != nil {
		return err
	}
	a.owed = map[string]bool{}
	for _, p := range posts {
		a.owed[p.Node] = true
	}
	return nil
}

// comment posts the head's comment, or edits the city's comment its mark
// finds, which it leaves as it is when it holds the comment already.
func (a *answering) comment(body, mark string) {
	for _, c := range a.comments {
		if c.Author == a.self && strings.Contains(c.Body, mark) {
			if a.holds(c.Body, body) {
				a.out.Comment = "kept"
				return
			}
			if err := a.l.Posts.Edit(a.host, a.repo, c.ID, body); err != nil {
				a.fail("the edit of the head's comment %d did not land: %v", c.ID, err)
				return
			}
			a.out.Comment = "edited"
			return
		}
	}
	if err := a.l.Posts.Comment(a.host, a.repo, a.number, body); err != nil {
		a.fail("the head's comment did not post: %v", err)
		return
	}
	a.out.Comment = "posted"
}

// holds reports whether posted, a comment the city posted, is body as the
// writer of the city's posts posts it, with the city's mark after it. A mark
// that does not read holds nothing, so the comment is edited.
func (a *answering) holds(posted, body string) bool {
	if a.l.Mark == nil {
		return false
	}
	mark, err := a.l.Mark()
	if mark = strings.TrimSpace(mark); err != nil || mark == "" {
		return false
	}
	posted = strings.TrimSpace(strings.ReplaceAll(posted, "\r\n", "\n"))
	posted, ok := strings.CutSuffix(posted, mark)
	return ok && strings.TrimSpace(posted) == strings.TrimSpace(body)
}

// due is what the round's post owes one post that an ask it ruled carries: the
// ruling, the post's URL, the reply it is owed, "" for none, with the line that
// opens that reply, and whether the ruling leaves the post owed nothing more
// once its words are on the PR.
type due struct {
	r     review.Ruling
	url   string
	mark  string
	words string
	final bool
}

// answer settles the questions the round's posts settle, then answers each
// post the round ruled, marks it handled, resolves its thread, and dismisses
// each request for changes whose points are all answered.
func (a *answering) answer() error {
	if err := a.readQuestions(); err != nil {
		return err
	}
	a.settle()
	var dues []due
	for _, r := range a.rulings {
		if d, ok := a.due(r); ok {
			dues = append(dues, d)
		}
	}
	posted := false
	for _, d := range dues {
		if d.words == "" {
			continue
		}
		p, ok := a.locate(d.url)
		if !ok || a.replied(d, p) {
			continue
		}
		var err error
		if p.thread >= 0 {
			err = a.l.Posts.Reply(a.host, a.threads[p.thread].ID, d.words)
		} else {
			err = a.l.Posts.Comment(a.host, a.repo, a.number, d.words)
		}
		if err != nil {
			a.fail("the reply to %s (%s) did not land: %v", d.url, d.r.Ask, err)
			continue
		}
		a.out.Replied = append(a.out.Replied, d.url)
		posted = true
	}
	if posted {
		if err := a.reread(); err != nil {
			return err
		}
	}
	threads := map[int]string{}
	for _, d := range dues {
		if !d.final {
			continue
		}
		p, ok := a.locate(d.url)
		if !ok {
			continue
		}
		if d.words != "" && !a.replied(d, p) {
			// The post returns non-zero for a reply it made that its read
			// does not show, so it runs again and marks the post once the
			// read finds the reply. Its ask closes once the step does, and
			// no later round would mark the post.
			if slices.Contains(a.out.Replied, d.url) {
				a.fail("the reply to %s (%s) landed, and the PR's read does not show it, so the post is not marked answered", d.url, d.r.Ask)
			}
			continue
		}
		if p.thread >= 0 {
			if _, seen := threads[p.thread]; !seen {
				threads[p.thread] = d.url
			}
		}
		if a.handled(p.node, p.reacted) {
			continue
		}
		if err := a.hub.AddReaction(p.node, handledMark); err != nil {
			a.fail("the city's %s did not land on %s: %v", handledMark, d.url, err)
			continue
		}
		a.marked[p.node] = true
		a.out.Marked = append(a.out.Marked, d.url)
	}
	for _, i := range slices.Sorted(maps.Keys(threads)) {
		a.resolve(i, threads[i])
	}
	return a.dismiss()
}

// due is what the round's post owes the post the ask r rules carries, and
// false when it owes it nothing here: r rules a lane's finding, or an ask that
// carries no person's post, which the head's comment answers, or the post is
// gone, its fix is not on the PR, or the question it settles did not close.
func (a *answering) due(r review.Ruling) (due, bool) {
	if r.Ask == "" {
		return due{}, false
	}
	i := slices.IndexFunc(a.asks, func(x review.Ask) bool { return x.ID == r.Ask })
	if i < 0 {
		a.leave("%s: the bead holds the ask no longer, so its post is not answered here", r.Ask)
		return due{}, false
	}
	ask := a.asks[i]
	url := PostNamed(ask.Reason, a.url)
	if url == "" {
		return due{}, false
	}
	p, ok := a.locate(url)
	switch {
	case !ok:
		a.leave("%s: GitHub holds the post %s no longer", r.Ask, url)
		return due{}, false
	case r.Ruling == review.RulingMustFix && a.pushed == "":
		a.leave("%s: %s is ruled must-fix, and the round pushed nothing, so its fix is not on the PR", r.Ask, url)
		return due{}, false
	}
	var settled *question
	if r.Settles != "" {
		if settled = a.questions[r.Settles]; settled == nil || !settled.closed {
			return due{}, false
		}
	}
	d := due{r: r, url: url, final: r.Ruling != review.RulingQuestion, mark: answerMark(r)}
	var standing []*question
	if d.final {
		for _, id := range slices.Sorted(maps.Keys(a.questions)) {
			if q := a.questions[id]; !q.closed && id != r.Settles && before(q.filed, ask.Filed) {
				standing = append(standing, q)
			}
		}
	}
	if (r.Wordless || (p.thread < 0 && r.Ruling == review.RulingMustFix)) && settled == nil && len(standing) == 0 {
		return d, true
	}
	var parts []string
	if settled != nil {
		parts = append(parts, settledSentence(r, settled, url))
	}
	ans := review.Punctuated(r.Answer(a.pushed))
	if r.Ruling == review.RulingQuestion {
		if p.thread >= 0 {
			ans += " It waits for your answer on the board, and this thread stays open until the question is settled."
		} else {
			ans += " It waits for your answer on the board, and the run answers here once it is settled."
		}
	}
	parts = append(parts, ans)
	for _, q := range standing {
		parts = append(parts, fmt.Sprintf("The question at %s, %q, still stands and waits for your answer on the board.", q.id, q.title))
	}
	text := strings.Join(parts, " ")
	if p.thread < 0 {
		text = fmt.Sprintf("On [%s](%s): %s", p.called(), url, text)
	}
	d.words = d.mark + "\n" + text
	return d, true
}

// settledSentence says what the post at url did to the question q: settled it,
// or with r's moot made it moot, with the gate closed on the post's words, or,
// for a gate a person closed first with an answer of their own, that it was
// settled on the board already.
func settledSentence(r review.Ruling, q *question, url string) string {
	if !strings.Contains(q.reason, url) {
		return fmt.Sprintf("The question at %s, %q, was settled on the board already: %s.", q.id, q.title,
			strings.TrimRight(firstLine(q.reason), "."))
	}
	if r.Moot {
		return fmt.Sprintf("This makes the question at %s, %q, moot, so its gate is closed with this comment as its reason.", q.id, q.title)
	}
	return fmt.Sprintf("This settles the question at %s, %q, so its gate is closed with this comment as its answer.", q.id, q.title)
}

// answerMark is the line that opens the city's reply to a post the round
// ruled, naming the post's ask: its answer, or for a question the reply that
// names the gate, which a later answer follows once the question is settled.
func answerMark(r review.Ruling) string {
	if r.Ruling == review.RulingQuestion {
		return fmt.Sprintf("<!-- gc:answer %s question %s -->", r.Ask, r.Gate)
	}
	return fmt.Sprintf("<!-- gc:answer %s -->", r.Ask)
}

// spot is a post on the PR as the round's post read it: its kind, its id and
// node id, its author, text and URL, a review's state, the reactions the
// city's account left on it, and the thread an inline comment sits in, by its
// index among the threads read, -1 for a post with no thread.
type spot struct {
	kind, node, author, body, url, state string
	id                                   int64
	reacted                              []string
	thread                               int
}

// called is a post with no thread as the reply that links it names it.
func (p spot) called() string {
	who := p.author
	if who == "" {
		who = "an account GitHub no longer names"
	}
	switch {
	case p.kind == PostReview && p.state == "CHANGES_REQUESTED":
		return "the request for changes by " + who
	case p.kind == PostReview && p.state == "APPROVED":
		return "the approval by " + who
	case p.kind == PostReview:
		return "the review by " + who
	}
	return "the comment by " + who
}

// locate finds the post url names in the post's read of the PR, by its kind
// and its id.
func (a *answering) locate(url string) (spot, bool) {
	_, frag, _ := strings.Cut(url, "#")
	m := postFragment.FindStringSubmatch(frag)
	if m == nil {
		return spot{}, false
	}
	id, err := strconv.ParseInt(m[2], 10, 64)
	if err != nil {
		return spot{}, false
	}
	switch m[1] {
	case "pullrequestreview-":
		for _, v := range a.reviews {
			if v.ID == id {
				return spot{kind: PostReview, id: id, node: v.NodeID, author: v.Author, body: v.Body, url: url,
					state: v.State, reacted: v.ViewerReactions, thread: -1}, true
			}
		}
	case "discussion_r":
		for i, t := range a.threads {
			for _, c := range t.Comments {
				if c.ID == id {
					return spot{kind: PostInline, id: id, node: c.NodeID, author: c.Author, body: c.Body, url: url,
						reacted: c.ViewerReactions, thread: i}, true
				}
			}
		}
	default:
		for _, c := range a.comments {
			if c.ID == id {
				return spot{kind: PostConversation, id: id, node: c.NodeID, author: c.Author, body: c.Body, url: url,
					reacted: c.ViewerReactions, thread: -1}, true
			}
		}
	}
	return spot{}, false
}

// replied reports whether the PR holds the city's reply d owes p: in p's
// thread, or on the conversation for a post with no thread, a post of the
// city's that carries d's mark.
func (a *answering) replied(d due, p spot) bool {
	if p.thread >= 0 {
		return slices.ContainsFunc(a.threads[p.thread].Comments, func(c gh.Comment) bool {
			return c.Author == a.self && strings.Contains(c.Body, d.mark)
		})
	}
	return slices.ContainsFunc(a.comments, func(c gh.IssueComment) bool {
		return c.Author == a.self && strings.Contains(c.Body, d.mark)
	})
}

// handled reports whether the post whose node id is node, with the reactions
// the city's account left on it, carries the city's handled mark, the one
// this post left included.
func (a *answering) handled(node string, reacted []string) bool {
	return a.marked[node] || slices.Contains(reacted, handledMark)
}

// resolve resolves thread i, which holds the post at url the round answered,
// once nothing in it is owed: each post in it that the definition of feedback
// reads as feedback, whoever's login made it, carries the handled mark. A post
// the definition sets aside, such as the city's own, one not for review or one
// a dismissal retired, owes nothing. A post the city has not taken, a
// question's post and a post the city took and has not answered keep it open.
func (a *answering) resolve(i int, url string) {
	t := a.threads[i]
	if t.Resolved {
		return
	}
	for _, c := range t.Comments {
		if a.owed[c.NodeID] && !a.handled(c.NodeID, c.ViewerReactions) {
			return
		}
	}
	if err := a.hub.ResolveThread(t.ID); err != nil {
		a.fail("the thread of %s did not resolve: %v", url, err)
		return
	}
	a.out.Resolved = append(a.out.Resolved, url)
}

// readQuestions reads the beads the bead that owns the PR waits on, and among
// them each gate of a question a review run put to a person.
func (a *answering) readQuestions() error {
	edges, err := a.owner.Edges()
	if err != nil {
		return &ledger.ReadError{ID: a.owner.ID, Reason: "its edges did not decode: " + err.Error()}
	}
	var ids []string
	for _, e := range edges {
		if e.Type == ledger.EdgeBlocks && !slices.Contains(ids, e.ID) {
			ids = append(ids, e.ID)
		}
	}
	a.questions = map[string]*question{}
	if len(ids) == 0 {
		return nil
	}
	if a.blockers, err = a.l.Ledger.Find(ledger.ByID(ids...).WithClosed()); err != nil {
		return err
	}
	for _, b := range a.blockers {
		if person.IsHumanGate(b.IssueType(), b.AwaitType()) && strings.HasPrefix(b.AwaitID(), review.QuestionKey) {
			a.questions[b.ID] = &question{id: b.ID, title: b.Title(), filed: b.CreatedAt(), reason: b.CloseReason(),
				closed: b.Status() == "closed"}
		}
	}
	return nil
}

// settle closes the gate of each question a post the round ruled settles, or
// makes moot, with the post's words and its URL as the answer, headed ruled:
// or moot:. A gate closed already is left with the answer it has.
func (a *answering) settle() {
	for _, r := range a.rulings {
		if r.Settles == "" || r.Ask == "" {
			continue
		}
		q := a.questions[r.Settles]
		if q == nil {
			a.leave("%s: %s is no question a review run put to a person on %s, so it is not closed", r.Ask, r.Settles, a.owner.ID)
			continue
		}
		if q.closed {
			continue
		}
		i := slices.IndexFunc(a.asks, func(x review.Ask) bool { return x.ID == r.Ask })
		url := ""
		if i >= 0 {
			url = PostNamed(a.asks[i].Reason, a.url)
		}
		if url == "" {
			a.leave("%s carries no person's post, so it settles no question, and %s stays open", r.Ask, q.id)
			continue
		}
		words := strings.Join(strings.Fields(r.Reason), " ")
		if p, ok := a.locate(url); ok && strings.TrimSpace(p.body) != "" {
			words = strings.Join(strings.Fields(p.body), " ")
		}
		head := "ruled: "
		if r.Moot {
			head = "moot: "
		}
		reason := fmt.Sprintf("%s%s (%s)", head, words, url)
		if err := a.l.Ledger.ResolveGate(q.id, reason); err != nil {
			a.fail("the gate %s, which %s settles, did not close: %v", q.id, url, err)
			continue
		}
		q.closed, q.reason = true, reason
		a.out.Settled = append(a.out.Settled, q.id)
	}
}

// dismiss dismisses each person's standing request for changes once every
// point it raised carries the city's handled mark (pointsOf), after the review
// request that asks its author to review again. A request for changes stands
// while it is its author's latest review that approves, requests changes or was
// dismissed, as the approval rule reads it. A request for changes under the
// city's own login asks no review, since GitHub takes none of a PR's author. A
// review request that is refused, such as one for a bot's login, which the gh
// adapter refuses before it asks, leaves the dismissal to go on.
func (a *answering) dismiss() error {
	latest := map[string]gh.Review{}
	for _, v := range a.reviews {
		if v.Author == "" || !slices.Contains(opinionStates, v.State) {
			continue
		}
		cur, seen := latest[v.Author]
		if !seen || v.SubmittedAt > cur.SubmittedAt || (v.SubmittedAt == cur.SubmittedAt && v.ID > cur.ID) {
			latest[v.Author] = v
		}
	}
	for _, login := range slices.Sorted(maps.Keys(latest)) {
		v := latest[login]
		if v.State != "CHANGES_REQUESTED" {
			continue
		}
		points := a.pointsOf(v)
		if len(points) == 0 || slices.ContainsFunc(points, func(p spot) bool { return !a.handled(p.node, p.reacted) }) {
			continue
		}
		note, err := a.dismissalNote(points)
		if err != nil {
			return err
		}
		if a.l.Mark == nil {
			a.fail("nothing reads the city's mark here, so %s is not dismissed", v.URL)
			continue
		}
		mark, err := a.l.Mark()
		if mark = strings.TrimSpace(mark); err != nil || mark == "" {
			a.fail("the city's mark did not read, so %s is not dismissed: %v", v.URL, err)
			continue
		}
		if login != a.self {
			switch err := a.hub.RequestReview(a.repo, a.number, login); {
			case err == nil:
				a.out.Requested = append(a.out.Requested, login)
			case gh.Refused(err):
				a.leave("the request that %s review again was refused, so %s is dismissed with no review asked: %v", login, v.URL, err)
			default:
				a.fail("the request that %s review again did not land, so %s is not dismissed: %v", login, v.URL, err)
				continue
			}
		}
		switch err := a.hub.DismissReview(a.repo, a.number, v.ID, note+"\n\n"+mark); {
		case err == nil:
			a.out.Dismissed = append(a.out.Dismissed, v.URL)
		case gh.Refused(err):
			a.leave("GitHub refused to dismiss %s: %v", v.URL, err)
		default:
			a.fail("the dismissal of %s did not land: %v", v.URL, err)
		}
	}
	return nil
}

// pointsOf is each point the review v raised that the definition of feedback
// reads as feedback: its message, when it carries text, and each inline comment
// it carries. A post the definition sets aside, such as one not for review, is
// owed no answer, so it raises no point.
func (a *answering) pointsOf(v gh.Review) []spot {
	var out []spot
	if a.owed[v.NodeID] {
		out = append(out, spot{kind: PostReview, id: v.ID, node: v.NodeID, url: v.URL, reacted: v.ViewerReactions, thread: -1})
	}
	for i, t := range a.threads {
		for _, c := range t.Comments {
			if c.Review != nil && c.Review.ID == v.ID && a.owed[c.NodeID] {
				out = append(out, spot{kind: PostInline, id: c.ID, node: c.NodeID, url: c.URL, reacted: c.ViewerReactions, thread: i})
			}
		}
	}
	return out
}

// dismissalNote is a dismissal's one line: how many of the review's points
// were fixed, declined, deferred or answered, by the rulings the runs on the
// bead made of each point's ask. A round rules an open ask again at each head,
// so a point counts by the weightiest ruling it got: fixed when a round ruled
// it must-fix, else deferred, else declined, else answered, which a point whose
// ask no run ruled, such as one another path answered, counts as too.
func (a *answering) dismissalNote(points []spot) (string, error) {
	byAsk, err := a.rulingsByAsk()
	if err != nil {
		return "", err
	}
	weight := []struct{ ruling, word string }{
		{review.RulingMustFix, "fixed"}, {review.RulingDeferred, review.RulingDeferred},
		{review.RulingDeclined, review.RulingDeclined},
	}
	count := map[string]int{}
	for _, p := range points {
		_, frag, _ := strings.Cut(p.url, "#")
		how := review.RulingAnswered
		for _, ask := range a.asks {
			url := PostNamed(ask.Reason, a.url)
			if _, f, _ := strings.Cut(url, "#"); url == "" || f != frag {
				continue
			}
			for _, w := range weight {
				if slices.ContainsFunc(byAsk[ask.ID], func(r review.Ruling) bool { return r.Ruling == w.ruling }) {
					how = w.word
					break
				}
			}
		}
		count[how]++
	}
	var parts []string
	for _, k := range []string{"fixed", review.RulingDeclined, review.RulingDeferred, review.RulingAnswered} {
		if count[k] > 0 {
			parts = append(parts, fmt.Sprintf("%d %s", count[k], k))
		}
	}
	return "Every point of this request for changes has its answer beside it on the PR: " + strings.Join(parts, ", ") + ".", nil
}

// rulingsByAsk is each ask's rulings, in the order the review runs attached to
// the bead made them: the runs by when they were filed, and each run's rounds
// in order. A bead that no run reads as one is passed over.
func (a *answering) rulingsByAsk() (map[string][]review.Ruling, error) {
	if a.byAsk != nil {
		return a.byAsk, nil
	}
	var roots []*ledger.Record
	for _, b := range a.blockers {
		if isReviewRoot(b) {
			roots = append(roots, b)
		}
	}
	slices.SortStableFunc(roots, func(x, y *ledger.Record) int {
		if c := strings.Compare(x.CreatedAt(), y.CreatedAt()); c != 0 {
			return c
		}
		return strings.Compare(x.ID, y.ID)
	})
	runs := []*review.Run{}
	for _, root := range roots {
		if root.ID == a.run.Root {
			continue
		}
		run, err := review.ReadRun(a.l.Ledger, root.ID)
		var notRun *review.NotARun
		switch {
		case errors.As(err, &notRun):
			continue
		case err != nil:
			return nil, err
		}
		runs = append(runs, run)
	}
	runs = append(runs, a.run)
	a.byAsk = map[string][]review.Ruling{}
	for _, run := range runs {
		for _, m := range slices.Sorted(maps.Keys(run.Iterations)) {
			for _, r := range run.Iterations[m].Rulings() {
				if r.Ask != "" {
					a.byAsk[r.Ask] = append(a.byAsk[r.Ask], r)
				}
			}
		}
	}
	return a.byAsk, nil
}

// before reports whether the instant a is earlier than the instant b, each as
// the store writes a bead's times. An instant that does not read is earlier
// than none.
func before(a, b string) bool {
	x, err := time.Parse(time.RFC3339Nano, a)
	if err != nil {
		return false
	}
	y, err := time.Parse(time.RFC3339Nano, b)
	return err == nil && x.Before(y)
}

// firstLine is s up to its first line break.
func firstLine(s string) string {
	line, _, _ := strings.Cut(strings.TrimSpace(s), "\n")
	return strings.TrimSpace(line)
}
