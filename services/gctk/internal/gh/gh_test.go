package gh_test

import (
	"errors"
	"reflect"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
)

// Each read is driven through a recorded answer, keyed by the query or the
// path it asks, so the tests pin what each read asks GitHub and what it makes
// of the answer.

type call struct{ args []string }

// recorded answers each call with the first answer whose key the call's
// arguments contain, and records the calls.
type recorded struct {
	answers [][2]string
	calls   []call
}

func (r *recorded) run(args ...string) ([]byte, error) {
	r.calls = append(r.calls, call{args})
	joined := strings.Join(args, "\x00")
	for _, a := range r.answers {
		if strings.Contains(joined, a[0]) {
			if strings.HasPrefix(a[1], "ERR:") {
				return nil, errors.New(strings.TrimPrefix(a[1], "ERR:"))
			}
			return []byte(a[1]), nil
		}
	}
	return nil, errors.New("no recorded answer")
}

func client(answers ...[2]string) (*gh.Client, *recorded) {
	r := &recorded{answers: answers}
	return gh.NewWithRunner("github.com", r.run), r
}

func TestPullRequest(t *testing.T) {
	c, r := client([2]string{"pullRequest(number:$number){\n    id number", `{"data":{"repository":{"pullRequest":{
		"id":"PR_kw1","number":7,"url":"https://github.com/acme/widgets/pull/7","state":"OPEN","isDraft":false,
		"headRefName":"polecat/tk-1","headRefOid":"abc","baseRefName":"main","mergeStateStatus":"CLEAN",
		"repository":{"nameWithOwner":"acme/widgets"},"mergedAt":null,"mergeCommit":null,
		"isInMergeQueue":true,"isMergeQueueEnabled":true}}}}`})
	p, err := c.PullRequest("acme/widgets", 7)
	if err != nil {
		t.Fatal(err)
	}
	want := gh.PullRequest{ID: "PR_kw1", Number: 7, URL: "https://github.com/acme/widgets/pull/7", State: "OPEN",
		HeadRefName: "polecat/tk-1", HeadRefOid: "abc", BaseRefName: "main", MergeStateStatus: "CLEAN",
		Repository: "acme/widgets", InMergeQueue: true, MergeQueueEnabled: true}
	if *p != want {
		t.Fatalf("got %+v, want %+v", *p, want)
	}
	args := strings.Join(r.calls[0].args, " ")
	for _, want := range []string{"api --hostname github.com graphql", "-f owner=acme", "-f name=widgets", "-F number=7"} {
		if !strings.Contains(args, want) {
			t.Errorf("the read asks %q without %q", args, want)
		}
	}
	if strings.Contains(args, "--paginate") {
		t.Errorf("a read of one PR pages nothing: %q", args)
	}
}

func TestAMergedPullRequestNamesItsMergeCommit(t *testing.T) {
	c, _ := client([2]string{"pullRequest(number:$number)", `{"data":{"repository":{"pullRequest":{
		"id":"PR_kw1","number":7,"url":"https://github.com/acme/widgets/pull/7","state":"MERGED","isDraft":false,
		"headRefName":"polecat/tk-1","headRefOid":"abc","baseRefName":"main","mergeStateStatus":"UNKNOWN",
		"repository":{"nameWithOwner":"acme/widgets"},"mergedAt":"2026-11-12T08:00:00Z","mergeCommit":{"oid":"def"},
		"isInMergeQueue":false,"isMergeQueueEnabled":false}}}}`})
	p, err := c.PullRequest("acme/widgets", 7)
	if err != nil {
		t.Fatal(err)
	}
	if p.State != "MERGED" || p.MergeCommit != "def" || p.MergedAt != "2026-11-12T08:00:00Z" {
		t.Fatalf("a merged PR read as %+v", *p)
	}
}

// A merge request and an enqueue each name the PR by its node id and pin the
// request to the head the caller judged, so GitHub refuses either once a push
// has moved the head.
func TestAMergeRequestIsPinnedToTheHeadItNames(t *testing.T) {
	for _, tc := range []struct {
		name, mutation string
		do             func(*gh.Client) error
	}{
		{"merge", "mergePullRequest(input:{pullRequestId:$id,expectedHeadOid:$head,mergeMethod:SQUASH})",
			func(c *gh.Client) error { return c.MergePullRequest("PR_kw1", "abc") }},
		{"enqueue", "enqueuePullRequest(input:{pullRequestId:$id,expectedHeadOid:$head})",
			func(c *gh.Client) error { return c.EnqueuePullRequest("PR_kw1", "abc") }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			c, r := client([2]string{tc.mutation, `{"data":{"x":{}}}`})
			if err := tc.do(c); err != nil {
				t.Fatal(err)
			}
			args := strings.Join(r.calls[0].args, " ")
			for _, want := range []string{"api --hostname github.com graphql", "-f id=PR_kw1", "-f head=abc"} {
				if !strings.Contains(args, want) {
					t.Errorf("the request %q lacks %q", args, want)
				}
			}
		})
	}
}

