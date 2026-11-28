package gh

import "testing"

// TestPostedReadsAPRWithItsConversationAndEachAuthorsStanding pins the read a
// quote is made from: the repository's permission for the account the read
// runs as, the PR's opener with its kind and association, and its conversation
// with each post's author kind and association.
func TestPostedReadsAPRWithItsConversationAndEachAuthorsStanding(t *testing.T) {
	var log []string
	c := NewWithRunner("github.com", answers(t, map[string]string{
		"query=" + postedQuery: `{"data":{"repository":{"viewerPermission":"WRITE","issueOrPullRequest":{
			"__typename":"PullRequest","url":"https://github.com/o/r/pull/7","title":"t","body":"b",
			"createdAt":"2026-11-27T10:00:00Z","authorAssociation":"MEMBER",
			"author":{"__typename":"User","login":"zook-bot"}}}}}`,
		"query=" + conversationQuery: `{"data":{"repository":{"pullRequest":{"reviewDecision":null,
			"reviews":{"pageInfo":{"hasNextPage":false},"nodes":[]},
			"reviewThreads":{"pageInfo":{"hasNextPage":false},"nodes":[]},
			"comments":{"pageInfo":{"hasNextPage":false},"nodes":[{"fullDatabaseId":"31","id":"IC_31",
				"url":"https://github.com/o/r/pull/7#issuecomment-31","body":"size","createdAt":"c","updatedAt":"u",
				"authorAssociation":"NONE","author":{"__typename":"Bot","login":"github-actions"},
				"reactionGroups":[]}]}}}}}`,
	}, &log))
	p, err := c.Posted("o/r", 7)
	if err != nil {
		t.Fatal(err)
	}
	if !p.PullRequest || p.ViewerPermission != "WRITE" || p.Title != "t" || p.Body != "b" ||
		p.Opener != (Account{Login: "zook-bot", Type: "User", Association: "MEMBER"}) {
		t.Fatalf("the PR read as %+v", p)
	}
	if len(p.Comments) != 1 || p.Comments[0].AuthorType != "Bot" || p.Comments[0].AuthorAssociation != "NONE" ||
		p.Comments[0].Author != "github-actions" {
		t.Fatalf("the conversation read as %+v", p.Comments)
	}
}

// TestPostedReadsAnIssueWithItsComments pins the read of an issue: its text
// and its comments, with no PR conversation read.
func TestPostedReadsAnIssueWithItsComments(t *testing.T) {
	var log []string
	c := NewWithRunner("github.com", answers(t, map[string]string{
		"query=" + postedQuery: `{"data":{"repository":{"viewerPermission":"READ","issueOrPullRequest":{
			"__typename":"Issue","url":"https://github.com/u/up/issues/3","title":"bug","body":"steps",
			"createdAt":"2026-11-27T10:00:00Z","authorAssociation":"NONE","author":null,
			"comments":{"pageInfo":{"hasNextPage":false},"nodes":[{"fullDatabaseId":"41","id":"IC_41",
				"url":"https://github.com/u/up/issues/3#issuecomment-41","body":"same here","createdAt":"c",
				"updatedAt":"u","authorAssociation":"CONTRIBUTOR","author":{"__typename":"User","login":"x"},
				"reactionGroups":[]}]}}}}}`,
	}, &log))
	p, err := c.Posted("u/up", 3)
	if err != nil {
		t.Fatal(err)
	}
	if p.PullRequest || p.ViewerPermission != "READ" || p.Opener != (Account{Association: "NONE"}) {
		t.Fatalf("the issue read as %+v", p)
	}
	if len(p.Comments) != 1 || p.Comments[0].AuthorAssociation != "CONTRIBUTOR" || p.Comments[0].Body != "same here" {
		t.Fatalf("the issue's comments read as %+v", p.Comments)
	}
	if len(log) != 1 {
		t.Fatalf("an issue's read ran %d calls, want 1: %q", len(log), log)
	}
}
