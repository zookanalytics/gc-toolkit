// Package person holds the rules about one bead that say whether a person owes
// its move: whether it is a human gate, whether only a person clears it, and
// whether it waits on work of its own first. Each reads a bead's row alone, or
// with the bead's own `blocks` edges, so every reader that weighs a person's
// move, a pull request's status and a bead's standing among them, reads a bead
// one way.
package person

import (
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/conversation"
)

// Blocker is one bead in the fields these rules, and the walks that apply them,
// read of it: the far end of a `blocks` edge, or a bead asked about itself. A
// store fills it from its own read, and passes the status and the issue type as
// they read, in any case. AwaitID is the key a gate was filed under. Assignee is
// the bead's assignee as it reads, which tells a conversation by its row
// ([conversation.IsCandidate]). ClosedAt is when it closed, "" while it is live.
// Metadata is the bead's metadata whole, each value as the store renders it, so
// the reader that needs a key names it: a merge anchor's facts about its own
// pull request, and the vars a review run was poured with.
type Blocker struct {
	ID        string
	Title     string
	Status    string
	IssueType string
	AwaitType string
	AwaitID   string
	Assignee  string
	ClosedAt  string
	Metadata  map[string]string
}

// Open reports whether the bead still blocks: any status but closed, a bead
// with no status included. It is the rule a human gate is read open by
// (HUMAN_GATE_JQ in assets/scripts/bd-lib.sh).
func (b Blocker) Open() bool { return !strings.EqualFold(b.Status, "closed") }

// IsHumanGate reports whether a bead of this issue type and await type is a
// human gate: Gas City's native bead for a wait a person must clear. It is the
// one reader rule bd_human_gates applies in assets/scripts/bd-lib.sh.
func IsHumanGate(issueType, awaitType string) bool {
	return strings.EqualFold(issueType, "gate") && awaitType == "human"
}

// Clears reports whether only a person clears a bead that is no human gate: a
// live decision or conversation. A conversation reads as one by its row
// ([conversation.IsCandidate]): a task in the operator's queue or held by a
// sitting, which a person's ruling or dismissal closes. No automated actor
// clears either. A human gate is never one, because the human-gate rule counts
// it on its own, and a route marks no bead as a person's. A bead with no status
// reads open, and only a closed one is not live. It reads the row alone, so it
// cannot tell one that waits on work of its own first, which no person owes a
// move on while that work is out: [Stays] tells that from the bead's own edges.
func Clears(b Blocker) bool {
	if !b.Open() || IsHumanGate(b.IssueType, b.AwaitType) {
		return false
	}
	return strings.EqualFold(b.IssueType, "decision") ||
		conversation.IsCandidate(strings.ToLower(b.IssueType), b.Assignee, b.ID)
}

// Stays reports whether a bead that [Clears] reads as a person's waits on work
// of its own first, by its own `blocks` edges (own), so no person owes a move on
// it while that work is out. One is a conversation its sitting stays in
// ([conversation.Staying]), whose open edges are the stay's, one onto each bead
// of the work it sent. The other is an open decision with an open edge onto
// work, a bead that is no gate: a ruling that sends work leaves its decision
// open with an edge onto that work, which the decision's validating closer
// checks once the work lands (converse-signoff.sh's --waiting-on). A decision
// whose open edges are only onto gates is a person's to clear.
func Stays(b Blocker, own []Blocker) bool {
	if !b.Open() {
		return false
	}
	if strings.EqualFold(b.IssueType, "decision") {
		return slices.ContainsFunc(own, isWork)
	}
	return conversation.IsCandidate(strings.ToLower(b.IssueType), b.Assignee, b.ID) &&
		conversation.Staying(b.Status, b.Assignee, slices.ContainsFunc(own, Blocker.Open))
}

// isWork reports whether a bead is work: an open bead that is no gate.
func isWork(b Blocker) bool { return b.Open() && !strings.EqualFold(b.IssueType, "gate") }
