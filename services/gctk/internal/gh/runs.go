package gh

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// WorkflowRun is one run of a GitHub Actions workflow as GitHub records it:
// its id and its number among its workflow's runs, the attempt its conclusion
// is of, the event that started it, the branch and commit it ran on, the
// repository that commit came from as owner/name, the headline of the commit's
// message, its workflow's name and the path of the workflow's file, the
// conclusion of its latest attempt, when it was made and when that attempt
// started, and its page. Conclusion is GitHub's word, such as success, failure,
// cancelled, skipped, timed_out, startup_failure, neutral, stale or
// action_required.
type WorkflowRun struct {
	ID         int64
	Number     int
	Attempt    int
	Event      string
	Branch     string
	Commit     string
	HeadRepo   string
	Headline   string
	Name       string
	Path       string
	Conclusion string
	Created    time.Time
	Started    time.Time
	URL        string
}

// Job is one job of a run's latest attempt: its name, its conclusion in
// GitHub's words, its page and its steps.
type Job struct {
	Name       string
	Conclusion string
	URL        string
	Steps      []Step
}

// Step is one step of a job: its number, its name and its conclusion in
// GitHub's words.
type Step struct {
	Number     int
	Name       string
	Conclusion string
}

// BranchRuns reads the newest n finished runs that a push to branch started in
// repo, of every workflow, newest first, in one page of GET
// repos/<repo>/actions/runs: the read is a window, not a list followed to its
// end. An answer that carries no list of runs, a run with no id, no workflow
// file or no time it was made, and one that does not decode fail the read.
func (c *Client) BranchRuns(repo, branch string, n int) ([]WorkflowRun, error) {
	if _, err := repoVars(repo); err != nil {
		return nil, err
	}
	if branch == "" {
		return nil, errors.New("github: a read of a branch's runs names no branch")
	}
	if n < 1 || n > 100 {
		return nil, fmt.Errorf("github: a page of %d runs is not one GitHub serves", n)
	}
	q := url.Values{"branch": {branch}, "event": {"push"}, "status": {"completed"},
		"per_page": {strconv.Itoa(n)}, "exclude_pull_requests": {"true"}}
	raw, err := c.call("api", "--hostname", c.host, "repos/"+repo+"/actions/runs?"+q.Encode())
	if err != nil {
		return nil, err
	}
	return decodeRuns(repo, raw)
}

// decodeRuns reads one answer of BranchRuns.
func decodeRuns(repo string, raw []byte) ([]WorkflowRun, error) {
	var page struct {
		Runs *[]struct {
			ID           int64  `json:"id"`
			Name         string `json:"name"`
			Path         string `json:"path"`
			Number       int    `json:"run_number"`
			Attempt      int    `json:"run_attempt"`
			Event        string `json:"event"`
			HeadBranch   string `json:"head_branch"`
			HeadSHA      string `json:"head_sha"`
			Conclusion   string `json:"conclusion"`
			CreatedAt    string `json:"created_at"`
			RunStartedAt string `json:"run_started_at"`
			HTMLURL      string `json:"html_url"`
			HeadCommit   *struct {
				Message string `json:"message"`
			} `json:"head_commit"`
			HeadRepository *struct {
				FullName string `json:"full_name"`
			} `json:"head_repository"`
		} `json:"workflow_runs"`
	}
	if err := json.Unmarshal(raw, &page); err != nil {
		return nil, fmt.Errorf("github: the runs of %s did not decode: %w", repo, err)
	}
	if page.Runs == nil {
		return nil, fmt.Errorf("github: the answer carries no list of the runs of %s", repo)
	}
	out := []WorkflowRun{}
	for _, r := range *page.Runs {
		if r.ID < 1 {
			return nil, fmt.Errorf("github: a run of %s carries no id", repo)
		}
		if r.Path == "" {
			return nil, fmt.Errorf("github: run %d of %s names no workflow file", r.ID, repo)
		}
		made, err := time.Parse(time.RFC3339, r.CreatedAt)
		if err != nil {
			return nil, fmt.Errorf("github: run %d of %s names no time it was made: %w", r.ID, repo, err)
		}
		run := WorkflowRun{ID: r.ID, Number: r.Number, Attempt: r.Attempt, Event: r.Event, Branch: r.HeadBranch,
			Commit: r.HeadSHA, Name: r.Name, Path: r.Path, Conclusion: r.Conclusion, Created: made, Started: made,
			URL: r.HTMLURL}
		if r.RunStartedAt != "" {
			if run.Started, err = time.Parse(time.RFC3339, r.RunStartedAt); err != nil {
				return nil, fmt.Errorf("github: run %d of %s names no time it started: %w", r.ID, repo, err)
			}
		}
		if r.HeadCommit != nil {
			run.Headline, _, _ = strings.Cut(r.HeadCommit.Message, "\n")
		}
		if r.HeadRepository != nil {
			run.HeadRepo = r.HeadRepository.FullName
		}
		out = append(out, run)
	}
	return out, nil
}

// RunJobs reads the jobs of run's latest attempt in repo, each with its steps,
// across every page of GET repos/<repo>/actions/runs/<run>/jobs. A page that
// does not decode, or carries no list of jobs, fails the read, so no answer is
// read off part of them.
func (c *Client) RunJobs(repo string, run int64) ([]Job, error) {
	if _, err := repoVars(repo); err != nil {
		return nil, err
	}
	if run < 1 {
		return nil, fmt.Errorf("github: %d is no run id", run)
	}
	raw, err := c.call("api", "--hostname", c.host,
		fmt.Sprintf("repos/%s/actions/runs/%d/jobs?filter=latest&per_page=100", repo, run), "--paginate")
	if err != nil {
		return nil, err
	}
	out := []Job{}
	err = eachPage(raw, func(page json.RawMessage) error {
		var p struct {
			Jobs *[]struct {
				Name       string `json:"name"`
				Conclusion string `json:"conclusion"`
				HTMLURL    string `json:"html_url"`
				Steps      []struct {
					Number     int    `json:"number"`
					Name       string `json:"name"`
					Conclusion string `json:"conclusion"`
				} `json:"steps"`
			} `json:"jobs"`
		}
		if err := json.Unmarshal(page, &p); err != nil || p.Jobs == nil {
			return fmt.Errorf("github: a page of the jobs of run %d in %s carries no list of them", run, repo)
		}
		for _, j := range *p.Jobs {
			job := Job{Name: j.Name, Conclusion: j.Conclusion, URL: j.HTMLURL, Steps: []Step{}}
			for _, s := range j.Steps {
				job.Steps = append(job.Steps, Step{Number: s.Number, Name: s.Name, Conclusion: s.Conclusion})
			}
			out = append(out, job)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return out, nil
}
