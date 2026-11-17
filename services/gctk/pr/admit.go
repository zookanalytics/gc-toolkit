package pr

import (
	"errors"
	"fmt"
	"slices"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
)

// The landing order admits the review run (specs/tk-1tfzr71.108/design.md,
// sections 1 and 7). For a PR open at the head the refinery validated, the run
// pours one review run, attached to the bead that owns the PR, when the
// evaluator finds no passed result there or the bead carries an ask a run can
// take, and only while nothing else writes the branch and no person is asked:
// no run is attached, no open bead other than an ask names the branch, and no
// human gate holds it. A conversation on the PR holds its merge and nothing
// else, so runs are poured while one is open, whether it waits in the
// operator's queue, a sitting holds it or its sitting stays: the evaluator
// reads the conversation's blocks edge as a wait of the bead's own, so the PR
// merges only once the conversation closes. The pour runs under the record
// lock the run holds for the record, so two runs that overlap pour one review
// run.
//
// The runs attached to a bead are its blocks edges onto roots of the review
// formula, open or closed, and each root carries the vars it was poured with,
// so the order keeps no list of its own. The pour gives every bead it created
// the bead's priority, then the bead its blocks edge onto the root. A run whose
// pr_bead var names the bead and that no edge of the bead names, live or ended,
// as a pour that stopped before its edge landed leaves it, gets that edge from
// the next run before that run decides anything of the record (attach), so it
// holds the bead as any attached run does and counts toward how the bead's runs
// ended. A run that ended without a result is poured again. When the last two
// runs at the validated head both ended without one, counting only runs that
// ended after the bead's last review-run-failed gate closed, the run asks a
// person through a gate under that key instead.

// Runs pours a review run: the formula, as a workflow of its own, with its
// vars.
type Runs interface {
	Pour(formula string, vars map[string]string) (Poured, error)
}

// Poured is what a pour created: the run's root, and every bead it created, the
// root among them.
type Poured struct {
	Root  string
	Beads []string
}

// runFailedKey keys the human gate the order files when the last two runs at
// one head ended without a result.
const runFailedKey = "review-run-failed"

// runOutsideKey keys the human gate the order files when the bead's store does
// not hold the root of a run it poured, so no edge can hold the bead on it.
const runOutsideKey = "review-run-outside-store"

