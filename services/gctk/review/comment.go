package review

import (
	"fmt"
	"slices"
	"sort"
	"strings"
)

// The head's comment is where every lane's verdict at a head reaches the PR,
// the place the operator decides from: one comment for each head a run
// judged, carrying each lane's verdict, approvals included, each finding the
// lane raised and how the round ruled it, and each ask the round took, the
// asks triage answered among them. Each point's answer says what the head
// carries for it: the commit that fixes it and the head that carries the
// commit, that the PR's summary carries its fix, or that the head carries no
// change for it. The comment opens with its mark, which names the run and the
// head, so a retry finds the comment and edits it rather than posting a second.
//
// GitHub refuses a comment over 65,536 characters, which no retry of the post
// gets past, so the comment stays within commentBudget. A comment that would
// pass it cuts each finding's message, each ask's reason, each ruling's reason
// and each lane's note to the person, at the loosest of commentCuts under which
// it fits. Past the tightest, it lists the points in order for as long as they
// fit and counts the ones it leaves out. An answer cut keeps its opening, which
// names the commit that fixes the point.

// commentBudget is the most bytes the head's comment takes. A character is
// never fewer than one byte, and the writer of the city's posts adds the
// city's mark after the comment.
const commentBudget = 60000

// commentCuts are the lengths, in characters, the comment cuts its texts to,
// loosest first, 0 for no cut.
var commentCuts = []int{0, 1500, 400, 200}

// Mark is the line that opens the comment of the run root at head.
func Mark(root, head string) string {
	return fmt.Sprintf("<!-- gc:review-run %s %s -->", root, head)
}

// Comment is the comment for iteration n of the run: its head's checks, their
// findings and the round's rulings, and the asks the round took, triage's and
// rule-and-repair's, with asks naming the ones on the bead. It is "" when the
// iteration has nothing to answer: triage has not written, or no lane ran
// there and the round took no ask.
func Comment(run *Run, n int, asks []Ask) string {
	it := run.Iterations[n]
	if it == nil || it.Triage == nil {
		return ""
	}
	c := commenting{run: run, n: n, it: it, asks: asks, round: it.Rulings(), pushed: it.Pushed()}
	for _, r := range c.round {
		if r.Ask != "" {
			c.askRulings = append(c.askRulings, r)
		}
	}
	if len(it.Lanes) == 0 && len(c.askRulings) == 0 {
		return ""
	}
	points := len(c.askRulings)
	for _, ln := range it.Lanes {
		points += len(ln.Findings)
	}
	for _, cut := range commentCuts {
		if body := c.render(cut, points); len(body) <= commentBudget {
			return body
		}
	}
	tightest := commentCuts[len(commentCuts)-1]
	shown := sort.Search(points, func(k int) bool { return len(c.render(tightest, k+1)) > commentBudget })
	return c.render(tightest, shown)
}

// commenting is one head's comment as it is rendered: the run, the iteration
// and its rulings, the head its round pushed, the asks on the bead and the
// rulings of the asks the round took.
type commenting struct {
	run        *Run
	n          int
	it         *Iteration
	asks       []Ask
	round      []Ruling
	pushed     string
	askRulings []Ruling
}

