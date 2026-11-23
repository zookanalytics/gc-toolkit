package actions

import (
	"errors"
	"fmt"
	"regexp"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	gcfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	ghfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh/fake"
)

// t0 is the time the first run of a test started.
var t0 = time.Date(2026, 11, 20, 6, 0, 0, 0, time.UTC)

// run is run number n of the Nightly workflow on main, of the commit whose oid is
// c repeated, started h hours after t0, which ended as conclusion.
func run(c byte, n, h int, conclusion string) gh.WorkflowRun {
	at := t0.Add(time.Duration(h) * time.Hour)
	return gh.WorkflowRun{ID: int64(1000 + n), Number: n, Attempt: 1, Event: "schedule", Branch: "main",
		Commit: strings.Repeat(string(c), 40), HeadRepo: "owner/repo-a", Headline: fmt.Sprintf("change %d", n),
		Name: "Nightly", Conclusion: conclusion, Created: at, Started: at,
		URL: fmt.Sprintf("https://github.com/owner/repo-a/actions/runs/%d", 1000+n)}
}

// failures is n failed runs, newest first, the newest numbered n started h
// hours after t0 and each an hour before the one after it.
func failures(n, h int) []gh.WorkflowRun {
	var out []gh.WorkflowRun
	for i := range n {
		out = append(out, run(byte('a'+i%20), n-i, h-i, "failure"))
	}
	return out
}

// The mark is a line of its own, from its first character: blanks after the #
// and space at its end read as the same line, and the mark inside other text
// does not.
func TestTheMarkIsALineOfItsOwn(t *testing.T) {
	re := regexp.MustCompile("(?m)" + markPattern)
	for _, line := range []string{Mark, "#gc:report-failures", "#\t gc:report-failures  ", Mark + "\r"} {
		if !re.MatchString("name: A\n" + line + "\non: push\n") {
			t.Errorf("%q is not read as the mark", line)
		}
	}
	for _, line := range []string{"  " + Mark, "run: echo '" + Mark + "'", Mark + "-later", "# gc:report-failures for nightly", "# gc: report-failures"} {
		if re.MatchString("name: A\n" + line + "\n") {
			t.Errorf("%q is read as the mark", line)
		}
	}
}

// A newest success is the state, whatever fails before it.
func TestANewestSuccessSucceeds(t *testing.T) {
	v := Judge([]gh.WorkflowRun{run('b', 2, 2, "success"), run('a', 1, 1, "failure")}, false)
	if v.State != Succeeded || v.Newest == nil || v.Newest.Number != 2 || len(v.Failed) != 0 || v.Good != nil {
		t.Fatalf("Judge = %+v", v)
	}
}

// A run of failures is every failed run from the newest back to the success
// before it, a timeout and a failure to start among them. A run cancelled,
// skipped or ended any other way neither ends the run of failures nor joins
// it.
func TestARunOfFailuresEndsAtTheSuccessBeforeIt(t *testing.T) {
	v := Judge([]gh.WorkflowRun{
		run('x', 9, 9, "cancelled"),
		run('d', 8, 8, "failure"),
		run('y', 7, 7, "skipped"),
		run('c', 6, 6, "timed_out"),
		run('z', 5, 5, "neutral"),
		run('b', 4, 4, "startup_failure"),
		run('w', 10, 3, "action_required"),
		run('v', 11, 3, "stale"),
		run('a', 3, 3, "success"),
		run('u', 2, 2, "failure"),
	}, true)
	var nums []int
	for _, f := range v.Failed {
		nums = append(nums, f.Number)
	}
	if v.State != Failing || v.Newest.Number != 8 || !slices.Equal(nums, []int{8, 6, 4}) || v.Good == nil || v.Good.Number != 3 || v.Through {
		t.Fatalf("Judge = state %s, newest %+v, run %v, good %+v, through %v", v.State, v.Newest, nums, v.Good, v.Through)
	}
}

