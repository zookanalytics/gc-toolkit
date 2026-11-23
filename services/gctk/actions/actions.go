// Package actions is the GitHub Actions domain: how each workflow a rig marks
// stands on the rig's default branch, as GitHub records its runs, and the
// patrol finding that carries a workflow's run of failures into the rig's own
// store. Its verb, `gctk actions report`, finds the workflows the default
// branch marks, reads each one's newest finished runs there, and files, notes
// or clears each one's finding through the runtime adapter's
// patrol-finding.sh. It owns no key on a bead and keeps no state of its own:
// each report reads the checkout and GitHub again, and the finding's writer
// keeps the finding.
//
// A workflow is the rig's to mark, with a line of its own in the workflow's
// file that reads Mark. The report reads the mark in the file, so a renamed
// workflow keeps it and a deleted one takes it along, and a rig whose files
// carry none costs a report no GitHub read.
package actions

import (
	"fmt"
	"path"
	"slices"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/git"
)

const (
	// Mark is the line that has a workflow's failures on the default branch
	// reported, at the start of a line of the workflow's file. Blanks after
	// the # and space at the end of the line read as the same line.
	Mark = "# gc:report-failures"
	// Window is how many of a workflow's newest finished runs on the default
	// branch a report reads: GitHub's largest page, so a run of failures
	// shorter than that shows the success before it.
	Window = 100
	// Listed is how many of a run of failures, and of a failed run's jobs,
	// the finding lists, newest first.
	Listed = 10
	// ReadBound bounds each GitHub read.
	ReadBound = 20 * time.Second
	// StartBound is how long after it starts a report still starts a
	// workflow. One it has not started by then is reported unread, so a
	// report ends inside the time its order gives it however many workflows
	// the rig marks.
	StartBound = 90 * time.Second
	// Scope is the finding's scope, named for the verb that files it.
	Scope = "actions-report"
	// Type and Priority are the finding's. A failed run on the default branch
	// is a failure there, which the pack's tracker of a failure on the
	// default branch files as a bug at priority 1
	// (assets/scripts/preexisting-failure.sh), so the proactive pool takes the
	// finding's reaction ahead of the default.
	Type     = "bug"
	Priority = 1
	// Script is the finding's writer, in the pack's scripts directory.
	Script = "patrol-finding.sh"
)

// markPattern is Mark as the checkout's grep reads it, an extended regular
// expression.
const markPattern = `^#[[:blank:]]*gc:report-failures[[:space:]]*$`

// workflowFiles are the pathspecs of the files GitHub runs as a repository's
// workflows: the YAML files directly under .github/workflows at its top.
var workflowFiles = []string{":(top,glob).github/workflows/*.yml", ":(top,glob).github/workflows/*.yaml"}

// The states of a workflow on the default branch.
const (
	// Failing is a newest decided run that failed.
	Failing = "failing"
	// Succeeded is a newest decided run that succeeded.
	Succeeded = "succeeded"
	// None is a read that holds no decided run.
	None = "none"
)

// City is Gas City as a report reaches it: its rigs, and the pack's scripts.
type City interface {
	Rigs() ([]gascity.Rig, error)
	Script(name string, args ...string) gascity.Result
}

// GitHub is GitHub as a report reaches it.
type GitHub interface {
	WorkflowRuns(repo, workflow, branch string, n int) ([]gh.WorkflowRun, error)
	RunJobs(repo string, run int64) ([]gh.Job, error)
}

// Checkout is a rig's checkout as a report reads it: the URL of its remote
// named origin, the branch origin's HEAD names, and the files at a rev whose
// text holds a line a pattern matches, among those pathspecs name.
type Checkout interface {
	OriginURL(dir string) (string, error)
	DefaultBranch(dir string) (string, error)
	Grep(dir, rev, pattern string, paths ...string) ([]string, error)
}

// Report reads the workflows one rig marks and keeps the finding of each.
// Host is the host the GitHub client reads, which the rig's origin must be on,
// and Now is the clock StartBound is read on.
type Report struct {
	City     City
	GitHub   GitHub
	Checkout Checkout
	Host     string
	Now      func() time.Time
}

// Verdict is how a workflow stands on the default branch. Newest is the newest
// decided run. When it failed, Failed is the run of failures it begins, newest
// first, Good is the newest success older than the run, nil when the read holds
// none, and Through says the run reaches the oldest run of a full window, so it
// may be longer than the read shows.
type Verdict struct {
	State   string
	Newest  *gh.WorkflowRun
	Failed  []gh.WorkflowRun
	Good    *gh.WorkflowRun
	Through bool
}

