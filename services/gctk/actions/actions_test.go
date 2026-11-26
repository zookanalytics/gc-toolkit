package actions

import (
	"errors"
	"fmt"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	gcfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	ghfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// t0 is the time the first run of a test was made.
var t0 = time.Date(2026, 11, 20, 6, 0, 0, 0, time.UTC)

const (
	repo  = "owner/repo-a"
	tests = ".github/workflows/tests.yml"
	lint  = ".github/workflows/lint.yml"
)

// run is run number n of the workflow whose file is path, which a push to main
// of repo started on the commit whose oid is c repeated, made and started h
// hours after t0, and which ended as conclusion.
func run(path string, n int, c byte, h int, conclusion string) gh.WorkflowRun {
	at := t0.Add(time.Duration(h) * time.Hour)
	return gh.WorkflowRun{ID: int64(1000 + n), Number: n, Attempt: 1, Event: "push", Branch: "main",
		Commit: strings.Repeat(string(c), 40), HeadRepo: repo, Headline: fmt.Sprintf("change %d", n), Name: "Tests",
		Path: path, Conclusion: conclusion, Created: at, Started: at,
		URL: fmt.Sprintf("https://github.com/%s/actions/runs/%d", repo, 1000+n)}
}

// city is one rig and what a pass over it reaches: GitHub, the rig's store,
// and the tracker's writer, which answers as preexisting-failure.sh does: key
// prints the path it is given, find prints the live tracker of a key, and file
// files one, sends it and prints its id last.
type city struct {
	rt     *gcfake.Runtime
	hub    *ghfake.GitHub
	store  *fake.Store
	live   map[string]string
	filed  int
	opened []string
}

func newCity(runs ...gh.WorkflowRun) *city {
	c := &city{rt: &gcfake.Runtime{}, hub: ghfake.New("bot"), store: fake.New(), live: map[string]string{}}
	c.rt.RigList = []gascity.Rig{{Name: "rig-a", Path: "/city/rigs/rig-a", Prefix: "ra"}}
	c.hub.Repos = map[string]*ghfake.Repo{repo: {Runs: runs, Jobs: map[int64][]gh.Job{}}}
	c.rt.OnScript = c.writer
	return c
}

func (c *city) writer(call gcfake.Call) gascity.Result {
	switch a := call.Args; a[0] {
	case "key":
		return gascity.Result{Output: a[2] + "\n"}
	case "find":
		if id := c.live[a[1]]; id != "" {
			return gascity.Result{Output: id + "\n"}
		}
		return gascity.Result{}
	case "file":
		id := fmt.Sprintf("ra-%d", 100+c.filed)
		c.filed++
		c.live[a[1]] = id
		return gascity.Result{Output: "Slung " + id + " to rig-a/polecat\npreexisting-failure: sent " + id + " to be fixed\n" + id + "\n"}
	}
	return gascity.Result{Code: 2, Output: "usage"}
}

func (c *city) pass() *Pass {
	return &Pass{City: c.rt, GitHub: c.hub, Host: "github.com",
		Store: func(db string) (*ledger.Ledger, error) {
			c.opened = append(c.opened, db)
			return ledger.New(c.store), nil
		},
		Origin:        func(string) (string, error) { return "https://github.com/owner/repo-a.git", nil },
		DefaultBranch: func(string) (string, error) { return "main", nil }}
}

// files is every file call the writer took.
func (c *city) files() []gcfake.Call {
	var out []gcfake.Call
	for _, s := range c.rt.Scripts() {
		if s.Name == Script && s.Args[0] == "file" {
			out = append(out, s)
		}
	}
	return out
}

// verbs is the writer's verb of each call the pass made, in order.
func (c *city) verbs() []string {
	var out []string
	for _, s := range c.rt.Scripts() {
		out = append(out, s.Args[0])
	}
	return out
}

// tracker is a closed tracker of key, filed f hours and closed h hours after
// t0, with edges.
func tracker(id, key string, f, h int, edges ...gcbd.Edge) fake.Bead {
	return fake.Bead{ID: id, Status: "closed", CreatedAt: hour(f), ClosedAt: hour(h),
		Metadata: map[string]string{"failure_key": key}, Edges: edges}
}

// hour is the time h hours after t0, as a bead records one.
func hour(h int) string { return t0.Add(time.Duration(h) * time.Hour).Format(time.RFC3339) }

// The newest run that failed, ran out of time, could not start or succeeded
// decides each workflow, and a run that ended any other way, or has not
// finished, decides nothing. A workflow carries the run made next after its
// deciding run, and a failing one its newest success older than the failure.
func TestTheNewestDecidedRunDecides(t *testing.T) {
	got := Judge([]gh.WorkflowRun{
		run(tests, 10, 'j', 10, ""),
		run(tests, 9, 'i', 9, "cancelled"),
		run(lint, 8, 'h', 8, "success"),
		run(tests, 7, 'g', 7, "failure"),
		run(lint, 6, 'f', 6, "failure"),
		run(tests, 5, 'e', 5, "cancelled"),
		run(tests, 4, 'd', 4, "timed_out"),
		run(tests, 3, 'c', 3, "success"),
		run(tests, 2, 'b', 2, "success"),
		run(".github/workflows/docs.yml", 1, 'a', 1, "skipped"),
	})
	var rows []string
	for _, v := range got {
		row := v.Path + "=" + v.State
		if v.Newest != nil {
			row += fmt.Sprintf(" #%d", v.Newest.Number)
		}
		if v.Next != nil {
			row += fmt.Sprintf(" next #%d", v.Next.Number)
		}
		if v.Good != nil {
			row += fmt.Sprintf(" after #%d", v.Good.Number)
		}
		rows = append(rows, row)
	}
	want := []string{".github/workflows/docs.yml=none", lint + "=succeeded #8", tests + "=failing #7 next #9 after #3"}
	if !slices.Equal(rows, want) {
		t.Errorf("Judge = %q, want %q", rows, want)
	}
	for conclusion, state := range map[string]string{"failure": Failing, "timed_out": Failing, "startup_failure": Failing,
		"success": Succeeded, "cancelled": None, "skipped": None, "neutral": None, "stale": None, "action_required": None,
		"": None} {
		if v := Judge([]gh.WorkflowRun{run(tests, 1, 'a', 1, conclusion)}); v[0].State != state {
			t.Errorf("a run that ended %s is %s, want %s", conclusion, v[0].State, state)
		}
	}
}

// Only a run that a push to the branch in the repository itself started
// counts: not another branch's, not a pull request's that carries the branch's
// name, and not one of a commit from a fork.
func TestOnlyThePushRunsOfTheBranchCount(t *testing.T) {
	other, pr, fork, shouted := run(tests, 4, 'd', 4, "failure"), run(tests, 3, 'c', 3, "failure"),
		run(tests, 2, 'b', 2, "failure"), run(tests, 1, 'a', 1, "success")
	other.Branch, pr.Event, fork.HeadRepo, shouted.HeadRepo = "release", "pull_request", "someone/repo-a", "Owner/Repo-A"
	got := branchRuns([]gh.WorkflowRun{other, pr, fork, shouted}, repo, "main")
	if len(got) != 1 || got[0].Number != 1 {
		t.Errorf("branchRuns = %+v, want run #1 alone", got)
	}
}

// A workflow failing on the branch gets one tracker, filed through the writer
// with the failed run's jobs, which are read only then. A second pass finds
// that tracker and files nothing, and reads GitHub once.
func TestAFailingCheckFilesOneTracker(t *testing.T) {
	c := newCity(run(tests, 7, 'b', 7, "failure"), run(lint, 6, 'z', 6, "success"), run(tests, 5, 'a', 5, "success"))
	c.hub.Repos[repo].Jobs[1007] = []gh.Job{
		{Name: "go", Conclusion: "failure", URL: "https://github.com/owner/repo-a/actions/runs/1007/job/1",
			Steps: []gh.Step{{Number: 1, Name: "Set up job", Conclusion: "success"}, {Number: 4, Name: "Run the tests", Conclusion: "failure"}}},
		{Name: "web", Conclusion: "success"},
	}
	out := c.pass().Run("rig-a", false)
	if out.Failure != "" || out.Repository != repo || out.Branch != "main" || out.Runs != 3 || len(out.Workflows) != 2 {
		t.Fatalf("the pass = %+v", out)
	}
	w := out.Workflows[1]
	if w.Path != tests || w.State != Failing || w.Key != tests || w.Did != Filed || w.Tracker != "ra-100" ||
		w.Said != "sent ra-100 to be fixed" || w.Run == nil || w.Run.Number != 7 {
		t.Errorf("the failing workflow = %+v", w)
	}
	if lintW := out.Workflows[0]; lintW.State != Succeeded || lintW.Did != "" || lintW.Key != "" {
		t.Errorf("the passing workflow = %+v", lintW)
	}
	if got := c.verbs(); !slices.Equal(got, []string{"key", "find", "file"}) {
		t.Errorf("the writer ran %q", got)
	}
	if got := c.hub.Reads(); !slices.Equal(got, []string{"BranchRuns", "RunJobs"}) {
		t.Errorf("the pass read GitHub %q", got)
	}
	if !slices.Equal(c.opened, []string{"/city/rigs/rig-a/.beads"}) {
		t.Errorf("the pass opened %q, want the rig's store", c.opened)
	}
	file := c.files()[0].Args
	if len(file) != 6 || file[1] != tests || file[2] != "--summary" || file[3] != "Tests (tests.yml) failed on main" ||
		file[4] != "--message" || !strings.Contains(file[5], "run #7") {
		t.Errorf("the file call = %q", file)
	}

	again := c.pass().Run("rig-a", false)
	if w := again.Workflows[1]; again.Failure != "" || w.Did != Tracked || w.Tracker != "ra-100" {
		t.Errorf("the second pass = %+v", again)
	}
	if len(c.files()) != 1 {
		t.Errorf("the second pass filed again: %+v", c.files())
	}
	if got := c.hub.Reads(); !slices.Equal(got, []string{"BranchRuns", "RunJobs", "BranchRuns"}) {
		t.Errorf("the passes read GitHub %q", got)
	}
}

// A failed run that started before the key's tracking ended files nothing when
// the tracking covered it, and its jobs are not read: the key's most recently
// closed tracker was filed after the run was made, or a newer run of the
// workflow, made before the tracking ended, has not decided. The newest run
// made after the filing and before the end files when it failed, as the run of
// the commit that landed the fix, which starts before the tracker closes, does
// when the fix did not end the failure. So does a run, or an attempt of one,
// that started after the end.
func TestTheTrackingHoldsBackTheRunsItCovered(t *testing.T) {
	red := run(tests, 7, 'b', 7, "failure")
	rerun := run(tests, 5, 'a', 5, "failure")
	rerun.Attempt, rerun.Started = 2, t0.Add(10*time.Hour)
	for name, tc := range map[string]struct {
		runs  []gh.WorkflowRun
		filed int
		did   string
	}{
		"the run the tracker was filed from": {runs: []gh.WorkflowRun{red}, filed: 8, did: HeldBack},
		"a run before the fix, with the fix's run in progress": {
			runs: []gh.WorkflowRun{run(tests, 8, 'c', 8, ""), red}, filed: 6, did: HeldBack},
		"a run before the fix, with the fix's run cancelled": {
			runs: []gh.WorkflowRun{run(tests, 8, 'c', 8, "cancelled"), red}, filed: 6, did: HeldBack},
		"the fix's own run, which started before the close and failed": {
			runs: []gh.WorkflowRun{red, run(tests, 5, 'a', 5, "failure")}, filed: 6, did: Filed},
		"the fix's own run, with a run made after the close in progress": {
			runs: []gh.WorkflowRun{run(tests, 10, 'd', 10, ""), red}, filed: 6, did: Filed},
		"a run that started after the close":      {runs: []gh.WorkflowRun{run(tests, 10, 'd', 10, "failure")}, filed: 1, did: Filed},
		"an attempt that started after the close": {runs: []gh.WorkflowRun{rerun}, filed: 6, did: Filed},
	} {
		c := newCity(tc.runs...)
		c.store.Put(tracker("ra-1", tests, tc.filed, 9))
		c.store.Put(tracker("ra-2", tests, 1, 4))
		c.store.Put(tracker("ra-3", lint, 8, 10))
		out := c.pass().Run("rig-a", false)
		w := out.Workflows[0]
		if out.Failure != "" || w.Did != tc.did {
			t.Errorf("%s: the pass = %+v", name, out)
			continue
		}
		if tc.did == Filed {
			if len(c.files()) != 1 {
				t.Errorf("%s: the writer took %d file calls, want 1", name, len(c.files()))
			}
			continue
		}
		if w.SettledBy != "ra-1" || w.Settled == nil || !w.Settled.Equal(t0.Add(9*time.Hour)) {
			t.Errorf("%s: held back by %q at %v, want ra-1's close", name, w.SettledBy, w.Settled)
		}
		if len(c.files()) != 0 || slices.Contains(c.hub.Reads(), "RunJobs") {
			t.Errorf("%s: a run held back filed %+v and read %q", name, c.files(), c.hub.Reads())
		}
	}
}

// A tracker closed as the duplicate of another bead, or superseded by one,
// ended when that bead closed: the failure moved there, and that bead's fix
// is what ends it, so a run from before that fix, with the fix's run in
// progress, is held back. The chain stops at a bead that is not closed, at one
// the store does not hold, and at one it reached before.
func TestTheTrackingEndsWhereItsChainCloses(t *testing.T) {
	dup := func(to string) gcbd.Edge { return gcbd.Edge{Type: "duplicates", ID: to} }
	sup := func(to string) gcbd.Edge { return gcbd.Edge{Type: "supersedes", ID: to} }
	for name, tc := range map[string]struct {
		beads []fake.Bead
		did   string
		by    string
	}{
		"a duplicate of a bead fixed later": {
			beads: []fake.Bead{tracker("ra-1", tests, 1, 3, dup("ra-9")), tracker("ra-9", "TestFoo", 1, 9)},
			did:   HeldBack, by: "ra-9"},
		"two hops": {
			beads: []fake.Bead{tracker("ra-1", tests, 1, 3, dup("ra-9")), tracker("ra-9", "TestFoo", 1, 4, sup("ra-8")),
				{ID: "ra-8", Status: "closed", ClosedAt: hour(9)}},
			did: HeldBack, by: "ra-8"},
		"a successor that is still open": {
			beads: []fake.Bead{tracker("ra-1", tests, 1, 3, dup("ra-9")), {ID: "ra-9", Status: "open"}},
			did:   Filed},
		"a successor in another store": {
			beads: []fake.Bead{tracker("ra-1", tests, 1, 3, dup("rb-9"))},
			did:   Filed},
		"a loop": {
			beads: []fake.Bead{tracker("ra-1", tests, 1, 3, dup("ra-9")), tracker("ra-9", "TestFoo", 1, 4, dup("ra-1"))},
			did:   Filed},
		"a chain from an older tracker": {
			beads: []fake.Bead{tracker("ra-1", tests, 1, 4), tracker("ra-2", tests, 1, 2, dup("ra-9")), tracker("ra-9", "TestFoo", 1, 9)},
			did:   Filed},
	} {
		c := newCity(run(tests, 8, 'c', 8, ""), run(tests, 7, 'b', 7, "failure"))
		for _, b := range tc.beads {
			c.store.Put(b)
		}
		out := c.pass().Run("rig-a", false)
		if w := out.Workflows[0]; out.Failure != "" || w.Did != tc.did || w.SettledBy != tc.by {
			t.Errorf("%s: the pass = %+v", name, out)
		}
	}
}

// A workflow whose newest decided run passed files nothing, whatever its
// earlier runs did, and a pass that finds nothing failing reads GitHub once and
// runs no writer and no store read.
func TestNothingFailingCostsOneRead(t *testing.T) {
	c := newCity(run(tests, 9, 'c', 9, "cancelled"), run(tests, 8, 'b', 8, "success"), run(tests, 7, 'a', 7, "failure"),
		run(lint, 6, 'z', 6, "skipped"))
	out := c.pass().Run("rig-a", false)
	if out.Failure != "" || len(out.Workflows) != 2 || out.Workflows[1].State != Succeeded || out.Workflows[0].State != None {
		t.Fatalf("the pass = %+v", out)
	}
	if got := c.hub.Reads(); !slices.Equal(got, []string{"BranchRuns"}) {
		t.Errorf("the pass read GitHub %q, want one read of the runs", got)
	}
	if len(c.rt.Scripts()) != 0 || len(c.opened) != 0 {
		t.Errorf("a pass with nothing failing ran %+v and opened %q", c.rt.Scripts(), c.opened)
	}
	if out.Since == nil || !out.Since.Equal(t0.Add(6*time.Hour)) {
		t.Errorf("the read's oldest run is %v", out.Since)
	}
}

// A dry run reads all a pass reads, the writer's key and lookup among them,
// and prints the file call it would make without making it.
func TestADryRunWritesNothing(t *testing.T) {
	c := newCity(run(tests, 7, 'b', 7, "failure"))
	out := c.pass().Run("rig-a", true)
	w := out.Workflows[0]
	if out.Failure != "" || w.Did != WouldFile || len(w.Would) != 6 || w.Would[0] != "file" || w.Would[1] != tests || w.Tracker != "" {
		t.Fatalf("the dry run = %+v", out)
	}
	if got := c.verbs(); !slices.Equal(got, []string{"key", "find"}) {
		t.Errorf("the dry run ran the writer for %q", got)
	}
	if got := c.hub.Reads(); !slices.Equal(got, []string{"BranchRuns", "RunJobs"}) {
		t.Errorf("the dry run read GitHub %q", got)
	}
}

// A read or a write that fails is the pass's failure, and files nothing for
// the workflow it fails, while the pass goes on to the others. A read of the
// rig's own that fails ends the pass before it reads GitHub or runs a writer.
func TestAFailureFilesNothing(t *testing.T) {
	for name, tc := range map[string]struct {
		set   func(c *city)
		want  string
		files int
	}{
		"the runs": {set: func(c *city) { c.hub.Fail["BranchRuns"] = errors.New("gh: HTTP 502") },
			want: "GitHub did not answer for the runs on main of owner/repo-a: gh: HTTP 502"},
		"the key": {set: func(c *city) { c.failing("key", "--target takes a repo-relative path") },
			want: tests + ": preexisting-failure.sh derived no key for " + tests, files: 1},
		"the lookup": {set: func(c *city) { c.failing("find", "the lookup could not read the store") },
			want: tests + ": preexisting-failure.sh could not look up the tracker of " + tests, files: 1},
		"the store": {set: func(c *city) { c.store.FindErr = errors.New("dolt: busy") },
			want: tests + ": the closed trackers of " + tests + " did not read: dolt: busy"},
		"the jobs": {set: func(c *city) { c.hub.Fail["RunJobs"] = errors.New("gh: HTTP 404") },
			want: tests + ": GitHub did not answer for the jobs of run 1007 of owner/repo-a: gh: HTTP 404"},
		"the filing": {set: func(c *city) { c.failing("file", "bd create filed nothing") },
			want: tests + ": preexisting-failure.sh did not file the tracker of " + tests, files: 2},
	} {
		c := newCity(run(tests, 7, 'b', 7, "failure"), run(lint, 6, 'a', 6, "failure"))
		tc.set(c)
		out := c.pass().Run("rig-a", false)
		if !strings.Contains(out.Failure, tc.want) {
			t.Errorf("%s: failure %q, want it to say %q", name, out.Failure, tc.want)
		}
		if got := len(c.files()); got != tc.files {
			t.Errorf("%s: the writer took %d file calls, want %d", name, got, tc.files)
		}
		if tc.files > 0 && (out.Workflows[0].Path != lint || out.Workflows[0].Did != Filed) {
			t.Errorf("%s: the other workflow = %+v", name, out.Workflows[0])
		}
	}
	for name, p := range map[string]func(*Pass){
		"the rigs": func(p *Pass) { p.City.(*gcfake.Runtime).RigsErr = errors.New("gc: no city") },
		"the origin": func(p *Pass) {
			p.Origin = func(string) (string, error) { return "https://gitlab.com/owner/repo-a.git", nil }
		},
		"the branch": func(p *Pass) {
			p.DefaultBranch = func(string) (string, error) { return "", errors.New("origin/HEAD names no branch") }
		},
	} {
		c := newCity(run(tests, 7, 'b', 7, "failure"))
		pass := c.pass()
		p(pass)
		if out := pass.Run("rig-a", false); out.Failure == "" || len(c.hub.Reads()) != 0 || len(c.rt.Scripts()) != 0 {
			t.Errorf("%s: the pass = %+v, read %q", name, out, c.hub.Reads())
		}
	}
	if out := newCity().pass().Run("rig-b", false); out.Failure != "the city names no rig rig-b" {
		t.Errorf("an unknown rig: %+v", out)
	}
}

// failing makes the writer fail verb for tests.yml, saying why as it says its
// own lines, and answer every other call as it does.
func (c *city) failing(verb, why string) {
	c.rt.OnScript = func(call gcfake.Call) gascity.Result {
		if call.Args[0] == verb && slices.Contains(call.Args, tests) {
			return gascity.Result{Code: 1, Output: said + why + "\n"}
		}
		return c.writer(call)
	}
}

// The tracker names the workflow, the failed run and its link, its commit, its
// failed jobs and steps, the command that prints the failed log and the last
// success before it, and ends with how its worker finds a tracker the failure
// already has.
func TestTheTrackerSaysWhatFailed(t *testing.T) {
	failedRun, good := run(tests, 7, 'b', 7, "failure"), run(tests, 5, 'a', 5, "success")
	failedRun.Attempt = 2
	jobs := []gh.Job{
		{Name: "go", Conclusion: "failure", URL: "https://github.com/owner/repo-a/actions/runs/1007/job/1", Steps: []gh.Step{
			{Number: 1, Name: "Set up job", Conclusion: "success"}, {Number: 4, Name: "Run the tests", Conclusion: "failure"},
			{Number: 5, Name: "Post", Conclusion: "skipped"}}},
		{Name: "web", Conclusion: "timed_out"},
		{Name: "lint", Conclusion: "success"},
	}
	got := message(repo, "main", Verdict{Path: tests, State: Failing, Newest: &failedRun, Good: &good}, jobs)
	for _, want := range []string{
		"The workflow Tests (tests.yml) failed on main of owner/repo-a in run #7 (attempt 2) at 2026-11-20 13:00 UTC: https://github.com/owner/repo-a/actions/runs/1007\n",
		"A push of commit bbbbbbb started it: change 7\n",
		"Its last success before it was run #5 at 2026-11-20 11:00 UTC, and the changes between their commits are https://github.com/owner/repo-a/compare/" +
			strings.Repeat("a", 40) + "..." + strings.Repeat("b", 40) + "\n",
		"- the job go: failure, at the step Run the tests (failure), https://github.com/owner/repo-a/actions/runs/1007/job/1\n",
		"- the job web: timed_out\n",
		"    gh run view 1007 --repo owner/repo-a --log-failed\n",
		"    KEY=$(\"$(gc <binding> scripts-dir)/preexisting-failure.sh\" key --test \"<the failing test function>\")\n",
		"    \"$(gc <binding> scripts-dir)/preexisting-failure.sh\" find \"$KEY\"\n",
		"close this bead as its duplicate",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("the tracker's text does not say %q:\n%s", want, got)
		}
	}
	if strings.Contains(got, "- the job lint") {
		t.Errorf("the tracker's text names a job that passed:\n%s", got)
	}
	same := run(tests, 6, 'b', 6, "success")
	if got := message(repo, "main", Verdict{Path: tests, State: Failing, Newest: &failedRun, Good: &same}, nil); !strings.Contains(got, "on the same commit") ||
		!strings.Contains(got, "- GitHub lists no failed job in it\n") {
		t.Errorf("a failure on its last success's commit, with no failed job:\n%s", got)
	}
	if got := message(repo, "main", Verdict{Path: tests, State: Failing, Newest: &failedRun}, nil); !strings.Contains(got, "None of its runs among the newest 100 push runs on main succeeded before it.") {
		t.Errorf("a failure with no success before it:\n%s", got)
	}
	many := make([]gh.Job, Listed+1)
	for i := range many {
		many[i] = gh.Job{Name: fmt.Sprintf("j%d", i), Conclusion: "failure"}
	}
	if got := message(repo, "main", Verdict{Path: tests, State: Failing, Newest: &failedRun}, many); strings.Count(got, "- the job ") != Listed ||
		!strings.Contains(got, "- and more failed jobs\n") {
		t.Errorf("more failed jobs than the tracker lists:\n%s", got)
	}
}

// The writer's answer is the last line it prints, unless that line is one it
// says of its own, so a lookup that only warns answers no tracker.
func TestTheWritersAnswerIsItsLastLine(t *testing.T) {
	for output, want := range map[string]string{
		"ra-1\n": "ra-1",
		"preexisting-failure: no live tracker holds 'k'; its closed tracker ra-1 moved the failure to ra-2, which is live, so ra-2 is its filing\nra-2\n": "ra-2",
		"preexisting-failure: the chain of disposition edges from ra-1 loops back to ra-2, so it names no bead that carries 'k'\n":                        "",
		"": "",
		"Slung ra-3 to rig-a/polecat\npreexisting-failure: sent ra-3 to be fixed\nra-3\n": "ra-3",
	} {
		if got := answerOf(gascity.Result{Output: output}); got != want {
			t.Errorf("answerOf(%q) = %q, want %q", output, got, want)
		}
	}
}
