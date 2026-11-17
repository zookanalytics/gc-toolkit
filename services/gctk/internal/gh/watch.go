package gh

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"maps"
	"slices"
	"strconv"
	"strings"
)

// The reads that watch a PR (specs/tk-1tfzr71.149/design.md, sections 1 and
// 4): the cheap question, which asks many PRs in one request for their signs
// and no detail, and the two reads of one PR that the one-PR update makes when
// a sign moved, its own facts with the check runs at its head, and its
// conversation, each in one request.

// SignsBatch is the most PRs one request of the cheap question asks about.
// GitHub ends a request at 10 seconds, and a request of 50 took 2.4 to 4.2.
const SignsBatch = 50

// Signs are a PR's cheap signs: its state and draft flag, its head, its base
// and the base's tip, when GitHub last changed it, its comments, conversation
// and inline together, its reviews and the dismissed among them, its labels,
// every one, sorted, and its checks at the head counted by state. Rollup is the
// head's check rollup state, empty when the head has none. CheckRuns and
// Statuses count the check runs and the commit statuses there by state,
// holding only the states that count one or more.
type Signs struct {
	Number      int
	State       string
	IsDraft     bool
	HeadRefOid  string
	BaseRefName string
	BaseTip     string
	UpdatedAt   string
	Comments    int
	Reviews     int
	Dismissed   int
	Labels      []string
	Rollup      string
	Contexts    int
	CheckRuns   map[string]int
	Statuses    map[string]int
}

const signsFragment = `fragment signs on PullRequest{number state isDraft headRefOid baseRefName baseRef{target{oid}} updatedAt
  totalCommentsCount reviews{totalCount} dismissed:reviews(states:[DISMISSED]){totalCount}
  labels(first:100){pageInfo{hasNextPage endCursor} nodes{name}}
  commits(last:1){nodes{commit{statusCheckRollup{state contexts{totalCount
    checkRunCountsByState{state count} statusContextCountsByState{state count}}}}}}}`

const labelsQuery = `query($owner:String!,$name:String!,$number:Int!,$endCursor:String!){
  repository(owner:$owner,name:$name){pullRequest(number:$number){
    labels(first:100,after:$endCursor){pageInfo{hasNextPage endCursor} nodes{name}}}}}`

// signsNode is one PR's signs as the cheap question asks for them. The net's
// read (full.go) asks for the same fields and pages more of two of them: the
// time each review on the first page last changed, and the check runs among
// the head's contexts.
type signsNode struct {
	Number      int    `json:"number"`
	State       string `json:"state"`
	IsDraft     bool   `json:"isDraft"`
	HeadRefOid  string `json:"headRefOid"`
	BaseRefName string `json:"baseRefName"`
	BaseRef     *struct {
		Target *struct {
			Oid string `json:"oid"`
		} `json:"target"`
	} `json:"baseRef"`
	UpdatedAt string `json:"updatedAt"`
	Comments  int    `json:"totalCommentsCount"`
	Reviews   *struct {
		TotalCount int `json:"totalCount"`
		connection[postTime]
	} `json:"reviews"`
	Dismissed *struct {
		TotalCount int `json:"totalCount"`
	} `json:"dismissed"`
	Labels  *connection[labelNode] `json:"labels"`
	Commits *struct {
		Nodes []struct {
			Commit *struct {
				Oid    string `json:"oid"`
				Rollup *struct {
					State    string `json:"state"`
					Contexts *struct {
						TotalCount int          `json:"totalCount"`
						Runs       []stateCount `json:"checkRunCountsByState"`
						Statuses   []stateCount `json:"statusContextCountsByState"`
						connection[contextNode]
					} `json:"contexts"`
				} `json:"statusCheckRollup"`
			} `json:"commit"`
		} `json:"nodes"`
	} `json:"commits"`
}

type labelNode struct {
	Name string `json:"name"`
}

type stateCount struct {
	State string `json:"state"`
	Count int    `json:"count"`
}

// counts holds each state that counts one or more.
func counts(l []stateCount) map[string]int {
	out := map[string]int{}
	for _, c := range l {
		if c.Count > 0 {
			out[c.State] += c.Count
		}
	}
	return out
}

