// Package composer reads the input box of an agent's terminal: whether the
// box Claude Code or Codex draws for the next message is on screen, and
// whether it holds text.
//
// It is a port of Gas City's own reader of that box, in
// internal/runtime/tmux at gastownhall/gascity 9f807760c: captureInputLines,
// stripDimText, readClaudeInput and paneShowsDrainedComposer. Gas City uses it
// inside its tmux runtime and exposes it through no gc command or supervisor
// endpoint. `gc session peek` returns the pane's text with its attributes
// dropped, and both providers draw a placeholder dim in an empty box: Claude
// Code its "Try ..." text and its prompt suggestions, Codex its example prompt
// (codex-rs/tui/src/bottom_pane/chat_composer.rs at openai/codex
// rust-v0.164.0). Without the attributes an empty box with a placeholder reads
// as one holding a draft, so the capture this package reads keeps them.
package composer

import (
	"strings"
	"unicode/utf8"
)

// CaptureArgs are the tmux arguments, after the target, that capture what
// Read reads: -e keeps the escape sequences, so dim text can be told apart,
// and -J joins a row tmux wrapped with the row it continues on. The window is
// the last 120 rows, Gas City's PromptObservationLines.
var CaptureArgs = []string{"-p", "-e", "-J", "-S", "-120"}

// State is what a capture shows of the live input box.
type State int

const (
	// Absent: no input box is on screen, such as while a dialog or a
	// permission menu has replaced it, or before the agent has drawn one.
	Absent State = iota
	// Empty: the box is on screen and holds no text.
	Empty
	// Holding: the box holds text, typed or a staged paste.
	Holding
)

func (s State) String() string {
	switch s {
	case Empty:
		return "empty"
	case Holding:
		return "holding"
	default:
		return "absent"
	}
}

// prompt is one provider's input row: the glyph that opens it and the
// placeholder the box shows for a paste that has not been submitted yet.
type prompt struct {
	prefix      string
	pasteMarker string
}

// prompts are the input rows Read knows, Gas City's stagedDraftMarkers:
// Claude Code's "❯ " (DefaultReadyPromptPrefix) and Codex's "› "
// (codexPromptPrefix).
var prompts = []prompt{
	{prefix: "❯ ", pasteMarker: "[Pasted text #"},
	{prefix: "› ", pasteMarker: "[Pasted Content "},
}

// Read reports the state of the live input box in capture, the output of
// capture-pane with CaptureArgs. The live box is the last row that opens with
// a provider's prompt glyph, because both providers draw earlier messages with
// the same glyph above it. Claude Code frames its box with full-width rules,
// and every row between them is the draft. A Codex box holds text when its
// row does after the glyph.
func Read(capture string) State {
	lines := strings.Split(strings.TrimRight(capture, "\n"), "\n")
	for i, line := range lines {
		lines[i] = StripDim(line)
	}
	live, prefix := -1, ""
	for i, line := range lines {
		for _, p := range prompts {
			if matchesPrompt(line, p.prefix) {
				live, prefix = i, p.prefix
			}
		}
	}
	if live < 0 {
		return Absent
	}
	for _, line := range lines[live:] {
		for _, p := range prompts {
			if strings.Contains(line, p.pasteMarker) {
				return Holding
			}
		}
	}
	// A prompt glyph on a wrapped row is still part of Claude's framed draft,
	// so the box is read from the rule above the live row.
	frameStart := live
	for frameStart > 0 && !isRule(lines[frameStart-1]) {
		frameStart--
	}
	if frameStart > 0 {
		if rows, ok := claudeInput(lines[frameStart-1:]); ok {
			for _, row := range rows {
				if strings.TrimSpace(row) != "" {
					return Holding
				}
			}
			return Empty
		}
	}
	if strings.TrimSpace(remainder(lines[live], prefix)) != "" {
		return Holding
	}
	return Empty
}

// claudeInput finds Claude Code's live input box in lines: the last prompt
// row directly under a full-width rule, the rows below it, and the rule that
// closes it. Rows of the transcript start with the same glyph but are not
// framed by rules, and neither is the "❯ 1. Yes" cursor of a permission menu.
// It reports false when no framed box is on screen (readClaudeInput).
func claudeInput(lines []string) ([]string, bool) {
	const claude = "❯ "
	for i := len(lines) - 1; i >= 1; i-- {
		if !isRule(lines[i-1]) || !matchesPrompt(lines[i], claude) {
			continue
		}
		rows := []string{remainder(lines[i], claude)}
		for _, line := range lines[i+1:] {
			if isRule(line) {
				return rows, true
			}
			rows = append(rows, line)
		}
		return nil, false
	}
	return nil, false
}

