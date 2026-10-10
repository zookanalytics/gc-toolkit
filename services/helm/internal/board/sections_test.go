package board

import (
	"reflect"
	"strings"
	"testing"
	"time"
)

// visitAnchor builds a visit wrapper the way source.gatherMetadataAnchors does:
// task_kind=visit, routed to the operator, naming its subject in
// gc.continuation_group, titled "visit: <subject> — <ask>".
func visitAnchor(id, subject, ask string) Anchor {
	return Anchor{
		ID: id, Kind: "human", Source: "human", Rig: "gc-toolkit", Prefix: "tk",
		Title: "visit: " + subject + " — " + ask,
		Metadata: map[string]string{
			"gc.routed_to":          "human",
			"task_kind":             "visit",
			"gc.continuation_group": subject,
		},
	}
}

// demandAnchor builds a demand wrapper: routed to the operator, naming its
// subject in gc.demand_for, with the authored question on its takeaway. Unlike a
// visit it is not visit presence, so folding it must not mark its subject Held.
func demandAnchor(id, subject, ask string) Anchor {
	return Anchor{
		ID: id, Kind: "human", Source: "human", Rig: "gc-toolkit", Prefix: "tk",
		Title:    "demand: " + ask,
		Takeaway: ask,
		Metadata: map[string]string{
			"gc.routed_to":  "human",
			"gc.demand_for": subject,
		},
	}
}

// TestSectionClassification pins the band each kind lands in.
func TestSectionClassification(t *testing.T) {
	anchors := []Anchor{
		// A pull request → review, whether or not the cadence recorded a position.
		{ID: "tk-pr", Kind: "merge", Source: "merge", Rig: "gc-toolkit", Prefix: "tk",
			Metadata: map[string]string{"merge_result": "pull_request", "pr_number": "7"}},
		// A decision → gate (a person must answer).
		{ID: "tk-dec", Kind: "decision", Source: "decision", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(1)},
		// A stranded epic → stalled.
		{ID: "tk-strand", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk",
			Children: []Child{{ID: "tk-x", Status: "open"}}},
		// A healthy in-flight epic → active.
		{ID: "tk-active", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk",
			Children: []Child{{ID: "tk-y", Status: "in_progress", Assignee: "sess-live"}}},
		// An empty anchor → cleanup.
		{ID: "tk-empty", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk"},
		// A closed anchor → done.
		{ID: "tk-closed", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk",
			ClosedAt: daysAgo(1), Children: []Child{{ID: "tk-z", Status: "closed"}}},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, liveOwners("sess-live"))

	want := map[string]string{
		"tk-pr":     SectionReview,
		"tk-dec":    SectionGate,
		"tk-strand": SectionStalled,
		"tk-active": SectionActive,
		"tk-empty":  SectionCleanup,
		"tk-closed": SectionDone,
	}
	for id, sec := range want {
		tile, ok := tileByID(b, id)
		if !ok {
			t.Fatalf("%s missing from board", id)
		}
		if tile.Section != sec {
			t.Errorf("%s: section = %q, want %q", id, tile.Section, sec)
		}
	}
}

// TestVisitFoldsIntoSubjectTile: a visit whose subject has a row of its own
// leaves ONE row — the subject, now owed, held, and carrying the visit's ask —
// and the visit's own row is gone.
func TestVisitFoldsIntoSubjectTile(t *testing.T) {
	anchors := []Anchor{
		visitAnchor("tk-vis", "tk-subj", "please review the plan"),
		{ID: "tk-subj", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2),
			Children: []Child{{ID: "tk-c1", Status: "open"}}},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})

	if _, ok := tileByID(b, "tk-vis"); ok {
		t.Errorf("the visit row should be folded away, not present")
	}
	subj, ok := tileByID(b, "tk-subj")
	if !ok {
		t.Fatalf("the subject row must survive the fold")
	}
	if !subj.Owed || !subj.Held {
		t.Errorf("folded subject is owed and held: owed=%v held=%v", subj.Owed, subj.Held)
	}
	if subj.Section != SectionGate {
		t.Errorf("folded subject bands as a gate: got %q", subj.Section)
	}
	if subj.Needs != "please review the plan" {
		t.Errorf("folded subject carries the visit ask: got %q", subj.Needs)
	}
}

