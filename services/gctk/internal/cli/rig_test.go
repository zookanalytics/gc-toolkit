package cli

import (
	"bytes"
	"encoding/json"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/rig"
)

// rigGCStub answers the gc calls a publish makes. `bd update` keeps the one
// --set-metadata pair it is given, or fails with STUB_UPDATE_RC, and `bd show`
// answers with the pair kept, or with STUB_SHOW_VALUE as its value. Every call
// is logged, one argv per line, and any other call fails.
const rigGCStub = `#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_GC_LOG"
case "$1 $2" in
  "bd update")
    if [ "${STUB_UPDATE_RC:-0}" != 0 ]; then echo "update refused" >&2; exit "$STUB_UPDATE_RC"; fi
    id=$3; shift 3
    while [ $# -gt 0 ]; do
      if [ "$1" = --set-metadata ]; then
        printf '%s' "${2%%=*}" > "$STUB_DIR/meta.key"
        printf '%s' "${2#*=}" > "$STUB_DIR/meta.value"
        shift 2
      else
        shift
      fi
    done
    echo "updated $id" ;;
  "bd show")
    key=$(cat "$STUB_DIR/meta.key" 2>/dev/null)
    val=$(cat "$STUB_DIR/meta.value" 2>/dev/null)
    if [ -n "${STUB_SHOW_VALUE+x}" ]; then val=$STUB_SHOW_VALUE; fi
    val=${val//\\/\\\\}; val=${val//\"/\\\"}
    printf '[{"id":"%s","metadata":{"%s":"%s"}}]\n' "$3" "$key" "$val" ;;
  *) echo "unexpected gc call: $*" >&2; exit 9 ;;
esac
`

// countCmd is a check command that appends its label to $COUNT_FILE, so a test
// can tell how many times, and which command, ran, then exits $CHECK_RC.
func countCmd(label string) string {
	return `printf '%s\n' ` + label + ` >> "$COUNT_FILE"; exit "${CHECK_RC:-0}"`
}

type rigFixture struct {
	t     *testing.T
	repo  string
	stub  string
	count string
	gcLog string
}

