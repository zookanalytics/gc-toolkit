package takeaway

import (
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
)

// A release of a bead still standing reopens it, assigns it to nobody, clears
// Gas City's route and the pins its last executor left, and writes the
// headline, all in one update guarded by the status and the assignee the
// release read, so a close or a claim that lands after the read refuses it
// whole (RELEASE, CAS).
func TestAReleaseParksAnOpenBeadInOneGuardedWrite(t *testing.T) {
	w := newWorld(t)
	w.put(fake.Bead{ID: "tk-a", Title: "the bead", Status: "open", IssueType: "task", Metadata: map[string]string{
		"gc.routed_to": "tk/gc-toolkit.polecat", "gc.execution_routed_to": "tk/gc-toolkit.polecat",
		"gc.session_name": "polecat-1", "gc.session_id": "s-1"}})
	code, out, err := w.take(Request{Bead: "tk-a", Text: "parked", By: "proactive", Release: true, NoWait: true})
	if code != 0 {
		t.Fatalf("a release exits %d (%v), want 0", code, err)
	}
	up := w.update("tk-a")
	has(t, up, "--if-status=open --if-assignee= --status=open --assignee= ", "(CAS) the park is guarded on the status and the assignee it read")
	for _, want := range []string{"--set-metadata gc.takeaway=parked", "--set-metadata gc.takeaway_by=proactive",
		"--set-metadata gc.takeaway_at=2026-11-20T06:00:00Z", "--set-metadata gc.takeaway_settled=1", "--set-metadata gc.routed_to= ",
		"--unset-metadata gc.execution_routed_to", "--unset-metadata gc.session_name", "--unset-metadata gc.session_id"} {
		has(t, up, want, "(RELEASE) the one update")
	}
	b := w.row("tk-a")
	if b.Status != "open" || b.Assignee != "" || b.Metadata["gc.routed_to"] != "" || b.Metadata["gc.session_id"] != "" || b.Metadata["gc.execution_routed_to"] != "" {
		t.Errorf("(RELEASE) the bead reads %s under %q with %v", b.Status, b.Assignee, b.Metadata)
	}
	if out != "takeaway set on tk-a (by proactive) [released]: parked" {
		t.Errorf("the success line is %q", out)
	}
}

// A release ends the run beneath the bead through the pack's run-cancel.sh,
// which runs Gas City's run cancel, and writes no step or root of any run
// itself. A run beneath another bead is left alone, and the release says which
// run it ended (CANCEL, NOMEMBER, SCOPE, REPORT).
func TestAReleaseEndsTheRunBeneathTheBead(t *testing.T) {
	w := newWorld(t)
	w.tk.DB = "/rig/.beads"
	if code, _, err := w.take(Request{Bead: "tk-a", Text: "stopped", Release: true, NoWait: true}); code != 0 {
		t.Fatalf("a release exits %d (%v)", code, err)
	}
	cancels := w.lines("SCRIPT ")
	want := "SCRIPT run-cancel.sh --root tk-root --db /rig/.beads --reason takeaway --release on tk-a took its work out of play"
	if len(cancels) != 1 || cancels[0] != want {
		t.Fatalf("(CANCEL) the cancels are %q, want the one run beneath the bead, %q", cancels, want)
	}
	for _, l := range w.lines("UPDATE ") {
		if !strings.HasPrefix(l, "UPDATE tk-a ") {
			t.Errorf("(NOMEMBER) the release wrote %q, and a run's beads are Gas City's to close", l)
		}
	}
	w.before("UPDATE tk-a", "SCRIPT run-cancel.sh", "the run ends after the release write")
	if !w.saidAny("ended run tk-root of tk-a through gascity") {
		t.Errorf("(REPORT) the release did not say which run it ended: %q", w.said)
	}
}

