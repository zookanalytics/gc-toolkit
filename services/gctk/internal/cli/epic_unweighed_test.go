package cli

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// runUnweighed prints what the store's epics answer, and returns its exit,
// stdout and stderr.
func runUnweighed(s *fake.Store) (int, string, string) {
	var out, errb bytes.Buffer
	code := epicUnweighed(ledger.New(s), &out, &errb)
	return code, out.String(), errb.String()
}

// Each change prints on one line: its time, its epic, what happened, the day a
// sync last weighed the epic or that none has, the ruling that followed a
// shift, and the reason, with each control character a space and a reason the
// store records none of said.
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
	code, out, errs := runUnweighed(s)
	want := strings.Join([]string{
		"2026-11-14T00:00:00Z e1 closed, never weighed: held: its signal showed",
		"2026-11-15T01:00:00Z e2 shifted, last weighed 2026-11-13: re-aimed",
		"2026-11-15T02:00:00Z e3 shifted, never weighed, then ruled continue on 2026-11-16: on the new course",
		"2026-11-17T00:00:00Z e4 closed, never weighed: no reason recorded",
	}, "\n") + "\n"
	if code != 0 || out != want || errs != "" {
		t.Errorf("exit %d, stdout:\n%s\nstderr: %q\nwant exit 0, stdout:\n%s", code, out, errs, want)
	}
}

// With nothing to weigh it prints the one line that says so, which an empty rig
// answers too.
func TestEpicUnweighedSaysWhenThereIsNothingToWeigh(t *testing.T) {
	s := fake.New()
	s.Put(fake.Bead{ID: "e1", Status: "closed", IssueType: "epic", ClosedAt: "2026-11-01T00:00:00Z",
		Metadata: map[string]string{"epic_hypothesis": "h", "epic_weighed_at": "2026-11-02T00:00:00Z"}})
	for name, store := range map[string]*fake.Store{"every change weighed": s, "an empty rig": fake.New()} {
		if code, out, errs := runUnweighed(store); code != 0 || out != unweighedNone+"\n" || errs != "" {
			t.Errorf("%s: exit %d, stdout %q, stderr %q; want exit 0 and the line that says nothing changed", name, code, out, errs)
		}
	}
}

// A store that does not answer prints nothing on stdout, says so on stderr and
// exits 1, since a list it could not read is not an empty one.
func TestEpicUnweighedStopsWhenTheStoreDoesNotAnswer(t *testing.T) {
	s := fake.New()
	s.FindErr = &gcbd.ReadError{Reason: "the listing did not answer"}
	code, out, errs := runUnweighed(s)
	if code != unweighedExitNoStore || out != "" || !strings.Contains(errs, "did not read") || !strings.Contains(errs, "run it again") {
		t.Errorf("exit %d, stdout %q, stderr %q; want exit 1, nothing on stdout and a line that says the epics did not read", code, out, errs)
	}
}

// unweighedStub answers `gc rig list --json` with $STUB_RIGS and exit
// $STUB_RIGS_RC, and `gc bd ... list` with $STUB_ROWS and exit $STUB_LIST_RC,
// and logs each call's argv to $STUB_LOG.
const unweighedStub = `#!/bin/sh
printf '%s\n' "$*" >> "$STUB_LOG"
case "$1 $2" in
"rig list") printf '%s' "$STUB_RIGS"; exit "${STUB_RIGS_RC:-0}" ;;
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
	t.Setenv("STUB_RIGS", `{"rigs":[{"name":"gc-toolkit","prefix":"tk","path":"/rigs/gc-toolkit"}]}`)
	t.Setenv("STUB_RIGS_RC", "0")
	t.Setenv("STUB_ROWS", rows)
	t.Setenv("STUB_LIST_RC", "0")
	t.Setenv("GC_NO_API", "1")
	return log
}

// --rig reads the store gc rig list names for the rig, with bd's --db on the
// read, which lists the store's epics, closed ones included.
func TestEpicUnweighedReadsTheStoreOfTheRigNamed(t *testing.T) {
	log := stubUnweighed(t, `[{"id":"tk-e","status":"closed","issue_type":"epic","closed_at":"2026-11-14T00:00:00Z","close_reason":"held","metadata":{"epic_hypothesis":"h"}}]`)
	var out, errb bytes.Buffer
	code := Run([]string{"epic", "unweighed", "--rig", "gc-toolkit"}, "test", &out, &errb)
	if code != 0 || out.String() != "2026-11-14T00:00:00Z tk-e closed, never weighed: held\n" {
		t.Errorf("exit %d, stdout %q, stderr %q", code, out.String(), errb.String())
	}
	raw, err := os.ReadFile(log)
	if err != nil {
		t.Fatal(err)
	}
	calls := strings.Split(strings.TrimSpace(string(raw)), "\n")
	if len(calls) != 2 || calls[0] != "rig list --json" || !strings.HasPrefix(calls[1], "bd --db /rigs/gc-toolkit/.beads list ") ||
		!strings.Contains(calls[1], " --all") || !strings.Contains(calls[1], " --type epic") {
		t.Errorf("calls = %q; want the rig list, then one list of the rig's epics in its store", calls)
	}
}

// A rig gc rig list does not name is a usage error, and a rig list or an epic
// list that fails is a store that did not answer: each prints nothing on
// stdout.
func TestEpicUnweighedRefusesARigItCannotRead(t *testing.T) {
	for _, tc := range []struct {
		name, rig, rigsRC, listRC string
		code                      int
		says                      string
	}{
		{"a rig gc rig list does not name", "nowhere", "0", "0", unweighedExitUsage, `names no rig "nowhere"`},
		{"a rig list that fails", "gc-toolkit", "1", "0", unweighedExitNoStore, "did not resolve"},
		{"an epic list that fails", "gc-toolkit", "0", "1", unweighedExitNoStore, "did not read"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			stubUnweighed(t, `[]`)
			t.Setenv("STUB_RIGS_RC", tc.rigsRC)
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
