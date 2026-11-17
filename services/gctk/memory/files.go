package memory

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// Agents write memory without the intake's lock, so every write the intake
// makes to a memory directory is guarded on the text it read.

// errMoved is a rewrite whose file another writer kept changing.
var errMoved = errors.New("it kept changing while it was written")

// errChanged is an edit that refused text other than the text it was given.
var errChanged = errors.New("it changed since it was listed")

// rewrite replaces file's text with edit(text) while the file still holds the
// text edit read, and tries again, up to three times, when another writer moved
// it. It returns the text written, or the text as it stands when edit changed
// nothing, and whether it wrote.
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
		tmp, err := os.CreateTemp(filepath.Dir(file), ".memory-intake.*")
		if err != nil {
			return "", false, err
		}
		_, werr := tmp.WriteString(after)
		if err := errors.Join(werr, tmp.Close(), os.Chmod(tmp.Name(), mode)); err != nil {
			os.Remove(tmp.Name())
			return "", false, err
		}
		now, err := os.ReadFile(file)
		if err == nil && string(now) == string(before) {
			if err := os.Rename(tmp.Name(), file); err != nil {
				os.Remove(tmp.Name())
				return "", false, err
			}
			return after, true, nil
		}
		os.Remove(tmp.Name())
		if err != nil {
			return "", false, err
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

// afterKeep runs between a removal's keeping of a note's text and its last
// read, so a test can land an agent's edit there.
var afterKeep = func(string) {}

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
	afterKeep(file)
	if now, err := os.ReadFile(file); err == nil && sum(string(now)) == full {
		if err := os.Remove(file); err != nil {
			if made {
				os.Remove(kept)
			}
			return failed, "", err
		}
		return removed, kept, nil
	}
	if made {
		os.Remove(kept)
	}
	return stays, "", nil
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

// prune takes the pointers to each note in gone out of the index and every
// collection note, and removes, with its text kept, a collection note that this
// leaves with no list item, whose own pointers then go in turn. gone gains the
// collection notes it removes.
func prune(state, dir string, gone map[string]bool) []string {
	var failures []string
	for range 3 {
		names, err := hubs(dir)
		if err != nil {
			return append(failures, fmt.Sprintf("cannot list %s, so the links to the notes removed were not taken out: %v", dir, err))
		}
		more := false
		for _, name := range names {
			file := filepath.Join(dir, name)
			had := false
			written, wrote, err := rewrite(file, func(text string) (string, error) {
				had = hasEntries(text)
				return pruneLinks(text, gone), nil
			})
			if err != nil {
				failures = append(failures, fmt.Sprintf("the links in %s were not taken out: %v", file, err))
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
		if !more {
			break
		}
	}
	return failures
}

// target is the note a link names in its directory, "" for a link elsewhere.
func target(seg string) string {
	var t string
	if strings.HasPrefix(seg, "[[") {
		t = seg[2:strings.Index(seg, "]]")]
		t, _, _ = strings.Cut(t, "|")
		t, _, _ = strings.Cut(t, "#")
		if !strings.HasSuffix(t, ".md") {
			t += ".md"
		}
	} else {
		open := strings.Index(seg, "](")
		t = seg[open+2:]
		t = t[:strings.Index(t, ")")]
		t = strings.TrimSuffix(strings.TrimPrefix(t, "<"), ">")
		t, _, _ = strings.Cut(t, "#")
		if i := strings.IndexAny(t, " \t"); i >= 0 {
			t = t[:i]
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
