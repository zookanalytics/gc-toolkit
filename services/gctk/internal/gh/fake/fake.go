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
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
)

// PR is one pull request's state on GitHub. Suites holds the check suites at
// each commit, by its oid. ReviewDecision is what the net's read and the read
// of the conversation give. The rest is what the cheap question reads beside
// what it counts from the rest: its labels, when GitHub last changed it, its
// base's tip, and its head's check rollup state and the commit statuses there,
// counted by state. Drafted is each time its timeline records it was returned
// to draft, oldest first, which a return to draft through ConvertToDraft adds
// to.
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
	Drafted        []string
}

// GitHub is an in-memory GitHub. Self is the login the reads run as. Fail
// fails a read or a request by its method's name, such as "Reviews", with its
// error. SignsFail fails the cheap question for the PRs it numbers, each with
// its error, and FullFail the net's read. LabeledPage sets the size of a page
// of the search for labeled PRs. OnRead, when set, runs as a read of
// a PR starts, so a test can change GitHub or another writer's state while a
// read is in flight. OnMerge, when set, answers a merge request or an enqueue
// in place of the default, which refuses a request whose head is not the PR's
// and otherwise merges the PR, or adds it to the queue. OnDismiss, when set,
// answers a dismissal in place of the default, which dismisses the review.
// OnReact, when set, runs as a reaction is asked, and an error it returns
// fails that reaction, which then leaves nothing on the post. Now stamps a
// return to draft in the PR's timeline, the system's clock when nil.
type GitHub struct {
	Self      string
	PRs       map[string]*PR
	Fail      map[string]error
	OnRead    func(method string, p *PR)
	OnMerge   func(method string, p *PR, head string) error
	OnDismiss func(p *PR, review int64) error
	OnReact   func(subject, content string) error
	Now       func() time.Time
	SignsFail map[int]error
	FullFail  map[int]error
	// LabeledPage is how many PRs a page of the search holds,
	// gh.LabeledBatch when it is 0.
	LabeledPage int
	// Repos is each repository's default branch and the checks at each ref,
	// by its owner/name.
	Repos map[string]*Repo

	mu       sync.Mutex
	reads    []string
	asks     []Ask
	signs    [][]int
	full     [][]int
	searched []string
}

// Searched returns the cursor each page of the search for labeled PRs started
// from, in order, "" for a first page.
func (g *GitHub) Searched() []string {
	g.mu.Lock()
	defer g.mu.Unlock()
	return slices.Clone(g.searched)
}

// Labeled answers a page of the search for the PRs in repo that carry any of
// the labels named, newest first: LabeledPage of them from the cursor after,
// which the page before gave as the position it ended at. It records one read,
// "Labeled", for each page.
func (g *GitHub) Labeled(repo string, names []string, after string) (gh.LabeledPage, error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.reads = append(g.reads, "Labeled")
	g.searched = append(g.searched, after)
	if err := g.Fail["Labeled"]; err != nil {
		return gh.LabeledPage{}, err
	}
	var found []*PR
	for _, p := range g.PRs {
		if strings.EqualFold(p.Facts.Repository, repo) && slices.ContainsFunc(p.Labels, func(l string) bool {
			return slices.Contains(names, l)
		}) {
			found = append(found, p)
		}
	}
	slices.SortFunc(found, func(a, b *PR) int { return b.Facts.Number - a.Facts.Number })
	from := 0
	if after != "" {
		n, err := strconv.Atoi(strings.TrimPrefix(after, "cursor:"))
		if err != nil || !strings.HasPrefix(after, "cursor:") || n < 0 || n > len(found) {
			return gh.LabeledPage{}, fmt.Errorf("github: %q is no cursor of the search", after)
		}
		from = n
	}
	size := g.LabeledPage
	if size <= 0 {
		size = gh.LabeledBatch
	}
	var page gh.LabeledPage
	end := min(from+size, len(found))
	for _, p := range found[from:end] {
		page.PRs = append(page.PRs, gh.LabeledPR{Number: p.Facts.Number, State: p.Facts.State})
	}
	if end < len(found) {
		page.Next = "cursor:" + strconv.Itoa(end)
	}
	return page, nil
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

// Repo is one repository's default branch and the checks at each ref.
type Repo struct {
	DefaultBranch string
	Checks        map[string]*gh.HeadChecks
}

// Ask is one request a test's code made of GitHub: "MergePullRequest" or
// "EnqueuePullRequest" with the PR's node id and the head it was pinned to,
// "MarkReady" or "ConvertToDraft" with the PR's node id, "DismissReview" with
// the review's id and the dismissal's message, "AddReaction" with the post's
// node id and the reaction as its message, or "RerunFailedJobs" with the
// workflow run's id.
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
	return &GitHub{Self: self, PRs: map[string]*PR{}, Fail: map[string]error{}, SignsFail: map[int]error{},
		FullFail: map[int]error{}}
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
		return fmt.Errorf("github: Head branch was modified. Review and try the merge again")
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
	if draft && !p.Facts.IsDraft {
		now := time.Now
		if g.Now != nil {
			now = g.Now
		}
		p.Drafted = append(p.Drafted, now().UTC().Format(time.RFC3339))
	}
	p.Facts.IsDraft = draft
	return nil
}