// A read with no run that succeeded or failed decides nothing, and a run of
// failures that fills a full window may be longer than the read shows.
func TestARunThatFillsTheWindowMayBeLonger(t *testing.T) {
	if v := Judge([]gh.WorkflowRun{run('a', 2, 2, "cancelled"), run('b', 1, 1, "skipped")}, true); v.State != None || v.Newest != nil || v.Through {
		t.Fatalf("a read with nothing decided = %+v", v)
	}
	if v := Judge(failures(5, 10), true); v.State != Failing || len(v.Failed) != 5 || !v.Through || v.Good != nil {
		t.Fatalf("a full window of failures read as %+v", v)
	}
	if v := Judge(failures(4, 10), false); v.State != Failing || len(v.Failed) != 4 || v.Through || v.Good != nil {
		t.Fatalf("every run there is, each a failure, read as %+v", v)
	}
}

// Only the branch's own runs count: not a pull request's, whose head can carry
// the branch's name, not one whose commit came from a fork, and not another
// branch's.
func TestOnlyTheBranchsOwnRunsCount(t *testing.T) {
	pr, fork, other, own := run('a', 4, 4, "failure"), run('b', 3, 3, "failure"), run('c', 2, 2, "failure"), run('d', 1, 1, "failure")
	pr.Event, fork.HeadRepo, other.Branch, own.HeadRepo = "pull_request_target", "someone/repo-a", "release", "Owner/Repo-A"
	got := branchRuns([]gh.WorkflowRun{pr, fork, other, own}, "owner/repo-a", "main")
	if len(got) != 1 || got[0].Number != 1 {
		t.Fatalf("branchRuns = %+v, want run 1 alone", got)
	}
}

// The key is one per workflow file, in the characters a finding's key takes.
func TestTheKeyIsOnePerWorkflow(t *testing.T) {
	valid := regexp.MustCompile(`^[A-Za-z0-9._-]+$`)
	for file, want := range map[string]string{
		"nightly.yml":        "actions.nightly.yml",
		"Nightly_Build.yaml": "actions.Nightly_Build.yaml",
		"a b+c.yml":          "actions.a-b-c.yml",
	} {
		if got := Key(file); got != want || !valid.MatchString(got) {
			t.Errorf("Key(%q) = %q, want %q", file, got, want)
		}
	}
}

// checkout is a rig's checkout: its origin, origin's default branch, and the
// files that branch marks. It records each grep.
type checkout struct {
	origin, branch       string
	marked               []string
	originErr, branchErr error
	grepErr              error
	greps                [][]string
}

func (c *checkout) OriginURL(dir string) (string, error) {
	if dir != "/city/rigs/rig-a" {
		return "", fmt.Errorf("no checkout at %s", dir)
	}
	return c.origin, c.originErr
}

func (c *checkout) DefaultBranch(string) (string, error) { return c.branch, c.branchErr }

func (c *checkout) Grep(dir, rev, pattern string, paths ...string) ([]string, error) {
	c.greps = append(c.greps, append([]string{dir, rev, pattern}, paths...))
	return slices.Clone(c.marked), c.grepErr
}

// world is a city with one rig whose checkout's origin is owner/repo-a on
// github.com, whose default branch marks the workflows it names, and that
// repository's runs and jobs.
type world struct {
	city   *gcfake.Runtime
	gh     *ghfake.GitHub
	co     *checkout
	report *Report
}

func newWorld(runs map[string][]gh.WorkflowRun) *world {
	w := &world{
		city: &gcfake.Runtime{RigList: []gascity.Rig{{Name: "rig-a", Path: "/city/rigs/rig-a", Prefix: "ra"}}},
		gh:   ghfake.New("bot"),
		co:   &checkout{origin: "git@github.com:owner/repo-a.git", branch: "main"},
	}
	for f := range runs {
		w.co.marked = append(w.co.marked, ".github/workflows/"+f)
	}
	w.gh.Repos = map[string]*ghfake.Repo{"owner/repo-a": {Runs: runs, Jobs: map[int64][]gh.Job{}}}
	w.city.OnScript = func(c gcfake.Call) gascity.Result {
		key, _ := arg(c.Args, "--key")
		return gascity.Result{Output: "patrol-finding: filed ra-1 for [" + key + "]\n{\"slung\":true}\n"}
	}
	w.report = &Report{City: w.city, GitHub: w.gh, Checkout: w.co, Host: "github.com", Now: func() time.Time { return t0 }}
	return w
}

