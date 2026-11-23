package gascity

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"
)

// The previews below are the text gc sling --dry-run --force printed on the
// city's build, with the rig, the agent and the beads renamed: a bead slung to
// a target with a default formula, and one slung to a target with none. The
// container's is dryRunBatch's text (cmd/gc/cmd_sling.go at
// gastownhall/gascity 8d2fb3120c).
const (
	beadPreview = `Dry run: gc sling rig/rig.polecat tk-1

Target:
  Session config: rig/rig.polecat (min=0 max=5)
  Sling query: bd update {} --set-metadata gc.routed_to=rig/rig.polecat
               Multi-session configs share a routed work queue via gc.routed_to.
               Any eligible session for that config can claim routed work.

Work:
  Bead:   tk-1 — "the work"
  Type:   task
  Status: open

Default formula:
  Formula: mol-polecat-work
  Target rig/rig.polecat has a default_sling_formula configured.
  A wisp will be attached automatically (use --no-formula to suppress).

  Would run: gc formula cook mol-polecat-work --attach tk-1
  Pre-check: tk-1 has no existing molecule/wisp children ✓

Route command (not executed):
  bd update 'tk-1' --set-metadata gc.routed_to=rig/rig.polecat
  This routes the bead to session config "rig/rig.polecat".
  A wisp/workflow root is also cooked and routed to the agent.

No side effects executed (--dry-run).
`
	nonePreview = `Dry run: gc sling rig/core.control-dispatcher tk-1

Target:
  Agent:       rig/core.control-dispatcher (non-expanding template)
  Sling query: bd update {} --set-metadata gc.routed_to=rig/core.control-dispatcher
               A sling query is the shell command that routes work.
               {} is replaced with the bead ID at dispatch time.

Work:
  Bead:   tk-1 — "the work"
  Type:   task
  Status: open

Route command (not executed):
  bd update 'tk-1' --set-metadata gc.routed_to=rig/core.control-dispatcher
  This assigns the bead to "rig/core.control-dispatcher".

No side effects executed (--dry-run).
`
	containerPreview = `Dry run: gc sling rig/rig.polecat tk-1

Work:
  Bead: tk-1 "a convoy"
  Type: convoy

  Children (2 total, 1 open):
    tk-2 "open child" (open) → would route + attach wisp
    tk-3 "done child" (closed) → skip

Default formula (per open child):
  Formula: mol-polecat-work
  Would run:
    gc formula cook mol-polecat-work --attach tk-2

Route commands (not executed):
  bd update 'tk-2' --set-metadata gc.routed_to=rig/rig.polecat

No side effects executed (--dry-run).
`
)

func TestDryRunDefaultReadsThePreview(t *testing.T) {
	for _, tc := range []struct {
		name, preview, formula string
		ok                     bool
	}{
		{"a bead to a target with a default", beadPreview, "mol-polecat-work", true},
		{"a bead to a target with none", nonePreview, "", true},
		{"a container", containerPreview, "mol-polecat-work", true},
		{"lines ended by CRLF", strings.ReplaceAll(beadPreview, "\n", "\r\n"), "mol-polecat-work", true},
		{"a preview cut short", beadPreview[:strings.Index(beadPreview, "Route command")], "", false},
		{"a preview cut short before any formula", nonePreview[:strings.Index(nonePreview, "Work:")], "", false},
		{"a heading with no formula line", strings.Replace(beadPreview, "  Formula: mol-polecat-work\n", "", 1), "", false},
		{"a heading with an empty formula", strings.Replace(beadPreview, "Formula: mol-polecat-work", "Formula: ", 1), "", false},
		{"two headings", strings.Replace(beadPreview, "Route command", "Default formula:\n  Formula: mol-other\n\nRoute command", 1), "", false},
		{"nothing", "", "", false},
	} {
		f, ok := dryRunDefault(tc.preview)
		if f != tc.formula || ok != tc.ok {
			t.Errorf("%s: dryRunDefault = %q, %v; want %q, %v", tc.name, f, ok, tc.formula, tc.ok)
		}
	}
}

