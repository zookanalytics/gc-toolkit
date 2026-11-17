package gh_test

import (
	"fmt"
	"reflect"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
)

// fullLists are the first page of each list a PR's node holds in the net's
// read, as GitHub answers it.
type fullLists struct {
	labels, comments, reviews, threads, contexts string
}

// fullDefaults is a PR with one label, one conversation comment, one review, an
// unresolved thread whose comment the account the read runs as reacted to and a
// resolved one, and a required check run beside a commit status, each list on
// one page.
var fullDefaults = fullLists{
	labels:   `{"pageInfo":{"hasNextPage":false,"endCursor":"l"},"nodes":[{"name":"status: working"}]}`,
	comments: `{"pageInfo":{"hasNextPage":false,"endCursor":"c"},"nodes":[{"updatedAt":"2026-11-16T09:01:00Z"}]}`,
	reviews: `{"totalCount":1,"pageInfo":{"hasNextPage":false,"endCursor":"r"},
		"nodes":[{"updatedAt":"2026-11-16T09:02:00Z"}]}`,
	threads: `{"pageInfo":{"hasNextPage":false,"endCursor":"t"},"nodes":[
		{"id":"T9","isResolved":false,"comments":{"pageInfo":{"hasNextPage":false,"endCursor":"x"},
			"nodes":[{"fullDatabaseId":"401","updatedAt":"2026-11-16T09:03:00Z","reactionGroups":[
				{"content":"THUMBS_UP","viewerHasReacted":true},{"content":"HEART","viewerHasReacted":false}]}]}},
		{"id":"T1","isResolved":true,"comments":{"pageInfo":{"hasNextPage":false,"endCursor":"x"},
			"nodes":[{"fullDatabaseId":"402","updatedAt":"2026-11-16T08:00:00Z","reactionGroups":[]}]}}]}`,
	contexts: `{"totalCount":2,"checkRunCountsByState":[{"state":"SUCCESS","count":1}],
		"statusContextCountsByState":[{"state":"PENDING","count":1}],
		"pageInfo":{"hasNextPage":false,"endCursor":"k"},"nodes":[
		{"__typename":"CheckRun","name":"test","status":"COMPLETED","conclusion":"SUCCESS","isRequired":true},
		{"__typename":"StatusContext"}]}`,
}

// fullNode is PR n as GitHub answers the net's read, with lists l.
func fullNode(n int, l fullLists) string {
	return fmt.Sprintf(`{"number":%d,"state":"OPEN","isDraft":false,"headRefOid":"h%d","baseRefName":"main",
		"baseRef":{"target":{"oid":"tip"}},"updatedAt":"2026-11-16T09:00:00Z","totalCommentsCount":2,
		"dismissed":{"totalCount":0},"mergeStateStatus":"BLOCKED","reviewDecision":"APPROVED",
		"isInMergeQueue":false,"isMergeQueueEnabled":true,
		"labels":%s,"comments":%s,"reviews":%s,"reviewThreads":%s,
		"commits":{"nodes":[{"commit":{"oid":"h%d","statusCheckRollup":{"state":"PENDING","contexts":%s}}}]}}`,
		n, n, l.labels, l.comments, l.reviews, l.threads, n, l.contexts)
}

