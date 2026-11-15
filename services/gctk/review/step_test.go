package review_test

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

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

// Triage reads the change since the nearest earlier head a run passed at for
// the target, else the run's own repair since its first head, else the whole
// PR. A passed result for another target, one that failed, and one off the
// branch are none of them.
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
	}
	for _, c := range cases {
		got, err := review.ChangeAt(run, c.results, repos, c.head)
		if err != nil {
			t.Fatalf("%s: %v", c.name, err)
		}
		if got != c.want {
			t.Errorf("%s: the change is %+v; want %+v", c.name, got, c.want)
		}
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

// A run's vars name the bead's record when its head is the head the record
// validated, its target the record's and its branch var the bead's branch. A
// shadow run judges a PR whose bead is on no record, and needs only the PR.
func TestARunsVarsNameTheRecord(t *testing.T) {
	mismatch := func(w *world) string {
		t.Helper()
		st, err := review.ReadStep(w.ledger(), w.step(1, "triage"))
		if err != nil {
			t.Fatal(err)
		}
		return st.Mismatch()
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
	setRoot(w, "gc.var.shadow", "true")
	if got := mismatch(w); got != "" {
		t.Errorf("a shadow run on a bead with a PR and no record reads %q", got)
	}
	setPR(w, "pr_url", "")
	if got := mismatch(w); !strings.Contains(got, "names no PR") {
		t.Errorf("a shadow run on a bead with no PR reads %q", got)
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
