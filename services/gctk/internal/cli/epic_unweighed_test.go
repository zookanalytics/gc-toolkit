package cli

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// readAt is the time a test's read takes, unless the test names another, and
// readLine the first line that read prints.
var (
	readAt   = time.Date(2026, 11, 18, 9, 30, 0, 0, time.UTC)
	readLine = unweighedReadAt + readAt.Format(time.RFC3339) + "\n"
)

// pinUnweighedClock makes the command's clock answer from clock until the test
// ends.
func pinUnweighedClock(t *testing.T, clock func() time.Time) {
	t.Helper()
	restore := now
	now = clock
	t.Cleanup(func() { now = restore })
}

// runUnweighed prints what the store's epics answer, read at readAt, and
// returns its exit, stdout and stderr.
func runUnweighed(t *testing.T, s *fake.Store) (int, string, string) {
	t.Helper()
	return runUnweighedAt(t, s, readAt)
}

// runUnweighedAt prints what the store's epics answer, read at when, and
// returns its exit, stdout and stderr.
func runUnweighedAt(t *testing.T, s *fake.Store, when time.Time) (int, string, string) {
	t.Helper()
	pinUnweighedClock(t, func() time.Time { return when })
	var out, errb bytes.Buffer
	code := epicUnweighed(ledger.New(s), &out, &errb)
	return code, out.String(), errb.String()
}

// The first line is the time of the read. Each change then prints on one line:
// its time, its epic, what happened, the day a sync last weighed the epic or
// that none has, the ruling that followed a shift, and the reason, with each
// control character a space and a reason the store records none of said.
func TestEpicUnweighedPrintsEachChangeOnALine(t *testing.T) {
	s := fake.New()
	s.Put(fake.Bead{ID: "e1", Status: "closed", IssueType: "epic", ClosedAt: "2026-11-14T00:00:00Z",
		CloseReason: "held:\nits signal\tshowed", Metadata: map[string]string{"epic_hypothesis": "h"}})
	s.Put(fake.Bead{ID: "e2", Status: "open", IssueType: "epic", Metadata: map[string]string{"epic_hypothesis": "h",
		"epic_ruling": "shift", "epic_ruling_at": "2026-11-15T01:00:00Z", "epic_ruling_reason": "re-aimed",
		"epic_weighed_at": "2026-11-13T09:00:00Z"}})
	s.Put(fake.Bead{ID: "e3", Status: "open", IssueType: "epic", Metadata: map[string]string{"epic_hypothesis": "h",
		"epic_ruling": "continue", "epic_ruling_at": "2026-11-16T01:00:00Z", "epic_ruling_reason": "on the new course",
		"epic_shifted_at": "2026-11-15T02:00:00Z"}})
	s.Put(fake.Bead{ID: "e4", Status: "closed", IssueType: "epic", ClosedAt: "2026-11-17T00:00:00Z",
		Metadata: map[string]string{"epic_hypothesis": "h"}})
	code, out, errs := runUnweighed(t, s)
	want := strings.Join([]string{
		"Read at 2026-11-18T09:30:00Z",
		"2026-11-14T00:00:00Z e1 closed, never weighed: held: its signal showed",
		"2026-11-15T01:00:00Z e2 shifted, last weighed 2026-11-13: re-aimed",
		"2026-11-15T02:00:00Z e3 shifted, never weighed, then ruled continue on 2026-11-16: on the new course",
		"2026-11-17T00:00:00Z e4 closed, never weighed: no reason recorded",
	}, "\n") + "\n"
	if code != 0 || out != want || errs != "" {
		t.Errorf("exit %d, stdout:\n%s\nstderr: %q\nwant exit 0, stdout:\n%s", code, out, errs, want)
	}
}

// With nothing to weigh it prints the time of the read and the one line that
// says so, which an empty rig answers too.
func TestEpicUnweighedSaysWhenThereIsNothingToWeigh(t *testing.T) {
	s := fake.New()
	s.Put(fake.Bead{ID: "e1", Status: "closed", IssueType: "epic", ClosedAt: "2026-11-01T00:00:00Z",
		Metadata: map[string]string{"epic_hypothesis": "h", "epic_weighed_at": "2026-11-02T00:00:00Z"}})
	for name, store := range map[string]*fake.Store{"every change weighed": s, "an empty rig": fake.New()} {
		if code, out, errs := runUnweighed(t, store); code != 0 || out != readLine+unweighedNone+"\n" || errs != "" {
			t.Errorf("%s: exit %d, stdout %q, stderr %q; want exit 0, the time of the read and the line that says nothing changed", name, code, out, errs)
		}
	}
}