// newRigFixture makes a scratch clone with one commit, puts the gc stub on
// PATH, and moves the test into the clone. Git reads no config of the host's,
// and rig's environment names a runner.
func newRigFixture(t *testing.T) *rigFixture {
	t.Helper()
	f := &rigFixture{t: t, repo: t.TempDir(), stub: t.TempDir()}
	f.count = filepath.Join(f.stub, "count")
	f.gcLog = filepath.Join(f.stub, "gc.log")
	gitConfig := filepath.Join(f.stub, "gitconfig")
	if err := os.WriteFile(gitConfig, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	for k, v := range map[string]string{
		"GIT_CONFIG_GLOBAL": gitConfig, "GIT_CONFIG_NOSYSTEM": "1",
		"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.com",
		"GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.com",
		"STUB_GC_LOG": f.gcLog, "STUB_DIR": f.stub, "COUNT_FILE": f.count,
		"GC_SESSION_NAME": "test-runner", "CHECK_RC": "0",
	} {
		t.Setenv(k, v)
	}
	if err := os.WriteFile(filepath.Join(f.stub, "gc"), []byte(rigGCStub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", f.stub+string(os.PathListSeparator)+os.Getenv("PATH"))
	f.git("init", "-q", "-b", "main")
	f.write("a.txt", "one\n")
	f.git("add", "-A")
	f.git("commit", "-q", "-m", "one")
	t.Chdir(f.repo)
	return f
}

func (f *rigFixture) git(args ...string) string {
	f.t.Helper()
	cmd := exec.Command("git", append([]string{"-C", f.repo}, args...)...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		f.t.Fatalf("git %v: %v\n%s", args, err, out)
	}
	return strings.TrimSpace(string(out))
}

func (f *rigFixture) write(name, body string) {
	f.t.Helper()
	if err := os.WriteFile(filepath.Join(f.repo, name), []byte(body), 0o644); err != nil {
		f.t.Fatal(err)
	}
}

// commitChange commits a change to a.txt, so HEAD names a new tree.
func (f *rigFixture) commitChange(body string) {
	f.t.Helper()
	f.write("a.txt", body)
	f.git("commit", "-q", "-am", "change")
}

func (f *rigFixture) call(args ...string) (int, string, string) {
	f.t.Helper()
	var out, errb bytes.Buffer
	code := Rig(args, &out, &errb)
	return code, out.String(), errb.String()
}

// runs lists the labels of the check commands that ran, in order.
func (f *rigFixture) runs() []string {
	f.t.Helper()
	raw, err := os.ReadFile(f.count)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		f.t.Fatal(err)
	}
	return strings.Fields(string(raw))
}

func (f *rigFixture) head() string { return f.git("rev-parse", "HEAD") }

func (f *rigFixture) recordPath(check, commit string) string {
	return filepath.Join(f.repo, ".git", "gc-rig-checks", check, "commits", commit+".json")
}

func (f *rigFixture) record(check, commit string) *rig.Record {
	f.t.Helper()
	raw, err := os.ReadFile(f.recordPath(check, commit))
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		f.t.Fatal(err)
	}
	var r rig.Record
	if err := json.Unmarshal(raw, &r); err != nil {
		f.t.Fatalf("record %s: %v", f.recordPath(check, commit), err)
	}
	return &r
}

// gcCalls lists the logged gc calls that start with prefix.
func (f *rigFixture) gcCalls(prefix string) []string {
	f.t.Helper()
	raw, err := os.ReadFile(f.gcLog)
	if os.IsNotExist(err) {
		return nil
	}
	var out []string
	for _, l := range strings.Split(strings.TrimRight(string(raw), "\n"), "\n") {
		if strings.HasPrefix(l, prefix) {
			out = append(out, l)
		}
	}
	return out
}

func eqRuns(t *testing.T, got []string, want ...string) {
	t.Helper()
	if strings.Join(got, " ") != strings.Join(want, " ") {
		t.Fatalf("runs = %v, want %v", got, want)
	}
}

func TestRigTestPassAtACommitIsRecordedAndNotRunAgain(t *testing.T) {
	f := newRigFixture(t)
	full := countCmd("full")

	code, _, errs := f.call("test", "--scope", "full", "--command", full)
	if code != 0 {
		t.Fatalf("first run = %d, want 0; stderr:\n%s", code, errs)
	}
	eqRuns(t, f.runs(), "full")
	r := f.record(rig.CheckTest, f.head())
	if r == nil {
		t.Fatal("the pass was not recorded")
	}
	if r.Result != rig.ResultPass || r.Scope != rig.ScopeFull || r.Commit != f.head() ||
		r.Tree != f.git("rev-parse", "HEAD^{tree}") || r.Runner != "test-runner" || r.ExitCode != 0 ||
		r.Command != full || r.RecordedAt == "" || r.DurationMS < 0 {
		t.Fatalf("record = %+v", r)
	}

	code, _, errs = f.call("test", "--scope", "full", "--command", full)
	if code != 0 || !strings.Contains(errs, "pass recorded at "+f.head()) || !strings.Contains(errs, "not run again") {
		t.Fatalf("second run = %d, stderr:\n%s", code, errs)
	}
	eqRuns(t, f.runs(), "full")
	// The caller passes the command, so a run reads no var: gc is never
	// called.
	if got := f.gcCalls(""); len(got) != 0 {
		t.Fatalf("gc was called: %q", got)
	}
}

func TestRigTestFullPassAnswersForANewCommitWithTheSameTree(t *testing.T) {
	f := newRigFixture(t)
	full := countCmd("full")
	if code, _, errs := f.call("test", "--scope", "full", "--command", full); code != 0 {
		t.Fatalf("first run = %d:\n%s", code, errs)
	}
	first := f.head()
	f.git("commit", "-q", "--allow-empty", "-m", "same tree")
	second := f.head()

	code, _, errs := f.call("test", "--scope", "full", "--command", full)
	if code != 0 || !strings.Contains(errs, "pass recorded at "+first) || !strings.Contains(errs, "is HEAD's ("+second+")") {
		t.Fatalf("run at a commit with the same tree = %d, stderr:\n%s", code, errs)
	}
	eqRuns(t, f.runs(), "full")
	code, out, _ := f.call("test", "--check")
	if code != 0 || !strings.Contains(out, `"commit":"`+first+`"`) {
		t.Fatalf("--check at the same tree = %d, stdout %q", code, out)
	}
	if f.record(rig.CheckTest, second) != nil {
		t.Fatal("a pass read through the tree was written as the new commit's own record")
	}

	f.commitChange("two\n")
	if code, _, _ := f.call("test", "--scope", "full", "--command", full); code != 0 {
		t.Fatal("a run at a new tree failed")
	}
	eqRuns(t, f.runs(), "full", "full")
}

func TestRigTestAffectedPassIsRecordedWithItsScopeAndStaysWithItsCommit(t *testing.T) {
	f := newRigFixture(t)
	affected := countCmd("affected")
	// The command works out its own diff, so rig needs no base to diff
	// against: this clone has no remote at all.
	if refs := f.git("for-each-ref", "refs/remotes"); refs != "" {
		t.Fatalf("the fixture has remote refs: %s", refs)
	}

	code, _, errs := f.call("test", "--scope", "affected", "--command", affected)
	if code != 0 {
		t.Fatalf("affected run = %d:\n%s", code, errs)
	}
	eqRuns(t, f.runs(), "affected")
	if r := f.record(rig.CheckTest, f.head()); r == nil || r.Scope != rig.ScopeAffected || r.Command != affected {
		t.Fatalf("record = %+v, want scope affected", r)
	}
	code, out, errs := f.call("test", "--check")
	if code != 0 || !strings.Contains(out, `"scope":"affected"`) || !strings.Contains(errs, "(scope affected") {
		t.Fatalf("--check = %d, stdout %q, stderr %q", code, out, errs)
	}
	// A subset depends on the commit's diff, not only on its tree.
	f.git("commit", "-q", "--allow-empty", "-m", "same tree")
	if code, _, errs := f.call("test", "--scope", "affected", "--command", affected); code != 0 {
		t.Fatalf("affected run at the same tree = %d:\n%s", code, errs)
	}
	eqRuns(t, f.runs(), "affected", "affected")
	if _, err := os.Stat(filepath.Join(f.repo, ".git", "gc-rig-checks", "test", "trees")); !os.IsNotExist(err) {
		t.Fatalf("an affected pass wrote a tree entry: %v", err)
	}
}

// A record answers only the run it records. A call that passes another
// command, or declares another scope, runs, and its result replaces the
// record.
func TestRigARecordAnswersOnlyTheRunItRecords(t *testing.T) {
	t.Run("an affected pass does not answer a full-suite call", func(t *testing.T) {
		f := newRigFixture(t)
		if code, _, _ := f.call("test", "--scope", "affected", "--command", countCmd("affected")); code != 0 {
			t.Fatal("the affected run failed")
		}
		code, _, errs := f.call("test", "--scope", "full", "--command", countCmd("full"))
		if code != 0 || !strings.Contains(errs, "is another run's, so this call runs") {
			t.Fatalf("full-suite call over an affected pass = %d:\n%s", code, errs)
		}
		eqRuns(t, f.runs(), "affected", "full")
		if r := f.record(rig.CheckTest, f.head()); r == nil || r.Scope != rig.ScopeFull || r.Command != countCmd("full") {
			t.Fatalf("record = %+v, want the full-suite run", r)
		}
	})
	t.Run("the same command line under another scope", func(t *testing.T) {
		f := newRigFixture(t)
		same := countCmd("same")
		if code, _, _ := f.call("test", "--scope", "affected", "--command", same); code != 0 {
			t.Fatal("the affected run failed")
		}
		if code, _, _ := f.call("test", "--scope", "full", "--command", same); code != 0 {
			t.Fatal("the full-suite run failed")
		}
		eqRuns(t, f.runs(), "same", "same")
	})
	t.Run("a changed command runs, and a recorded fail does not stand for it", func(t *testing.T) {
		f := newRigFixture(t)
		t.Setenv("CHECK_RC", "1")
		if code, _, _ := f.call("lint", "--command", countCmd("old")); code != 1 {
			t.Fatal("the old command did not fail")
		}
		t.Setenv("CHECK_RC", "0")
		code, _, errs := f.call("lint", "--command", countCmd("new"))
		if code != 0 || !strings.Contains(errs, "fail recorded at "+f.head()) {
			t.Fatalf("the changed command = %d:\n%s", code, errs)
		}
		eqRuns(t, f.runs(), "old", "new")
		// The old command's record was replaced, so it runs again too.
		if code, _, _ := f.call("lint", "--command", countCmd("old")); code != 0 {
			t.Fatal("the old command, run again, did not pass")
		}
		eqRuns(t, f.runs(), "old", "new", "old")
	})
	t.Run("a tree's full-suite pass answers only its own command", func(t *testing.T) {
		f := newRigFixture(t)
		if code, _, _ := f.call("test", "--scope", "full", "--command", countCmd("one")); code != 0 {
			t.Fatal("the first run failed")
		}
		f.git("commit", "-q", "--allow-empty", "-m", "same tree")
		if code, _, _ := f.call("test", "--scope", "full", "--command", countCmd("two")); code != 0 {
			t.Fatal("the second command failed")
		}
		eqRuns(t, f.runs(), "one", "two")
		// Nor does it answer an affected call with its own command.
		f.git("commit", "-q", "--allow-empty", "-m", "same tree again")
		if code, _, _ := f.call("test", "--scope", "affected", "--command", countCmd("two")); code != 0 {
			t.Fatal("the affected run failed")
		}
		eqRuns(t, f.runs(), "one", "two", "two")
	})
}

func TestRigRecordedFailFailsFastAndForceRunsAgain(t *testing.T) {
	f := newRigFixture(t)
	full := countCmd("full")
	t.Setenv("CHECK_RC", "3")

	if code, _, errs := f.call("test", "--scope", "full", "--command", full); code != 1 {
		t.Fatalf("a failing run = %d, want 1:\n%s", code, errs)
	}
	if r := f.record(rig.CheckTest, f.head()); r == nil || r.Result != rig.ResultFail || r.ExitCode != 3 {
		t.Fatalf("record = %+v, want a fail with the command's exit 3", r)
	}
	code, _, errs := f.call("test", "--scope", "full", "--command", full)
	if code != 1 || !strings.Contains(errs, "fail recorded at") || !strings.Contains(errs, "--force runs it again") {
		t.Fatalf("a run over a recorded fail = %d:\n%s", code, errs)
	}
	eqRuns(t, f.runs(), "full")
	code, out, _ := f.call("test", "--check")
	if code != 1 || !strings.Contains(out, `"result":"fail"`) {
		t.Fatalf("--check over a fail = %d, stdout %q", code, out)
	}

	t.Setenv("CHECK_RC", "0")
	if code, _, errs := f.call("test", "--scope", "full", "--command", full, "--force"); code != 0 {
		t.Fatalf("--force = %d:\n%s", code, errs)
	}
	eqRuns(t, f.runs(), "full", "full")
	if r := f.record(rig.CheckTest, f.head()); r == nil || r.Result != rig.ResultPass {
		t.Fatalf("record after --force = %+v, want the new pass", r)
	}
	if code, _, _ := f.call("test", "--scope", "full", "--command", full, "--force"); code != 0 {
		t.Fatal("--force over a pass failed")
	}
	eqRuns(t, f.runs(), "full", "full", "full")
}

func TestRigMachineFailuresHaveTheirOwnExitAndAreNotRecorded(t *testing.T) {
	cases := []struct {
		name    string
		command string
		args    []string
		reason  string
	}{
		{"command not found", "gctk-no-such-command-anywhere", nil, "not found (exit 127)"},
		{"killed", "kill -KILL $$", nil, "killed by signal 9"},
		{"timeout", "sleep 5", []string{"--timeout", "200ms"}, "timed out after 200ms"},
		{"does not parse", "echo (", nil, "does not parse"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			old := rig.StopGrace
			rig.StopGrace = 200 * time.Millisecond
			defer func() { rig.StopGrace = old }()
			f := newRigFixture(t)
			code, _, errs := f.call(append([]string{"test", "--scope", "full", "--command", c.command}, c.args...)...)
			if code != 4 || !strings.Contains(errs, "machine failure, nothing recorded") || !strings.Contains(errs, c.reason) {
				t.Fatalf("run = %d, want 4 naming %q:\n%s", code, c.reason, errs)
			}
			if r := f.record(rig.CheckTest, f.head()); r != nil {
				t.Fatalf("a machine failure was recorded: %+v", r)
			}
			if code, _, _ := f.call("test", "--check"); code != 3 {
				t.Fatalf("--check after a machine failure = %d, want 3", code)
			}
		})
	}
	t.Run("not in a checkout", func(t *testing.T) {
		newRigFixture(t)
		t.Chdir(t.TempDir())
		if code := Rig([]string{"test", "--check"}, &bytes.Buffer{}, &bytes.Buffer{}); code != 4 {
			t.Fatalf("--check outside a checkout = %d, want 4", code)
		}
	})
}

