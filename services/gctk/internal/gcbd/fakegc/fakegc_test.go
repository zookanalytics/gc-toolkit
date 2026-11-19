package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// fixture is a store in a directory of its own, answered in this process.
type fixture struct {
	t   *testing.T
	dir string
	env []string
}

func newFixture(t *testing.T, store, deps string) *fixture {
	t.Helper()
	dir := t.TempDir()
	f := &fixture{t: t, dir: dir}
	for name, body := range map[string]string{"beads.json": store, "deps.txt": deps, "kv.txt": "", "gc.log": "", "session.log": ""} {
		f.write(name, body)
	}
	f.env = []string{
		"STUB_STORE=" + filepath.Join(dir, "beads.json"), "STUB_DEPS=" + filepath.Join(dir, "deps.txt"),
		"STUB_KV=" + filepath.Join(dir, "kv.txt"), "STUB_GC_LOG=" + filepath.Join(dir, "gc.log"),
		"STUB_SESSION_LOG=" + filepath.Join(dir, "session.log"), "PATH=/nonexistent",
	}
	return f
}

func (f *fixture) write(name, body string) {
	f.t.Helper()
	if err := os.WriteFile(filepath.Join(f.dir, name), []byte(body), 0o644); err != nil {
		f.t.Fatal(err)
	}
}

func (f *fixture) file(name string) string {
	f.t.Helper()
	data, err := os.ReadFile(filepath.Join(f.dir, name))
	if err != nil {
		f.t.Fatal(err)
	}
	return string(data)
}

type result struct {
	out, err string
	status   int
}

// run answers `gc <args>` with the settings given ahead of the fixture's own.
func (f *fixture) run(settings []string, args ...string) result {
	return f.runAs("gc", settings, args...)
}

// runAs answers `<name> <args>`, the program run under name.
func (f *fixture) runAs(name string, settings []string, args ...string) result {
	var out, errb bytes.Buffer
	c := &Call{Name: name, Args: args, Env: append(append([]string{}, f.env...), settings...), Stdout: &out, Stderr: &errb}
	status := Run(c)
	return result{out.String(), errb.String(), status}
}

func (f *fixture) gc(args ...string) result { return f.run(nil, args...) }

func TestCanonicalNumber(t *testing.T) {
	// Each want is what jq 1.8.2 prints for the literal.
	for lit, want := range map[string]string{
		"1": "1", "1.0": "1.0", "1.50": "1.50", "1E2": "1E+2", "1.0e2": "1.0E+2", "-0": "-0",
		"100000000000000000001": "100000000000000000001", "1e400": "1E+400", "0.5": "0.5",
		"1e-7": "1E-7", "0.0001234": "0.0001234", "0.00": "0.00", "2.5": "2.5", "-12": "-12",
	} {
		if got := canonicalNumber(lit); got != want {
			t.Errorf("canonicalNumber(%q) = %q, want %q", lit, got, want)
		}
	}
	for s, want := range map[string]string{"01": "1", "+1": "1", "1.": "1", ".5": "0.5", "4.0": "4.0", "1e2": "1E+2"} {
		v, err := toNumber(s)
		if err != nil || Compact(v) != want {
			t.Errorf("toNumber(%q) = %v, %v; want %s", s, Compact(v), err, want)
		}
	}
	for _, s := range []string{" 1", "1 ", "0x10", "", "P1"} {
		if _, err := toNumber(s); err == nil {
			t.Errorf("toNumber(%q) parsed, and jq refuses it", s)
		}
	}
}

