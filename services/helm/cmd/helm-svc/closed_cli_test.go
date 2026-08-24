package main

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/closed"
)

func closedRow(visit, subject, title, outcome, takeaway string, at time.Time) closed.Row {
	return closed.Row{
		Rig: "gc-toolkit", Visit: visit, ClosedAt: at, Outcome: outcome,
		Subject: subject, SubjectTitle: title, Takeaway: takeaway,
	}
}

func renderClosed(rows []closed.Row, limit int) string {
	now := time.Date(2026, 8, 24, 6, 0, 0, 0, time.UTC)
	var buf bytes.Buffer
	renderClosedTable(&buf, closed.Build(closed.Input{
		Rows: rows, Now: now, Since: "24h", Cutoff: now.Add(-24 * time.Hour), Limit: limit,
	}))
	return buf.String()
}

// TestParseClosedArgs covers the flag surface, including the fail-closed cases:
// a bad value must be a usage error, never a silently-ignored flag that answers
// a different question than the caller asked.
func TestParseClosedArgs(t *testing.T) {
	t.Run("defaults", func(t *testing.T) {
		o, err := parseClosedArgs(nil)
		if err != nil {
			t.Fatalf("err = %v", err)
		}
		if o.since != "24h" || o.limit != -1 || o.json {
			t.Errorf("defaults = %+v", o)
		}
	})
	t.Run("both spellings of every valued flag", func(t *testing.T) {
		for _, args := range [][]string{
			{"--since=7d", "--limit=3", "--timeout=30"},
			{"--since", "7d", "--limit", "3", "--timeout", "30"},
		} {
			o, err := parseClosedArgs(args)
			if err != nil {
				t.Fatalf("%v: %v", args, err)
			}
			if o.since != "7d" || o.limit != 3 || o.timeout != 30*time.Second {
				t.Errorf("%v parsed to %+v", args, o)
			}
		}
	})
	t.Run("limit 0 is uncapped, not unset", func(t *testing.T) {
		o, err := parseClosedArgs([]string{"--limit=0"})
		if err != nil || o.limit != 0 {
			t.Errorf("limit = %d, err = %v", o.limit, err)
		}
	})
	t.Run("rejections", func(t *testing.T) {
		for _, args := range [][]string{
			{"--limit=-1"}, {"--limit=abc"}, {"--timeout=-5"},
			{"--since"}, {"--limit"}, {"--nonsense"}, {"stray"},
		} {
			if _, err := parseClosedArgs(args); err == nil {
				t.Errorf("%v was accepted; a bad flag must be a usage error", args)
			}
		}
	})
	t.Run("--since is validated by the model, not here", func(t *testing.T) {
		// parseClosedArgs takes the STRING; runClosed hands it to
		// closed.ParseSince. Keeping the spelling rules in one place is what
		// stops the CLI and the HTTP route disagreeing about what "2w" means.
		o, err := parseClosedArgs([]string{"--since=2w"})
		if err != nil {
			t.Fatalf("the parser should carry the string through: %v", err)
		}
		if _, err := closed.ParseSince(o.since); err == nil {
			t.Error("closed.ParseSince accepted 2w")
		}
	})
}

// TestClosedJSONIsABareArray pins the shape half of the contract, which a field
// check cannot see. `helm-svc board --json` made the same choice for the same
// reason: gc-helm.sh's `closed --json` promises an array, and an envelope would
// make every row invisible to a `jq '.[]'` while still parsing cleanly.
func TestClosedJSONIsABareArray(t *testing.T) {
	var out, errBuf bytes.Buffer
	rows := []closed.Row{closedRow("tk-v", "tk-s", "t", "routed", "why", time.Now().UTC())}
	if rc := renderClosedJSON(&out, &errBuf, rows); rc != boardExitOK {
		t.Fatalf("rc = %d", rc)
	}
	var arr []closed.Row
	if err := json.Unmarshal(out.Bytes(), &arr); err != nil {
		t.Fatalf("not an array: %v (%s)", err, out.String())
	}
	if len(arr) != 1 || arr[0].Visit != "tk-v" {
		t.Errorf("decoded %+v", arr)
	}
}

// TestClosedJSONEmptyIsArrayNotNull — a consumer running `jq 'length'` over an
// empty window must read 0, not an error.
func TestClosedJSONEmptyIsArrayNotNull(t *testing.T) {
	var out, errBuf bytes.Buffer
	if rc := renderClosedJSON(&out, &errBuf, nil); rc != boardExitOK {
		t.Fatalf("rc = %d", rc)
	}
	if got := strings.TrimSpace(out.String()); got != "[]" {
		t.Errorf("empty output = %q, want []", got)
	}
}