// A run that does not end is not a release that landed: nothing retries a
// cancel, so the verb fails after every other write, names the run and the
// cancel to run by hand, and keeps the release it wrote (CANCELFAIL).
func TestARunThatDoesNotEndFailsTheRelease(t *testing.T) {
	w := newWorld(t)
	w.cancelFails = true
	code, out, err := w.take(Request{Bead: "tk-a", Text: "stopped", Release: true, NoWait: true})
	if code != 4 || out != "" {
		t.Fatalf("a cancel that did not land exits %d with %q, want 4 and no success line", code, out)
	}
	has(t, errText(err), "a run beneath tk-a did not end", "(CANCELFAIL) the error")
	if !w.saidAny("run tk-root of tk-a did not end") || !w.saidAny("End it by hand: /pack/scripts/run-cancel.sh --root tk-root") {
		t.Errorf("(CANCELFAIL) the run and its cancel by hand are unnamed: %q", w.said)
	}
	if w.row("tk-a").Status != "open" {
		t.Error("(CANCELFAIL) the release already written was lost")
	}
}

// Runs that do not read are not runs that ended: the verb fails after every
// other write, says what it could not read, and cancels nothing on a guess
// (RUNSUNREAD).
func TestRunsThatDoNotReadEndNothing(t *testing.T) {
	w := newWorld(t)
	w.store.DependentsErr = errBroken
	code, _, err := w.take(Request{Bead: "tk-a", Text: "stopped", Release: true, NoWait: true})
	if code != 4 {
		t.Fatalf("an unread run exits %d (%v), want 4", code, err)
	}
	if !w.saidAny("could not read the runs beneath tk-a") {
		t.Errorf("(RUNSUNREAD) the failed read is unnamed: %q", w.said)
	}
	if n := len(w.lines("SCRIPT ")); n != 0 {
		t.Errorf("(RUNSUNREAD) %d runs were cancelled on a guess", n)
	}
	if w.row("tk-a").Status != "open" {
		t.Error("(RUNSUNREAD) the release already written was lost")
	}
}

// A run whose live member this session holds is its own, such as a sitting
// disposing the bead it runs on, and closes its own chain: the release writes
// none of its beads and cancels nothing of it, and the release itself still
// lands whole (OWNRUN, LIVESTEP).
func TestAReleaseLeavesThisSessionsOwnRun(t *testing.T) {
	w := newWorld(t)
	w.tk.Self = []string{"polecat-me", "s-me"}
	w.put(fake.Bead{ID: "tk-root-step", Status: "in_progress", Assignee: "s-me",
		Metadata: map[string]string{"gc.root_bead_id": "tk-root", "gc.step_ref": "mol-polecat-work.submit"}})
	if code, _, err := w.take(Request{Bead: "tk-a", Text: "released to the pool", Release: true, Route: pool}); code != 0 {
		t.Fatalf("a release beside this session's own run exits %d (%v)", code, err)
	}
	if n := len(w.lines("SCRIPT ")); n != 0 {
		t.Errorf("(OWNRUN) this session's own run was cancelled: %q", w.lines("SCRIPT "))
	}
	if !w.saidAny("kept run tk-root of tk-a: this session holds a step of it") {
		t.Errorf("(OWNRUN) the kept run is unreported: %q", w.said)
	}
	if b := w.row("tk-root-step"); b.Status != "in_progress" || b.Assignee != "s-me" {
		t.Errorf("(OWNRUN) the step this session runs from reads %s under %q", b.Status, b.Assignee)
	}
	if b := w.row("tk-a"); b.Status != "open" || b.Assignee != "" {
		t.Errorf("(LIVESTEP) the bead reads %s under %q, want released", b.Status, b.Assignee)
	}
	if got := w.lines("SLING "); len(got) != 1 {
		t.Errorf("(LIVESTEP) the bead was not routed: %q", got)
	}
}

// A route sends the released bead to its pool through a sling that pours
// nothing and files no convoy, once the release has landed and the run beneath
// it has ended. The release write itself clears the route, and says where the
// bead went (ROUTE, ROUTEONE, ROUTECLR).
func TestARouteSlingsTheBeadOnceItsRunHasEnded(t *testing.T) {
	w := newWorld(t)
	code, out, err := w.take(Request{Bead: "tk-a", Text: "actionable — routed to the polecat pool", By: "proactive", Release: true, Route: pool})
	if code != 0 {
		t.Fatalf("a release to a pool exits %d (%v)", code, err)
	}
	has(t, w.update("tk-a"), "--set-metadata gc.routed_to= ", "(ROUTE) the release write clears the route")
	if got := w.lines("SLING "); !slices.Equal(got, []string{"SLING " + pool + " tk-a --no-formula --no-convoy"}) {
		t.Errorf("(ROUTE) the slings are %q", got)
	}
	w.before("DISARM tk-a", "UPDATE tk-a", "the disarm comes first")
	w.before("SCRIPT run-cancel.sh", "SLING ", "the run ends before the sling")
	has(t, out, "[released to "+pool+"]", "(ROUTEONE) the success line")

	w = newWorld(t)
	if code, _, err := w.take(Request{Bead: "tk-a", Text: "back to the human", Release: true, NoWait: true}); code != 0 {
		t.Fatalf("a plain release exits %d (%v)", code, err)
	}
	if n := len(w.lines("SLING ")); n != 0 {
		t.Errorf("(ROUTECLR) a release with no route slung %d times", n)
	}
}

