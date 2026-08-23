package visit

// These tests drive a REAL subprocess — a tiny shell script standing in for
// gc-helm.sh — because what is being checked is exactly the exec boundary: that
// an exit code is reported as a result, that a killed run is reported as a
// timeout rather than as whatever exit code the kill produced, and that the
// argument arrives as one argv element however it is spelled.

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/server"
)

// writeScript drops an executable stand-in and points GC_HELM_OPEN_TOOL at it.
func writeScript(t *testing.T, body string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "gc-helm.sh")
	if err := os.WriteFile(path, []byte("#!/bin/sh\n"+body), 0o755); err != nil {
		t.Fatalf("write stub: %v", err)
	}
	t.Setenv("GC_HELM_OPEN_TOOL", path)
	return path
}

func TestNewResolvesTheConfiguredScript(t *testing.T) {
	path := writeScript(t, "exit 0\n")
	o, err := New("")
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	if o.Script() != path {
		t.Errorf("Script() = %q, want %q", o.Script(), path)
	}
}

// An unresolvable tool must be reported at construction, so the entrypoint can
// serve the board read-only and say why — rather than failing per request.
func TestNewReportsAnUnresolvableScript(t *testing.T) {
	t.Setenv("GC_HELM_OPEN_TOOL", filepath.Join(t.TempDir(), "absent.sh"))
	if _, err := New(""); err == nil {
		t.Fatal("New succeeded for a path that does not exist")
	}
	// A directory is not a tool either.
	t.Setenv("GC_HELM_OPEN_TOOL", t.TempDir())
	if _, err := New(""); err == nil {
		t.Fatal("New succeeded for a directory")
	}
}

// The verb, then the bead — as two argv elements, never one string.
func TestOpenPassesVerbAndBeadAsSeparateArgs(t *testing.T) {
	writeScript(t, `printf 'argc=%s a1=%s a2=%s\n' "$#" "$1" "$2"`)
	o, err := New("")
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	res, err := o.Open(context.Background(), "tk-abc12")
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	if want := "argc=2 a1=open a2=tk-abc12"; !strings.Contains(res.Stdout, want) {
		t.Errorf("stdout = %q, want it to contain %q", res.Stdout, want)
	}
}

// A non-zero exit is a RESULT: the HTTP layer maps the script's codes, so
// turning one into a Go error here would erase the distinction it maps on.
func TestOpenReportsExitCodesAsResults(t *testing.T) {
	for _, code := range []int{2, 3, 4, 9} {
		writeScript(t, "echo out; echo err >&2; exit "+strconv.Itoa(code)+"\n")
		o, err := New("")
		if err != nil {
			t.Fatalf("New: %v", err)
		}
		res, err := o.Open(context.Background(), "tk-abc12")
		if err != nil {
			t.Fatalf("exit %d returned a Go error: %v", code, err)
		}
		if res.ExitCode != code {
			t.Errorf("ExitCode = %d, want %d", res.ExitCode, code)
		}
		if !strings.Contains(res.Stdout, "out") || !strings.Contains(res.Stderr, "err") {
			t.Errorf("streams not captured separately: stdout=%q stderr=%q", res.Stdout, res.Stderr)
		}
	}
}

// A run killed by the deadline must classify as a timeout. Without the ctx.Err
// check first it would surface as a signal-shaped ExitError and be mapped as
// though the script had chosen that code.
func TestOpenClassifiesATimeout(t *testing.T) {
	writeScript(t, "sleep 5\n")
	o, err := New("")
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	o.timeout = 50 * time.Millisecond

	start := time.Now()
	res, err := o.Open(context.Background(), "tk-abc12")
	if !errors.Is(err, server.ErrToolTimeout) {
		t.Fatalf("err = %v, want ErrToolTimeout", err)
	}
	if res.ExitCode != 0 {
		t.Errorf("ExitCode = %d; a timeout must not be reported as a chosen exit code", res.ExitCode)
	}
	// Tight on purpose, and the reason is the bug this caught. The stub's child
	// sleeps 5s; before the process-group kill, Wait blocked on the pipe that
	// child still held and this returned after the FULL 5s despite the 50ms
	// deadline. A bound of 1s is far above the deadline and far below both the
	// sleep and killGrace, so it fails for the original bug AND for a regression
	// where only WaitDelay saves us because the group kill stopped working.
	if elapsed := time.Since(start); elapsed > time.Second {
		t.Errorf("took %s; the deadline did not reach the script's children", elapsed)
	}
}

// A caller that gives up must not be reported as the tool timing out.
func TestOpenPropagatesCallerCancellation(t *testing.T) {
	writeScript(t, "sleep 5\n")
	o, err := New("")
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	go func() {
		time.Sleep(20 * time.Millisecond)
		cancel()
	}()
	if _, err := o.Open(ctx, "tk-abc12"); err == nil {
		t.Fatal("a cancelled call returned no error")
	}
}

// A script that cannot be executed at all is a different failure from one that
// ran and failed: the operator's move is to fix the deployment, not the bead.
func TestOpenReportsAnUnrunnableScript(t *testing.T) {
	path := writeScript(t, "exit 0\n")
	if err := os.Chmod(path, 0o644); err != nil {
		t.Fatalf("chmod: %v", err)
	}
	o, err := New("")
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	if _, err := o.Open(context.Background(), "tk-abc12"); !errors.Is(err, server.ErrToolUnavailable) {
		t.Fatalf("err = %v, want ErrToolUnavailable", err)
	}
}

func TestTimeoutEnv(t *testing.T) {
	for _, tc := range []struct {
		set  string
		want time.Duration
	}{
		{"", DefaultTimeout},
		{"90s", 90 * time.Second},
		{"45", 45 * time.Second},
		{"0", DefaultTimeout},
		{"-5", DefaultTimeout},
		{"nonsense", DefaultTimeout},
	} {
		t.Setenv("GC_HELM_OPEN_TIMEOUT", tc.set)
		if got := timeout(); got != tc.want {
			t.Errorf("GC_HELM_OPEN_TIMEOUT=%q -> %s, want %s", tc.set, got, tc.want)
		}
	}
}
