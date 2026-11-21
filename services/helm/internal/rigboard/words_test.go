package rigboard

import (
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/standing/person"
)

// A row a gate or a bead a person owes holds through its own wait reads what
// that bead asks: your answer for a question, the conversation's words for a
// conversation, and otherwise the waits it names, so a bead behind another
// bead's pull request names that bead and never takes its words.
func TestOwnWaitWords(t *testing.T) {
	waits := []Ref{{ID: "tk-other"}, {ID: "tk-pr"}}
	for _, c := range []struct {
		name string
		o    person.Blocker
		want string
	}{
		{"a human gate", person.Blocker{ID: "tk-g", Status: "open", IssueType: "gate", AwaitType: "human"}, "Waits on your answer"},
		{"a conversation in your queue", person.Blocker{ID: "tk-c", Status: "open", IssueType: "task", Assignee: "human"}, "Conversation waits for you"},
		{"a conversation a sitting holds", person.Blocker{ID: "tk-c", Status: "open", IssueType: "task", Assignee: "gc-toolkit/gc-toolkit.tk-c"}, "In conversation"},
		{"a decision", person.Blocker{ID: "tk-d", Status: "open", IssueType: "decision"}, "Waits on your answer"},
		{"another bead's pull request", person.Blocker{ID: "tk-pr", Status: "open", IssueType: "task",
			Metadata: map[string]string{"merge_result": "pull_request"}}, "Waits on tk-other, tk-pr"},
	} {
		if got := ownWaitWords(&c.o, waits); got != c.want {
			t.Errorf("%s: %q, want %q", c.name, got, c.want)
		}
	}
}

// A question reads "Question", or the words of the conversation that answers
// it, and it is in conversation once a sitting holds that conversation.
func TestQuestionAsk(t *testing.T) {
	for _, c := range []struct {
		name, conv, assignee string
		want                 askAnswer
	}{
		{"no conversation answers it", "", "", askAnswer{kind: AskQuestion, words: "Question", need: NeedKindQuestion}},
		{"a conversation in your queue answers it", "tk-c", "human",
			askAnswer{kind: AskQuestion, words: "Conversation waits for you", need: NeedKindQuestion}},
		{"a sitting talks it over", "tk-c", "gc-toolkit/gc-toolkit.tk-c",
			askAnswer{kind: AskQuestion, words: "In conversation", need: NeedKindInConversation}},
	} {
		if got := questionAsk(c.conv, c.assignee); *got != c.want {
			t.Errorf("%s: %+v, want %+v", c.name, *got, c.want)
		}
	}
}
