// Package pr is gctk's pr domain: the pull request a bead owns
// (docs/gctk-architecture.md). Its evaluator, [Ready], is the one definition of
// whether a PR is ready to merge at its current revision, which the landing
// order acts on and prstatus renders for the status label and the board. It
// answers ready, with the head and the target it judged, or the conditions not
// met, and it is computed at each read and stored nowhere, so no answer stands
// as a permission on a commit another PR shares.
//
// It reads the bead's own waits through waits, the open beads whose anchor_bead
// names the bead, the holds set by hand, the review loop's results for the PR's
// live head and target, GitHub's live facts about the PR, and the receipts of
// the feedback the intake has handled. A read that fails returns an error and no
// answer, since a decision made on part of the facts is a decision about
// another PR.
package pr

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// Kind names a condition the evaluator found not met.
type Kind string

const (
	// KindRecord: the bead carries no complete pending record, or the PR
	// GitHub reports is not the one the record names by its URL, number,
	// repository, head branch or base.
	KindRecord Kind = "record"
	// KindOpen: the PR is not open.
	KindOpen Kind = "open"
	// KindDraft: the PR is a draft.
	KindDraft Kind = "draft"
	// KindHead: the PR's head is not the head the refinery validated.
	KindHead Kind = "head"
	// KindMergeState: GitHub reports a merge state other than CLEAN, which a
	// conflict, a check that is not passing or any rule of the target holds
	// back.
	KindMergeState Kind = "merge-state"
	// KindCheckFailed: a required check has a result at the head that did not
	// pass.
	KindCheckFailed Kind = "check-failed"
	// KindCheckPending: a required check has no result at the head that ran, or
	// one still running, so it waits for a run.
	KindCheckPending Kind = "check-pending"
	// KindApproval: no approval stands from an account that can push to the
	// repository.
	KindApproval Kind = "approval"
	// KindChangesRequested: a request for changes stands from an account that
	// can push to the repository.
	KindChangesRequested Kind = "changes-requested"
	// KindReview: no review result passed at the PR's live head and target.
	KindReview Kind = "review"
	// KindHold: a merge or rebase hold set by hand.
	KindHold Kind = "hold"
	// KindWait: a wait of the bead's own, such as work on the PR's branch, a
	// human gate or a conversation's gate. ID names the bead waited on.
	KindWait Kind = "wait"
	// KindInFlight: an open bead names the bead as its anchor. ID names it.
	KindInFlight Kind = "in-flight"
	// KindFeedback: a review or comment the intake counts is newer than the
	// receipts of the feedback it has handled.
	KindFeedback Kind = "feedback"
	// KindThread: a review thread waits on the city's answer.
	KindThread Kind = "thread"
)

// Condition is one condition not met: its kind, the sentence that names it,
// the bead it is when it is one, and the value it turns on when GitHub names
// one: the merge state, the check's name, the account or the review thread.
type Condition struct {
	Kind   Kind   `json:"kind"`
	Detail string `json:"detail"`
	ID     string `json:"id,omitempty"`
	Value  string `json:"value,omitempty"`
}

// Answer is the evaluator's answer for one bead's PR. Ready says the PR may
// merge at Head into Target, the head and the base it judged. Otherwise
// Conditions names each condition not met, and Head and Target name what it
// read of GitHub, when it read the PR.
type Answer struct {
	Bead       string      `json:"bead"`
	Ready      bool        `json:"ready"`
	Head       string      `json:"head,omitempty"`
	Target     string      `json:"target,omitempty"`
	Conditions []Condition `json:"conditions"`
}

// ReviewResult is one result of the review loop: the head and the target it
// judged, and whether the review passed there.
type ReviewResult struct {
	Head   string `json:"head"`
	Target string `json:"target"`
	Passed bool   `json:"passed"`
}

