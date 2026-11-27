package review

import (
	"fmt"
	"strings"
)

// A review run goes on while its must-fix findings fall, and comes to a person
// once they stop falling (specs/tk-vdyedm5/design.md). A round's account counts
// what its steps wrote: the lane findings the round ruled must-fix, and each of
// its findings that the round's ruler marked as restating one an earlier round
// of the run fixed. A person's ask is a request of their own, not a finding of
// the review, so it counts for nothing here, though a round that fixes one goes
// on to the next.
//
// The rule forces a question at round n when:
//   - the round ruled must-fix findings, no fewer than round n-2 did, and
//     round n-2 ruled some: its must-fix findings have not fallen over two
//     rounds; or
//   - one finding has come back a second time: findings of two rounds of the
//     run restate it after fixes, directly or through each other, the later
//     round n. Two lanes that raise it again in one round are one return.
//
// A fresh look, a step on a session that is never the round's ruler, is due
// at a round that goes on, one that ruled something must-fix or pushed, when
// the round is the third or every third after, when the rule forces a question
// there, or when it is the run's last round by its bound. A look the rule
// forces stops the run for a person's answer unless it names rules that changed
// on the PR's target as the cause, and a look at the last round stops it.

// Round is one round's account: its iteration, the head it judged, the lane
// findings it ruled must-fix, whether it goes on, and each earlier finding that
// came back in it after a fix, by the first finding of its chain, once each.
type Round struct {
	N       int
	Head    string
	MustFix int
	GoesOn  bool
	Returns []FindingRef
}

// Account is a run's rounds up to its last, and the rule's reading at the last:
// why it forces a question, "" when it does not, whether the last round is the
// run's last by its bound, and whether a fresh look is due there.
type Account struct {
	Rounds []Round
	Forced string
	Last   bool
	Due    bool
}

// Converge is the account of the run's rounds up to iteration n, each round
// that wrote its rulings. A round that wrote none yet counts nothing.
func Converge(run *Run, n int) Account {
	var a Account
	first := map[FindingRef]FindingRef{}
	back, at := map[FindingRef]int{}, map[FindingRef]int{}
	var latest []FindingRef
	for m := 1; m <= n; m++ {
		it := run.Iterations[m]
		if it == nil || it.Triage == nil || it.Repair == nil {
			continue
		}
		r := Round{N: m, Head: it.Triage.Head, GoesOn: it.Repair.Pushed != ""}
		for _, ru := range it.Repair.Rulings {
			if ru.Ruling == RulingMustFix {
				r.GoesOn = true
				if ru.Ask == "" {
					r.MustFix++
				}
			}
			if ru.Restates == nil || ru.Ask != "" {
				continue
			}
			ref := ru.Restates.key()
			root, ok := first[ref]
			if !ok {
				root = ref
			}
			first[FindingRef{Iteration: m, Check: ru.Check, Finding: ru.Finding}.key()] = root
			if at[root] == m {
				continue
			}
			at[root] = m
			back[root]++
			r.Returns = append(r.Returns, root)
			if m == n {
				latest = append(latest, root)
			}
		}
		a.Rounds = append(a.Rounds, r)
	}
	cur, ok := a.round(n)
	if !ok {
		return a
	}
	if was, ok := a.round(n - 2); ok && cur.MustFix > 0 && was.MustFix > 0 && cur.MustFix >= was.MustFix {
		a.Forced = fmt.Sprintf("its must-fix findings have not fallen over two rounds: %d at round %d, %d at round %d",
			was.MustFix, was.N, cur.MustFix, cur.N)
	}
	for _, root := range latest {
		if back[root] >= 2 && a.Forced == "" {
			a.Forced = fmt.Sprintf("%s has come back a second time after fixes", root)
		}
	}
	a.Last = run.MaxAttempts > 0 && n >= run.MaxAttempts
	a.Due = cur.GoesOn && (n%3 == 0 || a.Forced != "" || a.Last)
	return a
}

// key is the reference as the account matches it: the check without case, as
// a lane's check matches triage's pick, and the finding's id as written.
func (f FindingRef) key() FindingRef {
	return FindingRef{Iteration: f.Iteration, Check: strings.ToLower(f.Check), Finding: f.Finding}
}

// round is the account of iteration n, when it wrote its rulings.
func (a Account) round(n int) (Round, bool) {
	for _, r := range a.Rounds {
		if r.N == n {
			return r, true
		}
	}
	return Round{}, false
}

// Counts is each round's must-fix count, in order, as in "5, 2, 1".
func (a Account) Counts() string {
	var out []string
	for _, r := range a.Rounds {
		out = append(out, fmt.Sprint(r.MustFix))
	}
	return strings.Join(out, ", ")
}

// Line is the account's one line for its last round's comment: the round's
// must-fix findings with every round's count, how the count moved from the
// round before, the findings that came back, and what happens next.
func (a Account) Line() string {
	if len(a.Rounds) == 0 {
		return ""
	}
	cur := a.Rounds[len(a.Rounds)-1]
	var b strings.Builder
	fmt.Fprintf(&b, "Round %d: %s", cur.N, mustFix(cur.MustFix))
	if len(a.Rounds) > 1 {
		fmt.Fprintf(&b, " (%s by round)", a.Counts())
		if prev, ok := a.round(cur.N - 1); ok {
			fmt.Fprintf(&b, ", %s", trend(prev.MustFix, cur.MustFix))
		}
	}
	if k := len(cur.Returns); k > 0 {
		fmt.Fprintf(&b, ", %d back after a fix", k)
	}
	switch {
	case !cur.GoesOn:
		b.WriteString(", and the round pushed nothing.")
	case a.Last:
		fmt.Fprintf(&b, ". This is the run's last round by its bound, so a fresh look puts the review to you.")
	case a.Forced != "":
		fmt.Fprintf(&b, ". The review is not converging, as %s, so a fresh look reads why and puts it to you "+
			"unless rules that changed on its target explain the counts.", a.Forced)
	case a.Due:
		b.WriteString(". A fresh look at the whole review decides whether it goes on.")
	default:
		fmt.Fprintf(&b, ", so the review goes on to round %d.", cur.N+1)
	}
	return b.String()
}

// mustFix is a count of must-fix findings in words.
func mustFix(n int) string {
	switch n {
	case 0:
		return "no must-fix finding"
	case 1:
		return "1 must-fix finding"
	}
	return fmt.Sprintf("%d must-fix findings", n)
}

// trend is how a round's count moved from the round before's.
func trend(was, now int) string {
	switch {
	case now < was:
		return "falling"
	case now > was:
		return "rising"
	}
	return "level"
}
