package pr_test

import (
	"context"
	"errors"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/quote"
)

// A follow-up is one human gate per outside account on the bead that owns the
// PR: two posts by one account ask for one gate, a login of another shape and
// an account GitHub no longer names share the unnamed key, and a gate that does
// not file is an error naming it while the others are filed.
func TestFollowUpFilesOneGatePerOutsideAccount(t *testing.T) {
	g := &gates{}
	held := []quote.Held{
		{Kind: quote.KindConversation, Author: "Stranger", URL: prURL + "#issuecomment-1"},
		{Kind: quote.KindReview, Author: "Stranger", URL: prURL + "#pullrequestreview-2"},
		{Kind: quote.KindInline, Author: "other-one", URL: prURL + "#discussion_r3"},
		{Kind: quote.KindConversation, Author: "", URL: prURL + "#issuecomment-4"},
		{Kind: quote.KindConversation, Author: "not a login", URL: prURL + "#issuecomment-5"},
	}
	if err := pr.FollowUp(context.Background(), g, "tk-1", "acme/widgets", 7, held); err != nil {
		t.Fatal(err)
	}
	want := []string{"tk-1 outside-post-stranger", "tk-1 outside-post-other-one", "tk-1 outside-post-unnamed"}
	if got := g.list(); !slices.Equal(got, want) {
		t.Fatalf("gates filed %q, want %q", got, want)
	}
	if !strings.Contains(g.messages[0], prURL+"#issuecomment-1") ||
		!strings.HasPrefix(g.messages[2], "Posts by an account GitHub no longer names on acme/widgets#7") {
		t.Fatalf("messages %q", g.messages)
	}
	g = &gates{err: errors.New("human-gate.sh: exit 1")}
	if err := pr.FollowUp(context.Background(), g, "tk-1", "acme/widgets", 7, held[:1]); err == nil ||
		!strings.Contains(err.Error(), "exit 1") {
		t.Fatalf("a gate that did not file read as %v", err)
	}
	if err := pr.FollowUp(context.Background(), nil, "tk-1", "acme/widgets", 7, held[:1]); err == nil {
		t.Fatal("a follow-up with nothing to file gates through read as filed")
	}
}

// marks records each reaction a read's follow-up leaves, failing on the node
// fail names, and answers a read of the held posts again with them as they
// stand: held with each mark that landed among its reactions.
type marks struct {
	mu   sync.Mutex
	held []quote.Held
	left []string
	fail string
}

func (m *marks) AddReaction(subject, content string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if subject == m.fail {
		return errors.New("HTTP 502")
	}
	m.left = append(m.left, subject+" "+content)
	return nil
}

// read is the held posts as GitHub holds them now, each with the marks left on
// it since.
func (m *marks) read() ([]quote.Held, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	now := make([]quote.Held, 0, len(m.held))
	for _, h := range m.held {
		h.Reactions = slices.Clone(h.Reactions)
		for _, l := range m.left {
			if node, content, _ := strings.Cut(l, " "); node == h.Node && !slices.Contains(h.Reactions, content) {
				h.Reactions = append(h.Reactions, content)
			}
		}
		now = append(now, h)
	}
	return now, nil
}

// tk1 names tk-1 as the bead a follow-up goes on.
func tk1() (string, error) { return "tk-1", nil }

// followUpHeld is pr.FollowUpHeld on PR #7 of acme/widgets for tk-1, under a
// record lock of the test's own, reading the posts again through m.
func followUpHeld(t *testing.T, dir string, g pr.Gates, m *marks, held []quote.Held) error {
	t.Helper()
	m.mu.Lock()
	if m.held == nil {
		m.held = held
	}
	m.mu.Unlock()
	_, err := pr.FollowUpHeld(context.Background(), dir, time.Minute, g, m, m.read, tk1, "acme/widgets", 7, true, held)
	return err
}

