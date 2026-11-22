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
// The GitHub read is GitHub's side of the bead's PR at one head, which the read
// the one-PR update saves on the bead holds in its parts (saved.go). decideOver
// is the rule over the two, and reads nothing. FromStore composes the bead's
// side, the saved read and the rule, for a display and for the landing order
// alike, so each lists the same conditions in the same order.

// GitHubRead is GitHub's side of a PR at one head, reduced to what the rule
// reads: when it was read, the provenance instant the definition of feedback
// was applied with, the PR's identity, its head, state, draft flag and merge
// state, the required check runs at that head, the accounts whose approval or
// request for changes stands, the posts that are feedback the city has not
// taken and the review threads waiting on the city's answer. It holds no
// answer, no condition and no readiness, which the rule derives at each read.
type GitHubRead struct {
	ReadAt     string        `json:"read_at"`
	Since      string        `json:"since"`
	URL        string        `json:"url"`
	Number     int           `json:"number"`
	Repository string        `json:"repository"`
	HeadBranch string        `json:"head_branch"`
	Base       string        `json:"base"`
	Head       string        `json:"head"`
	State      string        `json:"state"`
	Draft      bool          `json:"draft"`
	MergeState string        `json:"merge_state"`
	Checks     []RequiredRun `json:"checks"`
	Approvers  []string      `json:"approvers"`
	Requesters []string      `json:"requesters"`
	Untaken    []Post        `json:"untaken"`
	Awaiting   []string      `json:"awaiting"`
}

// RequiredRun is one result of a check run the PR requires, at the read's head,
// as a check suite there holds its latest result: the suite that holds it, by
// its id, and where its log is read, empty when GitHub names nowhere.
type RequiredRun struct {
	Name       string `json:"name"`
	Status     string `json:"status"`
	Conclusion string `json:"conclusion"`
	Suite      int64  `json:"suite,omitempty"`
	URL        string `json:"url,omitempty"`
}

// githubReadKey is the saved read on the bead that owns the PR. Its one writer
// is the one-PR update (refresh.go).
var githubReadKey = ledger.Declare("pr_github_read", ledger.JSON[*SavedRead](),
	"GitHub's side of a PR as the one-PR update (gctk pr refresh) last read and saved it, one JSON object on "+
		"the bead that owns the PR, in four parts, each with read_at, the instant its read was sent, and, but "+
		"for labels, signs, the cheap signs read no later than its facts. pr: the PR's id, its node id on "+
		"GitHub, its url, number, repository, head_branch and base, its head, state, draft, merge_state, "+
		"in_merge_queue and merge_queue_enabled, and merge_commit and merged_at once it merged, with the signs "+
		"state, draft, head, base, base_tip and updated_at. checks: head; runs, the required check runs at "+
		"that head as {name, status, conclusion, suite, url}, suite the id of the check suite that holds the "+
		"result and url its log; and suites, each check suite at that head as {id, status, created_at, run, "+
		"attempt, check_runs}, run the GitHub Actions run behind it and attempt that run's attempt, both 0 "+
		"for a suite no Actions run is behind, and check_runs how many check runs it holds; with the signs "+
		"head, rollup, contexts, check_runs and statuses, the last two counts by state. A checks part that "+
		"holds no suites is read again. conversation: since, the provenance instant the definition "+
		"of feedback was applied from; approvers and requesters, the accounts that can push whose approval or "+
		"request for changes stands; untaken, each post that is feedback and carries neither of the city's "+
		"marks, its EYES or its THUMBS_UP, as {kind, id, node, author, url, state, path, line, review}: kind "+
		"review, inline or conversation, node its node id on GitHub, state a review's, path and line an inline "+
		"comment's file and the line it was made on, and review the review that carried it; awaiting, the "+
		"review threads waiting on the city's answer; unresolved, the unresolved threads; review_decision; and "+
		"approvals, each review that approves and has not been dismissed, whoever gave it, as {id, author, "+
		"commit}, with the signs comments, reviews, dismissed, updated_at, newest_post, the latest time a "+
		"post changed, and viewer_reactions, each reaction the account the read runs as left on an inline "+
		"comment, as the comment's id and the reaction, which the definition of feedback reads as an answer "+
		"to the comment's thread, absent when there is none. labels: names, every label, which are their own signs. The update writes a part only "+
		"when its read was sent after the saved part's: the whole part when it differs, and its read_at alone "+
		"when it holds the same, so a read sent before it is never saved after it. A read that fails saves "+
		"nothing. It holds no answer. The pr evaluator decides over it for a display, the PR's status: and "+
		"held: labels among them, as current only while it holds the pr, checks and conversation parts, the "+
		"checks at the PR's head, names the record's repository and number, its head is the head the store "+
		"holds (observed_pr_head_sha on a changed head, pr_head_sha otherwise) and its since is the bead's "+
		"pr_provenance_since. Absent or not current, GitHub's side of the PR reads as unread. The landing "+
		"order finds and does its work from it and the store, and reads GitHub first only for a merge: it has "+
		"the update read every part of the PR again, and decides the merge on what that read saved. Its take "+
		"files an ask for each untaken post and marks the post with the city's EYES, then has the update read "+
		"the PR's conversation again. The order's "+
		"label comparison reads the labels it saved, and labels that differ from the derived ones make a label "+
		"write due, on an open PR or, for one it shows merged or closed, a clear.",
	ledger.Warrant("saved-github-read"))

