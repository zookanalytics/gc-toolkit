package memory

import (
	"errors"
	"os"
	"path/filepath"
	"slices"
	"testing"
)

// A note's body hash reads the text after its front matter, without leading
// blank lines or use lines, so neither a save nor a use changes it; any other
// change to the body does.
func TestBodyHashReadsWhatTheWriterWrote(t *testing.T) {
	base := bodyHash("---\nname: n\n---\nThe lesson.\nIts detail.\n")
	for name, text := range map[string]string{
		"a front matter rewritten":    "---\nname: n\nmetadata:\n  modified: 2026-11-16T09:00:00.000Z\n---\n\nThe lesson.\nIts detail.\n",
		"use lines anywhere":          "---\nname: n\n---\nThe lesson.\nused 2026-11-16: it steered me\nIts detail.\n- used 2026-11-17: again\n",
		"a fence with trailing space": "--- \nother: x\n---\r\nThe lesson.\nIts detail.\n",
		"no final newline":            "---\nname: n\n---\nThe lesson.\nIts detail.",
	} {
		if got := bodyHash(text); got != base {
			t.Errorf("%s: hash changed", name)
		}
	}
	for name, text := range map[string]string{
		"a body line changed":  "---\nname: n\n---\nThe lesson, changed.\nIts detail.\n",
		"the request added":    "---\nname: n\n---\nThe lesson.\nIts detail.\n" + useLine + "\n",
		"no closing fence":     "---\nname: n\nThe lesson.\nIts detail.\n",
		"a line that mentions": "---\nname: n\n---\nThe lesson.\nIts detail.\nused once, then not again\n",
	} {
		if got := bodyHash(text); got == base {
			t.Errorf("%s: hash unchanged", name)
		}
	}
	if bodyHash("A note.\nused 2026-11-16: x\n") != bodyHash("A note.\n") {
		t.Error("a note with no front matter hashes its use lines")
	}
}

// An entry is a top-level item with the indented lines under it, a blank line
// belonging only when an indented line follows; a one-line item that begins
// with a link is a pointer.
func TestEntryTexts(t *testing.T) {
	text := "Intro.\n\n- [[a]] (A): pointer\n- [B](b.md) — pointer\n- (no file) one line\n- [C](c.md) — with\n  a line under it\n\n- second\n\n  under a blank line\n\n- third\nNot indented.\n"
	want := []string{"- (no file) one line\n", "- [C](c.md) — with\n  a line under it\n",
		"- second\n\n  under a blank line\n", "- third\n"}
	if got := entryTexts(text); !slices.Equal(got, want) {
		t.Errorf("entries %q\nwant %q", got, want)
	}
}

// A pointer to a removed note goes with the text after it, a line left with
// none goes, and a link elsewhere or an item with lines under it stays.
func TestPruneLinks(t *testing.T) {
	text := "# Index\n- [A](a.md) — a · [Gone](gone.md) — g · [B](<b.md#h>) — b\n- [[gone|Gone]] (G): g\n" +
		"- [[gone#part]] alone\n- [Out](../gone.md) — elsewhere\n- [Web](https://x/gone.md) — url\n" +
		"- [Gone](gone.md) — g\n  with a line under it\n- text first · [Gone](gone.md) — g\n"
	want := "# Index\n- [A](a.md) — a · [B](<b.md#h>) — b\n- [Out](../gone.md) — elsewhere\n" +
		"- [Web](https://x/gone.md) — url\n- [Gone](gone.md) — g\n  with a line under it\n- text first · [Gone](gone.md) — g\n"
	if got := pruneLinks(text, map[string]bool{"gone.md": true}); got != want {
		t.Errorf("pruned\n%s\nwant\n%s", got, want)
	}
}

// A rewrite lands only while the file holds the text it read: a writer that
// moves it once is waited out, and one that keeps moving it fails the rewrite,
// which leaves that writer's text.
func TestRewriteIsGuardedOnTheTextItRead(t *testing.T) {
	f := filepath.Join(t.TempDir(), "n.md")
	write(t, f, "one\n")
	moves := 1
	edit := func(text string) (string, error) {
		if moves > 0 {
			moves--
			write(t, f, text+"agent\n")
		}
		return text + "intake\n", nil
	}
	if got, wrote, err := rewrite(f, edit); err != nil || !wrote || got != "one\nagent\nintake\n" || read(t, f) != got {
		t.Errorf("rewrite = %q, %v, %v; the file reads %q", got, wrote, err, read(t, f))
	}
	moves = 3
	if _, wrote, err := rewrite(f, edit); !errors.Is(err, errMoved) || wrote {
		t.Errorf("rewrite under a writer that kept moving the file = %v, %v", wrote, err)
	}
	if got := read(t, f); got != "one\nagent\nintake\nagent\nagent\nagent\n" {
		t.Errorf("the file reads %q; want the agent's text alone", got)
	}
	if entries, _ := os.ReadDir(filepath.Dir(f)); len(entries) != 1 {
		t.Errorf("the rewrite left %d files beside the note", len(entries)-1)
	}
}

// A note that changed since the scan stays and keeps no text.
func TestRemoveNoteRefusesTextItWasNotGiven(t *testing.T) {
	dir, state := t.TempDir(), t.TempDir()
	write(t, filepath.Join(dir, "d.md"), "d lesson, edited.\n")
	if r, _, err := removeNote(state, dir, "d.md", sum("d lesson.\n")); r != stays || err != nil {
		t.Errorf("removeNote = %v, %v; want it to stay", r, err)
	}
	if kept, _ := filepath.Glob(filepath.Join(state, "removed", "*")); len(kept) != 0 || !exists(filepath.Join(dir, "d.md")) {
		t.Errorf("kept %v; want nothing kept and the note in place", kept)
	}
}
