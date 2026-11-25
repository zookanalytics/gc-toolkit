package standing

import (
	"slices"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus"
	"github.com/zookanalytics/gc-toolkit/services/gctk/queue"
	"github.com/zookanalytics/gc-toolkit/services/gctk/standing/person"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// facts is what a test gives the table about one bead: the readers' answers a
// read would have gathered.
type facts struct {
	holds    *waits.Holds
	holding  *prstatus.Holds
	unwalked bool
	pr       *prstatus.Facts
	answer   *pr.Answer
	prUnread bool
	place    *queue.Place
	// notScheduled is true for work queue's order lists as ready work that
	// nothing sends anywhere, and worked for a bead a live run works.
	notScheduled bool
	worked       bool
}

// readingOf is a read holding one bead and the readers' answers about it.
func readingOf(b Bead, k Kind, f facts) *Reading {
	r := &Reading{beads: map[string]Bead{b.ID: b}, kinds: map[string]Kind{b.ID: k}, answers: map[string]Answer{},
		answeredBy: map[string]string{}, holds: map[string]waits.Holds{}, unread: map[string]error{},
		holding: map[string]prstatus.Holds{}, unwalked: map[string]bool{}, facts: map[string]prstatus.Facts{},
		prAnswers: map[string]pr.Answer{}, noFacts: map[string]bool{}, places: map[string]queue.Place{},
		unsent: map[string]bool{}, worked: map[string]string{}}
	if f.notScheduled {
		r.unsent[b.ID] = true
	}
	if f.worked {
		r.worked[b.ID] = "tk-root"
	}
	if f.holds != nil {
		r.holds[b.ID] = *f.holds
		if root := rootOf(b.ID, *f.holds); root != "" {
			if f.holding != nil {
				r.holding[root] = *f.holding
			}
			if f.unwalked {
				r.unwalked[root] = true
			}
		}
	}
	if f.pr != nil {
		r.facts[b.ID] = *f.pr
		if f.answer != nil {
			r.prAnswers[b.ID] = *f.answer
		}
	}
	if f.prUnread {
		r.noFacts[b.ID] = true
	}
	if f.place != nil {
		r.places[b.ID] = *f.place
	}
	return r
}

// TestTable walks the table's rows in order: each case is the first row that
// matches, so an earlier row's answer stands over a later one's.
func TestTable(t *testing.T) {
	work := Bead{ID: "tk-w", Status: "open", IssueType: "task"}
	clear := &waits.Holds{ID: "tk-w", Status: waits.Clear}
	gateWait := waits.Wait{ID: "tk-g", Type: "blocks", Title: "a question", Status: "open", IssueType: "gate", AwaitType: "human"}
	parkWait := waits.Wait{ID: "tk-park", Type: "blocks", Title: "parked until the review", Status: "open", IssueType: "gate"}
	workWait := waits.Wait{ID: "tk-other", Type: "blocks", Title: "other work", Status: "open", IssueType: "task"}
	blockedOn := func(ws ...waits.Wait) *waits.Holds {
		return &waits.Holds{ID: "tk-w", Status: waits.Blocked, Waits: ws}
	}
	humanGate := person.Blocker{ID: "tk-g", Title: "a question", Status: "open", IssueType: "gate", AwaitType: "human"}
	conv := person.Blocker{ID: "tk-c", Title: "talk", Status: "open", IssueType: "task", Assignee: "human"}
	decision := person.Blocker{ID: "tk-d", Title: "pick one", Status: "open", IssueType: "decision"}
	// A merge anchor whose pull request waits on a person's review, as
	// prstatus.Holding names it among the beads a person owes.
	owesReview := person.Blocker{ID: "tk-pr", Title: "land the change", Status: "open", IssueType: "task",
		Metadata: map[string]string{"merge_result": "pull_request_pending", "pr_number": "7", "pr_posture": "review_required@h@t"}}
	prWait := waits.Wait{ID: "tk-pr", Type: "blocks", Title: "land the change", Status: "open", IssueType: "task"}
	// Where queue placed the bead: in a place something sends it from, in one
	// nothing does, and waiting outside the city.
	taken := &queue.Place{ID: "tk-w", Layer: 1, Scheduled: true}
	untaken := &queue.Place{ID: "tk-w", Layer: 1}
	ready := &queue.Place{ID: "tk-w", Layer: 0}
	outside := &queue.Place{ID: "tk-w", Layer: 0, Outside: true}
	sitting := "gc-toolkit/gc-toolkit.tk-c"

	cases := []struct {
		name  string
		b     Bead
		kind  Kind
		ask   Ask
		f     facts
		rule  Rule
		group Group
		names []string
		owed  string
		state prstatus.State
	}{
		{name: "closed", b: Bead{ID: "tk-w", Status: "closed"}, kind: KindWork,
			rule: RuleClosed, group: GroupClosed},
		{name: "an ask answers before anything holds it", b: work, kind: KindWork, ask: AskAssignedToYou, f: facts{holds: blockedOn(workWait)},
			rule: RuleAsk, group: GroupWaitingOnYou},
		{name: "an own human gate is an own wait", b: work, kind: KindWork,
			f:    facts{holds: blockedOn(gateWait), holding: &prstatus.Holds{Gates: []person.Blocker{humanGate}}},
			rule: RuleOwnWait, group: GroupWaitingOnYou, names: []string{"tk-g"}, owed: "tk-g"},
		{name: "an own conversation is an own wait", b: work, kind: KindWork,
			f:    facts{holds: blockedOn(waits.Wait{ID: "tk-c", Type: "blocks", Status: "open", IssueType: "task"}), holding: &prstatus.Holds{Owed: []person.Blocker{conv}}},
			rule: RuleOwnWait, group: GroupWaitingOnYou, names: []string{"tk-c"}, owed: "tk-c"},
		{name: "an own decision is an own wait", b: work, kind: KindWork,
			f:    facts{holds: blockedOn(waits.Wait{ID: "tk-d", Type: "blocks", Status: "open", IssueType: "decision"}), holding: &prstatus.Holds{Owed: []person.Blocker{decision}}},
			rule: RuleOwnWait, group: GroupWaitingOnYou, names: []string{"tk-d"}, owed: "tk-d"},
		{name: "a bead behind another bead's pull request names that bead", b: work, kind: KindWork,
			f:    facts{holds: blockedOn(workWait, prWait), holding: &prstatus.Holds{Owed: []person.Blocker{owesReview}}},
			rule: RuleOwnWait, group: GroupWaitingOnYou, names: []string{"tk-pr"}, owed: "tk-pr"},
		{name: "a person's move further along names what Holding returned first, a gate before an owed bead", b: work, kind: KindWork,
			f:    facts{holds: blockedOn(workWait), holding: &prstatus.Holds{Gates: []person.Blocker{humanGate}, Owed: []person.Blocker{decision}}},
			rule: RuleFurtherAlong, group: GroupWaitingOnYou, names: []string{"tk-g"}, owed: "tk-g"},
		{name: "a held bead's ancestor gate a person answers is further along", b: work, kind: KindWork,
			f: facts{holds: &waits.Holds{ID: "tk-w", Status: waits.Held, Waits: []waits.Wait{{ID: "tk-g", Type: "blocks", Status: "open", IssueType: "gate", AwaitType: "human", Ancestor: "tk-e"}}},
				holding: &prstatus.Holds{Gates: []person.Blocker{humanGate}}},
			rule: RuleFurtherAlong, group: GroupWaitingOnYou, names: []string{"tk-g"}, owed: "tk-g"},
		{name: "a gate no person answers parks it", b: work, kind: KindWork, f: facts{holds: blockedOn(workWait, parkWait), holding: &prstatus.Holds{}},
			rule: RuleParked, group: GroupNotMoving, names: []string{"tk-park"}},
		{name: "an ancestor's gate no person answers parks it", b: work, kind: KindWork,
			f:    facts{holds: &waits.Holds{ID: "tk-w", Status: waits.Held, Waits: []waits.Wait{{ID: "tk-park", Type: "blocks", Status: "open", IssueType: "gate", Title: "parked", Ancestor: "tk-e"}}}},
			rule: RuleParked, group: GroupNotMoving, names: []string{"tk-park"}},
		{name: "deferred is a status no pool offers", b: Bead{ID: "tk-w", Status: "deferred"}, kind: KindWork, f: facts{holds: clear},
			rule: RuleStatus, group: GroupNotMoving},
		{name: "blocked on the old record is a status no pool offers", b: Bead{ID: "tk-w", Status: "blocked", MergeResult: "pull_request", PRNumber: "12"}, kind: KindWork,
			f: facts{holds: clear}, rule: RuleStatus, group: GroupNotMoving},
		{name: "in flight", b: Bead{ID: "tk-w", Status: "in_progress", Assignee: "gc-toolkit/gc-toolkit.polecat-1"}, kind: KindWork,
			f: facts{holds: &waits.Holds{Status: waits.Clear, InFlight: "status in_progress"}}, rule: RuleInFlight, group: GroupQueued},
		{name: "in flight with an open pull request, where it stands", b: Bead{ID: "tk-w", Status: "open", MergeResult: "pull_request", PRNumber: "12"}, kind: KindWork,
			f:    facts{holds: &waits.Holds{Status: waits.Clear, InFlight: "carries merge_result"}, pr: &prstatus.Facts{InFlightCount: 1}},
			rule: RuleInFlight, group: GroupQueued, state: prstatus.Working},
		{name: "the blocked status Gas Town's pending record writes holds nothing", b: Bead{ID: "tk-w", Status: "blocked", MergeResult: "pull_request_pending", PRNumber: "12"}, kind: KindWork,
			f:    facts{holds: &waits.Holds{Status: waits.Clear, InFlight: "carries merge_result"}, pr: &prstatus.Facts{MergeResult: "pull_request_pending"}, answer: &pr.Answer{Ready: true}},
			rule: RuleInFlight, group: GroupQueued, state: prstatus.Merging},
		{name: "a changed head the record holds blocked reads the same", b: Bead{ID: "tk-w", Status: "blocked", MergeResult: "pull_request_head_changed", PRNumber: "12"}, kind: KindWork,
			f: facts{holds: &waits.Holds{Status: waits.Clear, InFlight: "carries merge_result"}, pr: &prstatus.Facts{MergeResult: "pull_request_head_changed"},
				answer: &pr.Answer{Conditions: []pr.Condition{{Kind: pr.KindGitHubUnread}}}},
			rule: RuleInFlight, group: GroupQueued, state: prstatus.Working},
		{name: "armed and clear is scheduled", b: work, kind: KindWork, f: facts{holds: &waits.Holds{Status: waits.Clear, Arm: &waits.Arm{Target: "gc-toolkit/gc-toolkit.polecat"}}, place: taken},
			rule: RuleScheduled, group: GroupQueued},
		{name: "routed and held behind work names each wait", b: work, kind: KindWork, f: facts{holds: blockedOn(workWait), place: taken},
			rule: RuleScheduled, group: GroupQueued, names: []string{"tk-other"}},
		{name: "ready work nothing sends is not scheduled", b: work, kind: KindWork, f: facts{holds: clear, place: ready, notScheduled: true},
			rule: RuleNotScheduled, group: GroupNotMoving},
		{name: "ready work nothing sends is not scheduled, though a run it no longer has left a branch on its row", b: work, kind: KindWork,
			f:    facts{holds: &waits.Holds{ID: "tk-w", Status: waits.Clear, InFlight: "carries branch"}, place: ready, notScheduled: true},
			rule: RuleNotScheduled, group: GroupNotMoving},
		{name: "nothing sends it and it waits, so it names each wait", b: work, kind: KindWork, f: facts{holds: blockedOn(workWait), place: untaken},
			rule: RuleNotReady, group: GroupNotMoving, names: []string{"tk-other"}},
		{name: "nothing sends it, and the store does not serve it as ready though it waits on nothing", b: work, kind: KindWork,
			f: facts{holds: clear, place: untaken}, rule: RuleNotReady, group: GroupNotMoving},
		{name: "held hold:external, armed or not, waits outside the city", b: Bead{ID: "tk-w", Status: "open", IssueType: "task", Labels: []string{"hold:external"}}, kind: KindWork,
			f:    facts{holds: &waits.Holds{ID: "tk-w", Status: waits.Clear, Arm: &waits.Arm{Target: "gc-toolkit/gc-toolkit.polecat"}}, place: outside},
			rule: RuleOutside, group: GroupNotMoving},
		{name: "held for the Product Owner in any spelling, with nothing sending it, waits for the Product Owner",
			b: Bead{ID: "tk-w", Status: "open", IssueType: "task", Labels: []string{" Hold:Mayor "}}, kind: KindWork,
			f:    facts{holds: &waits.Holds{ID: "tk-w", Status: waits.Clear, InFlight: "carries branch"}, place: ready},
			rule: RuleForProductOwner, group: GroupNotMoving},
		{name: "held for the Product Owner and worked by a live run is in flight from the run's start",
			b: Bead{ID: "tk-w", Status: "open", IssueType: "task", Labels: []string{"hold:mayor"}}, kind: KindWork,
			f: facts{holds: clear, place: taken, worked: true}, rule: RuleInFlight, group: GroupQueued},
		{name: "a live run works it from the run's start, before waits counts it in flight", b: work, kind: KindWork,
			f: facts{holds: clear, place: untaken, worked: true}, rule: RuleInFlight, group: GroupQueued},
		{name: "work that queue placed nowhere is unread", b: work, kind: KindWork, f: facts{holds: clear},
			rule: RuleUnread},
		{name: "an epic with no ask has members of its own", b: Bead{ID: "tk-e", Status: "open", IssueType: "epic"}, kind: KindEpic, f: facts{holds: clear},
			rule: RuleMembers},
		{name: "a gate that is no human gate has no move of its own", b: Bead{ID: "tk-p", Status: "open", IssueType: "gate"}, kind: KindGate, f: facts{holds: clear},
			rule: RuleGate},
		{name: "a bead waits could not answer is unread", b: work, kind: KindWork,
			rule: RuleUnread},
		{name: "a walk past its bound leaves the bead unread", b: work, kind: KindWork, f: facts{holds: blockedOn(workWait), unwalked: true},
			rule: RuleUnread},
		{name: "a conversation its sitting stays in waits on that work, queued", b: Bead{ID: "tk-c", Status: "open", IssueType: "task", Assignee: sitting}, kind: KindConversation,
			f: facts{holds: blockedOn(workWait)}, rule: RuleStaying, group: GroupQueued, names: []string{"tk-other"}},
		{name: "a conversation its sitting holds over an earlier stay's open work answers nothing of its own", b: Bead{ID: "tk-c", Status: "in_progress", IssueType: "task", Assignee: sitting}, kind: KindConversation,
			f: facts{holds: blockedOn(workWait)}, rule: RuleAnswers},
		{name: "a pull request prstatus could not answer is unread before any ask", b: work, kind: KindWork, ask: AskAssignedToYou, f: facts{prUnread: true},
			rule: RuleUnread},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			r := readingOf(c.b, c.kind, c.f)
			stays := map[string]bool{}
			if h, ok := r.holds[c.b.ID]; ok && (c.kind == KindConversation || c.kind == KindDecision) {
				stays[c.b.ID] = staying(c.b, h)
			}
			a := r.table(c.b, c.kind, c.ask, stays)
			var names []string
			for _, n := range a.Names {
				names = append(names, n.ID)
			}
			owed := ""
			if a.Owed != nil {
				owed = a.Owed.ID
			}
			if a.Rule != c.rule || a.Group != c.group || !slices.Equal(names, c.names) || owed != c.owed {
				t.Errorf("got rule=%q group=%q names=%v owed=%q\nwant rule=%q group=%q names=%v owed=%q",
					a.Rule, a.Group, names, owed, c.rule, c.group, c.names, c.owed)
			}
			if c.rule == RuleUnread && a.Why == "" {
				t.Errorf("an unread answer says no why")
			}
			if c.state != "" {
				if p := r.PullRequest(c.b.ID); p == nil || p.State() != c.state {
					t.Errorf("pull request = %+v, want state %q", p, c.state)
				}
			}
		})
	}
}

