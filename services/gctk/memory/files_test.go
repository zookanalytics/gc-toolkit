package memory

import (
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
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
	if left := beside(t, f); len(left) != 0 {
		t.Errorf("the rewrite left %q beside the note", left)
	}
}

// A rewrite keeps a save an agent makes at any step of it. A save before the
// swap is displaced, fails the check and is swapped back, and the rewrite
// edits it on its next try. A save after the swap lands over the edit, as a
// later save would.
func TestRewriteKeepsASaveMadeAtEachStep(t *testing.T) {
	edit := func(text string) (string, error) { return text + "intake\n", nil }
	for name, c := range map[string]struct {
		land func(t *testing.T)
		want string
	}{
		"in place before the swap": {func(t *testing.T) {
			landAt(t, "swap", func(f string) { appendTo(t, f, "agent\n") })
		}, "one\nagent\nintake\n"},
		"by rename before the swap": {func(t *testing.T) {
			landAt(t, "swap", func(f string) { saveByRename(t, f, "one\nagent\n") })
		}, "one\nagent\nintake\n"},
		"through a handle opened before the swap": {func(t *testing.T) {
			var h *os.File
			landAt(t, "swap", func(f string) { h = openAppend(t, f) })
			landAt(t, "check", func(string) {
				if _, err := h.WriteString("agent\n"); err != nil {
					t.Fatal(err)
				}
			})
		}, "one\nagent\nintake\n"},
		"in place after the swap": {func(t *testing.T) {
			landAt(t, "check", func(f string) { write(t, f, "one\nagent\n") })
		}, "one\nagent\n"},
		"by rename after the swap": {func(t *testing.T) {
			landAt(t, "check", func(f string) { saveByRename(t, f, "one\nagent\n") })
		}, "one\nagent\n"},
	} {
		t.Run(name, func(t *testing.T) {
			f := filepath.Join(t.TempDir(), "n.md")
			write(t, f, "one\n")
			c.land(t)
			if _, wrote, err := rewrite(f, edit); err != nil || !wrote || read(t, f) != c.want {
				t.Errorf("rewrite = %v, %v; the file reads %q, want %q", wrote, err, read(t, f), c.want)
			}
			if left := beside(t, f); len(left) != 0 {
				t.Errorf("the rewrite left %q beside the note", left)
			}
		})
	}
}

// When one save fails the check and another lands over the edit before the
// swap back, both stay, and the rewrite fails naming where the second one is.
func TestRewriteKeepsBothSavesOfTwoWriters(t *testing.T) {
	f := filepath.Join(t.TempDir(), "n.md")
	write(t, f, "one\n")
	landAt(t, "swap", func(f string) { appendTo(t, f, "first\n") })
	landAt(t, "back", func(f string) { write(t, f, "second\n") })
	_, wrote, err := rewrite(f, func(text string) (string, error) { return text + "intake\n", nil })
	if wrote || err == nil || errors.Is(err, errMoved) {
		t.Fatalf("rewrite = %v, %v; want it to fail on the two saves", wrote, err)
	}
	left := displaced(t, f)
	if read(t, f) != "one\nfirst\n" || len(left) != 1 {
		t.Fatalf("the file reads %q, with %q aside; want the first save, and one file aside", read(t, f), left)
	}
	for name, text := range left {
		if text != "second\n" || !strings.Contains(err.Error(), name) {
			t.Errorf("failed %v, with %q at %s; want the second save where the error says", err, text, name)
		}
	}
}

// A rewrite killed at any step leaves a whole file under the name, and every
// text it displaced in the aside folder.
func TestARewriteKilledAtAnyStepLeavesAWholeFile(t *testing.T) {
	edit := func(text string) (string, error) { return text + "intake\n", nil }
	for _, c := range []struct {
		step, race, name, left string
	}{
		{"swap", "", "one\n", "one\nintake\n"},
		{"check", "", "one\nintake\n", "one\n"},
		{"back", "agent\n", "one\nintake\n", "one\nagent\n"},
	} {
		t.Run(c.step, func(t *testing.T) {
			f := filepath.Join(t.TempDir(), "n.md")
			write(t, f, "one\n")
			if c.race != "" {
				landAt(t, "swap", func(f string) { appendTo(t, f, c.race) })
			}
			killedAt(t, c.step, func() { rewrite(f, edit) })
			left := displaced(t, f)
			if read(t, f) != c.name || len(left) != 1 {
				t.Fatalf("the file reads %q, with %q aside; want %q, and one file aside", read(t, f), left, c.name)
			}
			for _, text := range left {
				if text != c.left {
					t.Errorf("aside %q; want %q", text, c.left)
				}
			}
		})
	}
}