// signs is the node's signs with the labels on its first page.
func (n signsNode) signs() (Signs, error) {
	if n.Reviews == nil || n.Dismissed == nil || n.Labels == nil || n.Commits == nil {
		return Signs{}, fmt.Errorf("the signs of PR %d lack a part GitHub always gives", n.Number)
	}
	s := Signs{Number: n.Number, State: n.State, IsDraft: n.IsDraft, HeadRefOid: n.HeadRefOid,
		BaseRefName: n.BaseRefName, UpdatedAt: n.UpdatedAt, Comments: n.Comments,
		Reviews: n.Reviews.TotalCount, Dismissed: n.Dismissed.TotalCount,
		CheckRuns: map[string]int{}, Statuses: map[string]int{}}
	if n.BaseRef != nil && n.BaseRef.Target != nil {
		s.BaseTip = n.BaseRef.Target.Oid
	}
	for _, l := range n.Labels.Nodes {
		s.Labels = append(s.Labels, l.Name)
	}
	for _, c := range n.Commits.Nodes {
		if c.Commit == nil || c.Commit.Rollup == nil {
			continue
		}
		s.Rollup = c.Commit.Rollup.State
		if x := c.Commit.Rollup.Contexts; x != nil {
			s.Contexts, s.CheckRuns, s.Statuses = x.TotalCount, counts(x.Runs), counts(x.Statuses)
		}
	}
	return s, nil
}

// signsOf is PR number's signs in owner/name from its node, with its labels
// read on past the first page until they end, sorted.
func (c *Client) signsOf(owner, name string, number int, n *signsNode) (Signs, error) {
	s, err := n.signs()
	if err != nil {
		return Signs{}, err
	}
	if !n.Labels.PageInfo.HasNextPage {
		slices.Sort(s.Labels)
		return s, nil
	}
	more, err := pageOn(c, labelsQuery, pageVars(owner, name, number), n.Labels.PageInfo.EndCursor,
		prList[labelNode]("labels"))
	if err != nil {
		return Signs{}, fmt.Errorf("the labels of PR %d: %w", number, err)
	}
	for _, l := range more {
		s.Labels = append(s.Labels, l.Name)
	}
	slices.Sort(s.Labels)
	return s, nil
}

// Signs asks GitHub for the signs of each PR numbered in repo, owner/name, in
// one request for each SignsBatch of them, with one aliased field for each PR.
// A PR whose labels pass the first page has its labels read on, a page at a
// time, until they end. It returns the signs of each PR read whole and the
// error of each PR that was not: one an error of the answer names by its path,
// one GitHub returned nothing for, and one whose later page of labels failed.
// A request that did not answer, or whose answer names an error for no one PR,
// fails every PR it asked about.
func (c *Client) Signs(repo string, numbers []int) (map[int]Signs, map[int]error) {
	return readBatched(c, repo, numbers, SignsBatch, "signs", func(int) string { return "...signs" },
		signsFragment, (*Client).signsOf)
}

// readBatched reads each PR numbered in repo, owner/name, in one request for
// each size of them through aliasedRead, selecting field for each PR with
// fragments after the query, and makes each PR's result of its node with take,
// which can read on what the node leaves on a later page. It returns each PR's
// result and the error of each PR that has none.
func readBatched[T, R any](c *Client, repo string, numbers []int, size int, what string, field func(int) string,
	fragments string, take func(c *Client, owner, name string, number int, node *T) (R, error)) (map[int]R, map[int]error) {
	read, failed := map[int]R{}, map[int]error{}
	owner, name, err := splitRepo(repo)
	if err != nil {
		for _, n := range numbers {
			failed[n] = err
		}
		return read, failed
	}
	numbers = slices.Compact(slices.Sorted(slices.Values(numbers)))
	for start := 0; start < len(numbers); start += size {
		batch := numbers[start:min(start+size, len(numbers))]
		nodes, errs := aliasedRead[T](c, owner, name, what, batch, field, fragments)
		maps.Copy(failed, errs)
		for _, n := range slices.Sorted(maps.Keys(nodes)) {
			r, err := take(c, owner, name, n, nodes[n])
			if err != nil {
				failed[n] = fmt.Errorf("github: %w", err)
				continue
			}
			read[n] = r
		}
	}
	return read, failed
}

