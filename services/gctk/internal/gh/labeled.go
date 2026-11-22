package gh

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"
)

// The net's search for the PRs that carry a label of the city's
// (specs/tk-1tfzr71.149/design.md, section 9): one page of GitHub's search at a
// time, so the caller decides when it has read enough.

// LabeledBatch is how many PRs a page of the search holds, the most GitHub's
// search gives a page.
const LabeledBatch = 100

// LabeledPR is one PR the search found: its number and its state, OPEN, CLOSED
// or MERGED.
type LabeledPR struct {
	Number int
	State  string
}

// LabeledPage is one page of the search: its PRs, and the cursor the next page
// starts from, empty when the results end.
type LabeledPage struct {
	PRs  []LabeledPR
	Next string
}

const labeledQuery = `query($q:String!,$after:String){search(type:ISSUE,first:100,after:$after,query:$q){
  pageInfo{hasNextPage endCursor} nodes{... on PullRequest{number state}}}}`

// Labeled reads one page of the PRs in repo, owner/name, that carry any of the
// labels named, as GitHub's search lists them, starting after the cursor where
// the last page ended, or at the first page when after is empty. A page that
// does not answer whole is an error.
func (c *Client) Labeled(repo string, names []string, after string) (LabeledPage, error) {
	owner, name, err := splitRepo(repo)
	if err != nil {
		return LabeledPage{}, err
	}
	if len(names) == 0 {
		return LabeledPage{}, errors.New("github: the search names no label")
	}
	quoted := make([]string, 0, len(names))
	for _, n := range names {
		if n == "" || strings.ContainsAny(n, "\"\n") {
			return LabeledPage{}, fmt.Errorf("github: %q is no label the search can name", n)
		}
		quoted = append(quoted, `"`+n+`"`)
	}
	vars := []string{"-f", fmt.Sprintf("q=repo:%s/%s is:pr label:%s", owner, name, strings.Join(quoted, ","))}
	if after != "" {
		vars = append(vars, "-f", "after="+after)
	}
	var out LabeledPage
	err = c.graphql(labeledQuery, vars, false, func(data json.RawMessage) error {
		var page struct {
			Search *struct {
				connection[struct {
					Number int    `json:"number"`
					State  string `json:"state"`
				}]
			} `json:"search"`
		}
		if err := json.Unmarshal(data, &page); err != nil {
			return fmt.Errorf("the search did not decode: %w", err)
		}
		if page.Search == nil {
			return errors.New("the search held no results")
		}
		for _, n := range page.Search.Nodes {
			if n.Number < 1 {
				return errors.New("the search returned a result that is no pull request")
			}
			out.PRs = append(out.PRs, LabeledPR{Number: n.Number, State: n.State})
		}
		if page.Search.PageInfo.HasNextPage {
			if page.Search.PageInfo.EndCursor == "" || page.Search.PageInfo.EndCursor == after {
				return fmt.Errorf("the page after %q says more follow and names no new end cursor", after)
			}
			out.Next = page.Search.PageInfo.EndCursor
		}
		return nil
	})
	if err != nil {
		return LabeledPage{}, err
	}
	return out, nil
}
