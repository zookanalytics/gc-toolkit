package gascity

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

// stubGC is a City whose gc is the script body, after a line that logs each
// argument it was given, one per line, to the file log names.
func stubGC(t *testing.T, body string) (c *City, log func() []string) {
	t.Helper()
	dir := t.TempDir()
	logPath := filepath.Join(dir, "calls")
	script := "#!/bin/sh\nfor a in \"$@\"; do printf '%s\\n' \"$a\"; done >> '" + logPath + "'\n" + body
	bin := filepath.Join(dir, "gc")
	if err := os.WriteFile(bin, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	return &City{bin: bin}, func() []string {
		raw, _ := os.ReadFile(logPath)
		return strings.Split(strings.TrimSuffix(string(raw), "\n"), "\n")
	}
}

// gc doctor --json prints its report on standard output and its notices on
// standard error, and exits 1 when a blocking check failed. Doctor keeps the
// two apart and reads the results from the report.
func TestDoctorReadsTheReport(t *testing.T) {
	c, log := stubGC(t, `echo 'gc doctor: order "x" declares scope = "rig"' >&2
printf '%s\n' '{"schema_version":"1","ok":false,"error":{"code":"doctor_blocking_failed","exit_code":1},"passed":1,"results":[{"name":"controller","status":"ok","severity":"blocking","message":"running"},{"name":"worktree-disk-size","status":"error","severity":"advisory","message":"timed out","timed_out":true}]}'
exit 1
`)
	r := c.Doctor(context.Background())
	if r.Err != nil || r.Code != 1 || len(r.Results) != 2 {
		t.Fatalf("answered %+v", r)
	}
	if !r.Results[1].TimedOut || r.Results[0].Status != "ok" || r.Results[1].Severity != "advisory" {
		t.Errorf("results %+v", r.Results)
	}
	if !strings.Contains(r.Stderr, "declares scope") || strings.Contains(r.Stdout, "declares scope") {
		t.Errorf("stdout %q, stderr %q", r.Stdout, r.Stderr)
	}
	if got := strings.Join(log(), " "); got != "doctor --json" {
		t.Errorf("gc ran with %q", got)
	}
}

// A run whose standard output is no report, or a JSON object with no results
// list, answers no results.
func TestDoctorWithNoReport(t *testing.T) {
	for _, body := range []string{
		"echo 'gc doctor: not in a city' >&2\nexit 1\n",
		"printf '%s\\n' '{\"schema_version\":\"1\",\"ok\":false,\"error\":{\"code\":\"unknown_check\"}}'\nexit 1\n",
	} {
		c, _ := stubGC(t, body)
		if r := c.Doctor(context.Background()); r.Results != nil || r.Code != 1 {
			t.Errorf("%q answered %+v", body, r)
		}
	}
}

// When the context ends first, Doctor ends gc doctor's whole process group,
// the processes it started included, and answers ErrDeadline.
func TestDoctorEndsItsGroupAtTheDeadline(t *testing.T) {
	pidFile := filepath.Join(t.TempDir(), "child")
	c, _ := stubGC(t, "sleep 30 &\necho $! > '"+pidFile+"'\nwait\n")
	ctx, cancel := context.WithTimeout(context.Background(), 500*time.Millisecond)
	defer cancel()
	began := time.Now()
	r := c.Doctor(ctx)
	if !errors.Is(r.Err, ErrDeadline) || r.Code != -1 || r.Results != nil {
		t.Fatalf("answered %+v", r)
	}
	if took := time.Since(began); took > 10*time.Second {
		t.Fatalf("the run held its caller %s", took)
	}
	raw, err := os.ReadFile(pidFile)
	if err != nil {
		t.Fatal(err)
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(raw)))
	if err != nil {
		t.Fatal(err)
	}
	for end := time.Now().Add(3 * time.Second); ; time.Sleep(50 * time.Millisecond) {
		if err := syscall.Kill(pid, 0); errors.Is(err, syscall.ESRCH) {
			break
		}
		if time.Now().After(end) {
			t.Fatalf("the process gc doctor started, %d, outlived the deadline", pid)
		}
	}
}

// gc doctor leads its own group, so the SIGTERM or the Ctrl-C that reaches this
// process's group does not reach it. The call passes the signal on, ending the
// processes gc doctor started, then exits with the status the signal gives.
func TestBoundedPassesAStopSignalOnToItsGroup(t *testing.T) {
	for _, sig := range []syscall.Signal{syscall.SIGTERM, syscall.SIGINT} {
		t.Run(sig.String(), func(t *testing.T) {
			pidFile := filepath.Join(t.TempDir(), "child")
			c, _ := stubGC(t, "sleep 30 &\necho $! > '"+pidFile+"'\nwait\n")
			exited := make(chan int, 1)
			restore := exitProcess
			exitProcess = func(code int) { exited <- code }
			t.Cleanup(func() { exitProcess = restore })
			// The test's own relay, so a call that does not take the signal fails
			// this test rather than ending the test binary.
			held := make(chan os.Signal, 1)
			signal.Notify(held, sig)
			t.Cleanup(func() { signal.Stop(held) })

			done := make(chan DoctorRun, 1)
			go func() { done <- c.Doctor(context.Background()) }()
			pid := 0
			for end := time.Now().Add(5 * time.Second); pid == 0; time.Sleep(20 * time.Millisecond) {
				raw, _ := os.ReadFile(pidFile)
				pid, _ = strconv.Atoi(strings.TrimSpace(string(raw)))
				if pid == 0 && time.Now().After(end) {
					t.Fatal("the stub gc doctor never started its child")
				}
			}
			if err := syscall.Kill(os.Getpid(), sig); err != nil {
				t.Fatal(err)
			}
			select {
			case code := <-exited:
				if want := 128 + int(sig); code != want {
					t.Errorf("a relayed %v exited %d, want %d", sig, code, want)
				}
			case <-time.After(10 * time.Second):
				t.Fatalf("the call did not exit on the %v this process received", sig)
			}
			<-done
			for end := time.Now().Add(3 * time.Second); ; time.Sleep(50 * time.Millisecond) {
				if err := syscall.Kill(pid, 0); errors.Is(err, syscall.ESRCH) {
					break
				}
				if time.Now().After(end) {
					t.Fatalf("the process gc doctor started, %d, outlived the %v this process received", pid, sig)
				}
			}
		})
	}
}

