package memory

import (
	"errors"
	"fmt"
	"io/fs"
	"maps"
	"net/url"
	"os"
	"path/filepath"
	"strings"
)

// Agents write memory without the intake's lock, so the intake never replaces
// or removes a file in a memory directory by its name, which would take a save
// a writer made there after the intake's last read. It first displaces the
// file, keeping it whole under another name, and then checks the displaced
// file against the text it read.
//
// A new text goes in by an exchange: the new file and the file under the name
// swap in one step, so the name holds a whole file at every moment. A
// displaced file that fails the check is a writer's save, and it is swapped
// back. A removal, once the note's text is kept, moves the file aside. A moved
// file that fails the check goes back by a rename that fails when a writer has
// made a new file under the name since.
//
// A writer that opened a file before the exchange or the move can write to it
// at any moment after, so the intake removes no file that a note's name has
// held. Each file it displaces stays in the directory's .memory-intake folder,
// which nothing empties. A write through such a handle that lands before the
// check is a save the check sees. One that lands after the check, or before a
// check that a kill stopped, stays in the displaced file in that folder, and
// the note under the name does not carry it.
//
// A removal leaves a note's name free only until a writer saves under it, so
// a pointer to a removed note comes out only while its name holds no file. A
// rewrite's check runs its edit again on the text it read, since an edit can
// read more than its file, as the one that takes pointers out reads each name.
// A save under the name before the check swaps the rewrite back, and its next
// try keeps the pointer.

// errMoved is a rewrite whose file another writer kept changing.
var errMoved = errors.New("it kept changing while it was written")

// errChanged is an edit that refused text other than the text it was given.
var errChanged = errors.New("it changed since it was listed")

// beforeStep runs before each step of a write to file, named by the step, so a
// test can land an agent's save or a kill there. A rewrite takes "swap", the
// exchange, then "check", the read of the displaced file and the edit run
// again, then "back", the exchange that returns a displaced file that failed
// the check. A removal takes "move", the move aside, then "check".
var beforeStep = func(step, file string) {}

// asideDir is the folder in a memory directory that holds each file the intake
// displaced.
const asideDir = ".memory-intake"

// asideFile makes a new empty file in the aside folder of file's directory, its
// name begun with file's. A directory that is gone gets no folder.
func asideFile(file string) (*os.File, error) {
	dir := filepath.Join(filepath.Dir(file), asideDir)
	if err := os.Mkdir(dir, 0o755); err != nil && !errors.Is(err, fs.ErrExist) {
		return nil, err
	}
	return os.CreateTemp(dir, filepath.Base(file)+".*")
}

// put swaps the file at tmp, which holds after, in under file's name while
// file holds text and edit still makes after of it, and reports whether it
// did. The file that leaves the name stays at tmp.
func put(file, tmp, text, after string, edit func(string) (string, error)) (bool, error) {
	beforeStep("swap", file)
	if err := exchange(tmp, file); err != nil {
		os.Remove(tmp)
		return false, err
	}
	beforeStep("check", file)
	if now, err := os.ReadFile(tmp); err == nil && string(now) == text {
		if again, err := edit(text); err == nil && again == after {
			return true, nil
		}
	}
	beforeStep("back", file)
	if err := exchange(tmp, file); err != nil {
		return false, fmt.Errorf("%s holds the intake's edit, and the save it displaced is at %s: %w", file, tmp, err)
	}
	if now, err := os.ReadFile(tmp); err == nil && string(now) == after {
		return false, nil
	}
	return false, fmt.Errorf("%s was saved twice while it was written: it holds the first save, and what was under its name after that is at %s", file, tmp)
}

// aside moves file into the aside folder, and returns its name there.
func aside(file string) (string, error) {
	f, err := asideFile(file)
	if err != nil {
		return "", err
	}
	f.Close()
	if err := os.Rename(file, f.Name()); err != nil {
		os.Remove(f.Name())
		return "", err
	}
	return f.Name(), nil
}

