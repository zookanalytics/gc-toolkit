package pr_test

import (
	"context"
	"encoding/json"
	"errors"
	"slices"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	ghfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
)

// The take (specs/tk-1tfzr71.161/design.md, sections 1 to 3, and section 11's
// tests for unit 2), on the landing order's world: each post the saved read
// holds untaken becomes an ask on the bead, which the run files and then marks
// with the city's EYES, and once the marks land the one-PR update reads the
// conversation again.

// holdOnAsks has the store's blocked listing hold the bead on the beads held
// names and on each ask a run files on it, as bd's blocked rule holds a bead on
// each of its open blockers.
func (d *land) holdOnAsks(held ...string) {
	var mu sync.Mutex
	list := slices.Clone(held)
	d.store.List(bead, list...)
	d.store.OnWrite = func(kind, id string, _ []string) {
		if kind != "create" {
			return
		}
		b, ok := d.store.Row(id)
		if !ok || b.IssueType != "task" || b.Metadata["branch"] != branch {
			return
		}
		mu.Lock()
		defer mu.Unlock()
		list = append(list, id)
		d.store.List(bead, list...)
	}
}

// savedConversation is the conversation part of the read the one-PR update
// saved on the bead.
func (d *land) savedConversation(t *testing.T) *pr.SavedConversation {
	t.Helper()
	var s pr.SavedRead
	if err := json.Unmarshal([]byte(d.row(t).Metadata["pr_github_read"]), &s); err != nil || s.Conversation == nil {
		t.Fatalf("the bead holds no saved conversation: %v", err)
	}
	return s.Conversation
}

// asksFiled is each ask the store holds on the bead's branch, by its reason.
func (d *land) asksFiled() []string {
	var out []string
	for _, c := range d.store.Creates() {
		if b, ok := d.store.Row(c.ID); ok && b.IssueType == "task" && b.Metadata["branch"] == branch {
			out = append(out, b.Description)
		}
	}
	return out
}

// theAsk is the one ask the take has filed on the bead.
func (d *land) theAsk(t *testing.T) string {
	t.Helper()
	var ids []string
	for _, c := range d.store.Creates() {
		if b, ok := d.store.Row(c.ID); ok && b.IssueType == "task" && b.Metadata["branch"] == branch {
			ids = append(ids, c.ID)
		}
	}
	if len(ids) != 1 {
		t.Fatalf("the take filed the asks %v, want one", ids)
	}
	return ids[0]
}

// marked is each reaction the run asked GitHub to leave, as the post's node id
// and the reaction.
func (d *land) marked() []string {
	var out []string
	for _, a := range d.github.Asks()[d.asked:] {
		if a.Method == "AddReaction" {
			out = append(out, a.ID+" "+a.Message)
		}
	}
	return out
}

// takeOf splits a run's outcomes into the take's and the rest. A run that made
// no take gives a zero outcome for it.
func takeOf(t *testing.T, out []pr.RunOutcome) (pr.RunOutcome, []pr.RunOutcome) {
	t.Helper()
	var take pr.RunOutcome
	var rest []pr.RunOutcome
	for _, o := range out {
		if strings.Contains(o.Detail, "the take of "+prURL) {
			if take.Action != "" {
				t.Fatalf("two takes in one run: %+v", out)
			}
			take = o
			continue
		}
		rest = append(rest, o)
	}
	return take, rest
}

// onceTaking is the PR watch's pass, then a run of the landing order over a
// bead whose saved read holds a post the city has not taken, and returns the
// take's outcome and the record's.
func (d *land) onceTaking(t *testing.T) (pr.RunOutcome, pr.RunOutcome) {
	t.Helper()
	d.refresh(t)
	return d.runTaking(t)
}

// runTaking is a run of the landing order that makes a take beside the
// record's act, and returns the take's outcome and the record's.
func (d *land) runTaking(t *testing.T) (pr.RunOutcome, pr.RunOutcome) {
	t.Helper()
	take, rest := takeOf(t, d.reconcile(t, pr.Options{}))
	if take.Action == "" || len(rest) != 1 {
		t.Fatalf("a run with a take reported the take %+v and the outcomes %+v, want one of each", take, rest)
	}
	return take, rest[0]
}

// errUnmarked fails each mark the take asks while it is set, as a GitHub that
// does not answer the reaction.
var errUnmarked = errors.New("gh: error connecting to api.github.com")

