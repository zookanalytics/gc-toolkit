package reaction

import (
	"errors"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
)

// held makes the subject a bead its filer held for placement, with each label
// given, hold:mayor when none is.
func held(w *world, labels ...string) {
	if len(labels) == 0 {
		labels = []string{"hold:mayor"}
	}
	w.subject(func(b *fake.Bead) { b.Labels = labels })
}

// stillHeld fails the test unless the subject still carries its hold, with no
// set-state written and no hold lifted.
func stillHeld(w *world, what string) {
	w.t.Helper()
	s, _ := w.store.Row("tk-sub")
	if !slices.Contains(s.Labels, "hold:mayor") {
		w.t.Errorf("%s: the subject's labels are %v; want it still held", what, s.Labels)
	}
	w.hasnt("SET-STATE", what+": no hold is written over the filer's")
	w.hasnt("--remove-label", what+": the hold is not lifted")
}

// A subject that arrived held stays in the placement queue whatever the exit
// would route, since its placement is the po's and the operator's: an
// actionable exit routes a member, PR-finishing work and a failure's tracker
// nowhere, and a blocked exit arms no --then-route. The exit writes the
// headline and the release and leaves the hold its filer wrote, with no
// intake note, since the hold is the filer's.
func TestAnArrivalStaysHeldForPlacement(t *testing.T) {
	for name, edit := range map[string]func(*fake.Bead){
		"a member":            nil,
		"PR-finishing work":   func(b *fake.Bead) { b.Edges = nil; b.Metadata = map[string]string{"anchor_bead": "tk-anchor"} },
		"a failure's tracker": func(b *fake.Bead) { b.Edges = nil; b.Metadata = map[string]string{"failure_key": "TestReconcile"} },
	} {
		w := newWorld(t)
		held(w)
		if edit != nil {
			w.subject(edit)
		}
		code, out, err := w.dispose("tk-sub", "--disposition", "actionable", "--reason", "states a done condition", "--takeaway", "ready to build once placed",
			"--route", "gc-toolkit/gc-toolkit.polecat", "--run", root)
		wantCode(t, code, 0, err, "(ARRIVAL) "+name)
		w.has("TAKEAWAY tk-sub ready to build once placed --by proactive --release --no-wait", "(ARRIVAL) "+name+": released with no route")
		w.hasnt("--route", "(ARRIVAL) "+name+": no pool is offered it")
		w.hasnt("## Intake", "(ARRIVAL) "+name+": no intake note")
		stillHeld(w, "(ARRIVAL) "+name)
		w.saidHas("intake leaves tk-sub held for placement instead of gc-toolkit/gc-toolkit.polecat: it arrived held", "(ARRIVAL) "+name+": saying so")
		if out != "tk-sub disposed as actionable (held for placement)" {
			t.Errorf("(ARRIVAL) %s: the exit reported %q", name, out)
		}
	}

	w := newWorld(t)
	held(w, "learning", " Hold:Mayor")
	code, out, err := w.dispose("tk-sub", "--disposition", "blocked", "--reason", "waits on the migration", "--takeaway", "held: migration first",
		"--waiting-on", "tk-blk1", "--then-route", "gc-toolkit/gc-toolkit.polecat", "--run", root)
	wantCode(t, code, 0, err, "(ARRIVALBLK) a blocked arrival")
	w.has("TAKEAWAY tk-sub held: migration first --by proactive --release --waiting-on tk-blk1", "(ARRIVALBLK) its wait an edge")
	w.hasnt("ARM ", "(ARRIVALBLK) no dispatch armed")
	w.hasnt("SET-STATE", "(ARRIVALBLK) no hold written")
	w.hasnt("--remove-label", "(ARRIVALBLK) its hold, in any spelling, not lifted")
	if out != "tk-sub disposed as blocked (tk-blk1; held for placement)" {
		t.Errorf("(ARRIVALBLK) the exit reported %q", out)
	}
	w = newWorld(t)
	held(w)
	code, _, err = w.dispose("tk-sub", "--disposition", "blocked", "--reason", "r", "--takeaway", "t", "--waiting-on", "tk-blk1", "--run", root)
	wantCode(t, code, 0, err, "(ARRIVALBLK) a blocked arrival with no --then-route")
	stillHeld(w, "(ARRIVALBLK) with no --then-route")
	w.hasnt("ARM ", "(ARRIVALBLK) with no --then-route, no dispatch armed")

	// An emergency its check does not confirm leaves the arrival held, with
	// intake's note saying what the check found, which nothing else records.
	w = newWorld(t)
	held(w)
	w.red()
	w.gh.Repos["zook/repo"].Checks["main"].Runs[1].Conclusion = "success"
	code, _, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--route", "gc-toolkit/gc-toolkit.polecat",
		"--emergency", "test-macos", "--run", root)
	wantCode(t, code, 0, err, "(ARRIVALEMERGNO) an unconfirmed emergency on an arrival")
	w.has("## Intake (first reaction, 2026-11-16T12:00:00Z)\nLeft held for placement instead of reaching gc-toolkit/gc-toolkit.polecat: --emergency was not confirmed: test-macos is not failing",
		"(ARRIVALEMERGNO) the note says what the check found")
	w.before("TAKEAWAY", "## Intake", "(ARRIVALEMERGNO) after the release")
	w.hasnt("--priority", "(ARRIVALEMERGNO) at its own priority")
	stillHeld(w, "(ARRIVALEMERGNO)")

	w = newWorld(t)
	held(w)
	w.red()
	w.gh.Repos["zook/repo"].Checks["main"].Runs[1].Conclusion = "success"
	w.store.BeforeUpdate = func(id string, args []string) error {
		if strings.Contains(strings.Join(args, " "), "## Intake") {
			return errors.New("the store refused it")
		}
		return nil
	}
	code, _, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--route", "gc-toolkit/gc-toolkit.polecat",
		"--emergency", "test-macos", "--run", root)
	wantCode(t, code, 4, err, "(ARRIVALEMERGNO) a note the store refuses")
	errHas(t, err, "intake's note saying why the emergency was not confirmed did not", "(ARRIVALEMERGNO) naming the note")
}

