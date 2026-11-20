package doctor

import (
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// Entry is one check the accepted file names: a warning or error the operator
// accepted, with the reason and the ruling that accepted it. For, when set, is
// how long the check may fail before it is no longer accepted, from the time
// it first failed.
type Entry struct {
	Check  string `json:"-"`
	Reason string `json:"reason"`
	Ruling string `json:"ruling"`
	For    string `json:"for,omitempty"`

	bound time.Duration
}

// Accepts reports whether the entry accepts a check that first failed at
// first, judged at now.
func (e Entry) Accepts(first, now time.Time) bool {
	return e.bound == 0 || now.Sub(first) < e.bound
}

// The lines the accepted file's grammar reads.
var (
	tableLine = regexp.MustCompile(`^\[\[accepted\]\]$`)
	entryLine = regexp.MustCompile(`^([a-z]+)\s*=\s*(".*")$`)
)

// ReadAccepted reads the accepted file at path.
func ReadAccepted(path string) ([]Entry, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("the accepted file did not read: %w", err)
	}
	entries, err := ParseAccepted(string(raw))
	if err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	return entries, nil
}

// ParseAccepted reads the accepted file's text, in a strict subset of TOML:
// `#` comments, blank lines, an [[accepted]] table per entry, and in each
// table the keys check, reason and ruling, and optionally for, each set once
// to a basic string on one line. check names one result as gc doctor names it,
// whole, and no two entries name the same one. for is a Go duration over zero.
// Any other line is refused, so an entry the file means to hold is never
// silently dropped.
func ParseAccepted(text string) ([]Entry, error) {
	var out []Entry
	var cur *Entry
	set := map[string]bool{}
	seen := map[string]bool{}
	finish := func(line int) error {
		if cur == nil {
			return nil
		}
		for _, k := range []string{"check", "reason", "ruling"} {
			if !set[k] {
				return fmt.Errorf("the entry that ends before line %d has no %s", line, k)
			}
		}
		if seen[cur.Check] {
			return fmt.Errorf("two entries name the check %s", cur.Check)
		}
		seen[cur.Check] = true
		out = append(out, *cur)
		cur, set = nil, map[string]bool{}
		return nil
	}
	lines := strings.Split(text, "\n")
	for i, raw := range lines {
		n := i + 1
		line := strings.TrimSpace(raw)
		switch {
		case line == "" || strings.HasPrefix(line, "#"):
			continue
		case tableLine.MatchString(line):
			if err := finish(n); err != nil {
				return nil, err
			}
			cur = &Entry{}
			continue
		}
		m := entryLine.FindStringSubmatch(line)
		if m == nil {
			return nil, fmt.Errorf("line %d is neither an [[accepted]] table nor a key set to a string: %s", n, line)
		}
		if cur == nil {
			return nil, fmt.Errorf("line %d sets %s outside an [[accepted]] table", n, m[1])
		}
		key := m[1]
		if set[key] {
			return nil, fmt.Errorf("line %d sets %s a second time in one entry", n, key)
		}
		v, err := strconv.Unquote(m[2])
		if err != nil {
			return nil, fmt.Errorf("line %d: the value of %s is not one basic string: %s", n, key, m[2])
		}
		v = strings.TrimSpace(v)
		if v == "" {
			return nil, fmt.Errorf("line %d sets %s to nothing", n, key)
		}
		switch key {
		case "check":
			cur.Check = v
		case "reason":
			cur.Reason = v
		case "ruling":
			cur.Ruling = v
		case "for":
			d, err := time.ParseDuration(v)
			if err != nil || d <= 0 {
				return nil, fmt.Errorf("line %d: for is %q, which is no Go duration over zero", n, v)
			}
			cur.For, cur.bound = v, d
		default:
			return nil, fmt.Errorf("line %d sets %s, which is not a key of an entry (check, reason, ruling, for)", n, key)
		}
		set[key] = true
	}
	if err := finish(len(lines) + 1); err != nil {
		return nil, err
	}
	return out, nil
}