// A result the record store does not take is no answer of rig's: the call
// exits 4 and publishes nothing, so a published result always has the record
// --check reads behind it.
func TestRigAResultTheStoreDoesNotTakeIsAMachineFailureAndIsNotPublished(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root writes into a read-only directory")
	}
	cases := []struct {
		name string
		args []string
		rc   string
		want string
		exit int
	}{
		{"a pass", []string{"--scope", "full", "--command", countCmd("full")}, "0", "did not take the pass at", 0},
		{"a fail", []string{"--scope", "full", "--command", countCmd("full")}, "1", "did not take the fail at", 1},
		{"a pass that ran nothing", []string{"--nothing-declared"}, "0", "did not take the pass that ran nothing", 0},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			f := newRigFixture(t)
			t.Setenv("CHECK_RC", c.rc)
			store := filepath.Join(f.repo, ".git", "gc-rig-checks")
			if err := os.Mkdir(store, 0o555); err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { os.Chmod(store, 0o755) })
			args := append(append([]string{"test"}, c.args...), "--publish-bead", "tk-work")

			code, _, errs := f.call(args...)
			if code != 4 || !strings.Contains(errs, "machine failure: ") || !strings.Contains(errs, c.want) || !strings.Contains(errs, "permission denied") {
				t.Fatalf("run = %d, want 4 naming %q and the store's error:\n%s", code, c.want, errs)
			}
			if got := f.gcCalls("bd update"); len(got) != 0 {
				t.Fatalf("a result the store did not take was published: %q", got)
			}
			if code, _, _ := f.call("test", "--check"); code != 3 {
				t.Fatalf("--check after the refused write = %d, want 3", code)
			}

			// Nothing stands in for the record, so the next call runs again.
			if err := os.Chmod(store, 0o755); err != nil {
				t.Fatal(err)
			}
			if code, _, errs := f.call(args...); code != c.exit || !strings.Contains(errs, "published to tk-work") {
				t.Fatalf("the next call = %d, want %d:\n%s", code, c.exit, errs)
			}
			if r := f.record(rig.CheckTest, f.head()); r == nil {
				t.Fatal("the next call recorded nothing")
			}
		})
	}
}

