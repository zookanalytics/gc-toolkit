package review

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/git"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
)

// A step of a review run reads what its iteration judges: the run it belongs
// to, the PR the run judges, the iteration it runs in, the head that iteration
// judges and the change triage reads there.
//
// Before a run judges anything, its prepare asks whether the run must stop
// with no result: when its vars do not name the record the bead that owns the
// PR carries, or when GitHub's PR is not open from the bead's branch into the
// run's target at the run's head.
//
// The head of iteration 1 is the run's first head, the head the refinery
// validated. Each later iteration judges the head the round before it pushed,
// and the same head again when that round pushed nothing.
//
// The change triage reads at a head is, in order of the first that applies:
// none, at a head a run already passed at for the same target, where triage
// picks only the checks an ask sends back; the change since the nearest
// earlier head of the branch that a run passed at for the same target; the
// run's own repair, from its first head, at a head the repair pushed; and the
// whole PR, from where it left the target.

// The step names of a review run whose outputs the run reads: the last part of
// the step's gc.step_ref, as Gas City writes it at every iteration.
const (
	stepTriage = "triage"
	stepRepair = "rule-and-repair"
	stepLane   = "lane"
	stepRecord = "record"
)

// Step is one step of a review run: its bead, its gc.step_ref, the output it
// writes (triage, lane or repair, "" for a step that writes none), the
// iteration it runs in (0 outside the loop), the run, and the PR's record and
// branch as the bead that owns the PR carries them.
type Step struct {
	ID, Ref   string
	Output    string
	Iteration int
	Run       *Run
	Record    record.Record
	Branch    string
	BranchVar string
	Results   []Result
}

// ReadStep reads the step bead id names and the run it belongs to.
func ReadStep(l *ledger.Ledger, id string) (*Step, error) {
	b, err := one(l, id)
	if err != nil {
		return nil, err
	}
	run, err := ReadRun(l, id)
	if err != nil {
		return nil, err
	}
	st := &Step{ID: b.ID, Ref: str(stepRefKey, b), Run: run}
	if b.ID == run.Root {
		return nil, &NotARun{ID: id, Why: "it is the run's root, not one of its steps"}
	}
	switch last := st.Ref[strings.LastIndex(st.Ref, ".")+1:]; last {
	case stepTriage:
		st.Output = OutputTriage
	case stepRepair:
		st.Output = OutputRepair
	case stepLane:
		st.Output = OutputLane
	}
	if raw := str(attemptKey, b); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 1 {
			return nil, &NotARun{ID: id, Why: fmt.Sprintf("its gc.attempt reads %q, which names no iteration", raw)}
		}
		st.Iteration = n
	}
	if st.Output != "" && st.Iteration == 0 {
		return nil, &NotARun{ID: id, Why: "it writes a " + st.Output + " output and names no iteration"}
	}
	owner, err := one(l, run.PRBead)
	if err != nil {
		return nil, err
	}
	if st.Record, err = record.Read(owner); err != nil {
		return nil, err
	}
	if st.Results, _, err = resultsKey.Get(owner); err != nil {
		return nil, err
	}
	root, err := one(l, run.Root)
	if err != nil {
		return nil, err
	}
	st.Branch, st.BranchVar = view(record.Branch, owner), str(branchVar, root)
	if st.Branch == "" {
		st.Branch = st.BranchVar
	}
	return st, nil
}

// PR is the PR the run judges: the URL the record names, else the PR the bead
// names as its existing one.
func (st *Step) PR() string {
	if st.Record.URL != "" {
		return st.Record.URL
	}
	return st.Record.ExistingPR
}

// GitHub is the one read a run's prepare makes of GitHub, the PR the run
// judges, which the gh adapter's Client carries out and its fake answers.
type GitHub interface {
	PullRequest(repo string, number int) (*gh.PullRequest, error)
}

// MustStop is why the run must stop with no result, "" when it may go on: its
// vars do not name the record the bead that owns the PR carries, the PR the
// bead names is not a PR's URL, or GitHub's PR is not open, its head is not
// the run's head, it is from another branch or it merges into another target.
// It reads the PR once the vars name the record, through the GitHub that
// github returns for the host the URL names. A read of the PR that fails is
// an error, since whether the run stands is then unknown.
func (st *Step) MustStop(github func(host string) GitHub) (string, error) {
	if why := st.mismatch(); why != "" {
		return why, nil
	}
	url := st.PR()
	host, repo, number, ok := record.ParseURL(url)
	if !ok {
		return fmt.Sprintf("%q is not a PR's URL", url), nil
	}
	pr, err := github(host).PullRequest(repo, number)
	if err != nil {
		return "", fmt.Errorf("GitHub did not answer for %s: %w", url, err)
	}
	run := st.Run
	switch {
	case pr.State != "OPEN":
		return fmt.Sprintf("the PR is %s", strings.ToLower(pr.State)), nil
	case pr.HeadRefOid != run.Head:
		return fmt.Sprintf("the PR's head is %s, no longer the run's head %s", pr.HeadRefOid, run.Head), nil
	case pr.HeadRefName != st.Branch:
		return fmt.Sprintf("the PR is from %s, not the branch %s", pr.HeadRefName, st.Branch), nil
	case pr.BaseRefName != run.Target:
		return fmt.Sprintf("the PR merges into %s, not the run's target %s", pr.BaseRefName, run.Target), nil
	}
	return "", nil
}

