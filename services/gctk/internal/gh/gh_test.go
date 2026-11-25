package gh_test

import (
	"errors"
	"reflect"
	"slices"
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
			// A GraphQL answer that carries errors: gh writes it to stdout and
			// exits non-zero.
			if body, ok := strings.CutPrefix(a[1], "PARTIAL:"); ok {
				return []byte(body), errors.New("gh: exit status 1")
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
// has moved the head. The merge names its commit's headline, and an enqueue,
// which takes none, names none.
func TestAMergeRequestIsPinnedToTheHeadItNames(t *testing.T) {
	const headline = "fix: name the work (tk-1) (#7)"
	for _, tc := range []struct {
		name, mutation string
		do             func(*gh.Client) error
		headline       bool
	}{
		{"merge", "mergePullRequest(input:{pullRequestId:$id,expectedHeadOid:$head,mergeMethod:SQUASH,commitHeadline:$headline})",
			func(c *gh.Client) error { return c.MergePullRequest("PR_kw1", "abc", headline) }, true},
		{"enqueue", "enqueuePullRequest(input:{pullRequestId:$id,expectedHeadOid:$head})",
			func(c *gh.Client) error { return c.EnqueuePullRequest("PR_kw1", "abc") }, false},
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
			if named := slices.Contains(r.calls[0].args, "headline="+headline); named != tc.headline {
				t.Errorf("the request %q names the headline %t, want %t", args, named, tc.headline)
			}
		})
	}
}