// TestAsks holds each kind of ask to the reader that counts it. A pull request
// that stands beneath another ask (beneath) is an ask only for a reason of its
// own, whether its state is derived from its facts or rendered from the
// evaluator's answer on Gas Town's pending record.
func TestAsks(t *testing.T) {
	gate := Bead{ID: "tk-g", Status: "open", IssueType: "gate", AwaitType: "human"}
	decision := Bead{ID: "tk-d", Status: "open", IssueType: "decision"}
	sitting := "gc-toolkit/gc-toolkit.tk-c"
	held := person.Blocker{ID: "tk-g", Title: "which way?", Status: "open", IssueType: "gate", AwaitType: "human"}
	gated := &prstatus.Facts{Gates: []person.Blocker{held}}
	gatedAndFrozen := &prstatus.Facts{Gates: []person.Blocker{held}, MergeHold: "true"}
	waitsOnTheGate := &pr.Answer{Conditions: []pr.Condition{{Kind: pr.KindWait, ID: "tk-g"}}}
	failedBesideTheGate := &pr.Answer{Conditions: []pr.Condition{{Kind: pr.KindCheckFailed, Value: "test"}, {Kind: pr.KindWait, ID: "tk-g"}}}
	cases := []struct {
		name string
		b    Bead
		kind Kind
		// others are the other beads the read holds, with their kinds, and
		// stays the beads that wait on work of their own first.
		others    map[string]Bead
		stays     []string
		pr        *prstatus.Facts
		answer    *pr.Answer
		open, all int
		beneath   bool
		want      Ask
	}{
		{name: "a human gate is a question", b: gate, kind: KindGate, want: AskQuestion},
		{name: "a gate no person answers is never an ask", b: Bead{ID: "tk-p", Status: "open", IssueType: "gate", Assignee: "human"}, kind: KindGate},
		{name: "a decision is a question", b: decision, kind: KindDecision, want: AskQuestion},
		{name: "a decision a ruling left waiting on its work is no ask", b: decision, kind: KindDecision, stays: []string{"tk-d"}},
		{name: "a conversation is its own ask", b: Bead{ID: "tk-c", Status: "open", IssueType: "task", Assignee: "human"}, kind: KindConversation,
			want: AskConversation},
		{name: "a conversation a sitting holds is its own ask", b: Bead{ID: "tk-c", Status: "open", IssueType: "task", Assignee: sitting}, kind: KindConversation,
			want: AskConversation},
		{name: "a conversation its sitting stays in waits for its work and is no ask",
			b: Bead{ID: "tk-c", Status: "open", IssueType: "task", Assignee: sitting}, kind: KindConversation, stays: []string{"tk-c"}},
		{name: "a conversation that replies to an open human gate answers that question",
			b:    Bead{ID: "tk-c", Status: "open", IssueType: "task", Assignee: "human", Edges: []Edge{{ID: "tk-g", Type: "replies-to"}}},
			kind: KindConversation, others: map[string]Bead{"tk-g": gate}},
		{name: "a conversation that tracks a decision that is a question answers it",
			b:    Bead{ID: "tk-c", Status: "open", IssueType: "task", Assignee: "human", Edges: []Edge{{ID: "tk-d", Type: "tracks"}}},
			kind: KindConversation, others: map[string]Bead{"tk-d": decision}},
		{name: "a conversation that tracks a decision waiting on its work is its own ask",
			b:    Bead{ID: "tk-c", Status: "open", IssueType: "task", Assignee: "human", Edges: []Edge{{ID: "tk-d", Type: "tracks"}}},
			kind: KindConversation, others: map[string]Bead{"tk-d": decision}, stays: []string{"tk-d"}, want: AskConversation},
		{name: "a conversation that tracks a human gate it does not reply to is its own ask",
			b:    Bead{ID: "tk-c", Status: "open", IssueType: "task", Assignee: "human", Edges: []Edge{{ID: "tk-g", Type: "tracks"}}},
			kind: KindConversation, others: map[string]Bead{"tk-g": gate}, want: AskConversation},
		{name: "a pull request needing review is an ask", b: Bead{ID: "tk-w", Status: "open"}, kind: KindWork,
			pr: &prstatus.Facts{}, want: AskPullRequest},
		{name: "a pull request the city is changing is no ask", b: Bead{ID: "tk-w", Status: "open"}, kind: KindWork,
			pr: &prstatus.Facts{InFlightCount: 1}},
		{name: "a pull request a human gate alone holds is an ask while it stands beneath no other",
			b: Bead{ID: "tk-w", Status: "open"}, kind: KindWork, pr: gated, want: AskPullRequest},
		{name: "…and no ask beneath the gate's, whose answer is the person's move on it",
			b: Bead{ID: "tk-w", Status: "open"}, kind: KindWork, pr: gated, beneath: true},
		{name: "a pull request held by a gate and by a reason of its own is an ask beneath the gate's too",
			b: Bead{ID: "tk-w", Status: "open"}, kind: KindWork, pr: gatedAndFrozen, beneath: true, want: AskPullRequest},
		{name: "a pull request needing review is an ask beneath another ask",
			b: Bead{ID: "tk-w", Status: "open"}, kind: KindWork, pr: &prstatus.Facts{}, beneath: true, want: AskPullRequest},
		{name: "a pull request assigned to a person, beneath the ask of the gate that alone holds it, is assigned to you",
			b: Bead{ID: "tk-w", Status: "open", IssueType: "task", Assignee: "human"}, kind: KindWork, pr: gated, beneath: true,
			want: AskAssignedToYou},
		{name: "a pull request on the pending record that waits on the gate alone is no ask beneath the gate's",
			b: Bead{ID: "tk-w", Status: "open"}, kind: KindWork, pr: gated, answer: waitsOnTheGate, beneath: true},
		{name: "…and is an ask beneath it with a failed required check of its own",
			b: Bead{ID: "tk-w", Status: "open"}, kind: KindWork, pr: gated, answer: failedBesideTheGate, beneath: true,
			want: AskPullRequest},
		{name: "work in your queue is assigned to you", b: Bead{ID: "tk-w", Status: "open", IssueType: "task", Assignee: "human"}, kind: KindWork,
			want: AskAssignedToYou},
		{name: "a bead in your queue that is no task is assigned to you", b: Bead{ID: "tk-w", Status: "open", IssueType: "bug", Assignee: "human"}, kind: KindWork,
			want: AskAssignedToYou},
		{name: "work assigned to an agent is no ask", b: Bead{ID: "tk-w", Status: "open", IssueType: "bug", Assignee: "gc-toolkit.mechanik"}, kind: KindWork},
		{name: "an epic whose members all closed needs a ruling", b: Bead{ID: "tk-e", Status: "open", IssueType: "epic"}, kind: KindEpic,
			open: 0, all: 3, want: AskRuling},
		{name: "a landed Delivery waits for its checkpoint", b: Bead{ID: "tk-e.1", Status: "open", IssueType: "epic"}, kind: KindDelivery,
			open: 0, all: 2, want: AskRuling},
		{name: "an epic with open members needs no ruling", b: Bead{ID: "tk-e", Status: "open", IssueType: "epic"}, kind: KindEpic, open: 1, all: 3},
		{name: "an epic with no members needs no ruling", b: Bead{ID: "tk-e", Status: "open", IssueType: "epic"}, kind: KindEpic},
		{name: "a closed bead is no ask", b: Bead{ID: "tk-d", Status: "closed", IssueType: "decision"}, kind: KindDecision},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			f := facts{pr: c.pr, answer: c.answer}
			r := readingOf(c.b, c.kind, f)
			for id, o := range c.others {
				r.beads[id] = o
				r.kinds[id] = ownKind(o)
			}
			stays := map[string]bool{}
			for _, id := range c.stays {
				stays[id] = true
			}
			if got := r.askOf(c.b, c.kind, stays, c.open, c.all, c.beneath); got != c.want {
				t.Errorf("askOf = %q, want %q", got, c.want)
			}
		})
	}
}

