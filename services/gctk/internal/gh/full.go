package gh

import (
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strconv"
)

// The net's read (specs/tk-1tfzr71.149/design.md, section 2), which reads every
// PR the city owns in full every 10 minutes, so a change no cheap sign shows,
// such as a review thread resolved or an edit to a post, still reaches the
// PR's saved read. It reads the cheap question's signs and the facts no sign
// shows, and no post's text.

// FullReadBatch is the most PRs one request of the net's read asks about.
// GitHub counts a list nested in another once for each item that could hold
// it, so the inline comments of 10 review threads a PR make a request of 10
// PRs cost 2 points, and one of 9 cost 1.
const FullReadBatch = 10

// Full is the net's read of a PR: its cheap signs, and the facts no sign shows.
// MergeStateStatus, ReviewDecision, InMergeQueue and MergeQueueEnabled are as
// GitHub states them, the review decision empty where GitHub gives none. Posts
// holds the time each conversation comment, review and inline comment last
// changed, which an edit of its text moves. Unresolved holds the id of each
// review thread that is not resolved, sorted. ViewerReactions holds each
// reaction the account the read runs as left on a review thread's comment, as
// the comment's id and the reaction, such as "4591186925 THUMBS_UP", sorted: the
// city's mark that it handled a point, which moves no time and no count.
// Checks holds the check runs among
// the check rollup's contexts at ChecksAt, the PR's last commit, each with
// whether the PR requires it; the rollup's commit statuses are counted in the
// signs and read no further.
type Full struct {
	Signs
	MergeStateStatus  string
	ReviewDecision    string
	InMergeQueue      bool
	MergeQueueEnabled bool
	Posts             []string
	Unresolved        []string
	ViewerReactions   []string
	ChecksAt          string
	Checks            []CheckRun
}

// fullFragment is what the net reads of each PR beside its last commit, whose
// check runs say whether the PR requires each and so name the PR's own number
// (fullField). Each list's first page is read here.
const fullFragment = `fragment full on PullRequest{number state isDraft headRefOid baseRefName baseRef{target{oid}} updatedAt
  totalCommentsCount dismissed:reviews(states:[DISMISSED]){totalCount}
  mergeStateStatus reviewDecision isInMergeQueue isMergeQueueEnabled
  labels(first:100){pageInfo{hasNextPage endCursor} nodes{name}}
  comments(first:100){pageInfo{hasNextPage endCursor} nodes{updatedAt}}
  reviews(first:100){totalCount pageInfo{hasNextPage endCursor} nodes{updatedAt}}
  reviewThreads(first:10){pageInfo{hasNextPage endCursor} nodes{` + threadFields + `}}}`

// threadFields are what the net reads of a review thread: its id, whether it
// is resolved, and of each comment on its first page what threadPostFields
// reads.
const threadFields = `id isResolved comments(first:100){pageInfo{hasNextPage endCursor} nodes{` + threadPostFields + `}}`

// threadPostFields are what the net reads of a review thread's comment: its
// id, the time it last changed, and the reactions the account the read runs as
// left on it.
const threadPostFields = `fullDatabaseId updatedAt reactionGroups{content viewerHasReacted}`

// fullField is PR n's field in the net's read: the full fragment, and the check
// rollup at its last commit, with the contexts counted by state and the first
// page of them read.
func fullField(n int) string {
	return `...full commits(last:1){nodes{commit{oid statusCheckRollup{state contexts(first:100){totalCount
      checkRunCountsByState{state count} statusContextCountsByState{state count}
      pageInfo{hasNextPage endCursor} nodes{` + contextFields(strconv.Itoa(n)) + `}}}}}}`
}

// contextFields are what the net reads of a rollup's context: a check run's
// name, status, conclusion and whether PR number requires it, and a commit
// status's type alone.
func contextFields(number string) string {
	return `__typename ... on CheckRun{name status conclusion isRequired(pullRequestNumber:` + number + `)}`
}

// The queries that read a list of the net's on from where its first page
// ended: a PR's conversation comments, its reviews and its review threads, a
// thread's comments, and the contexts of the check rollup at a commit, which
// stay that commit's whatever the PR's head does meanwhile.
var (
	commentTimesQuery = laterPage("comments", 100, "updatedAt")
	reviewTimesQuery  = laterPage("reviews", 100, "updatedAt")
	threadsPageQuery  = laterPage("reviewThreads", 10, threadFields)
	threadTimesQuery  = `query($id:ID!,$endCursor:String!){
  node(id:$id){... on PullRequestReviewThread{
    comments(first:100,after:$endCursor){pageInfo{hasNextPage endCursor} nodes{` + threadPostFields + `}}}}}`
	contextsPageQuery = `query($owner:String!,$name:String!,$number:Int!,$oid:GitObjectID!,$endCursor:String!){
  repository(owner:$owner,name:$name){object(oid:$oid){... on Commit{
    statusCheckRollup{contexts(first:100,after:$endCursor){pageInfo{hasNextPage endCursor}
      nodes{` + contextFields("$number") + `}}}}}}}`
)

