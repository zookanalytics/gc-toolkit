package fake

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"syscall"
	"testing"
	"testing/synctest"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/host"
)

// blocks is a program that runs until its process ends.
func blocks(p *Process) int { <-p.Done(); return 0 }

func machine(t *testing.T, programs map[string]Program) *Machine {
	m := New()
	m.Programs = func(s host.Spec) Program { return programs[s.Argv[0]] }
	t.Cleanup(m.Halt)
	return m
}

// process is the machine's process pid, for a test to act as it.
func process(m *Machine, pid int) *Process {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.procs[pid]
}

func running(m *Machine, pid int) bool {
	_, ok := m.Caller().Proc(pid)
	return ok
}

// A start places its process as the host does: a session start leads a group
// of its own, any other joins its parent's group, and the table names each.
func TestFakeStartPlacesAProcessInAGroupAsTheHostDoes(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		m := machine(t, map[string]Program{"block": blocks,
			"parent": func(p *Process) int {
				if _, err := p.Start(host.Spec{Argv: []string{"block"}}); err != nil {
					return 1
				}
				<-p.Done()
				return 0
			}})
		me := m.Caller()
		leader, err := me.Start(host.Spec{Argv: []string{"parent"}, Session: true})
		if err != nil {
			t.Fatal(err)
		}
		synctest.Wait()
		starts := m.Starts()
		if len(starts) != 2 || starts[0].Parent != me.Pid() || starts[1].Parent != leader.Pid() {
			t.Fatalf("starts = %+v, want the leader, the caller's child, then its own child", starts)
		}
		kid := starts[1].Pid
		if p, ok := me.Proc(leader.Pid()); !ok || p.Group != leader.Pid() || p.Parent != me.Pid() || p.Started == "" {
			t.Errorf("the session start reads as %+v, %v: want a group of its own", p, ok)
		}
		if p, _ := me.Proc(kid); p.Group != leader.Pid() || p.Parent != leader.Pid() {
			t.Errorf("its child reads as %+v: want it in the leader's group, its child", p)
		}
		if got := me.Members(leader.Pid()); !slices.Equal(got, []int{leader.Pid(), kid}) {
			t.Errorf("members = %v", got)
		}

		// The leader ends alone: its child runs on, with PID 1 for its parent.
		_ = me.Signal(leader.Pid(), syscall.SIGTERM)
		if p, ok := me.Proc(kid); !ok || p.Parent != 1 {
			t.Errorf("the orphan reads as %+v, %v: want it running, PID 1's child", p, ok)
		}
		if me.GroupGone(leader.Pid()) {
			t.Error("a group with a member running reads as gone")
		}

		if _, err := me.Start(host.Spec{Argv: []string{"nothing"}}); !errors.Is(err, exec.ErrNotFound) {
			t.Errorf("a start of no program = %v, want exec.ErrNotFound", err)
		}
		if _, err := me.Start(host.Spec{Argv: []string{"block"}, Sandbox: &host.Sandbox{Port: 1}}); err == nil {
			t.Error("a sandboxed start with no directory started")
		}
	})
}