func TestFullReadReadsEachPRsFactsAndNoPostsText(t *testing.T) {
	nine := strings.Replace(strings.Replace(fullNode(9, fullDefaults), `"reviewDecision":"APPROVED"`,
		`"reviewDecision":null`, 1), `"statusCheckRollup":{"state":"PENDING","contexts":`+fullDefaults.contexts+`}`,
		`"statusCheckRollup":null`, 1)
	c, r := client([2]string{"p7:pullRequest(number:7)", `{"data":{"repository":{
		"p7":` + fullNode(7, fullDefaults) + `,"p9":` + nine + `}}}`})
	read, failed := c.FullRead("acme/widgets", []int{9, 7})
	if len(failed) != 0 {
		t.Fatalf("failed %v", failed)
	}
	want := gh.Full{
		Signs: gh.Signs{Number: 7, State: "OPEN", HeadRefOid: "h7", BaseRefName: "main", BaseTip: "tip",
			UpdatedAt: "2026-11-16T09:00:00Z", Comments: 2, Reviews: 1, Labels: []string{"status: working"},
			Rollup: "PENDING", Contexts: 2, CheckRuns: map[string]int{"SUCCESS": 1}, Statuses: map[string]int{"PENDING": 1}},
		MergeStateStatus: "BLOCKED", ReviewDecision: "APPROVED", MergeQueueEnabled: true,
		Posts:      []string{"2026-11-16T09:01:00Z", "2026-11-16T09:02:00Z", "2026-11-16T09:03:00Z", "2026-11-16T08:00:00Z"},
		Unresolved: []string{"T9"}, ViewerReactions: []string{"401 THUMBS_UP"}, ChecksAt: "h7",
		Checks: []gh.CheckRun{{Name: "test", Status: "COMPLETED", Conclusion: "SUCCESS", Required: true}},
	}
	if !reflect.DeepEqual(read[7], want) {
		t.Fatalf("PR 7 read as\n%+v\nwant\n%+v", read[7], want)
	}
	if n := read[9]; n.ReviewDecision != "" || n.ChecksAt != "h9" || len(n.Checks) != 0 || n.Rollup != "" {
		t.Fatalf("PR 9, with no review decision and no check rollup, read as %+v", n)
	}
	if len(r.calls) != 1 {
		t.Fatalf("two PRs took %d requests, want one", len(r.calls))
	}
	args := strings.Join(r.calls[0].args, " ")
	for _, want := range []string{"api --hostname github.com graphql", "-f owner=acme", "-f name=widgets",
		"isRequired(pullRequestNumber:7)", "isRequired(pullRequestNumber:9)", "reviewThreads(first:10)",
		"mergeStateStatus", "reviewDecision", "isInMergeQueue", "isMergeQueueEnabled", "labels(first:100)",
		"dismissed:reviews(states:[DISMISSED])", "checkRunCountsByState", "baseRef{target{oid}}",
		"reactionGroups{content viewerHasReacted}"} {
		if !strings.Contains(args, want) {
			t.Errorf("the request lacks %q", want)
		}
	}
	for _, text := range []string{"body", "author", "checkSuites"} {
		if strings.Contains(args, text) {
			t.Errorf("the net's read reads %q", text)
		}
	}
}

func TestFullReadAsksAtMostTenPRsARequest(t *testing.T) {
	var nodes []string
	var numbers []int
	for n := 1; n <= 11; n++ {
		numbers = append(numbers, n)
		nodes = append(nodes, fmt.Sprintf(`"p%d":%s`, n, fullNode(n, fullDefaults)))
	}
	c, r := client([2]string{"query", `{"data":{"repository":{` + strings.Join(nodes, ",") + `}}}`})
	read, failed := c.FullRead("acme/widgets", numbers)
	if len(read) != 11 || len(failed) != 0 {
		t.Fatalf("read %d, failed %v", len(read), failed)
	}
	if len(r.calls) != 2 {
		t.Fatalf("11 PRs took %d requests, want two", len(r.calls))
	}
	first, second := strings.Join(r.calls[0].args, " "), strings.Join(r.calls[1].args, " ")
	if strings.Count(first, "pullRequest(number:") != 10 || strings.Count(second, "pullRequest(number:") != 1 {
		t.Fatalf("the requests asked %d and %d PRs", strings.Count(first, "pullRequest(number:"),
			strings.Count(second, "pullRequest(number:"))
	}
}

// page is a later page of a list, the last.
func page(path, list string) string {
	open, closing := "", ""
	for _, p := range strings.Split(path, ".") {
		open += `{"` + p + `":`
		closing += "}"
	}
	return `{"data":` + open + `{"pageInfo":{"hasNextPage":false,"endCursor":"end"},"nodes":[` + list + `]}` + closing + `}`
}

