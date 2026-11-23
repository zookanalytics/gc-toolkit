package rigboard

import (
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/conversation"
	"github.com/zookanalytics/gc-toolkit/services/gctk/standing"
	"github.com/zookanalytics/gc-toolkit/services/gctk/standing/person"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// The board's words for where a row's bead stands. standing answers the bead's
// group, the rule that placed it, its ask and the beads that rule names, and
// this file is the only place the row's words for that answer are chosen:
//
//   - closed: "Closed", with how it closed.
//   - ask: the ask's words. A question reads "Question", or the words of the
//     conversation that answers it. A conversation reads whether it waits for
//     you or a sitting holds it. A pull request reads where it stands, a
//     ruling what it waits for, and a bead only a person clears "Assigned to
//     you".
//   - own-wait: "Waits on your answer" for a human gate or a decision, the
//     conversation's words for a conversation, and otherwise "Waits on <id>"
//     naming each of its waits, so a bead behind another bead's pull request
//     names that bead and never takes its words.
//   - further-along: "Waits on <id>", naming each of its waits, with line 3
//     naming the gate or the bead a person owes.
//   - parked: "Held by a gate", with the gate's title.
//   - status: "Deferred", or the store's word for any other status.
//   - staying: "Waits on <id>", naming each wait.
//   - answers: the conversation's words. members and gate: nothing.
//   - in-flight: "Pull request #<n>", with where it stands, or "In flight",
//     with its assignee.
//   - scheduled: "Queued" when nothing holds it, and "Waits on <id>" naming
//     each wait when one does.
//   - not-scheduled: "Not scheduled", whatever stamps its row carries, so the
//     row and the Work queue's list of ready work nothing sends give one
//     answer.
//   - outside: "Waits outside the city".
//   - for-product-owner: "Waits for the Product Owner".
//   - not-ready: "Waits on <id>" naming each wait, or "Not ready" when it waits
//     on nothing waits names.
//   - unread: "unread", in no group.

// Group is the label the board shows for where a row's work stands, one for
// each of standing's groups, which [standing.Group] defines. A row no group
// holds, such as a gate, or a bead a reader could not answer, carries none.
// docs/bead-standing.md gives each label to a person.
type Group string

const (
	GroupWaitingOnYou Group = "Waiting on you"
	GroupQueued       Group = "Queued"
	GroupNotMoving    Group = "Not moving"
	GroupClosed       Group = "Closed"
)

// groupOf is a standing group's label.
func groupOf(g standing.Group) Group {
	switch g {
	case standing.GroupWaitingOnYou:
		return GroupWaitingOnYou
	case standing.GroupQueued:
		return GroupQueued
	case standing.GroupNotMoving:
		return GroupNotMoving
	case standing.GroupClosed:
		return GroupClosed
	}
	return ""
}

// Ask is the kind of thing a person owes a move on, for a row that is an
// ask, one for each of standing's asks, which [standing.Ask] defines.
// docs/bead-standing.md gives each to a person.
type Ask string

const (
	AskQuestion      Ask = "Question"
	AskConversation  Ask = "Conversation"
	AskPullRequest   Ask = "Pull request"
	AskAssignedToYou Ask = "Assigned to you"
	AskRuling        Ask = "Ruling"
)

// NeedKind is the kind of need a row is, the kinds a Needs you view counts and
// filters its needs by. It is the row's ask, in the ask's own words, except
// that a conversation's kind says whether it waits for you or a sitting holds
// it, and a question a sitting is talking over is in conversation too, since
// your attention is already on it.
type NeedKind string

const (
	NeedKindPullRequest    NeedKind = "Pull request"
	NeedKindQuestion       NeedKind = "Question"
	NeedKindWaitsForYou    NeedKind = "Conversation waits for you"
	NeedKindInConversation NeedKind = "In conversation"
	NeedKindRuling         NeedKind = "Ruling"
	NeedKindAssignedToYou  NeedKind = "Assigned to you"
)

// verdict is a row's words for its standing.
type verdict struct {
	rule   standing.Rule
	group  Group
	signal string
	note   string
	line3  []Ref
}

// askAnswer is what makes a row an ask, the words its signal reads, and the
// kind of need it is.
type askAnswer struct {
	kind  Ask
	words string
	need  NeedKind
}

// Words the board writes that another document already gives.
const (
	signalUnread = "unread"
	// docs/epics.md, "How a Delivery ends", gives a landed Delivery's row.
	signalLandedDelivery = "landed — waits for its Epic Checkpoint"
	signalNeedsRuling    = "Needs a ruling"
)

// conversationKind is whether a conversation waits in the operator's queue or a
// sitting holds it, read off its assignee as conversation.IsAssignee reads one.
func conversationKind(assignee string) NeedKind {
	if strings.TrimSpace(assignee) == "human" {
		return NeedKindWaitsForYou
	}
	return NeedKindInConversation
}

// conversationWords is what a conversation's row says: its kind, in words.
func conversationWords(assignee string) string { return string(conversationKind(assignee)) }

// askWords is a row's ask in the board's words, nil for a row that is no ask.
func (bt *built) askWords(id string, a standing.Answer) *askAnswer {
	if a.Rule != standing.RuleAsk {
		return nil
	}
	ix := bt.ix
	b := ix.beads[id]
	switch a.Ask {
	case standing.AskQuestion:
		conv := ix.answeredBy[id]
		return questionAsk(conv, ix.beads[conv].Assignee)
	case standing.AskConversation:
		return &askAnswer{kind: AskConversation, words: conversationWords(b.Assignee), need: conversationKind(b.Assignee)}
	case standing.AskPullRequest:
		st := ""
		if p := ix.g.reading.PullRequest(id); p != nil {
			st = string(p.State())
		}
		return &askAnswer{kind: AskPullRequest, words: st, need: NeedKindPullRequest}
	case standing.AskAssignedToYou:
		return &askAnswer{kind: AskAssignedToYou, words: string(AskAssignedToYou), need: NeedKindAssignedToYou}
	case standing.AskRuling:
		if ix.kinds[id] == KindDelivery {
			return &askAnswer{kind: AskRuling, words: signalLandedDelivery, need: NeedKindRuling}
		}
		return &askAnswer{kind: AskRuling, words: signalNeedsRuling, need: NeedKindRuling}
	}
	return nil
}

// questionAsk is a question's ask: "Question", or its conversation's words when
// one answers it, a conversation that replies to a gate or tracks a decision.
// It is in conversation once a sitting holds that conversation, and a question
// otherwise.
func questionAsk(answeredBy, assignee string) *askAnswer {
	if answeredBy == "" {
		return &askAnswer{kind: AskQuestion, words: string(AskQuestion), need: NeedKindQuestion}
	}
	a := &askAnswer{kind: AskQuestion, words: conversationWords(assignee), need: NeedKindQuestion}
	if conversationKind(assignee) == NeedKindInConversation {
		a.need = NeedKindInConversation
	}
	return a
}

// verdictOf is a row's words for its standing.
func (bt *built) verdictOf(id string, a standing.Answer) verdict {
	b := bt.ix.beads[id]
	v := verdict{rule: a.Rule, group: groupOf(a.Group)}
	h, _ := bt.ix.g.reading.Holds(id)
	waitRefs := refsOf(h.Waits)
	switch a.Rule {
	case standing.RuleClosed:
		v.signal, v.note = "Closed", b.WorkOutcome
	case standing.RuleUnread:
		v.signal = signalUnread
	case standing.RuleAsk:
		if ask := bt.asks[id]; ask != nil {
			v.signal = ask.words
		}
	case standing.RuleOwnWait:
		v.signal = ownWaitWords(a.Owed, waitRefs)
	case standing.RuleFurtherAlong:
		first := a.Names[0]
		v.line3 = []Ref{{ID: first.ID, Title: first.Title}}
		v.signal = "Waits on " + first.ID
		if len(waitRefs) > 0 {
			v.signal = "Waits on " + joinIDs(waitRefs)
		}
	case standing.RuleParked:
		v.signal, v.note = "Held by a gate", a.Names[0].Title
	case standing.RuleStatus:
		v.signal = status(b)
		if v.signal == "deferred" {
			v.signal = "Deferred"
		}
	case standing.RuleStaying:
		v.signal = "Waits on " + joinIDs(waitRefs)
	case standing.RuleAnswers:
		v.signal = conversationWords(b.Assignee)
	case standing.RuleInFlight:
		if p := bt.ix.g.reading.PullRequest(id); p != nil && b.PRNumber != "" {
			v.signal, v.note = "Pull request #"+b.PRNumber, string(p.State())
		} else {
			v.signal, v.note = "In flight", b.Assignee
		}
	case standing.RuleScheduled:
		v.signal = "Queued"
		if h.Status != waits.Clear {
			v.signal = "Waits on " + joinIDs(waitRefs)
		}
	case standing.RuleNotScheduled:
		v.signal = "Not scheduled"
	case standing.RuleOutside:
		v.signal = "Waits outside the city"
	case standing.RuleForProductOwner:
		v.signal = "Waits for the Product Owner"
	case standing.RuleNotReady:
		v.signal = "Not ready"
		if len(waitRefs) > 0 {
			v.signal = "Waits on " + joinIDs(waitRefs)
		}
	}
	return v
}

// ownWaitWords is the words of a row a gate or a bead a person owes holds
// through one of its own waits.
func ownWaitWords(o *person.Blocker, waitRefs []Ref) string {
	switch {
	case person.IsHumanGate(o.IssueType, o.AwaitType):
		return "Waits on your answer"
	case conversation.IsCandidate(strings.ToLower(o.IssueType), o.Assignee, o.ID):
		return conversationWords(o.Assignee)
	case strings.EqualFold(strings.TrimSpace(o.IssueType), "decision"):
		return "Waits on your answer"
	}
	return "Waits on " + joinIDs(waitRefs)
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

// pullRequestOf is a bead's pull request in the pack's words, nil when it
// records none.
func pullRequestOf(b bead, p *standing.PR) *PullRequest {
	n := b.PRNumber
	if n == "" {
		return nil
	}
	out := &PullRequest{Number: n, URL: b.PRURL}
	if p != nil {
		out.State = string(p.State())
		for _, h := range p.Held() {
			out.Held = append(out.Held, string(h))
		}
	}
	return out
}

// reasonsOf is what holds a pull request, in the pack's words.
func reasonsOf(p *standing.PR) []Reason {
	if p == nil {
		return nil
	}
	var out []Reason
	for _, r := range p.Reasons() {
		out = append(out, Reason{Held: string(r.Held), ID: r.ID, Title: r.Title})
	}
	return out
}