func TestCompactAndRawPrintAsJq(t *testing.T) {
	v, err := Decode([]byte(`{"s":"a\u007fb </>&\u0000\b\f\u000b\t","b":true,"z":null,"a":[],"o":{},"n":[1,{"c":null}],"a":2}`))
	if err != nil {
		t.Fatal(err)
	}
	want := `{"s":"a\u007fb` + " " + `</>&\u0000\b\f\u000b\t","b":true,"z":null,"a":2,"o":{},"n":[1,{"c":null}]}`
	if got := Compact(v); got != want {
		t.Errorf("Compact:\n got %s\nwant %s", got, want)
	}
	o := v.(*Object)
	if got := Raw(get(o, "n")); got != "[\n  1,\n  {\n    \"c\": null\n  }\n]" {
		t.Errorf("Raw of an array = %q", got)
	}
	if got := Raw(get(o, "o")); got != "{}" {
		t.Errorf("Raw of an empty object = %q", got)
	}
}

func TestUpdateStoresTypedValuesInPlace(t *testing.T) {
	f := newFixture(t, `[{"id":"a","status":"open","metadata":{"keep":"k","typed":"old","gone":"g"}},{"id":"b"}]`, "")
	r := f.gc("bd", "update", "a", "--set-metadata", "typed=1", "--set-metadata", "flag=true", "--set-metadata", "txt= 007 ",
		"--set-metadata", "num= 7 ", "--set-metadata", "plus=+1", "--set-metadata", "eq=a=b", "--unset-metadata", "gone",
		"--status=closed", "--append-notes", "n1", "--priority=P1")
	if r.status != 0 || r.out != "updated a\n" {
		t.Fatalf("update: %+v", r)
	}
	want := `[{"id":"a","status":"closed","metadata":{"keep":"k","typed":1,"flag":true,"txt":" 007 ","num":7,"plus":"+1","eq":"a=b"},"priority":1,"notes":"n1"},{"id":"b"}]` + "\n"
	if got := f.file("beads.json"); got != want {
		t.Errorf("store after the update:\n got %s\nwant %s", got, want)
	}
	if got := f.file("gc.log"); !strings.HasPrefix(got, "bd update a --set-metadata typed=1 ") {
		t.Errorf("the call's log line is %q", got)
	}
}

func TestDropKeysLandsTheRest(t *testing.T) {
	f := newFixture(t, `[{"id":"a","status":"open","metadata":{"k":"old"}}]`, "")
	f.run([]string{"STUB_DROP_KEYS=a:status,k"}, "bd", "update", "a", "--status=closed", "--set-metadata", "k=new", "--set-metadata", "o=1")
	if got := f.file("beads.json"); got != `[{"id":"a","status":"open","metadata":{"k":"old","o":1}}]`+"\n" {
		t.Errorf("store = %s", got)
	}
}

func TestOneDependencyPerPair(t *testing.T) {
	f := newFixture(t, `[{"id":"a"},{"id":"b"}]`, "")
	if r := f.gc("bd", "dep", "add", "a", "b", "--type", "blocks"); r.status != 0 {
		t.Fatalf("first edge: %+v", r)
	}
	if r := f.gc("bd", "dep", "add", "a", "b", "--type=blocks"); r.status != 0 {
		t.Errorf("the same edge again: %+v", r)
	}
	r := f.gc("bd", "dep", "add", "a", "b", "--type=tracks")
	if r.status != 1 || !strings.Contains(r.err, `already exists with type "blocks"`) {
		t.Errorf("another type on the pair: %+v", r)
	}
	if r := f.gc("bd", "dep", "add", "b", "a", "--type=tracks"); r.status != 0 {
		t.Errorf("the reversed pair: %+v", r)
	}
	if got := f.file("deps.txt"); got != "b|blocks|a\nb|tracks|a\n" {
		t.Errorf("dep rows = %q", got)
	}
	show := f.gc("bd", "show", "a", "--json")
	if show.out != `[{"id":"a","priority":2,"dependencies":[{"id":"b","dependency_type":"blocks"}]}]`+"\n" {
		t.Errorf("show = %s", show.out)
	}
}

