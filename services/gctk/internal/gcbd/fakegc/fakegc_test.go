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
	want := `[{"id":"a","status":"closed","metadata":{"keep":"k","typed":1,"flag":true,"txt":" 007 ","num":7,"plus":"+1","eq":"a=b"},"closed_at":"2026-01-01T00:00:00Z","priority":1,"notes":"n1"},{"id":"b"}]` + "\n"
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
	t.Cleanup(func() { _ = os.Chmod(f.dir, 0o700) })
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

// ids is the id of each row a listing answers, comma-joined.
func ids(t *testing.T, r result) string {
	t.Helper()
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

func TestBlockedReadyAndMarksKeepBdsRule(t *testing.T) {
	// a waits on b; c's parent e waits on x; k is held by nothing live: its
	// blocker is closed, an external edge, and a bead the store does not hold;
	// w waits for spawner s, whose child is live; g is a gate.
	f := newFixture(t, `[
		{"id":"a","status":"open","metadata":{"key":"1"}},
		{"id":"b","status":"open","assignee":"bob","labels":["skip"]},
		{"id":"e","status":"open","issue_type":"epic"},
		{"id":"x","status":"in_progress"},
		{"id":"c","status":"open","parent":"e"},
		{"id":"k","status":"open","dependencies":[{"id":"done","dependency_type":"blocks"},{"depends_on_id":"far","type":"blocks","external":true}]},
		{"id":"done","status":"closed"},
		{"id":"far","status":"open"},
		{"id":"s","status":"open"},
		{"id":"sc","status":"open","parent":"s"},
		{"id":"w","status":"open"},
		{"id":"g","status":"open","issue_type":"gate"}]`,
		"b|blocks|a\nx|blocks|e\nk|blocks|nowhere\nw|waits-for|s\n")
	if got := ids(t, f.gc("bd", "blocked", "--json")); got != "a,e,c,w" {
		t.Errorf("blocked = %s", got)
	}
	r := f.gc("bd", "blocked", "--json")
	if !strings.Contains(r.out, `"id":"c"`) || !strings.Contains(r.out, `"blocked_by_count":1,"blocked_by":["e"]`) {
		t.Errorf("a bead held through its parent names the parent: %s", r.out)
	}
	if got := ids(t, f.gc("bd", "sql", "--json", "SELECT id FROM issues WHERE is_blocked = 1 AND status <> 'closed'")); got != "a,c,e,w" {
		t.Errorf("marks = %s", got)
	}
	if r := f.gc("bd", "sql", "--json", "SELECT * FROM issues"); r.status != 2 {
		t.Errorf("another query answers %+v", r)
	}
	for _, c := range []struct {
		args []string
		want string
	}{
		{nil, "b,k,far,s,sc"},
		{[]string{"--unassigned"}, "k,far,s,sc"},
		{[]string{"--exclude-label", "skip"}, "k,far,s,sc"},
		{[]string{"--exclude-type=task"}, ""},
		{[]string{"--has-metadata-key", "key"}, ""},
	} {
		if got := ids(t, f.gc(append([]string{"bd", "ready", "--json", "--limit", "0"}, c.args...)...)); got != c.want {
			t.Errorf("ready %v = %s, want %s", c.args, got, c.want)
		}
	}
	f.write("deps.txt", "")
	if got := ids(t, f.gc("bd", "ready", "--has-metadata-key=key", "--json")); got != "a" {
		t.Errorf("ready by key once nothing holds a = %s", got)
	}
}

func TestListCarriesEachEdgeAndSelectsByParent(t *testing.T) {
	f := newFixture(t, `[{"id":"p","status":"open"},{"id":"c","status":"open","parent":"p"},{"id":"d","status":"open","dependencies":[{"id":"p","dependency_type":"tracks"}]},{"id":"n","status":"open"}]`,
		"p|blocks|c\nc|tracks|n\n")
	r := f.gc("bd", "list", "--json")
	for _, want := range []string{
		`{"id":"c","status":"open","parent":"p","priority":2,"dependencies":[{"issue_id":"c","depends_on_id":"p","type":"blocks"},{"issue_id":"c","depends_on_id":"p","type":"parent-child"},{"issue_id":"c","depends_on_id":"n","type":"tracks"}]}`,
		`{"id":"d","status":"open","dependencies":[{"id":"p","dependency_type":"tracks"}],"priority":2}`,
		`{"id":"n","status":"open","priority":2}`,
	} {
		if !strings.Contains(r.out, want) {
			t.Errorf("list lacks %s:\n%s", want, r.out)
		}
	}
	if got := ids(t, f.gc("bd", "list", "--parent", "p", "--json")); got != "c" {
		t.Errorf("list --parent p = %s", got)
	}
}

func TestCommentsAreKeptPerBead(t *testing.T) {
	f := newFixture(t, `[{"id":"a","title":"Alpha","status":"open"},{"id":"b","status":"open"}]`, "")
	f.env = append(f.env, "STUB_COMMENTS="+filepath.Join(f.dir, "comments.json"))
	if r := f.gc("bd", "comments", "a", "--json"); r.out != "[]\n" || r.status != 0 {
		t.Errorf("no comments: %+v", r)
	}
	if r := f.run([]string{"BEADS_ACTOR=me"}, "bd", "comment", "a", "first"); r.out != "✓ Comment added to a — Alpha\n" || r.status != 0 {
		t.Errorf("comment: %+v", r)
	}
	f.gc("bd", "comment", "b", "other")
	f.gc("bd", "comment", "a", "second", "--json")
	r := f.gc("bd", "comments", "a", "--json")
	if !strings.Contains(r.out, `"issue_id":"a","author":"me","text":"first"`) || !strings.Contains(r.out, `"text":"second"`) || strings.Contains(r.out, "other") {
		t.Errorf("comments of a: %s", r.out)
	}
	if r := f.gc(readFlag, "comments", "a"); r.out != "first\nsecond\n" {
		t.Errorf("the comments reader: %+v", r)
	}
	if r := f.gc("bd", "comment", "nope", "x"); r.status != 1 || r.err != "Error: issue nope not found\n" {
		t.Errorf("a comment on a bead the store does not hold: %+v", r)
	}
	if r := f.gc("bd", "comments", "nope", "--json"); r.status != 1 || !strings.Contains(r.out, `"error":"issue nope not found"`) {
		t.Errorf("the comments of a bead the store does not hold: %+v", r)
	}
}

func TestRigListAnswersTheSetting(t *testing.T) {
	f := newFixture(t, `[]`, "")
	if r := f.gc("rig", "list", "--json"); r.out != `{"rigs":[]}`+"\n" {
		t.Errorf("no setting: %+v", r)
	}
	f.write("rigs.json", `{"rigs":[{"name":"r"}]}`)
	if r := f.run([]string{"STUB_RIGS=" + filepath.Join(f.dir, "rigs.json")}, "rig", "list", "--json"); r.out != `{"rigs":[{"name":"r"}]}` {
		t.Errorf("the setting's file: %+v", r)
	}
	if r := f.gc("rig", "status"); r.status != 2 {
		t.Errorf("another rig verb: %+v", r)
	}
}

func TestOrderListAnswersTheSetting(t *testing.T) {
	f := newFixture(t, `[]`, "")
	if r := f.gc("order", "list", "--json"); r.status != 0 || r.out != "" {
		t.Errorf("no setting: %+v, want nothing at exit 0", r)
	}
	f.write("orders.json", `{"orders":[{"name":"o","trigger":"cooldown","interval":"5m"}]}`)
	if r := f.run([]string{"STUB_ORDERS=" + filepath.Join(f.dir, "orders.json")}, "order", "list", "--json"); r.status != 0 || r.out != `{"orders":[{"name":"o","trigger":"cooldown","interval":"5m"}]}` {
		t.Errorf("the setting's file: %+v", r)
	}
	if r := f.run([]string{"STUB_ORDERS=" + filepath.Join(f.dir, "missing.json")}, "order", "list", "--json"); r.out != `{"orders":[]}`+"\n" {
		t.Errorf("a file that cannot be read: %+v, want an empty registry", r)
	}
	if r := f.gc("order", "run", "o"); r.status != 2 {
		t.Errorf("another order verb: %+v", r)
	}
}

func TestConfigShowAnswersTheSetting(t *testing.T) {
	f := newFixture(t, `[]`, "")
	if r := f.gc("config", "show", "--json"); r.status != 0 || r.out != noConfig+"\n" {
		t.Errorf("no setting: %+v, want a config that names no agent", r)
	}
	cfg := `{"ok":true,"config":{"Agents":[{"Name":"pool","Dir":"rig","DefaultSlingFormula":"mol-polecat-work"}]}}`
	f.write("config.json", cfg)
	if r := f.run([]string{"STUB_CONFIG=" + filepath.Join(f.dir, "config.json")}, "config", "show", "--json"); r.out != cfg {
		t.Errorf("the setting's file: %+v", r)
	}
	if r := f.run([]string{"STUB_CONFIG=" + filepath.Join(f.dir, "none.json")}, "config", "show", "--json"); r.out != noConfig+"\n" {
		t.Errorf("a file that does not read: %+v, want a config that names no agent", r)
	}
	if r := f.gc("config", "validate"); r.status != 2 {
		t.Errorf("another config verb: %+v", r)
	}
}

func TestHookRunsBeforeTheCallItNames(t *testing.T) {
	f := newFixture(t, `[{"id":"a","status":"open"}]`, "")
	hook := filepath.Join(f.dir, "hook.sh")
	f.write("hook.sh", "#!/bin/sh\nprintf '%s|%s|%s\\n' \"$*\" \"$STUB_HOOK_AT\" \"$(cat)\" >> \""+filepath.Join(f.dir, "fired")+"\"\n")
	if err := os.Chmod(hook, 0o755); err != nil {
		t.Fatal(err)
	}
	set := []string{"STUB_HOOK_AT=update a", "STUB_HOOK=" + hook}
	f.run(set, "bd", "show", "a", "--json")
	if _, err := os.Stat(filepath.Join(f.dir, "fired")); err == nil {
		t.Errorf("a call that does not carry the text ran the hook")
	}
	var out, errb bytes.Buffer
	c := &Call{Args: []string{"bd", "update", "a", "--status=closed"}, Env: append(append([]string{}, f.env...), set...),
		Stdin: strings.NewReader("the call's own input"), Stdout: &out, Stderr: &errb}
	if status := Run(c); status != 0 {
		t.Fatalf("update: %d %s", status, errb.String())
	}
	if got := f.file("fired"); got != "bd update a --status=closed||\n" {
		t.Errorf("the hook ran with %q, want the call's arguments, no setting and no input", got)
	}
}

func TestHarnessWritesSetRowsAndLogNothing(t *testing.T) {
	f := newFixture(t, `[{"id":"a","status":"closed"}]`, "")
	for _, args := range [][]string{
		{"row", "a", "status=open", "title=the bead a", "metadata.k=v"},
		{"row", "b", "status=open", "labels:=[\"x\"]", "priority:=1"},
		{"set", "a", "metadata.n:=2", "assignee=bob"},
	} {
		if r := f.gc(append([]string{writeFlag}, args...)...); r.status != 0 {
			t.Fatalf("%v: %+v", args, r)
		}
	}
	if got, want := f.file("beads.json"), `[{"id":"a","status":"open","title":"the bead a","metadata":{"k":"v","n":2},"assignee":"bob"},{"id":"b","status":"open","labels":["x"],"priority":1}]`+"\n"; got != want {
		t.Errorf("store %s, want %s", got, want)
	}
	for _, c := range []struct {
		args []string
		want string
	}{
		{[]string{"field", "a", "assignee"}, "bob\n"},
		{[]string{"field", "b", "labels"}, "[\"x\"]\n"},
		{[]string{"field", "b", "assignee"}, "\n"},
		{[]string{"field", "z", "assignee"}, "<absent>\n"},
		{[]string{"ids", "metadata.k=v"}, "a\n"},
		{[]string{"ids", "status=open"}, "a\nb\n"},
		{[]string{"ids", "metadata.n=2", "assignee=bob"}, "a\n"},
	} {
		if r := f.gc(append([]string{readFlag}, c.args...)...); r.out != c.want {
			t.Errorf("%v = %q, want %q", c.args, r.out, c.want)
		}
	}
	if r := f.gc(writeFlag, "set", "z", "status=open"); r.status != 1 {
		t.Errorf("a set on a bead the store does not hold: %+v", r)
	}
	if r := f.gc(writeFlag, "set", "a", "nope"); r.status != 2 {
		t.Errorf("a setting with no value: %+v", r)
	}
	if got := f.file("gc.log"); got != "" {
		t.Errorf("the writes logged %q", got)
	}
}

func TestEdgeReadersReadEveryPlaceAnEdgeIs(t *testing.T) {
	f := newFixture(t, `[{"id":"c","status":"open","dependencies":[{"id":"t2","dependency_type":"tracks"}]},{"id":"d","status":"open"},{"id":"t1"},{"id":"t2"}]`,
		"c|tracks|t1\nd|tracks|t1\nb|blocks|c\n")
	for _, c := range []struct {
		args []string
		want string
	}{
		{[]string{"edges", "c", "tracks"}, "t1 t2\n"},
		{[]string{"edges", "c", "blocks"}, "b\n"},
		{[]string{"edges", "d", "blocks"}, "\n"},
		{[]string{"onto", "t1", "tracks"}, "c d\n"},
		{[]string{"onto", "t2", "tracks"}, "c\n"},
	} {
		if r := f.gc(append([]string{readFlag}, c.args...)...); r.out != c.want {
			t.Errorf("%v = %q, want %q", c.args, r.out, c.want)
		}
	}
}

func TestFaultsByTextRefuseOnlyTheCallsThatCarryIt(t *testing.T) {
	f := newFixture(t, `[{"id":"a","status":"open"},{"id":"b","status":"open"}]`, "")
	refuse := []string{"STUB_DEP_ADD_FAIL_ON=--type replies-to", "STUB_UPDATE_FAIL_ON=assignee=x"}
	if r := f.run(refuse, "bd", "dep", "add", "a", "b", "--type", "replies-to"); r.status != 1 {
		t.Errorf("a dep add that carries the text: %+v", r)
	}
	if r := f.run(refuse, "bd", "dep", "add", "a", "b", "--type", "tracks"); r.status != 0 {
		t.Errorf("a dep add that does not: %+v", r)
	}
	if r := f.run(refuse, "bd", "update", "a", "--assignee=x"); r.status != 1 {
		t.Errorf("an update that carries the text: %+v", r)
	}
	if r := f.run(refuse, "bd", "update", "a", "--assignee=y"); r.status != 0 {
		t.Errorf("an update that does not: %+v", r)
	}
	if got := f.file("deps.txt"); got != "a|tracks|b\n" {
		t.Errorf("deps %q, want only the edge nothing refused", got)
	}
	if r := f.gc(readFlag, "assignee", "a"); r.out != "y\n" {
		t.Errorf("assignee %q", r.out)
	}
}

func TestCreateReadsItsFlagsInAnyOrder(t *testing.T) {
	f := newFixture(t, `[]`, "")
	if r := f.gc("bd", "create", "-t", "task", "--title", "flagged", "-d", "the body", "--assignee", "human", "-l", "a,b", "--json"); r.status != 0 {
		t.Fatalf("create: %+v", r)
	}
	f.gc("bd", "create", "positional", "--description=told", "--json")
	want := `[{"id":"new-1","status":"open","assignee":"human","title":"flagged","description":"the body","notes":"","issue_type":"task","metadata":{},"labels":["a","b"]},` +
		`{"id":"new-2","status":"open","assignee":"","title":"positional","description":"told","notes":"","issue_type":"task","metadata":{}}]` + "\n"
	if got := f.file("beads.json"); got != want {
		t.Errorf("store %s\nwant  %s", got, want)
	}
}

func TestACloseRecordsWhenAndWhy(t *testing.T) {
	f := newFixture(t, `[{"id":"a","status":"open"},{"id":"b","status":"open"},{"id":"c","status":"closed","closed_at":"2025-05-05T00:00:00Z"}]`, "")
	f.gc("bd", "close", "a", "--reason", "done")
	f.gc("bd", "update", "b", "--status=closed")
	f.gc("bd", "close", "c", "-r", "again")
	want := `[{"id":"a","status":"closed","closed_at":"2026-01-01T00:00:00Z","close_reason":"done"},{"id":"b","status":"closed","closed_at":"2026-01-01T00:00:00Z"},{"id":"c","status":"closed","closed_at":"2025-05-05T00:00:00Z","close_reason":"again"}]` + "\n"
	if got := f.file("beads.json"); got != want {
		t.Errorf("store %s\nwant  %s", got, want)
	}
}

func TestAGuardThatNoLongerHoldsWritesNothingAndExits13(t *testing.T) {
	f := newFixture(t, `[{"id":"a","status":"open","assignee":"bob"}]`, "")
	for _, c := range []struct {
		args   []string
		status int
	}{
		{[]string{"--if-assignee", "carol", "--assignee", "dan"}, 13},
		{[]string{"--if-status=closed", "--assignee", "dan"}, 13},
		{[]string{"--if-assignee=bob", "--if-status", "open", "--assignee", "dan"}, 0},
		{[]string{"--if-assignee", "", "--assignee", "eve"}, 13},
	} {
		if r := f.gc(append([]string{"bd", "update", "a"}, c.args...)...); r.status != c.status {
			t.Errorf("update %v: %+v, want exit %d", c.args, r, c.status)
		}
	}
	if r := f.gc(readFlag, "assignee", "a"); r.out != "dan\n" {
		t.Errorf("assignee %q, want only the update whose guards held", r.out)
	}
}

func TestUpdateEditsLabels(t *testing.T) {
	f := newFixture(t, `[{"id":"a","status":"open","labels":["x","hold:mayor"]}]`, "")
	f.gc("bd", "update", "a", "--add-label", "y", "--add-label=x", "--remove-label", "hold:mayor")
	if r := f.gc(readFlag, "field", "a", "labels"); r.out != `["x","y"]`+"\n" {
		t.Errorf("labels %q", r.out)
	}
	f.gc("bd", "update", "a", "--set-labels", "z")
	if r := f.gc(readFlag, "field", "a", "labels"); r.out != `["z"]`+"\n" {
		t.Errorf("labels after --set-labels %q", r.out)
	}
}

func TestAListingHidesTemplatesInfraAndWisps(t *testing.T) {
	f := newFixture(t, `[{"id":"t","status":"open"},{"id":"tpl","status":"open","is_template":true},{"id":"m","status":"open","issue_type":"message"},{"id":"w","status":"open","ephemeral":true}]`, "")
	for _, c := range []struct {
		args []string
		want string
	}{
		{[]string{"--json"}, "t"},
		{[]string{"--id", "t,tpl,m,w", "--json"}, "t"},
		{[]string{"--id", "t,tpl,m,w", "--include-templates", "--json"}, "t,tpl"},
		{[]string{"--id", "t,tpl,m,w", "--include-infra", "--json"}, "t,m,w"},
		{[]string{"--id", "t,tpl,m,w", "--include-ephemeral", "--json"}, "t,w"},
	} {
		if got := ids(t, f.gc(append([]string{"bd", "list"}, c.args...)...)); got != c.want {
			t.Errorf("list %v = %s, want %s", c.args, got, c.want)
		}
	}
}

func TestABlocksEdgeAcrossAParentChainIsRefused(t *testing.T) {
	f := newFixture(t, `[{"id":"p","status":"open"},{"id":"c","status":"open","parent":"p"},{"id":"g","status":"open"},{"id":"x","status":"open"}]`, "g|parent-child|c\n")
	for _, c := range []struct {
		args   []string
		status int
	}{
		{[]string{"g", "p", "--type", "blocks"}, 1},
		{[]string{"p", "g", "--type=conditional-blocks"}, 1},
		{[]string{"c", "p"}, 1},
		{[]string{"g", "p", "--type", "tracks"}, 0},
		{[]string{"x", "p", "--type", "blocks"}, 0},
	} {
		if r := f.gc(append([]string{"bd", "dep", "add"}, c.args...)...); r.status != c.status {
			t.Errorf("dep add %v: %+v, want exit %d", c.args, r, c.status)
		}
	}
	if got := f.file("deps.txt"); got != "g|parent-child|c\ng|tracks|p\np|blocks|x\n" {
		t.Errorf("deps %q", got)
	}
}

func TestFailOnRefusesAnyCallThatCarriesTheText(t *testing.T) {
	f := newFixture(t, `[{"id":"a","status":"open"}]`, "")
	set := []string{"STUB_FAIL_ON=list --id a"}
	if r := f.run(set, "bd", "list", "--id", "a", "--json"); r.status != 1 || r.out != "" {
		t.Errorf("a call that carries the text: %+v", r)
	}
	if r := f.run(set, "bd", "show", "a", "--json"); r.status != 0 {
		t.Errorf("a call that does not: %+v", r)
	}
	if got := f.file("gc.log"); got != "bd list --id a --json\nbd show a --json\n" {
		t.Errorf("log %q: a refused call is still logged", got)
	}
}

func TestListFailAfterFailsEveryListOnceTheTextIsLogged(t *testing.T) {
	f := newFixture(t, `[{"id":"a","status":"open"}]`, "")
	set := []string{"STUB_LIST_FAIL_AFTER=--status=closed"}
	if r := f.run(set, "bd", "list", "--json"); r.status != 0 {
		t.Errorf("a list before any call carries the text: %+v", r)
	}
	if r := f.run(set, "bd", "update", "a", "--status=closed"); r.status != 0 {
		t.Fatalf("the update that carries it: %+v", r)
	}
	if r := f.run(set, "bd", "list", "--id", "a", "--all", "--json"); r.status != 1 || r.out != "" {
		t.Errorf("a list after it: %+v, want it failed", r)
	}
	for _, args := range [][]string{{"bd", "show", "a", "--json"}, {"bd", "dep", "list", "a", "--json"}} {
		if r := f.run(set, args...); r.status != 0 {
			t.Errorf("%v, which is not a list: %+v", args, r)
		}
	}
}

func TestAHookThatFailsFailsItsCall(t *testing.T) {
	f := newFixture(t, `[{"id":"a","status":"open"}]`, "")
	f.write("second.sh", "#!/bin/sh\n[ -e \""+filepath.Join(f.dir, "seen")+"\" ] && exit 1\n: > \""+filepath.Join(f.dir, "seen")+"\"\n")
	if err := os.Chmod(filepath.Join(f.dir, "second.sh"), 0o755); err != nil {
		t.Fatal(err)
	}
	set := []string{"STUB_HOOK_AT=show a", "STUB_HOOK=" + filepath.Join(f.dir, "second.sh")}
	if r := f.run(set, "bd", "show", "a", "--json"); r.status != 0 {
		t.Errorf("the first show: %+v", r)
	}
	if r := f.run(set, "bd", "show", "a", "--json"); r.status != 1 || r.out != "" {
		t.Errorf("the second show, whose hook fails: %+v", r)
	}
}

func TestAfterWriteRunsOnceEachWriteHasLanded(t *testing.T) {
	f := newFixture(t, `[{"id":"a","status":"open"},{"id":"g","status":"open","issue_type":"gate"}]`, "")
	fired := filepath.Join(f.dir, "fired")
	// The program records its arguments, whether the setting reached it, and
	// the store as it finds it, so each line shows the write had landed.
	prog := filepath.Join(f.dir, "after.sh")
	f.write("after.sh", "#!/bin/sh\nIFS= read -r s < \"$STUB_STORE\"\nprintf '%s|%s|%s\\n' \"$*\" \"$STUB_AFTER_WRITE\" \"$s\" >> \""+fired+"\"\nexit 3\n")
	if err := os.Chmod(prog, 0o755); err != nil {
		t.Fatal(err)
	}
	set := []string{"STUB_AFTER_WRITE=" + prog}
	for _, args := range [][]string{
		{"bd", "show", "a", "--json"},
		{"bd", "list", "--json"},
		{"bd", "dep", "list", "a", "--json"},
		{"bd", "gate", "list", "--json"},
		{"rig", "list", "--json"},
		{"bd", "create", "a preview", "--dry-run", "--json"},
	} {
		if r := f.run(set, args...); r.status != 0 {
			t.Fatalf("%v: %+v", args, r)
		}
	}
	if _, err := os.Stat(fired); err == nil {
		t.Fatalf("a read or a dry run ran the program: %s", f.file("fired"))
	}
	if r := f.run(set, "bd", "update", "a", "--if-status=in_progress", "--status=closed"); r.status != 13 {
		t.Fatalf("a guarded update that does not hold: %+v", r)
	}
	if _, err := os.Stat(fired); err == nil {
		t.Fatalf("a write that did not land ran the program: %s", f.file("fired"))
	}
	if r := f.run(set, "bd", "--db", "/x/.beads", "update", "a", "--status=in_progress"); r.status != 0 {
		t.Errorf("an update whose program exits 3: %+v, want the update's own 0", r)
	}
	want := "bd --db /x/.beads update a --status=in_progress||" + `[{"id":"a","status":"in_progress"},{"id":"g","status":"open","issue_type":"gate"}]` + "\n"
	if got := f.file("fired"); got != want {
		t.Errorf("after the update the program ran with %q, want %q", got, want)
	}
	f.write("fired", "")
	for _, args := range [][]string{
		{"bd", "dep", "add", "a", "g"},
		{"bd", "dep", "remove", "a", "g"},
		{"bd", "gate", "resolve", "g", "--reason", "ruled: no"},
		{"bd", "close", "a"},
	} {
		if r := f.run(set, args...); r.status != 0 {
			t.Fatalf("%v: %+v", args, r)
		}
	}
	var verbs []string
	for _, l := range strings.Split(strings.TrimSuffix(f.file("fired"), "\n"), "\n") {
		verbs = append(verbs, strings.SplitN(l, "|", 2)[0])
	}
	if got := strings.Join(verbs, ","); got != "bd dep add a g,bd dep remove a g,bd gate resolve g --reason ruled: no,bd close a" {
		t.Errorf("the program ran after %q, want once after each write", got)
	}
	if r := f.run([]string{"STUB_AFTER_WRITE=" + filepath.Join(f.dir, "missing.sh")}, "bd", "update", "a", "--assignee=x"); r.status == 0 {
		t.Errorf("a program that does not start: %+v, want the call failed", r)
	}
}

func TestUnsetRemovesFieldsAndMetadataKeys(t *testing.T) {
	f := newFixture(t, `[{"id":"a","status":"open","owner":"o","metadata":{"k":"v","keep":"1"}}]`, "")
	if r := f.gc(writeFlag, "unset", "a", "owner", "metadata.k", "metadata.none"); r.status != 0 {
		t.Fatalf("unset: %+v", r)
	}
	if got := f.file("beads.json"); got != `[{"id":"a","status":"open","metadata":{"keep":"1"}}]`+"\n" {
		t.Errorf("store %s", got)
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

func TestACallMadeAsBdIsMatchedAsGcBd(t *testing.T) {
	f := newFixture(t, `[{"id":"a","status":"open"}]`, "")
	if r := f.runAs("bd", []string{"STUB_FAIL_ON=bd show a"}, "show", "a", "--json"); r.status != 1 || r.out != "" {
		t.Errorf("STUB_FAIL_ON: %+v, want a failure", r)
	}
	hook := filepath.Join(f.dir, "hook.sh")
	f.write("hook.sh", "#!/bin/sh\nprintf '%s\\n' \"$*\" > \""+filepath.Join(f.dir, "fired")+"\"\n")
	if err := os.Chmod(hook, 0o755); err != nil {
		t.Fatal(err)
	}
	if r := f.runAs("bd", []string{"STUB_HOOK_AT=bd update a", "STUB_HOOK=" + hook}, "update", "a", "--status=closed"); r.status != 0 {
		t.Fatalf("update: %+v", r)
	}
	if got := f.file("fired"); got != "bd update a --status=closed\n" {
		t.Errorf("the hook ran with %q, want the call's arguments as gc bd's", got)
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

func TestSetStateSwapsTheDimensionsLabelAndRecordsAnEvent(t *testing.T) {
	f := newFixture(t, `[{"id":"a","status":"open","labels":["x","situation:active"]}]`, "")
	r := f.gc("bd", "set-state", "a", "situation=cleared", "--reason", "fixed")
	if r.status != 0 || r.out != "✓ Set situation = cleared on a\n  Previous: active\n  Event: new-2\n" {
		t.Fatalf("set-state: %d %q %s", r.status, r.out, r.err)
	}
	if r := f.gc(readFlag, "field", "a", "labels"); r.out != `["x","situation:cleared"]`+"\n" {
		t.Errorf("labels %q, want the dimension's one label swapped", r.out)
	}
	for field, want := range map[string]string{"status": "closed", "issue_type": "event", "priority": "4",
		"title": "State change: situation → cleared", "description": "Changed situation from active to cleared\n\nReason: fixed"} {
		if r := f.gc(readFlag, "field", "new-2", field); r.out != want+"\n" {
			t.Errorf("the event's %s is %q, want %q", field, r.out, want)
		}
	}
	if r := f.gc(readFlag, "parents", "new-2"); r.out != "a\n" {
		t.Errorf("the event's parents are %q, want the bead", r.out)
	}
	r = f.gc("bd", "set-state", "a", "situation=cleared", "--json")
	if r.status != 0 || r.out != `{"changed":false,"dimension":"situation","issue_id":"a","value":"cleared"}`+"\n" {
		t.Errorf("a set-state to the value the bead holds: %d %q", r.status, r.out)
	}
	if n := strings.Count(f.file("beads.json"), `"issue_type":"event"`); n != 1 {
		t.Errorf("%d events after a set-state that changed nothing, want 1", n)
	}
	r = f.gc("bd", "set-state", "a", "mode=degraded", "--json")
	if r.out != `{"changed":true,"dimension":"mode","event_id":"new-3","issue_id":"a","new_value":"degraded","old_value":null}`+"\n" {
		t.Errorf("a first value for a dimension: %q", r.out)
	}
	if r := f.gc(readFlag, "field", "new-3", "description"); r.out != "Set mode to degraded\n" {
		t.Errorf("the first value's event says %q", r.out)
	}
	before := f.file("beads.json")
	for _, args := range [][]string{{"nope", "situation=active"}, {"a", "situation"}, {"a", "=active"}, {"a"}} {
		if r := f.gc(append([]string{"bd", "set-state"}, args...)...); r.status != 1 {
			t.Errorf("set-state %v: exit %d, want 1", args, r.status)
		}
	}
	if f.file("beads.json") != before {
		t.Errorf("a refused set-state wrote the store")
	}
}

func TestKvListAnswersEveryKeyByKey(t *testing.T) {
	f := newFixture(t, "[]", "")
	if r := f.gc("bd", "kv", "list", "--json"); r.status != 0 || r.out != `{"schema_version":1}`+"\n" {
		t.Errorf("an empty kv's list: %d %q", r.status, r.out)
	}
	f.gc("bd", "kv", "set", "b", "2")
	f.gc("bd", "kv", "set", "a", "x=1")
	if r := f.gc("bd", "kv", "list", "--json"); r.out != `{"a":"x=1","b":"2","schema_version":1}`+"\n" {
		t.Errorf("kv list --json: %q", r.out)
	}
	if r := f.gc("bd", "kv", "list"); r.out != "\nKey-Value Store:\n  a = x=1\n  b = 2\n" {
		t.Errorf("kv list: %q", r.out)
	}
	if r := f.run([]string{"STUB_KV_FAIL=1"}, "bd", "kv", "list", "--json"); r.status != 1 || r.out != "" {
		t.Errorf("kv list under STUB_KV_FAIL: %+v", r)
	}
}

func TestUpdateWritesTheTitleAndRefusesABlankOne(t *testing.T) {
	f := newFixture(t, `[{"id":"a","title":"old","status":"open"},{"id":"b","title":"old","status":"open"}]`, "")
	if r := f.gc("bd", "update", "a", "--title", "new a", "--set-metadata", "k=v"); r.status != 0 {
		t.Errorf("--title: %+v", r)
	}
	if r := f.gc("bd", "update", "b", "--title=new b"); r.status != 0 {
		t.Errorf("--title=: %+v", r)
	}
	for _, blank := range []string{"", "  "} {
		if r := f.gc("bd", "update", "b", "--title", blank, "--set-metadata", "k=v"); r.status != 1 || !strings.Contains(r.err, "title cannot be empty") {
			t.Errorf("--title %q: %+v, want bd's refusal", blank, r)
		}
	}
	want := `[{"id":"a","title":"new a","status":"open","metadata":{"k":"v"}},{"id":"b","title":"new b","status":"open"}]` + "\n"
	if got := f.file("beads.json"); got != want {
		t.Errorf("store = %s, want %s", got, want)
	}
}

func TestConvoyStatusAnswersItsMembersAsGcReadsThem(t *testing.T) {
	f := newFixture(t, `[{"id":"cv","title":"the convoy","status":"open","issue_type":"convoy","labels":["owned","x"],"metadata":{"target":"main","convoy.owner":"me","other":"o"}},`+
		`{"id":"c-late","title":"late child","status":"closed","parent":"cv","created_at":"2026-01-03T00:00:00Z"},`+
		`{"id":"c-early","title":"early child","status":"open","created_at":"2026-01-01T00:00:00Z"},`+
		`{"id":"t-both","title":"tracked child","status":"in_progress","assignee":"bob","issue_type":"bug","parent":"cv","created_at":"2026-01-02T00:00:00Z"},`+
		`{"id":"t-only","title":"tracked","status":"open","created_at":"2026-01-02T00:00:00Z"},`+
		`{"id":"other","title":"no member","status":"open","created_at":"2026-01-01T00:00:00Z"},`+
		`{"id":"empty","title":"no members","status":"open","issue_type":"convoy"},{"id":"task","title":"a task","status":"open"}]`,
		"c-early|parent-child|cv\ncv|tracks|t-both\ncv|tracks|t-only\ncv|tracks|gone\nother|tracks|t-only\n")
	want := `{"children":[{"id":"gone","title":"gone","status":"unknown","type":"task","dangling_track":true},` +
		`{"id":"c-early","title":"early child","status":"open","type":"task"},` +
		`{"id":"t-both","title":"tracked child","status":"in_progress","type":"bug","assignee":"bob"},` +
		`{"id":"t-only","title":"tracked","status":"open","type":"task"},` +
		`{"id":"c-late","title":"late child","status":"closed","type":"task"}],` +
		`"convoy":{"id":"cv","title":"the convoy","status":"open","owned":true,"fields":{"owner":"me","target":"main"},"labels":["owned","x"]},` +
		`"ok":true,"progress":{"closed":1,"total":5,"dangling_tracks":1},"schema_version":"1"}` + "\n"
	if r := f.gc("convoy", "status", "cv", "--json"); r.status != 0 || r.out != want {
		t.Errorf("a convoy's members:\n got %+v\nwant %s", r, want)
	}
	none := `{"children":[],"convoy":{"id":"empty","title":"no members","status":"open","owned":false,"fields":{}},"ok":true,"progress":{"closed":0,"total":0},"schema_version":"1"}` + "\n"
	if r := f.gc("convoy", "status", "--json", "empty"); r.status != 0 || r.out != none {
		t.Errorf("a convoy with no members:\n got %+v\nwant %s", r, none)
	}
	failed := `{"schema_version":"1","ok":false,"error":{"code":"command_failed","message":"command failed; see stderr for diagnostics","exit_code":1}}` + "\n"
	for id, why := range map[string]string{"task": "bead task is not a convoy", "nope": "convoy nope not found"} {
		if r := f.gc("convoy", "status", id, "--json"); r.status != 1 || r.out != failed || !strings.Contains(r.err, why) {
			t.Errorf("convoy status %s: %+v, want gc's refusal: %s", id, r, why)
		}
	}
	if r := f.gc("convoy", "status", "cv"); r.status != 2 {
		t.Errorf("the text answer: %+v, want unsupported", r)
	}
}
