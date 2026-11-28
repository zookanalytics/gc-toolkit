package cli

import (
	"bytes"
	"encoding/json"
	"errors"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/quote"
)

// postedHub answers a quote's read with p, or fails it with err.
type postedHub struct {
	p   *gh.Posted
	err error
}

func (h postedHub) Posted(string, int) (*gh.Posted, error) { return h.p, h.err }

func (postedHub) AddReaction(string, string) error { return nil }

// pinQuote makes the command read p, or fail with err, and record each
// follow-up it files, answering it with bead and followErr, until the test
// ends.
func pinQuote(t *testing.T, p *gh.Posted, err error, bead string, followErr error) *[]string {
	t.Helper()
	hub, follow := newQuoteHub, quoteFollowUp
	var filed []string
	newQuoteHub = func(string) quoteHub { return postedHub{p, err} }
	quoteFollowUp = func(_ quoteHub, url, repo string, number int, held []quote.Held) (string, error) {
		for _, h := range held {
			filed = append(filed, url+" "+h.Author+" "+h.URL)
		}
		return bead, followErr
	}
	t.Cleanup(func() { newQuoteHub, quoteFollowUp = hub, follow })
	return &filed
}

// aPR is a PR on a repository the city can push to, with one post by the
// city's account and one by an outside account.
func aPR() *gh.Posted {
	return &gh.Posted{Repository: "o/r", Number: 7, URL: "https://github.com/o/r/pull/7", PullRequest: true,
		Title: "fix: it", Body: "run `this`", ViewerPermission: "WRITE",
		Opener: gh.Account{Login: "zook-bot", Type: "User", Association: "MEMBER"},
		Comments: []gh.IssueComment{
			{ID: 1, URL: "https://github.com/o/r/pull/7#issuecomment-1", Author: "zook-bot", AuthorType: "User",
				AuthorAssociation: "MEMBER", Body: "own words"},
			{ID: 2, URL: "https://github.com/o/r/pull/7#issuecomment-2", Author: "stranger", AuthorType: "User",
				AuthorAssociation: "NONE", Body: "outside words"},
		}}
}

// A quote prints the block, holds the outside account's post, files its
// follow-up and says so on stderr, naming no bead, and exits 0.
func TestGitHubQuotePrintsTheBlockAndFilesTheFollowUp(t *testing.T) {
	filed := pinQuote(t, aPR(), nil, "tk-1", nil)
	var out, errb bytes.Buffer
	if code := Run([]string{"github", "quote", "https://github.com/o/r/pull/7"}, "test", &out, &errb); code != 0 {
		t.Fatalf("exit %d: %s", code, errb.String())
	}
	text := out.String()
	if !strings.HasPrefix(text, "<github-text>\n") || !strings.Contains(text, "│ run ˋthisˋ") ||
		!strings.Contains(text, "│ own words") || !strings.Contains(text, quote.Placeholder) ||
		strings.Contains(text, "outside words") || strings.Contains(text, "issuecomment-2") {
		t.Fatalf("the quote printed\n%s", text)
	}
	if len(*filed) != 1 || (*filed)[0] != "https://github.com/o/r/pull/7 stranger https://github.com/o/r/pull/7#issuecomment-2" {
		t.Fatalf("follow-ups filed %q", *filed)
	}
	if !strings.Contains(errb.String(), "the operator has a follow-up") || strings.Contains(errb.String(), "tk-1") {
		t.Fatalf("stderr %q", errb.String())
	}
}

