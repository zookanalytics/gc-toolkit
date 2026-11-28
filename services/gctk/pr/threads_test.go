package pr

import (
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
)

// A review thread is weighed without the posts the quote holds: their text
// reaches no agent, so an outside account's comment neither asks for the city's
// answer nor answers one, and the operator's follow-up is what holds the PR
// for it.
func TestThreadsOfWeighsAThreadWithoutItsHeldPosts(t *testing.T) {
	ts := threadsOf([]gh.Thread{
		{ID: "T1", Comments: []gh.Comment{
			{ID: 1, Author: "op", AuthorType: "User", AuthorAssociation: "OWNER", Body: "rename this"},
			{ID: 2, Author: "zook-bot", AuthorType: "User", AuthorAssociation: "MEMBER", Body: "renamed"},
			{ID: 3, Author: "someone", AuthorType: "User", AuthorAssociation: "NONE", Body: "and this"},
		}},
		{ID: "T2", Comments: []gh.Comment{
			{ID: 4, Author: "someone", AuthorType: "User", AuthorAssociation: "CONTRIBUTOR", Body: "why"},
		}},
	})
	if len(ts) != 2 || len(ts[0].Comments) != 2 || ts[0].Comments[1].ID != 2 || len(ts[1].Comments) != 0 {
		t.Fatalf("the threads weighed %+v", ts)
	}
}