// admit pours the review run the record s read is owed, or files the gate
// that asks a person once two runs at its head ended without a result, and
// says what it did. It returns false when the bead is owed no run, so the
// caller reports the evaluator's answer. ans is the evaluator's answer at the
// validated head and gr the GitHub read it made, which each write carries when
// it made one, asks the asks on the bead, and note what the run did with the
// record's withdrawals.
func (u *run) admit(s state, p *gh.PullRequest, ans Answer, gr *GitHubRead, asks []review.Ask, note string) (RunOutcome, bool) {
	var takeable []string
	for _, a := range asks {
		if a.Takeable() {
			takeable = append(takeable, a.ID)
		}
	}
	unreviewed := slices.ContainsFunc(ans.Conditions, func(c Condition) bool { return c.Kind == KindReview })
	if !unreviewed && len(takeable) == 0 {
		return RunOutcome{}, false
	}
	why := fmt.Sprintf("no review result passed at %s into %s", s.rec.Head, s.rec.Target)
	if !unreviewed {
		why = "ask " + strings.Join(takeable, ", ") + " is open, and nothing holds it"
	}
	checked := func(detail string) (RunOutcome, bool) {
		w := u.Ledger.Write(s.id)
		record.Checked(w, "open", s.now)
		if gr != nil {
			githubReadKey.Set(w, gr)
		}
		return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActChecked, Detail: withNote(detail, note)}), true
	}
	if len(s.runs) > 0 {
		return checked("review run " + strings.Join(s.runs, ", ") + " is attached, and the bead waits on it: " + why)
	}
	if by := heldBy(s); by != "" {
		return checked("no review run is poured while " + by + ": " + why)
	}
	writers, err := u.writers(s)
	if err != nil {
		return checked("no review run is poured, because the beads on " + s.branch + " did not read; the next run reads them: " + err.Error())
	}
	if len(writers) > 0 {
		return checked(fmt.Sprintf("no review run is poured while %s works %s: %s", strings.Join(writers, ", "), s.branch, why))
	}
	retry := func(detail string) (RunOutcome, bool) {
		w := u.Ledger.Write(s.id)
		record.Retry(w, "open", detail, s.now)
		if gr != nil {
			githubReadKey.Set(w, gr)
		}
		return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActRetry, Detail: withNote(detail, note)}), true
	}
	failed, err := u.failedRuns(s)
	if err != nil {
		return checked("no review run is poured, because how its earlier runs ended did not read; the next run reads it: " + err.Error())
	}
	if len(failed) == 2 {
		return u.runFailed(s, p, failed, gr, note), true
	}
	vars, err := reviewVars(u.Refinery)
	if err != nil {
		return checked("no review run is poured: " + err.Error())
	}
	vars["pr_bead"], vars["head"], vars["target"], vars["branch"] = s.id, s.rec.Head, s.rec.Target, s.branch
	if u.Runs == nil {
		return checked("no review run is poured, because nothing pours one here: " + why)
	}
	poured, err := u.Runs.Pour(reviewFormula, vars)
	if err != nil {
		return retry(fmt.Sprintf("the review run at %s did not pour, and the next run pours it: %v", s.rec.Head, err))
	}
	ranked := ""
	if err := u.Ledger.Prioritize(s.row.Priority(), poured.Beads...); err != nil {
		ranked = fmt.Sprintf(", and its beads keep the formula's priority, as the bead's did not land on them: %v", err)
	}
	if err := u.Ledger.AddBlocker(s.id, poured.Root); errors.Is(err, ledger.ErrNotHeld) {
		return u.runOutside(s, poured.Root, gr, note), true
	} else if err != nil {
		return retry(fmt.Sprintf("review run %s poured at %s, and the bead's edge onto it did not land; the next run attaches it: %v", poured.Root, s.rec.Head, err))
	}
	w := u.Ledger.Write(s.id)
	record.Checked(w, "open", s.now)
	if gr != nil {
		githubReadKey.Set(w, gr)
	}
	return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActPoured, Detail: withNote(fmt.Sprintf(
		"review run %s poured at %s into %s, attached to the bead%s: %s", poured.Root, s.rec.Head, s.rec.Target, ranked, why), note)}), true
}

// unattached reads the runs of the review formula, live and closed, whose
// pr_bead var names the bead s read and that no blocks edge of the bead names,
// in id order, leaving out a shadow run, which writes nothing outside itself.
func (u *run) unattached(s state) ([]*ledger.Record, error) {
	rows, err := u.Ledger.Find(ledger.Matching(runPRBeadVar, s.id).WithClosed())
	if err != nil {
		return nil, err
	}
	var out []*ledger.Record
	for _, r := range rows {
		if !isReviewRoot(r) || slices.ContainsFunc(s.blockers, func(b *ledger.Record) bool { return b.ID == r.ID }) {
			continue
		}
		shadow, _, err := runShadowVar.Get(r)
		if err != nil {
			return nil, err
		}
		if strings.TrimSpace(shadow) != "true" {
			out = append(out, r)
		}
	}
	slices.SortFunc(out, func(a, b *ledger.Record) int { return strings.Compare(a.ID, b.ID) })
	return out, nil
}

// attach gives the bead s read its blocks edge onto each of strays, the runs
// unattached found, before the run decides anything a run attached to the bead
// holds: a changed head's hand-over, a draft's ready mark, a merge request, a
// retired PR's close and a pour. Each run it attaches joins s's blockers, and a
// live one its runs, as a read of the bead after the edge finds them. It
// returns its account of the runs it attached, for the outcome. An edge that
// does not land writes the retry, the next run attaches the run, and ok is
// false.
func (u *run) attach(s *state, strays []*ledger.Record) (note string, out RunOutcome, ok bool) {
	var ids []string
	for _, r := range strays {
		if err := u.Ledger.AddBlocker(s.id, r.ID); err != nil {
			why := fmt.Sprintf("review run %s was poured for the bead with no edge onto it, and the edge did not land; the next run attaches it: %v", r.ID, err)
			w := u.Ledger.Write(s.id)
			record.Retry(w, "", why, s.now)
			return "", u.commit(*s, w, RunOutcome{Bead: s.id, Action: ActRetry, Detail: why}), false
		}
		s.blockers, ids = append(s.blockers, r), append(ids, r.ID)
		if r.Status() != "closed" {
			s.runs = append(s.runs, r.ID)
		}
	}
	if len(ids) == 0 {
		return "", RunOutcome{}, true
	}
	return fmt.Sprintf("review run %s had no edge of the bead onto it, and has that edge now", strings.Join(ids, ", ")), RunOutcome{}, true
}

