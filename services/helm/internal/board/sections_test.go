package board

import (
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
		// A pull request the operator is OWED → review: wedged on a ruling only a
		// person can give. review is the operator's own PR queue, not every PR.
		{ID: "tk-pr", Kind: "merge", Source: "merge", Rig: "gc-toolkit", Prefix: "tk",
			Metadata: map[string]string{"merge_result": "pull_request", "pr_number": "7",
				"pr.machine": "wedged-exception@abc123@2026-09-01T00:00:00Z"}},
		// A progressing pull request → active: healthy in-flight work the cadence
		// is moving, not a PR that wants the operator.
		{ID: "tk-pr-active", Kind: "merge", Source: "merge", Rig: "gc-toolkit", Prefix: "tk",
			Metadata: map[string]string{"merge_result": "pull_request", "pr_number": "8",
				"pr.machine": "progressing@def456@2026-09-01T00:00:00Z"}},
		// A pre-open gate nothing is moving and nobody owes, aged past the grace
		// window → stalled. No review armed, nothing in flight.
		{ID: "tk-preopen-stall", Kind: "merge", Source: "merge", Rig: "gc-toolkit", Prefix: "tk",
			UpdatedAt: daysAgo(5),
			Metadata:  map[string]string{"merge_result": "pre_open_gate", "branch": "polecat/tk-preopen-stall"}},
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
		"tk-pr":            SectionReview,
		"tk-pr-active":     SectionActive,
		"tk-preopen-stall": SectionStalled,
		"tk-dec":           SectionGate,
		"tk-strand":        SectionStalled,
		"tk-active":        SectionActive,
		"tk-empty":         SectionCleanup,
		"tk-closed":        SectionDone,
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

// TestPreOpenReReviewIsActive: a merge anchor in the pre-open re-review cadence
// carries a converse takeaway, so the gather admits it as BOTH a `parked` row
// (gc.takeaway) and a `merge` row (merge_result). It is forward-moving — the
// cadence recorded pr.machine=progressing and a fresh review is armed — so it
// must survive dedup as the `merge` row and band ACTIVE, not as a parked/stalled
// LOW row.
func TestPreOpenReReviewIsActive(t *testing.T) {
	md := map[string]string{
		"merge_result": "pre_open_gate",
		"branch":       "polecat/tk-8u81bo",
		"pr.machine":   "progressing@1d2ff83b@2026-09-15T02:41:48Z",
		"gc.takeaway":  "Cap retired; pre-open cadence re-reviews with fresh budget.",
	}
	rev := []Blocker{{ID: "tk-rev", Status: "open", TaskKind: "review"}}
	// The two rows one bead reaches the board as, exactly as the gather emits.
	parkedRow := Anchor{ID: "tk-8u81bo", Kind: "parked", Source: "parked", Rig: "gc-toolkit", Prefix: "tk",
		Priority: ptr(1), UpdatedAt: fixtureNow, Metadata: md, Takeaway: md["gc.takeaway"], Blockers: rev}
	mergeRow := Anchor{ID: "tk-8u81bo", Kind: "merge", Source: "merge", Rig: "gc-toolkit", Prefix: "tk",
		Priority: ptr(1), UpdatedAt: fixtureNow, Metadata: md, Blockers: rev}

	b := BuildBoard([]Anchor{parkedRow, mergeRow}, fixtureNow, false, nil, Facts{})
	tl, ok := tileByID(b, "tk-8u81bo")
	if !ok {
		t.Fatal("tk-8u81bo missing from board")
	}
	if tl.Kind == "parked" {
		t.Errorf("a live merge anchor must not read as parked; kind=%q", tl.Kind)
	}
	if tl.Section != SectionActive {
		t.Errorf("a progressing pre-open re-review anchor bands active; got %q (sev %s, needs %q)", tl.Section, tl.Severity, tl.Needs)
	}
	if tl.PreOpenStalled {
		t.Error("a progressing anchor is not a pre-open stall")
	}
}

// TestPreOpenGateStallSurfaces: a pre-open gate aged past the grace window with
// no review armed, nothing in flight, and nobody owed bands STALLED at ELEVATED,
// and its frontier/needs name the codex gate. A fresh gate in the same shape
// does not.
func TestPreOpenGateStallSurfaces(t *testing.T) {
	stall := Anchor{ID: "tk-or0ha2", Kind: "merge", Source: "merge", Rig: "gc-toolkit", Prefix: "tk",
		Priority: ptr(2), UpdatedAt: daysAgo(7),
		Metadata: map[string]string{"merge_result": "pre_open_gate", "branch": "polecat/tk-or0ha2"}}
	fresh := Anchor{ID: "tk-fresh-gate", Kind: "merge", Source: "merge", Rig: "gc-toolkit", Prefix: "tk",
		Priority: ptr(2), UpdatedAt: fixtureNow,
		Metadata: map[string]string{"merge_result": "pre_open_gate", "branch": "polecat/tk-fresh-gate"}}

	b := BuildBoard([]Anchor{stall, fresh}, fixtureNow, false, nil, Facts{})

	tl, ok := tileByID(b, "tk-or0ha2")
	if !ok {
		t.Fatal("tk-or0ha2 missing from board")
	}
	if !tl.PreOpenStalled {
		t.Fatal("an aged pre-open gate with no review and nothing in flight is stalled")
	}
	if tl.Section != SectionStalled {
		t.Errorf("a stalled pre-open gate bands stalled; got %q", tl.Section)
	}
	if tl.Severity != SevElevated {
		t.Errorf("a stalled pre-open gate is ELEVATED, out of the LOW floor; got %s", tl.Severity)
	}
	if !strings.Contains(tl.Needs, "codex gate") {
		t.Errorf("needs must name the codex gate; got %q", tl.Needs)
	}
	if !strings.Contains(tl.Frontier, "stalled") {
		t.Errorf("frontier must show the stall; got %q", tl.Frontier)
	}

	// A fresh gate in the same shape is a healthy park, not a stall.
	if ft, _ := tileByID(b, "tk-fresh-gate"); ft.PreOpenStalled || ft.Section == SectionStalled {
		t.Errorf("a fresh pre-open gate is healthy, not stalled; section=%q pre_open_stalled=%v", ft.Section, ft.PreOpenStalled)
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

// TestVisitKeptWhenSubjectHasNoTile: a visit whose subject is no anchor keeps
// its row — dropping it would erase the attention — but states the ask from its
// title rather than the empty "no question recorded".
func TestVisitKeptWhenSubjectHasNoTile(t *testing.T) {
	anchors := []Anchor{visitAnchor("tk-vis2", "tk-ghost", "investigate the flake")}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})

	vis, ok := tileByID(b, "tk-vis2")
	if !ok {
		t.Fatalf("a visit with no subject row must be kept")
	}
	if vis.Needs != "investigate the flake" {
		t.Errorf("kept visit states the ask from its title: got %q", vis.Needs)
	}
	if vis.Section != SectionGate {
		t.Errorf("kept visit is a gate: got %q", vis.Section)
	}
}

// TestClosedVisitDoesNotFold: a visit that has itself closed is a finished
// conversation, not a live ask — it stays in the DONE band and does not make its
// subject owed.
func TestClosedVisitDoesNotFold(t *testing.T) {
	v := visitAnchor("tk-vc", "tk-subj", "an ask that ended")
	v.ClosedAt = daysAgo(1)
	anchors := []Anchor{
		v,
		{ID: "tk-subj", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk",
			Children: []Child{{ID: "tk-c1", Status: "open"}}},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})

	subj, ok := tileByID(b, "tk-subj")
	if !ok {
		t.Fatalf("subject present")
	}
	if subj.Owed {
		t.Errorf("a closed visit must not make its subject owed")
	}
	if subj.Needs == "an ask that ended" {
		t.Errorf("a closed visit's ask must not become the subject's needs")
	}
	vc, ok := tileByID(b, "tk-vc")
	if !ok {
		t.Fatalf("the closed visit stays as its own row")
	}
	if vc.Section != SectionDone {
		t.Errorf("the closed visit bands done: got %q", vc.Section)
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
