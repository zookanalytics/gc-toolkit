package gascity

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
	term, child := filepath.Join(marks, "script.term"), filepath.Join(marks, "child.pid")
	for name, text := range map[string]string{
		"exits.sh": "#!/bin/sh\necho done\nexit 3\n",
		"stalls.sh": `#!/bin/sh
sh -c 'trap "" TERM; echo $$ > "$1"; exec sleep 30 >/dev/null 2>&1' _ "$CHILD_PID" &
trap 'touch "$SCRIPT_TERM"; exit 143' TERM
sleep 30 &
wait $!
`,
	} {
		if err := os.WriteFile(filepath.Join(scripts, name), []byte(text), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("SCRIPT_TERM", term)
	t.Setenv("CHILD_PID", child)
	c := &City{bin: "gc", scriptsDir: scripts}
	ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
	defer cancel()
	if res := c.ScriptContext(ctx, "exits.sh"); res.Err != nil || res.Code != 3 || res.Tail() != "done" {
		t.Fatalf("a script that ended inside its bound read %+v", res)
	}

	start := time.Now()
	ctx, cancel = context.WithTimeout(context.Background(), 300*time.Millisecond)
	defer cancel()
	res := c.ScriptContext(ctx, "stalls.sh")
	took := time.Since(start)
	if res.Code != -1 || !errors.Is(res.Err, context.DeadlineExceeded) || !strings.Contains(res.Err.Error(), "stopped, with every process it started") {
		t.Fatalf("a script its context stopped read %+v", res)
	}
	if took < StopGrace || took > 10*time.Second {
		t.Errorf("the script returned %s after it started, want once the %s grace of the child that ignores SIGTERM was spent", took, StopGrace)
	}
	if _, err := os.Stat(term); err != nil {
		t.Error("the script got no SIGTERM it could handle")
	}
	b, err := os.ReadFile(child)
	pid, _ := strconv.Atoi(strings.TrimSpace(string(b)))
	if err != nil || pid == 0 {
		t.Fatalf("the script's child wrote no pid: %v", err)
	}
	for deadline := time.Now().Add(5 * time.Second); !errors.Is(syscall.Kill(pid, 0), syscall.ESRCH); time.Sleep(10 * time.Millisecond) {
		if time.Now().After(deadline) {
			t.Fatal("the child that ignores SIGTERM outlived the script")
		}
	}
}
