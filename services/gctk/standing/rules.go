package standing

import (
	"slices"
	"sort"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/conversation"
	"github.com/zookanalytics/gc-toolkit/services/gctk/gate"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus"
	"github.com/zookanalytics/gc-toolkit/services/gctk/queue"
	"github.com/zookanalytics/gc-toolkit/services/gctk/standing/person"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// Group is where a bead's work stands, one of the four below. A bead with no
// move of its own, and a bead a reader could not answer, has none.
// docs/bead-standing.md gives each group to a person, beside the label the
// board shows for it (services/helm/internal/rigboard), with what the person
// can do.
type Group string

const (
	// GroupWaitingOnYou: a person owes the bead's next move. The bead is
	// itself an ask ([RuleAsk]), or a human gate or a bead only a person
	// clears holds it ([RuleOwnWait], [RuleFurtherAlong]).
	GroupWaitingOnYou Group = "waiting-on-you"
	// GroupQueued: the city takes the bead as things stand. It is work in
	// flight ([RuleInFlight]), work the city sends ([RuleScheduled]), or a
	// conversation or a decision that waits on the work it sent
	// ([RuleStaying]).
	GroupQueued Group = "queued"
	// GroupNotMoving: nothing moves the bead as things stand. A park holds it
	// ([RuleParked]), its status is one no pool offers ([RuleStatus]), or it
	// is work nothing sends: ready work ([RuleNotScheduled]), work that waits
	// outside the city ([RuleOutside]), work held for the Product Owner
	// ([RuleForProductOwner]), or work the store does not serve as ready
	// ([RuleNotReady]).
	GroupNotMoving Group = "not-moving"
	// GroupClosed: the bead is closed ([RuleClosed]).
	GroupClosed Group = "closed"
)

// Rule is the rule that placed a bead: the first that applies, in the order
// table tries them, which docs/gctk-architecture.md gives as well ("The bead
// stands contract"). The rules below are declared in that order, unread aside.
// Each applies only where none above it did, and says the group it gives.
type Rule string

const (
	// RuleClosed: the bead is closed. Group closed.
	RuleClosed Rule = "closed"
	// RuleAsk: the bead is itself an ask, which the answer's Ask names
	// ([Ask]). Group waiting-on-you.
	RuleAsk Rule = "ask"
	// RuleOwnWait: a human gate, or a bead only a person clears
	// ([person.Clears]), holds the bead through a wait of its own, as
	// prstatus.Holding walks what a person owes. Group waiting-on-you.
	RuleOwnWait Rule = "own-wait"
	// RuleFurtherAlong: such a gate or bead holds the bead further along its
	// waits, an ancestor's included. Group waiting-on-you.
	RuleFurtherAlong Rule = "further-along"
	// RuleParked: a gate that is no human gate, such as a park
	// (docs/steering.md, "A park"), holds the bead through a wait of its own
	// or an ancestor's, as gateHold reads it. Group not-moving.
	RuleParked Rule = "parked"
	// RuleStatus: the bead's status is one no pool offers, such as deferred.
	// Gas Town's pending record, the record a PR's bead carries from its
	// publication to its merge (services/gctk/pr/record declares its values,
	// and docs/state-machine.md, "The pending record", defines them), writes a
	// blocked status on a bead whose pull request it holds. That status is the
	// record's own and holds nothing, so it is not one of these. Group
	// not-moving.
	RuleStatus Rule = "status"
	// RuleStaying: the bead is a conversation its sitting stays in, or a
	// decision a ruling left waiting on the work it sent ([person.Stays]). It
	// is a person's move again once that work closes. Group queued.
	RuleStaying Rule = "staying"
	// RuleAnswers: the bead is a conversation that is no ask, which answers a
	// question whose row carries it. No group: it has no move of its own.
	RuleAnswers Rule = "answers"
	// RuleMembers: the bead is an epic or a Delivery that is no ruling, with
	// open members or none at all. No group: it has no move of its own.
	RuleMembers Rule = "members"
	// RuleGate: the bead is a gate that is no human gate, which holds what
	// waits on it and asks no one. No group: it has no move of its own.
	RuleGate Rule = "gate"
	// RuleNotScheduled: the work is ready work that nothing sends anywhere, as
	// queue's order lists it (queue.Ordered's NotScheduled): the store's ready
	// set serves it, no dispatch hold holds it, and nothing sends it, whatever
	// stamps its row carries. Group not-moving.
	RuleNotScheduled Rule = "not-scheduled"
	// RuleOutside: the work waits outside the city, as queue's order names it
	// (queue.Place's Outside): hold:external holds it and no live run works
	// it. Group not-moving.
	RuleOutside Rule = "outside"
	// RuleForProductOwner: nothing sends the work, and it is held for the
	// Product Owner's placement, as queue reads that hold
	// (queue.ForProductOwner). Group not-moving.
	RuleForProductOwner Rule = "for-product-owner"
	// RuleInFlight: the bead is work in flight, as waits answers it
	// (docs/steering.md, "In flight"), or work a live run works, from the
	// run's start. Group queued.
	RuleInFlight Rule = "in-flight"
	// RuleScheduled: something sends the work as things stand, as its place in
	// queue's order says (queue.Place): it is armed, routed to a pool or
	// assigned to an agent, and no dispatch hold holds it. Group queued.
	RuleScheduled Rule = "scheduled"
	// RuleNotReady: any other work, which nothing sends and the store does not
	// serve as ready. The answer names each wait that holds it. Group
	// not-moving.
	RuleNotReady Rule = "not-ready"
	// RuleUnread: a reader could not answer the part a rule needs, so the
	// answer stops at that rule, in no group, and its Why says what it could
	// not answer.
	RuleUnread Rule = "unread"
)

// Ask is what a person owes when a bead is itself the ask, one of the five
// below, which askOf reads. docs/bead-standing.md gives each ask to a person,
// beside the words the board shows for it (services/helm/internal/rigboard),
// with what the person can do.
type Ask string

const (
	// AskQuestion: an open human gate, or an open decision that does not wait
	// on work of its own first ([person.Stays]). A decision that waits on the
	// work a ruling sent is no person's move until that work closes.
	AskQuestion Ask = "question"
	// AskConversation: an open conversation that its sitting does not stay
	// in, that replies to no open human gate, and that tracks no open
	// decision that is a question. One that replies to such a gate or tracks
	// such a decision answers that question instead. One its sitting stays
	// in waits for the return of the work it sent, which comes back to the
	// operator once that work closes, so until then it is no person's move.
	AskConversation Ask = "conversation"
	// AskPullRequest: a bead whose pull request reads needs-review or
	// needs-attention ([prstatus.NeedsReview], [prstatus.NeedsAttention]).
	AskPullRequest Ask = "pull-request"
	// AskAssignedToYou: any other open bead only a person clears
	// ([person.Clears]), such as one assigned to human.
	AskAssignedToYou Ask = "assigned-to-you"
	// AskRuling: an epic with members and none of them open, or a landed
	// Delivery, which waits for the operator's review of the epic
	// (docs/epics.md, "Reviewing an epic").
	AskRuling Ask = "ruling"
)

// Kind is what a bead is, one of the six below, which kindOf reads.
type Kind string

const (
	// KindEpic: a bead whose type is epic, other than a Delivery.
	KindEpic Kind = "epic"
	// KindDelivery: an epic whose parent is an epic and which carries no
	// hypothesis (docs/epics.md, "What a Delivery is as a bead").
	KindDelivery Kind = "delivery"
	// KindWork: a bead that is none of the others, such as a task or a bug.
	KindWork Kind = "work"
	// KindGate: a bead whose type is gate, a human gate or any other.
	KindGate Kind = "gate"
	// KindDecision: a bead whose type is decision.
	KindDecision Kind = "decision"
	// KindConversation: a conversation, a task in the shape conversation.Shape
	// reads.
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

// kindOf is what a bead is ([Kind]): its own kind, or a Delivery, which takes
// its parent to tell.
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
// reading as an epic.
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

// answer answers each bead named that the read holds a bead for and has not
// answered.
func (r *Reading) answer(ids []string) {
	for _, id := range ids {
		b, ok := r.beads[id]
		if !ok {
			continue
		}
		if _, done := r.answers[id]; done {
			continue
		}
		k := r.kinds[id]
		var ask Ask
		// Work held for the Product Owner asks nothing of a person, whatever it
		// would ask, such as a review of its pull request: hold:mayor names the
		// Product Owner as its next actor.
		if !r.ForProductOwner(id) {
			members, open := 0, 0
			if k == KindEpic || k == KindDelivery {
				all, live := r.members(id)
				members, open = len(all), len(live)
			}
			ask = r.askOf(b, k, r.stays, open, members)
		}
		r.answers[id] = r.table(b, k, ask, r.stays)
	}
}

// members are an epic's or a Delivery's members, by id, and the open ones
// among them: the work, the Deliveries and the child epics its children's
// parent-child edges place under it. A child epic with a hypothesis of its own
// reads as an epic, not a Delivery, and while it is open its parent is not
// done.
func (r *Reading) members(id string) (all, open []string) {
	for _, c := range r.children[id] {
		if ck := r.kinds[c]; ck == KindWork || ck == KindDelivery || ck == KindEpic {
			all = append(all, c)
			if isOpen(r.beads[c]) {
				open = append(open, c)
			}
		}
	}
	return all, open
}

// reach is the beads the advance and the frontier of the beads named read,
// which the read holds and has not answered: each wait of a bead the read was
// asked about, which its frontier reads; each bead a queued bead waits on,
// which it advances behind; and each open member of an epic or a Delivery the
// members rule placed, which it advances with. A wait on a bead with no
// standing of its own reaches the bead that speaks for it.
func (r *Reading) reach(ids []string) []string {
	var next []string
	add := func(id string) {
		if t, ok := r.through[id]; ok {
			id = t
		}
		if _, held := r.beads[id]; !held {
			return
		}
		if _, done := r.answers[id]; !done && !slices.Contains(next, id) {
			next = append(next, id)
		}
	}
	for _, id := range ids {
		a, ok := r.answers[id]
		if !ok {
			continue
		}
		if r.asked[id] {
			for _, w := range r.holds[id].Waits {
				add(w.ID)
			}
		}
		switch a.Rule {
		case RuleStaying, RuleInFlight, RuleScheduled:
			for _, n := range a.Names {
				add(n.ID)
			}
		case RuleMembers:
			_, open := r.members(id)
			for _, m := range open {
				add(m)
			}
		}
	}
	sort.Strings(next)
	return next
}

// askOf is whether a bead is itself an ask, and which ([Ask] says when each
// applies): what the shared readers count as a person's move, and a ruling. A
// gate, a decision and a conversation are each answered by their kind alone,
// so a gate that is no human gate is never an ask. An epic or a Delivery is
// tried as a ruling first. Any other bead, and an epic or a Delivery that is
// no ruling, is tried as a pull request, then as assigned to you.
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
		return AskAssignedToYou
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

// table answers one bead, whose ask askOf read. The first rule that applies
// answers, tried in this order ([Rule] says when each applies and the group it
// gives):
//
//  1. closed
//  2. ask
//  3. own-wait, or further-along
//  4. parked
//  5. status
//  6. staying
//  7. answers, members or gate, by the bead's kind
//  8. not-scheduled, outside or for-product-owner, by the work's place in
//     queue's order
//  9. in-flight
//  10. scheduled
//  11. not-ready
//
// A bead a reader could not answer reads unread at the rule that needs the
// answer.
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
	place, placed := r.places[b.ID]
	if placed && r.unsent[b.ID] {
		return Answer{Group: GroupNotMoving, Rule: RuleNotScheduled}
	}
	if placed && place.Outside {
		return Answer{Group: GroupNotMoving, Rule: RuleOutside}
	}
	if placed && !place.Scheduled && queue.ForProductOwner(b.Labels) {
		return Answer{Group: GroupNotMoving, Rule: RuleForProductOwner}
	}
	// waits counts a run in flight only once it has passed load-context, which
	// answers whether an ancestor's wait still holds work that has not
	// started. A bead a live run works is the city's from the run's start.
	if h.InFlight != "" || r.worked[b.ID] != "" {
		return Answer{Group: GroupQueued, Rule: RuleInFlight, Names: refsOf(h.Waits)}
	}
	if !placed {
		return Answer{Rule: RuleUnread, Why: "queue placed it nowhere"}
	}
	if place.Scheduled {
		return Answer{Group: GroupQueued, Rule: RuleScheduled, Names: refsOf(h.Waits)}
	}
	return Answer{Group: GroupNotMoving, Rule: RuleNotReady, Names: refsOf(h.Waits)}
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
// (docs/steering.md, "A park"), whose gate gctk bead park files with no await
// type. A gate of a type bd closes by itself, such as a timer, reads as one
// too. A gate the city closes ([gate.CityCloses]), a stay's, is none: a
// conversation that waits on it stays.
func gateHold(h waits.Holds) *waits.Wait {
	for i, w := range h.Waits {
		if strings.EqualFold(w.IssueType, "gate") && !person.IsHumanGate(w.IssueType, w.AwaitType) && !gate.CityCloses(w.IssueType, w.AwaitType) {
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