// arg is the value that follows flag in args, and whether flag is there.
func arg(args []string, flag string) (string, bool) {
	i := slices.Index(args, flag)
	if i < 0 || i+1 >= len(args) {
		return "", i >= 0
	}
	return args[i+1], true
}

// The report reads the marks at origin's default branch, among the files
// GitHub runs as workflows.
func TestTheMarksAreReadAtOriginsDefaultBranch(t *testing.T) {
	w := newWorld(map[string][]gh.WorkflowRun{"nightly.yml": {run('a', 1, 1, "success")}})
	w.co.branch = "trunk"
	w.report.Run("rig-a", true)
	want := []string{"/city/rigs/rig-a", "refs/remotes/origin/trunk", markPattern, ":(top,glob).github/workflows/*.yml", ":(top,glob).github/workflows/*.yaml"}
	if len(w.co.greps) != 1 || !slices.Equal(w.co.greps[0], want) {
		t.Fatalf("the report grepped %q, want %q", w.co.greps, want)
	}
}

// A failing run is reported once, through the finding's writer, as a bug in the
// rig's store under the workflow's key, and the outcome names it.
func TestAFailingRunIsReportedAsOneFinding(t *testing.T) {
	w := newWorld(map[string][]gh.WorkflowRun{"nightly.yml": {run('c', 13, 3, "failure"), run('b', 12, 2, "timed_out"), run('a', 11, 1, "success")}})
	w.gh.Repos["owner/repo-a"].Jobs[1013] = []gh.Job{
		{Name: "test", Conclusion: "failure", URL: "https://github.com/owner/repo-a/actions/runs/1013/job/1", Steps: []gh.Step{
			{Number: 1, Name: "Set up job", Conclusion: "success"}, {Number: 4, Name: "Run the tests", Conclusion: "failure"}, {Number: 5, Name: "Post", Conclusion: "skipped"}}},
		{Name: "lint", Conclusion: "success", URL: "https://github.com/owner/repo-a/actions/runs/1013/job/2"},
	}
	out := w.report.Run("rig-a", false)
	if out.Failure != "" {
		t.Fatalf("the report failed: %s", out.Failure)
	}
	calls := w.city.Scripts()
	if len(calls) != 1 || calls[0].Name != "patrol-finding.sh" {
		t.Fatalf("the report ran %+v, want patrol-finding.sh once", calls)
	}
	args := calls[0].Args
	for flag, want := range map[string]string{"--key": "actions.nightly.yml", "--scope": "actions-report", "--rig": "rig-a", "--type": "bug", "--priority": "1"} {
		if got, _ := arg(args, flag); got != want {
			t.Errorf("%s = %q, want %q, in %q", flag, got, want, args)
		}
	}
	if _, ok := arg(args, "--cleared"); ok {
		t.Errorf("a failing run was reported as cleared: %q", args)
	}
	if got, _ := arg(args, "--title"); got != "The workflow Nightly (nightly.yml) fails on main of owner/repo-a" {
		t.Errorf("the title is %q", got)
	}
	msg, _ := arg(args, "--message")
	first, _, _ := strings.Cut(msg, "\n")
	if first != "The workflow Nightly (nightly.yml) failed on main of owner/repo-a in run #13 at 2026-11-20 09:00 UTC: https://github.com/owner/repo-a/actions/runs/1013" {
		t.Errorf("the message opens %q", first)
	}
	for _, want := range []string{
		"\n\nIt ran for the schedule event on commit ccccccc: change 13\n\n",
		"2 runs in a row have failed, the first run #12 at 2026-11-20 08:00 UTC. The one before them, run #11 at 2026-11-20 07:00 UTC, succeeded, and the changes between their commits are https://github.com/owner/repo-a/compare/" + strings.Repeat("a", 40) + "..." + strings.Repeat("b", 40) + "\n\n",
		"What failed in run #13:\n- the job test: failure, at the step Run the tests (failure), https://github.com/owner/repo-a/actions/runs/1013/job/1\n\n",
		"Its failed steps' log prints with: gh run view 1013 --repo owner/repo-a --log-failed\n\n",
		"The failed runs, newest first:\n- run #13 at 2026-11-20 09:00 UTC, for the schedule event on commit ccccccc: failure, https://github.com/owner/repo-a/actions/runs/1013\n- run #12 at 2026-11-20 08:00 UTC, for the schedule event on commit bbbbbbb: timed_out, https://github.com/owner/repo-a/actions/runs/1012\n\n",
		"the next run of the workflow on main that succeeds clears its situation.",
	} {
		if !strings.Contains(msg, want) {
			t.Errorf("the message does not say %q:\n%s", want, msg)
		}
	}
	if len(out.Workflows) != 1 {
		t.Fatalf("the outcome is %+v", out)
	}
	got := out.Workflows[0]
	if out.Repository != "owner/repo-a" || out.Branch != "main" || got.File != "nightly.yml" || got.State != Failing || got.Failures != 2 ||
		got.Newest == nil || got.Newest.Number != 13 || got.Newest.Link != "https://github.com/owner/repo-a/actions/runs/1013" ||
		got.Recorded != "filed ra-1 for [actions.nightly.yml]" {
		t.Errorf("the outcome is %+v, its workflow %+v", out, got)
	}
}

