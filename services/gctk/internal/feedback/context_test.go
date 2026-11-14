package feedback_test

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

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/feedback"
)

// stall writes name in dir as a command that stalls the way a command waiting
// on the network does: it starts a child that holds the command's output, as
// git fetching in a partial clone holds pr-post.sh's, records its process
// group in the file it returns once it has started, and waits on the child.
func stall(t *testing.T, dir, name string) string {
	t.Helper()
	group := filepath.Join(dir, name+".group")
	t.Setenv("STUB_GROUP", group)
	body := "#!/bin/sh\nsleep 30 &\necho $$ > \"$STUB_GROUP.tmp\" && mv \"$STUB_GROUP.tmp\" \"$STUB_GROUP\"\nwait\n"
	if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o755); err != nil {
		t.Fatal(err)
	}
	return group
}

// stallOnPath puts a stalling name first on PATH and returns the file it
// records its process group in.
func stallOnPath(t *testing.T, name string) string {
	t.Helper()
	dir := t.TempDir()
	group := stall(t, dir, name)
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	return group
}

// endsWithItsContext runs call, whose command is a stub that records its
// process group in group, and ends the call's context with cancel once the
// stub has started. The call then returns the cancellation promptly, the stub
// has ended and been waited on by the time it does, and the stub's whole
// process group, the child holding its output among it, is gone.
func endsWithItsContext(t *testing.T, group string, cancel context.CancelFunc, call func() error) {
	t.Helper()
	done := make(chan error, 1)
	go func() { done <- call() }()
	for began := time.Now(); ; time.Sleep(10 * time.Millisecond) {
		if _, err := os.Stat(group); err == nil {
			break
		}
		select {
		case err := <-done:
			t.Fatalf("the call returned %v before its command started", err)
		default:
		}
		if time.Since(began) > 10*time.Second {
			t.Fatal("the call's command did not start")
		}
	}
	raw, err := os.ReadFile(group)
	if err != nil {
		t.Fatal(err)
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(raw)))
	if err != nil {
		t.Fatalf("the stub wrote %q as its process group", raw)
	}
	cancel()
	select {
	case err := <-done:
		if !errors.Is(err, context.Canceled) {
			t.Errorf("the call returned %v, want its context's cancellation", err)
		}
	case <-time.After(1500 * time.Millisecond):
		_ = syscall.Kill(-pid, syscall.SIGKILL)
		t.Fatal("the call was still running 1.5s after its context ended")
	}
	// A call that returned when its context ended, while its command was
	// still being stopped, would find the stub here.
	if err := syscall.Kill(pid, 0); !errors.Is(err, syscall.ESRCH) {
		t.Errorf("the stub %d had not ended when the call returned (signal 0: %v)", pid, err)
	}
	// The child the stub started stays in the group until it is reaped.
	gone := time.Now().Add(5 * time.Second)
	for syscall.Kill(-pid, 0) == nil {
		if time.Now().After(gone) {
			_ = syscall.Kill(-pid, syscall.SIGKILL)
			t.Fatalf("the command's process group %d outlived the call", pid)
		}
		time.Sleep(20 * time.Millisecond)
	}
}

// The gc that names the pack's scripts directory ends with the caller's
// context.
func TestScriptsDirContextStopsItsGCWhenTheContextEnds(t *testing.T) {
	t.Setenv("GCTK_SCRIPTS_DIR", "")
	group := stallOnPath(t, "gc")
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	endsWithItsContext(t, group, cancel, func() error {
		_, err := feedback.ScriptsDirContext(ctx)
		return err
	})
}

// The load ends with the caller's context, and a stop that killed bash alone
// would leave the child that holds pr-post.sh's output, and the load waiting
// on it.
func TestLoadContextStopsPrPostWhenTheContextEnds(t *testing.T) {
	scripts, checkout := t.TempDir(), t.TempDir()
	group := stall(t, scripts, "pr-post.sh")
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	endsWithItsContext(t, group, cancel, func() error {
		_, err := feedback.LoadContext(ctx, scripts, checkout)
		return err
	})
}

// A rule loaded with a context applies the definition within it: each jq it
// runs ends when the context does.
func TestARuleLoadedWithAContextStopsItsJQWhenTheContextEnds(t *testing.T) {
	t.Setenv("GC_RIG_ROOT", "")
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	r, err := feedback.LoadContext(ctx, scripts(t), checkout(t, ""))
	if err != nil {
		t.Fatal(err)
	}
	group := stallOnPath(t, "jq")
	endsWithItsContext(t, group, cancel, func() error {
		_, err := r.Reviews(self, cutover, []feedback.Review{
			{ID: 1, Author: "operator", Body: "rename this", State: "COMMENTED", SubmittedAt: "2026-11-12T01:00:00Z"},
		})
		return err
	})
}

// A load with no context, the one `gctk pr status` and the landing order make,
// runs pr-post.sh in gctk's own process group. The order runner stops a
// landing pass that outlives its timeout by a signal to gctk's group, and a
// terminal delivers Ctrl-C the same way, so the load stops with gctk.
func TestLoadRunsInTheCallersProcessGroup(t *testing.T) {
	scripts := t.TempDir()
	group := filepath.Join(scripts, "group")
	t.Setenv("STUB_GROUP", group)
	if err := os.WriteFile(filepath.Join(scripts, "pr-post.sh"), []byte("ps -o pgid= -p $$ > \"$STUB_GROUP\"\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	if _, err := feedback.Load(scripts, t.TempDir()); err == nil {
		t.Fatal("the stub printed no definition, yet the load answered one")
	}
	raw, err := os.ReadFile(group)
	if err != nil {
		t.Fatalf("pr-post.sh did not run: %v", err)
	}
	if got, want := strings.TrimSpace(string(raw)), strconv.Itoa(syscall.Getpgrp()); got != want {
		t.Errorf("pr-post.sh ran in process group %s, want gctk's own, %s", got, want)
	}
}