func TestDepListReadsDownWhenItNamesNoDirection(t *testing.T) {
	f := newFixture(t, `[{"id":"a"},{"id":"b"},{"id":"c"}]`, "b|blocks|a\nc|tracks|b\n")
	edges := `[{"issue_id":"a","depends_on_id":"b","type":"blocks"},{"issue_id":"c","depends_on_id":"b","type":"tracks"}]` + "\n"
	for _, args := range [][]string{{"a", "c", "--json"}, {"a", "c", "--direction=down", "--json"}} {
		if r := f.gc(append([]string{"bd", "dep", "list"}, args...)...); r.status != 0 || r.out != edges {
			t.Errorf("dep list %v: %+v", args, r)
		}
	}
	if r := f.gc("bd", "dep", "list", "a", "--json"); r.status != 0 || r.out != `[{"id":"b","dependency_type":"blocks"}]`+"\n" {
		t.Errorf("dep list a: %+v", r)
	}
}

func TestCloseFailRefusesAnUpdateThatClosesInEitherSpelling(t *testing.T) {
	f := newFixture(t, `[{"id":"a","status":"open"}]`, "")
	fail := []string{"STUB_CLOSE_FAIL=a"}
	for _, args := range [][]string{{"--status=closed"}, {"--status", "closed"}} {
		if r := f.run(fail, append([]string{"bd", "update", "a"}, args...)...); r.status != 1 || !strings.Contains(r.err, "simulated close refusal") {
			t.Errorf("update a %v: %+v", args, r)
		}
	}
	if r := f.run(fail, "bd", "update", "a", "--status", "in_progress"); r.status != 0 {
		t.Errorf("an update to another status: %+v", r)
	}
	if got := f.file("beads.json"); got != `[{"id":"a","status":"in_progress"}]`+"\n" {
		t.Errorf("store = %s", got)
	}
}

func TestCreateRefusesAMissingDependency(t *testing.T) {
	f := newFixture(t, `[{"id":"a"},{"id":"p"}]`, "")
	r := f.gc("bd", "create", "x", "--deps", "a,blocks:nope")
	if r.status != 1 || !strings.Contains(r.err, "issue nope not found") {
		t.Fatalf("create: %+v", r)
	}
	if f.file("beads.json") != `[{"id":"a"},{"id":"p"}]` || f.file("deps.txt") != "" {
		t.Error("a refused create wrote the store")
	}
	r = f.gc("bd", "create", "y", "--metadata", `{"m":1}`, "--deps", "a", "--parent", "p", "-p", "0")
	if r.status != 0 || r.out != `{"id":"new-3"}`+"\n" {
		t.Fatalf("create: %+v", r)
	}
	if got := f.file("deps.txt"); got != "a|blocks|new-3\nnew-3|parent-child|p\n" {
		t.Errorf("dep rows = %q", got)
	}
	if got := f.file("beads.json"); !strings.Contains(got, `{"id":"new-3","status":"open","assignee":"","title":"y","description":"","notes":"","issue_type":"task","metadata":{"m":1},"parent":"p","priority":0}`) {
		t.Errorf("store = %s", got)
	}
}

func TestAStoreFailureIsLoud(t *testing.T) {
	f := newFixture(t, `[{"id":"a"}`, "")
	r := f.gc("bd", "update", "a", "--status=closed")
	if r.status != exitStore || !strings.Contains(r.err, "beads.json") {
		t.Errorf("an unreadable store: %+v", r)
	}
	f.write("beads.json", `[{"id":"a"}]`)
	if err := os.Chmod(f.dir, 0o500); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.Chmod(f.dir, 0o700) })
	r = f.gc("bd", "update", "a", "--status=closed")
	if r.status != exitStore || r.out != "" || !strings.Contains(r.err, "beads.json") {
		t.Errorf("an unwritable store: %+v", r)
	}
	if got := f.file("beads.json"); got != `[{"id":"a"}]` {
		t.Errorf("the store changed: %s", got)
	}
}

