package rig

import (
	"bytes"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"
)

func shortGrace(t *testing.T) {
	t.Helper()
	old := StopGrace
	StopGrace = 300 * time.Millisecond
	t.Cleanup(func() { StopGrace = old })
}

func run(t *testing.T, command string, timeout time.Duration) (Outcome, string, string) {
	t.Helper()
	var out, errb bytes.Buffer
	o := Run(t.TempDir(), command, timeout, &out, &errb)
	return o, out.String(), errb.String()
}

func TestRunClassifiesTheCommandsStatus(t *testing.T) {
	shortGrace(t)
	dir := t.TempDir()
	noexec := filepath.Join(dir, "noexec.sh")
	if err := os.WriteFile(noexec, []byte("#!/bin/sh\nexit 0\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	cases := []struct {
		name    string
		command string
		kind    Kind
		code    int
		reason  string
	}{
		{"exit 0 is a pass", "true", Passed, 0, ""},
		{"exit 1 is a fail", "exit 1", Failed, 1, ""},
		{"exit 2 is a fail, whatever printed it", "echo broken >&2; exit 2", Failed, 2, ""},
		{"exit 125 is a fail", "exit 125", Failed, 125, ""},
		{"a command not found is a machine failure", "gctk-no-such-command-anywhere", Machine, 0, "not found (exit 127)"},
		{"a command not executable is a machine failure", noexec, Machine, 0, "could not be executed (exit 126)"},
		{"a shell ended by SIGKILL is a machine failure", "kill -KILL $$", Machine, 0, "killed by signal 9"},
		{"a child ended by a signal, reported as 128+N, is a machine failure", "sleep 30 & kill -KILL $!; wait $!", Machine, 0, "ended by signal 9 (exit 137)"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			o, _, _ := run(t, c.command, time.Minute)
			if o.Kind != c.kind || o.ExitCode != c.code || !strings.Contains(o.Reason, c.reason) {
				t.Fatalf("Run(%q) = %+v, want kind %d, exit %d, reason containing %q", c.command, o, c.kind, c.code, c.reason)
			}
		})
	}
}

func TestRunRunsInDirWithStdinClosedAndPassesOutputThrough(t *testing.T) {
	dir := t.TempDir()
	var out, errb bytes.Buffer
	o := Run(dir, `pwd -P; echo to-stderr >&2; if read -r line; then echo "read: $line"; else echo "stdin at EOF"; fi`, time.Minute, &out, &errb)
	if o.Kind != Passed {
		t.Fatalf("Run = %+v, want a pass", o)
	}
	want, _ := filepath.EvalSymlinks(dir)
	if got := out.String(); got != want+"\nstdin at EOF\n" {
		t.Fatalf("stdout = %q, want the run's directory and stdin at EOF", got)
	}
	if errb.String() != "to-stderr\n" {
		t.Fatalf("stderr = %q", errb.String())
	}
}

func TestRunHandsAFileToTheCommandAsItIs(t *testing.T) {
	f, err := os.Create(filepath.Join(t.TempDir(), "out"))
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	// The command leaves a child holding its stdout. Handed the file itself,
	// the run ends when the command does, not when the child does.
	dir := t.TempDir()
	start := time.Now()
	o := Run(dir, "echo hello; sleep 30 & echo $! > child.pid", time.Minute, f, f)
	elapsed := time.Since(start)
	if raw, err := os.ReadFile(filepath.Join(dir, "child.pid")); err == nil {
		if pid, err := strconv.Atoi(strings.TrimSpace(string(raw))); err == nil {
			_ = syscall.Kill(pid, syscall.SIGKILL)
		}
	}
	if o.Kind != Passed || elapsed > 5*time.Second {
		t.Fatalf("Run = %+v after %s, want a prompt pass", o, elapsed)
	}
	raw, _ := os.ReadFile(f.Name())
	if !strings.HasPrefix(string(raw), "hello\n") {
		t.Fatalf("the file holds %q", raw)
	}
}

