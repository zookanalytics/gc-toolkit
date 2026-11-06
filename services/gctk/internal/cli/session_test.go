package cli

import (
	"bytes"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"
)

// titleGCStub answers the three gc calls `gctk session title` makes: `session
// rename` prints $STUB_RENAME_OUT and exits $STUB_RENAME_RC, `bd show` prints
// $STUB_SESSION_BEAD, and `session nudge` prints $STUB_NUDGE_OUT and exits
// $STUB_NUDGE_RC. Every call's arguments go to $STUB_LOG, one call per line
// with each argument followed by "|", so a title with spaces reads back whole.
const titleGCStub = `#!/bin/sh
{ printf 'gc|'; for a in "$@"; do printf '%s|' "$a"; done; echo; } >> "$STUB_LOG"
case "$1 $2" in
  "session rename")
    printf '%s\n' "$STUB_RENAME_OUT"
    [ -z "$STUB_RENAME_ERR" ] || printf '%s\n' "$STUB_RENAME_ERR" >&2
    exit "${STUB_RENAME_RC:-0}" ;;
  "bd show") printf '%s\n' "$STUB_SESSION_BEAD" ;;
  "session nudge")
    printf '%s\n' "$STUB_NUDGE_OUT"
    exit "${STUB_NUDGE_RC:-0}" ;;
  *) echo "unsupported: $*" >&2; exit 2 ;;
esac
`

// titleTmuxStub answers `list-panes` with $STUB_PANES, failing when
// $STUB_PANES_RC is set, and each `capture-pane` with the next file of
// $STUB_CAPTURES, a directory of captures named 1, 2, ..., repeating the last
// once they run out. It logs like titleGCStub.
const titleTmuxStub = `#!/bin/sh
{ printf 'tmux|'; for a in "$@"; do printf '%s|' "$a"; done; echo; } >> "$STUB_LOG"
for a in "$@"; do
  case "$a" in
    list-panes)
      [ -z "$STUB_PANES_RC" ] || { echo "can't find session" >&2; exit "$STUB_PANES_RC"; }
      printf '%s\n' "$STUB_PANES"; exit 0 ;;
    capture-pane)
      n=$(cat "$STUB_CAPTURES/next" 2>/dev/null || echo 1)
      f="$STUB_CAPTURES/$n"
      if [ -f "$f" ]; then echo $((n + 1)) > "$STUB_CAPTURES/next"; else f="$STUB_CAPTURES/$((n - 1))"; fi
      cat "$f"; exit 0 ;;
  esac
done
echo "unsupported: $*" >&2; exit 2
`

const (
	emptyClaudeBox = "────────────────────────────────────────\n\x1b[39m❯\u00a0\x1b[2mTry \"write a test for <filepath>\"\n────────────────────────────────────────\n"
	draftClaudeBox = "────────────────────────────────────────\n\x1b[39m❯\u00a0half a message\n────────────────────────────────────────\n"
	emptyCodexBox  = "• PONG\n\n\x1b[1m›\x1b[0m \x1b[2mExplain this codebase\x1b[22m\n\n  gpt-5.5 low · /tmp/probe\n"
	claudeBead     = `[{"id":"tk-s1","metadata":{"provider":"claude","session_name":"s-tk-s1"}}]`
)

type titleRig struct {
	t        *testing.T
	log      string
	captures string
}

