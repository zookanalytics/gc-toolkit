package standing

import (
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/conversation"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus"
	"github.com/zookanalytics/gc-toolkit/services/gctk/standing/person"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// Group is where a bead's work stands: a person owes its next move, the city
// takes it as things stand, nothing moves it as things stand, or it is closed.
// A bead with no move of its own, and a bead a reader could not answer, has
// none.
type Group string

const (
	GroupWaitingOnYou Group = "waiting-on-you"
	GroupQueued       Group = "queued"
	GroupNotMoving    Group = "not-moving"
	GroupClosed       Group = "closed"
)

// Rule is the rule that placed a bead: the first that applies, in the order
// docs/gctk-architecture.md gives them ("The bead stands contract").
type Rule string

const (
	RuleClosed       Rule = "closed"
	RuleAsk          Rule = "ask"
	RuleOwnWait      Rule = "own-wait"
	RuleFurtherAlong Rule = "further-along"
	RuleParked       Rule = "parked"
	RuleStatus       Rule = "status"
	RuleStaying      Rule = "staying"
	RuleAnswers      Rule = "answers"
	RuleMembers      Rule = "members"
	RuleGate         Rule = "gate"
	RuleInFlight     Rule = "in-flight"
	RuleScheduled    Rule = "scheduled"
	RuleNotScheduled Rule = "not-scheduled"
	// RuleUnread is the answer at a rule whose part a reader could not answer.
	RuleUnread Rule = "unread"
)

// Ask is what a person owes when a bead is itself the ask.
type Ask string

const (
	AskQuestion     Ask = "question"
	AskConversation Ask = "conversation"
	AskPullRequest  Ask = "pull-request"
	AskRoutedToYou  Ask = "routed-to-you"
	AskRuling       Ask = "ruling"
)

// Kind is what a bead is.
type Kind string

const (
	KindEpic         Kind = "epic"
	KindDelivery     Kind = "delivery"
	KindWork         Kind = "work"
	KindGate         Kind = "gate"
	KindDecision     Kind = "decision"
	KindConversation Kind = "conversation"
)

// Ref names a bead.
type Ref struct {
	ID    string
	Title string
}

// Answer is where a bead stands.
type Answer struct {
	Group Group
	Rule  Rule
	// Ask is what a person owes, for a bead the ask rule placed.
	Ask Ask
	// Names are the beads the rule names: the gate or the bead a person owes,
	// the gate that parks it, the question a conversation answers, or its
	// waits, each once.
	Names []Ref
	// Owed is the gate or the bead a person owes that the own-wait or the
	// further-along rule names, as the walk of what holds the bead read it.
	Owed *person.Blocker
	// Why is what a reader could not answer, for an unread answer.
	Why string
}

// kindOf is what a bead is. A Delivery is an epic whose parent is an epic and
// which carries no hypothesis (docs/epics.md, "What a Delivery is as a bead").
func (r *Reading) kindOf(b Bead) Kind {
	k := ownKind(b)
	if k == KindEpic && b.Hypothesis == "" {
		for _, p := range edgesOf(b, "parent-child") {
			if pb, ok := r.beads[p]; ok && issueType(pb) == "epic" {
				return KindDelivery
			}
		}
	}
	return k
}

// ownKind is what a bead is by its own row, an epic and a Delivery alike
// reading as an epic. A conversation is a task in the shape conversation.Shape
// reads.
func ownKind(b Bead) Kind {
	switch issueType(b) {
	case "gate":
		return KindGate
	case "decision":
		return KindDecision
	case "epic":
		return KindEpic
	}
	if conversation.IsCandidate(issueType(b), b.Assignee, b.ID) {
		if _, _, ok := conversation.Shape(conversationEdges(b)); ok {
			return KindConversation
		}
	}
	return KindWork
}

func (r *Reading) openHumanGate(id string) bool {
	b, ok := r.beads[id]
	return ok && isOpen(b) && person.IsHumanGate(b.IssueType, b.AwaitType)
}

func (r *Reading) openDecision(id string) bool {
	b, ok := r.beads[id]
	return ok && isOpen(b) && r.kinds[id] == KindDecision
}

// answer answers each bead named that the read holds a bead for.
func (r *Reading) answer(ids []string) {
	// Whether each conversation and decision waits on work of its own first,
	// read before any ask, since a conversation's ask reads whether the
	// decision it tracks stays.
	stays := map[string]bool{}
	for id, b := range r.beads {
		if k := r.kinds[id]; k == KindConversation || k == KindDecision {
			if h, ok := r.holds[id]; ok {
				stays[id] = staying(b, h)
			}
		}
	}
	children := map[string][]string{}
	for id, b := range r.beads {
		for _, p := range edgesOf(b, "parent-child") {
			children[p] = append(children[p], id)
		}
	}
	for _, id := range ids {
		b, ok := r.beads[id]
		if !ok {
			continue
		}
		k := r.kinds[id]
		var ask Ask
		// Work held for the Product Owner asks nothing of a person, whatever it
		// would ask, such as a review of its pull request: hold:mayor names the
		// Product Owner as its next actor.
		if !r.ForProductOwner(id) {
			// An epic's or a Delivery's members are the work, the Deliveries and
			// the child epics its children's parent-child edges place under it.
			// A child epic with a hypothesis of its own reads as an epic, not a
			// Delivery, and while it is open its parent is not done.
			members, open := 0, 0
			if k == KindEpic || k == KindDelivery {
				for _, c := range children[id] {
					if ck := r.kinds[c]; ck == KindWork || ck == KindDelivery || ck == KindEpic {
						members++
						if isOpen(r.beads[c]) {
							open++
						}
					}
				}
			}
			ask = r.askOf(b, k, stays, open, members)
		}
		r.answers[id] = r.table(b, k, ask, stays)
	}
}

// askOf is whether a bead is itself an ask, and which: what the shared readers
// count as a person's move, and a ruling.
//
//   - Question: an open human gate, or an open decision that does not wait on
//     work of its own first (staying). One that waits on the work a ruling
//     sent is no person's move until that work closes.
//   - Conversation: an open conversation that replies to no open human gate,
//     tracks no open decision that is a question, and that its sitting does
//     not stay in. One that replies to such a gate or tracks such a decision
//     answers that question. One its sitting stays in (staying) waits for the
//     return of the work it sent, which comes back to the operator once that
//     work closes, so until then it is no person's move.
//   - Pull request: a bead whose pull request reads needs-review or
//     needs-attention.
//   - Routed to you: any other open bead only a person clears ([person.Clears]).
//   - Ruling: an epic with members and none open, or a landed Delivery.
//
// A gate that is no human gate is never an ask.
func (r *Reading) askOf(b Bead, k Kind, stays map[string]bool, membersOpen, members int) Ask {
	if !isOpen(b) {
		return ""
	}
	switch k {
	case KindGate:
		if !person.IsHumanGate(b.IssueType, b.AwaitType) {
			return ""
		}
		return AskQuestion
	case KindDecision:
		if stays[b.ID] {
			return ""
		}
		return AskQuestion
	case KindConversation:
		if stays[b.ID] {
			return ""
		}
		if _, ok := r.questionOf(b, stays); ok {
			return ""
		}
		return AskConversation
	case KindEpic, KindDelivery:
		if members > 0 && membersOpen == 0 {
			return AskRuling
		}
	}
	if p := r.PullRequest(b.ID); p != nil {
		if st := p.State(); st == prstatus.NeedsReview || st == prstatus.NeedsAttention {
			return AskPullRequest
		}
	}
	if person.Clears(person.Blocker{ID: b.ID, Status: b.Status, IssueType: b.IssueType, AwaitType: b.AwaitType,
		Assignee: b.Assignee}) {
		return AskRoutedToYou
	}
	return ""
}

// questionOf is the question an open conversation answers: the first open
// human gate it replies to, or the open decision it tracks while that decision
// asks, one that does not stay.
func (r *Reading) questionOf(b Bead, stays map[string]bool) (Ref, bool) {
	for _, g := range edgesOf(b, "replies-to") {
		if r.openHumanGate(g) {
			return Ref{ID: g, Title: r.beads[g].Title}, true
		}
	}
	if subject, _, ok := conversation.Shape(conversationEdges(b)); ok && r.openDecision(subject) && !stays[subject] {
		return Ref{ID: subject, Title: r.beads[subject].Title}, true
	}
	return Ref{}, false
}

// table answers one bead, whose ask askOf read. The first row that applies
// answers:
//
//  1. closed: the bead is closed. Group closed.
//  2. ask: it is an ask. Group waiting-on-you.
//  3. own-wait or further-along: prstatus.Holding names a gate or a bead a
//     person owes for it, through one of its own waits or further along.
//     Group waiting-on-you.
//  4. parked: a wait behind its status is a gate that is no human gate, its
//     own or an ancestor's. Group not-moving.
//  5. status: its status is one no pool offers, such as deferred, other than
//     the blocked status Gas Town's pending record writes on a bead whose pull
//     request it holds, which is the record's own and holds nothing. Group
//     not-moving.
//  6. staying: it is a conversation its sitting stays in, or a decision a
//     ruling left waiting on the work it sent. Group queued: it is a person's
//     move again once that work closes.
//  7. answers, members or gate: it has no move of its own. A conversation
//     that is no ask answers a question, whose row carries it. An epic or a
//     Delivery that is no ruling has open members or none at all. A gate that
//     is no human gate holds what waits on it. No group.
//  8. in-flight: waits says it is work in flight, or a live run works it,
//     from the run's start. Group queued.
//  9. scheduled: the city takes it as things stand, as its place in queue's
//     order says (queue.Place): it is armed, routed to a pool or assigned to
//     an agent, and no dispatch hold holds it. Group queued.
//  10. not-scheduled: any other work. Group not-moving.
//
// A bead a reader could not answer reads unread at the row that needs the
// answer, in no group.
func (r *Reading) table(b Bead, k Kind, ask Ask, stays map[string]bool) Answer {
	if !isOpen(b) {
		return Answer{Group: GroupClosed, Rule: RuleClosed}
	}
	if r.noFacts[b.ID] {
		return Answer{Rule: RuleUnread, Why: "its pull request did not read"}
	}
	if ask != "" {
		return Answer{Group: GroupWaitingOnYou, Rule: RuleAsk, Ask: ask}
	}
	h, ok := r.holds[b.ID]
	if !ok {
		why := "waits did not answer what holds it"
		if err := r.unread[b.ID]; err != nil {
			why = "waits could not answer what holds it: " + err.Error()
		}
		return Answer{Rule: RuleUnread, Why: why}
	}
	if root := rootOf(b.ID, h); root != "" {
		if hold, ok := r.holding[root]; ok {
			if len(hold.Gates) > 0 || len(hold.Owed) > 0 {
				return holdingAnswer(h, hold)
			}
		} else if r.unwalked[root] {
			return Answer{Rule: RuleUnread, Why: "the walk of what a person owes for it ran past its bound"}
		}
	}
	if w := gateHold(h); w != nil {
		return Answer{Group: GroupNotMoving, Rule: RuleParked, Names: []Ref{{ID: w.ID, Title: w.Title}}}
	}
	switch st := status(b); {
	case st == "open", st == "in_progress", st == "hooked":
	case st == "blocked" && pr.OnRecord(b.MergeResult):
	default:
		return Answer{Group: GroupNotMoving, Rule: RuleStatus}
	}
	if (k == KindConversation || k == KindDecision) && stays[b.ID] {
		return Answer{Group: GroupQueued, Rule: RuleStaying, Names: refsOf(h.Waits)}
	}
	switch k {
	case KindConversation:
		a := Answer{Rule: RuleAnswers}
		if q, ok := r.questionOf(b, stays); ok {
			a.Names = []Ref{q}
		}
		return a
	case KindEpic, KindDelivery:
		return Answer{Rule: RuleMembers}
	case KindGate, KindDecision:
		// A decision that reaches here waits on work of its own, which the
		// staying row answered above, so only a gate that is no human gate does.
		return Answer{Rule: RuleGate}
	}
	// waits counts a run in flight only once it has passed load-context, which
	// answers whether an ancestor's wait still holds work that has not
	// started. A bead a live run works is the city's from the run's start.
	if h.InFlight != "" || r.worked[b.ID] != "" {
		return Answer{Group: GroupQueued, Rule: RuleInFlight, Names: refsOf(h.Waits)}
	}
	place, ok := r.places[b.ID]
	if !ok {
		return Answer{Rule: RuleUnread, Why: "queue placed it nowhere"}
	}
	if place.Scheduled {
		return Answer{Group: GroupQueued, Rule: RuleScheduled, Names: refsOf(h.Waits)}
	}
	return Answer{Group: GroupNotMoving, Rule: RuleNotScheduled, Names: refsOf(h.Waits)}
}

// holdingAnswer is row 3: what Holding names for the bead, through one of its
// own waits or further along. Holding lists the gates and the beads a person
// owes each nearest first, and the gates come first, as prstatus.Reasons
// orders them.
func holdingAnswer(h waits.Holds, hold prstatus.Holds) Answer {
	own := map[string]bool{}
	if h.Status == waits.Blocked || h.Status == waits.Unjudged {
		for _, w := range h.Waits {
			if w.Ancestor == "" {
				own[w.ID] = true
			}
		}
	}
	for _, list := range [][]person.Blocker{hold.Gates, hold.Owed} {
		for i, x := range list {
			if own[x.ID] {
				return Answer{Group: GroupWaitingOnYou, Rule: RuleOwnWait, Names: []Ref{{ID: x.ID, Title: x.Title}},
					Owed: &list[i]}
			}
		}
	}
	first := hold.Owed
	if len(hold.Gates) > 0 {
		first = hold.Gates
	}
	return Answer{Group: GroupWaitingOnYou, Rule: RuleFurtherAlong, Names: []Ref{{ID: first[0].ID, Title: first[0].Title}},
		Owed: &first[0]}
}

// gateHold is the first wait behind a bead's status, its own or an ancestor's,
// on a gate that is no human gate, and nil when none is: a park
// (docs/steering.md, "A park"), whose gate gc-helm.sh park files with no await
// type. A gate of a type bd closes by itself, such as a timer, reads as one
// too.
func gateHold(h waits.Holds) *waits.Wait {
	for i, w := range h.Waits {
		if strings.EqualFold(w.IssueType, "gate") && !person.IsHumanGate(w.IssueType, w.AwaitType) {
			return &h.Waits[i]
		}
	}
	return nil
}

// staying reports whether a conversation or a decision waits on work of its own
// first ([person.Stays]): a conversation its sitting stays in, or a decision a
// ruling left waiting on the work it sent. Its own waits are the ones waits
// names behind a blocked status, which are each the bead's own. prstatus reads a
// bead a pull request waits on by the same rule, so the bead's standing and its
// pull request's agree on whether the operator owes a move.
func staying(b Bead, h waits.Holds) bool {
	var own []person.Blocker
	if h.Status == waits.Blocked {
		for _, w := range h.Waits {
			own = append(own, person.Blocker{ID: w.ID, Title: w.Title, Status: w.Status, IssueType: w.IssueType,
				AwaitType: w.AwaitType})
		}
	}
	return person.Stays(person.Blocker{ID: b.ID, Title: b.Title, Status: b.Status, IssueType: b.IssueType,
		AwaitType: b.AwaitType, Assignee: b.Assignee}, own)
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