// A confirmed emergency is the one arrival a pool takes: the actionable exit
// routes it at P0, which the takeaway's route lifts the hold for, and the
// blocked exit lifts the hold before it arms the dispatch, since the
// deferred-dispatch pass fires no arm on a held bead.
func TestAnArrivalsEmergencyLeavesTheQueue(t *testing.T) {
	w := newWorld(t)
	held(w)
	w.red()
	code, out, err := w.dispose("tk-sub", "--disposition", "actionable", "--reason", "test-macos fails on main", "--takeaway", "fix red main",
		"--route", "gc-toolkit/gc-toolkit.polecat", "--emergency", "test-macos", "--run", root)
	wantCode(t, code, 0, err, "(ARRIVALEMERG) a confirmed emergency on an arrival")
	w.has("--priority 0", "(ARRIVALEMERG) written P0")
	w.has("--release --route gc-toolkit/gc-toolkit.polecat --no-wait", "(ARRIVALEMERG) routed by the takeaway, whose release lifts the hold")
	w.hasnt("SET-STATE", "(ARRIVALEMERG) no hold written")
	if out != "tk-sub disposed as actionable (gc-toolkit/gc-toolkit.polecat at P0)" {
		t.Errorf("(ARRIVALEMERG) the exit reported %q", out)
	}

	w = newWorld(t)
	held(w, "hold:mayor", "HOLD:MAYOR ")
	w.red()
	code, out, err = w.dispose("tk-sub", "--disposition", "blocked", "--reason", "r", "--takeaway", "t", "--waiting-on", "tk-blk1",
		"--then-route", "gc-toolkit/gc-toolkit.polecat", "--emergency", "test-macos", "--run", root)
	wantCode(t, code, 0, err, "(ARRIVALEMERGBLK) a blocked emergency on an arrival")
	w.has("UPDATE tk-sub --remove-label hold:mayor --remove-label HOLD:MAYOR ", "(ARRIVALEMERGBLK) every spelling lifted in one write")
	w.before("TAKEAWAY", "--remove-label", "(ARRIVALEMERGBLK) after the release")
	w.before("--remove-label", "ARM tk-sub --target gc-toolkit/gc-toolkit.polecat", "(ARRIVALEMERGBLK) before the arm")
	if s, _ := w.store.Row("tk-sub"); len(s.Labels) != 0 {
		t.Errorf("(ARRIVALEMERGBLK) the subject still carries %v", s.Labels)
	}
	if out != "tk-sub disposed as blocked (tk-blk1; armed at P0)" {
		t.Errorf("(ARRIVALEMERGBLK) the exit reported %q", out)
	}
}

