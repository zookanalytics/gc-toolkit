package pr

import (
	"context"
	"errors"
	"fmt"
	"maps"
	"regexp"
	"slices"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
	"github.com/zookanalytics/gc-toolkit/services/gctk/standing/person"
)

// The red-check and conflict acts (specs/tk-1tfzr71.161/design.md, section 4).
// A red check or a conflict on a PR the city owns is an ask on the PR's own
// bead, which the PR's review run works, as the one writer of its branch, and a
// human gate only where the city cannot go on. The landing order decides them
// for each owned PR from the read the one-PR update saved on its bead and the
// store (decideRed), as one act among its acts (redPlans), and takes that act
// under the record lock, deciding it again from the bead it reads there. An act
// that files work, re-runs a check, restarts one or files a gate is skipped
// while a hold set by hand or a human gate holds the bead, since bringing the
// branch current or sending a fix performs one horn of what a person may be
// deciding. A conversation holds only the PR's merge, so it holds none of
// these. The withdrawal of a red-check gate is never skipped.
//
// Each act reads a required check by its newest result at the head: the result
// in the newest check suite that holds one for it, a skip aside. A suite keeps
// a re-run's result in place of the attempt it re-ran, and a head carries a
// suite for each run of each workflow, such as a draft's skipped run beside the
// run its ready transition started. A newest result that passed stands for the
// check only while no older suite at the head holds a result the rule for
// required checks reads as failed (holdsFailed in rules.go). That failure still
// holds the merge though the same code passed, so the acts take it for a
// failure no code change fixes and re-run the run that holds it.

// redCap is how many earlier heads may each have drawn a red-check ask before a
// red head files the pr-fix-capped gate in place of another ask.
const redCap = 3

// stuckAfter is how long a check suite stays queued with no check runs before
// the act takes it for one that never starts, and how long the act waits after
// it restarts the head's checks before it asks a person.
const stuckAfter = 10 * time.Minute

// The situation keys of the red-check gates, each for one PR, by its number:
// a head still red after its ask closed, a PR whose asks reached the cap, a
// failure no code change fixes, and a required check that never reports.
const (
	keyUnmoved    = "pr-fix-unmoved"
	keyCapped     = "pr-fix-capped"
	keyNoncode    = "pr-fix-noncode"
	keyUnreported = "pr-check-unreported"
)

// redKeys are the keys of the red-check gates for PR number, in the order the
// withdrawal names them.
func redKeys(number int) []string {
	var out []string
	for _, k := range []string{keyUnmoved, keyCapped, keyNoncode, keyUnreported} {
		out = append(out, fmt.Sprintf("%s.%d", k, number))
	}
	return out
}

// deployCheck is the name of a check that a deploy platform reports, whose
// failure no change on the branch and no re-run of its jobs is sure to fix.
var deployCheck = regexp.MustCompile(`(?i)vercel|netlify|deploy`)

// The conclusions of a check run that failed for a cause no code change fixes:
// it timed out, was cancelled, failed to start, wants an action, or never
// finished before GitHub marked it stale.
var noncodeConclusions = []string{"TIMED_OUT", "CANCELLED", "STARTUP_FAILURE", "ACTION_REQUIRED", "STALE"}

// headCheck is one required check at the saved read's head: its name, the
// result the acts read it by, nil when its every result is a skip, the suite
// that holds that result, nil when the read names none, and whether a newer
// suite there passed the check, which makes that result a failure no code
// change fixes.
type headCheck struct {
	name        string
	result      *RequiredRun
	suite       *SavedSuite
	passedLater bool
}

// passing reports whether the check's result completed as a success.
func (h headCheck) passing() bool {
	return h.result != nil && h.result.Status == "COMPLETED" && slices.Contains(passingConclusions, h.result.Conclusion)
}

// failed reports whether the check's result completed without passing.
func (h headCheck) failed() bool {
	return h.result != nil && h.result.Status == "COMPLETED" && !slices.Contains(passingConclusions, h.result.Conclusion)
}

// noncode reports whether the check's result failed for a cause no code change
// fixes: a conclusion that says so, or a newer suite at the head that passed
// the check on the same code.
func (h headCheck) noncode() bool {
	return h.failed() && (h.passedLater || slices.Contains(noncodeConclusions, h.result.Conclusion))
}