// failed reports whether a run or a job with conclusion failed: it failed, ran
// out of time or could not start.
func failed(conclusion string) bool {
	return conclusion == "failure" || conclusion == "timed_out" || conclusion == "startup_failure"
}

// Judge reads how a workflow stands from one read of its runs on the default
// branch, newest first, where full says the read filled its window. A failed
// run is a failure, and a success a success. A run that ends any other way,
// such as one cancelled or skipped, decides nothing, so it neither ends a run
// of failures nor extends one.
func Judge(runs []gh.WorkflowRun, full bool) Verdict {
	v := Verdict{State: None}
	for i := range runs {
		r := &runs[i]
		switch {
		case failed(r.Conclusion):
			if v.Newest == nil {
				v.State, v.Newest = Failing, r
			}
			v.Failed = append(v.Failed, *r)
		case r.Conclusion == "success":
			if v.Newest == nil {
				return Verdict{State: Succeeded, Newest: r}
			}
			v.Good = r
			return v
		}
	}
	v.Through = v.State == Failing && full
	return v
}

// branchRuns are the runs that ran on branch itself. A pull request's run is
// left out, since its head can carry the branch's name, and so is a run whose
// commit came from another repository, such as a fork's.
func branchRuns(runs []gh.WorkflowRun, repo, branch string) []gh.WorkflowRun {
	var out []gh.WorkflowRun
	for _, r := range runs {
		if r.Branch == branch && strings.EqualFold(r.HeadRepo, repo) && !strings.HasPrefix(r.Event, "pull_request") {
			out = append(out, r)
		}
	}
	return out
}

// Outcome is what one report read and did: the rig, its repository, its
// default branch, and each workflow the branch marks. Failure says why the
// report did not complete, the rig's own reads or each workflow's that did not,
// and is empty when it did.
type Outcome struct {
	Rig        string     `json:"rig"`
	Repository string     `json:"repository,omitempty"`
	Branch     string     `json:"branch,omitempty"`
	Workflows  []Workflow `json:"workflows"`
	Failure    string     `json:"failure,omitempty"`
}

// Workflow is what a report read and did for one workflow. State is the
// Verdict's, Failures the length of a run of failures, and Recorded what the
// finding's writer said. Would is the writer's arguments on a dry run, which
// calls no writer. Failure says why this workflow's report did not complete,
// and is empty when it did.
type Workflow struct {
	File     string   `json:"file"`
	State    string   `json:"state,omitempty"`
	Newest   *Ran     `json:"newest,omitempty"`
	Failures int      `json:"failures,omitempty"`
	Recorded string   `json:"recorded,omitempty"`
	Would    []string `json:"would,omitempty"`
	Failure  string   `json:"failure,omitempty"`
}

// Ran is the newest decided run, as an outcome names it.
type Ran struct {
	Number     int       `json:"number"`
	Attempt    int       `json:"attempt"`
	Event      string    `json:"event"`
	Commit     string    `json:"commit"`
	Conclusion string    `json:"conclusion"`
	Started    time.Time `json:"started"`
	Link       string    `json:"link"`
}

// Run reports the workflows rig marks on its default branch.
func (r *Report) Run(rig string, dryRun bool) Outcome {
	start := r.Now()
	out := Outcome{Rig: rig, Workflows: []Workflow{}}
	fail := func(format string, a ...any) Outcome {
		out.Failure = fmt.Sprintf(format, a...)
		return out
	}
	rigs, err := r.City.Rigs()
	if err != nil {
		return fail("the city's rigs did not read: %v", err)
	}
	i := slices.IndexFunc(rigs, func(g gascity.Rig) bool { return g.Name == rig })
	if i < 0 {
		return fail("the city names no rig %s", rig)
	}
	dir := rigs[i].Path
	url, err := r.Checkout.OriginURL(dir)
	if err != nil {
		return fail("the origin of %s's checkout %s did not read: %v", rig, dir, err)
	}
	host, repo, ok := git.RemoteRepository(url)
	if !ok || !strings.EqualFold(host, r.Host) {
		return fail("the origin of %s's checkout, %s, names no repository on %s", rig, url, r.Host)
	}
	out.Repository = repo
	branch, err := r.Checkout.DefaultBranch(dir)
	if err != nil {
		return fail("the default branch of %s's checkout %s did not read: %v", rig, dir, err)
	}
	out.Branch = branch
	files, err := r.Checkout.Grep(dir, "refs/remotes/origin/"+branch, markPattern, workflowFiles...)
	if err != nil {
		return fail("the workflows on %s in %s's checkout did not read: %v", branch, rig, err)
	}
	slices.Sort(files)
	var unfinished []string
	for _, f := range files {
		w := Workflow{File: path.Base(f)}
		if ran := r.Now().Sub(start); ran > StartBound {
			w.Failure = fmt.Sprintf("not read, since the report had run %s, past the %s in which it starts a workflow", ran.Round(time.Second), StartBound)
		} else {
			r.workflow(&w, rig, repo, branch, dryRun)
		}
		if w.Failure != "" {
			unfinished = append(unfinished, w.File+": "+w.Failure)
		}
		out.Workflows = append(out.Workflows, w)
	}
	out.Failure = strings.Join(unfinished, "; ")
	return out
}

