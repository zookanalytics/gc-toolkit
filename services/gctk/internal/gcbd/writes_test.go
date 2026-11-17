package gcbd

import (
	"errors"
	"os"
	"strings"
	"testing"
	"time"
)

// LastWrites asks the store once for the newest write of every actor named,
// over both write logs, and reads each row's time.
func TestLastWritesReadsTheWriteLog(t *testing.T) {
	log := blockedStub(t, "", "", `[{"actor":"hq-a","newest":"2026-11-16T23:21:19Z"},{"actor":"rig/gc-toolkit.polecat-2","newest":"2026-11-16T20:00:00.5Z"}]`)
	got, err := (&Client{bin: "gc"}).LastWrites([]string{"rig/gc-toolkit.polecat-2", "hq-a", "hq-none", "hq-a"})
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]time.Time{
		"hq-a":                     time.Date(2026, 11, 16, 23, 21, 19, 0, time.UTC),
		"rig/gc-toolkit.polecat-2": time.Date(2026, 11, 16, 20, 0, 0, 5e8, time.UTC),
	}
	if len(got) != len(want) || !got["hq-a"].Equal(want["hq-a"]) || !got["rig/gc-toolkit.polecat-2"].Equal(want["rig/gc-toolkit.polecat-2"]) {
		t.Errorf("read %v", got)
	}
	raw, _ := os.ReadFile(log)
	call := strings.TrimSpace(string(raw))
	if strings.Count(call, "\n") != 0 || !strings.HasPrefix(call, "bd sql --json SELECT actor") {
		t.Fatalf("the store was asked %q", call)
	}
	for _, part := range []string{"FROM events WHERE actor IN ('hq-a','hq-none','rig/gc-toolkit.polecat-2')", "FROM wisp_events WHERE actor IN ('hq-a','hq-none','rig/gc-toolkit.polecat-2')"} {
		if !strings.Contains(call, part) {
			t.Errorf("the query lacks %q: %s", part, call)
		}
	}
}

// A read of no actors asks the store nothing.
func TestLastWritesOfNoActors(t *testing.T) {
	log := blockedStub(t, "", "", "")
	got, err := (&Client{bin: "gc"}).LastWrites(nil)
	if err != nil || len(got) != 0 {
		t.Errorf("answered %v, %v", got, err)
	}
	if raw, _ := os.ReadFile(log); len(raw) != 0 {
		t.Errorf("the store was asked %q", raw)
	}
}

// A name a query cannot hold is refused before the store is asked, and a read
// that fails or a row that does not read is a read error, never an empty
// answer.
func TestLastWritesFailsClosed(t *testing.T) {
	log := blockedStub(t, "", "", "[]")
	var rerr *ReadError
	if _, err := (&Client{bin: "gc"}).LastWrites([]string{"hq-a", "x' OR '1'='1"}); !errors.As(err, &rerr) {
		t.Errorf("an actor with a quote answered %v", err)
	}
	if raw, _ := os.ReadFile(log); len(raw) != 0 {
		t.Errorf("the store was asked %q", raw)
	}
	for _, c := range []struct{ answer, rc string }{
		{`{"error":"no such table: wisp_events"}`, "1"},
		{`[]`, "1"},
		{`{"rows":[]}`, "0"},
		{`[{"actor":"hq-a","newest":"yesterday"}]`, "0"},
		{`[{"actor":"hq-other","newest":"2026-11-16T23:21:19Z"}]`, "0"},
	} {
		blockedStub(t, "", "", c.answer)
		t.Setenv("STUB_MARKS_RC", c.rc)
		if got, err := (&Client{bin: "gc"}).LastWrites([]string{"hq-a"}); !errors.As(err, &rerr) {
			t.Errorf("%s (exit %s) answered %v, %v", c.answer, c.rc, got, err)
		}
	}
}
