package cli

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
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

// titleTmuxStub logs a call like titleGCStub and fails it, so a read of the
// session's pane would show in the log rather than reach a real tmux server.
const titleTmuxStub = `#!/bin/sh
{ printf 'tmux|'; for a in "$@"; do printf '%s|' "$a"; done; echo; } >> "$STUB_LOG"
exit 1
`

const (
	claudeBead = `[{"id":"tk-s1","metadata":{"provider":"claude","session_name":"s-tk-s1"}}]`
	codexBead  = `[{"id":"tk-s1","metadata":{"provider":"codex","session_name":"s-tk-s1"}}]`
)

type titleRig struct {
	t   *testing.T
	log string
}

// newTitleRig puts the stubs first on PATH. The defaults are a Claude session
// tk-s1, a rename and a nudge that succeed, and a caller whose own session is
// tk-s1.
func newTitleRig(t *testing.T) *titleRig {
	t.Helper()
	bin := t.TempDir()
	for name, body := range map[string]string{"gc": titleGCStub, "tmux": titleTmuxStub} {
		if err := os.WriteFile(filepath.Join(bin, name), []byte(body), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	r := &titleRig{t: t, log: filepath.Join(t.TempDir(), "log")}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STUB_LOG", r.log)
	t.Setenv("GC_SESSION_ID", "tk-s1")
	t.Setenv("STUB_RENAME_OUT", `{"schema_version":"1","ok":true,"command":"session rename","action":"rename","session_id":"tk-s1","title":"x"}`)
	t.Setenv("STUB_RENAME_RC", "0")
	t.Setenv("STUB_RENAME_ERR", "")
	t.Setenv("STUB_SESSION_BEAD", claudeBead)
	t.Setenv("STUB_NUDGE_OUT", `{"schema_version":"1","ok":true,"session_id":"tk-s1","delivery":"immediate","queued":false,"outcome":"delivered"}`)
	t.Setenv("STUB_NUDGE_RC", "0")
	return r
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
		{"newline in subject", []string{"--topic", "x", "--subject", "tk-1\ntwo"}, "tk-s1"},
		{"no session to default to", []string{"--topic", "x"}, ""},
		{"PR given as #<n>", []string{"--topic", "x", "--pr", "#41"}, "tk-s1"},
		{"PR given as its link", []string{"--topic", "x", "--pr", "https://github.com/acme/widgets/pull/41"}, "tk-s1"},
		{"PR with no value", []string{"--topic", "x", "--pr"}, "tk-s1"},
		{"PR twice", []string{"--topic", "x", "--pr", "41", "--pr", "42"}, "tk-s1"},
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
	t.Run("renames, then types /rename at once, reading no pane", func(t *testing.T) {
		r := newTitleRig(t)
		stdout, stderr, code := r.run("--subject", "tk-a8k8dpw", "--topic", "converse tab title from its topic")
		if code != sessionExitDone {
			t.Fatalf("exit %d, stderr %q", code, stderr)
		}
		title := "tk-a8k8dpw — converse tab title from its topic"
		want := []string{
			"gc|session|rename|tk-s1|" + title + "|--json|",
			"gc|bd|show|tk-s1|",
			"gc|session|nudge|tk-s1|--delivery|immediate|/rename " + title + "|--json|",
		}
		got := r.calls("")
		if len(got) != len(want) {
			t.Fatalf("calls = %q, want %q", got, want)
		}
		for i := range want {
			if !strings.HasPrefix(got[i], want[i]) {
				t.Fatalf("call %d = %q, want %q", i, got[i], want[i])
			}
		}
		for _, line := range []string{"renamed tk-s1 to \"" + title + "\"", "nudged tk-s1: /rename delivered"} {
			if !strings.Contains(stdout, line) {
				t.Fatalf("stdout %q lacks %q", stdout, line)
			}
		}
	})

	t.Run("a codex session takes the same /rename", func(t *testing.T) {
		r := newTitleRig(t)
		t.Setenv("STUB_SESSION_BEAD", codexBead)
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

	t.Run("a provider whose name holds codex is codex, as Gas City reads it", func(t *testing.T) {
		r := newTitleRig(t)
		t.Setenv("STUB_SESSION_BEAD", `[{"id":"tk-s1","metadata":{"provider":"my-codex","session_name":"s-tk-s1"}}]`)
		if _, _, code := r.run("--topic", "x"); code != sessionExitDone || len(r.calls("gc|session|nudge|")) != 1 {
			t.Fatalf("exit %d, nudges %q", code, r.calls("gc|session|nudge|"))
		}
	})

	t.Run("another provider: renamed, no nudge", func(t *testing.T) {
		r := newTitleRig(t)
		t.Setenv("STUB_SESSION_BEAD", `[{"id":"tk-s1","metadata":{"provider":"gemini","session_name":"s-tk-s1"}}]`)
		stdout, _, code := r.run("--topic", "x")
		if code != sessionExitDone || len(r.calls("gc|session|nudge|")) != 0 {
			t.Fatalf("exit %d, calls %q", code, r.calls(""))
		}
		if !strings.Contains(stdout, "skipped the /rename nudge: provider gemini has no /rename command") {
			t.Fatalf("stdout %q", stdout)
		}
	})

	t.Run("a session that records no provider: renamed, no nudge", func(t *testing.T) {
		r := newTitleRig(t)
		t.Setenv("STUB_SESSION_BEAD", `[{"id":"tk-s1","metadata":{"session_name":"s-tk-s1"}}]`)
		stdout, _, code := r.run("--topic", "x")
		if code != sessionExitDone || len(r.calls("gc|session|nudge|")) != 0 || !strings.Contains(stdout, "skipped the /rename nudge: session tk-s1 records no provider") {
			t.Fatalf("exit %d, stdout %q, calls %q", code, stdout, r.calls(""))
		}
	})

	t.Run("a session bead that cannot be read: renamed, no nudge", func(t *testing.T) {
		r := newTitleRig(t)
		t.Setenv("STUB_SESSION_BEAD", "")
		stdout, _, code := r.run("--topic", "x")
		if code != sessionExitDone || len(r.calls("gc|session|nudge|")) != 0 || !strings.Contains(stdout, "skipped the /rename nudge: session tk-s1 could not be read") {
			t.Fatalf("exit %d, stdout %q, calls %q", code, stdout, r.calls(""))
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
		if got := r.calls(""); len(got) != 1 {
			t.Fatalf("ran past a failed rename: %q", got)
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

	t.Run("a nudge that reports no outcome is reported as sent", func(t *testing.T) {
		r := newTitleRig(t)
		t.Setenv("STUB_NUDGE_OUT", `{"ok":true,"queued":false}`)
		if stdout, _, code := r.run("--topic", "x"); code != sessionExitDone || !strings.Contains(stdout, "nudged tk-s1: /rename sent") {
			t.Fatalf("exit %d, stdout %q", code, stdout)
		}
	})
}

// TestSessionTitleItems covers each combination of the items a title is made
// of, which the session record and the typed /rename both carry.
func TestSessionTitleItems(t *testing.T) {
	cases := []struct {
		name  string
		args  []string
		title string
	}{
		{"subject, PR and topic", []string{"--subject", "tk-a8k8dpw", "--pr", "1409", "--topic", "show the PR on the tab"}, "tk-a8k8dpw #1409 — show the PR on the tab"},
		{"subject and topic", []string{"--subject", "tk-a8k8dpw", "--topic", "show the PR on the tab"}, "tk-a8k8dpw — show the PR on the tab"},
		{"PR and topic", []string{"--pr", "1409", "--topic", "show the PR on the tab"}, "#1409 — show the PR on the tab"},
		{"the topic alone", []string{"--topic", "triage the review queue"}, "triage the review queue"},
		{"an empty PR is not given", []string{"--subject", "tk-a8k8dpw", "--pr", "", "--topic", "t"}, "tk-a8k8dpw — t"},
		{"a blank subject is not given", []string{"--subject", " ", "--pr", "1409", "--topic", "t"}, "#1409 — t"},
		{"the flags in another order", []string{"--topic", "t", "--pr", " 1409 ", "--subject", "tk-a8k8dpw"}, "tk-a8k8dpw #1409 — t"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			r := newTitleRig(t)
			stdout, stderr, code := r.run(tc.args...)
			if code != sessionExitDone {
				t.Fatalf("exit %d, stderr %q", code, stderr)
			}
			if got := r.calls("gc|session|rename|"); len(got) != 1 || got[0] != "gc|session|rename|tk-s1|"+tc.title+"|--json|" {
				t.Fatalf("rename calls = %q, want the title %q", got, tc.title)
			}
			if got := r.calls("gc|session|nudge|"); len(got) != 1 || got[0] != "gc|session|nudge|tk-s1|--delivery|immediate|/rename "+tc.title+"|--json|" {
				t.Fatalf("nudge calls = %q, want /rename %q", got, tc.title)
			}
			if want := "renamed tk-s1 to \"" + tc.title + "\""; !strings.Contains(stdout, want) {
				t.Fatalf("stdout %q lacks %q", stdout, want)
			}
		})
	}
}