// recommendationSubject is a subject a reaction has stamped with a recommended
// execution formula — the key that makes its visit a recommendation (Accept +
// Discuss) rather than a plain one (Discuss only).
func recommendationSubject(id, formula string) Anchor {
	return Anchor{
		ID: id, Kind: "human", Source: "human", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2),
		Title: "t " + id,
		Metadata: map[string]string{
			"gc.routed_to":           "human",
			"gc.recommended_formula": formula,
		},
	}
}

// openSitting / engagedSitting are a visit's sitting as facts carries it: open
// is parked and un-engaged, in_progress is a converse holding it.
func openSitting(subject string) Sitting { return Sitting{Subject: subject, Status: "open"} }
func engagedSitting(subject string) Sitting {
	return Sitting{Subject: subject, Status: "in_progress", Session: "converse-1"}
}

// pendingSitting is the window between engage binding the visit and the hook
// claim promoting it: still open, no session stamped yet, but bound by assignee.
func pendingSitting(subject string) Sitting {
	return Sitting{Subject: subject, Status: "open", Assignee: "converse-1"}
}

// TestRecommendationSubjectIsAcceptable: a subject carrying a recommended
// formula whose visit stands un-engaged is Acceptable, and names the formula
// Accept would dispatch. The visit wrapper folds away and never carries it.
func TestRecommendationSubjectIsAcceptable(t *testing.T) {
	anchors := []Anchor{
		visitAnchor("tk-vis", "tk-subj", "retire the wedged PR"),
		recommendationSubject("tk-subj", "mol-dispose-pr"),
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{Sittings: []Sitting{openSitting("tk-subj")}})

	subj, ok := tileByID(b, "tk-subj")
	if !ok {
		t.Fatalf("the subject row must survive the fold")
	}
	if !subj.Acceptable {
		t.Errorf("a recommendation subject with an un-engaged visit is acceptable: got Acceptable=%v", subj.Acceptable)
	}
	if subj.AcceptFormula != "mol-dispose-pr" {
		t.Errorf("the accept formula names what accepting dispatches: got %q", subj.AcceptFormula)
	}
	if v, ok := tileByID(b, "tk-vis"); ok {
		t.Errorf("the visit wrapper should fold away, never carry Accept itself; got a tile Acceptable=%v", v.Acceptable)
	}
}

// TestRecommendationWithLiveSittingIsNotAcceptable: a converse engaging the
// visit (in_progress) suppresses Accept while the operator is deciding by hand.
// An engaged visit is not gathered as an anchor, so only the subject row and its
// live sitting are on the board.
func TestRecommendationWithLiveSittingIsNotAcceptable(t *testing.T) {
	anchors := []Anchor{recommendationSubject("tk-subj", "mol-dispose-pr")}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{Sittings: []Sitting{engagedSitting("tk-subj")}})

	subj := mustTile(t, b, "tk-subj")
	if subj.Acceptable || subj.AcceptFormula != "" {
		t.Errorf("a live sitting suppresses Accept: Acceptable=%v formula=%q", subj.Acceptable, subj.AcceptFormula)
	}
}

// TestRecommendationWithPendingEngagementIsNotAcceptable: engage binds the visit
// by assignee while it is still open, before the hook claim promotes it to
// in_progress and stamps the session. In that window the sitting reads open with
// no session but a bound assignee, and Accept must already be suppressed —
// otherwise the board offers Accept on a visit a converse is about to hold, and
// the recommendation is actuated twice.
func TestRecommendationWithPendingEngagementIsNotAcceptable(t *testing.T) {
	anchors := []Anchor{recommendationSubject("tk-subj", "mol-dispose-pr")}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{Sittings: []Sitting{pendingSitting("tk-subj")}})

	subj := mustTile(t, b, "tk-subj")
	if subj.Acceptable || subj.AcceptFormula != "" {
		t.Errorf("a pending engagement (open + assigned) suppresses Accept: Acceptable=%v formula=%q", subj.Acceptable, subj.AcceptFormula)
	}
}

