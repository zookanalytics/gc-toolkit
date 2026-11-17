package pr

import (
	"fmt"
	"maps"
	"reflect"
	"slices"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
)

// The saved read (specs/tk-1tfzr71.149/design.md, section 3) is GitHub's side
// of a PR on the bead that owns it, in four parts: the PR, its checks, its
// conversation and its labels. Each part keeps the instant its read was sent
// and the signs read with it, never later than its facts, so the one-PR update
// can tell which part a moved sign makes stale, and an older read of a part
// never replaces a newer one.

// SavedRead is GitHub's side of a PR as the one-PR update saved it. A part is
// nil until the update has read it.
type SavedRead struct {
	PR           *SavedPR           `json:"pr,omitempty"`
	Checks       *SavedChecks       `json:"checks,omitempty"`
	Conversation *SavedConversation `json:"conversation,omitempty"`
	Labels       *SavedLabels       `json:"labels,omitempty"`
}

// SavedPR is the PR's own facts: its node id, which a request to GitHub names
// it by, its identity, head branch and base, its head, state, draft flag and
// merge state, whether it is in a merge queue and whether its base requires
// one, and, once it merged, its merge commit and when it merged.
type SavedPR struct {
	ReadAt            string  `json:"read_at"`
	ID                string  `json:"id"`
	URL               string  `json:"url"`
	Number            int     `json:"number"`
	Repository        string  `json:"repository"`
	HeadBranch        string  `json:"head_branch"`
	Base              string  `json:"base"`
	Head              string  `json:"head"`
	State             string  `json:"state"`
	Draft             bool    `json:"draft"`
	MergeState        string  `json:"merge_state"`
	InMergeQueue      bool    `json:"in_merge_queue"`
	MergeQueueEnabled bool    `json:"merge_queue_enabled"`
	MergeCommit       string  `json:"merge_commit"`
	MergedAt          string  `json:"merged_at"`
	Signs             PRSigns `json:"signs"`
}

// PRSigns are the signs kept with the PR's own facts.
type PRSigns struct {
	State     string `json:"state"`
	Draft     bool   `json:"draft"`
	Head      string `json:"head"`
	Base      string `json:"base"`
	BaseTip   string `json:"base_tip"`
	UpdatedAt string `json:"updated_at"`
}

// SavedChecks is the required check runs at Head, each result its check suite
// holds as the run's latest.
type SavedChecks struct {
	ReadAt string        `json:"read_at"`
	Head   string        `json:"head"`
	Runs   []RequiredRun `json:"runs"`
	Signs  CheckSigns    `json:"signs"`
}

// CheckSigns are the signs kept with the checks: the head, the rollup's state,
// the contexts' total and the check runs and commit statuses counted by state.
type CheckSigns struct {
	Head      string         `json:"head"`
	Rollup    string         `json:"rollup"`
	Contexts  int            `json:"contexts"`
	CheckRuns map[string]int `json:"check_runs"`
	Statuses  map[string]int `json:"statuses"`
}

// SavedConversation is what the rule reads of the PR's conversation, with the
// definition of feedback applied from Since: the accounts whose approval or
// request for changes stands, the newest feedback in each id space, the review
// threads waiting on the city's answer, the unresolved threads and GitHub's
// review decision. Approvals is each approval that stands, which an approval's
// withdrawal reads.
type SavedConversation struct {
	ReadAt         string            `json:"read_at"`
	Since          string            `json:"since"`
	Approvers      []string          `json:"approvers"`
	Requesters     []string          `json:"requesters"`
	Feedback       NewestFeedback    `json:"feedback"`
	Awaiting       []string          `json:"awaiting"`
	Unresolved     []string          `json:"unresolved"`
	ReviewDecision string            `json:"review_decision"`
	Approvals      []Approval        `json:"approvals"`
	Signs          ConversationSigns `json:"signs"`
}

