package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// rigFixture is a fixture whose default store sits beside rig stores of its
// own: alpha (prefix al), beta (bt) and deep (al-x) each keep a store at
// <path>/.beads, and bare (br) is listed with none. Every store holds the
// rows al-1, al-x-1, bt-1, br-1 and x-1, so a write lands wherever it is
// routed and the test reads where it went.
func rigFixture(t *testing.T) *fixture {
	t.Helper()
	rows := `[{"id":"al-1"},{"id":"al-x-1"},{"id":"bt-1"},{"id":"br-1"},{"id":"x-1"}]`
	f := newFixture(t, rows, "")
	for _, r := range []string{"alpha", "beta", "deep"} {
		dir := filepath.Join(f.dir, r, ".beads")
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
		for name, body := range map[string]string{"beads.json": rows, "deps.txt": "", "kv.txt": "", "comments.json": "[]"} {
			if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o644); err != nil {
				t.Fatal(err)
			}
		}
	}
	if err := os.MkdirAll(filepath.Join(f.dir, "bare"), 0o755); err != nil {
		t.Fatal(err)
	}
	f.write("rigs.json", `{"rigs":[`+
		`{"name":"alpha","prefix":"al","path":"`+filepath.Join(f.dir, "alpha")+`"},`+
		`{"name":"beta","prefix":"bt","path":"`+filepath.Join(f.dir, "beta")+`"},`+
		`{"name":"deep","prefix":"al-x","path":"`+filepath.Join(f.dir, "deep")+`"},`+
		`{"name":"bare","prefix":"br","path":"`+filepath.Join(f.dir, "bare")+`"}]}`)
	f.env = append(f.env, "STUB_RIGS="+filepath.Join(f.dir, "rigs.json"))
	return f
}

// wroteTo names the stores whose row id carries metadata via=<tag>.
func (f *fixture) wroteTo(id, tag string) string {
	f.t.Helper()
	var got []string
	for _, s := range []string{"", "alpha/.beads/", "beta/.beads/", "deep/.beads/"} {
		if strings.Contains(f.file(s+"beads.json"), `{"id":"`+id+`","metadata":{"via":"`+tag+`"}}`) {
			got = append(got, strings.TrimSuffix(strings.TrimSuffix(s, "/.beads/"), "/"))
		}
	}
	return strings.Join(got, ",")
}

func TestACallActsInTheStoreGcPicks(t *testing.T) {
	f := rigFixture(t)
	beads := func(r string) string { return filepath.Join(f.dir, r, ".beads") }
	for _, c := range []struct {
		name     string
		settings []string
		args     []string
		id, want string
	}{
		{"a --db pin over the id's prefix", nil, []string{"--db", beads("alpha")}, "bt-1", "alpha"},
		{"a --db pin after the verb", nil, []string{"--db=" + beads("beta")}, "al-1", "beta"},
		{"a --db pin on a directory with no store is passed over", nil, []string{"--db", filepath.Join(f.dir, "bare", ".beads")}, "al-1", "alpha"},
		{"an explicit --rig over the id's prefix", nil, []string{"--rig", "beta"}, "al-1", "beta"},
		{"a --rig whose rig has no store is passed over", []string{"GC_RIG=beta"}, []string{"--rig", "bare"}, "x-1", "beta"},
		{"the id's prefix", nil, nil, "al-1", "alpha"},
		{"the longest prefix the id carries", nil, nil, "al-x-1", "deep"},
		{"a prefix whose rig has no store falls to GC_RIG", []string{"GC_RIG=beta"}, nil, "br-1", "beta"},
		{"an id no rig claims goes to GC_RIG's store", []string{"GC_RIG=beta"}, nil, "x-1", "beta"},
		{"GC_RIG naming a rig with no store", []string{"GC_RIG=bare"}, nil, "x-1", ""},
		{"no rig at all", nil, nil, "x-1", ""},
	} {
		tag := strings.ReplaceAll(c.name, " ", "_")
		args := []string{"bd"}
		pin := c.args
		if len(pin) > 0 && strings.HasPrefix(pin[0], "--db=") {
			args = append(args, "update", c.id, "--set-metadata", "via="+tag, pin[0])
		} else {
			args = append(append(args, pin...), "update", c.id, "--set-metadata", "via="+tag)
		}
		if r := f.run(c.settings, args...); r.status != 0 {
			t.Errorf("%s: %+v", c.name, r)
			continue
		}
		if got := f.wroteTo(c.id, tag); got != c.want {
			t.Errorf("%s: the write landed in %q, want %q (the default store is \"\")", c.name, got, c.want)
		}
	}
	if r := f.run([]string{"GC_RIG=alpha"}, "bd", "create", "a-new-bead", "--json"); r.out != `{"id":"new-6"}`+"\n" || !strings.Contains(f.file("alpha/.beads/beads.json"), `"title":"a-new-bead"`) {
		t.Errorf("a create goes to GC_RIG's store and mints for its rows: %+v", r)
	}
	if r := f.gc("bd", "--db", beads("alpha"), "where", "--json"); r.out != `{"path":"`+beads("alpha")+`","prefix":"al"}`+"\n" {
		t.Errorf("where names a rig's store and its prefix: %+v", r)
	}
	if r := f.gc("bd", "--db", beads("beta"), "kv", "set", "k", "v"); r.status != 0 || f.file("beta/.beads/kv.txt") != "k=v\n" || f.file("kv.txt") != "" {
		t.Errorf("a kv write goes to the store's own kv rows: %+v", r)
	}
	if got := f.file("gc.log"); !strings.HasPrefix(got, "bd --db "+beads("alpha")+" update bt-1 ") {
		t.Errorf("a call is logged as it was made: %q", got)
	}
}