// TestSubjectWithoutRecommendedFormulaIsDiscussOnly: a visit with no
// gc.recommended_formula on its subject is discuss-only, exactly as today —
// Accept is absent whether or not the visit is un-engaged.
func TestSubjectWithoutRecommendedFormulaIsDiscussOnly(t *testing.T) {
	anchors := []Anchor{
		visitAnchor("tk-vis", "tk-subj", "let's talk it through"),
		humanKid("tk-subj"),
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{Sittings: []Sitting{openSitting("tk-subj")}})

	subj := mustTile(t, b, "tk-subj")
	if subj.Acceptable || subj.AcceptFormula != "" {
		t.Errorf("no gc.recommended_formula is discuss-only: Acceptable=%v formula=%q", subj.Acceptable, subj.AcceptFormula)
	}
}

// TestRecommendationWithNoVisitIsNotAcceptable: the recommendation key is
// present but no visit stands open on the subject (none filed, or it was
// dismissed), so there is nothing to accept-and-dismiss.
func TestRecommendationWithNoVisitIsNotAcceptable(t *testing.T) {
	anchors := []Anchor{recommendationSubject("tk-subj", "mol-dispose-pr")}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})

	subj := mustTile(t, b, "tk-subj")
	if subj.Acceptable {
		t.Errorf("a recommendation with no open visit is not acceptable: got Acceptable=%v", subj.Acceptable)
	}
}

// heldSubject is a plain live anchor, held by a visit through Facts.Visits — the
// path an engaged (in_progress) visit takes, which is not itself gathered as an
// open anchor and so never folds.
func heldSubject(id string) Anchor {
	return Anchor{
		ID: id, Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk",
		Children: []Child{{ID: id + ".c", Status: "open"}},
	}
}

// TestVisitStateSplitsHeldIntoParkedAndEngaged: VisitState refines Held into the
// two states the operator distinguishes on the board — a parked visit waiting for
// them, and an engaged one a live sitting is in right now. A row no visit holds
// carries the empty string. The pending-engagement window (open, bound by
// assignee, not yet claimed) reads engaged, the same window that suppresses Accept.
func TestVisitStateSplitsHeldIntoParkedAndEngaged(t *testing.T) {
	anchors := []Anchor{
		heldSubject("tk-engaged"), heldSubject("tk-parked"),
		heldSubject("tk-pending"), heldSubject("tk-novisit"),
	}
	facts := Facts{
		Visits: map[string]bool{"tk-engaged": true, "tk-parked": true, "tk-pending": true},
		Sittings: []Sitting{
			engagedSitting("tk-engaged"),
			openSitting("tk-parked"),
			pendingSitting("tk-pending"),
		},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, facts)

	want := map[string]string{
		"tk-engaged": VisitEngaged,
		"tk-parked":  VisitParked,
		"tk-pending": VisitEngaged,
		"tk-novisit": "",
	}
	for id, state := range want {
		tl := mustTile(t, b, id)
		if (id != "tk-novisit") != tl.Held {
			t.Fatalf("%s: Held = %v; the fixture holds every row but tk-novisit", id, tl.Held)
		}
		if tl.VisitState != state {
			t.Errorf("%s: VisitState = %q, want %q", id, tl.VisitState, state)
		}
	}
}

// TestFoldedVisitWithNoSittingReadsParked: a visit wrapper folds Held onto its
// subject even when its sitting has aged out of the window, so classifyVisits has
// no sitting to read. The fallback is parked — an open visit no session is on is
// waiting for the operator, never reported as being worked.
func TestFoldedVisitWithNoSittingReadsParked(t *testing.T) {
	anchors := []Anchor{
		visitAnchor("tk-vis", "tk-subj", "please review the plan"),
		{ID: "tk-subj", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2),
			Children: []Child{{ID: "tk-c1", Status: "open"}}},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})

	subj := mustTile(t, b, "tk-subj")
	if !subj.Held {
		t.Fatalf("the folded subject must be held")
	}
	if subj.VisitState != VisitParked {
		t.Errorf("a held row with no readable sitting falls back to parked: got %q", subj.VisitState)
	}
}

