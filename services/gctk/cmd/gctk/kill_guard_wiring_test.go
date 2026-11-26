package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/cli"
)

// The pack's Claude overlays, from this package's directory.
const overlaysDir = "../../../../overlays"

// killGuardHandler is the command each overlay registers for the kill guard,
// and killGuardVerb the gctk words it runs. The command exits 0 whatever gctk
// does, so a gctk that is missing, or too old to know the verb, passes the
// call: Claude Code reads a PreToolUse hook's exit 2 as a refusal.
const (
	killGuardHandler = `G="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"; [ -x "$G" ] && "$G" session kill-guard; exit 0`
	killGuardVerb    = "session kill-guard"
)

// hookGroup is one entry of a settings file's PreToolUse list.
type hookGroup struct {
	Matcher string `json:"matcher"`
	Hooks   []struct {
		Type    string `json:"type"`
		Command string `json:"command"`
	} `json:"hooks"`
}

// Every agent runs the PreToolUse group for Bash that runs the gh origin guard:
// each Claude agent through its overlay, and each Codex agent through the copy
// gh-origin-guard-codex.sh makes of that group
// (assets/scripts/gh-origin-guard-wiring.test.sh holds each agent to it). So
// the kill guard reaches every agent when each such group runs it, once.
func TestEveryGroupRunningTheGhGuardRunsTheKillGuard(t *testing.T) {
	paths, err := filepath.Glob(filepath.Join(overlaysDir, "*", ".claude", "settings.json"))
	if err != nil || len(paths) == 0 {
		t.Fatalf("no overlay settings found in %s (%v)", overlaysDir, err)
	}
	groups := 0
	for _, path := range paths {
		raw, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		var settings struct {
			Hooks struct {
				PreToolUse []hookGroup `json:"PreToolUse"`
			} `json:"hooks"`
		}
		if err := json.Unmarshal(raw, &settings); err != nil {
			t.Fatalf("%s: %v", path, err)
		}
		for _, g := range settings.Hooks.PreToolUse {
			ghGuard, killGuards := false, 0
			for _, h := range g.Hooks {
				ghGuard = ghGuard || strings.Contains(h.Command, "gh-origin-guard.sh")
				if strings.Contains(h.Command, killGuardVerb) {
					killGuards++
					if h.Command != killGuardHandler || h.Type != "command" {
						t.Errorf("%s: the kill guard's handler is %s %q, want command %q", path, h.Type, h.Command, killGuardHandler)
					}
				}
			}
			if !ghGuard {
				continue
			}
			groups++
			if g.Matcher != "Bash" || killGuards != 1 {
				t.Errorf("%s: the %q group that runs gh-origin-guard.sh runs the kill guard %d times, want a Bash group that runs it once", path, g.Matcher, killGuards)
			}
		}
	}
	if groups == 0 {
		t.Fatalf("no overlay in %s registers gh-origin-guard.sh", overlaysDir)
	}
}

// The words the handler runs are the verb gctk refuses a pattern kill with, and
// it passes a kill by a recorded pid.
func TestTheKillGuardHandlerRunsTheVerb(t *testing.T) {
	if !strings.Contains(killGuardHandler, `"$G" `+killGuardVerb+";") {
		t.Fatalf("the handler %q does not run %q", killGuardHandler, killGuardVerb)
	}
	for command, refused := range map[string]bool{
		"pkill -f 'tools/run-tests.sh'": true,
		"kill -TERM 12345":              false,
	} {
		payload, err := json.Marshal(map[string]any{"tool_name": "Bash", "tool_input": map[string]string{"command": command}})
		if err != nil {
			t.Fatal(err)
		}
		out, errText, code := runVerb(t, payload)
		denied := strings.Contains(out, `"permissionDecision":"deny"`)
		if code != 0 || denied != refused {
			t.Errorf("%s: exit %d, denied %v, want exit 0 and denied %v (stdout %q, stderr %q)", command, code, denied, refused, out, errText)
		}
	}
}

// runVerb runs the kill guard's verb in this process with payload on stdin.
func runVerb(t *testing.T, payload []byte) (stdout, stderr string, code int) {
	t.Helper()
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	stdin := os.Stdin
	os.Stdin = r
	defer func() { os.Stdin = stdin }()
	if _, err := w.Write(payload); err != nil {
		t.Fatal(err)
	}
	if err := w.Close(); err != nil {
		t.Fatal(err)
	}
	var out, errb bytes.Buffer
	code = cli.Run(strings.Fields(killGuardVerb), "test", &out, &errb)
	return out.String(), errb.String(), code
}