// resultsAtHead is each required check the checks part holds a result of, by
// name, with the result the acts read it by. That is its newest result: the
// one in the suite created last, by its creation time and then its id, among
// those that hold a result for it other than SKIPPED. A result whose suite the
// part does not list ranks below every listed one. When the newest result
// passed and an older suite holds one the rule for required checks reads as
// failed (holdsFailed), the check is read by the newest such failure, with
// passedLater set.
func resultsAtHead(c *SavedChecks) []headCheck {
	suites := map[int64]*SavedSuite{}
	for i := range c.Suites {
		suites[c.Suites[i].ID] = &c.Suites[i]
	}
	later := func(a, b *SavedSuite) bool {
		switch {
		case a == nil:
			return false
		case b == nil:
			return true
		case a.CreatedAt != b.CreatedAt:
			return after(a.CreatedAt, b.CreatedAt)
		}
		return a.ID > b.ID
	}
	byName, held := map[string]*headCheck{}, map[string]*headCheck{}
	for i := range c.Runs {
		r := &c.Runs[i]
		h := byName[r.Name]
		if h == nil {
			h = &headCheck{name: r.Name}
			byName[r.Name] = h
		}
		if r.Conclusion == "SKIPPED" {
			continue
		}
		s := suites[r.Suite]
		if h.result == nil || later(s, h.suite) {
			h.result, h.suite = r, s
		}
		if f := held[r.Name]; holdsFailed(*r) && (f == nil || later(s, f.suite)) {
			held[r.Name] = &headCheck{name: r.Name, result: r, suite: s, passedLater: true}
		}
	}
	var out []headCheck
	for _, name := range slices.Sorted(maps.Keys(byName)) {
		h := byName[name]
		if f := held[name]; f != nil && h.passing() {
			h = f
		}
		out = append(out, *h)
	}
	return out
}

// checkNames is each check's name, joined by a space, as the asks and gates name
// them.
func checkNames(checks []headCheck) string {
	var out []string
	for _, h := range checks {
		out = append(out, h.name)
	}
	return strings.Join(out, " ")
}

// redAsk is one red-check ask on the bead: its id, the head its reason names,
// lower-cased, whether it is open, and when it closed.
type redAsk struct {
	id, head string
	open     bool
	closed   string
}

// redAskReason reads a red-check ask's reason: it names the PR by its number
// and the head it was filed at.
var redAskReason = regexp.MustCompile(`^Required check\(s\) failing on PR#([0-9]+) at head ([0-9a-fA-F]{7,64}):`)

// redState is what the acts decide one owned PR on: the bead, the read saved on
// it, what holds the bead from an act that files work, re-runs or restarts a
// check or files a gate, empty when nothing does, the open human gates on the
// bead under each red-check key, the red-check asks on it, its other open
// asks, the open beads other than its asks that name its branch, read only for
// a PR GitHub reads as conflicting, whether the review loop passed at the head
// the refinery validated, and the clock.
type redState struct {
	o       owned
	held    string
	gates   map[string][]string
	asks    []redAsk
	others  []string
	writers []string
	passed  bool
	now     time.Time
}

// The steps an act takes.
const (
	stepNone     = ""
	stepWithdraw = "withdraw"
	stepAsk      = "ask"
	stepGate     = "gate"
	stepRerun    = "rerun"
	stepRestart  = "restart"
)

// redStep is what the acts owe one PR in a run: one step, with what it acts on,
// or none, with why. why is the account the outcome gives. A re-run carries the
// runs it re-runs and, for a refusal, the gate it files on an approved PR in
// key and message, which name the refusal at %v. A restart carries the suite
// that never started and the earliest suite's creation at the head, the time
// after which a return to draft is the act's own.
type redStep struct {
	kind, why    string
	keys         []string
	reason       string
	key, message string
	runs         []int64
	approved     bool
	suite        SavedSuite
	pushed       string
}

func (s redState) none(why string) redStep { return redStep{why: why} }

// pr is the PR as the saved read shows it.
func (s redState) pr() *SavedPR { return s.o.saved.PR }

// approved reports whether an approval stands on the PR and no request for
// changes does, by the saved read's conversation.
func (s redState) approved() bool {
	c := s.o.saved.Conversation
	return c != nil && len(c.Approvers) > 0 && len(c.Requesters) == 0
}

