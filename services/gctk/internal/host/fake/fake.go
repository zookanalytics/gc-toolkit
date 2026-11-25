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
	// MemoryBytes is the machine's physical memory, which Memory reports, and
	// MemoryErr, when set, fails Memory.
	MemoryBytes int64
	MemoryErr   error
	// LockErr, when set, fails every Lock and Holder.
	LockErr error

	mu      sync.Mutex
	procs   map[int]*Process
	lastPid int
	port    int
	listens map[int][]int
	starts  []Start
	ends    []End
	locks   map[string]*fileLock
	files   map[string]string
	rss     map[int]int64
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
	stdout  io.Writer
	closed  bool
	file    *os.File
	notify  map[os.Signal][]chan<- os.Signal
	ignored map[os.Signal]bool
	ended   bool
	status  int
	done    chan struct{}
	relayed chan struct{}
	// outCut and stdoutCut are set once the writer of a relayed stream, Out's
	// or Stdout's own, refused a write, where the relay's copy stops.
	outCut, stdoutCut bool
}

var (
	_ host.Host  = (*Process)(nil)
	_ host.Child = (*Process)(nil)
)

// New returns a machine whose one running process is the test's own, Caller,
// which leads a group of its own.
func New() *Machine {
	m := &Machine{procs: map[int]*Process{}, lastPid: 1000, port: 40000, listens: map[int][]int{},
		running: new(sync.WaitGroup), MemoryBytes: 64 << 30, locks: map[string]*fileLock{},
		files: map[string]string{}, rss: map[int]int64{}}
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

// Out is where the process's output goes, as Spec's Out names it: its
// standard error, and its standard output too unless Spec's Stdout takes it. A
// write once the process has ended fails, as a write to a pipe whose reader
// has gone does. With Relay, a write its writer refuses ends the copy of that
// stream, as it ends a relay's: a later write to the stream fails as one after
// the process's end does, and a writer that is a host.Ender is not told the
// stream ended.
func (p *Process) Out() io.Writer { return output{p: p} }

// Stdout is where the process's standard output goes: Spec's Stdout, or Out
// when the spec names none.
func (p *Process) Stdout() io.Writer { return output{p: p, stdout: true} }

type output struct {
	p      *Process
	stdout bool
}

func (w output) Write(b []byte) (int, error) {
	m := w.p.m
	m.mu.Lock()
	defer m.mu.Unlock()
	to, cut := w.p.out, &w.p.outCut
	if w.stdout && w.p.stdout != nil {
		to, cut = w.p.stdout, &w.p.stdoutCut
	}
	switch {
	case w.p.ended:
		return 0, syscall.EPIPE
	case w.stdout && w.p.closed:
		return 0, syscall.EBADF
	case *cut:
		return 0, syscall.EPIPE
	case to == nil:
		return len(b), nil
	}
	n, err := to.Write(b)
	if err != nil && w.p.spec.Relay {
		*cut = true
	}
	return n, err
}

// CloseStdout closes the process's standard output, as a program that closes
// its descriptor 1 and runs on does: a later write to Stdout fails. With
// Relay, Spec's Stdout is told the stream has ended when it is a host.Ender,
// as the relay tells it. Spec's Stdout unset, the standard output shares Out
// with the standard error, whose stream goes on.
func (p *Process) CloseStdout() {
	m := p.m
	m.mu.Lock()
	defer m.mu.Unlock()
	if p.closed || p.ended {
		return
	}
	p.closed = true
	if p.spec.Relay && p.stdout != nil && !p.stdoutCut {
		ends(p.stdout)
	}
}

// ends tells w its stream has ended, when w is a host.Ender.
func ends(w io.Writer) {
	if e, ok := w.(host.Ender); ok {
		e.End()
	}
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
			_ = file.Close()
		}
		return nil, fmt.Errorf("process %d has ended: %w", p.pid, syscall.ESRCH)
	}
	m.lastPid++
	group := p.group
	if s.Session {
		group = m.lastPid
	}
	q := m.add(m.lastPid, group, p.pid, s)
	q.out, q.stdout = s.Out, s.Stdout
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