// --json prints the quote as one object, a held post carrying its kind alone,
// and --description the title and the body alone, with no follow-up owed.
func TestGitHubQuoteJSONAndDescription(t *testing.T) {
	filed := pinQuote(t, aPR(), nil, "tk-1", nil)
	var out, errb bytes.Buffer
	if code := Run([]string{"github", "quote", "--json", "https://github.com/o/r/pull/7"}, "test", &out, &errb); code != 0 {
		t.Fatalf("exit %d: %s", code, errb.String())
	}
	var q struct {
		OwnRepository bool         `json:"own_repository"`
		Posts         []quote.Post `json:"posts"`
	}
	if err := json.Unmarshal(out.Bytes(), &q); err != nil {
		t.Fatal(err)
	}
	if !q.OwnRepository || len(q.Posts) != 3 || !q.Posts[2].Held || q.Posts[2].URL != "" || q.Posts[1].Text != "│ own words" {
		t.Fatalf("the JSON quote read %+v", q)
	}
	*filed = nil
	out.Reset()
	errb.Reset()
	if code := Run([]string{"github", "quote", "--description", "https://github.com/o/r/pull/7"}, "test", &out, &errb); code != 0 {
		t.Fatalf("exit %d: %s", code, errb.String())
	}
	if strings.Contains(out.String(), "own words") || !strings.Contains(out.String(), "│ fix: it") || len(*filed) != 0 {
		t.Fatalf("the description printed\n%s\nand filed %q", out.String(), *filed)
	}
}

// A URL of another shape, or --description with a post's URL, is a usage
// error; a read that fails, or a follow-up that does not file, exits 1, the
// latter once the quote printed; and a PR no bead owns files nothing and says
// so.
func TestGitHubQuoteExits(t *testing.T) {
	pinQuote(t, aPR(), nil, "", nil)
	var out, errb bytes.Buffer
	for _, args := range [][]string{{"github", "quote", "https://github.com/o/r"},
		{"github", "quote", "--description", "https://github.com/o/r/pull/7#issuecomment-1"}} {
		if code := Run(args, "test", &out, &errb); code != 2 {
			t.Fatalf("%q exited %d, want 2", args, code)
		}
	}
	errb.Reset()
	if code := Run([]string{"github", "quote", "https://github.com/o/r/pull/7"}, "test", &out, &errb); code != 0 ||
		!strings.Contains(errb.String(), "no bead in this store owns the PR") {
		t.Fatalf("a PR no bead owns exited %d: %s", code, errb.String())
	}
	pinQuote(t, nil, errors.New("gh: HTTP 502"), "", nil)
	if code := Run([]string{"github", "quote", "https://github.com/o/r/pull/7"}, "test", &out, &errb); code != 1 {
		t.Fatalf("a failed read exited %d", code)
	}
	pinQuote(t, aPR(), nil, "tk-1", errors.New("human-gate.sh: exit 1"))
	out.Reset()
	errb.Reset()
	if code := Run([]string{"github", "quote", "https://github.com/o/r/pull/7"}, "test", &out, &errb); code != 1 ||
		!strings.Contains(out.String(), quote.Placeholder) || !strings.Contains(errb.String(), "did not complete") {
		t.Fatalf("a follow-up that did not file exited %d: %s", code, errb.String())
	}
	pinQuote(t, aPR(), nil, "tk-1", nil)
	if code := Run([]string{"github", "quote", "https://github.com/o/r/pull/7#issuecomment-9"}, "test", &out, &errb); code != 1 {
		t.Fatalf("a post the PR does not hold exited %d", code)
	}
}

// A held post that already carries the city's EYES was followed up by the take
// or an earlier read, so a quote files nothing for it, however often the PR is
// read after the operator clears its gate, and says so.
func TestGitHubQuoteFilesNothingForAPostAlreadyFollowedUp(t *testing.T) {
	p := aPR()
	p.Comments[1].NodeID, p.Comments[1].ViewerReactions = "IC_2", []string{"EYES"}
	filed := pinQuote(t, p, nil, "tk-1", nil)
	var out, errb bytes.Buffer
	if code := Run([]string{"github", "quote", "https://github.com/o/r/pull/7"}, "test", &out, &errb); code != 0 {
		t.Fatalf("exit %d: %s", code, errb.String())
	}
	if len(*filed) != 0 || !strings.Contains(out.String(), quote.Placeholder) ||
		!strings.Contains(errb.String(), "followed up already") {
		t.Fatalf("filed %q, stderr %q", *filed, errb.String())
	}
}