// A hand-off of a named agent's own work takes an arrival out of the queue, since
// Gas City serves a held bead to no hook: the refinery's assignee rides the
// takeaway's release, which lifts the hold of a bead it sends on, and the
// mechanik's route is the exit's own sling, so the exit lifts the hold before
// it. A lift the store refuses stops the exit before the hand-off.
func TestAnArrivalsHandOffLiftsItsHold(t *testing.T) {
	w := newWorld(t)
	held(w)
	code, _, err := w.dispose("tk-sub", "--disposition", "actionable", "--reason", "a city.toml edit", "--takeaway", "city.toml edit for mechanik",
		"--assign", "gc-toolkit.mechanik", "--run", root)
	wantCode(t, code, 0, err, "(ARRIVALHANDOFF) an arrival handed to the mechanik")
	w.has("UPDATE tk-sub --remove-label hold:mayor", "(ARRIVALHANDOFF) the hold is lifted")
	w.before("TAKEAWAY", "--remove-label", "(ARRIVALHANDOFF) after the release")
	w.before("--remove-label", "SLING gc-toolkit.mechanik tk-sub --no-formula", "(ARRIVALHANDOFF) before the hand-off")
	w.saidHas("lifted hold:mayor from tk-sub for the hand-off to gc-toolkit.mechanik", "(ARRIVALHANDOFF) saying so")

	w = newWorld(t)
	held(w)
	code, _, err = w.dispose("tk-sub", "--disposition", "blocked", "--reason", "r", "--takeaway", "t", "--waiting-on", "tk-blk1",
		"--then-assign", "gc-toolkit.mechanik", "--run", root)
	wantCode(t, code, 0, err, "(ARRIVALHANDOFF) a blocked arrival handed to the mechanik")
	w.before("--remove-label", "SLING gc-toolkit.mechanik tk-sub --no-formula", "(ARRIVALHANDOFF) blocked: lifted before the hand-off")

	w = newWorld(t)
	held(w)
	code, _, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--assign", "gc-toolkit/gc-toolkit.refinery", "--run", root)
	wantCode(t, code, 0, err, "(ARRIVALHANDOFF) an arrival handed to the refinery")
	w.has("--release --assign gc-toolkit/gc-toolkit.refinery", "(ARRIVALHANDOFF) the takeaway assigns it, lifting the hold")
	w.hasnt("--remove-label", "(ARRIVALHANDOFF) the exit lifts nothing itself")

	w = newWorld(t)
	held(w)
	w.store.BeforeUpdate = func(id string, args []string) error {
		if slices.Contains(args, "--remove-label") {
			return errors.New("the store refused it")
		}
		return nil
	}
	code, _, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--assign", "gc-toolkit.mechanik", "--run", root)
	wantCode(t, code, 4, err, "(ARRIVALLIFT) a lift the store refuses")
	errHas(t, err, "hold:mayor was not lifted for the hand-off to gc-toolkit.mechanik (", "(ARRIVALLIFT) naming the lift")
	errHas(t, err, "a re-run resumes rather than refusing", "(ARRIVALLIFT) and the re-run")
	w.hasnt("SLING ", "(ARRIVALLIFT) no hand-off")

	// The re-offered worker of the same run meets a held subject that carries
	// the run's headline and its card, which its check passes, and the re-run
	// finishes the exit.
	w.subject(func(b *fake.Bead) { b.Notes = "# First reaction · run " + root + " · a city.toml edit" })
	w.store.BeforeUpdate = nil
	if code, said := w.check("tk-sub", root); code != 0 {
		t.Fatalf("(ARRIVALREOFFER) the re-offered check exits %d saying %q", code, said)
	}
	w.reset()
	code, _, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--assign", "gc-toolkit.mechanik", "--run", root)
	wantCode(t, code, 0, err, "(ARRIVALREOFFER) the re-run")
	w.before("--remove-label", "SLING gc-toolkit.mechanik tk-sub --no-formula", "(ARRIVALREOFFER) the re-run lifts the hold, then hands it over")
}