// A success clears the finding's situation, naming the success, and files
// nothing new.
func TestASuccessClearsTheFinding(t *testing.T) {
	w := newWorld(map[string][]gh.WorkflowRun{"nightly.yml": {run('z', 15, 5, "cancelled"), run('b', 14, 4, "success"), run('a', 13, 3, "failure")}})
	out := w.report.Run("rig-a", false)
	calls := w.city.Scripts()
	if out.Failure != "" || len(calls) != 1 {
		t.Fatalf("the report ran %+v: %+v", calls, out)
	}
	args := calls[0].Args
	if _, ok := arg(args, "--cleared"); !ok {
		t.Fatalf("a success was not reported as cleared: %q", args)
	}
	if got, _ := arg(args, "--key"); got != "actions.nightly.yml" {
		t.Errorf("--key = %q", got)
	}
	if got, _ := arg(args, "--message"); got != "The workflow Nightly (nightly.yml) succeeded on main of owner/repo-a in run #14 at 2026-11-20 10:00 UTC: https://github.com/owner/repo-a/actions/runs/1014" {
		t.Errorf("the clear's reason is %q", got)
	}
	for _, flag := range []string{"--title", "--type", "--priority"} {
		if _, ok := arg(args, flag); ok {
			t.Errorf("a clear passed %s: %q", flag, args)
		}
	}
	if got := out.Workflows[0]; got.State != Succeeded || got.Failures != 0 {
		t.Errorf("the outcome is %+v", got)
	}
	if reads := w.gh.Reads(); !slices.Equal(reads, []string{"WorkflowRuns"}) {
		t.Errorf("a success read %q of GitHub, want the runs alone", reads)
	}
}

// A rig whose default branch marks no workflow asks GitHub nothing and writes
// nothing, and a read with no decided run records nothing.
func TestNothingMarkedOrDecidedWritesNothing(t *testing.T) {
	w := newWorld(nil)
	out := w.report.Run("rig-a", false)
	if out.Failure != "" || len(out.Workflows) != 0 || len(w.gh.Reads()) != 0 || len(w.city.Scripts()) != 0 {
		t.Errorf("a rig that marks nothing: %+v, reads %q, writes %+v", out, w.gh.Reads(), w.city.Scripts())
	}
	w = newWorld(map[string][]gh.WorkflowRun{"nightly.yml": {run('a', 1, 1, "cancelled")}})
	out = w.report.Run("rig-a", false)
	if out.Failure != "" || out.Workflows[0].State != None || !strings.Contains(out.Workflows[0].Recorded, "nothing to record") || len(w.city.Scripts()) != 0 {
		t.Errorf("a read with nothing decided: %+v", out)
	}
}