// RerunFailedJobs records the re-run, with the run's id, and answers it by
// raising the attempt of the check suite the run is behind and queueing each
// of its check runs that completed without passing, as a re-run of a run's
// failed jobs does. A run no PR's suite is behind is an error, as GitHub
// answers a run it does not hold, and so is one whose suite has not completed,
// which GitHub refuses as already running.
func (g *GitHub) RerunFailedJobs(repo string, run int64) error {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.asks = append(g.asks, Ask{Method: "RerunFailedJobs", ID: strconv.FormatInt(run, 10)})
	if err := g.Fail["RerunFailedJobs"]; err != nil {
		return err
	}
	for _, p := range g.PRs {
		if !strings.EqualFold(p.Facts.Repository, repo) {
			continue
		}
		for oid := range p.Suites {
			for i := range p.Suites[oid] {
				s := &p.Suites[oid][i]
				if s.Run != run {
					continue
				}
				if s.Status != "COMPLETED" {
					return fmt.Errorf("github: run %d cannot be rerun; This workflow is already running (HTTP 403)", run)
				}
				s.Attempt++
				s.Status = "QUEUED"
				for j := range s.Runs {
					r := &s.Runs[j]
					if r.Status == "COMPLETED" && r.Conclusion != "SUCCESS" && r.Conclusion != "NEUTRAL" &&
						r.Conclusion != "SKIPPED" {
						r.Status, r.Conclusion = "QUEUED", ""
					}
				}
				return nil
			}
		}
	}
	return fmt.Errorf("github: %s holds no workflow run %d (HTTP 404)", repo, run)
}

// ConvertedToDraft returns each time the PR's timeline records it was returned
// to draft. It records the read, "ConvertedToDraft".
func (g *GitHub) ConvertedToDraft(repo string, number int) ([]string, error) {
	p, err := g.pr("ConvertedToDraft", repo, number)
	if err != nil {
		return nil, err
	}
	g.mu.Lock()
	defer g.mu.Unlock()
	return append([]string{}, p.Drafted...), nil
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

// AddReaction records the reaction and answers it: with OnReact's error when it
// returns one, else by leaving content among the reactions Self left on the
// review, inline comment or conversation comment whose node id is subject,
// once, as GitHub keeps one reaction of each content for each account. A node
// id no post holds is an error, as GitHub answers one that resolves to nothing.
func (g *GitHub) AddReaction(subject, content string) error {
	g.mu.Lock()
	g.asks = append(g.asks, Ask{Method: "AddReaction", ID: subject, Message: content})
	err := g.Fail["AddReaction"]
	g.mu.Unlock()
	if err != nil {
		return err
	}
	if g.OnReact != nil {
		if err := g.OnReact(subject, content); err != nil {
			return err
		}
	}
	g.mu.Lock()
	defer g.mu.Unlock()
	add := func(have []string) []string {
		if slices.Contains(have, content) {
			return have
		}
		return append(slices.Clone(have), content)
	}
	for _, p := range g.PRs {
		for i, v := range p.Reviews {
			if v.NodeID == subject {
				p.Reviews[i].ViewerReactions = add(v.ViewerReactions)
				return nil
			}
		}
		for i, t := range p.Threads {
			for j, c := range t.Comments {
				if c.NodeID == subject {
					p.Threads[i].Comments = slices.Clone(t.Comments)
					p.Threads[i].Comments[j].ViewerReactions = add(c.ViewerReactions)
					return nil
				}
			}
		}
		for i, c := range p.Comments {
			if c.NodeID == subject {
				p.Comments[i].ViewerReactions = add(c.ViewerReactions)
				return nil
			}
		}
	}
	return fmt.Errorf("github: Could not resolve to a node with the global id of '%s'", subject)
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
			Unresolved: []string{}, ViewerReactions: []string{}, ChecksAt: p.Facts.HeadRefOid, Checks: []gh.CheckRun{}}
		for _, v := range p.Reviews {
			f.Posts = append(f.Posts, v.UpdatedAt)
		}
		for _, t := range p.Threads {
			if !t.Resolved {
				f.Unresolved = append(f.Unresolved, t.ID)
			}
			for _, c := range t.Comments {
				f.Posts = append(f.Posts, c.UpdatedAt)
				for _, r := range c.ViewerReactions {
					f.ViewerReactions = append(f.ViewerReactions, strconv.FormatInt(c.ID, 10)+" "+r)
				}
			}
		}
		for _, c := range p.Comments {
			f.Posts = append(f.Posts, c.UpdatedAt)
		}
		slices.Sort(f.Unresolved)
		slices.Sort(f.ViewerReactions)
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

// DefaultBranch answers the repository's default branch, failing as
// Fail["DefaultBranch"] says, and for a repository Repos does not hold.
func (g *GitHub) DefaultBranch(repo string) (string, error) {
	r, err := g.repo("DefaultBranch", repo)
	if err != nil {
		return "", err
	}
	if r.DefaultBranch == "" {
		return "", fmt.Errorf("github: %s named no default branch", repo)
	}
	return r.DefaultBranch, nil
}

// HeadChecks answers the checks Repos holds at ref, failing as
// Fail["HeadChecks"] says, and for a ref it holds none at.
func (g *GitHub) HeadChecks(repo, ref string) (*gh.HeadChecks, error) {
	r, err := g.repo("HeadChecks", repo)
	if err != nil {
		return nil, err
	}
	h, ok := r.Checks[ref]
	if !ok {
		return nil, fmt.Errorf("github: no checks at %s in %s", ref, repo)
	}
	out := *h
	out.Runs, out.Statuses = slices.Clone(h.Runs), slices.Clone(h.Statuses)
	return &out, nil
}

func (g *GitHub) repo(read, repo string) (*Repo, error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.reads = append(g.reads, read)
	if err := g.Fail[read]; err != nil {
		return nil, err
	}
	r, ok := g.Repos[strings.ToLower(repo)]
	if !ok {
		return nil, fmt.Errorf("github: no repository %s", repo)
	}
	return r, nil
}
