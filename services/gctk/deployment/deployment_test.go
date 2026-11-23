package deployment

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

// t0 is the time the first deployment of a test was made.
var t0 = time.Date(2026, 11, 20, 6, 0, 0, 0, time.UTC)

// dep is a deployment of the commit whose oid is c repeated, made h hours
// after t0, whose latest status is state, from pull request pr when it is not
// zero.
func dep(c byte, h int, state string, pr int) gh.Deployment {
	oid := strings.Repeat(string(c), 40)
	d := gh.Deployment{Created: t0.Add(time.Duration(h) * time.Hour), Commit: oid, State: state, Failing: []gh.CommitStatus{}}
	if pr > 0 {
		d.PR, d.PRURL, d.Headline = pr, fmt.Sprintf("https://github.com/owner/repo-a/pull/%d", pr), fmt.Sprintf("change %d", pr)
	}
	if state == "FAILURE" || state == "SUCCESS" {
		d.LogURL = "https://repo-a-" + string(c) + ".host.example"
		d.Description = map[string]string{"FAILURE": "Deployment has failed", "SUCCESS": "Deployment has completed"}[state]
	}
	return d
}

// failures is n failed deployments, newest first, the newest made h hours
// after t0 and each an hour before the one after it.
func failures(n, h int) []gh.Deployment {
	var out []gh.Deployment
	for i := range n {
		out = append(out, dep(byte('a'+i%20), h-i, "FAILURE", 100+n-i))
	}
	return out
}

// A newest success is the state, whatever fails before it.
func TestANewestSuccessSucceeds(t *testing.T) {
	v := Judge([]gh.Deployment{dep('b', 2, "SUCCESS", 2), dep('a', 1, "FAILURE", 1)}, Window)
	if v.State != Succeeded || v.Newest == nil || v.Newest.Commit[0] != 'b' || len(v.Failed) != 0 || v.Good != nil {
		t.Fatalf("Judge = %+v", v)
	}
}

// A run of failures is every failure from the newest back to the success
// before it. A deployment still going, one GitHub marks INACTIVE and one with
// no status yet neither end the run nor join it.
func TestARunOfFailuresEndsAtTheSuccessBeforeIt(t *testing.T) {
	v := Judge([]gh.Deployment{
		dep('x', 9, "IN_PROGRESS", 9),
		dep('d', 8, "FAILURE", 8),
		dep('y', 7, "INACTIVE", 7),
		dep('c', 6, "ERROR", 6),
		dep('z', 5, "", 5),
		dep('b', 4, "FAILURE", 4),
		dep('a', 3, "SUCCESS", 3),
		dep('w', 2, "FAILURE", 2),
	}, Window)
	var run []byte
	for _, f := range v.Failed {
		run = append(run, f.Commit[0])
	}
	if v.State != Failing || v.Newest.Commit[0] != 'd' || string(run) != "dcb" || v.Good == nil || v.Good.Commit[0] != 'a' || v.Through {
		t.Fatalf("Judge = state %s, newest %s, run %s, good %+v, through %v", v.State, v.Newest.Commit[:1], run, v.Good, v.Through)
	}
}

// A read with no finished deployment decides nothing.
func TestUnfinishedDeploymentsDecideNothing(t *testing.T) {
	var deps []gh.Deployment
	for i, s := range []string{"QUEUED", "PENDING", "IN_PROGRESS", "WAITING", "INACTIVE", ""} {
		deps = append(deps, dep(byte('a'+i), 9-i, s, 0))
	}
	if v := Judge(deps, len(deps)); v.State != None || v.Newest != nil || v.Through {
		t.Fatalf("Judge = %+v", v)
	}
	if v := Judge(nil, Window); v.State != None {
		t.Fatalf("Judge of no deployment = %+v", v)
	}
}

// A run that reaches the oldest deployment of a full window may be longer
// than the read shows, and one that reaches the oldest of a shorter read is
// every deployment there is.
func TestARunThatFillsTheWindowMayBeLonger(t *testing.T) {
	if v := Judge(failures(5, 10), 5); v.State != Failing || len(v.Failed) != 5 || !v.Through || v.Good != nil {
		t.Fatalf("a full window of failures read as %+v", v)
	}
	if v := Judge(failures(4, 10), 5); v.State != Failing || len(v.Failed) != 4 || v.Through || v.Good != nil {
		t.Fatalf("every deployment there is, each a failure, read as %+v", v)
	}
}

