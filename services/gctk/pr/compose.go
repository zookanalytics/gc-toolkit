package pr

import (
	"fmt"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// Request is what a composition takes besides the bead: the PR as GitHub has
// it, and the gates its bead's check set resolves to at its head.
type Request struct {
	// Head is the commit the PR opens at, or carries now.
	Head string
	// Body is the PR's body as published, nil for a PR not opened yet.
	Body *string
	// Opening is a PR opened, or adopted, at Head once its pre-open gates
	// signed off there. A composition then writes the summary region whenever
	// it differs, and marks one over the shape a body took before the markers
	// existed. Otherwise the PR is open, and the region is written only when it
	// no longer says what the bead says at Head.
	Opening bool
	// Gates is the gate set the bead's check set resolves to at Head, which the
	// summary region names. Nil means it was not resolved: a region that must
	// be written is then left as it stands, and reads NeedsGates.
	Gates []Gate
	// Supersedes is the PR this one replaces, which an opening PR's region
	// names.
	Supersedes *Superseded
	// Summary and BranchBeads say which of the body's sections to compose.
	Summary, BranchBeads bool
}

// Outcome is what a composition did with one section of the body.
type Outcome string

// The outcomes.
const (
	// Written: the section is composed into the body, which differs from the
	// one published.
	Written Outcome = "written"
	// Current: the published section already says it.
	Current Outcome = "current"
	// Unmanaged: the body carries no section the composition can read back,
	// a hand-written body or markers cut into another shape, so it is left as
	// it stands.
	Unmanaged Outcome = "unmanaged"
	// NeedsGates: the summary region must be written, and the request carries
	// no gates for it to name.
	NeedsGates Outcome = "needs-gates"
	// Single: the branch carries one bead's work, the PR's own, which the
	// summary region names already, so the body carries no branch-beads
	// section.
	Single Outcome = "single"
	// Unread: the beads on the branch did not read, so the section is left as
	// it stands.
	Unread Outcome = "unread"
)

// Composition is a PR's title and body as its bead says they should be, and
// what became of each section asked for.
type Composition struct {
	Title string
	Body  string
	// Summary is the summary region's outcome, "" when it was not asked for.
	Summary Outcome
	// BranchBeads is the branch-beads section's outcome, "" when it was not
	// asked for, and BranchBeadCount the beads whose work is on the branch.
	BranchBeads     Outcome
	BranchBeadCount int
	// Unread is why the beads on the branch did not read, when they did not.
	Unread error
}

// Compose composes the title and body of the PR the bead owns. It reads the bead
// and, for the branch-beads section, the beads whose work is on its branch. A
// bead the store does not hold, or one that does not read, returns an error and
// no composition. A failed read of the beads on the branch leaves that section
// Unread and composes the rest.
func Compose(l *ledger.Ledger, id string, req Request) (*Composition, error) {
	recs, err := l.Find(ledger.ByID(id).WithClosed())
	if err != nil {
		return nil, err
	}
	var bead *ledger.Record
	for _, r := range recs {
		if r.ID == id {
			bead = r
		}
	}
	if bead == nil {
		return nil, fmt.Errorf("the store holds no bead %s", id)
	}
	r, branch, err := readRegion(bead, req)
	if err != nil {
		return nil, err
	}
	out := &Composition{Title: Title(id, bead.Title(), bead.IssueType())}
	var body []string
	if req.Body != nil {
		body = textLines(strings.ReplaceAll(*req.Body, "\r", ""))
	}
	if req.Summary {
		body, out.Summary = composeSummary(body, req, r)
	}
	if req.BranchBeads {
		body, out.BranchBeads, out.BranchBeadCount, out.Unread = composeBeads(l, body, id, branch)
	}
	out.Body = text(body)
	return out, nil
}

// readRegion is what the bead's summary region says, and the bead's branch.
// The summary and the dispatch text are taken as the region carries them, and
// a summary of whitespace alone is none. The target is merged_target, else
// target, else main.
func readRegion(bead *ledger.Record, req Request) (region, string, error) {
	keys := []ledger.Key[string]{summaryKey, branchKey, mergedTargetKey, targetKey, checkSetKey}
	vals := make([]string, len(keys))
	for i, k := range keys {
		v, err := value(bead, k)
		if err != nil {
			return region{}, "", err
		}
		vals[i] = v
	}
	summary, branch, merged, target, checkSet := vals[0], vals[1], vals[2], vals[3], vals[4]
	summary = carried(summary)
	if strings.TrimFunc(summary, isSpace) == "" {
		summary = ""
	}
	return region{
		summary:  summary,
		desc:     carried(bead.Description()),
		id:       bead.ID,
		branch:   branch,
		target:   firstOf(merged, target, "main"),
		checkSet: checkSet,
		head:     req.Head,
		opening:  req.Opening,
		gates:    req.Gates,
		sup:      req.Supersedes,
	}, branch, nil
}

// carried is a bead's text as the region carries it: ended at its last line,
// and with no carriage return, because a published body is read with none. A
// region that kept one would never read back as the one written, and every
// pass would write it again.
func carried(s string) string {
	return strings.TrimRight(strings.ReplaceAll(s, "\r", ""), "\n")
}

func firstOf(vals ...string) string {
	for _, v := range vals {
		if v != "" {
			return v
		}
	}
	return ""
}

// composeSummary is the body with the summary region composed in, and what
// became of it. A PR not opened yet gets the region, marked, as its body. A
// published body's region is written in place when it is behind, an opening
// PR's whenever it differs. An opening PR's body that carries the shape written
// before the markers existed gets the region marked over that shape. Any other
// body is left as it stands.
func composeSummary(body []string, req Request, r region) ([]string, Outcome) {
	known := req.Gates != nil
	if req.Body == nil {
		if !known {
			return body, NeedsGates
		}
		return append(append([]string{summaryOpen}, r.lines()...), summaryClose), Written
	}
	switch markers(body, summaryOpen, summaryClose) {
	case markersOne:
		cur := between(body, summaryOpen, summaryClose)
		if !req.Opening && r.current(cur) {
			return body, Current
		}
		if !known {
			return body, NeedsGates
		}
		want := r.lines()
		if sameLines(cur, want) {
			return body, Current
		}
		return splice(body, summaryOpen, summaryClose, want), Written
	case markersNone:
		if !req.Opening {
			return body, Unmanaged
		}
		if _, ok := establish(body, nil); !ok {
			return body, Unmanaged
		}
		if !known {
			return body, NeedsGates
		}
		established, _ := establish(body, r.lines())
		return established, Written
	}
	return body, Unmanaged
}

// composeBeads is the body with the branch-beads section composed in, what
// became of it, and the beads on the branch. A branch that carries one bead's
// work gets no section. A section is written in place between its markers, or
// added at the end of a body that has none, and a body whose markers are cut
// into another shape is left as it stands.
func composeBeads(l *ledger.Ledger, body []string, anchor, branch string) ([]string, Outcome, int, error) {
	if branch == "" {
		return body, Unread, 0, fmt.Errorf("%s records no branch", anchor)
	}
	beads, err := branchBeads(l, branch)
	if err != nil {
		return body, Unread, 0, err
	}
	if len(beads) < 2 {
		return body, Single, len(beads), nil
	}
	section := beadsSection(branch, anchor, beads)
	switch markers(body, beadsOpen, beadsClose) {
	case markersOne:
		if sameLines(between(body, beadsOpen, beadsClose), section) {
			return body, Current, len(beads), nil
		}
		return splice(body, beadsOpen, beadsClose, section), Written, len(beads), nil
	case markersNone:
		return appendSection(body, beadsOpen, beadsClose, section), Written, len(beads), nil
	}
	return body, Unmanaged, len(beads), nil
}
