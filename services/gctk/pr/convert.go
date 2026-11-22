package pr

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
)

// The conversion of the old receipts (specs/tk-1tfzr71.161/design.md, section
// 2, "The old receipts on a moved bead", and section 11, row 3). A bead that
// owns a PR on the record can carry pr-facts.sh's receipts: in each id space
// the highest id it routed (a watermark) and the highest its review threads had
// answered past that (an answered mark), and the batches it routed, each with
// the bead it went to. The landing order converts them into the city's marks,
// as an act decided from the bead, and takes no post on a bead that carries them
// (untakenOn) and pours no review run on one (admit), so no post the old path
// routed is filed twice.
//
// Under the record lock the act makes its own read of the PR's posts and
// threads. It files the post of each open human finding on the bead as its ask,
// the post's mark following once the ask stands, marks with the city's EYES
// each other post the receipts reach that is feedback carrying neither of the
// city's marks (oldMarks.covers), resolves each unresolved thread that holds
// only the city's own posts, the old path's machine findings, and closes the
// asks the batches went to and each finding whose post is gone. A post
// pr-facts.sh marked when it routed it carries the city's EYES already, so the
// act leaves it as it is. With the lock free, the disposition writer closes
// each finding onto the ask of its post, and the one-PR update reads the PR's
// conversation again, since a mark and a resolution move no sign the cheap
// question reads. Last, under the lock again, the act unsets the receipts, once
// no open human finding and no open ask a batch went to is left on the bead and
// the saved read shows no post they reach untaken, so the take, which decides
// from the saved read, files only the posts no receipt reaches. While such a
// finding or ask is on the bead, the act waits as long as a review run is
// attached to the bead or another open bead works its branch, since that run or
// that writer may rule or answer them. An act that does not complete leaves the
// receipts on the bead, and the next run converts again from where GitHub and
// the store then stand.

// pr-facts.sh's receipts on the bead that owns a PR (lifecycle/lifecycle.toml,
// [posture] and [metadata.pr_posture]). pr-facts.sh writes each, and the
// landing order's conversion reads them and unsets them.
var (
	reviewWatermarkKey = ledger.Declare("pr_review_watermark", ledger.String,
		"The highest id of a review whose message pr-facts.sh routed, among the comments and requests for "+
			"changes it counts. "+receiptDoc)
	commentWatermarkKey = ledger.Declare("pr_comment_watermark", ledger.String,
		"The highest id of an inline comment pr-facts.sh routed. "+receiptDoc)
	issueCommentWatermarkKey = ledger.Declare("pr_issue_comment_watermark", ledger.String,
		"The highest id of a conversation comment pr-facts.sh routed. "+receiptDoc)
	reviewAnsweredKey = ledger.Declare("pr_review_answered", ledger.String,
		"How far past pr_review_watermark the review threads had answered the counted reviews' messages when "+
			"pr-facts.sh last read them. "+receiptDoc)
	commentAnsweredKey = ledger.Declare("pr_comment_answered", ledger.String,
		"How far past pr_comment_watermark the review threads had answered the inline comments when pr-facts.sh "+
			"last read them. "+receiptDoc)
	reviewBatchKey = ledger.Declare("pr_review_batch", ledger.String,
		"The batches of review messages pr-facts.sh routed, oldest first, as <disposition>|<exclusive floor>|"+
			"<inclusive mark> records joined by ;, each disposition rework:<bead> or human:<gate>. "+receiptDoc)
	commentBatchKey = ledger.Declare("pr_comment_batch", ledger.String,
		"The batches of inline comments pr-facts.sh routed, in pr_review_batch's form. "+receiptDoc)
	issueCommentBatchKey = ledger.Declare("pr_issue_comment_batch", ledger.String,
		"The batches of conversation comments pr-facts.sh routed, in pr_review_batch's form. "+receiptDoc)
	commentDispositionKey = ledger.Declare("pr_comment_disposition", ledger.String,
		"What pr-facts.sh routed a PR's last batch of posts to: rework:<bead>, the bead that answers it, or "+
			"human:<gate>. "+receiptDoc)
)

// receiptDoc says, for each receipt, who writes it and what the conversion does
// with it.
const receiptDoc = "pr-facts.sh writes it on the bead that owns the PR. On a bead that owns a PR on the " +
	"pending record, the landing order's conversion of the old receipts reads it, marks with the city's EYES each " +
	"post it reaches that carries neither of the city's marks, and unsets it once the saved read shows the marks."

