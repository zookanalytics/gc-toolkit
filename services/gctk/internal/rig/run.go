package rig

import (
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"runtime"
	"sync"
	"syscall"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/host"
)

// Kind is what a run of a check command came to.
type Kind int

const (
	// Passed: the command exited 0.
	Passed Kind = iota
	// Failed: the command exited with a status that says the code failed.
	Failed
	// Machine: the command could not run to a verdict, so its status says
	// nothing about the code. Nothing is recorded.
	Machine
	// Interrupted: this process was sent SIGTERM or SIGINT during the run. The
	// command's process group was stopped, and nothing is recorded.
	Interrupted
)

// Outcome is one run's result.
type Outcome struct {
	Kind Kind
	// ExitCode is the command's exit status, for Passed and Failed.
	ExitCode int
	// Reason says what stopped a Machine run.
	Reason string
	// Signal is the one that interrupted this process, for Interrupted.
	Signal syscall.Signal
	// Duration is the wall time from start to exit.
	Duration time.Duration
	// Peak is the most memory the command's processes held at once, in
	// bytes, as far as the run saw: the largest sum Sample read over the
	// command's process tree, one read every SamplePeriod, and never less than
	// the largest single process among the command and those it waited for.
	Peak int64
}

// Sample reads the memory resident for a process and its descendants, and
// SamplePeriod is how often a run reads it. Variables, so a test can stand in
// for the process table.
var (
	Sample       = host.Local().Resident
	SamplePeriod = 5 * time.Second
)

// StopGrace is how long a stopped command's process group has between SIGTERM
// and SIGKILL. A variable so a test can shorten it.
var StopGrace = 10 * time.Second

// maxSignal bounds the signal numbers a shell reports as 128+N.
const maxSignal = 64

// Parses reports whether bash parses command, so a command line that cannot
// run at all is a machine failure rather than a recorded fail at every commit.
// The reason carries bash's own message.
func Parses(command string) (bool, string) {
	cmd := exec.Command("bash", "-n", "-c", command)
	cmd.Stdin = nil
	out, err := cmd.CombinedOutput()
	if err == nil {
		return true, ""
	}
	var ee *exec.ExitError
	if errors.As(err, &ee) {
		return false, fmt.Sprintf("bash does not parse the command: %s", trimOutput(out))
	}
	return false, fmt.Sprintf("bash did not start: %v", err)
}

// Run runs command in a bash of its own, in dir, with stdin closed, and waits
// for it. The command's output goes to stdout and stderr; an *os.File is handed
// to the command as it is, so nothing it leaves running holds the wait open.
//
// The command leads a process group of its own, and Run stops a run by stopping
// that group: SIGTERM, then SIGKILL to whatever is left of it after StopGrace.
// The stop reaches every child that stays in the group, including one still
// running after the command itself has exited, and a stopped run returns only
// once its group is empty or has been sent SIGKILL. A child the command starts
// in a group of its own, as a runner under bash's `set -m` does, is the
// command's to stop. With a timeout above zero, a run still going at the
// timeout is stopped and is a Machine outcome.
//
// The command's environment is this process's with NoCapVar set to 1, because
// the slots the run holds cover everything the command starts.
//
// Its own group also puts the command out of reach of a signal sent to this
// process's group, which is how an order runner stops a job that outlives its
// timeout and how a terminal delivers Ctrl-C. So a SIGTERM or SIGINT that
// reaches this process during the run stops the command's group, and Run
// returns Interrupted; the caller records nothing and exits with 128 plus the
// signal. A signal this process inherited as ignored stays ignored.
//
// Run returns only once the command has been waited for, however the run
// ended, so nothing the command started writes to a stdout or stderr that is
// not a file after Run returns.
func Run(dir, command string, timeout time.Duration, stdout, stderr io.Writer) Outcome {
	cmd := exec.Command("bash", "-c", command)
	cmd.Dir = dir
	cmd.Stdin = nil
	cmd.Stdout = stdout
	cmd.Stderr = stderr
	cmd.Env = append(os.Environ(), NoCapVar+"=1")
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	// A writer that is not a file is fed through a pipe, and a child the
	// command leaves running can hold that pipe open after the command exits.
	cmd.WaitDelay = StopGrace

	stop := make(chan os.Signal, 1)
	for _, s := range []os.Signal{syscall.SIGTERM, syscall.SIGINT} {
		if !signal.Ignored(s) {
			signal.Notify(stop, s)
		}
	}
	start := time.Now()
	if err := cmd.Start(); err != nil {
		signal.Stop(stop)
		return Outcome{Kind: Machine, Reason: fmt.Sprintf("bash did not start: %v", err)}
	}
	group := -cmd.Process.Pid
	// The outcome is read from cmd.ProcessState, so Wait's error, which
	// repeats the exit or reports the output's copy, is not needed.
	waited := make(chan struct{}, 1)
	exited := make(chan struct{})
	go func() { _ = cmd.Wait(); close(exited); waited <- struct{}{} }()
	var peak sampled
	peak.watch(cmd.Process.Pid, exited)

	var expired <-chan time.Time
	if timeout > 0 {
		t := time.NewTimer(timeout)
		defer t.Stop()
		expired = t.C
	}
	var got os.Signal
	timedOut := false
	select {
	case <-waited:
	case got = <-stop:
		stopGroup(group, waited, stop)
	case <-expired:
		timedOut = true
		got = stopGroup(group, waited, stop)
	}
	elapsed := time.Since(start)
	most := max(peak.most(), largestProcess(cmd.ProcessState))
	// A signal that arrived as the command finished is still this process's to
	// take.
	signal.Stop(stop)
	if got == nil {
		select {
		case got = <-stop:
		default:
		}
	}
	if got != nil {
		sig, _ := got.(syscall.Signal)
		return Outcome{Kind: Interrupted, Signal: sig, Duration: elapsed, Peak: most}
	}
	if timedOut {
		return Outcome{Kind: Machine, Duration: elapsed, Peak: most,
			Reason: fmt.Sprintf("timed out after %s; its process group was stopped", timeout)}
	}
	o := classify(cmd.ProcessState)
	o.Duration = elapsed
	o.Peak = most
	return o
}

