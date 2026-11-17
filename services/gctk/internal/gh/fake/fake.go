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
// each commit, by its oid. The rest is what the cheap question reads beside
// what it counts from the rest: its labels, when GitHub last changed it, its
// base's tip, its review decision, and its head's check rollup state and the
// commit statuses there, counted by state.
type PR struct {
	Facts          gh.PullRequest
	Reviews        []gh.Review
	Suites         map[string][]gh.CheckSuite
	Threads        []gh.Thread
	Comments       []gh.IssueComment
	Labels         []string
	UpdatedAt      string
	BaseTip        string
	ReviewDecision string
	Rollup         string
	Statuses       map[string]int
}

// GitHub is an in-memory GitHub. Self is the login the reads run as. Fail
// fails a read or a request by its method's name, such as "Reviews", with its
// error. SignsFail fails the cheap question for the PRs it numbers, each with
// its error, and FullFail the net's read. OnRead, when set, runs as a read of a PR starts, so a test can change
// GitHub or another writer's state while a read is in flight. OnMerge, when
// set, answers a merge request or an enqueue in place of the default, which
// refuses a request whose head is not the PR's and otherwise merges the PR, or
// adds it to the queue. OnDismiss, when set, answers a dismissal in place of
// the default, which dismisses the review. Descends names, for each commit,
// the commits it descends from, which a compare reads.
type GitHub struct {
	Self      string
	PRs       map[string]*PR
	Fail      map[string]error
	OnRead    func(method string, p *PR)
	OnMerge   func(method string, p *PR, head string) error
	OnDismiss func(p *PR, review int64) error
	Descends  map[string][]string
	SignsFail map[int]error
	FullFail  map[int]error

	mu    sync.Mutex
	reads []string
	asks  []Ask
	signs [][]int
	full  [][]int
}

// SignsAsked returns the PRs each cheap question asked about, in order.
func (g *GitHub) SignsAsked() [][]int {
	g.mu.Lock()
	defer g.mu.Unlock()
	return slices.Clone(g.signs)
}

// FullAsked returns the PRs each of the net's reads asked about, in order.
func (g *GitHub) FullAsked() [][]int {
	g.mu.Lock()
	defer g.mu.Unlock()
	return slices.Clone(g.full)
}

// Ask is one request a test's code made of GitHub: "MergePullRequest" or
// "EnqueuePullRequest" with the PR's node id and the head it was pinned to,
// "MarkReady" or "ConvertToDraft" with the PR's node id, or "DismissReview"
// with the review's id and the dismissal's message.
type Ask struct {
	Method, ID, Head, Message string
}

// Asks returns the merge requests made, in order.
func (g *GitHub) Asks() []Ask {
	g.mu.Lock()
	defer g.mu.Unlock()
	return slices.Clone(g.asks)
}

