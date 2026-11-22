package gh_test

import (
	"fmt"
	"reflect"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
)

// signsNode is one PR's signs as GitHub answers the cheap question.
func signsNode(n int, labels string, more bool) string {
	return fmt.Sprintf(`{"number":%d,"state":"OPEN","isDraft":false,"headRefOid":"h%d","baseRefName":"main",
		"baseRef":{"target":{"oid":"tip"}},"updatedAt":"2026-11-16T09:00:00Z","totalCommentsCount":3,
		"reviews":{"totalCount":2},"dismissed":{"totalCount":1},
		"labels":{"pageInfo":{"hasNextPage":%v,"endCursor":"c1"},"nodes":[%s]},
		"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"PENDING","contexts":{"totalCount":3,
			"checkRunCountsByState":[{"state":"SUCCESS","count":2},{"state":"FAILURE","count":0}],
			"statusContextCountsByState":[{"state":"PENDING","count":1}]}}}}]}}`, n, n, more, labels)
}

func TestSignsAsksEveryPRInOneRequestAndReadsOnlyItsSigns(t *testing.T) {
	c, r := client([2]string{"p7:pullRequest(number:7)", `{"data":{"repository":{
		"p7":` + signsNode(7, `{"name":"status: working"},{"name":"held: you"}`, false) + `,
		"p9":` + signsNode(9, ``, false) + `}}}`})
	read, failed := c.Signs("acme/widgets", []int{9, 7})
	if len(failed) != 0 {
		t.Fatalf("failed %v", failed)
	}
	want := gh.Signs{Number: 7, State: "OPEN", HeadRefOid: "h7", BaseRefName: "main", BaseTip: "tip",
		UpdatedAt: "2026-11-16T09:00:00Z", Comments: 3, Reviews: 2, Dismissed: 1,
		Labels: []string{"held: you", "status: working"}, Rollup: "PENDING", Contexts: 3,
		CheckRuns: map[string]int{"SUCCESS": 2}, Statuses: map[string]int{"PENDING": 1}}
	if !reflect.DeepEqual(read[7], want) {
		t.Fatalf("PR 7's signs read as\n%+v\nwant\n%+v", read[7], want)
	}
	if read[9].Labels != nil || read[9].HeadRefOid != "h9" {
		t.Fatalf("PR 9's signs read as %+v", read[9])
	}
	if len(r.calls) != 1 {
		t.Fatalf("two PRs took %d requests, want one", len(r.calls))
	}
	args := strings.Join(r.calls[0].args, " ")
	for _, want := range []string{"api --hostname github.com graphql", "-f owner=acme", "-f name=widgets",
		"p9:pullRequest(number:9){...signs}", "labels(first:100)", "dismissed:reviews(states:[DISMISSED])",
		"checkRunCountsByState", "statusContextCountsByState", "baseRef{target{oid}}"} {
		if !strings.Contains(args, want) {
			t.Errorf("the request lacks %q", want)
		}
	}
	for _, detail := range []string{"body", "checkSuites", "reviewThreads", "nodes{fullDatabaseId"} {
		if strings.Contains(args, detail) {
			t.Errorf("the cheap question reads a detail, %q", detail)
		}
	}
}

func TestSignsAsksAtMostFiftyPRsARequest(t *testing.T) {
	var nodes []string
	var numbers []int
	for n := 1; n <= 51; n++ {
		numbers = append(numbers, n)
		nodes = append(nodes, fmt.Sprintf(`"p%d":%s`, n, signsNode(n, ``, false)))
	}
	c, r := client([2]string{"query", `{"data":{"repository":{` + strings.Join(nodes, ",") + `}}}`})
	read, failed := c.Signs("acme/widgets", numbers)
	if len(read) != 51 || len(failed) != 0 {
		t.Fatalf("read %d, failed %v", len(read), failed)
	}
	if len(r.calls) != 2 {
		t.Fatalf("51 PRs took %d requests, want two", len(r.calls))
	}
	first, second := strings.Join(r.calls[0].args, " "), strings.Join(r.calls[1].args, " ")
	if strings.Count(first, "pullRequest(number:") != 50 || strings.Count(second, "pullRequest(number:") != 1 {
		t.Fatalf("the requests asked %d and %d PRs", strings.Count(first, "pullRequest(number:"),
			strings.Count(second, "pullRequest(number:"))
	}
}

