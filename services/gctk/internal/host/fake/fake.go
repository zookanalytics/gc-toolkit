// Package fake is the host adapter's in-memory fake: a machine whose
// processes are goroutines, each running a program its test names, with a
// process table, process groups, signals and loopback ports
// (docs/gctk-architecture.md, "The adapters"). A test runs it inside a
// testing/synctest bubble, whose clock is fake, so the waits and graces a
// domain sets pass at once and in order. The fake keeps no clock of its own.
//
// A process ends when its program returns, with the code it returns, or when
// a signal it neither catches nor ignores reaches it, with 128 plus the
// signal, as a shell reports it. A program that blocks reads Done, which
// closes when its process ends, and returns then. An ended process leaves the
// process table at once, as one its parent reaps does, and its children take
// PID 1 as their parent, as an orphan's do.
package fake

import (
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"slices"
	"sync"
	"syscall"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/host"
)

// Program is the body of a fake process. It returns the process's exit code.
type Program func(p *Process) int

// Machine is a fake machine. New makes one.
type Machine struct {
	// Programs names what a start runs: the program for the process s
	// describes, or nil when s names none, which Start refuses as exec refuses
	// a program it cannot find. Set it before the first start.
	Programs func(s host.Spec) Program
	// FreePortErr, when set, fails FreePort.
	FreePortErr error

	mu      sync.Mutex
	procs   map[int]*Process
	lastPid int
	port    int
	listens map[int][]int
	starts  []Start
	ends    []End
	running *sync.WaitGroup
	caller  *Process
}

// Start is one start the machine took: the process it ran, the process that
// started it, and what it was asked to run.
type Start struct {
	Pid, Parent int
	Spec        host.Spec
}

// End is one process's end: the process, its status as a shell reports it,
// and the bubble's time when it ended.
type End struct {
	Pid, Status int
	At          time.Time
}

// Process is a process on the machine, and the machine as that process sees
// it. It is the host.Host its program runs on, and the host.Child its parent
// got from Start.
type Process struct {
	m       *Machine
	pid     int
	group   int
	parent  int
	spec    host.Spec
	out     io.Writer
	file    *os.File
	notify  map[os.Signal][]chan<- os.Signal
	ignored map[os.Signal]bool
	ended   bool
	status  int
	done    chan struct{}
	relayed chan struct{}
}

var (
	_ host.Host  = (*Process)(nil)
	_ host.Child = (*Process)(nil)
)

// New returns a machine whose one running process is the test's own, Caller,
// which leads a group of its own.
func New() *Machine {
	m := &Machine{procs: map[int]*Process{}, lastPid: 1000, port: 40000, listens: map[int][]int{},
		running: new(sync.WaitGroup)}
	m.caller = m.add(100, 100, 1, host.Spec{})
	return m
}

func (m *Machine) add(pid, group, parent int, s host.Spec) *Process {
	p := &Process{m: m, pid: pid, group: group, parent: parent, spec: s,
		notify: map[os.Signal][]chan<- os.Signal{}, ignored: map[os.Signal]bool{},
		done: make(chan struct{}), relayed: make(chan struct{})}
	m.procs[pid] = p
	return p
}

// Caller is the test's own process.
func (m *Machine) Caller() *Process { return m.caller }

// Starts returns every start the machine took, in order.
func (m *Machine) Starts() []Start {
	m.mu.Lock()
	defer m.mu.Unlock()
	return slices.Clone(m.starts)
}

// Ends returns every process's end, in order.
func (m *Machine) Ends() []End {
	m.mu.Lock()
	defer m.mu.Unlock()
	return slices.Clone(m.ends)
}

// Halt kills every process but the caller, and waits for each program to
// return, so none outlives the test's bubble. A test's cleanup calls it.
func (m *Machine) Halt() {
	m.mu.Lock()
	for _, p := range m.procs {
		if p != m.caller {
			m.end(p, 128+int(syscall.SIGKILL))
		}
	}
	m.mu.Unlock()
	m.running.Wait()
}

// --- what a program reads -----------------------------------------------------

// Spec is what the process was started with.
func (p *Process) Spec() host.Spec { return p.spec }