// runOutside files the gate that asks a person about the run at root, which the
// order poured and whose root the bead's store does not hold, so the bead
// cannot wait on it and no later run can see it. The gate holds the bead, so no
// other run is poured until a person clears it. Each write carries gr, the
// GitHub read the check made, when it made one.
func (u *run) runOutside(s state, root string, gr *GitHubRead, note string) RunOutcome {
	message := fmt.Sprintf("Review run %s was poured for %s at its validated head %s into %s, and %s's store does not "+
		"hold the run's root, so the bead cannot wait on the run and the landing order cannot see it. The landing order "+
		"pours no other run while this gate is open. Cancel the run, and clear this gate once the city pours a review "+
		"run into %s's store, since a run poured before then lands where this one did.", root, s.id, s.rec.Head,
		s.rec.Target, s.id, s.id)
	w := u.Ledger.Write(s.id)
	if err := u.Gates.File(s.id, runOutsideKey, message); err != nil {
		why := fmt.Sprintf("%s: review run %s's root is not in the bead's store, and the human gate did not file; the next run files it: %v", runOutsideKey, root, err)
		record.Retry(w, "open", why, s.now)
		if gr != nil {
			githubReadKey.Set(w, gr)
		}
		return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActRetry, Detail: withNote(why, note)})
	}
	record.Checked(w, "open", s.now)
	if gr != nil {
		githubReadKey.Set(w, gr)
	}
	return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActExcepted, Detail: withNote(fmt.Sprintf(
		"%s: review run %s poured at %s, and the bead's store does not hold its root, so a person is asked before another run",
		runOutsideKey, root, s.rec.Head), note)})
}

// heldBy names the open human gate on the bead s read, which keeps the order
// from pouring a run on it, because a gate asks a person and the next run
// starts from the answer. It is empty when no gate is open on the bead. An
// open conversation on the PR is no such hold, since it holds the PR's merge
// and nothing else.
func heldBy(s state) string {
	for _, b := range s.blockers {
		if b.Status() != "closed" && isHumanGate(b) {
			return fmt.Sprintf("human gate %s (%s) holds the bead", b.ID, firstOf(b.AwaitID(), "no key"))
		}
	}
	return ""
}

// isHumanGate reports whether b is a human gate: Gas City's native bead for a
// wait a person must clear, the rule prstatus.IsHumanGate states.
func isHumanGate(b *ledger.Record) bool {
	return strings.EqualFold(b.IssueType(), "gate") && b.AwaitType() == "human"
}

// writers names the open beads other than the bead s read and its asks that
// name its branch, each of them work of its own on the branch, such as a
// rework child.
func (u *run) writers(s state) ([]string, error) {
	rows, err := u.Ledger.Find(record.OnBranch(s.branch))
	if err != nil {
		return nil, err
	}
	var out []string
	for _, r := range rows {
		if r.ID == s.id || r.Status() == "closed" || review.IsAsk(r, s.branch) {
			continue
		}
		out = append(out, r.ID)
	}
	slices.Sort(out)
	return out, nil
}

// failedRuns is the last two runs attached to the bead s read at its validated
// head and target, when both ended without a result, counting only runs that
// closed after the bead's last review-run-failed gate closed. It is empty
// otherwise.
func (u *run) failedRuns(s state) ([]review.Ending, error) {
	since := time.Time{}
	for _, b := range s.blockers {
		if !isHumanGate(b) || b.AwaitID() != runFailedKey || b.Status() != "closed" {
			continue
		}
		at, err := closedTime(b)
		if err != nil {
			return nil, err
		}
		if at.After(since) {
			since = at
		}
	}
	type ended struct {
		id string
		at time.Time
	}
	var closed []ended
	for _, b := range s.blockers {
		if b.Status() != "closed" || !isReviewRoot(b) {
			continue
		}
		head, _, err := runHeadVar.Get(b)
		if err != nil {
			return nil, err
		}
		target, _, err := runTargetVar.Get(b)
		if err != nil {
			return nil, err
		}
		if strings.TrimSpace(head) != s.rec.Head || strings.TrimSpace(target) != s.rec.Target {
			continue
		}
		at, err := closedTime(b)
		if err != nil {
			return nil, err
		}
		if at.After(since) {
			closed = append(closed, ended{b.ID, at})
		}
	}
	if len(closed) < 2 {
		return nil, nil
	}
	slices.SortStableFunc(closed, func(a, b ended) int {
		if c := a.at.Compare(b.at); c != 0 {
			return c
		}
		return strings.Compare(a.id, b.id)
	})
	var out []review.Ending
	for _, c := range closed[len(closed)-2:] {
		e, err := review.Ended(u.Ledger, c.id)
		if err != nil {
			return nil, err
		}
		if e.Result {
			return nil, nil
		}
		out = append(out, e)
	}
	return out, nil
}