func TestSignsAnErrorFailsOnlyThePRsItNames(t *testing.T) {
	c, _ := client([2]string{"query", `PARTIAL:{"data":{"repository":{"p7":` + signsNode(7, ``, false) + `,"p8":null}},
		"errors":[{"type":"NOT_FOUND","path":["repository","p8"],"message":"Could not resolve to a PullRequest with the number of 8."}]}`})
	read, failed := c.Signs("acme/widgets", []int{7, 8})
	if _, ok := read[7]; !ok || len(read) != 1 {
		t.Fatalf("read %v, want PR 7 alone", read)
	}
	if err := failed[8]; err == nil || !strings.Contains(err.Error(), "Could not resolve") {
		t.Fatalf("PR 8 failed as %v", failed[8])
	}
}

func TestSignsARequestThatFailsWholeFailsEveryPRItAsked(t *testing.T) {
	for name, answer := range map[string]string{
		"no answer":                 "ERR:gh: connection reset",
		"an error that names no PR": `PARTIAL:{"data":null,"errors":[{"message":"Something went wrong"}]}`,
		"no data":                   `{"data":null}`,
		"a page that does not read": `{"data":`,
	} {
		t.Run(name, func(t *testing.T) {
			c, _ := client([2]string{"query", answer})
			read, failed := c.Signs("acme/widgets", []int{7, 8})
			if len(read) != 0 || failed[7] == nil || failed[8] == nil {
				t.Fatalf("read %v, failed %v", read, failed)
			}
		})
	}
}

func TestSignsReadsLabelsOnUntilTheyEnd(t *testing.T) {
	c, r := client(
		[2]string{"endCursor=c2", `{"data":{"repository":{"pullRequest":{"labels":{
			"pageInfo":{"hasNextPage":false,"endCursor":"c3"},"nodes":[{"name":"c-label"}]}}}}}`},
		[2]string{"endCursor=c1", `{"data":{"repository":{"pullRequest":{"labels":{
			"pageInfo":{"hasNextPage":true,"endCursor":"c2"},"nodes":[{"name":"b-label"}]}}}}}`},
		[2]string{"p7:", `{"data":{"repository":{"p7":` + signsNode(7, `{"name":"d-label"},{"name":"a-label"}`, true) + `}}}`})
	read, failed := c.Signs("acme/widgets", []int{7})
	if len(failed) != 0 {
		t.Fatalf("failed %v", failed)
	}
	if want := []string{"a-label", "b-label", "c-label", "d-label"}; !reflect.DeepEqual(read[7].Labels, want) {
		t.Fatalf("labels read as %v, want %v", read[7].Labels, want)
	}
	if len(r.calls) != 3 {
		t.Fatalf("%d requests, want the signs and two pages of labels", len(r.calls))
	}

	c, _ = client(
		[2]string{"endCursor=c1", "ERR:gh: HTTP 502"},
		[2]string{"p7:", `{"data":{"repository":{"p7":` + signsNode(7, `{"name":"a"}`, true) + `,
			"p8":` + signsNode(8, `{"name":"b"}`, false) + `}}}`})
	read, failed = c.Signs("acme/widgets", []int{7, 8})
	if failed[7] == nil || len(read) != 1 || read[8].Labels[0] != "b" {
		t.Fatalf("a failed page of PR 7's labels read as %v, %v", read, failed)
	}
}

func TestSignsRefusesAFirstLabelPageThatSaysMoreFollowAndNamesNoCursor(t *testing.T) {
	node := strings.Replace(signsNode(7, `{"name":"status: merging"}`, true), `"endCursor":"c1"`, `"endCursor":""`, 1)
	c, r := client([2]string{"p7:", `{"data":{"repository":{"p7":` + node + `,
		"p8":` + signsNode(8, `{"name":"b"}`, false) + `}}}`})
	read, failed := c.Signs("acme/widgets", []int{7, 8})
	if failed[7] == nil || len(read) != 1 || read[8].Labels[0] != "b" {
		t.Fatalf("a first page of PR 7's labels with no cursor read as %v, %v", read, failed)
	}
	if len(r.calls) != 1 {
		t.Fatalf("%d requests, want the signs alone", len(r.calls))
	}
}

