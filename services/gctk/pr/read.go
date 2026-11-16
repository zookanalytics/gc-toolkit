package pr

import (
	"fmt"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
)

// The evaluator's two reads and its one rule (specs/tk-1tfzr71.134/design.md,
// sections 1 and 2). The bead's side is what the store holds about the bead.
// The GitHub read is GitHub's side of the bead's PR at one head, which observe
// makes live, and which the read the one-PR update saves on the bead holds in
// its parts (saved.go). decide is the rule over the two, and reads nothing.
// Ready composes the bead's side, observe and decide for the merge, and
// FromStore composes the bead's side, the saved read and decide for a display,
// so the two list the same conditions in the same order.

// GitHubRead is GitHub's side of a PR at one head, reduced to what the rule
// reads: when it was read, the provenance instant the definition of feedback
// was applied with, the PR's identity, its head, state, draft flag and merge
// state, the required check runs at that head, the accounts whose approval or
// request for changes stands, the newest feedback in each id space and the
// review threads waiting on the city's answer. It holds no answer, no condition
// and no readiness, which the rule derives at each read.
type GitHubRead struct {
	ReadAt     string         `json:"read_at"`
	Since      string         `json:"since"`
	URL        string         `json:"url"`
	Number     int            `json:"number"`
	Repository string         `json:"repository"`
	HeadBranch string         `json:"head_branch"`
	Base       string         `json:"base"`
	Head       string         `json:"head"`
	State      string         `json:"state"`
	Draft      bool           `json:"draft"`
	MergeState string         `json:"merge_state"`
	Checks     []RequiredRun  `json:"checks"`
	Approvers  []string       `json:"approvers"`
	Requesters []string       `json:"requesters"`
	Feedback   NewestFeedback `json:"feedback"`
	Awaiting   []string       `json:"awaiting"`
}

// RequiredRun is one result of a check run the PR requires, at the read's head,
// as a check suite there holds its latest result.
type RequiredRun struct {
	Name       string `json:"name"`
	Status     string `json:"status"`
	Conclusion string `json:"conclusion"`
}

// NewestFeedback is the highest feedback id in each id space, 0 where there is
// none: the reviews the intake counts, the inline comments and the
// conversation comments.
type NewestFeedback struct {
	Review       int64 `json:"review"`
	Inline       int64 `json:"inline"`
	Conversation int64 `json:"conversation"`
}

// githubReadKey is the saved read on the bead that owns the PR. Its one writer
// is the one-PR update (refresh.go).
var githubReadKey = ledger.Declare("pr_github_read", ledger.JSON[*SavedRead](),
	"GitHub's side of a PR as the one-PR update (gctk pr refresh) last read and saved it, one JSON object on "+
		"the bead that owns the PR, in four parts, each with read_at, the instant its read was sent, and "+
		"signs, the cheap signs read no later than its facts. pr: the PR's url, number, repository, "+
		"head_branch and base, its head, state, draft, merge_state, in_merge_queue and merge_queue_enabled, "+
		"with the signs state, draft, head, base, base_tip and updated_at. checks: head and runs, the "+
		"required check runs at that head as {name, status, conclusion}, with the signs head, rollup, "+
		"contexts, check_runs and statuses, the last two counts by state. conversation: since, the "+
		"provenance instant the definition of feedback was applied from; approvers and requesters, the "+
		"accounts that can push whose approval or request for changes stands; feedback, the newest feedback "+
		"id in each id space as {review, inline, conversation}; awaiting, the review threads waiting on the "+
		"city's answer; unresolved, the unresolved threads; and review_decision, with the signs comments, "+
		"reviews, dismissed, updated_at and newest_post, the latest time a post changed. labels: names, every "+
		"label, which are their own signs. The update writes a part only when its read was sent after the "+
		"saved part's and differs from it, and a read that fails saves nothing. It holds no answer. The pr "+
		"evaluator decides over it for a display, as current only while it holds the pr, checks and "+
		"conversation parts, the checks at the PR's head, names the record's repository and number, its head "+
		"is the head the store holds (observed_pr_head_sha on a changed head, pr_head_sha otherwise) and its "+
		"since is the bead's pr_provenance_since. Absent or not current, GitHub's side of the PR reads as "+
		"unread.",
	ledger.Warrant("saved-github-read"))