// TestVisitStateAgreesWithAcceptable: engaged and Accept read one predicate
// (engagedVisit), so a recommendation subject cannot read "parked" while Accept
// is suppressed, or "engaged" while Accept is offered.
func TestVisitStateAgreesWithAcceptable(t *testing.T) {
	build := func(s Sitting) Board {
		return BuildBoard(
			[]Anchor{recommendationSubject("tk-subj", "mol-dispose-pr")},
			fixtureNow, false, nil,
			Facts{Visits: map[string]bool{"tk-subj": true}, Sittings: []Sitting{s}},
		)
	}
	p := mustTile(t, build(openSitting("tk-subj")), "tk-subj")
	if p.VisitState != VisitParked || !p.Acceptable {
		t.Errorf("an open un-engaged recommendation is parked and acceptable: state=%q acceptable=%v", p.VisitState, p.Acceptable)
	}
	e := mustTile(t, build(engagedSitting("tk-subj")), "tk-subj")
	if e.VisitState != VisitEngaged || e.Acceptable {
		t.Errorf("a live-sitting recommendation is engaged and not acceptable: state=%q acceptable=%v", e.VisitState, e.Acceptable)
	}
}

// TestVisitKeptWhenSubjectHasNoTile: a visit whose subject is no anchor keeps
// its row — dropping it would erase the attention — stating the ask in NEEDS.
// Its TITLE names the visit and its subject, not the ask, so a surface that
// prints both columns does not repeat the same sentence in each.
func TestVisitKeptWhenSubjectHasNoTile(t *testing.T) {
	anchors := []Anchor{visitAnchor("tk-vis2", "tk-ghost", "investigate the flake")}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})

	vis, ok := tileByID(b, "tk-vis2")
	if !ok {
		t.Fatalf("a visit with no subject row must be kept")
	}
	if vis.Needs != "investigate the flake" {
		t.Errorf("kept visit states the ask in NEEDS: got %q", vis.Needs)
	}
	if vis.Title != "visit: tk-ghost" {
		t.Errorf("kept visit titles by kind and subject, not the ask: got %q", vis.Title)
	}
	if vis.Title == vis.Needs || strings.Contains(vis.Title, vis.Needs) {
		t.Errorf("NEEDS must not repeat TITLE: title=%q needs=%q", vis.Title, vis.Needs)
	}
	if vis.Section != SectionGate {
		t.Errorf("kept visit is a gate: got %q", vis.Section)
	}
}

// TestClosedWrapperDropsBesideItsSubject: a visit or demand that has itself
// closed is a finished conversation, not a live ask. Its subject's row, live or
// DONE, already stands for the attention, so the closed wrapper takes no row
// beside it. Its ask does not fold either, so the subject's row is exactly the
// row the subject has on its own: not owed, not held, its own needs and band.
func TestClosedWrapperDropsBesideItsSubject(t *testing.T) {
	for _, tc := range []struct {
		name          string
		wrapper       Anchor
		subjectClosed bool
	}{
		{"visit, live subject", visitAnchor("tk-wc", "tk-subj", "an ask that ended"), false},
		{"visit, DONE subject", visitAnchor("tk-wc", "tk-subj", "an ask that ended"), true},
		{"demand, live subject", demandAnchor("tk-wc", "tk-subj", "an ask that ended"), false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			w := tc.wrapper
			w.ClosedAt = daysAgo(1)
			subject := Anchor{ID: "tk-subj", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk",
				Children: []Child{{ID: "tk-c1", Status: "open"}}}
			if tc.subjectClosed {
				subject.ClosedAt = daysAgo(2)
			}
			b := BuildBoard([]Anchor{w, subject}, fixtureNow, false, nil, Facts{})

			if wc, ok := tileByID(b, "tk-wc"); ok {
				t.Errorf("a closed wrapper beside its subject's row takes no row of its own; got one in %q", wc.Section)
			}
			subj := mustTile(t, b, "tk-subj")
			if subj.Owed || subj.Needs == "an ask that ended" {
				t.Errorf("a closed wrapper's ask must not fold onto its subject: owed=%v needs=%q", subj.Owed, subj.Needs)
			}
			alone := mustTile(t, BuildBoard([]Anchor{subject}, fixtureNow, false, nil, Facts{}), "tk-subj")
			if !reflect.DeepEqual(subj, alone) {
				t.Errorf("a closed wrapper leaves its subject's row as the subject has it alone:\n got  %+v\n want %+v", subj, alone)
			}
		})
	}
}

