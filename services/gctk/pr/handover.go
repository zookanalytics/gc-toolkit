package pr

import (
	"context"
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

// The hand-over to the refinery of a changed head, and of a record a dead
// writer left half written (specs/tk-1tfzr71.165/gas-city-search.md,
// specs/tk-1tfzr71.209/gas-city-search.md). A changed head goes to the
// refinery in the write that assigns the bead to it and clears the marker,
// once no open withdrawal and no attached review run holds the head. A bead a
// run is attached to stays assigned to nobody, since Gas City retires a
// workflow at its next claim once its input bead is assigned to an agent
// outside it (workflowInputMembersSettled). A half-written record is sent back
// for its full validation, and it too goes to the refinery in the write that
// assigns the bead to it and clears the marker (revalidate). The refinery can
// take the bead at its next find-work once nothing holds it but merge holds: a
// conversation on the PR, or an ask on it, each of which holds the PR's merge
// and not the refinery's take of the head (refinery-find-work.sh). An
// assignment alone gives a running refinery no turn: an open bead assigned to
// a session is demand that wakes it only while the session is stopped and the
// store reads the bead ready (workBeadHasAwakeDemand, at gastownhall/gascity
// 192fa2d394), and nothing tells a running, idle refinery of the bead
// (docs/deferred-dispatch.md, "A named agent hears through Gas City's
// hand-off"). So whenever the refinery can take the bead, because nothing
// holds it or only merge holds do, the run assigns the bead to the refinery,
// then wakes and nudges the refinery, and only then clears the marker. The
// find-work the wake starts lists the beads the refinery is assigned, so the
// bead is among them by then. A wake that does not land keeps the marker, so
// the next run wakes the refinery again. While another wait holds the bead,
// such as a human gate, the bead is not the refinery's to take yet: the run
// hands the head over in one write and wakes no one, and core's
// cascade-nudge-on-blocker-close nudges the bead's assignee once that blocker
// closes with no other still holding the bead (its still_held, at the same
// commit). A run records no error for a hand-over it could not finish: the
// marker stays on the bead, and the next run finds the same changed head, or
// the same half-written record, and hands it over
// (specs/tk-1tfzr71.149/design.md, section 11).

// handOver hands a changed head that no open withdrawal and no attached review
// run holds to the refinery, in the write that assigns the bead to it and
// clears the marker. When the refinery can take the bead (mergeHolds), the
// bead is assigned to the refinery and the refinery woken and nudged before
// the marker clears (wakeAndSettle). A read of what holds the bead that fails
// keeps the marker, for the next run to hand the head over. action and detail
// are what the run did with the record before the hand-over, which its
// outcome reports. The wake is stopped once ctx, the act's, ends.
func (u *run) handOver(ctx context.Context, s state, action, detail string) RunOutcome {
	holds, takeable, err := u.mergeHolds(s)
	if err != nil {
		return u.handOverLater(s, detail, "what holds the bead did not read, so the next run reads it again: "+err.Error())
	}
	if !takeable {
		return u.settle(s, action, detail)
	}
	return u.wakeAndSettle(ctx, s, headChanged, holds, action, detail)
}

// revalidate sends a record a dead writer left half written back to the
// refinery for its full validation, and requests no merge. Whenever the
// refinery can take the bead (mergeHolds), the write that sends the record
// back keeps the marker, and the bead is assigned to the refinery and the
// refinery woken and nudged before the marker clears (wakeAndSettle), so a wake
// that does not land leaves the next run to send the record back and wake the
// refinery again. A read of what holds the bead that fails keeps the marker as
// well, for the next run to read it again. While another wait holds the bead,
// the write that sends the record back assigns the bead to the refinery and
// clears the marker, and wakes no one. The wake is stopped once ctx, the
// act's, ends.
func (u *run) revalidate(ctx context.Context, s state) RunOutcome {
	detail := "the record was half written: the bead goes back to the refinery, and no merge is requested"
	holds, takeable, unread := u.mergeHolds(s)
	keep := unread != nil || takeable
	to := u.Refinery
	if keep {
		to = ""
	}
	w := u.Ledger.Write(s.id)
	record.Revalidate(w, "Interrupted PR handoff record is incomplete; full refinery validation is required", to)
	done := u.commit(s, w, RunOutcome{Bead: s.id, Action: ActRevalidate, Detail: detail})
	if done.Action != ActRevalidate || !keep {
		return done
	}
	if unread != nil {
		return u.handOverLater(s, detail, "what holds the bead did not read, so the next run reads it again: "+unread.Error())
	}
	return u.wakeAndSettle(ctx, s, recordIncomplete, holds, ActRevalidate, detail)
}

// news is what a hand-over's wake tells the refinery: what came of the PR's
// record, and what is the refinery's to do about it.
type news struct{ what, owed string }

var (
	// headChanged is a PR's head the refinery has not validated.
	headChanged = news{what: "PR head changed", owed: "the new head is yours to validate"}
	// recordIncomplete is a record a dead writer left half written.
	recordIncomplete = news{what: "PR record incomplete", owed: "its full validation is yours"}
)

// wakeAndSettle hands what the bead s read carries for the refinery, which it
// can take now, to the refinery. It first assigns the bead to the refinery
// with the marker kept, then wakes and nudges the refinery with said, so the
// bead is the refinery's when the wake reaches it, and then clears the marker
// (settle). holds are the merge holds on the bead, none when nothing holds it.
// A wake that does not land keeps the marker, so the next run wakes the
// refinery again.
func (u *run) wakeAndSettle(ctx context.Context, s state, said news, holds []hold, action, detail string) RunOutcome {
	if s.assignee != u.Refinery {
		w := u.Ledger.Write(s.id)
		w.Assignee(u.Refinery)
		w.Guard(s.status, s.assignee)
		switch err := u.Ledger.Commit(w); {
		case errors.Is(err, ledger.ErrGuard):
			return RunOutcome{Bead: s.id, Action: ActMoved,
				Detail: detail + "; the bead moved before it was assigned to the refinery, so the next run reads it as it stands"}
		case err != nil:
			return RunOutcome{Bead: s.id, Action: ActFailed, Detail: detail + "; the bead's assignment to the refinery did not land: " + err.Error()}
		}
		s.assignee = u.Refinery
	}
	if err := u.wakeRefinery(ctx, s, said, holds); err != nil {
		return u.handOverLater(s, detail, fmt.Sprintf("%s, and the refinery's wake did not land, so the next run wakes it: %v",
			whatHolds(holds), err))
	}
	return u.settle(s, action, detail+"; "+whatHolds(holds)+", so the refinery was woken and nudged")
}

// settle hands what the bead s read carries for the refinery to it in one
// write, which assigns the bead to it and clears the marker (Settle).
func (u *run) settle(s state, action, detail string) RunOutcome {
	w := u.Ledger.Write(s.id)
	record.Settle(w, u.Refinery)
	w.Guard(s.status, s.assignee)
	switch err := u.Ledger.Commit(w); {
	case err == nil:
		return RunOutcome{Bead: s.id, Action: action, Detail: detail + "; the bead is assigned to the refinery and the marker is cleared"}
	case errors.Is(err, ledger.ErrGuard):
		return RunOutcome{Bead: s.id, Action: ActMoved,
			Detail: detail + "; the bead moved before it was handed to the refinery, so the next run reads it as it stands"}
	default:
		return RunOutcome{Bead: s.id, Action: ActFailed, Detail: detail + "; the hand-over to the refinery did not land: " + err.Error()}
	}
}

// handOverLater leaves the marker on a bead whose changed head or half-written
// record the run could not hand over, and writes nothing, so the next run finds
// the marker and hands the bead over.
func (u *run) handOverLater(s state, detail, why string) RunOutcome {
	return RunOutcome{Bead: s.id, Action: ActRetry, Detail: detail + "; " + why}
}

// hold is a merge hold on a PR's bead: a wait that holds the PR's merge and not
// the refinery's take of its head, a conversation or an ask on the PR.
type hold struct {
	id, kind string
}

// mergeHolds says whether the refinery can take the bead s read now, which it
// can when nothing holds the bead or only merge holds do, and names those merge
// holds, none when nothing holds it. When another wait holds the bead, the
// bead is not the refinery's to take yet. What holds the bead is the store's
// answer through waits, as the evaluator reads it (ownWaits), and each wait's
// row, read here, says what the wait is. A conversation has the shape
// conversation.sh gives the scripts, and an ask is review.IsAsk's on the
// bead's branch with the status open, as refinery-lib.sh's refinery_ask reads
// one: the two waits refinery-find-work.sh takes a bead past.
func (u *run) mergeHolds(s state) (holds []hold, takeable bool, err error) {
	snap, err := waits.Read(u.Ledger, s.id)
	if err != nil {
		return nil, false, err
	}
	h, err := snap.Holds(s.id)
	if err != nil {
		return nil, false, err
	}
	if h.Status == waits.Clear || len(h.Waits) == 0 {
		return nil, true, nil
	}
	var ids []string
	for _, w := range h.Waits {
		if w.Ancestor != "" || w.Type != ledger.EdgeBlocks {
			return nil, false, nil
		}
		ids = append(ids, w.ID)
	}
	rows, err := u.Ledger.Find(ledger.ByID(ids...).WithClosed())
	if err != nil {
		return nil, false, err
	}
	for _, id := range ids {
		i := slices.IndexFunc(rows, func(r *ledger.Record) bool { return r.ID == id })
		switch {
		case i < 0:
			return nil, false, nil
		case isConversation(rows[i]):
			holds = append(holds, hold{id: id, kind: "conversation"})
		case rows[i].Status() == "open" && review.IsAsk(rows[i], s.branch):
			holds = append(holds, hold{id: id, kind: "ask"})
		default:
			return nil, false, nil
		}
	}
	slices.SortFunc(holds, func(a, b hold) int { return strings.Compare(a.id, b.id) })
	return slices.CompactFunc(holds, func(a, b hold) bool { return a.id == b.id }), true, nil
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

// wakeRefinery wakes the refinery and nudges it to take the bead s read, telling
// it said, naming the merge holds that hold the PR's merge when there are any,
// stopped once ctx ends.
func (u *run) wakeRefinery(ctx context.Context, s state, said news, holds []hold) error {
	if u.Wake == nil {
		return errors.New("nothing wakes a session here")
	}
	while := ""
	if len(holds) > 0 {
		while = fmt.Sprintf(" while %s %s its merge", holdNames(holds), holdVerb(holds))
	}
	return u.Wake.Wake(ctx, u.Refinery, fmt.Sprintf("%s on %s (%s)%s: %s. Run 'gc prime' to check merge "+
		"queue and begin processing.", said.what, s.id, firstOf(s.rec.URL, s.rec.ExistingPR, "its PR"), while, said.owed))
}

// whatHolds says what holds a bead the refinery can take: only its merge holds,
// or nothing.
func whatHolds(holds []hold) string {
	if len(holds) == 0 {
		return "nothing holds the bead"
	}
	return fmt.Sprintf("only %s %s the bead", holdNames(holds), holdVerb(holds))
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
