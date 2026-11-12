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
// fails a read by its method's name, such as "Reviews", with its error.
type GitHub struct {
	Self string
	PRs  map[string]*PR
	Fail map[string]error

	reads []string
}

// New returns a GitHub that reads as self and holds no PR.
func New(self string) *GitHub {
	return &GitHub{Self: self, PRs: map[string]*PR{}, Fail: map[string]error{}}
}

// Put adds p under its repository and number.
func (g *GitHub) Put(p *PR) { g.PRs[key(p.Facts.Repository, p.Facts.Number)] = p }

// Reads returns the reads made, in order, each as its method's name.
func (g *GitHub) Reads() []string { return slices.Clone(g.reads) }

func key(repo string, number int) string {
	return fmt.Sprintf("%s#%d", strings.ToLower(repo), number)
}

func (g *GitHub) pr(read, repo string, number int) (*PR, error) {
	g.reads = append(g.reads, read)
	if err := g.Fail[read]; err != nil {
		return nil, err
	}
	p, ok := g.PRs[key(repo, number)]
	if !ok {
		return nil, fmt.Errorf("github: %s holds no pull request %d", repo, number)
	}
	return p, nil
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
	g.reads = append(g.reads, "Login")
	if err := g.Fail["Login"]; err != nil {
		return "", err
	}
	if g.Self == "" {
		return "", fmt.Errorf("github: gh named no account it acts as")
	}
	return g.Self, nil
}