// workflow reads one workflow's runs on branch and keeps its finding.
func (r *Report) workflow(w *Workflow, rig, repo, branch string, dryRun bool) {
	read, err := r.GitHub.WorkflowRuns(repo, w.File, branch, Window)
	if err != nil {
		w.Failure = fmt.Sprintf("GitHub did not answer for the runs of %s on %s of %s: %v", w.File, branch, repo, err)
		return
	}
	v := Judge(branchRuns(read, repo, branch), len(read) >= Window)
	w.State, w.Failures = v.State, len(v.Failed)
	if n := v.Newest; n != nil {
		w.Newest = &Ran{Number: n.Number, Attempt: n.Attempt, Event: n.Event, Commit: n.Commit, Conclusion: n.Conclusion, Started: n.Started, Link: n.URL}
	}
	var jobs []gh.Job
	if v.State == Failing {
		if jobs, err = r.GitHub.RunJobs(repo, v.Newest.ID); err != nil {
			w.Failure = fmt.Sprintf("GitHub did not answer for the jobs of run %d of %s in %s: %v", v.Newest.ID, w.File, repo, err)
			return
		}
	}
	args := findingArgs(rig, repo, branch, w.File, v, jobs)
	if args == nil {
		w.Recorded = fmt.Sprintf("no run of %s on %s among its newest %d succeeded or failed, so there is nothing to record", w.File, branch, Window)
		return
	}
	if dryRun {
		w.Would = args
		return
	}
	res := r.City.Script(Script, args...)
	if f := res.Failure(); f != "" {
		w.Failure = fmt.Sprintf("%s did not record the runs of %s on %s of %s: %s", Script, w.File, branch, repo, f)
		return
	}
	w.Recorded = res.Said("patrol-finding")
}

// Key is the finding's key for the workflow whose file is named file: one
// finding per workflow in a rig's store. A character a key does not take
// becomes a dash.
func Key(file string) string {
	return "actions." + strings.Map(func(c rune) rune {
		if c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '.' || c == '_' || c == '-' {
			return c
		}
		return '-'
	}, file)
}

// findingArgs are the finding writer's arguments for how a workflow stands: a
// report of a failing run, a clear on a success, and nil when the read holds
// no decided run.
func findingArgs(rig, repo, branch, file string, v Verdict, jobs []gh.Job) []string {
	base := []string{"--key", Key(file), "--scope", Scope, "--rig", rig}
	switch v.State {
	case Failing:
		return append(base, "--type", Type, "--priority", fmt.Sprint(Priority),
			"--title", title(repo, branch, file, v), "--message", message(repo, branch, file, v, jobs))
	case Succeeded:
		n := v.Newest
		return append(base, "--cleared", "--message", fmt.Sprintf("The workflow %s succeeded on %s of %s in %s at %s: %s",
			named(file, n), branch, repo, runName(n), stamp(n.Started), n.URL))
	}
	return nil
}

// title is the finding's label, which its bead keeps from its first filing.
func title(repo, branch, file string, v Verdict) string {
	return fmt.Sprintf("The workflow %s fails on %s of %s", named(file, v.Newest), branch, repo)
}

