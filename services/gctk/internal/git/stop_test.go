package git

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

// stalledSSH is an ssh that never answers: it handles SIGTERM as git does,
// leaving a mark, and starts a child that ignores SIGTERM and writes its pid,
// so only a SIGKILL to the group ends that child.
const stalledSSH = `#!/bin/sh
sh -c 'trap "" TERM; echo $$ > "$1"; exec sleep 30 >/dev/null 2>&1' _ "$CHILD_PID" &
trap 'touch "$SSH_TERM"; exit 143' TERM
sleep 30 &
wait $!
`

// pidOf reads the pid a process wrote to path, once it is there.
func pidOf(t *testing.T, path string) int {
	t.Helper()
	for deadline := time.Now().Add(10 * time.Second); time.Now().Before(deadline); time.Sleep(10 * time.Millisecond) {
		if b, err := os.ReadFile(path); err == nil {
			if pid, err := strconv.Atoi(strings.TrimSpace(string(b))); err == nil && pid > 0 {
				return pid
			}
		}
	}
	t.Fatalf("no pid appeared in %s", path)
	return 0
}

// goneWithin reports whether kill(2) finds no process with pid within d.
func goneWithin(pid int, d time.Duration) bool {
	for deadline := time.Now().Add(d); ; time.Sleep(10 * time.Millisecond) {
		if errors.Is(syscall.Kill(pid, 0), syscall.ESRCH) {
			return true
		}
		if time.Now().After(deadline) {
			return false
		}
	}
}

// A fetch whose ssh does not answer is stopped once its context ends: git and
// the ssh carrying it get SIGTERM, which git handles by removing its lock
// files, and a process of git's group that outlives SIGTERM is sent SIGKILL
// once StopGrace is spent, before the fetch returns.
func TestAFetchItsContextStoppedEndsWithEveryProcessInItsGroup(t *testing.T) {
	g := StopGrace
	StopGrace = time.Second
	t.Cleanup(func() { StopGrace = g })
	dir := repo(t)
	marks := t.TempDir()
	ssh, term, child := filepath.Join(marks, "ssh"), filepath.Join(marks, "ssh.term"), filepath.Join(marks, "child.pid")
	if err := os.WriteFile(ssh, []byte(stalledSSH), 0o755); err != nil {
		t.Fatal(err)
	}
	// GIT_SSH_COMMAND outranks GIT_SSH and core.sshCommand.
	t.Setenv("GIT_SSH_COMMAND", ssh)
	t.Setenv("SSH_TERM", term)
	t.Setenv("CHILD_PID", child)
	gitIn(t, dir, "remote", "add", "origin", "ssh://git.invalid/acme/widgets.git")

	start := time.Now()
	ctx, cancel := context.WithTimeout(context.Background(), 300*time.Millisecond)
	defer cancel()
	err := FetchTipContext(ctx, dir, "main")
	took := time.Since(start)
	if !errors.Is(err, context.DeadlineExceeded) || !strings.Contains(err.Error(), "stopped, with every process it started") {
		t.Fatalf("a fetch its context stopped read %v", err)
	}
	if took < StopGrace || took > 10*time.Second {
		t.Errorf("the fetch returned %s after it started, want once the %s grace of the child that ignores SIGTERM was spent", took, StopGrace)
	}
	if _, err := os.Stat(term); err != nil {
		t.Error("the ssh carrying the fetch got no SIGTERM it could handle")
	}
	if !goneWithin(pidOf(t, child), 5*time.Second) {
		t.Error("the child that ignores SIGTERM outlived the fetch")
	}
}