// Lock takes the lock on path when no process holds it. The process that
// holds a lock frees it when it ends.
func (p *Process) Lock(path string) (host.Lock, bool, error) {
	m := p.m
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.LockErr != nil {
		return nil, false, m.LockErr
	}
	if _, ok := m.files[path]; !ok {
		m.files[path] = ""
	}
	if _, held := m.locks[path]; held {
		return nil, false, nil
	}
	l := &fileLock{m: m, owner: p.pid, path: path}
	m.locks[path] = l
	return l, true, nil
}

func (p *Process) Holder(path string) (string, bool, error) {
	m := p.m
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.LockErr != nil {
		return "", false, m.LockErr
	}
	_, held := m.locks[path]
	return m.files[path], held, nil
}

func (p *Process) Alive(pid int) bool {
	p.m.mu.Lock()
	defer p.m.mu.Unlock()
	q, ok := p.m.procs[pid]
	return ok && !q.ended
}

func (p *Process) Memory() (int64, error) {
	p.m.mu.Lock()
	defer p.m.mu.Unlock()
	return p.m.MemoryBytes, p.m.MemoryErr
}

// Resident sums the sizes SetResident gave pid and the running processes
// descended from it.
func (p *Process) Resident(pid int) (int64, error) {
	m := p.m
	m.mu.Lock()
	defer m.mu.Unlock()
	if q, ok := m.procs[pid]; !ok || q.ended {
		return 0, fmt.Errorf("the process table names no process %d", pid)
	}
	var sum int64
	for next := []int{pid}; len(next) > 0; {
		pid := next[len(next)-1]
		next = next[:len(next)-1]
		sum += m.rss[pid]
		for _, c := range m.procs {
			if c.parent == pid && !c.ended {
				next = append(next, c.pid)
			}
		}
	}
	return sum, nil
}

// SetResident gives the process pid a resident size, which Resident counts.
func (m *Machine) SetResident(pid int, bytes int64) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.rss[pid] = bytes
}

// File is the line the file at path holds, and whether a process holds its
// lock.
func (m *Machine) File(path string) (string, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	_, held := m.locks[path]
	return m.files[path], held
}

// Holds takes the lock on path for the process pid, which need not run on
// the machine, and stamps line into the file, as a holder outside the test's
// process does. The lock is freed when that process ends or Free frees it. It
// reports false when the lock is held already.
func (m *Machine) Holds(pid int, path, line string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	if _, held := m.locks[path]; held {
		return false
	}
	m.locks[path] = &fileLock{m: m, owner: pid, path: path}
	m.files[path] = line
	return true
}

// Free frees the lock on path, whoever holds it.
func (m *Machine) Free(path string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.locks, path)
}

// fileLock is a lock a process holds on a file of the machine.
type fileLock struct {
	m     *Machine
	owner int
	path  string
}

func (l *fileLock) Stamp(line string) error {
	m := l.m
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.locks[l.path] != l {
		return fmt.Errorf("%s: the lock is not held", l.path)
	}
	m.files[l.path] = line
	return nil
}

func (l *fileLock) Unlock() {
	m := l.m
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.locks[l.path] == l {
		delete(m.locks, l.path)
	}
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
		if q.stdout != nil && !q.closed && !q.stdoutCut {
			ends(q.stdout)
		}
		if !q.outCut {
			ends(q.out)
		}
		close(q.relayed)
	}
	if q.file != nil {
		_ = q.file.Close()
	}
	for port, pids := range m.listens {
		m.listens[port] = slices.DeleteFunc(pids, func(pid int) bool { return pid == q.pid })
	}
	for path, l := range m.locks {
		if l.owner == q.pid {
			delete(m.locks, path)
		}
	}
	for _, c := range m.procs {
		if c.parent == q.pid && !c.ended {
			c.parent = 1
		}
	}
	m.ends = append(m.ends, End{Pid: q.pid, Status: status, At: time.Now()})
}
