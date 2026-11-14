package listing

import (
	"context"
	"errors"
	"strconv"
	"sync"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/feedback"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	ghfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
)

// everyPost is a definition of feedback that reads every post as feedback and
// no thread as waiting on the city's answer.
type everyPost struct{}

func ids64[T any](xs []T, id func(T) int64) []int64 {
	var out []int64
	for _, x := range xs {
		out = append(out, id(x))
	}
	return out
}

func (everyPost) Reviews(_, _ string, rs []feedback.Review) ([]int64, error) {
	return ids64(rs, func(r feedback.Review) int64 { return r.ID }), nil
}

func (everyPost) Comments(_, _ string, cs []feedback.Comment) ([]int64, error) {
	return ids64(cs, func(c feedback.Comment) int64 { return c.ID }), nil
}

func (everyPost) IssueComments(_, _ string, cs []feedback.Comment) ([]int64, error) {
	return ids64(cs, func(c feedback.Comment) int64 { return c.ID }), nil
}

func (everyPost) Awaiting(_, _ string, _ []feedback.Thread) ([]string, error) { return nil, nil }

const (
	readyHead  = "1111111111111111111111111111111111111111"
	readyStore = "/fixture/acme/.beads"
)

// pending is a bead on Gas Town's pending record for PR number of
// acme/widgets, recorded at readyHead.
func pending(id, number string) fake.Bead {
	return fake.Bead{ID: id, Title: "the work", Status: "blocked", IssueType: "task", Assignee: "acme/refinery",
		Metadata: map[string]string{
			"merge_result": "pull_request_pending", "pr_url": "https://github.com/acme/widgets/pull/" + number,
			"pr_number": number, "pr_repo": "acme/widgets", "pr_head_sha": readyHead, "merged_target": "main",
			"branch":         "polecat/" + id,
			"review_results": `[{"head":"` + readyHead + `","target":"main","passed":true}]`,
		}}
}

// readyPR is PR number on GitHub, open at readyHead on the bead's branch,
// approved, with its required check passed.
func readyPR(bead string, number int) *ghfake.PR {
	return &ghfake.PR{
		Facts: gh.PullRequest{Number: number, URL: "https://github.com/acme/widgets/pull/" + strconv.Itoa(number), State: "OPEN",
			HeadRefName: "polecat/" + bead, HeadRefOid: readyHead, BaseRefName: "main", MergeStateStatus: "CLEAN",
			Repository: "acme/widgets"},
		Reviews: []gh.Review{{ID: 100, State: "APPROVED", Author: "operator", AuthorCanPush: true,
			SubmittedAt: "2026-11-12T01:00:00Z"}},
		Suites: map[string][]gh.CheckSuite{readyHead: {{ID: 1, Runs: []gh.CheckRun{
			{Name: "test", Status: "COMPLETED", Conclusion: "SUCCESS", Required: true}}}}},
	}
}

// readyWorld is a listing of a store at readyStore that holds two beads on the
// pending record, tk-a for PR 7, which GitHub holds ready, and tk-b for PR 8,
// which GitHub does not hold, beside the GitHub and the definition of feedback
// Ready reads through, each recording what it was asked.
type readyWorld struct {
	ls     *Listing
	github *ghfake.GitHub
	mu     sync.Mutex
	hosts  []string
	ages   []time.Duration
	loaded []string
}