// GitHub is the reads the evaluator makes of GitHub, which the gh
// adapter's Client carries out and its fake answers.
type GitHub interface {
	PullRequest(repo string, number int) (*gh.PullRequest, error)
	Reviews(repo string, number int) ([]gh.Review, error)
	CheckSuites(repo, oid string, number int) ([]gh.CheckSuite, error)
	ReviewThreads(repo string, number int) ([]gh.Thread, error)
	IssueComments(repo string, number int) ([]gh.IssueComment, error)
	Login() (string, error)
}

// Sources are where the evaluator reads: the store, through the ledger;
// GitHub, through the reads GitHub returns for the host a PR's URL names; and
// the pack's definition of feedback, loaded in the rig's checkout.
type Sources struct {
	Ledger   *ledger.Ledger
	GitHub   func(host string) GitHub
	Feedback Feedback
}

// The record's values that name a PR open on the record: the head the refinery
// validated, and a head it has not.
const (
	pending     = "pull_request_pending"
	headChanged = "pull_request_head_changed"
)

// OnRecord reports whether a bead whose merge_result is v owns a PR on Gas
// Town's pending record, the PRs the evaluator answers for.
func OnRecord(v string) bool { return v == pending || v == headChanged }

// prURL is a PR's URL: https, its host, its repository and its number.
var prURL = regexp.MustCompile(`^https://([^/]+)/([^/]+/[^/]+)/pull/([0-9]+)$`)

