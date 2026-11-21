package pr

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"strings"
	"time"

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
// so the order keeps no list of its own. A run that ended without a result is
// poured again. When the last two runs at the validated head both ended
// without one, counting only runs that ended after the bead's last
// review-run-failed gate closed, the run asks a person through a gate under
// that key instead.

// Runs pours a review run: the formula, as a sub-workflow attached to the
// bead, with its vars. It returns the run's root.
type Runs interface {
	Pour(formula, bead string, vars map[string]string) (string, error)
}

// runFailedKey keys the human gate the order files when the last two runs at
// one head ended without a result.
const runFailedKey = "review-run-failed"

// pourReserve is how much of its bound an act must have left to start a review
// run's pour. The pour is the one call an act does not stop: gc formula cook
// --attach makes the run before it adds the edge that attaches it, and a cook
// stopped between the two leaves a run whose steps the pools take and that the
// order never reads, so the next run pours a second. A pour is a few store
// calls, which take seconds, so a pour started with this much left ends inside
// the bound. One that does not, such as a cook the store keeps waiting, holds
// the record lock until it ends or the order's timeout ends the run.
const pourReserve = 10 * time.Second

// admit decides the review run the record s read is owed: the pour, or the
// gate that asks a person once two runs at its head ended without a result,
// or why none is poured. It returns false when the bead is owed no run, so the
// caller reports the evaluator's answer. ans is the evaluator's answer at the
// validated head, on the act's own read of the PR, and asks the asks on the
// bead. A run owed is held off, as checked, only while a run, a gate or
// another writer holds the branch, and a read that did not answer, or a pour
// this run cannot make, is a retry (ActRetry).
func (u *run) admit(s state, ans Answer, asks []review.Ask) (plan, bool) {
	var takeable []string
	for _, a := range asks {
		if a.Takeable() {
			takeable = append(takeable, a.ID)
		}
	}
	unreviewed := slices.ContainsFunc(ans.Conditions, func(c Condition) bool { return c.Kind == KindReview })
	if !unreviewed && len(takeable) == 0 {
		return plan{}, false
	}
	why := fmt.Sprintf("no review result passed at %s into %s", s.rec.Head, s.rec.Target)
	if !unreviewed {
		why = "ask " + strings.Join(takeable, ", ") + " is open, and nothing holds it"
	}
	checked := func(detail string) (plan, bool) { return none(s, ActChecked, detail), true }
	retry := func(detail string) (plan, bool) {
		return none(s, ActRetry, detail+"; the next run decides again"), true
	}
	if len(s.runs) > 0 {
		return checked("review run " + strings.Join(s.runs, ", ") + " is attached, and the bead waits on it: " + why)
	}
	if by := heldBy(s); by != "" {
		return checked("no review run is poured while " + by + ": " + why)
	}
	writers, err := u.writers(s)
	if err != nil {
		return retry("no review run is poured, because the beads on " + s.branch + " did not read: " + err.Error())
	}
	if len(writers) > 0 {
		return checked(fmt.Sprintf("no review run is poured while %s works %s: %s", strings.Join(writers, ", "), s.branch, why))
	}
	failed, err := u.failedRuns(s)
	if err != nil {
		return retry("no review run is poured, because how its earlier runs ended did not read: " + err.Error())
	}
	if len(failed) == 2 {
		return doing(func(ctx context.Context, c carriedOut) RunOutcome { return u.runFailed(ctx, s, failed, c.note) }), true
	}
	vars, err := reviewVars(u.Refinery)
	if err != nil {
		return retry("no review run is poured: " + err.Error())
	}
	vars["pr_bead"], vars["head"], vars["target"], vars["branch"] = s.id, s.rec.Head, s.rec.Target, s.branch
	if u.Runs == nil {
		return retry("no review run is poured, because nothing pours one here: " + why)
	}
	return doing(func(ctx context.Context, c carriedOut) RunOutcome {
		if left, ok := ctx.Deadline(); ok && time.Until(left) < pourReserve {
			return RunOutcome{Bead: s.id, Action: ActLeft, Detail: withNote(fmt.Sprintf("the act had less than the %s "+
				"a review run's pour reserves left of its bound, so the next run pours the run at %s", pourReserve,
				s.rec.Head), c.note)}
		}
		root, err := u.Runs.Pour(reviewFormula, s.id, vars)
		if err != nil {
			return RunOutcome{Bead: s.id, Action: ActRetry, Detail: withNote(fmt.Sprintf(
				"the review run at %s did not pour, and the next run pours it: %v", s.rec.Head, err), c.note)}
		}
		return RunOutcome{Bead: s.id, Action: ActPoured, Detail: withNote(fmt.Sprintf(
			"review run %s poured at %s into %s, attached to the bead: %s", root, s.rec.Head, s.rec.Target, why), c.note)}
	}), true
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
	rows, err := s.reads.Find(record.OnBranch(s.branch))
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
		e, err := review.Ended(s.reads, c.id)
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
// pours one more.
func (u *run) runFailed(ctx context.Context, s state, failed []review.Ending, note string) RunOutcome {
	var parts []string
	for _, e := range failed {
		parts = append(parts, fmt.Sprintf("%s, where %s", e.Root, e.How))
	}
	message := fmt.Sprintf("The last two review runs of %s at its validated head %s into %s both ended without a result: %s. "+
		"The landing order pours a run that ends without a result again once, so this is the city's machinery failing at "+
		"this head, not a ruling the PR (%s) waits on. Look at the two runs and fix what stopped them, then clear this "+
		"gate, and the landing order pours one more run.", s.id, s.rec.Head, s.rec.Target, strings.Join(parts, "; and "), s.rec.URL)
	if err := u.Gates.File(ctx, s.id, runFailedKey, message); err != nil {
		return RunOutcome{Bead: s.id, Action: ActRetry, Detail: withNote(
			fmt.Sprintf("%s: the human gate did not file; the next run files it: %v", runFailedKey, err), note)}
	}
	return RunOutcome{Bead: s.id, Action: ActExcepted, Detail: withNote(fmt.Sprintf(
		"%s: review runs %s and %s ended without a result at %s, so a person is asked before another run", runFailedKey,
		failed[0].Root, failed[1].Root, s.rec.Head), note)}
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
