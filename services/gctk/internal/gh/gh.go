// Package gh is gctk's seam to GitHub (docs/gctk-architecture.md, "The
// adapters"). Each read is one `gh api` call against the host the caller
// names, paginated to its end where GitHub pages the answer, and returns
// GitHub's facts as GitHub states them. It holds no rule of the pack's: which
// review counts, which check passes and which post is feedback are the pr
// domain's to decide.
//
// A read that GitHub did not answer whole returns an error, never a partial
// answer: a page that does not decode, a GraphQL error, a connection cut short
// or an id that is not a number. A decision read off part of a PR's reviews or
// checks would be a decision about another PR.
package gh

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os/exec"
	"strconv"
	"strings"
)

// Runner runs gh with args and returns its stdout. A failure carries gh's own
// message.
type Runner func(args ...string) ([]byte, error)

// Client reads GitHub through gh, as the account gh is logged in as on host.
type Client struct {
	host string
	run  Runner
}

// New returns a client for host, such as github.com, that runs the gh on PATH.
func New(host string) *Client { return &Client{host: host, run: gh} }

// NewWithRunner returns a client for host that runs gh through run, so the
// adapter's own tests serve recorded answers.
func NewWithRunner(host string, run Runner) *Client { return &Client{host: host, run: run} }

// gh runs the gh on PATH.
func gh(args ...string) ([]byte, error) {
	cmd := exec.Command("gh", args...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		var ee *exec.ExitError
		if msg := strings.TrimSpace(stderr.String()); errors.As(err, &ee) && msg != "" {
			return nil, fmt.Errorf("gh: %s", msg)
		}
		return nil, fmt.Errorf("gh: %w", err)
	}
	return out, nil
}

// PullRequest is a PR as GitHub reports it. ID is its node id, which a merge
// request names it by. State is OPEN, CLOSED or MERGED. MergeStateStatus is
// GitHub's merge state, such as CLEAN, BLOCKED or DIRTY. Repository is the base
// repository, owner/name. MergedAt and MergeCommit are set once it merged.
// InMergeQueue is whether it is in a merge queue, and MergeQueueEnabled whether
// its base requires one (isMergeQueueEnabled).
type PullRequest struct {
	ID                string
	Number            int
	URL               string
	State             string
	IsDraft           bool
	HeadRefName       string
	HeadRefOid        string
	BaseRefName       string
	MergeStateStatus  string
	Repository        string
	MergedAt          string
	MergeCommit       string
	InMergeQueue      bool
	MergeQueueEnabled bool
}

// Review is one review of a PR. State is APPROVED, CHANGES_REQUESTED,
// COMMENTED, DISMISSED or PENDING. AuthorCanPush is whether its author can push
// to the repository (authorCanPushToRepository).
type Review struct {
	ID            int64
	State         string
	Body          string
	SubmittedAt   string
	Author        string
	AuthorCanPush bool
}

// CheckSuite is one check suite at a commit, with the latest result of each of
// its check runs.
type CheckSuite struct {
	ID   int64
	Runs []CheckRun
}

// CheckRun is one check run's latest result in its suite. Status is
// QUEUED, IN_PROGRESS, COMPLETED and the like, and Conclusion, set once it
// completed, is SUCCESS, FAILURE, NEUTRAL, CANCELLED, SKIPPED, TIMED_OUT,
// ACTION_REQUIRED, STALE or STARTUP_FAILURE. Required is whether the PR the
// read named requires it to pass before merging (isRequired).
type CheckRun struct {
	Name       string
	Status     string
	Conclusion string
	Required   bool
}

// Thread is one review thread with all of its comments, oldest first.
type Thread struct {
	ID       string
	Resolved bool
	Comments []Comment
}

// Comment is one inline comment on a PR. Review is the review that carried it,
// nil when GitHub names none. ViewerReactions are the reactions the account
// the read ran as left on it, such as THUMBS_UP.
type Comment struct {
	ID              int64
	Author          string
	Body            string
	CreatedAt       string
	Review          *CommentReview
	ViewerReactions []string
}

// CommentReview is the review that carried an inline comment.
type CommentReview struct {
	ID          int64
	State       string
	SubmittedAt string
}

// IssueComment is one comment on a PR's conversation.
type IssueComment struct {
	ID        int64
	Author    string
	Body      string
	CreatedAt string
}

