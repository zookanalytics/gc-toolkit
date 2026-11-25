package gh_test

import (
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
)

// The read of a PR's title and body asks for them beside the PR's own facts,
// and returns them as GitHub has them.
func TestAPullRequestsText(t *testing.T) {
	c, r := client([2]string{"title body}}}", `{"data":{"repository":{"pullRequest":{
		"id":"PR_kw1","number":7,"url":"https://github.com/acme/widgets/pull/7","state":"OPEN","isDraft":true,
		"headRefName":"polecat/tk-1","headRefOid":"abc","baseRefName":"main","mergeStateStatus":"CLEAN",
		"repository":{"nameWithOwner":"acme/widgets"},"mergedAt":null,"mergeCommit":null,
		"isInMergeQueue":false,"isMergeQueueEnabled":false,
		"title":"feat: the work (tk-1)","body":"<!-- gc:summary -->\r\n## Summary\n\nIt does the work."}}}}`})
	got, err := c.PullRequestText("acme/widgets", 7)
	if err != nil {
		t.Fatal(err)
	}
	want := gh.Text{PullRequest: gh.PullRequest{ID: "PR_kw1", Number: 7, URL: "https://github.com/acme/widgets/pull/7",
		State: "OPEN", IsDraft: true, HeadRefName: "polecat/tk-1", HeadRefOid: "abc", BaseRefName: "main",
		MergeStateStatus: "CLEAN", Repository: "acme/widgets"},
		Title: "feat: the work (tk-1)", Body: "<!-- gc:summary -->\r\n## Summary\n\nIt does the work."}
	if *got != want {
		t.Fatalf("got %+v, want %+v", *got, want)
	}
	args := strings.Join(r.calls[0].args, " ")
	for _, want := range []string{"api --hostname github.com graphql", "-f owner=acme", "-f name=widgets", "-F number=7"} {
		if !strings.Contains(args, want) {
			t.Errorf("the read asks %q without %q", args, want)
		}
	}
	c, _ = client([2]string{"title body", `{"data":{"repository":{"pullRequest":null}}}`})
	if _, err := c.PullRequestText("acme/widgets", 7); err == nil {
		t.Fatal("read the text of a PR the repository does not hold")
	}
}

// An edit names the PR by its node id and sets each of the title and the body
// it is given, as raw strings, and nothing it is not given, so GitHub leaves
// that one as it stands. An edit that sets nothing, or names no PR, is never
// sent, and one GitHub refuses is an error.
func TestAnEditSetsWhatItIsGivenAndNothingElse(t *testing.T) {
	title, body := "fix: the work (tk-1)", "@notes.md\n## Summary"
	for _, tc := range []struct {
		name        string
		title, body *string
		has, hasnt  []string
	}{
		{"both", &title, &body,
			[]string{"updatePullRequest(input:{pullRequestId:$id,title:$title,body:$body})", "-f title=" + title, "-f body=" + body}, nil},
		{"the title", &title, nil,
			[]string{"updatePullRequest(input:{pullRequestId:$id,title:$title})", "-f title=" + title}, []string{"body"}},
		{"the body", nil, &body,
			[]string{"updatePullRequest(input:{pullRequestId:$id,body:$body})", "-f body=" + body}, []string{"title"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			c, r := client([2]string{"updatePullRequest", `{"data":{"updatePullRequest":{"pullRequest":{"id":"PR_kw1"}}}}`})
			if err := c.EditPullRequest("PR_kw1", tc.title, tc.body); err != nil {
				t.Fatal(err)
			}
			args := r.calls[0].args
			joined := strings.Join(args, " ")
			for _, want := range append(tc.has, "api --hostname github.com graphql", "-f id=PR_kw1") {
				if !strings.Contains(joined, want) {
					t.Errorf("the edit %q lacks %q", joined, want)
				}
			}
			for _, not := range tc.hasnt {
				if slices.ContainsFunc(args, func(a string) bool { return strings.HasPrefix(a, not+"=") }) {
					t.Errorf("the edit %q sets %s, which it was not given", joined, not)
				}
			}
			if slices.Contains(args, "-F") {
				t.Errorf("the edit %q sends a field gh reads as typed, where a body that opens with @ names a file", joined)
			}
		})
	}
	c, r := client()
	if err := c.EditPullRequest("PR_kw1", nil, nil); err == nil || len(r.calls) != 0 {
		t.Fatalf("an edit that sets nothing read as %v, with calls %v", err, r.calls)
	}
	if err := c.EditPullRequest("", &title, nil); err == nil || len(r.calls) != 0 {
		t.Fatalf("an edit that names no PR read as %v, with calls %v", err, r.calls)
	}
	c, _ = client([2]string{"updatePullRequest", `{"data":null,"errors":[{"message":"Resource not accessible by integration"}]}`})
	if err := c.EditPullRequest("PR_kw1", &title, nil); err == nil || !strings.Contains(err.Error(), "Resource not accessible") {
		t.Fatalf("a refused edit read as %v", err)
	}
}
