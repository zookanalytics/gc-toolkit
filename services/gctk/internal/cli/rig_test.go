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

// rigGCStub answers the gc calls the gate makes. `formula show` prints
// $RIG_VARS_JSON, or fails when STUB_FORMULA_RC is set. `bd update` keeps the
// one --set-metadata pair it is given, or fails with STUB_UPDATE_RC, and `bd
// show` answers with the pair kept, or with STUB_SHOW_VALUE as its value.
// Every call is logged, one argv per line.
const rigGCStub = `#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_GC_LOG"
case "$1 $2" in
  "formula show")
    if [ -n "${STUB_FORMULA_RC:-}" ]; then echo '{"ok":false,"error":"stubbed failure"}'; exit "$STUB_FORMULA_RC"; fi
    printf '%s\n' "$RIG_VARS_JSON" ;;
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

// newRigFixture makes a scratch clone whose HEAD is origin/main, puts the gc
// stub on PATH, and moves the test into the clone. Git reads no config of the
// host's, and the gate's environment names a rig and a runner.
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
		"GC_RIG": "testrig", "GC_RIG_ROOT": "", "GC_SESSION_NAME": "test-runner",
		"CHECK_RC": "0", "RIG_VARS_JSON": `{"ok":true,"vars":[]}`,
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
	f.git("update-ref", "refs/remotes/origin/main", "HEAD")
	f.git("symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main")
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

// commitChange commits a change to a.txt, so HEAD's diff against origin/main
// names a file.
func (f *rigFixture) commitChange(body string) {
	f.t.Helper()
	f.write("a.txt", body)
	f.git("commit", "-q", "-am", "change")
}

// vars sets what the rig declares, as rig values over empty formula defaults.
func (f *rigFixture) vars(kv map[string]string) {
	f.t.Helper()
	type v struct {
		Name       string `json:"name"`
		Default    string `json:"default"`
		RigDefault string `json:"rig_default"`
	}
	var list []v
	for _, name := range []string{rig.VarTest, rig.VarAffected, rig.VarLint, rig.VarTypecheck, rig.VarBuild, rig.VarSetup} {
		if val, ok := kv[name]; ok {
			list = append(list, v{Name: name, RigDefault: val})
		} else {
			list = append(list, v{Name: name})
		}
	}
	raw, err := json.Marshal(map[string]any{"ok": true, "vars": list})
	if err != nil {
		f.t.Fatal(err)
	}
	f.t.Setenv("RIG_VARS_JSON", string(raw))
}

func (f *rigFixture) gate(args ...string) (int, string, string) {
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
	f.vars(map[string]string{rig.VarTest: countCmd("full")})

	code, _, errs := f.gate("test")
	if code != 0 {
		t.Fatalf("first run = %d, want 0; stderr:\n%s", code, errs)
	}
	eqRuns(t, f.runs(), "full")
	r := f.record(rig.CheckTest, f.head())
	if r == nil {
		t.Fatal("the pass was not recorded")
	}
	if r.Result != rig.ResultPass || r.Method != rig.MethodFull || r.Commit != f.head() ||
		r.Tree != f.git("rev-parse", "HEAD^{tree}") || r.Runner != "test-runner" || r.ExitCode != 0 ||
		r.Command != countCmd("full") || r.RecordedAt == "" || r.DurationMS < 0 {
		t.Fatalf("record = %+v", r)
	}

	code, _, errs = f.gate("test")
	if code != 0 || !strings.Contains(errs, "pass recorded at "+f.head()) || !strings.Contains(errs, "not run again") {
		t.Fatalf("second run = %d, stderr:\n%s", code, errs)
	}
	eqRuns(t, f.runs(), "full")
	if n := len(f.gcCalls("formula show")); n != 1 {
		t.Fatalf("gc formula show ran %d times; a recorded pass needs no vars", n)
	}
}

func TestRigTestFullPassAnswersForANewCommitWithTheSameTree(t *testing.T) {
	f := newRigFixture(t)
	f.vars(map[string]string{rig.VarTest: countCmd("full")})
	if code, _, errs := f.gate("test"); code != 0 {
		t.Fatalf("first run = %d:\n%s", code, errs)
	}
	first := f.head()
	f.git("commit", "-q", "--allow-empty", "-m", "same tree")
	second := f.head()

	code, _, errs := f.gate("test")
	if code != 0 || !strings.Contains(errs, "pass recorded at "+first) || !strings.Contains(errs, "is HEAD's ("+second+")") {
		t.Fatalf("run at a commit with the same tree = %d, stderr:\n%s", code, errs)
	}
	eqRuns(t, f.runs(), "full")
	code, out, _ := f.gate("test", "--check")
	if code != 0 || !strings.Contains(out, `"commit":"`+first+`"`) {
		t.Fatalf("--check at the same tree = %d, stdout %q", code, out)
	}
	if f.record(rig.CheckTest, second) != nil {
		t.Fatal("a pass read through the tree was written as the new commit's own record")
	}

	f.commitChange("two\n")
	if code, _, _ := f.gate("test"); code != 0 {
		t.Fatal("a run at a new tree failed")
	}
	eqRuns(t, f.runs(), "full", "full")
}

func TestRigTestAffectedPassIsRecordedWithItsMethodAndStaysWithItsCommit(t *testing.T) {
	f := newRigFixture(t)
	f.vars(map[string]string{rig.VarTest: countCmd("full"), rig.VarAffected: countCmd("affected")})
	f.commitChange("two\n")

	code, _, errs := f.gate("test", "--affected")
	if code != 0 {
		t.Fatalf("affected run = %d:\n%s", code, errs)
	}
	eqRuns(t, f.runs(), "affected")
	if r := f.record(rig.CheckTest, f.head()); r == nil || r.Method != rig.MethodAffected || r.Command != countCmd("affected") {
		t.Fatalf("record = %+v, want method affected", r)
	}
	code, out, errs := f.gate("test", "--check")
	if code != 0 || !strings.Contains(out, `"method":"affected"`) || !strings.Contains(errs, "(method affected") {
		t.Fatalf("--check = %d, stdout %q, stderr %q", code, out, errs)
	}
	// An affected pass counts as a pass by default, and the run says how it was
	// made.
	code, _, errs = f.gate("test")
	if code != 0 || !strings.Contains(errs, "pass recorded at "+f.head()+" (method affected") {
		t.Fatalf("a full-suite call over an affected pass = %d:\n%s", code, errs)
	}
	eqRuns(t, f.runs(), "affected")

	// A subset is a property of the commit's diff, not of its tree.
	f.git("commit", "-q", "--allow-empty", "-m", "same tree")
	if code, _, errs := f.gate("test", "--affected"); code != 0 {
		t.Fatalf("affected run at the same tree = %d:\n%s", code, errs)
	}
	eqRuns(t, f.runs(), "affected", "affected")
}

func TestRigTestAffectedFallsBackToTheFullSuite(t *testing.T) {
	t.Run("the diff against the base names no file", func(t *testing.T) {
		f := newRigFixture(t)
		f.vars(map[string]string{rig.VarTest: countCmd("full"), rig.VarAffected: countCmd("affected")})
		if code, _, errs := f.gate("test", "--affected"); code != 0 {
			t.Fatalf("run = %d:\n%s", code, errs)
		}
		eqRuns(t, f.runs(), "full")
		if r := f.record(rig.CheckTest, f.head()); r == nil || r.Method != rig.MethodFull {
			t.Fatalf("record = %+v, want method full", r)
		}
	})
	t.Run("affected_tests_command is empty", func(t *testing.T) {
		f := newRigFixture(t)
		f.vars(map[string]string{rig.VarTest: countCmd("full")})
		f.commitChange("two\n")
		if code, _, errs := f.gate("test", "--affected"); code != 0 {
			t.Fatalf("run = %d:\n%s", code, errs)
		}
		eqRuns(t, f.runs(), "full")
	})
	t.Run("the base is named with --base", func(t *testing.T) {
		f := newRigFixture(t)
		f.vars(map[string]string{rig.VarTest: countCmd("full"), rig.VarAffected: countCmd("affected")})
		f.git("update-ref", "refs/remotes/origin/feature", "HEAD")
		f.commitChange("two\n")
		f.git("update-ref", "refs/remotes/origin/main", "HEAD")
		// Against origin/main the diff is empty; against origin/feature it is
		// not.
		if code, _, errs := f.gate("test", "--affected", "--base", "feature"); code != 0 {
			t.Fatalf("run = %d:\n%s", code, errs)
		}
		eqRuns(t, f.runs(), "affected")
	})
	t.Run("a base the clone does not hold is a machine failure", func(t *testing.T) {
		f := newRigFixture(t)
		f.vars(map[string]string{rig.VarTest: countCmd("full"), rig.VarAffected: countCmd("affected")})
		code, _, errs := f.gate("test", "--affected", "--base", "no-such-branch")
		if code != 4 || !strings.Contains(errs, "origin/no-such-branch") {
			t.Fatalf("run = %d, want 4:\n%s", code, errs)
		}
		eqRuns(t, f.runs())
	})
}

func TestRigRecordedFailFailsFastAndForceRunsAgain(t *testing.T) {
	f := newRigFixture(t)
	f.vars(map[string]string{rig.VarTest: countCmd("full")})
	t.Setenv("CHECK_RC", "3")

	if code, _, errs := f.gate("test"); code != 1 {
		t.Fatalf("a failing run = %d, want 1:\n%s", code, errs)
	}
	if r := f.record(rig.CheckTest, f.head()); r == nil || r.Result != rig.ResultFail || r.ExitCode != 3 {
		t.Fatalf("record = %+v, want a fail with the command's exit 3", r)
	}
	code, _, errs := f.gate("test")
	if code != 1 || !strings.Contains(errs, "fail recorded at") || !strings.Contains(errs, "--force runs it again") {
		t.Fatalf("a run over a recorded fail = %d:\n%s", code, errs)
	}
	eqRuns(t, f.runs(), "full")
	code, out, _ := f.gate("test", "--check")
	if code != 1 || !strings.Contains(out, `"result":"fail"`) {
		t.Fatalf("--check over a fail = %d, stdout %q", code, out)
	}

	t.Setenv("CHECK_RC", "0")
	if code, _, errs := f.gate("test", "--force"); code != 0 {
		t.Fatalf("--force = %d:\n%s", code, errs)
	}
	eqRuns(t, f.runs(), "full", "full")
	if r := f.record(rig.CheckTest, f.head()); r == nil || r.Result != rig.ResultPass {
		t.Fatalf("record after --force = %+v, want the new pass", r)
	}
	if code, _, _ := f.gate("test", "--force"); code != 0 {
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
			f.vars(map[string]string{rig.VarTest: c.command})
			code, _, errs := f.gate(append([]string{"test"}, c.args...)...)
			if code != 4 || !strings.Contains(errs, "machine failure, nothing recorded") || !strings.Contains(errs, c.reason) {
				t.Fatalf("run = %d, want 4 naming %q:\n%s", code, c.reason, errs)
			}
			if r := f.record(rig.CheckTest, f.head()); r != nil {
				t.Fatalf("a machine failure was recorded: %+v", r)
			}
			if code, _, _ := f.gate("test", "--check"); code != 3 {
				t.Fatalf("--check after a machine failure = %d, want 3", code)
			}
		})
	}
	t.Run("the rig's vars cannot be read", func(t *testing.T) {
		f := newRigFixture(t)
		t.Setenv("STUB_FORMULA_RC", "1")
		if code, _, errs := f.gate("test"); code != 4 || !strings.Contains(errs, "cannot read rig testrig's check commands") {
			t.Fatalf("run = %d:\n%s", code, errs)
		}
		if f.record(rig.CheckTest, f.head()) != nil {
			t.Fatal("unreadable vars were recorded as a run")
		}
	})
	t.Run("no rig is named", func(t *testing.T) {
		f := newRigFixture(t)
		t.Setenv("GC_RIG", "")
		if code, _, errs := f.gate("test"); code != 4 || !strings.Contains(errs, "no rig named") {
			t.Fatalf("run = %d:\n%s", code, errs)
		}
	})
	t.Run("not in a checkout", func(t *testing.T) {
		newRigFixture(t)
		t.Chdir(t.TempDir())
		if code := Rig([]string{"test", "--check"}, &bytes.Buffer{}, &bytes.Buffer{}); code != 4 {
			t.Fatalf("--check outside a checkout = %d, want 4", code)
		}
	})
}

// A result the record store does not take is no answer of the gate's: the
// call exits 4 and publishes nothing, so a published result always has the
// record --check reads behind it.
func TestRigAResultTheStoreDoesNotTakeIsAMachineFailureAndIsNotPublished(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root writes into a read-only directory")
	}
	cases := []struct {
		name string
		vars map[string]string
		rc   string
		want string
		exit int
	}{
		{"a pass", map[string]string{rig.VarTest: countCmd("full")}, "0", "did not take the pass at", 0},
		{"a fail", map[string]string{rig.VarTest: countCmd("full")}, "1", "did not take the fail at", 1},
		{"a pass with nothing to run", map[string]string{}, "0", "did not take the pass with method none", 0},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			f := newRigFixture(t)
			f.vars(c.vars)
			t.Setenv("CHECK_RC", c.rc)
			store := filepath.Join(f.repo, ".git", "gc-rig-checks")
			if err := os.Mkdir(store, 0o555); err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { os.Chmod(store, 0o755) })

			code, _, errs := f.gate("test", "--publish-bead", "tk-work")
			if code != 4 || !strings.Contains(errs, "machine failure: ") || !strings.Contains(errs, c.want) || !strings.Contains(errs, "permission denied") {
				t.Fatalf("run = %d, want 4 naming %q and the store's error:\n%s", code, c.want, errs)
			}
			if got := f.gcCalls("bd update"); len(got) != 0 {
				t.Fatalf("a result the store did not take was published: %q", got)
			}
			if code, _, _ := f.gate("test", "--check"); code != 3 {
				t.Fatalf("--check after the refused write = %d, want 3", code)
			}

			// Nothing stands in for the record, so the next call runs again.
			if err := os.Chmod(store, 0o755); err != nil {
				t.Fatal(err)
			}
			if code, _, errs := f.gate("test", "--publish-bead", "tk-work"); code != c.exit || !strings.Contains(errs, "published to tk-work") {
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
	} {
		t.Run(name, func(t *testing.T) {
			f := newRigFixture(t)
			f.vars(map[string]string{rig.VarTest: countCmd("full")})
			dirty(f)
			for _, args := range [][]string{{"test"}, {"test", "--force"}, {"test", "--check"}} {
				code, _, errs := f.gate(args...)
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

func TestRigCheckReadsTheRecordWithNoGc(t *testing.T) {
	f := newRigFixture(t)
	f.vars(map[string]string{rig.VarTest: countCmd("full")})
	if code, _, _ := f.gate("test"); code != 0 {
		t.Fatal("the run failed")
	}
	// A gc that answers nothing and leaves a mark, ahead of the stub.
	trap := t.TempDir()
	mark := filepath.Join(trap, "gc-was-called")
	if err := os.WriteFile(filepath.Join(trap, "gc"), []byte("#!/bin/sh\ntouch '"+mark+"'\nexit 1\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", trap+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("GC_RIG", "")

	code, out, errs := f.gate("test", "--check")
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
	if code, _, _ := f.gate("lint", "--check"); code != 3 {
		t.Fatalf("--check of a check never run = %d, want 3", code)
	}
}

func TestRigPublishBeadUpsertsTheResultOntoTheBead(t *testing.T) {
	f := newRigFixture(t)
	f.vars(map[string]string{rig.VarTest: countCmd("full")})

	code, _, errs := f.gate("test", "--publish-bead", "tk-work")
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
	code, _, errs = f.gate("test", "--publish-bead", "tk-anchor")
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
	code, _, errs = f.gate("test", "--publish-bead", "tk-work")
	if code != 0 || !strings.Contains(errs, "WARN the result was not published to tk-work") {
		t.Fatalf("a refused publish = %d:\n%s", code, errs)
	}
	t.Setenv("STUB_UPDATE_RC", "0")
	t.Setenv("STUB_SHOW_VALUE", "something else")
	code, _, errs = f.gate("test", "--publish-bead", "tk-work")
	if code != 0 || !strings.Contains(errs, "did not read back as written") {
		t.Fatalf("a publish that did not read back = %d:\n%s", code, errs)
	}
}

func TestRigPreExistingAnnotatesTheRecordedFail(t *testing.T) {
	f := newRigFixture(t)
	f.vars(map[string]string{rig.VarTest: countCmd("full")})
	if code, _, _ := f.gate("test", "--pre-existing", "tk-trk"); code != 3 {
		t.Fatalf("--pre-existing with nothing recorded = %d, want 3", code)
	}
	t.Setenv("CHECK_RC", "1")
	if code, _, _ := f.gate("test"); code != 1 {
		t.Fatal("the failing run did not fail")
	}
	code, out, errs := f.gate("test", "--pre-existing", "tk-trk", "--publish-bead", "tk-work")
	if code != 0 || !strings.Contains(out, `"disposition":"pre-existing","tracker":"tk-trk"`) || !strings.Contains(errs, "published to tk-work") {
		t.Fatalf("--pre-existing = %d, stdout %q:\n%s", code, out, errs)
	}
	code, _, errs = f.gate("test")
	if code != 1 || !strings.Contains(errs, "pre-existing, carried by tk-trk") {
		t.Fatalf("a run over the annotated fail = %d:\n%s", code, errs)
	}
	eqRuns(t, f.runs(), "full")

	t.Setenv("CHECK_RC", "0")
	if code, _, _ := f.gate("test", "--force"); code != 0 {
		t.Fatal("--force did not pass")
	}
	if code, _, errs := f.gate("test", "--pre-existing", "tk-trk"); code != 3 || !strings.Contains(errs, "no fail is recorded") {
		t.Fatalf("--pre-existing over a pass = %d:\n%s", code, errs)
	}
}

func TestRigNothingDeclaredIsAPassThatRanNothing(t *testing.T) {
	f := newRigFixture(t)
	f.vars(map[string]string{rig.VarAffected: countCmd("affected")})

	// An empty diff selects no subset, and the rig declares no full suite.
	code, _, errs := f.gate("test", "--affected", "--publish-bead", "tk-work")
	if code != 0 || !strings.Contains(errs, "nothing to run") || !strings.Contains(errs, "published to tk-work") {
		t.Fatalf("run = %d:\n%s", code, errs)
	}
	eqRuns(t, f.runs())
	r := f.record(rig.CheckTest, f.head())
	if r == nil || r.Result != rig.ResultPass || r.Method != rig.MethodNone || r.Command != "" {
		t.Fatalf("record = %+v, want a pass with method none", r)
	}
	if code, out, _ := f.gate("test", "--check"); code != 0 || !strings.Contains(out, `"method":"none"`) {
		t.Fatalf("--check = %d, %q", code, out)
	}
	// A record of nothing run is worked out again, so a command the rig
	// declares later runs.
	f.vars(map[string]string{rig.VarTest: countCmd("full")})
	if code, _, errs := f.gate("test"); code != 0 {
		t.Fatalf("run after declaring = %d:\n%s", code, errs)
	}
	eqRuns(t, f.runs(), "full")
	// Nothing to run never replaces the record of a run, and does not publish
	// it as this call's answer.
	f.vars(map[string]string{})
	code, _, errs = f.gate("test", "--force", "--publish-bead", "tk-other")
	if code != 0 || !strings.Contains(errs, "stands, and nothing was published") {
		t.Fatalf("--force with nothing declared = %d:\n%s", code, errs)
	}
	if n := len(f.gcCalls("bd update tk-other")); n != 0 {
		t.Fatalf("the kept record was published %d times", n)
	}
	if r := f.record(rig.CheckTest, f.head()); r == nil || r.Method != rig.MethodFull {
		t.Fatalf("record = %+v, want the full run kept", r)
	}
}

func TestRigLintAndTypecheckAreRecordedPerCommit(t *testing.T) {
	f := newRigFixture(t)
	f.vars(map[string]string{rig.VarLint: countCmd("lint"), rig.VarTypecheck: countCmd("typecheck")})
	for _, check := range []string{rig.CheckLint, rig.CheckTypecheck} {
		if code, _, errs := f.gate(check); code != 0 {
			t.Fatalf("%s = %d:\n%s", check, code, errs)
		}
		if r := f.record(check, f.head()); r == nil || r.Check != check || r.Method != rig.MethodFull {
			t.Fatalf("%s record = %+v", check, r)
		}
		if code, _, _ := f.gate(check); code != 0 {
			t.Fatalf("recorded %s failed", check)
		}
	}
	eqRuns(t, f.runs(), "lint", "typecheck")
	// Lint may be scoped by the diff, so its pass does not cross to another
	// commit with the same tree.
	f.git("commit", "-q", "--allow-empty", "-m", "same tree")
	if code, _, _ := f.gate("lint"); code != 0 {
		t.Fatal("lint at the same tree failed")
	}
	eqRuns(t, f.runs(), "lint", "typecheck", "lint")
	if f.record(rig.CheckTest, f.head()) != nil {
		t.Fatal("a lint run wrote a test record")
	}
}

func TestRigSetupAndBuildRunAndRecordNothing(t *testing.T) {
	f := newRigFixture(t)
	f.vars(map[string]string{rig.VarSetup: countCmd("setup"), rig.VarBuild: countCmd("build")})
	if code, _, errs := f.gate("setup"); code != 0 {
		t.Fatalf("setup = %d:\n%s", code, errs)
	}
	t.Setenv("CHECK_RC", "2")
	if code, _, _ := f.gate("build"); code != 1 {
		t.Fatalf("a failing build = %d, want 1", code)
	}
	t.Setenv("CHECK_RC", "0")
	if code, _, _ := f.gate("build"); code != 0 {
		t.Fatal("build did not pass")
	}
	eqRuns(t, f.runs(), "setup", "build", "build")
	if _, err := os.Stat(filepath.Join(f.repo, ".git", "gc-rig-checks")); !os.IsNotExist(err) {
		t.Fatalf("setup or build wrote to the record store: %v", err)
	}
	// setup runs in a tree it is about to change, so a dirty one is no reason
	// to refuse it.
	f.write("node_modules.txt", "x\n")
	if code, _, _ := f.gate("setup"); code != 0 {
		t.Fatal("setup refused a dirty tree")
	}
	f.vars(map[string]string{})
	if code, _, errs := f.gate("build"); code != 0 || !strings.Contains(errs, "nothing to run: build_command is not set") {
		t.Fatalf("build with nothing declared = %d:\n%s", code, errs)
	}
}

func TestRigNamedByGCRigMustOwnTheCheckout(t *testing.T) {
	f := newRigFixture(t)
	f.vars(map[string]string{rig.VarTest: countCmd("full")})
	other := newRigFixtureRepo(t)
	t.Setenv("GC_RIG_ROOT", other)
	code, _, errs := f.gate("test")
	if code != 4 || !strings.Contains(errs, "not to rig testrig's clone") {
		t.Fatalf("a checkout of another clone = %d:\n%s", code, errs)
	}
	eqRuns(t, f.runs())
	// --rig names the rig outright, so the session's own rig is not consulted.
	if code, _, errs := f.gate("test", "--rig", "testrig"); code != 0 {
		t.Fatalf("--rig = %d:\n%s", code, errs)
	}
	if got := f.gcCalls("formula show"); len(got) != 1 || got[0] != "formula show mol-polecat-work --rig testrig --json" {
		t.Fatalf("formula show calls = %q", got)
	}
	t.Setenv("GC_RIG_ROOT", f.repo)
	if code, _, errs := f.gate("test", "--force"); code != 0 {
		t.Fatalf("the rig's own clone = %d:\n%s", code, errs)
	}
}

// newRigFixtureRepo makes a second scratch clone, for a rig root that is not
// the checkout's.
func newRigFixtureRepo(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	for _, args := range [][]string{{"init", "-q", "-b", "main"}, {"commit", "-q", "--allow-empty", "-m", "x"}} {
		if out, err := exec.Command("git", append([]string{"-C", dir}, args...)...).CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
	return dir
}

// A SIGTERM during the run reaches the command's group, and the gate exits
// 128+15 with nothing recorded. The test's own Notify keeps a build without the
// relay from killing the test binary.
func TestRigStoppedBySignalRecordsNothing(t *testing.T) {
	held := make(chan os.Signal, 4)
	signal.Notify(held, syscall.SIGTERM)
	defer signal.Stop(held)
	f := newRigFixture(t)
	ready := filepath.Join(f.stub, "ready")
	f.vars(map[string]string{rig.VarTest: `touch "` + ready + `"; sleep 30 & wait $!`})
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
	code, _, errs := f.gate("test")
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
		{"test", "--check", "--force"},
		{"test", "--check", "--pre-existing", "tk-x"},
		{"test", "--force", "--pre-existing", "tk-x"},
		{"test", "--check", "--publish-bead", "tk-x"},
		{"test", "--base", "main"},
		{"test", "--affected", "--affected"},
		{"test", "--publish-bead"},
		{"test", "--pre-existing", ""},
		{"test", "--timeout", "soon"},
		{"test", "--timeout", "-1s"},
		{"test", "--frobnicate"},
		{"lint", "--affected"},
		{"typecheck", "--base", "main"},
		{"setup", "--check"},
		{"build", "--publish-bead", "tk-x"},
		{"setup", "--force"},
	} {
		var out, errb bytes.Buffer
		if code := Rig(args, &out, &errb); code != 2 {
			t.Errorf("gctk rig %v = %d, want 2; stderr:\n%s", args, code, errb.String())
		}
	}
	var out bytes.Buffer
	if code := Rig([]string{"--help"}, &out, &bytes.Buffer{}); code != 0 || !strings.Contains(out.String(), "usage:") {
		t.Errorf("--help = %d, %q", code, out.String())
	}
}
