package reaction

import (
	"errors"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	ghfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh/fake"
)

// unplaced makes the subject a bead with no parent, which intake holds.
func unplaced(w *world) { w.subject(func(b *fake.Bead) { b.Edges = nil }) }

// An unplaced subject is released with no route and nothing waiting, then
// noted, then held with Gas City's hold:mayor as the exit's last write, through
// set-state with intake's reason; the route it never writes is not probed, and
// GitHub is not read with no emergency claimed.
func TestIntakeHoldsAnUnplacedSubject(t *testing.T) {
	w := newWorld(t)
	unplaced(w)
	code, out, err := w.dispose("tk-sub", "--disposition", "actionable", "--reason", "states a done condition and a branch",
		"--takeaway", "ready to build once placed", "--route", "gc-toolkit/gc-toolkit.polecat", "--run", root)
	wantCode(t, code, 0, err, "(INTAKE) an unplaced subject's actionable exit")
	states := w.store.States()
	if len(states) != 1 || states[0].Dimension != "hold" || states[0].Value != "mayor" ||
		!strings.HasPrefix(states[0].Reason, "Held for placement instead of reaching gc-toolkit/gc-toolkit.polecat: tk-sub has no parent epic and is not PR-finishing work") {
		t.Fatalf("(INTAKE) the holds were %+v", states)
	}
	w.has("HELM takeaway tk-sub ready to build once placed --by proactive --release --no-wait", "(INTAKE) released with no route, nothing waiting")
	w.hasnt("--route", "(INTAKE) no pool is offered it")
	w.has("## Intake (first reaction, 2026-11-16T12:00:00Z)", "(INTAKE) it is noted")
	w.has("gc beads list --label hold:mayor lists it", "(INTAKENOTE) the note names the queue's read")
	w.before("HELM takeaway", "## Intake (first reaction", "(INTAKEORDER) the release first")
	w.before("## Intake (first reaction", "SET-STATE", "(INTAKEORDER) then the note")
	if wr := w.writes(); !strings.HasPrefix(wr[len(wr)-1], "SET-STATE tk-sub hold=mayor") {
		t.Errorf("(INTAKEORDER) the last write was %q, want the hold", wr[len(wr)-1])
	}
	if out != "tk-sub disposed as actionable (held for placement)" {
		t.Errorf("(INTAKE) the exit reported %q", out)
	}
	if slices.Contains(w.rt.Reads(), "roster") {
		t.Errorf("(INTAKEPOOL) the route it never writes was probed: %q", w.rt.Reads())
	}
	if r := w.gh.Reads(); len(r) != 0 {
		t.Errorf("(INTAKE) GitHub was read with no emergency claimed: %q", r)
	}

	w = newWorld(t)
	w.store.Put(fake.Bead{ID: "tk-rl", Title: "an epic it waits on", Status: "open", IssueType: "epic"})
	w.subject(func(b *fake.Bead) { b.Edges = []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "tk-rl", Status: "open"}} })
	code, _, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--route", "gc-toolkit/gc-toolkit.polecat", "--run", root)
	wantCode(t, code, 0, err, "(INTAKEMEMBER) a subject that waits on an epic")
	w.has("SET-STATE tk-sub hold=mayor", "(INTAKEMEMBER) a blocks edge onto an epic is not membership")

	w = newWorld(t)
	w.subject(func(b *fake.Bead) { b.Edges = nil; b.Metadata = map[string]string{"anchor_bead": "tk-anchor"} })
	code, _, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--route", "gc-toolkit/gc-toolkit.polecat", "--run", root)
	wantCode(t, code, 0, err, "(INTAKEANCHOR) PR-finishing work")
	w.has("--release --route gc-toolkit/gc-toolkit.polecat --no-wait", "(INTAKEANCHOR) it is routed")
	w.hasnt("SET-STATE", "(INTAKEANCHOR) unheld")

	w = newWorld(t)
	unplaced(w)
	w.store.StateErr = errors.New("gc bd set-state exited 1: the store refused it")
	code, out, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--route", "gc-toolkit/gc-toolkit.polecat", "--run", root)
	wantCode(t, code, 4, err, "(INTAKEMARK) a hold the store refuses")
	errHas(t, err, "the hold:mayor label did not", "(INTAKEMARK) naming the refused write")
	w.has("HELM takeaway tk-sub", "(INTAKEMARK) after the release, which stands")
	if out != "" {
		t.Errorf("(INTAKEMARK) the exit reported %q", out)
	}
	w.store.StateErr = nil
	w.reset()
	code, _, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--route", "gc-toolkit/gc-toolkit.polecat", "--run", root)
	wantCode(t, code, 0, err, "(INTAKEMARK) the re-run")
	w.before("HELM takeaway", "SET-STATE tk-sub hold=mayor", "(INTAKEMARK) releasing again, then holding")

	w = newWorld(t)
	unplaced(w)
	w.store.BeforeUpdate = func(id string, args []string) error {
		if strings.Contains(strings.Join(args, " "), "## Intake") {
			return errors.New("the store refused it")
		}
		return nil
	}
	code, _, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--route", "gc-toolkit/gc-toolkit.polecat", "--run", root)
	wantCode(t, code, 4, err, "(INTAKEMARK) a note the store refuses")
	errHas(t, err, "intake's note saying why it holds tk-sub did not", "(INTAKEMARK) naming the note")
	w.hasnt("SET-STATE", "(INTAKEMARK) before the hold")

	w = newWorld(t)
	unplaced(w)
	w.helmFails = true
	code, _, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--route", "gc-toolkit/gc-toolkit.polecat", "--run", root)
	wantCode(t, code, 4, err, "(INTAKESTAMP) a held subject whose release the store refuses")
	errHas(t, err, "gc-helm.sh takeaway failed on tk-sub", "(INTAKESTAMP) naming the release")
	w.hasnt("SET-STATE", "(INTAKESTAMP) before the hold")

	w = newWorld(t)
	unplaced(w)
	code, out, err = w.dispose("tk-sub", "--disposition", "blocked", "--reason", "waits on the migration", "--takeaway", "held: migration first",
		"--waiting-on", "tk-blk1", "--then-route", "gc-toolkit/gc-toolkit.polecat", "--run", root)
	wantCode(t, code, 0, err, "(INTAKEBLK) an unplaced blocked subject")
	w.has("SET-STATE tk-sub hold=mayor", "(INTAKEBLK) held for placement")
	w.has("--release --waiting-on tk-blk1", "(INTAKEBLK) its wait still an edge")
	w.before("HELM takeaway", "SET-STATE", "(INTAKEBLK) the hold after the wait")
	w.hasnt("ARM ", "(INTAKEBLK) no dispatch armed")
	if slices.Contains(w.rt.Reads(), "roster") {
		t.Errorf("(INTAKEBLK) the then-route was probed: %q", w.rt.Reads())
	}
	if out != "tk-sub disposed as blocked (tk-blk1; held for placement)" {
		t.Errorf("(INTAKEBLK) the exit reported %q", out)
	}
}