const partPR = `"id":"PR_kw1","number":7,"url":"https://github.com/acme/widgets/pull/7","state":"OPEN","isDraft":false,
	"headRefName":"polecat/tk-1","headRefOid":"abc","baseRefName":"main","mergeStateStatus":"BLOCKED",
	"repository":{"nameWithOwner":"acme/widgets"},"mergedAt":null,"mergeCommit":null,
	"isInMergeQueue":false,"isMergeQueueEnabled":false`

func TestPullRequestPartReadsTheChecksAtTheHeadInTheSameRequest(t *testing.T) {
	c, r := client([2]string{"checkSuites(first:100)", `{"data":{"repository":{"pullRequest":{` + partPR + `,
		"commits":{"nodes":[{"commit":{"oid":"abc","checkSuites":{"pageInfo":{"hasNextPage":false,"endCursor":"x"},
			"nodes":[{"databaseId":5,"checkRuns":{"pageInfo":{"hasNextPage":false},
				"nodes":[{"name":"test","status":"COMPLETED","conclusion":"SUCCESS","isRequired":true}]}}]}}}]}}}}}`})
	p, err := c.PullRequestPart("acme/widgets", 7, true)
	if err != nil {
		t.Fatal(err)
	}
	if p.HeadRefOid != "abc" || p.MergeStateStatus != "BLOCKED" || p.ChecksAt != "abc" {
		t.Fatalf("read %+v", p)
	}
	want := []gh.CheckSuite{{ID: 5, Runs: []gh.CheckRun{{Name: "test", Status: "COMPLETED", Conclusion: "SUCCESS", Required: true}}}}
	if !reflect.DeepEqual(p.Suites, want) {
		t.Fatalf("suites %+v", p.Suites)
	}
	args := strings.Join(r.calls[0].args, " ")
	for _, want := range []string{"filterBy:{checkType:LATEST}", "isRequired(pullRequestNumber:$number)", "-F number=7"} {
		if !strings.Contains(args, want) {
			t.Errorf("the request lacks %q", want)
		}
	}
	if len(r.calls) != 1 {
		t.Fatalf("%d requests, want one", len(r.calls))
	}
}

func TestPullRequestPartAloneReadsNoChecks(t *testing.T) {
	c, r := client([2]string{"pullRequest(number:$number)", `{"data":{"repository":{"pullRequest":{` + partPR + `}}}}`})
	p, err := c.PullRequestPart("acme/widgets", 7, false)
	if err != nil {
		t.Fatal(err)
	}
	if p.Suites != nil || p.ChecksAt != "" || strings.Contains(strings.Join(r.calls[0].args, " "), "checkSuites") {
		t.Fatalf("the PR alone read checks: %+v", p)
	}
}

func TestPullRequestPartReadsCheckSuitesOnPastTheFirstPage(t *testing.T) {
	c, r := client(
		[2]string{"object(oid:$oid)", `{"data":{"repository":{"object":{"checkSuites":{"pageInfo":{"hasNextPage":false,"endCursor":"y"},
			"nodes":[{"databaseId":6,"checkRuns":{"pageInfo":{"hasNextPage":false},"nodes":[]}}]}}}}}`},
		[2]string{"commits(last:1)", `{"data":{"repository":{"pullRequest":{` + partPR + `,
			"commits":{"nodes":[{"commit":{"oid":"abc","checkSuites":{"pageInfo":{"hasNextPage":true,"endCursor":"x"},
				"nodes":[{"databaseId":5,"checkRuns":{"pageInfo":{"hasNextPage":false},"nodes":[]}}]}}}]}}}}}`})
	p, err := c.PullRequestPart("acme/widgets", 7, true)
	if err != nil {
		t.Fatal(err)
	}
	if len(p.Suites) != 1 || p.Suites[0].ID != 6 || len(r.calls) != 2 {
		t.Fatalf("suites %+v after %d requests, want the paged read's", p.Suites, len(r.calls))
	}
}