// decideRed is what the red-check and conflict acts owe the PR s holds, and
// reads nothing. Checks read at another head than the PR's decide nothing. Once
// every required check passes at the head, each open red-check gate is
// withdrawn, whatever holds the bead. Otherwise the record must be pending at
// the head the refinery validated, since a changed head goes to the refinery's
// validation first, and nothing may hold the bead. A PR GitHub reads DIRTY, or
// BEHIND, which holds its merge as DIRTY does, is the conflict act's: an ask to
// bring the branch current, on an approved PR whose branch nothing else writes,
// and nothing on any other, since its checks wait for that merge. Then a code
// failure, a deploy's failure, a failure no code change fixes and a required
// check that never reports, in that order.
func decideRed(s redState) redStep {
	p, c := s.pr(), s.o.saved.Checks
	switch {
	case c == nil || c.Head != p.Head:
		return s.none("the PR's checks are not read at its head " + p.Head + " yet")
	case c.Suites == nil:
		return s.none("the saved checks hold no check suites yet, which the PR watch's next pass reads")
	}
	checks := resultsAtHead(c)
	green := len(checks) > 0 && !slices.ContainsFunc(checks, func(h headCheck) bool { return !h.passing() })
	if green {
		var keys []string
		for _, k := range redKeys(p.Number) {
			if len(s.gates[k]) > 0 {
				keys = append(keys, k)
			}
		}
		if len(keys) > 0 {
			return redStep{kind: stepWithdraw, keys: keys,
				why: fmt.Sprintf("every required check passes at head %s", p.Head)}
		}
	}
	switch {
	case s.o.rec.Result != record.Pending || p.Head != s.o.rec.Head:
		return s.none(fmt.Sprintf("the record is not pending at the PR's head %s, so the refinery's validation comes first", p.Head))
	case s.held != "":
		return s.none(s.held + ", so nothing is filed, re-run or restarted")
	case p.MergeState == "DIRTY" || p.MergeState == "BEHIND":
		return s.conflict()
	case green:
		return s.none("every required check passes at head " + p.Head)
	}
	var code, deploy, noncode []headCheck
	for _, h := range checks {
		switch {
		case h.failed() && deployCheck.MatchString(h.name):
			deploy = append(deploy, h)
		case h.noncode():
			noncode = append(noncode, h)
		case h.failed():
			code = append(code, h)
		}
	}
	switch {
	case len(code) > 0:
		return s.codeFailure(code)
	case len(deploy) > 0:
		return s.gate(keyNoncode, fmt.Sprintf("PR #%d (%s) has the deploy check(s) %s failing at head %s, which neither "+
			"a change on the branch nor a re-run of its jobs is sure to fix. Look at the deploy and fix it, or re-run it.",
			p.Number, p.URL, checkNames(deploy), p.Head), "a deploy's check fails: "+checkNames(deploy))
	case len(noncode) > 0:
		return s.noncodeFailure(noncode)
	}
	if suite, why := s.unreported(checks); why == "" {
		pushed := ""
		for _, x := range c.Suites {
			if pushed == "" || after(pushed, x.CreatedAt) {
				pushed = x.CreatedAt
			}
		}
		return redStep{kind: stepRestart, suite: suite, pushed: pushed,
			why: fmt.Sprintf("no required check has reported at head %s, and check suite %d has stayed queued with no "+
				"check runs since %s", p.Head, suite.ID, suite.CreatedAt)}
	}
	return s.none("no required check has failed at head " + p.Head)
}

// conflict is the conflict act's step for a PR GitHub reads DIRTY or BEHIND.
func (s redState) conflict() redStep {
	p := s.pr()
	switch {
	case !s.approved():
		return s.none(fmt.Sprintf("GitHub reads the PR %s, and no approval stands, so the city brings nothing current "+
			"and the PR's label shows the conflict", p.MergeState))
	case len(s.writers) > 0:
		return s.none(fmt.Sprintf("GitHub reads the PR %s, and %s works %s, so no conflict ask is filed beside it",
			p.MergeState, strings.Join(s.writers, ", "), p.HeadBranch))
	}
	reason := fmt.Sprintf("PR#%d conflicts with '%s' at head %s. Bring '%s' current by merging origin/%s in, resolve the "+
		"conflict, and push the merge as a fast-forward.", p.Number, p.Base, p.Head, p.HeadBranch, p.Base)
	if p.MergeState == "BEHIND" {
		reason = fmt.Sprintf("PR#%d is behind '%s' at head %s, which requires a current branch. Bring '%s' current by "+
			"merging origin/%s in, and push the merge as a fast-forward.", p.Number, p.Base, p.Head, p.HeadBranch, p.Base)
	}
	return redStep{kind: stepAsk, reason: reason, why: fmt.Sprintf("GitHub reads the approved PR %s at head %s", p.MergeState, p.Head)}
}

