package pr

import (
	"errors"
	"fmt"
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/conversation"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// The hand-over of a changed head (specs/tk-1tfzr71.165/gas-city-search.md). A
// changed head goes back to the refinery in the record's requeue, and the
// refinery takes it at its next find-work once nothing holds the bead but merge
// holds: a conversation on the PR, or an ask on it, each of which holds the
// PR's merge and not the refinery's take of the head (refinery-find-work.sh).
// Gas City gives the refinery that turn only for a bead nothing holds: an open
// bead is a session's demand only while the store reads it ready
// (workBeadHasAwakeDemand), and core's cascade-nudge-on-blocker-close nudges a
// dependent's assignee only when no other blocker still holds it (its
// still_held), both at gastownhall/gascity 192fa2d394. So while a merge hold is
// open, neither gives the refinery a turn, and the run gives it one: once no
// open withdrawal and no attached review run holds the changed head, and only
// merge holds hold the bead, it wakes and nudges the refinery before the write
// that clears the marker. A wake that does not land keeps the marker, so the
// next run wakes the refinery again.

// handOver hands a changed head that no open withdrawal and no attached review
// run holds to the refinery, in the write that clears the marker, and when only
// merge holds hold the bead it wakes and nudges the refinery first
// (mergeHolds). A read of what holds the bead that fails keeps the marker and
// records why, for the next run to hand the head over. action and detail are
// what the run did with the record before the hand-over, which its outcome
// reports.
func (u *run) handOver(s state, action, detail string) RunOutcome {
	holds, err := u.mergeHolds(s)
	if err != nil {
		return u.handOverLater(s, detail, "what holds the bead did not read, so the next run reads it again: "+err.Error())
	}
	return u.wakeAndSettle(s, holds, action, detail)
}

// wakeAndSettle wakes and nudges the refinery when the merge holds holds alone
// hold the bead s read, then clears the marker of its changed head. A wake that
// does not land keeps the marker and records why, so the next run wakes the
// refinery again.
func (u *run) wakeAndSettle(s state, holds []hold, action, detail string) RunOutcome {
	if len(holds) > 0 {
		if err := u.wakeRefinery(s, holds); err != nil {
			return u.handOverLater(s, detail, fmt.Sprintf("only %s %s the bead, and the refinery's wake did not land, "+
				"so the next run wakes it: %v", holdNames(holds), holdVerb(holds), err))
		}
		detail += fmt.Sprintf("; only %s %s the bead, so the refinery was woken and nudged", holdNames(holds), holdVerb(holds))
	}
	w := u.Ledger.Write(s.id)
	record.Settle(w)
	w.Guard(s.status, s.assignee)
	switch err := u.Ledger.Commit(w); {
	case err == nil:
		return RunOutcome{Bead: s.id, Action: action, Detail: detail + "; the marker is cleared"}
	case errors.Is(err, ledger.ErrGuard):
		return RunOutcome{Bead: s.id, Action: ActMoved,
			Detail: detail + "; the bead moved before the marker cleared, so the next run reads it as it stands"}
	default:
		return RunOutcome{Bead: s.id, Action: ActFailed, Detail: detail + "; the marker did not clear: " + err.Error()}
	}
}

// handOverLater keeps the marker of a changed head the run could not hand over,
// and records why for the next run, which hands it over.
func (u *run) handOverLater(s state, detail, why string) RunOutcome {
	w := u.Ledger.Write(s.id)
	record.Retry(w, "", why, s.now)
	return u.commit(s, w, RunOutcome{Bead: s.id, Action: ActRetry, Detail: detail + "; " + why})
}

// hold is a merge hold on a PR's bead: a wait that holds the PR's merge and not
// the refinery's take of its head, a conversation or an ask on the PR.
type hold struct {
	id, kind string
}

// mergeHolds names the waits that hold the bead s read when every one is a
// merge hold, and is empty otherwise: when nothing holds the bead, Gas City
// gives the refinery its turn, and when another wait holds it, the bead is not
// the refinery's to take yet. What holds the bead is the store's answer through
// waits, as the evaluator reads it (ownWaits), and each wait's row, read here,
// says what the wait is. A conversation has the shape conversation.sh gives
// the scripts, and an ask is review.IsAsk's on the bead's branch, the two
// waits refinery-find-work.sh takes a bead past.
func (u *run) mergeHolds(s state) ([]hold, error) {
	snap, err := waits.Read(u.Ledger, s.id)
	if err != nil {
		return nil, err
	}
	h, err := snap.Holds(s.id)
	if err != nil {
		return nil, err
	}
	if h.Status == waits.Clear || len(h.Waits) == 0 {
		return nil, nil
	}
	var ids []string
	for _, w := range h.Waits {
		if w.Ancestor != "" || w.Type != ledger.EdgeBlocks {
			return nil, nil
		}
		ids = append(ids, w.ID)
	}
	rows, err := u.Ledger.Find(ledger.ByID(ids...).WithClosed())
	if err != nil {
		return nil, err
	}
	var holds []hold
	for _, id := range ids {
		i := slices.IndexFunc(rows, func(r *ledger.Record) bool { return r.ID == id })
		switch {
		case i < 0:
			return nil, nil
		case isConversation(rows[i]):
			holds = append(holds, hold{id: id, kind: "conversation"})
		case rows[i].Status() != "closed" && review.IsAsk(rows[i], s.branch):
			holds = append(holds, hold{id: id, kind: "ask"})
		default:
			return nil, nil
		}
	}
	slices.SortFunc(holds, func(a, b hold) int { return strings.Compare(a.id, b.id) })
	return slices.CompactFunc(holds, func(a, b hold) bool { return a.id == b.id }), nil
}

// isConversation reports whether r is an open conversation: a task whose
// assignee is one a conversation carries, with the one tracks edge that names
// its subject (conversation.IsCandidate and conversation.Shape).
func isConversation(r *ledger.Record) bool {
	if r.Status() == "closed" || !conversation.IsCandidate(strings.ToLower(r.IssueType()), r.Assignee(), r.ID) {
		return false
	}
	edges, err := r.Edges()
	if err != nil {
		return false
	}
	own := make([]conversation.Edge, 0, len(edges))
	for _, e := range edges {
		own = append(own, conversation.Edge{Type: e.Type, DependsOnID: e.ID})
	}
	_, _, ok := conversation.Shape(own)
	return ok
}

// wakeRefinery wakes the refinery and nudges it to take the bead s read, whose
// changed head only the merge holds holds keep from reading ready.
func (u *run) wakeRefinery(s state, holds []hold) error {
	if u.Wake == nil {
		return errors.New("nothing wakes a session here")
	}
	return u.Wake.Wake(u.Refinery, fmt.Sprintf("PR head changed on %s (%s) while %s %s its merge: the new head "+
		"is yours to validate. Run 'gc prime' to check merge queue and begin processing.",
		s.id, firstOf(s.rec.URL, s.rec.ExistingPR, "its PR"), holdNames(holds), holdVerb(holds)))
}

// holdNames names the merge holds, each by its kind and id.
func holdNames(holds []hold) string {
	var names []string
	for _, h := range holds {
		names = append(names, h.kind+" "+h.id)
	}
	switch len(names) {
	case 1:
		return names[0]
	case 2:
		return names[0] + " and " + names[1]
	}
	return strings.Join(names[:len(names)-1], ", ") + " and " + names[len(names)-1]
}

// holdVerb is "hold" for more than one merge hold, else "holds".
func holdVerb(holds []hold) string {
	if len(holds) > 1 {
		return "hold"
	}
	return "holds"
}

// onRuns is the account of a changed head that a review run attached to the
// bead s read still holds from the refinery.
func onRuns(s state) string {
	noun, which := "review run ", "that run ends"
	if len(s.runs) > 1 {
		noun, which = "review runs ", "those runs end"
	}
	return "its changed head waits on " + noun + strings.Join(s.runs, ", ") +
		", attached to the bead, and the landing order hands the head to the refinery once " + which
}