// laterPage is the query for the page of field, one of PR $number's lists,
// that starts after $endCursor, first items long, reading nodes of each.
func laterPage(field string, first int, nodes string) string {
	return fmt.Sprintf(`query($owner:String!,$name:String!,$number:Int!,$endCursor:String!){
  repository(owner:$owner,name:$name){pullRequest(number:$number){
    %s(first:%d,after:$endCursor){pageInfo{hasNextPage endCursor} nodes{%s}}}}}`, field, first, nodes)
}

// fullNode is one PR as the net's read asks for it: its signs, read as the
// cheap question reads them, and the facts no sign shows.
type fullNode struct {
	signsNode
	MergeStateStatus    string                   `json:"mergeStateStatus"`
	ReviewDecision      *string                  `json:"reviewDecision"`
	IsInMergeQueue      bool                     `json:"isInMergeQueue"`
	IsMergeQueueEnabled bool                     `json:"isMergeQueueEnabled"`
	IssueComments       *connection[postTime]    `json:"comments"`
	Threads             *connection[threadState] `json:"reviewThreads"`
}

// postTime is when a post last changed.
type postTime struct {
	UpdatedAt string `json:"updatedAt"`
}

// threadState is a review thread as the net reads it.
type threadState struct {
	ID         string                  `json:"id"`
	IsResolved bool                    `json:"isResolved"`
	Comments   *connection[threadPost] `json:"comments"`
}

// threadPost is a review thread's comment as the net reads it.
type threadPost struct {
	ID             string `json:"fullDatabaseId"`
	UpdatedAt      string `json:"updatedAt"`
	ReactionGroups []struct {
		Content          string `json:"content"`
		ViewerHasReacted bool   `json:"viewerHasReacted"`
	} `json:"reactionGroups"`
}

// contextNode is one of a check rollup's contexts: a check run, or a commit
// status, of which the net reads only its type.
type contextNode struct {
	Type       string  `json:"__typename"`
	Name       string  `json:"name"`
	Status     string  `json:"status"`
	Conclusion *string `json:"conclusion"`
	IsRequired bool    `json:"isRequired"`
}

// FullRead reads each PR numbered in repo, owner/name, as the net reads it, in
// one request for each FullReadBatch of them, with one aliased field for each
// PR. A list that passes its first page is read on, a page at a time, until it
// ends: a PR's labels, conversation comments, reviews and review threads, a
// thread's comments, and the contexts of the check rollup at its last commit,
// read at that commit. It returns the read of each PR read whole and the error
// of each PR that was not, as Signs does, a PR whose later page failed among
// them.
func (c *Client) FullRead(repo string, numbers []int) (map[int]Full, map[int]error) {
	return readBatched(c, repo, numbers, FullReadBatch, "full read", fullField, fullFragment, (*Client).full)
}

