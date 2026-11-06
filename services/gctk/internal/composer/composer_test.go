package composer

import (
	"strings"
	"testing"
)

// The Claude Code rows below are real: captured with `tmux capture-pane -p -e
// -J` from Claude Code 2.1.318 under tmux 3.8, the input box, its rules and the
// status row under them. Rows that named the account or its usage were
// replaced by a neutral status row. Claude Code puts a no-break space (U+00A0)
// after its prompt glyph.
var (
	claudeRuleTrue  = "\x1b[38;2;136;136;136m" + strings.Repeat("─", 100)
	claudeCloseTrue = "\x1b[0m\x1b[38;2;136;136;136m" + strings.Repeat("─", 100)
	claudeStatus    = "\x1b[39m  \x1b[38;2;255;193;7m⏵⏵ auto mode on\x1b[38;2;153;153;153m (shift+tab to cycle)"
	claudeRule256   = "\x1b[38;5;244m" + strings.Repeat("─", 80)
)

// The Codex 0.164 rows are built from its render code at openai/codex
// rust-v0.164.0, not captured: ChatComposer::render_with_options draws the
// glyph on the first row of the draft alone, the draft's rows from the third
// column, its placeholder dim from that column while the draft is empty, and
// its scroll arrows dim in the right margin. The footer under the composer
// starts in the same third column (FOOTER_INDENT_COLS), in a color that is not
// dim (secondary_text_style).
var (
	codexGlyph  = "\x1b[1m›\x1b[0m"
	codexFooter = "\x1b[38;2;139;139;139m  ? for shortcuts" + strings.Repeat(" ", 46) + "100% context left\x1b[39m"
)

func capture(rows ...string) string { return strings.Join(rows, "\n") + "\n" }