// TestClosedTableSaysAQuietWindowIsQuiet — the two answers look identical
// otherwise, and only one of them means nothing was decided.
func TestClosedTableSaysAQuietWindowIsQuiet(t *testing.T) {
	out := renderClosed(nil, 0)
	if !strings.Contains(out, "No visit reached a disposition") {
		t.Errorf("empty render = %q", out)
	}
	if !strings.Contains(out, "exits 3") {
		t.Error("the empty render must distinguish itself from a failed read")
	}
}

// TestClosedTableRendersIncompleteRows — a closed visit is terminal whether or
// not sign-off stamped it, and dropping the row would hide the very disposition
// whose record is incomplete.
func TestClosedTableRendersIncompleteRows(t *testing.T) {
	now := time.Date(2026, 8, 24, 5, 0, 0, 0, time.UTC)
	out := renderClosed([]closed.Row{closedRow("tk-bare", "", "", "", "", now)}, 0)
	if !strings.Contains(out, "(unlinked)") {
		t.Errorf("a subject-less visit must render as (unlinked):\n%s", out)
	}
	if !strings.Contains(out, "—") {
		t.Errorf("an empty cell must read as 'this row has none':\n%s", out)
	}
}

// TestClosedTableIDsStayDistinct is the tk-mtuej rule on this view's id column.
// A hierarchical bead id carries its discriminator in the TAIL, so a fixed
// width renders three distinct subjects as three identical cells — and the
// operator cannot tell which decision belongs to which.
func TestClosedTableIDsStayDistinct(t *testing.T) {
	now := time.Date(2026, 8, 24, 5, 0, 0, 0, time.UTC)
	rows := []closed.Row{
		closedRow("tk-v1", "sl-kg9z6.4.1", "one", "routed", "a", now),
		closedRow("tk-v2", "sl-kg9z6.4.2", "two", "routed", "b", now.Add(-time.Minute)),
		closedRow("tk-v3", "sl-kg9z6.4.9", "nine", "routed", "c", now.Add(-2*time.Minute)),
	}
	out := renderClosed(rows, 0)
	for _, id := range []string{"sl-kg9z6.4.1", "sl-kg9z6.4.2", "sl-kg9z6.4.9"} {
		if !strings.Contains(out, id) {
			t.Errorf("id %s lost its tail:\n%s", id, out)
		}
	}
}

// TestClosedTableBoundsProse — an unbounded takeaway is not a wide cell but a
// single row wrapping over every row beneath it. --json keeps both strings
// whole, so nothing is lost by clipping the table.
func TestClosedTableBoundsProse(t *testing.T) {
	now := time.Date(2026, 8, 24, 5, 0, 0, 0, time.UTC)
	long := strings.Repeat("x", 900)
	out := renderClosed([]closed.Row{closedRow("tk-v", "tk-s", long, "routed", long, now)}, 0)
	for _, line := range strings.Split(out, "\n") {
		if strings.Contains(line, "tk-s") && len([]rune(line)) > 200 {
			t.Errorf("row is %d runes; the prose columns are unbounded", len([]rune(line)))
		}
	}
	if !strings.Contains(out, "…") {
		t.Error("a clipped cell must say it was clipped")
	}
}

// TestClosedTableSaysWhatItHid — a capped list that looked complete would be a
// quiet lie about the window.
func TestClosedTableSaysWhatItHid(t *testing.T) {
	now := time.Date(2026, 8, 24, 5, 0, 0, 0, time.UTC)
	var rows []closed.Row
	for i := range 10 {
		rows = append(rows, closedRow("tk-v"+string(rune('a'+i)), "tk-s", "t", "routed", "w", now.Add(-time.Duration(i)*time.Minute)))
	}
	out := renderClosed(rows, 3)
	if !strings.Contains(out, "Showing the newest 3 of 10") {
		t.Errorf("a capped table must name what it hid:\n%s", out)
	}
	if strings.Contains(renderClosed(rows, 0), "Showing the newest") {
		t.Error("an uncapped table must not claim to be hiding rows")
	}
}

// TestClosedTableStatesTheWindow — "the last 24h" is ambiguous about WHICH 24
// hours, and an operator comparing two glances needs the absolute instant.
func TestClosedTableStatesTheWindow(t *testing.T) {
	now := time.Date(2026, 8, 24, 5, 0, 0, 0, time.UTC)
	out := renderClosed([]closed.Row{closedRow("tk-v", "tk-s", "t", "routed", "w", now)}, 0)
	if !strings.Contains(out, "2026-08-23T06:00:00Z") {
		t.Errorf("the cutoff instant is not stated:\n%s", out)
	}
	if !strings.Contains(out, "per VISIT") {
		t.Error("the table must say rows are per-visit, or a repeated subject reads as a bug")
	}
}