// A dry run reads the checkout and GitHub and calls no writer.
func TestADryRunWritesNothing(t *testing.T) {
	w := newWorld(map[string][]gh.WorkflowRun{"nightly.yml": {run('b', 2, 2, "failure"), run('a', 1, 1, "success")}})
	out := w.report.Run("rig-a", true)
	got := out.Workflows[0]
	if out.Failure != "" || got.State != Failing || len(got.Would) == 0 || got.Recorded != "" {
		t.Errorf("a dry run's outcome is %+v", got)
	}
	if key, _ := arg(got.Would, "--key"); key != "actions.nightly.yml" {
		t.Errorf("a dry run would pass %q", got.Would)
	}
	if calls := w.city.Scripts(); len(calls) != 0 {
		t.Errorf("a dry run called %+v", calls)
	}
	if reads := w.gh.Reads(); !slices.Equal(reads, []string{"WorkflowRuns", "RunJobs"}) {
		t.Errorf("a dry run read %q of GitHub, want the runs and the failure's jobs", reads)
	}
}

// A report that cannot read what it decides on writes nothing and says why:
// the rig list, the rig, its origin, a host other than the client's, the
// default branch, the marks, GitHub's runs and jobs, and the writer itself.
func TestAReadThatFailsWritesNothing(t *testing.T) {
	failing := map[string][]gh.WorkflowRun{"nightly.yml": {run('b', 2, 2, "failure")}}
	for name, tc := range map[string]struct {
		set  func(*world)
		want string
	}{
		"the rig list":       {func(w *world) { w.city.RigsErr = errors.New("gc: no city") }, "the city's rigs did not read"},
		"an unknown rig":     {func(w *world) { w.city.RigList = nil }, "the city names no rig rig-a"},
		"the origin":         {func(w *world) { w.co.originErr = errors.New("not a git repository") }, "did not read: not a git repository"},
		"no repository":      {func(w *world) { w.co.origin = "" }, "names no repository on github.com"},
		"another host":       {func(w *world) { w.co.origin = "git@git.example.com:owner/repo-a.git" }, "names no repository on github.com"},
		"the default branch": {func(w *world) { w.co.branchErr = errors.New("origin/HEAD names no branch") }, "the default branch of rig-a's checkout /city/rigs/rig-a did not read"},
		"the marks":          {func(w *world) { w.co.grepErr = errors.New("git grep: bad revision") }, "the workflows on main in rig-a's checkout did not read: git grep: bad revision"},
		"the runs":           {func(w *world) { w.gh.Fail["WorkflowRuns"] = errors.New("gh: HTTP 502") }, "nightly.yml: GitHub did not answer for the runs of nightly.yml on main of owner/repo-a: gh: HTTP 502"},
		"an unknown workflow": {func(w *world) { w.co.marked = []string{".github/workflows/gone.yml"} },
			"gone.yml: GitHub did not answer for the runs of gone.yml"},
		"the jobs": {func(w *world) { w.gh.Fail["RunJobs"] = errors.New("gh: HTTP 502") }, "nightly.yml: GitHub did not answer for the jobs of run 1002 of nightly.yml in owner/repo-a: gh: HTTP 502"},
	} {
		w := newWorld(failing)
		tc.set(w)
		out := w.report.Run("rig-a", false)
		if !strings.Contains(out.Failure, tc.want) {
			t.Errorf("%s: the failure is %q, want %q", name, out.Failure, tc.want)
		}
		if calls := w.city.Scripts(); len(calls) != 0 {
			t.Errorf("%s: a report that did not read called %+v", name, calls)
		}
	}
	w := newWorld(failing)
	w.co.origin = "git@git.example.com:owner/repo-a.git"
	if w.report.Run("rig-a", false); len(w.gh.Reads()) != 0 || len(w.co.greps) != 0 {
		t.Errorf("a report whose origin is on another host read GitHub %q and grepped %q", w.gh.Reads(), w.co.greps)
	}
	w = newWorld(failing)
	w.city.OnScript = func(gcfake.Call) gascity.Result {
		return gascity.Result{Code: 1, Output: "patrol-finding: dedup lookup failed for [actions.nightly.yml]\n"}
	}
	if out := w.report.Run("rig-a", false); !strings.Contains(out.Failure, "nightly.yml: patrol-finding.sh did not record the runs of nightly.yml on main of owner/repo-a: exit 1: patrol-finding: dedup lookup failed") {
		t.Errorf("a writer that failed: %+v", out)
	}
}