// stubCity is a City whose gc is a script: it logs each call, answers config
// show --json with config, and answers a sling with the preview and the exit
// that previews gives its target. log returns the calls so far.
func stubCity(t *testing.T, config string, previews map[string]stubPreview) (c *City, log func() []string) {
	t.Helper()
	dir := t.TempDir()
	write := func(name, body string, mode os.FileMode) {
		t.Helper()
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), mode); err != nil {
			t.Fatal(err)
		}
	}
	write("gc", `#!/bin/sh
d=$(dirname "$0")
printf '%s\n' "$*" >> "$d/log"
if [ "$1 $2 $3" = "config show --json" ]; then cat "$d/config.json"; exit 0; fi
[ "$1" = sling ] || exit 2
shift
[ "$1" = --rig ] && shift 2
f="$d/$(printf '%s' "$1" | tr / _)"
[ -f "$f.out" ] || { echo "gc sling: agent \"$1\" not found in city.toml" >&2; exit 1; }
cat "$f.out"
exit "$(cat "$f.code")"
`, 0o755)
	write("config.json", config, 0o644)
	for target, p := range previews {
		name := strings.ReplaceAll(target, "/", "_")
		write(name+".out", p.out, 0o644)
		write(name+".code", p.code, 0o644)
	}
	return &City{bin: filepath.Join(dir, "gc")}, func() []string {
		raw, _ := os.ReadFile(filepath.Join(dir, "log"))
		return strings.Split(strings.TrimSpace(string(raw)), "\n")
	}
}

type stubPreview struct{ out, code string }

// An agent's own default formula is config show's answer, and no dry run is
// asked for it, even when it is empty. An agent that names none of its own,
// which config show's JSON prints for one whose pack's [agent_defaults] gives
// it one, takes the formula the sling's forced dry run prints, through the rig
// the sling names. A dry run that fails or does not read, or a sling that
// names no bead, is no answer, and a target no agent answers to is an error.
func TestDefaultFormula(t *testing.T) {
	config := `{"ok":true,"config":{"Agents":[
{"Name":"polecat","Dir":"rig","DefaultSlingFormula":"mol-own"},
{"Name":"po","Dir":"rig","DefaultSlingFormula":""},
{"Name":"inherits","Dir":"rig","DefaultSlingFormula":null},
{"Name":"control-dispatcher","Dir":"rig"},
{"Name":"refused","Dir":"rig"},
{"Name":"garbled","Dir":"rig"}]}}`
	c, log := stubCity(t, config, map[string]stubPreview{
		"rig/rig.inherits":            {strings.ReplaceAll(beadPreview, "mol-polecat-work", "mol-pack"), "0"},
		"rig/core.control-dispatcher": {nonePreview, "0"},
		"rig/rig.refused":             {"gc sling: bead tk-1 already has attached workflow tk-9\n", "1"},
		"rig/rig.garbled":             {"Dry run: gc sling rig/rig.garbled tk-1\n", "0"},
	})
	for _, tc := range []struct {
		name    string
		s       Sling
		formula string
		says    string
		asks    string
	}{
		{"an agent's own formula", Sling{Rig: "rig", Target: "rig/rig.polecat", Bead: "tk-1"}, "mol-own", "", ""},
		{"an agent's own empty formula", Sling{Target: "rig/rig.po", Bead: "tk-1"}, "", "", ""},
		{"a formula its pack gives", Sling{Rig: "rig", Target: "rig/rig.inherits", Bead: "tk-1"}, "mol-pack", "", "sling --rig rig rig/rig.inherits tk-1 --dry-run --force"},
		{"a pack's formula asked with no rig", Sling{Target: "rig/rig.inherits", Bead: "tk-2"}, "mol-pack", "", "sling rig/rig.inherits tk-2 --dry-run --force"},
		{"no formula from the agent or its pack", Sling{Target: "rig/core.control-dispatcher", Bead: "tk-1"}, "", "", "sling rig/core.control-dispatcher tk-1 --dry-run --force"},
		{"a dry run that fails", Sling{Target: "rig/rig.refused", Bead: "tk-1"}, "", "already has attached workflow", "sling rig/rig.refused tk-1 --dry-run --force"},
		{"a preview that does not read", Sling{Target: "rig/rig.garbled", Bead: "tk-1"}, "", "did not read", "sling rig/rig.garbled tk-1 --dry-run --force"},
		{"no bead to ask about", Sling{Target: "rig/rig.inherits"}, "", "no bead to name", ""},
		{"a target no agent answers to", Sling{Target: "rig/rig.none", Bead: "tk-1"}, "", "no agent in the city's config answers to rig/rig.none", ""},
	} {
		before := len(log())
		f, err := c.DefaultFormula(tc.s)
		switch {
		case tc.says == "" && (err != nil || f != tc.formula):
			t.Errorf("%s: DefaultFormula = %q, %v; want %q", tc.name, f, err, tc.formula)
		case tc.says != "" && (err == nil || !strings.Contains(err.Error(), tc.says)):
			t.Errorf("%s: DefaultFormula = %q, %v; want an error saying %q", tc.name, f, err, tc.says)
		}
		var asked []string
		for _, l := range log()[before:] {
			if strings.HasPrefix(l, "sling ") {
				asked = append(asked, l)
			}
		}
		if want := []string{tc.asks}; (tc.asks == "" && len(asked) != 0) || (tc.asks != "" && strings.Join(asked, "|") != strings.Join(want, "|")) {
			t.Errorf("%s: gc was asked %q; want %q", tc.name, asked, tc.asks)
		}
	}
	if n := strings.Count(strings.Join(log(), "\n"), "config show --json"); n != 1 {
		t.Errorf("config show was read %d times; want once", n)
	}
}