// An emergency is checked, not asserted: its claim admits the bead at P0, the
// priority written before the route or the arm, only when the check it names
// fails at the head of the default branch of the subject's repository. A green
// main, another check failing, a check main does not carry, or a check that
// cannot run confirms nothing, and the bead is held with a note saying what
// the check found.
func TestAnEmergencyIsCheckedNotAsserted(t *testing.T) {
	w := newWorld(t)
	unplaced(w)
	w.red()
	code, out, err := w.dispose("tk-sub", "--disposition", "actionable", "--reason", "test-macos fails on main", "--takeaway", "fix red main",
		"--route", "gc-toolkit/gc-toolkit.polecat", "--emergency", "test-macos", "--run", root)
	wantCode(t, code, 0, err, "(EMERG) a confirmed emergency's actionable exit")
	w.has("UPDATE tk-sub --priority 0 --append-notes ## Intake (first reaction, 2026-11-16T12:00:00Z)\nRouted to gc-toolkit/gc-toolkit.polecat at P0 as an emergency: main of zook/repo at abcdef123456 is red: test-macos (failure).",
		"(EMERG) P0 is written, with a note naming the head and the failing check")
	w.before("--priority 0", "HELM takeaway", "(EMERG) before the route")
	w.has("--release --route gc-toolkit/gc-toolkit.polecat --no-wait", "(EMERG) the bead is routed")
	w.hasnt("SET-STATE", "(EMERG) unheld")
	if out != "tk-sub disposed as actionable (gc-toolkit/gc-toolkit.polecat at P0)" {
		t.Errorf("(EMERG) the exit reported %q", out)
	}

	w = newWorld(t)
	unplaced(w)
	w.red()
	w.gh.Repos["zook/repo"].Checks["main"].Statuses = []gh.CommitStatus{{Context: "ci/legacy", State: "failure"}}
	code, _, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--route", "gc-toolkit/gc-toolkit.polecat", "--emergency", "ci/legacy", "--run", root)
	wantCode(t, code, 0, err, "(EMERGSTATUS) a failing commit status")
	w.has("--priority 0", "(EMERGSTATUS) confirms an emergency")
	w.has("ci/legacy (failure)", "(EMERGSTATUS) named in the note")

	w = newWorld(t)
	w.red()
	code, _, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--route", "gc-toolkit/gc-toolkit.polecat", "--emergency", "test-macos", "--run", root)
	wantCode(t, code, 0, err, "(EMERGMEMBER) a member claimed as an emergency")
	w.has("--priority 0", "(EMERGMEMBER) is written P0")

	green := func(w *world) {
		w.red()
		w.gh.Repos["zook/repo"].Checks["main"].Runs[1].Conclusion = "cancelled"
	}
	w = newWorld(t)
	unplaced(w)
	green(w)
	code, _, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--route", "gc-toolkit/gc-toolkit.polecat", "--emergency", "test-macos", "--run", root)
	wantCode(t, code, 0, err, "(EMERGNO) an unconfirmed emergency")
	w.has("SET-STATE tk-sub hold=mayor", "(EMERGNO) held for placement")
	w.hasnt("--priority", "(EMERGNO) at its own priority")
	w.hasnt("--route", "(EMERGNO) unrouted")
	w.has("--emergency was not confirmed: test-macos is not failing on main of zook/repo at abcdef123456", "(EMERGNO) the note says what the check found")
	w.hasnt("other checks failing", "(EMERGNO) naming no other failing check")
	w = newWorld(t)
	green(w)
	code, _, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--route", "gc-toolkit/gc-toolkit.polecat", "--emergency", "test-macos", "--run", root)
	wantCode(t, code, 0, err, "(EMERGNO) an unconfirmed emergency on a member")
	w.has("--release --route gc-toolkit/gc-toolkit.polecat", "(EMERGNO) routes as a member")
	w.hasnt("--priority", "(EMERGNO) at its own priority")

	w = newWorld(t)
	unplaced(w)
	w.red()
	code, _, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--route", "gc-toolkit/gc-toolkit.polecat", "--emergency", "lint", "--run", root)
	wantCode(t, code, 0, err, "(EMERGOTHER) a claim on a passing check")
	w.has("--emergency was not confirmed: lint is not failing on main of zook/repo at abcdef123456; other checks failing there: test-macos (failure)", "(EMERGOTHER) naming what does fail")
	w.has("SET-STATE tk-sub hold=mayor", "(EMERGOTHER) held")
	w = newWorld(t)
	unplaced(w)
	w.red()
	code, _, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--route", "gc-toolkit/gc-toolkit.polecat", "--emergency", "test-windows", "--run", root)
	wantCode(t, code, 0, err, "(EMERGOTHER) a claim on a check main does not carry")
	w.has("main of zook/repo at abcdef123456 has no check named test-windows; other checks failing there: test-macos (failure)", "(EMERGOTHER) saying no such check runs there")

	w = newWorld(t)
	unplaced(w)
	w.red()
	w.gh.Fail["DefaultBranch"] = errors.New("gh: HTTP 502")
	code, _, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--route", "gc-toolkit/gc-toolkit.polecat", "--emergency", "test-macos", "--run", root)
	wantCode(t, code, 0, err, "(EMERGDOWN) a GitHub that does not answer")
	w.has("SET-STATE tk-sub hold=mayor", "(EMERGDOWN) held, since an unread check confirms nothing")
	w.has("GitHub did not answer for the default branch of zook/repo (gh: HTTP 502)", "(EMERGDOWN) the note says so")

	w = newWorld(t)
	unplaced(w)
	w.red()
	w.gh.Fail["HeadChecks"] = errors.New("gh: GitHub did not answer within 20s")
	code, _, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--route", "gc-toolkit/gc-toolkit.polecat", "--emergency", "test-macos", "--run", root)
	wantCode(t, code, 0, err, "(EMERGSLOW) a GitHub that runs out of time")
	w.has("GitHub did not answer for the checks on main of zook/repo (gh: GitHub did not answer within 20s)", "(EMERGSLOW) the note says the read ran out of time")
	w.has("SET-STATE tk-sub hold=mayor", "(EMERGSLOW) held")

	w = newWorld(t)
	unplaced(w)
	w.red()
	w.origin = ""
	code, _, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--route", "gc-toolkit/gc-toolkit.polecat", "--emergency", "test-macos", "--run", root)
	wantCode(t, code, 0, err, "(EMERGDOWN) a checkout with no origin")
	w.has("is not a GitHub repository", "(EMERGDOWN) the note names why")
	if r := w.gh.Reads(); len(r) != 0 {
		t.Errorf("(EMERGDOWN) GitHub was asked about a repository nobody named: %q", r)
	}
	for _, url := range []string{"https://github.com/zook/repo", "ssh://git@github.com/zook/repo.git", "https://github.com/zook/repo/"} {
		w := newWorld(t)
		unplaced(w)
		w.red()
		w.origin = url
		code, _, err := w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--route", "gc-toolkit/gc-toolkit.polecat", "--emergency", "test-macos", "--run", root)
		wantCode(t, code, 0, err, "(EMERGPAGE) an origin of "+url)
		w.has("--priority 0", "(EMERG) the origin "+url+" names zook/repo")
	}

	w = newWorld(t)
	unplaced(w)
	w.red()
	w.store.BeforeUpdate = func(id string, args []string) error {
		if slices.Contains(args, "--priority") {
			return errors.New("the store refused it")
		}
		return nil
	}
	code, _, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--route", "gc-toolkit/gc-toolkit.polecat", "--emergency", "test-macos", "--run", root)
	wantCode(t, code, 4, err, "(EMERGPRIO) a P0 the store refuses")
	errHas(t, err, "could not write priority P0 on tk-sub", "(EMERGPRIO) naming the write")
	w.hasnt("HELM takeaway", "(EMERGPRIO) before the route")

	w = newWorld(t)
	unplaced(w)
	w.red()
	code, out, err = w.dispose("tk-sub", "--disposition", "blocked", "--reason", "r", "--takeaway", "t", "--waiting-on", "tk-blk1",
		"--then-route", "gc-toolkit/gc-toolkit.polecat", "--emergency", "test-macos", "--run", root)
	wantCode(t, code, 0, err, "(EMERGBLK) a blocked emergency")
	w.before("--priority 0", "ARM ", "(EMERGBLK) P0 before the arm")
	w.has("ARM tk-sub --target gc-toolkit/gc-toolkit.polecat", "(EMERGBLK) and the dispatch armed")
	if out != "tk-sub disposed as blocked (tk-blk1; armed at P0)" {
		t.Errorf("(EMERGBLK) the exit reported %q", out)
	}

	for name, args := range map[string][]string{
		"--emergency beside --assign":           {"--disposition", "actionable", "--assign", "gc-toolkit.mechanik", "--emergency", "test-macos"},
		"--emergency on a blocked exit unarmed": {"--disposition", "blocked", "--waiting-on", "tk-blk1", "--emergency", "test-macos"},
		"close --emergency":                     {"--disposition", "close", "--emergency", "test-macos"},
		"ruling --emergency":                    {"--disposition", "ruling", "--emergency", "test-macos"},
		"an empty --emergency":                  {"--disposition", "actionable", "--emergency", ""},
		"a blank --emergency":                   {"--disposition", "actionable", "--emergency", "  "},
	} {
		w := newWorld(t)
		code, _, err := w.dispose(append([]string{"tk-sub", "--reason", "r", "--takeaway", "t", "--run", root}, args...)...)
		wantCode(t, code, 2, err, "(EMERGARGS) "+name)
		if len(w.log) != 0 {
			t.Errorf("(EMERGARGS) %s read or wrote %q", name, w.log)
		}
	}
	w = newWorld(t)
	_, _, err = w.dispose("tk-sub", "--reason", "r", "--takeaway", "t", "--disposition", "actionable", "--emergency", " ")
	errHas(t, err, "needs the name of the check that fails on main", "(EMERGARGS) saying what it needs")
}

