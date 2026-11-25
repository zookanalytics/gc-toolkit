package pr_test

import (
	"errors"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
)

// The red-check and conflict acts (specs/tk-1tfzr71.161/design.md, section 4,
// and section 11's tests for unit 5), on the landing order's world: a PR on the
// record at the head the refinery validated, approved, whose review passed
// there, and whose required checks ran in one GitHub Actions run.

// The run behind the required checks, and when GitHub created its suite.
const (
	testsRun     = 101
	suiteCreated = "2026-11-12T08:30:00Z"
)

// logOf is where a check's log is read in the tests run.
func logOf(name string) string {
	return "https://github.com/acme/widgets/actions/runs/101/job/" + name
}

// redWorld is the landing order's world for the acts, with the run's clock, a
// review run's pour, and the PR's checks in the tests run's suite.
type redWorld struct {
	*land
	at   *clock
	runs *pours
}

func newRed(t *testing.T) *redWorld {
	t.Helper()
	d := newCycle(t)
	d.l.Refinery = boundRefinery
	at := d.timed()
	d.github.Now = at.now
	p := &pours{store: d.store}
	d.l.Runs = p
	w := &redWorld{land: d, at: at, runs: p}
	w.checks(t, "COMPLETED", testsRun, 1, check("test", "SUCCESS"), check("test-macos", "SUCCESS"))
	return w
}

// check is a required check run of the tests run that completed with
// conclusion, with its log.
func check(name, conclusion string) gh.CheckRun {
	return gh.CheckRun{Name: name, Status: "COMPLETED", Conclusion: conclusion, Required: true, URL: logOf(name)}
}

// checks sets the one suite at the head: its status, the Actions run behind
// it, 0 for none, at attempt, and its check runs.
func (d *redWorld) checks(t *testing.T, status string, run int64, attempt int, runs ...gh.CheckRun) {
	t.Helper()
	d.pr.Suites[head] = []gh.CheckSuite{{ID: 1, Status: status, CreatedAt: suiteCreated, Run: run, Attempt: attempt, Runs: runs}}
}

// redOutcome splits a run's outcomes into the act's and the rest. A run that
// made no act gives a zero outcome for it.
func redOutcome(t *testing.T, out []pr.RunOutcome) (pr.RunOutcome, []pr.RunOutcome) {
	t.Helper()
	var red pr.RunOutcome
	var rest []pr.RunOutcome
	for _, o := range out {
		if strings.Contains(o.Detail, "the red checks and conflicts of "+prURL) {
			if red.Action != "" {
				t.Fatalf("two of the act in one run: %+v", out)
			}
			red = o
			continue
		}
		rest = append(rest, o)
	}
	return red, rest
}

// runRed is the PR watch's pass, then a run of the landing order, and returns
// the act's outcome, zero when the run made none.
func (d *redWorld) runRed(t *testing.T) pr.RunOutcome {
	t.Helper()
	d.refresh(t)
	red, _ := redOutcome(t, d.reconcile(t, pr.Options{}))
	return red
}

// redAsks is each red-check or conflict ask filed on the bead's branch, by its
// reason.
func (d *redWorld) redAsks() []string {
	var out []string
	for _, reason := range d.asksFiled() {
		if strings.HasPrefix(reason, "Required check(s) failing") || strings.Contains(reason, "Bring '") {
			out = append(out, reason)
		}
	}
	return out
}

// closeAsks closes each ask on the bead's branch at at, as a review run's
// record closes one it answered, and stops the blocked listing holding the bead
// on it.
func (d *redWorld) closeAsks(t *testing.T, at string) {
	t.Helper()
	var closed []string
	for _, c := range d.store.Creates() {
		b, ok := d.store.Row(c.ID)
		if !ok || b.IssueType != "task" || b.Metadata["branch"] != branch || b.Status == "closed" {
			continue
		}
		b.Status, b.ClosedAt = "closed", at
		d.store.Put(b)
		closed = append(closed, c.ID)
	}
	d.edit(t, func(b *fake.Bead) {
		for i := range b.Edges {
			if slices.Contains(closed, b.Edges[i].ID) {
				b.Edges[i].Status, b.Edges[i].ClosedAt = "closed", at
			}
		}
	})
	d.store.Unlist(closed...)
}

// closeRedAsks closes each red-check ask on the bead's branch at at, as a
// review run's record closes one it ruled, and leaves its other asks open.
func (d *redWorld) closeRedAsks(t *testing.T, at string) {
	t.Helper()
	var closed []string
	for _, c := range d.store.Creates() {
		b, ok := d.store.Row(c.ID)
		if !ok || b.IssueType != "task" || b.Metadata["branch"] != branch || b.Status == "closed" ||
			!strings.HasPrefix(b.Description, "Required check(s) failing") {
			continue
		}
		b.Status, b.ClosedAt = "closed", at
		d.store.Put(b)
		closed = append(closed, c.ID)
	}
	d.edit(t, func(b *fake.Bead) {
		for i := range b.Edges {
			if slices.Contains(closed, b.Edges[i].ID) {
				b.Edges[i].Status, b.Edges[i].ClosedAt = "closed", at
			}
		}
	})
	d.store.Unlist(closed...)
}

