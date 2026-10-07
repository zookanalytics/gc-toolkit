package board

import (
	"strings"
	"testing"
	"time"
)

// preOpenGateAnchor builds a merge anchor parked at the pre-open codex gate, last
// touched `days` ago — the shape the stall signal reads. mergeAnchor defaults
// merge_result to pull_request and updated_at to fixtureNow, so both are
// overridden here.
func preOpenGateAnchor(id string, days int, extra map[string]string, blockers ...Blocker) Anchor {
	md := map[string]string{
		"merge_result": mergeResultPreOpenGate,
		"check_set":    checkSetCodex,
	}
	for k, v := range extra {
		md[k] = v
	}
	a := mergeAnchor(id, md, blockers...)
	a.UpdatedAt = fixtureNow.Add(-time.Duration(days) * 24 * time.Hour)
	return a
}

// TestPreOpenCodexGateStallFires: the bare held shape — past the threshold, no
// live review — is owed, ELEVATED out of the LOW floor, carries its age on the
// owed clock, and names the codex gate instead of "in the merge cadence". The
// three cases cover the reasons the NEEDS line reports.
func TestPreOpenCodexGateStallFires(t *testing.T) {
	cases := []struct {
		id       string
		blockers []Blocker
		reason   string // substring the NEEDS line must carry
	}{
		{"tk-never", nil, "no review has run"},
		{"tk-find", []Blocker{{ID: "tk-rw", Title: "Rework branch polecat/tk-find: address pre-open findings", Status: "open"}}, "findings open"},
		{"tk-radv", []Blocker{{ID: "tk-rv", Title: "Review branch polecat/tk-radv -> main", Status: "closed"}}, "reviewed, not advanced"},
	}
	for _, c := range cases {
		a := preOpenGateAnchor(c.id, 5, nil, c.blockers...)
		b := BuildBoard([]Anchor{a}, fixtureNow, false, nil, Facts{})
		tile := mustTile(t, b, c.id)

		if !tile.Owed {
			t.Errorf("%s: a stalled pre-open codex gate is the operator's move — owed", c.id)
		}
		if tile.Severity != SevElevated {
			t.Errorf("%s: severity = %q, want ELEVATED out of the LOW floor", c.id, tile.Severity)
		}
		if !strings.Contains(tile.Needs, "codex gate stalled") || !strings.Contains(tile.Needs, c.reason) {
			t.Errorf("%s: needs = %q, want the codex-gate stall naming %q", c.id, tile.Needs, c.reason)
		}
		if tile.Needs == "in the merge cadence" || strings.HasPrefix(tile.Needs, "position unknown") {
			t.Errorf("%s: needs must not keep the mis-framed phrase, got %q", c.id, tile.Needs)
		}
		if !tile.PROwedSince.Equal(a.UpdatedAt) {
			t.Errorf("%s: pr_owed_since = %v, want the stall start (updated_at) %v", c.id, tile.PROwedSince, a.UpdatedAt)
		}
		if !strings.Contains(tile.Frontier, "owed 5d") {
			t.Errorf("%s: the row carries its age on the frontier, got %q", c.id, tile.Frontier)
		}
		// It is a merge anchor, so it still reads in the REVIEW band beside the
		// wedged pre-open rows, not re-sectioned.
		if tile.Section != SectionReview {
			t.Errorf("%s: section = %q, want review", c.id, tile.Section)
		}
	}
}