// FromStore answers what Ready answers for the bead's PR, over the read the
// one-PR update saved on the bead in place of a live one: it reads the bead's
// side through l and decides. It reads no GitHub and loads no definition of
// feedback, so it is a display's question. A read of the store that fails, or
// a saved read that does not decode, returns its error and no answer.
func FromStore(l *ledger.Ledger, bead string) (Answer, error) {
	b, r, err := readSide(l.Pass(), bead)
	if err != nil {
		return Answer{}, err
	}
	saved, _, err := githubReadKey.Get(r)
	if err != nil {
		return Answer{}, err
	}
	read, why := saved.view()
	return decideOver(b, read, why), nil
}

// side is the bead's side of a read: what the store holds about the bead. The
// store's conditions are its holds set by hand, its own waits and the beads
// anchored to it. missing is what its record lacks to name its PR, and host and
// number name the PR once it lacks nothing.
type side struct {
	bead    string
	rec     record.Record
	branch  string
	holds   []string
	rc      receipts
	since   string
	results []review.Result
	missing []string
	waits   []Condition
	host    string
	number  int
}

// readSide reads the bead's side through l, a pass, and returns the bead's row
// with it. A read that fails, or a value that does not decode, returns its
// error.
func readSide(l *ledger.Ledger, bead string) (side, *ledger.Record, error) {
	rows, err := l.Find(ledger.ByID(bead).WithClosed())
	if err != nil {
		return side{}, nil, err
	}
	if len(rows) == 0 {
		return side{}, nil, &ledger.ReadError{ID: bead, Reason: "the store holds no such bead"}
	}
	r := rows[0]
	read := func(k reading) string {
		v, _, e := k.Get(r)
		if e != nil && err == nil {
			err = e
		}
		return strings.TrimSpace(v)
	}
	rec, serr := record.Read(r)
	if err == nil {
		err = serr
	}
	b := side{bead: bead, rec: rec, branch: read(record.Branch),
		holds: []string{read(mergeHoldKey), read(rebaseHoldKey)},
		rc: receipts{
			review: mark(read(reviewWatermarkKey)), comment: mark(read(commentWatermarkKey)),
			issueComment:   mark(read(issueCommentWatermarkKey)),
			reviewAnswered: mark(read(reviewAnsweredKey)), commentAnswered: mark(read(commentAnsweredKey)),
		},
		since: read(provenanceKey),
	}
	results, _, rerr := review.Results.Get(r)
	if err == nil {
		err = rerr
	}
	if err != nil {
		return side{}, nil, err
	}
	b.results = results

	// The record names the PR the rest is read about.
	b.missing = recordGaps(rec, b.branch)
	if !OnRecord(rec.Result) {
		b.missing = append([]string{fmt.Sprintf("a pending merge_result (it reads %q)", rec.Result)}, b.missing...)
	}
	if len(b.missing) == 0 {
		b.host, _, b.number, _ = record.ParseURL(rec.URL)
	}
	waitConds, err := ownWaits(l, bead)
	if err != nil {
		return side{}, nil, err
	}
	anchored, err := anchoredTo(l, bead)
	if err != nil {
		return side{}, nil, err
	}
	b.waits = append(waitConds, anchored...)
	return b, r, nil
}

// head is the head the store holds for the PR (storeHead).
func (b side) head() string { return storeHead(b.rec) }

// storeHead is the head the store holds for a record's PR: the one the landing
// order found when the record reads a changed head, and the one the refinery
// validated otherwise.
func storeHead(rec record.Record) string {
	if rec.Result == record.HeadChanged {
		return rec.Observed
	}
	return rec.Head
}