func TestFullReadReadsEachListOnPastItsFirstPage(t *testing.T) {
	more := fullLists{
		labels:   strings.Replace(fullDefaults.labels, `"hasNextPage":false,"endCursor":"l"`, `"hasNextPage":true,"endCursor":"L1"`, 1),
		comments: strings.Replace(fullDefaults.comments, `"hasNextPage":false,"endCursor":"c"`, `"hasNextPage":true,"endCursor":"C1"`, 1),
		reviews:  strings.Replace(fullDefaults.reviews, `"hasNextPage":false,"endCursor":"r"`, `"hasNextPage":true,"endCursor":"R1"`, 1),
		threads: `{"pageInfo":{"hasNextPage":true,"endCursor":"T1"},"nodes":[
			{"id":"T9","isResolved":false,"comments":{"pageInfo":{"hasNextPage":true,"endCursor":"N1"},
				"nodes":[{"fullDatabaseId":"401","updatedAt":"2026-11-16T09:03:00Z","reactionGroups":[]}]}}]}`,
		contexts: strings.Replace(fullDefaults.contexts, `"hasNextPage":false,"endCursor":"k"`, `"hasNextPage":true,"endCursor":"K1"`, 1),
	}
	c, r := client(
		[2]string{"endCursor=L1", page("repository.pullRequest.labels", `{"name":"a-label"}`)},
		[2]string{"endCursor=C1", page("repository.pullRequest.comments", `{"updatedAt":"2026-11-16T10:01:00Z"}`)},
		[2]string{"endCursor=R1", page("repository.pullRequest.reviews", `{"updatedAt":"2026-11-16T10:02:00Z"}`)},
		[2]string{"endCursor=T1", page("repository.pullRequest.reviewThreads", `{"id":"T2","isResolved":false,
			"comments":{"pageInfo":{"hasNextPage":false,"endCursor":"z"},"nodes":[{"fullDatabaseId":"403",
			"updatedAt":"2026-11-16T10:03:00Z","reactionGroups":[{"content":"EYES","viewerHasReacted":true}]}]}}`)},
		[2]string{"endCursor=N1", page("node.comments", `{"fullDatabaseId":"404","updatedAt":"2026-11-16T10:04:00Z",
			"reactionGroups":[{"content":"THUMBS_UP","viewerHasReacted":true}]}`)},
		[2]string{"endCursor=K1", page("repository.object.statusCheckRollup.contexts",
			`{"__typename":"CheckRun","name":"lint","status":"IN_PROGRESS","conclusion":null,"isRequired":false}`)},
		[2]string{"p7:", `{"data":{"repository":{"p7":` + fullNode(7, more) + `}}}`})
	read, failed := c.FullRead("acme/widgets", []int{7})
	if len(failed) != 0 {
		t.Fatalf("failed %v", failed)
	}
	f := read[7]
	if want := []string{"a-label", "status: working"}; !slices.Equal(f.Labels, want) {
		t.Errorf("labels %v, want %v", f.Labels, want)
	}
	posts := slices.Sorted(slices.Values(f.Posts))
	if want := []string{"2026-11-16T09:01:00Z", "2026-11-16T09:02:00Z", "2026-11-16T09:03:00Z", "2026-11-16T10:01:00Z",
		"2026-11-16T10:02:00Z", "2026-11-16T10:03:00Z", "2026-11-16T10:04:00Z"}; !slices.Equal(posts, want) {
		t.Errorf("post times %v, want %v", posts, want)
	}
	if want := []string{"T2", "T9"}; !slices.Equal(f.Unresolved, want) {
		t.Errorf("unresolved %v, want %v", f.Unresolved, want)
	}
	if want := []string{"403 EYES", "404 THUMBS_UP"}; !slices.Equal(f.ViewerReactions, want) {
		t.Errorf("the account's reactions %v, want %v", f.ViewerReactions, want)
	}
	if want := []gh.CheckRun{{Name: "test", Status: "COMPLETED", Conclusion: "SUCCESS", Required: true},
		{Name: "lint", Status: "IN_PROGRESS"}}; !reflect.DeepEqual(f.Checks, want) {
		t.Errorf("checks %+v, want %+v", f.Checks, want)
	}
	if len(r.calls) != 7 {
		t.Fatalf("%d requests, want the read and one later page of each of six lists", len(r.calls))
	}
	for cursor, want := range map[string][]string{
		"endCursor=L1": {"labels(first:100,after:$endCursor)", "-F number=7"},
		"endCursor=C1": {"comments(first:100,after:$endCursor)", "nodes{updatedAt}"},
		"endCursor=R1": {"reviews(first:100,after:$endCursor)", "nodes{updatedAt}"},
		"endCursor=T1": {"reviewThreads(first:10,after:$endCursor)", "isResolved", "viewerHasReacted"},
		"endCursor=N1": {"node(id:$id)", "-f id=T9", "reactionGroups{content viewerHasReacted}"},
		"endCursor=K1": {"object(oid:$oid)", "-f oid=h7", "-F number=7", "isRequired(pullRequestNumber:$number)"},
	} {
		var args string
		for _, call := range r.calls {
			if joined := strings.Join(call.args, " "); strings.Contains(joined, cursor) {
				args = joined
			}
		}
		for _, w := range want {
			if !strings.Contains(args, w) {
				t.Errorf("the page after %s asked %q, which lacks %q", cursor, args, w)
			}
		}
		if strings.Contains(args, "body") {
			t.Errorf("the page after %s reads a post's text", cursor)
		}
	}
}