// Ready answers whether the PR the bead owns is ready to merge at its current
// revision. A read that fails returns its error and no answer. A bead with no
// complete pending record is not ready, and its answer says what the record
// lacks without reading GitHub.
func Ready(src Sources, bead string) (Answer, error) {
	l := src.Ledger.Pass()
	ans := Answer{Bead: bead, Conditions: []Condition{}}
	rows, err := l.Find(ledger.ByID(bead).WithClosed())
	if err != nil {
		return Answer{}, err
	}
	if len(rows) == 0 {
		return Answer{}, &ledger.ReadError{ID: bead, Reason: "the store holds no such bead"}
	}
	r := rows[0]
	read := func(k ledger.Key[string]) string {
		v, _, e := k.Get(r)
		if e != nil && err == nil {
			err = e
		}
		return strings.TrimSpace(v)
	}
	rec := struct{ result, url, number, repo, head, target, branch string }{
		read(mergeResultKey), read(prURLKey), read(prNumberKey), read(prRepoKey),
		read(prHeadKey), read(mergedTargetKey), read(branchKey),
	}
	holds := []string{read(mergeHoldKey), read(rebaseHoldKey)}
	rc := receipts{
		review: mark(read(reviewWatermarkKey)), comment: mark(read(commentWatermarkKey)),
		issueComment:   mark(read(issueCommentWatermarkKey)),
		reviewAnswered: mark(read(reviewAnsweredKey)), commentAnswered: mark(read(commentAnsweredKey)),
	}
	since := read(provenanceKey)
	results, _, rerr := reviewResultsKey.Get(r)
	if err == nil {
		err = rerr
	}
	if err != nil {
		return Answer{}, err
	}

	// The record names the PR the rest is read about.
	host, number, missing := "", 0, recordGaps(rec.result, rec.url, rec.number, rec.repo, rec.head, rec.target, rec.branch)
	if m := prURL.FindStringSubmatch(rec.url); m != nil && len(missing) == 0 {
		host = m[1]
		number, _ = strconv.Atoi(rec.number)
		if !strings.EqualFold(m[2], rec.repo) || m[3] != rec.number {
			missing = append(missing, "a URL that names its repository and number")
		}
	}
	if len(missing) > 0 {
		ans.Conditions = append(ans.Conditions, Condition{Kind: KindRecord,
			Detail: "the bead's pending record is incomplete: it lacks " + strings.Join(missing, ", ")})
	}

	// The bead's side: its holds, its own waits and the beads anchored to it.
	for i, name := range []string{"merge hold", "rebase hold"} {
		if isSet(holds[i]) {
			ans.Conditions = append(ans.Conditions, Condition{Kind: KindHold,
				Detail: fmt.Sprintf("a %s is set on the bead (%s)", name, holds[i])})
		}
	}
	waitConds, err := ownWaits(l, bead)
	if err != nil {
		return Answer{}, err
	}
	ans.Conditions = append(ans.Conditions, waitConds...)
	anchored, err := anchoredTo(l, bead)
	if err != nil {
		return Answer{}, err
	}
	ans.Conditions = append(ans.Conditions, anchored...)
	if len(missing) > 0 {
		return ans, nil
	}

	// GitHub's side, read fresh.
	hub := src.GitHub(host)
	p, err := hub.PullRequest(rec.repo, number)
	if err != nil {
		return Answer{}, err
	}
	ans.Head, ans.Target = p.HeadRefOid, p.BaseRefName
	var front []Condition
	if ids := identityGaps(p, rec.url, number, rec.repo, rec.branch, rec.target); len(ids) > 0 {
		front = append(front, Condition{Kind: KindRecord,
			Detail: "the PR on GitHub is not the one the record names: " + strings.Join(ids, ", ")})
	}
	if p.State != "OPEN" {
		front = append(front, Condition{Kind: KindOpen, Detail: "the PR is " + strings.ToLower(p.State)})
	}
	if p.IsDraft {
		front = append(front, Condition{Kind: KindDraft, Detail: "the PR is a draft"})
	}
	if p.HeadRefOid != rec.head {
		front = append(front, Condition{Kind: KindHead,
			Detail: fmt.Sprintf("the PR's head %s is not the head the refinery validated, %s", p.HeadRefOid, rec.head)})
	}
	if p.MergeStateStatus != "CLEAN" {
		front = append(front, Condition{Kind: KindMergeState, Value: p.MergeStateStatus,
			Detail: fmt.Sprintf("GitHub reports the PR's merge state %s, not CLEAN", p.MergeStateStatus)})
	}
	suites, err := hub.CheckSuites(rec.repo, p.HeadRefOid, number)
	if err != nil {
		return Answer{}, err
	}
	front = append(front, checks(suites)...)
	reviews, err := hub.Reviews(rec.repo, number)
	if err != nil {
		return Answer{}, err
	}
	approvers, requesters := approval(reviews)
	if len(approvers) == 0 {
		front = append(front, Condition{Kind: KindApproval,
			Detail: "no approval stands from an account that can push to the repository"})
	}
	for _, login := range requesters {
		front = append(front, Condition{Kind: KindChangesRequested, Value: login,
			Detail: login + " requests changes, and the request stands"})
	}
	if !passedAt(results, p.HeadRefOid, p.BaseRefName) {
		front = append(front, Condition{Kind: KindReview,
			Detail: fmt.Sprintf("no review result passed at head %s into %s", p.HeadRefOid, p.BaseRefName)})
	}

	// The feedback the intake has handled, read against its receipts.
	self, err := hub.Login()
	if err != nil {
		return Answer{}, err
	}
	threads, err := hub.ReviewThreads(rec.repo, number)
	if err != nil {
		return Answer{}, err
	}
	comments, err := hub.IssueComments(rec.repo, number)
	if err != nil {
		return Answer{}, err
	}
	fresh, err := unhandled(src.Feedback, self, since, rc, reviews, threads, comments)
	if err != nil {
		return Answer{}, err
	}
	waiting, err := awaiting(src.Feedback, self, since, threads)
	if err != nil {
		return Answer{}, err
	}
	ans.Conditions = append(front, ans.Conditions...)
	ans.Conditions = append(ans.Conditions, fresh...)
	ans.Conditions = append(ans.Conditions, waiting...)
	ans.Ready = len(ans.Conditions) == 0
	return ans, nil
}

