package pr

import (
	"regexp"
	"slices"
	"strings"
)

// The managed summary region sits between these two lines of a PR's body. They
// are HTML comments, so the rendered body does not show them, and everything
// outside them is text people added, which a composition leaves as it is.
const (
	summaryOpen  = "<!-- gc:pr-summary -->"
	summaryClose = "<!-- /gc:pr-summary -->"
)

// dispatchOpener is the second line of the collapsed section that carries the
// dispatch text below the summary. With the `<details>` line above it, it is
// one of the two boundaries the summary's own lines end at.
const dispatchOpener = "<summary>Dispatch — what this work was asked to do</summary>"

// Gate is one check a bead's check set resolves to at a head, and the phase it
// gates.
type Gate struct {
	Name, Phase string
}

// The phases a region names: the checks that sign off before the PR opens, and
// the ones that run against it while it is a draft.
const (
	phasePreOpen     = "pre-open"
	phaseOpenAsDraft = "open-as-draft"
)

// ParseGates reads the gates `review-checks.sh --resolve --with-phase` prints:
// one `<check>\t<phase>` per line. A blank line names no gate.
func ParseGates(s string) []Gate {
	var out []Gate
	for _, line := range strings.Split(s, "\n") {
		if line == "" {
			continue
		}
		f := strings.Split(line, "\t")
		g := Gate{Name: f[0]}
		if len(f) > 1 {
			g.Phase = f[1]
		}
		out = append(out, g)
	}
	return out
}

// band is the names of the gates in phase, in their order, as one comma list.
func band(gates []Gate, phase string) string {
	var names []string
	for _, g := range gates {
		if g.Phase == phase {
			names = append(names, g.Name)
		}
	}
	return strings.Join(names, ",")
}

// Superseded is a PR the branch had that closed unmerged, which a new PR
// replaces, and the head it closed at.
type Superseded struct {
	Number, Head string
}

// region is what the managed summary region says, and of what.
type region struct {
	summary, desc, id, branch, target, checkSet, head string
	// opening is a PR opened, or adopted, at head once its pre-open gates
	// signed off there. Otherwise the PR is open already, and its head may have
	// moved past the one the gates signed off at.
	opening bool
	gates   []Gate
	sup     *Superseded
}

// summaryLines are the lines the region's `## Summary` carries: the summary,
// else the dispatch text, else a line that names the bead.
func (r region) summaryLines() []string {
	switch {
	case r.summary != "":
		return stripSummaryHeading(r.summary)
	case r.desc != "":
		return strings.Split(r.desc, "\n")
	}
	return []string{"Refinery handoff for `" + r.id + "`."}
}

// lines are the region's lines, between its markers: its content, then the
// refinery handoff's facts under their heading.
func (r region) lines() []string {
	out := append(r.content(), handoffHead...)
	return append(out, r.facts()...)
}

// handoffHead is the lines between a region's content and its handoff facts.
var handoffHead = []string{"", "## Refinery handoff", ""}

// content is what the region says of the change: the summary a reviewer reads
// first, and the dispatch text in a collapsed section below it when both exist.
func (r region) content() []string {
	out := []string{"## Summary", ""}
	out = append(out, r.summaryLines()...)
	if r.summary != "" && r.desc != "" {
		out = append(out, "", "<details>", dispatchOpener, "")
		out = append(out, strings.Split(r.desc, "\n")...)
		out = append(out, "", "</details>")
	}
	return out
}