// closedTime is when b closed, which a closed bead's row carries.
func closedTime(b *ledger.Record) (time.Time, error) {
	at, err := time.Parse(time.RFC3339Nano, b.ClosedAt())
	if err != nil {
		return time.Time{}, &ledger.ReadError{ID: b.ID, Reason: fmt.Sprintf("its close time %q does not read as a time", b.ClosedAt())}
	}
	return at, nil
}

// runFailed files the gate that asks a person to look at the two runs at the
// validated head that ended without a result. The gate holds the bead, so no
// run is poured until a person clears it, and then the next run of the order
// pours one more. Each write carries gr, the GitHub read the check made, when
// it made one.
func (u *run) runFailed(s state, p *gh.PullRequest, failed []review.Ending, gr *GitHubRead, note string) RunOutcome {
	var parts []string
	for _, e := range failed {
		parts = append(parts, fmt.Sprintf("%s, where %s", e.Root, e.How))
	}
	message := fmt.Sprintf("The last two review runs of %s at its validated head %s into %s both ended without a result: %s. "+
		"The landing order pours a run that ends without a result again once, so this is the city's machinery failing at "+
		"this head, not a ruling the PR (%s) waits on. Look at the two runs and fix what stopped them, then clear this "+
		"gate, and the landing order pours one more run.", s.id, s.rec.Head, s.rec.Target, strings.Join(parts, "; and "), p.URL)
	if err := u.Gates.File(s.id, runFailedKey, message); err != nil {
		w := u.Ledger.Write(s.id)
		why := fmt.Sprintf("%s: the human gate did not file; the next run files it: %v", runFailedKey, err)
		record.Retry(w, "open", why, s.now)
		if gr != nil {
			githubReadKey.Set(w, gr)
		}
		return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActRetry, Detail: withNote(why, note)})
	}
	w := u.Ledger.Write(s.id)
	record.Checked(w, "open", s.now)
	if gr != nil {
		githubReadKey.Set(w, gr)
	}
	return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActExcepted, Detail: withNote(fmt.Sprintf(
		"%s: review runs %s and %s ended without a result at %s, so a person is asked before another run", runFailedKey,
		failed[0].Root, failed[1].Root, s.rec.Head), note)})
}

// reviewVars are the vars a review run is poured with beyond the record's:
// the pools its steps route to and the binding the pack is imported under, all
// read off the refinery's address, <rig>/<binding>refinery, as
// refinery-reconcile.sh reads the pools a review and a fix go to. A cooked
// formula takes only the vars it is given, so the binding is passed too, and an
// address that names no binding pours nothing, since the run's steps name the
// pack's scripts by it.
func reviewVars(refinery string) (map[string]string, error) {
	rig, name, ok := strings.Cut(refinery, "/")
	binding, named := strings.CutSuffix(name, "refinery")
	if !ok || rig == "" || !named || strings.Contains(name, "/") || !strings.HasSuffix(binding, ".") {
		return nil, fmt.Errorf("the refinery's address %q names no <rig>/<binding>.refinery, so the review run's pools and the binding its steps call the pack's scripts by cannot be named", refinery)
	}
	return map[string]string{
		"review_target":  rig + "/" + binding + "polecat-codex",
		"repair_target":  rig + "/" + binding + "polecat",
		"binding_prefix": binding,
	}, nil
}

// isReviewRoot reports whether b is the root of a review run: a workflow
// whose formula is the review formula.
func isReviewRoot(b *ledger.Record) bool {
	kind, _, kerr := kindKey.Get(b)
	name, _, nerr := formulaNameKey.Get(b)
	return errors.Join(kerr, nerr) == nil && strings.TrimSpace(kind) == "workflow" && strings.TrimSpace(name) == reviewFormula
}