func TestConversationReadsEveryListInOneRequest(t *testing.T) {
	c, r := client([2]string{"reviewDecision", `{"data":{"repository":{"pullRequest":{"reviewDecision":"APPROVED",
		"reviews":{"pageInfo":{"hasNextPage":false},"nodes":[{"fullDatabaseId":"100","state":"APPROVED","body":"",
			"submittedAt":"2026-11-16T01:00:00Z","updatedAt":"2026-11-16T01:00:05Z","authorCanPushToRepository":true,
			"author":{"login":"operator"},"commit":{"oid":"abc"}}]},
		"reviewThreads":{"pageInfo":{"hasNextPage":false},"nodes":[{"id":"T1","isResolved":false,"comments":{
			"pageInfo":{"hasNextPage":false},"nodes":[{"fullDatabaseId":"200","author":{"login":"operator"},"body":"fix",
				"createdAt":"2026-11-16T02:00:00Z","updatedAt":"2026-11-16T02:30:00Z",
				"pullRequestReview":{"fullDatabaseId":"101","submittedAt":"2026-11-16T02:00:00Z","state":"COMMENTED"},
				"reactionGroups":[]}]}}]},
		"comments":{"pageInfo":{"hasNextPage":false},"nodes":[{"fullDatabaseId":"300","body":"hi",
			"createdAt":"2026-11-16T03:00:00Z","updatedAt":"2026-11-16T03:00:00Z","author":{"login":"zook-bot"}}]}}}}}`})
	conv, err := c.Conversation("acme/widgets", 7)
	if err != nil {
		t.Fatal(err)
	}
	if conv.ReviewDecision != "APPROVED" || len(conv.Reviews) != 1 || conv.Reviews[0].UpdatedAt != "2026-11-16T01:00:05Z" {
		t.Fatalf("reviews %+v", conv)
	}
	if len(conv.Threads) != 1 || conv.Threads[0].Comments[0].UpdatedAt != "2026-11-16T02:30:00Z" ||
		conv.Threads[0].Comments[0].Review.ID != 101 {
		t.Fatalf("threads %+v", conv.Threads)
	}
	if len(conv.Comments) != 1 || conv.Comments[0].ID != 300 || conv.Comments[0].Author != "zook-bot" {
		t.Fatalf("comments %+v", conv.Comments)
	}
	if len(r.calls) != 1 {
		t.Fatalf("%d requests, want one", len(r.calls))
	}
}