// A removal keeps a save an agent makes at any step of it. A save before the
// move fails the check, so the note goes back with it and stays, and a save
// under the name after the move is a new file the removal leaves.
func TestRemoveNoteKeepsASaveMadeAtEachStep(t *testing.T) {
	for name, c := range map[string]struct {
		land func(t *testing.T)
		want removal
	}{
		"in place before the move": {func(t *testing.T) {
			landAt(t, "move", func(f string) { appendTo(t, f, "agent\n") })
		}, stays},
		"by rename before the move": {func(t *testing.T) {
			landAt(t, "move", func(f string) { saveByRename(t, f, "d lesson.\nagent\n") })
		}, stays},
		"through a handle opened before the move": {func(t *testing.T) {
			var h *os.File
			landAt(t, "move", func(f string) { h = openAppend(t, f) })
			landAt(t, "check", func(string) {
				if _, err := h.WriteString("agent\n"); err != nil {
					t.Fatal(err)
				}
			})
		}, stays},
		"as a new file before the check": {func(t *testing.T) {
			landAt(t, "check", func(f string) { write(t, f, "d lesson.\nagent\n") })
		}, removed},
	} {
		t.Run(name, func(t *testing.T) {
			dir, state := t.TempDir(), t.TempDir()
			f := filepath.Join(dir, "d.md")
			write(t, f, "d lesson.\n")
			c.land(t)
			r, kept, err := removeNote(state, dir, "d.md", sum("d lesson.\n"))
			if r != c.want || err != nil {
				t.Fatalf("removeNote = %v, %v; want %v", r, err, c.want)
			}
			if read(t, f) != "d lesson.\nagent\n" {
				t.Errorf("the note reads %q; want the agent's save", read(t, f))
			}
			if left := beside(t, f); len(left) != 0 {
				t.Errorf("the removal left %q beside the note", left)
			}
			all, _ := filepath.Glob(filepath.Join(state, "removed", "*"))
			if r == removed && (len(all) != 1 || read(t, kept) != "d lesson.\n") {
				t.Errorf("kept %v; want the text listed", all)
			}
			if r == stays && len(all) != 0 {
				t.Errorf("kept %v for a note that stayed", all)
			}
			if aside := displaced(t, f); r == removed && (len(aside) != 1 || !holds(aside, "d lesson.\n")) || r == stays && len(aside) != 0 {
				t.Errorf("aside %q; want the note removed, and nothing for a note that stayed", aside)
			}
		})
	}
}

// When one save fails a removal's check and another makes a new file under
// the name while the note is moved aside, both stay, and the removal fails
// naming where the first one is.
func TestRemoveNoteKeepsBothSavesOfTwoWriters(t *testing.T) {
	dir, state := t.TempDir(), t.TempDir()
	f := filepath.Join(dir, "d.md")
	write(t, f, "d lesson.\n")
	landAt(t, "move", func(f string) { appendTo(t, f, "first\n") })
	landAt(t, "check", func(f string) { write(t, f, "second\n") })
	r, _, err := removeNote(state, dir, "d.md", sum("d lesson.\n"))
	if r != failed || err == nil {
		t.Fatalf("removeNote = %v, %v; want it to fail on the two saves", r, err)
	}
	left := displaced(t, f)
	if read(t, f) != "second\n" || len(left) != 1 {
		t.Fatalf("the note reads %q, with %q aside; want the second save, and one file aside", read(t, f), left)
	}
	for name, text := range left {
		if text != "d lesson.\nfirst\n" || !strings.Contains(err.Error(), name) {
			t.Errorf("failed %v, with %q at %s; want the first save where the error says", err, text, name)
		}
	}
}

