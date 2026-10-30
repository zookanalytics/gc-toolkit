package board

import (
	"fmt"
	"regexp"
	"slices"
	"strings"
)

// The operator's side of the board is two kinds of bead the gather admits as
// anchors of their own.
//
// A human gate is a bead of issue_type gate whose await type is human, the one
// reader rule bd-lib.sh's HUMAN_GATE_JQ applies. It blocks each bead that waits
// on it, and only a person clears it, by resolving it with an answer.
//
// A conversation is a task that tracks the one bead it is about
// (assets/scripts/conversation.sh). It is assigned to `human` while it waits in
// the operator's queue and to its sitting's alias while a sitting holds it. It
// replies to each human gate it answers, and it blocks nothing.
//
// Each is a wrapper on the beads it concerns. The fold drops its row and moves
// what it asks onto the rows of those beads, and keeps its row only when none
// of them has one ([foldWrappers]).
const (
	KindGate         = "gate"
	KindConversation = "conversation"
)

// The states a held row can be in, carried on [Tile.SittingState].
// SittingStartFailed is a row a conversation on which last spawned a sitting
// that failed to start, with no sitting spawned for it since. A row nothing
// holds carries the empty string, except a conversation's own row whose
// sitting failed to start ([classifySittings]).
const (
	SittingInSession   = "in_session"
	SittingWaiting     = "waiting"
	SittingStartFailed = "start-failed"
)

const (
	awaitHuman = "human"
	// firstReactionKey is the key the recommend exit files its gate under, so
	// the recommendation's gate is the human gate with this await id.
	firstReactionKey = "first-reaction"
	// assigneeHuman is a conversation's assignee while it waits in the
	// operator's queue.
	assigneeHuman = "human"
	mdSessionName = "gc.session_name"
)

// acceptAnswer is an Accept's answer on the recommendation's gate: the close
// reason `ruled: accepted <formula> accept:<token>` gc-helm.sh accept resolves
// the gate with, and finishes an acceptance under.
var acceptAnswer = regexp.MustCompile(`^ruled: accepted ([^ ]+) accept:[0-9a-f]+$`)

// isWrapperKind reports whether a kind is one the fold moves onto the beads it
// concerns.
func isWrapperKind(source string) bool {
	return source == KindGate || source == KindConversation
}

// humanGate reports whether a blocker is a human gate, open or closed.
func humanGate(b Blocker) bool {
	return b.IssueType == "gate" && b.AwaitType == awaitHuman
}

// openHumanGate reports whether a blocker is a human gate that is still open.
func openHumanGate(b Blocker) bool { return humanGate(b) && b.Status != "closed" }

// askList names asks the way Needs names gates: the one ask, or `N× — a · b`
// over several.
func askList(asks []string) string {
	switch len(asks) {
	case 0:
		return ""
	case 1:
		return asks[0]
	default:
		return fmt.Sprintf("%d× — %s", len(asks), strings.Join(asks, " · "))
	}
}

// askOf is what a gate or a conversation asks: its title, or its id for one
// filed without a title.
func askOf(id, title string) string {
	if t := collapseWS(title); t != "" {
		return t
	}
	return id
}

// acceptance is what Accept's three conditions read off one bead's own
// `blocks` listing, the one reader rule's read, which carries a closed gate
// with its answer.
type acceptance struct {
	// formula is the bead's gc.recommended_formula. Condition one holds when it
	// is set.
	formula string
	// meets says condition two holds: the recommendation's gate is open and
	// unassigned, or closed with an acceptance an earlier Accept did not
	// finish.
	meets bool
	// unfinished is the recommendation's gate when it is closed with an
	// Accept's answer that the bead still carries the recommendation beside,
	// and nil otherwise.
	unfinished *Blocker
	// others is every other open human gate that blocks the bead. Condition
	// three holds when it is empty.
	others []Blocker
}

// acceptable reports whether all three of Accept's conditions hold.
func (ac acceptance) acceptable() bool { return ac.meets && len(ac.others) == 0 }

// withheld reports whether the first two conditions hold and the third fails.
func (ac acceptance) withheld() bool { return ac.meets && len(ac.others) > 0 }