// A route names a pool by its rig and rides a release, and a call that breaks
// either is refused before anything is written (ROUTEQUAL, ROUTEREL).
func TestARouteIsRigQualifiedAndRidesARelease(t *testing.T) {
	for name, req := range map[string]Request{
		"ROUTEQUAL": {Bead: "tk-a", Text: "bare", Release: true, Route: "gc-toolkit.polecat"},
		"ROUTEREL":  {Bead: "tk-a", Text: "no release", Route: pool},
	} {
		w := newWorld(t)
		code, _, err := w.take(req)
		if code != 2 || len(w.log) != 0 {
			t.Errorf("(%s) exits %d (%v) with %q written, want 2 and nothing", name, code, err, w.log)
		}
	}
}

// A release that sends a held bead on, to a pool or to a named agent, is a
// placement, so its write lifts every spelling of the placement hold, hold:po
// and its earlier spelling hold:mayor, and keeps the other labels, a hold of
// another value among them. A release back to a person keeps the hold
// (HOLDROUTE, HOLDAGENT, HOLDPARK).
func TestAReleaseThatSendsTheBeadOnLiftsItsHold(t *testing.T) {
	held := func(w *world) {
		w.put(fake.Bead{ID: "tk-a", Title: "the bead", Status: "open", IssueType: "task", Labels: []string{"hold:mayor", "Hold:Mayor", "hold:po", "hold:release-train", "learning"}})
	}
	w := newWorld(t)
	held(w)
	code, out, err := w.take(Request{Bead: "tk-a", Text: "placed — routed to the polecat pool", Release: true, Route: pool})
	if code != 0 {
		t.Fatalf("(HOLDROUTE) exits %d (%v)", code, err)
	}
	if got := w.row("tk-a").Labels; !slices.Equal(got, []string{"hold:release-train", "learning"}) {
		t.Errorf("(HOLDROUTE) the labels are %q, want the placement hold gone and the rest kept", got)
	}
	has(t, out, "hold:mayor and Hold:Mayor and hold:po lifted", "(HOLDROUTE) the success line")

	w = newWorld(t)
	held(w)
	if code, _, err := w.take(Request{Bead: "tk-a", Text: "a city.toml edit, mechanik's", Release: true, Assign: "gc-toolkit.mechanik", NoWait: true}); code != 0 {
		t.Fatalf("(HOLDAGENT) exits %d (%v)", code, err)
	}
	has(t, w.update("tk-a"), "--remove-label hold:mayor --remove-label Hold:Mayor --remove-label hold:po", "(HOLDAGENT) the release write")
	hasnt(t, w.update("tk-a"), "hold:release-train", "(HOLDAGENT) the release write")

	w = newWorld(t)
	held(w)
	if code, _, err := w.take(Request{Bead: "tk-a", Text: "back to the person", Release: true, NoWait: true}); code != 0 {
		t.Fatalf("(HOLDPARK) exits %d (%v)", code, err)
	}
	hasnt(t, w.update("tk-a"), "--remove-label", "(HOLDPARK) a release back to a person")
}