// A removal killed at any step leaves the note's text under its name or kept.
func TestARemovalKilledAtAnyStepKeepsTheText(t *testing.T) {
	for _, step := range []string{"move", "check"} {
		t.Run(step, func(t *testing.T) {
			dir, state := t.TempDir(), t.TempDir()
			f := filepath.Join(dir, "d.md")
			write(t, f, "d lesson.\n")
			killedAt(t, step, func() { removeNote(state, dir, "d.md", sum("d lesson.\n")) })
			kept := filepath.Join(state, "removed", "d.md@"+sum("d lesson.\n"))
			if exists(f) && read(t, f) != "d lesson.\n" || !exists(f) && read(t, kept) != "d lesson.\n" {
				t.Errorf("the note's text is neither under its name nor kept")
			}
		})
	}
}

// A save through a handle a writer opened before a write, landing once the
// write is done, stays in the file the write took from under the name: the
// note a removal moved aside, the text a rewrite displaced, and the edit a
// rewrite swapped back.
func TestASaveThroughAHandleOpenedBeforeAWriteStays(t *testing.T) {
	late := func(t *testing.T, h *os.File) {
		t.Helper()
		if _, err := h.WriteString("agent\n"); err != nil {
			t.Fatal(err)
		}
	}
	edit := func(text string) (string, error) { return text + "intake\n", nil }
	t.Run("removal", func(t *testing.T) {
		dir, state := t.TempDir(), t.TempDir()
		f := filepath.Join(dir, "d.md")
		write(t, f, "d lesson.\n")
		h := openAppend(t, f)
		if r, kept, err := removeNote(state, dir, "d.md", sum("d lesson.\n")); r != removed || err != nil || read(t, kept) != "d lesson.\n" {
			t.Fatalf("removeNote = %v, %v; want it removed with the text listed kept", r, err)
		}
		late(t, h)
		if aside := displaced(t, f); exists(f) || !holds(aside, "d lesson.\nagent\n") {
			t.Errorf("aside %q; want the note with the save", aside)
		}
	})
	t.Run("rewrite", func(t *testing.T) {
		f := filepath.Join(t.TempDir(), "n.md")
		write(t, f, "one\n")
		h := openAppend(t, f)
		if _, wrote, err := rewrite(f, edit); err != nil || !wrote {
			t.Fatalf("rewrite = %v, %v", wrote, err)
		}
		late(t, h)
		if aside := displaced(t, f); read(t, f) != "one\nintake\n" || !holds(aside, "one\nagent\n") {
			t.Errorf("the file reads %q, with %q aside; want the edit, and the text it displaced with the save", read(t, f), aside)
		}
	})
	t.Run("rewrite swapped back", func(t *testing.T) {
		f := filepath.Join(t.TempDir(), "n.md")
		write(t, f, "one\n")
		landAt(t, "swap", func(f string) { appendTo(t, f, "first\n") })
		var h *os.File
		landAt(t, "back", func(f string) { h = openAppend(t, f) })
		if _, wrote, err := rewrite(f, edit); err != nil || !wrote {
			t.Fatalf("rewrite = %v, %v", wrote, err)
		}
		late(t, h)
		if aside := displaced(t, f); read(t, f) != "one\nfirst\nintake\n" || !holds(aside, "one\nintake\nagent\n") {
			t.Errorf("the file reads %q, with %q aside; want the second try's edit, and the first's with the save", read(t, f), aside)
		}
	})
}

// A link names the note its destination names in the directory. A destination
// in angle brackets keeps its spaces, a title after a destination is not part
// of it, a percent escape is decoded unless the destination does not decode,
// and a link elsewhere names none.
func TestTarget(t *testing.T) {
	for seg, want := range map[string]string{
		"[Lesson](<my lesson.md>)":            "my lesson.md",
		`[Lesson](<my lesson.md> "A title")`:  "my lesson.md",
		"[Lesson](<my lesson.md#part>) — l":   "my lesson.md",
		`[A](a.md "A title")`:                 "a.md",
		"[[my lesson|Lesson]]":                "my lesson.md",
		"[[a](a.md) — a bracket, then a link": "a.md",
		"[Lesson](my%20lesson.md)":            "my lesson.md",
		"[Lesson](<my%20lesson.md>)":          "my lesson.md",
		"[Whole](100%.md)":                    "100%.md",
		"[Out](a%2Fb.md)":                     "",
		"[Out](../a.md)":                      "",
		"[Web](https://x/a.md)":               "",
		"[Text](notes.txt)":                   "",
	} {
		if got := target(seg); got != want {
			t.Errorf("target(%q) = %q; want %q", seg, got, want)
		}
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