// A bounded command starts in the city's directory, and on a city As an actor
// it runs with BEADS_ACTOR naming that actor, as every command the city runs
// does. The city it came from runs as the process does.
func TestBoundedActsAsItsActorInItsDirectory(t *testing.T) {
	base := t.TempDir()
	log := filepath.Join(base, "who")
	bin := filepath.Join(base, "gc")
	stub := "#!/bin/sh\nprintf '%s %s\\n' \"${BEADS_ACTOR:-none}\" \"$(pwd -P)\" >> '" + log + "'\n"
	if err := os.WriteFile(bin, []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("BEADS_ACTOR", "")
	there := t.TempDir()
	from := (&City{bin: bin}).In(there)
	from.As("rig/gc-toolkit.refinery").Doctor(context.Background())
	from.Doctor(context.Background())
	resolved, err := filepath.EvalSymlinks(there)
	if err != nil {
		t.Fatal(err)
	}
	raw, _ := os.ReadFile(log)
	if want := "rig/gc-toolkit.refinery " + resolved + "\nnone " + resolved + "\n"; string(raw) != want {
		t.Fatalf("the commands ran as %q, want %q", raw, want)
	}
}

// Events reads one type, with --since when a window is given, from the JSON
// lines gc events prints, and leaves its notices on standard error out.
func TestEventsReadsTheLines(t *testing.T) {
	c, log := stubGC(t, `echo 'gc events: showing the newest 500 events' >&2
printf '%s\n' '{"actor":"controller","seq":7,"subject":"reaper","ts":"2026-11-16T12:00:00Z","type":"order.completed","ok":true}' '' '{"seq":9,"subject":"orphan-sweep:rig:a","ts":"2026-11-16T12:05:00Z","type":"order.completed","payload":{"a":1}}'
`)
	got, err := c.Events(context.Background(), "order.completed", 70*time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 || got[0].Seq != 7 || got[0].Subject != "reaper" || !got[0].Ts.Equal(time.Date(2026, 11, 16, 12, 0, 0, 0, time.UTC)) ||
		got[1].Subject != "orphan-sweep:rig:a" || string(got[1].Payload) != `{"a":1}` {
		t.Fatalf("read %+v", got)
	}
	if args := strings.Join(log(), " "); args != "events --type order.completed --since 1h10m0s" {
		t.Errorf("gc ran with %q", args)
	}
	c, log = stubGC(t, "")
	if _, err := c.Events(context.Background(), "gc-toolkit.doctor.ran", 0); err != nil {
		t.Fatal(err)
	}
	if args := strings.Join(log(), " "); args != "events --type gc-toolkit.doctor.ran" {
		t.Errorf("a read with no window ran %q", args)
	}
}

// A read that exits non-zero, or prints a line that is no event, fails.
func TestEventsFails(t *testing.T) {
	c, _ := stubGC(t, "echo 'gc events: no API at 127.0.0.1' >&2\nexit 1\n")
	if _, err := c.Events(context.Background(), "order.completed", 0); err == nil || !strings.Contains(err.Error(), "no API") {
		t.Errorf("err = %v", err)
	}
	c, _ = stubGC(t, "echo 'not json'\n")
	if _, err := c.Events(context.Background(), "order.completed", 0); err == nil || !strings.Contains(err.Error(), "not an event") {
		t.Errorf("err = %v", err)
	}
}

// Emit passes the event's fields to gc event emit --json, and succeeds only
// when gc's summary says it submitted the event.
func TestEmit(t *testing.T) {
	c, log := stubGC(t, `printf '%s\n' '{"schema_version":"1","ok":true,"event_type":"gc-toolkit.doctor.ran","has_payload":true,"submitted":true}'`)
	err := c.Emit(context.Background(), Emit{Type: "gc-toolkit.doctor.ran", Actor: "gctk", Message: "doctor ran", Payload: json.RawMessage(`{"a":1}`)})
	if err != nil {
		t.Fatal(err)
	}
	if args := strings.Join(log(), "|"); args != `event|emit|gc-toolkit.doctor.ran|--json|--actor|gctk|--message|doctor ran|--payload|{"a":1}` {
		t.Errorf("gc ran with %q", args)
	}
	for body, says := range map[string]string{
		`printf '%s\n' '{"ok":true,"submitted":false}'; echo 'gc event emit: no event provider' >&2`: "did not submit the event: gc event emit: no event provider",
		"echo 'gc event emit: reserved actor' >&2\nexit 1\n":                                         "did not run: exit 1: gc event emit: reserved actor",
		"echo done\n": "answered no summary that reads",
	} {
		c, _ := stubGC(t, body)
		if err := c.Emit(context.Background(), Emit{Type: "x"}); err == nil || !strings.Contains(err.Error(), says) {
			t.Errorf("%q: err = %v, want one saying %q", body, err, says)
		}
	}
}