// receiptKeys are the receipts, in the order a conversion names them.
var receiptKeys = []ledger.Key[string]{reviewWatermarkKey, commentWatermarkKey, issueCommentWatermarkKey,
	reviewAnsweredKey, commentAnsweredKey, reviewBatchKey, commentBatchKey, issueCommentBatchKey,
	commentDispositionKey}

// The keys of a human finding that the conversion reads, which finding.sh
// writes as pr-facts.sh routes a person's post.
var (
	findingLaneKey = ledger.ReadOnly("finding.lane", ledger.String,
		"The lane a finding was raised on: human for a person's post pr-facts.sh routed. finding.sh writes it "+
			"on a finding alone, in the create that files it.")
	findingCommentKey = ledger.ReadOnly("finding.comment_id", ledger.String,
		"The id of the post a human finding was raised from, in its own id space.")
	findingReviewKey = ledger.ReadOnly("finding.review_id", ledger.String,
		"The review a human finding's post belongs to: its own id for a review's message, the review that "+
			"carried it for an inline comment, and none for a conversation comment.")
)

// receiptsOn names each receipt r carries.
func receiptsOn(r *ledger.Record) []string {
	var out []string
	for _, k := range receiptKeys {
		if _, ok, _ := k.Get(r); ok {
			out = append(out, k.Name())
		}
	}
	return out
}

// oldMarks is how far pr-facts.sh's receipts on a bead reach in each id space:
// the highest id a watermark, an answered mark or a record of a batch ledger
// names there. batches are the beads the batches went to, as each disposition
// names one with rework:<bead>.
type oldMarks struct {
	review, inline, conversation int64
	batches                      []string
}

// marksOf reads the receipts on r. A value that does not read as an id, and a
// ledger record that does not read as one, reach nothing, as pr-facts.sh reads a
// watermark that is not a number as 0.
func marksOf(r *ledger.Record) oldMarks {
	var m oldMarks
	id := func(k ledger.Key[string]) int64 {
		v, _, _ := k.Get(r)
		n, err := strconv.ParseInt(strings.TrimSpace(v), 10, 64)
		if err != nil {
			return 0
		}
		return n
	}
	ledgerMark := func(k ledger.Key[string]) int64 {
		v, _, _ := k.Get(r)
		var top int64
		for _, rec := range strings.Split(v, ";") {
			parts := strings.Split(strings.TrimSpace(rec), "|")
			if len(parts) != 3 {
				continue
			}
			m.went(parts[0])
			if hi, err := strconv.ParseInt(parts[2], 10, 64); err == nil {
				top = max(top, hi)
			}
		}
		return top
	}
	m.review = max(id(reviewWatermarkKey), id(reviewAnsweredKey), ledgerMark(reviewBatchKey))
	m.inline = max(id(commentWatermarkKey), id(commentAnsweredKey), ledgerMark(commentBatchKey))
	m.conversation = max(id(issueCommentWatermarkKey), ledgerMark(issueCommentBatchKey))
	last, _, _ := commentDispositionKey.Get(r)
	m.went(last)
	return m
}

// went records the bead a batch went to, when disposition names one.
func (m *oldMarks) went(disposition string) {
	id, ok := strings.CutPrefix(strings.TrimSpace(disposition), "rework:")
	if ok && id != "" && !slices.Contains(m.batches, id) {
		m.batches = append(m.batches, id)
	}
}

// covers reports whether the receipts reach p: an inline comment or a
// conversation comment at or below its space's mark, or the message of a
// comment or a request for changes at or below the review space's.
// pr-facts.sh routed no approval's message, so no receipt reaches one, and the
// take files it once the receipts are gone.
func (m oldMarks) covers(p Post) bool {
	switch p.Kind {
	case PostReview:
		return (p.State == "COMMENTED" || p.State == "CHANGES_REQUESTED") && p.ID <= m.review
	case PostInline:
		return p.ID <= m.inline
	case PostConversation:
		return p.ID <= m.conversation
	}
	return false
}

// finding is an open human finding on a bead: its id, status and assignee, and
// the post it names, by kind and id, or why it names none the conversion can
// place.
type finding struct {
	id, status, assignee string
	kind                 string
	post                 int64
	unplaced             string
}

