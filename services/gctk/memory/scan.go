package memory

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

// A Unit is a whole note, or an entry of a collection note with text of its
// own, as one scan read it.
type Unit struct {
	Kind string
	// Name is the file that holds it.
	Name string
	// Hash is what the list keys it by: a note's body hash, an entry's hash.
	Hash string
	// Full is the hash of its whole text, the file for a note, which a ref
	// names, so a decision acts only on the text that was listed.
	Full string
	// Mtime is the file's modification time.
	Mtime time.Time
	// Text is an entry's text, each line ending in a newline.
	Text string
}

// scan reads every unit dir holds. A directory that does not list, or a file
// it lists that does not read, fails the scan, since a scan that is not whole
// would read as notes gone.
func scan(dir string) ([]Unit, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, fmt.Errorf("cannot list %s: %w", dir, err)
	}
	var units []Unit
	for _, e := range entries {
		name := e.Name()
		if !e.Type().IsRegular() || !strings.HasSuffix(name, ".md") || name == indexName || hasControl(name) {
			continue
		}
		info, err := e.Info()
		if err != nil {
			return nil, fmt.Errorf("cannot read every note in %s: %w", dir, err)
		}
		raw, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			return nil, fmt.Errorf("cannot read every note in %s: %w", dir, err)
		}
		text := string(raw)
		if !strings.HasPrefix(name, hubPrefix) {
			units = append(units, Unit{Kind: Note, Name: name, Hash: bodyHash(text), Full: sum(text), Mtime: info.ModTime()})
			continue
		}
		for _, t := range entryTexts(text) {
			h := sum(t)
			units = append(units, Unit{Kind: Entry, Name: name, Hash: h, Full: h, Mtime: info.ModTime(), Text: t})
		}
	}
	return units, nil
}

func hasControl(s string) bool {
	return strings.ContainsFunc(s, func(r rune) bool { return r < 0x20 || r == 0x7f })
}

// lines is text split into lines, a last line with no newline counted, and no
// line after a final newline.
func lines(text string) []string {
	if text == "" {
		return nil
	}
	return strings.Split(strings.TrimSuffix(text, "\n"), "\n")
}

// joined is ls each followed by a newline.
func joined(ls []string) string {
	if len(ls) == 0 {
		return ""
	}
	return strings.Join(ls, "\n") + "\n"
}

// bodyHash hashes what a note's writer wrote: the text after its front matter,
// without leading blank lines or the lines that record a use. A Claude Code
// save rewrites only front matter (specs/tk-riu2z5n/claude-code-saves.md), so
// neither a save nor a recorded use changes it.
func bodyHash(text string) string {
	ls := lines(text)
	start := 0
	if len(ls) > 0 && fence(ls[0]) {
		for j := 1; j < len(ls); j++ {
			if fence(ls[j]) {
				start = j + 1
				break
			}
		}
	}
	var body []string
	for _, l := range ls[start:] {
		if len(body) == 0 && strings.TrimSpace(l) == "" {
			continue
		}
		if !useRecord.MatchString(l) {
			body = append(body, l)
		}
	}
	return sum(joined(body))
}

func fence(l string) bool { return strings.TrimRight(l, " \t\r") == "---" }

// An entry is a top-level list item with the indented lines under it, and a
// blank line belongs to it only when an indented line follows. An entry of one
// line that begins with a link is a pointer to a note, not a unit.
var (
	wikiLink = regexp.MustCompile(`^\[\[[^]]+\]\]`)
	mdLink   = regexp.MustCompile(`^\[[^]]*\]\([^)]+\)`)
)

func linkStart(s string) bool { return wikiLink.MatchString(s) || mdLink.MatchString(s) }

// entryEnd is the last line of the entry that begins at ls[i].
func entryEnd(ls []string, i int) int {
	e := i
	for k := i + 1; k < len(ls); k++ {
		if strings.TrimLeft(ls[k], " \t") == "" {
			continue
		}
		if ls[k][0] != ' ' && ls[k][0] != '\t' {
			break
		}
		e = k
	}
	return e
}

func pointer(ls []string, i, e int) bool { return e == i && linkStart(ls[i][2:]) }

// entryTexts is the text of each entry of a collection note that is not a
// pointer, in the order the note holds them.
func entryTexts(text string) []string {
	ls := lines(text)
	var out []string
	for i := 0; i < len(ls); i++ {
		if !strings.HasPrefix(ls[i], "- ") {
			continue
		}
		e := entryEnd(ls, i)
		if !pointer(ls, i, e) {
			out = append(out, joined(ls[i:e+1]))
		}
		i = e
	}
	return out
}

// hasEntries reports whether a collection note holds any list item.
func hasEntries(text string) bool {
	for _, l := range lines(text) {
		if strings.HasPrefix(l, "- ") {
			return true
		}
	}
	return false
}
