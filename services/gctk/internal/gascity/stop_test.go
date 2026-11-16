package gascity

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

// pidIn reads the pid a process wrote to path, once it is there.
func pidIn(t *testing.T, path string) int {
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

// A script that ends inside its bound reports its own exit, and one its
// context stopped ends with every process in its group: the script and its
// children get SIGTERM, which the git a script runs handles by removing its
// lock files, and a child that outlives SIGTERM is sent SIGKILL once StopGrace
// is spent, before the call returns.
func TestAScriptItsContextStoppedEndsWithEveryProcessInItsGroup(t *testing.T) {
	g := StopGrace
	StopGrace = time.Second
	t.Cleanup(func() { StopGrace = g })
	scripts := t.TempDir()
	marks := t.TempDir()
	term, ready, child := filepath.Join(marks, "script.term"), filepath.Join(marks, "script.ready"), filepath.Join(marks, "child.pid")
	for name, text := range map[string]string{
		"exits.sh": "#!/bin/sh\necho done\nexit 3\n",
		// stalls.sh marks $SCRIPT_READY once its trap is set and it forks
		// nothing more.
		"stalls.sh": `#!/bin/sh
sh -c 'trap "" TERM; echo $$ > "$1"; exec sleep 30 >/dev/null 2>&1' _ "$CHILD_PID" &
trap ': > "$SCRIPT_TERM"; exit 143' TERM
sleep 30 &
: > "$SCRIPT_READY"
wait $!
`,
	} {
		if err := os.WriteFile(filepath.Join(scripts, name), []byte(text), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("SCRIPT_TERM", term)
	t.Setenv("SCRIPT_READY", ready)
	t.Setenv("CHILD_PID", child)
	c := &City{bin: "gc", scriptsDir: scripts}
	ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
	defer cancel()
	if res := c.ScriptContext(ctx, "exits.sh"); res.Err != nil || res.Code != 3 || res.Tail() != "done" {
		t.Fatalf("a script that ended inside its bound read %+v", res)
	}

	ctx, cancel = context.WithCancel(context.Background())
	defer cancel()
	done := make(chan Result, 1)
	go func() { done <- c.ScriptContext(ctx, "stalls.sh") }()
	pid := pidIn(t, child)
	for deadline := time.Now().Add(10 * time.Second); ; time.Sleep(10 * time.Millisecond) {
		if _, err := os.Stat(ready); err == nil {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("the script never set its trap")
		}
	}
	cancel()
	stop := time.Now()
	var res Result
	select {
	case res = <-done:
	case <-time.After(20 * time.Second):
		t.Fatal("the script did not return once its context ended")
	}
	took := time.Since(stop)
	if res.Code != -1 || !errors.Is(res.Err, context.Canceled) || !strings.Contains(res.Err.Error(), "stopped, with every process it started") {
		t.Fatalf("a script its context stopped read %+v", res)
	}
	if took < StopGrace || took > 10*time.Second {
		t.Errorf("the script returned %s after its context ended, want once the %s grace of the child that ignores SIGTERM was spent", took, StopGrace)
	}
	if _, err := os.Stat(term); err != nil {
		t.Error("the script got no SIGTERM it could handle")
	}
	for deadline := time.Now().Add(5 * time.Second); !errors.Is(syscall.Kill(pid, 0), syscall.ESRCH); time.Sleep(10 * time.Millisecond) {
		if time.Now().After(deadline) {
			t.Fatal("the child that ignores SIGTERM outlived the script")
		}
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
