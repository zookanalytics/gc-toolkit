package pr

import (
	"cmp"
	"regexp"
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
)

// The branch-beads section sits between these two lines of a PR's body, below
// the managed summary region.
const (
	beadsOpen  = "<!-- gc:branch-beads -->"
	beadsClose = "<!-- /gc:branch-beads -->"
)

// onBranch is one bead whose work is on a PR's branch.
type onBranch struct {
	id, title, created, branch string
}

// branchBeads reads the beads whose work is on branch, at any status, since a
// closed bead's work is on the branch as much as an open one's. Three records
// put a bead there, and the beads are their union:
//   - its own branch, when it is the branch's anchor (it carries a
//     merge_result) or carries no route, because a rework child carries the
//     branch from its creation, and its fix is not on the branch until its
//     polecat's hand-off clears the route;
//   - fold_target, when a polecat folded its work onto the branch;
//   - merged_target with merge_result=merged, when its work landed on the
//     branch.
//
// A bead that put no work there is left out: one closed as another bead's
// duplicate, whose branch can name this one, and one whose work outcome reads
// no-op. So are the beads a listing hides unless asked, gates, wisps and
// templates, which carry no work. A read that fails fails the whole set, since
// a short list published as the whole one would drop beads the body names.
func branchBeads(l *ledger.Ledger, branch string) ([]onBranch, error) {
	direct, err := l.Find(ledger.Matching(branchKey, branch).WithClosed())
	if err != nil {
		return nil, err
	}
	folded, err := l.Find(ledger.Matching(foldTargetKey, branch).WithClosed())
	if err != nil {
		return nil, err
	}
	landed, err := l.Find(record.OnTarget(branch).WithClosed())
	if err != nil {
		return nil, err
	}
	var out []onBranch
	add := func(r *ledger.Record) error {
		if slices.ContainsFunc(out, func(b onBranch) bool { return b.id == r.ID }) {
			return nil
		}
		worked, err := putWork(r)
		if err != nil || !worked {
			return err
		}
		own, _, err := branchKey.Get(r)
		if err != nil {
			return err
		}
		out = append(out, onBranch{id: r.ID, title: r.Title(), created: r.CreatedAt(), branch: own})
		return nil
	}
	for _, r := range direct {
		result, err := value(r, record.Result)
		if err != nil {
			return nil, err
		}
		route, err := value(r, routedToKey)
		if err != nil {
			return nil, err
		}
		if result == "" && route != "" {
			continue
		}
		if err := add(r); err != nil {
			return nil, err
		}
	}
	for _, r := range folded {
		if err := add(r); err != nil {
			return nil, err
		}
	}
	for _, r := range landed {
		result, err := value(r, record.Result)
		if err != nil {
			return nil, err
		}
		if result != "merged" {
			continue
		}
		if err := add(r); err != nil {
			return nil, err
		}
	}
	return out, nil
}

// putWork reports whether a bead a record of the branch names put work on it:
// it is no gate, wisp or template, it closed as no other bead's duplicate, and
// its work outcome does not read no-op.
func putWork(r *ledger.Record) (bool, error) {
	if r.IssueType() == "gate" || r.EphemeralPlane() || r.Template() {
		return false, nil
	}
	edges, err := r.Edges()
	if err != nil {
		return false, err
	}
	if slices.ContainsFunc(edges, func(e ledger.Edge) bool { return e.Type == "duplicates" && e.ID != "" }) {
		return false, nil
	}
	outcome, err := value(r, workOutcomeKey)
	return outcome != "no-op", err
}

// value is a key's value on r, "" when r does not carry it.
func value(r *ledger.Record, k reading) (string, error) {
	v, _, err := k.Get(r)
	return v, err
}

// beadsSection is the section's lines: every bead whose work is on the branch,
// the anchor first as the bead the PR was opened for, then the rest in the
// order their work reached the branch, oldest first. A bead whose own branch is
// another one got here by a merge, so its line names that branch: a separate
// work item riding the PR reads differently from a fix to it.
func beadsSection(branch, anchor string, beads []onBranch) []string {
	ordered := slices.Clone(beads)
	slices.SortStableFunc(ordered, func(a, b onBranch) int {
		switch {
		case a.id == anchor:
			return -1
		case b.id == anchor:
			return 1
		}
		return cmp.Or(strings.Compare(a.created, b.created), strings.Compare(a.id, b.id))
	})
	out := []string{
		"## Beads on this branch",
		"",
		"Every bead whose work is on `" + branch + "`. Approving this PR approves all of them.",
		"",
	}
	for _, b := range ordered {
		line := "- `" + b.id + "` — " + oneLine(b.title)
		switch {
		case b.id == anchor:
			line += " _(opener)_"
		case b.branch != "" && b.branch != branch:
			line += " _(merged in from `" + b.branch + "`)_"
		}
		out = append(out, line)
	}
	return out
}

// lineBreaks is a run of the characters that would break a title's line.
var lineBreaks = regexp.MustCompile(`[\r\n\t]+`)

// oneLine is a bead's title as one line of the section: each run of line
// breaks and tabs one space, the HTML comment delimiters gone so no title can
// open or close a marker, and the first 160 characters.
func oneLine(title string) string {
	t := lineBreaks.ReplaceAllString(title, " ")
	t = strings.ReplaceAll(t, "<!--", "")
	t = strings.ReplaceAll(t, "-->", "")
	if r := []rune(t); len(r) > 160 {
		t = string(r[:160])
	}
	return t
}
