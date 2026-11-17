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
// checks would be a decision about another PR. The cheap question (watch.go)
// asks about many PRs in one request, and answers each PR whole or with that
// PR's own error.
package gh

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// Runner runs gh with args and returns its stdout. A failure carries gh's own
// message, and returns what gh wrote to stdout beside it, since gh writes a
// GraphQL answer that carries errors and exits non-zero.
type Runner func(args ...string) ([]byte, error)

// Client reads GitHub through gh, as the account gh is logged in as on host.
// A call it makes through the gh on PATH stops when ctx ends.
type Client struct {
	host string
	run  Runner
	ctx  context.Context
}

// New returns a client for host, such as github.com, that runs the gh on PATH.
func New(host string) *Client { return &Client{host: host} }

// NewWithRunner returns a client for host that runs gh through run, so the
// adapter's own tests serve recorded answers.
func NewWithRunner(host string, run Runner) *Client { return &Client{host: host, run: run} }

// Within returns a client for c's host whose every call stops when ctx ends:
// the gh it is running is killed, and the call returns an error that wraps the
// one that ended ctx. GitHub may still take a request whose call was stopped,
// as it may one whose answer was lost. A client NewWithRunner made runs its
// runner as it is.
func (c *Client) Within(ctx context.Context) *Client {
	d := *c
	d.ctx = ctx
	return &d
}

// call runs gh with args: through the client's runner when it has one, else
// the gh on PATH, stopped when the client's context ends.
func (c *Client) call(args ...string) ([]byte, error) {
	if c.run != nil {
		return c.run(args...)
	}
	ctx := c.ctx
	if ctx == nil {
		ctx = context.Background()
	}
	return gh(ctx, args...)
}

// ghStopGrace bounds how long a stopped gh, or a child of it that holds its
// output, keeps a call waiting after the kill.
const ghStopGrace = 2 * time.Second