// A signal acts as its disposition says: a default SIGTERM ends a process with
// 143, a notified one reaches its channel, an ignored one does nothing, and
// SIGKILL ends a process whatever it set.
func TestFakeSignalsActAsTheirDispositionsSay(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		got := make(chan os.Signal, 1)
		m := machine(t, map[string]Program{
			"block":   blocks,
			"ignores": func(p *Process) int { p.Ignore(syscall.SIGTERM); <-p.Done(); return 0 },
			"notices": func(p *Process) int { p.Notify(got, syscall.SIGTERM); <-p.Done(); return 0 },
		})
		me := m.Caller()
		group, _ := me.Start(host.Spec{Argv: []string{"notices"}, Session: true})
		synctest.Wait()
		var plain, deaf host.Child
		for name, c := range map[string]*host.Child{"block": &plain, "ignores": &deaf} {
			var err error
			// A member of the leader's group, started from inside it.
			*c, err = process(m, group.Pid()).Start(host.Spec{Argv: []string{name}})
			if err != nil {
				t.Fatal(err)
			}
		}
		synctest.Wait()
		start := time.Now()
		time.Sleep(time.Second)
		if err := me.SignalGroup(group.Pid(), syscall.SIGTERM); err != nil {
			t.Fatal(err)
		}
		if s := <-got; s != syscall.SIGTERM {
			t.Errorf("the notifying process got %v", s)
		}
		if code := plain.Wait(); code != 143 {
			t.Errorf("a default SIGTERM ended a process with %d, want 143", code)
		}
		if !running(m, group.Pid()) || !running(m, deaf.Pid()) {
			t.Error("a notified or ignored SIGTERM ended its process")
		}
		if err := me.Signal(deaf.Pid(), syscall.SIGKILL); err != nil || deaf.Wait() != 137 {
			t.Errorf("SIGKILL to a process that ignores SIGTERM: %v, status %d, want 137", err, deaf.Wait())
		}
		if err := me.Signal(deaf.Pid(), 0); !errors.Is(err, syscall.ESRCH) {
			t.Errorf("signal 0 to an ended process = %v, want ESRCH", err)
		}
		ends := m.Ends()
		if len(ends) != 2 || ends[0].Pid != plain.Pid() || !ends[0].At.Equal(start.Add(time.Second)) {
			t.Errorf("ends = %+v, want the plain member's first, on the bubble's clock", ends)
		}
		if err := me.SignalGroup(1, 0); !errors.Is(err, syscall.EINVAL) {
			t.Errorf("SignalGroup(1) = %v, want EINVAL", err)
		}
	})
}

// A port answers while a process listens on it, and FreePort passes over it.
func TestFakePortsAnswerWhileTheirListenerRuns(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		m := machine(t, map[string]Program{"block": blocks})
		me := m.Caller()
		port, err := me.FreePort()
		if err != nil {
			t.Fatal(err)
		}
		c, _ := me.Start(host.Spec{Argv: []string{"block"}})
		process(m, c.Pid()).Listen(port + 1)
		if next, _ := me.FreePort(); next != port+2 {
			t.Errorf("FreePort = %d, want %d, past the port a process listens on", next, port+2)
		}
		if pids, _ := me.Listeners(port + 1); !me.Answers(port+1) || !slices.Equal(pids, []int{c.Pid()}) {
			t.Errorf("a listened port answers %v, listeners %v", me.Answers(port+1), pids)
		}
		_ = me.Signal(c.Pid(), syscall.SIGTERM)
		if pids, _ := me.Listeners(port + 1); me.Answers(port+1) || len(pids) != 0 {
			t.Errorf("an ended listener's port answers %v, listeners %v", me.Answers(port+1), pids)
		}
		m.FreePortErr = errors.New("none")
		if _, err := me.FreePort(); err == nil {
			t.Error("FreePortErr did not fail FreePort")
		}
	})
}

// A process writes its output where its spec's Out leads, through a copy of a
// file its parent may close, until it ends. A relay is done once it has ended.
func TestFakeOutputLandsUntilTheProcessEnds(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		writes := make(chan bool)
		m := machine(t, map[string]Program{"writer": func(p *Process) int {
			for range writes {
				if _, err := p.Out().Write([]byte("line\n")); err != nil {
					return 1
				}
			}
			<-p.Done()
			return 0
		}})
		path := filepath.Join(t.TempDir(), "log")
		f, err := os.Create(path)
		if err != nil {
			t.Fatal(err)
		}
		c, err := m.Caller().Start(host.Spec{Argv: []string{"writer"}, Out: f, Relay: true})
		f.Close()
		if err != nil {
			t.Fatal(err)
		}
		writes <- true
		synctest.Wait()
		select {
		case <-c.Relayed():
			t.Error("the relay is done while the process runs")
		default:
		}
		_ = m.Caller().Signal(c.Pid(), syscall.SIGKILL)
		<-c.Relayed()
		if b, _ := os.ReadFile(path); string(b) != "line\n" {
			t.Errorf("the log holds %q, want the line written while the process ran", b)
		}
		if _, err := process(m, c.Pid()).Out().Write([]byte("late\n")); !errors.Is(err, syscall.EPIPE) {
			t.Errorf("a write after the end = %v, want EPIPE", err)
		}
		close(writes)
	})
}