// back renames the file moved aside to moved back to file's name. When a
// writer has made a new file under the name since the move, both stay, and the
// error says where the moved one is.
func back(moved, file string) error {
	err := renameNew(moved, file)
	switch {
	case err == nil:
		return nil
	case errors.Is(err, fs.ErrExist):
		return fmt.Errorf("%s was saved twice while it was removed: the newer save is under its name, and the older one is at %s", file, moved)
	}
	return fmt.Errorf("%s is at %s and could not be put back under its name: %w", file, moved, err)
}

// take removes file from under its name, into the aside folder, while it holds
// the text whose hash is full.
func take(file, full string) (removal, error) {
	beforeStep("move", file)
	moved, err := aside(file)
	switch {
	case errors.Is(err, os.ErrNotExist):
		return stays, nil
	case err != nil:
		return failed, err
	}
	beforeStep("check", file)
	now, err := os.ReadFile(moved)
	if err == nil && sum(string(now)) == full {
		return removed, nil
	}
	if berr := back(moved, file); berr != nil || err != nil {
		return failed, errors.Join(err, berr)
	}
	return stays, nil
}

// rewrite replaces file's text with edit(text) while the file still holds the
// text edit read and edit still makes the same text of it, and tries again, up
// to three times, when another writer moved what it read. It returns the text
// written, or the text as it stands when edit changed nothing, and whether it
// wrote.
func rewrite(file string, edit func(string) (string, error)) (string, bool, error) {
	for range 3 {
		before, err := os.ReadFile(file)
		if err != nil {
			return "", false, err
		}
		after, err := edit(string(before))
		if err != nil {
			return "", false, err
		}
		if after == string(before) {
			return after, false, nil
		}
		mode := os.FileMode(0o644)
		if fi, err := os.Stat(file); err == nil {
			mode = fi.Mode().Perm()
		}
		tmp, err := asideFile(file)
		if err != nil {
			return "", false, err
		}
		_, werr := tmp.WriteString(after)
		if err := errors.Join(werr, tmp.Close(), os.Chmod(tmp.Name(), mode)); err != nil {
			os.Remove(tmp.Name())
			return "", false, err
		}
		wrote, err := put(file, tmp.Name(), string(before), after, edit)
		if err != nil {
			return "", false, err
		}
		if wrote {
			return after, true, nil
		}
	}
	return "", false, errMoved
}

// keep files text, whose hash is hash, at <state>/removed/<name>@<hash>, and
// reports whether it made that file, so a unit that stays can take it back.
func keep(state, name, hash, text string) (string, bool, error) {
	if sum(text) != hash {
		return "", false, errChanged
	}
	dir := filepath.Join(state, removedDir)
	dest := filepath.Join(dir, name+"@"+hash)
	if raw, err := os.ReadFile(dest); err == nil && sum(string(raw)) == hash {
		return dest, false, nil
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", false, err
	}
	if err := replace(dest, text, 0o644); err != nil {
		return "", false, err
	}
	return dest, true, nil
}

// A removal's result: the unit is gone with its text kept, it stays because it
// changed or is gone, or it stays because a write failed.
type removal int

const (
	removed removal = iota
	stays
	failed
)

// removeNote removes a note, or a collection note left with no entries, while
// it holds the text whose hash is full, once that text is kept.
func removeNote(state, dir, name, full string) (removal, string, error) {
	file := filepath.Join(dir, name)
	raw, err := os.ReadFile(file)
	switch {
	case errors.Is(err, os.ErrNotExist):
		return stays, "", nil
	case err != nil:
		return failed, "", err
	case sum(string(raw)) != full:
		return stays, "", nil
	}
	kept, made, err := keep(state, name, full, string(raw))
	if err != nil {
		return failed, "", fmt.Errorf("its text was not kept: %w", err)
	}
	r, err := take(file, full)
	if r != removed {
		if made {
			os.Remove(kept)
		}
		return r, "", err
	}
	return removed, kept, nil
}