func TestSlingAndWorkflowActInTheBeadsStore(t *testing.T) {
	f := rigFixture(t)
	if r := f.gc("sling", "--rig", "beta", "beta/pool", "x-1", "--on", "mol-x"); r.status != 0 || !strings.Contains(f.file("beta/.beads/beads.json"), `{"id":"x-1","metadata":{"gc.execution_routed_to":"beta/pool"}`) {
		t.Errorf("a sling's --rig picks the store it stamps: %+v %s", r, f.file("beta/.beads/beads.json"))
	}
	if r := f.gc("sling", "alpha/pool", "al-1", "--on", "mol-x"); r.status != 0 || !strings.Contains(f.file("alpha/.beads/beads.json"), `{"id":"al-1","metadata":{"gc.execution_routed_to":"alpha/pool"}`) {
		t.Errorf("a sling with no --rig stamps the bead's own store: %+v", r)
	}
	if r := f.gc("workflow", "reopen-source", "bt-1"); r.status != 0 || !strings.Contains(f.file("beta/.beads/beads.json"), `{"id":"bt-1","metadata":null,"status":"open","assignee":""}`) {
		t.Errorf("a workflow reopen acts in the bead's store: %+v", r)
	}
	if strings.Contains(f.file("beads.json"), "metadata") || strings.Contains(f.file("beads.json"), "status") {
		t.Errorf("the default store was written: %s", f.file("beads.json"))
	}
}

func TestHarnessReadsAndWritesFollowTheRoute(t *testing.T) {
	f := rigFixture(t)
	if r := f.gc(writeFlag, "row", "al-9", "status=blocked"); r.status != 0 || !strings.Contains(f.file("alpha/.beads/beads.json"), `{"id":"al-9","status":"blocked"}`) {
		t.Fatalf("a fixture write goes to the id's store: %+v", r)
	}
	if r := f.gc(readFlag, "status", "al-9"); r.out != "blocked\n" {
		t.Errorf("a read of the id's store: %+v", r)
	}
	if r := f.gc(readFlag, "status", "x-9"); r.out != "<absent>\n" {
		t.Errorf("an id no rig claims reads the default store: %+v", r)
	}
	f.run([]string{"GC_RIG=beta"}, writeFlag, "row", "x-9", "status=open")
	if r := f.run([]string{"GC_RIG=beta"}, readFlag, "status", "x-9"); r.out != "open\n" || strings.Contains(f.file("beads.json"), "x-9") {
		t.Errorf("GC_RIG picks the store an unclaimed id is read and written in: %+v", r)
	}
	if r := f.run([]string{"GC_RIG=alpha"}, readFlag, "ids", "status=blocked"); r.out != "al-9\n" {
		t.Errorf("ids reads GC_RIG's store: %+v", r)
	}
	if got := f.file("gc.log"); got != "" {
		t.Errorf("the harness's calls logged %q", got)
	}
}

