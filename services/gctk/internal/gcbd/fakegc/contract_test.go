package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/gcbdtest"
)

// The contract test runs the same calls against the fake and against a scratch
// store of the bd the city runs (gcbdtest), and compares what each answers and
// what each leaves, so it pins every rule of bd the fake keeps. It runs when
// GCTK_STORE_ACCEPTANCE=1 asks for it, as the store adapter's acceptance test
// does, and again whenever the fake or the bd the city runs changes:
//
//	GCTK_STORE_ACCEPTANCE=1 go test ./internal/gcbd/fakegc -run TestContract -v
//
// A case names its beads, which each side creates, and writes a call's bead ids
// as {name}. Where the fake keeps a rule only while a setting asks for it, such
// as bd's refusal to close a blocked bead, the call names that setting.

// A step is one call: bd's arguments, the input it reads, the settings the
// fake takes for it, the actor it runs as, and what of its answer to compare.
type step struct {
	args     []string
	stdin    string
	settings []string
	actor    string
	answer   string // "", "rows", "edges", "listed-edges", "texts", "json", "null-or-ids" or "count:<title>"
}

type contractCase struct {
	name  string
	beads []string   // created first, each titled by its name
	more  [][]string // further beads: a name, then bd create's arguments
	steps []step
	// state names the beads whose state is compared after the last step.
	state []string
}

func TestContract(t *testing.T) {
	if !gcbdtest.Asked() {
		t.Skip("the contract test runs the city's bd on a scratch store; GCTK_STORE_ACCEPTANCE=1 runs it")
	}
	real := newRealSide(t)
	fake := newFakeSide(t)
	for _, c := range contractCases() {
		t.Run(c.name, func(t *testing.T) {
			ids := map[string]map[string]string{"bd": {}, "fake": {}}
			for _, side := range []sideRunner{real, fake} {
				for _, b := range c.beads {
					ids[side.name()][b] = side.create(t, b)
				}
				for _, m := range c.more {
					ids[side.name()][m[0]] = side.create(t, m[0], subst(m[1:], ids[side.name()])...)
				}
			}
			for i, st := range c.steps {
				var got [2]outcome
				for k, side := range []sideRunner{real, fake} {
					got[k] = side.call(t, st, subst(st.args, ids[side.name()]), names(ids[side.name()]))
				}
				label := fmt.Sprintf("step %d, bd %s", i, strings.Join(st.args, " "))
				if (got[0].status == 0) != (got[1].status == 0) {
					t.Errorf("%s: bd exits %d and the fake %d\n bd:   %s\n fake: %s", label, got[0].status, got[1].status, got[0].raw, got[1].raw)
					continue
				}
				if st.answer != "" && !reflect.DeepEqual(got[0].answer, got[1].answer) {
					t.Errorf("%s: answers differ\n bd:   %#v\n fake: %#v", label, got[0].answer, got[1].answer)
				}
			}
			for _, b := range c.state {
				var st [2]map[string]any
				for k, side := range []sideRunner{real, fake} {
					st[k] = side.state(t, ids[side.name()][b], names(ids[side.name()]))
				}
				for key := range st[0] {
					if !reflect.DeepEqual(st[0][key], st[1][key]) {
						t.Errorf("bead %s: %s is %#v in bd and %#v in the fake", b, key, st[0][key], st[1][key])
					}
				}
			}
		})
	}
}

