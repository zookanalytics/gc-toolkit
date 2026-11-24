package gh

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"
)

// Text is a PR's title and body as GitHub has them, with the PR's own facts,
// which a caller checks before it edits them.
type Text struct {
	PullRequest
	Title, Body string
}

const textQuery = `query($owner:String!,$name:String!,$number:Int!){
  repository(owner:$owner,name:$name){pullRequest(number:$number){
    ` + prPartFields + ` title body}}}`

// PullRequestText reads the title and the body of PR number in repo,
// owner/name, with the PR's own facts.
func (c *Client) PullRequestText(repo string, number int) (*Text, error) {
	var page struct {
		Repository *struct {
			PullRequest *struct {
				prNode
				Title string `json:"title"`
				Body  string `json:"body"`
			} `json:"pullRequest"`
		} `json:"repository"`
	}
	vars, err := prVars(repo, number)
	if err != nil {
		return nil, err
	}
	if err := c.graphql(textQuery, vars, false, func(data json.RawMessage) error {
		return json.Unmarshal(data, &page)
	}); err != nil {
		return nil, err
	}
	if page.Repository == nil || page.Repository.PullRequest == nil {
		return nil, fmt.Errorf("github: %s holds no pull request %d", repo, number)
	}
	p := page.Repository.PullRequest
	return &Text{PullRequest: p.pullRequest(), Title: p.Title, Body: p.Body}, nil
}

// EditPullRequest sets the title, the body or both of the PR whose node id is
// id, through GitHub's updatePullRequest mutation, whose input names only the
// ones given, so GitHub leaves the one that is nil as it stands. Each goes to gh
// as a raw field, so a body that opens with @ is text, not a file to read. An
// error is a request GitHub refused or one whose answer did not arrive, which
// may still take effect: the caller reads the PR again to learn which.
func (c *Client) EditPullRequest(id string, title, body *string) error {
	if id == "" {
		return errors.New("github: an edit of a PR names no pull request")
	}
	if title == nil && body == nil {
		return errors.New("github: an edit of a PR sets neither its title nor its body")
	}
	params, input, vars := []string{"$id:ID!"}, []string{"pullRequestId:$id"}, []string{"-f", "id=" + id}
	for _, f := range []struct {
		name  string
		value *string
	}{{"title", title}, {"body", body}} {
		if f.value == nil {
			continue
		}
		params = append(params, "$"+f.name+":String!")
		input = append(input, f.name+":$"+f.name)
		vars = append(vars, "-f", f.name+"="+*f.value)
	}
	query := fmt.Sprintf("mutation(%s){\n  updatePullRequest(input:{%s}){pullRequest{id}}}",
		strings.Join(params, ","), strings.Join(input, ","))
	return c.graphql(query, vars, false, func(json.RawMessage) error { return nil })
}