func TestFullReadAFailedReadFailsOnlyThePRsItNames(t *testing.T) {
	c, _ := client([2]string{"query", `PARTIAL:{"data":{"repository":{"p7":` + fullNode(7, fullDefaults) + `,"p8":null}},
		"errors":[{"type":"NOT_FOUND","path":["repository","p8"],"message":"Could not resolve to a PullRequest with the number of 8."}]}`})
	read, failed := c.FullRead("acme/widgets", []int{7, 8})
	if _, ok := read[7]; !ok || len(read) != 1 {
		t.Fatalf("read %v, want PR 7 alone", read)
	}
	if err := failed[8]; err == nil || !strings.Contains(err.Error(), "Could not resolve") {
		t.Fatalf("PR 8 failed as %v", failed[8])
	}

	// An error inside one PR's field, such as a check's required flag, fails
	// that PR alone.
	c, _ = client([2]string{"query", `PARTIAL:{"data":{"repository":{"p7":` + fullNode(7, fullDefaults) + `,
		"p8":` + fullNode(8, fullDefaults) + `}},"errors":[{"path":["repository","p8","commits","nodes",0,"commit",
		"statusCheckRollup","contexts","nodes",0,"isRequired"],"message":"Something went wrong"}]}`})
	read, failed = c.FullRead("acme/widgets", []int{7, 8})
	if _, ok := read[7]; !ok || failed[8] == nil || len(read) != 1 {
		t.Fatalf("read %v, failed %v, want PR 7 read and PR 8 failed", read, failed)
	}

	// A later page that fails fails its PR alone.
	more := fullDefaults
	more.threads = strings.Replace(fullDefaults.threads, `"hasNextPage":false,"endCursor":"t"`, `"hasNextPage":true,"endCursor":"T1"`, 1)
	c, _ = client(
		[2]string{"endCursor=T1", "ERR:gh: HTTP 502"},
		[2]string{"p7:", `{"data":{"repository":{"p7":` + fullNode(7, more) + `,"p9":` + fullNode(9, fullDefaults) + `}}}`})
	read, failed = c.FullRead("acme/widgets", []int{7, 9})
	if failed[7] == nil || len(read) != 1 || read[9].Number != 9 {
		t.Fatalf("a failed page of PR 7's threads read as %v, %v", read, failed)
	}

	// A request that did not answer fails every PR it asked about.
	c, _ = client([2]string{"query", "ERR:gh: connection reset"})
	read, failed = c.FullRead("acme/widgets", []int{7, 8})
	if len(read) != 0 || failed[7] == nil || failed[8] == nil {
		t.Fatalf("read %v, failed %v", read, failed)
	}
}