// One workflow that does not read leaves the others reported, and the outcome
// names the one alone.
func TestOneWorkflowsFailureLeavesTheOthersReported(t *testing.T) {
	w := newWorld(map[string][]gh.WorkflowRun{
		"nightly.yml": {run('a', 1, 1, "success")},
		"lint.yml":    {run('b', 2, 2, "success")},
	})
	w.co.marked = append(w.co.marked, ".github/workflows/gone.yml")
	out := w.report.Run("rig-a", false)
	var files []string
	for _, wf := range out.Workflows {
		files = append(files, wf.File)
	}
	if !slices.Equal(files, []string{"gone.yml", "lint.yml", "nightly.yml"}) {
		t.Fatalf("the workflows reported are %q, want each marked one in order", files)
	}
	if !strings.HasPrefix(out.Failure, "gone.yml: GitHub did not answer") || strings.Contains(out.Failure, "lint.yml") || strings.Contains(out.Failure, "nightly.yml") {
		t.Errorf("the failure is %q, want gone.yml's alone", out.Failure)
	}
	if calls := w.city.Scripts(); len(calls) != 2 {
		t.Errorf("the report wrote %+v, want a clear for each workflow that read", calls)
	}
}

// A report starts no workflow past its start bound, and reports each it did not
// start as unread.
func TestAReportStartsNoWorkflowPastItsBound(t *testing.T) {
	w := newWorld(map[string][]gh.WorkflowRun{
		"a.yml": {run('a', 1, 1, "success")},
		"b.yml": {run('b', 2, 2, "success")},
		"c.yml": {run('c', 3, 3, "success")},
	})
	now := t0
	w.report.Now = func() time.Time { return now }
	w.city.OnScript = func(gcfake.Call) gascity.Result {
		now = now.Add(StartBound/2 + time.Second)
		return gascity.Result{Output: "patrol-finding: no live bead holds it\n"}
	}
	out := w.report.Run("rig-a", false)
	if len(w.city.Scripts()) != 2 || len(out.Workflows) != 3 || out.Workflows[2].State != "" ||
		!strings.Contains(out.Failure, "c.yml: not read, since the report had run 1m32s, past the 1m30s in which it starts a workflow") {
		t.Errorf("the report wrote %+v: %+v", w.city.Scripts(), out)
	}
}