// gh runs the gh on PATH, killed when ctx ends. gh holds no lock that a kill
// leaves behind.
func gh(ctx context.Context, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, "gh", args...)
	cmd.WaitDelay = ghStopGrace
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		if ctx.Err() != nil {
			return out, fmt.Errorf("gh: the call was stopped: %w", ctx.Err())
		}
		var ee *exec.ExitError
		if msg := strings.TrimSpace(stderr.String()); errors.As(err, &ee) && msg != "" {
			return out, fmt.Errorf("gh: %s", msg)
		}
		return out, fmt.Errorf("gh: %w", err)
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
// to the repository (authorCanPushToRepository). Commit is the commit the
// review was given on, its commit_id, empty when GitHub names none. UpdatedAt
// is when the review last changed, which an edit of its text moves.
type Review struct {
	ID            int64
	State         string
	Body          string
	SubmittedAt   string
	UpdatedAt     string
	Author        string
	AuthorCanPush bool
	Commit        string
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
// the read ran as left on it, such as THUMBS_UP. UpdatedAt is when it last
// changed, which an edit of its text moves.
type Comment struct {
	ID              int64
	Author          string
	Body            string
	CreatedAt       string
	UpdatedAt       string
	Review          *CommentReview
	ViewerReactions []string
}

// CommentReview is the review that carried an inline comment.
type CommentReview struct {
	ID          int64
	State       string
	SubmittedAt string
}

// IssueComment is one comment on a PR's conversation. UpdatedAt is when it
// last changed, which an edit of its text moves.
type IssueComment struct {
	ID        int64
	Author    string
	Body      string
	CreatedAt string
	UpdatedAt string
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

	// The PR's stage, the two mutations gh pr ready and gh pr ready --undo
	// make, each naming the PR by its node id.
	readyMutation = `mutation($id:ID!){
  markPullRequestReadyForReview(input:{pullRequestId:$id}){pullRequest{isDraft}}}`

	draftMutation = `mutation($id:ID!){
  convertPullRequestToDraft(input:{pullRequestId:$id}){pullRequest{isDraft}}}`

	reviewsQuery = `query($owner:String!,$name:String!,$number:Int!,$endCursor:String){
  repository(owner:$owner,name:$name){pullRequest(number:$number){
    reviews(first:100,after:$endCursor){pageInfo{hasNextPage endCursor}
      nodes{` + reviewFields + `}}}}}`

	// The check runs are read with GitHub's LATEST filter, so a re-run's
	// result stands in place of the attempt it re-ran, in the suite of both.
	checksQuery = `query($owner:String!,$name:String!,$oid:GitObjectID!,$number:Int!,$endCursor:String){
  repository(owner:$owner,name:$name){object(oid:$oid){... on Commit{
    checkSuites(first:100,after:$endCursor){pageInfo{hasNextPage endCursor}
      nodes{databaseId checkRuns(first:100,filterBy:{checkType:LATEST}){pageInfo{hasNextPage}
        nodes{name status conclusion isRequired(pullRequestNumber:$number)}}}}}}}}`

	reviewFields = `fullDatabaseId state body submittedAt updatedAt authorCanPushToRepository author{login} commit{oid}`

	commentFields = `fullDatabaseId author{login} body createdAt updatedAt
          pullRequestReview{fullDatabaseId submittedAt state}
          reactionGroups{content viewerHasReacted}`

	issueCommentFields = `fullDatabaseId body createdAt updatedAt author{login}`

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
      nodes{` + issueCommentFields + `}}}}}`
)

// PullRequest reads PR number in repo, owner/name.
func (c *Client) PullRequest(repo string, number int) (*PullRequest, error) {
	var page struct {
		Repository *struct {
			PullRequest *prNode `json:"pullRequest"`
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
	out := page.Repository.PullRequest.pullRequest()
	return &out, nil
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

// MarkReady marks the PR whose node id is id ready for review. An error is a
// request GitHub refused or one whose answer did not arrive, which may still
// take effect: the caller reads the PR's draft flag again to learn which.
func (c *Client) MarkReady(id string) error { return c.stage(readyMutation, id) }

// ConvertToDraft returns the PR whose node id is id to draft. An error reads as
// MarkReady's.
func (c *Client) ConvertToDraft(id string) error { return c.stage(draftMutation, id) }

// stage runs a request that moves the PR whose node id is id between draft and
// ready.
func (c *Client) stage(query, id string) error {
	if id == "" {
		return errors.New("github: a change of a PR's stage names no pull request")
	}
	return c.graphql(query, []string{"-f", "id=" + id}, false, func(json.RawMessage) error { return nil })
}

// DismissReview dismisses review id of PR number in repo with message, through
// GitHub's review dismissal (PUT repos/<repo>/pulls/<n>/reviews/<id>/dismissals).
// An error is a dismissal GitHub refused, or one whose answer did not arrive,
// which may still take effect; Refused tells the two apart.
func (c *Client) DismissReview(repo string, number int, id int64, message string) error {
	if _, err := prVars(repo, number); err != nil {
		return err
	}
	if id < 1 {
		return fmt.Errorf("github: %d is no review id", id)
	}
	if strings.TrimSpace(message) == "" {
		return errors.New("github: a dismissal needs a message")
	}
	_, err := c.call("api", "--hostname", c.host, "-X", "PUT",
		fmt.Sprintf("repos/%s/pulls/%d/reviews/%d/dismissals", repo, number, id), "-f", "message="+message)
	return err
}

// httpStatus is the HTTP status gh reports for an API request GitHub answered
// with an error, as gh writes it at the end of its message: "(HTTP 422)".
var httpStatus = regexp.MustCompile(`\(HTTP ([0-9]{3})\)`)

// Refused reports whether err is GitHub's refusal of a request it answered: an
// HTTP status from 400 to 499, other than a rate limit. Any other error, such
// as a connection that failed, a server error or a rate limit, is a request
// whose answer did not arrive, which a later try may still see taken.
func Refused(err error) bool {
	if err == nil {
		return false
	}
	msg := err.Error()
	m := httpStatus.FindAllStringSubmatch(msg, -1)
	if len(m) == 0 {
		return false
	}
	code, _ := strconv.Atoi(m[len(m)-1][1])
	return code >= 400 && code < 500 && code != 429 && !strings.Contains(strings.ToLower(msg), "rate limit")
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
					Reviews *connection[reviewNode] `json:"reviews"`
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
			v, err := n.review()
			if err != nil {
				return err
			}
			out = append(out, v)
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

// reviewNode is a review as the reads ask for it.
type reviewNode struct {
	ID            string `json:"fullDatabaseId"`
	State         string `json:"state"`
	Body          string `json:"body"`
	SubmittedAt   string `json:"submittedAt"`
	UpdatedAt     string `json:"updatedAt"`
	AuthorCanPush bool   `json:"authorCanPushToRepository"`
	Author        *actor `json:"author"`
	Commit        *struct {
		Oid string `json:"oid"`
	} `json:"commit"`
}

func (n reviewNode) review() (Review, error) {
	id, err := databaseID(n.ID)
	if err != nil {
		return Review{}, err
	}
	v := Review{ID: id, State: n.State, Body: n.Body, SubmittedAt: n.SubmittedAt, UpdatedAt: n.UpdatedAt,
		Author: n.Author.name(), AuthorCanPush: n.AuthorCanPush}
	if n.Commit != nil {
		v.Commit = n.Commit.Oid
	}
	return v, nil
}

// issueCommentNode is a conversation comment as the reads ask for it.
type issueCommentNode struct {
	ID        string `json:"fullDatabaseId"`
	Body      string `json:"body"`
	CreatedAt string `json:"createdAt"`
	UpdatedAt string `json:"updatedAt"`
	Author    *actor `json:"author"`
}

func (n issueCommentNode) comment() (IssueComment, error) {
	id, err := databaseID(n.ID)
	if err != nil {
		return IssueComment{}, err
	}
	return IssueComment{ID: id, Author: n.Author.name(), Body: n.Body, CreatedAt: n.CreatedAt, UpdatedAt: n.UpdatedAt}, nil
}

// commentNode is an inline comment as the thread reads ask for it.
type commentNode struct {
	ID        string `json:"fullDatabaseId"`
	Author    *actor `json:"author"`
	Body      string `json:"body"`
	CreatedAt string `json:"createdAt"`
	UpdatedAt string `json:"updatedAt"`
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
	c := Comment{ID: id, Author: n.Author.name(), Body: n.Body, CreatedAt: n.CreatedAt, UpdatedAt: n.UpdatedAt}
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
					ReviewThreads *connection[threadNode] `json:"reviewThreads"`
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
			t, more, err := n.thread()
			if err != nil {
				return err
			}
			if more {
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
					Comments *connection[issueCommentNode] `json:"comments"`
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

// Login reads the login of the account gh acts as on the host.
func (c *Client) Login() (string, error) {
	raw, err := c.call("api", "--hostname", c.host, "user")
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
	owner, name, err := splitRepo(repo)
	if err != nil {
		return nil, err
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
	raw, err := c.call(args...)
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