// The queries. Each paginated one pages a single connection, which is what
// `gh api graphql --paginate` follows through $endCursor.
const (
	pullQuery = `query($owner:String!,$name:String!,$number:Int!){
  repository(owner:$owner,name:$name){pullRequest(number:$number){
    id number url state isDraft headRefName headRefOid baseRefName mergeStateStatus
    repository{nameWithOwner} mergedAt mergeCommit{oid} isInMergeQueue isMergeQueueEnabled}}}`

	// A merge request pinned to the head the caller judged: GitHub merges, or
	// adds the PR to its base's merge queue, only while the PR's head is that
	// commit (expectedHeadOid). The merge squashes, as gctk merge's
	// `gh pr merge --squash --match-head-commit` does.
	mergeMutation = `mutation($id:ID!,$head:GitObjectID!){
  mergePullRequest(input:{pullRequestId:$id,expectedHeadOid:$head,mergeMethod:SQUASH}){pullRequest{number}}}`

	enqueueMutation = `mutation($id:ID!,$head:GitObjectID!){
  enqueuePullRequest(input:{pullRequestId:$id,expectedHeadOid:$head}){mergeQueueEntry{id}}}`

	reviewsQuery = `query($owner:String!,$name:String!,$number:Int!,$endCursor:String){
  repository(owner:$owner,name:$name){pullRequest(number:$number){
    reviews(first:100,after:$endCursor){pageInfo{hasNextPage endCursor}
      nodes{fullDatabaseId state body submittedAt authorCanPushToRepository author{login}}}}}}`

	// The check runs are read with GitHub's LATEST filter, so a re-run's
	// result stands in place of the attempt it re-ran, in the suite of both.
	checksQuery = `query($owner:String!,$name:String!,$oid:GitObjectID!,$number:Int!,$endCursor:String){
  repository(owner:$owner,name:$name){object(oid:$oid){... on Commit{
    checkSuites(first:100,after:$endCursor){pageInfo{hasNextPage endCursor}
      nodes{databaseId checkRuns(first:100,filterBy:{checkType:LATEST}){pageInfo{hasNextPage}
        nodes{name status conclusion isRequired(pullRequestNumber:$number)}}}}}}}}`

	commentFields = `fullDatabaseId author{login} body createdAt
          pullRequestReview{fullDatabaseId submittedAt state}
          reactionGroups{content viewerHasReacted}`

	threadsQuery = `query($owner:String!,$name:String!,$number:Int!,$endCursor:String){
  repository(owner:$owner,name:$name){pullRequest(number:$number){
    reviewThreads(first:100,after:$endCursor){pageInfo{hasNextPage endCursor}
      nodes{id isResolved comments(first:100){pageInfo{hasNextPage}
        nodes{` + commentFields + `}}}}}}}`

	threadCommentsQuery = `query($id:ID!,$endCursor:String){
  node(id:$id){... on PullRequestReviewThread{
    comments(first:100,after:$endCursor){pageInfo{hasNextPage endCursor}
      nodes{` + commentFields + `}}}}}`

	issueCommentsQuery = `query($owner:String!,$name:String!,$number:Int!,$endCursor:String){
  repository(owner:$owner,name:$name){pullRequest(number:$number){
    comments(first:100,after:$endCursor){pageInfo{hasNextPage endCursor}
      nodes{fullDatabaseId body createdAt author{login}}}}}}`
)

