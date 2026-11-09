package gcbd

import (
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// pinStub puts a `gc` on PATH that logs each call's argv and answers every read
// with an empty array.
func pinStub(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	log := filepath.Join(dir, "calls")
	stub := `#!/bin/sh
printf '%s\n' "$*" >> "$STUB_LOG"
echo '[]'
`
	if err := os.WriteFile(filepath.Join(dir, "gc"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STUB_LOG", log)
	return log
}

// A pinned client names its store ahead of the verb on every call, the
// listing, the rows, the blocked set and its marks alike, and reads none of
// them from the supervisor.
func TestInNamesTheStoreOnEveryCall(t *testing.T) {
	log := pinStub(t)
	c := (&Client{bin: "gc", baseURL: "http://supervisor", city: "city"}).In("/rig/.beads")
	if c.daemonConfigured() {
		t.Error("a pinned client still reads the supervisor's bead route, which answers from another store")
	}
	if _, err := c.Find(Query{IDs: []string{"b-1"}}); err != nil {
		t.Fatal(err)
	}
	if _, err := c.Rows([]string{"b-1"}); err == nil {
		t.Fatal("rows: want the error for a bead the reply carries no row for")
	}
	if _, err := c.Blocked(); err != nil {
		t.Fatal(err)
	}
	calls := findCalls(t, log)
	if len(calls) != 4 {
		t.Fatalf("calls = %q, want the listing, the rows, the blocked set and its marks", calls)
	}
	for _, call := range calls {
		if !strings.HasPrefix(call, "bd --db /rig/.beads ") {
			t.Errorf("call %q does not name the store ahead of its verb", call)
		}
	}
}

// A call that names its own store keeps it, and an empty pin is no pin.
func TestInKeepsAStoreTheCallNames(t *testing.T) {
	log := pinStub(t)
	c := (&Client{bin: "gc"}).In("/rig/.beads")
	c.array(false, "bd", "show", "b-1", "--db", "/other/.beads", "--json")
	if got := findCalls(t, log); !slices.Equal(got, []string{"bd show b-1 --db /other/.beads --json"}) {
		t.Errorf("calls = %q, want the store the call names and no other", got)
	}
	plain := &Client{bin: "gc"}
	if plain.In("") != plain {
		t.Error("In(\"\") returned a new client; want the same one, pinned to nothing")
	}
}

// Where names the store gc resolves, and a reply that names none fails the read.
func TestWhereNamesTheResolvedStore(t *testing.T) {
	dir := t.TempDir()
	stub := `#!/bin/sh
case "$*" in
"bd where --json") printf '%s\n' "$STUB_WHERE"; exit "${STUB_WHERE_RC:-0}" ;;
esac
echo "stub gc: no answer for $*" >&2
exit 2
`
	if err := os.WriteFile(filepath.Join(dir, "gc"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	c := &Client{bin: "gc"}
	t.Setenv("STUB_WHERE", `{"path":"/rig/.beads","prefix":"tk"}`)
	if got, err := c.Where(); err != nil || got != "/rig/.beads" {
		t.Errorf("Where() = %q, %v; want /rig/.beads", got, err)
	}
	for _, tc := range []struct{ reply, rc string }{
		{`{"prefix":"tk"}`, "0"},
		{`{"error":"no beads database found","schema_version":1}`, "1"},
	} {
		t.Setenv("STUB_WHERE", tc.reply)
		t.Setenv("STUB_WHERE_RC", tc.rc)
		var re *ReadError
		if _, err := c.Where(); !errors.As(err, &re) {
			t.Errorf("Where() on %s = %v; want a *ReadError", tc.reply, err)
		}
	}
}