// TestClosedWrapperChainDropsToItsSubject: a demand gates an epic, and a visit
// and a second demand are filed on that demand; all three have closed. Each one's
// subject has a row: the epic for the inner demand, the inner demand for the
// other two. The inner demand's row goes in favour of the epic's, so the epic's
// row is the one left, exactly as the epic has it on its own.
func TestClosedWrapperChainDropsToItsSubject(t *testing.T) {
	epic := Anchor{ID: "tk-epic", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk",
		Children: []Child{{ID: "tk-c1", Status: "open"}}}
	inner := demandAnchor("tk-d1", "tk-epic", "set direction on the epic")
	visit := visitAnchor("tk-v", "tk-d1", "discuss broadly")
	outer := demandAnchor("tk-d2", "tk-d1", "what the discussion settles next")
	for _, w := range []*Anchor{&inner, &visit, &outer} {
		w.ClosedAt = daysAgo(1)
	}
	b := BuildBoard([]Anchor{epic, inner, visit, outer}, fixtureNow, false, nil, Facts{})

	for _, id := range []string{"tk-d1", "tk-v", "tk-d2"} {
		if w, ok := tileByID(b, id); ok {
			t.Errorf("%s: a closed wrapper whose subject has a row takes none of its own; got one in %q", id, w.Section)
		}
	}
	alone := mustTile(t, BuildBoard([]Anchor{epic}, fixtureNow, false, nil, Facts{}), "tk-epic")
	if got := mustTile(t, b, "tk-epic"); !reflect.DeepEqual(got, alone) {
		t.Errorf("closed wrappers leave the epic's row as the epic has it alone:\n got  %+v\n want %+v", got, alone)
	}
}

// TestClosedWrapperLoopKeepsItsRows: two closed visits that each name the other
// as their subject. Each subject has a row, but dropping each beside the other
// would leave neither, so a loop of closed wrappers keeps its rows in DONE.
func TestClosedWrapperLoopKeepsItsRows(t *testing.T) {
	va := visitAnchor("tk-va", "tk-vb", "first ask")
	vb := visitAnchor("tk-vb", "tk-va", "second ask")
	va.ClosedAt, vb.ClosedAt = daysAgo(1), daysAgo(1)
	b := BuildBoard([]Anchor{va, vb}, fixtureNow, false, nil, Facts{})

	for _, id := range []string{"tk-va", "tk-vb"} {
		v, ok := tileByID(b, id)
		if !ok {
			t.Errorf("%s: a closed wrapper in a loop keeps its row", id)
			continue
		}
		if v.Section != SectionDone {
			t.Errorf("%s: bands done: got %q", id, v.Section)
		}
	}
}

// TestClosedVisitWithNoSubjectRowStaysDone: a closed visit whose subject has no
// row is the only trace of the attention it carried, so it keeps its own row in
// the DONE band, as any closed anchor does.
func TestClosedVisitWithNoSubjectRowStaysDone(t *testing.T) {
	v := visitAnchor("tk-vc", "tk-ghost", "an ask that ended")
	v.ClosedAt = daysAgo(1)
	b := BuildBoard([]Anchor{v}, fixtureNow, false, nil, Facts{})

	vc, ok := tileByID(b, "tk-vc")
	if !ok {
		t.Fatalf("a closed visit with no subject row must keep its row")
	}
	if vc.Section != SectionDone {
		t.Errorf("the closed visit bands done: got %q", vc.Section)
	}
}

