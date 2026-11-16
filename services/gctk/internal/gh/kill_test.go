package gh

import (
	"errors"
	"os"
	"os/exec"
	"syscall"
	"testing"
)

// darwin's kill(2) to a group does not reach a child whose fork is under way
// as it runs, so one SIGKILL can leave a process of the group running. The
// stop sends SIGKILL again until the group is empty, so a process the first
// one missed is gone once the stop returns, and a group already gone reads as
// a process that is done.
func TestAKillThatMissesAProcessKillsAgain(t *testing.T) {
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
		if sig == syscall.SIGKILL && !missed {
			// The process this SIGKILL missed.
			missed = true
			return nil
		}
		return send(pgid, sig)
	}
	if err := killGroup(pgid); err != nil {
		t.Fatalf("the kill read %v", err)
	}
	if err := syscall.Kill(-pgid, 0); !errors.Is(err, syscall.ESRCH) {
		t.Fatalf("a process the first SIGKILL missed outlived the stop: kill(-%d, 0) read %v", pgid, err)
	}
	if err := killGroup(pgid); !errors.Is(err, os.ErrProcessDone) {
		t.Fatalf("the kill of a group already gone read %v, want os.ErrProcessDone", err)
	}
}