// carried is an inline comment the approval review carries, which no mark of
// the city's marks.
func carried(id, review int64) gh.Comment {
	return gh.Comment{ID: id, NodeID: "PRRC_" + strconv.FormatInt(id, 10), URL: prURL + "#discussion_r" + strconv.FormatInt(id, 10),
		Author: "operator", Body: "rename this", CreatedAt: "2026-11-12T01:00:00Z",
		Review: &gh.CommentReview{ID: review, State: "APPROVED", SubmittedAt: "2026-11-12T01:00:00Z"}}
}

// taking is the landing order's world whose PR's conversation holds posts the
// city has not taken: an approval with a message, a review submitted after the
// city took posts whose ids are above its own, an inline comment it carries on
// a line of a file, and two conversation comments, one the city took.
func taking(t *testing.T) *land {
	t.Helper()
	d := newLand(t)
	d.l.Mark = func() (string, error) { return cityMark, nil }
	at := "2026-11-12T05:00:00Z"
	d.pr.Reviews = append(d.pr.Reviews,
		gh.Review{ID: 160, NodeID: "PRR_160", URL: prURL + "#pullrequestreview-160", State: "APPROVED", Author: "reviewer",
			AuthorCanPush: true, Body: "approved, but rename X", SubmittedAt: at},
		gh.Review{ID: 150, NodeID: "PRR_150", URL: prURL + "#pullrequestreview-150", State: "COMMENTED", Author: "visitor",
			Body: "a few points", SubmittedAt: "2026-11-12T06:00:00Z"})
	d.pr.Threads = []gh.Thread{{ID: "T1", Comments: []gh.Comment{{ID: 500, NodeID: "PRRC_500",
		URL: prURL + "#discussion_r500", Author: "visitor", Body: "rename this", CreatedAt: at, Path: "a/b.go",
		OriginalLine: 42, Review: &gh.CommentReview{ID: 150, State: "COMMENTED", SubmittedAt: "2026-11-12T06:00:00Z"}}}}}
	d.pr.Comments = []gh.IssueComment{
		{ID: 600, NodeID: "IC_600", URL: prURL + "#issuecomment-600", Author: "visitor", Body: "taken already",
			CreatedAt: at, ViewerReactions: []string{"EYES"}},
		{ID: 700, NodeID: "IC_700", URL: prURL + "#issuecomment-700", Author: "operator", Body: "one more thing",
			CreatedAt: at},
	}
	d.holdOnAsks()
	return d
}

// Each post the saved read holds untaken becomes its own ask, whose reason names
// the post's kind, its author, the PR, an inline comment's file and line, and
// its URL, and the take marks each post with the city's EYES once its ask is
// filed. A review submitted below the ids of posts the city took is taken
// like any other, and so is an approval's message. Once the marks land, the
// one-PR update reads the conversation again, so the saved read holds no
// untaken post, and the next run takes nothing.
func TestTheTakeFilesAnAskForEachPostAndMarksIt(t *testing.T) {
	d := taking(t)
	d.refresh(t)
	d.asked = len(d.github.Asks())
	take, _ := takeOf(t, d.reconcile(t, pr.Options{}))
	is(t, take, pr.ActTaken)
	want := []string{
		"Review by visitor on PR #7: " + prURL + "#pullrequestreview-150",
		"Approval message by reviewer on PR #7: " + prURL + "#pullrequestreview-160",
		"Inline comment by visitor on PR #7 at a/b.go line 42: " + prURL + "#discussion_r500",
		"Conversation comment by operator on PR #7: " + prURL + "#issuecomment-700",
	}
	if got := d.asksFiled(); !slices.Equal(got, want) {
		t.Fatalf("the take filed the asks\n%q\nwant\n%q", got, want)
	}
	if got := d.marked(); !slices.Equal(got, []string{"PRR_150 EYES", "PRR_160 EYES", "PRRC_500 EYES", "IC_700 EYES"}) {
		t.Fatalf("the take marked %q", got)
	}
	if got := d.savedConversation(t).Untaken; len(got) != 0 {
		t.Fatalf("once the marks landed the saved read holds the untaken posts %+v", got)
	}
	d.asked = len(d.github.Asks())
	take, _ = takeOf(t, d.reconcile(t, pr.Options{}))
	if take.Action != "" || len(d.marked()) != 0 || len(d.asksFiled()) != 4 {
		t.Fatalf("the next run took %+v, marked %q and filed %d asks", take, d.marked(), len(d.asksFiled()))
	}
}