// unread says why read is not GitHub's side of the bead's PR at the head the
// store holds, and is empty when it is: it names the repository, compared
// without case, and the number the record names, its head is the store's, and
// it applied the definition of feedback from the bead's provenance instant. A
// read made before that instant was stamped, or before the refinery published
// the head, is older than the facts the bead holds.
func (b side) unread(read *GitHubRead) string {
	switch {
	case read == nil:
		return "no read of GitHub is saved on the bead"
	case !strings.EqualFold(read.Repository, b.rec.Repo) || read.Number != b.number:
		return fmt.Sprintf("the read is of %s#%d", read.Repository, read.Number)
	case read.Head != b.head():
		return "the read is at head " + read.Head
	case read.Since != b.since:
		return fmt.Sprintf("the read applied the definition of feedback from %q, not from the bead's provenance instant %q",
			read.Since, b.since)
	}
	return ""
}

// observe reads GitHub's side of the PR numbered number in repo live, through
// hub and the definition of feedback applied from since, and stamps it at at.
// Its reads are the evaluator's, in their order: the PR, the check suites at its
// head, its reviews, the login the city's account acts as, its review threads
// and its conversation comments. The definition of feedback reads the text of
// every post, which the read does not keep, so it runs here, and the read keeps
// what it found: the newest feedback in each id space and the threads waiting
// on the city's answer. The approval rule reads GitHub's reviews alone, and the
// read keeps the accounts it finds. A read that fails returns its error and no
// read, so no part of GitHub's side stands for the whole.
func observe(hub GitHub, rule Feedback, repo string, number int, since, at string) (*GitHubRead, error) {
	p, err := hub.PullRequest(repo, number)
	if err != nil {
		return nil, err
	}
	suites, err := hub.CheckSuites(repo, p.HeadRefOid, number)
	if err != nil {
		return nil, err
	}
	reviews, err := hub.Reviews(repo, number)
	if err != nil {
		return nil, err
	}
	self, err := hub.Login()
	if err != nil {
		return nil, err
	}
	threads, err := hub.ReviewThreads(repo, number)
	if err != nil {
		return nil, err
	}
	comments, err := hub.IssueComments(repo, number)
	if err != nil {
		return nil, err
	}
	fresh, err := newestFeedback(rule, self, since, reviews, threads, comments)
	if err != nil {
		return nil, err
	}
	waiting, err := awaiting(rule, self, since, threads)
	if err != nil {
		return nil, err
	}
	approvers, requesters := approval(reviews)
	return &GitHubRead{
		ReadAt: at, Since: since,
		URL: p.URL, Number: p.Number, Repository: p.Repository, HeadBranch: p.HeadRefName, Base: p.BaseRefName,
		Head: p.HeadRefOid, State: p.State, Draft: p.IsDraft, MergeState: p.MergeStateStatus,
		Checks: requiredRuns(suites), Approvers: listed(approvers), Requesters: listed(requesters),
		Feedback: fresh, Awaiting: listed(waiting),
	}, nil
}

// requiredRuns is each result the check suites hold of a check run the PR
// requires, suite by suite, in the order GitHub lists them.
func requiredRuns(suites []gh.CheckSuite) []RequiredRun {
	out := []RequiredRun{}
	for _, s := range suites {
		for _, r := range s.Runs {
			if r.Required {
				out = append(out, RequiredRun{Name: r.Name, Status: r.Status, Conclusion: r.Conclusion})
			}
		}
	}
	return out
}

// listed is l, or an empty list for none, so a saved read names an empty set as
// one.
func listed(l []string) []string {
	if l == nil {
		return []string{}
	}
	return l
}

// decide is the evaluator's rule over the bead's side and a GitHub read, and
// reads nothing. A bead whose record lacks a part gets the store's conditions
// alone, the record's gap first. A read that is absent, or not of the PR at the
// head the store holds (unread), gets one condition in place of every condition
// of GitHub's, ahead of the store's, and judges no head. Otherwise GitHub's
// conditions come first: the PR's identity, state, draft flag, head and merge
// state, its required checks, its approval and the review loop's result, then
// the store's, then the feedback the receipts do not cover and the review
// threads waiting on the city's answer. An answer that judged a head carries
// the review loop's result there, passed or not, when one stands.
func decide(b side, read *GitHubRead) Answer { return decideOver(b, read, "") }