// askedAt files a red-check ask at h on the bead, closed at at, as the act
// filed one at an earlier head and the review run closed it there.
func (d *redWorld) askedAt(t *testing.T, id, h, at string) {
	t.Helper()
	reason := "Required check(s) failing on PR#7 at head " + h + ": test. Fix the failing check(s) on '" + branch + "'."
	d.store.Put(fake.Bead{ID: id, Title: "Review ask: " + reason, Status: "closed", ClosedAt: at, IssueType: "task",
		Description: reason, Metadata: map[string]string{"branch": branch}})
	d.edit(t, func(b *fake.Bead) {
		b.Edges = append(b.Edges, gcbd.Edge{Type: gcbd.EdgeBlocks, ID: id, Title: "Review ask", Status: "closed",
			IssueType: "task", ClosedAt: at})
	})
}

// gateOn files an open human gate on the bead under key, which the blocked
// listing holds the bead on.
func (d *redWorld) gateOn(t *testing.T, id, key string) {
	t.Helper()
	d.store.Put(fake.Bead{ID: id, Title: "a gate keyed " + key, Status: "open", IssueType: "gate", AwaitType: "human",
		AwaitID: key, CreatedAt: "2026-11-12T08:50:00Z"})
	d.edit(t, func(b *fake.Bead) {
		b.Edges = append(b.Edges, gcbd.Edge{Type: gcbd.EdgeBlocks, ID: id, Title: "a gate keyed " + key, Status: "open",
			IssueType: "gate", AwaitType: "human"})
	})
	d.store.List(bead, id)
}

// rerunAsks is the id of each run the acts asked GitHub to re-run.
func (d *redWorld) rerunAsks() []string {
	var out []string
	for _, a := range d.github.Asks() {
		if a.Method == "RerunFailedJobs" {
			out = append(out, a.ID)
		}
	}
	return out
}

// stages is each move between draft and ready the acts asked GitHub for.
func (d *redWorld) stages() []string {
	var out []string
	for _, a := range d.github.Asks() {
		if a.Method == "ConvertToDraft" || a.Method == "MarkReady" {
			out = append(out, a.Method)
		}
	}
	return out
}

// unapprove leaves the PR with no review.
func (d *redWorld) unapprove() { d.pr.Reviews = nil }

// evaluate is the evaluator's answer from the read the PR watch last saved on
// the bead.
func (d *redWorld) evaluate(t *testing.T) pr.Answer {
	t.Helper()
	ans, err := pr.FromStore(ledger.New(d.store), bead)
	if err != nil {
		t.Fatalf("FromStore: %v", err)
	}
	return ans
}

// A required check that failed for a code cause gets one ask for the head,
// which names the PR, the head, the failing check with its log and the branch
// to fix, and the review run is poured to take it. A later run at the same
// head files none beside it.
func TestACodeFailureFilesOneAskForItsHead(t *testing.T) {
	d := newRed(t)
	d.checks(t, "COMPLETED", testsRun, 1, check("test", "FAILURE"), check("test-macos", "SUCCESS"))
	red := d.runRed(t)
	is(t, red, pr.ActAsked)
	want := "Required check(s) failing on PR#7 at head " + head + ": test. Run log(s): " + logOf("test") +
		". Fix the failing check(s) on '" + branch + "'."
	if got := d.redAsks(); !slices.Equal(got, []string{want}) {
		t.Fatalf("the act filed %q, want %q", got, want)
	}
	if red := d.runRed(t); red.Action != "" || d.runs.count() != 1 {
		t.Fatalf("a run with the ask open at the head made %+v and poured %d runs, want no act and the one run", red,
			d.runs.count())
	}
	if got := d.redAsks(); len(got) != 1 {
		t.Fatalf("the acts filed %d asks for one head", len(got))
	}
}

// A closed ask at a head still red there files pr-fix-unmoved in place of a
// second ask.
func TestAHeadStillRedAfterItsAskClosedIsGated(t *testing.T) {
	d := newRed(t)
	d.checks(t, "COMPLETED", testsRun, 1, check("test", "FAILURE"), check("test-macos", "SUCCESS"))
	is(t, d.runRed(t), pr.ActAsked)
	d.closeAsks(t, "2026-11-12T08:59:00Z")
	is(t, d.runRed(t), pr.ActGated)
	if got := d.gates.list(); !slices.Equal(got, []string{bead + " pr-fix-unmoved.7"}) {
		t.Fatalf("the act filed %v, want the unmoved gate", got)
	}
	if got := d.redAsks(); len(got) != 1 {
		t.Fatalf("the act filed a second ask at the head: %q", got)
	}
}