// PullRequest reads PR number in repo, owner/name.
func (c *Client) PullRequest(repo string, number int) (*PullRequest, error) {
	var page struct {
		Repository *struct {
			PullRequest *struct {
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
			} `json:"pullRequest"`
		} `json:"repository"`
	}
	vars, err := prVars(repo, number)
	if err != nil {
		return nil, err
	}
	if err := c.graphql(pullQuery, vars, false, func(data json.RawMessage) error {
		return json.Unmarshal(data, &page)
	}); err != nil {
		return nil, err
	}
	if page.Repository == nil || page.Repository.PullRequest == nil {
		return nil, fmt.Errorf("github: %s holds no pull request %d", repo, number)
	}
	p := page.Repository.PullRequest
	out := &PullRequest{
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
	return out, nil
}

// MergePullRequest asks GitHub to squash-merge the PR whose node id is id, only
// while its head is head. An error is a request GitHub refused, such as one a
// push since the caller's read made stale, or one whose answer did not arrive,
// which may still take effect: the caller reads the PR again to learn which.
func (c *Client) MergePullRequest(id, head string) error {
	return c.mutate(mergeMutation, id, head)
}

// EnqueuePullRequest asks GitHub to add the PR whose node id is id to its base's
// merge queue, only while its head is head. An error reads as MergePullRequest's.
func (c *Client) EnqueuePullRequest(id, head string) error {
	return c.mutate(enqueueMutation, id, head)
}

// mutate runs a request that names a PR by its node id and pins it to head.
func (c *Client) mutate(query, id, head string) error {
	if id == "" {
		return errors.New("github: a merge request names no pull request")
	}
	if head == "" {
		return errors.New("github: a merge request names no head to pin it to")
	}
	return c.graphql(query, []string{"-f", "id=" + id, "-f", "head=" + head}, false,
		func(json.RawMessage) error { return nil })
}

// Reviews reads every review of PR number in repo, oldest first.
func (c *Client) Reviews(repo string, number int) ([]Review, error) {
	vars, err := prVars(repo, number)
	if err != nil {
		return nil, err
	}
	var out []Review
	err = c.graphql(reviewsQuery, vars, true, func(data json.RawMessage) error {
		var page struct {
			Repository *struct {
				PullRequest *struct {
					Reviews *connection[struct {
						ID            string `json:"fullDatabaseId"`
						State         string `json:"state"`
						Body          string `json:"body"`
						SubmittedAt   string `json:"submittedAt"`
						AuthorCanPush bool   `json:"authorCanPushToRepository"`
						Author        *actor `json:"author"`
					}] `json:"reviews"`
				} `json:"pullRequest"`
			} `json:"repository"`
		}
		if err := json.Unmarshal(data, &page); err != nil {
			return err
		}
		if page.Repository == nil || page.Repository.PullRequest == nil || page.Repository.PullRequest.Reviews == nil {
			return fmt.Errorf("the page holds no reviews of %s#%d", repo, number)
		}
		for _, n := range page.Repository.PullRequest.Reviews.Nodes {
			id, err := databaseID(n.ID)
			if err != nil {
				return err
			}
			out = append(out, Review{ID: id, State: n.State, Body: n.Body, SubmittedAt: n.SubmittedAt,
				Author: n.Author.name(), AuthorCanPush: n.AuthorCanPush})
		}
		return nil
	})
	return out, err
}

// CheckSuites reads every check suite at commit oid in repo, each with the
// latest result of its check runs and whether PR number requires each. A
// suite with more check runs than one page holds is an error.
func (c *Client) CheckSuites(repo, oid string, number int) ([]CheckSuite, error) {
	vars, err := prVars(repo, number)
	if err != nil {
		return nil, err
	}
	vars = append(vars, "-f", "oid="+oid)
	var out []CheckSuite
	err = c.graphql(checksQuery, vars, true, func(data json.RawMessage) error {
		var page struct {
			Repository *struct {
				Object *struct {
					CheckSuites *connection[struct {
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
					}] `json:"checkSuites"`
				} `json:"object"`
			} `json:"repository"`
		}
		if err := json.Unmarshal(data, &page); err != nil {
			return err
		}
		if page.Repository == nil || page.Repository.Object == nil || page.Repository.Object.CheckSuites == nil {
			return fmt.Errorf("the page holds no check suites at %s in %s", oid, repo)
		}
		for _, n := range page.Repository.Object.CheckSuites.Nodes {
			if n.CheckRuns == nil {
				return fmt.Errorf("check suite %d at %s holds no check runs", n.ID, oid)
			}
			if n.CheckRuns.PageInfo.HasNextPage {
				return fmt.Errorf("check suite %d at %s has more check runs than one page holds", n.ID, oid)
			}
			s := CheckSuite{ID: n.ID}
			for _, r := range n.CheckRuns.Nodes {
				run := CheckRun{Name: r.Name, Status: r.Status, Required: r.IsRequired}
				if r.Conclusion != nil {
					run.Conclusion = *r.Conclusion
				}
				s.Runs = append(s.Runs, run)
			}
			out = append(out, s)
		}
		return nil
	})
	return out, err
}

// commentNode is an inline comment as the thread reads ask for it.
type commentNode struct {
	ID        string `json:"fullDatabaseId"`
	Author    *actor `json:"author"`
	Body      string `json:"body"`
	CreatedAt string `json:"createdAt"`
	Review    *struct {
		ID          string `json:"fullDatabaseId"`
		SubmittedAt string `json:"submittedAt"`
		State       string `json:"state"`
	} `json:"pullRequestReview"`
	ReactionGroups []struct {
		Content          string `json:"content"`
		ViewerHasReacted bool   `json:"viewerHasReacted"`
	} `json:"reactionGroups"`
}

func (n commentNode) comment() (Comment, error) {
	id, err := databaseID(n.ID)
	if err != nil {
		return Comment{}, err
	}
	c := Comment{ID: id, Author: n.Author.name(), Body: n.Body, CreatedAt: n.CreatedAt}
	if n.Review != nil {
		rid, err := databaseID(n.Review.ID)
		if err != nil {
			return Comment{}, err
		}
		c.Review = &CommentReview{ID: rid, State: n.Review.State, SubmittedAt: n.Review.SubmittedAt}
	}
	for _, g := range n.ReactionGroups {
		if g.ViewerHasReacted {
			c.ViewerReactions = append(c.ViewerReactions, g.Content)
		}
	}
	return c, nil
}

// ReviewThreads reads every review thread of PR number in repo, each with all
// of its comments, oldest first. A thread with more comments than one page
// holds is read again on its own, to its end.
func (c *Client) ReviewThreads(repo string, number int) ([]Thread, error) {
	vars, err := prVars(repo, number)
	if err != nil {
		return nil, err
	}
	var out []Thread
	var long []int
	err = c.graphql(threadsQuery, vars, true, func(data json.RawMessage) error {
		var page struct {
			Repository *struct {
				PullRequest *struct {
					ReviewThreads *connection[struct {
						ID         string `json:"id"`
						IsResolved bool   `json:"isResolved"`
						Comments   *struct {
							PageInfo struct {
								HasNextPage bool `json:"hasNextPage"`
							} `json:"pageInfo"`
							Nodes []commentNode `json:"nodes"`
						} `json:"comments"`
					}] `json:"reviewThreads"`
				} `json:"pullRequest"`
			} `json:"repository"`
		}
		if err := json.Unmarshal(data, &page); err != nil {
			return err
		}
		if page.Repository == nil || page.Repository.PullRequest == nil || page.Repository.PullRequest.ReviewThreads == nil {
			return fmt.Errorf("the page holds no review threads of %s#%d", repo, number)
		}
		for _, n := range page.Repository.PullRequest.ReviewThreads.Nodes {
			if n.Comments == nil {
				return fmt.Errorf("review thread %s holds no comments", n.ID)
			}
			t := Thread{ID: n.ID, Resolved: n.IsResolved}
			for _, cn := range n.Comments.Nodes {
				cm, err := cn.comment()
				if err != nil {
					return err
				}
				t.Comments = append(t.Comments, cm)
			}
			if n.Comments.PageInfo.HasNextPage {
				long = append(long, len(out))
			}
			out = append(out, t)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	for _, i := range long {
		if out[i].Comments, err = c.threadComments(out[i].ID); err != nil {
			return nil, err
		}
	}
	return out, nil
}

// threadComments reads review thread id's comments from its first to its end.
func (c *Client) threadComments(id string) ([]Comment, error) {
	if id == "" {
		return nil, errors.New("github: a review thread with more comments than one page names no id")
	}
	var out []Comment
	err := c.graphql(threadCommentsQuery, []string{"-f", "id=" + id}, true, func(data json.RawMessage) error {
		var page struct {
			Node *struct {
				Comments *connection[commentNode] `json:"comments"`
			} `json:"node"`
		}
		if err := json.Unmarshal(data, &page); err != nil {
			return err
		}
		if page.Node == nil || page.Node.Comments == nil {
			return fmt.Errorf("the page holds no comments of review thread %s", id)
		}
		for _, n := range page.Node.Comments.Nodes {
			cm, err := n.comment()
			if err != nil {
				return err
			}
			out = append(out, cm)
		}
		return nil
	})
	return out, err
}

// IssueComments reads every comment on the conversation of PR number in repo,
// oldest first.
func (c *Client) IssueComments(repo string, number int) ([]IssueComment, error) {
	vars, err := prVars(repo, number)
	if err != nil {
		return nil, err
	}
	var out []IssueComment
	err = c.graphql(issueCommentsQuery, vars, true, func(data json.RawMessage) error {
		var page struct {
			Repository *struct {
				PullRequest *struct {
					Comments *connection[struct {
						ID        string `json:"fullDatabaseId"`
						Body      string `json:"body"`
						CreatedAt string `json:"createdAt"`
						Author    *actor `json:"author"`
					}] `json:"comments"`
				} `json:"pullRequest"`
			} `json:"repository"`
		}
		if err := json.Unmarshal(data, &page); err != nil {
			return err
		}
		if page.Repository == nil || page.Repository.PullRequest == nil || page.Repository.PullRequest.Comments == nil {
			return fmt.Errorf("the page holds no comments of %s#%d", repo, number)
		}
		for _, n := range page.Repository.PullRequest.Comments.Nodes {
			id, err := databaseID(n.ID)
			if err != nil {
				return err
			}
			out = append(out, IssueComment{ID: id, Author: n.Author.name(), Body: n.Body, CreatedAt: n.CreatedAt})
		}
		return nil
	})
	return out, err
}

// Login reads the login of the account gh acts as on the host.
func (c *Client) Login() (string, error) {
	raw, err := c.run("api", "--hostname", c.host, "user")
	if err != nil {
		return "", err
	}
	var u struct {
		Login string `json:"login"`
	}
	if err := json.Unmarshal(raw, &u); err != nil {
		return "", fmt.Errorf("github: the account gh acts as did not decode: %w", err)
	}
	if u.Login == "" {
		return "", errors.New("github: gh named no account it acts as")
	}
	return u.Login, nil
}

// connection is one page of a GraphQL connection.
type connection[T any] struct {
	PageInfo struct {
		HasNextPage bool   `json:"hasNextPage"`
		EndCursor   string `json:"endCursor"`
	} `json:"pageInfo"`
	Nodes []T `json:"nodes"`
}

// actor is a post's author, which GitHub leaves null for a deleted account.
type actor struct {
	Login string `json:"login"`
}

func (a *actor) name() string {
	if a == nil {
		return ""
	}
	return a.Login
}

// prVars are the variables every PR query takes.
func prVars(repo string, number int) ([]string, error) {
	owner, name, ok := strings.Cut(repo, "/")
	if !ok || owner == "" || name == "" || strings.Contains(name, "/") {
		return nil, fmt.Errorf("github: %q names no repository as owner/name", repo)
	}
	if number < 1 {
		return nil, fmt.Errorf("github: %d is no pull request number", number)
	}
	return []string{"-f", "owner=" + owner, "-f", "name=" + name, "-F", "number=" + strconv.Itoa(number)}, nil
}

// databaseID reads a fullDatabaseId, which GitHub gives as a string.
func databaseID(s string) (int64, error) {
	id, err := strconv.ParseInt(s, 10, 64)
	if err != nil || id < 1 {
		return 0, fmt.Errorf("github: %q is no database id", s)
	}
	return id, nil
}

// graphql runs query with vars and hands each page's data to take: one page,
// or every page when paginate is set. A page that carries GraphQL errors, holds
// no data or does not decode fails the read.
func (c *Client) graphql(query string, vars []string, paginate bool, take func(json.RawMessage) error) error {
	args := []string{"api", "--hostname", c.host, "graphql"}
	if paginate {
		args = append(args, "--paginate")
	}
	args = append(args, "-f", "query="+query)
	args = append(args, vars...)
	raw, err := c.run(args...)
	if err != nil {
		return err
	}
	dec := json.NewDecoder(bytes.NewReader(raw))
	pages := 0
	for {
		var page struct {
			Data   json.RawMessage   `json:"data"`
			Errors []json.RawMessage `json:"errors"`
		}
		if err := dec.Decode(&page); err != nil {
			if errors.Is(err, io.EOF) {
				break
			}
			return fmt.Errorf("github: a page did not decode: %w", err)
		}
		if len(page.Errors) > 0 {
			return fmt.Errorf("github: the query failed: %s", page.Errors[0])
		}
		if len(page.Data) == 0 || string(page.Data) == "null" {
			return errors.New("github: a page held no data")
		}
		if err := take(page.Data); err != nil {
			return fmt.Errorf("github: %w", err)
		}
		pages++
	}
	if pages == 0 {
		return errors.New("github: the read returned no page")
	}
	return nil
}
