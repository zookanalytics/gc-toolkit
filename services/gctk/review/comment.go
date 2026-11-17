package review

import (
	"fmt"
	"slices"
	"strings"
)

// The head's comment is where every lane's verdict at a head reaches the PR,
// the place the operator decides from: one comment for each head a run
// judged, carrying each lane's verdict, approvals included, each finding the
// lane raised and how the round ruled it, and each ask the round took. Each
// point's answer says what the head carries for it: the commit that fixes it
// and the head that carries the commit, or that the head carries no change for
// it. The comment opens with its mark, which names the run and the head, so a
// retry finds the comment and edits it rather than posting a second.

// Mark is the line that opens the comment of the run root at head.
func Mark(root, head string) string {
	return fmt.Sprintf("<!-- gc:review-run %s %s -->", root, head)
}

// Comment is the comment for iteration n of the run: its head's checks, their
// findings and the round's rulings, and the asks the round took, with asks
// naming the ones on the bead. It is "" when the iteration has nothing to
// answer: no lane ran there and the round took no ask.
func Comment(run *Run, n int, asks []Ask) string {
	it := run.Iterations[n]
	if it == nil || it.Triage == nil || it.Repair == nil {
		return ""
	}
	rp := it.Repair
	var askRulings []Ruling
	for _, r := range rp.Rulings {
		if r.Ask != "" {
			askRulings = append(askRulings, r)
		}
	}
	if len(it.Lanes) == 0 && len(askRulings) == 0 {
		return ""
	}
	head := it.Triage.Head
	var b strings.Builder
	fmt.Fprintln(&b, Mark(run.Root, head))
	fmt.Fprintf(&b, "**Review at `%s`**: %s\n\n", short(head), summary(it, run.Shadow))
	for _, ln := range it.Lanes {
		if ln.NeedsYou != "" {
			fmt.Fprintf(&b, "**Needs you (%s):** %s\n\n", ln.Check, oneLine(ln.NeedsYou))
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
			fmt.Fprintf(&b, "| %s | %s | %s | %s |\n", ln.Check, ln.Verdict, g, tally(ln, rp))
		}
		fmt.Fprintln(&b)
	}
	for _, ln := range it.Lanes {
		if len(ln.Findings) == 0 {
			continue
		}
		fmt.Fprintf(&b, "<details><summary>%s: %s, %s</summary>\n\n", ln.Check, ln.Verdict, grades(ln))
		for _, f := range bySeverity(ln.Findings) {
			grade := f.Severity
			if grade == "" {
				grade = "ungraded"
			}
			fmt.Fprintf(&b, "- **%s** (%s, `%s`): %s\n", f.ID, grade, f.Locus, oneLine(f.Message))
			r, ok := rulingOf(rp, func(r Ruling) bool { return r.rulesFinding(ln.Check, f.ID) })
			fmt.Fprintf(&b, "  - %s\n", answer(r, ok, rp, run.Shadow))
		}
		fmt.Fprintln(&b, "\n</details>")
		fmt.Fprintln(&b)
	}
	if len(askRulings) > 0 {
		fmt.Fprintln(&b, "**Asks the round took**")
		fmt.Fprintln(&b)
		for _, r := range askRulings {
			what := r.Ask
			for _, a := range asks {
				if a.ID == r.Ask && a.Reason != "" {
					what = fmt.Sprintf("%s (%s)", oneLine(a.Reason), r.Ask)
				}
			}
			fmt.Fprintf(&b, "- %s: %s\n", what, answer(r, true, rp, run.Shadow))
		}
		fmt.Fprintln(&b)
	}
	fmt.Fprintf(&b, "<sub>Review run %s, iteration %d, into %s.</sub>\n", run.Root, n, run.Target)
	return b.String()
}

// summary is the comment's first sentence: each lane's verdict, and what the
// round did.
func summary(it *Iteration, shadow bool) string {
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
	for _, r := range it.Repair.Rulings {
		count[r.Ruling]++
	}
	var did []string
	if c := count[RulingMustFix]; c > 0 {
		switch {
		case shadow:
			did = append(did, fmt.Sprintf("would fix %d (a shadow run changes nothing)", c))
		case it.Repair.Pushed != "":
			did = append(did, fmt.Sprintf("fixed %d in `%s`", c, short(it.Repair.Pushed)))
		default:
			did = append(did, fmt.Sprintf("ruled %d must-fix", c))
		}
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
func tally(ln Lane, rp *Repair) string {
	if len(ln.Findings) == 0 {
		return "none"
	}
	count := map[string]int{}
	for _, f := range ln.Findings {
		r, ok := rulingOf(rp, func(r Ruling) bool { return r.rulesFinding(ln.Check, f.ID) })
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

// answer is one point's answer: its ruling, and what the head carries for it.
func answer(r Ruling, ok bool, rp *Repair, shadow bool) string {
	if !ok {
		return "Not ruled."
	}
	reason := oneLine(r.Reason)
	switch r.Ruling {
	case RulingMustFix:
		switch {
		case shadow:
			return "Must fix, and a shadow run fixes nothing: " + reason
		case rp.Pushed != "":
			return fmt.Sprintf("Fixed by `%s`, which `%s` carries: %s", short(r.Commit), short(rp.Pushed), reason)
		default:
			return fmt.Sprintf("Fixed by `%s`: %s", short(r.Commit), reason)
		}
	case RulingDeclined:
		return "Declined, and the head carries no change for it: " + reason
	case RulingDeferred:
		return "Deferred to work of its own once this PR lands: " + reason
	case RulingAnswered:
		return "Answered: " + reason
	case RulingQuestion:
		if r.Gate == "" {
			return "A question for you: " + reason
		}
		return fmt.Sprintf("Put to you through %s: %s", r.Gate, reason)
	}
	return fmt.Sprintf("Ruled %s: %s", r.Ruling, reason)
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