// A closed ask at a head still red there files no gate while another ask is
// open on the bead, such as one a review run left waiting on the tracker of a
// failure the target carries, and pr-fix-unmoved once that ask closes with the
// head still red.
func TestAHeadStillRedWaitsWhileAnotherAskIsOpen(t *testing.T) {
	d := newRed(t)
	d.checks(t, "COMPLETED", testsRun, 1, check("test", "FAILURE"), check("test-macos", "SUCCESS"))
	is(t, d.runRed(t), pr.ActAsked)
	d.store.Put(fake.Bead{ID: "tk-tracker", Title: "Pre-existing failure: TestTheCap", Status: "open", IssueType: "bug"})
	if _, ok, err := review.FileAsk(ledger.New(d.store), review.AskRequest{Bead: bead, WaitingOn: []string{"tk-tracker"},
		Reason: "Bring '" + branch + "' current by merging origin/main in once tk-tracker fixes test on 'main'."},
		nil); err != nil || !ok {
		t.Fatalf("the waiting ask did not file: %v", err)
	}
	d.closeRedAsks(t, "2026-11-12T08:59:00Z")
	if red := d.runRed(t); red.Action != "" {
		t.Fatalf("a run with another ask open on the bead made %+v, want no act", red)
	}
	if got := d.gates.list(); len(got) != 0 {
		t.Fatalf("the act filed %v while another ask was open", got)
	}
	d.closeAsks(t, "2026-11-12T09:30:00Z")
	is(t, d.runRed(t), pr.ActGated)
	if got := d.gates.list(); !slices.Equal(got, []string{bead + " pr-fix-unmoved.7"}) {
		t.Fatalf("the act filed %v, want the unmoved gate", got)
	}
}

// Three earlier heads that each drew an ask file pr-fix-capped at a fourth red
// head in place of a fourth ask.
func TestARedHeadAfterThreeAskedHeadsIsGated(t *testing.T) {
	d := newRed(t)
	for i, h := range []string{older, later, rewrite} {
		d.askedAt(t, "tk-asked"+string(rune('a'+i)), h, "2026-11-12T07:00:00Z")
	}
	d.checks(t, "COMPLETED", testsRun, 1, check("test", "FAILURE"), check("test-macos", "SUCCESS"))
	is(t, d.runRed(t), pr.ActGated)
	if got := d.gates.list(); !slices.Equal(got, []string{bead + " pr-fix-capped.7"}) {
		t.Fatalf("the act filed %v, want the capped gate", got)
	}
	if got := d.redAsks(); len(got) != 0 {
		t.Fatalf("the act filed a fourth ask: %q", got)
	}
}

// Two earlier heads leave the third its ask.
func TestARedHeadAfterTwoAskedHeadsIsAsked(t *testing.T) {
	d := newRed(t)
	d.askedAt(t, "tk-askeda", older, "2026-11-12T07:00:00Z")
	d.askedAt(t, "tk-askedb", later, "2026-11-12T07:00:00Z")
	d.checks(t, "COMPLETED", testsRun, 1, check("test", "FAILURE"), check("test-macos", "SUCCESS"))
	is(t, d.runRed(t), pr.ActAsked)
}

// A deploy's failed check files a gate, approved or not, and no ask.
func TestADeploysFailureIsGated(t *testing.T) {
	d := newRed(t)
	d.unapprove()
	d.checks(t, "COMPLETED", testsRun, 1, check("test", "SUCCESS"), check("Vercel Preview Deploy", "FAILURE"))
	is(t, d.runRed(t), pr.ActGated)
	if got := d.gates.list(); !slices.Equal(got, []string{bead + " pr-fix-noncode.7"}) || len(d.redAsks()) != 0 {
		t.Fatalf("the act filed %v and the asks %q, want the noncode gate alone", got, d.redAsks())
	}
}