func TestRigRefusesADirtyTree(t *testing.T) {
	for name, dirty := range map[string]func(f *rigFixture){
		"an untracked file":   func(f *rigFixture) { f.write("new.txt", "x\n") },
		"an unstaged change":  func(f *rigFixture) { f.write("a.txt", "changed\n") },
		"a staged change":     func(f *rigFixture) { f.write("a.txt", "changed\n"); f.git("add", "a.txt") },
		"a deleted file":      func(f *rigFixture) { os.Remove(filepath.Join(f.repo, "a.txt")) },
		"an untracked subdir": func(f *rigFixture) { os.Mkdir(filepath.Join(f.repo, "d"), 0o755); f.write("d/x", "x\n") },
		"an untracked file config hides": func(f *rigFixture) {
			f.git("config", "status.showUntrackedFiles", "no")
			f.write("foo_test.go", "package foo\n")
		},
	} {
		t.Run(name, func(t *testing.T) {
			f := newRigFixture(t)
			dirty(f)
			full := countCmd("full")
			for _, args := range [][]string{
				{"test", "--scope", "full", "--command", full},
				{"test", "--scope", "full", "--command", full, "--force"},
				{"test", "--nothing-declared"},
				{"test", "--check"},
			} {
				code, _, errs := f.call(args...)
				if code != 4 || !strings.Contains(errs, "changes HEAD does not hold") {
					t.Fatalf("%v on a dirty tree = %d, want 4:\n%s", args, code, errs)
				}
			}
			eqRuns(t, f.runs())
			if _, err := os.Stat(filepath.Join(f.repo, ".git", "gc-rig-checks")); !os.IsNotExist(err) {
				t.Fatalf("a refused run wrote to the record store: %v", err)
			}
		})
	}
}