func TestRunTimeoutStopsTheWholeGroup(t *testing.T) {
	shortGrace(t)
	dir := t.TempDir()
	pidFile := filepath.Join(dir, "child.pid")
	start := time.Now()
	var out bytes.Buffer
	o := Run(dir, `sleep 30 & echo $! > child.pid; wait`, 300*time.Millisecond, &out, &out)
	if o.Kind != Machine || !strings.Contains(o.Reason, "timed out after 300ms") {
		t.Fatalf("Run = %+v, want a timeout", o)
	}
	if time.Since(start) > 10*time.Second {
		t.Fatalf("the timed-out run took %s to return", time.Since(start))
	}
	raw, err := os.ReadFile(pidFile)
	if err != nil {
		t.Fatalf("the command never wrote its child's pid: %v", err)
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(raw)))
	if err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(5 * time.Second)
	for syscall.Kill(pid, 0) == nil {
		if time.Now().After(deadline) {
			_ = syscall.Kill(pid, syscall.SIGKILL)
			t.Fatalf("the command's child %d outlived the timeout", pid)
		}
		time.Sleep(20 * time.Millisecond)
	}
}

func TestRunKillsAGroupThatIgnoresSIGTERM(t *testing.T) {
	shortGrace(t)
	var out bytes.Buffer
	start := time.Now()
	o := Run(t.TempDir(), `trap '' TERM; sleep 30 & wait; sleep 30`, 200*time.Millisecond, &out, &out)
	if o.Kind != Machine || !strings.Contains(o.Reason, "timed out") {
		t.Fatalf("Run = %+v, want a timeout", o)
	}
	if time.Since(start) > 10*time.Second {
		t.Fatalf("a group that ignores SIGTERM held the run for %s", time.Since(start))
	}
}

func TestRunWithNoTimeoutWaits(t *testing.T) {
	o, _, _ := run(t, "sleep 0.3; exit 4", 0)
	if o.Kind != Failed || o.ExitCode != 4 || o.Duration < 300*time.Millisecond {
		t.Fatalf("Run with no timeout = %+v, want exit 4 after the sleep", o)
	}
}

// untilStopped keeps a command running until a stop reaches its shell. Each
// sleep is short because a stop can land just as the shell starts the next one.
// That sleep can miss the SIGTERM and stays in the group until it ends, so a
// long one would hold the stop open until the SIGKILL at the grace deadline. The
// loop ends after 30 seconds, so a build that never delivers the stop fails its
// test rather than hanging it.
const untilStopped = `while [ "$SECONDS" -lt 30 ]; do sleep 0.05 & wait $!; done`

// A SIGTERM to this process during the run reaches the command's group and
// returns Interrupted. The test's own Notify keeps a build without the relay
// from killing the test binary: such a build fails the assertions instead.
func TestRunRelaysSIGTERMToTheCommandsGroup(t *testing.T) {
	held := make(chan os.Signal, 4)
	signal.Notify(held, syscall.SIGTERM)
	defer signal.Stop(held)

	dir := t.TempDir()
	marker := filepath.Join(dir, "got-term")
	pidFile := filepath.Join(dir, "ready")
	go func() {
		deadline := time.Now().Add(10 * time.Second)
		for time.Now().Before(deadline) {
			if _, err := os.Stat(pidFile); err == nil {
				_ = syscall.Kill(os.Getpid(), syscall.SIGTERM)
				return
			}
			time.Sleep(10 * time.Millisecond)
		}
	}()
	var out bytes.Buffer
	o := Run(dir, `trap 'touch got-term; exit 143' TERM; echo $$ > ready; `+untilStopped, time.Minute, &out, &out)
	if o.Kind != Interrupted || o.Signal != syscall.SIGTERM {
		t.Fatalf("Run = %+v, want Interrupted by SIGTERM", o)
	}
	deadline := time.Now().Add(5 * time.Second)
	for {
		if _, err := os.Stat(marker); err == nil {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("the command's group never received the relayed SIGTERM")
		}
		time.Sleep(20 * time.Millisecond)
	}
}

// sigtermWhenReady sends this process SIGTERM once the command has written
// path. The caller's own Notify keeps a build without the relay from killing
// the test binary. The command writes path from its own shell, with `: > path`.
// A child such as touch can still be running when the file appears, and bash
// reports a foreground child that SIGTERM kills on stderr, which breaks a test
// of the command's exact output.
func sigtermWhenReady(path string) {
	go func() {
		deadline := time.Now().Add(10 * time.Second)
		for time.Now().Before(deadline) {
			if _, err := os.Stat(path); err == nil {
				_ = syscall.Kill(os.Getpid(), syscall.SIGTERM)
				return
			}
			time.Sleep(10 * time.Millisecond)
		}
	}()
}