// A post whose mark did not land stays untaken in the saved read, so the run in
// which its take failed exits non-zero and the next run takes it again: it
// finds the ask it filed by its reason, files no second one, and marks the
// post.
func TestAPostWhoseMarkFailedIsMarkedAgainWithNoSecondAsk(t *testing.T) {
	d := taking(t)
	d.github.OnReact = func(subject, _ string) error {
		if subject == "IC_700" {
			return errors.New("gh: error connecting to api.github.com")
		}
		return nil
	}
	d.refresh(t)
	take, _ := takeOf(t, d.reconcile(t, pr.Options{}))
	is(t, take, pr.ActRetry)
	says(t, take, "conversation comment 700", "did not land")
	if got := d.savedConversation(t).Untaken; len(got) != 1 || got[0].ID != 700 {
		t.Fatalf("the saved read holds the untaken posts %+v, want comment 700 alone", got)
	}
	d.github.OnReact = nil
	d.asked = len(d.github.Asks())
	take, _ = takeOf(t, d.reconcile(t, pr.Options{}))
	is(t, take, pr.ActTaken)
	says(t, take, "ask tk-5 found")
	if got := d.marked(); !slices.Equal(got, []string{"IC_700 EYES"}) {
		t.Fatalf("the next run marked %q, want comment 700 alone", got)
	}
	if n := len(d.asksFiled()); n != 4 {
		t.Fatalf("the take filed %d asks over two runs, want one for each of the four posts", n)
	}
}

// A take keeps the last of its bound for the read of the conversation that
// saves its marks: once a mark has landed with less than that left, it starts
// no other post and leaves the rest for the next run, whose saved read holds
// only the posts it left. So a PR with more posts than one act can take has
// them taken over runs, each starting where the last one's marks were saved.
// Here an act's bound is shorter than the reserve, so each run takes one post.
func TestATakeKeepsTimeForTheReadThatSavesItsMarks(t *testing.T) {
	d := taking(t)
	refresh := d.l.RefreshConversation
	d.l.RefreshConversation = func(ctx context.Context, url string) error {
		if err := ctx.Err(); err != nil {
			return err
		}
		return refresh(ctx, url)
	}
	d.refresh(t)
	nodes := []string{"PRR_150", "PRR_160", "PRRC_500", "IC_700"}
	for i, node := range nodes {
		d.asked = len(d.github.Asks())
		take, _ := takeOf(t, d.reconcile(t, pr.Options{Stop: 5 * time.Second}))
		if i < len(nodes)-1 {
			is(t, take, pr.ActLeft)
			says(t, take, "for the next run", "the read of the conversation that saves the marks")
		} else {
			is(t, take, pr.ActTaken)
		}
		if got := d.marked(); !slices.Equal(got, []string{node + " EYES"}) {
			t.Fatalf("run %d marked %q, want %s alone", i+1, got, node)
		}
		var left []string
		for _, p := range d.savedConversation(t).Untaken {
			left = append(left, p.Node)
		}
		if n := len(d.asksFiled()); n != i+1 || !slices.Equal(left, nodes[i+1:]) {
			t.Fatalf("after run %d the take has filed %d asks and the saved read holds %q untaken, want %d and %q",
				i+1, n, left, i+1, nodes[i+1:])
		}
	}
	d.asked = len(d.github.Asks())
	if take, _ := takeOf(t, d.reconcile(t, pr.Options{Stop: 5 * time.Second})); take.Action != "" || len(d.marked()) != 0 {
		t.Fatalf("a run once every post was taken took %+v and marked %q", take, d.marked())
	}
}

// A post edited after its take files nothing new: the post carries the city's
// mark, so the update reads it as taken. One edited while its mark has not
// landed keeps the reason its ask was filed under, which holds none of the
// post's text, so the take finds that ask and files no second one.
func TestAnEditedPostIsNotFiledTwice(t *testing.T) {
	d := taking(t)
	d.github.OnReact = func(subject, _ string) error {
		if subject == "PRRC_500" {
			return errors.New("gh: error connecting to api.github.com")
		}
		return nil
	}
	d.refresh(t)
	take, _ := takeOf(t, d.reconcile(t, pr.Options{}))
	is(t, take, pr.ActRetry)
	d.pr.Threads[0].Comments[0].Body = "rename this, and that"
	d.pr.Threads[0].Comments[0].UpdatedAt = "2026-11-12T07:30:00Z"
	d.pr.Comments[1].Body = "one more thing, edited"
	d.pr.Comments[1].UpdatedAt = "2026-11-12T07:30:00Z"
	d.github.OnReact = nil
	d.refresh(t)
	take, _ = takeOf(t, d.reconcile(t, pr.Options{}))
	is(t, take, pr.ActTaken)
	if n := len(d.asksFiled()); n != 4 {
		t.Fatalf("the edits left %d asks, want the four the posts were filed under", n)
	}
	d.refresh(t)
	if take, _ := takeOf(t, d.reconcile(t, pr.Options{})); take.Action != "" || len(d.asksFiled()) != 4 {
		t.Fatalf("a run after the edits took %+v and left %d asks", take, len(d.asksFiled()))
	}
}

