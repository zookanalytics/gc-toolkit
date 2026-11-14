package pr

import (
	"regexp"
	"strings"
)

// conventionalTitle matches a title that opens with a conventional-commit type,
// with a scope or not and a breaking mark or not. A repository's PR-title check
// requires that opening, and a title an author typed with one is kept as
// written, whatever the bead's kind. The recognized types are wider than the
// ones typeFor supplies, so any hand-written prefix survives.
var conventionalTitle = regexp.MustCompile(`^(build|chore|ci|docs|feat|fix|ops|perf|refactor|revert|security|style|test)(\([^)]+\))?!?: `)

// typeFor is the type a title no author typed takes from the bead's kind: by
// then the kind is the only signal left. Each is a type every conventional
// check accepts.
func typeFor(issueType string) string {
	switch issueType {
	case "bug":
		return "fix"
	case "feature", "feat":
		return "feat"
	case "docs":
		return "docs"
	}
	return "chore"
}

// Title is the PR's title for a bead: its own title, opened with a
// conventional-commit type when it does not open with one, then the bead's id,
// in words, each run of whitespace one space and none at either end. The squash
// merge takes its commit subject from it. It is empty when the bead's title has
// no words, since a type and an id alone name nothing.
func Title(id, title, issueType string) string {
	if words(title) == "" {
		return ""
	}
	t := title
	if !conventionalTitle.MatchString(t) {
		t = typeFor(issueType) + ": " + t
	}
	return words(t + " (" + id + ")")
}

// words is s with each run of whitespace one space and none at either end, so
// two titles that differ only in spacing read the same.
func words(s string) string {
	return strings.Join(strings.FieldsFunc(s, isSpace), " ")
}

// isSpace is the C locale's whitespace.
func isSpace(r rune) bool {
	switch r {
	case ' ', '\t', '\n', '\v', '\f', '\r':
		return true
	}
	return false
}