// A required check that failed for a cause no code change fixes is re-run once
// for the head, and only once the run that holds it has finished. A second
// failure at the head files the gate on an approved PR, as does one in a
// second run at that head whose own attempt is 1, and neither is re-run.
func TestANoncodeFailureIsReRunOnceForItsHeadAfterItsRunFinished(t *testing.T) {
	d := newRed(t)
	d.checks(t, "IN_PROGRESS", testsRun, 1, check("test", "CANCELLED"), gh.CheckRun{Name: "test-macos",
		Status: "IN_PROGRESS", Required: true})
	if red := d.runRed(t); red.Action != "" || len(d.rerunAsks()) != 0 {
		t.Fatalf("a failure in a run still going made %+v and re-ran %v", red, d.rerunAsks())
	}
	d.checks(t, "COMPLETED", testsRun, 1, check("test", "CANCELLED"), check("test-macos", "SUCCESS"))
	is(t, d.runRed(t), pr.ActRerun)
	if got := d.rerunAsks(); !slices.Equal(got, []string{"101"}) {
		t.Fatalf("the act re-ran %v, want run 101", got)
	}
	if s := d.pr.Suites[head][0]; s.Attempt != 2 {
		t.Fatalf("the re-run left the suite at attempt %d", s.Attempt)
	}
	// The re-run fails again.
	d.checks(t, "COMPLETED", testsRun, 2, check("test", "TIMED_OUT"), check("test-macos", "SUCCESS"))
	is(t, d.runRed(t), pr.ActGated)
	if got := d.gates.list(); !slices.Equal(got, []string{bead + " pr-fix-noncode.7"}) || len(d.rerunAsks()) != 1 {
		t.Fatalf("a second failure at the head filed %v and re-ran %v, want the gate and no second re-run",
			got, d.rerunAsks())
	}

	// A second run at the head, at its own attempt 1, fails the same way: the
	// head reads re-run by the first run's attempt.
	e := newRed(t)
	e.pr.Suites[head] = []gh.CheckSuite{
		{ID: 1, Status: "COMPLETED", CreatedAt: suiteCreated, Run: testsRun, Attempt: 2,
			Runs: []gh.CheckRun{check("test", "SUCCESS"), check("test-macos", "SUCCESS")}},
		{ID: 2, Status: "COMPLETED", CreatedAt: "2026-11-12T08:40:00Z", Run: 102, Attempt: 1,
			Runs: []gh.CheckRun{check("test-macos", "CANCELLED")}},
	}
	is(t, e.runRed(t), pr.ActGated)
	if got := e.rerunAsks(); len(got) != 0 {
		t.Fatalf("a head read re-run was re-run again: %v", got)
	}
}

// Each failure no code change fixes asks a person only on an approved PR: one
// at a head already re-run, one outside any Actions run and a re-run GitHub
// refuses. An unapproved PR waits for its review with no gate, and a refused
// re-run is asked for again at the next run.
func TestANoncodeFailureIsGatedOnlyOnAnApprovedPR(t *testing.T) {
	for _, c := range []struct {
		name  string
		setup func(*redWorld, *testing.T)
		reran bool
	}{
		{"at a head already re-run", func(d *redWorld, t *testing.T) {
			d.checks(t, "COMPLETED", testsRun, 2, check("test", "CANCELLED"), check("test-macos", "SUCCESS"))
		}, false},
		{"outside any Actions run", func(d *redWorld, t *testing.T) {
			d.checks(t, "COMPLETED", 0, 0, check("test", "STARTUP_FAILURE"), check("test-macos", "SUCCESS"))
		}, false},
		{"whose re-run GitHub refuses", func(d *redWorld, t *testing.T) {
			d.checks(t, "COMPLETED", testsRun, 1, check("test", "CANCELLED"), check("test-macos", "SUCCESS"))
			d.github.Fail["RerunFailedJobs"] = errors.New("gh: Unable to retry this workflow run because it was created " +
				"over a month ago (HTTP 403)")
		}, true},
	} {
		t.Run(c.name, func(t *testing.T) {
			d := newRed(t)
			c.setup(d, t)
			is(t, d.runRed(t), pr.ActGated)
			if got := d.gates.list(); !slices.Equal(got, []string{bead + " pr-fix-noncode.7"}) {
				t.Fatalf("on an approved PR the act filed %v, want the noncode gate", got)
			}
			if c.reran != (len(d.rerunAsks()) == 1) {
				t.Fatalf("the act re-ran %v", d.rerunAsks())
			}

			e := newRed(t)
			e.unapprove()
			c.setup(e, t)
			red := e.runRed(t)
			if len(e.gates.list()) != 0 {
				t.Fatalf("on an unapproved PR the act filed %v", e.gates.list())
			}
			if c.reran {
				is(t, red, pr.ActChecked)
				if red := e.runRed(t); red.Action != pr.ActChecked || len(e.rerunAsks()) != 2 {
					t.Fatalf("the next run made %+v and asked for the re-runs %v, want the re-run asked again", red,
						e.rerunAsks())
				}
			} else if red.Action != "" {
				t.Fatalf("on an unapproved PR the act made %+v", red)
			}
		})
	}
}

