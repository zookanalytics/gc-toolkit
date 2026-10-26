package board

import (
	"fmt"
	"strings"
	"testing"
)

// failedSitting is a visit whose sitting failed to start, as the gather leaves
// it: still bound the way the failed start left it (in_progress under the
// sitting's alias), with the reason Gas City recorded.
func failedSitting(id, subject, reason string) Sitting {
	return Sitting{ID: id, Subject: subject, Status: "in_progress",
		Assignee: "gc-toolkit/gc-toolkit." + id, StartFailure: reason}
}

// releasedFailedSitting is the same visit after the witness released the dead
// binding: open and unbound, the failure still the last thing that happened.
func releasedFailedSitting(id, subject, reason string) Sitting {
	return Sitting{ID: id, Subject: subject, Status: "open", StartFailure: reason}
}

// TestStartFailedVisitReadsStartFailedWithItsReason: the held row reads the
// failure, not "engaged" (which is what the stale binding alone would say). It
// is owed, at least ELEVATED, and NEEDS leads with the reason ahead of the ask.
func TestStartFailedVisitReadsStartFailedWithItsReason(t *testing.T) {
	anchors := []Anchor{
		visitAnchor("tk-vis", "tk-subj", "talk the plan over"),
		heldSubject("tk-subj"),
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{
		Visits:   map[string]bool{"tk-subj": true},
		Sittings: []Sitting{failedSitting("tk-vis", "tk-subj", "setup timeout")},
	})
	subj := mustTile(t, b, "tk-subj")
	if subj.VisitState != VisitStartFailed || subj.VisitStartFailure != "setup timeout" {
		t.Errorf("state=%q reason=%q, want start-failed with the reason", subj.VisitState, subj.VisitStartFailure)
	}
	if got, want := subj.Needs, "start failed (setup timeout): talk the plan over"; got != want {
		t.Errorf("NEEDS = %q, want %q", got, want)
	}
	if !subj.Owed || subj.Section != SectionGate {
		t.Errorf("a failed start is the operator's move: owed=%v section=%q", subj.Owed, subj.Section)
	}
	if subj.Severity != SevElevated {
		t.Errorf("a NORMAL row whose visit failed to start bands ELEVATED: %s", subj.Severity)
	}
	if subj.RankScore != rankScore(SevElevated, subj.Weight, subj.StaleDays, 0) {
		t.Errorf("rank_score follows the lifted band: %d", subj.RankScore)
	}
	if engagedVisit("tk-subj", b.Sittings) {
		t.Error("a binding to a sitting that never started is not an engagement")
	}
}

// TestStartFailedOwnRowStaysInTheQueue: a visit whose subject has no row keeps
// a row of its own. Once the witness re-parks it, its headline reads as a
// ruling, which bands it LOW and drops it from the queue. A failed start keeps
// it owed and ELEVATED all the same.
func TestStartFailedOwnRowStaysInTheQueue(t *testing.T) {
	reparked := visitAnchor("tk-vis", "tk-plain", "talk the plan over")
	reparked.Takeaway = "Reclaimed from a gone sitting; re-parked for re-engagement."
	reparked.Metadata["gc.takeaway"] = reparked.Takeaway

	build := func(s Sitting) Tile {
		b := BuildBoard([]Anchor{reparked}, fixtureNow, false, nil, Facts{Sittings: []Sitting{s}})
		return mustTile(t, b, "tk-vis")
	}

	control := build(Sitting{ID: "tk-vis", Subject: "tk-plain", Status: "open"})
	if control.Owed || control.Severity != SevLow {
		t.Fatalf("fixture: a re-parked visit's own row reads ruled, LOW and not owed; got owed=%v %s", control.Owed, control.Severity)
	}

	row := build(releasedFailedSitting("tk-vis", "tk-plain", "startup timeout"))
	if row.VisitState != VisitStartFailed || row.VisitStartFailure != "startup timeout" {
		t.Errorf("the visit's own row reads start failed: state=%q reason=%q", row.VisitState, row.VisitStartFailure)
	}
	if !row.Owed || row.Severity != SevElevated || row.Section != SectionGate {
		t.Errorf("a failed start keeps the row in the queue: owed=%v %s section=%q", row.Owed, row.Severity, row.Section)
	}
	if !strings.HasPrefix(row.Needs, "start failed (startup timeout): ") {
		t.Errorf("NEEDS leads with the failure: %q", row.Needs)
	}
}