// codeFailure is the step for required checks that failed at the head for a
// code cause: an ask, one for each head, which the bounds read in the
// red-check asks on the bead, open or closed. An ask open at the head is the
// review run's to take. One closed there with the PR still red at that head
// files pr-fix-unmoved in place of a second: the review run closes an ask it
// fixed only once a later round judged the head that carries the fix, by which
// time the PR watch has saved that head, so an ask closed at the head the saved
// read still gives was answered there with no change. While another ask is
// open on the bead, such as one a run left waiting on the tracker of a failure
// the target carries, the run still has work on the PR, so no person is asked
// yet. Three earlier heads that each drew an ask file pr-fix-capped in place
// of a fourth.
func (s redState) codeFailure(code []headCheck) redStep {
	p := s.pr()
	head := strings.ToLower(p.Head)
	var closedHere *redAsk
	earlier := map[string]bool{}
	for i, a := range s.asks {
		switch {
		case a.head == head && a.open:
			return s.none(fmt.Sprintf("ask %s for the failing check(s) at head %s is open, and the PR's review run takes it", a.id, p.Head))
		case a.head == head:
			if closedHere == nil || after(a.closed, closedHere.closed) {
				closedHere = &s.asks[i]
			}
		default:
			earlier[a.head] = true
		}
	}
	if closedHere != nil && len(s.others) > 0 {
		return s.none(fmt.Sprintf("ask %s closed at head %s with %s still red, and ask %s is open on the bead, which the "+
			"PR's review run takes before a person is asked", closedHere.id, p.Head, checkNames(code),
			strings.Join(s.others, ", ")))
	}
	if closedHere != nil {
		return s.gate(keyUnmoved, fmt.Sprintf("PR #%d (%s) is still red on required check(s) %s at head %s, and the city's "+
			"ask to fix them there, %s, closed without moving the head. Another ask would repeat it, so the city stops "+
			"here. Read %s for why it closed, then fix the check(s) or re-run them.", p.Number, p.URL, checkNames(code), p.Head,
			closedHere.id, closedHere.id), fmt.Sprintf("ask %s closed at head %s and the head is still red on %s",
			closedHere.id, p.Head, checkNames(code)))
	}
	if len(earlier) >= redCap {
		return s.gate(keyCapped, fmt.Sprintf("PR #%d (%s) is red on required check(s) %s at head %s, after asks to fix its "+
			"checks at %d earlier heads, so the city files no further ask. Take the fix over by hand.", p.Number, p.URL,
			checkNames(code), p.Head, len(earlier)), fmt.Sprintf("%d earlier heads each drew an ask, and head %s is red on %s",
			len(earlier), p.Head, checkNames(code)))
	}
	var logs []string
	for _, h := range code {
		if h.result.URL != "" {
			logs = append(logs, h.result.URL)
		}
	}
	reason := fmt.Sprintf("Required check(s) failing on PR#%d at head %s: %s.", p.Number, p.Head, checkNames(code))
	if len(logs) > 0 {
		reason += " Run log(s): " + strings.Join(logs, " ") + "."
	}
	reason += fmt.Sprintf(" Fix the failing check(s) on '%s'.", p.HeadBranch)
	return redStep{kind: stepAsk, reason: reason, why: fmt.Sprintf("required check(s) %s failed at head %s", checkNames(code), p.Head)}
}

// noncodeFailure is the step for required checks that failed at the head for a
// cause no code change fixes, a newer run's pass of the same code among them: a
// re-run of the failed jobs of each GitHub Actions run that holds one, once per
// head and only once those runs have finished. A head reads re-run once a suite
// at it that holds a required check shows its run at an attempt above 1,
// whoever re-ran it. A failure at a head that reads re-run, and one outside any
// Actions run, files pr-fix-noncode on an approved PR, and an unapproved PR
// waits for its review.
func (s redState) noncodeFailure(failing []headCheck) redStep {
	p, c := s.pr(), s.o.saved.Checks
	var runs []int64
	var outside, running []string
	for _, h := range failing {
		switch {
		case h.suite == nil || h.suite.Run == 0:
			outside = append(outside, h.name)
		case h.suite.Status != "COMPLETED":
			running = append(running, fmt.Sprintf("%s (run %d)", h.name, h.suite.Run))
		}
		if h.suite != nil && h.suite.Run != 0 && !slices.Contains(runs, h.suite.Run) {
			runs = append(runs, h.suite.Run)
		}
	}
	_, rerun := reRunBy(c)
	cause := fmt.Sprintf("PR #%d (%s) has required check(s) %s failing at head %s for a cause no code change fixes",
		p.Number, p.URL, checkNames(failing), p.Head)
	if later := slices.DeleteFunc(slices.Clone(failing), func(h headCheck) bool { return !h.passedLater }); len(later) > 0 {
		cause += fmt.Sprintf(" (%s passed in a newer run at the head, and the merge still waits on the failed result)",
			checkNames(later))
	}
	switch {
	case len(outside) > 0:
		return s.gateApproved(cause+fmt.Sprintf(", and %s ran outside any GitHub Actions run, which the city cannot "+
			"re-run. Re-run them where they ran, or fix what runs them.", strings.Join(outside, " ")),
			strings.Join(outside, " ")+" failed outside any GitHub Actions run")
	case rerun:
		return s.gateApproved(cause+". The failed jobs were re-run once at this head already, and the check(s) failed "+
			"again. Re-run them again or fix the runner.", fmt.Sprintf("head %s was re-run once and %s failed again",
			p.Head, checkNames(failing)))
	case len(running) > 0:
		return s.none(fmt.Sprintf("%s failed for a cause no code change fixes, and the run behind %s has not finished, "+
			"which GitHub re-runs only once it has", checkNames(failing), strings.Join(running, ", ")))
	}
	return redStep{kind: stepRerun, runs: runs, approved: s.approved(), key: keyNoncode,
		message: cause + ", and GitHub refused the city's re-run of their failed jobs: %v. Re-run them by hand or fix the runner.",
		why:     fmt.Sprintf("%s failed at head %s for a cause no code change fixes", checkNames(failing), p.Head)}
}