func TestWritesToAMissingBeadAreRefused(t *testing.T) {
	f := newFixture(t, `[{"id":"a","status":"open"}]`, "")
	for _, args := range [][]string{
		{"bd", "update", "nope", "--status=closed"},
		{"bd", "close", "nope"},
		{"bd", "update", "a", "--set-metadata", "k=v", "--set-metadata", "novalue"},
	} {
		if r := f.gc(args...); r.status != 1 {
			t.Errorf("%v: %+v, want a refusal", args, r)
		}
	}
	if got := f.file("beads.json"); got != `[{"id":"a","status":"open"}]` {
		t.Errorf("a refused write wrote the store: %s", got)
	}
	r := f.gc("bd", "show", "nope", "--json")
	if r.status != 1 || r.out != `{"error":"no issues found matching the provided IDs","schema_version":1}`+"\n" {
		t.Errorf("show of a missing id: %+v", r)
	}
	if r := f.gc("bd", "show", "nope", "a", "--json"); r.status != 0 || !strings.HasPrefix(r.out, `[{"id":"a"`) {
		t.Errorf("show of a missing id beside a held one: %+v", r)
	}
	if r := f.gc("bd", "update", "a", "--status", "in_progress"); r.status != 0 || !strings.Contains(f.file("beads.json"), `"status":"in_progress"`) {
		t.Errorf("update --status <value>: %+v", r)
	}
}

func TestHarnessReadLogsNothing(t *testing.T) {
	f := newFixture(t, `[{"id":"a","status":"open","metadata":{"n":1.50,"f":false}},{"id":"a","status":null}]`, "a|parent-child|p\n")
	for _, c := range []struct {
		args []string
		want string
	}{
		{[]string{"meta", "a", "n"}, "1.50\n<absent>\n"},
		{[]string{"meta", "a", "f"}, "<absent>\n<absent>\n"},
		{[]string{"meta", "x", "n"}, "<absent>\n"},
		{[]string{"status", "a"}, "open\n"},
		{[]string{"priority", "a"}, "2\n2\n"},
		{[]string{"notes", "a"}, "\n"},
		{[]string{"parents", "a"}, "p\n"},
	} {
		if r := f.gc(append([]string{readFlag}, c.args...)...); r.out != c.want || r.status != 0 {
			t.Errorf("%v: %+v, want %q", c.args, r, c.want)
		}
	}
	if got := f.file("gc.log"); got != "" {
		t.Errorf("the reads logged %q", got)
	}
}

func TestListFilters(t *testing.T) {
	f := newFixture(t, `[{"id":"a","status":"open","title":"Alpha","metadata":{"k":"v","n":1}},{"id":"g","issue_type":"gate","status":"closed"},{"id":"c","status":"in_progress","metadata":{"k":"v","n":2}}]`, "")
	ids := func(r result) string {
		v, err := Decode([]byte(r.out))
		if err != nil {
			t.Fatalf("%q: %v", r.out, err)
		}
		var out []string
		for _, row := range v.([]Value) {
			out = append(out, get(row.(*Object), "id").(string))
		}
		return strings.Join(out, ",")
	}
	for _, c := range []struct {
		args []string
		want string
	}{
		{[]string{"--json"}, "a,c"},
		{[]string{"--all", "--json"}, "a,g,c"},
		{[]string{"--status=open,in_progress"}, "a,c"},
		{[]string{"--status=closed"}, "g"},
		{[]string{"--metadata-field", "k=v", "--metadata-field=n=1"}, "a"},
		{[]string{"--title-contains", "ALPH"}, "a"},
		{[]string{"--type=gate", "--all"}, "g"},
		{[]string{"--id", "a,c"}, "a,c"},
		{[]string{"--id=g", "--all"}, ""},
		{[]string{"--id=g", "--all", "--include-gates"}, "g"},
	} {
		if got := ids(f.gc(append([]string{"bd", "list"}, c.args...)...)); got != c.want {
			t.Errorf("list %v = %s, want %s", c.args, got, c.want)
		}
	}
}