// A relayed signal stops the command, and Run returns only once the command
// has stopped: what it writes while it stops is in the caller's writer by then,
// and nothing writes to that writer afterwards.
func TestRunReturnsFromARelayedSignalOnceTheCommandHasStopped(t *testing.T) {
	held := make(chan os.Signal, 4)
	signal.Notify(held, syscall.SIGTERM)
	defer signal.Stop(held)

	dir := t.TempDir()
	sigtermWhenReady(filepath.Join(dir, "ready"))
	var out bytes.Buffer
	o := Run(dir, `trap 'sleep 0.5; echo stopped; exit 143' TERM; : > ready; `+untilStopped, time.Minute, &out, &out)
	if o.Kind != Interrupted || o.Signal != syscall.SIGTERM {
		t.Fatalf("Run = %+v, want Interrupted by SIGTERM", o)
	}
	if got := out.String(); got != "stopped\n" {
		t.Fatalf("output when Run returned = %q, want the command's last line, written as it stopped", got)
	}
}

// A command that ignores the relayed SIGTERM is killed after StopGrace, as at
// a timeout.
func TestRunKillsARelayedGroupThatIgnoresSIGTERM(t *testing.T) {
	shortGrace(t)
	held := make(chan os.Signal, 4)
	signal.Notify(held, syscall.SIGTERM)
	defer signal.Stop(held)

	dir := t.TempDir()
	sigtermWhenReady(filepath.Join(dir, "ready"))
	start := time.Now()
	var out bytes.Buffer
	o := Run(dir, `trap '' TERM; echo $$ > ready; sleep 30 & wait; sleep 30`, time.Minute, &out, &out)
	if o.Kind != Interrupted || o.Signal != syscall.SIGTERM {
		t.Fatalf("Run = %+v, want Interrupted by SIGTERM", o)
	}
	if time.Since(start) > 10*time.Second {
		t.Fatalf("a group that ignores SIGTERM held the run for %s", time.Since(start))
	}
	raw, err := os.ReadFile(filepath.Join(dir, "ready"))
	if err != nil {
		t.Fatal(err)
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(raw)))
	if err != nil {
		t.Fatal(err)
	}
	// A member killed outright can stay in the group until it is reaped.
	deadline := time.Now().Add(5 * time.Second)
	for syscall.Kill(-pid, 0) == nil {
		if time.Now().After(deadline) {
			_ = syscall.Kill(-pid, syscall.SIGKILL)
			t.Fatalf("the command's group %d outlived the relayed stop", pid)
		}
		time.Sleep(20 * time.Millisecond)
	}
}

// outputFile is a file for a run's output. The CLI hands Run its own stdout
// and stderr, which are files, so the command writes to them directly and no
// pipe holds the wait open while a child the command started lives on.
func outputFile(t *testing.T) *os.File {
	t.Helper()
	f, err := os.Create(filepath.Join(t.TempDir(), "out"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = f.Close() })
	return f
}

// outlivesItsShell is a command whose shell exits on SIGTERM while the child
// it started ignores SIGTERM. The child writes its pid to child.pid once it
// ignores the signal.
const outlivesItsShell = `bash -c 'trap "" TERM; echo $$ > child.pid; exec sleep 60' & wait`

// requireExited fails the test unless the process whose pid is in path exits
// within a few seconds, and kills it if it has not.
func requireExited(t *testing.T, path string) {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("the command's child never wrote its pid, so the stop reached it before it ignored SIGTERM: %v", err)
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(raw)))
	if err != nil {
		t.Fatal(err)
	}
	// A child killed outright still answers until it has been reaped.
	deadline := time.Now().Add(5 * time.Second)
	for syscall.Kill(pid, 0) == nil {
		if time.Now().After(deadline) {
			_ = syscall.Kill(pid, syscall.SIGKILL)
			t.Fatalf("the command's child %d outlived the stop", pid)
		}
		time.Sleep(20 * time.Millisecond)
	}
}

// A stop is over when the command's group is, not when the command is: a child
// that ignores SIGTERM after its shell has exited is killed at the grace
// deadline, before Run returns.
func TestRunTimeoutKillsAChildThatOutlivesItsShell(t *testing.T) {
	shortGrace(t)
	dir := t.TempDir()
	f := outputFile(t)
	const timeout = time.Second
	start := time.Now()
	o := Run(dir, outlivesItsShell, timeout, f, f)
	elapsed := time.Since(start)
	if o.Kind != Machine || !strings.Contains(o.Reason, "timed out") {
		t.Fatalf("Run = %+v, want a timeout", o)
	}
	requireExited(t, filepath.Join(dir, "child.pid"))
	if elapsed < timeout+StopGrace {
		t.Fatalf("Run returned after %s, before the grace deadline at %s, while the command's child ignored SIGTERM", elapsed, timeout+StopGrace)
	}
}