// aliasedRead asks GitHub in one request for one aliased field of each PR
// numbered in batch, p<number>, holding what field selects for that PR, with
// fragments after the query, and decodes each PR's field as a T. It returns the
// field of each PR it read and the error of each PR it did not: one an error of
// the answer names by its path, and one GitHub returned nothing for. A request
// that did not answer, or whose answer names an error for no one PR, fails every
// PR in batch. what names the read in an error.
func aliasedRead[T any](c *Client, owner, name, what string, batch []int, field func(int) string,
	fragments string) (map[int]*T, map[int]error) {
	nodes, failed := map[int]*T{}, map[int]error{}
	var q strings.Builder
	q.WriteString("query($owner:String!,$name:String!){repository(owner:$owner,name:$name){")
	for _, n := range batch {
		if n < 1 {
			failed[n] = fmt.Errorf("github: %d is no pull request number", n)
			continue
		}
		fmt.Fprintf(&q, "\n  p%d:pullRequest(number:%d){%s}", n, n, field(n))
	}
	q.WriteString("}}\n" + fragments)
	failAll := func(err error) {
		for _, n := range batch {
			if _, done := failed[n]; !done {
				failed[n] = err
			}
		}
	}
	raw, runErr := c.run("api", "--hostname", c.host, "graphql", "-f", "query="+q.String(),
		"-f", "owner="+owner, "-f", "name="+name)
	var page struct {
		Data *struct {
			Repository map[string]*T `json:"repository"`
		} `json:"data"`
		Errors []struct {
			Path    []any  `json:"path"`
			Message string `json:"message"`
		} `json:"errors"`
	}
	if len(bytes.TrimSpace(raw)) == 0 {
		if runErr == nil {
			runErr = errors.New("github: the read returned no page")
		}
		failAll(runErr)
		return nodes, failed
	}
	if err := json.Unmarshal(raw, &page); err != nil {
		failAll(fmt.Errorf("github: the %s did not decode: %w", what, err))
		return nodes, failed
	}
	if runErr != nil && len(page.Errors) == 0 {
		failAll(runErr)
		return nodes, failed
	}
	for _, e := range page.Errors {
		n, ok := aliased(e.Path)
		if !ok {
			failAll(fmt.Errorf("github: the %s failed: %s", what, e.Message))
			return nodes, failed
		}
		failed[n] = fmt.Errorf("github: the %s of PR %d failed: %s", what, n, e.Message)
	}
	if page.Data == nil || page.Data.Repository == nil {
		err := runErr
		if err == nil {
			err = fmt.Errorf("github: the %s held no data", what)
		}
		failAll(err)
		return nodes, failed
	}
	for _, n := range batch {
		if _, done := failed[n]; done {
			continue
		}
		node := page.Data.Repository[fmt.Sprintf("p%d", n)]
		if node == nil {
			failed[n] = fmt.Errorf("github: %s/%s holds no pull request %d", owner, name, n)
			continue
		}
		nodes[n] = node
	}
	return nodes, failed
}

// aliased reads the PR an error's path names through its alias, p<number>,
// the field below the repository.
func aliased(path []any) (int, bool) {
	if len(path) < 2 {
		return 0, false
	}
	alias, ok := path[1].(string)
	if !ok || !strings.HasPrefix(alias, "p") {
		return 0, false
	}
	n, err := strconv.Atoi(alias[1:])
	return n, err == nil && n > 0
}

// pageVars are the variables of a query for a later page of one of PR
// number's lists in owner/name.
func pageVars(owner, name string, number int) []string {
	return []string{"-f", "owner=" + owner, "-f", "name=" + name, "-F", "number=" + strconv.Itoa(number)}
}

// prList finds field, one of a PR's lists, in a page of a query that reads it.
func prList[T any](field string) func(json.RawMessage) (*connection[T], error) {
	return func(data json.RawMessage) (*connection[T], error) {
		var page struct {
			Repository *struct {
				PullRequest map[string]*connection[T] `json:"pullRequest"`
			} `json:"repository"`
		}
		if err := json.Unmarshal(data, &page); err != nil {
			return nil, err
		}
		if page.Repository == nil || page.Repository.PullRequest == nil || page.Repository.PullRequest[field] == nil {
			return nil, fmt.Errorf("the page holds no %s", field)
		}
		return page.Repository.PullRequest[field], nil
	}
}