func TestHangsHoldTheCall(t *testing.T) {
	f := newFixture(t, `[{"id":"a","status":"closed"}]`, "")
	var held []time.Duration
	var out bytes.Buffer
	c := &Call{Args: []string{"workflow", "reopen-source", "a"}, Env: append(f.env, "STUB_REOPEN_SOURCE_STALL=0.25", "STUB_REOPEN_SOURCE_HANG=2"),
		Stdout: &out, Stderr: &out, Stall: func(d time.Duration) { held = append(held, d) }}
	if status := Run(c); status != 0 || out.String() != "result=reopened source_bead_id=a\n" {
		t.Fatalf("reopen-source: %d %q", status, out.String())
	}
	if len(held) != 2 || held[0] != 250*time.Millisecond || held[1] != 2*time.Second {
		t.Errorf("held %v", held)
	}
	if got := f.file("beads.json"); got != `[{"id":"a","status":"open","metadata":null,"assignee":""}]`+"\n" {
		t.Errorf("store = %s", got)
	}
}

func TestHoldsReadIsHandedOn(t *testing.T) {
	f := newFixture(t, `[]`, "")
	var path string
	var argv, env []string
	c := &Call{Args: []string{"bd", "--db", "/x", "list", "--json"}, Env: append(f.env, "HOLDS_STUB_READ=1", "STUB_HOLDS_ANSWER=/holds.sh", "HOLDS_STORE=stale"),
		Stdout: &bytes.Buffer{}, Stderr: &bytes.Buffer{},
		Exec: func(p string, a, e []string) error { path, argv, env = p, a, e; return nil }}
	if status := Run(c); status != 0 {
		t.Fatalf("status %d", status)
	}
	if path != "/holds.sh" || strings.Join(argv, " ") != "/holds.sh answer --db /x list --json" {
		t.Errorf("handed to %s %v", path, argv)
	}
	got := strings.Join(env, "\n")
	if !strings.Contains(got, "HOLDS_STORE="+filepath.Join(f.dir, "beads.json")) || strings.Contains(got, "HOLDS_STORE=stale") {
		t.Errorf("env %v", env)
	}
}

func TestACallMadeAsBdAnswersAsGcBd(t *testing.T) {
	f := newFixture(t, `[{"id":"a","status":"open"}]`, "")
	viaGc := f.gc("bd", "show", "a", "--json")
	asBd := f.runAs("bd", nil, "show", "a", "--json")
	if asBd.status != 0 || asBd.out != viaGc.out {
		t.Errorf("bd show a = %+v, gc bd show a = %+v", asBd, viaGc)
	}
	if r := f.runAs("bd", nil, "update", "a", "--status=closed"); r.status != 0 || !strings.Contains(f.file("beads.json"), `"status":"closed"`) {
		t.Errorf("bd update: %+v", r)
	}
	if got := f.file("gc.log"); got != "bd show a --json\nbd show a --json\nbd update a --status=closed\n" {
		t.Errorf("log = %q", got)
	}
}

func TestGcFailFailsEveryGcCallButNotOneMadeAsBd(t *testing.T) {
	f := newFixture(t, `[{"id":"a","status":"open"}]`, "")
	cold := []string{"STUB_GC_FAIL=1"}
	for _, args := range [][]string{{"bd", "show", "a", "--json"}, {"convoy", "list"}, {"session", "nudge", "x", "m"}} {
		if r := f.run(cold, args...); r.status != 1 || r.out != "" {
			t.Errorf("gc %v: %+v, want a failure", args, r)
		}
	}
	if r := f.runAs("bd", cold, "show", "a", "--json"); r.status != 0 || !strings.HasPrefix(r.out, `[{"id":"a"`) {
		t.Errorf("bd show a: %+v", r)
	}
	if got := f.file("gc.log"); got != "bd show a --json\nconvoy list\nsession nudge x m\nbd show a --json\n" {
		t.Errorf("a failed call is still logged: log = %q", got)
	}
	if got := f.file("session.log"); got != "" {
		t.Errorf("a failed session call reached the session log: %q", got)
	}
}

