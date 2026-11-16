package git

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

// stalledSSH is an ssh that never answers: it handles SIGTERM as git does,
// leaving a mark, and starts a child that ignores SIGTERM and writes its pid,
// so only a SIGKILL to the group ends that child. It marks $SSH_READY once its
// trap is set and it forks nothing more.
const stalledSSH = `#!/bin/sh
sh -c 'trap "" TERM; echo $$ > "$1"; exec sleep 30 >/dev/null 2>&1' _ "$CHILD_PID" &
trap ': > "$SSH_TERM"; exit 143' TERM
sleep 30 &
: > "$SSH_READY"
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

// waitFor waits for a process to make the file at path.
func waitFor(t *testing.T, path string) {
	t.Helper()
	for deadline := time.Now().Add(10 * time.Second); time.Now().Before(deadline); time.Sleep(10 * time.Millisecond) {
		if _, err := os.Stat(path); err == nil {
			return
		}
	}
	t.Fatalf("nothing made %s", path)
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
	ssh := filepath.Join(marks, "ssh")
	term, ready, child := filepath.Join(marks, "ssh.term"), filepath.Join(marks, "ssh.ready"), filepath.Join(marks, "child.pid")
	if err := os.WriteFile(ssh, []byte(stalledSSH), 0o755); err != nil {
		t.Fatal(err)
	}
	// GIT_SSH_COMMAND outranks GIT_SSH and core.sshCommand.
	t.Setenv("GIT_SSH_COMMAND", ssh)
	t.Setenv("SSH_TERM", term)
	t.Setenv("SSH_READY", ready)
	t.Setenv("CHILD_PID", child)
	gitIn(t, dir, "remote", "add", "origin", "ssh://git.invalid/acme/widgets.git")

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	go func() { done <- FetchTipContext(ctx, dir, "main") }()
	pid := pidOf(t, child)
	waitFor(t, ready)
	cancel()
	stop := time.Now()
	var err error
	select {
	case err = <-done:
	case <-time.After(20 * time.Second):
		t.Fatal("the fetch did not return once its context ended")
	}
	took := time.Since(stop)
	if !errors.Is(err, context.Canceled) || !strings.Contains(err.Error(), "stopped, with every process it started") {
		t.Fatalf("a fetch its context stopped read %v", err)
	}
	if took < StopGrace || took > 10*time.Second {
		t.Errorf("the fetch returned %s after its context ended, want once the %s grace of the child that ignores SIGTERM was spent", took, StopGrace)
	}
	if _, err := os.Stat(term); err != nil {
		t.Error("the ssh carrying the fetch got no SIGTERM it could handle")
	}
	if !goneWithin(pid, 5*time.Second) {
		t.Error("the child that ignores SIGTERM outlived the fetch")
	}
}

// darwin's kill(2) to a group does not reach a child whose fork is under way
// as it runs, so one SIGKILL can leave a process of the group running. A stop
// sends SIGKILL again until the group is empty, so a process the first one
// missed is gone once the stop returns.
func TestAStopKillsAgainAProcessTheFirstSIGKILLMissed(t *testing.T) {
	g := StopGrace
	StopGrace = 100 * time.Millisecond
	t.Cleanup(func() { StopGrace = g })
	cmd := exec.Command("sleep", "30")
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	pgid := cmd.Process.Pid
	go func() { _ = cmd.Wait() }()
	t.Cleanup(func() { _ = syscall.Kill(-pgid, syscall.SIGKILL) })
	send := signalGroup
	t.Cleanup(func() { signalGroup = send })
	missed := false
	signalGroup = func(pgid int, sig syscall.Signal) error {
		switch {
		case sig == syscall.SIGTERM:
			// A process that ignores SIGTERM.
			return nil
		case sig == syscall.SIGKILL && !missed:
			// The process this SIGKILL missed.
			missed = true
			return nil
		}
		return send(pgid, sig)
	}
	if err := stopGroup(pgid); err != nil {
		t.Fatalf("the stop read %v", err)
	}
	if !missed {
		t.Fatal("the stop sent no SIGKILL")
	}
	if err := syscall.Kill(-pgid, 0); !errors.Is(err, syscall.ESRCH) {
		t.Fatalf("a process the first SIGKILL missed outlived the stop: kill(-%d, 0) read %v", pgid, err)
	}
}