func contractCases() []contractCase {
	return []contractCase{
		{name: "gate list names none while the store has no gate", steps: []step{
			{args: []string{"gate", "list", "--json"}, answer: "null-or-ids"},
		}},
		{name: "update stores each metadata value as bd types it", beads: []string{"a"}, state: []string{"a"}, steps: []step{
			{args: []string{"update", "{a}", "--set-metadata", "n=1", "--set-metadata", "f=2.50", "--set-metadata", "t=true",
				"--set-metadata", "fa=false", "--set-metadata", "nu=null", "--set-metadata", "plus=+1", "--set-metadata", "zz=00",
				"--set-metadata", "half=.5", "--set-metadata", "nan=NaN", "--set-metadata", "pad= 007 ", "--set-metadata", "pad7= 7 ",
				"--set-metadata", "eq=a=b", "--set-metadata", `q="q"`, "--set-metadata", "e=1e5", "--set-metadata", "neg=-0",
				"--set-metadata", "empty=", "--set-metadata", "gone=x"}},
			{args: []string{"update", "{a}", "--unset-metadata", "gone"}},
		}},
		{name: "update appends notes and writes the assignee, the status and the priority", beads: []string{"a"}, state: []string{"a"}, steps: []step{
			{args: []string{"update", "{a}", "--append-notes", "one", "--assignee", "bob", "--status=in_progress", "--priority=P1"}},
			{args: []string{"update", "{a}", "--append-notes", "two", "-p", "3"}},
		}},
		{name: "an update of several ids writes each", beads: []string{"a", "b"}, state: []string{"a", "b"}, steps: []step{
			{args: []string{"update", "{a}", "{b}", "--set-metadata", "m=1", "--priority=0"}},
		}},
		{name: "a create carries its fields, typed metadata and bd's defaults", beads: []string{"p"},
			more: [][]string{
				{"full", "--metadata", `{"a":1,"b":"x","c":{"d":[true]}}`, "-t", "epic", "-p", "P1", "--notes", "nn", "--status", "in_progress", "--parent", "{p}"},
				{"plain"},
			},
			state: []string{"full", "plain"}},
		{name: "a create refuses metadata that is not JSON and files nothing", steps: []step{
			{args: []string{"create", "refused-meta", "--metadata", "{nope", "--json"}},
			{args: []string{"list", "--all", "--json"}, answer: "count:refused-meta"},
		}},
		{name: "a create's dependencies land in every form and a missing target refuses it", beads: []string{"a", "b", "c"},
			more: [][]string{
				{"d", "--deps", "{a},blocks:{b}", "--deps", "tracks:{c}"},
				{"e", "--deps", "depends-on:{a}", "--deps", "blocked-by:{b}"},
			},
			state: []string{"b", "d", "e"},
			steps: []step{
				{args: []string{"create", "refused-dep", "--deps", "{a},ct-nope", "--json"}},
				{args: []string{"list", "--all", "--json"}, answer: "count:refused-dep"},
			}},
		{name: "one dependency per pair of beads", beads: []string{"a", "b"}, state: []string{"a", "b"}, steps: []step{
			{args: []string{"dep", "add", "{a}", "{b}", "--type", "blocks"}},
			{args: []string{"dep", "add", "{a}", "{b}", "--type=blocks"}},
			{args: []string{"dep", "add", "{a}", "{b}", "--type=tracks"}},
			{args: []string{"dep", "add", "{b}", "{a}", "--type=tracks"}},
			{args: []string{"dep", "remove", "{a}", "{a}"}},
		}},
		{name: "dep list answers a far bead's row, or many ids' edges, or bd's error", beads: []string{"a", "b", "c"}, steps: []step{
			{args: []string{"dep", "add", "{a}", "{b}", "--type=blocks"}},
			{args: []string{"dep", "add", "{c}", "{a}", "--type=tracks"}},
			{args: []string{"dep", "list", "{a}", "--json"}, answer: "rows"},
			{args: []string{"dep", "list", "{a}", "--direction=down", "--json"}, answer: "rows"},
			{args: []string{"dep", "list", "{a}", "--direction=up", "--json"}, answer: "rows"},
			{args: []string{"dep", "list", "{a}", "{c}", "--direction=down", "--json"}, answer: "edges"},
			{args: []string{"dep", "list", "{a}", "{c}", "--json"}, answer: "edges"},
			{args: []string{"dep", "list", "ct-nope", "--json"}, answer: "json"},
		}},
		{name: "a batch of edges with a refused pair writes none of them", beads: []string{"a", "b", "c"}, state: []string{"a", "c"}, steps: []step{
			{args: []string{"dep", "add", "{a}", "{b}", "--type=tracks"}},
			{args: []string{"dep", "add", "--file", "-"}, stdin: `{"from":"{c}","to":"{b}","type":"blocks"}` + "\n" + `{"from":"{a}","to":"{b}","type":"blocks"}` + "\n"},
			{args: []string{"dep", "add", "--file", "-"}, stdin: `{"from":"{c}","to":"{a}","type":"blocks"}` + "\n"},
		}},
		{name: "show answers each bead with its edges, and bd's error for one it does not hold", beads: []string{"a", "b"}, state: []string{"a", "b"}, steps: []step{
			{args: []string{"dep", "add", "{a}", "{b}", "--type=blocks"}},
			{args: []string{"show", "{a}", "{b}", "--json"}, answer: "rows"},
			{args: []string{"show", "ct-nope", "--json"}, answer: "json"},
		}},
		{name: "a list by id leaves out a gate unless it asks for gates", beads: []string{"t"}, more: [][]string{{"g", "-t", "gate"}}, steps: []step{
			{args: []string{"list", "--id", "{g}", "--json"}, answer: "null-or-ids"},
			{args: []string{"list", "--id", "{g}", "--include-gates", "--json"}, answer: "null-or-ids"},
		}},
		{name: "a gate resolves once and keeps its first reason; a task is no gate", beads: []string{"t"}, more: [][]string{{"g", "-t", "gate"}},
			state: []string{"g"}, steps: []step{
				{args: []string{"gate", "resolve", "{g}", "--reason", "first"}},
				{args: []string{"gate", "resolve", "{g}", "--reason", "again"}},
				{args: []string{"gate", "resolve", "{t}", "--reason", "r"}},
			}},
		{name: "kv answers found and not found in bd's shape", steps: []step{
			{args: []string{"kv", "get", "ct-key", "--json"}, answer: "json"},
			{args: []string{"kv", "set", "ct-key", "v1"}},
			{args: []string{"kv", "get", "ct-key", "--json"}, answer: "json"},
			{args: []string{"kv", "clear", "ct-key"}},
			{args: []string{"kv", "get", "ct-key", "--json"}, answer: "json"},
		}},
		{name: "close refuses a bead another actor holds and update does not", beads: []string{"x", "y"}, state: []string{"x", "y"}, steps: []step{
			{args: []string{"update", "{x}", "{y}", "--assignee", "bob"}},
			{args: []string{"close", "{x}"}, actor: "me", settings: []string{"STUB_ENFORCE_CLOSE_OWNER=1"}},
			{args: []string{"update", "{y}", "--status=closed"}, actor: "me", settings: []string{"STUB_ENFORCE_CLOSE_OWNER=1"}},
		}},
		{name: "a bead the store does not hold takes no write, and a show answers only what it holds", beads: []string{"a"}, steps: []step{
			{args: []string{"update", "ct-nope", "--status=closed"}},
			{args: []string{"close", "ct-nope"}},
			{args: []string{"show", "ct-nope", "--json"}, answer: "json"},
			{args: []string{"show", "{a}", "ct-nope", "--json"}, answer: "rows"},
			{args: []string{"show", "ct-nope", "{a}", "--json"}, answer: "rows"},
		}},
		{name: "a list with no status leaves out closed beads", beads: []string{"a", "b"}, steps: []step{
			{args: []string{"close", "{b}"}},
			{args: []string{"list", "--json"}, answer: "null-or-ids"},
			{args: []string{"list", "--all", "--json"}, answer: "null-or-ids"},
			{args: []string{"list", "--status=closed", "--json"}, answer: "null-or-ids"},
		}},
		{name: "an update reads --status in either spelling and refuses a key with no value", beads: []string{"a", "b"}, state: []string{"a", "b"}, steps: []step{
			{args: []string{"update", "{a}", "--status", "in_progress"}},
			{args: []string{"update", "{b}", "--set-metadata", "k=v", "--set-metadata", "novalue"}},
		}},
		{name: "an update writes the title it names, in either spelling, beside its other fields", beads: []string{"a", "b"}, state: []string{"a", "b"}, steps: []step{
			{args: []string{"update", "{a}", "--title", "ct-retitled", "--set-metadata", "pr_summary=s"}},
			{args: []string{"update", "{b}", "--title=ct-retitled-too"}},
			{args: []string{"update", "{b}", "--title", ""}},
			{args: []string{"update", "{b}", "--title", "  ", "--set-metadata", "k=v"}},
			{args: []string{"list", "--all", "--json"}, answer: "count:ct-retitled"},
			{args: []string{"list", "--all", "--json"}, answer: "count:ct-retitled-too"},
		}},
		{name: "a dep add that names no type adds a blocks edge", beads: []string{"a", "b"}, state: []string{"a"}, steps: []step{
			{args: []string{"dep", "add", "{a}", "{b}"}},
		}},
		{name: "close and update refuse to close a blocked bead", beads: []string{"k", "j", "blocker"}, state: []string{"k", "j"}, steps: []step{
			{args: []string{"dep", "add", "{k}", "{blocker}", "--type=blocks"}},
			{args: []string{"dep", "add", "{j}", "{blocker}", "--type=blocks"}},
			{args: []string{"close", "{k}"}, settings: []string{"STUB_ENFORCE_BLOCKS=1"}},
			{args: []string{"update", "{j}", "--status=closed"}, settings: []string{"STUB_ENFORCE_BLOCKS=1"}},
		}},
		{name: "a listing carries each bead's edges, and --parent selects a bead's children", beads: []string{"p", "n"},
			more: [][]string{{"c", "--parent", "{p}"}}, steps: []step{
				{args: []string{"dep", "add", "{c}", "{n}", "--type=tracks"}},
				{args: []string{"list", "--json"}, answer: "listed-edges"},
				{args: []string{"list", "--parent", "{p}", "--json"}, answer: "null-or-ids"},
			}},
		{name: "blocked, the marks and ready keep bd's rule", beads: []string{"a", "b", "e", "x", "k", "done"},
			more: [][]string{{"c", "--parent", "{e}"}, {"g", "-t", "gate"}, {"keyed", "--metadata", `{"key":"1"}`}}, steps: []step{
				{args: []string{"dep", "add", "{a}", "{b}", "--type=blocks"}},
				{args: []string{"dep", "add", "{e}", "{x}", "--type=blocks"}},
				{args: []string{"dep", "add", "{k}", "{done}", "--type=blocks"}},
				{args: []string{"close", "{done}"}},
				{args: []string{"blocked", "--json"}, answer: "null-or-ids"},
				{args: []string{"sql", "--json", "SELECT id FROM issues WHERE is_blocked = 1 AND status <> 'closed' AND status <> 'pinned' " +
					"UNION ALL SELECT id FROM wisps WHERE is_blocked = 1 AND status <> 'closed' AND status <> 'pinned'"}, answer: "null-or-ids"},
				{args: []string{"ready", "--json", "--limit", "0"}, answer: "null-or-ids"},
				{args: []string{"ready", "--has-metadata-key", "key", "--json", "--limit", "0"}, answer: "null-or-ids"},
			}},
		{name: "a guard that no longer holds writes nothing", beads: []string{"a"}, state: []string{"a"}, steps: []step{
			{args: []string{"update", "{a}", "--assignee", "bob"}},
			{args: []string{"update", "{a}", "--if-assignee", "carol", "--assignee", "dan"}},
			{args: []string{"update", "{a}", "--if-status", "closed", "--assignee", "dan"}},
			{args: []string{"update", "{a}", "--if-assignee", "bob", "--if-status", "open", "--assignee", "eve"}},
		}},
		{name: "a listing hides infrastructure beads and wisps unless it asks for them", beads: []string{"t"},
			more: [][]string{{"m", "-t", "message"}, {"w", "--ephemeral"}}, steps: []step{
				{args: []string{"list", "--json"}, answer: "null-or-ids"},
				{args: []string{"list", "--id", "{t},{m},{w}", "--json"}, answer: "null-or-ids"},
				{args: []string{"list", "--id", "{t},{m},{w}", "--include-infra", "--json"}, answer: "null-or-ids"},
				{args: []string{"list", "--id", "{t},{m},{w}", "--include-ephemeral", "--json"}, answer: "null-or-ids"},
			}},
		{name: "a blocks edge across a parent chain is refused either way", beads: []string{"p", "x"},
			more: [][]string{{"c", "--parent", "{p}"}, {"g", "--parent", "{c}"}}, state: []string{"g", "p"}, steps: []step{
				{args: []string{"dep", "add", "{g}", "{p}", "--type", "blocks"}},
				{args: []string{"dep", "add", "{p}", "{g}", "--type", "blocks"}},
				{args: []string{"dep", "add", "{x}", "{p}", "--type", "blocks"}},
			}},
		{name: "a create reads its title from --title, after its other flags", steps: []step{
			{args: []string{"create", "-t", "task", "--title", "ct-flagged", "-d", "the body", "--assignee", "bob", "--json"}},
			{args: []string{"list", "--all", "--json"}, answer: "count:ct-flagged"},
		}},
		{name: "comments are kept per bead, and a bead the store does not hold takes none", beads: []string{"a", "b"}, steps: []step{
			{args: []string{"comments", "{a}", "--json"}, answer: "texts"},
			{args: []string{"comment", "{a}", "first"}},
			{args: []string{"comment", "{b}", "other"}},
			{args: []string{"comment", "{a}", "second"}},
			{args: []string{"comments", "{a}", "--json"}, answer: "texts"},
			{args: []string{"comment", "ct-nope", "x"}},
			{args: []string{"comments", "ct-nope", "--json"}, answer: "json"},
		}},
	}
}