// TestStartFailedLeadsTheQueue: by age a failed start sorts at the tail, below
// the head the picker offers. It leads the queue instead, and the cap keeps it.
func TestStartFailedLeadsTheQueue(t *testing.T) {
	anchors := []Anchor{visitAnchor("tk-vis", "tk-subj", "talk the plan over"), heldSubject("tk-subj")}
	for i := 0; i < 50; i++ {
		anchors = append(anchors, Anchor{
			ID: fmt.Sprintf("tk-old%02d", i), Kind: "human", Source: "human", Rig: "gc-toolkit", Prefix: "tk",
			UpdatedAt: daysAgo(30 + i), Metadata: map[string]string{"gc.routed_to": "human"},
		})
	}
	anchors[0].UpdatedAt = fixtureNow // the visit was filed just now
	facts := func(s Sitting) Facts {
		return Facts{Visits: map[string]bool{"tk-subj": true}, Sittings: []Sitting{s}}
	}

	queue := OperatorQueue(BuildBoard(anchors, fixtureNow, false, nil, facts(failedSitting("tk-vis", "tk-subj", "startup timeout"))).Tiles)
	if queue[0].ID != "tk-subj" {
		t.Errorf("the failed start leads the queue: got %s first", queue[0].ID)
	}
	if capped := CapQueue(queue, 36); capped[0].ID != "tk-subj" {
		t.Errorf("the cap keeps the head: got %s first", capped[0].ID)
	}

	// The same row parked sorts by age, behind every row owed longer.
	parked := OperatorQueue(BuildBoard(anchors, fixtureNow, false, nil, facts(Sitting{ID: "tk-vis", Subject: "tk-subj", Status: "open"})).Tiles)
	if last := parked[len(parked)-1]; last.ID != "tk-subj" {
		t.Errorf("control: a parked visit filed just now sorts last, got %s last", last.ID)
	}
}

// TestStartFailedAcceptFollowsTheBinding: Accept is the rule gc-helm.sh accept
// re-reads live, which counts every binding. While the failed start's binding
// stands, accept refuses the visit as engaged, so the board offers no Accept;
// once the witness releases it, the visit stands open and unbound and Accept is
// offered. The row reads start failed throughout.
func TestStartFailedAcceptFollowsTheBinding(t *testing.T) {
	build := func(s Sitting) Tile {
		b := BuildBoard(
			[]Anchor{recommendationSubject("tk-subj", "mol-dispose-pr")},
			fixtureNow, false, nil,
			Facts{Visits: map[string]bool{"tk-subj": true}, Sittings: []Sitting{s}},
		)
		return mustTile(t, b, "tk-subj")
	}
	bound := build(failedSitting("tk-vis", "tk-subj", "startup timeout"))
	if bound.VisitState != VisitStartFailed || bound.Acceptable {
		t.Errorf("bound: state=%q acceptable=%v, want start-failed and no Accept", bound.VisitState, bound.Acceptable)
	}
	released := build(releasedFailedSitting("tk-vis", "tk-subj", "startup timeout"))
	if released.VisitState != VisitStartFailed || !released.Acceptable {
		t.Errorf("released: state=%q acceptable=%v, want start-failed and Accept", released.VisitState, released.Acceptable)
	}
}

// TestStartFailureOutranksALiveSitting: two visits on one subject are two
// conversations. A live sitting in one does not hide that the other's never
// started.
func TestStartFailureOutranksALiveSitting(t *testing.T) {
	live := engagedSitting("tk-subj")
	live.ID = "tk-vis1"
	b := BuildBoard([]Anchor{heldSubject("tk-subj")}, fixtureNow, false, nil, Facts{
		Visits:   map[string]bool{"tk-subj": true},
		Sittings: []Sitting{live, failedSitting("tk-vis2", "tk-subj", "never started")},
	})
	if subj := mustTile(t, b, "tk-subj"); subj.VisitState != VisitStartFailed || subj.VisitStartFailure != "never started" {
		t.Errorf("state=%q reason=%q, want the failure", subj.VisitState, subj.VisitStartFailure)
	}
}

// TestClosedSubjectIsNeverMarked: a closed anchor is never owed, so its DONE row
// is not marked. The fold leaves the open visit on a row of its own, and that
// row carries the failure.
func TestClosedSubjectIsNeverMarked(t *testing.T) {
	closed := heldSubject("tk-subj")
	closed.ClosedAt = daysAgo(1)
	b := BuildBoard([]Anchor{visitAnchor("tk-vis", "tk-subj", "talk the plan over"), closed}, fixtureNow, false, nil, Facts{
		Visits:   map[string]bool{"tk-subj": true},
		Sittings: []Sitting{failedSitting("tk-vis", "tk-subj", "startup timeout")},
	})
	if subj := mustTile(t, b, "tk-subj"); subj.VisitState == VisitStartFailed || subj.Owed {
		t.Errorf("a DONE row is never marked or owed: state=%q owed=%v", subj.VisitState, subj.Owed)
	}
	if own := mustTile(t, b, "tk-vis"); own.VisitState != VisitStartFailed || !own.Owed {
		t.Errorf("the visit's own row carries the failure: state=%q owed=%v", own.VisitState, own.Owed)
	}
}