// A run speaks for the commit it started at only while it leaves HEAD and
// every tracked file as it found them. One that changes either records and
// publishes nothing, pass or fail.
func TestRigARunThatChangesTheCheckoutRecordsNothing(t *testing.T) {
	cases := []struct {
		name    string
		command string
		reason  string
	}{
		{"a commit, then a pass", `git commit -q --allow-empty -m moved`, "HEAD moved from"},
		{"a tracked file rewritten, then a pass", `printf 'fixed\n' > a.txt`, "its pass (exit 0) says nothing about"},
		{"a tracked file rewritten, then a fail", `printf 'fixed\n' > a.txt; exit 1`, "its fail (exit 1) says nothing about"},
		{"a new file staged", `printf 'x\n' > b.txt && git add b.txt`, "A  b.txt"},
		{"a tracked file deleted", `rm a.txt`, " D a.txt"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			f := newRigFixture(t)
			start := f.head()
			code, _, errs := f.call("test", "--scope", "full", "--command", c.command, "--publish-bead", "tk-work")
			if code != 4 || !strings.Contains(errs, "machine failure, nothing recorded: the command changed the checkout it ran in") ||
				!strings.Contains(errs, c.reason) || !strings.Contains(errs, start) {
				t.Fatalf("run = %d, want 4 naming %q and %s:\n%s", code, c.reason, start, errs)
			}
			if _, err := os.Stat(filepath.Join(f.repo, ".git", "gc-rig-checks")); !os.IsNotExist(err) {
				t.Fatalf("a run that changed the checkout wrote to the record store: %v", err)
			}
			if got := f.gcCalls("bd update"); len(got) != 0 {
				t.Fatalf("a run that changed the checkout was published: %q", got)
			}
		})
	}
	t.Run("a checkout rig cannot read after the run", func(t *testing.T) {
		f := newRigFixture(t)
		// Git looks for the moved .git no higher than the clone itself.
		t.Setenv("GIT_CEILING_DIRECTORIES", filepath.Dir(f.repo))
		gitDir := filepath.Join(f.repo, ".git")
		code, _, errs := f.call("test", "--scope", "full", "--command", `mv .git .git-gone`)
		if err := os.Rename(gitDir+"-gone", gitDir); err != nil {
			t.Fatal(err)
		}
		if code != 4 || !strings.Contains(errs, "machine failure, nothing recorded: cannot read the checkout after the run") {
			t.Fatalf("run = %d, want 4:\n%s", code, errs)
		}
		if _, err := os.Stat(filepath.Join(gitDir, "gc-rig-checks")); !os.IsNotExist(err) {
			t.Fatalf("a run rig could not check wrote to the record store: %v", err)
		}
	})
}