// A re-run the saved read does not show yet, the city's own from a run before
// or a person's, is not asked for again: GitHub refuses a run still going, and
// that refusal would ask a person about a re-run already under way, and a
// re-run that already failed again would be re-run a second time at the head.
// Once the PR watch reads the re-run, the act owes nothing until it finishes.
func TestAReRunTheSavedReadLacksIsNotAskedForAgain(t *testing.T) {
	d := newRed(t)
	d.checks(t, "COMPLETED", testsRun, 1, check("test", "CANCELLED"), check("test-macos", "SUCCESS"))
	is(t, d.runRed(t), pr.ActRerun)
	red, _ := redOutcome(t, d.reconcile(t, pr.Options{}))
	is(t, red, pr.ActChecked)
	if got := d.rerunAsks(); len(got) != 1 || len(d.gates.list()) != 0 {
		t.Fatalf("a run before the PR watch read the re-run asked for the re-runs %v and filed %v, want the one "+
			"re-run and no gate", got, d.gates.list())
	}
	if red := d.runRed(t); red.Action != "" {
		t.Fatalf("a re-run the saved read shows going made %+v", red)
	}

	e := newRed(t)
	e.checks(t, "COMPLETED", testsRun, 1, check("test", "CANCELLED"), check("test-macos", "SUCCESS"))
	e.refresh(t)
	e.checks(t, "QUEUED", testsRun, 2, gh.CheckRun{Name: "test", Status: "QUEUED", Required: true},
		check("test-macos", "SUCCESS"))
	red, _ = redOutcome(t, e.reconcile(t, pr.Options{}))
	is(t, red, pr.ActChecked)
	if got := e.rerunAsks(); len(got) != 0 || len(e.gates.list()) != 0 {
		t.Fatalf("a person's re-run the saved read lacks drew the re-runs %v and the gates %v", got, e.gates.list())
	}

	f := newRed(t)
	f.checks(t, "COMPLETED", testsRun, 1, check("test", "CANCELLED"), check("test-macos", "SUCCESS"))
	is(t, f.runRed(t), pr.ActRerun)
	f.checks(t, "COMPLETED", testsRun, 2, check("test", "TIMED_OUT"), check("test-macos", "SUCCESS"))
	red, _ = redOutcome(t, f.reconcile(t, pr.Options{}))
	is(t, red, pr.ActChecked)
	if got := f.rerunAsks(); len(got) != 1 {
		t.Fatalf("a re-run that failed again before the PR watch read it was asked for again: %v", got)
	}
	is(t, f.runRed(t), pr.ActGated)
}

// A re-run GitHub did not answer is a retry, which asks no person.
func TestAReRunGitHubDidNotAnswerIsARetry(t *testing.T) {
	d := newRed(t)
	d.checks(t, "COMPLETED", testsRun, 1, check("test", "CANCELLED"), check("test-macos", "SUCCESS"))
	d.github.Fail["RerunFailedJobs"] = errors.New("gh: error connecting to api.github.com")
	is(t, d.runRed(t), pr.ActRetry)
	if len(d.gates.list()) != 0 {
		t.Fatalf("an unanswered re-run filed %v", d.gates.list())
	}
}

// Once every required check passes at the PR's head, each red-check gate open
// on the bead is withdrawn, even while a hold set by hand holds the bead, and
// a gate under another key is left.
func TestTheRedCheckGatesAreWithdrawnOnceTheChecksPass(t *testing.T) {
	d := newRed(t)
	d.gateOn(t, "tk-g1", "pr-fix-unmoved.7")
	d.gateOn(t, "tk-g2", "pr-check-unreported.7")
	d.gateOn(t, "tk-g3", "review-run-failed")
	d.edit(t, func(b *fake.Bead) { b.Metadata["merge_hold"] = "operator: wait" })
	red := d.runRed(t)
	is(t, red, pr.ActWithdrawn)
	want := []string{bead + " pr-fix-unmoved.7 every required check passes at head " + head,
		bead + " pr-check-unreported.7 every required check passes at head " + head}
	if got := d.gates.withdrawals(); !slices.Equal(got, want) {
		t.Fatalf("the act withdrew %q, want %q", got, want)
	}
	if !strings.Contains(red.Detail, "tk-g1") || !strings.Contains(red.Detail, "tk-g2") {
		t.Fatalf("the withdrawal names no gate: %s", red.Detail)
	}

	// While a check still fails, nothing is withdrawn.
	e := newRed(t)
	e.gateOn(t, "tk-g1", "pr-fix-unmoved.7")
	e.checks(t, "COMPLETED", testsRun, 1, check("test", "FAILURE"), check("test-macos", "SUCCESS"))
	if red := e.runRed(t); red.Action != "" || len(e.gates.withdrawals()) != 0 {
		t.Fatalf("a red head made %+v and withdrew %v", red, e.gates.withdrawals())
	}

	// A withdrawal that does not land is a retry, and the next run withdraws.
	f := newRed(t)
	f.gateOn(t, "tk-g1", "pr-fix-unmoved.7")
	f.gates.withdrawErr = errors.New("human-gate: could not resolve the gate")
	is(t, f.runRed(t), pr.ActRetry)
	f.gates.withdrawErr = nil
	is(t, f.runRed(t), pr.ActWithdrawn)
}