// The update's exit decides: a refused update fails the verb, and nothing
// after it is written, no edge, no run ended and no sling (REFUSED).
func TestARefusedUpdateFailsTheVerb(t *testing.T) {
	for _, req := range []Request{
		{Bead: "tk-a", Text: "refused", Release: true, NoWait: true},
		{Bead: "tk-a", Text: "refused", Release: true, Route: pool},
		{Bead: "tk-a", Text: "refused", WaitingOn: []string{"tk-b"}},
	} {
		w := newWorld(t)
		w.store.UpdateErr = errBroken
		code, out, err := w.take(req)
		if code != 4 || out != "" {
			t.Errorf("a refused update exits %d with %q, want 4 and no success line", code, out)
		}
		has(t, errText(err), "could not write the headline on tk-a", "(REFUSED) the error")
		if got := w.wrote(); len(got) != 0 {
			t.Errorf("(REFUSED) after a refused update the verb wrote %q", got)
		}
	}
}

// A release's first write removes the bead's arm, carrying the headline as its
// reason, and a disarm that does not land fails the verb with nothing else
// written. A bare headline removes no arm (DISARM, DISARMFAIL).
func TestAReleaseRemovesTheArmFirst(t *testing.T) {
	w := newWorld(t)
	w.armed = true
	if code, _, err := w.take(Request{Bead: "tk-a", Text: "stopped — the work moved", Release: true, NoWait: true}); code != 0 {
		t.Fatalf("(DISARM) exits %d (%v)", code, err)
	}
	if w.log[0] != "DISARM tk-a takeaway --release: stopped — the work moved" {
		t.Errorf("(DISARM) the first act is %q", w.log[0])
	}
	if !w.saidAny("disarmed tk-a") {
		t.Errorf("(DISARM) the removed arm is unsaid: %q", w.said)
	}
	w = newWorld(t)
	if code, _, _ := w.take(Request{Bead: "tk-a", Text: "a headline alone"}); code != 0 || len(w.lines("DISARM ")) != 0 {
		t.Errorf("(DISARM) a bare headline exits %d and disarms %q", code, w.lines("DISARM "))
	}
	for _, req := range []Request{
		{Bead: "tk-a", Text: "parked on the child", Release: true, NoWait: true},
		{Bead: "tk-a", Text: "routed on", Release: true, Route: pool},
	} {
		w = newWorld(t)
		w.disarmErr = errBroken
		code, _, err := w.take(req)
		if code != 4 {
			t.Fatalf("(DISARMFAIL) exits %d (%v), want 4", code, err)
		}
		has(t, errText(err), "that disarm did not land", "(DISARMFAIL) the error")
		if got := w.wrote(); len(got) != 0 {
			t.Errorf("(DISARMFAIL) after a failed disarm the verb wrote %q", got)
		}
	}
}

// folded is a bead a fold closed, superseded by tk-carrier, with a run still
// live beneath it.
func folded(w *world) {
	w.put(fake.Bead{ID: "tk-a", Title: "the bead", Status: "closed", IssueType: "task", Assignee: "polecat-old",
		Metadata: map[string]string{"gc.routed_to": "human"}, Edges: []gcbd.Edge{{Type: "supersedes", ID: "tk-carrier"}}})
	w.put(fake.Bead{ID: "tk-carrier", Title: "the carrier", Status: "open", IssueType: "task"})
}

// A closed bead keeps its disposition: the release writes the headline alone,
// with no reopen, no unassign and no route clear, and still ends the run
// beneath it, which a fold that landed after the pour leaves going (FOLDED,
// FOLDSTORE).
func TestAReleaseOnAClosedBeadKeepsItsDisposition(t *testing.T) {
	w := newWorld(t)
	folded(w)
	code, out, err := w.take(Request{Bead: "tk-a", Text: "folded into tk-carrier", By: "proactive", Release: true})
	if code != 0 {
		t.Fatalf("(FOLDED) a release on a closed bead exits %d (%v), want 0", code, err)
	}
	up := w.update("tk-a")
	for _, never := range []string{"--status", "--assignee", "--if-", "gc.routed_to", "--unset-metadata"} {
		hasnt(t, up, never, "(FOLDED) the closed bead's write")
	}
	has(t, up, "--set-metadata gc.takeaway=folded into tk-carrier", "(FOLDED) the headline")
	if b := w.row("tk-a"); b.Status != "closed" || b.Assignee != "polecat-old" || b.Metadata["gc.routed_to"] != "human" {
		t.Errorf("(FOLDSTORE) the closed bead reads %s under %q routed %q", b.Status, b.Assignee, b.Metadata["gc.routed_to"])
	}
	if got := w.lines("SCRIPT run-cancel.sh --root tk-root "); len(got) != 1 {
		t.Errorf("(FOLDED) the run beneath the closed bead was not ended: %q", w.lines("SCRIPT "))
	}
	if !w.saidAny("superseded by tk-carrier") {
		t.Errorf("(FOLDED) the successor is unnamed: %q", w.said)
	}
	has(t, out, "[run ended; anchor left closed]", "(FOLDED) the success line")
}