func TestEdgeAndRecordReaders(t *testing.T) {
	f := newFixture(t, `[{"id":"a","status":"open","parent":"p"},{"id":"b"},{"id":"c"}]`, "a|supersedes|b\nb|blocks|a\nc|tracks|b\n")
	for _, c := range []struct {
		args []string
		want string
	}{
		{[]string{"edge", "a", "b"}, "blocks supersedes\n"},
		{[]string{"edge", "a", "p"}, "parent-child\n"},
		{[]string{"edge", "b", "a"}, "\n"},
		{[]string{"edge", "c", "b"}, "tracks\n"},
		{[]string{"record", "a"}, `{"id":"a","status":"open","parent":"p"}` + "\na|supersedes|b\nb|blocks|a\n"},
		{[]string{"record", "z"}, ""},
	} {
		if r := f.gc(append([]string{readFlag}, c.args...)...); r.out != c.want {
			t.Errorf("%v = %q, want %q", c.args, r.out, c.want)
		}
	}
}

func TestADryRunCreatePreviewsTheRowAndWritesNothing(t *testing.T) {
	f := newFixture(t, `[]`, "")
	bin := filepath.Join(f.dir, "bin")
	if err := os.MkdirAll(bin, 0o755); err != nil {
		t.Fatal(err)
	}
	f.write("bin/git", "#!/bin/sh\n[ \"$*\" = 'config user.name' ] && echo 'Git Name'\n")
	if err := os.Chmod(filepath.Join(bin, "git"), 0o755); err != nil {
		t.Fatal(err)
	}
	for _, c := range []struct {
		settings []string
		args     []string
		actor    string
	}{
		{nil, nil, "unknown"},
		{[]string{"USER=u"}, nil, "u"},
		{[]string{"USER=u", "PATH=" + bin}, nil, "Git Name"},
		{[]string{"USER=u", "PATH=" + bin, "BD_ACTOR=bd-actor"}, nil, "bd-actor"},
		{[]string{"BD_ACTOR=bd-actor", "BEADS_ACTOR=beads-actor"}, nil, "beads-actor"},
		{[]string{"BEADS_ACTOR=beads-actor"}, []string{"--actor", "Named Actor"}, "Named Actor"},
	} {
		r := f.run(c.settings, append(append([]string{"bd"}, c.args...), "create", "a preview", "--dry-run", "--json", "-p", "1")...)
		want := `{"created_by":"` + c.actor + `","id":"","issue_type":"task","priority":1,"status":"open","title":"a preview"}` + "\n"
		if r.status != 0 || r.out != want {
			t.Errorf("%v %v: %+v, want %s", c.settings, c.args, r, want)
		}
	}
	if got := f.file("beads.json"); got != "[]" {
		t.Errorf("a dry run wrote the store: %s", got)
	}
	if r := f.run([]string{"STUB_CREATE_FAIL=1"}, "bd", "create", "a preview", "--dry-run", "--json"); r.status != 1 || r.out != "" {
		t.Errorf("a create that is refused previews nothing: %+v", r)
	}
}

func TestStatusesNameEachStatusAndItsCategory(t *testing.T) {
	f := newFixture(t, `[]`, "")
	r := f.gc("bd", "statuses", "--json")
	v, err := Decode([]byte(r.out))
	if r.status != 0 || err != nil {
		t.Fatalf("statuses: %+v %v", r, err)
	}
	var live []string
	for _, s := range iterate(get(v.(*Object), "built_in_statuses")) {
		o := s.(*Object)
		if ToString(get(o, "category")) != "done" {
			live = append(live, ToString(get(o, "name")))
		}
	}
	if got := strings.Join(live, ","); got != "open,in_progress,blocked,deferred,pinned,hooked" {
		t.Errorf("the statuses outside the done category are %s", got)
	}
}