// readAcceptance reads Accept's conditions off the bead the way gc-helm.sh
// accept reads them live. The recommendation's gate is the open human gate
// under the key first-reaction, or each of them when a race filed two. With
// none open, it is the newest gate under that key, because no recommendation
// is older than the gate that asks it. A gate assigned to a person is that
// person's to clear, so it does not meet condition two. Only an Accept's own
// answer leaves an acceptance to finish: a sitting's ruling, a withdrawal or a
// person's resolve closes the gate with that answer, and the bead offers
// Discuss alone.
//
// A bead whose waits the source could not read meets nothing, because an
// unread listing cannot show that no other gate blocks it.
func readAcceptance(a Anchor) acceptance {
	ac := acceptance{formula: a.Metadata[mdRecommendedFormula]}
	if ac.formula == "" || a.WaitingUnknown {
		return ac
	}
	var recOpen []Blocker
	var newest *Blocker
	for i := range a.Blockers {
		b := a.Blockers[i]
		if !humanGate(b) {
			continue
		}
		if b.AwaitID != firstReactionKey {
			if openHumanGate(b) {
				ac.others = append(ac.others, b)
			}
			continue
		}
		if openHumanGate(b) {
			recOpen = append(recOpen, b)
		}
		if newest == nil || !b.CreatedAt.Before(newest.CreatedAt) {
			newest = &a.Blockers[i]
		}
	}
	switch {
	case len(recOpen) > 0:
		ac.meets = !slices.ContainsFunc(recOpen, func(b Blocker) bool { return b.Assignee != "" })
	case newest != nil:
		if m := acceptAnswer.FindStringSubmatch(newest.CloseReason); m != nil && m[1] == ac.formula {
			ac.meets = true
			ac.unfinished = newest
		}
	}
	return ac
}

// gateTitles names each gate by what it asks.
func gateTitles(gates []Blocker) []string {
	out := make([]string, 0, len(gates))
	for _, g := range gates {
		out = append(out, askOf(g.ID, g.Title))
	}
	return out
}

// inSession reports whether a sitting holds the conversation now: it is open,
// its assignee is a sitting's alias rather than the operator's queue, and the
// session holding it is a live sitting ([Facts.sittingLive]). A sitting whose
// session has ended does not hold it, so its conversation waits for the
// operator again.
func (f Facts) inSession(a Anchor) bool {
	if a.Source != KindConversation || !a.ClosedAt.IsZero() || a.Assignee == "" || a.Assignee == assigneeHuman {
		return false
	}
	return f.sittingLive(a.Assignee) || f.sittingLive(a.Metadata[mdSessionName])
}

// sittingLive reports whether the session a conversation's holder names is a
// live sitting: a live owner ([Facts.ownerLive]) whose state [SessionEnded]
// does not read as ended. gc-helm.sh's live_sittings reads a session listed
// with no state, or as closed or failed-create, as ended in the same way.
func (f Facts) sittingLive(name string) bool {
	return f.ownerLive(name) && !SessionEnded(f.OwnerState[name])
}

// SessionEnded reports whether a session's listed state says it has ended:
// archived, closed, failed-create, or no state at all, which is the state Gas
// City gives a closed session. A failed-create session is one whose launch was
// rolled back without closing it, so the list still carries it.
func SessionEnded(state string) bool {
	switch state {
	case "", "archived", "closed", "failed-create":
		return true
	}
	return false
}

// humanIndex holds, for each bead, the open human gates that block it and the
// open conversations that track it, read off the gate and conversation anchors
// the gather admitted, and which of them a live sitting holds or answers.
// [BuildBoard] builds it once, before it derives any tile, so a row's held
// fact and the fold read one index.
type humanIndex struct {
	// gates maps a bead id to the open human gates whose Subjects name it.
	gates map[string][]string
	// convs maps a bead id to the open conversations that track it.
	convs map[string][]string
	// live is the open conversations a live session holds.
	live map[string]bool
	// answering is the open human gates a conversation in live replies to.
	answering map[string]bool
}