// The close exit hands an arrival to its validating closer, its next actor, so
// it lifts the hold before the closer is sent: before the sling of a closer
// that runs now, and after the holds and before the arm of one that waits,
// since the deferred-dispatch pass fires no arm on a held bead.
func TestAnArrivalsCloseLiftsItsHold(t *testing.T) {
	w := newWorld(t)
	held(w)
	code, _, err := w.dispose("tk-sub", "--disposition", "close", "--reason", "already fixed", "--takeaway", "close: fixed in #123", "--run", root)
	wantCode(t, code, 0, err, "(ARRIVALCLOSE) an arrival's close")
	w.before("TAKEAWAY", "--remove-label hold:mayor", "(ARRIVALCLOSE) after the headline")
	w.before("--remove-label hold:mayor", "SLING gc-toolkit/gc-toolkit.polecat tk-sub --on mol-validate-close", "(ARRIVALCLOSE) before the closer")

	w = newWorld(t)
	held(w)
	code, _, err = w.dispose("tk-sub", "--disposition", "close", "--reason", "its code retires", "--takeaway", "close once tk-blk1 lands",
		"--waiting-on", "tk-blk1", "--run", root)
	wantCode(t, code, 0, err, "(ARRIVALCLOSEWAIT) an arrival's close that waits")
	w.before("DEP-ADD", "--remove-label hold:mayor", "(ARRIVALCLOSEWAIT) after the hold on the bead it waits for")
	w.before("--remove-label hold:mayor", "ARM tk-sub --target gc-toolkit/gc-toolkit.polecat --on mol-validate-close", "(ARRIVALCLOSEWAIT) before the arm")

	w = newWorld(t)
	code, _, err = w.dispose("tk-sub", "--disposition", "close", "--reason", "r", "--takeaway", "t", "--run", root)
	wantCode(t, code, 0, err, "(CLOSE) a close of a bead that did not arrive held")
	w.hasnt("--remove-label", "(CLOSE) lifts nothing")
}

// A subject a placement or an Accept sent on while its first reaction ran
// carries a dispatch the check took it without: a live run of another
// formula, a route, an arm or an assignee. The exit then lands the headline
// alone, since a release would end that run, remove that arm and park the
// bead, and it writes no hold, route or arm of its own. The reaction's own run
// is no such dispatch.
func TestAnExitLeavesADispatchMadeWhileItRan(t *testing.T) {
	arm := map[string]string{"gc.dispatch_when_ready": "gc-toolkit/gc-toolkit.polecat", "gc.dispatch_when_ready_args": "[]",
		"gc.dispatch_when_ready_armed_by": "gc-toolkit/gc-toolkit.mechanik", "gc.dispatch_when_ready_armed_at": "2026-10-01T00:00:00Z"}
	for name, c := range map[string]struct {
		sendOn func(*world)
		sent   string
	}{
		"a placement's build": {func(w *world) {
			w.subject(func(b *fake.Bead) {
				b.Labels = nil
				b.Metadata = map[string]string{"gc.routed_to": "gc-toolkit/gc-toolkit.polecat"}
			})
			w.run("tk-build", "mol-polecat-work", "tk-sub", "in_progress")
		}, "gc.routed_to=gc-toolkit/gc-toolkit.polecat, live run tk-build"},
		"a placement's arm": {func(w *world) {
			w.subject(func(b *fake.Bead) { b.Labels = nil; b.Metadata = arm })
		}, "an arm to gc-toolkit/gc-toolkit.polecat"},
		"an Accept's build, hold kept": {func(w *world) {
			w.run("tk-accepted", "mol-x", "tk-sub", "in_progress")
		}, "live run tk-accepted"},
		"an assignee": {func(w *world) {
			w.subject(func(b *fake.Bead) { b.Assignee = "gc-toolkit.mechanik" })
		}, "assigned to gc-toolkit.mechanik"},
	} {
		w := newWorld(t)
		held(w)
		w.run(root, Formula, "tk-sub", "in_progress")
		c.sendOn(w)
		code, _, err := w.dispose("tk-sub", "--disposition", "actionable", "--reason", "states a done condition", "--takeaway", "ready to build",
			"--route", "gc-toolkit/gc-toolkit.polecat", "--run", root)
		wantCode(t, code, 0, err, "(SENT-ON) "+name)
		w.has("TAKEAWAY tk-sub ready to build --by proactive", "(SENT-ON) "+name+": the headline lands")
		w.hasnt("--release", "(SENT-ON) "+name+": nothing is released")
		w.hasnt("ARM ", "(SENT-ON) "+name+": nothing is armed")
		w.hasnt("SET-STATE", "(SENT-ON) "+name+": no hold is written")
		w.hasnt("SLING", "(SENT-ON) "+name+": nothing is routed")
		w.saidHas("tk-sub was sent on while this reaction ran ("+c.sent+"): its headline landed alone", "(SENT-ON) "+name+": saying what sent it")
	}
}