// A required check is read by its newest result: a failure in a newer suite
// than a pass asks, and so does one a newer run skipped. A failure in a suite
// created before one where the check passed still holds the merge, by the rule
// for required checks, so it is a failure no code change fixes, and the act
// re-runs the run that holds it.
func TestTheNewestResultOfACheckIsTheOneActedOn(t *testing.T) {
	older := gh.CheckSuite{ID: 1, Status: "COMPLETED", CreatedAt: suiteCreated, Run: testsRun, Attempt: 1}
	newer := gh.CheckSuite{ID: 2, Status: "COMPLETED", CreatedAt: "2026-11-12T08:40:00Z", Run: 102, Attempt: 1}
	for _, c := range []struct {
		name        string
		first, then string
		want        string
	}{
		{"a failure a newer run passed", "FAILURE", "SUCCESS", pr.ActRerun},
		{"a pass a newer run failed", "SUCCESS", "FAILURE", pr.ActAsked},
		{"a failure a newer run skipped", "FAILURE", "SKIPPED", pr.ActAsked},
	} {
		t.Run(c.name, func(t *testing.T) {
			d := newRed(t)
			a, b := older, newer
			a.Runs = []gh.CheckRun{check("test", c.first), check("test-macos", "SUCCESS")}
			b.Runs = []gh.CheckRun{check("test", c.then)}
			d.pr.Suites[head] = []gh.CheckSuite{b, a}
			if red := d.runRed(t); red.Action != c.want {
				t.Fatalf("the act made %+v, want %q", red, c.want)
			}
		})
	}
}

// laterPass sets the head's two suites: the tests run, at attempt, where test
// ended with first, and a newer run where test passed.
func (d *redWorld) laterPass(t *testing.T, attempt int, first string) {
	t.Helper()
	d.pr.Suites[head] = []gh.CheckSuite{
		{ID: 2, Status: "COMPLETED", CreatedAt: "2026-11-12T08:40:00Z", Run: 102, Attempt: 1,
			Runs: []gh.CheckRun{check("test", "SUCCESS")}},
		{ID: 1, Status: "COMPLETED", CreatedAt: suiteCreated, Run: testsRun, Attempt: attempt,
			Runs: []gh.CheckRun{check("test", first), check("test-macos", "SUCCESS")}},
	}
}

// A failure a newer run at the head passed holds the merge as long as its
// suite holds it, so the act re-runs that suite's run, once for the head, and
// the merge and the acts read the head green together once the re-run passes:
// the evaluator holds no failed check, and the red-check gates are withdrawn
// then and not before. A re-run that fails again asks a person on an approved
// PR, and names the newer pass.
func TestAFailureANewerRunPassedIsReRunUntilTheMergeReadsItPassed(t *testing.T) {
	d := newRed(t)
	d.laterPass(t, 1, "FAILURE")
	is(t, d.runRed(t), pr.ActRerun)
	if got := d.rerunAsks(); !slices.Equal(got, []string{"101"}) {
		t.Fatalf("the act re-ran %v, want run 101, which holds the failure", got)
	}
	d.laterPass(t, 2, "SUCCESS")
	if red := d.runRed(t); red.Action != "" || len(d.rerunAsks()) != 1 || len(d.gates.list()) != 0 {
		t.Fatalf("once the re-run passed the act made %+v, re-ran %v and filed %v", red, d.rerunAsks(), d.gates.list())
	}
	if ans := d.evaluate(t); slices.ContainsFunc(ans.Conditions, func(c pr.Condition) bool {
		return c.Kind == pr.KindCheckFailed || c.Kind == pr.KindCheckPending
	}) {
		t.Fatalf("once the re-run passed the evaluator still holds the checks: %+v", ans.Conditions)
	}

	e := newRed(t)
	e.gateOn(t, "tk-g1", "pr-fix-noncode.7")
	e.laterPass(t, 1, "FAILURE")
	if red := e.runRed(t); red.Action != "" || len(e.gates.withdrawals()) != 0 {
		t.Fatalf("while the older suite holds the failure the act made %+v and withdrew %v", red, e.gates.withdrawals())
	}
	if ans := e.evaluate(t); !slices.ContainsFunc(ans.Conditions, func(c pr.Condition) bool { return c.Kind == pr.KindCheckFailed }) {
		t.Fatalf("the evaluator does not hold the failure the act acts on: %+v", ans.Conditions)
	}
	e.laterPass(t, 2, "SUCCESS")
	is(t, e.runRed(t), pr.ActWithdrawn)

	f := newRed(t)
	f.laterPass(t, 2, "FAILURE")
	is(t, f.runRed(t), pr.ActGated)
	if got := f.gates.list(); !slices.Equal(got, []string{bead + " pr-fix-noncode.7"}) || len(f.rerunAsks()) != 0 {
		t.Fatalf("a failure that failed again at its re-run filed %v and re-ran %v, want the gate alone", got, f.rerunAsks())
	}
	if msg := f.gates.messages[0]; !strings.Contains(msg, "test passed in a newer run at the head") {
		t.Fatalf("the gate does not name the newer pass: %s", msg)
	}
}