// findingsOn reads the open human findings on the bead id: the live beads whose
// anchor_bead names it, raised on the human lane, which only a finding names. A
// finding names its post as pr-facts.sh records it: by its comment id, with its
// review id the comment id itself for a review's message, the review that
// carried it for an inline comment, and none for a conversation comment.
func findingsOn(l *ledger.Ledger, id string) ([]finding, error) {
	rows, err := l.Find(ledger.Matching(anchorKey, id))
	if err != nil {
		return nil, err
	}
	var out []finding
	for _, r := range rows {
		lane, _, _ := findingLaneKey.Get(r)
		if r.ID == id || r.Status() == "closed" || strings.TrimSpace(lane) != "human" {
			continue
		}
		f := finding{id: r.ID, status: r.Status(), assignee: r.Assignee()}
		comment, _, _ := findingCommentKey.Get(r)
		reviewID, _, _ := findingReviewKey.Get(r)
		comment, reviewID = strings.TrimSpace(comment), strings.TrimSpace(reviewID)
		n, err := strconv.ParseInt(comment, 10, 64)
		switch {
		case err != nil || n <= 0:
			f.unplaced = fmt.Sprintf("its finding.comment_id reads %q, which names no post", comment)
		case reviewID == "":
			f.kind, f.post = PostConversation, n
		case reviewID == comment:
			f.kind, f.post = PostReview, n
		default:
			f.kind, f.post = PostInline, n
		}
		out = append(out, f)
	}
	slices.SortFunc(out, func(a, b finding) int { return strings.Compare(a.id, b.id) })
	return out, nil
}

// postsOn is each post the read c holds, by its kind and id (postKey).
func postsOn(c *gh.Conversation) map[string]Post {
	out := map[string]Post{}
	for _, v := range c.Reviews {
		out[postKey(PostReview, v.ID)] = reviewPost(v)
	}
	for _, t := range c.Threads {
		for _, cm := range t.Comments {
			out[postKey(PostInline, cm.ID)] = inlinePost(cm)
		}
	}
	for _, cm := range c.Comments {
		out[postKey(PostConversation, cm.ID)] = conversationPost(cm)
	}
	return out
}

func postKey(kind string, id int64) string { return kind + " " + strconv.FormatInt(id, 10) }

// convertOf is the conversion one owned PR's bead owes: the bead, the PR's URL
// as the bead names it, and the PR's identity.
type convertOf struct {
	bead, url, key string
}

// of names the conversion, as each outcome it reports opens.
func (c convertOf) of() string { return "the conversion of pr-facts.sh's receipts on " + c.bead }

// unconvertible says why the bead o reads owes no conversion now, and is empty
// when it owes one: it carries the receipts, owns the PR on the record, is open
// or blocked, is assigned to nobody or to the refinery, as any act's bead is,
// names its branch, which each ask names, holds a provenance instant, which the
// definition of feedback is applied from, and holds a saved read of its PR that
// shows the PR open.
func (u *run) unconvertible(o owned) string {
	s := o.saved
	switch {
	case len(o.receipts) == 0:
		return "the bead carries none of pr-facts.sh's receipts"
	case !record.OnRecord(o.rec.Result):
		return fmt.Sprintf("the bead owns no PR on the record: its merge_result reads %q", o.rec.Result)
	case o.status != "open" && o.status != "blocked":
		return "the bead's status " + o.status + " is none the record knows"
	case o.assignee != "" && o.assignee != u.Refinery:
		return "the bead is assigned to " + o.assignee + ", who works it now"
	case o.branch == "":
		return "the bead names no branch for an ask to name"
	case o.since == "":
		return "the bead holds no provenance instant to apply the definition of feedback from"
	case s == nil || s.PR == nil:
		return "the bead holds no saved read of the PR yet"
	case !strings.EqualFold(s.PR.Repository, o.repo) || s.PR.Number != o.number:
		return fmt.Sprintf("the saved read is of %s#%d", s.PR.Repository, s.PR.Number)
	case s.PR.State != "OPEN":
		return "the saved read shows the PR " + strings.ToLower(s.PR.State)
	}
	return ""
}

// converted is what the part of a conversion made under the record lock did:
// what it did, each finding it filed as the ask of its post, for the
// disposition writer to close onto that ask, and each step that did not
// complete.
type converted struct {
	did, failed []string
	rehomes     []rehoming
}

