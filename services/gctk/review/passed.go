package review

import (
	"fmt"
	"maps"
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/git"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// The pass rule, the check script of a review run's loop. An iteration passes
// when triage wrote the head it judged, every lane triage bonded wrote its
// verdict at that head, rule-and-repair ruled every finding and every ask it
// took, ruled nothing must-fix and pushed nothing, and every ask open on the
// bead that the run can take is one the round took, with each check it sends
// back run at the head. An ask that something holds counts for nothing, so it
// spends no attempt, and its own edge holds the PR until a later run takes it.
// Each finding or ask the run ruled must-fix at an earlier head must name the
// commit that fixes it. A finding declined by its lane's own rule counts as
// ruled, and so does a question put to a person, so the loop stops there
// rather than spend its attempts on a question only a person can settle.
//
// The rule reads only the store, because a check runs inside the control
// dispatcher with a PATH that has no gh, and the steps' outputs carry the
// heads.

// Verdict is the pass rule's answer for one iteration of a run: whether it
// passed, and each reason it did not, with what the rule read to decide it.
type Verdict struct {
	Run       *Run
	Iteration int
	Asks      []Ask
	Passed    bool
	Reasons   []string
}

// Passed applies the pass rule to iteration n of the run id names, its root or
// any bead poured under it, and with n 0 to the latest iteration any step
// wrote for. A read that fails returns the store's error and no verdict.
func Passed(l *ledger.Ledger, id string, n int) (*Verdict, error) {
	run, err := ReadRun(l, id)
	if err != nil {
		return nil, err
	}
	asks, err := AsksOn(l, run.PRBead)
	if err != nil {
		return nil, err
	}
	if n == 0 {
		n = run.Latest()
	}
	v := &Verdict{Run: run, Iteration: n, Asks: asks}
	v.Reasons = judge(run, n, asks)
	v.Passed = len(v.Reasons) == 0
	return v, nil
}

// judge is each reason iteration n of run does not pass, none when it does.
func judge(run *Run, n int, asks []Ask) []string {
	var why []string
	for _, b := range run.Broken {
		why = append(why, "an output does not read, so its step has not written: "+b)
	}
	it := run.Iterations[n]
	if n < 1 || it == nil {
		return append(why, "no step has written for the iteration, so triage has judged no head")
	}
	if it.Triage == nil || it.Triage.Head == "" {
		return append(why, fmt.Sprintf("triage wrote no head in iteration %d", n))
	}
	head := it.Triage.Head
	ran := map[string]bool{}
	for _, p := range it.Triage.Checks {
		if p.Head != head {
			why = append(why, fmt.Sprintf("triage picked %s at %s, not at the head it judged, %s", p.Check, p.Head, head))
			continue
		}
		ln, ok := lane(it, p.Check)
		switch {
		case !ok:
			why = append(why, fmt.Sprintf("the %s lane wrote no verdict in iteration %d", p.Check, n))
		case ln.Head != head:
			why = append(why, fmt.Sprintf("the %s lane reviewed %s, not the head triage judged, %s", p.Check, ln.Head, head))
		case ln.Verdict != VerdictApprove && ln.Verdict != VerdictRequestChanges:
			why = append(why, fmt.Sprintf("the %s lane's verdict reads %q, not %s or %s", p.Check, ln.Verdict, VerdictApprove, VerdictRequestChanges))
		default:
			ran[strings.ToLower(p.Check)] = true
		}
	}
	rp := it.Repair
	if rp == nil {
		return append(why, fmt.Sprintf("rule-and-repair wrote no rulings in iteration %d", n))
	}
	if rp.Head != head {
		why = append(why, fmt.Sprintf("rule-and-repair ruled at %s, not at the head triage judged, %s", rp.Head, head))
	}
	for _, r := range rp.Rulings {
		why = append(why, ruled(r, head)...)
	}
	for _, p := range it.Triage.Checks {
		ln, ok := lane(it, p.Check)
		if !ok {
			continue
		}
		for _, f := range ln.Findings {
			if f.ID == "" {
				why = append(why, fmt.Sprintf("a %s finding names no id, so no ruling can answer it", ln.Check))
				continue
			}
			if _, ok := rulingOf(rp, func(r Ruling) bool { return r.rulesFinding(ln.Check, f.ID) }); !ok {
				why = append(why, fmt.Sprintf("%s finding %s is not ruled", ln.Check, f.ID))
			}
		}
	}
	if rp.Pushed != "" {
		why = append(why, fmt.Sprintf("the round pushed %s, which triage has not judged", rp.Pushed))
	}
	for _, a := range asks {
		if !a.Takeable() {
			continue
		}
		if _, ok := rulingOf(rp, func(r Ruling) bool { return r.Ask == a.ID }); !ok {
			why = append(why, fmt.Sprintf("ask %s is open and nothing holds it, and the round did not take it", a.ID))
		}
		for _, c := range a.Checks {
			if !ran[strings.ToLower(c)] {
				why = append(why, fmt.Sprintf("ask %s sends back %s, which did not run at %s", a.ID, c, head))
			}
		}
	}
	for _, m := range slices.Sorted(maps.Keys(run.Iterations)) {
		earlier := run.Iterations[m]
		if m >= n || earlier.Repair == nil {
			continue
		}
		for _, r := range earlier.Repair.Rulings {
			if r.Ruling == RulingMustFix && !git.IsObjectID(r.Commit) {
				why = append(why, fmt.Sprintf("%s was ruled must-fix at %s, in iteration %d, and names no commit that fixes it",
					r.Subject(), earlier.Repair.Head, m))
			}
		}
	}
	return why
}

// ruled is why one ruling at head does not count as ruled, or as ruled and
// passing: a ruling outside the set, a must-fix, a question that names no
// gate, and a finding sent ahead that names no ask the PR waits on for it.
func ruled(r Ruling, head string) []string {
	switch {
	case r.Ask == "" && (r.Check == "" || r.Finding == ""):
		return []string{fmt.Sprintf("a ruling names neither an ask nor a lane's finding (it reads %q)", r.Ruling)}
	case !slices.Contains(rulings, r.Ruling):
		return []string{fmt.Sprintf("%s is ruled %q, which is not a ruling (%s)", r.Subject(), r.Ruling, strings.Join(rulings, ", "))}
	case r.Ruling == RulingMustFix:
		return []string{fmt.Sprintf("%s was ruled must-fix at %s", r.Subject(), head)}
	case r.Ruling == RulingQuestion && r.Gate == "":
		return []string{fmt.Sprintf("%s was put to a person and names no gate", r.Subject())}
	case r.Ruling == RulingAhead && r.Waits == "":
		return []string{fmt.Sprintf("%s was sent ahead and names no ask the PR waits on for it", r.Subject())}
	}
	return nil
}

// lane is the iteration's lane for check, compared without case.
func lane(it *Iteration, check string) (Lane, bool) {
	for _, ln := range it.Lanes {
		if strings.EqualFold(ln.Check, check) {
			return ln, true
		}
	}
	return Lane{}, false
}

// rulingOf is the round's first ruling that match accepts.
func rulingOf(rp *Repair, match func(Ruling) bool) (Ruling, bool) {
	if rp == nil {
		return Ruling{}, false
	}
	for _, r := range rp.Rulings {
		if match(r) {
			return r, true
		}
	}
	return Ruling{}, false
}

// Explain is the account --explain prints of the iteration the verdict
// judged: its head and picks, each lane's verdict and findings, each ruling,
// the push, the asks on the bead, and the verdict with its reasons.
func (v *Verdict) Explain() string {
	var b strings.Builder
	run := v.Run
	fmt.Fprintf(&b, "run %s on %s, first head %s, into %s\n", run.Root, run.PRBead, run.Head, run.Target)
	it := run.Iterations[v.Iteration]
	if it == nil {
		fmt.Fprintf(&b, "iteration %d: nothing written\n", v.Iteration)
	} else {
		fmt.Fprintf(&b, "iteration %d\n", it.N)
		if t := it.Triage; t != nil {
			var picks []string
			for _, p := range t.Checks {
				picks = append(picks, p.Check)
			}
			fmt.Fprintf(&b, "  triage: head %s, material %t, picked %s\n", t.Head, t.Material, orNone(picks))
		} else {
			fmt.Fprintln(&b, "  triage: nothing written")
		}
		for _, ln := range it.Lanes {
			fmt.Fprintf(&b, "  lane %s at %s: %s, %d finding(s)\n", ln.Check, ln.Head, ln.Verdict, len(ln.Findings))
			if ln.NeedsYou != "" {
				fmt.Fprintf(&b, "    needs you: %s\n", oneLine(ln.NeedsYou))
			}
			for _, f := range ln.Findings {
				fmt.Fprintf(&b, "    %s %s %s: %s\n", f.ID, f.Severity, f.Locus, oneLine(f.Message))
			}
		}
		if rp := it.Repair; rp != nil {
			fmt.Fprintf(&b, "  rule-and-repair at %s: %d ruling(s), pushed %s\n", rp.Head, len(rp.Rulings), orNone([]string{rp.Pushed}))
			for _, r := range rp.Rulings {
				fmt.Fprintf(&b, "    %s: %s", r.Subject(), r.Ruling)
				if r.Commit != "" {
					fmt.Fprintf(&b, " by %s", r.Commit)
				}
				if r.Gate != "" {
					fmt.Fprintf(&b, " through %s", r.Gate)
				}
				if r.Reason != "" {
					fmt.Fprintf(&b, ": %s", oneLine(r.Reason))
				}
				fmt.Fprintln(&b)
			}
		} else {
			fmt.Fprintln(&b, "  rule-and-repair: nothing written")
		}
	}
	for _, a := range v.Asks {
		if !a.Open() {
			continue
		}
		fmt.Fprintf(&b, "ask %s (%s, holds %s), checks %s: %s\n", a.ID, a.Status, a.Holds, orNone(a.Checks), oneLine(a.Reason))
	}
	if v.Passed {
		fmt.Fprintf(&b, "passed: iteration %d\n", v.Iteration)
	} else {
		fmt.Fprintf(&b, "not yet: iteration %d\n", v.Iteration)
		for _, r := range v.Reasons {
			fmt.Fprintf(&b, "  - %s\n", r)
		}
	}
	return b.String()
}

func orNone(list []string) string {
	var kept []string
	for _, s := range list {
		if s != "" {
			kept = append(kept, s)
		}
	}
	if len(kept) == 0 {
		return "none"
	}
	return strings.Join(kept, ", ")
}

func oneLine(s string) string { return strings.Join(strings.Fields(s), " ") }