// reRunBy is the check suite that makes c's head read re-run: one that holds a
// required check and shows the Actions run behind it at an attempt above 1. ok
// is false when no suite there does.
func reRunBy(c *SavedChecks) (x SavedSuite, ok bool) {
	for _, x := range c.Suites {
		if x.Attempt > 1 && slices.ContainsFunc(c.Runs, func(r RequiredRun) bool { return r.Suite == x.ID }) {
			return x, true
		}
	}
	return SavedSuite{}, false
}

// unreported is the suite at the head that never started, while every
// condition holds for the act to restart the head's checks, or why it does
// not: the PR is approved, ready and BLOCKED, its review result passed at the
// head the refinery validated, no required check has a result there but a
// skip, and a suite there has stayed queued with no check runs for stuckAfter
// since GitHub created it. A suite that never starts moves no sign, so the
// saved read still holds it as queued, and its creation is compared with the
// clock.
func (s redState) unreported(checks []headCheck) (SavedSuite, string) {
	p, c := s.pr(), s.o.saved.Checks
	switch {
	case p.Draft:
		return SavedSuite{}, "the PR is a draft"
	case p.MergeState != "BLOCKED":
		return SavedSuite{}, "GitHub reads the PR " + p.MergeState
	case !s.approved():
		return SavedSuite{}, "no approval stands"
	case !s.passed:
		return SavedSuite{}, "no review result passed at the head"
	case slices.ContainsFunc(checks, func(h headCheck) bool { return h.result != nil }):
		return SavedSuite{}, "a required check has reported"
	}
	for _, x := range c.Suites {
		created, err := time.Parse(time.RFC3339Nano, x.CreatedAt)
		if x.Status == "QUEUED" && x.CheckRuns == 0 && err == nil && !s.now.Before(created.Add(stuckAfter)) {
			return x, ""
		}
	}
	return SavedSuite{}, "no check suite has stayed queued with no check runs for " + stuckAfter.String()
}

// gate is the step that files the red-check gate key on the PR, with message,
// and the line that says when it is withdrawn.
func (s redState) gate(key, message, why string) redStep {
	return redStep{kind: stepGate, key: fmt.Sprintf("%s.%d", key, s.pr().Number), why: why,
		message: message + " This gate is withdrawn once every required check passes at the PR's head, and one cleared " +
			"while the PR is still red there is filed again."}
}

// gateApproved is gate for a failure no code change fixes, which asks a person
// only on an approved PR.
func (s redState) gateApproved(message, why string) redStep {
	if !s.approved() {
		return s.none(why + ", and no approval stands, so the PR waits for its review with no gate")
	}
	return s.gate(keyNoncode, message, why)
}

// redOf is the act one owned PR owes: the bead that owns it, the PR's URL as
// the bead names it, and the PR's identity.
type redOf struct {
	bead, url, key string
}

// of names the act, as each outcome it reports opens.
func (t redOf) of() string { return "the red checks and conflicts of " + t.url }

// redPlans are the acts the PRs the store's live beads own owe, read through
// pass: one for each PR whose bead's saved read and store owe a step
// (decideRed). A PR more than one live bead owns owes none, since the store
// names no one bead its asks and gates would hold. The plans are in the order
// of the PRs' identities.
func (u *run) redPlans(pass *ledger.Ledger) ([]plan, error) {
	all, err := ownersIn(pass)
	if err != nil {
		return nil, err
	}
	var out []plan
	for _, key := range slices.Sorted(maps.Keys(all)) {
		if len(all[key]) != 1 {
			continue
		}
		o := all[key][0]
		rows, err := pass.Find(ledger.ByID(o.id))
		if err != nil || len(rows) != 1 {
			continue
		}
		s, why := u.redOn(pass, rows[0], o)
		if why != "" || decideRed(s).kind == stepNone {
			continue
		}
		out = append(out, plan{id: "red " + o.id, red: &redOf{bead: o.id, url: o.url, key: key}})
	}
	return out, nil
}