func TestRunRelayedStopKillsAChildThatOutlivesItsShell(t *testing.T) {
	shortGrace(t)
	held := make(chan os.Signal, 4)
	signal.Notify(held, syscall.SIGTERM)
	defer signal.Stop(held)

	dir := t.TempDir()
	sigtermWhenReady(filepath.Join(dir, "child.pid"))
	f := outputFile(t)
	start := time.Now()
	o := Run(dir, outlivesItsShell, time.Minute, f, f)
	elapsed := time.Since(start)
	if o.Kind != Interrupted || o.Signal != syscall.SIGTERM {
		t.Fatalf("Run = %+v, want Interrupted by SIGTERM", o)
	}
	requireExited(t, filepath.Join(dir, "child.pid"))
	if elapsed < StopGrace {
		t.Fatalf("Run returned after %s, inside the %s grace, while the command's child ignored SIGTERM", elapsed, StopGrace)
	}
}

// A child still stopping after its shell has exited is waited for, and the
// stop ends when that child does, not at the grace deadline.
func TestRunStopWaitsForAChildThatIsStillStopping(t *testing.T) {
	old := StopGrace
	StopGrace = 20 * time.Second
	t.Cleanup(func() { StopGrace = old })
	held := make(chan os.Signal, 4)
	signal.Notify(held, syscall.SIGTERM)
	defer signal.Stop(held)

	dir := t.TempDir()
	sigtermWhenReady(filepath.Join(dir, "ready"))
	f := outputFile(t)
	start := time.Now()
	o := Run(dir, `bash -c 'trap "sleep 0.5; touch stopped; exit 0" TERM; : > ready; `+untilStopped+`' & wait`, time.Minute, f, f)
	elapsed := time.Since(start)
	if o.Kind != Interrupted || o.Signal != syscall.SIGTERM {
		t.Fatalf("Run = %+v, want Interrupted by SIGTERM", o)
	}
	if _, err := os.Stat(filepath.Join(dir, "stopped")); err != nil {
		t.Fatalf("Run returned after %s, before the command's child had finished stopping", elapsed)
	}
	if elapsed > StopGrace/2 {
		t.Fatalf("Run returned after %s, waiting toward the %s grace deadline for a group that had exited", elapsed, StopGrace)
	}
}

// slowWriter takes each write only after a delay, so a command's output is
// still being delivered for a while after its whole group has exited.
type slowWriter struct {
	mu    sync.Mutex
	delay time.Duration
	buf   bytes.Buffer
}

func (w *slowWriter) Write(p []byte) (int, error) {
	time.Sleep(w.delay)
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.buf.Write(p)
}

func (w *slowWriter) String() string {
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.buf.String()
}

// An empty group does not end a stop while the command's output is still
// being delivered to a writer that is not a file.
func TestRunStopWaitsForTheCommandsOutputToBeDelivered(t *testing.T) {
	held := make(chan os.Signal, 4)
	signal.Notify(held, syscall.SIGTERM)
	defer signal.Stop(held)

	dir := t.TempDir()
	sigtermWhenReady(filepath.Join(dir, "ready"))
	w := &slowWriter{delay: 500 * time.Millisecond}
	o := Run(dir, `trap 'echo stopped; exit 143' TERM; : > ready; `+untilStopped, time.Minute, w, w)
	if o.Kind != Interrupted || o.Signal != syscall.SIGTERM {
		t.Fatalf("Run = %+v, want Interrupted by SIGTERM", o)
	}
	if got := w.String(); got != "stopped\n" {
		t.Fatalf("output when Run returned = %q, want the line the command wrote as it stopped", got)
	}
}

func TestParsesTellsASyntaxErrorFromARunnableCommand(t *testing.T) {
	if ok, why := Parses("tools/run-tests.sh $(git diff --name-only origin/main...HEAD)"); !ok {
		t.Fatalf("a well-formed command did not parse: %s", why)
	}
	if ok, _ := Parses("gctk-no-such-command-anywhere --flag"); !ok {
		t.Fatal("a command that is not installed failed to parse; parsing runs nothing")
	}
	ok, why := Parses("echo (")
	if ok || !strings.Contains(why, "syntax error") {
		t.Fatalf("Parses(%q) = (%v, %q), want a syntax error", "echo (", ok, why)
	}
}