// A route or an assignment on a closed bead is refused on its disposition:
// the headline and the run's end still land, and the bead is never sent on
// (FOLDROUTE, TOAGENTFOLD, DELEGFOLD).
func TestAClosedBeadIsNeverSentOn(t *testing.T) {
	for name, req := range map[string]Request{
		"FOLDROUTE":   {Bead: "tk-a", Text: "route a disposed bead", Release: true, Route: pool},
		"TOAGENTFOLD": {Bead: "tk-a", Text: "assign a disposed bead", Release: true, Assign: "gc-toolkit.mechanik", NoWait: true},
	} {
		w := newWorld(t)
		folded(w)
		w.put(fake.Bead{ID: "tk-child", Title: "the child", Status: "open", IssueType: "task"})
		w.blockOn("tk-a", "tk-child")
		code, out, err := w.take(req)
		if code != 4 || out != "" {
			t.Errorf("(%s) exits %d with %q, want 4", name, code, out)
		}
		has(t, errText(err), "tk-a is closed, so it was not", "("+name+") the error")
		if n := len(w.lines("SLING ")); n != 0 {
			t.Errorf("(%s) a closed bead was slung", name)
		}
		hasnt(t, w.update("tk-a"), "--assignee", "("+name+") the closed bead's write")
		if got := w.lines("SCRIPT run-cancel.sh --root tk-root "); len(got) != 1 {
			t.Errorf("(%s) the run's end did not land: %q", name, w.lines("SCRIPT "))
		}
	}
}

// A status that does not read is no proof the bead is open, and the reopen is
// the one write whose cost is unbounded, so the release is refused with
// nothing written. A headline alone needs no status (FOLDBLIND).
func TestAReleaseThatCannotReadTheStatusWritesNothing(t *testing.T) {
	w := newWorld(t)
	code, _, err := w.take(Request{Bead: "tk-nope", Text: "unreadable", Release: true, NoWait: true})
	if code != 4 || len(w.wrote()) != 0 || len(w.lines("DISARM ")) != 0 {
		t.Errorf("(FOLDBLIND) a bead its store does not hold exits %d with %q written", code, w.log)
	}
	has(t, errText(err), "could not read the status of tk-nope", "(FOLDBLIND) the error")
	w = newWorld(t)
	w.store.FindErr = errBroken
	if code, _, _ := w.take(Request{Bead: "tk-a", Text: "unreadable", Release: true, NoWait: true}); code != 4 || len(w.log) != 0 {
		t.Errorf("(FOLDBLIND) a read that failed exits %d with %q written", code, w.log)
	}
}

// A bead whose PR waits on the pending record is worked by the landing order
// while it is assigned to nobody, so a release would not stop it, and it is
// refused before anything is written, naming what does: a human gate on the
// bead, or the PR's retirement (RECORD).
func TestABeadOnThePendingRecordIsNotReleased(t *testing.T) {
	for _, mr := range []string{"pull_request_pending", "pull_request_head_changed"} {
		w := newWorld(t)
		w.put(fake.Bead{ID: "tk-a", Title: "the bead", Status: "open", IssueType: "task", Metadata: map[string]string{"merge_result": mr}})
		code, _, err := w.take(Request{Bead: "tk-a", Text: "stopped", Release: true, NoWait: true})
		if code != 2 || len(w.log) != 0 {
			t.Errorf("(RECORD %s) exits %d with %q written, want 2 and nothing", mr, code, w.log)
		}
		has(t, errText(err), "/pack/scripts/human-gate.sh --subject tk-a", "(RECORD) the refusal names the gate")
		has(t, errText(err), "/pack/scripts/pr-dispose.sh --anchor tk-a", "(RECORD) and the retirement")
	}
}