// redOn is what the acts decide the bead r, which owns the PR o names, on, read
// through l, or why they decide nothing: the bead must own the PR on the
// record, be open or blocked, be assigned to nobody or to the refinery, as any
// act's bead is, and name its branch, and the saved read must be of its PR,
// show it open, and give it the bead's branch and the record's target, as the
// record act's identity check reads them (identityGaps), since a conflict ask
// names the base it merges. A read of the store that fails is a why too, which
// the act reports as a retry. The beads the bead waits on are read closed too while
// the record is pending, for the red-check asks' bounds, and open alone
// otherwise, since only a withdrawal is owed then.
func (u *run) redOn(l *ledger.Ledger, r *ledger.Record, o owned) (redState, string) {
	saved := o.saved
	switch {
	case !record.OnRecord(o.rec.Result):
		return redState{}, fmt.Sprintf("the bead owns no PR on the record: its merge_result reads %q", o.rec.Result)
	case o.status != "open" && o.status != "blocked":
		return redState{}, "the bead's status " + o.status + " is none the record knows"
	case o.assignee != "" && o.assignee != u.Refinery:
		return redState{}, "the bead is assigned to " + o.assignee + ", who works it now"
	case o.branch == "":
		return redState{}, "the bead names no branch"
	case saved == nil || saved.PR == nil:
		return redState{}, "the bead holds no saved read of the PR yet"
	case !strings.EqualFold(saved.PR.Repository, o.repo) || saved.PR.Number != o.number:
		return redState{}, fmt.Sprintf("the saved read is of %s#%d", saved.PR.Repository, saved.PR.Number)
	case saved.PR.State != "OPEN":
		return redState{}, "the saved read shows the PR " + strings.ToLower(saved.PR.State)
	}
	if ids := identityGaps(saved.PR.pullRequest(), o.rec.URL, o.number, o.rec.Repo, o.branch, o.rec.Target); len(ids) > 0 {
		return redState{}, "the PR on GitHub is not the one the record names: " + strings.Join(ids, ", ")
	}
	pending := o.rec.Result == record.Pending
	blockers, err := blockersIn(l, r, pending)
	if err != nil {
		return redState{}, "the beads it waits on did not read: " + err.Error()
	}
	s := redState{o: o, gates: map[string][]string{}, now: u.clock()}
	for i, name := range []string{"merge hold", "rebase hold"} {
		v, _, err := []reading{mergeHoldKey, rebaseHoldKey}[i].Get(r)
		if err != nil {
			return redState{}, "its holds did not read: " + err.Error()
		}
		if isSet(strings.TrimSpace(v)) && s.held == "" {
			s.held = fmt.Sprintf("a %s is set on the bead (%s)", name, strings.TrimSpace(v))
		}
	}
	keys := redKeys(o.number)
	var gates []*ledger.Record
	for _, b := range blockers {
		if b.Status() == "closed" || !person.IsHumanGate(b.IssueType(), b.AwaitType()) {
			continue
		}
		if s.held == "" {
			s.held = fmt.Sprintf("human gate %s (%s) holds the bead", b.ID, firstOf(b.AwaitID(), "no key"))
		}
		if slices.Contains(keys, b.AwaitID()) {
			gates = append(gates, b)
		}
	}
	slices.SortStableFunc(gates, gateOrder)
	for _, g := range gates {
		s.gates[g.AwaitID()] = append(s.gates[g.AwaitID()], g.ID)
	}
	if !pending {
		return s, ""
	}
	asks, err := review.AsksIn(l, r, blockers)
	if err != nil {
		return redState{}, "the asks on the bead did not read: " + err.Error()
	}
	closed := map[string]string{}
	for _, b := range blockers {
		if b.Status() == "closed" {
			closed[b.ID] = b.ClosedAt()
		}
	}
	for _, a := range asks {
		m := redAskReason.FindStringSubmatch(a.Reason)
		if m == nil || m[1] != fmt.Sprint(o.number) {
			if a.Open() {
				s.others = append(s.others, a.ID)
			}
			continue
		}
		s.asks = append(s.asks, redAsk{id: a.ID, head: strings.ToLower(m[2]), open: a.Open(), closed: closed[a.ID]})
	}
	results, _, err := review.Results.Get(r)
	if err != nil {
		return redState{}, "the review results did not read: " + err.Error()
	}
	s.passed = passedAt(results, o.rec.Head, o.rec.Target)
	if m := saved.PR.MergeState; m == "DIRTY" || m == "BEHIND" {
		rows, err := l.Find(record.OnBranch(o.branch))
		if err != nil {
			return redState{}, "the beads on the branch did not read: " + err.Error()
		}
		for _, w := range rows {
			if w.ID != o.id && w.Status() != "closed" && !review.IsAsk(w, o.branch) {
				s.writers = append(s.writers, w.ID)
			}
		}
		slices.Sort(s.writers)
	}
	return s, ""
}

// gateOrder orders the gates under one key as human-gate.sh's dedup reads them
// (bd_gates_open_under_key): by the time each was created, a time that does
// not read as one last, and then by id.
func gateOrder(a, b *ledger.Record) int {
	ta, ea := time.Parse(time.RFC3339Nano, a.CreatedAt())
	tb, eb := time.Parse(time.RFC3339Nano, b.CreatedAt())
	switch {
	case ea != nil && eb == nil:
		return 1
	case ea == nil && eb != nil:
		return -1
	case ea == nil && eb == nil:
		if c := ta.Compare(tb); c != 0 {
			return c
		}
	}
	return strings.Compare(a.ID, b.ID)
}