// facts are the refinery handoff's facts: the bead, its branches and its gates.
//
// The last fact states the gates, in words that turn on whether the PR is
// opening. Neither states a CI result, because the body is static and CI state
// is live. An opening PR's says its pre-open gates signed off at its head, true
// at that moment. An open PR's names the head and points to the PR's checks,
// because its gates have not signed off again at a head a rework moved, and one
// of them may be asking for changes.
func (r region) facts() []string {
	out := []string{
		"- Issue: `" + r.id + "`",
		"- Source branch: `" + r.branch + "`",
		"- Target: `" + r.target + "`",
	}
	head := short(r.head)
	signed, draft := band(r.gates, phasePreOpen), band(r.gates, phaseOpenAsDraft)
	switch {
	case r.opening && signed != "":
		out = append(out, "- Gates `"+signed+"` signed off pre-open at `"+head+"`. For CI status, see the PR checks.")
	case r.opening:
		out = append(out, "- Anchor declares no pre-open gate (`check_set="+r.checkSet+"`); opened at `"+head+"`.")
	case signed != "":
		out = append(out, "- Head `"+head+"`; gates `"+signed+"`; see the PR checks for current status.")
	default:
		out = append(out, "- Head `"+head+"`; anchor declares no pre-open gate (`check_set="+r.checkSet+"`).")
	}
	if draft != "" {
		out = append(out, "- Draft-stage gates `"+draft+"` run against the open PR before it is marked ready for review.")
	}
	if r.sup != nil && r.sup.Number != "" {
		out = append(out, "- Supersedes #"+r.sup.Number+" (closed unmerged at `"+short(r.sup.Head)+"`); re-implemented and re-gated at `"+head+"`.")
	}
	return out
}

// short is a commit's first eight characters, which the region names it by.
func short(oid string) string {
	if len(oid) > 8 {
		return oid[:8]
	}
	return oid
}

// summaryHeading is a summary's own Summary heading: the region writes its
// own, so a summary that opens with one is not published under two. A heading
// that carries other words is content, and stays.
var summaryHeading = regexp.MustCompile(`^[[:space:]]*#{1,6}[[:space:]]+[Ss]ummary[[:space:]]*$`)

// blank is a line of whitespace alone.
var blank = regexp.MustCompile(`^[[:space:]]*$`)

// stripSummaryHeading is the summary's lines, less a bare Summary heading on
// its first line and the blank lines right after it.
func stripSummaryHeading(summary string) []string {
	var out []string
	skipping := false
	for i, line := range strings.Split(summary, "\n") {
		if i == 0 && summaryHeading.MatchString(line) {
			skipping = true
			continue
		}
		if skipping && blank.MatchString(line) {
			continue
		}
		skipping = false
		out = append(out, line)
	}
	return out
}

// handoffHeading is the heading the region's handoff facts sit under.
var handoffHeading = regexp.MustCompile(`^##[ \t]+Refinery handoff[ \t]*$`)

// openedGreen is a handoff fact an older composer wrote, which says the PR
// opened green: a CI result, which a static body cannot know.
var openedGreen = regexp.MustCompile("^- Gates `[^`]*` signed off pre-open at `[^`]*`; PR opened green\\.$")

// current reports whether the lines between a body's markers still say what
// this region says of the PR at its head: they open with the same content,
// summary and dispatch text alike, and the handoff facts after it name this head
// and state no CI result. The other facts are not compared, so an open PR whose
// content and head have not moved keeps the facts it was opened with. The
// content is compared whole, as the composer writes it, never read up to a
// boundary line, so a summary that carries a collapsed section of its own, or a
// line like the handoff heading, reads as itself.
func (r region) current(between []string) bool {
	head := append(r.content(), handoffHead...)
	if !hasPrefix(between, head...) {
		return false
	}
	names := false
	for _, f := range between[len(head):] {
		if openedGreen.MatchString(f) {
			return false
		}
		if r.head != "" && strings.Contains(f, "`"+short(r.head)+"`") {
			names = true
		}
	}
	return names
}

// sameLines reports whether two sections say the same, blank lines at their
// ends aside.
func sameLines(a, b []string) bool {
	return slices.Equal(trimBlankEnd(a), trimBlankEnd(b))
}

func trimBlankEnd(lines []string) []string {
	for len(lines) > 0 && lines[len(lines)-1] == "" {
		lines = lines[:len(lines)-1]
	}
	return lines
}