// TestStaying holds a stay to the state the stay's last write leaves: open
// under its sitting, held by a wait of its own. A claim, the operator's queue
// or no wait each make it something the operator owes a move. A decision stays
// by the same reader, while a wait of its own on work holds it: a ruling that
// sent work leaves it so, and a wait on a gate alone, an ancestor's wait or no
// wait leaves it the operator's.
func TestStaying(t *testing.T) {
	work := waits.Wait{ID: "tk-w", Type: "blocks", Status: "open", IssueType: "task"}
	blocked := waits.Holds{ID: "tk-c", Status: waits.Blocked, Waits: []waits.Wait{work}}
	sitting := "gc-toolkit/gc-toolkit.tk-c"
	decision := Bead{ID: "tk-d", Status: "open", IssueType: "decision"}
	gate := waits.Wait{ID: "tk-g", Type: "blocks", Status: "open", IssueType: "gate", AwaitType: "human"}
	cases := []struct {
		name string
		b    Bead
		h    waits.Holds
		want bool
	}{
		{name: "open under its sitting and held by its work is a stay",
			b: Bead{ID: "tk-c", Status: "open", IssueType: "task", Assignee: sitting}, h: blocked, want: true},
		{name: "claimed by its sitting over an earlier stay's work is a hold",
			b: Bead{ID: "tk-c", Status: "in_progress", IssueType: "task", Assignee: sitting}, h: blocked},
		{name: "in the operator's queue over work still out is theirs to move",
			b: Bead{ID: "tk-c", Status: "open", IssueType: "task", Assignee: "human"}, h: blocked},
		{name: "open under its sitting with nothing holding it is back",
			b: Bead{ID: "tk-c", Status: "open", IssueType: "task", Assignee: sitting}, h: waits.Holds{ID: "tk-c", Status: waits.Clear}},
		{name: "a decision a ruling left waiting on its work stays", b: decision,
			h: waits.Holds{ID: "tk-d", Status: waits.Blocked, Waits: []waits.Wait{work}}, want: true},
		{name: "a decision that waits on a gate and on work stays", b: decision,
			h: waits.Holds{ID: "tk-d", Status: waits.Blocked, Waits: []waits.Wait{gate, work}}, want: true},
		{name: "a decision that waits only on a gate is the operator's", b: decision,
			h: waits.Holds{ID: "tk-d", Status: waits.Blocked, Waits: []waits.Wait{gate}}},
		{name: "a decision held only through an epic's wait is the operator's", b: decision,
			h: waits.Holds{ID: "tk-d", Status: waits.Held, Waits: []waits.Wait{{ID: "tk-w", Type: "blocks", Status: "open", IssueType: "task", Ancestor: "tk-e"}}}},
		{name: "a decision nothing holds is the operator's", b: decision, h: waits.Holds{ID: "tk-d", Status: waits.Clear}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := staying(c.b, c.h); got != c.want {
				t.Errorf("staying = %v, want %v", got, c.want)
			}
		})
	}
}