func TestHookCurrentNamesTheClaim(t *testing.T) {
	f := newFixture(t, `[]`, "")
	for _, c := range []struct {
		settings []string
		args     []string
		status   int
		out      string
	}{
		{[]string{"GC_SESSION_ID=s1", "STUB_HOOK_CURRENT=tk-w"}, []string{"--id-only"}, 0, "tk-w\n"},
		{[]string{"GC_SESSION_ID=s1", "STUB_HOOK_CURRENT=tk-w"}, nil, 0, "tk-w (claimed by session s1)\n"},
		{[]string{"GC_SESSION_ID=s1", "STUB_HOOK_CURRENT="}, []string{"--id-only"}, 1, ""},
		{[]string{"STUB_HOOK_CURRENT=tk-w"}, []string{"--id-only"}, 1, ""},
	} {
		r := f.run(c.settings, append([]string{"hook", "current"}, c.args...)...)
		if r.status != c.status || r.out != c.out {
			t.Errorf("%v %v: %+v, want %d %q", c.settings, c.args, r, c.status, c.out)
		}
	}
	if r := f.run(nil, "hook", "--claim"); r.status != 2 {
		t.Errorf("another hook verb: %+v, want unsupported", r)
	}
}

func TestRuntimeDrainAckAnswersAndIsLogged(t *testing.T) {
	f := newFixture(t, `[]`, "")
	if r := f.gc("runtime", "drain-ack"); r.status != 0 || r.out != "" {
		t.Errorf("drain-ack: %+v", r)
	}
	if r := f.gc("runtime", "request-restart"); r.status != 2 {
		t.Errorf("another runtime verb: %+v, want unsupported", r)
	}
	if got := f.file("gc.log"); got != "runtime drain-ack\nruntime request-restart\n" {
		t.Errorf("log = %q", got)
	}
}

func TestUpdateFailOnRefusesByTheTextOfItsArguments(t *testing.T) {
	f := newFixture(t, `[{"id":"a","status":"open"},{"id":"b","status":"open"}]`, "")
	on := []string{"STUB_UPDATE_FAIL_ON=k=v"}
	if r := f.run(on, "bd", "update", "a", "--set-metadata", "k=v", "--status=closed"); r.status != 1 || !strings.Contains(r.err, "simulated update refusal for a") {
		t.Errorf("an update carrying the text: %+v", r)
	}
	if r := f.run(on, "bd", "update", "a", "--set-metadata", "k=w"); r.status != 0 {
		t.Errorf("an update without the text: %+v", r)
	}
	if r := f.run([]string{"STUB_UPDATE_FAIL_ON=b --status"}, "bd", "update", "b", "--status=closed"); r.status != 1 {
		t.Errorf("text spanning the id and an argument: %+v", r)
	}
	if got := f.file("beads.json"); got != `[{"id":"a","status":"open","metadata":{"k":"w"}},{"id":"b","status":"open"}]`+"\n" {
		t.Errorf("store = %s", got)
	}
}

func TestListObjectAnswersAnObjectAtExitZero(t *testing.T) {
	f := newFixture(t, `[{"id":"a","status":"open","metadata":{"branch":"x"}}]`, "")
	object := `{"error":"gc: simulated answer that is not a list"}` + "\n"
	if r := f.run([]string{"STUB_LIST_OBJECT=1"}, "bd", "list", "--json"); r.status != 0 || r.out != object {
		t.Errorf("every list: %+v", r)
	}
	limited := []string{"STUB_LIST_OBJECT=branch=x"}
	if r := f.run(limited, "bd", "list", "--metadata-field", "branch=x", "--json"); r.status != 0 || r.out != object {
		t.Errorf("a list carrying the text: %+v", r)
	}
	if r := f.run(limited, "bd", "list", "--json"); r.status != 0 || !strings.HasPrefix(r.out, `[{"id":"a"`) {
		t.Errorf("a list without the text: %+v", r)
	}
}