// sampled is the largest sum Sample read over a command's process tree.
type sampled struct {
	mu   sync.Mutex
	max  int64
	done chan struct{}
}

// watch reads the tree under pid every SamplePeriod until exited closes.
func (s *sampled) watch(pid int, exited <-chan struct{}) {
	s.done = make(chan struct{})
	go func() {
		defer close(s.done)
		t := time.NewTicker(SamplePeriod)
		defer t.Stop()
		for {
			select {
			case <-exited:
				return
			case <-t.C:
				if n, err := Sample(pid); err == nil {
					s.mu.Lock()
					s.max = max(s.max, n)
					s.mu.Unlock()
				}
			}
		}
	}()
}

// most waits for the watch to end, which it does once the command has
// exited, and returns the largest read.
func (s *sampled) most() int64 {
	<-s.done
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.max
}

// largestProcess is the largest resident size among the command and the
// processes it waited for, from the kernel's account of the command, which
// counts bytes on darwin and KiB on linux.
func largestProcess(ps *os.ProcessState) int64 {
	if ps == nil {
		return 0
	}
	ru, ok := ps.SysUsage().(*syscall.Rusage)
	if !ok {
		return 0
	}
	n := int64(ru.Maxrss)
	if runtime.GOOS == "linux" {
		n <<= 10
	}
	return n
}

// groupPoll is how often a stop looks for members left in the command's group
// once the command itself has been waited for.
const groupPoll = 25 * time.Millisecond

// stopGroup stops the command's process group: SIGTERM, then SIGKILL to
// whatever is left of the group after StopGrace. The command's own exit does
// not end the stop, because a child that ignores SIGTERM runs on after the
// shell that started it has exited. So the stop ends before StopGrace only once
// the command has been waited for and its group is empty. At StopGrace it
// sends SIGKILL and returns once the command has been waited for, which
// WaitDelay bounds once the command has exited. It returns the first SIGTERM
// or SIGINT that reached this process while it waited, if one did.
func stopGroup(group int, waited <-chan struct{}, stop <-chan os.Signal) os.Signal {
	_ = syscall.Kill(group, syscall.SIGTERM)
	grace := time.NewTimer(StopGrace)
	defer grace.Stop()
	poll := time.NewTicker(groupPoll)
	defer poll.Stop()
	waitedFor := false
	var got os.Signal
	for {
		select {
		case <-waited:
			waitedFor = true
			if groupEmpty(group) {
				return got
			}
		case <-poll.C:
			if waitedFor && groupEmpty(group) {
				return got
			}
		case s := <-stop:
			if got == nil {
				got = s
			}
		case <-grace.C:
			_ = syscall.Kill(group, syscall.SIGKILL)
			if !waitedFor {
				<-waited
			}
			return got
		}
	}
}

// groupEmpty reports whether no process is left in the group. darwin answers
// EPERM, not ESRCH, for a group whose only members have exited and are not yet
// reaped, and a member this process may not signal answers EPERM too, so only
// ESRCH reads as empty.
func groupEmpty(group int) bool {
	return errors.Is(syscall.Kill(group, 0), syscall.ESRCH)
}

// classify reads a finished command's status. A status the shell gives to a
// command that never ran, or to one a signal ended, is a Machine outcome:
// 126 is a command found but not executable, 127 a command not found, and
// 128+N a command ended by signal N. Any other non-zero status is the
// command's verdict on the code.
func classify(ps *os.ProcessState) Outcome {
	if ps == nil {
		return Outcome{Kind: Machine, Reason: "the command's exit status could not be read"}
	}
	if ws, ok := ps.Sys().(syscall.WaitStatus); ok && ws.Signaled() {
		return Outcome{Kind: Machine, Reason: fmt.Sprintf("killed by signal %d (%s)", int(ws.Signal()), ws.Signal())}
	}
	code := ps.ExitCode()
	switch {
	case code == 0:
		return Outcome{Kind: Passed}
	case code == 126:
		return Outcome{Kind: Machine, Reason: "the command could not be executed (exit 126)"}
	case code == 127:
		return Outcome{Kind: Machine, Reason: "the command was not found (exit 127)"}
	case code > 128 && code <= 128+maxSignal:
		return Outcome{Kind: Machine, Reason: fmt.Sprintf("the command was ended by signal %d (exit %d)", code-128, code)}
	case code < 0:
		return Outcome{Kind: Machine, Reason: "the command's exit status could not be read"}
	}
	return Outcome{Kind: Failed, ExitCode: code}
}

// trimOutput keeps a subprocess's message to its last few hundred bytes.
func trimOutput(out []byte) string {
	const keep = 400
	s := string(out)
	if len(s) > keep {
		s = "…" + s[len(s)-keep:]
	}
	for len(s) > 0 && (s[len(s)-1] == '\n' || s[len(s)-1] == ' ') {
		s = s[:len(s)-1]
	}
	return s
}