// An exit that stopped after its headline releases the acceptance lock, so a
// placement can send its subject on before the exit is run again, such as by
// arming it behind a wait. The re-run then lands the headline alone: under its
// headline, the one dispatch an exit reads as its own is its hand-off to the
// named agent it names.
func TestAReRunLeavesADispatchMadeAfterItsHeadline(t *testing.T) {
	for name, c := range map[string]struct {
		sendOn func(*fake.Bead)
		sent   string
	}{
		"a placement's arm": {func(b *fake.Bead) {
			b.Labels = nil
			b.Metadata["gc.dispatch_when_ready"] = "gc-toolkit/gc-toolkit.polecat"
			b.Metadata["gc.dispatch_when_ready_args"] = "[]"
			b.Metadata["gc.dispatch_when_ready_armed_by"] = "gc-toolkit/gc-toolkit.po"
			b.Metadata["gc.dispatch_when_ready_armed_at"] = "2026-11-16T11:00:00Z"
		}, "an arm to gc-toolkit/gc-toolkit.polecat"},
		"a route to a pool": {func(b *fake.Bead) { b.Labels = nil; b.Metadata["gc.routed_to"] = "gc-toolkit/gc-toolkit.polecat" },
			"gc.routed_to=gc-toolkit/gc-toolkit.polecat"},
		"another agent's assignee": {func(b *fake.Bead) { b.Labels = nil; b.Assignee = "gc-toolkit/gc-toolkit.refinery" },
			"assigned to gc-toolkit/gc-toolkit.refinery"},
	} {
		w := newWorld(t)
		held(w)
		w.store.BeforeUpdate = func(id string, args []string) error {
			if slices.Contains(args, "--remove-label") {
				return errors.New("the store refused it")
			}
			return nil
		}
		args := []string{"tk-sub", "--disposition", "actionable", "--reason", "a city.toml edit", "--takeaway", "city.toml edit for mechanik",
			"--assign", "gc-toolkit.mechanik", "--run", root}
		code, _, err := w.dispose(args...)
		wantCode(t, code, 4, err, "(RERUN) "+name+": a lift the store refuses")
		// The world's takeaway logs the headline the real one writes.
		w.subject(func(b *fake.Bead) {
			b.Metadata = map[string]string{"gc.takeaway": "city.toml edit for mechanik", "gc.takeaway_by": "proactive"}
		})
		w.store.BeforeUpdate = nil
		w.subject(c.sendOn)
		w.reset()
		code, _, err = w.dispose(args...)
		wantCode(t, code, 0, err, "(RERUN) "+name)
		w.has("TAKEAWAY tk-sub city.toml edit for mechanik --by proactive", "(RERUN) "+name+": the headline lands")
		w.hasnt("--release", "(RERUN) "+name+": nothing is released")
		w.hasnt("SLING", "(RERUN) "+name+": no hand-off")
		w.saidHas("tk-sub was sent on while this reaction ran ("+c.sent+"): its headline landed alone", "(RERUN) "+name+": saying what sent it")
	}
}