// isRule reports whether line is a full-width rule: ten or more box-drawing
// "─" and nothing else (isDialogRule).
func isRule(line string) bool {
	trimmed := strings.TrimSpace(line)
	return utf8.RuneCountInString(trimmed) >= 10 && strings.Trim(trimmed, "─") == ""
}

// matchesPrompt reports whether line opens with prefix, a prompt glyph and the
// space after it, or is the bare glyph. A non-breaking space reads as a space,
// and a leading box border is stripped, for a TUI that draws its input row
// inside a box (matchesPromptPrefix).
func matchesPrompt(line, prefix string) bool {
	glyph := strings.TrimSpace(prefix)
	trimmed := strings.TrimSpace(strings.ReplaceAll(line, "\u00a0", " "))
	for _, cand := range []string{trimmed, stripBoxBorder(trimmed)} {
		if strings.HasPrefix(cand, prefix) || cand == glyph {
			return true
		}
	}
	return false
}

// remainder is what line holds after the prompt glyph prefix opens it
// (lastComposerRemainder).
func remainder(line, prefix string) string {
	glyph := strings.TrimSpace(prefix)
	trimmed := strings.TrimSpace(strings.ReplaceAll(line, "\u00a0", " "))
	for _, cand := range []string{trimmed, stripBoxBorder(trimmed)} {
		if rest, ok := strings.CutPrefix(cand, prefix); ok {
			return rest
		}
		if cand == glyph {
			return ""
		}
	}
	return ""
}

// stripBoxBorder removes a leading vertical box-drawing character, and the
// space around it (stripLeadingBoxBorder).
func stripBoxBorder(s string) string {
	s = strings.TrimLeft(s, " \t")
	r := []rune(s)
	if len(r) > 0 && (r[0] == '│' || r[0] == '┃') {
		return strings.TrimLeft(string(r[1:]), " \t")
	}
	return s
}

// StripDim removes the escape sequences from a row captured with
// capture-pane -e, and with them every character drawn dim (faint). On an
// empty box the cursor sits on the placeholder's first character, which is
// drawn reverse video rather than dim, so a single reverse-video cell followed
// directly by dim text goes with the placeholder. A longer reverse-video run,
// or one followed by anything else, is the cursor on typed text, or
// highlighted text, and stays (stripDimText).
func StripDim(line string) string {
	var b strings.Builder
	var attrs sgrAttrs
	// cursor holds a reverse-video run until the next visible character shows
	// whether a dim placeholder follows it.
	var cursor strings.Builder
	settle := func(beforeDim bool) {
		if !beforeDim || utf8.RuneCountInString(cursor.String()) != 1 {
			b.WriteString(cursor.String())
		}
		cursor.Reset()
	}
	for i := 0; i < len(line); {
		if line[i] != 0x1b {
			switch {
			case attrs.dim:
				settle(true)
			case attrs.reverse:
				cursor.WriteByte(line[i])
			default:
				settle(false)
				b.WriteByte(line[i])
			}
			i++
			continue
		}
		if i+1 >= len(line) {
			break
		}
		switch line[i+1] {
		case '[': // CSI: parameters, then a final byte in 0x40-0x7e.
			j := i + 2
			for j < len(line) && (line[j] < 0x40 || line[j] > 0x7e) {
				j++
			}
			if j < len(line) && line[j] == 'm' {
				attrs = attrs.apply(line[i+2 : j])
			}
			i = j + 1
		case ']': // OSC, such as a hyperlink: ends with BEL or ESC \.
			j := i + 2
			for j < len(line) && line[j] != 0x07 && !strings.HasPrefix(line[j:], "\x1b\\") {
				j++
			}
			if j < len(line) && line[j] == 0x1b {
				j++
			}
			i = j + 1
		default:
			i += 2
		}
	}
	settle(false)
	return b.String()
}

// sgrAttrs are the SGR attributes StripDim tracks.
type sgrAttrs struct {
	dim     bool // SGR 2, cleared by 22
	reverse bool // SGR 7, cleared by 27
}

// apply returns a after the SGR parameters params; an empty list resets.
func (a sgrAttrs) apply(params string) sgrAttrs {
	if params == "" {
		return sgrAttrs{}
	}
	parts := strings.Split(params, ";")
	for k := 0; k < len(parts); k++ {
		switch parts[k] {
		case "", "0":
			a = sgrAttrs{}
		case "2":
			a.dim = true
		case "22":
			a.dim = false
		case "7":
			a.reverse = true
		case "27":
			a.reverse = false
		case "38", "48", "58": // extended color: 5;n or 2;r;g;b
			if k+1 < len(parts) {
				switch parts[k+1] {
				case "5":
					k += 2
				case "2":
					k += 4
				}
			}
		}
	}
	return a
}