// render is the comment with each text cut to cut characters, 0 for none,
// listing the first shown points, each lane's findings in turn and then the
// asks, and counting the rest.
func (c commenting) render(cut, shown int) string {
	it, round, pushed := c.it, c.round, c.pushed
	head := it.Triage.Head
	listed := 0
	var b strings.Builder
	fmt.Fprintln(&b, Mark(c.run.Root, head))
	fmt.Fprintf(&b, "**Review at `%s`**: %s\n\n", short(head), summary(it))
	for _, ln := range it.Lanes {
		if ln.NeedsYou != "" {
			fmt.Fprintf(&b, "**Needs you (%s):** %s\n\n", ln.Check, clip(oneLine(ln.NeedsYou), cut))
		}
	}
	for _, ln := range it.Lanes {
		if ln.Visual != "" {
			fmt.Fprintf(&b, "%s Visual: %s\n\n", ln.Check, visualLine(ln))
		}
	}
	if len(it.Lanes) > 0 {
		fmt.Fprintln(&b, "| Check | Verdict | Findings | Ruled |")
		fmt.Fprintln(&b, "|---|---|---|---|")
		for _, ln := range it.Lanes {
			g := grades(ln)
			if g == "" {
				g = "none"
			}
			fmt.Fprintf(&b, "| %s | %s | %s | %s |\n", ln.Check, ln.Verdict, g, tally(ln, round))
		}
		fmt.Fprintln(&b)
	}
	for _, ln := range it.Lanes {
		if len(ln.Findings) == 0 || listed >= shown {
			continue
		}
		fmt.Fprintf(&b, "<details><summary>%s: %s, %s</summary>\n\n", ln.Check, ln.Verdict, grades(ln))
		for _, f := range bySeverity(ln.Findings) {
			if listed >= shown {
				break
			}
			listed++
			grade := f.Severity
			if grade == "" {
				grade = "ungraded"
			}
			fmt.Fprintf(&b, "- **%s** (%s, `%s`): %s\n", f.ID, grade, f.Locus, clip(oneLine(f.Message), cut))
			r, ok := rulingOf(round, func(r Ruling) bool { return r.rulesFinding(ln.Check, f.ID) })
			fmt.Fprintf(&b, "  - %s\n", answer(clipped(r, cut), ok, pushed))
		}
		fmt.Fprintln(&b, "\n</details>")
		fmt.Fprintln(&b)
	}
	if len(c.askRulings) > 0 && listed < shown {
		fmt.Fprintln(&b, "**Asks the round took**")
		fmt.Fprintln(&b)
		for _, r := range c.askRulings {
			if listed >= shown {
				break
			}
			listed++
			what := r.Ask
			for _, a := range c.asks {
				if a.ID == r.Ask && a.Reason != "" {
					what = fmt.Sprintf("%s (%s)", clip(oneLine(a.Reason), cut), r.Ask)
				}
			}
			fmt.Fprintf(&b, "- %s: %s\n", what, settles(answer(clipped(r, cut), true, pushed), r))
		}
		fmt.Fprintln(&b)
	}
	total := len(c.askRulings)
	for _, ln := range it.Lanes {
		total += len(ln.Findings)
	}
	switch left := total - listed; {
	case left == 1:
		fmt.Fprintln(&b, "1 more point is left out here to fit the size GitHub allows a comment.")
		fmt.Fprintln(&b)
	case left > 1:
		fmt.Fprintf(&b, "%d more points are left out here to fit the size GitHub allows a comment.\n\n", left)
	}
	fmt.Fprintf(&b, "<sub>Review run %s, iteration %d, into %s.</sub>\n", c.run.Root, c.n, c.run.Target)
	return b.String()
}

// clip is s cut to at most n characters, at a word boundary when one falls in
// the second half, with an ellipsis marking the cut. A cut of 0 leaves s whole.
func clip(s string, n int) string {
	rs := []rune(s)
	if n <= 0 || len(rs) <= n {
		return s
	}
	h := string(rs[:n])
	if i := strings.LastIndexAny(h, " \t"); i >= 0 && len([]rune(h[:i])) >= n/2 {
		h = h[:i]
	}
	return strings.TrimRight(h, " \t") + "…"
}

// clipped is r with its reason cut to n characters.
func clipped(r Ruling, n int) Ruling {
	r.Reason = clip(oneLine(r.Reason), n)
	return r
}

// summary is the comment's first sentence: each lane's verdict, and what the
// round did, with the points fixed in the PR's summary alone counted apart
// from the ones a commit fixes.
func summary(it *Iteration) string {
	var lanes []string
	for _, ln := range it.Lanes {
		v := "approved"
		if ln.Verdict == VerdictRequestChanges {
			v = "requested changes"
		}
		lanes = append(lanes, ln.Check+" "+v)
	}
	ran := "no check ran at this head"
	if len(lanes) > 0 {
		ran = strings.Join(lanes, ", ")
	}
	count := map[string]int{}
	inSummary := 0
	for _, r := range it.Rulings() {
		if r.Ruling == RulingMustFix && r.Commit == "" && r.Summary {
			inSummary++
			continue
		}
		count[r.Ruling]++
	}
	var did []string
	if c := count[RulingMustFix]; c > 0 {
		switch pushed := it.Pushed(); {
		case pushed != "":
			did = append(did, fmt.Sprintf("fixed %d in `%s`", c, short(pushed)))
		default:
			did = append(did, fmt.Sprintf("ruled %d must-fix", c))
		}
	}
	if inSummary > 0 {
		did = append(did, fmt.Sprintf("fixed %d in the PR's summary", inSummary))
	}
	for _, k := range []struct{ ruling, word string }{
		{RulingDeclined, "declined"}, {RulingDeferred, "deferred"}, {RulingAnswered, "answered"}, {RulingQuestion, "put to you"},
	} {
		if c := count[k.ruling]; c > 0 {
			did = append(did, fmt.Sprintf("%s %d", k.word, c))
		}
	}
	if len(did) == 0 {
		return ran + "."
	}
	return ran + ". The round " + strings.Join(did, ", ") + "."
}