// TestPreOpenCodexGateLiveVsDeadReview is the discriminating pair: two anchors
// identical but for one fact — whether the session behind the routed review is
// live. Both read pr.machine=progressing, whose position phrase is "in the merge
// cadence"; the signal splits them on liveness, surfacing the routed review no
// live session is draining as a stall.
func TestPreOpenCodexGateLiveVsDeadReview(t *testing.T) {
	review := func(assignee string) Blocker {
		return Blocker{
			ID: "tk-review", Title: "Review branch polecat/tk-gate -> main", Status: "open",
			RoutedTo: "gc-toolkit/gc-toolkit.polecat-codex", Assignee: assignee,
		}
	}

	// A codex polecat is claiming the review: the city's move, not a stall.
	liveAnchor := preOpenGateAnchor("tk-gate", 5, nil, review("gc-toolkit__polecat-codex-lx-live"))
	live := BuildBoard([]Anchor{liveAnchor}, fixtureNow, false, nil, liveOwners("gc-toolkit__polecat-codex-lx-live"))
	lt := mustTile(t, live, "tk-gate")
	if lt.PRMachine != MachineProgressing {
		t.Fatalf("a pool-routed review reads progressing, got %q", lt.PRMachine)
	}
	if lt.Owed {
		t.Error("a review a live session is working is not owed by the operator")
	}
	if lt.Needs != "in the merge cadence" {
		t.Errorf("a healthy hold keeps its position phrase, got %q", lt.Needs)
	}

	// The same anchor and the same routed review, but the session has drained —
	// no pool is draining the queue, so nothing is moving it.
	deadAnchor := preOpenGateAnchor("tk-gate", 5, nil, review("gc-toolkit__polecat-codex-lx-gone"))
	dead := BuildBoard([]Anchor{deadAnchor}, fixtureNow, false, nil,
		Facts{OwnerState: map[string]string{"gc-toolkit__polecat-codex-lx-gone": "archived"}})
	dt := mustTile(t, dead, "tk-gate")
	if dt.PRMachine != MachineProgressing {
		t.Fatalf("routed-ness still reads progressing, got %q", dt.PRMachine)
	}
	if !dt.Owed || dt.Severity != SevElevated {
		t.Errorf("a routed review no live session is draining is a stall: owed=%v sev=%q", dt.Owed, dt.Severity)
	}
	if !strings.Contains(dt.Needs, "codex gate stalled") {
		t.Errorf("the dead-pool hold names the gate, got %q", dt.Needs)
	}
	// The reason reads a review has run (the routed child), not never-reviewed.
	if !strings.Contains(dt.Needs, "reviewed, not advanced") {
		t.Errorf("an open review with no rework reads reviewed-not-advanced, got %q", dt.Needs)
	}
}

// TestPreOpenCodexGateStallDoesNotFire: every shape that must NOT surface as a
// stall. A fresh hold, a green gate, and a recorded wedge each keep their own
// position phrase.
func TestPreOpenCodexGateStallDoesNotFire(t *testing.T) {
	wedgedAt := fixtureNow.Add(-120 * time.Hour)
	cases := []struct {
		name      string
		anchor    Anchor
		wantOwed  bool
		wantNeeds string
	}{
		{
			name:      "fresh hold below the threshold",
			anchor:    preOpenGateAnchor("tk-fresh", 1, nil),
			wantOwed:  false,
			wantNeeds: "position unknown — the merge cadence has recorded none",
		},
		{
			name:      "the gate marker is a bare green — the PR is about to open",
			anchor:    preOpenGateAnchor("tk-green", 5, map[string]string{"check.codex": checkGreen}),
			wantOwed:  false,
			wantNeeds: "position unknown — the merge cadence has recorded none",
		},
		{
			name:      "a recorded wedge already owns the row",
			anchor:    preOpenGateAnchor("tk-wedge", 5, map[string]string{"pr.machine": dated(MachineWedgedException, headLive, wedgedAt)}),
			wantOwed:  true, // owed, but by the wedge — not the stall
			wantNeeds: "wedged: the review cap parked this anchor — a ruling releases it, a new commit does not",
		},
		{
			name:      "not the codex gate set",
			anchor:    preOpenGateAnchor("tk-other", 5, map[string]string{"check_set": "shellcheck"}),
			wantOwed:  false,
			wantNeeds: "position unknown — the merge cadence has recorded none",
		},
	}
	for _, c := range cases {
		b := BuildBoard([]Anchor{c.anchor}, fixtureNow, false, nil, Facts{})
		tile := mustTile(t, b, c.anchor.ID)
		if strings.Contains(tile.Needs, "codex gate stalled") {
			t.Errorf("%s: the stall must not fire, got needs %q", c.name, tile.Needs)
		}
		if tile.Owed != c.wantOwed {
			t.Errorf("%s: owed = %v, want %v", c.name, tile.Owed, c.wantOwed)
		}
		if tile.Needs != c.wantNeeds {
			t.Errorf("%s: needs = %q, want %q", c.name, tile.Needs, c.wantNeeds)
		}
	}
}

