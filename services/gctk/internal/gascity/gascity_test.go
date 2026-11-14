package gascity

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
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