// Done is closed once the process has ended.
func (p *Process) Done() <-chan struct{} { return p.done }

// Out is where the process's output goes, as Spec's Out names it. A write
// once the process has ended fails, as a write to a pipe whose reader has
// gone does.
func (p *Process) Out() io.Writer { return output{p} }

type output struct{ p *Process }

func (w output) Write(b []byte) (int, error) {
	m := w.p.m
	m.mu.Lock()
	defer m.mu.Unlock()
	switch {
	case w.p.ended:
		return 0, syscall.EPIPE
	case w.p.out == nil:
		return len(b), nil
	}
	return w.p.out.Write(b)
}

// Listen has the process listen on the loopback port until it ends.
func (p *Process) Listen(port int) {
	m := p.m
	m.mu.Lock()
	defer m.mu.Unlock()
	if !p.ended {
		m.listens[port] = append(m.listens[port], p.pid)
	}
}

// --- host.Child ---------------------------------------------------------------

// Pid is the process's id.
func (p *Process) Pid() int { return p.pid }

// Wait waits for the process to end and returns its status.
func (p *Process) Wait() int {
	<-p.done
	p.m.mu.Lock()
	defer p.m.mu.Unlock()
	return p.status
}

// Relayed is closed once the process has ended, for a Spec with Relay, since a
// fake process writes its output itself.
func (p *Process) Relayed() <-chan struct{} { return p.relayed }

// --- host.Host ----------------------------------------------------------------

func (p *Process) Notify(c chan<- os.Signal, sig ...os.Signal) {
	p.m.mu.Lock()
	defer p.m.mu.Unlock()
	for _, s := range sig {
		delete(p.ignored, s)
		p.notify[s] = append(p.notify[s], c)
	}
}

func (p *Process) Ignore(sig ...os.Signal) {
	p.m.mu.Lock()
	defer p.m.mu.Unlock()
	for _, s := range sig {
		delete(p.notify, s)
		p.ignored[s] = true
	}
}

