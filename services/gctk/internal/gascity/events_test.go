package gascity

import (
	"context"
	"encoding/json"
	"errors"
	"os"
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
