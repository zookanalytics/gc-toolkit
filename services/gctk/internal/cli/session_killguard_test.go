package cli

import (
	"bytes"
	"encoding/json"
	"os"
	"strings"
	"testing"
)

// runKillGuard runs `gctk session kill-guard` with payload on its stdin.
func runKillGuard(t *testing.T, payload string) (stdout, stderr string, code int) {
	t.Helper()
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	stdin := os.Stdin
	os.Stdin = r
	t.Cleanup(func() { os.Stdin = stdin })
	if _, err := w.WriteString(payload); err != nil {
		t.Fatal(err)
	}
	if err := w.Close(); err != nil {
		t.Fatal(err)
	}
	var out, errb bytes.Buffer
	code = Run([]string{"session", "kill-guard"}, "test", &out, &errb)
	return out.String(), errb.String(), code
}

// shellCall is a PreToolUse payload for a shell call running command.
func shellCall(t *testing.T, tool, command string) string {
	t.Helper()
	raw, err := json.Marshal(map[string]any{
		"hook_event_name": "PreToolUse",
		"tool_name":       tool,
		"tool_input":      map[string]string{"command": command},
		"cwd":             "/work/tree",
	})
	if err != nil {
		t.Fatal(err)
	}
	return string(raw)
}

func TestKillGuardRefusesAPatternKill(t *testing.T) {
	codex := `{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"cd /work && killall node"},` +
		`"cwd":"/work","turn_id":"t-1","transcript_path":"/tmp/t.jsonl","tool_use_id":"call-1"}`
	for name, c := range map[string]struct{ payload, killer string }{
		"a Claude Code call": {shellCall(t, "Bash", "pkill -f 'tools/run-tests.sh'"), "pkill"},
		"a Codex call":       {codex, "killall"},
	} {
		t.Run(name, func(t *testing.T) {
			out, errText, code := runKillGuard(t, c.payload)
			if code != 0 || errText != "" {
				t.Fatalf("exit %d, stderr %q; want 0 and nothing", code, errText)
			}
			var deny preToolUseDeny
			if err := json.Unmarshal([]byte(out), &deny); err != nil {
				t.Fatalf("stdout is not the deny object: %v\n%s", err, out)
			}
			h := deny.HookSpecificOutput
			if h.HookEventName != "PreToolUse" || h.PermissionDecision != "deny" {
				t.Errorf("deny = %+v, want PreToolUse and deny", h)
			}
			for _, want := range []string{"`" + c.killer + "`", "TaskStop", "`kill <pid>`", "`kill -- -<pgid>`"} {
				if !strings.Contains(h.PermissionDecisionReason, want) {
					t.Errorf("the reason does not name %s:\n%s", want, h.PermissionDecisionReason)
				}
			}
			if !strings.Contains(out, "<pid>") || strings.Count(strings.TrimSpace(out), "\n") != 0 {
				t.Errorf("want one JSON line whose reason reads as written, got:\n%s", out)
			}
		})
	}
}

func TestKillGuardPassesWhatItDoesNotRefuse(t *testing.T) {
	for name, payload := range map[string]string{
		"a kill by pid":           shellCall(t, "Bash", "kill -TERM 12345"),
		"a kill by process group": shellCall(t, "Bash", "kill -TERM -- -4321"),
		"a grep for pkill":        shellCall(t, "Bash", "grep -rn pkill docs/"),
		"another tool":            shellCall(t, "Write", "pkill -f x"),
		"a payload with no tool":  `{"tool_input":{"command":"pkill -f x"}}`,
		"a payload not JSON":      `pkill -f x`,
		"an empty payload":        ``,
	} {
		t.Run(name, func(t *testing.T) {
			out, errText, code := runKillGuard(t, payload)
			if code != 0 || out != "" || errText != "" {
				t.Errorf("exit %d, stdout %q, stderr %q; want 0 and nothing", code, out, errText)
			}
		})
	}
}
