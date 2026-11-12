package host

import (
	"bytes"
	"errors"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

// These tests start real processes, so they pin what host/fake stands in for:
// a process group that ends whole, a start that leads a session of its own
// with its caller's environment, listeners read through lsof, and a start
// inside the capture's sandbox.

// A helper process is this test binary, run again with GCTK_HOST_TEST_HELPER
// set: it sleeps until a signal ends it.
func TestMain(m *testing.M) {
	if os.Getenv("GCTK_HOST_TEST_HELPER") == "sleep" {
		time.Sleep(time.Minute)
		os.Exit(0)
	}
	os.Exit(m.Run())
}

func waitFor(bound time.Duration, cond func() bool) bool {
	deadline := time.Now().Add(bound)
	for !cond() {
		if time.Now().After(deadline) {
			return false
		}
		time.Sleep(50 * time.Millisecond)
	}
	return true
}

// stat is a process's state as ps names it.
func stat(pid int) string {
	out, _ := exec.Command("ps", "-o", "stat=", "-p", strconv.Itoa(pid)).Output()
	return strings.TrimSpace(string(out))
}

// environ is a process's environment as Gas City's orphan sweep reads it:
// /proc on Linux, ps on macOS, which reads it for a binary that is not one of
// Apple's.
func environ(pid int) string {
	if b, err := os.ReadFile("/proc/" + strconv.Itoa(pid) + "/environ"); err == nil {
		return strings.ReplaceAll(string(b), "\x00", "\n")
	}
	out, _ := exec.Command("ps", "eww", "-o", "command=", "-p", strconv.Itoa(pid)).Output()
	return strings.ReplaceAll(string(out), " ", "\n")
}

func TestStartInASessionOfItsOwnLeadsAGroupWithTheCallersEnvironment(t *testing.T) {
	for k, v := range map[string]string{"GCTK_HOST_TEST_HELPER": "sleep", "GC_SESSION_ID": "host-test-session",
		"GC_CITY_PATH": "/no/city", "GC_RUNTIME_EPOCH": "7"} {
		t.Setenv(k, v)
	}
	h := Local()
	c, err := h.Start(Spec{Argv: []string{os.Args[0], "-test.run=^$"}, Session: true})
	if err != nil {
		t.Fatal(err)
	}
	pid := c.Pid()
	t.Cleanup(func() { _ = h.SignalGroup(pid, syscall.SIGKILL); c.Wait() })
	if !waitFor(10*time.Second, func() bool { return strings.Contains(environ(pid), "GC_SESSION_ID=") }) {
		t.Fatalf("the process's environment never showed: %q", environ(pid))
	}
	p, ok := h.Proc(pid)
	if !ok || p.Group != pid || p.Parent != os.Getpid() || p.Started == "" {
		t.Errorf("Proc = %+v, %v: want it leading group %d, this process's child, with a start", p, ok, pid)
	}
	if s := stat(pid); !strings.Contains(s, "s") {
		t.Errorf("the process leads no session of its own: stat %q", s)
	}
	if me, _ := h.Proc(os.Getpid()); me.Group == pid {
		t.Error("the process is in its caller's group")
	}
	env := environ(pid)
	for _, kv := range []string{"GC_SESSION_ID=host-test-session", "GC_CITY_PATH=/no/city", "GC_RUNTIME_EPOCH=7"} {
		if !strings.Contains(env, kv) {
			t.Errorf("the process does not carry %s where the orphan sweep reads it", kv)
		}
	}
	if again, _ := h.Proc(pid); again.Started != p.Started {
		t.Errorf("the process's start reads %q, then %q", p.Started, again.Started)
	}

	if err := h.SignalGroup(pid, syscall.SIGTERM); err != nil {
		t.Fatal(err)
	}
	if code := c.Wait(); code != 128+int(syscall.SIGTERM) {
		t.Errorf("Wait = %d, want 143 for a process SIGTERM ended", code)
	}
	if _, ok := h.Proc(pid); ok || !h.GroupGone(pid) {
		t.Errorf("an ended process reads as running (%v), or its group as left (%v)", ok, !h.GroupGone(pid))
	}
}

func TestSignalGroupReachesEveryMemberAndAGroupEndsWhole(t *testing.T) {
	h := Local()
	c, err := h.Start(Spec{Argv: []string{"bash", "-c", `sleep 60 & (trap "" TERM; exec sleep 61) & wait`}, Session: true})
	if err != nil {
		t.Fatal(err)
	}
	pid := c.Pid()
	t.Cleanup(func() { _ = h.SignalGroup(pid, syscall.SIGKILL); c.Wait() })
	if !waitFor(10*time.Second, func() bool { return len(h.Members(pid)) == 3 }) {
		t.Fatalf("the group's members are %v, want the shell and its two sleeps", h.Members(pid))
	}
	members := h.Members(pid)
	if !slices.Contains(members, pid) {
		t.Errorf("the members %v leave out the group's leader, %d", members, pid)
	}
	for _, m := range members {
		if p, ok := h.Proc(m); !ok || p.Group != pid || (m != pid && p.Parent != pid) {
			t.Errorf("member %d reads as %+v, %v: want it in group %d, the leader's child", m, p, ok, pid)
		}
	}

	// SIGTERM ends the shell and the sleep that takes it, and leaves the one
	// that ignores it, which is no longer the shell's child.
	if err := h.SignalGroup(pid, syscall.SIGTERM); err != nil {
		t.Fatal(err)
	}
	if code := c.Wait(); code != 128+int(syscall.SIGTERM) {
		t.Errorf("the shell's status = %d, want 143", code)
	}
	if !waitFor(10*time.Second, func() bool { return len(h.Members(pid)) == 1 }) {
		t.Fatalf("after SIGTERM the members are %v, want the one that ignores it", h.Members(pid))
	}
	left := h.Members(pid)[0]
	if p, ok := h.Proc(left); !ok || p.Parent == pid {
		t.Errorf("the member left reads as %+v, %v: want it running, no longer the ended shell's child", p, ok)
	}
	if h.GroupGone(pid) {
		t.Error("the group reads as gone while a member runs")
	}

	if err := h.SignalGroup(pid, syscall.SIGKILL); err != nil {
		t.Fatal(err)
	}
	if !waitFor(10*time.Second, func() bool { return h.GroupGone(pid) }) {
		t.Fatalf("the group survived SIGKILL: %v", h.Members(pid))
	}
	if m := h.Members(pid); len(m) != 0 {
		t.Errorf("a group that ended lists members %v", m)
	}
	if err := h.SignalGroup(pid, 0); !errors.Is(err, syscall.ESRCH) {
		t.Errorf("signal 0 to an ended group = %v, want ESRCH", err)
	}
}

// An ended child that no one has reaped is still in the process table, as a
// zombie, and reads as ended.
func TestProcLeavesOutAProcessThatEndedAndWaitsToBeReaped(t *testing.T) {
	h := Local()
	c, err := h.Start(Spec{Argv: []string{"sh", "-c", "exit 3"}})
	if err != nil {
		t.Fatal(err)
	}
	pid := c.Pid()
	if !waitFor(10*time.Second, func() bool { return strings.HasPrefix(stat(pid), "Z") }) {
		t.Fatalf("the child never waited to be reaped: stat %q", stat(pid))
	}
	if p, ok := h.Proc(pid); ok {
		t.Errorf("a zombie reads as running: %+v", p)
	}
	me, _ := h.Proc(os.Getpid())
	if slices.Contains(h.Members(me.Group), pid) {
		t.Errorf("a zombie is among its group's members, %v", h.Members(me.Group))
	}
	if code := c.Wait(); code != 3 {
		t.Errorf("Wait = %d, want 3", code)
	}
}

func TestListenersAreTheProcessesLoopbackReachesOnThePort(t *testing.T) {
	if _, err := exec.LookPath("lsof"); err != nil {
		t.Skip("lsof is not on PATH, and the adapter reads listeners through it")
	}
	h := Local()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	port := l.Addr().(*net.TCPAddr).Port
	if !h.Answers(port) {
		t.Errorf("port %d, which this process listens on, does not answer", port)
	}
	if pids, err := h.Listeners(port); err != nil || !slices.Equal(pids, []int{os.Getpid()}) {
		t.Errorf("Listeners(%d) = %v, %v; want this process alone", port, pids, err)
	}
	free, err := h.FreePort()
	if err != nil {
		t.Fatal(err)
	}
	if pids, err := h.Listeners(free); err != nil || len(pids) != 0 || h.Answers(free) {
		t.Errorf("a free port: Listeners %v, %v, answers %v; want none, no error, and no answer", pids, err, h.Answers(free))
	}

	// A listener on an address loopback does not reach is left out.
	if ip := outsideAddress(); ip != nil {
		o, err := net.Listen("tcp", net.JoinHostPort(ip.String(), "0"))
		if err != nil {
			t.Fatal(err)
		}
		defer o.Close()
		op := o.Addr().(*net.TCPAddr).Port
		if pids, err := h.Listeners(op); err != nil || len(pids) != 0 {
			t.Errorf("a listener on %s only: Listeners %v, %v; want it left out", o.Addr(), pids, err)
		}
	}

	for addr, want := range map[string]bool{
		"127.0.0.1:80": true, "*:80": true, "[::1]:80": true, "[::]:80": true, "localhost:80": true,
		"100.64.1.2:80": false, "[fd7a:115c::1]:80": false, "192.168.1.5:80": false,
	} {
		if got := reachedFromLoopback(addr); got != want {
			t.Errorf("reachedFromLoopback(%q) = %v, want %v", addr, got, want)
		}
	}
}

// outsideAddress is an IPv4 address of this machine that is not loopback, or
// nil when it has none.
func outsideAddress() net.IP {
	addrs, err := net.InterfaceAddrs()
	if err != nil {
		return nil
	}
	for _, a := range addrs {
		if n, ok := a.(*net.IPNet); ok && n.IP.To4() != nil && !n.IP.IsLoopback() {
			return n.IP
		}
	}
	return nil
}

// sandboxStub stands in for demo-engine-lib.sh. Its demo_engine_sandboxed
// logs its port, its directory, PROG and its working directory, then runs the
// command in the directory, as the real one does inside the sandbox.
const sandboxStub = `demo_engine_sandboxed() {
  printf '%s|%s|%s|%s\n' "$1" "$2" "$PROG" "$(pwd -P)" > "$SANDBOX_LOG"
  local dir=$2
  shift 2
  cd "$dir" && exec "$@"
}
`

func TestStartInTheSandboxRunsTheCommandThroughTheLibraryFromItsDirectory(t *testing.T) {
	dir, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	work, lib, log := filepath.Join(dir, "work"), filepath.Join(dir, "lib.sh"), filepath.Join(dir, "sandbox.log")
	if err := os.Mkdir(work, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(lib, []byte(sandboxStub), 0o644); err != nil {
		t.Fatal(err)
	}
	h := Local()
	var out bytes.Buffer
	c, err := h.Start(Spec{
		Argv:    []string{"bash", "-c", `echo "out $PORT $(pwd -P)"; echo err >&2; exit 3`},
		Dir:     work,
		Env:     []string{"PORT=4242", "SANDBOX_LOG=" + log},
		Out:     &out,
		Relay:   true,
		Sandbox: &Sandbox{Lib: lib, Port: 4242, Prog: "gctk host test"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if code := c.Wait(); code != 3 {
		t.Errorf("Wait = %d, want the command's 3", code)
	}
	<-c.Relayed()
	if got, want := out.String(), "out 4242 "+work+"\nerr\n"; got != want {
		t.Errorf("relayed %q, want %q: the command's output and errors, through the relay", got, want)
	}
	b, _ := os.ReadFile(log)
	if got, want := strings.TrimSpace(string(b)), "4242|"+work+"|gctk host test|"+work; got != want {
		t.Errorf("the sandbox got %q, want %q: the port, the directory and the name its messages start with, from the directory", got, want)
	}

	if c, err := h.Start(Spec{Argv: []string{"true"}, Dir: work, Sandbox: &Sandbox{Lib: filepath.Join(dir, "none.sh"), Port: 4242}}); err != nil {
		t.Fatal(err)
	} else if code := c.Wait(); code != 126 {
		t.Errorf("a sandbox whose library cannot be read: Wait = %d, want 126", code)
	}
	if _, err := h.Start(Spec{Argv: []string{"true"}, Sandbox: &Sandbox{Lib: lib, Port: 4242}}); err == nil {
		t.Error("a sandboxed start with no directory started")
	}
}

// Group 1 and below would reach every process the caller may signal, or the
// caller's own group, so no signal goes there.
func TestSignalRefusesWhatNamesNoOneProcessOrGroup(t *testing.T) {
	h := Local()
	for _, pgid := range []int{1, 0, -5} {
		if err := h.SignalGroup(pgid, 0); !errors.Is(err, syscall.EINVAL) {
			t.Errorf("SignalGroup(%d) = %v, want EINVAL", pgid, err)
		}
	}
	for _, pid := range []int{0, -1} {
		if err := h.Signal(pid, 0); !errors.Is(err, syscall.EINVAL) {
			t.Errorf("Signal(%d) = %v, want EINVAL", pid, err)
		}
	}
}