// New returns a GitHub that reads as self and holds no PR.
func New(self string) *GitHub {
	return &GitHub{Self: self, PRs: map[string]*PR{}, Fail: map[string]error{}, Descends: map[string][]string{},
		SignsFail: map[int]error{}, FullFail: map[int]error{}}
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

// MarkReady records the request and marks the PR ready.
func (g *GitHub) MarkReady(id string) error {
	return g.stage("MarkReady", id, false)
}

// ConvertToDraft records the request and returns the PR to draft.
func (g *GitHub) ConvertToDraft(id string) error {
	return g.stage("ConvertToDraft", id, true)
}

func (g *GitHub) stage(method, id string, draft bool) error {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.asks = append(g.asks, Ask{Method: method, ID: id})
	if err := g.Fail[method]; err != nil {
		return err
	}
	p := g.byID(id)
	if p == nil {
		return fmt.Errorf("github: no pull request has the node id %s", id)
	}
	p.Facts.IsDraft = draft
	return nil
}

// Compare answers how head stands against base by Descends: identical, ahead
// when head descends from base, behind when base descends from head, and
// diverged otherwise.
func (g *GitHub) Compare(repo, base, head string) (string, error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.reads = append(g.reads, "Compare")
	if err := g.Fail["Compare"]; err != nil {
		return "", err
	}
	switch {
	case base == head:
		return "identical", nil
	case slices.Contains(g.Descends[head], base):
		return "ahead", nil
	case slices.Contains(g.Descends[base], head):
		return "behind", nil
	}
	return "diverged", nil
}

// DismissReview records the dismissal and answers it: by OnDismiss when set,
// else by dismissing the review, which GitHub refuses for a review the PR does
// not hold and for one that neither approves nor requests changes.
func (g *GitHub) DismissReview(repo string, number int, id int64, message string) error {
	g.mu.Lock()
	g.asks = append(g.asks, Ask{Method: "DismissReview", ID: fmt.Sprint(id), Message: message})
	err := g.Fail["DismissReview"]
	p, ok := g.PRs[key(repo, number)]
	g.mu.Unlock()
	if err != nil {
		return err
	}
	if !ok {
		return fmt.Errorf("gh: gh: Not Found (HTTP 404)")
	}
	if g.OnDismiss != nil {
		return g.OnDismiss(p, id)
	}
	g.mu.Lock()
	defer g.mu.Unlock()
	for i, v := range p.Reviews {
		if v.ID != id {
			continue
		}
		if v.State != "APPROVED" && v.State != "CHANGES_REQUESTED" {
			return fmt.Errorf("gh: gh: Can not dismiss a %s pull request review (HTTP 422)", strings.ToLower(v.State))
		}
		p.Reviews[i].State = "DISMISSED"
		return nil
	}
	return fmt.Errorf("gh: gh: Not Found (HTTP 404)")
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

// Signs answers the cheap question for each PR numbered in repo from the PR's
// state: its facts, the comments and the inline comments counted together, the
// reviews and the dismissed among them, its labels sorted, and the check runs
// at its head counted by their conclusion, or by their status while one runs.
// It records one read, "Signs", for the whole question, and a PR it holds no
// such PR for, or one SignsFail numbers, fails alone.
func (g *GitHub) Signs(repo string, numbers []int) (map[int]gh.Signs, map[int]error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.reads = append(g.reads, "Signs")
	g.signs = append(g.signs, slices.Sorted(slices.Values(numbers)))
	read, failed := map[int]gh.Signs{}, map[int]error{}
	for _, n := range numbers {
		if err := g.Fail["Signs"]; err != nil {
			failed[n] = err
			continue
		}
		if err := g.SignsFail[n]; err != nil {
			failed[n] = err
			continue
		}
		p, ok := g.PRs[key(repo, n)]
		if !ok {
			failed[n] = fmt.Errorf("github: %s holds no pull request %d", repo, n)
			continue
		}
		read[n] = p.signs()
	}
	return read, failed
}

func (p *PR) signs() gh.Signs {
	s := gh.Signs{Number: p.Facts.Number, State: p.Facts.State, IsDraft: p.Facts.IsDraft,
		HeadRefOid: p.Facts.HeadRefOid, BaseRefName: p.Facts.BaseRefName, BaseTip: p.BaseTip,
		UpdatedAt: p.UpdatedAt, Comments: len(p.Comments), Reviews: len(p.Reviews), Rollup: p.Rollup,
		CheckRuns: map[string]int{}, Statuses: map[string]int{}}
	for _, t := range p.Threads {
		s.Comments += len(t.Comments)
	}
	for _, v := range p.Reviews {
		if v.State == "DISMISSED" {
			s.Dismissed++
		}
	}
	if len(p.Labels) > 0 {
		s.Labels = slices.Sorted(slices.Values(p.Labels))
	}
	for _, suite := range p.Suites[p.Facts.HeadRefOid] {
		for _, r := range suite.Runs {
			state := r.Status
			if r.Status == "COMPLETED" {
				state = r.Conclusion
			}
			s.CheckRuns[state]++
			s.Contexts++
		}
	}
	for state, n := range p.Statuses {
		if n > 0 {
			s.Statuses[state] = n
			s.Contexts += n
		}
	}
	return s
}

// FullRead answers the net's read for each PR numbered in repo from the PR's
// state: its signs, as Signs answers them, its merge state, review decision and
// merge-queue flags, the time each review, inline comment and conversation
// comment last changed, the threads that are not resolved, and every check run
// in the check suites at its head, listed by name: GitHub's check rollup lists
// them in an order of its own, not suite by suite. It records one read,
// "FullRead", for the whole read, and a PR it holds no such PR for, or one
// FullFail numbers, fails alone.
func (g *GitHub) FullRead(repo string, numbers []int) (map[int]gh.Full, map[int]error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.reads = append(g.reads, "FullRead")
	g.full = append(g.full, slices.Sorted(slices.Values(numbers)))
	read, failed := map[int]gh.Full{}, map[int]error{}
	for _, n := range numbers {
		if err := g.Fail["FullRead"]; err != nil {
			failed[n] = err
			continue
		}
		if err := g.FullFail[n]; err != nil {
			failed[n] = err
			continue
		}
		p, ok := g.PRs[key(repo, n)]
		if !ok {
			failed[n] = fmt.Errorf("github: %s holds no pull request %d", repo, n)
			continue
		}
		f := gh.Full{Signs: p.signs(), MergeStateStatus: p.Facts.MergeStateStatus, ReviewDecision: p.ReviewDecision,
			InMergeQueue: p.Facts.InMergeQueue, MergeQueueEnabled: p.Facts.MergeQueueEnabled, Posts: []string{},
			Unresolved: []string{}, ChecksAt: p.Facts.HeadRefOid, Checks: []gh.CheckRun{}}
		for _, v := range p.Reviews {
			f.Posts = append(f.Posts, v.UpdatedAt)
		}
		for _, t := range p.Threads {
			if !t.Resolved {
				f.Unresolved = append(f.Unresolved, t.ID)
			}
			for _, c := range t.Comments {
				f.Posts = append(f.Posts, c.UpdatedAt)
			}
		}
		for _, c := range p.Comments {
			f.Posts = append(f.Posts, c.UpdatedAt)
		}
		slices.Sort(f.Unresolved)
		for _, s := range p.Suites[p.Facts.HeadRefOid] {
			f.Checks = append(f.Checks, s.Runs...)
		}
		slices.SortStableFunc(f.Checks, func(a, b gh.CheckRun) int { return strings.Compare(a.Name, b.Name) })
		read[n] = f
	}
	return read, failed
}

// PullRequestPart returns the PR's facts and, with checks, the check suites at
// its head. It records "PullRequestPart", or "PullRequestPart+checks".
func (g *GitHub) PullRequestPart(repo string, number int, checks bool) (*gh.PRPart, error) {
	read := "PullRequestPart"
	if checks {
		read += "+checks"
	}
	p, err := g.pr(read, repo, number)
	if err != nil {
		return nil, err
	}
	g.mu.Lock()
	defer g.mu.Unlock()
	out := &gh.PRPart{PullRequest: p.Facts}
	if checks {
		out.ChecksAt = p.Facts.HeadRefOid
		out.Suites = slices.Clone(p.Suites[p.Facts.HeadRefOid])
		if out.Suites == nil {
			out.Suites = []gh.CheckSuite{}
		}
	}
	return out, nil
}

// Conversation returns the PR's reviews, threads, conversation comments and
// review decision.
func (g *GitHub) Conversation(repo string, number int) (*gh.Conversation, error) {
	p, err := g.pr("Conversation", repo, number)
	if err != nil {
		return nil, err
	}
	g.mu.Lock()
	defer g.mu.Unlock()
	return &gh.Conversation{Reviews: slices.Clone(p.Reviews), Threads: slices.Clone(p.Threads),
		Comments: slices.Clone(p.Comments), ReviewDecision: p.ReviewDecision}, nil
}
