package gh

import (
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"time"
)

// Deployment is one deployment as GitHub records it: when it was made, the
// commit it deployed, that commit's headline and the pull request GitHub
// associates with it, the deployment's latest status, and each commit status
// on the commit that is failing now. State is the latest status's state in
// GitHub's words, such as SUCCESS, FAILURE, ERROR, INACTIVE or IN_PROGRESS,
// and empty for a deployment that has no status yet. LogURL is the URL the
// status gives for the deployment's output, and EnvironmentURL the one it
// gives for what the deployment serves. A commit status holds only its
// context's latest post, which a later run on the same commit can replace.
type Deployment struct {
	Created        time.Time
	Commit         string
	Headline       string
	PR             int
	PRURL          string
	State          string
	Description    string
	LogURL         string
	EnvironmentURL string
	Failing        []CommitStatus
}

// deploymentsQuery reads the newest $n deployments of $environment in one
// page: the read is a window, not a connection followed to its end.
const deploymentsQuery = `query($owner:String!,$name:String!,$environment:String!,$n:Int!){
  repository(owner:$owner,name:$name){
    deployments(environments:[$environment],first:$n,orderBy:{field:CREATED_AT,direction:DESC}){
      nodes{createdAt commitOid
        commit{messageHeadline associatedPullRequests(first:1){nodes{number url}}
          status{contexts{context state description targetUrl}}}
        latestStatus{state description logUrl environmentUrl}}}}}`

// Deployments reads the newest n deployments of environment in repo, newest
// first, each with its latest status, in one GraphQL read. A commit status
// counts as failing in state FAILURE or ERROR. An answer that names no
// repository, or carries no list of its deployments, fails the read, as does
// one that does not decode.
func (c *Client) Deployments(repo, environment string, n int) ([]Deployment, error) {
	vars, err := repoVars(repo)
	if err != nil {
		return nil, err
	}
	if environment == "" {
		return nil, errors.New("github: a read of deployments names no environment")
	}
	if n < 1 {
		return nil, fmt.Errorf("github: a read of %d deployments reads nothing", n)
	}
	vars = append(vars, "-f", "environment="+environment, "-F", "n="+strconv.Itoa(n))
	var out []Deployment
	err = c.graphql(deploymentsQuery, vars, false, func(data json.RawMessage) error {
		d, err := decodeDeployments(repo, data)
		out = d
		return err
	})
	if err != nil {
		return nil, err
	}
	return out, nil
}

// decodeDeployments reads one answer of deploymentsQuery.
func decodeDeployments(repo string, data json.RawMessage) ([]Deployment, error) {
	var page struct {
		Repository *struct {
			Deployments *struct {
				Nodes []struct {
					CreatedAt string `json:"createdAt"`
					CommitOid string `json:"commitOid"`
					Commit    *struct {
						MessageHeadline        string `json:"messageHeadline"`
						AssociatedPullRequests struct {
							Nodes []struct {
								Number int    `json:"number"`
								URL    string `json:"url"`
							} `json:"nodes"`
						} `json:"associatedPullRequests"`
						Status *struct {
							Contexts []struct {
								Context     string `json:"context"`
								State       string `json:"state"`
								Description string `json:"description"`
								TargetURL   string `json:"targetUrl"`
							} `json:"contexts"`
						} `json:"status"`
					} `json:"commit"`
					LatestStatus *struct {
						State          string `json:"state"`
						Description    string `json:"description"`
						LogURL         string `json:"logUrl"`
						EnvironmentURL string `json:"environmentUrl"`
					} `json:"latestStatus"`
				} `json:"nodes"`
			} `json:"deployments"`
		} `json:"repository"`
	}
	if err := json.Unmarshal(data, &page); err != nil {
		return nil, fmt.Errorf("the deployments of %s did not decode: %w", repo, err)
	}
	switch {
	case page.Repository == nil:
		return nil, fmt.Errorf("the answer names no repository %s", repo)
	case page.Repository.Deployments == nil:
		return nil, fmt.Errorf("the answer carries no list of %s's deployments", repo)
	}
	out := []Deployment{}
	for _, n := range page.Repository.Deployments.Nodes {
		at, err := time.Parse(time.RFC3339, n.CreatedAt)
		if err != nil {
			return nil, fmt.Errorf("a deployment of %s in %s names no time it was made: %w", n.CommitOid, repo, err)
		}
		d := Deployment{Created: at, Commit: n.CommitOid, Failing: []CommitStatus{}}
		if cm := n.Commit; cm != nil {
			d.Headline = cm.MessageHeadline
			if prs := cm.AssociatedPullRequests.Nodes; len(prs) > 0 {
				d.PR, d.PRURL = prs[0].Number, prs[0].URL
			}
			if cm.Status != nil {
				for _, s := range cm.Status.Contexts {
					if s.State == "FAILURE" || s.State == "ERROR" {
						d.Failing = append(d.Failing, CommitStatus{Context: s.Context, State: s.State, Description: s.Description, TargetURL: s.TargetURL})
					}
				}
			}
		}
		if s := n.LatestStatus; s != nil {
			d.State, d.Description, d.LogURL, d.EnvironmentURL = s.State, s.Description, s.LogURL, s.EnvironmentURL
		}
		out = append(out, d)
	}
	return out, nil
}
