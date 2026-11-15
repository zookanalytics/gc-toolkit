// Package fake is the gh adapter's in-memory fake: the PRs a test sets,
// each with its reviews, the check suites at each commit, its review threads
// and its conversation, answered through the reads the adapter's Client makes
// (docs/gctk-architecture.md, "The adapters"). A domain's tests run on it, so
// every rule about a PR is tested in Go without GitHub. It holds none of
// GitHub's rules: what a test sets is what each read returns.
package fake

import (
	"fmt"
	"slices"
	"strings"
	"sync"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
)

// PR is one pull request's state on GitHub. Suites holds the check suites at
// each commit, by its oid.
type PR struct {
	Facts    gh.PullRequest
	Reviews  []gh.Review
	Suites   map[string][]gh.CheckSuite
	Threads  []gh.Thread
	Comments []gh.IssueComment
}

// GitHub is an in-memory GitHub. Self is the login the reads run as. Fail
// fails a read or a request by its method's name, such as "Reviews", with its
// error. OnRead, when set, runs as a read of a PR starts, so a test can change
// GitHub or another writer's state while a read is in flight. OnMerge, when
// set, answers a merge request or an enqueue in place of the default, which
// refuses a request whose head is not the PR's and otherwise merges the PR, or
// adds it to the queue.
type GitHub struct {
	Self    string
	PRs     map[string]*PR
	Fail    map[string]error
	OnRead  func(method string, p *PR)
	OnMerge func(method string, p *PR, head string) error

	mu    sync.Mutex
	reads []string
	asks  []Ask
}

// Ask is one merge request a test's code made: "MergePullRequest" or
// "EnqueuePullRequest", the PR's node id and the head it was pinned to.
type Ask struct {
	Method, ID, Head string
}

// Asks returns the merge requests made, in order.
func (g *GitHub) Asks() []Ask {
	g.mu.Lock()
	defer g.mu.Unlock()
	return slices.Clone(g.asks)
}

// New returns a GitHub that reads as self and holds no PR.
func New(self string) *GitHub {
	return &GitHub{Self: self, PRs: map[string]*PR{}, Fail: map[string]error{}}
}

// Put adds p under its repository and number.
func (g *GitHub) Put(p *PR) { g.PRs[key(p.Facts.Repository, p.Facts.Number)] = p }

// Reads returns the reads made, in order, each as its method's name.
func (g *GitHub) Reads() []string {
	g.mu.Lock()
	defer g.mu.Unlock()
	return slices.Clone(g.reads)
}

func key(repo string, number int) string {
	return fmt.Sprintf("%s#%d", strings.ToLower(repo), number)
}

func (g *GitHub) pr(read, repo string, number int) (*PR, error) {
	g.mu.Lock()
	g.reads = append(g.reads, read)
	err := g.Fail[read]
	p, ok := g.PRs[key(repo, number)]
	g.mu.Unlock()
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, fmt.Errorf("github: %s holds no pull request %d", repo, number)
	}
	if g.OnRead != nil {
		g.OnRead(read, p)
	}
	return p, nil
}

// byID finds the PR whose node id is id.
func (g *GitHub) byID(id string) *PR {
	for _, p := range g.PRs {
		if p.Facts.ID == id {
			return p
		}
	}
	return nil
}

// MergePullRequest records the request and answers it: by OnMerge when set,
// else by refusing a head that is not the PR's and otherwise merging the PR,
// with a merge commit named after its head.
func (g *GitHub) MergePullRequest(id, head string) error {
	return g.ask("MergePullRequest", id, head, func(p *PR) {
		p.Facts.State, p.Facts.MergedAt = "MERGED", "2026-11-12T08:00:00Z"
		p.Facts.MergeCommit = "e" + head[1:]
	})
}

// EnqueuePullRequest records the request and answers it as MergePullRequest
// does, adding the PR to the queue where that one merges it.
func (g *GitHub) EnqueuePullRequest(id, head string) error {
	return g.ask("EnqueuePullRequest", id, head, func(p *PR) { p.Facts.InMergeQueue = true })
}

func (g *GitHub) ask(method, id, head string, take func(*PR)) error {
	g.mu.Lock()
	g.asks = append(g.asks, Ask{Method: method, ID: id, Head: head})
	err := g.Fail[method]
	p := g.byID(id)
	g.mu.Unlock()
	if err != nil {
		return err
	}
	if p == nil {
		return fmt.Errorf("github: no pull request has the node id %s", id)
	}
	if g.OnMerge != nil {
		return g.OnMerge(method, p, head)
	}
	if p.Facts.HeadRefOid != head {
		return fmt.Errorf("github: Head branch was modified. Review and try the merge again.")
	}
	take(p)
	return nil
}

// PullRequest returns the PR's facts.
func (g *GitHub) PullRequest(repo string, number int) (*gh.PullRequest, error) {
	p, err := g.pr("PullRequest", repo, number)
	if err != nil {
		return nil, err
	}
	f := p.Facts
	return &f, nil
}

// Reviews returns the PR's reviews.
func (g *GitHub) Reviews(repo string, number int) ([]gh.Review, error) {
	p, err := g.pr("Reviews", repo, number)
	if err != nil {
		return nil, err
	}
	return slices.Clone(p.Reviews), nil
}

// CheckSuites returns the check suites at oid.
func (g *GitHub) CheckSuites(repo, oid string, number int) ([]gh.CheckSuite, error) {
	p, err := g.pr("CheckSuites", repo, number)
	if err != nil {
		return nil, err
	}
	return slices.Clone(p.Suites[oid]), nil
}

// ReviewThreads returns the PR's review threads.
func (g *GitHub) ReviewThreads(repo string, number int) ([]gh.Thread, error) {
	p, err := g.pr("ReviewThreads", repo, number)
	if err != nil {
		return nil, err
	}
	return slices.Clone(p.Threads), nil
}

// IssueComments returns the comments on the PR's conversation.
func (g *GitHub) IssueComments(repo string, number int) ([]gh.IssueComment, error) {
	p, err := g.pr("IssueComments", repo, number)
	if err != nil {
		return nil, err
	}
	return slices.Clone(p.Comments), nil
}

// Login returns Self.
func (g *GitHub) Login() (string, error) {
	g.mu.Lock()
	g.reads = append(g.reads, "Login")
	err := g.Fail["Login"]
	g.mu.Unlock()
	if err != nil {
		return "", err
	}
	if g.Self == "" {
		return "", fmt.Errorf("github: gh named no account it acts as")
	}
	return g.Self, nil
}