// TestVisitLifecycleKeepsOneRow follows one visit through parked, engaged and
// dismissed, gathered at each stage the way the source gathers it. The open pass
// returns the visit while it is parked. Engage's claim moves it to in_progress,
// which the open pass does not return, so the running sitting is what holds the
// subject. Dismiss closes it, and the closed pass returns it again. At every
// stage the subject's row is the visit's only row. An engaged visit stays visible
// on that row, and a dismissed one does not come back as a second row beside it.
func TestVisitLifecycleKeepsOneRow(t *testing.T) {
	subject := heldSubject("tk-subj")
	open := visitAnchor("tk-v", "tk-subj", "decide the rollout")
	closed := open
	closed.ClosedAt = daysAgo(0)
	running := Facts{Visits: map[string]bool{"tk-subj": true}}

	parkedFacts := running
	parkedFacts.Sittings = []Sitting{openSitting("tk-subj")}
	engagedFacts := running
	engagedFacts.Sittings = []Sitting{engagedSitting("tk-subj")}
	dismissedFacts := Facts{Sittings: []Sitting{{Subject: "tk-subj", Status: "closed", ClosedAt: daysAgo(0)}}}

	for _, stage := range []struct {
		name      string
		anchors   []Anchor
		facts     Facts
		wantHeld  bool
		wantState string
	}{
		{"parked", []Anchor{open, subject}, parkedFacts, true, VisitParked},
		{"engaged", []Anchor{subject}, engagedFacts, true, VisitEngaged},
		{"dismissed", []Anchor{closed, subject}, dismissedFacts, false, ""},
	} {
		t.Run(stage.name, func(t *testing.T) {
			b := BuildBoard(stage.anchors, fixtureNow, false, nil, stage.facts)
			if v, ok := tileByID(b, "tk-v"); ok {
				t.Errorf("the visit must not take a row beside its subject; got one in %q", v.Section)
			}
			subj := mustTile(t, b, "tk-subj")
			if subj.Held != stage.wantHeld || subj.VisitState != stage.wantState {
				t.Errorf("subject row: held=%v state=%q, want held=%v state=%q",
					subj.Held, subj.VisitState, stage.wantHeld, stage.wantState)
			}
		})
	}
}

// TestTwoVisitsOneSubject: two visits on one subject fold into a single row that
// counts them and lists both asks.
func TestTwoVisitsOneSubject(t *testing.T) {
	anchors := []Anchor{
		visitAnchor("tk-va", "tk-subj", "first ask"),
		visitAnchor("tk-vb", "tk-subj", "second ask"),
		{ID: "tk-subj", Kind: "convoy", Source: "convoy", Rig: "gc-toolkit", Prefix: "tk",
			Children: []Child{{ID: "tk-c1", Status: "open"}}},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})

	if _, ok := tileByID(b, "tk-va"); ok {
		t.Errorf("first visit folded away")
	}
	if _, ok := tileByID(b, "tk-vb"); ok {
		t.Errorf("second visit folded away")
	}
	subj, _ := tileByID(b, "tk-subj")
	if !strings.Contains(subj.Needs, "2×") || !strings.Contains(subj.Needs, "first ask") || !strings.Contains(subj.Needs, "second ask") {
		t.Errorf("folded subject counts and lists both asks: got %q", subj.Needs)
	}
}

// TestDemandFoldsButSubjectNotHeld: a demand folds onto its subject like a visit
// — one row, owed, carrying the ask — but a demand is not visit presence, so the
// subject must NOT be marked Held (the CLI renders Held as an open-visit glyph).
func TestDemandFoldsButSubjectNotHeld(t *testing.T) {
	anchors := []Anchor{
		demandAnchor("tk-dem", "tk-subj", "approve the budget"),
		{ID: "tk-subj", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2),
			Children: []Child{{ID: "tk-c1", Status: "open"}}},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})

	if _, ok := tileByID(b, "tk-dem"); ok {
		t.Errorf("the demand row should be folded away, not present")
	}
	subj, ok := tileByID(b, "tk-subj")
	if !ok {
		t.Fatalf("the subject row must survive the fold")
	}
	if !subj.Owed {
		t.Errorf("a folded demand makes its subject owed")
	}
	if subj.Held {
		t.Errorf("a demand is not visit presence: the subject must not be held")
	}
	if subj.Needs != "approve the budget" {
		t.Errorf("folded subject carries the demand ask: got %q", subj.Needs)
	}
}

