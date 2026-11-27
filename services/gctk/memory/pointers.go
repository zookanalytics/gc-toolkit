package memory

import (
	"regexp"
	"strings"
	"unicode"
)

// A pointer line is a list item of one line that points at notes, as the index
// and a collection note hold them. After an optional label it begins with a
// link, and bold or italics can wrap the link. A label is bold or italic text
// that holds no link and ends in a colon, inside the emphasis or just after it,
// with a space after it, as in "**Verify:** [value](value.md)".
//
// Each link in a pointer line that names a note in the directory begins a
// pointer, which holds the text that describes that note and the separator
// after it. It runs to the next such link at its own depth of parentheses, and
// one inside parentheses ends at their close at the latest, so a pointer holds
// the parentheses in its text and the links in them. A link elsewhere, and a
// link in a code span, are text.
var (
	wikiLink = regexp.MustCompile(`^\[\[[^]]+\]\]`)
	mdLink   = regexp.MustCompile(`^\[[^]]*\]\([^)]+\)`)
)

// A pointer is one in a pointer line's item, the text after its "- ": where it
// begins, the emphasis that opens on its link included, where the next begins,
// whether its link sits inside parentheses, and the note it names.
type pointer struct {
	start, end int
	nested     bool
	name       string
}

// pointerLine reports whether the list item ls[i], whose last line is ls[e],
// is a pointer line.
func pointerLine(ls []string, i, e int) bool { return e == i && points(ls[i][2:]) }

// points reports whether item, the text of a list item after its "- ", begins
// as a pointer line does.
func points(item string) bool {
	i := labelEnd(item)
	i += emphasis(item[i:])
	return linkAt(item[i:]) > 0
}

// labelEnd is where the label that begins item ends, after the spaces that
// follow it, or 0 when item begins with none.
func labelEnd(item string) int {
	n := emphasis(item)
	if n == 0 || n > 2 {
		return 0
	}
	j := strings.Index(item[n:], item[:n])
	if j <= 0 {
		return 0
	}
	inner, after := item[n:n+j], item[n+j+n:]
	if strings.ContainsAny(inner, "[]`"+item[:1]) {
		return 0
	}
	if !strings.HasSuffix(inner, ":") {
		if !strings.HasPrefix(after, ":") {
			return 0
		}
		after = after[1:]
	}
	rest := strings.TrimLeft(after, " \t")
	if len(rest) == len(after) {
		return 0
	}
	return len(item) - len(rest)
}

// emphasis is how many of the characters that open bold or italics begin s,
// up to three of one kind.
func emphasis(s string) int {
	n := 0
	for n < len(s) && n < 3 && (s[n] == '*' || s[n] == '_') && s[n] == s[0] {
		n++
	}
	return n
}

// linkAt is the length of the link s begins with, 0 when it begins with none.
func linkAt(s string) int {
	if m := wikiLink.FindStringIndex(s); m != nil {
		return m[1]
	}
	if m := mdLink.FindStringIndex(s); m != nil {
		return m[1]
	}
	return 0
}

// A link is one a line holds: where it begins and ends, the note it names, ""
// for a link elsewhere, and the parentheses it sits in, -1 for none.
type link struct {
	start, end int
	name       string
	group      int
}

// A group is a pair of parentheses: where it closes, -1 when it does not, and
// the group it sits in.
type group struct{ close, in int }

// links reads s for its links and parentheses, outside code spans.
func links(s string) ([]link, []group) {
	var ls []link
	var gs []group
	cur := -1
	for i := 0; i < len(s); {
		switch s[i] {
		case '`':
			n := len(s[i:]) - len(strings.TrimLeft(s[i:], "`"))
			if j := strings.Index(s[i+n:], s[i:i+n]); j >= 0 {
				i += n + j + n
			} else {
				i += n
			}
			continue
		case '[':
			if n := linkAt(s[i:]); n > 0 {
				ls = append(ls, link{start: i, end: i + n, name: target(s[i : i+n]), group: cur})
				i += n
				continue
			}
		case '(':
			gs = append(gs, group{close: -1, in: cur})
			cur = len(gs) - 1
		case ')':
			if cur >= 0 {
				gs[cur].close = i
				cur = gs[cur].in
			}
		}
		i++
	}
	return ls, gs
}

// pointers is each pointer of item, in the order item holds them.
func pointers(item string) []pointer {
	head := labelEnd(item)
	body := item[head:]
	ls, gs := links(body)
	var notes []link
	for _, l := range ls {
		if l.name != "" {
			notes = append(notes, l)
		}
	}
	out := make([]pointer, 0, len(notes))
	for k, l := range notes {
		end := len(body)
		if l.group >= 0 && gs[l.group].close >= 0 {
			end = gs[l.group].close
		}
		for _, n := range notes[k+1:] {
			if n.group == l.group {
				end = opened(body, n.start)
				break
			}
		}
		out = append(out, pointer{start: head + opened(body, l.start), end: head + end, nested: l.group >= 0, name: l.name})
	}
	return out
}

// opened is where the link at i in s begins, with the bold or italics that
// open on it.
func opened(s string, i int) int {
	n := 0
	for n < 3 && i-n > 0 && (s[i-n-1] == '*' || s[i-n-1] == '_') && s[i-n-1] == s[i-1] {
		n++
	}
	if n > 0 && i-n > 0 && !unicode.IsSpace(rune(s[i-n-1])) && s[i-n-1] != '(' {
		return i
	}
	return i - n
}

// pruneItem is item, the text of a pointer line after its "- ", without each
// pointer to a note gone names, and whether the line stays. A line whose
// pointers went, and that holds no other link, goes, its label with it.
func pruneItem(item string, gone func(string) bool) (string, bool) {
	took := false
	for {
		var cut *pointer
		for _, p := range pointers(item) {
			if gone(p.name) && (cut == nil || cut.nested && !p.nested) {
				cut = &p
			}
		}
		if cut == nil {
			break
		}
		item, took = cutPointer(item, *cut), true
	}
	if !took {
		return item, true
	}
	ls, _ := links(item)
	return item, len(ls) > 0
}

// cutPointer is item without p, and without the separator p's going leaves at
// the end of the item or of the parentheses p sat in, or those parentheses
// when it leaves them empty.
func cutPointer(item string, p pointer) string {
	before, after := item[:p.start], item[p.end:]
	if after == "" || p.nested && strings.HasPrefix(after, ")") {
		before = strings.TrimRightFunc(before, separator)
		if p.nested && strings.HasSuffix(before, "(") && strings.HasPrefix(after, ")") {
			before, after = strings.TrimRightFunc(before[:len(before)-1], unicode.IsSpace), after[1:]
		}
	}
	return before + after
}

// separator reports whether r is space or a mark that joins one pointer to the
// next.
func separator(r rune) bool { return unicode.IsSpace(r) || strings.ContainsRune("·,;|—–", r) }

// linkNames is each note line's links name, outside code spans.
func linkNames(line string) []string {
	ls, _ := links(line)
	var out []string
	for _, l := range ls {
		if l.name != "" {
			out = append(out, l.name)
		}
	}
	return out
}