// subst writes each {name} in args as that bead's id.
func subst(args []string, ids map[string]string) []string {
	out := make([]string, len(args))
	for i, a := range args {
		for n, id := range ids {
			a = strings.ReplaceAll(a, "{"+n+"}", id)
		}
		out[i] = a
	}
	return out
}

// names maps each id back to its bead's name.
func names(ids map[string]string) map[string]string {
	out := map[string]string{}
	for n, id := range ids {
		out[id] = n
	}
	return out
}

type outcome struct {
	status int
	raw    string
	answer any
}

type sideRunner interface {
	name() string
	create(t *testing.T, title string, args ...string) string
	run(st step, args []string) (stdout, stderr string, status int)
	call(t *testing.T, st step, args []string, names map[string]string) outcome
	state(t *testing.T, id string, names map[string]string) map[string]any
}

// side holds what both runners share: reading an answer and a bead's state.
type side struct{ self sideRunner }

func (s side) call(t *testing.T, st step, args []string, nm map[string]string) outcome {
	t.Helper()
	stdin := st.stdin
	for id, n := range nm {
		stdin = strings.ReplaceAll(stdin, "{"+n+"}", id)
	}
	st.stdin = stdin
	out, errOut, status := s.self.run(st, args)
	o := outcome{status: status, raw: out + errOut}
	if st.answer == "" {
		return o
	}
	v := decodeAny(t, out)
	switch {
	case st.answer == "rows":
		var rows []string
		for _, r := range asList(v) {
			m := r.(map[string]any)
			rows = append(rows, fmt.Sprintf("%s:%v", nameOf(nm, m["id"]), m["dependency_type"]))
		}
		sort.Strings(rows)
		o.answer = rows
	case st.answer == "edges":
		var edges []string
		for _, r := range asList(v) {
			m := r.(map[string]any)
			edges = append(edges, fmt.Sprintf("%s->%s:%v", nameOf(nm, m["issue_id"]), nameOf(nm, m["depends_on_id"]), m["type"]))
		}
		sort.Strings(edges)
		o.answer = edges
	case st.answer == "listed-edges":
		var edges []string
		for _, r := range asList(v) {
			m := r.(map[string]any)
			if _, named := nm[fmt.Sprint(m["id"])]; !named {
				continue
			}
			for _, d := range asList(m["dependencies"]) {
				e := d.(map[string]any)
				edges = append(edges, fmt.Sprintf("%s->%s:%v", nameOf(nm, e["issue_id"]), nameOf(nm, e["depends_on_id"]), e["type"]))
			}
		}
		sort.Strings(edges)
		o.answer = edges
	case st.answer == "texts":
		var texts []string
		for _, r := range asList(v) {
			texts = append(texts, fmt.Sprint(r.(map[string]any)["text"]))
		}
		o.answer = texts
	case st.answer == "json":
		m, _ := v.(map[string]any)
		delete(m, "hint")
		o.answer = m
	case st.answer == "null-or-ids":
		if v == nil {
			o.answer = "null"
			break
		}
		var ids []string
		for _, r := range asList(v) {
			if n, ok := nm[fmt.Sprint(r.(map[string]any)["id"])]; ok {
				ids = append(ids, n)
			}
		}
		sort.Strings(ids)
		o.answer = ids
	case strings.HasPrefix(st.answer, "count:"):
		n := 0
		for _, r := range asList(v) {
			if r.(map[string]any)["title"] == strings.TrimPrefix(st.answer, "count:") {
				n++
			}
		}
		o.answer = n
	}
	return o
}

