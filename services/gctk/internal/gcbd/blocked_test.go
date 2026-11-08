package gcbd

import (
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// blockedStub puts a `gc` on PATH that answers `bd show` with $STUB_SHOW and
// exit $STUB_SHOW_RC, `bd blocked --json` with $STUB_BLOCKED and exit
// $STUB_BLOCKED_RC, and `bd sql --json <query>` with $STUB_MARKS and exit
// $STUB_MARKS_RC, each after printing $STUB_STDERR, when set, on stderr. It
// logs each call's argv, one line per call, to the file it returns.
func blockedStub(t *testing.T, show, blocked, marks string) string {
	t.Helper()
	dir := t.TempDir()
	log := filepath.Join(dir, "calls")
	stub := `#!/bin/sh
printf '%s\n' "$*" >> "$STUB_LOG"
[ -z "${STUB_STDERR:-}" ] || printf '%s\n' "$STUB_STDERR" >&2
case "$1 $2" in
"bd show") printf '%s\n' "$STUB_SHOW"; exit "${STUB_SHOW_RC:-0}" ;;
"bd blocked") printf '%s\n' "$STUB_BLOCKED"; exit "${STUB_BLOCKED_RC:-0}" ;;
"bd sql") printf '%s\n' "$STUB_MARKS"; exit "${STUB_MARKS_RC:-0}" ;;
esac
echo "stub gc: no answer for $*" >&2
exit 2
`
	if err := os.WriteFile(filepath.Join(dir, "gc"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STUB_LOG", log)
	t.Setenv("STUB_SHOW", show)
	t.Setenv("STUB_BLOCKED", blocked)
	t.Setenv("STUB_MARKS", marks)
	return log
}

// The rows the cases read: a bead with a blocks edge onto an open bead, one held
// only through its blocked parent, one with a waits-for edge of its own, one
// with a waits-for edge the listing leaves out, one the listing lost, one the
// listing names by a bead its row does not reach, and one nothing holds.
const blockedRows = `[
 {"id":"b-own","status":"open","dependencies":[{"id":"b-blocker","dependency_type":"blocks","status":"in_progress"}]},
 {"id":"b-child","status":"open","dependencies":[{"id":"b-parent","dependency_type":"parent-child","status":"open"}]},
 {"id":"b-waits","status":"open","dependencies":[{"id":"b-parent","dependency_type":"parent-child","status":"open"},{"id":"b-spawner","dependency_type":"waits-for","status":"closed","closed_at":"2026-11-08T10:00:00Z"}]},
 {"id":"b-waits-lost","status":"open","dependencies":[{"id":"b-spawner","dependency_type":"waits-for","status":"closed"}]},
 {"id":"b-lost","status":"open","dependencies":[{"id":"b-parent","dependency_type":"parent-child","status":"open"}]},
 {"id":"b-stranger","status":"open","dependencies":[{"id":"b-parent","dependency_type":"parent-child","status":"open"}]},
 {"id":"b-clear","status":"open","dependencies":[{"id":"b-done","dependency_type":"blocks","status":"closed","closed_at":"2026-11-07T09:00:00Z"}]}
]`

const blockedListing = `[
 {"id":"b-own","status":"open","blocked_by":["b-blocker"],"blocked_by_count":1},
 {"id":"b-child","status":"open","blocked_by":["b-parent"],"blocked_by_count":1},
 {"id":"b-waits","status":"open","blocked_by":["b-parent"],"blocked_by_count":1},
 {"id":"b-stranger","status":"open","blocked_by":["b-elsewhere"],"blocked_by_count":1}
]`

const blockedMarks = `[{"id":"b-own"},{"id":"b-child"},{"id":"b-waits"},{"id":"b-waits-lost"},{"id":"b-lost"},{"id":"b-stranger"}]`

func readBlocked(t *testing.T) (map[string]*Bead, *BlockedSet, string) {
	t.Helper()
	log := blockedStub(t, blockedRows, blockedListing, blockedMarks)
	c := &Client{bin: "gc"}
	rows, err := c.Rows([]string{"b-own", "b-child", "b-waits", "b-waits-lost", "b-lost", "b-stranger", "b-clear"})
	if err != nil {
		t.Fatalf("Rows: %v", err)
	}
	set, err := c.Blocked()
	if err != nil {
		t.Fatalf("Blocked: %v", err)
	}
	byID := map[string]*Bead{}
	for i := range rows {
		byID[rows[i].ID] = &rows[i]
	}
	return byID, set, log
}

func TestBlockedAnswersFromTheListing(t *testing.T) {
	rows, set, _ := readBlocked(t)
	for _, tc := range []struct {
		id   string
		want Blocking
	}{
		{"b-own", Blocking{Blocked: true, On: []string{"b-blocker"}}},
		{"b-child", Blocking{Blocked: true, Through: "b-parent"}},
		{"b-clear", Blocking{}},
	} {
		got, err := set.Answer(rows[tc.id])
		if err != nil {
			t.Errorf("%s: %v", tc.id, err)
			continue
		}
		if got.Blocked != tc.want.Blocked || got.Through != tc.want.Through || !slices.Equal(got.On, tc.want.On) {
			t.Errorf("%s: %+v, want %+v", tc.id, got, tc.want)
		}
	}
}

// A bead with a waits-for edge of its own gets the waits-for error whether the
// listing names it, here by a parent that holds nothing, or leaves it out.
func TestBlockedWaitsForComesFromTheBeadsOwnEdge(t *testing.T) {
	rows, set, _ := readBlocked(t)
	for _, id := range []string{"b-waits", "b-waits-lost"} {
		_, err := set.Answer(rows[id])
		var wf *WaitsForError
		if !errors.As(err, &wf) {
			t.Fatalf("%s: %v, want a *WaitsForError", id, err)
		}
		if wf.ID != id || !slices.Equal(wf.Spawners, []string{"b-spawner"}) {
			t.Errorf("%s: %+v, want its own spawner named", id, wf)
		}
		var re *ReadError
		if errors.As(err, &re) {
			t.Errorf("%s: the waits-for error reads as a *ReadError too", id)
		}
	}
}

// A marked bead the listing lost has no waits-for edge, so it gets the read
// error, never the waits-for one. So does one the listing names by a bead its
// row does not reach.
func TestBlockedListingThatLosesABeadIsAReadError(t *testing.T) {
	rows, set, _ := readBlocked(t)
	for _, id := range []string{"b-lost", "b-stranger"} {
		_, err := set.Answer(rows[id])
		var re *ReadError
		if !errors.As(err, &re) || re.ID != id {
			t.Fatalf("%s: %v, want a *ReadError naming it", id, err)
		}
		var wf *WaitsForError
		if errors.As(err, &wf) {
			t.Errorf("%s: a lost bead reads as a *WaitsForError", id)
		}
	}
}

// The marks read asks the store the question bd's own listing starts from, over
// both of its tables.
func TestBlockedAsksTheListingAndTheMarks(t *testing.T) {
	_, _, log := readBlocked(t)
	raw, err := os.ReadFile(log)
	if err != nil {
		t.Fatal(err)
	}
	calls := strings.Split(strings.TrimSpace(string(raw)), "\n")
	want := []string{
		"bd show b-own b-child b-waits b-waits-lost b-lost b-stranger b-clear --json",
		"bd blocked --json",
		"bd sql --json " + marksQuery,
	}
	if !slices.Equal(calls, want) {
		t.Fatalf("calls:\n%s\nwant:\n%s", strings.Join(calls, "\n"), strings.Join(want, "\n"))
	}
	for _, table := range []string{"FROM issues WHERE is_blocked = 1", "FROM wisps WHERE is_blocked = 1"} {
		if !strings.Contains(marksQuery, table) {
			t.Errorf("the marks read does not read %q", table)
		}
	}
}

// A read that fails is a *ReadError naming no bead, and so is a reply that is
// not one JSON array.
func TestBlockedReadThatFailsIsAReadError(t *testing.T) {
	for _, tc := range []struct {
		name, env, value string
		blocked, marks   string
	}{
		{"the listing exits non-zero", "STUB_BLOCKED_RC", "1", blockedListing, blockedMarks},
		{"the marks read exits non-zero", "STUB_MARKS_RC", "1", blockedListing, blockedMarks},
		{"the listing is not an array", "", "", `{"error":"dolt timeout"}`, blockedMarks},
		{"the listing has more after its array", "", "", blockedListing + "[]", blockedMarks},
		{"the marks are not an array", "", "", blockedListing, `null`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			blockedStub(t, blockedRows, tc.blocked, tc.marks)
			if tc.env != "" {
				t.Setenv(tc.env, tc.value)
			}
			set, err := (&Client{bin: "gc"}).Blocked()
			var re *ReadError
			if !errors.As(err, &re) || re.ID != "" || set != nil {
				t.Fatalf("Blocked = %v, %v; want a *ReadError naming no bead", set, err)
			}
		})
	}
	t.Run("rows that do not read", func(t *testing.T) {
		blockedStub(t, blockedRows, blockedListing, blockedMarks)
		t.Setenv("STUB_SHOW_RC", "1")
		rows, err := (&Client{bin: "gc"}).Rows([]string{"b-own"})
		var re *ReadError
		if !errors.As(err, &re) || rows != nil {
			t.Fatalf("Rows = %v, %v; want a *ReadError", rows, err)
		}
	})
	// bd's show leaves out a bead it does not hold and one whose lookup failed
	// alike, and exits 0 while it found another, so a bead named that the reply
	// carries no row for is a read that could not answer it.
	t.Run("a bead the reply carries no row for", func(t *testing.T) {
		blockedStub(t, `[{"id":"b-own","status":"open"}]`, blockedListing, blockedMarks)
		rows, err := (&Client{bin: "gc"}).Rows([]string{"b-own", "b-gone"})
		var re *ReadError
		if !errors.As(err, &re) || re.ID != "b-gone" || rows != nil {
			t.Fatalf("Rows = %v, %v; want a *ReadError naming b-gone", rows, err)
		}
	})
}

// A read that exits non-zero says what failed: the error bd's --json reply
// carries on stdout, ahead of gc's notice of the store it answers from on
// stderr, else stderr's first line, where gc reports a failure of its own.
func TestAFailedReadSaysWhatFailed(t *testing.T) {
	const notice = `gc bd: answering from the rig "gc-toolkit" store`
	for _, tc := range []struct {
		name, show, stderr, want, wantNot string
	}{
		{"bd's error on stdout", `{"error":"no issues found matching the provided IDs","schema_version":1}`, notice + "\nIssue b-gone not found",
			"gc bd show exited 1: no issues found matching the provided IDs", notice},
		{"gc's error on stderr", "", "Error: unknown flag: --json", "gc bd show exited 1: Error: unknown flag: --json", ""},
		{"no error printed", "", "", "gc bd show exited 1: it printed no error", ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			blockedStub(t, tc.show, blockedListing, blockedMarks)
			t.Setenv("STUB_SHOW_RC", "1")
			t.Setenv("STUB_STDERR", tc.stderr)
			_, err := (&Client{bin: "gc"}).Rows([]string{"b-gone"})
			var re *ReadError
			if !errors.As(err, &re) || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("Rows = %v; want a *ReadError saying %q", err, tc.want)
			}
			if tc.wantNot != "" && strings.Contains(err.Error(), tc.wantNot) {
				t.Errorf("Rows = %v; it names gc's notice rather than what failed", err)
			}
		})
	}
}

func TestEdgesCarryTheFarBead(t *testing.T) {
	b := decode(t, `[{"id":"b","dependencies":[{"id":"d","dependency_type":"blocks","status":"closed","closed_at":"2026-11-07T09:00:00Z"},{"id":"p","dependency_type":"parent-child","status":"open","closed_at":null}]}]`)
	edges, err := b.Edges()
	if err != nil {
		t.Fatal(err)
	}
	want := []Edge{
		{Type: "blocks", ID: "d", Status: "closed", ClosedAt: "2026-11-07T09:00:00Z"},
		{Type: "parent-child", ID: "p", Status: "open"},
	}
	if !slices.Equal(edges, want) {
		t.Fatalf("Edges = %+v, want %+v", edges, want)
	}
	if _, err := decode(t, `[{"id":"b","dependencies":[{"id":"d"}]}]`).Edges(); err == nil {
		t.Error("an edge with no type decoded")
	}
}