// pageOn reads a list on from after, the end cursor of a page already read, a
// page at a time until the list ends, through query, which takes where its page
// starts as $endCursor beside vars. list finds the list in a page's data.
func pageOn[T any](c *Client, query string, vars []string, after string,
	list func(json.RawMessage) (*connection[T], error)) ([]T, error) {
	var out []T
	for after != "" {
		var next string
		err := c.graphql(query, append(slices.Clone(vars), "-f", "endCursor="+after), false, func(data json.RawMessage) error {
			l, err := list(data)
			if err != nil {
				return err
			}
			out = append(out, l.Nodes...)
			if l.PageInfo.HasNextPage {
				if l.PageInfo.EndCursor == "" {
					return fmt.Errorf("the page after %s says more follow and names no end cursor", after)
				}
				next = l.PageInfo.EndCursor
			}
			return nil
		})
		if err != nil {
			return nil, err
		}
		if next == after {
			return nil, fmt.Errorf("the list pages past %s to itself", after)
		}
		after = next
	}
	return out, nil
}

// whole is the list whose first page is first, read on through query from
// where that page ended while more follow, as pageOn reads it.
func whole[T any](c *Client, first *connection[T], query string, vars []string,
	list func(json.RawMessage) (*connection[T], error)) ([]T, error) {
	out := slices.Clone(first.Nodes)
	if !first.PageInfo.HasNextPage {
		return out, nil
	}
	if first.PageInfo.EndCursor == "" {
		return nil, errors.New("the first page says more follow and names no end cursor")
	}
	more, err := pageOn(c, query, vars, first.PageInfo.EndCursor, list)
	if err != nil {
		return nil, err
	}
	return append(out, more...), nil
}

// PRPart is a PR's own facts, read in one request with, when asked, the check
// suites at its head, each with the latest result of its check runs and whether
// the PR requires each. ChecksAt is the commit the check suites were read at,
// the PR's last commit, empty when they were not asked for.
type PRPart struct {
	PullRequest
	Suites   []CheckSuite
	ChecksAt string
}

const prPartFields = `id number url state isDraft headRefName headRefOid baseRefName mergeStateStatus
    repository{nameWithOwner} mergedAt mergeCommit{oid} isInMergeQueue isMergeQueueEnabled`

// The check suites at the PR's last commit, read with GitHub's LATEST filter as
// CheckSuites reads them.
const prChecksFields = `
    commits(last:1){nodes{commit{oid checkSuites(first:100){pageInfo{hasNextPage endCursor}
      nodes{databaseId checkRuns(first:100,filterBy:{checkType:LATEST}){pageInfo{hasNextPage}
        nodes{name status conclusion isRequired(pullRequestNumber:$number)}}}}}}}`

// prNode is a PR's own facts as the reads ask for them.
type prNode struct {
	ID               string `json:"id"`
	Number           int    `json:"number"`
	URL              string `json:"url"`
	State            string `json:"state"`
	IsDraft          bool   `json:"isDraft"`
	HeadRefName      string `json:"headRefName"`
	HeadRefOid       string `json:"headRefOid"`
	BaseRefName      string `json:"baseRefName"`
	MergeStateStatus string `json:"mergeStateStatus"`
	Repository       struct {
		NameWithOwner string `json:"nameWithOwner"`
	} `json:"repository"`
	MergedAt    *string `json:"mergedAt"`
	MergeCommit *struct {
		Oid string `json:"oid"`
	} `json:"mergeCommit"`
	IsInMergeQueue      bool `json:"isInMergeQueue"`
	IsMergeQueueEnabled bool `json:"isMergeQueueEnabled"`
}

func (p prNode) pullRequest() PullRequest {
	out := PullRequest{
		ID: p.ID, Number: p.Number, URL: p.URL, State: p.State, IsDraft: p.IsDraft,
		HeadRefName: p.HeadRefName, HeadRefOid: p.HeadRefOid, BaseRefName: p.BaseRefName,
		MergeStateStatus: p.MergeStateStatus, Repository: p.Repository.NameWithOwner,
		InMergeQueue: p.IsInMergeQueue, MergeQueueEnabled: p.IsMergeQueueEnabled,
	}
	if p.MergedAt != nil {
		out.MergedAt = *p.MergedAt
	}
	if p.MergeCommit != nil {
		out.MergeCommit = p.MergeCommit.Oid
	}
	return out
}

