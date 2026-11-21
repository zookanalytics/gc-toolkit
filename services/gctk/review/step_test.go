package review_test

import (
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	ghfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
)

// A run's steps as Gas City writes them: the first iteration's steps carry the
// loop's bare name and later ones the formula's name before it, and a lane
// bonded inside an iteration carries its own formula's name before that.
func stepRef(n int, name string) string {
	loop := "review-loop.iteration.1"
	if n > 1 {
		loop = "mol-pr-review.review-loop.iteration." + string(rune('0'+n))
	}
	if name == "lane" {
		return "mol-pr-review-lane." + loop + ".triage.item.1.lane"
	}
	return loop + "." + name
}

// step puts an open step of iteration n under the run and returns its id.
func (w *world) step(n int, name string) string {
	w.steps++
	id := "tk-open" + string(rune('a'+w.steps))
	w.store.Put(bead{ID: id, Status: "in_progress", IssueType: "task", Metadata: map[string]string{
		"gc.root_bead_id": root, "gc.step_ref": stepRef(n, name), "gc.attempt": string(rune('0' + n)),
	}})
	return id
}

// headRepo is a git repository whose main sits at base, with h1 and h2 on the PR's
// branch after it, and origin/main naming base.
type headRepo struct{ dir, base, h1, h2, side string }