func TestAMergeRequestGitHubRefusesIsAnError(t *testing.T) {
	c, _ := client([2]string{"mergePullRequest", `{"data":null,"errors":[{"message":"Head branch was modified. Review and try the merge again."}]}`})
	if err := c.MergePullRequest("PR_kw1", "abc", "fix: name the work (tk-1) (#7)"); err == nil || !strings.Contains(err.Error(), "Head branch was modified") {
		t.Fatalf("a refused merge request read as %v", err)
	}
	c, r := client()
	if err := c.MergePullRequest("", "abc", "fix: name the work (tk-1) (#7)"); err == nil {
		t.Fatal("a merge request that names no PR was sent")
	}
	for _, headline := range []string{"", " \t"} {
		if err := c.MergePullRequest("PR_kw1", "abc", headline); err == nil {
			t.Fatalf("a merge request under the headline %q was sent", headline)
		}
	}
	if len(r.calls) != 0 {
		t.Fatalf("a request that names no PR or no headline reached gh: %v", r.calls)
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

// Each review names the commit it was given on, which GitHub leaves null for a
// review it can name no commit of.
func TestAReviewNamesTheCommitItWasGivenOn(t *testing.T) {
	c, r := client([2]string{"reviews(first:100", `{"data":{"repository":{"pullRequest":{"reviews":{"pageInfo":{"hasNextPage":false,"endCursor":"c"},
		"nodes":[{"fullDatabaseId":"5","state":"APPROVED","body":"","submittedAt":"2026-11-12T01:00:00Z","authorCanPushToRepository":true,
		"author":{"login":"operator"},"commit":{"oid":"1111111111111111111111111111111111111111"}},
		{"fullDatabaseId":"6","state":"APPROVED","body":"","submittedAt":"2026-11-12T02:00:00Z","authorCanPushToRepository":true,
		"author":{"login":"operator"},"commit":null}]}}}}}`})
	got, err := c.Reviews("acme/widgets", 7)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 || got[0].Commit != "1111111111111111111111111111111111111111" || got[1].Commit != "" {
		t.Fatalf("the reviews read their commits as %+v", got)
	}
	if args := strings.Join(r.calls[0].args, " "); !strings.Contains(args, "commit{oid}") {
		t.Fatalf("the read %q does not ask each review's commit", args)
	}
}
func TestADismissalNamesTheReviewAndCarriesItsMessage(t *testing.T) {
	c, r := client([2]string{"/dismissals", `{"id":100,"state":"DISMISSED"}`})
	if err := c.DismissReview("acme/widgets", 7, 100, "The change needs another look.\n\n<!-- gc:city -->"); err != nil {
		t.Fatal(err)
	}
	want := []string{"api", "--hostname", "github.com", "-X", "PUT", "repos/acme/widgets/pulls/7/reviews/100/dismissals",
		"-f", "message=The change needs another look.\n\n<!-- gc:city -->"}
	if !reflect.DeepEqual(r.calls[0].args, want) {
		t.Fatalf("the dismissal asked %q, want %q", r.calls[0].args, want)
	}
	c, r = client()
	for _, err := range []error{
		c.DismissReview("acme/widgets", 7, 0, "m"),
		c.DismissReview("acme/widgets", 7, 100, " "),
		c.DismissReview("widgets", 7, 100, "m"),
	} {
		if err == nil {
			t.Fatal("a dismissal that names no review, message or repository ran")
		}
	}
	if len(r.calls) != 0 {
		t.Fatalf("a dismissal refused before GitHub asked it: %+v", r.calls)
	}
}

// The PR's stage moves by the mutations gh pr ready makes, each naming the PR
// by its node id.
func TestTheStageOfAPRMovesByItsNodeID(t *testing.T) {
	for _, tc := range []struct {
		name, mutation string
		do             func(*gh.Client) error
	}{
		{"ready", "markPullRequestReadyForReview(input:{pullRequestId:$id})", func(c *gh.Client) error { return c.MarkReady("PR_kw1") }},
		{"draft", "convertPullRequestToDraft(input:{pullRequestId:$id})", func(c *gh.Client) error { return c.ConvertToDraft("PR_kw1") }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			c, r := client([2]string{tc.mutation, `{"data":{"x":{"pullRequest":{"isDraft":false}}}}`})
			if err := tc.do(c); err != nil {
				t.Fatal(err)
			}
			if args := strings.Join(r.calls[0].args, " "); !strings.Contains(args, "-f id=PR_kw1") {
				t.Fatalf("the request %q does not name the PR", args)
			}
		})
	}
	c, _ := client([2]string{"convertPullRequestToDraft", `{"data":null,"errors":[{"message":"Pull request is closed"}]}`})
	if err := c.ConvertToDraft("PR_kw1"); err == nil {
		t.Fatal("a refused conversion read as taken")
	}
	c, r := client()
	if err := c.MarkReady(""); err == nil || len(r.calls) != 0 {
		t.Fatalf("a request that names no PR ran: %v, %+v", err, r.calls)
	}
}

// A reaction names its post by the post's node id and its content by GitHub's
// name for it. One that names no post, or a content GitHub has no name of that
// form for, asks nothing, and a refused one is an error.
func TestAReactionNamesThePostByItsNodeID(t *testing.T) {
	c, r := client([2]string{"addReaction(input:{subjectId:$id,content:$content})",
		`{"data":{"addReaction":{"reaction":{"content":"EYES"}}}}`})
	if err := c.AddReaction("PRRC_kw1", "EYES"); err != nil {
		t.Fatal(err)
	}
	if args := strings.Join(r.calls[0].args, " "); !strings.Contains(args, "-f id=PRRC_kw1") ||
		!strings.Contains(args, "-f content=EYES") {
		t.Fatalf("the request %q does not name the post and the reaction", args)
	}
	c, r = client()
	for _, err := range []error{c.AddReaction("", "EYES"), c.AddReaction("PRRC_kw1", "eyes"), c.AddReaction("PRRC_kw1", "")} {
		if err == nil {
			t.Fatal("a reaction that names no post or no content GitHub names ran")
		}
	}
	if len(r.calls) != 0 {
		t.Fatalf("a refused reaction asked GitHub: %+v", r.calls)
	}
	c, _ = client([2]string{"addReaction", `{"data":null,"errors":[{"message":"Could not resolve to a node"}]}`})
	if err := c.AddReaction("PRRC_gone", "EYES"); err == nil {
		t.Fatal("a refused reaction read as added")
	}
}

// A resolution names its review thread by the thread's node id. One that names
// no thread asks nothing, and a refused one is an error.
func TestAResolutionNamesTheThreadByItsNodeID(t *testing.T) {
	c, r := client([2]string{"resolveReviewThread(input:{threadId:$id})",
		`{"data":{"resolveReviewThread":{"thread":{"isResolved":true}}}}`})
	if err := c.ResolveThread("PRRT_kw1"); err != nil {
		t.Fatal(err)
	}
	if args := strings.Join(r.calls[0].args, " "); !strings.Contains(args, "-f id=PRRT_kw1") {
		t.Fatalf("the request %q does not name the thread", args)
	}
	c, r = client()
	if err := c.ResolveThread(""); err == nil || len(r.calls) != 0 {
		t.Fatalf("a resolution that names no thread answered %v and asked %+v", err, r.calls)
	}
	c, _ = client([2]string{"resolveReviewThread", `{"data":null,"errors":[{"message":"Could not resolve to a node"}]}`})
	if err := c.ResolveThread("PRRT_gone"); err == nil {
		t.Fatal("a refused resolution read as made")
	}
}

// A review request names the PR and the account by its login, and refuses a
// login GitHub takes no request for before it asks.
func TestAReviewRequestNamesThePRAndTheLogin(t *testing.T) {
	c, r := client([2]string{"/requested_reviewers", `{"number":7}`})
	if err := c.RequestReview("acme/widgets", 7, "operator"); err != nil {
		t.Fatal(err)
	}
	want := []string{"api", "--hostname", "github.com", "-X", "POST", "repos/acme/widgets/pulls/7/requested_reviewers",
		"-f", "reviewers[]=operator"}
	if !reflect.DeepEqual(r.calls[0].args, want) {
		t.Fatalf("the request asked %q, want %q", r.calls[0].args, want)
	}
	c, r = client()
	for _, err := range []error{
		c.RequestReview("acme/widgets", 7, ""),
		c.RequestReview("acme/widgets", 7, "dependabot[bot]"),
		c.RequestReview("acme/widgets", 7, "-x"),
		c.RequestReview("widgets", 7, "operator"),
		c.RequestReview("acme/widgets", 0, "operator"),
	} {
		if err == nil {
			t.Fatal("a review request that names no login, a bot, no repository or no PR ran")
		}
	}
	if len(r.calls) != 0 {
		t.Fatalf("a refused review request asked GitHub: %+v", r.calls)
	}
}

// GitHub refused a request when it answered it with a client error, other than
// a rate limit. A request whose answer did not arrive, or that GitHub could not
// serve, is not refused.
func TestRefusedTellsARefusalFromNoAnswer(t *testing.T) {
	for msg, want := range map[string]bool{
		"gh: gh: Validation Failed (HTTP 422)":                               true,
		"gh: gh: Resource not accessible by integration (HTTP 403)":          true,
		"gh: gh: Not Found (HTTP 404)":                                       true,
		"gh: gh: API rate limit exceeded for user ID 1. (HTTP 403)":          false,
		"gh: gh: You have exceeded a secondary rate limit (HTTP 403)":        false,
		"gh: gh: Too Many Requests (HTTP 429)":                               false,
		"gh: gh: Bad Gateway (HTTP 502)":                                     false,
		"gh: error connecting to api.github.com":                             false,
		"github: the query failed: {\"message\":\"Pull request is closed\"}": false,
	} {
		if got := gh.Refused(errors.New(msg)); got != want {
			t.Errorf("Refused(%q) = %v, want %v", msg, got, want)
		}
	}
	if gh.Refused(nil) {
		t.Error("no error read as a refusal")
	}
}

func TestCheckSuitesReadTheLatestResultOfEachRequiredRun(t *testing.T) {
	c, r := client([2]string{"checkSuites(first:100", `{"data":{"repository":{"object":{"checkSuites":{
		"pageInfo":{"hasNextPage":false,"endCursor":"c"},"nodes":[{"databaseId":116886735833,"status":"IN_PROGRESS",
		"createdAt":"2026-11-16T07:00:00Z","workflowRun":{"databaseId":42114792210,"runAttempt":2},"checkRuns":{
		"pageInfo":{"hasNextPage":false},"nodes":[
		{"name":"test","status":"COMPLETED","conclusion":"SKIPPED","isRequired":true,
			"detailsUrl":"https://github.com/acme/widgets/actions/runs/42114792210/job/1"},
		{"name":"go","status":"IN_PROGRESS","conclusion":null,"detailsUrl":null,"isRequired":false}]}},
		{"databaseId":7,"status":"COMPLETED","createdAt":"2026-11-16T07:00:01Z","workflowRun":null,"checkRuns":{
		"pageInfo":{"hasNextPage":false},"nodes":[]}}]}}}}}`})
	got, err := c.CheckSuites("acme/widgets", "abc", 7)
	if err != nil {
		t.Fatal(err)
	}
	want := []gh.CheckSuite{{ID: 116886735833, Status: "IN_PROGRESS", CreatedAt: "2026-11-16T07:00:00Z", Run: 42114792210,
		Attempt: 2, Runs: []gh.CheckRun{
			{Name: "test", Status: "COMPLETED", Conclusion: "SKIPPED", Required: true,
				URL: "https://github.com/acme/widgets/actions/runs/42114792210/job/1"},
			{Name: "go", Status: "IN_PROGRESS"},
		}}, {ID: 7, Status: "COMPLETED", CreatedAt: "2026-11-16T07:00:01Z"}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %+v, want %+v", got, want)
	}
	args := strings.Join(r.calls[0].args, " ")
	for _, want := range []string{"filterBy:{checkType:LATEST}", "isRequired(pullRequestNumber:$number)", "object(oid:$oid)",
		"-f oid=abc", "--paginate", "workflowRun{databaseId runAttempt}", "status createdAt", "detailsUrl"} {
		if !strings.Contains(args, want) {
			t.Errorf("the read %q does not ask %q", args, want)
		}
	}
}

func TestASuiteWithMoreRunsThanAPageIsAnError(t *testing.T) {
	c, _ := client([2]string{"checkSuites", `{"data":{"repository":{"object":{"checkSuites":{
		"pageInfo":{"hasNextPage":false,"endCursor":"c"},"nodes":[{"databaseId":1,"status":"COMPLETED",
		"createdAt":"2026-11-16T07:00:00Z","checkRuns":{"pageInfo":{"hasNextPage":true},"nodes":[]}}]}}}}}`})
	if _, err := c.CheckSuites("acme/widgets", "abc", 7); err == nil {
		t.Fatal("read a suite whose check runs were cut short")
	}
}

// A suite read with no status or creation time, or with an Actions run that
// names no attempt, is a read that did not ask for them, which no decision is
// made on.
func TestASuiteThatNamesNoStatusTimeOrAttemptIsAnError(t *testing.T) {
	for name, node := range map[string]string{
		"no status":        `{"databaseId":1,"createdAt":"2026-11-16T07:00:00Z","checkRuns":{"pageInfo":{"hasNextPage":false},"nodes":[]}}`,
		"no creation time": `{"databaseId":1,"status":"QUEUED","checkRuns":{"pageInfo":{"hasNextPage":false},"nodes":[]}}`,
		"no attempt": `{"databaseId":1,"status":"QUEUED","createdAt":"2026-11-16T07:00:00Z","workflowRun":{"databaseId":9},
			"checkRuns":{"pageInfo":{"hasNextPage":false},"nodes":[]}}`,
	} {
		c, _ := client([2]string{"checkSuites", `{"data":{"repository":{"object":{"checkSuites":{
			"pageInfo":{"hasNextPage":false,"endCursor":"c"},"nodes":[` + node + `]}}}}}`})
		if _, err := c.CheckSuites("acme/widgets", "abc", 7); err == nil {
			t.Errorf("%s: read a suite as whole", name)
		}
	}
}

// A re-run asks GitHub to re-run one Actions run's failed jobs, named by the
// run's id, and a refusal reads as one.
func TestRerunFailedJobsAsksForTheRunsFailedJobs(t *testing.T) {
	c, r := client([2]string{"rerun-failed-jobs", ""})
	if err := c.RerunFailedJobs("acme/widgets", 42114792210); err != nil {
		t.Fatal(err)
	}
	if got, want := strings.Join(r.calls[0].args, " "),
		"api --hostname github.com -X POST repos/acme/widgets/actions/runs/42114792210/rerun-failed-jobs"; got != want {
		t.Fatalf("the re-run ran %q, want %q", got, want)
	}
	refused, _ := client([2]string{"rerun-failed-jobs", "ERR:gh: This workflow is already running (HTTP 403)"})
	if err := refused.RerunFailedJobs("acme/widgets", 1); !gh.Refused(err) {
		t.Fatalf("a re-run GitHub refused returned %v, which reads as no refusal", err)
	}
	if err := c.RerunFailedJobs("acme/widgets", 0); err == nil || len(r.calls) != 1 {
		t.Fatalf("a run with no id was asked for: %v", err)
	}
}

// The returns to draft are read from the PR's timeline, every page of it.
func TestConvertedToDraftReadsEveryReturnToDraftOnTheTimeline(t *testing.T) {
	c, r := client([2]string{"CONVERT_TO_DRAFT_EVENT", `{"data":{"repository":{"pullRequest":{"timelineItems":{
		"pageInfo":{"hasNextPage":true,"endCursor":"a"},"nodes":[{"createdAt":"2026-11-12T00:10:00Z"}]}}}}}
		{"data":{"repository":{"pullRequest":{"timelineItems":{
		"pageInfo":{"hasNextPage":false,"endCursor":"b"},"nodes":[{"createdAt":"2026-11-12T00:20:00Z"}]}}}}}`})
	got, err := c.ConvertedToDraft("acme/widgets", 7)
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{"2026-11-12T00:10:00Z", "2026-11-12T00:20:00Z"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("read %v, want %v", got, want)
	}
	if args := strings.Join(r.calls[0].args, " "); !strings.Contains(args, "--paginate") {
		t.Errorf("the read %q does not page", args)
	}
	none, _ := client([2]string{"CONVERT_TO_DRAFT_EVENT", `{"data":{"repository":{"pullRequest":{"timelineItems":{
		"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}}`})
	if got, err := none.ConvertedToDraft("acme/widgets", 7); err != nil || got == nil || len(got) != 0 {
		t.Fatalf("a PR never returned to draft read %v, %v", got, err)
	}
	timeless, _ := client([2]string{"CONVERT_TO_DRAFT_EVENT", `{"data":{"repository":{"pullRequest":{"timelineItems":{
		"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{}]}}}}}`})
	if _, err := timeless.ConvertedToDraft("acme/widgets", 7); err == nil {
		t.Fatal("read a return to draft that names no time")
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
