// Package conversation is the one Go definition of a conversation's shape, the
// rule assets/scripts/conversation.sh holds for the scripts. A conversation is
// an ordinary task that tracks the one bead it is about. It is assigned to
// `human` while it waits in the operator's queue, and to its sitting's alias
// while a sitting holds it. That alias names the task's own id, or its `c-`
// fallback when the runtime refuses the bare id, and a claim records it
// qualified by the session's rig and template binding
// (`<rig>/<binding>.<alias>`), so a held conversation is known by its assignee
// alone, even once its session has closed. It carries no pack marker, so the
// shape is read off the task's type, its assignee and its own edges.
//
// A conversation on an open PR holds the PR's merge until it closes, and
// otherwise blocks nothing: the PR's anchor depends on it through a `blocks`
// edge (gc-helm.sh, conversation_hold_merge).
//
// The package sits outside internal/ so the helm board, a separate module, can
// import it.
package conversation

import (
	"slices"
	"strings"
)

// IssueType is the issue type a conversation is filed as.
const IssueType = "task"

// IsAssignee reports whether assignee is one a conversation carries: `human`,
// or the alias that names the task's own id, bare, as its `c-` fallback, or
// qualified by the session's rig and template binding. It is the rule
// conversation.sh's conversation_assignee applies, so the board, the PR's
// facts and the scripts read one shape.
func IsAssignee(assignee, id string) bool {
	if assignee == "" || id == "" {
		return false
	}
	if assignee == "human" {
		return true
	}
	for _, alias := range []string{id, "c-" + id} {
		if assignee == alias || strings.HasSuffix(assignee, "/"+alias) || strings.HasSuffix(assignee, "."+alias) {
			return true
		}
	}
	return false
}

// IsCandidate reports whether a bead reads as a conversation by its row alone:
// a task whose assignee is one a conversation carries ([IsAssignee]). Its own
// edges decide the rest of the shape ([Shape]). A reader that holds the row and
// not the edges, such as the far end of a `blocks` edge, reads a candidate as a
// person's to move: a conversation, or work assigned to the operator, and no
// automated actor moves either. A reader that also knows whether a wait of the
// candidate's own holds it can tell a conversation its sitting stays in
// ([Staying]), which is no person's move until that wait clears.
func IsCandidate(issueType, assignee, id string) bool {
	return issueType == IssueType && IsAssignee(assignee, id)
}

// Staying reports whether a conversation reads as one its sitting stays in:
// open under its sitting's alias, which the stay's last write leaves it, while
// a wait of its own holds it (waiting), the edge the stay writes onto each bead
// of the work it sent. The sitting comes back to the operator once that work
// closes, so until then the conversation is no person's move, and what it
// waits on counts on its own, a human gate as a gate. A sitting that holds its
// conversation keeps it claimed, in progress, and one in the operator's queue
// is assigned to `human`, so neither is a stay, whatever edge an earlier stay
// left on it. Once no wait holds it, it is a person's move again, as the
// sitting's return is. The helm board's row and the PR's facts (prstatus)
// both read a stay by this rule, each with its own read of the wait.
func Staying(status, assignee string, waiting bool) bool {
	a := strings.TrimSpace(assignee)
	return waiting && strings.EqualFold(strings.TrimSpace(status), "open") && a != "" && a != "human"
}

// Edge is one of a task's own dependency edges: its type, and the bead it
// names.
type Edge struct {
	Type        string
	DependsOnID string
}

// Shape reads a conversation's subject and replies off its own edges. ok is
// true only when exactly one `tracks` edge names a bead, which is the subject.
// replies is every bead its `replies-to` edges name, each once and sorted.
func Shape(edges []Edge) (subject string, replies []string, ok bool) {
	var tracked []string
	for _, e := range edges {
		switch e.Type {
		case "tracks":
			tracked = append(tracked, e.DependsOnID)
		case "replies-to":
			replies = append(replies, e.DependsOnID)
		}
	}
	if tracked = unique(tracked); len(tracked) != 1 {
		return "", nil, false
	}
	return tracked[0], unique(replies), true
}

// unique drops the empty and repeated values of in and sorts the rest.
func unique(in []string) []string {
	out := make([]string, 0, len(in))
	for _, v := range in {
		if v != "" && !slices.Contains(out, v) {
			out = append(out, v)
		}
	}
	slices.Sort(out)
	return out
}
