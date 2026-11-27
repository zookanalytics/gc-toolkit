package gh

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"strings"
)

// The labels on a PR and in its repository, through GitHub's REST API, which
// names a label by its name, so no request needs a node id: the labels a PR
// carries, the labels a repository holds, a label's creation and the edit of
// its description, and the labels added to a PR or taken off it.

// Label is a label as a repository holds it: its name, its colour as six hex
// digits with no leading '#', and its description.
type Label struct {
	Name, Color, Description string
}

// PullRequestLabels reads the name of each label PR number in repo, owner/name,
// carries (GET repos/<repo>/issues/<n>/labels), across all its pages.
func (c *Client) PullRequestLabels(repo string, number int) ([]string, error) {
	if _, err := prVars(repo, number); err != nil {
		return nil, err
	}
	raw, err := c.call("api", "--hostname", c.host,
		fmt.Sprintf("repos/%s/issues/%d/labels?per_page=100", repo, number), "--paginate")
	if err != nil {
		return nil, err
	}
	labels, err := labelPages(raw, fmt.Sprintf("PR %d in %s", number, repo))
	if err != nil {
		return nil, err
	}
	names := make([]string, 0, len(labels))
	for _, l := range labels {
		names = append(names, l.Name)
	}
	return names, nil
}

// RepoLabels reads every label repo, owner/name, holds (GET
// repos/<repo>/labels), across all its pages.
func (c *Client) RepoLabels(repo string) ([]Label, error) {
	if _, err := repoVars(repo); err != nil {
		return nil, err
	}
	raw, err := c.call("api", "--hostname", c.host, "repos/"+repo+"/labels?per_page=100", "--paginate")
	if err != nil {
		return nil, err
	}
	return labelPages(raw, repo)
}

// labelPages reads each page of labels in raw, of, as a read names it. A page
// that is not a list of labels, or a label with no name, fails the read.
func labelPages(raw []byte, of string) ([]Label, error) {
	var out []Label
	err := eachPage(raw, func(page json.RawMessage) error {
		var labels *[]struct {
			Name        string `json:"name"`
			Color       string `json:"color"`
			Description string `json:"description"`
		}
		if err := json.Unmarshal(page, &labels); err != nil || labels == nil {
			return fmt.Errorf("github: a page of the labels of %s carries no list of them", of)
		}
		for _, l := range *labels {
			if l.Name == "" {
				return fmt.Errorf("github: a page of the labels of %s holds a label with no name", of)
			}
			out = append(out, Label{Name: l.Name, Color: l.Color, Description: l.Description})
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return out, nil
}

// CreateLabel creates l in repo (POST repos/<repo>/labels). An error is a
// request GitHub refused, such as one for a name repo already holds, or one
// whose answer did not arrive, which may still take effect.
func (c *Client) CreateLabel(repo string, l Label) error {
	if err := named(repo, l.Name); err != nil {
		return err
	}
	_, err := c.call("api", "--hostname", c.host, "-X", "POST", "repos/"+repo+"/labels",
		"-f", "name="+l.Name, "-f", "color="+l.Color, "-f", "description="+l.Description)
	return err
}

// EditLabel sets the description of the label l names in repo to l's (PATCH
// repos/<repo>/labels/<name>), and leaves its colour as it stands. An error
// reads as CreateLabel's.
func (c *Client) EditLabel(repo string, l Label) error {
	if err := named(repo, l.Name); err != nil {
		return err
	}
	_, err := c.call("api", "--hostname", c.host, "-X", "PATCH", "repos/"+repo+"/labels/"+url.PathEscape(l.Name),
		"-f", "description="+l.Description)
	return err
}

// AddLabels adds the labels named to PR number in repo, in one request (POST
// repos/<repo>/issues/<n>/labels), and leaves the labels it carries. An error
// reads as CreateLabel's.
func (c *Client) AddLabels(repo string, number int, names []string) error {
	if _, err := prVars(repo, number); err != nil {
		return err
	}
	if len(names) == 0 {
		return errors.New("github: a request to add labels names none")
	}
	args := []string{"api", "--hostname", c.host, "-X", "POST", fmt.Sprintf("repos/%s/issues/%d/labels", repo, number)}
	for _, n := range names {
		if err := named(repo, n); err != nil {
			return err
		}
		args = append(args, "-f", "labels[]="+n)
	}
	_, err := c.call(args...)
	return err
}

// RemoveLabel takes the label named off PR number in repo (DELETE
// repos/<repo>/issues/<n>/labels/<name>). An error reads as CreateLabel's, and
// GitHub refuses a label the PR does not carry.
func (c *Client) RemoveLabel(repo string, number int, name string) error {
	if _, err := prVars(repo, number); err != nil {
		return err
	}
	if err := named(repo, name); err != nil {
		return err
	}
	_, err := c.call("api", "--hostname", c.host, "-X", "DELETE",
		fmt.Sprintf("repos/%s/issues/%d/labels/%s", repo, number, url.PathEscape(name)))
	return err
}

// named refuses a request about a label with no name, or about a repository
// that is not owner/name.
func named(repo, label string) error {
	if _, err := repoVars(repo); err != nil {
		return err
	}
	if strings.TrimSpace(label) == "" {
		return errors.New("github: a request about a label names none")
	}
	return nil
}