// message is the finding's text. It is made from what the read holds of the
// run of failures and nothing of when it was read, so a report of a run that
// has not moved repeats it, and the finding counts the report, while a new
// failure changes it. The window a run outgrows moves with every new run, so
// the text names nothing that depends on where the window ends. Its first
// line names the newest failure and its link, because the note a changed text
// leaves on the finding keeps only its first 200 characters.
func message(repo, branch, file string, v Verdict, jobs []gh.Job) string {
	n := v.Newest
	first := &v.Failed[len(v.Failed)-1]
	var b strings.Builder
	fmt.Fprintf(&b, "The workflow %s failed on %s of %s in %s at %s: %s\n\n", named(file, n), branch, repo, runName(n), stamp(n.Started), n.URL)
	fmt.Fprintf(&b, "It ran for the %s event on commit %s", n.Event, short(n.Commit))
	if h := oneLine(n.Headline); h != "" {
		fmt.Fprintf(&b, ": %s", h)
	}
	b.WriteString("\n\n")
	switch {
	case v.Good != nil && len(v.Failed) == 1:
		fmt.Fprintf(&b, "The last success before it was %s at %s%s\n\n", runName(v.Good), stamp(v.Good.Started), changes(repo, v.Good, n))
	case v.Good != nil:
		fmt.Fprintf(&b, "%d runs in a row have failed, the first %s at %s. The last success before them was %s at %s%s\n\n",
			len(v.Failed), runName(first), stamp(first.Started), runName(v.Good), stamp(v.Good.Started), changes(repo, v.Good, first))
	case v.Through:
		fmt.Fprintf(&b, "None of the newest %d runs of the workflow on %s succeeded, so the failures may have begun before them.\n\n", Window, branch)
	case len(v.Failed) == 1:
		fmt.Fprintf(&b, "No run of the workflow on %s has succeeded, and none failed before this one.\n\n", branch)
	default:
		fmt.Fprintf(&b, "No run of the workflow on %s has succeeded. %d have failed, the first %s at %s.\n\n",
			branch, len(v.Failed), runName(first), stamp(first.Started))
	}
	fmt.Fprintf(&b, "What failed in %s:\n", runName(n))
	var red []gh.Job
	for _, j := range jobs {
		if failed(j.Conclusion) {
			red = append(red, j)
		}
	}
	for _, j := range red[:min(len(red), Listed)] {
		fmt.Fprintf(&b, "- the job %s: %s%s", oneLine(j.Name), j.Conclusion, at(j.Steps))
		if j.URL != "" {
			fmt.Fprintf(&b, ", %s", j.URL)
		}
		b.WriteByte('\n')
	}
	switch {
	case len(red) == 0:
		b.WriteString("- GitHub lists no failed job in it\n")
	case len(red) > Listed:
		b.WriteString("- and more failed jobs\n")
	}
	fmt.Fprintf(&b, "\nIts failed steps' log prints with: gh run view %d --repo %s --log-failed\n\n", n.ID, repo)
	b.WriteString("The failed runs, newest first:\n")
	for i := range v.Failed[:min(len(v.Failed), Listed)] {
		f := &v.Failed[i]
		fmt.Fprintf(&b, "- %s at %s, for the %s event on commit %s: %s, %s\n", runName(f), stamp(f.Started), f.Event, short(f.Commit), f.Conclusion, f.URL)
	}
	if len(v.Failed) > Listed {
		b.WriteString("- and older failures\n")
	}
	fmt.Fprintf(&b, "\nThis finding notes each later failure, and the next run of the workflow on %s that succeeds clears its situation.", branch)
	return b.String()
}

// at names the steps of a failed job that ended in neither a success nor a
// skip, as a job's line closes, and nothing when it has none.
func at(steps []gh.Step) string {
	var names []string
	for _, s := range steps {
		if s.Conclusion != "" && s.Conclusion != "success" && s.Conclusion != "skipped" {
			names = append(names, fmt.Sprintf("%s (%s)", oneLine(s.Name), s.Conclusion))
		}
	}
	switch len(names) {
	case 0:
		return ""
	case 1:
		return ", at the step " + names[0]
	}
	return ", at the steps " + strings.Join(names, ", ")
}

// changes closes the sentence that names the success before a run of
// failures: the changes from its commit to the first failure's, or that the
// two ran on one commit.
func changes(repo string, from, to *gh.WorkflowRun) string {
	if from.Commit == to.Commit {
		return ", on the same commit, so the code did not change between them."
	}
	return ", and the changes between their commits are https://github.com/" + repo + "/compare/" + from.Commit + "..." + to.Commit
}

// named is how a message names the workflow: its name with its file, or its
// file alone when the workflow names itself after its path, as GitHub names
// one whose file gives it no name.
func named(file string, r *gh.WorkflowRun) string {
	name := oneLine(r.Name)
	if name == "" || name == file || strings.HasSuffix(name, "/"+file) {
		return file
	}
	return name + " (" + file + ")"
}

// runName is a run as a message names it: its number, with its attempt when
// GitHub ran it more than once.
func runName(r *gh.WorkflowRun) string {
	if r.Attempt > 1 {
		return fmt.Sprintf("run #%d (attempt %d)", r.Number, r.Attempt)
	}
	return fmt.Sprintf("run #%d", r.Number)
}

// short is a commit's short oid.
func short(commit string) string { return commit[:min(len(commit), 7)] }

// stamp is a time as a message names it.
func stamp(t time.Time) string { return t.UTC().Format("2006-01-02 15:04 UTC") }

// oneLine is text on one line, its control characters blanked and its runs of
// space closed up.
func oneLine(s string) string {
	return strings.Join(strings.FieldsFunc(s, func(r rune) bool { return r == ' ' || r < 0x20 || r == 0x7f }), " ")
}
