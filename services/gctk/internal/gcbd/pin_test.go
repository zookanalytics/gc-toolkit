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

// routeStub puts a `gc` on PATH that answers `bd where` from $STUB_WHERE and
// `rig list` from $STUB_RIGS, each at its own exit code, and logs every call.
func routeStub(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	log := filepath.Join(dir, "calls")
	stub := `#!/bin/sh
printf '%s\n' "$*" >> "$STUB_LOG"
case "$*" in
"bd where --json") printf '%s\n' "$STUB_WHERE"; exit "${STUB_WHERE_RC:-0}" ;;
"rig list --json") printf '%s\n' "$STUB_RIGS"; exit "${STUB_RIGS_RC:-0}" ;;
esac
echo "stub gc: no answer for $*" >&2
exit 2
`
	if err := os.WriteFile(filepath.Join(dir, "gc"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STUB_LOG", log)
	return log
}

// Where names the store gc resolves and its prefix, and a reply that names no
// store fails the read.
func TestWhereNamesTheResolvedStore(t *testing.T) {
	routeStub(t)
	c := &Client{bin: "gc"}
	t.Setenv("STUB_WHERE", `{"path":"/rig/.beads","prefix":"tk"}`)
	if path, prefix, err := c.Where(); err != nil || path != "/rig/.beads" || prefix != "tk" {
		t.Errorf("Where() = %q, %q, %v; want /rig/.beads, tk", path, prefix, err)
	}
	for _, tc := range []struct{ reply, rc string }{
		{`{"prefix":"tk"}`, "0"},
		{`{"error":"no beads database found","schema_version":1}`, "1"},
	} {
		t.Setenv("STUB_WHERE", tc.reply)
		t.Setenv("STUB_WHERE_RC", tc.rc)
		var re *ReadError
		if _, _, err := c.Where(); !errors.As(err, &re) {
			t.Errorf("Where() on %s = %v; want a *ReadError", tc.reply, err)
		}
	}
}

// The stores this city names, the city's among them, with a rig whose prefix
// begins another's.
const routeRigs = `{"rigs":[
 {"name":"city","prefix":"hq","path":"/city","hq":true},
 {"name":"gc-toolkit","prefix":"tk","path":"/city/rigs/gc-toolkit"},
 {"name":"tk-extra","prefix":"tk-x","path":"/city/rigs/extra"},
 {"name":"unbound","prefix":"ub","path":""}]}`

// StoreOf names the store whose prefix begins the id, the longest such when
// several do, and none when no bound store's prefix begins it.
func TestStoreOfNamesTheLongestPrefix(t *testing.T) {
	routeStub(t)
	t.Setenv("STUB_RIGS", routeRigs)
	c := &Client{bin: "gc"}
	for _, tc := range []struct {
		id, want string
		ok       bool
	}{
		{"tk-ssm8qns.12", "/city/rigs/gc-toolkit/.beads", true},
		{"tk-x-1", "/city/rigs/extra/.beads", true},
		{"hq-wisp-1a2b3", "/city/.beads", true},
		{"ub-1", "", false},
		{"zz-1", "", false},
		{"tkx-1", "", false},
	} {
		got, ok, err := c.StoreOf(tc.id)
		if err != nil || got != tc.want || ok != tc.ok {
			t.Errorf("StoreOf(%q) = %q, %v, %v; want %q, %v", tc.id, got, ok, err, tc.want, tc.ok)
		}
	}
	t.Setenv("STUB_RIGS_RC", "1")
	var re *ReadError
	if _, _, err := c.StoreOf("tk-1"); !errors.As(err, &re) {
		t.Errorf("StoreOf with a failed listing = %v; want a *ReadError", err)
	}
}

// Route keeps the store gc resolves when its prefix begins the first id, and
// lists the stores only for a bead in another, as gc routes a read that names a
// bead and no store. A listing that fails leaves the resolved store.
func TestRouteFollowsTheFirstBeadsPrefix(t *testing.T) {
	log := routeStub(t)
	t.Setenv("STUB_WHERE", `{"path":"/city/.beads","prefix":"hq"}`)
	t.Setenv("STUB_RIGS", routeRigs)
	c := &Client{bin: "gc"}
	for _, tc := range []struct {
		ids   []string
		want  string
		lists bool
	}{
		{nil, "/city/.beads", false},
		{[]string{"hq-10", "tk-2"}, "/city/.beads", false},
		{[]string{"tk-2", "hq-10"}, "/city/rigs/gc-toolkit/.beads", true},
		{[]string{"zz-9"}, "/city/.beads", true},
	} {
		if err := os.WriteFile(log, nil, 0o644); err != nil {
			t.Fatal(err)
		}
		got, err := c.Route(tc.ids...)
		if err != nil || got != tc.want {
			t.Errorf("Route(%q) = %q, %v; want %q", tc.ids, got, err, tc.want)
		}
		if listed := slices.Contains(findCalls(t, log), "rig list --json"); listed != tc.lists {
			t.Errorf("Route(%q) listed the stores = %v; want %v", tc.ids, listed, tc.lists)
		}
	}
	t.Setenv("STUB_RIGS_RC", "1")
	if got, err := c.Route("tk-2"); err != nil || got != "/city/.beads" {
		t.Errorf("Route over a failed listing = %q, %v; want the resolved store", got, err)
	}
	t.Setenv("STUB_WHERE_RC", "1")
	var re *ReadError
	if _, err := c.Route("tk-2"); !errors.As(err, &re) {
		t.Errorf("Route with no resolved store = %v; want a *ReadError", err)
	}
}
