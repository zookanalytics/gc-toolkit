// Package host is gctk's adapter to the machine it runs on: the processes it
// starts and signals, what the process table says of them, and its loopback
// ports (docs/gctk-architecture.md, "The adapters"). A domain reaches them only
// through Host. Local is the machine gctk runs on, and host/fake is one in
// memory, so a domain's rules about processes and ports are tested in Go with
// no process started.
package host

import (
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"slices"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

// Host is the machine as one process on it sees it.
type Host interface {
	// Pid is this process's id.
	Pid() int
	// Notify relays the signals named to c in place of their default action,
	// and Ignore has this process ignore them, as os/signal's functions of the
	// same names do.
	Notify(c chan<- os.Signal, sig ...os.Signal)
	Ignore(sig ...os.Signal)

	// Start starts a process as s says, as a child of this process. The
	// process gets its output and no other file this process has open.
	Start(s Spec) (Child, error)
	// Signal sends sig to the process pid, and SignalGroup sends it to every
	// process in the group pgid. Signal 0 sends nothing and says whether a
	// signal could be sent.
	Signal(pid int, sig syscall.Signal) error
	SignalGroup(pgid int, sig syscall.Signal) error

	// Proc reads a running process from the process table. It reports false
	// for a process the table does not name, and for one that has ended and
	// waits to be reaped.
	Proc(pid int) (Proc, bool)
	// Members lists the running processes in the group pgid. A read that
	// fails lists none.
	Members(pgid int) []int
	// GroupGone reports whether no running process is left in the group pgid.
	GroupGone(pgid int) bool

	// FreePort picks a loopback port that nothing listens on.
	FreePort() (int, error)
	// Answers reports whether something accepts a connection on the loopback
	// port.
	Answers(port int) bool
	// Listeners lists the processes that listen on the TCP port at an address
	// a connection to loopback reaches: a loopback address or every address.
	// One that listens on another address only, as a publisher's daemon
	// listens on the host's network address, is left out.
	Listeners(port int) ([]int, error)
}

// Spec is a process to start.
type Spec struct {
	// Argv is the program, found on PATH, and its arguments.
	Argv []string
	// Dir is its working directory, and empty means this process's.
	Dir string
	// Env holds variables, each NAME=value, set on top of this process's
	// environment, which the process otherwise gets whole.
	Env []string
	// Out takes its standard output and its standard error, and nil discards
	// them. Its standard input reads nothing.
	Out io.Writer
	// Relay has the process write into a pipe that this process copies into
	// Out, so the process needs no access to where Out leads, and dies at its
	// next write once this process is gone. Child.Relayed says when the copy
	// is done.
	Relay bool
	// Session starts the process in a session of its own, so it leads a
	// process group of its own, which outlives this process. Without it the
	// process joins this process's group.
	Session bool
	// Sandbox, when set, runs the process inside the sandbox a demo capture
	// runs in, from Dir, which it needs.
	Sandbox *Sandbox
}

// Sandbox is the sandbox the pack's demo capture runs a command in, which
// demo_engine_sandboxed in Lib composes: the process reads and writes its
// working directory, reaches no loopback port but Port, signals no process
// outside the sandbox, and gets none of the variables that point a command at
// the city.
type Sandbox struct {
	// Lib is the file that defines it, the pack's demo-engine-lib.sh.
	Lib string
	// Port is the one loopback port the process may reach.
	Port int
	// Prog is the name the sandbox's messages start with.
	Prog string
}

// Child is a process Start started.
type Child interface {
	// Pid is its process id.
	Pid() int
	// Wait waits for it to end, reaps it, and returns its status as a shell
	// reports it: its exit code, or 128 plus the signal that ended it.
	Wait() int
	// Relayed is closed once the relay of a Spec with Relay has copied all the
	// output it gets, which is once every process that holds the pipe has
	// ended. It is closed from the start for a Spec without Relay.
	Relayed() <-chan struct{}
}

// Proc is a running process, as the process table names it.
type Proc struct {
	// Group is its process group.
	Group int
	// Parent is its parent's pid.
	Parent int
	// Started is its start, in a form that stays the same for as long as it
	// runs, so a pid the kernel reused, which names a process that started
	// later, is told from it. Empty when the table does not say.
	Started string
}

// Local returns the machine gctk runs on, as this process sees it.
func Local() Host { return local{} }

type local struct{}

func (local) Pid() int { return os.Getpid() }

func (local) Notify(c chan<- os.Signal, sig ...os.Signal) { signal.Notify(c, sig...) }

func (local) Ignore(sig ...os.Signal) { signal.Ignore(sig...) }

// sandboxed sources the file it is given first and runs the rest, the port,
// the directory and the command, through demo_engine_sandboxed.
const sandboxed = `. "$1" || exit 126; shift; demo_engine_sandboxed "$@"`

func (local) Start(s Spec) (Child, error) {
	if len(s.Argv) == 0 {
		return nil, errors.New("no program to start")
	}
	argv, env := s.Argv, s.Env
	if b := s.Sandbox; b != nil {
		if s.Dir == "" {
			return nil, errors.New("a sandboxed process needs a directory to run in")
		}
		argv = append([]string{"bash", "-c", sandboxed, b.Prog, b.Lib, strconv.Itoa(b.Port), s.Dir}, argv...)
		env = append(slices.Clone(env), "PROG="+b.Prog)
	}
	cmd := exec.Command(argv[0], argv[1:]...)
	cmd.Dir = s.Dir
	if len(env) > 0 {
		cmd.Env = append(os.Environ(), env...)
	}
	if s.Session {
		cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	}
	c := &child{cmd: cmd, relayed: make(chan struct{})}
	if !s.Relay || s.Out == nil {
		cmd.Stdout, cmd.Stderr = s.Out, s.Out
		if err := cmd.Start(); err != nil {
			return nil, err
		}
		close(c.relayed)
		return c, nil
	}
	pr, pw, err := os.Pipe()
	if err != nil {
		return nil, err
	}
	cmd.Stdout, cmd.Stderr = pw, pw
	err = cmd.Start()
	pw.Close()
	if err != nil {
		pr.Close()
		return nil, err
	}
	go func() {
		_, _ = io.Copy(s.Out, pr)
		pr.Close()
		close(c.relayed)
	}()
	return c, nil
}

type child struct {
	cmd     *exec.Cmd
	relayed chan struct{}
	once    sync.Once
	status  int
}

func (c *child) Pid() int { return c.cmd.Process.Pid }

func (c *child) Wait() int {
	c.once.Do(func() {
		err := c.cmd.Wait()
		c.status = exitStatus(c.cmd.ProcessState, err)
	})
	return c.status
}

func (c *child) Relayed() <-chan struct{} { return c.relayed }

// exitStatus is a finished command's status as a shell reports it: its exit
// code, or 128 plus the signal that ended it.
func exitStatus(ps *os.ProcessState, err error) int {
	if ps == nil {
		return 127
	}
	if ws, ok := ps.Sys().(syscall.WaitStatus); ok && ws.Signaled() {
		return 128 + int(ws.Signal())
	}
	if code := ps.ExitCode(); code >= 0 {
		return code
	}
	if err != nil {
		return 1
	}
	return 0
}

func (local) Signal(pid int, sig syscall.Signal) error {
	if pid <= 0 {
		return fmt.Errorf("pid %d names no one process: %w", pid, syscall.EINVAL)
	}
	return syscall.Kill(pid, sig)
}

// SignalGroup refuses group 1 and below, which kill(2) reads as every process
// the caller may signal, or the caller's own group.
func (local) SignalGroup(pgid int, sig syscall.Signal) error {
	if pgid <= 1 {
		return fmt.Errorf("pgid %d names no one process group: %w", pgid, syscall.EINVAL)
	}
	return syscall.Kill(-pgid, sig)
}

func (local) Proc(pid int) (Proc, bool) {
	if pid <= 0 {
		return Proc{}, false
	}
	out, err := exec.Command("ps", "-o", "pgid=,ppid=,stat=", "-p", strconv.Itoa(pid)).Output()
	if err != nil {
		return Proc{}, false
	}
	f := strings.Fields(string(out))
	if len(f) < 3 || strings.HasPrefix(f[2], "Z") {
		return Proc{}, false
	}
	group, gerr := strconv.Atoi(f[0])
	parent, perr := strconv.Atoi(f[1])
	if gerr != nil || perr != nil {
		return Proc{}, false
	}
	return Proc{Group: group, Parent: parent, Started: started(pid)}, true
}

// started is a process's start: the starttime field of /proc/<pid>/stat where
// that exists, else ps's start time in the C locale and UTC.
func started(pid int) string {
	if b, err := os.ReadFile(fmt.Sprintf("/proc/%d/stat", pid)); err == nil {
		s := string(b)
		if i := strings.LastIndex(s, ") "); i >= 0 {
			if f := strings.Fields(s[i+2:]); len(f) > 19 {
				return f[19]
			}
		}
		return ""
	}
	cmd := exec.Command("ps", "-o", "lstart=", "-p", strconv.Itoa(pid))
	cmd.Env = append(os.Environ(), "LC_ALL=C", "TZ=UTC")
	out, err := cmd.Output()
	if err != nil {
		return ""
	}
	return strings.Join(strings.Fields(string(out)), " ")
}

// Members leaves out any member that has exited and waits to be reaped. ps
// runs in a group of its own, so it never lists itself among the group a
// member of it asks about.
func (local) Members(pgid int) []int {
	cmd := exec.Command("ps", "-A", "-o", "pgid=,pid=,stat=")
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	out, err := cmd.Output()
	if err != nil {
		return nil
	}
	var pids []int
	for _, line := range strings.Split(string(out), "\n") {
		f := strings.Fields(line)
		if len(f) < 3 || f[0] != strconv.Itoa(pgid) || strings.HasPrefix(f[2], "Z") {
			continue
		}
		if p, err := strconv.Atoi(f[1]); err == nil {
			pids = append(pids, p)
		}
	}
	return pids
}

// GroupGone asks kill first: it answers ESRCH for an empty group, and on
// darwin EPERM for one whose only members have exited and wait to be reaped.
func (h local) GroupGone(pgid int) bool {
	err := h.SignalGroup(pgid, 0)
	if errors.Is(err, syscall.ESRCH) {
		return true
	}
	return errors.Is(err, syscall.EPERM) && len(h.Members(pgid)) == 0
}

func (local) FreePort() (int, error) {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return 0, err
	}
	defer l.Close()
	return l.Addr().(*net.TCPAddr).Port, nil
}