// state is what the store holds for a bead, read by a show: each field bd and
// the fake both keep, with a missing field as its empty value, metadata as
// JSON values, and the bead's edges by far bead and type.
func (s side) state(t *testing.T, id string, nm map[string]string) map[string]any {
	t.Helper()
	out, errOut, status := s.self.run(step{}, []string{"show", id, "--json"})
	if status != 0 {
		t.Fatalf("%s: show %s exits %d: %s", s.self.name(), id, status, errOut)
	}
	rows := asList(decodeAny(t, out))
	if len(rows) != 1 {
		t.Fatalf("%s: show %s answers %d rows", s.self.name(), id, len(rows))
	}
	r := rows[0].(map[string]any)
	st := map[string]any{}
	for _, k := range []string{"status", "assignee", "notes", "issue_type", "close_reason"} {
		v, _ := r[k].(string)
		st[k] = v
	}
	st["priority"] = fmt.Sprint(r["priority"])
	meta, _ := r["metadata"].(map[string]any)
	if meta == nil {
		meta = map[string]any{}
	}
	st["metadata"] = meta
	var deps []string
	for _, d := range asList(r["dependencies"]) {
		m := d.(map[string]any)
		deps = append(deps, fmt.Sprintf("%s:%v", nameOf(nm, m["id"]), m["dependency_type"]))
	}
	sort.Strings(deps)
	st["dependencies"] = deps
	return st
}

