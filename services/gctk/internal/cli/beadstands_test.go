package cli

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// stands runs `gctk bead stands` over holdsStore, through the store adapter's
// real reads of the gc stub.
func stands(t *testing.T, args ...string) ([]map[string]any, int) {
	t.Helper()
	bin := t.TempDir()
	if err := os.WriteFile(filepath.Join(bin, "gc"), []byte(storeStub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STUB_STORE", holdsStore)
	if os.Getenv("STUB_BLOCKED") == "" {
		t.Setenv("STUB_BLOCKED", holdsBlocked)
	}
	t.Setenv("STUB_MARKS", holdsMarks)
	var out, errbuf bytes.Buffer
	code := Run(append([]string{"bead", "stands"}, args...), "", &out, &errbuf)
	var lines []map[string]any
	for _, l := range strings.Split(strings.TrimSpace(out.String()), "\n") {
		if l == "" {
			continue
		}
		var m map[string]any
		if err := json.Unmarshal([]byte(l), &m); err != nil {
			t.Fatalf("a line is not one JSON object: %q: %v", l, err)
		}
		lines = append(lines, m)
	}
	return lines, code
}

// The command prints one line per bead, in the order named, each once, with
// every field the contract names: the epic its human gate holds, the gate
// itself, the member held through the epic, the armed bead behind work in
// flight, the member a live workflow works, and the bead behind a waits-for
// edge the store cannot judge.
func TestBeadStandsPrintsOneLinePerBead(t *testing.T) {
	lines, code := stands(t, "epic", "gate", "member", "own", "worked", "waiter", "member")
	if code != 0 || len(lines) != 6 {
		t.Fatalf("exit %d with %d lines; want 0 with one line per bead", code, len(lines))
	}
	want := []string{
		`{"advance":"stuck","ask":"","frontier":"stuck","group":"waiting-on-you","id":"epic","names":[{"id":"gate","title":"park the epic"}],"rule":"own-wait","stuck_on":{"id":"gate","why":"own-wait"},"why":""}`,
		`{"advance":"stuck","ask":"question","frontier":"ready","group":"waiting-on-you","id":"gate","names":[],"rule":"ask","stuck_on":{"id":"gate","why":"question"},"why":""}`,
		`{"advance":"stuck","ask":"","frontier":"stuck","group":"waiting-on-you","id":"member","names":[{"id":"gate","title":"park the epic"}],"rule":"further-along","stuck_on":{"id":"gate","why":"further-along"},"why":""}`,
		`{"advance":"advancing","ask":"","frontier":"advancing","group":"queued","id":"own","names":[{"id":"blocker","title":"the work it waits on"}],"rule":"scheduled","stuck_on":null,"why":""}`,
		`{"advance":"advancing","ask":"","frontier":"ready","group":"queued","id":"worked","names":[],"rule":"in-flight","stuck_on":null,"why":""}`,
		`{"advance":"stuck","ask":"","frontier":"stuck","group":"not-moving","id":"waiter","names":[{"id":"spawner","title":""}],"rule":"not-scheduled","stuck_on":{"id":"waiter","why":"not-scheduled"},"why":""}`,
	}
	for i, w := range want {
		raw, _ := json.Marshal(lines[i])
		if string(raw) != w {
			t.Errorf("line %d = %s\nwant %s", i, raw, w)
		}
	}
}

// A bead the store does not hold, and one with no standing of its own, prints
// its error and no answer, and the command exits 1; every bead does when a read
// fails.
func TestBeadStandsABeadItCannotAnswer(t *testing.T) {
	lines, code := stands(t, "ghost", "cv", "root", "own")
	if code != 1 || len(lines) != 4 {
		t.Fatalf("exit %d, lines %v; want 1 and a line for each bead", code, lines)
	}
	for i, want := range []string{"the store holds no such bead", "it has no standing of its own", "it has no standing of its own"} {
		if e, _ := lines[i]["error"].(string); !strings.HasPrefix(e, want) || lines[i]["rule"] != nil {
			t.Errorf("%v: want an error that begins %q and no answer", lines[i], want)
		}
	}
	if lines[3]["rule"] != "scheduled" {
		t.Errorf("own = %v; want its answer beside the errors", lines[3])
	}
	t.Setenv("STUB_BLOCKED", "{}")
	t.Setenv("STUB_BLOCKED_RC", "1")
	lines, code = stands(t, "member", "own")
	if code != 1 || len(lines) != 2 {
		t.Fatalf("exit %d, lines %v; want 1 and a line for each bead", code, lines)
	}
	for _, l := range lines {
		if l["error"] == nil || l["rule"] != nil {
			t.Errorf("%v: want an error and no answer", l)
		}
	}
}

func TestBeadStandsUsageErrors(t *testing.T) {
	for _, args := range [][]string{{}, {" "}} {
		var out, errbuf bytes.Buffer
		if code := Run(append([]string{"bead", "stands"}, args...), "", &out, &errbuf); code != 2 || out.Len() != 0 {
			t.Errorf("bead stands %q = exit %d, out %q; want a usage error", args, code, out.String())
		}
	}
}

// --db names the store every read of the command makes, and without it every
// read names the store gc routes the first bead to.
func TestBeadStandsReadsTheNamedStore(t *testing.T) {
	for _, tc := range []struct {
		name  string
		args  []string
		store string
		lead  int
	}{
		{"named", []string{"--db", "/rig/.beads", "own"}, "/rig/.beads", 0},
		// The store gc resolves, then the stores, since no prefix begins "own".
		{"resolved", []string{"own"}, "/stub/.beads", 2},
	} {
		t.Run(tc.name, func(t *testing.T) {
			log := filepath.Join(t.TempDir(), "db")
			t.Setenv("STUB_DB_LOG", log)
			lines, code := stands(t, tc.args...)
			if code != 0 || len(lines) != 1 || lines[0]["rule"] != "scheduled" {
				t.Fatalf("exit %d, lines %v; want 0 and own scheduled", code, lines)
			}
			raw, err := os.ReadFile(log)
			if err != nil {
				t.Fatal(err)
			}
			calls := strings.Split(strings.TrimSpace(string(raw)), "\n")
			if len(calls) <= tc.lead {
				t.Fatalf("the stub logged %q; want reads of the store after %d routing read(s)", calls, tc.lead)
			}
			for i, db := range calls[tc.lead:] {
				if db != tc.store {
					t.Errorf("read %d named the store %q; want %s", i+1, db, tc.store)
				}
			}
		})
	}
}
