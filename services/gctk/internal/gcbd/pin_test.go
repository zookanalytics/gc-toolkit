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
// `config show --json` from $STUB_CONFIG, each at its own exit code, logs every
// call, and answers no other, `rig list` among them.
func routeStub(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	log := filepath.Join(dir, "calls")
	stub := `#!/bin/sh
printf '%s\n' "$*" >> "$STUB_LOG"
case "$*" in
"bd where --json") printf '%s\n' "$STUB_WHERE"; exit "${STUB_WHERE_RC:-0}" ;;
"config show --json") printf '%s\n' "$STUB_CONFIG"; exit "${STUB_CONFIG_RC:-0}" ;;
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

// The city's config as `gc config show --json` prints it: the city's own store
// in the folder it was read from, under [workspace], and its rigs, among them
// one whose prefix begins another's, one bound to no folder, one whose prefix
// the config leaves for Gas City to derive from its name, and one whose folder
// it gives relative to the city's.
const routeConfig = `{"schema_version":"1","city_path":"/city","config":{
 "Workspace":{"Name":"city","Prefix":"hq","Provider":"claude"},
 "Rigs":[
  {"Name":"gc-toolkit","Path":"/city/rigs/gc-toolkit","Prefix":"tk","Suspended":false},
  {"Name":"tk-extra","Path":"/city/rigs/extra","Prefix":"tk-x"},
  {"Name":"unbound","Path":"","Prefix":"ub"},
  {"Name":"myFrontend","Path":"/city/rigs/front","Prefix":""},
  {"Name":"project","Path":"rigs/project","Prefix":"pr"}]},
 "warnings":[],"validation":{"ok":true,"warnings":[],"errors":[]}}`

// readsTheConfigOnly fails t unless every call in log read the city's config,
// or named the store gc resolves, and none listed the rigs.
func readsTheConfigOnly(t *testing.T, log string) {
	t.Helper()
	for _, call := range findCalls(t, log) {
		if call != "config show --json" && call != "bd where --json" {
			t.Errorf("call %q; want only the config read and the store gc resolves", call)
		}
	}
}

// StoreOf names the store whose prefix begins the id, the longest such when
// several do, and none when no bound store's prefix begins it, from the city's
// config alone. A prefix the config leaves unset is the one Gas City derives
// from the name, and a folder it gives as a relative path is under the city's.
func TestStoreOfNamesTheLongestPrefix(t *testing.T) {
	log := routeStub(t)
	t.Setenv("STUB_CONFIG", routeConfig)
	c := &Client{bin: "gc"}
	for _, tc := range []struct {
		id, want string
		ok       bool
	}{
		{"tk-ssm8qns.12", "/city/rigs/gc-toolkit/.beads", true},
		{"tk-x-1", "/city/rigs/extra/.beads", true},
		{"hq-wisp-1a2b3", "/city/.beads", true},
		{"mf-7", "/city/rigs/front/.beads", true},
		{"pr-1", "/city/rigs/project/.beads", true},
		{"ub-1", "", false},
		{"zz-1", "", false},
		{"tkx-1", "", false},
	} {
		got, ok, err := c.StoreOf(tc.id)
		if err != nil || got != tc.want || ok != tc.ok {
			t.Errorf("StoreOf(%q) = %q, %v, %v; want %q, %v", tc.id, got, ok, err, tc.want, tc.ok)
		}
	}
	readsTheConfigOnly(t, log)
	var re *ReadError
	for _, tc := range []struct{ config, rc string }{
		{routeConfig, "1"},
		{"not json", "0"},
		{`{"schema_version":"1","city_path":"/city"}`, "0"},
	} {
		t.Setenv("STUB_CONFIG", tc.config)
		t.Setenv("STUB_CONFIG_RC", tc.rc)
		if _, _, err := c.StoreOf("tk-1"); !errors.As(err, &re) || re.ID != "tk-1" {
			t.Errorf("StoreOf over a config %q at exit %s = %v; want a *ReadError for tk-1", tc.config, tc.rc, err)
		}
	}
}

// The city's own prefix, when its config sets none, is the one Gas City
// derives from the city's name.
func TestStoreOfDerivesTheCitysPrefix(t *testing.T) {
	routeStub(t)
	t.Setenv("STUB_CONFIG", `{"city_path":"/town","config":{"Workspace":{"Name":"loomington","Prefix":""},"Rigs":[]}}`)
	c := &Client{bin: "gc"}
	if got, ok, err := c.StoreOf("lo-1"); err != nil || !ok || got != "/town/.beads" {
		t.Errorf("StoreOf(lo-1) = %q, %v, %v; want the city's store, /town/.beads", got, ok, err)
	}
}

// derivedPrefix gives the prefix Gas City derives from a name, on Gas City's
// own cases (TestDeriveBeadsPrefix in internal/config/config_test.go at
// gastownhall/gascity f5302d1dcf).
func TestDerivedPrefixFollowsGasCity(t *testing.T) {
	for name, want := range map[string]string{
		"my-frontend": "mf", "my-backend": "mb", "backend": "ba", "frontend": "fr",
		"tower-of-hanoi": "toh", "api": "api", "db": "db", "x": "x",
		"myFrontend": "mf", "GasCity": "gc", "my-project-go": "mp", "my-project-py": "mp",
		"hello_world": "hw", "a-b-c-d": "abcd", "longname": "lo",
	} {
		if got := derivedPrefix(name); got != want {
			t.Errorf("derivedPrefix(%q) = %q, want %q", name, got, want)
		}
	}
}

// RigStore names the .beads directory under the folder the city's config gives
// the rig of that name, the city's among them, from one read of the config
// each, under the city's folder when the config gives a relative path. A
// prefix is no rig's name, a rig the config binds to no folder has no
// store, and a config that does not read or decode is a *ReadError.
func TestRigStoreNamesTheRigsBeadsDirectory(t *testing.T) {
	log := routeStub(t)
	t.Setenv("STUB_CONFIG", routeConfig)
	c := &Client{bin: "gc"}
	cases := []struct {
		name, want string
		ok         bool
	}{
		{"gc-toolkit", "/city/rigs/gc-toolkit/.beads", true},
		{"city", "/city/.beads", true},
		{"project", "/city/rigs/project/.beads", true},
		{"tk", "", false},
		{"unbound", "", false},
		{"nowhere", "", false},
	}
	for _, tc := range cases {
		got, ok, err := c.RigStore(tc.name)
		if err != nil || got != tc.want || ok != tc.ok {
			t.Errorf("RigStore(%q) = %q, %v, %v; want %q, %v", tc.name, got, ok, err, tc.want, tc.ok)
		}
	}
	if got := findCalls(t, log); len(got) != len(cases) || slices.ContainsFunc(got, func(c string) bool { return c != "config show --json" }) {
		t.Errorf("calls = %q, want one config read each", got)
	}
	var re *ReadError
	t.Setenv("STUB_CONFIG_RC", "1")
	if _, _, err := c.RigStore("gc-toolkit"); !errors.As(err, &re) {
		t.Errorf("RigStore with a config that did not read = %v; want a *ReadError", err)
	}
	t.Setenv("STUB_CONFIG_RC", "0")
	t.Setenv("STUB_CONFIG", "not json")
	if _, _, err := c.RigStore("gc-toolkit"); !errors.As(err, &re) {
		t.Errorf("RigStore with a config that did not decode = %v; want a *ReadError", err)
	}
}

// Route keeps the store gc resolves when its prefix begins the first id, and
// reads the city's config only for a bead in another, as gc routes a read that
// names a bead and no store. A config that does not read leaves the resolved
// store.
func TestRouteFollowsTheFirstBeadsPrefix(t *testing.T) {
	log := routeStub(t)
	t.Setenv("STUB_WHERE", `{"path":"/city/.beads","prefix":"hq"}`)
	t.Setenv("STUB_CONFIG", routeConfig)
	c := &Client{bin: "gc"}
	for _, tc := range []struct {
		ids   []string
		want  string
		lists bool
	}{
		{nil, "/city/.beads", false},
		{[]string{"hq-10", "tk-2"}, "/city/.beads", false},
		{[]string{"tk-2", "hq-10"}, "/city/rigs/gc-toolkit/.beads", true},
		{[]string{"mf-3"}, "/city/rigs/front/.beads", true},
		{[]string{"pr-4"}, "/city/rigs/project/.beads", true},
		{[]string{"zz-9"}, "/city/.beads", true},
	} {
		if err := os.WriteFile(log, nil, 0o644); err != nil {
			t.Fatal(err)
		}
		got, err := c.Route(tc.ids...)
		if err != nil || got != tc.want {
			t.Errorf("Route(%q) = %q, %v; want %q", tc.ids, got, err, tc.want)
		}
		if read := slices.Contains(findCalls(t, log), "config show --json"); read != tc.lists {
			t.Errorf("Route(%q) read the config = %v; want %v", tc.ids, read, tc.lists)
		}
		readsTheConfigOnly(t, log)
	}
	t.Setenv("STUB_CONFIG_RC", "1")
	if got, err := c.Route("tk-2"); err != nil || got != "/city/.beads" {
		t.Errorf("Route over a config that did not read = %q, %v; want the resolved store", got, err)
	}
	t.Setenv("STUB_WHERE_RC", "1")
	var re *ReadError
	if _, err := c.Route("tk-2"); !errors.As(err, &re) {
		t.Errorf("Route with no resolved store = %v; want a *ReadError", err)
	}
}