func decodeAny(t *testing.T, s string) any {
	t.Helper()
	var v any
	if err := json.Unmarshal([]byte(strings.TrimSpace(s)), &v); err != nil {
		t.Fatalf("an answer that is not JSON: %q", s)
	}
	return v
}

func asList(v any) []any {
	l, _ := v.([]any)
	return l
}

func nameOf(nm map[string]string, id any) string {
	if n, ok := nm[fmt.Sprint(id)]; ok {
		return n
	}
	return fmt.Sprint(id)
}

// realSide runs bd on a scratch store.
type realSide struct {
	side
	store *gcbdtest.Store
	env   []string
}

func newRealSide(t *testing.T) *realSide {
	s := gcbdtest.New(t, "ct")
	var env []string
	for _, kv := range os.Environ() {
		if !strings.HasPrefix(kv, "BEADS_") && !strings.HasPrefix(kv, "GC_") {
			env = append(env, kv)
		}
	}
	r := &realSide{store: s, env: append(env, "BEADS_DIR="+s.DB())}
	r.self = r
	return r
}

func (r *realSide) name() string { return "bd" }

func (r *realSide) create(t *testing.T, title string, args ...string) string {
	t.Helper()
	return r.store.Create(title, args...)
}

func (r *realSide) run(st step, args []string) (string, string, int) {
	if st.actor != "" {
		args = append([]string{"--actor", st.actor}, args...)
	}
	cmd := exec.Command("bd", args...)
	cmd.Dir, cmd.Env, cmd.Stdin = r.store.Dir, r.env, strings.NewReader(st.stdin)
	return runCmd(cmd)
}