// indexHuman builds the index from the open gate and conversation anchors.
func indexHuman(anchors []Anchor, f Facts) humanIndex {
	ix := humanIndex{
		gates:     map[string][]string{},
		convs:     map[string][]string{},
		live:      map[string]bool{},
		answering: map[string]bool{},
	}
	seen := map[string]bool{}
	for _, a := range anchors {
		if !isWrapperKind(a.Source) || !a.ClosedAt.IsZero() || seen[a.ID] {
			continue
		}
		seen[a.ID] = true
		into := ix.gates
		if a.Source == KindConversation {
			into = ix.convs
			if f.inSession(a) {
				ix.live[a.ID] = true
				for _, g := range a.RepliesTo {
					ix.answering[g] = true
				}
			}
		}
		for _, s := range a.Subjects {
			if s != "" && s != a.ID {
				into[s] = append(into[s], a.ID)
			}
		}
	}
	return ix
}

// holds reports whether an open human gate blocks the bead or an open
// conversation tracks it.
func (ix humanIndex) holds(id string) bool {
	return len(ix.gates[id]) > 0 || len(ix.convs[id]) > 0
}

// inSessionOn reports whether a live sitting is on the row: the row is a
// conversation a live session holds, or one of the conversations that track
// its bead is.
func (ix humanIndex) inSessionOn(id string) bool {
	if ix.live[id] {
		return true
	}
	return slices.ContainsFunc(ix.convs[id], func(c string) bool { return ix.live[c] })
}

// classifySittings stamps [Tile.SittingState] on every held row: start failed
// when the sitting last spawned for a conversation on the row failed to start
// ([humanIndex.startFailure]), in session when a live sitting is on it
// ([humanIndex.inSessionOn]), and waiting on any other held row, which waits
// for the operator. It runs after the fold, where Held is final, and before
// [tagClusters], which keys on the section a failed start rewrites.
//
// A failed start outranks a live sitting on the same row. Each conversation on
// a bead is a conversation of its own, and the failure is the one state on the
// row nothing else would tell the operator about. A closed row is never marked,
// because a closed anchor is never owed. A conversation whose subject has no
// live row keeps a row of its own, so that row carries the failure instead.
func classifySittings(tiles []Tile, f Facts) {
	failed := startFailures(f.Sittings)
	for i := range tiles {
		t := &tiles[i]
		live := t.ClosedAt.IsZero()
		if !t.Held {
			if reason := failed[t.ID]; reason != "" && live {
				markStartFailed(t, reason)
			}
			continue
		}
		if reason := f.human.startFailure(t.ID, failed); reason != "" && live {
			markStartFailed(t, reason)
			continue
		}
		t.SittingState = SittingWaiting
		if f.human.inSessionOn(t.ID) {
			t.SittingState = SittingInSession
		}
	}
}

// startFailures maps each open conversation whose last sitting failed to start
// ([Sitting.StartFailure]) to the reason.
func startFailures(sittings []Sitting) map[string]string {
	out := map[string]string{}
	for _, s := range sittings {
		if s.Status != "closed" && s.StartFailure != "" {
			out[s.ID] = s.StartFailure
		}
	}
	return out
}

// startFailure returns why the sitting last spawned for a conversation on the
// row id failed to start: the row's own conversation, or one that tracks its
// bead. It is "" when none of them records a failed start.
func (ix humanIndex) startFailure(id string, failed map[string]string) string {
	if reason := failed[id]; reason != "" {
		return reason
	}
	for _, c := range ix.convs[id] {
		if reason := failed[c]; reason != "" {
			return reason
		}
	}
	return ""
}

// markStartFailed puts a row whose conversation's sitting failed to start in
// front of the operator, the one person who can engage the conversation again.
// The state and its reason ride the wire, and NEEDS leads with the failure, so
// every surface that prints the row says so. The row is owed and banded at
// least ELEVATED, whatever its own markers made of it. [owedFirst] puts the
// row at the head of the queue.
func markStartFailed(t *Tile, reason string) {
	t.SittingState = SittingStartFailed
	t.SittingStartFailure = reason
	t.Owed = true
	if t.Severity.rank() < SevElevated.rank() {
		t.Severity = SevElevated
		t.RankScore = rankScore(t.Severity, t.Weight, t.StaleDays, 0)
	}
	needs := "start failed (" + reason + ")"
	if t.Needs != "" {
		needs += ": " + t.Needs
	}
	t.Needs = needs
	t.Section = classifySection(*t)
}