// decideOver is decide over a read that why, when it is not empty, says is no
// read of the PR at one head.
func decideOver(b side, read *GitHubRead, why string) Answer {
	ans := Answer{Bead: b.bead, Conditions: []Condition{}}
	var store []Condition
	if len(b.missing) > 0 {
		store = append(store, Condition{Kind: KindRecord,
			Detail: "the bead's pending record is incomplete: it lacks " + strings.Join(b.missing, ", ")})
	}
	for i, name := range []string{"merge hold", "rebase hold"} {
		if isSet(b.holds[i]) {
			store = append(store, Condition{Kind: KindHold,
				Detail: fmt.Sprintf("a %s is set on the bead (%s)", name, b.holds[i])})
		}
	}
	store = append(store, b.waits...)
	if len(b.missing) > 0 {
		ans.Conditions = append(ans.Conditions, store...)
		return ans
	}
	if why == "" {
		why = b.unread(read)
	}
	if why != "" {
		ans.Conditions = append(ans.Conditions, Condition{Kind: KindGitHubUnread,
			Detail: fmt.Sprintf("GitHub's side of the PR is not read at the head the store holds, %s: %s", b.head(), why)})
		ans.Conditions = append(ans.Conditions, store...)
		return ans
	}

	ans.Head, ans.Target = read.Head, read.Base
	ans.ReviewResult = resultAt(b.results, read.Head, read.Base)
	// Empty rather than nil, so a ready answer's conditions encode as [].
	front := []Condition{}
	named := &gh.PullRequest{URL: read.URL, Number: read.Number, Repository: read.Repository,
		HeadRefName: read.HeadBranch, BaseRefName: read.Base}
	if ids := identityGaps(named, b.rec.URL, b.number, b.rec.Repo, b.branch, b.rec.Target); len(ids) > 0 {
		front = append(front, Condition{Kind: KindRecord,
			Detail: "the PR on GitHub is not the one the record names: " + strings.Join(ids, ", ")})
	}
	if read.State != "OPEN" {
		front = append(front, Condition{Kind: KindOpen, Detail: "the PR is " + strings.ToLower(read.State)})
	}
	if read.Draft {
		front = append(front, Condition{Kind: KindDraft, Detail: "the PR is a draft"})
	}
	if read.Head != b.rec.Head {
		front = append(front, Condition{Kind: KindHead,
			Detail: fmt.Sprintf("the PR's head %s is not the head the refinery validated, %s", read.Head, b.rec.Head)})
	}
	// GitHub reads a failing or pending required check as BLOCKED, so UNSTABLE
	// leaves only checks the base does not require, which hold no merge, as the
	// old merge pass also proceeds on it.
	if read.MergeState != "CLEAN" && read.MergeState != "UNSTABLE" {
		front = append(front, Condition{Kind: KindMergeState, Value: read.MergeState,
			Detail: fmt.Sprintf("GitHub reports the PR's merge state %s, not CLEAN or UNSTABLE", read.MergeState)})
	}
	front = append(front, checks(read.Checks)...)
	if len(read.Approvers) == 0 {
		front = append(front, Condition{Kind: KindApproval,
			Detail: "no approval stands from an account that can push to the repository"})
	}
	for _, login := range read.Requesters {
		front = append(front, Condition{Kind: KindChangesRequested, Value: login,
			Detail: login + " requests changes, and the request stands"})
	}
	if r := ans.ReviewResult; r == nil || !r.Passed {
		front = append(front, Condition{Kind: KindReview,
			Detail: fmt.Sprintf("no review result passed at head %s into %s", read.Head, read.Base)})
	}

	ans.Conditions = append(front, store...)
	ans.Conditions = append(ans.Conditions, unhandled(b.rc, read.Feedback)...)
	for _, id := range read.Awaiting {
		ans.Conditions = append(ans.Conditions, Condition{Kind: KindThread, Value: id,
			Detail: fmt.Sprintf("review thread %s waits on the city's answer", id)})
	}
	ans.Ready = len(ans.Conditions) == 0
	return ans
}

// stamp is the time a read or a write records, RFC 3339 UTC to the second, the
// form whose order is its text's order, by now, or by the system's clock when
// now is nil.
func stamp(now func() time.Time) string {
	if now == nil {
		now = time.Now
	}
	return now().UTC().Format("2006-01-02T15:04:05Z")
}