func (local) Answers(port int) bool {
	c, err := net.DialTimeout("tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(port)), time.Second)
	if err != nil {
		return false
	}
	c.Close()
	return true
}

// Listeners reads the listeners through lsof.
func (local) Listeners(port int) ([]int, error) {
	out, err := exec.Command("lsof", "-nP", "-iTCP:"+strconv.Itoa(port), "-sTCP:LISTEN", "-F", "pn").Output()
	var ee *exec.ExitError
	if err != nil && !(errors.As(err, &ee) && len(out) == 0) {
		return nil, fmt.Errorf("lsof did not list the listeners on port %d: %v", port, err)
	}
	seen := map[int]bool{}
	var pids []int
	pid := 0
	for _, line := range strings.Split(string(out), "\n") {
		switch {
		case strings.HasPrefix(line, "p"):
			pid, _ = strconv.Atoi(line[1:])
		case strings.HasPrefix(line, "n") && pid > 0 && reachedFromLoopback(line[1:]) && !seen[pid]:
			seen[pid] = true
			pids = append(pids, pid)
		}
	}
	return pids, nil
}

// reachedFromLoopback reports whether a listening address, host:port as lsof
// names it, takes a connection to loopback.
func reachedFromLoopback(addr string) bool {
	host := addr
	if i := strings.LastIndex(addr, ":"); i >= 0 {
		host = addr[:i]
	}
	host = strings.Trim(host, "[]")
	switch host {
	case "*", "0.0.0.0", "::", "localhost", "::1":
		return true
	}
	return strings.HasPrefix(host, "127.")
}