// A read's follow-up files nothing for a post the city already marked taken or
// handled, files one gate per account for the rest, and marks each of their
// posts with EYES once its account's gate filed, so a later read after the
// operator clears the gate files nothing for them. A post whose gate did not
// file is not marked, and a mark that did not land is an error naming it.
func TestFollowUpHeldSkipsMarkedPostsAndMarksTheRest(t *testing.T) {
	dir := t.TempDir()
	g, m := &gates{}, &marks{}
	held := []quote.Held{
		{Kind: quote.KindConversation, Author: "stranger", URL: prURL + "#issuecomment-1", Node: "IC_1"},
		{Kind: quote.KindReview, Author: "stranger", URL: prURL + "#pullrequestreview-2", Node: "PRR_2"},
		{Kind: quote.KindInline, Author: "other", URL: prURL + "#discussion_r3", Node: "PRRC_3",
			Reactions: []string{"EYES"}},
		{Kind: quote.KindConversation, Author: "third", URL: prURL + "#issuecomment-4", Node: "IC_4",
			Reactions: []string{"HEART", "THUMBS_UP"}},
	}
	if got := len(pr.Owed(held)); got != 2 {
		t.Fatalf("owed %d posts, want 2", got)
	}
	if err := followUpHeld(t, dir, g, m, held); err != nil {
		t.Fatal(err)
	}
	if got := g.list(); !slices.Equal(got, []string{"tk-1 outside-post-stranger"}) {
		t.Fatalf("gates filed %q", got)
	}
	if !strings.Contains(g.messages[0], prURL+"#issuecomment-1") {
		t.Fatalf("the gate names %q", g.messages[0])
	}
	if !slices.Equal(m.left, []string{"IC_1 EYES", "PRR_2 EYES"}) {
		t.Fatalf("marks left %q", m.left)
	}
	g, m = &gates{err: errors.New("human-gate.sh: exit 1")}, &marks{}
	if err := followUpHeld(t, dir, g, m, held[:1]); err == nil || len(m.left) != 0 {
		t.Fatalf("a gate that did not file read as %v, and left marks %q", err, m.left)
	}
	g, m = &gates{}, &marks{fail: "PRR_2"}
	if err := followUpHeld(t, dir, g, m, held[:2]); err == nil ||
		!strings.Contains(err.Error(), "pullrequestreview-2") || !slices.Equal(m.left, []string{"IC_1 EYES"}) {
		t.Fatalf("a mark that did not land read as %v, with marks %q", err, m.left)
	}
	if _, err := pr.FollowUpHeld(context.Background(), dir, time.Minute, g, nil, m.read, tk1, "acme/widgets", 7, true,
		held[:1]); err == nil {
		t.Fatal("a follow-up with nothing to mark posts through read as filed")
	}
}

// A read decides on each post as GitHub holds it once it has the record lock,
// not as the quote it printed saw it: a post another filer followed up since
// carries the city's EYES and files nothing, one deleted since, or no longer
// held, files nothing, and a read again that fails files nothing and says so.
func TestFollowUpHeldDecidesOnThePostsAsTheyStand(t *testing.T) {
	dir := t.TempDir()
	held := []quote.Held{
		{Kind: quote.KindConversation, Author: "stranger", URL: prURL + "#issuecomment-1", Node: "IC_1"},
		{Kind: quote.KindConversation, Author: "gone", URL: prURL + "#issuecomment-2", Node: "IC_2"},
	}
	g, m := &gates{}, &marks{held: []quote.Held{{Kind: quote.KindConversation, Author: "stranger",
		URL: prURL + "#issuecomment-1", Node: "IC_1", Reactions: []string{"EYES"}}}}
	if err := followUpHeld(t, dir, g, m, held); err != nil {
		t.Fatal(err)
	}
	if len(g.list()) != 0 || len(m.left) != 0 {
		t.Fatalf("filed %q and marked %q for posts already followed up or gone", g.list(), m.left)
	}
	failing := func() ([]quote.Held, error) { return nil, errors.New("gh: HTTP 502") }
	if _, err := pr.FollowUpHeld(context.Background(), dir, time.Minute, g, m, failing, tk1, "acme/widgets", 7, true,
		held); err == nil || !strings.Contains(err.Error(), "did not read the posts again") || len(g.list()) != 0 {
		t.Fatalf("a read again that failed read as %v, filing %q", err, g.list())
	}
}

