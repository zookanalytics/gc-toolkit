package gh

import (
	"strings"
	"testing"
	"time"
)

// runsPath is the read of the newest 100 runs a push to main started.
const runsPath = "repos/owner/repo-a/actions/runs?branch=main&event=push&exclude_pull_requests=true&per_page=100"

// recordedRuns is GitHub's answer for three runs of two workflows, trimmed to
// the fields the read takes: a run still in progress, a run whose second
// attempt failed, and a run whose answer leaves out its start, its commit and
// its head repository.
const recordedRuns = `{"total_count":3,"workflow_runs":[
{"id":7013,"name":"Tests","path":".github/workflows/tests.yml","run_number":13,"run_attempt":1,"event":"push",
 "head_branch":"main","head_sha":"cccccccccccccccccccccccccccccccccccccccc","status":"in_progress","conclusion":null,
 "created_at":"2026-11-20T07:00:00Z","run_started_at":"2026-11-20T07:00:00Z",
 "html_url":"https://github.com/owner/repo-a/actions/runs/7013",
 "head_commit":{"message":"fix: loosen the schema"},"head_repository":{"full_name":"owner/repo-a"}},
{"id":7012,"name":"Tests","path":".github/workflows/tests.yml","run_number":12,"run_attempt":2,"event":"push",
 "head_branch":"main","head_sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","status":"completed","conclusion":"failure",
 "created_at":"2026-11-20T06:00:00Z","run_started_at":"2026-11-20T06:30:00Z",
 "html_url":"https://github.com/owner/repo-a/actions/runs/7012",
 "head_commit":{"message":"fix: tighten the schema\n\nThe body."},"head_repository":{"full_name":"owner/repo-a"}},
{"id":7011,"name":"Lint","path":".github/workflows/lint.yml","run_number":11,"run_attempt":1,"event":"push",
 "head_branch":"main","head_sha":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","status":"completed","conclusion":"success",
 "created_at":"2026-11-19T06:00:00Z","html_url":"https://github.com/owner/repo-a/actions/runs/7011"}
]}`

// The runs are one page of the branch's newest push runs across its
// workflows, finished or not, each with its workflow's file, its attempt,
// event, commit and the headline of its message. A run that has not finished
// has no conclusion, and a run whose answer leaves out its start started when
// it was made.
func TestTheRunsAreOnePageOfTheBranchsNewestPushRuns(t *testing.T) {
	var log []string
	c := NewWithRunner("github.com", answers(t, map[string]string{runsPath: recordedRuns}, &log))
	got, err := c.BranchRuns("owner/repo-a", "main", 100)
	if err != nil {
		t.Fatal(err)
	}
	if len(log) != 1 || log[0] != "api --hostname github.com "+runsPath {
		t.Fatalf("the read ran %q, want one GET of %s", log, runsPath)
	}
	if len(got) != 3 {
		t.Fatalf("BranchRuns = %+v, want three", got)
	}
	if r := got[0]; r.ID != 7013 || r.Conclusion != "" || r.Headline != "fix: loosen the schema" {
		t.Errorf("the run in progress read as %+v", r)
	}
	got = got[1:]
	want := WorkflowRun{ID: 7012, Number: 12, Attempt: 2, Event: "push", Branch: "main",
		Commit: strings.Repeat("a", 40), HeadRepo: "owner/repo-a", Headline: "fix: tighten the schema", Name: "Tests",
		Path: ".github/workflows/tests.yml", Conclusion: "failure", Created: time.Date(2026, 11, 20, 6, 0, 0, 0, time.UTC),
		Started: time.Date(2026, 11, 20, 6, 30, 0, 0, time.UTC), URL: "https://github.com/owner/repo-a/actions/runs/7012"}
	if got[0] != want {
		t.Errorf("the failed run read as %+v, want %+v", got[0], want)
	}
	if r := got[1]; r.Conclusion != "success" || r.Path != ".github/workflows/lint.yml" || r.Headline != "" ||
		r.HeadRepo != "" || !r.Started.Equal(r.Created) {
		t.Errorf("a run with no start, commit or head repository read as %+v", r)
	}
}