func TestACreateKeepsADependencyOntoAnotherStoresBead(t *testing.T) {
	f := rigFixture(t)
	if r := f.run([]string{"GC_RIG=alpha"}, "bd", "create", "c", "--deps", "related:bt-9", "--json"); r.status != 0 || !strings.Contains(f.file("alpha/.beads/deps.txt"), "new-6|related|bt-9\n") {
		t.Errorf("a rig's store keeps a dependency onto another prefix's bead: %+v", r)
	}
	if r := f.run([]string{"GC_RIG=alpha"}, "bd", "create", "c2", "--deps", "related:al-9", "--json"); r.status != 1 || strings.Contains(f.file("alpha/.beads/beads.json"), `"c2"`) {
		t.Errorf("a missing bead of the store's own prefix refuses the create: %+v", r)
	}
	if r := f.gc("bd", "create", "c3", "--deps", "related:bt-9", "--json"); r.status != 1 {
		t.Errorf("a store that is no rig's knows no prefix of its own, so it refuses every missing target: %+v", r)
	}
}

func TestTheCheckedCloseKeepsBdsRules(t *testing.T) {
	enforce := []string{"STUB_ENFORCE_BLOCKS=1"}
	for _, c := range []struct {
		name, store, deps string
		args              []string
		status            int
		says              string
	}{
		{"a pinned blocker holds nothing", `[{"id":"a"},{"id":"b","status":"pinned"}]`, "b|blocks|a\n",
			[]string{"update", "a", "--status=closed"}, 0, ""},
		{"an open blocker holds the close", `[{"id":"a"},{"id":"b","status":"open"},{"id":"c","status":"closed"}]`, "b|blocks|a\nc|blocks|a\n",
			[]string{"update", "a", "--status=closed"}, 1, "a is blocked by [b]"},
		{"a blocker a row stores holds it too", `[{"id":"a","dependencies":[{"id":"b","dependency_type":"blocks"}]},{"id":"b"}]`, "",
			[]string{"close", "a"}, 1, "a is blocked by [b]"},
		{"a pinned child holds its parent", `[{"id":"a"},{"id":"k","status":"pinned"}]`, "k|parent-child|a\n",
			[]string{"update", "a", "--status=closed"}, 1, "1 open child issue(s)"},
		{"a deferred child named by its parent field", `[{"id":"a"},{"id":"k","status":"deferred","parent":"a"}]`, "",
			[]string{"close", "a"}, 1, "1 open child issue(s)"},
		{"a closed child holds nothing", `[{"id":"a"},{"id":"k","status":"closed"}]`, "k|parent-child|a\n",
			[]string{"update", "a", "--status=closed"}, 0, ""},
		{"a stale guard refuses ahead of the blockers", `[{"id":"a","status":"open"},{"id":"b"}]`, "b|blocks|a\n",
			[]string{"update", "a", "--if-status=in_progress", "--status=closed"}, 13, "status mismatch"},
		{"an update that does not close is not checked", `[{"id":"a"},{"id":"b"}]`, "b|blocks|a\n",
			[]string{"update", "a", "--status=in_progress"}, 0, ""},
	} {
		f := newFixture(t, c.store, c.deps)
		r := f.run(enforce, append([]string{"bd"}, c.args...)...)
		if r.status != c.status || !strings.Contains(r.err, c.says) {
			t.Errorf("%s: %+v, want exit %d saying %q", c.name, r, c.status, c.says)
		}
	}
	f := newFixture(t, `[{"id":"a","assignee":"someone"},{"id":"p","status":"pinned"}]`, "")
	for _, id := range []string{"a", "p"} {
		if r := f.run(append(enforce, "BEADS_ACTOR=other"), "bd", "update", id, "--status=closed"); r.status != 0 {
			t.Errorf("an update closes %s whoever holds it and whatever its status, as bd's update keeps no such guard: %+v", id, r)
		}
	}
}

func TestADepAddThatIsNeverKeptReportsSuccess(t *testing.T) {
	f := newFixture(t, `[{"id":"a"},{"id":"b"}]`, "")
	if r := f.run([]string{"STUB_DEP_ADD_NOOP=a"}, "bd", "dep", "add", "a", "b", "--type", "supersedes"); r.status != 0 || f.file("deps.txt") != "" {
		t.Errorf("a dep add from a bead the setting names: %+v, deps %q", r, f.file("deps.txt"))
	}
	if r := f.run([]string{"STUB_DEP_ADD_NOOP=a"}, "bd", "dep", "add", "b", "a", "--type", "supersedes"); r.status != 0 || f.file("deps.txt") != "b|supersedes|a\n" {
		t.Errorf("one from any other bead lands: %+v, deps %q", r, f.file("deps.txt"))
	}
}