// A store that does not answer prints nothing on stdout, the time included,
// says so on stderr and exits 1, since a list it could not read is not an empty
// one.
func TestEpicUnweighedStopsWhenTheStoreDoesNotAnswer(t *testing.T) {
	s := fake.New()
	s.FindErr = &gcbd.ReadError{Reason: "the listing did not answer"}
	code, out, errs := runUnweighed(t, s)
	if code != unweighedExitNoStore || out != "" || !strings.Contains(errs, "did not read") || !strings.Contains(errs, "run it again") {
		t.Errorf("exit %d, stdout %q, stderr %q; want exit 1, nothing on stdout and a line that says the epics did not read", code, out, errs)
	}
}

// The command reads its clock before the store answers, so each change the
// read did not show was written after the time it prints.
func TestEpicUnweighedTakesItsTimeBeforeTheStoreAnswers(t *testing.T) {
	s := fake.New()
	findsAtClock := -1
	pinUnweighedClock(t, func() time.Time { findsAtClock = len(s.Finds()); return readAt })
	var out, errb bytes.Buffer
	if code := epicUnweighed(ledger.New(s), &out, &errb); code != 0 || out.String() != readLine+unweighedNone+"\n" {
		t.Fatalf("exit %d, stdout %q, stderr %q", code, out.String(), errb.String())
	}
	if findsAtClock != 0 || len(s.Finds()) != 1 {
		t.Errorf("the clock was read after %d of the store's %d reads; want it read before the one read", findsAtClock, len(s.Finds()))
	}
}

// A sync reads late on one day, the epic shifts after the read, and the sync
// notes its ruling on the epic after midnight, marking it with the read's time
// as the portfolio-sync skill does. The next sync lists the shift, which no
// sync saw. A mark at the note's own time would take it off that list.
func TestEpicUnweighedListsWhatASyncAcrossMidnightDidNotRead(t *testing.T) {
	s := fake.New()
	s.Put(fake.Bead{ID: "e1", Status: "open", IssueType: "epic", Metadata: map[string]string{"epic_hypothesis": "h"}})
	_, out, _ := runUnweighedAt(t, s, time.Date(2026, 11, 14, 23, 50, 0, 0, time.UTC))
	first, _, _ := strings.Cut(out, "\n")
	read, ok := strings.CutPrefix(first, unweighedReadAt)
	if !ok || out != first+"\n"+unweighedNone+"\n" {
		t.Fatalf("the sync's read printed %q; want its time, then nothing to weigh", out)
	}

	shiftedAndMarked := func(mark string) fake.Bead {
		return fake.Bead{ID: "e1", Status: "open", IssueType: "epic", Metadata: map[string]string{"epic_hypothesis": "h",
			"epic_ruling": "shift", "epic_ruling_at": "2026-11-14T23:55:00Z", "epic_shifted_at": "2026-11-14T23:55:00Z",
			"epic_ruling_reason": "re-aimed after the read", "epic_weighed_at": mark}}
	}
	nextSync := time.Date(2026, 11, 15, 9, 0, 0, 0, time.UTC)
	s.Put(shiftedAndMarked(read))
	code, out, errs := runUnweighedAt(t, s, nextSync)
	want := "Read at 2026-11-15T09:00:00Z\n2026-11-14T23:55:00Z e1 shifted, last weighed 2026-11-14: re-aimed after the read\n"
	if code != 0 || out != want || errs != "" {
		t.Errorf("the next sync's read: exit %d, stdout %q, stderr %q; want exit 0 and stdout %q", code, out, errs, want)
	}

	s.Put(shiftedAndMarked("2026-11-15T00:05:00Z"))
	if _, out, _ := runUnweighedAt(t, s, nextSync); out != "Read at 2026-11-15T09:00:00Z\n"+unweighedNone+"\n" {
		t.Errorf("marked at the note's own time, the next read printed %q; want the shift gone, which is why a sync marks with the read's time", out)
	}
}

// unweighedStub answers `gc config show --json` with $STUB_CONFIG and exit
// $STUB_CONFIG_RC, and `gc bd ... list` with $STUB_ROWS and exit
// $STUB_LIST_RC, and logs each call's argv to $STUB_LOG.
const unweighedStub = `#!/bin/sh
printf '%s\n' "$*" >> "$STUB_LOG"
case "$1 $2" in
"config show") printf '%s' "$STUB_CONFIG"; exit "${STUB_CONFIG_RC:-0}" ;;
esac
for a in "$@"; do
  case "$a" in list) printf '%s' "$STUB_ROWS"; exit "${STUB_LIST_RC:-0}" ;; esac
done
echo "stub gc: no answer for $*" >&2
exit 2
`