// fakeSide runs the fake gc, built from this package, on a store of its own.
type fakeSide struct {
	side
	bin, dir string
	env      []string
}

func newFakeSide(t *testing.T) *fakeSide {
	dir := t.TempDir()
	bin := filepath.Join(dir, "bin", "gc")
	build := exec.Command("go", "build", "-o", bin, ".")
	if out, err := build.CombinedOutput(); err != nil {
		t.Fatalf("the fake gc did not build: %v\n%s", err, out)
	}
	files := map[string]string{"beads.json": "[]", "deps.txt": "", "kv.txt": "", "gc.log": "", "session.log": "", "comments.json": "[]"}
	for name, body := range files {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	f := &fakeSide{bin: bin, dir: dir, env: []string{
		"PATH=" + filepath.Dir(bin) + string(os.PathListSeparator) + os.Getenv("PATH"),
		"STUB_STORE=" + filepath.Join(dir, "beads.json"), "STUB_DEPS=" + filepath.Join(dir, "deps.txt"),
		"STUB_KV=" + filepath.Join(dir, "kv.txt"), "STUB_GC_LOG=" + filepath.Join(dir, "gc.log"),
		"STUB_SESSION_LOG=" + filepath.Join(dir, "session.log"), "STUB_COMMENTS=" + filepath.Join(dir, "comments.json"),
	}}
	f.self = f
	return f
}

func (f *fakeSide) name() string { return "fake" }

func (f *fakeSide) create(t *testing.T, title string, args ...string) string {
	t.Helper()
	out, errOut, status := f.run(step{}, append([]string{"create", title, "--json"}, args...))
	var row struct {
		ID string `json:"id"`
	}
	if status != 0 || json.Unmarshal([]byte(out), &row) != nil || row.ID == "" {
		t.Fatalf("fake: create %s: %d %s %s", title, status, out, errOut)
	}
	return row.ID
}

func (f *fakeSide) run(st step, args []string) (string, string, int) {
	cmd := exec.Command(f.bin, append([]string{"bd"}, args...)...)
	cmd.Env = append(append(append([]string{}, f.env...), st.settings...), "BEADS_ACTOR="+st.actor)
	cmd.Dir, cmd.Stdin = f.dir, strings.NewReader(st.stdin)
	return runCmd(cmd)
}

func runCmd(cmd *exec.Cmd) (string, string, int) {
	var out, errOut bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &errOut
	err := cmd.Run()
	status := 0
	if ee, ok := err.(*exec.ExitError); ok {
		status = ee.ExitCode()
	} else if err != nil {
		status = -1
		errOut.WriteString(err.Error())
	}
	return out.String(), errOut.String(), status
}
