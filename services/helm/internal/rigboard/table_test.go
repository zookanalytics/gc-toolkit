package rigboard

import (
	"slices"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/listing"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

func noOwed(prstatus.Blocker) string { return "" }

// TestTableRows walks the table's rows in order: each case is the first row
// that matches, so an earlier row's answer stands over a later one's.
func TestTableRows(t *testing.T) {
	work := bead{ID: "tk-w", Status: "open", IssueType: "task"}
	clear := &waits.Holds{ID: "tk-w", Status: waits.Clear}
	gateWait := waits.Wait{ID: "tk-g", Type: "blocks", Title: "a question", Status: "open", IssueType: "gate", AwaitType: "human"}
	parkWait := waits.Wait{ID: "tk-park", Type: "blocks", Title: "parked until the review", Status: "open", IssueType: "gate"}
	workWait := waits.Wait{ID: "tk-other", Type: "blocks", Title: "other work", Status: "open", IssueType: "task"}
	blockedOn := func(ws ...waits.Wait) *waits.Holds {
		return &waits.Holds{ID: "tk-w", Status: waits.Blocked, Waits: ws}
	}
	humanGate := prstatus.Blocker{ID: "tk-g", Title: "a question", Status: "open", IssueType: "gate", AwaitType: "human"}
	conv := func(assignee string) prstatus.Blocker {
		return prstatus.Blocker{ID: "tk-c", Title: "talk", Status: "open", IssueType: "task", Assignee: assignee}
	}
	decision := prstatus.Blocker{ID: "tk-d", Title: "pick one", Status: "open", IssueType: "decision"}
	withAsk := func(id string, a *askAnswer) func(prstatus.Blocker) string {
		return func(b prstatus.Blocker) string {
			if b.ID == id {
				return a.words
			}
			return ""
		}
	}

	cases := []struct {
		name   string
		in     tableInput
		out    outcome
		group  Group
		signal string
		note   string
		line3  []string
	}{
		{name: "closed reads how it closed",
			in:  tableInput{b: bead{ID: "tk-w", Status: "closed", WorkOutcome: "shipped"}, kind: KindWork},
			out: outClosed, group: GroupClosed, signal: "Closed", note: "shipped"},
		{name: "an ask reads its words before anything holds it",
			in:  tableInput{b: work, kind: KindWork, ask: &askAnswer{kind: AskRoutedToYou, words: "Routed to you"}, holds: blockedOn(workWait)},
			out: outAsk, group: GroupWaitingOnYou, signal: "Routed to you"},
		{name: "an own human gate waits on your answer",
			in: tableInput{b: work, kind: KindWork, holds: blockedOn(gateWait),
				holding: &prstatus.Holds{Gates: []prstatus.Blocker{humanGate}}, owedSignal: noOwed},
			out: outOwnWait, group: GroupWaitingOnYou, signal: "Waits on your answer"},
		{name: "an own conversation in your queue waits for you",
			in: tableInput{b: work, kind: KindWork, holds: blockedOn(waits.Wait{ID: "tk-c", Type: "blocks", Status: "open", IssueType: "task"}),
				holding: &prstatus.Holds{Owed: []prstatus.Blocker{conv("human")}}, owedSignal: noOwed},
			out: outOwnWait, group: GroupWaitingOnYou, signal: "Conversation waits for you"},
		{name: "an own conversation a sitting holds is in conversation",
			in: tableInput{b: work, kind: KindWork, holds: blockedOn(waits.Wait{ID: "tk-c", Type: "blocks", Status: "open", IssueType: "task"}),
				holding: &prstatus.Holds{Owed: []prstatus.Blocker{conv("gc-toolkit/gc-toolkit.tk-c")}}, owedSignal: noOwed},
			out: outOwnWait, group: GroupWaitingOnYou, signal: "In conversation"},
		{name: "an own owed bead reads that bead's own signal",
			in: tableInput{b: work, kind: KindWork, holds: blockedOn(waits.Wait{ID: "tk-d", Type: "blocks", Status: "open", IssueType: "decision"}),
				holding:    &prstatus.Holds{Owed: []prstatus.Blocker{decision}},
				owedSignal: withAsk("tk-d", &askAnswer{kind: AskQuestion, words: "Question"})},
			out: outOwnWait, group: GroupWaitingOnYou, signal: "Question"},
		{name: "a person's move further along names the wait and ends on what Holding returned first",
			in: tableInput{b: work, kind: KindWork, holds: blockedOn(workWait),
				holding: &prstatus.Holds{Gates: []prstatus.Blocker{humanGate}, Owed: []prstatus.Blocker{decision}}, owedSignal: noOwed},
			out: outEndsOnYou, group: GroupWaitingOnYou, signal: "Waits on tk-other", line3: []string{"tk-g"}},
		{name: "a held bead's ancestor gate a person answers is further along",
			in: tableInput{b: work, kind: KindWork,
				holds:   &waits.Holds{ID: "tk-w", Status: waits.Held, Waits: []waits.Wait{{ID: "tk-g", Type: "blocks", Status: "open", IssueType: "gate", AwaitType: "human", Ancestor: "tk-e"}}},
				holding: &prstatus.Holds{Gates: []prstatus.Blocker{humanGate}}, owedSignal: noOwed},
			out: outEndsOnYou, group: GroupWaitingOnYou, signal: "Waits on tk-g", line3: []string{"tk-g"}},
		{name: "a gate no person answers holds it",
			in:  tableInput{b: work, kind: KindWork, holds: blockedOn(workWait, parkWait), holding: &prstatus.Holds{}, owedSignal: noOwed},
			out: outHeldByGate, group: GroupNotMoving, signal: "Held by a gate", note: "parked until the review"},
		{name: "an ancestor's gate no person answers holds it",
			in: tableInput{b: work, kind: KindWork,
				holds: &waits.Holds{ID: "tk-w", Status: waits.Held, Waits: []waits.Wait{{ID: "tk-park", Type: "blocks", Status: "open", IssueType: "gate", Title: "parked", Ancestor: "tk-e"}}}},
			out: outHeldByGate, group: GroupNotMoving, signal: "Held by a gate", note: "parked"},
		{name: "deferred",
			in:  tableInput{b: bead{ID: "tk-w", Status: "deferred"}, kind: KindWork, holds: clear},
			out: outNotOpen, group: GroupNotMoving, signal: "Deferred"},
		{name: "another status reads as the store's word",
			in:  tableInput{b: bead{ID: "tk-w", Status: "blocked"}, kind: KindWork, holds: clear},
			out: outNotOpen, group: GroupNotMoving, signal: "blocked"},
		{name: "in flight names its assignee",
			in:  tableInput{b: bead{ID: "tk-w", Status: "in_progress", Assignee: "gc-toolkit/gc-toolkit.polecat-1"}, kind: KindWork, holds: &waits.Holds{Status: waits.Clear, InFlight: "status in_progress"}},
			out: outInFlight, group: GroupQueued, signal: "In flight", note: "gc-toolkit/gc-toolkit.polecat-1"},
		{name: "in flight with an open pull request names it and where it stands",
			in: tableInput{b: bead{ID: "tk-w", Status: "open", MergeResult: "pull_request", PRNumber: "12"}, kind: KindWork,
				holds: &waits.Holds{Status: waits.Clear, InFlight: "carries merge_result"}, facts: &prstatus.Facts{InFlightCount: 1}},
			out: outPullRequest, group: GroupQueued, signal: "Pull request #12", note: "working"},
		{name: "armed and clear is queued",
			in:  tableInput{b: work, kind: KindWork, holds: &waits.Holds{Status: waits.Clear, Arm: &waits.Arm{Target: "gc-toolkit/gc-toolkit.polecat"}}},
			out: outQueued, group: GroupQueued, signal: "Queued"},
		{name: "routed and held behind work names each wait",
			in: tableInput{b: bead{ID: "tk-w", Status: "open", RoutedTo: "gc-toolkit/gc-toolkit.polecat"}, kind: KindWork,
				holds: blockedOn(workWait), owedSignal: noOwed},
			out: outQueuedBehind, group: GroupQueued, signal: "Waits on tk-other"},
		{name: "assigned to an agent is queued",
			in:  tableInput{b: bead{ID: "tk-w", Status: "open", Assignee: "gc-toolkit.mechanik"}, kind: KindWork, holds: clear},
			out: outQueued, group: GroupQueued, signal: "Queued"},
		{name: "nobody scheduled it, and line 3 names what it waits on",
			in:  tableInput{b: work, kind: KindWork, holds: blockedOn(workWait), owedSignal: noOwed},
			out: outNotScheduled, group: GroupNotMoving, signal: "Not scheduled", line3: []string{"tk-other"}},
		{name: "rows 6 to 8 never apply to an epic",
			in:  tableInput{b: bead{ID: "tk-e", Status: "open", IssueType: "epic", Assignee: "gc-toolkit.mechanik"}, kind: KindEpic, holds: clear},
			out: outNone},
		{name: "a bead waits could not answer is unread",
			in:  tableInput{b: work, kind: KindWork},
			out: outUnread, signal: "unread"},
		{name: "a walk past its bound leaves the bead unread",
			in:  tableInput{b: work, kind: KindWork, holds: blockedOn(workWait), unwalked: true},
			out: outUnread, signal: "unread"},
		{name: "a pull request prstatus could not answer is unread before any ask",
			in:  tableInput{b: work, kind: KindWork, ask: &askAnswer{kind: AskRoutedToYou, words: "Routed to you"}, prUnread: true},
			out: outUnread, signal: "unread"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			v := table(c.in)
			var line3 []string
			for _, r := range v.line3 {
				line3 = append(line3, r.ID)
			}
			if v.out != c.out || v.group != c.group || v.signal != c.signal || v.note != c.note || !slices.Equal(line3, c.line3) {
				t.Errorf("got out=%d group=%q signal=%q note=%q line3=%v\nwant out=%d group=%q signal=%q note=%q line3=%v",
					v.out, v.group, v.signal, v.note, line3, c.out, c.group, c.signal, c.note, c.line3)
			}
		})
	}
}