// full is PR number's read in owner/name from its node, with each list read on
// past its first page until it ends.
func (c *Client) full(owner, name string, number int, n *fullNode) (Full, error) {
	signs, err := c.signsOf(owner, name, number, &n.signsNode)
	if err != nil {
		return Full{}, err
	}
	if n.IssueComments == nil || n.Threads == nil || len(n.Commits.Nodes) != 1 || n.Commits.Nodes[0].Commit == nil {
		return Full{}, fmt.Errorf("the full read of PR %d lacks a part GitHub always gives", number)
	}
	f := Full{Signs: signs, MergeStateStatus: n.MergeStateStatus, InMergeQueue: n.IsInMergeQueue,
		MergeQueueEnabled: n.IsMergeQueueEnabled, Posts: []string{}, Unresolved: []string{}, ViewerReactions: []string{},
		Checks: []CheckRun{}}
	if n.ReviewDecision != nil {
		f.ReviewDecision = *n.ReviewDecision
	}
	vars := pageVars(owner, name, number)
	comments, err := whole(c, n.IssueComments, commentTimesQuery, vars, prList[postTime]("comments"))
	if err != nil {
		return Full{}, fmt.Errorf("the conversation comments of PR %d: %w", number, err)
	}
	reviews, err := whole(c, &n.Reviews.connection, reviewTimesQuery, vars, prList[postTime]("reviews"))
	if err != nil {
		return Full{}, fmt.Errorf("the reviews of PR %d: %w", number, err)
	}
	threads, err := whole(c, n.Threads, threadsPageQuery, vars, prList[threadState]("reviewThreads"))
	if err != nil {
		return Full{}, fmt.Errorf("the review threads of PR %d: %w", number, err)
	}
	for _, p := range append(comments, reviews...) {
		f.Posts = append(f.Posts, p.UpdatedAt)
	}
	for _, t := range threads {
		if !t.IsResolved {
			f.Unresolved = append(f.Unresolved, t.ID)
		}
		posts, err := c.threadPosts(t)
		if err != nil {
			return Full{}, fmt.Errorf("review thread %s of PR %d: %w", t.ID, number, err)
		}
		for _, p := range posts {
			f.Posts = append(f.Posts, p.UpdatedAt)
			reacted, err := viewerReactions(p)
			if err != nil {
				return Full{}, fmt.Errorf("review thread %s of PR %d: %w", t.ID, number, err)
			}
			f.ViewerReactions = append(f.ViewerReactions, reacted...)
		}
	}
	slices.Sort(f.Unresolved)
	slices.Sort(f.ViewerReactions)
	commit := n.Commits.Nodes[0].Commit
	f.ChecksAt = commit.Oid
	if commit.Rollup == nil || commit.Rollup.Contexts == nil {
		return f, nil
	}
	contexts, err := whole(c, &commit.Rollup.Contexts.connection, contextsPageQuery,
		append(slices.Clone(vars), "-f", "oid="+commit.Oid), rollupContexts)
	if err != nil {
		return Full{}, fmt.Errorf("the checks of PR %d at %s: %w", number, commit.Oid, err)
	}
	for _, x := range contexts {
		if x.Type != "CheckRun" {
			continue
		}
		run := CheckRun{Name: x.Name, Status: x.Status, Required: x.IsRequired}
		if x.Conclusion != nil {
			run.Conclusion = *x.Conclusion
		}
		f.Checks = append(f.Checks, run)
	}
	return f, nil
}

// threadPosts is each of review thread t's comments, those past the first page
// read on, by the thread's id, until they end.
func (c *Client) threadPosts(t threadState) ([]threadPost, error) {
	if t.Comments == nil {
		return nil, errors.New("the thread holds no comments")
	}
	if t.Comments.PageInfo.HasNextPage && t.ID == "" {
		return nil, errors.New("a review thread with more comments than one page names no id")
	}
	return whole(c, t.Comments, threadTimesQuery, []string{"-f", "id=" + t.ID}, threadComments)
}

// viewerReactions is each reaction the account the read runs as left on p, as
// Full.ViewerReactions names one. A comment that reacted and names no id fails
// the read, since its reaction would match no other read's.
func viewerReactions(p threadPost) ([]string, error) {
	var out []string
	for _, g := range p.ReactionGroups {
		if !g.ViewerHasReacted {
			continue
		}
		id, err := databaseID(p.ID)
		if err != nil {
			return nil, err
		}
		out = append(out, strconv.FormatInt(id, 10)+" "+g.Content)
	}
	return out, nil
}

// threadComments finds a review thread's comments in a page of
// threadTimesQuery.
func threadComments(data json.RawMessage) (*connection[threadPost], error) {
	var page struct {
		Node *struct {
			Comments *connection[threadPost] `json:"comments"`
		} `json:"node"`
	}
	if err := json.Unmarshal(data, &page); err != nil {
		return nil, err
	}
	if page.Node == nil || page.Node.Comments == nil {
		return nil, errors.New("the page holds no comments of the review thread")
	}
	return page.Node.Comments, nil
}

// rollupContexts finds the contexts of a commit's check rollup in a page of
// contextsPageQuery.
func rollupContexts(data json.RawMessage) (*connection[contextNode], error) {
	var page struct {
		Repository *struct {
			Object *struct {
				Rollup *struct {
					Contexts *connection[contextNode] `json:"contexts"`
				} `json:"statusCheckRollup"`
			} `json:"object"`
		} `json:"repository"`
	}
	if err := json.Unmarshal(data, &page); err != nil {
		return nil, err
	}
	if page.Repository == nil || page.Repository.Object == nil || page.Repository.Object.Rollup == nil ||
		page.Repository.Object.Rollup.Contexts == nil {
		return nil, errors.New("the page holds no contexts of the commit's check rollup")
	}
	return page.Repository.Object.Rollup.Contexts, nil
}