// red is the act's turn, which ends stop after it starts: under the record
// lock it reads the bead again, decides it again, and takes the step it owes
// (redLocked). A step that does not complete makes it a retry, and the next
// run decides it again.
func (u *run) red(t redOf, stop time.Duration) RunOutcome {
	ctx, cancel := bounded(stop)
	defer cancel()
	out := u.redLocked(ctx, t)
	if ctx.Err() != nil && (out.Action == ActRetry || out.Action == ActFailed) {
		out.Action = ActRetry
		out.Detail = fmt.Sprintf("the act was stopped at its %s: %s", stop, out.Detail)
	}
	return out
}

// redLocked is the act made under the record lock, within ctx, whose outcome's
// detail opens with the act it is (redOf.of).
func (u *run) redLocked(ctx context.Context, t redOf) RunOutcome {
	unbound := u.Ledger
	u.Ledger = unbound.Within(ctx)
	defer func() { u.Ledger = unbound }()
	said := func(action, detail string) RunOutcome {
		return RunOutcome{Bead: t.bead, Action: action, Detail: t.of() + " " + detail}
	}
	release, err := record.Lock(u.Dir, lockWait(ctx, u.Wait))
	if err != nil {
		return said(ActRetry, "waits for the next run: the record lock did not come free: "+err.Error())
	}
	defer release()
	r, err := u.read(t.bead)
	if err != nil {
		return said(ActFailed, "did not read the bead: "+err.Error())
	}
	if r == nil {
		return said(ActSkipped, "acts on nothing: the store no longer holds the bead")
	}
	o, ok := ownerOf(r)
	if !ok || o.key() != t.key {
		return said(ActSkipped, "acts on nothing: the bead no longer owns the PR")
	}
	s, why := u.redOn(u.Ledger.Pass(), r, o)
	if why != "" {
		return said(ActChecked, "acts on nothing: "+why)
	}
	step := decideRed(s)
	if step.kind == stepNone {
		return said(ActChecked, "owes nothing: "+step.why)
	}
	if why := u.originDiffers(o.host, o.repo); why != "" {
		return said(ActRetry, "waits for the next run: "+why)
	}
	switch step.kind {
	case stepWithdraw:
		var done []string
		for _, key := range step.keys {
			if err := u.Gates.Withdraw(ctx, o.id, key, step.why); err != nil {
				return said(ActRetry, fmt.Sprintf("did not withdraw the %s gate, and the next run withdraws it: %v%s", key,
					err, also(" It withdrew ", done)))
			}
			done = append(done, fmt.Sprintf("%s (%s)", key, strings.Join(s.gates[key], ", ")))
		}
		return said(ActWithdrawn, fmt.Sprintf("withdrew the gate(s) %s: %s", strings.Join(done, ", "), step.why))
	case stepAsk:
		noChecks := func(string) (review.Index, error) {
			return review.Index{}, errors.New("a red-check or conflict ask sends back no check")
		}
		ask, filed, err := review.FileAsk(u.Ledger, review.AskRequest{Bead: o.id, Reason: step.reason}, noChecks)
		if err != nil {
			return said(ActRetry, fmt.Sprintf("did not file its ask (%s), and the next run files it: %v", step.why, err))
		}
		how := "filed"
		if !filed {
			how = "found"
		}
		return said(ActAsked, fmt.Sprintf("%s ask %s for the PR's review run: %s", how, ask, step.why))
	case stepGate:
		return u.redGate(ctx, o, step, said)
	case stepRerun:
		// The saved read shows a re-run only once the PR watch reads the checks
		// again, so the act reads the head's suites first, and a re-run made
		// since, the city's own in a run before or a person's, is not asked for
		// again: GitHub refuses a run still going, and a finished one would be
		// re-run twice at the head.
		hub := u.Hub(ctx, o.host)
		head := o.saved.PR.Head
		suites, err := hub.CheckSuites(o.repo, head, o.number)
		if err != nil {
			return said(ActRetry, fmt.Sprintf("did not read the check suites at head %s before their re-run (%s), and "+
				"the next run decides again: %v", head, step.why, err))
		}
		if x, ok := reRunBy(&SavedChecks{Runs: requiredRuns(suites), Suites: savedSuites(suites)}); ok {
			return said(ActChecked, fmt.Sprintf("owes nothing yet: GitHub shows run %d at attempt %d at head %s, a "+
				"re-run the PR watch's next read saves: %s", x.Run, x.Attempt, head, step.why))
		}
		var ran []string
		for _, run := range step.runs {
			err := hub.RerunFailedJobs(o.repo, run)
			switch {
			case err == nil:
				ran = append(ran, fmt.Sprint(run))
				continue
			case !gh.Refused(err):
				return said(ActRetry, fmt.Sprintf("asked GitHub to re-run the failed jobs of run %d, which did not answer, "+
					"and the next run decides again: %v%s", run, err, also(" It re-ran ", ran)))
			case !step.approved:
				return said(ActChecked, fmt.Sprintf("asked GitHub to re-run the failed jobs of run %d, which refused: %v. No "+
					"approval stands, so the PR waits for its review with no gate, and the next run asks for the re-run "+
					"again%s", run, err, also(". It re-ran ", ran)))
			}
			step.kind, step.why = stepGate, fmt.Sprintf("GitHub refused the re-run of run %d: %v", run, err)
			step.key, step.message = fmt.Sprintf("%s.%d", step.key, o.number), fmt.Sprintf(step.message, err)+
				" This gate is withdrawn once every required check passes at the PR's head, and one cleared while the "+
				"PR is still red there is filed again."
			return u.redGate(ctx, o, step, said)
		}
		return said(ActRerun, fmt.Sprintf("re-ran the failed jobs of run(s) %s once at head %s: %s",
			strings.Join(ran, ", "), o.saved.PR.Head, step.why))
	case stepRestart:
		return u.restart(ctx, s, step, said)
	}
	return said(ActFailed, "decided a step it does not know, "+step.kind)
}