// rehoming is a finding the disposition writer closes onto the ask of its post:
// the finding, the status and assignee the act read it under, the ask, and the
// post's URL.
type rehoming struct {
	finding, status, assignee, ask, post string
}

// convert is a conversion's act, which ends stop after it starts. Under the
// record lock it converts what its read of the PR and the store show
// (convertLocked). With the lock free the disposition writer closes each human
// finding it filed onto the ask of its post, and the one-PR update reads the
// PR's conversation again. Last it unsets the receipts under the lock
// (unsetReceipts). A step that does not complete makes the act a retry, and
// the next run converts again.
func (u *run) convert(c convertOf, stop time.Duration) RunOutcome {
	ctx, cancel := bounded(stop)
	defer cancel()
	out, done := u.convertLocked(ctx, c)
	if done != nil {
		out = u.convertFree(ctx, c, *done)
	}
	if ctx.Err() != nil && (out.Action == ActRetry || out.Action == ActFailed) {
		out.Action = ActRetry
		out.Detail = fmt.Sprintf("the act was stopped at its %s: %s", stop, out.Detail)
	}
	return out
}

// convertFree is the part of a conversion made once the lock is free, after
// the part under it did done: the closes of the findings it filed as asks, the
// one-PR update's read of the conversation, and then the unset of the receipts,
// which follows only when every step before it completed.
func (u *run) convertFree(ctx context.Context, c convertOf, done converted) RunOutcome {
	for _, f := range done.rehomes {
		if ctx.Err() != nil {
			done.failed = append(done.failed, f.finding+" was not reached for its close onto "+f.ask)
			continue
		}
		if u.Dispositions == nil {
			done.failed = append(done.failed, f.finding+" did not close onto "+f.ask+": no disposition writer is set")
			continue
		}
		err := u.Dispositions.Close(Disposal{Bead: f.finding, Status: f.status, Assignee: f.assignee,
			Disposition: Disposition{Kind: "re-homed", Successor: f.ask},
			Note: fmt.Sprintf("The landing order's conversion of pr-facts.sh's receipts on %s filed this finding's post "+
				"(%s) as the ask %s, which carries it now.", c.bead, f.post, f.ask)})
		if err != nil {
			done.failed = append(done.failed, fmt.Sprintf("%s did not close onto %s: %v", f.finding, f.ask, err))
			continue
		}
		done.did = append(done.did, fmt.Sprintf("closed finding %s onto %s", f.finding, f.ask))
	}
	refreshed := "nothing reads the PR's conversation again here"
	if u.RefreshConversation != nil {
		refreshed = ""
		if err := u.RefreshConversation(ctx, c.url); err != nil {
			refreshed = "the one-PR update's read of the PR's conversation did not save: " + err.Error()
		}
	}
	if refreshed != "" {
		done.failed = append(done.failed, refreshed)
	}
	if len(done.failed) > 0 {
		detail := fmt.Sprintf("%s did not complete, so the receipts stay and the next run converts again: %s",
			c.of(), strings.Join(done.failed, "; "))
		if len(done.did) > 0 {
			detail += "; it " + strings.Join(done.did, ", ")
		}
		return RunOutcome{Bead: c.bead, Action: ActRetry, Detail: detail}
	}
	return u.unsetReceipts(ctx, c, done.did)
}