// The checks the emergency reads are GitHub's whole answer, so a failure past
// the first page confirms, as the adapter reads every page.
func TestAnEmergencyReadsEveryCheck(t *testing.T) {
	w := newWorld(t)
	unplaced(w)
	w.origin = "git@github.com:zook/repo.git"
	w.gh.Repos["zook/repo"] = &ghfake.Repo{DefaultBranch: "trunk", Checks: map[string]*gh.HeadChecks{"trunk": {
		Runs: []gh.RefCheckRun{{Name: "lint", Conclusion: "success", HeadSHA: "0123456789abcdef"}, {Name: "test-e2e", Conclusion: "timed_out", HeadSHA: "0123456789abcdef"}},
	}}}
	code, _, err := w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--route", "gc-toolkit/gc-toolkit.polecat", "--emergency", "test-e2e", "--run", root)
	wantCode(t, code, 0, err, "(EMERGPAGE) a timed-out run on the default branch")
	w.has("trunk of zook/repo at 0123456789ab is red: test-e2e (timed_out)", "(EMERGPAGE) confirms, at the head the runs name")
}

// The po takes no work by assignment, bare or qualified, and the refusal comes
// before any read or write, naming the pool flag that does the job; an agent
// whose name only ends in po is not the po.
func TestThePoTakesNoWorkByAssignment(t *testing.T) {
	for _, who := range []string{"gc-toolkit.po", "po", "gc-toolkit/gc-toolkit.po"} {
		w := newWorld(t)
		code, _, err := w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--assign", who, "--run", root)
		wantCode(t, code, 2, err, "(PO) --assign "+who)
		errHas(t, err, "--assign "+who+" names the po, which takes no work by assignment", "(PO) saying why")
		if len(w.log) != 0 {
			t.Errorf("(PO) --assign %s read or wrote %q", who, w.log)
		}
	}
	w := newWorld(t)
	code, _, err := w.dispose("tk-sub", "--disposition", "blocked", "--reason", "r", "--takeaway", "t", "--waiting-on", "tk-blk1", "--then-assign", "gc-toolkit.po", "--run", root)
	wantCode(t, code, 2, err, "(PO) --then-assign naming the po")
	errHas(t, err, "--then-assign gc-toolkit.po names the po", "(PO) naming the flag")
	errHas(t, err, "Pass --then-route", "(PO) and the pool flag that does the job")
	w = newWorld(t)
	_, _, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--assign", "gc-toolkit.polecat-po", "--run", root)
	if err != nil && strings.Contains(err.Error(), "names the po") {
		t.Errorf("(PO) an agent whose name ends in po was taken for the po: %v", err)
	}
}

// One dispose reads the city's rig list once, however many of its rules ask
// which rig owns a store.
func TestADisposeReadsTheRigListOnce(t *testing.T) {
	w := newWorld(t)
	w.red()
	unplaced(w)
	code, _, err := w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--route", "gc-toolkit/gc-toolkit.polecat", "--emergency", "test-macos", "--run", root)
	wantCode(t, code, 0, err, "an emergency routed to a pool")
	n := 0
	for _, r := range w.rt.Reads() {
		if r == "rigs" {
			n++
		}
	}
	if n == 0 {
		t.Fatalf("the dispose read no rig list: %q", w.rt.Reads())
	}
}