func newHeadRepo(t *testing.T) headRepo {
	t.Helper()
	dir := t.TempDir()
	g := func(args ...string) string {
		t.Helper()
		cmd := exec.Command("git", append([]string{"-C", dir, "-c", "user.name=t", "-c", "user.email=t@example.com",
			"-c", "commit.gpgsign=false"}, args...)...)
		cmd.Env = append(os.Environ(), "GIT_CONFIG_GLOBAL=/dev/null", "GIT_CONFIG_NOSYSTEM=1")
		out, err := cmd.CombinedOutput()
		if err != nil {
			t.Fatalf("git %v: %v: %s", args, err, out)
		}
		return strings.TrimSpace(string(out))
	}
	write := func(path, text string) {
		t.Helper()
		if err := os.MkdirAll(filepath.Dir(filepath.Join(dir, path)), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, path), []byte(text), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	g("init", "-q", "-b", "main")
	write("a.go", "package a\n")
	g("add", "-A")
	g("commit", "-q", "-m", "base")
	r := headRepo{dir: dir, base: g("rev-parse", "HEAD")}
	g("update-ref", "refs/remotes/origin/main", r.base)
	g("checkout", "-q", "-b", "side")
	write("side.go", "package a\n")
	g("add", "-A")
	g("commit", "-q", "-m", "side")
	r.side = g("rev-parse", "HEAD")
	g("checkout", "-q", "-b", "pr", r.base)
	write("a.go", "package a\n\nfunc F() {}\n")
	g("commit", "-q", "-am", "h1")
	r.h1 = g("rev-parse", "HEAD")
	write("docs/review-arch.md", "Read the boundaries.\n")
	g("add", "-A")
	g("commit", "-q", "-m", "h2")
	r.h2 = g("rev-parse", "HEAD")
	return r
}

// Iteration 1 judges the run's first head, and a later one the head the
// round before it pushed, or the head it judged again when that round pushed
// nothing.
func TestTheHeadEachIterationJudges(t *testing.T) {
	w := newWorld(t)
	w.output(triage(1, h1, "correctness"))
	w.output(repair(1, h1, h2))
	w.output(triage(2, h2))
	w.output(repair(2, h2, ""))
	run, err := review.ReadRun(w.ledger(), root)
	if err != nil {
		t.Fatal(err)
	}
	for n, want := range map[int]string{1: h1, 2: h2, 3: h2} {
		if got := run.HeadOf(n); got != want {
			t.Errorf("iteration %d judges %s; want %s", n, got, want)
		}
	}
}

// Triage reads nothing at a head a run already passed at for the target, else
// the change since the nearest earlier head a run passed at for the target,
// else the run's own repair since its first head, else the whole PR. A passed
// result for another target, one that failed, and one off the branch are none
// of them.
func TestTheChangeTriageReads(t *testing.T) {
	r := newHeadRepo(t)
	run := &review.Run{Root: root, PRBead: prBead, Head: r.h1, Target: target}
	repos := []string{r.dir}
	cases := []struct {
		name    string
		results []review.Result
		head    string
		want    review.Change
	}{
		{"the first head of a PR with no result", nil, r.h1, review.Change{Head: r.h1, Why: review.ChangeWhole}},
		{"a head the run's repair pushed", nil, r.h2, review.Change{From: r.h1, Head: r.h2, Why: review.ChangeRepair}},
		{"a passed head behind it", []review.Result{{Head: r.h1, Target: target, Passed: true}}, r.h2,
			review.Change{From: r.h1, Head: r.h2, Why: review.ChangeSincePassed}},
		{"the nearer of two passed heads", []review.Result{{Head: r.base, Target: target, Passed: true},
			{Head: r.h1, Target: target, Passed: true}}, r.h2, review.Change{From: r.h1, Head: r.h2, Why: review.ChangeSincePassed}},
		{"a passed head for another target", []review.Result{{Head: r.h1, Target: "release", Passed: true}}, r.h2,
			review.Change{From: r.h1, Head: r.h2, Why: review.ChangeRepair}},
		{"a head that did not pass", []review.Result{{Head: r.h1, Target: target}}, r.h2,
			review.Change{From: r.h1, Head: r.h2, Why: review.ChangeRepair}},
		{"a passed head off the branch", []review.Result{{Head: r.side, Target: target, Passed: true}}, r.h1,
			review.Change{Head: r.h1, Why: review.ChangeWhole}},
		{"a passed head the clone does not hold, which no origin serves", []review.Result{
			{Head: strings.Repeat("ab", 20), Target: target, Passed: true}}, r.h2,
			review.Change{From: r.h1, Head: r.h2, Why: review.ChangeRepair}},
		{"the first head, which already passed", []review.Result{{Head: r.h1, Target: target, Passed: true}}, r.h1,
			review.Change{From: r.h1, Head: r.h1, Why: review.ChangeNone}},
		{"a head that passed, with a pass behind it", []review.Result{{Head: r.h1, Target: target, Passed: true},
			{Head: r.h2, Target: target, Passed: true}}, r.h2, review.Change{From: r.h2, Head: r.h2, Why: review.ChangeNone}},
		{"a head that passed for another target", []review.Result{{Head: r.h1, Target: "release", Passed: true}}, r.h1,
			review.Change{Head: r.h1, Why: review.ChangeWhole}},
		{"a head whose result did not pass", []review.Result{{Head: r.h1, Target: target}}, r.h1,
			review.Change{Head: r.h1, Why: review.ChangeWhole}},
	}
	for _, c := range cases {
		got, err := review.ChangeAt(run, c.results, repos, c.head)
		if err != nil {
			t.Fatalf("%s: %v", c.name, err)
		}
		if got != c.want {
			t.Errorf("%s: the change is %+v; want %+v", c.name, got, c.want)
		}
		if got.None() != (c.want.Why == review.ChangeNone) {
			t.Errorf("%s: the change reads as none: %t", c.name, got.None())
		}
	}
	// A head that passed needs no clone: nothing behind it is read.
	if got, err := review.ChangeAt(run, []review.Result{{Head: r.h2, Target: target, Passed: true}}, nil, r.h2); err != nil || !got.None() {
		t.Errorf("a passed head with no repository = %+v, %v; want none", got, err)
	}
	if _, err := review.ChangeAt(run, []review.Result{{Head: r.h1, Target: target, Passed: true}}, nil, r.h2); err == nil {
		t.Error("with no repository to read the heads in, the change reads; want an error")
	}
}

// A step names the output it writes by the last part of its gc.step_ref at any
// iteration, and its iteration by gc.attempt.
func TestAStepNamesItsOutputAndIteration(t *testing.T) {
	w := newWorld(t)
	for _, c := range []struct {
		n          int
		name, want string
	}{{1, "triage", review.OutputTriage}, {2, "rule-and-repair", review.OutputRepair}, {2, "lane", review.OutputLane}} {
		st, err := review.ReadStep(w.ledger(), w.step(c.n, c.name))
		if err != nil {
			t.Fatal(err)
		}
		if st.Output != c.want || st.Iteration != c.n {
			t.Errorf("%s at iteration %d reads as %q at iteration %d", c.name, c.n, st.Output, st.Iteration)
		}
	}
	if _, err := review.ReadStep(w.ledger(), root); err == nil {
		t.Error("the run's root reads as one of its steps")
	}
}

// openPR is GitHub holding the PR the bead names once its pr_url is set, open
// from the bead's branch into its target at the run's head, and that PR, for a
// test to change.
func openPR() (*ghfake.GitHub, *ghfake.PR) {
	g := ghfake.New("")
	p := &ghfake.PR{Facts: gh.PullRequest{Repository: "o/r", Number: 7, State: "OPEN", HeadRefOid: h1,
		HeadRefName: branch, BaseRefName: target}}
	g.Put(p)
	return g, p
}

// mustStop is why the run must stop, as a step of its first iteration asks it
// of the GitHub github returns for a host.
func (w *world) mustStop(github func(host string) review.GitHub) (string, error) {
	w.t.Helper()
	st, err := review.ReadStep(w.ledger(), w.step(1, "triage"))
	if err != nil {
		w.t.Fatal(err)
	}
	return st.MustStop(github)
}

// on is a GitHub factory that answers every host from g.
func on(g *ghfake.GitHub) func(string) review.GitHub {
	return func(string) review.GitHub { return g }
}

// A run's vars name the bead's record when its head is the head the record
// validated, its target the record's and its branch var the bead's branch, and
// a run whose vars do not stops before it reads GitHub, as does a run whose
// bead is on no record or names no PR.
func TestARunsVarsNameTheRecord(t *testing.T) {
	mismatch := func(w *world) string {
		t.Helper()
		g, _ := openPR()
		why, err := w.mustStop(on(g))
		if err != nil {
			t.Fatal(err)
		}
		if reads := g.Reads(); why != "" && len(reads) > 0 {
			t.Errorf("a run that stops for %q read GitHub first: %v", why, reads)
		}
		return why
	}
	setPR := func(w *world, k, v string) {
		pr, _ := w.store.Row(prBead)
		if v == "" {
			delete(pr.Metadata, k)
		} else {
			pr.Metadata[k] = v
		}
		w.store.Put(pr)
	}
	setRoot := func(w *world, k, v string) {
		r, _ := w.store.Row(root)
		r.Metadata[k] = v
		w.store.Put(r)
	}
	w := newWorld(t)
	setPR(w, "pr_url", "https://github.com/o/r/pull/7")
	if got := mismatch(w); got != "" {
		t.Errorf("a run poured from its record does not name it: %s", got)
	}
	for _, c := range []struct{ name, why string }{{"head", "validated head"}, {"target", "target"}, {"branch", "branch var"}} {
		w := newWorld(t)
		setPR(w, "pr_url", "https://github.com/o/r/pull/7")
		switch c.name {
		case "head":
			setPR(w, "pr_head_sha", h2)
		case "target":
			setRoot(w, "gc.var.target", "release")
		case "branch":
			setRoot(w, "gc.var.branch", "polecat/other")
		}
		if got := mismatch(w); !strings.Contains(got, c.why) {
			t.Errorf("a run whose %s differs from the record's reads %q; want it to name the %s", c.name, got, c.why)
		}
	}
	w = newWorld(t)
	setPR(w, "pr_url", "https://github.com/o/r/pull/7")
	setPR(w, "merge_result", "")
	if got := mismatch(w); !strings.Contains(got, "not on the pending record") {
		t.Errorf("a bead on no record reads %q", got)
	}
	setPR(w, "pr_url", "")
	if got := mismatch(w); !strings.Contains(got, "names no PR") {
		t.Errorf("a bead with no PR reads %q", got)
	}
}

// In a later round the run stands at the head that round judges, the
// repair's push, and stops once the PR moved past it. The bead's record keeps
// the head the refinery validated while the run holds the bead, and reads
// head-changed once the landing order saw the push, so the run's vars still
// name it.
func TestALaterRoundStandsAtTheHeadItJudges(t *testing.T) {
	w := newWorld(t)
	setPR := func(k, v string) {
		pr, _ := w.store.Row(prBead)
		pr.Metadata[k] = v
		w.store.Put(pr)
	}
	setPR("pr_url", "https://github.com/o/r/pull/7")
	setPR("merge_result", "pull_request_head_changed")
	w.output(triage(1, h1, "correctness"))
	w.output(lane(1, "correctness", h1, review.VerdictRequestChanges, "F1"))
	w.output(repair(1, h1, h2, review.Ruling{Check: "correctness", Finding: "F1", Ruling: review.RulingMustFix, Commit: fix}))
	st, err := review.ReadStep(w.ledger(), w.step(2, "triage"))
	if err != nil {
		t.Fatal(err)
	}
	g, p := openPR()
	p.Facts.HeadRefOid = h2
	if why, err := st.MustStop(on(g)); why != "" || err != nil {
		t.Errorf("iteration 2 at the repair's push stops for %q, %v", why, err)
	}
	p.Facts.HeadRefOid = h1
	want := "the PR's head is " + h1 + ", no longer the head iteration 2 judges, " + h2
	if why, err := st.MustStop(on(g)); why != want || err != nil {
		t.Errorf("iteration 2 with the PR back at the first head stops for %q, %v; want %q", why, err, want)
	}
}

// A run whose vars name the record goes on while GitHub's PR, read on the host
// its URL names, is open from the bead's branch into the run's target at the
// run's head. It stops with no result when the PR is closed or merged, its head
// moved, it is from another branch or it merges into another target, and when
// the bead names no PR's URL. A GitHub that does not answer is a read error,
// not a reason to stop.
func TestARunStopsUnlessThePRIsOpenAtItsHead(t *testing.T) {
	withURL := func(url string) *world {
		w := newWorld(t)
		pr, _ := w.store.Row(prBead)
		pr.Metadata["pr_url"] = url
		w.store.Put(pr)
		return w
	}
	const url = "https://github.com/o/r/pull/7"
	g, _ := openPR()
	var hosts []string
	why, err := withURL(url).mustStop(func(host string) review.GitHub {
		hosts = append(hosts, host)
		return g
	})
	if why != "" || err != nil {
		t.Errorf("a run at its open PR's head stops for %q, %v", why, err)
	}
	if !slices.Equal(hosts, []string{"github.com"}) {
		t.Errorf("the run asked GitHub on %v; want the URL's host, github.com", hosts)
	}
	for _, c := range []struct {
		name   string
		change func(*ghfake.PR)
		why    string
	}{
		{"closed", func(p *ghfake.PR) { p.Facts.State = "CLOSED" }, "the PR is closed"},
		{"merged", func(p *ghfake.PR) { p.Facts.State = "MERGED" }, "the PR is merged"},
		{"whose head moved", func(p *ghfake.PR) { p.Facts.HeadRefOid = h2 },
			"the PR's head is " + h2 + ", no longer the run's head " + h1},
		{"from another branch", func(p *ghfake.PR) { p.Facts.HeadRefName = "polecat/other" },
			"the PR is from polecat/other, not the branch " + branch},
		{"into another target", func(p *ghfake.PR) { p.Facts.BaseRefName = "release" },
			"the PR merges into release, not the run's target " + target},
	} {
		g, p := openPR()
		c.change(p)
		if why, err := withURL(url).mustStop(on(g)); why != c.why || err != nil {
			t.Errorf("a PR %s: the run stops for %q, %v; want %q", c.name, why, err, c.why)
		}
	}
	g, _ = openPR()
	why, err = withURL("https://github.com/o/r/issues/7").mustStop(on(g))
	if want := `"https://github.com/o/r/issues/7" is not a PR's URL`; why != want || err != nil {
		t.Errorf("a bead whose URL is an issue's: the run stops for %q, %v; want %q", why, err, want)
	}
	if reads := g.Reads(); len(reads) > 0 {
		t.Errorf("a bead with no PR's URL read GitHub: %v", reads)
	}
	limited := errors.New("rate limited")
	g, _ = openPR()
	g.Fail["PullRequest"] = limited
	why, err = withURL(url).mustStop(on(g))
	if why != "" || !errors.Is(err, limited) {
		t.Errorf("a GitHub that does not answer: the run stops for %q, %v; want the read's error", why, err)
	}
}

// jsonOf is v as one JSON object.
func jsonOf(t *testing.T, v any) []byte {
	t.Helper()
	raw, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return raw
}