// recordGaps names what a pending record lacks.
func recordGaps(result, url, number, repo, head, target, branch string) []string {
	var gaps []string
	if !OnRecord(result) {
		gaps = append(gaps, fmt.Sprintf("a pending merge_result (it reads %q)", result))
	}
	if !prURL.MatchString(url) {
		gaps = append(gaps, "a PR URL")
	}
	if n, err := strconv.Atoi(number); err != nil || n < 1 {
		gaps = append(gaps, "a PR number")
	}
	if repo == "" {
		gaps = append(gaps, "a repository")
	}
	if head == "" {
		gaps = append(gaps, "the head the refinery validated")
	}
	if target == "" {
		gaps = append(gaps, "a target")
	}
	if branch == "" {
		gaps = append(gaps, "a branch")
	}
	return gaps
}

// identityGaps names where the PR GitHub reports differs from the one the
// record names, as Gas Town's reconcile compares them: the URL, the number, the
// repository without case, the head branch and the base.
func identityGaps(p *gh.PullRequest, rawURL string, number int, repo, branch, target string) []string {
	var gaps []string
	if p.URL != rawURL {
		gaps = append(gaps, fmt.Sprintf("its URL is %s", p.URL))
	}
	if p.Number != number {
		gaps = append(gaps, fmt.Sprintf("its number is %d", p.Number))
	}
	if !strings.EqualFold(p.Repository, repo) {
		gaps = append(gaps, fmt.Sprintf("its repository is %s", p.Repository))
	}
	if p.HeadRefName != branch {
		gaps = append(gaps, fmt.Sprintf("its head branch is %s, not %s", p.HeadRefName, branch))
	}
	if p.BaseRefName != target {
		gaps = append(gaps, fmt.Sprintf("its base is %s, not %s", p.BaseRefName, target))
	}
	return gaps
}

// passedAt reports whether a review result passed at head into target. A result
// for another head or another target counts for nothing.
func passedAt(results []ReviewResult, head, target string) bool {
	for _, r := range results {
		if r.Head == head && r.Target == target && r.Passed {
			return true
		}
	}
	return false
}

// ownWaits is one condition for each wait of the bead's own, through waits,
// the answer `gctk bead holds` gives: work on the PR's branch, a human gate, a
// conversation's gate, or work that must land first. The blocked status the
// record writes is no wait.
func ownWaits(l *ledger.Ledger, bead string) ([]Condition, error) {
	snap, err := waits.Read(l, bead)
	if err != nil {
		return nil, err
	}
	h, err := snap.Holds(bead)
	if err != nil {
		return nil, err
	}
	if h.Status == waits.Clear {
		return nil, nil
	}
	var out []Condition
	for _, w := range h.Waits {
		out = append(out, Condition{Kind: KindWait, ID: w.ID,
			Detail: fmt.Sprintf("the bead waits on %s (%s, %s): %s", w.ID, w.Type, w.Status, w.Title)})
	}
	if len(out) == 0 {
		out = append(out, Condition{Kind: KindWait,
			Detail: fmt.Sprintf("the store reads the bead %s with no wait named", h.Status)})
	}
	return out, nil
}

// anchoredTo is one condition for each open bead whose anchor_bead names the
// bead, the work on a PR's branch that its writers file with no blocks edge
// yet. This is the one place the evaluator reads that link, and it goes once no
// writer files such work without the edge.
func anchoredTo(l *ledger.Ledger, bead string) ([]Condition, error) {
	rows, err := l.Find(ledger.Matching(anchorKey, bead))
	if err != nil {
		return nil, err
	}
	var out []Condition
	for _, r := range rows {
		if r.ID == bead {
			continue
		}
		out = append(out, Condition{Kind: KindInFlight, ID: r.ID,
			Detail: fmt.Sprintf("%s (%s) names the bead as its anchor: %s", r.ID, r.Status(), r.Title())})
	}
	return out, nil
}

// isSet is the truthiness rule the holds are read by: null and false arrive
// empty, and the string spellings of an unset flag are unset too.
func isSet(v string) bool {
	switch v {
	case "", "false", "False", "FALSE", "0", "null":
		return false
	}
	return true
}