// An untracked file a run leaves behind changes no file the commit holds, so
// the run's result is recorded.
func TestRigARunThatLeavesAnUntrackedFileKeepsItsRecord(t *testing.T) {
	f := newRigFixture(t)
	command := `printf x > cover.out; ` + countCmd("full")
	if code, _, errs := f.call("test", "--scope", "full", "--command", command); code != 0 {
		t.Fatalf("run = %d, want 0:\n%s", code, errs)
	}
	if r := f.record(rig.CheckTest, f.head()); r == nil || r.Result != rig.ResultPass {
		t.Fatalf("record = %+v, want the pass", r)
	}
}

func TestRigCheckReadsTheRecordWithNoGc(t *testing.T) {
	f := newRigFixture(t)
	if code, _, _ := f.call("test", "--scope", "full", "--command", countCmd("full")); code != 0 {
		t.Fatal("the run failed")
	}
	// A gc that answers nothing and leaves a mark, ahead of the stub.
	trap := t.TempDir()
	mark := filepath.Join(trap, "gc-was-called")
	if err := os.WriteFile(filepath.Join(trap, "gc"), []byte("#!/bin/sh\ntouch '"+mark+"'\nexit 1\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", trap+string(os.PathListSeparator)+os.Getenv("PATH"))

	code, out, errs := f.call("test", "--check")
	if code != 0 {
		t.Fatalf("--check = %d:\n%s", code, errs)
	}
	var r rig.Record
	if err := json.Unmarshal([]byte(out), &r); err != nil || r.Result != rig.ResultPass || r.Commit != f.head() {
		t.Fatalf("--check stdout %q is not the record (%v)", out, err)
	}
	if strings.Count(out, "\n") != 1 {
		t.Fatalf("--check printed %q, want one JSON line", out)
	}
	if _, err := os.Stat(mark); !os.IsNotExist(err) {
		t.Fatal("--check called gc")
	}
	if code, _, _ := f.call("lint", "--check"); code != 3 {
		t.Fatalf("--check of a check never run = %d, want 3", code)
	}
}

func TestRigPublishBeadUpsertsTheResultOntoTheBead(t *testing.T) {
	f := newRigFixture(t)
	full := countCmd("full")

	code, _, errs := f.call("test", "--scope", "full", "--command", full, "--publish-bead", "tk-work")
	if code != 0 || !strings.Contains(errs, "published to tk-work as rig_check.test") {
		t.Fatalf("run = %d:\n%s", code, errs)
	}
	updates := f.gcCalls("bd update")
	stored, _ := os.ReadFile(f.recordPath(rig.CheckTest, f.head()))
	want := "bd update tk-work --set-metadata rig_check.test=" + strings.TrimSpace(string(stored))
	if len(updates) != 1 || updates[0] != want {
		t.Fatalf("bd update calls = %q, want [%q]", updates, want)
	}
	if shows := f.gcCalls("bd show"); len(shows) != 1 || shows[0] != "bd show tk-work --json" {
		t.Fatalf("read-back = %q", shows)
	}

	// A recorded result answers without running and is published as well.
	code, _, errs = f.call("test", "--scope", "full", "--command", full, "--publish-bead", "tk-anchor")
	if code != 0 || !strings.Contains(errs, "published to tk-anchor") {
		t.Fatalf("recorded run = %d:\n%s", code, errs)
	}
	eqRuns(t, f.runs(), "full")
	if n := len(f.gcCalls("bd update tk-anchor --set-metadata rig_check.test=")); n != 1 {
		t.Fatalf("a recorded pass was published %d times, want 1", n)
	}

	// A publish that fails, or does not read back, is reported and changes no
	// exit.
	t.Setenv("STUB_UPDATE_RC", "1")
	code, _, errs = f.call("test", "--scope", "full", "--command", full, "--publish-bead", "tk-work")
	if code != 0 || !strings.Contains(errs, "WARN the result was not published to tk-work") {
		t.Fatalf("a refused publish = %d:\n%s", code, errs)
	}
	t.Setenv("STUB_UPDATE_RC", "0")
	t.Setenv("STUB_SHOW_VALUE", "something else")
	code, _, errs = f.call("test", "--scope", "full", "--command", full, "--publish-bead", "tk-work")
	if code != 0 || !strings.Contains(errs, "did not read back as written") {
		t.Fatalf("a publish that did not read back = %d:\n%s", code, errs)
	}
}

func TestRigNothingDeclaredIsAPassThatRanNothing(t *testing.T) {
	f := newRigFixture(t)

	code, _, errs := f.call("test", "--nothing-declared", "--publish-bead", "tk-work")
	if code != 0 || !strings.Contains(errs, "nothing declared to run") || !strings.Contains(errs, "published to tk-work") {
		t.Fatalf("run = %d:\n%s", code, errs)
	}
	eqRuns(t, f.runs())
	r := f.record(rig.CheckTest, f.head())
	if r == nil || r.Result != rig.ResultPass || r.Scope != rig.ScopeNone || r.Command != "" {
		t.Fatalf("record = %+v, want a pass with scope none", r)
	}
	if code, out, _ := f.call("test", "--check"); code != 0 || !strings.Contains(out, `"scope":"none"`) {
		t.Fatalf("--check = %d, %q", code, out)
	}
	// Declared again, the record answers.
	if code, _, errs := f.call("test", "--nothing-declared"); code != 0 || !strings.Contains(errs, "not run again") {
		t.Fatalf("nothing declared again = %d:\n%s", code, errs)
	}
	// A call that passes a command declares another run, so the command runs.
	if code, _, errs := f.call("test", "--scope", "full", "--command", countCmd("full")); code != 0 {
		t.Fatalf("run after declaring = %d:\n%s", code, errs)
	}
	eqRuns(t, f.runs(), "full")
	if r := f.record(rig.CheckTest, f.head()); r == nil || r.Scope != rig.ScopeFull {
		t.Fatalf("record = %+v, want the full run", r)
	}
	// Nothing declared is a run like any other, and the last record wins.
	if code, _, _ := f.call("lint", "--nothing-declared"); code != 0 {
		t.Fatal("lint with nothing declared failed")
	}
	if r := f.record(rig.CheckLint, f.head()); r == nil || r.Scope != rig.ScopeNone {
		t.Fatalf("lint record = %+v, want scope none", r)
	}
}

func TestRigLintAndTypecheckAreRecordedPerCommit(t *testing.T) {
	f := newRigFixture(t)
	for _, check := range []string{rig.CheckLint, rig.CheckTypecheck} {
		if code, _, errs := f.call(check, "--command", countCmd(check)); code != 0 {
			t.Fatalf("%s = %d:\n%s", check, code, errs)
		}
		if r := f.record(check, f.head()); r == nil || r.Check != check || r.Scope != "" || r.Command != countCmd(check) {
			t.Fatalf("%s record = %+v, want no scope", check, r)
		}
		if code, _, _ := f.call(check, "--command", countCmd(check)); code != 0 {
			t.Fatalf("recorded %s failed", check)
		}
	}
	eqRuns(t, f.runs(), "lint", "typecheck")
	// A lint command may read the commit's diff, so its pass does not cross
	// to another commit with the same tree.
	f.git("commit", "-q", "--allow-empty", "-m", "same tree")
	if code, _, _ := f.call("lint", "--command", countCmd("lint")); code != 0 {
		t.Fatal("lint at the same tree failed")
	}
	eqRuns(t, f.runs(), "lint", "typecheck", "lint")
	if f.record(rig.CheckTest, f.head()) != nil {
		t.Fatal("a lint run wrote a test record")
	}
}

func TestRigSetupAndBuildRunAndRecordNothing(t *testing.T) {
	f := newRigFixture(t)
	if code, _, errs := f.call("setup", "--command", countCmd("setup")); code != 0 {
		t.Fatalf("setup = %d:\n%s", code, errs)
	}
	t.Setenv("CHECK_RC", "2")
	if code, _, _ := f.call("build", "--command", countCmd("build")); code != 1 {
		t.Fatalf("a failing build = %d, want 1", code)
	}
	t.Setenv("CHECK_RC", "0")
	if code, _, _ := f.call("build", "--command", countCmd("build")); code != 0 {
		t.Fatal("build did not pass")
	}
	eqRuns(t, f.runs(), "setup", "build", "build")
	if _, err := os.Stat(filepath.Join(f.repo, ".git", "gc-rig-checks")); !os.IsNotExist(err) {
		t.Fatalf("setup or build wrote to the record store: %v", err)
	}
	// setup runs in a tree it is about to change, so a dirty one is no reason
	// to refuse it.
	f.write("node_modules.txt", "x\n")
	if code, _, _ := f.call("setup", "--command", countCmd("setup")); code != 0 {
		t.Fatal("setup refused a dirty tree")
	}
}

// A SIGTERM during the run reaches the command's group, and rig exits 128+15
// with nothing recorded. The test's own Notify keeps a build without the relay
// from killing the test binary.
func TestRigStoppedBySignalRecordsNothing(t *testing.T) {
	held := make(chan os.Signal, 4)
	signal.Notify(held, syscall.SIGTERM)
	defer signal.Stop(held)
	f := newRigFixture(t)
	ready := filepath.Join(f.stub, "ready")
	go func() {
		deadline := time.Now().Add(10 * time.Second)
		for time.Now().Before(deadline) {
			if _, err := os.Stat(ready); err == nil {
				_ = syscall.Kill(os.Getpid(), syscall.SIGTERM)
				return
			}
			time.Sleep(10 * time.Millisecond)
		}
	}()
	code, _, errs := f.call("test", "--scope", "full", "--command", `touch "`+ready+`"; sleep 30 & wait $!`)
	if code != 128+int(syscall.SIGTERM) || !strings.Contains(errs, "nothing was recorded") {
		t.Fatalf("a run stopped by SIGTERM = %d:\n%s", code, errs)
	}
	if f.record(rig.CheckTest, f.head()) != nil {
		t.Fatal("a stopped run was recorded")
	}
}

func TestRigUsageErrors(t *testing.T) {
	newRigFixture(t)
	for _, args := range [][]string{
		{},
		{"deploy"},
		{"test"},
		{"test", "--scope", "full"},
		{"test", "--command", "true"},
		{"test", "--scope", "everything", "--command", "true"},
		{"test", "--scope", "full", "--command", ""},
		{"test", "--scope", "full", "--command"},
		{"test", "--scope", "full", "--command", "true", "--nothing-declared"},
		{"test", "--scope", "full", "--command", "true", "--check"},
		{"test", "--nothing-declared", "--check"},
		{"test", "--nothing-declared", "--scope", "full"},
		{"test", "--nothing-declared", "--force"},
		{"test", "--nothing-declared", "--timeout", "1m"},
		{"test", "--check", "--force"},
		{"test", "--check", "--scope", "full"},
		{"test", "--check", "--timeout", "1m"},
		{"test", "--check", "--publish-bead", "tk-x"},
		{"test", "--check", "--check"},
		{"test", "--scope", "full", "--command", "true", "--publish-bead"},
		{"test", "--scope", "full", "--command", "true", "--timeout", "soon"},
		{"test", "--scope", "full", "--command", "true", "--timeout", "-1s"},
		{"test", "--affected"},
		{"test", "--frobnicate"},
		{"lint", "--scope", "full", "--command", "true"},
		{"typecheck", "--scope", "affected", "--command", "true"},
		{"setup"},
		{"setup", "--check"},
		{"build", "--command", "true", "--publish-bead", "tk-x"},
		{"setup", "--command", "true", "--force"},
		{"build", "--nothing-declared"},
	} {
		var out, errb bytes.Buffer
		if code := Rig(args, &out, &errb); code != 2 {
			t.Errorf("gctk rig %q = %d, want 2; stderr:\n%s", args, code, errb.String())
		}
	}
	var out, errb bytes.Buffer
	if code := Rig([]string{"--help"}, &out, &errb); code != 0 || out.Len() == 0 || errb.Len() != 0 {
		t.Errorf("--help = %d, stdout %d bytes, stderr %q", code, out.Len(), errb.String())
	}
}