// convertLocked is the part of a conversion made under the record lock, within
// ctx: it reads the bead again, decides from that read whether it owes its
// conversion (unconvertible), and waits while a review run is attached or
// another open bead works the branch when an open human finding or batch ask
// is on the bead. Otherwise it reads the PR's posts and threads and, in this
// order, files the post of each open human finding as its ask and then marks
// the post, marks each other post the receipts reach that the read shows
// untaken, resolves each unresolved thread that holds only the city's own
// posts, closes each open ask a batch went to, and closes each finding whose
// post the read does not hold. It returns the act's outcome when the act ends
// here, and otherwise what it did, for the part made once the lock is free.
func (u *run) convertLocked(ctx context.Context, c convertOf) (RunOutcome, *converted) {
	unbound := u.Ledger
	u.Ledger = unbound.Within(ctx)
	defer func() { u.Ledger = unbound }()
	said := func(action, detail string) (RunOutcome, *converted) {
		return RunOutcome{Bead: c.bead, Action: action, Detail: c.of() + " " + detail}, nil
	}
	release, err := record.Lock(u.Dir, lockWait(ctx, u.Wait))
	if err != nil {
		return said(ActRetry, "waits for the next run: the record lock did not come free: "+err.Error())
	}
	defer release()
	r, err := u.read(c.bead)
	if err != nil {
		return said(ActFailed, "did not read the bead: "+err.Error())
	}
	if r == nil {
		return said(ActSkipped, "converts nothing: the store no longer holds the bead")
	}
	o, ok := ownerOf(r)
	if !ok || o.key() != c.key {
		return said(ActSkipped, "converts nothing: the bead no longer owns the PR")
	}
	if why := u.unconvertible(o); why != "" {
		return said(ActChecked, "converts nothing: "+why)
	}
	if why := u.originDiffers(o.host, o.repo); why != "" {
		return said(ActRetry, "waits for the next run: "+why)
	}
	marks := marksOf(r)
	findings, err := findingsOn(u.Ledger, o.id)
	if err != nil {
		return said(ActRetry, "waits for the next run: the human findings on the bead did not read: "+err.Error())
	}
	blockers, err := blockersIn(u.Ledger, r, true)
	var runs []string
	var asks []review.Ask
	if err == nil {
		runs, err = runsIn(blockers)
	}
	if err == nil {
		asks, err = review.AsksIn(u.Ledger, r, blockers)
	}
	if err != nil {
		return said(ActRetry, "waits for the next run: what holds the bead did not read: "+err.Error())
	}
	var batches []review.Ask
	for _, a := range asks {
		if a.Open() && slices.Contains(marks.batches, a.ID) {
			batches = append(batches, a)
		}
	}
	if len(findings) > 0 || len(batches) > 0 {
		if len(runs) > 0 {
			return said(ActChecked, fmt.Sprintf("waits for review run %s to end, which may rule the old path's "+
				"findings and batches on the bead", strings.Join(runs, ", ")))
		}
		writers, err := u.writers(state{id: o.id, branch: o.branch, reads: u.Ledger})
		if err != nil {
			return said(ActRetry, "waits for the next run: the beads on "+o.branch+" did not read: "+err.Error())
		}
		if len(writers) > 0 {
			return said(ActChecked, fmt.Sprintf("waits while %s works %s, which may answer the old path's findings on "+
				"the bead", strings.Join(writers, ", "), o.branch))
		}
	}
	hub := u.Hub(ctx, o.host)
	conv, err := hub.Conversation(o.repo, o.number)
	if err != nil {
		return said(ActRetry, "waits for the next run: its read of the PR's posts and threads did not answer: "+err.Error())
	}
	rule, err := u.rule()
	if err != nil {
		return said(ActRetry, "waits for the next run: the definition of feedback did not load: "+err.Error())
	}
	self, err := u.login(o.host, hub)
	if err != nil {
		return said(ActRetry, "waits for the next run: the login the city's account acts as did not read: "+err.Error())
	}
	untaken, err := untakenOf(rule, self, o.since, conv.Reviews, conv.Threads, conv.Comments)
	if err == nil {
		var own []string
		if own, err = ownThreads(rule, self, o.since, conv.Threads); err == nil {
			return RunOutcome{}, u.convertRead(ctx, o, hub, marks, findings, batches, conv, untaken, own)
		}
	}
	return said(ActRetry, "waits for the next run: the definition of feedback did not answer: "+err.Error())
}

