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
