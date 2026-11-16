package gh_test

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

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
)

// A call its context stopped kills gh's whole process group at once, a child
// that ignores SIGTERM among it, and returns an error that wraps the context's
// cause.
func TestACallItsContextStoppedKillsGhsWholeGroup(t *testing.T) {
	bin, marks := t.TempDir(), t.TempDir()
	child := filepath.Join(marks, "child.pid")
	stub := `#!/bin/sh
sh -c 'trap "" TERM; echo $$ > "$1"; exec sleep 30 >/dev/null 2>&1' _ "$CHILD_PID" &
sleep 30
`
	if err := os.WriteFile(filepath.Join(bin, "gh"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("CHILD_PID", child)
	cause := errors.New("the push held the store's record lock for 1s, the most it may")
	ctx, cancel := context.WithCancelCause(context.Background())
	defer cancel(nil)
	time.AfterFunc(300*time.Millisecond, func() { cancel(cause) })
	start := time.Now()
	_, err := gh.NewContext(ctx, "github.com").PullRequest("acme/widgets", 7)
	if took := time.Since(start); took > 5*time.Second {
		t.Errorf("the call returned %s after it started, long after its context ended", took)
	}
	if !errors.Is(err, cause) || !strings.Contains(err.Error(), "gh: stopped, with every process it started") {
		t.Fatalf("a call its context stopped read %v", err)
	}
	b, err := os.ReadFile(child)
	pid, _ := strconv.Atoi(strings.TrimSpace(string(b)))
	if err != nil || pid == 0 {
		t.Fatalf("gh's child wrote no pid: %v", err)
	}
	for deadline := time.Now().Add(5 * time.Second); !errors.Is(syscall.Kill(pid, 0), syscall.ESRCH); time.Sleep(10 * time.Millisecond) {
		if time.Now().After(deadline) {
			t.Fatal("gh's child outlived the call")
		}
	}
}
