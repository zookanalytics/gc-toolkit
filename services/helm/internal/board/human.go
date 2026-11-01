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

// The states a sitting can be in, carried on [Sitting.State] and derived once
// ([Facts.sittingState]). SittingInSession is a conversation a live session
// holds now. SittingStartFailed is an open conversation whose last spawned
// sitting failed to start, with no sitting spawned for it since. SittingWaiting
// is any other open conversation: no live session holds it, so it waits for the
// operator. SittingClosed is a conversation that has ended.
//
// A held row's [Tile.SittingState] is the roll-up of the states of the sittings
// on it ([classifySittings]). It never reads SittingClosed, and a row nothing
// holds carries the empty string.
const (
	SittingInSession   = "in_session"
	SittingWaiting     = "waiting"
	SittingStartFailed = "start-failed"
	SittingClosed      = "closed"
)

const (
	awaitHuman = "human"
	// firstReactionKey is the key the recommend exit files its gate under, so
	// the recommendation's gate is the human gate with this await id.
	firstReactionKey = "first-reaction"
	// assigneeHuman is a conversation's assignee while it waits in the
	// operator's queue.
	assigneeHuman = "human"
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

// sittingState derives a sitting's one state from its conversation's status and
// holder. A sitting is in session when its assignee is a sitting's alias rather
// than the operator's queue, and the session holding it is a live sitting
// ([Facts.sittingLive]). A sitting whose session has ended holds nothing, so its
// conversation waits for the operator again. A failed start outranks a live
// holder, because it is the state nothing else would tell the operator about.
func (f Facts) sittingState(s Sitting) string {
	switch {
	case s.Status == "closed":
		return SittingClosed
	case s.StartFailure != "":
		return SittingStartFailed
	case s.Assignee != "" && s.Assignee != assigneeHuman && (f.sittingLive(s.Assignee) || f.sittingLive(s.Session)):
		return SittingInSession
	}
	return SittingWaiting
}

// stampSittings is the record as the board carries it: a copy of the gather's
// sittings, each with its state and headline derived. [BuildBoard] runs it
// before anything reads a sitting, so every row and every renderer reads these
// values and none derives its own.
func stampSittings(in []Sitting, f Facts) []Sitting {
	out := slices.Clone(in)
	for i := range out {
		out[i].State = f.sittingState(out[i])
		out[i].Headline = sittingHeadline(out[i])
	}
	return out
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
	// sittings maps a conversation's id to its sitting. A row reads the state it
	// carries ([stampSittings]) and has no reading of its own.
	sittings map[string]Sitting
	// answering is the open human gates a conversation in session replies to.
	answering map[string]bool
}

// indexHuman builds the index from the open gate and conversation anchors.
func indexHuman(anchors []Anchor, f Facts) humanIndex {
	ix := humanIndex{
		gates:     map[string][]string{},
		convs:     map[string][]string{},
		sittings:  map[string]Sitting{},
		answering: map[string]bool{},
	}
	for _, s := range f.Sittings {
		ix.sittings[s.ID] = s
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
			if ix.inSession(a.ID) {
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
// conversation tracks it: the operator's side has the bead. Only the gate
// holds its work ([humanIndex.holdsWork]).
func (ix humanIndex) holds(id string) bool {
	return len(ix.gates[id]) > 0 || len(ix.convs[id]) > 0
}

// holdsWork reports whether an open human gate blocks the bead, so its work
// cannot move until the operator answers. A conversation blocks nothing.
func (ix humanIndex) holdsWork(id string) bool {
	return len(ix.gates[id]) > 0
}

// inSession reports whether the conversation id is in session: a live session
// holds it, by the state its sitting carries.
func (ix humanIndex) inSession(id string) bool {
	return ix.sittings[id].State == SittingInSession
}

// inSessionOn reports whether a live sitting is on the row: the row is a
// conversation in session, or one of the conversations that track its bead is.
func (ix humanIndex) inSessionOn(id string) bool {
	return ix.inSession(id) || slices.ContainsFunc(ix.convs[id], ix.inSession)
}

// classifySittings stamps [Tile.SittingState] on every held row, the roll-up of
// the states of the sittings on it: start failed when one failed to start
// ([humanIndex.startFailure]), in session when one is in session
// ([humanIndex.inSessionOn]), and waiting otherwise, which is also what a row
// only a human gate holds reads. It runs after the fold, where Held is final,
// and before [tagClusters], which keys on the section a failed start rewrites.
//
// A failed start outranks a live sitting on the same row. Each conversation on
// a bead is a conversation of its own, and the failure is the one state on the
// row nothing else would tell the operator about. A closed row is never marked,
// because a closed anchor is never owed. A conversation whose subject has no
// live row keeps a row of its own, so that row carries the failure instead.
func classifySittings(tiles []Tile, f Facts) {
	for i := range tiles {
		t := &tiles[i]
		if !t.Held {
			continue
		}
		if reason := f.human.startFailure(t.ID); reason != "" && t.ClosedAt.IsZero() {
			markStartFailed(t, reason)
			continue
		}
		t.SittingState = SittingWaiting
		if f.human.inSessionOn(t.ID) {
			t.SittingState = SittingInSession
		}
	}
}

// startFailure returns why the sitting last spawned for a conversation on the
// row id failed to start: the row's own conversation, or one that tracks its
// bead. It is "" when no sitting on the row is in that state.
func (ix humanIndex) startFailure(id string) string {
	for _, c := range append([]string{id}, ix.convs[id]...) {
		if s := ix.sittings[c]; s.State == SittingStartFailed {
			return s.StartFailure
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
