package pr

import (
	"context"
	"fmt"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
)

// The draft cycle (specs/tk-1tfzr71.108/design.md, section 5). A round is the
// city's work on a PR's branch between two ready transitions. Every writer of
// the city onto an open PR's branch returns the PR to draft with Draft before it
// pushes, so the round's first push finds the PR ready and converts it, and a
// later push finds it a draft and changes nothing. The landing order makes the
// ready transition, in its run (readyBar), from the draft flag the read the PR
// watch saved shows. Each transition changes the draft flag only when it reads
// it as other than the one it sets, so a retry, a restart or a person's own
// toggle leaves the cycle to finish from where the PR stands. A return to draft
// dismisses no approval.

// Drafted is what Draft found and did: the PR it read, and whether it converted
// the PR to draft, which it does only when the PR was ready.
type Drafted struct {
	URL       string
	Converted bool
}

// DraftRefusal is a return to draft the PR's state refused: the bead names no
// PR, or the PR is not open, or not open from the bead's branch. The PR is left
// as it stands.
type DraftRefusal struct{ Bead, Why string }

func (e *DraftRefusal) Error() string {
	return fmt.Sprintf("%s: the PR is left as it stands: %s", e.Bead, e.Why)
}

// Draft returns the PR the bead owns to draft before a writer pushes a new head
// onto it. The PR is the one url names, else the one the bead's record names,
// else the PR the bead records for the refinery to reuse. It must be in the
// rig's own repository, open, and open from the bead's branch when the bead
// records one. It reads the PR's draft flag first and converts only a PR that
// is ready. A conversion GitHub refused or did not answer is an error, and the
// PR may still be ready, so the writer pushes nothing.
func (l Landing) Draft(bead, url string) (Drafted, error) {
	o, why, err := l.owned(bead, url)
	if err != nil {
		return Drafted{URL: o.url}, err
	}
	if why != "" {
		return Drafted{}, &DraftRefusal{Bead: bead, Why: why}
	}
	hub := l.Hub(context.Background(), o.host)
	p, err := hub.PullRequest(o.repo, o.number)
	if err != nil {
		return Drafted{URL: o.url}, err
	}
	if why := notOpenFrom(p, o.branch); why != "" {
		return Drafted{URL: o.url}, &DraftRefusal{Bead: bead, Why: why}
	}
	if p.IsDraft {
		return Drafted{URL: o.url}, nil
	}
	if err := hub.ConvertToDraft(p.ID); err != nil {
		return Drafted{URL: o.url}, fmt.Errorf("PR %s did not return to draft, so it may still be ready: %w", o.url, err)
	}
	return Drafted{URL: o.url, Converted: true}, nil
}

// ownedPR is the PR a bead owns, as a writer onto it takes it: its URL, the
// host, repository and number the URL names, and the bead's branch, "" when
// it records none.
type ownedPR struct {
	url, host, repo, branch string
	number                  int
}

// owned is the PR the bead owns as Draft and Edit take it: the one url names,
// else the one the bead's record names, else the PR the bead records for the
// refinery to reuse, in the rig's own repository. why says why the bead names
// no PR they take, "" when it names one. A PR outside the rig's repository is
// an OriginError, and a read that fails returns the store's error.
func (l Landing) owned(bead, url string) (o ownedPR, why string, err error) {
	r, err := l.read(bead)
	if err != nil {
		return ownedPR{}, "", err
	}
	if r == nil {
		return ownedPR{}, "the store holds no such bead", nil
	}
	rec, err := record.Read(r)
	if err != nil {
		return ownedPR{}, "", err
	}
	branch, _, err := record.Branch.Get(r)
	if err != nil {
		return ownedPR{}, "", err
	}
	if url == "" {
		url = firstOf(rec.URL, rec.ExistingPR)
	}
	if url == "" {
		return ownedPR{}, "it names no PR", nil
	}
	host, repo, number, ok := record.ParseURL(url)
	if !ok {
		return ownedPR{}, fmt.Sprintf("%q is not a pull request's URL", url), nil
	}
	o = ownedPR{url: url, host: host, repo: repo, number: number, branch: strings.TrimSpace(branch)}
	if err := l.sameOrigin(host, repo); err != nil {
		return ownedPR{url: url}, "", err
	}
	return o, "", nil
}

// notOpenFrom says why the PR GitHub reports is not one a writer takes onto
// the bead's branch, and is empty when it is: it is open, and open from the
// branch when the bead records one.
func notOpenFrom(p *gh.PullRequest, branch string) string {
	switch {
	case p.State != "OPEN":
		return fmt.Sprintf("PR %s is %s, not open", p.URL, strings.ToLower(p.State))
	case branch != "" && p.HeadRefName != branch:
		return fmt.Sprintf("PR %s is open from %s, not from the bead's branch %s", p.URL, p.HeadRefName, branch)
	}
	return ""
}

// readyBar says why the run does not mark a draft ready, and is empty when it
// marks it: the saved read shows the PR a draft open at the head the refinery
// validated, the record is pending there, a passed result of the
// review loop names that head and the PR's target, no review run is attached
// to the bead and no ask a run can take is open on it, so the order has no run
// to pour for it. An ask that something holds starts no round until a run can
// take it, so it keeps no PR a draft. It does not wait for CI.
func readyBar(s state, p *gh.PullRequest, results []review.Result, asks []review.Ask) string {
	switch {
	case !p.IsDraft:
		return "the PR is ready already"
	case s.rec.Result != record.Pending || p.HeadRefOid != s.rec.Head:
		return "the record is not pending at the PR's head"
	case !passedAt(results, p.HeadRefOid, p.BaseRefName):
		return fmt.Sprintf("no review result passed at head %s into %s", p.HeadRefOid, p.BaseRefName)
	case len(s.runs) > 0:
		return "the review run " + strings.Join(s.runs, ", ") + " is attached to the bead"
	}
	for _, a := range asks {
		if a.Takeable() {
			return "ask " + a.ID + " is open and nothing holds it, so a review run takes it before the PR is ready"
		}
	}
	return ""
}