// redGate files the red-check gate the step names on the bead. human-gate.sh
// files one open gate under the key, so a gate open there already stands.
func (u *run) redGate(ctx context.Context, o owned, step redStep, said func(string, string) RunOutcome) RunOutcome {
	if err := u.Gates.File(ctx, o.id, step.key, step.message); err != nil {
		return said(ActRetry, fmt.Sprintf("did not file the %s gate (%s), and the next run files it: %v", step.key, step.why, err))
	}
	return said(ActGated, fmt.Sprintf("filed the %s gate, so a person is asked: %s", step.key, step.why))
}

// restart restarts the checks at a head whose suite never started, once per
// head: it reads when the PR's timeline records it was returned to draft, and
// a return after the head's earliest suite was created is the act's own, since
// a writer of the branch returns the PR to draft before it pushes. A writer's
// return whose push never landed reads as the act's own too, and the ready
// transition that ended its draft started the workflows again, as the act's
// would. With none, it returns the PR to draft and marks it ready again, which
// sends the pull_request event that starts the workflows again. With one, it
// waits stuckAfter from it for the checks to report, and then files
// pr-check-unreported.
func (u *run) restart(ctx context.Context, s redState, step redStep, said func(string, string) RunOutcome) RunOutcome {
	p := s.pr()
	hub := u.Hub(ctx, s.o.host)
	drafted, err := hub.ConvertedToDraft(s.o.repo, s.o.number)
	if err != nil {
		return said(ActRetry, fmt.Sprintf("did not read the PR's returns to draft (%s), and the next run reads them: %v", step.why, err))
	}
	own := ""
	for _, at := range drafted {
		if after(at, step.pushed) && (own == "" || after(at, own)) {
			own = at
		}
	}
	if own == "" {
		if err := hub.ConvertToDraft(p.ID); err != nil {
			return said(ActRetry, fmt.Sprintf("did not return the PR to draft (%s), and the next run decides again: %v", step.why, err))
		}
		if err := hub.MarkReady(p.ID); err != nil {
			return said(ActRetry, fmt.Sprintf("returned the PR to draft, and its ready transition did not land, which the "+
				"record's next run makes (%s): %v", step.why, err))
		}
		return said(ActRestarted, fmt.Sprintf("returned the PR to draft and marked it ready, so its workflows start again: %s", step.why))
	}
	at, err := time.Parse(time.RFC3339Nano, own)
	if err != nil {
		return said(ActRetry, fmt.Sprintf("read the PR's return to draft at %q, which is no time, and the next run reads it again", own))
	}
	if s.now.Before(at.Add(stuckAfter)) {
		return said(ActChecked, fmt.Sprintf("owes nothing yet: the PR was returned to draft at %s to restart its checks, "+
			"which have %s from then to report: %s", own, stuckAfter, step.why))
	}
	step.key = fmt.Sprintf("%s.%d", keyUnreported, p.Number)
	step.why = fmt.Sprintf("the checks were restarted at %s and still have not reported: %s", own, step.why)
	step.message = fmt.Sprintf("PR #%d (%s) is approved and its review passed at head %s, but no required check has "+
		"reported there: GitHub reads it BLOCKED, and check suite %d has stayed queued with no jobs since %s. The city "+
		"returned the PR to draft and marked it ready again at %s to restart its checks, and they still have not "+
		"reported. Start them by hand, such as by returning the PR to draft and marking it ready again, or look at the "+
		"runners. This gate is withdrawn once every required check passes at the PR's head.", p.Number, p.URL, p.Head,
		step.suite.ID, step.suite.CreatedAt, own)
	return u.redGate(ctx, s.o, step, said)
}

// also is the clause that names what an act did before a step that did not
// complete, empty when it did nothing.
func also(lead string, done []string) string {
	if len(done) == 0 {
		return ""
	}
	return lead + strings.Join(done, ", ")
}
