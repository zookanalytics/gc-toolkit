package pr

import (
	"context"
	"fmt"
	"slices"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/gate"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// A stay's gate (services/gctk/gate) holds a conversation until the work it
// awaits comes back: the landing order is its only closer
// (specs/tk-ai367om/design.md, sections 2 to 4). Where it decides an open PR at
// its head, for each open gate whose work is the PR's bead, once the PR's own
// status is needs-review or merging, it puts the hold of each conversation
// that waits on the gate on the PR, then resolves the gate, and requests
// nothing else of the PR in that pass. It requests no merge while such a gate
// is open, and lists the gates again at its last read before a merge request.
// In every run it resolves each open gate whose work has closed.

// Status is a PR's own status as the status owner reads it (prstatus.Own),
// which imports this package, so the caller hands it over as it hands Labels.
type Status interface {
	// Own returns the own status of the PR bead owns, read through pass:
	// needs-attention, working, merging or needs-review.
	Own(pass *ledger.Ledger, bead string) (string, error)
}

// The own statuses at which a gctk:needs-review gate resolves.
const (
	ownNeedsReview = "needs-review"
	ownMerging     = "merging"
)

// openGates is the open gates of the pack's types whose work is bead, read
// through l, from one unbounded list of the store's open gates.
func openGates(l *ledger.Ledger, bead string) ([]gate.Gate, error) {
	rows, err := l.Find(ledger.Typed("gate"))
	if err != nil {
		return nil, err
	}
	var out []gate.Gate
	for _, g := range gate.Open(rows) {
		if g.Work == bead {
			out = append(out, g)
		}
	}
	return out, nil
}

// decideGates is the stay's step where a run decides an open PR at its head,
// on the answer the evaluator gave there. ok is false when no open gate of the
// pack's types names the bead, or when one does and the PR's own status is
// neither needs-review nor merging, which leaves the PR to the rest of the
// decision: the PR is not ready then, so no merge is requested.
func (u *run) decideGates(s state, f seen, ans Answer) (plan, bool) {
	gates, err := openGates(s.reads, s.id)
	if err != nil {
		return none(s, ActRetry, "the store's open gates did not read, so no merge is requested; the next run decides again: "+err.Error()), true
	}
	if len(gates) == 0 {
		return plan{}, false
	}
	if u.Status == nil {
		return u.withCarry(s, f, none(s, ActChecked, fmt.Sprintf("the open gate %s names the bead, and nothing reads the PR's "+
			"own status here, so no merge is requested", gates[0].ID))), true
	}
	own, err := u.Status.Own(s.reads, s.id)
	if err != nil {
		return none(s, ActRetry, "the PR's own status did not read, so no merge is requested; the next run decides again: "+err.Error()), true
	}
	if own != ownNeedsReview && own != ownMerging {
		if ans.Ready {
			return u.withCarry(s, f, none(s, ActChecked, fmt.Sprintf("the open gate %s names the bead and the PR reads %s in its "+
				"own right, so no merge is requested", gates[0].ID, own))), true
		}
		return plan{}, false
	}
	head := f.pr.HeadRefOid
	if ans.Head != "" {
		head = ans.Head
	}
	return u.withCarry(s, f, doing(func(_ context.Context, c carriedOut) RunOutcome {
		return u.returnStay(s, gates, own, head, c)
	})), true
}

// returnStay puts the hold of each open or in-progress bead that waits on each
// gate, the conversation, on the PR's bead, then resolves the gate with the own
// status the PR read at head. An edge already there is a no-op. A read or a
// write that does not land leaves that gate open and ends the act, and the next
// run tries again.
func (u *run) returnStay(s state, gates []gate.Gate, own, head string, c carriedOut) RunOutcome {
	retry := func(why string) RunOutcome {
		return RunOutcome{Bead: s.id, Action: ActRetry, Detail: withNote(why+", so the gate stays open and no merge is requested; "+
			"the next run tries again", c.note)}
	}
	var held, resolved []string
	for _, g := range gates {
		waiting, err := u.Ledger.Dependents(g.ID, ledger.EdgeBlocks)
		if err != nil {
			return retry(fmt.Sprintf("the beads that wait on %s did not read: %v", g.ID, err))
		}
		for _, w := range waiting {
			if st := w.Status(); st != "open" && st != "in_progress" {
				continue
			}
			if err := u.Ledger.AddBlocker(s.id, w.ID); err != nil {
				return retry(fmt.Sprintf("the hold of %s on the PR did not land: %v", w.ID, err))
			}
			if !slices.Contains(held, w.ID) {
				held = append(held, w.ID)
			}
		}
		if err := u.Ledger.ResolveGate(g.ID, gate.ResolvedAt(s.id, own, head)); err != nil {
			return retry(fmt.Sprintf("the resolve of %s did not land: %v", g.ID, err))
		}
		resolved = append(resolved, g.ID)
	}
	hold := "with no conversation open to hold the PR"
	if len(held) > 0 {
		hold = "after the hold of " + strings.Join(held, ", ") + " on the PR"
	}
	return RunOutcome{Bead: s.id, Action: ActResolved, Detail: withNote(fmt.Sprintf("the PR reads %s in its own right at %s, so "+
		"the run resolved %s %s, and requested nothing else of it", own, head, strings.Join(resolved, ", "), hold), c.note)}
}

// gateCloses are the resolves a run owes the open gates of the pack's types
// whose work has closed, read through pass: one for each such gate, which
// takes no lock and writes nothing but the gate's close. A read that does not
// answer is an outcome of its own, and the next run reads the gates again.
func (u *run) gateCloses(pass *ledger.Ledger) []plan {
	unread := func(err error) []plan {
		return []plan{{out: RunOutcome{Action: ActRetry, Detail: "the store's open gates did not read, so no gate whose work " +
			"has closed is resolved; the next run reads them again: " + err.Error()}}}
	}
	rows, err := pass.Find(ledger.Typed("gate"))
	if err != nil {
		return unread(err)
	}
	gates := gate.Open(rows)
	var works []string
	for _, g := range gates {
		if g.Work != "" && !slices.Contains(works, g.Work) {
			works = append(works, g.Work)
		}
	}
	if len(works) == 0 {
		return nil
	}
	ws, err := pass.Find(ledger.ByID(works...).WithClosed())
	if err != nil {
		return unread(err)
	}
	closed := map[string]bool{}
	for _, w := range ws {
		if w.Status() == "closed" {
			closed[w.ID] = true
		}
	}
	var out []plan
	for _, g := range gates {
		if closed[g.Work] {
			out = append(out, plan{id: g.ID, resolve: &g})
		}
	}
	return out
}

// resolveClosed resolves gate g, whose work has closed, within stop.
func (u *run) resolveClosed(g gate.Gate, stop time.Duration) RunOutcome {
	ctx, cancel := bounded(stop)
	defer cancel()
	if err := u.Ledger.Within(ctx).ResolveGate(g.ID, gate.ResolvedClosed(g.Work)); err != nil {
		return RunOutcome{Bead: g.ID, Action: ActRetry, Detail: fmt.Sprintf("%s has closed, and the resolve of its gate did not land; "+
			"the next run tries again: %v", g.Work, err)}
	}
	return RunOutcome{Bead: g.ID, Action: ActResolved, Detail: fmt.Sprintf("%s has closed, so the run resolved its gate", g.Work)}
}