// convertRead makes the writes of a conversation's locked part, on its read of
// the PR's posts and threads: conv, the posts it shows untaken and the threads
// that hold only the city's own posts. Each write starts only while ctx is
// live, and a mark goes on a post only once any ask it is owed stands, so a
// mark never stands for a post whose ask is not filed.
func (u *run) convertRead(ctx context.Context, o owned, hub Hub, marks oldMarks, findings []finding,
	batches []review.Ask, conv *gh.Conversation, untaken []Post, own []string) *converted {
	done := &converted{}
	stopped := func(what string) bool {
		if ctx.Err() != nil {
			done.failed = append(done.failed, what+" was not reached")
			return true
		}
		return false
	}
	isUntaken := func(p Post) bool {
		return slices.ContainsFunc(untaken, func(q Post) bool { return q.Kind == p.Kind && q.ID == p.ID })
	}
	mark := func(p Post) bool {
		if err := hub.AddReaction(p.Node, takenMark); err != nil {
			done.failed = append(done.failed, fmt.Sprintf("the city's %s did not land on %s: %v", takenMark, p.name(), err))
			return false
		}
		return true
	}
	posts := postsOn(conv)
	noChecks := func(string) (review.Index, error) {
		return review.Index{}, errors.New("a post's ask sends back no check")
	}
	owed := map[string]bool{}
	var marked, gone []string
	var goneFindings []finding
	for _, f := range findings {
		if f.unplaced != "" {
			done.failed = append(done.failed, fmt.Sprintf("finding %s names no post to file as its ask: %s", f.id, f.unplaced))
			continue
		}
		p, ok := posts[postKey(f.kind, f.post)]
		if !ok {
			goneFindings = append(goneFindings, f)
			continue
		}
		owed[postKey(p.Kind, p.ID)] = true
		if stopped("the ask of finding " + f.id) {
			continue
		}
		ask, filed, err := review.FileAsk(u.Ledger, review.AskRequest{Bead: o.id, Reason: p.reason(o.number)}, noChecks)
		if err != nil {
			done.failed = append(done.failed, fmt.Sprintf("finding %s: the ask of %s did not file: %v", f.id, p.name(), err))
			continue
		}
		how := "filed"
		if !filed {
			how = "found"
		}
		if isUntaken(p) {
			if !mark(p) {
				continue
			}
			marked = append(marked, p.name())
		}
		done.did = append(done.did, fmt.Sprintf("%s ask %s for the post of finding %s, %s", how, ask, f.id, p.name()))
		done.rehomes = append(done.rehomes, rehoming{finding: f.id, status: f.status, assignee: f.assignee, ask: ask,
			post: p.URL})
	}
	for _, p := range untaken {
		if !marks.covers(p) || owed[postKey(p.Kind, p.ID)] || stopped("the mark on "+p.name()) {
			continue
		}
		if mark(p) {
			marked = append(marked, p.name())
		}
	}
	if len(marked) > 0 {
		done.did = append(done.did, fmt.Sprintf("marked %s with the city's %s", strings.Join(marked, ", "), takenMark))
	}
	var resolved []string
	for _, id := range own {
		if stopped("the resolution of thread " + id) {
			continue
		}
		if err := hub.ResolveThread(id); err != nil {
			done.failed = append(done.failed, fmt.Sprintf("thread %s, which holds only the city's own posts, did not "+
				"resolve: %v", id, err))
			continue
		}
		resolved = append(resolved, id)
	}
	if len(resolved) > 0 {
		done.did = append(done.did, fmt.Sprintf("resolved thread %s, which holds only the city's own posts",
			strings.Join(resolved, ", ")))
	}
	at := u.stamp()
	var closed []string
	for _, a := range batches {
		if stopped("the close of the batch's ask " + a.ID) {
			continue
		}
		note := fmt.Sprintf("The landing order closed this ask (%s) in converting pr-facts.sh's receipts on %s: each "+
			"post of its batch carries the city's mark, and each one its open findings name is an ask of its own, so no "+
			"review run takes it.", at, o.id)
		if err := u.moot(a.ID, a.Status, "", note); err != nil {
			done.failed = append(done.failed, fmt.Sprintf("the batch's ask %s did not close: %v", a.ID, err))
			continue
		}
		closed = append(closed, a.ID)
	}
	if len(closed) > 0 {
		done.did = append(done.did, fmt.Sprintf("closed the batch's ask %s", strings.Join(closed, ", ")))
	}
	for _, f := range goneFindings {
		if stopped("the close of finding " + f.id) {
			continue
		}
		note := fmt.Sprintf("The landing order closed this finding (%s) in converting pr-facts.sh's receipts on %s: "+
			"its post, %s %d, is no longer on the PR, so nothing is owed to it.", at, o.id, f.kind, f.post)
		if err := u.moot(f.id, f.status, f.assignee, note); err != nil {
			done.failed = append(done.failed, fmt.Sprintf("finding %s, whose post is gone, did not close: %v", f.id, err))
			continue
		}
		gone = append(gone, f.id)
	}
	if len(gone) > 0 {
		done.did = append(done.did, fmt.Sprintf("closed finding %s, whose post is no longer on the PR", strings.Join(gone, ", ")))
	}
	return done
}