// TestFoldDatesSubjectByAsk: the folded subject's owed clock is the wrapper's ask
// instant, not the subject's own last-touch, so the queue orders the row by when
// the person was first asked.
func TestFoldDatesSubjectByAsk(t *testing.T) {
	dem := demandAnchor("tk-dem2", "tk-subj2", "decide the rollout")
	dem.TakeawayAt = daysAgo(5).Format(time.RFC3339)
	anchors := []Anchor{
		dem,
		{ID: "tk-subj2", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2),
			UpdatedAt: fixtureNow, Children: []Child{{ID: "tk-c1", Status: "open"}}},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})

	subj, ok := tileByID(b, "tk-subj2")
	if !ok {
		t.Fatalf("the subject row must survive the fold")
	}
	if want := daysAgo(5); !subj.PROwedSince.Equal(want) {
		t.Errorf("folded subject owed-since dates the ask: got %v, want %v", subj.PROwedSince, want)
	}
}

// TestClusterTagging: at or above the threshold, rows sharing a section and a
// needs sentence are tagged; below it they are not.
func TestClusterTagging(t *testing.T) {
	anchors := []Anchor{
		// Three human-routed beads with no recorded question → identical needs.
		{ID: "tk-h1", Kind: "human", Source: "human", Rig: "gc-toolkit", Prefix: "tk",
			Metadata: map[string]string{"gc.routed_to": "human"}},
		{ID: "tk-h2", Kind: "human", Source: "human", Rig: "gc-toolkit", Prefix: "tk",
			Metadata: map[string]string{"gc.routed_to": "human"}},
		{ID: "tk-h3", Kind: "human", Source: "human", Rig: "gc-toolkit", Prefix: "tk",
			Metadata: map[string]string{"gc.routed_to": "human"}},
		// Two decisions → identical needs, but below the threshold.
		{ID: "tk-d1", Kind: "decision", Source: "decision", Rig: "gc-toolkit", Prefix: "tk"},
		{ID: "tk-d2", Kind: "decision", Source: "decision", Rig: "gc-toolkit", Prefix: "tk"},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})

	for _, id := range []string{"tk-h1", "tk-h2", "tk-h3"} {
		tile, _ := tileByID(b, id)
		if tile.ClusterKey == "" {
			t.Errorf("%s should be clustered (3 share the needs), got empty key", id)
		}
		if tile.ClusterKey != tile.Needs {
			t.Errorf("%s cluster key is its needs: key=%q needs=%q", id, tile.ClusterKey, tile.Needs)
		}
	}
	for _, id := range []string{"tk-d1", "tk-d2"} {
		tile, _ := tileByID(b, id)
		if tile.ClusterKey != "" {
			t.Errorf("%s should NOT cluster (only 2 share the needs), got %q", id, tile.ClusterKey)
		}
	}
}

// TestParkedParentBandsGateNotActive: a roll-up whose every open child is parked
// for the operator is waiting on the operator to rule those child rows, not
// active work — so it bands gate rather than masquerading as in-flight, even
// when its own route markers are empty.
func TestParkedParentBandsGateNotActive(t *testing.T) {
	anchors := []Anchor{
		{ID: "tk-parent", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", UpdatedAt: fixtureNow,
			Children: []Child{{ID: "tk-child", Status: "open", Metadata: map[string]string{"gc.routed_to": "human"}}}},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})
	tile, ok := tileByID(b, "tk-parent")
	if !ok {
		t.Fatal("tk-parent missing")
	}
	if tile.Section != SectionGate {
		t.Errorf("a parent whose only open child is parked for the operator bands gate, got %q", tile.Section)
	}
}