// Each post the conversation read returns carries its node id, which the
// take marks it by, its URL, which its ask names, and the reactions the reading
// account left on it, which say whether the city has taken it. An inline
// comment carries its file and the line it was made on, and a comment on a file
// as a whole, whose line GitHub gives as null, carries none.
func TestConversationReadsEachPostsAddressAndTheCitysMarks(t *testing.T) {
	eyes := `[{"content":"THUMBS_UP","viewerHasReacted":false},{"content":"EYES","viewerHasReacted":true}]`
	c, r := client([2]string{"reviewDecision", `{"data":{"repository":{"pullRequest":{"reviewDecision":null,
		"reviews":{"pageInfo":{"hasNextPage":false},"nodes":[{"fullDatabaseId":"100","id":"PRR_1",
			"url":"https://github.com/acme/widgets/pull/7#pullrequestreview-100","state":"APPROVED","body":"rename X",
			"submittedAt":"s","updatedAt":"u","authorCanPushToRepository":true,"author":{"login":"operator"},"commit":null,
			"reactionGroups":` + eyes + `}]},
		"reviewThreads":{"pageInfo":{"hasNextPage":false},"nodes":[{"id":"T1","isResolved":false,"comments":{
			"pageInfo":{"hasNextPage":false},"nodes":[
			{"fullDatabaseId":"200","id":"PRRC_1","url":"https://github.com/acme/widgets/pull/7#discussion_r200",
				"author":{"login":"operator"},"body":"fix","createdAt":"c","updatedAt":"u","path":"a/b.go","originalLine":42,
				"pullRequestReview":{"fullDatabaseId":"101","submittedAt":"s","state":"COMMENTED"},"reactionGroups":[]},
			{"fullDatabaseId":"201","id":"PRRC_2","url":"https://github.com/acme/widgets/pull/7#discussion_r201",
				"author":{"login":"operator"},"body":"whole file","createdAt":"c","updatedAt":"u","path":"a/c.go",
				"originalLine":null,"pullRequestReview":{"fullDatabaseId":"101","submittedAt":"s","state":"COMMENTED"},
				"reactionGroups":[]}]}}]},
		"comments":{"pageInfo":{"hasNextPage":false},"nodes":[{"fullDatabaseId":"300","id":"IC_1",
			"url":"https://github.com/acme/widgets/pull/7#issuecomment-300","body":"hi","createdAt":"c","updatedAt":"u",
			"author":{"login":"visitor"},"reactionGroups":` + eyes + `}]}}}}}`})
	conv, err := c.Conversation("acme/widgets", 7)
	if err != nil {
		t.Fatal(err)
	}
	review := gh.Review{ID: 100, NodeID: "PRR_1", URL: "https://github.com/acme/widgets/pull/7#pullrequestreview-100",
		State: "APPROVED", Body: "rename X", SubmittedAt: "s", UpdatedAt: "u", Author: "operator", AuthorCanPush: true,
		ViewerReactions: []string{"EYES"}}
	if !reflect.DeepEqual(conv.Reviews, []gh.Review{review}) {
		t.Fatalf("reviews %+v, want %+v", conv.Reviews, review)
	}
	inline := conv.Threads[0].Comments
	if inline[0].NodeID != "PRRC_1" || inline[0].URL != "https://github.com/acme/widgets/pull/7#discussion_r200" ||
		inline[0].Path != "a/b.go" || inline[0].OriginalLine != 42 || inline[0].ViewerReactions != nil {
		t.Fatalf("inline comment %+v", inline[0])
	}
	if inline[1].Path != "a/c.go" || inline[1].OriginalLine != 0 {
		t.Fatalf("a comment on a file as a whole reads %+v, want its file and no line", inline[1])
	}
	comment := gh.IssueComment{ID: 300, NodeID: "IC_1", URL: "https://github.com/acme/widgets/pull/7#issuecomment-300",
		Author: "visitor", Body: "hi", CreatedAt: "c", UpdatedAt: "u", ViewerReactions: []string{"EYES"}}
	if !reflect.DeepEqual(conv.Comments, []gh.IssueComment{comment}) {
		t.Fatalf("comments %+v, want %+v", conv.Comments, comment)
	}
	query := strings.Join(r.calls[0].args, " ")
	if n := strings.Count(query, "reactionGroups{content viewerHasReacted}"); n != 3 || !strings.Contains(query, "path originalLine") {
		t.Fatalf("the read %q asks the reactions of %d lists, want the reviews, the inline comments and the "+
			"conversation comments, and an inline comment's file and line", query, n)
	}
}

func TestConversationReadsAListPastItsFirstPageOnItsOwn(t *testing.T) {
	c, r := client(
		[2]string{"reviews(first:100,after:$endCursor)", `{"data":{"repository":{"pullRequest":{"reviews":{
			"pageInfo":{"hasNextPage":false},"nodes":[{"fullDatabaseId":"100","state":"APPROVED","body":"",
			"submittedAt":"s","updatedAt":"u","authorCanPushToRepository":true,"author":{"login":"a"},"commit":null},
			{"fullDatabaseId":"101","state":"COMMENTED","body":"x","submittedAt":"s","updatedAt":"u",
			"authorCanPushToRepository":true,"author":{"login":"a"},"commit":null}]}}}}}`},
		[2]string{"reviewDecision", `{"data":{"repository":{"pullRequest":{"reviewDecision":null,
			"reviews":{"pageInfo":{"hasNextPage":true,"endCursor":"r1"},"nodes":[{"fullDatabaseId":"100","state":"APPROVED",
				"body":"","submittedAt":"s","updatedAt":"u","authorCanPushToRepository":true,"author":{"login":"a"},"commit":null}]},
			"reviewThreads":{"pageInfo":{"hasNextPage":false},"nodes":[]},
			"comments":{"pageInfo":{"hasNextPage":false},"nodes":[]}}}}}`})
	conv, err := c.Conversation("acme/widgets", 7)
	if err != nil {
		t.Fatal(err)
	}
	if len(conv.Reviews) != 2 || conv.ReviewDecision != "" || len(r.calls) != 2 {
		t.Fatalf("read %+v after %d requests", conv, len(r.calls))
	}
}