// Script runs a script from the pack's scripts directory with each argument as
// given, a line break inside one included, and answers its exit and its output.
// A city whose scripts directory is unnamed runs nothing and says why.
func TestScriptRunsFromThePacksScriptsDirectory(t *testing.T) {
	dir := t.TempDir()
	log := filepath.Join(dir, "calls")
	stub := "#!/bin/sh\nfor a in \"$@\"; do printf '%s\\n' \"$a\"; done >> '" + log + "'\n" +
		"[ \"${STUB_EXIT:-0}\" = 0 ] || echo 'human-gate.sh: the store refused it' >&2\nexit \"${STUB_EXIT:-0}\"\n"
	if err := os.WriteFile(filepath.Join(dir, "human-gate.sh"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	c := &City{scriptsDir: dir}
	if r := c.Script("human-gate.sh", "--subject", "tk-1", "--message", "Pull request closed.\nMore."); r.Code != 0 || r.Failure() != "" {
		t.Fatalf("a script that exits 0 answered %+v", r)
	}
	if raw, _ := os.ReadFile(log); string(raw) != "--subject\ntk-1\n--message\nPull request closed.\nMore.\n" {
		t.Fatalf("the script got %q", raw)
	}
	t.Setenv("STUB_EXIT", "1")
	if f := c.Script("human-gate.sh").Failure(); f != "exit 1: human-gate.sh: the store refused it" {
		t.Fatalf("a script that exits 1 failed as %q", f)
	}
	if r := (&City{}).Script("human-gate.sh"); r.Code != -1 || r.Err == nil || !strings.Contains(r.Err.Error(), "GCTK_SCRIPTS_DIR") {
		t.Fatalf("a city with no scripts directory answered %+v", r)
	}
}

// A city Within a context stops each command it runs once the context ends,
// and says so, whether or not the command's child still holds its output. A
// city with no context lets the same command run to its end.
func TestWithinStopsACommandWhenItsContextEnds(t *testing.T) {
	dir := t.TempDir()
	stub := "#!/bin/sh\nsleep 6 &\nsleep 6\n"
	if err := os.WriteFile(filepath.Join(dir, "pr-status-label.sh"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	start := time.Now()
	r := (&City{scriptsDir: dir}).In(dir).Within(ctx).Script("pr-status-label.sh", "clear")
	if took := time.Since(start); took > 200*time.Millisecond+stopGrace+time.Second {
		t.Fatalf("the stopped script held the call %s", took)
	}
	if r.Code != -1 || !errors.Is(r.Err, context.DeadlineExceeded) || !strings.Contains(r.Failure(), "pr-status-label.sh was stopped") {
		t.Fatalf("a stopped script answered %+v", r)
	}
	if err := os.WriteFile(filepath.Join(dir, "quick.sh"), []byte("#!/bin/sh\necho done\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	quick, stop := context.WithTimeout(context.Background(), 10*time.Second)
	defer stop()
	if r := (&City{scriptsDir: dir}).Within(quick).Script("quick.sh"); r.Code != 0 || strings.TrimSpace(r.Output) != "done" {
		t.Fatalf("a script that ends inside its bound answered %+v", r)
	}
}

// A city In a directory starts every command there, its scripts and gc alike,
// and a relative scripts directory still names the one it named from the
// process's working directory. The city it came from runs where the process
// does.
func TestInStartsEveryCommandInItsDirectory(t *testing.T) {
	base := t.TempDir()
	log := filepath.Join(base, "where")
	stub := "#!/bin/sh\npwd -P >> '" + log + "'\n"
	if err := os.MkdirAll(filepath.Join(base, "scripts"), 0o755); err != nil {
		t.Fatal(err)
	}
	for _, p := range []string{"scripts/human-gate.sh", "gc"} {
		if err := os.WriteFile(filepath.Join(base, p), []byte(stub), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	t.Chdir(base)
	there := t.TempDir()
	from := &City{bin: filepath.Join(base, "gc"), scriptsDir: "scripts"}
	c := from.In(there)
	if r := c.Script("human-gate.sh"); r.Code != 0 {
		t.Fatalf("the script in a relative scripts directory answered %+v", r)
	}
	c.Sling(Sling{Target: "rig/rig.polecat", Bead: "tk-1", Formula: "mol-polecat-work", Title: "the work"})
	from.Script("human-gate.sh")
	resolvedThere, err := filepath.EvalSymlinks(there)
	if err != nil {
		t.Fatal(err)
	}
	resolvedBase, err := filepath.EvalSymlinks(base)
	if err != nil {
		t.Fatal(err)
	}
	raw, _ := os.ReadFile(log)
	if want := resolvedThere + "\n" + resolvedThere + "\n" + resolvedBase + "\n"; string(raw) != want {
		t.Fatalf("the commands ran in %q, want %q", raw, want)
	}
}

// A city As an actor runs every command with BEADS_ACTOR naming that actor,
// and keeps the directory its commands start in. The city it came from runs
// as the process does.
func TestAsActsAsItsActorInItsDirectory(t *testing.T) {
	base := t.TempDir()
	log := filepath.Join(base, "who")
	stub := "#!/bin/sh\nprintf '%s %s\\n' \"${BEADS_ACTOR:-none}\" \"$(pwd -P)\" >> '" + log + "'\n"
	if err := os.WriteFile(filepath.Join(base, "bead-rehome.sh"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("BEADS_ACTOR", "")
	there := t.TempDir()
	from := (&City{scriptsDir: base}).In(there)
	from.As("rig/gc-toolkit.refinery").Script("bead-rehome.sh")
	from.Script("bead-rehome.sh")
	resolved, err := filepath.EvalSymlinks(there)
	if err != nil {
		t.Fatal(err)
	}
	raw, _ := os.ReadFile(log)
	if want := "rig/gc-toolkit.refinery " + resolved + "\nnone " + resolved + "\n"; string(raw) != want {
		t.Fatalf("the commands ran as %q, want %q", raw, want)
	}
}

// A cook passes its vars in their names' order, as --var flags, and reads the
// root from the summary line it prints with --json (formulaCookJSONResult in
// cmd/gc/cmd_formula.go at gastownhall/gascity 03f6fe825c). A cook that exits
// non-zero names no root, and one whose output names none answers with none.
func TestCookPassesItsVarsAndReadsTheRoot(t *testing.T) {
	dir := t.TempDir()
	gc := filepath.Join(dir, "gc")
	if err := os.WriteFile(gc, []byte(`#!/bin/sh
printf '%s\n' "$*" >> "$(dirname "$0")/log"
case "$5" in
  tk-1) echo 'warning: gc formula cook: projecting execution facts'; echo '{"schema_version":"1","ok":true,"formula":"mol-pr-review","mode":"attach","attach_bead_id":"tk-1","root_id":"tk-root","created":9}' ;;
  tk-2) echo 'gc formula cook: attach bead tk-2: not found' >&2; exit 1 ;;
  *) echo 'Root: tk-other' ;;
esac
`), 0o755); err != nil {
		t.Fatal(err)
	}
	c := &City{bin: gc}
	got := c.Cook(Cook{Formula: "mol-pr-review", Bead: "tk-1", Vars: map[string]string{"target": "main", "head": "abc", "pr_bead": "tk-1"}})
	if got.Code != 0 || got.Root != "tk-root" {
		t.Fatalf("the cook answered %+v, want exit 0 and root tk-root", got)
	}
	if got := c.Cook(Cook{Formula: "mol-pr-review", Bead: "tk-2"}); got.Code != 1 || got.Root != "" {
		t.Fatalf("a refused cook answered %+v, want exit 1 and no root", got)
	}
	if got := c.Cook(Cook{Formula: "mol-pr-review", Bead: "tk-3"}); got.Root != "" {
		t.Fatalf("a cook with no summary line named root %q", got.Root)
	}
	raw, _ := os.ReadFile(filepath.Join(dir, "log"))
	first := strings.Split(string(raw), "\n")[0]
	if want := "formula cook mol-pr-review --attach tk-1 --json --var head=abc --var pr_bead=tk-1 --var target=main"; first != want {
		t.Fatalf("the cook ran %q, want %q", first, want)
	}
}

// A formula sling names the target and the formula, asks for the JSON line, and
// reads the run's root from it: the workflow, else the molecule. A notice on
// standard error leaves the line readable, a sling that exits non-zero names no
// root and fails with its last line, and one whose line names neither answers
// with no root.
func TestAFormulaSlingReadsTheRunsRoot(t *testing.T) {
	c, log := stubGC(t, `case "$2" in
  rig/rig.polecat) echo 'gc sling: warning: projecting execution facts' >&2
    echo '{"schema_version":"1","success":true,"target":"rig/rig.polecat","method":"formula","formula":"mol-x","workflow_id":"tk-root","routed":true}' ;;
  rig/rig.wisp) echo '{"schema_version":"1","success":true,"molecule_id":"tk-wisp"}' ;;
  rig/rig.gone) echo 'gc sling: no agent rig/rig.gone' >&2; exit 1 ;;
  *) echo '{"schema_version":"1","success":true}' ;;
esac
`)
	got := c.SlingFormula(context.Background(), "rig/rig.polecat", "mol-x")
	if got.Failure() != "" || got.Root != "tk-root" {
		t.Fatalf("the sling answered %+v, want root tk-root", got)
	}
	if got := c.SlingFormula(context.Background(), "rig/rig.wisp", "mol-x"); got.Root != "tk-wisp" {
		t.Fatalf("a sling that names only its molecule answered %+v", got)
	}
	if got := c.SlingFormula(context.Background(), "rig/rig.gone", "mol-x"); got.Failure() != "exit 1: gc sling: no agent rig/rig.gone" || got.Root != "" {
		t.Fatalf("a refused sling answered %+v, failure %q", got, got.Failure())
	}
	if got := c.SlingFormula(context.Background(), "rig/rig.none", "mol-x"); got.Failure() != "" || got.Root != "" {
		t.Fatalf("a sling whose line names no root answered %+v", got)
	}
	if want := []string{"sling", "rig/rig.polecat", "mol-x", "--formula", "--json"}; !slices.Equal(log()[:5], want) {
		t.Fatalf("the sling ran %q, want %q", log()[:5], want)
	}
}

// A wake and a nudge name the session, and a nudge passes its message as one
// argument, whatever spaces and quotes it holds. A command that exits non-zero
// answers with its exit and its last line.
func TestAWakeAndANudgeNameTheSessionAndPassTheMessageWhole(t *testing.T) {
	dir := t.TempDir()
	gc := filepath.Join(dir, "gc")
	if err := os.WriteFile(gc, []byte(`#!/bin/sh
for a in "$@"; do printf '%s\n' "$a"; done >> "$(dirname "$0")/log"
echo -- >> "$(dirname "$0")/log"
[ "$3" = rig/gone.refinery ] && { echo "gc session $2: session not found" >&2; exit 1; }
exit 0
`), 0o755); err != nil {
		t.Fatal(err)
	}
	c := &City{bin: gc}
	msg := "PR head changed on tk-1: run 'gc prime' to check merge queue and begin processing."
	if r := c.Wake("rig/gc-toolkit.refinery"); r.Failure() != "" {
		t.Fatalf("the wake answered %+v", r)
	}
	if r := c.Nudge("rig/gc-toolkit.refinery", msg); r.Failure() != "" {
		t.Fatalf("the nudge answered %+v", r)
	}
	if f := c.Nudge("rig/gone.refinery", msg).Failure(); f != "exit 1: gc session nudge: session not found" {
		t.Fatalf("a nudge gc refused failed with %q", f)
	}
	raw, _ := os.ReadFile(filepath.Join(dir, "log"))
	want := "session\nwake\nrig/gc-toolkit.refinery\n--\nsession\nnudge\nrig/gc-toolkit.refinery\n" + msg + "\n--\n" +
		"session\nnudge\nrig/gone.refinery\n" + msg + "\n--\n"
	if string(raw) != want {
		t.Fatalf("gc ran with\n%s\nwant\n%s", raw, want)
	}
}

// The Claude settings file sits under the city's root.
func TestTheClaudeSettingsFile(t *testing.T) {
	dir := t.TempDir()
	gc := filepath.Join(dir, "gc")
	if err := os.WriteFile(gc, []byte(`#!/bin/sh
[ "$1 $2 $3" = "rig list --json" ] || exit 2
echo '{"rigs":[{"name":"town","path":"`+dir+`","prefix":"lx","hq":true},{"name":"r","path":"/r","prefix":"tk"}]}'
`), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(filepath.Join(dir, ".gc"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("GC_CITY_PATH", "")
	t.Setenv("GC_CITY", "")
	t.Setenv("GC_CITY_ROOT", "")
	c := &City{bin: gc}
	if got, err := c.ClaudeSettings(); err != nil || got != filepath.Join(dir, ".gc", "settings.json") {
		t.Errorf("ClaudeSettings = %q, %v", got, err)
	}
}