// The take files and marks posts only on a bead the order may work, while the
// saved read is of the PR it owns, open and read from its provenance instant: a
// bead someone else is assigned and a PR that closed take nothing.
func TestTheTakeTakesNothingOnABeadItMayNotWork(t *testing.T) {
	for name, edit := range map[string]func(*land){
		"assigned to someone else": func(d *land) { d.put("blocked", "rig/gc-toolkit.polecat-1") },
		"closed":                   func(d *land) { d.pr.Facts.State = "CLOSED" },
	} {
		t.Run(name, func(t *testing.T) {
			d := taking(t)
			edit(d)
			d.refresh(t)
			d.asked = len(d.github.Asks())
			out := d.reconcile(t, pr.Options{})
			if take, _ := takeOf(t, out); take.Action != "" || len(d.asksFiled()) != 0 || len(d.marked()) != 0 {
				t.Fatalf("the run took %+v, filed %q and marked %q over %+v", take, d.asksFiled(), d.marked(), out)
			}
		})
	}
}

// A take is an act like the record's: a run past its window starts none, and
// leaves it to the next run.
func TestATakePastTheWindowIsLeftForTheNextRun(t *testing.T) {
	d := taking(t)
	d.refresh(t)
	now := time.Date(2026, 11, 12, 9, 0, 0, 0, time.UTC)
	d.l.Now = func() time.Time { now = now.Add(time.Minute); return now }
	take, _ := takeOf(t, d.reconcile(t, pr.Options{Window: 45 * time.Second}))
	is(t, take, pr.ActLeft)
	if got := d.asksFiled(); len(got) != 0 {
		t.Fatalf("a run past its window filed %q", got)
	}
}

// No merge is requested over a post the city has not taken: one the saved read
// holds holds the PR, and so does one only the merge's own read of GitHub
// sees, which the one-PR update's re-read saves before the order decides the
// merge again.
func TestNoMergeOverAnUntakenPost(t *testing.T) {
	merges := func(d *land) []string {
		var out []string
		for _, a := range d.github.Asks() {
			if a.Method == "MergePullRequest" || a.Method == "EnqueuePullRequest" {
				out = append(out, a.Method)
			}
		}
		return out
	}
	t.Run("one the saved read holds", func(t *testing.T) {
		d := newLand(t)
		d.github.Fail["AddReaction"] = errors.New("gh: error connecting to api.github.com")
		d.pr.Comments = []gh.IssueComment{{ID: 700, NodeID: "IC_700", URL: prURL + "#issuecomment-700",
			Author: "operator", Body: "hold on", CreatedAt: "2026-11-12T05:00:00Z"}}
		d.refresh(t)
		take, rest := takeOf(t, d.reconcile(t, pr.Options{}))
		is(t, take, pr.ActRetry)
		if len(rest) != 1 || len(merges(d)) != 0 {
			t.Fatalf("over an untaken post the run reported %+v and asked %v", rest, merges(d))
		}
		says(t, rest[0], "feedback")
	})
	t.Run("one only the merge's own read sees", func(t *testing.T) {
		d := newLand(t)
		d.refresh(t)
		d.github.OnRead = func(method string, p *ghfake.PR) {
			if method == "Conversation" && len(p.Comments) == 0 {
				p.Comments = []gh.IssueComment{{ID: 700, NodeID: "IC_700", URL: prURL + "#issuecomment-700",
					Author: "operator", Body: "wait, one more thing", CreatedAt: "2026-11-12T08:59:00Z"}}
			}
		}
		o := d.run(t)
		rereads(t, d)
		is(t, o, pr.ActChecked)
		says(t, o, "feedback")
		if got := merges(d); len(got) != 0 {
			t.Fatalf("a post only the merge's read saw was merged over: %v", got)
		}
		if got := d.savedConversation(t).Untaken; len(got) != 1 || got[0].ID != 700 {
			t.Fatalf("the re-read saved the untaken posts %+v, want comment 700", got)
		}
	})
}
