package rigboard

import (
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/conversation"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus"
	"github.com/zookanalytics/gc-toolkit/services/gctk/queue"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// The table that turns the readers' answers into a row's group and signal.
// It is the only place those words are chosen, and the first row that
// matches answers:
//
//  1. The bead is closed: "Closed", with how it closed. Group Closed.
//  2. It is an ask: the ask's words. Group Waiting on you.
//  3. prstatus.Holding names a gate or a bead a person owes for it. When that
//     is one of its own waits: "Waits on your answer" for a human gate or a
//     decision, "Conversation waits for you" or "In conversation" for a
//     conversation, and otherwise "Waits on <id>" naming each of its waits, so
//     a bead behind another bead's pull request names that bead and never
//     takes its words. When it is further along: "Waits on <id>", with line 3
//     naming what Holding returned first. Group Waiting on you.
//  4. A wait behind its status is a gate that is no human gate, its own or an
//     ancestor's: "Held by a gate", with the gate's title. Group Not moving.
//  5. Its status is deferred: "Deferred". Any other status that is neither
//     open nor a claim reads as the store's word. Group Not moving. A
//     conversation its sitting stays in (staying) then reads "Waits on <id>",
//     naming each wait, in Group Queued: its sitting comes back once that work
//     closes.
//  6. waits says it is in flight. With an open pull request: "Pull request
//     #<n>", with where it stands. Otherwise "In flight", with its assignee.
//     Group Queued.
//  7. The city takes it as things stand, as its place in queue's order says
//     (queue.Place): it is armed, routed to a pool or assigned to an agent,
//     and no dispatch hold holds it. "Queued" when nothing holds it, and
//     "Waits on <id>" naming each wait when one does. Group Queued.
//  8. Otherwise: "Not scheduled", with line 3 naming each wait when one holds
//     it. Group Not moving.
//
// Rows 6 to 8 apply only to a piece of work: an epic, a Delivery, a gate, a
// decision and a conversation are never sent to a pool. A bead a reader could
// not answer reads "unread" and sits in no group.

// Group is where a row's work stands: it waits on you, it will be done
// without you, it will not be done as things stand, or it is closed. A row no
// group holds, such as a gate, or a bead a reader could not answer, carries
// none.
type Group string

const (
	GroupWaitingOnYou Group = "Waiting on you"
	GroupQueued       Group = "Queued"
	GroupNotMoving    Group = "Not moving"
	GroupClosed       Group = "Closed"
)

// Ask is the kind of thing a person owes a move on, for a row that is an
// ask.
type Ask string

const (
	AskQuestion     Ask = "Question"
	AskConversation Ask = "Conversation"
	AskPullRequest  Ask = "Pull request"
	AskRoutedToYou  Ask = "Routed to you"
	AskRuling       Ask = "Ruling"
)

// outcome is the row of the table that answered.
type outcome int

const (
	outNone outcome = iota
	outUnread
	outClosed
	outAsk
	outOwnWait
	outEndsOnYou
	outHeldByGate
	outNotOpen
	outInFlight
	outPullRequest
	outQueued
	outQueuedBehind
	outNotScheduled
)

// verdict is the table's answer for one row.
type verdict struct {
	out    outcome
	group  Group
	signal string
	note   string
	line3  []Ref
}

// askAnswer is what makes a row an ask, and the words its signal reads.
type askAnswer struct {
	kind  Ask
	words string
}

// Words the table writes that another document already gives.
const (
	signalUnread = "unread"
	// docs/epics.md, "How a Delivery ends", gives a landed Delivery's row.
	signalLandedDelivery = "landed — waits for its Epic Checkpoint"
	signalNeedsRuling    = "Needs a ruling"
)

// conversationWords is what a conversation's row says: whether it waits in the
// operator's queue or a sitting holds it, read off its assignee as
// conversation.IsAssignee reads one.
func conversationWords(assignee string) string {
	if strings.TrimSpace(assignee) == "human" {
		return "Conversation waits for you"
	}
	return "In conversation"
}

// staying reports whether a conversation reads as its sitting's stay: open
// under the sitting, which the stay's last write leaves it, with a wait of its
// own holding it. A sitting that holds keeps its conversation claimed, in
// progress, and one in the operator's queue is assigned to them, so neither
// is a stay, whatever edge an earlier stay left on it: the operator owes it a
// move.
func staying(b bead, h waits.Holds) bool {
	a := strings.TrimSpace(b.Assignee)
	return status(b) == "open" && a != "" && a != "human" && h.Status == waits.Blocked
}

// table answers one row. in carries the readers' answers about it.
type tableInput struct {
	b       bead
	kind    Kind
	ask     *askAnswer
	holds   *waits.Holds
	holding *prstatus.Holds
	// unwalked is true when the row needs Holding's answer and its walk ran
	// past its bound.
	unwalked bool
	// facts is the row's pull request facts, nil when it has no open pull
	// request, and prUnread is true when it has one prstatus could not answer.
	facts    *prstatus.Facts
	prUnread bool
	// place is the row's place in queue's order, nil when queue placed it
	// nowhere.
	place *queue.Place
}

func table(in tableInput) verdict {
	b := in.b
	if !isOpen(b) {
		return verdict{out: outClosed, group: GroupClosed, signal: "Closed", note: b.WorkOutcome}
	}
	if in.prUnread {
		return verdict{out: outUnread, signal: signalUnread}
	}
	if in.ask != nil {
		return verdict{out: outAsk, group: GroupWaitingOnYou, signal: in.ask.words}
	}
	if in.holds == nil || in.unwalked {
		return verdict{out: outUnread, signal: signalUnread}
	}
	h := *in.holds
	if in.holding != nil && (len(in.holding.Gates) > 0 || len(in.holding.Owed) > 0) {
		return holdingVerdict(h, *in.holding)
	}
	for _, w := range h.Waits {
		if strings.EqualFold(w.IssueType, "gate") && !prstatus.IsHumanGate(w.IssueType, w.AwaitType) {
			return verdict{out: outHeldByGate, group: GroupNotMoving, signal: "Held by a gate", note: w.Title}
		}
	}
	switch st := status(b); st {
	case "open", "in_progress", "hooked":
	case "deferred":
		return verdict{out: outNotOpen, group: GroupNotMoving, signal: "Deferred"}
	default:
		return verdict{out: outNotOpen, group: GroupNotMoving, signal: st}
	}
	if in.kind == KindConversation {
		if staying(b, h) && len(h.Waits) > 0 {
			return verdict{out: outNone, group: GroupQueued, signal: "Waits on " + joinIDs(refsOf(h.Waits))}
		}
		return verdict{out: outNone, signal: conversationWords(b.Assignee)}
	}
	if in.kind != KindWork {
		return verdict{out: outNone}
	}
	if h.InFlight != "" {
		if in.facts != nil && b.PRNumber != "" {
			return verdict{out: outPullRequest, group: GroupQueued, signal: "Pull request #" + b.PRNumber,
				note: string(prstatus.Derive(*in.facts))}
		}
		return verdict{out: outInFlight, group: GroupQueued, signal: "In flight", note: b.Assignee}
	}
	if in.place == nil {
		return verdict{out: outUnread, signal: signalUnread}
	}
	waitRefs := refsOf(h.Waits)
	if in.place.Scheduled {
		if h.Status == waits.Clear {
			return verdict{out: outQueued, group: GroupQueued, signal: "Queued"}
		}
		return verdict{out: outQueuedBehind, group: GroupQueued, signal: "Waits on " + joinIDs(waitRefs)}
	}
	return verdict{out: outNotScheduled, group: GroupNotMoving, signal: "Not scheduled", line3: waitRefs}
}

// holdingVerdict is row 3: what Holding names for the row, through one of its
// own waits or further along. Holding lists the gates and the beads a person
// owes each nearest first, and the gates come first, as prstatus.Reasons
// orders them.
func holdingVerdict(h waits.Holds, hold prstatus.Holds) verdict {
	own := map[string]bool{}
	if h.Status == waits.Blocked || h.Status == waits.Unjudged {
		for _, w := range h.Waits {
			if w.Ancestor == "" {
				own[w.ID] = true
			}
		}
	}
	for _, g := range hold.Gates {
		if own[g.ID] {
			return verdict{out: outOwnWait, group: GroupWaitingOnYou, signal: "Waits on your answer"}
		}
	}
	for _, o := range hold.Owed {
		if !own[o.ID] {
			continue
		}
		if conversation.IsCandidate(strings.ToLower(o.IssueType), o.Assignee, o.ID) {
			return verdict{out: outOwnWait, group: GroupWaitingOnYou, signal: conversationWords(o.Assignee)}
		}
		if strings.EqualFold(strings.TrimSpace(o.IssueType), "decision") {
			return verdict{out: outOwnWait, group: GroupWaitingOnYou, signal: "Waits on your answer"}
		}
		return verdict{out: outOwnWait, group: GroupWaitingOnYou, signal: "Waits on " + joinIDs(refsOf(h.Waits))}
	}
	first := hold.Owed
	if len(hold.Gates) > 0 {
		first = hold.Gates
	}
	ends := []Ref{{ID: first[0].ID, Title: first[0].Title}}
	signal := "Waits on " + first[0].ID
	if len(h.Waits) > 0 {
		signal = "Waits on " + joinIDs(refsOf(h.Waits))
	}
	return verdict{out: outEndsOnYou, group: GroupWaitingOnYou, signal: signal, line3: ends}
}

// refsOf names each wait once.
func refsOf(ws []waits.Wait) []Ref {
	var out []Ref
	for _, w := range ws {
		if !slices.ContainsFunc(out, func(r Ref) bool { return r.ID == w.ID }) {
			out = append(out, Ref{ID: w.ID, Title: w.Title})
		}
	}
	return out
}

func joinIDs(refs []Ref) string {
	ids := make([]string, len(refs))
	for i, r := range refs {
		ids[i] = r.ID
	}
	return strings.Join(ids, ", ")
}

// askOf is row 2's question: whether a row is an ask, and its words. An ask is
// what the shared readers count as a person's move, and a ruling.
//
//   - Question: an open human gate, or an open decision.
//   - Conversation: an open conversation that replies to no open gate a
//     person answers and that its sitting does not stay in. One that replies
//     to such a gate belongs to that gate's ask, as its conversation. One its
//     sitting stays in (staying) waits for the return of the work it sent,
//     which comes back to the operator once that work closes, so until then it
//     is no person's move.
//   - Pull request: a bead whose pull request reads needs-review or
//     needs-attention, in those words.
//   - Routed to you: any other open bead prstatus.IsPersonBlocker counts, as
//     the listing answers it for the bead.
//   - Ruling: an epic with members and none open, or a landed Delivery.
//
// A gate that is no human gate is never an ask.
func askOf(b bead, k Kind, answeredBy string, answeredByAssignee string, openQuestionGate func(string) bool,
	facts *prstatus.Facts, membersOpen, members int, stay bool) *askAnswer {
	if !isOpen(b) {
		return nil
	}
	switch k {
	case KindGate:
		if !prstatus.IsHumanGate(b.IssueType, b.AwaitType) {
			return nil
		}
		return questionAsk(answeredBy, answeredByAssignee)
	case KindDecision:
		return questionAsk("", "")
	case KindConversation:
		if stay {
			return nil
		}
		for _, g := range edgesOf(b, "replies-to") {
			if openQuestionGate(g) {
				return nil
			}
		}
		return &askAnswer{kind: AskConversation, words: conversationWords(b.Assignee)}
	case KindEpic, KindDelivery:
		if members > 0 && membersOpen == 0 {
			if k == KindDelivery {
				return &askAnswer{kind: AskRuling, words: signalLandedDelivery}
			}
			return &askAnswer{kind: AskRuling, words: signalNeedsRuling}
		}
	}
	if facts != nil {
		if st := prstatus.Derive(*facts); st == prstatus.NeedsReview || st == prstatus.NeedsAttention {
			return &askAnswer{kind: AskPullRequest, words: string(st)}
		}
	}
	if b.PersonBlocker {
		return &askAnswer{kind: AskRoutedToYou, words: string(AskRoutedToYou)}
	}
	return nil
}

// questionAsk is a question's ask: "Question", or its conversation's words when
// one answers it.
func questionAsk(answeredBy, assignee string) *askAnswer {
	if answeredBy != "" {
		return &askAnswer{kind: AskQuestion, words: conversationWords(assignee)}
	}
	return &askAnswer{kind: AskQuestion, words: string(AskQuestion)}
}

// pullRequestOf is a bead's pull request in the pack's words, nil when it
// records none.
func pullRequestOf(b bead, facts *prstatus.Facts) *PullRequest {
	n := b.PRNumber
	if n == "" {
		return nil
	}
	pr := &PullRequest{Number: n, URL: b.PRURL}
	if facts != nil {
		pr.State = string(prstatus.Derive(*facts))
		for _, h := range prstatus.Held(*facts) {
			pr.Held = append(pr.Held, string(h))
		}
	}
	return pr
}

// reasonsOf is what holds a pull request, in the pack's words.
func reasonsOf(facts *prstatus.Facts) []Reason {
	if facts == nil {
		return nil
	}
	var out []Reason
	for _, r := range prstatus.Reasons(*facts) {
		out = append(out, Reason{Held: string(r.Held), ID: r.ID, Title: r.Title})
	}
	return out
}