// racing files a gate as human-gate.sh does, which reads the bead's open gates
// and then files one, with a window between the two in which another filer
// can read the same nothing.
type racing struct {
	mu    sync.Mutex
	open  map[string]bool
	filed []string
}

func (r *racing) File(_ context.Context, subject, key, _ string) error {
	r.mu.Lock()
	open := r.open[subject+" "+key]
	r.mu.Unlock()
	if open {
		return nil
	}
	time.Sleep(100 * time.Millisecond)
	r.mu.Lock()
	defer r.mu.Unlock()
	r.open[subject+" "+key] = true
	r.filed = append(r.filed, subject+" "+key)
	return nil
}

func (r *racing) Withdraw(context.Context, string, string, string) error { return nil }

// Two reads of one PR at once, each holding an outside account's post its
// quote saw unmarked, file one gate between them: each decides and files under
// the store's record lock, so the second finds the post marked by the first.
func TestFollowUpHeldFilesOneGateForReadsAtOnce(t *testing.T) {
	dir := t.TempDir()
	held := []quote.Held{{Kind: quote.KindConversation, Author: "stranger", URL: prURL + "#issuecomment-1",
		Node: "IC_1"}}
	g, m := &racing{open: map[string]bool{}}, &marks{held: held}
	start := make(chan struct{})
	errs := make(chan error, 2)
	var wg sync.WaitGroup
	for range 2 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			<-start
			_, err := pr.FollowUpHeld(context.Background(), dir, time.Minute, g, m, m.read, tk1, "acme/widgets", 7,
				true, held)
			errs <- err
		}()
	}
	close(start)
	wg.Wait()
	close(errs)
	for err := range errs {
		if err != nil {
			t.Fatal(err)
		}
	}
	if !slices.Equal(g.filed, []string{"tk-1 outside-post-stranger"}) {
		t.Fatalf("two reads at once filed %q, want one gate", g.filed)
	}
}

// A follow-up lands on the bead that owns the PR: the live one, else a closed
// anchor that named it in pr_url and is no other bead's child, and nowhere when
// the store holds neither.
func TestOwnerOfIsTheLiveOwnerElseAClosedAnchor(t *testing.T) {
	d := newLand(t)
	if got, err := pr.OwnerOf(d.l.Ledger, prURL); err != nil || got != bead {
		t.Fatalf("the live owner read as %q, %v", got, err)
	}
	other := "https://github.com/acme/widgets/pull/99"
	if got, err := pr.OwnerOf(d.l.Ledger, other); err != nil || got != "" {
		t.Fatalf("a PR no bead owns read as %q, %v", got, err)
	}
	d.store.Put(fake.Bead{ID: "tk-child", Status: "closed", IssueType: "task",
		Metadata: map[string]string{"pr_url": other, "anchor_bead": "tk-root"}})
	d.store.Put(fake.Bead{ID: "tk-root", Status: "closed", IssueType: "task",
		Metadata: map[string]string{"pr_url": other, "merge_result": "merged"}})
	if got, err := pr.OwnerOf(d.l.Ledger, other); err != nil || got != "tk-root" {
		t.Fatalf("the closed anchor read as %q, %v", got, err)
	}
	if _, err := pr.OwnerOf(ledger.New(d.store), "not a url"); err == nil {
		t.Fatal("a URL that names no PR read as owned")
	}
}

// findings records each finding a follow-up files, answering it with id, or
// failing it with err.
type findings struct {
	filed []string
	id    string
	err   error
}

func (f *findings) File(_ context.Context, key, title, message string) (string, error) {
	f.filed = append(f.filed, key+" "+title+"\n"+message)
	return f.id, f.err
}