// Approval is one review that approves the PR and has not been dismissed,
// whoever gave it: its id, its author, the commit it was given on, "" when
// GitHub names none, and Inline, the newest inline comment it carries that is
// feedback by the definition, 0 for none, which a dismissal would retire.
type Approval struct {
	ID     int64  `json:"id"`
	Author string `json:"author"`
	Commit string `json:"commit"`
	Inline int64  `json:"inline"`
}

// ConversationSigns are the signs kept with the conversation: the comment, review
// and dismissed counts, when GitHub last changed the PR, and the newest post
// time, the latest time any conversation comment, review or inline comment
// changed, which the update reads with the posts.
type ConversationSigns struct {
	Comments        int      `json:"comments"`
	Reviews         int      `json:"reviews"`
	Dismissed       int      `json:"dismissed"`
	UpdatedAt       string   `json:"updated_at"`
	NewestPost      string   `json:"newest_post"`
	ViewerReactions []string `json:"viewer_reactions,omitempty"`
}

// SavedLabels is the PR's labels, every one, sorted. They are their own signs.
type SavedLabels struct {
	ReadAt string   `json:"read_at"`
	Names  []string `json:"names"`
}

// view is the saved read as the rule reads it, GitHub's side of the PR at one
// head, and why it is no such read when it is not: no read is saved, a part the
// rule reads is missing, or the checks were read at another head than the PR.
func (s *SavedRead) view() (*GitHubRead, string) {
	switch {
	case s == nil || (s.PR == nil && s.Checks == nil && s.Conversation == nil):
		return nil, "no read of GitHub is saved on the bead"
	case s.PR == nil:
		return nil, "the saved read holds no read of the PR itself"
	case s.Checks == nil:
		return nil, "the saved read holds no read of the PR's checks"
	case s.Conversation == nil:
		return nil, "the saved read holds no read of the PR's conversation"
	case s.Checks.Head != s.PR.Head:
		return nil, fmt.Sprintf("the checks are read at head %s and the PR at %s", s.Checks.Head, s.PR.Head)
	}
	p, c := s.PR, s.Conversation
	return &GitHubRead{ReadAt: p.ReadAt, Since: c.Since, URL: p.URL, Number: p.Number, Repository: p.Repository,
		HeadBranch: p.HeadBranch, Base: p.Base, Head: p.Head, State: p.State, Draft: p.Draft, MergeState: p.MergeState,
		Checks: s.Checks.Runs, Approvers: c.Approvers, Requesters: c.Requesters, Feedback: c.Feedback,
		Awaiting: c.Awaiting}, ""
}

// parts names the parts of a saved read a read covers.
type parts struct{ pr, checks, conversation, labels bool }

func (p parts) any() bool { return p.pr || p.checks || p.conversation || p.labels }

// plus is each part p or q names.
func (p parts) plus(q parts) parts {
	return parts{p.pr || q.pr, p.checks || q.checks, p.conversation || q.conversation, p.labels || q.labels}
}

// every is each part.
var every = parts{true, true, true, true}

func (p parts) String() string {
	var names []string
	for _, n := range []struct {
		on   bool
		name string
	}{{p.pr, "pr"}, {p.checks, "checks"}, {p.conversation, "conversation"}, {p.labels, "labels"}} {
		if n.on {
			names = append(names, n.name)
		}
	}
	return strings.Join(names, ", ")
}

// prSigns, checkSigns and labels are the cheap signs as each part keeps them.
func prSigns(s gh.Signs) PRSigns {
	return PRSigns{State: s.State, Draft: s.IsDraft, Head: s.HeadRefOid, Base: s.BaseRefName, BaseTip: s.BaseTip,
		UpdatedAt: s.UpdatedAt}
}

func checkSigns(s gh.Signs) CheckSigns {
	return CheckSigns{Head: s.HeadRefOid, Rollup: s.Rollup, Contexts: s.Contexts, CheckRuns: counted(s.CheckRuns),
		Statuses: counted(s.Statuses)}
}

func (a CheckSigns) equal(b CheckSigns) bool {
	return a.Head == b.Head && a.Rollup == b.Rollup && a.Contexts == b.Contexts &&
		maps.Equal(counted(a.CheckRuns), counted(b.CheckRuns)) && maps.Equal(counted(a.Statuses), counted(b.Statuses))
}