func newReadyWorld(t *testing.T) *readyWorld {
	t.Helper()
	s := fake.New()
	s.Put(pending("tk-a", "7"))
	s.Put(pending("tk-b", "8"))
	ls, err := read(ledger.New(s))
	if err != nil {
		t.Fatal(err)
	}
	ls.db = readyStore
	w := &readyWorld{ls: ls, github: ghfake.New("zook-bot")}
	w.github.Put(readyPR("tk-a", 7))
	oldGitHub, oldFeedback := gitHubOn, feedbackIn
	t.Cleanup(func() { gitHubOn, feedbackIn = oldGitHub, oldFeedback })
	gitHubOn = func(_ context.Context, host string, maxAge time.Duration) pr.GitHub {
		w.mu.Lock()
		defer w.mu.Unlock()
		w.hosts, w.ages = append(w.hosts, host), append(w.ages, maxAge)
		return w.github
	}
	feedbackIn = func(checkout string) (pr.Feedback, error) {
		w.mu.Lock()
		defer w.mu.Unlock()
		w.loaded = append(w.loaded, checkout)
		return everyPost{}, nil
	}
	return w
}

// Ready answers each bead from the listing's rows and GitHub's facts, and a
// bead whose read of GitHub failed gets that error and no answer. GitHub is
// read on the host the PR's URL names, at the age the caller allows, and the
// definition of feedback is loaded once, in the checkout that holds the
// listing's store.
func TestReadyAnswersEachBeadOnThePendingRecord(t *testing.T) {
	w := newReadyWorld(t)
	answers, failed := w.ls.Ready([]string{"tk-b", "tk-a", "tk-a"}, 5*time.Minute)
	a, ok := answers["tk-a"]
	if !ok || !a.Ready || a.Head != readyHead || a.Target != "main" {
		t.Errorf("tk-a answers %+v (answered: %v, error: %v), want ready at %s into main", a, ok, failed["tk-a"], readyHead)
	}
	if _, ok := answers["tk-b"]; ok || failed["tk-b"] == nil {
		t.Errorf("tk-b, whose PR GitHub does not hold, answers %+v with error %v, want no answer and an error",
			answers["tk-b"], failed["tk-b"])
	}
	if len(answers)+len(failed) != 2 {
		t.Errorf("Ready answered %v and failed %v, want each bead once", answers, failed)
	}
	if len(w.loaded) != 1 || w.loaded[0] != "/fixture/acme" {
		t.Errorf("the definition of feedback loaded in %v, want once in /fixture/acme", w.loaded)
	}
	for i, host := range w.hosts {
		if host != "github.com" || w.ages[i] != 5*time.Minute {
			t.Errorf("GitHub was read on %s at age %s, want github.com at 5m", host, w.ages[i])
		}
	}
	if len(w.hosts) != 2 {
		t.Errorf("GitHub was asked for %d clients, want one per bead", len(w.hosts))
	}
}

// A definition of feedback that does not load leaves every bead without an
// answer, and so does a listing that names no store, since no rig's checkout
// holds its definition. A call that names no bead loads nothing.
func TestReadyWithNoDefinitionOfFeedbackAnswersNoBead(t *testing.T) {
	w := newReadyWorld(t)
	broken := errors.New("pr-post.sh printed no definition")
	feedbackIn = func(string) (pr.Feedback, error) { return nil, broken }
	answers, failed := w.ls.Ready([]string{"tk-a", "tk-b"}, time.Minute)
	if len(answers) != 0 || !errors.Is(failed["tk-a"], broken) || !errors.Is(failed["tk-b"], broken) {
		t.Errorf("Ready answered %v and failed %v, want every bead failed by the definition's error", answers, failed)
	}

	w = newReadyWorld(t)
	w.ls.db = ""
	answers, failed = w.ls.Ready([]string{"tk-a"}, time.Minute)
	if len(answers) != 0 || failed["tk-a"] == nil || len(w.loaded) != 0 {
		t.Errorf("a listing with no store answered %v, failed %v and loaded %v, want tk-a failed and nothing loaded",
			answers, failed, w.loaded)
	}

	w = newReadyWorld(t)
	if answers, failed := w.ls.Ready(nil, time.Minute); len(answers)+len(failed) != 0 || len(w.loaded) != 0 {
		t.Errorf("a call naming no bead answered %v, failed %v and loaded %v", answers, failed, w.loaded)
	}
}
