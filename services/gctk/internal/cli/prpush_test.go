package cli

import (
	"bytes"
	"context"
	"errors"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"slices"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/git"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
)

// The sitting's push reads the store through the stub the bead holds tests use,
// and pushes through the pack's own branch-push.sh against a real origin. The
// proof's rules and the order of the draft and the push are pr's own tests, on
// the fakes.

// pushStore is a bead on the pending record that waits on a conversation in
// progress under the sitting rig/gc-toolkit.st-conv.
const pushStore = `[
 {"id":"st-1","status":"blocked","assignee":"rig/refinery","issue_type":"task",
  "metadata":{"merge_result":"pull_request_pending","branch":"polecat/st-1","pr_url":"https://github.com/acme/widgets/pull/7"},
  "dependencies":[{"id":"st-conv","dependency_type":"blocks","status":"in_progress"}]},
 {"id":"st-conv","status":"in_progress","issue_type":"task","assignee":"rig/gc-toolkit.st-conv"}
]`

// asSession makes this session the one whose alias is alias.
func asSession(t *testing.T, alias string) {
	t.Helper()
	for _, k := range []string{"GC_SESSION_NAME", "GC_SESSION_ID", "GC_AGENT"} {
		t.Setenv(k, "")
	}
	t.Setenv("GC_ALIAS", alias)
}

func TestPRPushUsage(t *testing.T) {
	for name, args := range map[string][]string{
		"no bead":        {"pr", "push"},
		"no holder":      {"pr", "push", "st-1"},
		"a blank holder": {"pr", "push", "st-1", "--held-by", " "},
	} {
		t.Run(name, func(t *testing.T) {
			if code := Run(args, "", io.Discard, io.Discard); code != 1 {
				t.Fatalf("exit %d, want the usage exit 1", code)
			}
		})
	}
}

// A push needs the pack's pusher, so a caller that names no scripts directory
// stops before anything is read or changed.
func TestPRPushNeedsThePacksPusherBeforeItReadsTheStore(t *testing.T) {
	asSession(t, "rig/gc-toolkit.st-conv")
	t.Setenv("GCTK_SCRIPTS_DIR", "")
	log := filepath.Join(t.TempDir(), "calls")
	t.Setenv("STUB_DB_LOG", log)
	_, errs, code := landingCmd(t, pushStore, "https://github.com/acme/widgets.git",
		"pr", "push", "st-1", "--held-by", "st-conv", "--db", t.TempDir())
	if code != 1 || !strings.Contains(errs, "GCTK_SCRIPTS_DIR names no pack scripts directory") {
		t.Fatalf("exit %d, stderr %q, want exit 1 naming GCTK_SCRIPTS_DIR", code, errs)
	}
	if _, err := os.Stat(log); err == nil {
		t.Fatal("the store was read before the pusher was found")
	}
}

// --check proves the holding from the store and changes nothing, and names
// the session that does not hold the conversation.
func TestPRPushCheckProvesTheHoldingFromTheStore(t *testing.T) {
	asSession(t, "rig/gc-toolkit.st-conv")
	out, errs, code := landingCmd(t, pushStore, "https://github.com/acme/widgets.git",
		"pr", "push", "st-1", "--held-by", "st-conv", "--check", "--db", t.TempDir())
	if code != 0 || !strings.Contains(out, "conversation st-conv holds its branch polecat/st-1, and nothing else writes it") {
		t.Fatalf("exit %d, stdout %q, stderr %q, want the holding", code, out, errs)
	}
	asSession(t, "rig/gc-toolkit.st-other")
	_, errs, code = landingCmd(t, pushStore, "https://github.com/acme/widgets.git",
		"pr", "push", "st-1", "--held-by", "st-conv", "--check", "--db", t.TempDir())
	if code != 3 || !strings.Contains(errs, "so this session does not hold it") {
		t.Fatalf("exit %d, stderr %q, want the refusal exit 3", code, errs)
	}
}

// Each stop the push or its proof makes has its own exit.
func TestPRPushExitsByWhatStoppedIt(t *testing.T) {
	for want, err := range map[int]error{
		3: &pr.PushRefusal{Bead: "st-1", Why: "it has no blocks edge onto conversation st-conv"},
		4: &pr.Moved{Branch: "polecat/st-1", Why: "it moved"},
		2: errors.New("gh: error connecting to api.github.com"),
	} {
		if got := pushFailed("st-1", err, io.Discard); got != want {
			t.Errorf("%v exits %d, want %d", err, got, want)
		}
	}
	if got := pushFailed("st-1", &pr.DraftRefusal{Bead: "st-1", Why: "the PR is not open"}, io.Discard); got != 3 {
		t.Errorf("a PR that is not open exits %d, want 3", got)
	}
}

