// Package pr is gctk's pr domain: the pull request a bead owns
// (docs/gctk-architecture.md). Its evaluator is the one definition of whether a
// PR is ready to merge at its current revision: one rule over the bead's side,
// read from the store, and GitHub's side of the PR at one head, as the read the
// one-PR update ([Watcher.Refresh]) saved on the bead holds it. [FromStore]
// decides over that read and reads no GitHub: the displays read its answer, and
// the landing order acts on it, deciding a merge on the read the update saves
// once it has re-read the PR in full ([Watcher.Reread]). It answers ready, with
// the head and the target it judged, or the conditions not met, which prstatus
// renders as the PR's status. The answer is computed at each read and stored
// nowhere, so no answer stands as a permission on a commit another PR shares,
// and what the update saves is GitHub's facts, which grant nothing.
//
// The bead's side is its pending record and branch, the holds set by hand, its
// own waits through waits, the open beads whose anchor_bead names it, the
// review loop's results, the receipts of the feedback the intake has handled
// and the provenance instant the definition of feedback is applied from. A read
// that fails returns an error and no answer, since a decision made on part of
// the facts is a decision about another PR.
//
// Its composition, [Compose], is what the PR says of the bead. Gas Town's
// refinery opens a PR with its bead's title and writes the body once. A
// composition gives the title the conventional-commit type a repository's title
// check requires, and keeps two marked sections of the body current while it
// leaves the text people add: the managed summary region, which says what the
// change does and how it reached the refinery, and the branch-beads section,
// which names every bead whose work the branch carries.
package pr

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// Kind names a condition the evaluator found not met.
type Kind string

const (
	// KindRecord: the bead carries no complete pending record, or the PR
	// GitHub reports is not the one the record names by its URL, number,
	// repository, head branch or base.
	KindRecord Kind = "record"
	// KindGitHubUnread: GitHub's side of the PR is not read at the head the
	// store holds for it: no read is saved on the bead, or the read names
	// another PR, another head or another provenance instant. It stands in
	// place of every condition of GitHub's.
	KindGitHubUnread Kind = "github-unread"
	// KindOpen: the PR is not open.
	KindOpen Kind = "open"
	// KindDraft: the PR is a draft.
	KindDraft Kind = "draft"
	// KindHead: the PR's head is not the head the refinery validated.
	KindHead Kind = "head"
	// KindMergeState: GitHub reports a merge state other than CLEAN or
	// UNSTABLE, which a conflict, a branch behind a base that requires it
	// current, a required commit status or any other rule of the target holds
	// back. UNSTABLE says only that a check the base does not require is not
	// passing, and the required check runs are the evaluator's own read
	// (KindCheckFailed, KindCheckPending).
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
	// KindAssigned: the bead is assigned to someone, who works it now, such as
	// the refinery validating a head. Value names the assignee.
	KindAssigned Kind = "assigned"
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
// Conditions names each condition not met, and Head and Target name the head
// and the base of the GitHub read it judged, empty when it judged none, for a
// record that lacks a part or a side of GitHub's that is unread. ReviewResult
// is the review loop's result for the head and the base it judged, passed or
// not, and nil when none stands there or it judged no head.
type Answer struct {
	Bead         string         `json:"bead"`
	Ready        bool           `json:"ready"`
	Head         string         `json:"head,omitempty"`
	Target       string         `json:"target,omitempty"`
	Conditions   []Condition    `json:"conditions"`
	ReviewResult *review.Result `json:"review_result,omitempty"`
}

// GitHub is the reads of GitHub an act makes of what it changes, which the gh
// adapter's Client carries out and its fake answers: the PR a return to draft
// reads, and the reviews, review threads and login a withdrawal reads before
// it dismisses an approval.
type GitHub interface {
	PullRequest(repo string, number int) (*gh.PullRequest, error)
	Reviews(repo string, number int) ([]gh.Review, error)
	ReviewThreads(repo string, number int) ([]gh.Thread, error)
	Login() (string, error)
}

// OnRecord reports whether a bead whose merge_result is v owns a PR on Gas
// Town's pending record, the PRs the evaluator answers for.
func OnRecord(v string) bool { return record.OnRecord(v) }

// recordGaps names what a pending record lacks to name its PR, the one reading
// of a whole record that the evaluator and the landing order share: a PR URL,
// read through record.ParseURL, that names the repository and the number the
// record names, the number, the repository, the head the refinery validated as
// a full commit id, the target and the branch. Whether its merge_result reads
// pending is each reader's own question.
func recordGaps(r record.Record, branch string) []string {
	var gaps []string
	_, repo, number, urlOK := record.ParseURL(r.URL)
	if !urlOK {
		gaps = append(gaps, "a PR URL")
	}
	if n, err := strconv.Atoi(r.Number); err != nil || n < 1 {
		gaps = append(gaps, "a PR number")
	}
	if r.Repo == "" {
		gaps = append(gaps, "a repository")
	}
	if r.Head == "" {
		gaps = append(gaps, "the head the refinery validated")
	}
	if r.Target == "" {
		gaps = append(gaps, "a target")
	}
	if branch == "" {
		gaps = append(gaps, "a branch")
	}
	if len(gaps) == 0 && (!strings.EqualFold(repo, r.Repo) || strconv.Itoa(number) != r.Number) {
		gaps = append(gaps, "a URL that names its repository and number")
	}
	if r.Head != "" && !record.IsObjectID(r.Head) {
		gaps = append(gaps, "a validated head that is a full commit id")
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

// resultAt is the review loop's result for head into target, the one entry the
// loop's check keeps for that head and target, and nil when none stands. A
// result for another head or another target counts for nothing.
func resultAt(results []review.Result, head, target string) *review.Result {
	for _, r := range results {
		if r.Head == head && r.Target == target {
			return &r
		}
	}
	return nil
}

// passedAt reports whether the review loop's result for head into target
// passed.
func passedAt(results []review.Result, head, target string) bool {
	r := resultAt(results, head, target)
	return r != nil && r.Passed
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
