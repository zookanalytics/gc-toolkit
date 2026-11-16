package gascity

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"
	"strings"
	"sync/atomic"
	"syscall"
	"time"
)

// ErrDeadline is the Err of a command the adapter ended because the context it
// ran under ended first.
var ErrDeadline = errors.New("ended at its deadline")

// pipeWait bounds how long a command's output is waited for once the command
// has exited or been ended, so a descendant that keeps its output open cannot
// hold the caller.
const pipeWait = 5 * time.Second

// Bounded is what a command run under a deadline answered: its exit code, and
// its standard output and standard error apart, since a command whose output is
// JSON prints its notices to standard error. Code is -1 when it did not run to
// an exit, and Err then says why: ErrDeadline when the context ended first.
type Bounded struct {
	Code           int
	Stdout, Stderr string
	Err            error
}

// Failure is why the command failed, in one line, empty for exit 0.
func (b Bounded) Failure() string {
	switch {
	case b.Err != nil:
		return b.Err.Error()
	case b.Code != 0:
		return fmt.Sprintf("exit %d: %s", b.Code, Result{Output: b.Stderr}.Tail())
	}
	return ""
}

// DoctorResult is one result of a doctor report, as `gc doctor --json` prints
// it (doctorJSONResult in cmd/gc/cmd_doctor.go at gastownhall/gascity
// c7eb6d2f43): the check's name, its status (ok, warning, error), its severity
// (advisory, blocking), its message, and whether doctor abandoned it at its
// per-check timeout.
type DoctorResult struct {
	Name     string `json:"name"`
	Status   string `json:"status"`
	Severity string `json:"severity"`
	Message  string `json:"message"`
	TimedOut bool   `json:"timed_out"`
}

// DoctorRun is what one `gc doctor --json` answered. Results is nil when its
// standard output is not a JSON object carrying a results list, which a report
// always carries, a run with blocking failures included, where gc wraps the
// report in its failure envelope (writeDoctorJSON there).
type DoctorRun struct {
	Bounded
	Results []DoctorResult
}

// Doctor runs `gc doctor --json`, never with --fix, in a process group of its
// own, and ends that group when ctx ends first, so the checks it started end
// with it. gc doctor exits 0 when no blocking check failed and 1 when one did,
// and prints its report on standard output either way (doDoctor there).
func (c *City) Doctor(ctx context.Context) DoctorRun {
	b := runBounded(ctx, c.dir, c.bin, "doctor", "--json")
	out := DoctorRun{Bounded: b}
	if b.Err != nil {
		return out
	}
	var report struct {
		Results *[]DoctorResult `json:"results"`
	}
	if json.Unmarshal([]byte(strings.TrimSpace(b.Stdout)), &report) == nil && report.Results != nil {
		out.Results = *report.Results
	}
	return out
}

// Event is one event of the city's log, as `gc events` prints it: one JSON
// object per line (cliWireEvent in cmd/gc/cmd_events.go at
// gastownhall/gascity c7eb6d2f43).
type Event struct {
	Seq     int64           `json:"seq"`
	Type    string          `json:"type"`
	Ts      time.Time       `json:"ts"`
	Actor   string          `json:"actor,omitempty"`
	Subject string          `json:"subject,omitempty"`
	Message string          `json:"message,omitempty"`
	Payload json.RawMessage `json:"payload,omitempty"`
}

// Events reads the city's events of one type through `gc events --type`. With
// since zero it reads the newest page of them, up to 500; with since set it
// reads every one recorded within since, across as many pages as gc's own
// time budget lets it walk, and gc keeps the newest pages when that budget
// runs out (fetchCityEvents there). gc prints them oldest first, by seq.
func (c *City) Events(ctx context.Context, typ string, since time.Duration) ([]Event, error) {
	args := []string{"events", "--type", typ}
	if since > 0 {
		args = append(args, "--since", since.Round(time.Second).String())
	}
	b := runBounded(ctx, c.dir, c.bin, args...)
	if f := b.Failure(); f != "" {
		return nil, fmt.Errorf("gc events --type %s did not read: %s", typ, f)
	}
	var out []Event
	sc := bufio.NewScanner(strings.NewReader(b.Stdout))
	sc.Buffer(make([]byte, 0, 64*1024), 2*1024*1024)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" {
			continue
		}
		var e Event
		if err := json.Unmarshal([]byte(line), &e); err != nil {
			return nil, fmt.Errorf("gc events --type %s printed a line that is not an event: %v", typ, err)
		}
		out = append(out, e)
	}
	if err := sc.Err(); err != nil {
		return nil, fmt.Errorf("gc events --type %s printed output that did not read: %v", typ, err)
	}
	return out, nil
}

// Emit is one event to record in the city's log.
type Emit struct {
	Type, Actor, Subject, Message string
	Payload                       json.RawMessage
}

// Emit records e through `gc event emit --json`. gc exits 0 whether or not it
// recorded anything, and its JSON summary says whether it submitted the event
// to the city's log (cmdEventEmitSubmitted in cmd/gc/cmd_event_emit.go at
// gastownhall/gascity c7eb6d2f43), so Emit answers an error unless the summary
// says it did.
func (c *City) Emit(ctx context.Context, e Emit) error {
	args := []string{"event", "emit", e.Type, "--json"}
	if e.Actor != "" {
		args = append(args, "--actor", e.Actor)
	}
	if e.Subject != "" {
		args = append(args, "--subject", e.Subject)
	}
	if e.Message != "" {
		args = append(args, "--message", e.Message)
	}
	if len(e.Payload) > 0 {
		args = append(args, "--payload", string(e.Payload))
	}
	b := runBounded(ctx, c.dir, c.bin, args...)
	if f := b.Failure(); f != "" {
		return fmt.Errorf("gc event emit %s did not run: %s", e.Type, f)
	}
	var summary struct {
		Submitted bool `json:"submitted"`
	}
	if err := json.Unmarshal([]byte(strings.TrimSpace(b.Stdout)), &summary); err != nil {
		return fmt.Errorf("gc event emit %s answered no summary that reads: %v", e.Type, err)
	}
	if !summary.Submitted {
		return fmt.Errorf("gc event emit %s did not submit the event: %s", e.Type, Result{Output: b.Stderr}.Tail())
	}
	return nil
}

// runBounded runs bin with args in dir, the process's own working directory
// when dir is empty, in a process group the command leads, its standard input
// reading nothing. When ctx ends first it kills that whole group, so the
// processes the command started end with it, and answers ErrDeadline.
func runBounded(ctx context.Context, dir, bin string, args ...string) Bounded {
	cmd := exec.CommandContext(ctx, bin, args...)
	cmd.Dir = dir
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	var ended atomic.Bool
	cmd.Cancel = func() error {
		ended.Store(true)
		if err := syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL); err != nil && !errors.Is(err, syscall.ESRCH) {
			return err
		}
		return nil
	}
	cmd.WaitDelay = pipeWait
	err := cmd.Run()
	out := Bounded{Stdout: stdout.String(), Stderr: stderr.String()}
	var ee *exec.ExitError
	switch {
	case ended.Load() || (err != nil && ctx.Err() != nil && cmd.Process == nil):
		out.Code, out.Err = -1, ErrDeadline
	case err == nil:
		out.Code = 0
	case errors.As(err, &ee):
		out.Code = ee.ExitCode()
	case errors.Is(err, exec.ErrWaitDelay) && cmd.ProcessState != nil:
		out.Code = cmd.ProcessState.ExitCode()
	default:
		out.Code, out.Err = -1, err
	}
	return out
}