// newTitleRig puts the stubs first on PATH, names a tmux server in $TMUX and
// shortens the wait for an input box to empty. The defaults are a Claude
// session tk-s1 whose one agent pane shows an empty input box, a rename and a
// nudge that succeed, and a caller whose own session is tk-s1.
func newTitleRig(t *testing.T) *titleRig {
	t.Helper()
	bin := t.TempDir()
	for name, body := range map[string]string{"gc": titleGCStub, "tmux": titleTmuxStub} {
		if err := os.WriteFile(filepath.Join(bin, name), []byte(body), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	r := &titleRig{t: t, log: filepath.Join(t.TempDir(), "log"), captures: t.TempDir()}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STUB_LOG", r.log)
	t.Setenv("STUB_CAPTURES", r.captures)
	t.Setenv("TMUX", "/tmp/tmux-test/city,123,0")
	t.Setenv("GC_SESSION_ID", "tk-s1")
	t.Setenv("STUB_RENAME_OUT", `{"schema_version":"1","ok":true,"command":"session rename","action":"rename","session_id":"tk-s1","title":"x"}`)
	t.Setenv("STUB_RENAME_RC", "0")
	t.Setenv("STUB_RENAME_ERR", "")
	t.Setenv("STUB_SESSION_BEAD", claudeBead)
	t.Setenv("STUB_PANES", "agent\t%7")
	t.Setenv("STUB_PANES_RC", "")
	t.Setenv("STUB_NUDGE_OUT", `{"schema_version":"1","ok":true,"session_id":"tk-s1","delivery":"immediate","queued":false,"outcome":"delivered"}`)
	t.Setenv("STUB_NUDGE_RC", "0")
	r.screens(emptyClaudeBox)
	wait, poll := titleDraftWait, titleDraftPoll
	titleDraftWait, titleDraftPoll = 300*time.Millisecond, 20*time.Millisecond
	t.Cleanup(func() { titleDraftWait, titleDraftPoll = wait, poll })
	return r
}

// screens sets what successive captures of the pane show.
func (r *titleRig) screens(captures ...string) {
	r.t.Helper()
	os.Remove(filepath.Join(r.captures, "next"))
	for i, c := range captures {
		if err := os.WriteFile(filepath.Join(r.captures, strconv.Itoa(i+1)), []byte(c), 0o644); err != nil {
			r.t.Fatal(err)
		}
	}
}

// calls returns the logged calls whose program and leading arguments are
// prefix, such as "gc|session|nudge|".
func (r *titleRig) calls(prefix string) []string {
	r.t.Helper()
	raw, err := os.ReadFile(r.log)
	if err != nil && !os.IsNotExist(err) {
		r.t.Fatal(err)
	}
	var out []string
	for _, line := range strings.Split(strings.TrimSpace(string(raw)), "\n") {
		if strings.HasPrefix(line, prefix) {
			out = append(out, line)
		}
	}
	return out
}

func (r *titleRig) run(args ...string) (stdout, stderr string, code int) {
	r.t.Helper()
	var o, e bytes.Buffer
	code = Session(append([]string{"title"}, args...), &o, &e)
	return o.String(), e.String(), code
}

func TestSessionTitleUsage(t *testing.T) {
	cases := []struct {
		name string
		args []string
		env  string // GC_SESSION_ID
	}{
		{"no topic", []string{"--subject", "tk-1"}, "tk-s1"},
		{"blank topic", []string{"--topic", "  "}, "tk-s1"},
		{"unknown flag", []string{"--topic", "x", "--session-id", "tk-s1"}, "tk-s1"},
		{"flag twice", []string{"--topic", "x", "--topic", "y"}, "tk-s1"},
		{"flag with no value", []string{"--topic"}, "tk-s1"},
		{"newline in topic", []string{"--topic", "one\ntwo"}, "tk-s1"},
		{"no session to default to", []string{"--topic", "x"}, ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			r := newTitleRig(t)
			t.Setenv("GC_SESSION_ID", tc.env)
			if _, stderr, code := r.run(tc.args...); code != sessionExitUsage || !strings.Contains(stderr, "usage:") {
				t.Fatalf("exit %d, stderr %q; want usage exit %d", code, stderr, sessionExitUsage)
			}
			if got := r.calls("gc|"); len(got) != 0 {
				t.Fatalf("a usage error ran %v", got)
			}
		})
	}

	t.Run("unknown verb", func(t *testing.T) {
		var o, e bytes.Buffer
		if code := Session([]string{"name"}, &o, &e); code != sessionExitUsage {
			t.Fatalf("exit %d, want %d", code, sessionExitUsage)
		}
	})
}

func TestSessionTitle(t *testing.T) {
	t.Run("renames, then types /rename into an empty input box", func(t *testing.T) {
		r := newTitleRig(t)
		stdout, stderr, code := r.run("--subject", "tk-a8k8dpw", "--topic", "converse tab title from its topic")
		if code != sessionExitDone {
			t.Fatalf("exit %d, stderr %q", code, stderr)
		}
		title := "tk-a8k8dpw — converse tab title from its topic"
		if got := r.calls("gc|session|rename|"); len(got) != 1 || got[0] != "gc|session|rename|tk-s1|"+title+"|--json|" {
			t.Fatalf("rename calls = %q", got)
		}
		if got := r.calls("gc|session|nudge|"); len(got) != 1 || got[0] != "gc|session|nudge|tk-s1|--delivery|immediate|/rename "+title+"|--json|" {
			t.Fatalf("nudge calls = %q", got)
		}
		capture := r.calls("tmux|-S|/tmp/tmux-test/city|capture-pane|-t|%7|")
		if len(capture) != 1 {
			t.Fatalf("the agent pane was captured %d times, want once: %q", len(capture), r.calls("tmux|"))
		}
		for _, want := range []string{"renamed tk-s1 to \"" + title + "\"", "nudged tk-s1: /rename delivered"} {
			if !strings.Contains(stdout, want) {
				t.Fatalf("stdout %q lacks %q", stdout, want)
			}
		}
	})

	t.Run("the topic alone without a subject", func(t *testing.T) {
		r := newTitleRig(t)
		if _, stderr, code := r.run("--topic", "triage the review queue"); code != sessionExitDone {
			t.Fatalf("exit %d, stderr %q", code, stderr)
		}
		if got := r.calls("gc|session|nudge|"); len(got) != 1 || !strings.Contains(got[0], "|/rename triage the review queue|") {
			t.Fatalf("nudge calls = %q", got)
		}
	})

	t.Run("a draft that stays: no nudge", func(t *testing.T) {
		r := newTitleRig(t)
		r.screens(draftClaudeBox)
		stdout, _, code := r.run("--topic", "x")
		if code != sessionExitDone {
			t.Fatalf("exit %d, want %d", code, sessionExitDone)
		}
		if got := r.calls("gc|session|nudge|"); len(got) != 0 {
			t.Fatalf("typed into a draft: %q", got)
		}
		if !strings.Contains(stdout, "skipped the /rename nudge: the input box still held text") {
			t.Fatalf("stdout %q does not report the skip", stdout)
		}
		if n := len(r.calls("tmux|-S|/tmp/tmux-test/city|capture-pane|")); n < 2 {
			t.Fatalf("the box was read %d times; a draft is waited on", n)
		}
	})

	t.Run("a draft sent within the wait: nudged once the box is empty", func(t *testing.T) {
		r := newTitleRig(t)
		r.screens(draftClaudeBox, draftClaudeBox, emptyClaudeBox)
		stdout, _, code := r.run("--topic", "x")
		if code != sessionExitDone || len(r.calls("gc|session|nudge|")) != 1 {
			t.Fatalf("exit %d, nudges %q, stdout %q", code, r.calls("gc|session|nudge|"), stdout)
		}
	})

	t.Run("no input box on screen: no nudge", func(t *testing.T) {
		r := newTitleRig(t)
		r.screens("  Do you want to proceed?\n ❯ 1. Yes\n   2. No\n")
		stdout, _, code := r.run("--topic", "x")
		if code != sessionExitDone || len(r.calls("gc|session|nudge|")) != 0 || !strings.Contains(stdout, "skipped the /rename nudge") {
			t.Fatalf("exit %d, nudges %q, stdout %q", code, r.calls("gc|session|nudge|"), stdout)
		}
	})

	t.Run("a codex session takes the same /rename", func(t *testing.T) {
		r := newTitleRig(t)
		t.Setenv("STUB_SESSION_BEAD", `[{"id":"tk-s1","metadata":{"provider":"codex","session_name":"s-tk-s1"}}]`)
		r.screens(emptyCodexBox)
		if _, stderr, code := r.run("--topic", "x"); code != sessionExitDone || len(r.calls("gc|session|nudge|")) != 1 {
			t.Fatalf("exit %d, stderr %q, nudges %q", code, stderr, r.calls("gc|session|nudge|"))
		}
	})

	t.Run("a wrapped provider whose builtin is claude", func(t *testing.T) {
		r := newTitleRig(t)
		t.Setenv("STUB_SESSION_BEAD", `[{"id":"tk-s1","metadata":{"provider":"claude-watch","builtin_ancestor":"claude","session_name":"s-tk-s1"}}]`)
		if _, _, code := r.run("--topic", "x"); code != sessionExitDone || len(r.calls("gc|session|nudge|")) != 1 {
			t.Fatalf("exit %d, nudges %q", code, r.calls("gc|session|nudge|"))
		}
	})

	t.Run("another provider: renamed, no nudge, no pane read", func(t *testing.T) {
		r := newTitleRig(t)
		t.Setenv("STUB_SESSION_BEAD", `[{"id":"tk-s1","metadata":{"provider":"gemini","session_name":"s-tk-s1"}}]`)
		stdout, _, code := r.run("--topic", "x")
		if code != sessionExitDone || len(r.calls("gc|session|nudge|")) != 0 || len(r.calls("tmux|")) != 0 {
			t.Fatalf("exit %d, calls %q", code, r.calls(""))
		}
		if !strings.Contains(stdout, "provider gemini has no /rename command") {
			t.Fatalf("stdout %q", stdout)
		}
	})

	t.Run("an alias resolves to the id the rename reports", func(t *testing.T) {
		r := newTitleRig(t)
		t.Setenv("STUB_RENAME_OUT", `{"ok":true,"action":"rename","session_id":"tk-s9","title":"x"}`)
		t.Setenv("STUB_SESSION_BEAD", `[{"id":"tk-s9","metadata":{"provider":"claude","session_name":"s-tk-s9"}}]`)
		if _, _, code := r.run("--topic", "x", "--session", "gc-toolkit/gc-toolkit.tk-c1"); code != sessionExitDone {
			t.Fatalf("exit %d", code)
		}
		if got := r.calls("gc|session|rename|"); len(got) != 1 || !strings.HasPrefix(got[0], "gc|session|rename|gc-toolkit/gc-toolkit.tk-c1|") {
			t.Fatalf("rename calls = %q", got)
		}
		if got := r.calls("gc|bd|show|tk-s9|"); len(got) != 1 {
			t.Fatalf("the session bead read = %q, want tk-s9", r.calls("gc|bd|"))
		}
		if got := r.calls("tmux|-S|/tmp/tmux-test/city|list-panes|-s|-t|=s-tk-s9:|"); len(got) != 1 {
			t.Fatalf("pane lookup = %q", r.calls("tmux|"))
		}
		if got := r.calls("gc|session|nudge|tk-s9|"); len(got) != 1 {
			t.Fatalf("nudge calls = %q", r.calls("gc|session|nudge|"))
		}
	})

	t.Run("a failed rename fails the command and does nothing else", func(t *testing.T) {
		r := newTitleRig(t)
		t.Setenv("STUB_RENAME_RC", "1")
		t.Setenv("STUB_RENAME_OUT", "")
		t.Setenv("STUB_RENAME_ERR", "gc session rename: session not found")
		_, stderr, code := r.run("--topic", "x")
		if code != sessionExitRenameFail {
			t.Fatalf("exit %d, want %d", code, sessionExitRenameFail)
		}
		if !strings.Contains(stderr, "session not found") {
			t.Fatalf("stderr %q does not carry gc's error", stderr)
		}
		if got := r.calls("gc|session|nudge|"); len(got) != 0 || len(r.calls("tmux|")) != 0 {
			t.Fatalf("ran past a failed rename: %q", r.calls(""))
		}
	})

	t.Run("a failed nudge exits 3", func(t *testing.T) {
		r := newTitleRig(t)
		t.Setenv("STUB_NUDGE_RC", "1")
		t.Setenv("STUB_NUDGE_OUT", `{"ok":false,"error":"session is not running"}`)
		if _, stderr, code := r.run("--topic", "x"); code != sessionExitNudgeFailed || !strings.Contains(stderr, "not running") {
			t.Fatalf("exit %d, stderr %q", code, stderr)
		}
	})

	t.Run("a queued nudge is reported as queued", func(t *testing.T) {
		r := newTitleRig(t)
		t.Setenv("STUB_NUDGE_OUT", `{"ok":true,"queued":true,"outcome":"queued"}`)
		if stdout, _, code := r.run("--topic", "x"); code != sessionExitDone || !strings.Contains(stdout, "queued the /rename nudge") {
			t.Fatalf("exit %d, stdout %q", code, stdout)
		}
	})

	t.Run("no tmux server named: no pane read, no nudge", func(t *testing.T) {
		r := newTitleRig(t)
		t.Setenv("TMUX", "")
		stdout, _, code := r.run("--topic", "x")
		if code != sessionExitDone || len(r.calls("tmux|")) != 0 || len(r.calls("gc|session|nudge|")) != 0 {
			t.Fatalf("exit %d, calls %q", code, r.calls(""))
		}
		if !strings.Contains(stdout, "$TMUX is unset") {
			t.Fatalf("stdout %q", stdout)
		}
	})

	t.Run("a session not on this tmux server", func(t *testing.T) {
		r := newTitleRig(t)
		t.Setenv("STUB_PANES_RC", "1")
		if stdout, _, code := r.run("--topic", "x"); code != sessionExitDone || len(r.calls("gc|session|nudge|")) != 0 || !strings.Contains(stdout, "is not on the tmux server") {
			t.Fatalf("exit %d, stdout %q", code, stdout)
		}
	})
}

func TestTitlePaneChoice(t *testing.T) {
	cases := []struct {
		name, panes, want string // want "" = no pane, so no nudge
	}{
		{"the marked agent pane among a person's splits", "pane\t%3\nagent\t%7\npane\t%9", "%7"},
		{"one unmarked pane", "pane\t%4", "%4"},
		{"unmarked splits: none is known to be the agent's", "pane\t%3\npane\t%4", ""},
		{"the agent pane is gone", "orphan\t%3", ""},
		{"two marked panes", "agent\t%3\nagent\t%4", ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			r := newTitleRig(t)
			t.Setenv("STUB_PANES", tc.panes)
			if _, _, code := r.run("--topic", "x"); code != sessionExitDone {
				t.Fatalf("exit %d", code)
			}
			captured := r.calls("tmux|-S|/tmp/tmux-test/city|capture-pane|-t|")
			nudges := r.calls("gc|session|nudge|")
			if tc.want == "" {
				if len(captured) != 0 || len(nudges) != 0 {
					t.Fatalf("read or typed into a pane: %q %q", captured, nudges)
				}
				return
			}
			if len(captured) != 1 || !strings.HasPrefix(captured[0], "tmux|-S|/tmp/tmux-test/city|capture-pane|-t|"+tc.want+"|") || len(nudges) != 1 {
				t.Fatalf("captured %q, nudges %q; want pane %s", captured, nudges, tc.want)
			}
		})
	}
}