func TestRead(t *testing.T) {
	cases := []struct {
		name    string
		capture string
		want    State
	}{
		{
			// A fresh Claude Code at its idle prompt draws its placeholder dim.
			name: "claude idle, dim placeholder",
			capture: capture(
				"\x1b[39m  \x1b[38;2;255;193;7mWelcome back",
				claudeRuleTrue,
				"\x1b[39m❯\u00a0\x1b[2mTry \"write a test for <filepath>\"",
				claudeCloseTrue,
				claudeStatus,
			),
			want: Empty,
		},
		{
			name: "claude draft",
			capture: capture(
				claudeRuleTrue,
				"\x1b[39m❯\u00a0half a message                   ",
				claudeRuleTrue,
				claudeStatus,
			),
			want: Holding,
		},
		{
			// A turn running: the spinner and tip above the box, which is empty.
			name: "claude mid-turn, empty",
			capture: capture(
				"\x1b[38;5;174m·\x1b[39m \x1b[38;5;174mBurrowing…\x1b[39m (9m 22s · ↓ 27.5k tokens)",
				"\x1b[38;5;246m  ⎿  Tip: Use /btw to ask a quick side question without interrupting Claude's",
				"",
				claudeRule256,
				"\x1b[38;5;246m❯\u00a0\x1b[39m"+strings.Repeat(" ", 70),
				claudeRule256,
				"\x1b[0m  \x1b[38;5;211m⏵⏵ bypass permissions on\x1b[38;5;246m (shift+tab to cycle)",
			),
			want: Empty,
		},
		{
			// The cursor on an empty box is a reverse-video cell on the
			// placeholder's first character.
			name: "claude idle, reverse-video cursor on the placeholder",
			capture: capture(
				claudeRuleTrue,
				"\x1b[39m❯\u00a0\x1b[7mP\x1b[27m\x1b[2mress up to edit queued messages",
				claudeCloseTrue,
			),
			want: Empty,
		},
		{
			// The second row of a draft is a draft too.
			name: "claude multi-line draft, first row empty",
			capture: capture(
				claudeRuleTrue,
				"\x1b[39m❯\u00a0",
				"  and the rest of it",
				claudeRuleTrue,
			),
			want: Holding,
		},
		{
			// A prompt glyph on a wrapped row of a draft is still the draft.
			name: "claude draft whose second row opens with the glyph",
			capture: capture(
				claudeRuleTrue,
				"\x1b[39m❯\u00a0a first line",
				"❯ quoted on the second",
				claudeRuleTrue,
			),
			want: Holding,
		},
		{
			// A user message in the transcript opens with the glyph, unframed.
			name: "claude transcript glyph above an empty box",
			capture: capture(
				"❯ an earlier message",
				"",
				"⏺ a reply",
				claudeRuleTrue,
				"\x1b[39m❯\u00a0\x1b[2mTry \"refactor <filepath>\"",
				claudeCloseTrue,
			),
			want: Empty,
		},
		{
			// A permission menu replaces the box. Its cursor row opens with
			// the glyph, but no rules frame it, so there is no box to type
			// into.
			name: "claude permission menu",
			capture: capture(
				claudeRuleTrue,
				" Bash command",
				"   ls -la",
				" Do you want to proceed?",
				" ❯ 1. Yes",
				"   2. No",
			),
			want: Absent,
		},
		{
			// A dialog drawn in the box's place leaves only the transcript's
			// glyph rows, which no rules frame.
			name: "claude transcript glyph with a dialog in the box's place",
			capture: capture(
				"❯ an earlier message",
				"",
				"⏺ a reply",
				claudeRuleTrue,
				" Background tasks",
				"   1 shell running",
			),
			want: Absent,
		},
		{
			name: "claude staged paste",
			capture: capture(
				claudeRuleTrue,
				"\x1b[39m❯\u00a0[Pasted text #1 +40 lines]",
				claudeRuleTrue,
			),
			want: Holding,
		},
		{
			name:    "nothing drawn yet",
			capture: capture("", "  Starting…", ""),
			want:    Absent,
		},
		{
			// Codex's idle pane: a finished reply, the composer with its
			// example prompt drawn dim, and the model and directory under it
			// (Gas City's live fixture from codex-cli 0.147.0).
			name: "codex idle, dim placeholder",
			capture: capture(
				"• PONG",
				"",
				"\x1b[1m›\x1b[0m \x1b[2mExplain this codebase\x1b[22m",
				"",
				"  \x1b[2mgpt-5.5 low · /tmp/probe\x1b[22m",
			),
			want: Empty,
		},
		{
			name: "codex mid-turn, empty",
			capture: capture(
				"• Working (3s • esc to interrupt)",
				"",
				"\x1b[1m›\x1b[0m \x1b[2mFind and fix a bug in @filename\x1b[22m",
				"",
				"  gpt-6.1-sol · ~/work",
			),
			want: Empty,
		},
		{
			name: "codex draft",
			capture: capture(
				"• PONG",
				"",
				"\x1b[1m›\x1b[0m fix the flaky test",
				"",
				"  gpt-5.5 low · /tmp/probe",
			),
			want: Holding,
		},
		{
			// Codex draws earlier user messages with the same glyph; the live
			// composer is the last such row.
			name: "codex earlier message above an empty composer",
			capture: capture(
				"› what does this repo do?",
				"",
				"• It builds a CLI.",
				"",
				"\x1b[1m›\x1b[0m \x1b[2mExplain this codebase\x1b[22m",
				"",
				"  gpt-5.5 low · /tmp/probe",
			),
			want: Empty,
		},
		{
			name: "codex staged paste",
			capture: capture(
				"\x1b[1m›\x1b[0m [Pasted Content 1200 chars]",
				"",
				"  gpt-5.5 low · /tmp/probe",
			),
			want: Holding,
		},
		{
			// The footer's text is not dim, and the placeholder still marks
			// the box empty.
			name: "codex 0.164 idle, footer not dim",
			capture: capture(
				"",
				codexGlyph+" \x1b[2mAsk Codex to do anything\x1b[22m",
				"",
				codexFooter,
			),
			want: Empty,
		},
		{
			// A cursor drawn on the placeholder's first character goes with
			// the placeholder, as StripDim pairs them.
			name: "codex placeholder under a reverse-video cursor cell",
			capture: capture(
				"",
				codexGlyph+" \x1b[7mA\x1b[27m\x1b[2msk Codex to do anything\x1b[22m",
				"",
				codexFooter,
			),
			want: Empty,
		},
		{
			// A draft whose first line is blank, such as one written in the
			// external editor, leaves nothing after the glyph.
			name: "codex draft whose first row is blank",
			capture: capture(
				"",
				codexGlyph+" ",
				"  unfinished operator message",
				"",
				codexFooter,
			),
			want: Holding,
		},
		{
			// A draft taller than the box, scrolled to a blank line of it: the
			// dim scroll arrow in the right margin is no placeholder.
			name: "codex scrolled draft showing a blank row",
			capture: capture(
				"",
				codexGlyph+strings.Repeat(" ", 78)+"\x1b[2m↑\x1b[22m",
				"  a later line of a long draft"+strings.Repeat(" ", 49)+"\x1b[2m↓\x1b[22m",
				"",
				codexFooter,
			),
			want: Holding,
		},
		{
			// A later row of the draft that is the bare glyph is no prompt.
			name: "codex draft whose later row is a bare glyph",
			capture: capture(
				"",
				codexGlyph+" hello",
				"  ›",
				"",
				codexFooter,
			),
			want: Holding,
		},
		{
			// A plain capture with the attributes gone, as `gc session peek`
			// prints it: an empty Claude box still reads empty.
			name: "claude empty box without escapes",
			capture: capture(
				strings.Repeat("─", 80),
				"❯\u00a0",
				strings.Repeat("─", 80),
			),
			want: Empty,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := Read(tc.capture); got != tc.want {
				t.Fatalf("Read = %v, want %v", got, tc.want)
			}
		})
	}
}

func TestStripDim(t *testing.T) {
	cases := []struct {
		name, in, want string
	}{
		{"dim run removed", "a\x1b[2mdim\x1b[22mb", "ab"},
		{"reset ends dim", "\x1b[2mdim\x1b[0mkept", "kept"},
		{"empty SGR resets", "\x1b[2mdim\x1b[mkept", "kept"},
		{"colors are not dim", "\x1b[38;5;246mgrey\x1b[39m", "grey"},
		// A 24-bit color whose components hold a 2 must not read as dim.
		{"truecolor with a 2 component", "\x1b[38;2;2;2;2mtext", "text"},
		{"one reverse cell before dim goes", "❯ \x1b[7mT\x1b[27m\x1b[2mry it", "❯ "},
		{"reverse cell before typed text stays", "\x1b[7mh\x1b[27mello", "hello"},
		{"longer reverse run stays", "\x1b[7msel\x1b[27m\x1b[2mdim", "sel"},
		{"hyperlink escape removed", "\x1b]8;id=1;https://x\x1b\\link\x1b]8;;\x1b\\", "link"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := StripDim(tc.in); got != tc.want {
				t.Fatalf("StripDim(%q) = %q, want %q", tc.in, got, tc.want)
			}
		})
	}
}