// stuck leaves the PR approved and passed but BLOCKED, with no required check
// reported at the head: the draft's suite skipped its jobs, and the suite the
// ready transition started has stayed queued with no check runs since queued.
func (d *redWorld) stuck(t *testing.T, queued string) {
	t.Helper()
	d.pr.Facts.MergeStateStatus = "BLOCKED"
	skipped := gh.CheckRun{Name: "test", Status: "COMPLETED", Conclusion: "SKIPPED", Required: true}
	d.pr.Suites[head] = []gh.CheckSuite{
		{ID: 1, Status: "COMPLETED", CreatedAt: suiteCreated, Run: testsRun, Attempt: 1, Runs: []gh.CheckRun{skipped}},
		{ID: 2, Status: "QUEUED", CreatedAt: queued, Run: 102, Attempt: 1},
	}
}

// A required check that never reports, behind a suite that stayed queued with
// no check runs for ten minutes, has the PR returned to draft and marked ready
// once for its head, which starts its workflows again. Ten minutes after that
// with still no report, a person is asked.
func TestAStuckSuiteIsRestartedOnceAndThenGated(t *testing.T) {
	d := newRed(t)
	d.stuck(t, "2026-11-12T08:55:00Z")
	if red := d.runRed(t); red.Action != "" {
		t.Fatalf("a suite queued for five minutes made %+v", red)
	}
	d.at.advance(6 * time.Minute)
	is(t, d.runRed(t), pr.ActRestarted)
	if got := d.stages(); !slices.Equal(got, []string{"ConvertToDraft", "MarkReady"}) || d.pr.Facts.IsDraft {
		t.Fatalf("the restart asked %v and left the PR a draft: %v", got, d.pr.Facts.IsDraft)
	}
	d.at.advance(time.Minute)
	if red := d.runRed(t); red.Action != pr.ActChecked || len(d.stages()) != 2 || len(d.gates.list()) != 0 {
		t.Fatalf("a minute after the restart the act made %+v, asked %v and filed %v", red, d.stages(), d.gates.list())
	}
	d.at.advance(10 * time.Minute)
	is(t, d.runRed(t), pr.ActGated)
	if got := d.gates.list(); !slices.Equal(got, []string{bead + " pr-check-unreported.7"}) || len(d.stages()) != 2 {
		t.Fatalf("the act filed %v and asked %v, want the unreported gate and no second restart", got, d.stages())
	}
}

// The restart is the act's own once per head: a return to draft before the
// head's first suite, or in the second GitHub created it, as a writer of the
// branch makes before it pushes, is the draft cycle's and leaves the restart to
// make. A PR that is not approved, a
// suite that started its runs, and a required check that reported each make
// none.
func TestTheRestartWaitsOnlyForItsOwnReturnToDraft(t *testing.T) {
	d := newRed(t)
	d.stuck(t, "2026-11-12T08:40:00Z")
	d.pr.Drafted = []string{"2026-11-12T08:29:00Z", suiteCreated}
	is(t, d.runRed(t), pr.ActRestarted)

	for name, change := range map[string]func(*redWorld){
		"unapproved": func(d *redWorld) { d.unapprove() },
		"a started suite": func(d *redWorld) {
			d.pr.Suites[head][1].Runs = []gh.CheckRun{{Name: "lint", Status: "QUEUED"}}
		},
		"a reported check": func(d *redWorld) {
			d.pr.Suites[head][0].Runs = []gh.CheckRun{{Name: "test", Status: "IN_PROGRESS", Required: true}}
		},
		"a draft": func(d *redWorld) { d.pr.Facts.IsDraft = true },
	} {
		t.Run(name, func(t *testing.T) {
			e := newRed(t)
			e.stuck(t, "2026-11-12T08:40:00Z")
			change(e)
			if red := e.runRed(t); red.Action == pr.ActRestarted || red.Action == pr.ActGated {
				t.Fatalf("the act made %+v", red)
			}
		})
	}
}

