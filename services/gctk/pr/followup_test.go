package pr_test

import (
	"context"
	"errors"
	"slices"
	"strings"
	"testing"

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
// fail names.
type marks struct {
	left []string
	fail string
}

func (m *marks) AddReaction(subject, content string) error {
	if subject == m.fail {
		return errors.New("HTTP 502")
	}
	m.left = append(m.left, subject+" "+content)
	return nil
}

// A read's follow-up files nothing for a post the city already marked taken or
// handled, files one gate per account for the rest, and marks each of their
// posts with EYES once its account's gate filed, so a later read after the
// operator clears the gate files nothing for them. A post whose gate did not
// file is not marked, and a mark that did not land is an error naming it.
func TestFollowUpHeldSkipsMarkedPostsAndMarksTheRest(t *testing.T) {
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
	if err := pr.FollowUpHeld(context.Background(), g, m, "tk-1", "acme/widgets", 7, held); err != nil {
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
	if err := pr.FollowUpHeld(context.Background(), g, m, "tk-1", "acme/widgets", 7, held[:1]); err == nil ||
		len(m.left) != 0 {
		t.Fatalf("a gate that did not file read as %v, and left marks %q", err, m.left)
	}
	g, m = &gates{}, &marks{fail: "PRR_2"}
	if err := pr.FollowUpHeld(context.Background(), g, m, "tk-1", "acme/widgets", 7, held[:2]); err == nil ||
		!strings.Contains(err.Error(), "pullrequestreview-2") || !slices.Equal(m.left, []string{"IC_1 EYES"}) {
		t.Fatalf("a mark that did not land read as %v, with marks %q", err, m.left)
	}
	if err := pr.FollowUpHeld(context.Background(), g, nil, "tk-1", "acme/widgets", 7, held[:1]); err == nil {
		t.Fatal("a follow-up with nothing to mark posts through read as filed")
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