// A follow-up goes on the bead that owns the PR. An issue, which no bead owns,
// and a PR no bead owns get a finding of their own for the item, one under the
// item's key, so no held post goes without a question.
func TestFollowUpSubjectIsTheOwnerElseAFindingOfItsOwn(t *testing.T) {
	d := newLand(t)
	f := &findings{id: "tk-f1"}
	if got, err := pr.FollowUpSubject(context.Background(), d.l.Ledger, f, "acme/widgets", 7, true, prURL); err != nil ||
		got != bead || len(f.filed) != 0 {
		t.Fatalf("the owned PR's follow-up goes on %q, %v, filing %q", got, err, f.filed)
	}
	other := "https://github.com/acme/widgets/pull/99"
	if got, err := pr.FollowUpSubject(context.Background(), d.l.Ledger, f, "acme/widgets", 99, true, other); err != nil ||
		got != "tk-f1" || len(f.filed) != 1 || !strings.HasPrefix(f.filed[0], "outside-posts.acme.widgets.99 Posts by "+
		"outside accounts on acme/widgets#99 are held from the city's agents\n") ||
		!strings.Contains(f.filed[0], "no bead owns the PR") {
		t.Fatalf("a PR no bead owns goes on %q, %v, filing %q", got, err, f.filed)
	}
	issue := "https://github.com/acme/widgets/issues/5"
	if got, err := pr.FollowUpSubject(context.Background(), d.l.Ledger, f, "acme/widgets", 5, false, issue); err != nil ||
		got != "tk-f1" || len(f.filed) != 2 || !strings.HasPrefix(f.filed[1], "outside-posts.acme.widgets.5 ") ||
		!strings.Contains(f.filed[1], "no bead owns the issue") {
		t.Fatalf("an issue goes on %q, %v, filing %q", got, err, f.filed)
	}
	f = &findings{err: errors.New("patrol-finding.sh: exit 1")}
	if _, err := pr.FollowUpSubject(context.Background(), d.l.Ledger, f, "acme/widgets", 5, false, issue); err == nil {
		t.Fatal("a finding that did not file read as a bead")
	}
}

// A read files no finding while every post it held was followed up by another
// filer: it asks for the bead only once a post is owed one under the lock, and
// a bead it cannot name files nothing and says so. On an issue the gate's
// message names the issue.
func TestFollowUpHeldNamesItsBeadOnlyWhenAPostIsOwed(t *testing.T) {
	dir := t.TempDir()
	held := []quote.Held{{Kind: quote.KindConversation, Author: "stranger",
		URL: "https://github.com/acme/widgets/issues/5#issuecomment-1", Node: "IC_1"}}
	asked := 0
	subject := func() (string, error) { asked++; return "tk-f1", nil }
	g, m := &gates{}, &marks{held: []quote.Held{{Kind: quote.KindConversation, Author: "stranger",
		URL: held[0].URL, Node: "IC_1", Reactions: []string{"EYES"}}}}
	if got, err := pr.FollowUpHeld(context.Background(), dir, time.Minute, g, m, m.read, subject, "acme/widgets", 5,
		false, held); err != nil || got != "" || asked != 0 || len(g.list()) != 0 {
		t.Fatalf("a post followed up since went on %q, %v, asking for its bead %d times and filing %q",
			got, err, asked, g.list())
	}
	m = &marks{held: held}
	if got, err := pr.FollowUpHeld(context.Background(), dir, time.Minute, g, m, m.read, subject, "acme/widgets", 5,
		false, held); err != nil || got != "tk-f1" || asked != 1 ||
		!slices.Equal(g.list(), []string{"tk-f1 outside-post-stranger"}) {
		t.Fatalf("an owed post went on %q, %v, asking %d times and filing %q", got, err, asked, g.list())
	}
	if msg := g.messages[0]; !strings.Contains(msg, "its posts on issue #5") || !strings.Contains(msg, "on the issue.") {
		t.Fatalf("the issue's gate reads %q", msg)
	}
	nobody := func() (string, error) { return "", nil }
	g, m = &gates{}, &marks{held: held}
	if _, err := pr.FollowUpHeld(context.Background(), dir, time.Minute, g, m, m.read, nobody, "acme/widgets", 5,
		false, held); err == nil || len(g.list()) != 0 || len(m.left) != 0 {
		t.Fatalf("a follow-up with no bead read as %v, filing %q and marking %q", err, g.list(), m.left)
	}
}