// counted is the states of m that count one or more, never nil.
func counted(m map[string]int) map[string]int {
	out := map[string]int{}
	for k, v := range m {
		if v > 0 {
			out[k] = v
		}
	}
	return out
}

func labels(s gh.Signs) []string { return listed(slices.Sorted(slices.Values(s.Labels))) }

// moved is the parts of saved that the signs s, read just now, say are stale,
// by the one-PR update's table (specs/tk-1tfzr71.149/design.md, section 4). A
// part whose own signs differ is stale. A move of the comment, review or
// dismissed count makes the PR part stale too, since reviews move its merge
// state, and so does a move of the checks, which are read with it. Every part
// is stale when the saved read lacks a part or stale says it is not current for
// the bead.
func moved(saved *SavedRead, s gh.Signs, stale string) parts {
	if stale != "" || saved == nil || saved.PR == nil || saved.Checks == nil || saved.Conversation == nil ||
		saved.Labels == nil {
		return every
	}
	var p parts
	p.labels = !slices.Equal(saved.Labels.Names, labels(s))
	p.checks = !saved.Checks.Signs.equal(checkSigns(s))
	c := saved.Conversation.Signs
	counts := c.Comments != s.Comments || c.Reviews != s.Reviews || c.Dismissed != s.Dismissed
	p.conversation = counts || c.UpdatedAt != s.UpdatedAt
	p.pr = saved.PR.Signs != prSigns(s) || p.checks || counts
	return p
}

// differs is the parts of saved that the net's read f shows differ from
// GitHub's side of the PR (specs/tk-1tfzr71.149/design.md, section 2), beside
// the signs moved compares: the PR part when the PR's state, draft flag, head,
// base, merge state or either merge-queue flag differs; the checks when they
// were read at another commit than f's, or the check runs the PR requires there
// differ in a name or a result; and the conversation when the review decision,
// the unresolved threads, the newest post time or the reactions the account the
// read runs as left on the inline comments differ. A merge state f reads
// as UNKNOWN differs in nothing, since GitHub reads an open PR's so until it
// has computed one, and a merged PR's for good. A part saved does not hold is
// moved's to read.
func differs(saved *SavedRead, f gh.Full) parts {
	var p parts
	if saved == nil {
		return p
	}
	if s := saved.PR; s != nil {
		p.pr = s.State != f.State || s.Draft != f.IsDraft || s.Head != f.HeadRefOid || s.Base != f.BaseRefName ||
			s.InMergeQueue != f.InMergeQueue || s.MergeQueueEnabled != f.MergeQueueEnabled ||
			(f.MergeStateStatus != "UNKNOWN" && s.MergeState != f.MergeStateStatus)
	}
	if s := saved.Checks; s != nil {
		p.checks = s.Head != f.ChecksAt || !sameRuns(s.Runs, requiredRuns([]gh.CheckSuite{{Runs: f.Checks}}))
	}
	if s := saved.Conversation; s != nil {
		newest := ""
		for _, at := range f.Posts {
			newest = later(newest, at)
		}
		p.conversation = s.ReviewDecision != f.ReviewDecision || s.Signs.NewestPost != newest ||
			!slices.Equal(listed(s.Unresolved), listed(f.Unresolved)) ||
			!slices.Equal(listed(s.Signs.ViewerReactions), listed(f.ViewerReactions))
	}
	return p
}

// sameRuns reports whether a and b hold the same check runs with the same
// results, in whatever order each read listed them: the check suites at a head
// list them by suite, and the check rollup by context.
func sameRuns(a, b []RequiredRun) bool {
	keys := func(runs []RequiredRun) []string {
		out := make([]string, 0, len(runs))
		for _, r := range runs {
			out = append(out, r.Name+"\x00"+r.Status+"\x00"+r.Conclusion)
		}
		slices.Sort(out)
		return out
	}
	return slices.Equal(keys(a), keys(b))
}