// TestAsks holds each kind of ask to the reader that counts it.
func TestAsks(t *testing.T) {
	noGate := func(string) bool { return false }
	openGate := func(id string) bool { return id == "tk-g" }
	needsReview := &prstatus.Facts{}
	working := &prstatus.Facts{InFlightCount: 1}
	cases := []struct {
		name        string
		b           bead
		kind        Kind
		conv, convA string
		gateOpen    func(string) bool
		facts       *prstatus.Facts
		open, all   int
		want        *askAnswer
	}{
		{name: "a human gate is a question", b: bead{ID: "tk-g", Status: "open", IssueType: "gate", AwaitType: "human"}, kind: KindGate,
			want: &askAnswer{kind: AskQuestion, words: "Question"}},
		{name: "a human gate a conversation answers reads the conversation", b: bead{ID: "tk-g", Status: "open", IssueType: "gate", AwaitType: "human"}, kind: KindGate,
			conv: "tk-c", convA: "human", want: &askAnswer{kind: AskQuestion, words: "Conversation waits for you"}},
		{name: "a gate no person answers is never an ask", b: bead{ID: "tk-p", Status: "open", IssueType: "gate", RoutedTo: "human", PersonBlocker: true}, kind: KindGate},
		{name: "a decision is a question", b: bead{ID: "tk-d", Status: "open", IssueType: "decision"}, kind: KindDecision,
			want: &askAnswer{kind: AskQuestion, words: "Question"}},
		{name: "a conversation is its own ask", b: bead{ID: "tk-c", Status: "open", IssueType: "task", Assignee: "human"}, kind: KindConversation,
			gateOpen: noGate, want: &askAnswer{kind: AskConversation, words: "Conversation waits for you"}},
		{name: "a conversation that replies to an open human gate belongs to its ask",
			b:    bead{ID: "tk-c", Status: "open", IssueType: "task", Assignee: "human", Edges: []listing.Edge{{ID: "tk-g", Type: "replies-to"}}},
			kind: KindConversation, gateOpen: openGate},
		{name: "a pull request needing review is an ask in prstatus's words", b: bead{ID: "tk-w", Status: "open"}, kind: KindWork,
			facts: needsReview, want: &askAnswer{kind: AskPullRequest, words: "needs-review"}},
		{name: "a pull request the city is changing is no ask", b: bead{ID: "tk-w", Status: "open"}, kind: KindWork, facts: working},
		{name: "work routed to a person is routed to you", b: bead{ID: "tk-w", Status: "open", RoutedTo: "human", PersonBlocker: true}, kind: KindWork,
			want: &askAnswer{kind: AskRoutedToYou, words: "Routed to you"}},
		{name: "an epic whose members all closed needs a ruling", b: bead{ID: "tk-e", Status: "open", IssueType: "epic"}, kind: KindEpic,
			open: 0, all: 3, want: &askAnswer{kind: AskRuling, words: "Needs a ruling"}},
		{name: "a landed Delivery waits for its checkpoint", b: bead{ID: "tk-e.1", Status: "open", IssueType: "epic"}, kind: KindDelivery,
			open: 0, all: 2, want: &askAnswer{kind: AskRuling, words: "landed — waits for its Epic Checkpoint"}},
		{name: "an epic with open members needs no ruling", b: bead{ID: "tk-e", Status: "open", IssueType: "epic"}, kind: KindEpic, open: 1, all: 3},
		{name: "an epic with no members needs no ruling", b: bead{ID: "tk-e", Status: "open", IssueType: "epic"}, kind: KindEpic},
		{name: "a closed bead is no ask", b: bead{ID: "tk-d", Status: "closed", IssueType: "decision"}, kind: KindDecision},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			gateOpen := c.gateOpen
			if gateOpen == nil {
				gateOpen = noGate
			}
			got := askOf(c.b, c.kind, c.conv, c.convA, gateOpen, c.facts, c.open, c.all)
			if (got == nil) != (c.want == nil) || (got != nil && *got != *c.want) {
				t.Errorf("askOf = %+v, want %+v", got, c.want)
			}
		})
	}
}
