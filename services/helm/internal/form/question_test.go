package form

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"
)

// scriptSave is fakeHelm with its save recorded and then run by a Script, so a
// test reads both the save request and the argv open was given.
type scriptSave struct {
	*fakeHelm
	s Script
}

func (h scriptSave) Save(ctx context.Context, req SaveRequest) (Saved, error) {
	h.saves = append(h.saves, req)
	return h.s.Save(ctx, req)
}

// keptCommandFiles runs the command a cancelled form's note prints, with a
// gc-helm.sh stand-in first on PATH, and returns the question it filed.
func keptCommandFiles(t *testing.T, note string) string {
	t.Helper()
	dir := t.TempDir()
	got := filepath.Join(dir, "reason")
	stub := "#!/bin/sh\nfor a; do last=$a; done\nprintf '%s' \"$last\" > '" + got + "'\n"
	if err := os.WriteFile(filepath.Join(dir, "gc-helm.sh"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	_, command, ok := strings.Cut(note, "start it again with: ")
	if !ok {
		t.Fatalf("note = %q", note)
	}
	c := exec.Command("sh", "-c", command)
	c.Env = append(os.Environ(), "PATH="+dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	if err := c.Run(); err != nil {
		t.Fatalf("%s: %v", command, err)
	}
	b, err := os.ReadFile(got)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

// reasonArg is the --reason argument of a recorded argv.
func reasonArg(t *testing.T, args []string) string {
	t.Helper()
	for i, a := range args {
		if a == "--reason" && i+1 < len(args) {
			return args[i+1]
		}
	}
	t.Fatalf("no --reason in %q", args)
	return ""
}

// A pasted tab is saved as a tab, through edits around it, and the screen
// marks where it is. The paste runs from the Model to the argv open gets.
func TestAPastedTabIsSavedAsATab(t *testing.T) {
	s, dir := stubHelm(t, `{"subject":"tk-a","conversation":"tk-c1","filed":true}`+"\n", "", 0)
	f := &fakeHelm{about: map[string]About{"tk-a": subjectAbout("tk-a", "gc-toolkit")}}
	m := newFormOn(t, scriptSave{f, s}, Options{Subject: "tk-a"})
	settle(m)
	m.Update(tea.PasteMsg{Content: "target:\n\techo hi\n"})
	typeText(m, "# donx")
	m.Update(key(tea.KeyBackspace))
	typeText(m, "e")
	want := "target:\n\techo hi\n# done"
	if got := m.question.Value(); got != want {
		t.Fatalf("question = %q, want %q", got, want)
	}
	v := m.composeView()
	if !strings.Contains(v, tabMark+"echo hi") || strings.Contains(v, "    echo hi") {
		t.Fatalf("the screen does not mark the tab:\n%s", v)
	}
	_, cmd := m.Update(ctrl('s'))
	deliver(m, cmd)
	if len(f.saves) != 1 || f.saves[0].Question != want {
		t.Fatalf("saves = %+v, want one with the question %q", f.saves, want)
	}
	if got := reasonArg(t, argv(t, dir)); got != want {
		t.Fatalf("open was given --reason %q, want %q", got, want)
	}
}

// A question given on the command line keeps its tabs, and a CRLF in it is one
// line break: in the save, and, when the form is cancelled, in its draft and in
// what the command the note prints files.
func TestAQuestionGivenWithATabKeepsIt(t *testing.T) {
	f := &fakeHelm{
		about:    map[string]About{"tk-a": subjectAbout("tk-a", "gc-toolkit")},
		saveResp: Saved{Subject: "tk-a", Conversation: "tk-c1", Filed: true},
	}
	m := newForm(t, f, Options{Subject: "tk-a", Question: "set\tvalue\r\nnext"})
	settle(m)
	_, cmd := m.Update(ctrl('s'))
	deliver(m, cmd)
	if len(f.saves) != 1 || f.saves[0].Question != "set\tvalue\nnext" {
		t.Fatalf("saves = %+v, want the question with its tab and one line break", f.saves)
	}
	dir := t.TempDir()
	m = newForm(t, &fakeHelm{}, Options{Subject: "tk-a", Question: "set\tvalue\r\n", DraftDir: dir})
	m.Update(key(tea.KeyEscape))
	files, _ := filepath.Glob(filepath.Join(dir, "engage-draft-*.txt"))
	if len(files) != 1 {
		t.Fatalf("draft files %v", files)
	}
	if b, _ := os.ReadFile(files[0]); string(b) != "set\tvalue\n" {
		t.Fatalf("kept draft = %q", b)
	}
	if got := keptCommandFiles(t, m.Note()); got != "set\tvalue\n" {
		t.Fatalf("the command filed %q", got)
	}
}

// A pasted CRLF is one line break, and a CR alone, as a terminal sends a line,
// is one too. Typed text is unchanged.
func TestAPastedCRLFIsOneLineBreak(t *testing.T) {
	m := newForm(t, &fakeHelm{}, Options{Subject: "tk-a"})
	m.Update(tea.PasteMsg{Content: "a\r\nb\rc"})
	typeText(m, "\nd")
	if got := m.question.Value(); got != "a\nb\nc\nd" {
		t.Fatalf("question = %q", got)
	}
}

// The editor holds a tab as U+FDD0, so a U+FDD0 it is given is left out, typed
// or pasted, and never comes back as a tab.
func TestTheRuneATabIsHeldAsIsLeftOut(t *testing.T) {
	m := newForm(t, &fakeHelm{}, Options{Subject: "tk-a", Question: "x\uFDD0y"})
	m.Update(tea.PasteMsg{Content: "\uFDD0\tz"})
	m.Update(tea.KeyPressMsg{Code: '\uFDD0', Text: "\uFDD0"})
	if got := m.question.Value(); got != "xy\tz" {
		t.Fatalf("question = %q, want %q", got, "xy\tz")
	}
}

// Ctrl+V pastes the clipboard through the same edge as a terminal's paste, so
// its tabs are kept too. The textarea's own paste, which would bypass it, never
// runs.
func TestCtrlVPastesTheClipboardWithItsTabs(t *testing.T) {
	was := clipboardText
	t.Cleanup(func() { clipboardText = was })
	clipboardText = func() (string, error) { return "a\tb", nil }
	m := newForm(t, &fakeHelm{}, Options{Subject: "tk-a"})
	if m.question.ta.KeyMap.Paste.Enabled() {
		t.Fatalf("the textarea's own paste is enabled")
	}
	_, cmd := m.Update(ctrl('v'))
	if cmd == nil {
		t.Fatalf("Ctrl+V read nothing")
	}
	m.Update(cmd())
	if got := m.question.Value(); got != "a\tb" {
		t.Fatalf("question after Ctrl+V = %q", got)
	}
	clipboardText = func() (string, error) { return "", errors.New("no clipboard") }
	_, cmd = m.Update(ctrl('v'))
	if msg := cmd(); msg != nil {
		t.Fatalf("a clipboard that did not read pasted %v", msg)
	}
}