// stubUnweighed puts the stub first on PATH, with one rig and the rows its
// store answers, and returns the file its calls are logged in.
func stubUnweighed(t *testing.T, rows string) string {
	t.Helper()
	bin := t.TempDir()
	if err := os.WriteFile(filepath.Join(bin, "gc"), []byte(unweighedStub), 0o755); err != nil {
		t.Fatal(err)
	}
	log := filepath.Join(bin, "calls")
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STUB_LOG", log)
	t.Setenv("STUB_CONFIG", `{"city_path":"/city","config":{"Workspace":{"Name":"city","Prefix":"hq"},"Rigs":[{"Name":"gc-toolkit","Prefix":"tk","Path":"/rigs/gc-toolkit"}]}}`)
	t.Setenv("STUB_CONFIG_RC", "0")
	t.Setenv("STUB_ROWS", rows)
	t.Setenv("STUB_LIST_RC", "0")
	t.Setenv("GC_NO_API", "1")
	return log
}

// --rig reads the store the city's config names for the rig, with bd's --db on
// the read, which lists the store's epics, closed ones included.
func TestEpicUnweighedReadsTheStoreOfTheRigNamed(t *testing.T) {
	log := stubUnweighed(t, `[{"id":"tk-e","status":"closed","issue_type":"epic","closed_at":"2026-11-14T00:00:00Z","close_reason":"held","metadata":{"epic_hypothesis":"h"}}]`)
	pinUnweighedClock(t, func() time.Time { return readAt })
	var out, errb bytes.Buffer
	code := Run([]string{"epic", "unweighed", "--rig", "gc-toolkit"}, "test", &out, &errb)
	if code != 0 || out.String() != readLine+"2026-11-14T00:00:00Z tk-e closed, never weighed: held\n" {
		t.Errorf("exit %d, stdout %q, stderr %q", code, out.String(), errb.String())
	}
	raw, err := os.ReadFile(log)
	if err != nil {
		t.Fatal(err)
	}
	calls := strings.Split(strings.TrimSpace(string(raw)), "\n")
	if len(calls) != 2 || calls[0] != "config show --json" || !strings.HasPrefix(calls[1], "bd --db /rigs/gc-toolkit/.beads list ") ||
		!strings.Contains(calls[1], " --all") || !strings.Contains(calls[1], " --type epic") {
		t.Errorf("calls = %q; want the config read, then one list of the rig's epics in its store", calls)
	}
}

// A rig the city's config does not name is a usage error, and a config read or
// an epic list that fails is a store that did not answer: each prints nothing
// on stdout.
func TestEpicUnweighedRefusesARigItCannotRead(t *testing.T) {
	for _, tc := range []struct {
		name, rig, configRC, listRC string
		code                        int
		says                        string
	}{
		{"a rig the city's config does not name", "nowhere", "0", "0", unweighedExitUsage, `names no rig "nowhere"`},
		{"a config read that fails", "gc-toolkit", "1", "0", unweighedExitNoStore, "did not resolve"},
		{"an epic list that fails", "gc-toolkit", "0", "1", unweighedExitNoStore, "did not read"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			stubUnweighed(t, `[]`)
			t.Setenv("STUB_CONFIG_RC", tc.configRC)
			t.Setenv("STUB_LIST_RC", tc.listRC)
			var out, errb bytes.Buffer
			code := Run([]string{"epic", "unweighed", "--rig", tc.rig}, "test", &out, &errb)
			if code != tc.code || out.String() != "" || !strings.Contains(errb.String(), tc.says) {
				t.Errorf("exit %d, stdout %q, stderr %q; want exit %d and %q", code, out.String(), errb.String(), tc.code, tc.says)
			}
		})
	}
}

// The verb takes no argument, so one is a usage error.
func TestEpicUnweighedTakesNoArgument(t *testing.T) {
	stubUnweighed(t, `[]`)
	var out, errb bytes.Buffer
	if code := Run([]string{"epic", "unweighed", "tk-e"}, "test", &out, &errb); code != unweighedExitUsage || out.String() != "" {
		t.Errorf("exit %d, stdout %q; want the usage exit and nothing on stdout", code, out.String())
	}
}
