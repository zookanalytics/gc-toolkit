package form

import (
	"slices"
	"strings"

	"charm.land/bubbles/v2/textarea"
	tea "charm.land/bubbletea/v2"
	"github.com/atotto/clipboard"
)

// questionEditor is the question field: bubbles' textarea, with what it is
// given mapped at the field's edge so that the question reads back as the
// operator gave it.
//
// The textarea passes everything it inserts, whether set, pasted or typed,
// through a sanitizer that turns a tab into four spaces and a CR into a line
// break, and leaves out the other control characters and U+FFFD. It takes no
// other sanitizer: the field is unexported, and san() builds the default
// (charm.land/bubbles/v2 v2.0.0, textarea.go insertRunesFromUserInput and san).
// So hold maps the text before the textarea sees it. A CRLF becomes one line
// break, where the sanitizer would make it two, and each tab is held as
// heldTab, which the sanitizer keeps. Value maps heldTab back to a tab, and
// View shows tabMark where a tab is. The other control characters, such as BEL
// and ESC, are still left out.
type questionEditor struct {
	ta textarea.Model
	// pasteKeys are the keys of the textarea's own paste, Ctrl+V. Its clipboard
	// read (textarea.Paste) hands the text straight to the sanitizer, so the
	// textarea's binding is disabled, and these keys read the clipboard as a
	// paste.
	pasteKeys []string
}

// heldTab is how the textarea holds a tab of the question. U+FDD0 is a Unicode
// noncharacter, reserved for a program's own use, so no question carries it,
// and the sanitizer keeps it. It is one cell wide, as tabMark is. hold leaves
// out a U+FDD0 it is given, and a key press that would type one types nothing,
// so every heldTab the textarea holds stands for a tab.
const heldTab = '\uFDD0'

// tabMark is what the screen shows where the question has a tab: U+2409, the
// symbol for a horizontal tab.
const tabMark = "␉"

func newQuestionEditor() questionEditor {
	ta := textarea.New()
	ta.ShowLineNumbers = false
	ta.MaxHeight = 0 // a question is as long as the operator makes it
	ta.CharLimit = 0
	ta.Placeholder = "What do you want to talk about? Enter adds a line."
	ta.SetWidth(76)
	ta.SetHeight(8)
	pasteKeys := ta.KeyMap.Paste.Keys()
	ta.KeyMap.Paste.SetEnabled(false)
	return questionEditor{ta: ta, pasteKeys: pasteKeys}
}

// hold is s as the textarea holds it.
func hold(s string) string {
	s = strings.ReplaceAll(s, "\r\n", "\n")
	s = strings.ReplaceAll(s, string(heldTab), "")
	return strings.ReplaceAll(s, "\t", string(heldTab))
}

// SetValue fills the field with s.
func (e *questionEditor) SetValue(s string) { e.ta.SetValue(hold(s)) }

// Value is the question as the operator gave it.
func (e *questionEditor) Value() string {
	return strings.ReplaceAll(e.ta.Value(), string(heldTab), "\t")
}

// View is the field as the screen shows it.
func (e *questionEditor) View() string {
	return strings.ReplaceAll(e.ta.View(), string(heldTab), tabMark)
}

func (e *questionEditor) Focus() tea.Cmd { return e.ta.Focus() }
func (e *questionEditor) Blur()          { e.ta.Blur() }
func (e *questionEditor) SetWidth(w int) { e.ta.SetWidth(w) }

// Update hands msg to the textarea. A paste is held first. A typed key never
// carries a tab or a CR, since Tab moves the focus and Enter adds a line, so
// typing goes to the textarea as it comes.
func (e *questionEditor) Update(msg tea.Msg) tea.Cmd {
	switch msg := msg.(type) {
	case tea.PasteMsg:
		msg.Content = hold(msg.Content)
		return e.update(msg)
	case tea.KeyPressMsg:
		if slices.Contains(e.pasteKeys, msg.String()) {
			return readClipboard
		}
		if strings.ContainsRune(msg.Text, heldTab) {
			return nil
		}
	}
	return e.update(msg)
}

func (e *questionEditor) update(msg tea.Msg) tea.Cmd {
	var cmd tea.Cmd
	e.ta, cmd = e.ta.Update(msg)
	return cmd
}

// clipboardText reads the clipboard, as textarea.Paste does. A test stands in
// for it.
var clipboardText = clipboard.ReadAll

// readClipboard hands the clipboard back as a paste, so it is held as a paste
// from the terminal is. A clipboard that does not read pastes nothing, as the
// textarea's own paste then does.
func readClipboard() tea.Msg {
	s, err := clipboardText()
	if err != nil {
		return nil
	}
	return tea.PasteMsg{Content: s}
}