// unsetReceipts is a conversion's last step, under the record lock within ctx:
// it reads the bead again and unsets the receipts it carries, in one write
// guarded on the status and assignee that read shows, once it still owes its
// conversion and no open human finding and no open ask a batch went to is left
// on it, and its saved conversation, read from its provenance instant, holds no
// untaken post the receipts reach. did is what the act did before it, which the
// outcome names.
func (u *run) unsetReceipts(ctx context.Context, c convertOf, did []string) RunOutcome {
	unbound := u.Ledger
	u.Ledger = unbound.Within(ctx)
	defer func() { u.Ledger = unbound }()
	account := func() string {
		if len(did) == 0 {
			return ""
		}
		return "; it " + strings.Join(did, ", ")
	}
	said := func(action, detail string) RunOutcome {
		return RunOutcome{Bead: c.bead, Action: action, Detail: c.of() + " " + detail + account()}
	}
	release, err := record.Lock(u.Dir, lockWait(ctx, u.Wait))
	if err != nil {
		return said(ActRetry, "leaves the receipts for the next run: the record lock did not come free: "+err.Error())
	}
	defer release()
	r, err := u.read(c.bead)
	if err != nil {
		return said(ActFailed, "did not read the bead again: "+err.Error())
	}
	if r == nil {
		return said(ActSkipped, "unset nothing: the store no longer holds the bead")
	}
	o, ok := ownerOf(r)
	if !ok || o.key() != c.key {
		return said(ActSkipped, "unset nothing: the bead no longer owns the PR")
	}
	if why := u.unconvertible(o); why != "" {
		return said(ActRetry, "leaves the receipts for the next run: "+why)
	}
	marks := marksOf(r)
	findings, err := findingsOn(u.Ledger, o.id)
	if err != nil {
		return said(ActRetry, "leaves the receipts for the next run: the human findings on the bead did not read: "+err.Error())
	}
	if len(findings) > 0 {
		var ids []string
		for _, f := range findings {
			ids = append(ids, f.id)
		}
		return said(ActRetry, "leaves the receipts for the next run: the human finding "+strings.Join(ids, ", ")+
			" is still open on the bead")
	}
	asks, err := review.AsksOn(u.Ledger, o.id)
	if err != nil {
		return said(ActRetry, "leaves the receipts for the next run: the asks on the bead did not read: "+err.Error())
	}
	for _, a := range asks {
		if a.Open() && slices.Contains(marks.batches, a.ID) {
			return said(ActRetry, "leaves the receipts for the next run: the batch's ask "+a.ID+" is still open")
		}
	}
	conv := o.saved.Conversation
	switch {
	case conv == nil || conv.Untaken == nil:
		return said(ActRetry, "leaves the receipts for the next run: the saved read holds no list of the posts the "+
			"city has not taken")
	case conv.Since != o.since:
		return said(ActRetry, fmt.Sprintf("leaves the receipts for the next run: the saved conversation applied the "+
			"definition of feedback from %q, not from the bead's provenance instant %q", conv.Since, o.since))
	}
	for _, p := range conv.Untaken {
		if marks.covers(p) {
			return said(ActRetry, "leaves the receipts for the next run: the saved read shows "+p.name()+
				", which they reach, untaken")
		}
	}
	w := u.Ledger.Write(o.id)
	w.Guard(o.status, o.assignee)
	for _, k := range receiptKeys {
		if slices.Contains(o.receipts, k.Name()) {
			k.Clear(w)
		}
	}
	w.Note(fmt.Sprintf("The landing order converted pr-facts.sh's receipts on this bead (%s) into the city's marks on "+
		"its PR's posts, and unset %s.", u.stamp(), strings.Join(o.receipts, ", ")))
	if err := u.Ledger.Commit(w); err != nil {
		if errors.Is(err, ledger.ErrGuard) {
			return said(ActMoved, "unset nothing: the bead moved since the act read it: "+err.Error())
		}
		return said(ActRetry, "leaves the receipts for the next run: their unset did not land: "+err.Error())
	}
	return RunOutcome{Bead: c.bead, Action: ActConverted,
		Detail: fmt.Sprintf("%s unset %s%s", c.of(), strings.Join(o.receipts, ", "), account())}
}