// mismatch is why the run's vars do not name the record the bead that owns
// the PR carries, "" when they do: the run's head is the head the record
// validated, its target the record's, and its branch var, when it names one,
// the bead's branch. A shadow run judges a PR whose bead may be on no record,
// so it needs only the PR, its branch and a head.
func (st *Step) mismatch() string {
	run, rec := st.Run, st.Record
	switch {
	case !git.IsObjectID(run.Head):
		return fmt.Sprintf("its head var reads %q, which is not a full object name", run.Head)
	case run.Target == "":
		return "its target var is empty"
	case st.Branch == "":
		return fmt.Sprintf("neither %s nor the run's branch var names the PR's branch", run.PRBead)
	case st.PR() == "":
		return fmt.Sprintf("%s names no PR", run.PRBead)
	case run.Shadow:
		return ""
	case !record.OnRecord(rec.Result):
		return fmt.Sprintf("%s is not on the pending record: its merge_result reads %q", run.PRBead, rec.Result)
	case rec.Head != run.Head:
		return fmt.Sprintf("the record names the validated head %s, and the run's head var is %s", rec.Head, run.Head)
	case rec.Target != run.Target:
		return fmt.Sprintf("the record names the target %q, and the run's target var is %q", rec.Target, run.Target)
	case st.BranchVar != "" && st.BranchVar != st.Branch:
		return fmt.Sprintf("%s's branch is %s, and the run's branch var is %s", run.PRBead, st.Branch, st.BranchVar)
	}
	return ""
}

// HeadOf is the head iteration n of the run judges: the run's first head at
// iteration 1, and at a later one the head the last round before it pushed,
// else the head the last triage before it judged.
func (run *Run) HeadOf(n int) string {
	head := run.Head
	for m := 1; m < n; m++ {
		it := run.Iterations[m]
		if it == nil {
			continue
		}
		if it.Triage != nil && it.Triage.Head != "" {
			head = it.Triage.Head
		}
		if it.Repair != nil && it.Repair.Pushed != "" {
			head = it.Repair.Pushed
		}
	}
	return head
}

// Change is the change triage reads at a head: From..Head, none when From is
// the head itself, or the whole PR from where it left the target when From is
// "". Why names which rule chose it.
type Change struct {
	From, Head, Why string
}

// The rules that choose a change.
const (
	ChangeNone        = "the head already passed into its target"
	ChangeSincePassed = "since the last head that passed"
	ChangeRepair      = "the run's own repair, since its first head"
	ChangeWhole       = "the whole PR"
)

// None reports whether the change is empty: the head already passed, so no
// change is left to judge.
func (c Change) None() bool { return c.From != "" && c.From == c.Head }

func (c Change) String() string {
	switch {
	case c.None():
		return fmt.Sprintf("none at %s: %s", c.Head, c.Why)
	case c.From == "":
		return fmt.Sprintf("the whole PR at %s, from where it left its target", c.Head)
	}
	return fmt.Sprintf("%s..%s, %s", c.From, c.Head, c.Why)
}

// ChangeAt is the change triage reads at head, for the run's target: none
// when a passed result names the head itself for that target, so a run poured
// for an ask at a passed head judges only what the ask sends back; else since
// the nearest earlier head of the branch a passed result names for that
// target; else the run's own repair since its first head when the head is not
// the first; else the whole PR. Results are the entries on the bead that owns
// the PR. repos are the checkouts that can answer which commit descends from
// which; the head is fetched from origin by its id when none of them holds it,
// and a read that fails is an error, because a wrong change is a wrong triage.
// A clone that holds the head holds every commit behind it, so a passed head
// that clone does not hold is not behind the head, such as one a rewrite of
// the branch left behind, which origin may no longer serve.
func ChangeAt(run *Run, results []Result, repos []string, head string) (Change, error) {
	if !git.IsObjectID(head) {
		return Change{}, fmt.Errorf("the head %q is not a full object name", head)
	}
	var passed []string
	for _, r := range results {
		switch {
		case !r.Passed || r.Target != run.Target:
		case r.Head == head:
			return Change{From: head, Head: head, Why: ChangeNone}, nil
		case git.IsObjectID(r.Head):
			passed = append(passed, r.Head)
		}
	}
	if len(passed) > 0 {
		repo, err := commitRepo(repos, head, "which head passed behind it went unread")
		if err != nil {
			return Change{}, err
		}
		var behind []string
		for _, p := range passed {
			if !git.HasCommit(repo, p) {
				continue
			}
			ok, err := ancestor(repo, p, head)
			if err != nil {
				return Change{}, err
			}
			if ok {
				behind = append(behind, p)
			}
		}
		if nearest, err := latest(repo, behind); err != nil {
			return Change{}, err
		} else if nearest != "" {
			return Change{From: nearest, Head: head, Why: ChangeSincePassed}, nil
		}
	}
	if head != run.Head && run.Head != "" {
		return Change{From: run.Head, Head: head, Why: ChangeRepair}, nil
	}
	return Change{Head: head, Why: ChangeWhole}, nil
}

// ancestor reports whether a is an ancestor of b, or b itself, in repo.
func ancestor(repo, a, b string) (bool, error) {
	if a == b {
		return true, nil
	}
	ok, err := git.IsAncestor(repo, a, b)
	if err != nil {
		return false, fmt.Errorf("whether %s is behind %s did not read: %w", a, b, err)
	}
	return ok, nil
}

// latest is the commit of heads that descends from every other, the nearest
// to the head they all sit behind, "" for none.
func latest(repo string, heads []string) (string, error) {
	best := ""
	for _, h := range heads {
		if best == "" {
			best = h
			continue
		}
		ok, err := ancestor(repo, best, h)
		if err != nil {
			return "", err
		}
		if ok {
			best = h
		}
	}
	return best, nil
}