// A runs read that GitHub did not answer whole is an error, never a shorter
// list, and a read that names no branch or a page GitHub does not serve is
// refused before it calls gh.
func TestARunsReadThatDoesNotAnswerWholeFails(t *testing.T) {
	for name, body := range map[string]string{
		"no list of runs":            `{"total_count":0}`,
		"a run with no id":           `{"workflow_runs":[{"path":".github/workflows/a.yml","created_at":"2026-11-20T06:00:00Z"}]}`,
		"a run with no workflow":     `{"workflow_runs":[{"id":1,"created_at":"2026-11-20T06:00:00Z"}]}`,
		"a time that does not read":  `{"workflow_runs":[{"id":1,"path":".github/workflows/a.yml","created_at":"yesterday"}]}`,
		"a start that does not read": `{"workflow_runs":[{"id":1,"path":".github/workflows/a.yml","created_at":"2026-11-20T06:00:00Z","run_started_at":"soon"}]}`,
		"an answer that is not JSON": `<html>`,
		"a read that failed":         `!`,
	} {
		var log []string
		c := NewWithRunner("github.com", answers(t, map[string]string{runsPath: body}, &log))
		if got, err := c.BranchRuns("owner/repo-a", "main", 100); err == nil {
			t.Errorf("%s read as %+v", name, got)
		}
	}
	var log []string
	c := NewWithRunner("github.com", answers(t, map[string]string{}, &log))
	for name, read := range map[string]func() error{
		"a repository with no owner": func() error { _, err := c.BranchRuns("repo-a", "main", 1); return err },
		"no branch":                  func() error { _, err := c.BranchRuns("owner/repo-a", "", 1); return err },
		"a page of none":             func() error { _, err := c.BranchRuns("owner/repo-a", "main", 0); return err },
		"a page past GitHub's":       func() error { _, err := c.BranchRuns("owner/repo-a", "main", 101); return err },
		"a run with no id":           func() error { _, err := c.RunJobs("owner/repo-a", 0); return err },
	} {
		if read() == nil {
			t.Errorf("%s read", name)
		}
	}
	if len(log) != 0 {
		t.Errorf("a read refused before it ran still called gh: %q", log)
	}
}

// jobsPath is the read of the jobs of run 7012's latest attempt.
const jobsPath = "repos/owner/repo-a/actions/runs/7012/jobs?filter=latest&per_page=100"

// The jobs are every job of the run's latest attempt across all their pages,
// each with its steps, and a page that carries no list of jobs fails the
// whole read.
func TestTheJobsAreEveryJobOfTheLatestAttempt(t *testing.T) {
	var log []string
	c := NewWithRunner("github.com", answers(t, map[string]string{jobsPath: `{"total_count":2,"jobs":[
{"name":"test","conclusion":"failure","html_url":"https://github.com/owner/repo-a/actions/runs/7012/job/1","steps":[
 {"number":1,"name":"Set up job","conclusion":"success"},{"number":4,"name":"Run the tests","conclusion":"failure"},
 {"number":5,"name":"Post Run","conclusion":"skipped"}]}]}
{"total_count":2,"jobs":[{"name":"lint","conclusion":"success","html_url":"https://github.com/owner/repo-a/actions/runs/7012/job/2"}]}`}, &log))
	got, err := c.RunJobs("owner/repo-a", 7012)
	if err != nil {
		t.Fatal(err)
	}
	if len(log) != 1 || log[0] != "api --hostname github.com "+jobsPath+" --paginate" {
		t.Fatalf("the read ran %q", log)
	}
	if len(got) != 2 || got[0].Name != "test" || got[0].Conclusion != "failure" || len(got[0].Steps) != 3 ||
		got[0].Steps[1] != (Step{Number: 4, Name: "Run the tests", Conclusion: "failure"}) ||
		got[1].Name != "lint" || got[1].Steps == nil || len(got[1].Steps) != 0 {
		t.Errorf("RunJobs = %+v", got)
	}
	for name, body := range map[string]string{
		"a page with no list": `{"total_count":1,"jobs":[]}` + "\n" + `{"total_count":1}`,
		"no page":             ``,
		"a read that failed":  `!`,
	} {
		log = nil
		c := NewWithRunner("github.com", answers(t, map[string]string{jobsPath: body}, &log))
		if got, err := c.RunJobs("owner/repo-a", 7012); err == nil {
			t.Errorf("%s read as %+v", name, got)
		}
	}
}
