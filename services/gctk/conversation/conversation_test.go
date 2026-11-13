package conversation

import (
	"slices"
	"testing"
)

// TestIsAssigneeIsTheQueueOrTheSittingsAlias pins the assignee half of the
// shape conversation.sh defines: `human`, or the alias that names the task's
// own id, bare, as its `c-` fallback, or qualified by a session's rig and
// binding. conversation.test.sh runs the shell rule over the same assignees.
func TestIsAssigneeIsTheQueueOrTheSittingsAlias(t *testing.T) {
	for _, tc := range []struct {
		assignee string
		want     bool
	}{
		{"human", true},
		{"tk-c1", true},
		{"c-tk-c1", true},
		{"gc-toolkit/gc-toolkit.tk-c1", true},
		{"gc-toolkit/gc-toolkit.c-tk-c1", true},
		{"converse.tk-c1", true},
		{"", false},
		{"alice", false},
		{"gc-toolkit/gc-toolkit.tk-c2", false},
		{"tk-c11", false},
	} {
		if got := IsAssignee(tc.assignee, "tk-c1"); got != tc.want {
			t.Errorf("IsAssignee(%q, tk-c1) = %v, want %v", tc.assignee, got, tc.want)
		}
	}
	if IsAssignee("human", "") {
		t.Error("IsAssignee(human, \"\") = true, want false: a task with no id has no shape")
	}
}

// TestIsCandidateIsATaskAConversationsAssigneeHolds pins the row half: a task
// whose assignee is one a conversation carries, whatever else it is.
func TestIsCandidateIsATaskAConversationsAssigneeHolds(t *testing.T) {
	for _, tc := range []struct {
		issueType, assignee string
		want                bool
	}{
		{"task", "human", true},
		{"task", "gc-toolkit/converse-claude-opus.c-tk-c1", true},
		{"task", "alice", false},
		{"task", "", false},
		{"gate", "human", false},
		{"bug", "tk-c1", false},
	} {
		if got := IsCandidate(tc.issueType, tc.assignee, "tk-c1"); got != tc.want {
			t.Errorf("IsCandidate(%q, %q, tk-c1) = %v, want %v", tc.issueType, tc.assignee, got, tc.want)
		}
	}
}

// TestStayingIsOpenUnderItsSittingWithAWaitOfItsOwn pins the stay: the state
// the stay's last write leaves, open under the sitting, held by a wait of its
// own. A claim, the operator's queue or no wait each make it a person's move.
func TestStayingIsOpenUnderItsSittingWithAWaitOfItsOwn(t *testing.T) {
	sitting := "gc-toolkit/gc-toolkit.tk-c1"
	for _, tc := range []struct {
		status, assignee string
		waiting, want    bool
	}{
		{"open", sitting, true, true},
		{" Open ", sitting, true, true},
		{"in_progress", sitting, true, false},
		{"open", "human", true, false},
		{"open", "", true, false},
		{"open", sitting, false, false},
		{"closed", sitting, true, false},
		{"", sitting, true, false},
	} {
		if got := Staying(tc.status, tc.assignee, tc.waiting); got != tc.want {
			t.Errorf("Staying(%q, %q, %v) = %v, want %v", tc.status, tc.assignee, tc.waiting, got, tc.want)
		}
	}
}

// TestShapeIsOneTracksEdgeAndItsReplies pins the edge half: exactly one bead a
// `tracks` edge names, which is the subject, and the beads its `replies-to`
// edges name, each once and sorted. Every other edge is read past.
func TestShapeIsOneTracksEdgeAndItsReplies(t *testing.T) {
	for _, tc := range []struct {
		name    string
		edges   []Edge
		subject string
		replies []string
		ok      bool
	}{
		{"one tracks edge", []Edge{{"tracks", "tk-s"}}, "tk-s", []string{}, true},
		{"its replies, each once and sorted",
			[]Edge{{"replies-to", "tk-g2"}, {"tracks", "tk-s"}, {"replies-to", "tk-g1"}, {"replies-to", "tk-g2"}},
			"tk-s", []string{"tk-g1", "tk-g2"}, true},
		{"the same subject twice is one", []Edge{{"tracks", "tk-s"}, {"tracks", "tk-s"}}, "tk-s", []string{}, true},
		{"other edges read past", []Edge{{"tracks", "tk-s"}, {"blocks", "tk-b"}, {"parent-child", "tk-p"}}, "tk-s", []string{}, true},
		{"no tracks edge", []Edge{{"replies-to", "tk-g1"}}, "", nil, false},
		{"two subjects", []Edge{{"tracks", "tk-s"}, {"tracks", "tk-t"}}, "", nil, false},
		{"a tracks edge onto nothing", []Edge{{"tracks", ""}}, "", nil, false},
		{"no edges", nil, "", nil, false},
	} {
		subject, replies, ok := Shape(tc.edges)
		if subject != tc.subject || ok != tc.ok || !slices.Equal(replies, tc.replies) {
			t.Errorf("%s: Shape = (%q, %v, %v), want (%q, %v, %v)", tc.name, subject, replies, ok, tc.subject, tc.replies, tc.ok)
		}
	}
}
