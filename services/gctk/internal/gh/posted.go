package gh

import (
	"encoding/json"
	"fmt"
)

// Posted is the text people posted on an issue or a PR, by number in one
// repository: its title and body with the account that opened it, and its
// conversation. A PR's conversation is its reviews, its review threads and its
// conversation comments, and an issue's is its comments, each oldest first.
// ViewerPermission is the permission the account the read runs as holds on the
// repository: ADMIN, MAINTAIN, WRITE, TRIAGE or READ, empty when GitHub names
// none. Opener is the account that opened it, with its kind and its
// association with the repository, as a review's author is.
type Posted struct {
	Repository       string
	Number           int
	URL              string
	PullRequest      bool
	Title            string
	Body             string
	CreatedAt        string
	Opener           Account
	ViewerPermission string
	Reviews          []Review
	Threads          []Thread
	Comments         []IssueComment
}

// Account is an account that posted: its login, the kind of account it is and
// its association with the repository, each empty for an account GitHub no
// longer names.
type Account struct {
	Login       string
	Type        string
	Association string
}

const postedQuery = `query($owner:String!,$name:String!,$number:Int!){
  repository(owner:$owner,name:$name){viewerPermission
    issueOrPullRequest(number:$number){__typename
      ... on PullRequest{url title body createdAt authorAssociation author{__typename login}}
      ... on Issue{url title body createdAt authorAssociation author{__typename login}
        comments(first:100){pageInfo{hasNextPage endCursor} nodes{` + issueCommentFields + `}}}}}}`

const issueCommentsOfIssueQuery = `query($owner:String!,$name:String!,$number:Int!,$endCursor:String){
  repository(owner:$owner,name:$name){issue(number:$number){
    comments(first:100,after:$endCursor){pageInfo{hasNextPage endCursor}
      nodes{` + issueCommentFields + `}}}}}`

// Posted reads the issue or the PR number in repo, owner/name, with its whole
// conversation. A PR's conversation is read as Conversation reads it, and an
// issue's comments past their first page are read again on their own, to their
// end.
func (c *Client) Posted(repo string, number int) (*Posted, error) {
	vars, err := prVars(repo, number)
	if err != nil {
		return nil, err
	}
	var page struct {
		Repository *struct {
			ViewerPermission *string `json:"viewerPermission"`
			Item             *struct {
				Typename    string                        `json:"__typename"`
				URL         string                        `json:"url"`
				Title       string                        `json:"title"`
				Body        string                        `json:"body"`
				CreatedAt   string                        `json:"createdAt"`
				Association string                        `json:"authorAssociation"`
				Author      *actor                        `json:"author"`
				Comments    *connection[issueCommentNode] `json:"comments"`
			} `json:"issueOrPullRequest"`
		} `json:"repository"`
	}
	if err := c.graphql(postedQuery, vars, false, func(data json.RawMessage) error {
		return json.Unmarshal(data, &page)
	}); err != nil {
		return nil, err
	}
	if page.Repository == nil || page.Repository.Item == nil {
		return nil, fmt.Errorf("github: %s holds no issue or pull request %d", repo, number)
	}
	it := page.Repository.Item
	out := &Posted{Repository: repo, Number: number, URL: it.URL, Title: it.Title, Body: it.Body,
		CreatedAt: it.CreatedAt, Opener: Account{Login: it.Author.name(), Type: it.Author.kind(), Association: it.Association},
		Reviews: []Review{}, Threads: []Thread{}, Comments: []IssueComment{}}
	if page.Repository.ViewerPermission != nil {
		out.ViewerPermission = *page.Repository.ViewerPermission
	}
	switch it.Typename {
	case "PullRequest":
		out.PullRequest = true
		conv, err := c.Conversation(repo, number)
		if err != nil {
			return nil, err
		}
		out.Reviews, out.Threads, out.Comments = conv.Reviews, conv.Threads, conv.Comments
	case "Issue":
		if it.Comments == nil {
			return nil, fmt.Errorf("github: issue %s#%d lacks the comments GitHub always gives", repo, number)
		}
		if it.Comments.PageInfo.HasNextPage {
			if out.Comments, err = c.issueComments(repo, number); err != nil {
				return nil, err
			}
			break
		}
		for _, n := range it.Comments.Nodes {
			cm, err := n.comment()
			if err != nil {
				return nil, fmt.Errorf("github: %w", err)
			}
			out.Comments = append(out.Comments, cm)
		}
	default:
		return nil, fmt.Errorf("github: %s#%d is a %q, neither an issue nor a pull request", repo, number, it.Typename)
	}
	return out, nil
}

// issueComments reads every comment of issue number in repo, oldest first.
func (c *Client) issueComments(repo string, number int) ([]IssueComment, error) {
	vars, err := prVars(repo, number)
	if err != nil {
		return nil, err
	}
	out := []IssueComment{}
	err = c.graphql(issueCommentsOfIssueQuery, vars, true, func(data json.RawMessage) error {
		var page struct {
			Repository *struct {
				Issue *struct {
					Comments *connection[issueCommentNode] `json:"comments"`
				} `json:"issue"`
			} `json:"repository"`
		}
		if err := json.Unmarshal(data, &page); err != nil {
			return err
		}
		if page.Repository == nil || page.Repository.Issue == nil || page.Repository.Issue.Comments == nil {
			return fmt.Errorf("the page holds no comments of issue %s#%d", repo, number)
		}
		for _, n := range page.Repository.Issue.Comments.Nodes {
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