func TestAMergeRequestGitHubRefusesIsAnError(t *testing.T) {
	c, _ := client([2]string{"mergePullRequest", `{"data":null,"errors":[{"message":"Head branch was modified. Review and try the merge again."}]}`})
	if err := c.MergePullRequest("PR_kw1", "abc"); err == nil || !strings.Contains(err.Error(), "Head branch was modified") {
		t.Fatalf("a refused merge request read as %v", err)
	}
	c, _ = client()
	if err := c.MergePullRequest("", "abc"); err == nil {
		t.Fatal("a merge request that names no PR was sent")
	}
}

func TestAPullRequestTheRepositoryDoesNotHoldIsAnError(t *testing.T) {
	c, _ := client([2]string{"pullRequest", `{"data":{"repository":{"pullRequest":null}}}`})
	if _, err := c.PullRequest("acme/widgets", 7); err == nil {
		t.Fatal("read a PR the repository does not hold")
	}
}

func TestReviewsArePagedToTheirEnd(t *testing.T) {
	page := func(id, state, login string, push bool, next bool) string {
		p := "false"
		if push {
			p = "true"
		}
		n := "false"
		if next {
			n = "true"
		}
		return `{"data":{"repository":{"pullRequest":{"reviews":{"pageInfo":{"hasNextPage":` + n + `,"endCursor":"c"},
			"nodes":[{"fullDatabaseId":"` + id + `","state":"` + state + `","body":"b","submittedAt":"2026-11-12T01:00:00Z",
			"authorCanPushToRepository":` + p + `,"author":{"login":"` + login + `"}}]}}}}}`
	}
	c, r := client([2]string{"reviews(first:100", page("5839141068", "APPROVED", "operator", true, true) + "\n" +
		page("5839141069", "CHANGES_REQUESTED", "visitor", false, false)})
	got, err := c.Reviews("acme/widgets", 7)
	if err != nil {
		t.Fatal(err)
	}
	want := []gh.Review{
		{ID: 5839141068, State: "APPROVED", Body: "b", SubmittedAt: "2026-11-12T01:00:00Z", Author: "operator", AuthorCanPush: true},
		{ID: 5839141069, State: "CHANGES_REQUESTED", Body: "b", SubmittedAt: "2026-11-12T01:00:00Z", Author: "visitor"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %+v, want %+v", got, want)
	}
	if args := strings.Join(r.calls[0].args, " "); !strings.Contains(args, "--paginate") || !strings.Contains(args, "authorCanPushToRepository") {
		t.Fatalf("the read %q does not page the reviews or ask whether each author can push", args)
	}
}

func TestCheckSuitesReadTheLatestResultOfEachRequiredRun(t *testing.T) {
	c, r := client([2]string{"checkSuites(first:100", `{"data":{"repository":{"object":{"checkSuites":{
		"pageInfo":{"hasNextPage":false,"endCursor":"c"},"nodes":[{"databaseId":116886735833,"checkRuns":{
		"pageInfo":{"hasNextPage":false},"nodes":[
		{"name":"test","status":"COMPLETED","conclusion":"SKIPPED","isRequired":true},
		{"name":"go","status":"IN_PROGRESS","conclusion":null,"isRequired":false}]}}]}}}}}`})
	got, err := c.CheckSuites("acme/widgets", "abc", 7)
	if err != nil {
		t.Fatal(err)
	}
	want := []gh.CheckSuite{{ID: 116886735833, Runs: []gh.CheckRun{
		{Name: "test", Status: "COMPLETED", Conclusion: "SKIPPED", Required: true},
		{Name: "go", Status: "IN_PROGRESS"},
	}}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %+v, want %+v", got, want)
	}
	args := strings.Join(r.calls[0].args, " ")
	for _, want := range []string{"filterBy:{checkType:LATEST}", "isRequired(pullRequestNumber:$number)", "object(oid:$oid)", "-f oid=abc", "--paginate"} {
		if !strings.Contains(args, want) {
			t.Errorf("the read %q does not ask %q", args, want)
		}
	}
}

func TestASuiteWithMoreRunsThanAPageIsAnError(t *testing.T) {
	c, _ := client([2]string{"checkSuites", `{"data":{"repository":{"object":{"checkSuites":{
		"pageInfo":{"hasNextPage":false,"endCursor":"c"},"nodes":[{"databaseId":1,"checkRuns":{
		"pageInfo":{"hasNextPage":true},"nodes":[]}}]}}}}}`})
	if _, err := c.CheckSuites("acme/widgets", "abc", 7); err == nil {
		t.Fatal("read a suite whose check runs were cut short")
	}
}

func TestReviewThreadsReadALongThreadToItsEnd(t *testing.T) {
	node := func(id string, react bool) string {
		g := "false"
		if react {
			g = "true"
		}
		return `{"fullDatabaseId":"` + id + `","author":{"login":"operator"},"body":"b","createdAt":"2026-11-12T01:00:00Z",
			"pullRequestReview":{"fullDatabaseId":"900","submittedAt":"2026-11-12T01:00:01Z","state":"COMMENTED"},
			"reactionGroups":[{"content":"THUMBS_UP","viewerHasReacted":` + g + `},{"content":"EYES","viewerHasReacted":false}]}`
	}
	c, r := client(
		[2]string{"node(id:$id)", `{"data":{"node":{"comments":{"pageInfo":{"hasNextPage":false,"endCursor":"c"},"nodes":[` +
			node("1", false) + `,` + node("2", true) + `]}}}}`},
		[2]string{"reviewThreads(first:100", `{"data":{"repository":{"pullRequest":{"reviewThreads":{
			"pageInfo":{"hasNextPage":false,"endCursor":"c"},"nodes":[
			{"id":"T1","isResolved":false,"comments":{"pageInfo":{"hasNextPage":true},"nodes":[` + node("1", false) + `]}},
			{"id":"T2","isResolved":true,"comments":{"pageInfo":{"hasNextPage":false},"nodes":[` + node("3", false) + `]}}]}}}}}`},
	)
	got, err := c.ReviewThreads("acme/widgets", 7)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 || len(got[0].Comments) != 2 || len(got[1].Comments) != 1 {
		t.Fatalf("got %+v, want T1 read whole with 2 comments and T2 with 1", got)
	}
	c2 := got[0].Comments[1]
	want := gh.Comment{ID: 2, Author: "operator", Body: "b", CreatedAt: "2026-11-12T01:00:00Z",
		Review:          &gh.CommentReview{ID: 900, State: "COMMENTED", SubmittedAt: "2026-11-12T01:00:01Z"},
		ViewerReactions: []string{"THUMBS_UP"}}
	if !reflect.DeepEqual(c2, want) {
		t.Fatalf("got %+v, want %+v", c2, want)
	}
	if !got[1].Resolved || got[0].Resolved {
		t.Fatalf("resolved flags %v %v, want false true", got[0].Resolved, got[1].Resolved)
	}
	if len(r.calls) != 2 || !strings.Contains(strings.Join(r.calls[1].args, " "), "-f id=T1") {
		t.Fatalf("calls %+v, want the long thread T1 read again on its own", r.calls)
	}
}

func TestIssueComments(t *testing.T) {
	c, _ := client([2]string{"comments(first:100", `{"data":{"repository":{"pullRequest":{"comments":{
		"pageInfo":{"hasNextPage":false,"endCursor":"c"},"nodes":[
		{"fullDatabaseId":"6763031671","body":"b","createdAt":"2026-11-10T08:47:09Z","author":null}]}}}}}`})
	got, err := c.IssueComments("acme/widgets", 7)
	if err != nil {
		t.Fatal(err)
	}
	want := []gh.IssueComment{{ID: 6763031671, Body: "b", CreatedAt: "2026-11-10T08:47:09Z"}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %+v, want %+v", got, want)
	}
}

func TestLogin(t *testing.T) {
	c, r := client([2]string{"user", `{"login":"zook-bot","id":1}`})
	got, err := c.Login()
	if err != nil || got != "zook-bot" {
		t.Fatalf("got %q, %v, want zook-bot", got, err)
	}
	if args := strings.Join(r.calls[0].args, " "); args != "api --hostname github.com user" {
		t.Fatalf("the read asks %q", args)
	}
	c, _ = client([2]string{"user", `{"message":"Bad credentials"}`})
	if _, err := c.Login(); err == nil {
		t.Fatal("read a login from an answer that names none")
	}
}

func TestAnAnswerThatIsNotWholeIsAnError(t *testing.T) {
	cases := map[string]string{
		"a GraphQL error":           `{"data":null,"errors":[{"message":"Something went wrong"}]}`,
		"no page":                   ``,
		"a page that is not JSON":   `{"data":`,
		"an id that is not numeric": `{"data":{"repository":{"pullRequest":{"reviews":{"pageInfo":{"hasNextPage":false},"nodes":[{"fullDatabaseId":"x","state":"APPROVED"}]}}}}}`,
		"gh's own failure":          `ERR:gh: HTTP 502`,
	}
	for name, answer := range cases {
		t.Run(name, func(t *testing.T) {
			c, _ := client([2]string{"reviews", answer})
			if _, err := c.Reviews("acme/widgets", 7); err == nil {
				t.Fatal("read reviews from an answer that is not whole")
			}
		})
	}
	t.Run("a repository named with no owner", func(t *testing.T) {
		c, r := client()
		if _, err := c.Reviews("widgets", 7); err == nil || len(r.calls) > 0 {
			t.Fatalf("err=%v calls=%d: read a repository with no owner", err, len(r.calls))
		}
	})
}