func hasPrefix(lines []string, prefix ...string) bool {
	return len(lines) >= len(prefix) && slices.Equal(lines[:len(prefix)], prefix)
}

// The shapes a body's markers can take.
const (
	markersOne   = iota // exactly one pair, the opener above the closer
	markersNone         // neither marker
	markersOther        // a lone marker, a second pair, or a closer above its opener
)

// markers is the shape the open and close markers take in a body's lines. A
// marker is a whole line. A body cut into a shape other than one pair is one a
// composition cannot read its section back from, so it leaves it alone.
func markers(body []string, open, close string) int {
	var opens, closes []int
	for i, line := range body {
		switch line {
		case open:
			opens = append(opens, i)
		case close:
			closes = append(closes, i)
		}
	}
	switch {
	case len(opens) == 0 && len(closes) == 0:
		return markersNone
	case len(opens) == 1 && len(closes) == 1 && opens[0] < closes[0]:
		return markersOne
	}
	return markersOther
}

// between is the lines between a body's one pair of markers.
func between(body []string, open, close string) []string {
	o, c := slices.Index(body, open), slices.Index(body, close)
	return append([]string{}, body[o+1:c]...)
}

// splice is the body with section in place of the lines between its one pair of
// markers.
func splice(body []string, open, close string, section []string) []string {
	o, c := slices.Index(body, open), slices.Index(body, close)
	out := append([]string{}, body[:o+1]...)
	out = append(out, section...)
	return append(out, body[c:]...)
}

// appendSection is the body with section, between its markers, added below
// what is there after a blank line.
func appendSection(body []string, open, close string, section []string) []string {
	out := append(append([]string{}, body...), "", open)
	out = append(out, section...)
	return append(out, close)
}

// The legacy shape's lines: its summary heading, a blank line, and a handoff
// fact.
var (
	legacySummary = regexp.MustCompile(`^##[ \t]+Summary[ \t]*$`)
	legacyBlank   = regexp.MustCompile(`^[ \t]*$`)
	legacyFact    = regexp.MustCompile(`^-[ \t]`)
)

// establish is the body with the managed region marked over the shape a
// composition wrote before the markers existed: the first `## Summary` heading,
// whatever follows it up to the `## Refinery handoff` heading, and that
// heading's contiguous facts. Whatever comes before the heading or after the
// facts stays. ok is false when the body does not carry that shape, so a body
// it did not write is never cut.
func establish(body []string, section []string) (out []string, ok bool) {
	const (
		lead = iota
		toHandoff
		handoffHead
		facts
		tail
	)
	state, opened := lead, false
	for _, line := range body {
		switch state {
		case lead:
			if legacySummary.MatchString(line) {
				out = append(out, summaryOpen)
				out = append(out, section...)
				out = append(out, summaryClose)
				opened, state = true, toHandoff
				continue
			}
			out = append(out, line)
		case toHandoff:
			if handoffHeading.MatchString(line) {
				state = handoffHead
			}
		case handoffHead:
			switch {
			case legacyBlank.MatchString(line):
			case legacyFact.MatchString(line):
				state = facts
			default:
				state = tail
				out = append(out, line)
			}
		case facts:
			if legacyFact.MatchString(line) {
				continue
			}
			state = tail
			out = append(out, line)
		case tail:
			out = append(out, line)
		}
	}
	return out, opened && state != toHandoff
}

// textLines is a text's lines: a final newline ends the last line rather than
// starting another, and an empty text has none.
func textLines(s string) []string {
	if s == "" {
		return nil
	}
	return strings.Split(strings.TrimSuffix(s, "\n"), "\n")
}

// text is lines as a body, each line ended by a newline.
func text(lines []string) string {
	if len(lines) == 0 {
		return ""
	}
	return strings.Join(lines, "\n") + "\n"
}