// A re-run of an exit that stopped after its own hand-off, at a nudge that did
// not reach the agent, finds the hand-off under its headline and finishes the
// exit. With no headline, the same hand-off is another actor's, since an exit
// writes its own after its headline.
func TestAReRunFinishesItsOwnHandOff(t *testing.T) {
	for name, c := range map[string]struct {
		assign string
		own    func(*fake.Bead)
		again  string
	}{
		"the refinery's assignee": {"gc-toolkit/gc-toolkit.refinery", func(b *fake.Bead) { b.Assignee = "gc-toolkit/gc-toolkit.refinery" },
			"TAKEAWAY tk-sub t --by proactive --release --assign gc-toolkit/gc-toolkit.refinery --no-wait"},
		"the mechanik's route": {"gc-toolkit.mechanik", func(b *fake.Bead) { b.Metadata["gc.routed_to"] = "gc-toolkit.mechanik" },
			"SLING gc-toolkit.mechanik tk-sub --no-formula --no-convoy"},
	} {
		args := []string{"tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--assign", c.assign, "--run", root}
		w := newWorld(t)
		w.nudgeFails = true
		code, _, err := w.dispose(args...)
		wantCode(t, code, 4, err, "(OWNHANDOFF) "+name+": a nudge that did not land")
		w.subject(func(b *fake.Bead) { b.Metadata = map[string]string{"gc.takeaway": "t", "gc.takeaway_by": "proactive"} })
		w.subject(c.own)
		w.nudgeFails = false
		w.reset()
		code, _, err = w.dispose(args...)
		wantCode(t, code, 0, err, "(OWNHANDOFF) "+name)
		w.has(c.again, "(OWNHANDOFF) "+name+": the hand-off made again")
		w.has("NUDGE "+c.assign+" tk-sub is ", "(OWNHANDOFF) "+name+": the nudge it owed")

		w = newWorld(t)
		w.subject(func(b *fake.Bead) { b.Metadata = map[string]string{} })
		w.subject(c.own)
		code, _, err = w.dispose(args...)
		wantCode(t, code, 0, err, "(OWNHANDOFF) "+name+" with no headline")
		w.hasnt("--release", "(OWNHANDOFF) "+name+" with no headline: nothing is released")
		w.hasnt("NUDGE", "(OWNHANDOFF) "+name+" with no headline: no nudge")
	}
}

// An exit holds the subject's acceptance lock, which a placement and an
// Accept hold too, and refuses with nothing read or written while one of them
// holds it.
func TestAnExitWaitsForTheAcceptanceLock(t *testing.T) {
	w := newWorld(t)
	held(w)
	unlock, holder, err := LockBead(w.rt, "tk-sub")
	if err != nil || unlock == nil {
		t.Fatalf("LockBead = %v, %q; want the lock", err, holder)
	}
	before := len(w.writes())
	code, _, err := w.dispose("tk-sub", "--disposition", "actionable", "--reason", "states a done condition", "--takeaway", "ready to build",
		"--route", "gc-toolkit/gc-toolkit.polecat", "--run", root)
	if code == 0 || err == nil || !strings.Contains(err.Error(), "holds its acceptance lock") || !strings.Contains(err.Error(), "wrote nothing") {
		t.Fatalf("an exit while the lock is held: code %d, %v; want it refused, naming the lock", code, err)
	}
	if got := w.writes()[before:]; len(got) != 0 {
		t.Errorf("an exit refused for the lock read or wrote %v", got)
	}
	unlock()
	code, _, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "states a done condition", "--takeaway", "ready to build",
		"--route", "gc-toolkit/gc-toolkit.polecat", "--run", root)
	wantCode(t, code, 0, err, "(LOCK) once the lock is free")
}
