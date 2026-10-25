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

// The two states a held row can be in, carried on [Tile.SittingState].
const (
	SittingInSession = "in_session"
	SittingWaiting   = "waiting"
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
// session holding it is live, read against the session list the way the board
// reads every owner's liveness. A sitting whose session has closed does not
// hold it, so its conversation waits for the operator again.
func (f Facts) inSession(a Anchor) bool {
	if a.Source != KindConversation || !a.ClosedAt.IsZero() || a.Assignee == "" || a.Assignee == assigneeHuman {
		return false
	}
	return f.ownerLive(a.Assignee) || f.ownerLive(a.Metadata[mdSessionName])
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

// classifySittings stamps [Tile.SittingState] on every held row: in session
// when a live sitting is on it ([humanIndex.inSessionOn]), and waiting on any
// other held row, which waits for the operator. It runs after the fold, where
// Held is final.
func classifySittings(tiles []Tile, f Facts) {
	for i := range tiles {
		if !tiles[i].Held {
			continue
		}
		tiles[i].SittingState = SittingWaiting
		if f.human.inSessionOn(tiles[i].ID) {
			tiles[i].SittingState = SittingInSession
		}
	}
}