// suiteNode is a check suite as the reads ask for it.
type suiteNode struct {
	ID        int64 `json:"databaseId"`
	CheckRuns *struct {
		PageInfo struct {
			HasNextPage bool `json:"hasNextPage"`
		} `json:"pageInfo"`
		Nodes []struct {
			Name       string  `json:"name"`
			Status     string  `json:"status"`
			Conclusion *string `json:"conclusion"`
			IsRequired bool    `json:"isRequired"`
		} `json:"nodes"`
	} `json:"checkRuns"`
}

func (n suiteNode) suite(oid string) (CheckSuite, error) {
	if n.CheckRuns == nil {
		return CheckSuite{}, fmt.Errorf("check suite %d at %s holds no check runs", n.ID, oid)
	}
	if n.CheckRuns.PageInfo.HasNextPage {
		return CheckSuite{}, fmt.Errorf("check suite %d at %s has more check runs than one page holds", n.ID, oid)
	}
	s := CheckSuite{ID: n.ID}
	for _, r := range n.CheckRuns.Nodes {
		run := CheckRun{Name: r.Name, Status: r.Status, Required: r.IsRequired}
		if r.Conclusion != nil {
			run.Conclusion = *r.Conclusion
		}
		s.Runs = append(s.Runs, run)
	}
	return s, nil
}

// PullRequestPart reads PR number in repo, and with checks the check suites at
// its last commit, in one request. Check suites past the first page are read
// on, to their end, by CheckSuites.
func (c *Client) PullRequestPart(repo string, number int, checks bool) (*PRPart, error) {
	vars, err := prVars(repo, number)
	if err != nil {
		return nil, err
	}
	fields := prPartFields
	if checks {
		fields += prChecksFields
	}
	query := `query($owner:String!,$name:String!,$number:Int!){
  repository(owner:$owner,name:$name){pullRequest(number:$number){
    ` + fields + `}}}`
	var page struct {
		Repository *struct {
			PullRequest *struct {
				prNode
				Commits *struct {
					Nodes []struct {
						Commit *struct {
							Oid    string                 `json:"oid"`
							Suites *connection[suiteNode] `json:"checkSuites"`
						} `json:"commit"`
					} `json:"nodes"`
				} `json:"commits"`
			} `json:"pullRequest"`
		} `json:"repository"`
	}
	if err := c.graphql(query, vars, false, func(data json.RawMessage) error {
		return json.Unmarshal(data, &page)
	}); err != nil {
		return nil, err
	}
	if page.Repository == nil || page.Repository.PullRequest == nil {
		return nil, fmt.Errorf("github: %s holds no pull request %d", repo, number)
	}
	p := page.Repository.PullRequest
	out := &PRPart{PullRequest: p.prNode.pullRequest()}
	if !checks {
		return out, nil
	}
	if p.Commits == nil || len(p.Commits.Nodes) != 1 || p.Commits.Nodes[0].Commit == nil ||
		p.Commits.Nodes[0].Commit.Suites == nil {
		return nil, fmt.Errorf("github: %s#%d names no last commit with its check suites", repo, number)
	}
	commit := p.Commits.Nodes[0].Commit
	out.ChecksAt = commit.Oid
	if commit.Suites.PageInfo.HasNextPage {
		suites, err := c.CheckSuites(repo, commit.Oid, number)
		if err != nil {
			return nil, err
		}
		out.Suites = suites
		return out, nil
	}
	out.Suites = []CheckSuite{}
	for _, n := range commit.Suites.Nodes {
		s, err := n.suite(commit.Oid)
		if err != nil {
			return nil, fmt.Errorf("github: %w", err)
		}
		out.Suites = append(out.Suites, s)
	}
	return out, nil
}

// Conversation is a PR's conversation: its reviews, its review threads with
// their comments, its conversation comments, each oldest first and each post
// with when it last changed, and GitHub's review decision.
type Conversation struct {
	Reviews        []Review
	Threads        []Thread
	Comments       []IssueComment
	ReviewDecision string
}

const conversationQuery = `query($owner:String!,$name:String!,$number:Int!){
  repository(owner:$owner,name:$name){pullRequest(number:$number){
    reviewDecision
    reviews(first:100){pageInfo{hasNextPage endCursor} nodes{` + reviewFields + `}}
    reviewThreads(first:100){pageInfo{hasNextPage endCursor}
      nodes{id isResolved comments(first:100){pageInfo{hasNextPage}
        nodes{` + commentFields + `}}}}
    comments(first:100){pageInfo{hasNextPage endCursor} nodes{` + issueCommentFields + `}}}}}`

