package person

import "testing"

func task(id string) Blocker { return Blocker{ID: id, Status: "open", IssueType: "task"} }

func decision(id string) Blocker {
	return Blocker{ID: id, Title: "decide " + id, Status: "open", IssueType: "decision"}
}

func closed(b Blocker) Blocker {
	b.Status = "closed"
	return b
}

// A bead is a human gate only when it is a gate whose await type is human: a
// gate of another await type, or of none, as park's gate declares, is not one,
// and neither is a task. The issue type reads in any case.
func TestIsHumanGate(t *testing.T) {
	for _, tc := range []struct {
		issueType, awaitType string
		want                 bool
	}{
		{"gate", "human", true},
		{"Gate", "human", true},
		{"gate", "", false},
		{"gate", "timer", false},
		{"task", "human", false},
	} {
		if got := IsHumanGate(tc.issueType, tc.awaitType); got != tc.want {
			t.Errorf("IsHumanGate(%q, %q) = %v, want %v", tc.issueType, tc.awaitType, got, tc.want)
		}
	}
}

// Only a person clears a live decision, and never a human gate, which the
// human-gate rule counts on its own.
func TestClears(t *testing.T) {
	for _, tc := range []struct {
		name string
		b    Blocker
		want bool
	}{
		{"a decision", Blocker{ID: "d", Status: "open", IssueType: "decision"}, true},
		{"a decision in any case", Blocker{ID: "d", Status: "open", IssueType: "Decision"}, true},
		{"a decision in progress", Blocker{ID: "d", Status: "IN_PROGRESS", IssueType: "decision"}, true},
		{"a decision with no status", Blocker{ID: "d", IssueType: "decision"}, true},
		{"closed", Blocker{ID: "d", Status: "closed", IssueType: "decision"}, false},
		{"closed in any case", Blocker{ID: "d", Status: "Closed", IssueType: "decision"}, false},
		{"a task", Blocker{ID: "d", Status: "open", IssueType: "task"}, false},
		{"routed to a pool", Blocker{ID: "d", Status: "open", Metadata: map[string]string{"gc.routed_to": "gc-toolkit/gc-toolkit.polecat"}}, false},
		{"routed to human", Blocker{ID: "d", Status: "open", IssueType: "task", Metadata: map[string]string{"gc.routed_to": "human"}}, false},
		{"a human gate", Blocker{ID: "g", Status: "open", IssueType: "gate", AwaitType: "human"}, false},
		{"a timer gate", Blocker{ID: "g", Status: "open", IssueType: "gate", AwaitType: "timer"}, false},
		{"a bug in your queue", Blocker{ID: "b", Status: "open", IssueType: "bug", Assignee: "human"}, true},
		{"an epic in your queue", Blocker{ID: "e", Status: "open", IssueType: "epic", Assignee: "human"}, true},
		{"a human gate in your queue", Blocker{ID: "g", Status: "open", IssueType: "gate", AwaitType: "human", Assignee: "human"}, false},
		{"closed in your queue", Blocker{ID: "b", Status: "closed", IssueType: "bug", Assignee: "human"}, false},
		{"assigned to an agent", Blocker{ID: "b", Status: "open", IssueType: "bug", Assignee: "gc-toolkit.mechanik"}, false},
		{"a merge anchor waiting on a review", Blocker{ID: "b", Title: "pr b", Status: "open", IssueType: "task",
			Metadata: map[string]string{"merge_result": "pull_request_pending"}}, false},
	} {
		if got := Clears(tc.b); got != tc.want {
			t.Errorf("%s: Clears(%+v) = %v, want %v", tc.name, tc.b, got, tc.want)
		}
	}
}

// Stays reads a bead by its own row and its own edges alone: a closed decision
// stays for nothing, and a task that is no conversation never stays.
func TestStays(t *testing.T) {
	for _, tc := range []struct {
		name string
		b    Blocker
		own  []Blocker
		want bool
	}{
		{"an open decision with open work", decision("d"), []Blocker{task("w")}, true},
		{"a decision of any case", Blocker{ID: "d", Status: "open", IssueType: "Decision"}, []Blocker{task("w")}, true},
		{"a closed decision", closed(decision("d")), []Blocker{task("w")}, false},
		{"a decision with no edge", decision("d"), nil, false},
		{"a decision whose gate is of any case", decision("d"), []Blocker{{ID: "g", Status: "open", IssueType: "Gate"}}, false},
		{"a task that is no conversation", task("t"), []Blocker{task("w")}, false},
	} {
		if got := Stays(tc.b, tc.own); got != tc.want {
			t.Errorf("%s: Stays = %v, want %v", tc.name, got, tc.want)
		}
	}
}
