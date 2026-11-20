package cli

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/doctor"
)

// doctorStub puts a gc on PATH that logs each call's arguments on one line and
// answers a doctor run, the two event reads and the emit the way a city does.
func doctorStub(t *testing.T) (calls func() string) {
	t.Helper()
	bin := t.TempDir()
	log := filepath.Join(bin, "calls")
	stub := `#!/bin/sh
echo "$*" >> '` + log + `'
case "$1 $2" in
  "doctor --json")
    echo 'gc doctor: a notice' >&2
    printf '%s\n' '{"schema_version":"1","ok":false,"error":{"code":"doctor_blocking_failed"},"results":[{"name":"controller","status":"ok","severity":"blocking","message":"running"},{"name":"orphan-sessions","status":"warning","severity":"blocking","message":"19 orphaned session(s)"}]}'
    exit 1 ;;
  "events --type") exit 0 ;;
  "event emit") printf '%s\n' '{"ok":true,"submitted":true}' ;;
  *) exit 9 ;;
esac
`
	if err := os.WriteFile(filepath.Join(bin, "gc"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	return func() string {
		raw, _ := os.ReadFile(log)
		return string(raw)
	}
}

func acceptedFile(t *testing.T, text string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "accepted.toml")
	if err := os.WriteFile(p, []byte(text), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

// The verb needs the accepted file, and refuses a call that names none as a
// usage error.
func TestDoctorRunNeedsTheAcceptedFile(t *testing.T) {
	calls := doctorStub(t)
	var out, errb bytes.Buffer
	if code := Run([]string{"doctor", "run"}, "", &out, &errb); code != 2 || !strings.Contains(errb.String(), `"accepted" not set`) {
		t.Fatalf("exit %d, stderr %q", code, errb.String())
	}
	if calls() != "" {
		t.Errorf("gc was called: %q", calls())
	}
}

// An accepted file that does not read stops the run before anything runs, so
// nothing is recorded.
func TestDoctorRunRefusesAnAcceptedFileThatDoesNotRead(t *testing.T) {
	calls := doctorStub(t)
	var out, errb bytes.Buffer
	code := Run([]string{"doctor", "run", "--accepted", acceptedFile(t, "check = \"a\"\n")}, "", &out, &errb)
	if code != 1 || !strings.Contains(errb.String(), "no doctor ran and nothing was recorded") || out.Len() != 0 {
		t.Fatalf("exit %d, stdout %q, stderr %q", code, out.String(), errb.String())
	}
	if calls() != "" {
		t.Errorf("gc was called: %q", calls())
	}
}

// A run reads the previous event, runs doctor, reads the monitors' runs,
// records the event, prints the record and a summary, and exits 0.
func TestDoctorRunRecordsTheRun(t *testing.T) {
	calls := doctorStub(t)
	var out, errb bytes.Buffer
	acc := acceptedFile(t, "[[accepted]]\ncheck = \"hold-label-routed-to\"\nreason = \"r\"\nruling = \"u\"\n")
	code := Run([]string{"doctor", "run", "--accepted", acc}, "", &out, &errb)
	if code != 0 {
		t.Fatalf("exit %d, stderr %q", code, errb.String())
	}
	var rec doctor.Record
	if err := json.Unmarshal(out.Bytes(), &rec); err != nil {
		t.Fatalf("stdout %q: %v", out.String(), err)
	}
	if !rec.Completed || len(rec.Failing) != 1 || rec.Failing[0].Name != "orphan-sessions" || rec.Failing[0].Streak != 1 {
		t.Errorf("record %+v", rec)
	}
	if got := errb.String(); got != "gctk doctor run: doctor ran: 1 failing, 0 not measured, 0 accepted, recorded\n" {
		t.Errorf("stderr %q", got)
	}
	lines := strings.Split(strings.TrimSpace(calls()), "\n")
	if len(lines) != 4 || lines[0] != "events --type gc-toolkit.doctor.ran" || lines[1] != "doctor --json" ||
		lines[2] != "events --type order.completed --since 24h0m0s" || !strings.HasPrefix(lines[3], "event emit gc-toolkit.doctor.ran --json --actor gctk --message doctor ran: 1 failing") {
		t.Errorf("gc was called:\n%s", calls())
	}
}
