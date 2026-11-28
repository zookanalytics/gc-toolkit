package pr_test

import (
	"context"
	"errors"
	"slices"
	"strings"
	"testing"

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