// Conversation reads PR number's conversation in repo in one request. A list
// past its first page is read again on its own, to its end: the reviews, the
// threads, a thread's comments or the conversation comments.
func (c *Client) Conversation(repo string, number int) (*Conversation, error) {
	vars, err := prVars(repo, number)
	if err != nil {
		return nil, err
	}
	var page struct {
		Repository *struct {
			PullRequest *struct {
				ReviewDecision *string                       `json:"reviewDecision"`
				Reviews        *connection[reviewNode]       `json:"reviews"`
				Threads        *connection[threadNode]       `json:"reviewThreads"`
				Comments       *connection[issueCommentNode] `json:"comments"`
			} `json:"pullRequest"`
		} `json:"repository"`
	}
	if err := c.graphql(conversationQuery, vars, false, func(data json.RawMessage) error {
		return json.Unmarshal(data, &page)
	}); err != nil {
		return nil, err
	}
	if page.Repository == nil || page.Repository.PullRequest == nil {
		return nil, fmt.Errorf("github: %s holds no pull request %d", repo, number)
	}
	p := page.Repository.PullRequest
	if p.Reviews == nil || p.Threads == nil || p.Comments == nil {
		return nil, fmt.Errorf("github: the conversation of %s#%d lacks a list GitHub always gives", repo, number)
	}
	out := &Conversation{Reviews: []Review{}, Threads: []Thread{}, Comments: []IssueComment{}}
	if p.ReviewDecision != nil {
		out.ReviewDecision = *p.ReviewDecision
	}
	if p.Reviews.PageInfo.HasNextPage {
		if out.Reviews, err = c.Reviews(repo, number); err != nil {
			return nil, err
		}
	} else {
		for _, n := range p.Reviews.Nodes {
			v, err := n.review()
			if err != nil {
				return nil, fmt.Errorf("github: %w", err)
			}
			out.Reviews = append(out.Reviews, v)
		}
	}
	if p.Threads.PageInfo.HasNextPage {
		if out.Threads, err = c.ReviewThreads(repo, number); err != nil {
			return nil, err
		}
	} else {
		for _, n := range p.Threads.Nodes {
			t, long, err := n.thread()
			if err != nil {
				return nil, fmt.Errorf("github: %w", err)
			}
			if long {
				if t.Comments, err = c.threadComments(t.ID); err != nil {
					return nil, err
				}
			}
			out.Threads = append(out.Threads, t)
		}
	}
	if p.Comments.PageInfo.HasNextPage {
		if out.Comments, err = c.IssueComments(repo, number); err != nil {
			return nil, err
		}
	} else {
		for _, n := range p.Comments.Nodes {
			cm, err := n.comment()
			if err != nil {
				return nil, fmt.Errorf("github: %w", err)
			}
			out.Comments = append(out.Comments, cm)
		}
	}
	return out, nil
}

// threadNode is a review thread as the reads ask for it.
type threadNode struct {
	ID         string `json:"id"`
	IsResolved bool   `json:"isResolved"`
	Comments   *struct {
		PageInfo struct {
			HasNextPage bool `json:"hasNextPage"`
		} `json:"pageInfo"`
		Nodes []commentNode `json:"nodes"`
	} `json:"comments"`
}

// thread is the thread with the comments its first page holds, and whether it
// holds more than that page.
func (n threadNode) thread() (Thread, bool, error) {
	if n.Comments == nil {
		return Thread{}, false, fmt.Errorf("review thread %s holds no comments", n.ID)
	}
	t := Thread{ID: n.ID, Resolved: n.IsResolved}
	for _, cn := range n.Comments.Nodes {
		cm, err := cn.comment()
		if err != nil {
			return Thread{}, false, err
		}
		t.Comments = append(t.Comments, cm)
	}
	return t, n.Comments.PageInfo.HasNextPage, nil
}

// splitRepo reads owner/name.
func splitRepo(repo string) (owner, name string, err error) {
	owner, name, ok := strings.Cut(repo, "/")
	if !ok || owner == "" || name == "" || strings.Contains(name, "/") {
		return "", "", fmt.Errorf("github: %q names no repository as owner/name", repo)
	}
	return owner, name, nil
}