// owned is a live bead that owns a PR, as the PR watch reads it: the bead, its
// status and assignee, the PR's URL, host, repository and number, its pending
// record, branch and provenance instant, and the read saved on it, nil when it
// holds none or one that does not decode.
type owned struct {
	id, status, assignee string
	url, host, repo      string
	number               int
	rec                  record.Record
	branch, since        string
	saved                *SavedRead
}

// stale says why the saved read is not current for the bead, and is empty when
// it is: the read the rule takes from it (view) names another PR than the bead
// owns, it applied the definition of feedback from another instant than the
// bead's, or, on a whole pending record, its head is not the head the store
// holds, as the evaluator's currency test (unread) reads each.
func (o owned) stale() string {
	read, why := o.saved.view()
	switch {
	case why != "":
		return why
	case !strings.EqualFold(read.Repository, o.repo) || read.Number != o.number:
		return fmt.Sprintf("the read is of %s#%d", read.Repository, read.Number)
	case read.Since != o.since:
		return fmt.Sprintf("the read applied the definition of feedback from %q, not from the bead's provenance instant %q",
			read.Since, o.since)
	case record.OnRecord(o.rec.Result) && len(recordGaps(o.rec, o.branch)) == 0 && read.Head != storeHead(o.rec):
		return "the read is at head " + read.Head
	}
	return ""
}

// instant is the time a read is sent, RFC 3339 UTC to the millisecond, so two
// reads of one part are ordered by when each was sent.
func instant(now func() time.Time) string {
	if now == nil {
		now = time.Now
	}
	return now().UTC().Format("2006-01-02T15:04:05.000Z")
}

// after reports whether a, an instant a read was sent, is later than b. An
// instant that does not read as one is earlier than any that does.
func after(a, b string) bool {
	ta, errA := time.Parse(time.RFC3339Nano, a)
	tb, errB := time.Parse(time.RFC3339Nano, b)
	switch {
	case errA != nil:
		return false
	case errB != nil:
		return true
	}
	return ta.After(tb)
}

// sameButInstant reports whether a and b, two reads of one part, hold the same
// facts and signs, whatever instant each was read at.
func sameButInstant[T any](a, b *T, instant func(*T) *string) bool {
	if a == nil || b == nil {
		return a == b
	}
	x, y := *a, *b
	*instant(&x), *instant(&y) = "", ""
	return reflect.DeepEqual(x, y)
}

// merge is saved with each part of fresh that was read after the saved part's
// instant. took names the parts whose facts or signs differ from the saved
// ones, and restamped the parts that hold the same ones, of which only the
// instant moves: the instant of the latest read of a part, so an older read
// still in flight, of facts that have moved on since, is never saved after it.
// It changes neither argument.
func merge(saved, fresh *SavedRead) (out *SavedRead, took, restamped parts) {
	out = &SavedRead{}
	if saved != nil {
		*out = *saved
	}
	out.PR, took.pr, restamped.pr = newer(out.PR, fresh.PR, func(p *SavedPR) *string { return &p.ReadAt })
	out.Checks, took.checks, restamped.checks = newer(out.Checks, fresh.Checks,
		func(p *SavedChecks) *string { return &p.ReadAt })
	out.Conversation, took.conversation, restamped.conversation = newer(out.Conversation, fresh.Conversation,
		func(p *SavedConversation) *string { return &p.ReadAt })
	out.Labels, took.labels, restamped.labels = newer(out.Labels, fresh.Labels,
		func(p *SavedLabels) *string { return &p.ReadAt })
	return out, took, restamped
}

// newer is the part merge keeps of saved and fresh, two reads of one part:
// fresh when it was read after saved, saved otherwise. took says fresh holds
// other facts or signs, and restamped that it holds the same ones.
func newer[T any](saved, fresh *T, instant func(*T) *string) (kept *T, took, restamped bool) {
	if fresh == nil || (saved != nil && !after(*instant(fresh), *instant(saved))) {
		return saved, false, false
	}
	if sameButInstant(fresh, saved, instant) {
		return fresh, false, true
	}
	return fresh, true, false
}