// The key is one per environment, in the characters a finding's key takes.
func TestTheKeyIsOnePerEnvironment(t *testing.T) {
	valid := regexp.MustCompile(`^[A-Za-z0-9._-]+$`)
	for env, want := range map[string]string{
		"Production":              "deployment.production",
		"Production – repo-a app": "deployment.production-repo-a-app",
		"staging":                 "deployment.staging",
		"  Preview/2 ":            "deployment.preview-2",
	} {
		if got := Key(env); got != want || !valid.MatchString(got) {
			t.Errorf("Key(%q) = %q, want %q", env, got, want)
		}
	}
}

// world is a city with one rig whose checkout's origin is on github.com, and
// that repository's deployments to Production.
type world struct {
	city   *gcfake.Runtime
	gh     *ghfake.GitHub
	origin string
	report *Report
}

func newWorld(deps ...gh.Deployment) *world {
	w := &world{
		city:   &gcfake.Runtime{RigList: []gascity.Rig{{Name: "rig-a", Path: "/city/rigs/rig-a", Prefix: "ra"}}},
		gh:     ghfake.New("bot"),
		origin: "git@github.com:owner/repo-a.git",
	}
	w.gh.Repos = map[string]*ghfake.Repo{"owner/repo-a": {Deployments: map[string][]gh.Deployment{"Production": deps}}}
	w.city.OnScript = func(c gcfake.Call) gascity.Result {
		return gascity.Result{Output: "patrol-finding: filed ra-1 for [deployment.production]\n{\"slung\":true}\n"}
	}
	w.report = &Report{City: w.city, GitHub: w.gh, Host: "github.com", Origin: func(dir string) (string, error) {
		if dir != "/city/rigs/rig-a" {
			return "", fmt.Errorf("no checkout at %s", dir)
		}
		return w.origin, nil
	}}
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

// A failing run is reported once, through the finding's writer, as a task in
// the rig's store under the environment's key, and the outcome names it.
func TestAFailingRunIsReportedAsOneFinding(t *testing.T) {
	w := newWorld(dep('c', 3, "FAILURE", 13), dep('b', 2, "FAILURE", 12), dep('a', 1, "SUCCESS", 11))
	out := w.report.Run("rig-a", "", false)
	if out.Failure != "" {
		t.Fatalf("the report failed: %s", out.Failure)
	}
	calls := w.city.Scripts()
	if len(calls) != 1 || calls[0].Name != "patrol-finding.sh" {
		t.Fatalf("the report ran %+v, want patrol-finding.sh once", calls)
	}
	args := calls[0].Args
	for flag, want := range map[string]string{"--key": "deployment.production", "--scope": "deployment-report", "--rig": "rig-a", "--type": "task", "--priority": "1"} {
		if got, _ := arg(args, flag); got != want {
			t.Errorf("%s = %q, want %q, in %q", flag, got, want, args)
		}
	}
	if _, ok := arg(args, "--cleared"); ok {
		t.Errorf("a failing run was reported as cleared: %q", args)
	}
	if got, _ := arg(args, "--title"); got != "The Production deployment of owner/repo-a fails at ccccccc (#13): change 13" {
		t.Errorf("the title is %q", got)
	}
	msg, _ := arg(args, "--message")
	first, _, _ := strings.Cut(msg, "\n")
	if first != "The Production deployment of ccccccc (#13) failed at 2026-11-20 09:00 UTC: https://repo-a-c.host.example" {
		t.Errorf("the message opens %q", first)
	}
	for _, want := range []string{
		"2 deployments in a row have failed, the first of bbbbbbb (#12) at 2026-11-20 08:00 UTC.",
		"The one before them, of aaaaaaa (#11) at 2026-11-20 07:00 UTC, succeeded, and the changes from it to the first failure are https://github.com/owner/repo-a/compare/" + strings.Repeat("a", 40) + "..." + strings.Repeat("b", 40),
		"- the deployment's status: FAILURE, Deployment has failed, https://repo-a-c.host.example\n",
		"- ccccccc (#13) at 2026-11-20 09:00 UTC, https://github.com/owner/repo-a/pull/13: change 13\n- bbbbbbb (#12) at",
		"GitHub carries no build log",
	} {
		if !strings.Contains(msg, want) {
			t.Errorf("the message does not say %q:\n%s", want, msg)
		}
	}
	if out.State != Failing || out.Failures != 2 || out.Repository != "owner/repo-a" || out.Environment != "Production" ||
		out.Newest == nil || out.Newest.PR != 13 || out.Newest.Link != "https://repo-a-c.host.example" ||
		out.Recorded != "filed ra-1 for [deployment.production]" {
		t.Errorf("the outcome is %+v", out)
	}
}

// A success clears the finding's situation, naming the success, and files
// nothing new.
func TestASuccessClearsTheFinding(t *testing.T) {
	w := newWorld(dep('z', 5, "IN_PROGRESS", 15), dep('b', 4, "SUCCESS", 14), dep('a', 3, "FAILURE", 13))
	out := w.report.Run("rig-a", "Production", false)
	calls := w.city.Scripts()
	if out.Failure != "" || len(calls) != 1 {
		t.Fatalf("the report ran %+v: %+v", calls, out)
	}
	args := calls[0].Args
	if _, ok := arg(args, "--cleared"); !ok {
		t.Fatalf("a success was not reported as cleared: %q", args)
	}
	if got, _ := arg(args, "--key"); got != "deployment.production" {
		t.Errorf("--key = %q", got)
	}
	if got, _ := arg(args, "--message"); got != "The Production deployment of bbbbbbb (#14) succeeded at 2026-11-20 10:00 UTC: https://repo-a-b.host.example" {
		t.Errorf("the clear's reason is %q", got)
	}
	for _, flag := range []string{"--title", "--type", "--priority"} {
		if _, ok := arg(args, flag); ok {
			t.Errorf("a clear passed %s: %q", flag, args)
		}
	}
	if out.State != Succeeded || out.Failures != 0 {
		t.Errorf("the outcome is %+v", out)
	}
}

// A read with no finished deployment records nothing, and a dry run reads
// GitHub and calls no writer.
func TestNothingFinishedAndADryRunWriteNothing(t *testing.T) {
	w := newWorld(dep('a', 1, "IN_PROGRESS", 1))
	if out := w.report.Run("rig-a", "", false); out.Failure != "" || out.State != None || !strings.Contains(out.Recorded, "nothing to record") {
		t.Errorf("an unfinished read's outcome is %+v", out)
	}
	w = newWorld(dep('b', 2, "FAILURE", 2), dep('a', 1, "SUCCESS", 1))
	out := w.report.Run("rig-a", "", true)
	if out.Failure != "" || out.State != Failing || len(out.Would) == 0 || out.Recorded != "" {
		t.Errorf("a dry run's outcome is %+v", out)
	}
	if got, _ := arg(out.Would, "--key"); got != "deployment.production" {
		t.Errorf("a dry run would pass %q", out.Would)
	}
	if calls := w.city.Scripts(); len(calls) != 0 {
		t.Errorf("a dry run called %+v", calls)
	}
	if reads := w.gh.Reads(); len(reads) != 1 || reads[0] != "Deployments" {
		t.Errorf("a dry run read %q of GitHub, want the deployments once", reads)
	}
}

// A report that cannot read what it decides on writes nothing and says why:
// the rig list, the rig, its origin, a host other than the client's, GitHub,
// and the writer itself.
func TestAReadThatFailsWritesNothing(t *testing.T) {
	for name, tc := range map[string]struct {
		set  func(*world)
		want string
	}{
		"the rig list":    {func(w *world) { w.city.RigsErr = errors.New("gc: no city") }, "the city's rigs did not read"},
		"an unknown rig":  {func(w *world) { w.city.RigList = nil }, "the city names no rig rig-a"},
		"the origin":      {func(w *world) { w.origin = "" }, "names no repository on github.com"},
		"another host":    {func(w *world) { w.origin = "git@git.example.com:owner/repo-a.git" }, "names no repository on github.com"},
		"GitHub":          {func(w *world) { w.gh.Fail["Deployments"] = errors.New("gh: HTTP 502") }, "GitHub did not answer for the Production deployments of owner/repo-a: gh: HTTP 502"},
		"an unknown repo": {func(w *world) { w.origin = "git@github.com:owner/repo-b.git" }, "GitHub did not answer"},
	} {
		w := newWorld(dep('b', 2, "FAILURE", 2))
		tc.set(w)
		out := w.report.Run("rig-a", "", false)
		if !strings.Contains(out.Failure, tc.want) {
			t.Errorf("%s: the failure is %q, want %q", name, out.Failure, tc.want)
		}
		if calls := w.city.Scripts(); len(calls) != 0 {
			t.Errorf("%s: a report that did not read called %+v", name, calls)
		}
	}
	w := newWorld(dep('b', 2, "FAILURE", 2))
	w.origin = ""
	w.report.Origin = func(string) (string, error) { return "", errors.New("not a git repository") }
	if out := w.report.Run("rig-a", "", false); !strings.Contains(out.Failure, "did not read: not a git repository") || len(w.gh.Reads()) != 0 {
		t.Errorf("an origin that did not read: %+v, reads %q", out, w.gh.Reads())
	}
	w = newWorld(dep('b', 2, "FAILURE", 2))
	w.city.OnScript = func(gcfake.Call) gascity.Result {
		return gascity.Result{Code: 1, Output: "patrol-finding: dedup lookup failed for [deployment.production]\n"}
	}
	if out := w.report.Run("rig-a", "", false); !strings.Contains(out.Failure, "patrol-finding.sh did not record the Production deployments of owner/repo-a: exit 1: patrol-finding: dedup lookup failed") {
		t.Errorf("a writer that failed: %+v", out)
	}
}

// The message is made from the run alone, so a report of a run that has not
// moved repeats it, whatever else the window holds, and a new failure changes
// its first line, which is the part the finding notes.
func TestTheMessageMovesOnlyWithTheRun(t *testing.T) {
	msg := func(deps []gh.Deployment) string {
		v := Judge(deps, Window)
		if v.State != Failing {
			t.Fatalf("the read is %s", v.State)
		}
		return message("owner/repo-a", "Production", v)
	}
	run := []gh.Deployment{dep('c', 3, "FAILURE", 13), dep('b', 2, "FAILURE", 12), dep('a', 1, "SUCCESS", 11)}
	base := msg(run)
	if got := msg(append([]gh.Deployment{dep('z', 4, "IN_PROGRESS", 14)}, run...)); got != base {
		t.Errorf("a deployment still going changed the message:\n%s\nfrom\n%s", got, base)
	}
	next := msg(append([]gh.Deployment{dep('d', 4, "FAILURE", 14)}, run...))
	first, _, _ := strings.Cut(next, "\n")
	if next == base || !strings.HasPrefix(first, "The Production deployment of ddddddd (#14) failed") {
		t.Errorf("a new failure opens the message %q", first)
	}
	if len([]rune(first)) > 200 {
		t.Errorf("the first line runs %d characters, past the 200 a note keeps: %q", len([]rune(first)), first)
	}

	// A run longer than the window: a new deployment that is still going
	// pushes the oldest failure out, and the message stays.
	full := failures(Window, 200)
	long := msg(full)
	if !strings.Contains(long, "None of the newest 100 Production deployments succeeded") || !strings.Contains(long, "- and older failures\n") {
		t.Errorf("a run past the window reads:\n%s", long)
	}
	slid := append([]gh.Deployment{dep('z', 201, "QUEUED", 0)}, full[:Window-1]...)
	if got := msg(slid); got != long {
		t.Errorf("the window's slide changed the message:\n%s\nfrom\n%s", got, long)
	}
	_, list, _ := strings.Cut(long, "The failed deployments, newest first:\n")
	list, _, _ = strings.Cut(list, "\n\n")
	if n := strings.Count(list, "\n") + 1; n != Listed+1 {
		t.Errorf("the message lists %d lines of failures, want the newest %d and one for the older ones:\n%s", n, Listed, list)
	}
}

// The newest failure's commit statuses that are failing are quoted with their
// links, and a run with no success before it says so.
func TestTheFailingStatusesAreQuoted(t *testing.T) {
	d := dep('b', 2, "FAILURE", 12)
	d.Failing = []gh.CommitStatus{{Context: "deploy", State: "FAILURE", Description: "Deployment has failed — run the host's inspect command", TargetURL: "https://host.example/inspect/b"}}
	msg := message("owner/repo-a", "Production", Judge([]gh.Deployment{d, dep('a', 1, "ERROR", 11)}, Window))
	for _, want := range []string{
		"- the commit status deploy: FAILURE, Deployment has failed — run the host's inspect command, https://host.example/inspect/b\n",
		"No Production deployment has succeeded. 2 have failed, the first of aaaaaaa (#11) at 2026-11-20 07:00 UTC.",
	} {
		if !strings.Contains(msg, want) {
			t.Errorf("the message does not say %q:\n%s", want, msg)
		}
	}
	lone := message("owner/repo-a", "Production", Judge([]gh.Deployment{dep('b', 2, "FAILURE", 12), dep('a', 1, "SUCCESS", 11)}, Window))
	if !strings.Contains(lone, "The deployment before it, of aaaaaaa (#11) at 2026-11-20 07:00 UTC, succeeded, and the changes between them are https://github.com/owner/repo-a/compare/") {
		t.Errorf("a lone failure reads:\n%s", lone)
	}
}