// Start runs the program Programs names for s in a goroutine of its own, as
// this process's child: in a group of its own with Session, else in this
// process's group. An *os.File Out is copied for the process, as a child
// inherits a descriptor, so the parent may close its own.
func (p *Process) Start(s host.Spec) (host.Child, error) {
	m := p.m
	if len(s.Argv) == 0 {
		return nil, errors.New("no program to start")
	}
	if s.Sandbox != nil && s.Dir == "" {
		return nil, errors.New("a sandboxed process needs a directory to run in")
	}
	var prog Program
	if m.Programs != nil {
		prog = m.Programs(s)
	}
	if prog == nil {
		return nil, &exec.Error{Name: s.Argv[0], Err: exec.ErrNotFound}
	}
	var file *os.File
	if f, ok := s.Out.(*os.File); ok && f != nil {
		fd, err := syscall.Dup(int(f.Fd()))
		if err != nil {
			return nil, err
		}
		file = os.NewFile(uintptr(fd), f.Name())
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if p.ended {
		if file != nil {
			file.Close()
		}
		return nil, fmt.Errorf("process %d has ended: %w", p.pid, syscall.ESRCH)
	}
	m.lastPid++
	group := p.group
	if s.Session {
		group = m.lastPid
	}
	q := m.add(m.lastPid, group, p.pid, s)
	q.out = s.Out
	if file != nil {
		q.out, q.file = file, file
	}
	if !s.Relay {
		close(q.relayed)
	}
	m.starts = append(m.starts, Start{Pid: q.pid, Parent: p.pid, Spec: s})
	m.running.Add(1)
	go func() {
		defer m.running.Done()
		code := prog(q)
		m.mu.Lock()
		defer m.mu.Unlock()
		m.end(q, code)
	}()
	return q, nil
}

func (p *Process) Signal(pid int, sig syscall.Signal) error {
	if pid <= 0 {
		return fmt.Errorf("pid %d names no one process: %w", pid, syscall.EINVAL)
	}
	m := p.m
	m.mu.Lock()
	defer m.mu.Unlock()
	q, ok := m.procs[pid]
	if !ok || q.ended {
		return syscall.ESRCH
	}
	m.deliver(q, sig)
	return nil
}

func (p *Process) SignalGroup(pgid int, sig syscall.Signal) error {
	if pgid <= 1 {
		return fmt.Errorf("pgid %d names no one process group: %w", pgid, syscall.EINVAL)
	}
	m := p.m
	m.mu.Lock()
	defer m.mu.Unlock()
	members := m.members(pgid)
	if len(members) == 0 {
		return syscall.ESRCH
	}
	for _, q := range members {
		m.deliver(q, sig)
	}
	return nil
}

func (p *Process) Proc(pid int) (host.Proc, bool) {
	m := p.m
	m.mu.Lock()
	defer m.mu.Unlock()
	q, ok := m.procs[pid]
	if !ok || q.ended {
		return host.Proc{}, false
	}
	return host.Proc{Group: q.group, Parent: q.parent, Started: fmt.Sprintf("start-%d", q.pid)}, true
}

func (p *Process) Members(pgid int) []int {
	p.m.mu.Lock()
	defer p.m.mu.Unlock()
	var pids []int
	for _, q := range p.m.members(pgid) {
		pids = append(pids, q.pid)
	}
	return pids
}

func (p *Process) GroupGone(pgid int) bool {
	p.m.mu.Lock()
	defer p.m.mu.Unlock()
	return len(p.m.members(pgid)) == 0
}

// FreePort picks the next port above the last it picked that nothing listens
// on.
func (p *Process) FreePort() (int, error) {
	m := p.m
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.FreePortErr != nil {
		return 0, m.FreePortErr
	}
	for {
		m.port++
		if len(m.listens[m.port]) == 0 {
			return m.port, nil
		}
	}
}

func (p *Process) Answers(port int) bool {
	p.m.mu.Lock()
	defer p.m.mu.Unlock()
	return len(p.m.listens[port]) > 0
}

func (p *Process) Listeners(port int) ([]int, error) {
	p.m.mu.Lock()
	defer p.m.mu.Unlock()
	return slices.Clone(p.m.listens[port]), nil
}

// --- the machine, under its lock -----------------------------------------------

// members returns the running processes of the group, by pid.
func (m *Machine) members(pgid int) []*Process {
	var ps []*Process
	for _, q := range m.procs {
		if q.group == pgid && !q.ended {
			ps = append(ps, q)
		}
	}
	slices.SortFunc(ps, func(a, b *Process) int { return a.pid - b.pid })
	return ps
}

// deliver has a signal reach a process: SIGKILL ends it, a signal it notifies
// reaches each of its channels that has room, as os/signal sends one, and one
// it neither notifies nor ignores ends it when that is the signal's default.
func (m *Machine) deliver(q *Process, sig syscall.Signal) {
	switch {
	case sig == 0:
	case sig == syscall.SIGKILL:
		m.end(q, 128+int(sig))
	case len(q.notify[sig]) > 0:
		for _, c := range q.notify[sig] {
			select {
			case c <- sig:
			default:
			}
		}
	case q.ignored[sig]:
	case terminates(sig):
		m.end(q, 128+int(sig))
	}
}

// terminates reports whether a signal's default action ends a process.
func terminates(sig syscall.Signal) bool {
	switch sig {
	case syscall.SIGHUP, syscall.SIGINT, syscall.SIGQUIT, syscall.SIGTERM, syscall.SIGUSR1,
		syscall.SIGUSR2, syscall.SIGPIPE, syscall.SIGALRM, syscall.SIGABRT:
		return true
	}
	return false
}

// end ends a process with its status, once: it leaves the table and stops
// listening, its children take PID 1 as their parent, and whatever waits on
// it wakes.
func (m *Machine) end(q *Process, status int) {
	if q.ended {
		return
	}
	q.ended, q.status = true, status
	close(q.done)
	if q.spec.Relay {
		close(q.relayed)
	}
	if q.file != nil {
		q.file.Close()
	}
	for port, pids := range m.listens {
		m.listens[port] = slices.DeleteFunc(pids, func(pid int) bool { return pid == q.pid })
	}
	for _, c := range m.procs {
		if c.parent == q.pid && !c.ended {
			c.parent = 1
		}
	}
	m.ends = append(m.ends, End{Pid: q.pid, Status: status, At: time.Now()})
}