// provenanceKey is the instant from which the definition of feedback reads an
// unmarked post under the city's login as feedback. The one-PR update stamps it
// on a bead that lacks it, in the write that saves the first conversation it
// reads there.
var provenanceKey = ledger.Declare("pr_provenance_since", ledger.String,
	"The instant from which a post under the city's login is feedback unless it carries the city's mark, UTC "+
		"in the form YYYY-MM-DDTHH:MM:SSZ: when the city first read the PR's conversation. The one-PR update "+
		"(gctk pr refresh) stamps it on the bead that owns the PR, when the bead lacks it, in the write that "+
		"saves the first conversation it reads there, applying the definition from it. A value that is not an "+
		"instant in that form makes every such post the city's own.")

// FromStore answers whether the PR the bead owns is ready to merge at its
// current revision, over the read the one-PR update saved on the bead: it reads
// the bead's side through a pass of l and decides. It reads no GitHub and loads
// no definition of feedback. A bead with no complete pending record is not
// ready, and its answer says what the record lacks. A read of the store that
// fails, or a saved read that does not decode, returns its error and no answer.
func FromStore(l *ledger.Ledger, bead string) (Answer, error) { return fromSaved(l.Pass(), bead) }

// fromSaved is FromStore, reading through l, a pass the caller holds.
func fromSaved(l *ledger.Ledger, bead string) (Answer, error) {
	b, r, err := readSide(l, bead)
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
// store's conditions are its holds set by hand, its assignee, its own waits and
// the beads anchored to it. missing is what its record lacks to name its PR,
// and host and number name the PR once it lacks nothing.
type side struct {
	bead     string
	rec      record.Record
	branch   string
	holds    []string
	assignee string
	since    string
	results  []review.Result
	missing  []string
	waits    []Condition
	host     string
	number   int
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
		holds:    []string{read(mergeHoldKey), read(rebaseHoldKey)},
		assignee: strings.TrimSpace(r.Assignee()),
		since:    read(provenanceKey),
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
	if err := postAsks(l, r, rec.URL, waitConds); err != nil {
		return side{}, nil, err
	}
	anchored, err := anchoredTo(l, bead)
	if err != nil {
		return side{}, nil, err
	}
	b.waits = append(waitConds, anchored...)
	return b, r, nil
}

// postAsks names, on each of waits that is an open ask filed for a post on the
// PR at url, the post it carries, as the URL its reason ends with (postNamed),
// since a person's post the city works reads working on the PR. It reads the
// asks on the bead r only when the bead waits on something.
func postAsks(l *ledger.Ledger, r *ledger.Record, url string, waits []Condition) error {
	if len(waits) == 0 || url == "" {
		return nil
	}
	asks, err := review.AsksOn(l, r.ID)
	if err != nil {
		return err
	}
	for _, a := range asks {
		if !a.Open() {
			continue
		}
		post := postNamed(a.Reason, url)
		if post == "" {
			continue
		}
		for i := range waits {
			if waits[i].Kind == KindWait && waits[i].ID == a.ID {
				waits[i].Value = post
			}
		}
	}
	return nil
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

// requiredRuns is each result the check suites hold of a check run the PR
// requires, suite by suite, in the order GitHub lists them, each with its
// suite's id and its log.
func requiredRuns(suites []gh.CheckSuite) []RequiredRun {
	out := []RequiredRun{}
	for _, s := range suites {
		for _, r := range s.Runs {
			if r.Required {
				out = append(out, RequiredRun{Name: r.Name, Status: r.Status, Conclusion: r.Conclusion,
					Suite: s.ID, URL: r.URL})
			}
		}
	}
	return out
}

// savedSuites is each check suite as the checks part keeps it, in the order
// GitHub lists them, never nil.
func savedSuites(suites []gh.CheckSuite) []SavedSuite {
	out := []SavedSuite{}
	for _, s := range suites {
		out = append(out, SavedSuite{ID: s.ID, Status: s.Status, CreatedAt: s.CreatedAt, Run: s.Run,
			Attempt: s.Attempt, CheckRuns: len(s.Runs)})
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

// decideOver is the evaluator's rule over the bead's side and a GitHub read, and
// reads nothing. why, when it is not empty, says read is no read of the PR at
// one head. A bead whose record lacks a part gets the store's conditions
// alone, the record's gap first. A read that is absent, or not of the PR at the
// head the store holds (unread), gets one condition in place of every condition
// of GitHub's, ahead of the store's, and judges no head. Otherwise GitHub's
// conditions come first: the PR's identity, state, draft flag, head and merge
// state, its required checks, its approval and the review loop's result, then
// the store's, then each post that is feedback the city has not taken and the
// review threads waiting on the city's answer. An answer that judged a head carries
// the review loop's result there, passed or not, when one stands.
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
	if b.assignee != "" {
		store = append(store, Condition{Kind: KindAssigned, Value: b.assignee,
			Detail: fmt.Sprintf("the bead is assigned to %s, who works it now", b.assignee)})
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
	// leaves only checks the base does not require, which hold no merge.
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
	ans.Conditions = append(ans.Conditions, unhandled(read.Untaken)...)
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