// A checkout whose origin is not the PR's repository is refused before
// GitHub is asked anything or anything is pushed, though the rig's clone names
// the PR's repository: the push is bound to where the checkout itself fetches
// and pushes.
func TestPRPushRefusesACheckoutOfAnotherRepository(t *testing.T) {
	hermeticGit(t)
	asSession(t, "rig/gc-toolkit.st-conv")
	const b = "polecat/st-1"
	root := t.TempDir()
	fork := filepath.Join(root, "fork.git")
	treeGit(t, root, "init", "-q", "--bare", fork)
	seed := filepath.Join(root, "seed")
	treeGit(t, root, "clone", "-q", fork, seed)
	treeGit(t, seed, "checkout", "-q", "-b", b)
	before := treeCommit(t, seed, "a.txt", "one\n")
	treeGit(t, seed, "push", "-q", "origin", b)
	tr := filepath.Join(root, "tree")
	treeGit(t, root, "clone", "-q", fork, tr)
	treeGit(t, tr, "checkout", "-q", "--detach", "origin/"+b)
	treeCommit(t, tr, "a.txt", "two\n")
	url := treeGit(t, tr, "remote", "get-url", "origin")

	bin := t.TempDir()
	calls := filepath.Join(t.TempDir(), "gh-calls")
	if err := os.WriteFile(filepath.Join(bin, "gh"), []byte("#!/bin/sh\nprintf 'gh %s\\n' \"$*\" >> \"$GH_CALLS\"\nexit 1\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("GH_CALLS", calls)
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Chdir(tr)
	_, errs, code := landingCmd(t, pushStore, "https://github.com/acme/widgets.git",
		"pr", "push", "st-1", "--held-by", "st-conv", "--db", t.TempDir())
	want := "the checkout's origin is not the PR's repository, github.com/acme/widgets: it fetches from and pushes to " + url + ", which names no repository on a host"
	if code != 3 || !strings.Contains(errs, want) {
		t.Fatalf("exit %d, stderr %q, want the refusal exit 3 saying %q", code, errs, want)
	}
	if raw, err := os.ReadFile(calls); err == nil {
		t.Fatalf("GitHub was asked before the refusal:\n%s", raw)
	}
	if got := treeGit(t, fork, "rev-parse", b); got != before {
		t.Fatalf("the fork's %s is %s, want %s, which nothing replaced", b, got, before)
	}
}

// hermeticGit runs git with no global or system config, so no rewrite a host
// configures moves a URL, and points GCTK_SCRIPTS_DIR at the pack's own
// scripts.
func hermeticGit(t *testing.T) {
	t.Helper()
	cfg := filepath.Join(t.TempDir(), "gitconfig")
	if err := os.WriteFile(cfg, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("GIT_CONFIG_GLOBAL", cfg)
	t.Setenv("GIT_CONFIG_NOSYSTEM", "1")
	scripts, err := filepath.Abs("../../../../assets/scripts")
	if err != nil {
		t.Fatal(err)
	}
	t.Setenv("GCTK_SCRIPTS_DIR", scripts)
}

// treeGit runs git in dir with no global or system config and a fixed identity,
// and returns its trimmed output.
func treeGit(t *testing.T, dir string, args ...string) string {
	t.Helper()
	c := exec.Command("git", append([]string{"-C", dir}, args...)...)
	c.Env = append(os.Environ(), "GIT_AUTHOR_NAME=t", "GIT_AUTHOR_EMAIL=t@example.com",
		"GIT_COMMITTER_NAME=t", "GIT_COMMITTER_EMAIL=t@example.com")
	out, err := c.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
	return strings.TrimSpace(string(out))
}

// treeCommit commits a change to file in dir and returns the commit.
func treeCommit(t *testing.T, dir, file, text string) string {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, file), []byte(text), 0o644); err != nil {
		t.Fatal(err)
	}
	treeGit(t, dir, "add", file)
	treeGit(t, dir, "commit", "-q", "-m", "change "+file)
	return treeGit(t, dir, "rev-parse", "HEAD")
}

// The checkout reads where its origin fetches from and pushes to as git
// resolves it, pushes its HEAD through the pack's branch-push.sh, reads work no
// commit holds, and takes nothing onto a branch that holds a commit it does
// not, until it holds that commit too.
func TestTheSittingsCheckoutPushesThroughThePacksPusher(t *testing.T) {
	hermeticGit(t)
	const b = "polecat/st-1"
	root := t.TempDir()
	origin := filepath.Join(root, "origin.git")
	treeGit(t, root, "init", "-q", "--bare", origin)
	other := filepath.Join(root, "other")
	treeGit(t, root, "clone", "-q", origin, other)
	treeGit(t, other, "checkout", "-q", "-b", b)
	treeCommit(t, other, "a.txt", "one\n")
	treeGit(t, other, "push", "-q", "origin", b)
	tr := filepath.Join(root, "tree")
	treeGit(t, root, "clone", "-q", origin, tr)
	treeGit(t, tr, "checkout", "-q", "--detach", "origin/"+b)

	s, err := newSittingTree(tr)
	if err != nil {
		t.Fatal(err)
	}
	url := treeGit(t, tr, "remote", "get-url", "origin")
	if fetch, push, err := s.Origin(); err != nil || !slices.Equal(fetch, []string{url}) || !slices.Equal(push, []string{url}) {
		t.Fatalf("the checkout's origin read %q, %q, %v, want %s for both", fetch, push, err, url)
	}
	treeGit(t, tr, "config", "url.git@github.com:fork/.pushInsteadOf", url)
	if fetch, push, err := s.Origin(); err != nil || !slices.Equal(fetch, []string{url}) || !slices.Equal(push, []string{"git@github.com:fork/"}) {
		t.Fatalf("with a pushInsteadOf the checkout's origin read %q, %q, %v, want the push rewritten", fetch, push, err)
	}
	treeGit(t, tr, "config", "--remove-section", "url.git@github.com:fork/")
	if left, err := s.Uncommitted(); err != nil || left != "" {
		t.Fatalf("a clean checkout lists %q, %v", left, err)
	}
	mine := treeCommit(t, tr, "a.txt", "two\n")
	if err := os.WriteFile(filepath.Join(tr, "loose.txt"), []byte("x\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if left, err := s.Uncommitted(); err != nil || !strings.Contains(left, "loose.txt") {
		t.Fatalf("work no commit holds lists %q, %v", left, err)
	}
	if err := os.Remove(filepath.Join(tr, "loose.txt")); err != nil {
		t.Fatal(err)
	}
	if err := s.Push(t.Context(), b); err != nil {
		t.Fatalf("the push read %v", err)
	}
	if got := treeGit(t, origin, "rev-parse", b); got != mine {
		t.Fatalf("origin's %s is %s, want the checkout's %s", b, got, mine)
	}

	treeGit(t, other, "pull", "-q", "origin", b)
	theirs := treeCommit(t, other, "b.txt", "theirs\n")
	treeGit(t, other, "push", "-q", "origin", b)
	treeCommit(t, tr, "c.txt", "mine\n")
	var moved *pr.Moved
	if err := s.Push(t.Context(), b); !errors.As(err, &moved) {
		t.Fatalf("a push onto a branch that moved read %v", err)
	}
	if got := treeGit(t, origin, "rev-parse", b); got != theirs {
		t.Fatalf("origin's %s is %s, want the other writer's %s kept", b, got, theirs)
	}
	treeGit(t, tr, "merge", "-q", "--no-edit", "origin/"+b)
	if err := s.Push(t.Context(), b); err != nil {
		t.Fatalf("the push after the merge read %v", err)
	}
	if got, head := treeGit(t, origin, "rev-parse", b), treeGit(t, tr, "rev-parse", "HEAD"); got != head {
		t.Fatalf("origin's %s is %s, want the checkout's %s", b, got, head)
	}
}

// shortLockWait sets how long a writer waits for the record lock, and so how
// long a push may hold it, half of that, and the grace a stopped fetch or
// script has between SIGTERM and SIGKILL, for one test.
func shortLockWait(t *testing.T, wait, grace time.Duration) {
	t.Helper()
	w, g, s := recordLockWait, git.StopGrace, gascity.StopGrace
	recordLockWait, git.StopGrace, gascity.StopGrace = wait, grace, grace
	t.Cleanup(func() { recordLockWait, git.StopGrace, gascity.StopGrace = w, g, s })
}

// lockFreeIn reports whether nothing holds the record lock of the store whose
// .beads directory is db.
func lockFreeIn(db string) bool {
	release, err := record.Lock(db, 0)
	if err != nil {
		return false
	}
	release()
	return true
}

// goneWithin reports whether kill(2) finds no process at target within d: a
// pid, or a process group as its negated pgid. A pid that has not been read
// names nothing.
func goneWithin(target int, d time.Duration) bool {
	if target == 0 {
		return false
	}
	for deadline := time.Now().Add(d); ; time.Sleep(20 * time.Millisecond) {
		if errors.Is(syscall.Kill(target, 0), syscall.ESRCH) {
			return true
		}
		if time.Now().After(deadline) {
			return false
		}
	}
}

// stalledGH is a gh that writes its pid to $GH_PID and never answers, with a
// child that ignores SIGTERM, so only the stop's SIGKILL to its group ends it.
// The child holds none of gh's output, so the wait for gh ends once gh itself
// has exited, and only the stop keeps the child from outliving the call.
const stalledGH = "#!/bin/sh\necho $$ > \"$GH_PID\"\n(trap '' TERM; exec sleep 30 >/dev/null 2>&1) &\nsleep 30\n"

// stalledPush readies a push whose read of the PR GitHub does not answer: the
// store stub holds pushStore, the rig's clone and the checkout both name the
// PR's repository, and the gh on PATH is stalledGH. It returns the verb's
// arguments, the store's .beads directory and the file gh writes its pid to.
func stalledPush(t *testing.T) (args []string, db, ghPid string) {
	t.Helper()
	hermeticGit(t)
	asSession(t, "rig/gc-toolkit.st-conv")
	bin := t.TempDir()
	ghPid = filepath.Join(t.TempDir(), "gh.pid")
	for name, text := range map[string]string{"gc": storeStub, "gh": stalledGH} {
		if err := os.WriteFile(filepath.Join(bin, name), []byte(text), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STUB_STORE", pushStore)
	t.Setenv("GH_PID", ghPid)
	root := t.TempDir()
	for _, dir := range []string{"rig", "tree"} {
		treeGit(t, root, "init", "-q", dir)
		treeGit(t, filepath.Join(root, dir), "remote", "add", "origin", "https://github.com/acme/widgets.git")
	}
	treeCommit(t, filepath.Join(root, "tree"), "a.txt", "one\n")
	t.Setenv("GC_RIG_ROOT", filepath.Join(root, "rig"))
	t.Chdir(filepath.Join(root, "tree"))
	db = t.TempDir()
	return []string{"pr", "push", "st-1", "--held-by", "st-conv", "--db", db}, db, ghPid
}

// A push whose call does not answer is stopped once the push has held the
// record lock for half the time a writer waits for it: the call's whole
// process group ends, the lock is free, and the verb exits 2 saying why.
func TestPRPushStopsACallThatDoesNotAnswerAndLetsTheLockGo(t *testing.T) {
	args, db, ghPid := stalledPush(t)
	shortLockWait(t, 2*time.Second, 500*time.Millisecond)
	var errs bytes.Buffer
	start := time.Now()
	code := Run(args, "", io.Discard, &errs)
	if took := time.Since(start); took > 15*time.Second {
		t.Errorf("the push returned after %s, past its 1s under the lock and its grace", took)
	}
	if code != 2 || !strings.Contains(errs.String(), "the push held the store's record lock for 1s, the most it may") {
		t.Fatalf("exit %d, stderr %q, want exit 2 naming the push's time under the lock", code, errs.String())
	}
	if !lockFreeIn(db) {
		t.Error("the record lock was still held after the push returned")
	}
	if !goneWithin(-readPid(ghPid), 5*time.Second) {
		t.Error("a process of gh's group outlived the push")
	}
}

// A SIGTERM that reaches the push stops the call still running with every
// process it started, and the push exits as a SIGTERM would, once the lock is
// free.
func TestPRPushPassesASIGTERMOnToTheCallStillRunning(t *testing.T) {
	args, db, ghPid := stalledPush(t)
	shortLockWait(t, time.Minute, 500*time.Millisecond)
	// The test's own relay, so a push that does not take the signal fails this
	// test rather than ending the test binary.
	held := make(chan os.Signal, 1)
	signal.Notify(held, syscall.SIGTERM)
	t.Cleanup(func() { signal.Stop(held) })
	exited := make(chan int, 1)
	go func() { exited <- Run(args, "", io.Discard, io.Discard) }()
	if !appears(ghPid, 10*time.Second) {
		t.Fatal("the push never reached GitHub")
	}
	if err := syscall.Kill(os.Getpid(), syscall.SIGTERM); err != nil {
		t.Fatal(err)
	}
	select {
	case code := <-exited:
		if code != 128+int(syscall.SIGTERM) {
			t.Errorf("a push sent SIGTERM exited %d, want %d", code, 128+int(syscall.SIGTERM))
		}
	case <-time.After(15 * time.Second):
		t.Fatal("the push did not end on the SIGTERM this process received")
	}
	if !lockFreeIn(db) {
		t.Error("the record lock was still held after the push exited")
	}
	if !goneWithin(-readPid(ghPid), 5*time.Second) {
		t.Error("a process of gh's group outlived the push the SIGTERM stopped")
	}
}

// The checkout's fetch and its push each end with the processes they started
// once the push's context does: a fetch whose ssh does not answer, and a
// pusher that does not return.
func TestTheSittingsCheckoutStopsAFetchOrAPushThatDoesNotAnswer(t *testing.T) {
	hermeticGit(t)
	shortLockWait(t, time.Minute, 500*time.Millisecond)
	const b = "polecat/st-1"
	stall := "#!/bin/sh\necho $$ > \"$STALL_PID\"\n(trap '' TERM; exec sleep 30 >/dev/null 2>&1) &\nsleep 30\n"
	for name, c := range map[string]struct {
		setup func(t *testing.T, tree string)
		// gone is what must be gone once the push returns, from the pid the
		// stalled process wrote: the ssh itself, or the pusher's group.
		gone func(pid int) int
	}{
		"a fetch whose ssh does not answer": {
			setup: func(t *testing.T, tree string) {
				ssh := filepath.Join(t.TempDir(), "ssh")
				if err := os.WriteFile(ssh, []byte("#!/bin/sh\necho $$ > \"$STALL_PID\"\nexec sleep 30\n"), 0o755); err != nil {
					t.Fatal(err)
				}
				// GIT_SSH_COMMAND outranks GIT_SSH and core.sshCommand.
				t.Setenv("GIT_SSH_COMMAND", ssh)
				treeGit(t, tree, "remote", "add", "origin", "ssh://git.invalid/acme/widgets.git")
			},
			gone: func(pid int) int { return pid },
		},
		"a pusher that does not return": {
			setup: func(t *testing.T, tree string) {
				origin := filepath.Join(t.TempDir(), "origin.git")
				treeGit(t, tree, "init", "-q", "--bare", origin)
				treeGit(t, tree, "remote", "add", "origin", origin)
				treeGit(t, tree, "push", "-q", "origin", "HEAD:refs/heads/"+b)
				scripts := t.TempDir()
				if err := os.WriteFile(filepath.Join(scripts, "branch-push.sh"), []byte(stall), 0o755); err != nil {
					t.Fatal(err)
				}
				t.Setenv("GCTK_SCRIPTS_DIR", scripts)
			},
			gone: func(pid int) int { return -pid },
		},
	} {
		t.Run(name, func(t *testing.T) {
			tree := t.TempDir()
			treeGit(t, tree, "init", "-q")
			treeCommit(t, tree, "a.txt", "one\n")
			pid := filepath.Join(t.TempDir(), "pid")
			t.Setenv("STALL_PID", pid)
			c.setup(t, tree)
			s, err := newSittingTree(tree)
			if err != nil {
				t.Fatal(err)
			}
			ctx, cancel := context.WithTimeout(t.Context(), 300*time.Millisecond)
			defer cancel()
			start := time.Now()
			err = s.Push(ctx, b)
			if took := time.Since(start); took > 10*time.Second {
				t.Errorf("the push returned after %s, long past its context's end", took)
			}
			if !errors.Is(err, context.DeadlineExceeded) || !strings.Contains(err.Error(), "stopped, with every process it started") {
				t.Fatalf("a push that did not answer read %v", err)
			}
			if !goneWithin(c.gone(readPid(pid)), 5*time.Second) {
				t.Error("the stalled process outlived the push")
			}
		})
	}
}