// TestPreOpenCodexGateStallYieldsToStrongerSurfacing: a takeaway or a human route
// already carries the row's NEEDS, so the stall defers rather than renaming it.
// A human-routed signoff-cap park and a converse takeaway each carry their own
// NEEDS, and the human route also owns the band.
func TestPreOpenCodexGateStallYieldsToStrongerSurfacing(t *testing.T) {
	// A converse sitting parked it: gathered as the parked kind, carrying its
	// takeaway as the NEEDS sentence.
	parked := preOpenGateAnchor("tk-parked", 5, map[string]string{"gc.takeaway": "waiting on the upstream decision"})
	parked.Kind, parked.Source = "parked", "parked"
	parked.Takeaway = "waiting on the upstream decision"

	// Routed to a person after the signoff cap: humanGated owns it.
	human := preOpenGateAnchor("tk-human", 5, map[string]string{
		"gc.routed_to": "human",
		"merge_hold":   "signoff_cap",
	})
	human.Kind, human.Source = "human", "human"

	b := BuildBoard([]Anchor{parked, human}, fixtureNow, false, nil, Facts{})

	pk := mustTile(t, b, "tk-parked")
	if strings.Contains(pk.Needs, "codex gate stalled") {
		t.Errorf("a parked row keeps its takeaway, got %q", pk.Needs)
	}
	if pk.Needs != "waiting on the upstream decision" {
		t.Errorf("needs = %q, want the takeaway", pk.Needs)
	}

	hm := mustTile(t, b, "tk-human")
	if strings.Contains(hm.Needs, "codex gate stalled") {
		t.Errorf("a human-routed row keeps its own finding, got %q", hm.Needs)
	}
	if !hm.Owed || hm.Severity != SevElevated {
		t.Errorf("the human-gated park is owed and elevated by its own path: owed=%v sev=%q", hm.Owed, hm.Severity)
	}
}

// TestPreOpenCodexGateStallYieldsToOpenDemand: an open demand already owns the
// row and names the operator's actual question, so the stall must not overwrite
// it with the gate's generic wording. The row renders `asking: <title>`, not
// `codex gate stalled`, even though every other stall precondition holds — past
// the threshold, no live review. This is the row shape the stall guard's
// `ask == nil` clause protects.
func TestPreOpenCodexGateStallYieldsToOpenDemand(t *testing.T) {
	demand := Blocker{
		ID: "tk-ask", Title: "operator: which rig owns the shared fixture?",
		Status: "open", IssueType: "decision",
	}
	a := preOpenGateAnchor("tk-demand", 5, nil, demand)
	tile := mustTile(t, BuildBoard([]Anchor{a}, fixtureNow, false, nil, Facts{}), "tk-demand")

	if strings.Contains(tile.Needs, "codex gate stalled") {
		t.Errorf("an open demand owns the row; the stall must not overwrite it, got %q", tile.Needs)
	}
	if tile.Needs != "asking: operator: which rig owns the shared fixture?" {
		t.Errorf("needs = %q, want the demand rendered as `asking: <title>`", tile.Needs)
	}
	if !tile.Owed {
		t.Error("a row carrying an unanswered demand is owed")
	}
}

// TestPreOpenCodexGateLiveReviewNotRouted: a real mol-review child is not stamped
// with gc.routed_to — `gc sling` leaves it open and puts the in-flight state on
// the workflow, visible only through Facts.Inflight — so the live suppression
// recognizes it by the cadence title and the live workflow behind it, not by the
// route. A live review moving the gate is a healthy hold, not a stall.
func TestPreOpenCodexGateLiveReviewNotRouted(t *testing.T) {
	// No RoutedTo: the route lives on the workflow, not the child.
	review := Blocker{ID: "tk-rev", Title: "Review branch polecat/tk-live -> main", Status: "open"}
	a := preOpenGateAnchor("tk-live", 5, nil, review)
	f := Facts{
		Inflight:   map[string][]string{"tk-rev": {"gc-toolkit__polecat-codex-lx-run"}},
		OwnerState: map[string]string{"gc-toolkit__polecat-codex-lx-run": "active"},
	}
	tile := mustTile(t, BuildBoard([]Anchor{a}, fixtureNow, false, nil, f), "tk-live")

	if strings.Contains(tile.Needs, "codex gate stalled") {
		t.Errorf("a live review workflow with no route is a healthy hold, not a stall; got %q", tile.Needs)
	}
	if tile.Owed {
		t.Error("a pre-open gate a live review is moving is not the operator's move — not owed")
	}
}