// A PR GitHub reads DIRTY gets an ask to bring its branch current once it is
// approved and nothing holds it, a conversation on the PR included, and none
// while it is unapproved, a hold or a human gate holds it, another bead works
// its branch, or GitHub gives it another base or head branch than the record
// names, whichever act the run takes first. BEHIND asks the same.
func TestAConflictIsAskedOnlyOnAnApprovedPRThatNothingHolds(t *testing.T) {
	conflicts := "PR#7 conflicts with 'main' at head " + head + ". Bring '" + branch + "' current by merging " +
		"origin/main in, resolve the conflict, and push the merge as a fast-forward."
	for _, c := range []struct {
		name  string
		setup func(*redWorld, *testing.T)
		want  string
	}{
		{"approved", func(*redWorld, *testing.T) {}, conflicts},
		{"approved, with a conversation open on the PR", func(d *redWorld, t *testing.T) {
			(&admitting{land: d.land, runs: d.runs}).conversation(t, "open", "", "")
		}, conflicts},
		{"behind a target that requires a current branch", func(d *redWorld, _ *testing.T) {
			d.pr.Facts.MergeStateStatus = "BEHIND"
		}, "PR#7 is behind 'main' at head " + head + ", which requires a current branch. Bring '" + branch +
			"' current by merging origin/main in, and push the merge as a fast-forward."},
		{"unapproved", func(d *redWorld, _ *testing.T) { d.unapprove() }, ""},
		{"held by a rebase hold", func(d *redWorld, t *testing.T) {
			d.edit(t, func(b *fake.Bead) { b.Metadata["rebase_hold"] = "true" })
		}, ""},
		{"held by a human gate", func(d *redWorld, t *testing.T) { d.gateOn(t, "tk-g1", "review-run-failed") }, ""},
		{"with a rework child on its branch", func(d *redWorld, _ *testing.T) {
			d.store.Put(fake.Bead{ID: "tk-rework", Title: "rework", Status: "open", IssueType: "task",
				Metadata: map[string]string{"branch": branch, "task_kind": "rework", "gc.routed_to": "rig/polecat"}})
		}, ""},
		{"retargeted to another base", func(d *redWorld, _ *testing.T) {
			d.pr.Facts.BaseRefName = "develop"
			d.l.Shuffle = redFirst
		}, ""},
		{"on another head branch", func(d *redWorld, _ *testing.T) {
			d.pr.Facts.HeadRefName = "polecat/other"
			d.l.Shuffle = redFirst
		}, ""},
	} {
		t.Run(c.name, func(t *testing.T) {
			d := newRed(t)
			d.pr.Facts.MergeStateStatus = "DIRTY"
			c.setup(d, t)
			red := d.runRed(t)
			got := d.redAsks()
			if c.want == "" {
				if red.Action != "" || len(got) != 0 {
					t.Fatalf("the act made %+v and filed %q, want nothing", red, got)
				}
				return
			}
			is(t, red, pr.ActAsked)
			if !slices.Equal(got, []string{c.want}) {
				t.Fatalf("the act filed %q, want %q", got, c.want)
			}
		})
	}
}

// redFirst orders a run's acts with the red-check and conflict act first.
func redFirst(ids []string) {
	for i, id := range ids {
		if id == "red "+bead {
			ids[0], ids[i] = ids[i], ids[0]
			return
		}
	}
}

// A hold set by hand or a human gate keeps the act from filing an ask for a
// red check, and a conflicting PR's red checks wait for the merge that brings
// it current.
func TestAHeldOrConflictingPRGetsNoRedCheckAsk(t *testing.T) {
	for name, setup := range map[string]func(*redWorld, *testing.T){
		"a merge hold": func(d *redWorld, t *testing.T) {
			d.edit(t, func(b *fake.Bead) { b.Metadata["merge_hold"] = "operator" })
		},
		"a human gate": func(d *redWorld, t *testing.T) { d.gateOn(t, "tk-g1", "pr-fix-capped.7") },
		"an unapproved conflict": func(d *redWorld, _ *testing.T) {
			d.pr.Facts.MergeStateStatus = "DIRTY"
			d.unapprove()
		},
	} {
		t.Run(name, func(t *testing.T) {
			d := newRed(t)
			d.checks(t, "COMPLETED", testsRun, 1, check("test", "FAILURE"), check("test-macos", "SUCCESS"))
			setup(d, t)
			if red := d.runRed(t); red.Action != "" || len(d.redAsks()) != 0 {
				t.Fatalf("the act made %+v and filed %q", red, d.redAsks())
			}
		})
	}
}

// A changed head waits for the refinery's validation: its red checks get no
// ask, and the red-check gates on it are still withdrawn once its checks pass.
func TestAChangedHeadGetsOnlyTheWithdrawal(t *testing.T) {
	d := newRed(t)
	d.edit(t, func(b *fake.Bead) {
		b.Status, b.Assignee = "open", boundRefinery
		b.Metadata["merge_result"] = "pull_request_head_changed"
		b.Metadata["observed_pr_head_sha"] = other
		delete(b.Metadata, "pr_reconcile_pending")
	})
	d.pr.Facts.HeadRefOid = other
	d.pr.Suites[other] = []gh.CheckSuite{{ID: 3, Status: "COMPLETED", CreatedAt: suiteCreated, Run: 103, Attempt: 1,
		Runs: []gh.CheckRun{check("test", "FAILURE")}}}
	d.refresh(t)
	red, _ := redOutcome(t, d.reconcile(t, pr.Options{}))
	if red.Action != "" || len(d.redAsks()) != 0 {
		t.Fatalf("a changed head made %+v and filed %q", red, d.redAsks())
	}
	d.gateOn(t, "tk-g1", "pr-fix-unmoved.7")
	d.pr.Suites[other][0].Runs = []gh.CheckRun{check("test", "SUCCESS")}
	d.refresh(t)
	red, _ = redOutcome(t, d.reconcile(t, pr.Options{}))
	is(t, red, pr.ActWithdrawn)
}