// bySeverity is the findings, the most severe first, in the lane's order
// within a grade, an ungraded one after the P2s.
func bySeverity(fs []Finding) []Finding {
	out := slices.Clone(fs)
	slices.SortStableFunc(out, func(a, b Finding) int { return rank(a.Severity) - rank(b.Severity) })
	return out
}

func rank(grade string) int {
	if i := slices.Index([]string{"P0", "P1", "P2"}, strings.ToUpper(grade)); i >= 0 {
		return i
	}
	return 3
}

// grades is a lane's findings counted per grade, as in "1 P1, 2 P2".
func grades(ln Lane) string {
	count := map[string]int{}
	for _, f := range ln.Findings {
		g := strings.ToUpper(f.Severity)
		if g == "" {
			g = "ungraded"
		}
		count[g]++
	}
	var out []string
	for _, g := range []string{"P0", "P1", "P2", "ungraded"} {
		if count[g] > 0 {
			out = append(out, fmt.Sprintf("%d %s", count[g], g))
		}
	}
	return strings.Join(out, ", ")
}

// tally is a lane's findings by how the round ruled them.
func tally(ln Lane, round []Ruling) string {
	if len(ln.Findings) == 0 {
		return "none"
	}
	count := map[string]int{}
	for _, f := range ln.Findings {
		r, ok := rulingOf(round, func(r Ruling) bool { return r.rulesFinding(ln.Check, f.ID) })
		if !ok {
			count["unruled"]++
			continue
		}
		count[r.Ruling]++
	}
	var out []string
	for _, k := range []string{RulingMustFix, RulingDeclined, RulingDeferred, RulingAnswered, RulingQuestion, "unruled"} {
		if count[k] > 0 {
			out = append(out, fmt.Sprintf("%d %s", count[k], k))
		}
	}
	return strings.Join(out, ", ")
}

// answer is one point's answer: its ruling, and what the head carries for it,
// where pushed is the head the round pushed.
func answer(r Ruling, ok bool, pushed string) string {
	if !ok {
		return "Not ruled."
	}
	return r.Answer(pushed)
}

// settles is an ask's answer with what its ruling says of the question the
// ask's post settles, the answer as it is when the post settles none.
func settles(answer string, r Ruling) string {
	switch {
	case r.Settles == "":
		return answer
	case r.Moot:
		return fmt.Sprintf("%s The post makes the question at %s moot.", Punctuated(answer), r.Settles)
	}
	return fmt.Sprintf("%s The post settles the question at %s.", Punctuated(answer), r.Settles)
}

// Punctuated is s with a full stop at its end when it ends with no mark that
// ends a sentence, so a sentence can follow it.
func Punctuated(s string) string {
	s = strings.TrimRight(s, " ")
	if s == "" || strings.ContainsAny(s[len(s)-1:], ".!?") {
		return s
	}
	return s + "."
}

// visualLine says what kind of visual a demo verdict rests on: its modality,
// with a repo-artifact read as author-committed, since a committed visual is
// what an author recorded and not a capture of the reviewed commit, and the
// modality a fallback stands in for.
func visualLine(ln Lane) string {
	var notes []string
	if ln.Visual == "repo-artifact" {
		notes = append(notes, "author-committed")
	}
	if ln.VisualFallbackFrom != "" {
		notes = append(notes, "fallback from "+ln.VisualFallbackFrom)
	}
	if len(notes) == 0 {
		return ln.Visual
	}
	return fmt.Sprintf("%s (%s)", ln.Visual, strings.Join(notes, "; "))
}

// short is a commit's first twelve characters.
func short(oid string) string {
	if len(oid) > 12 {
		return oid[:12]
	}
	return oid
}
