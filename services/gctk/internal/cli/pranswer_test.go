package cli

import (
	"bytes"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	gcfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
)

// The round's posts go through pr-post.sh, each with the call its verb takes,
// and a call that does not exit 0 is an error that names it.
func TestTheRoundsPostsGoThroughPrPost(t *testing.T) {
	rt := &gcfake.Runtime{OnScript: func(c gcfake.Call) gascity.Result {
		if c.Args[0] == "reply" {
			return gascity.Result{Code: 1, Output: "gh: the thread is locked"}
		}
		return gascity.Result{}
	}}
	p := prPosts{rt: rt}
	if err := p.Comment("github.com", "acme/widgets", 7, "the body"); err != nil {
		t.Fatal(err)
	}
	if err := p.Edit("github.com", "acme/widgets", 42, "the body"); err != nil {
		t.Fatal(err)
	}
	if err := p.Reply("github.com", "PRRT_1", "the body"); err == nil || !strings.Contains(err.Error(), "pr-post.sh reply") ||
		!strings.Contains(err.Error(), "the thread is locked") {
		t.Fatalf("a reply that did not land returned %v", err)
	}
	want := [][]string{
		{"comment", "--repo", "github.com/acme/widgets", "--pr", "7", "--body", "the body"},
		{"edit", "--repo", "github.com/acme/widgets", "--comment", "42", "--body", "the body"},
		{"reply", "--host", "github.com", "--thread", "PRRT_1", "--body", "the body"},
	}
	calls := rt.Scripts()
	if len(calls) != len(want) {
		t.Fatalf("the posts ran %+v", calls)
	}
	for i, c := range calls {
		if c.Name != "pr-post.sh" || !slices.Equal(c.Args, want[i]) {
			t.Errorf("post %d ran %s %q, want pr-post.sh %q", i, c.Name, c.Args, want[i])
		}
	}
}

// The command refuses what is no round to post, a bead that is no review run
// and a run whose iteration has no rulings yet, with exit 3, and a call that
// names no run is a usage error, 64, which review-run.sh passes on as its own.
func TestTheRoundsPostRefusesWhatIsNoRoundToPost(t *testing.T) {
	s := fake.New()
	s.Put(fake.Bead{ID: "tk-x", Status: "open", IssueType: "task"})
	s.Put(fake.Bead{ID: "tk-run", Status: "open", IssueType: "task", Metadata: map[string]string{
		"gc.kind": "workflow", "gc.var.pr_bead": "tk-pr", "gc.var.head": runHead, "gc.var.target": "main"}})
	l := pr.Landing{Ledger: ledger.New(s)}
	for run, why := range map[string]string{"tk-x": "is not a review run", "tk-run": "has no rulings yet"} {
		var out, errb bytes.Buffer
		if code := prAnswer(l, run, 0, &out, &errb); code != 3 || !strings.Contains(errb.String(), why) {
			t.Errorf("the post of %s = exit %d: %s%s; want 3, saying it %s", run, code, out.String(), errb.String(), why)
		}
	}
	if code, _, _ := runGctk(t, "pr", "answer"); code != 64 {
		t.Errorf("a call that names no run exits %d, want 64", code)
	}
}