// TestTakeawayRowsDoNotCluster: a row carrying a takeaway never clusters, however
// many share its needs — a deterministic signoff-cap headline templated across
// anchors does not fold into a count-plus-id soup that loses the per-bead
// content. A deterministic STATE phrase, which no bead authored,
// still clusters.
func TestTakeawayRowsDoNotCluster(t *testing.T) {
	tmpl := "signoff did not converge after 3 rework rounds (cap 3)"
	anchors := []Anchor{
		// Three parked beads with the SAME templated takeaway → must not cluster.
		{ID: "tk-t1", Kind: "parked", Source: "parked", Rig: "gc-toolkit", Prefix: "tk",
			Metadata: map[string]string{"gc.takeaway": tmpl}, Takeaway: tmpl},
		{ID: "tk-t2", Kind: "parked", Source: "parked", Rig: "gc-toolkit", Prefix: "tk",
			Metadata: map[string]string{"gc.takeaway": tmpl}, Takeaway: tmpl},
		{ID: "tk-t3", Kind: "parked", Source: "parked", Rig: "gc-toolkit", Prefix: "tk",
			Metadata: map[string]string{"gc.takeaway": tmpl}, Takeaway: tmpl},
		// Three human beads with no takeaway and one shared state phrase → cluster.
		{ID: "tk-c1", Kind: "human", Source: "human", Rig: "gc-toolkit", Prefix: "tk",
			Metadata: map[string]string{"gc.routed_to": "human"}},
		{ID: "tk-c2", Kind: "human", Source: "human", Rig: "gc-toolkit", Prefix: "tk",
			Metadata: map[string]string{"gc.routed_to": "human"}},
		{ID: "tk-c3", Kind: "human", Source: "human", Rig: "gc-toolkit", Prefix: "tk",
			Metadata: map[string]string{"gc.routed_to": "human"}},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})
	for _, id := range []string{"tk-t1", "tk-t2", "tk-t3"} {
		tile, _ := tileByID(b, id)
		if tile.ClusterKey != "" {
			t.Errorf("%s carries a takeaway and must not cluster, got key %q", id, tile.ClusterKey)
		}
	}
	for _, id := range []string{"tk-c1", "tk-c2", "tk-c3"} {
		tile, _ := tileByID(b, id)
		if tile.ClusterKey == "" {
			t.Errorf("%s is a takeaway-less state phrase shared by 3 and must still cluster", id)
		}
	}
}

// TestClusterRowsCollapse: ClusterRows folds a cluster to one line with every
// member, and leaves unclustered rows on their own line, in first-seen order.
func TestClusterRowsCollapse(t *testing.T) {
	tiles := []Tile{
		{ID: "a", Section: SectionGate, Needs: "same", ClusterKey: "same"},
		{ID: "b", Section: SectionGate, Needs: "solo"},
		{ID: "c", Section: SectionGate, Needs: "same", ClusterKey: "same"},
		{ID: "d", Section: SectionGate, Needs: "same", ClusterKey: "same"},
	}
	rows := ClusterRows(tiles)
	if len(rows) != 2 {
		t.Fatalf("want 2 render rows (one cluster + one solo), got %d", len(rows))
	}
	if rows[0].Tile.ID != "a" || len(rows[0].Members) != 3 {
		t.Errorf("cluster head is the first member and holds all 3: head=%s n=%d", rows[0].Tile.ID, len(rows[0].Members))
	}
	if rows[1].Tile.ID != "b" || len(rows[1].Members) != 1 {
		t.Errorf("solo row stands alone: id=%s n=%d", rows[1].Tile.ID, len(rows[1].Members))
	}
}

// TestGroupBySection returns only non-empty bands, in SectionOrder.
func TestGroupBySection(t *testing.T) {
	tiles := []Tile{
		{ID: "a", Section: SectionCleanup},
		{ID: "b", Section: SectionReview},
		{ID: "c", Section: SectionGate},
	}
	groups := GroupBySection(tiles)
	got := make([]string, len(groups))
	for i, g := range groups {
		got[i] = g.Key
	}
	want := []string{SectionReview, SectionGate, SectionCleanup}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Errorf("section order: got %v, want %v", got, want)
	}
}