// removeEntry takes an entry out of its collection note once its text is kept,
// and the collection note with it when that leaves it no list item. hubGone
// reports that the collection note went.
func removeEntry(state, dir string, u Unit) (r removal, kept string, hubGone bool, err error) {
	kept, made, err := keep(state, u.Name, u.Hash, u.Text)
	if err != nil {
		return failed, "", false, fmt.Errorf("its text was not kept: %w", err)
	}
	written, wrote, err := rewrite(filepath.Join(dir, u.Name), func(text string) (string, error) {
		return dropEntry(text, u.Text)
	})
	if err != nil || !wrote {
		if made {
			os.Remove(kept)
		}
		if err == nil || errors.Is(err, errChanged) || errors.Is(err, errMoved) || errors.Is(err, os.ErrNotExist) {
			return stays, "", false, nil
		}
		return failed, "", false, err
	}
	if hasEntries(written) {
		return removed, kept, false, nil
	}
	hr, _, err := removeNote(state, dir, u.Name, sum(written))
	switch hr {
	case removed:
		return removed, kept, true, nil
	case failed:
		return removed, kept, false, fmt.Errorf("%s has no entries left and stays: %w", u.Name, err)
	}
	return removed, kept, false, nil
}

// dropEntry is text without the first entry whose lines are entry's.
func dropEntry(text, entry string) (string, error) {
	ls, want := lines(text), lines(entry)
	for i := 0; i < len(ls); i++ {
		if !strings.HasPrefix(ls[i], "- ") {
			continue
		}
		e := entryEnd(ls, i)
		if e-i+1 == len(want) && equal(ls[i:e+1], want) {
			out := append(append([]string{}, ls[:i]...), ls[e+1:]...)
			return joinedLike(text, out), nil
		}
		i = e
	}
	return "", errChanged
}