// The message is made from the run of failures alone, so a report of a run that
// has not moved repeats it, whatever else the window holds, and a new failure
// changes its first line, which is the part the finding notes.
func TestTheMessageMovesOnlyWithTheRun(t *testing.T) {
	msg := func(runs []gh.WorkflowRun) string {
		v := Judge(runs, len(runs) >= Window)
		if v.State != Failing {
			t.Fatalf("the read is %s", v.State)
		}
		return message("owner/repo-a", "main", "nightly.yml", v, nil)
	}
	runs := []gh.WorkflowRun{run('c', 13, 3, "failure"), run('b', 12, 2, "failure"), run('a', 11, 1, "success")}
	base := msg(runs)
	if got := msg(append([]gh.WorkflowRun{run('z', 14, 4, "cancelled")}, runs...)); got != base {
		t.Errorf("a cancelled run changed the message:\n%s\nfrom\n%s", got, base)
	}
	next := msg(append([]gh.WorkflowRun{run('d', 14, 4, "failure")}, runs...))
	first, _, _ := strings.Cut(next, "\n")
	if next == base || !strings.HasPrefix(first, "The workflow Nightly (nightly.yml) failed on main of owner/repo-a in run #14") {
		t.Errorf("a new failure opens the message %q", first)
	}
	if len([]rune(first)) > 200 {
		t.Errorf("the first line runs %d characters, past the 200 a note keeps: %q", len([]rune(first)), first)
	}

	// A run longer than the window: a newer run that decides nothing pushes
	// the oldest failure out, and the message stays.
	full := failures(Window, 200)
	long := msg(full)
	if !strings.Contains(long, "None of the newest 100 runs of the workflow on main succeeded") || !strings.Contains(long, "- and older failures\n") {
		t.Errorf("a run past the window reads:\n%s", long)
	}
	slid := append([]gh.WorkflowRun{run('z', 201, 201, "skipped")}, full[:Window-1]...)
	if got := msg(slid); got != long {
		t.Errorf("the window's slide changed the message:\n%s\nfrom\n%s", got, long)
	}
	_, list, _ := strings.Cut(long, "The failed runs, newest first:\n")
	list, _, _ = strings.Cut(list, "\n\n")
	if n := strings.Count(list, "\n") + 1; n != Listed+1 {
		t.Errorf("the message lists %d lines of failures, want the newest %d and one for the older ones:\n%s", n, Listed, list)
	}
}

// A lone failure after a success on the same commit says the code did not
// change, a run with no success says how long it is, a run GitHub ran again
// names its attempt, and a failed run with no failed job says so.
func TestTheRunsAroundTheFailureAreNamed(t *testing.T) {
	again := run('a', 12, 2, "failure")
	again.Attempt = 2
	lone := message("owner/repo-a", "main", "nightly.yml", Judge([]gh.WorkflowRun{again, run('a', 11, 1, "success")}, false), nil)
	for _, want := range []string{
		"in run #12 (attempt 2) at 2026-11-20 08:00 UTC",
		"The run before it, run #11 at 2026-11-20 07:00 UTC, succeeded, on the same commit, so the code did not change between them.\n\n",
		"What failed in run #12 (attempt 2):\n- GitHub lists no failed job in it\n",
	} {
		if !strings.Contains(lone, want) {
			t.Errorf("a lone failure on an unchanged commit does not say %q:\n%s", want, lone)
		}
	}
	never := message("owner/repo-a", "main", "nightly.yml", Judge(failures(3, 5), false), nil)
	if !strings.Contains(never, "No run of the workflow on main has succeeded. 3 have failed, the first run #1 at 2026-11-20 09:00 UTC.") {
		t.Errorf("a run with no success reads:\n%s", never)
	}
	var jobs []gh.Job
	for i := range Listed + 2 {
		jobs = append(jobs, gh.Job{Name: fmt.Sprintf("shard %d", i), Conclusion: "failure"})
	}
	many := message("owner/repo-a", "main", "nightly.yml", Judge(failures(1, 1), false), jobs)
	if strings.Count(many, "- the job shard") != Listed || !strings.Contains(many, "- and more failed jobs\n") {
		t.Errorf("a run with many failed jobs reads:\n%s", many)
	}
}

// A workflow whose file names it nothing is named by its file alone.
func TestAWorkflowWithNoNameIsNamedByItsFile(t *testing.T) {
	r := run('a', 1, 1, "failure")
	for name, want := range map[string]string{"": "nightly.yml", ".github/workflows/nightly.yml": "nightly.yml", "nightly.yml": "nightly.yml", "Nightly\nbuild": "Nightly build (nightly.yml)"} {
		r.Name = name
		if got := named("nightly.yml", &r); got != want {
			t.Errorf("named for %q = %q, want %q", name, got, want)
		}
	}
}