func equal(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// joinedLike joins ls into lines, ending in a newline when text did.
func joinedLike(text string, ls []string) string {
	out := strings.Join(ls, "\n")
	if len(ls) > 0 && strings.HasSuffix(text, "\n") {
		out += "\n"
	}
	return out
}

// pruneLinks is text without each pointer to a note in gone: a list item of one
// line that begins with a link, which can hold several pointers joined by
// " · ". A pointer goes with the text that follows it, and a line left with
// none goes. An item with lines under it stays whole.
func pruneLinks(text string, gone map[string]bool) string {
	ls := lines(text)
	var out []string
	for i := 0; i < len(ls); i++ {
		if !strings.HasPrefix(ls[i], "- ") {
			out = append(out, ls[i])
			continue
		}
		e := entryEnd(ls, i)
		if !pointer(ls, i, e) {
			out = append(out, ls[i:e+1]...)
			i = e
			continue
		}
		var kept []string
		keepSeg := true
		for _, seg := range strings.Split(ls[i][2:], " · ") {
			if linkStart(seg) {
				keepSeg = !gone[target(seg)]
			}
			if keepSeg {
				kept = append(kept, seg)
			}
		}
		if len(kept) > 0 {
			out = append(out, "- "+strings.Join(kept, " · "))
		}
	}
	return joinedLike(text, out)
}

// unlink takes out the pointers to each note in gone, and keeps the names
// under state while a pointer did not come out, so the next run reads them
// into its gone and tries again. gone ends holding those of its notes, and of
// the collection notes prune removed, whose names hold no file. It returns
// what it could not do.
func unlink(state, dir string, gone map[string]bool) []string {
	var failures []string
	if len(gone) > 0 {
		failures = prune(state, dir, gone)
	}
	left := absent(dir, gone)
	maps.DeleteFunc(gone, func(name string, _ bool) bool { return !left[name] })
	if len(failures) == 0 {
		clear(left)
	}
	if err := writeGone(state, left); err != nil {
		failures = append(failures, err.Error())
	}
	return failures
}

// absent is each note in gone whose name holds no file in dir.
func absent(dir string, gone map[string]bool) map[string]bool {
	out := map[string]bool{}
	for name := range gone {
		if _, err := os.Lstat(filepath.Join(dir, name)); errors.Is(err, fs.ErrNotExist) {
			out[name] = true
		}
	}
	return out
}

// prune takes the pointers to each note in gone whose name holds no file out
// of the index and every collection note, and removes, with its text kept, a
// collection note that this leaves with no list item, whose own pointers then
// go in turn, until a pass removes no collection note. gone gains the
// collection notes it removes.
func prune(state, dir string, gone map[string]bool) []string {
	var failures []string
	for more := true; more; {
		names, err := hubs(dir)
		if err != nil {
			return append(failures, fmt.Sprintf("cannot list %s, so the links to the notes removed were not taken out, and the next run tries again: %v", dir, err))
		}
		more = false
		for _, name := range names {
			file := filepath.Join(dir, name)
			had := false
			written, wrote, err := rewrite(file, func(text string) (string, error) {
				had = hasEntries(text)
				return pruneLinks(text, absent(dir, gone)), nil
			})
			if err != nil {
				failures = append(failures, fmt.Sprintf("the links in %s were not taken out, and the next run tries again: %v", file, err))
				continue
			}
			if !wrote || name == indexName || !had || hasEntries(written) {
				continue
			}
			switch r, _, err := removeNote(state, dir, name, sum(written)); r {
			case removed:
				gone[name], more = true, true
			case failed:
				failures = append(failures, fmt.Sprintf("%s has no entries left and stays: %v", file, err))
			}
		}
	}
	return failures
}

// target is the note a link names in its directory, "" for a link elsewhere. A
// link's destination in angle brackets can hold spaces, and one without them
// ends at the first space, where the link's title begins. A percent escape in
// a destination stands for the character it escapes, and a destination that
// does not decode is read as written.
func target(seg string) string {
	var t string
	if w := wikiLink.FindString(seg); w != "" {
		t, _, _ = strings.Cut(w[2:len(w)-2], "|")
		t, _, _ = strings.Cut(t, "#")
		if !strings.HasSuffix(t, ".md") {
			t += ".md"
		}
	} else if m := mdLink.FindString(seg); m != "" {
		t = m[strings.Index(m, "](")+2 : len(m)-1]
		if strings.HasPrefix(t, "<") {
			t, _, _ = strings.Cut(t[1:], ">")
		} else if i := strings.IndexAny(t, " \t"); i >= 0 {
			t = t[:i]
		}
		t, _, _ = strings.Cut(t, "#")
		if u, err := url.PathUnescape(t); err == nil {
			t = u
		}
	}
	if t == "" || strings.ContainsAny(t, "/:") || !strings.HasSuffix(t, ".md") {
		return ""
	}
	return t
}

// asksUse reports whether a note holds the line that asks for its uses: a line
// that begins with useMark.
func asksUse(text string) bool {
	for _, l := range lines(text) {
		if strings.HasPrefix(l, useMark) {
			return true
		}
	}
	return false
}

// withUse is text with the line that asks for its uses at its end, while text
// is the text whose hash is full.
func withUse(full string) func(string) (string, error) {
	return func(text string) (string, error) {
		if sum(text) != full {
			return "", errChanged
		}
		if text != "" && !strings.HasSuffix(text, "\n") {
			text += "\n"
		}
		return text + useLine + "\n", nil
	}
}

// withoutUse is text without the line that asks for its uses, its use lines
// kept, while text is the text whose hash is full.
func withoutUse(full string) func(string) (string, error) {
	return func(text string) (string, error) {
		if sum(text) != full {
			return "", errChanged
		}
		var b strings.Builder
		for _, l := range strings.SplitAfter(text, "\n") {
			if !strings.HasPrefix(l, useMark) {
				b.WriteString(l)
			}
		}
		return b.String(), nil
	}
}
