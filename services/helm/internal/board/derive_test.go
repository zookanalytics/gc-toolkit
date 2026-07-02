package board

import (
	"strings"
	"testing"
	"time"
)

func ptr(i int) *int { return &i }

// fixtureNow is an arbitrary fixed timestamp; the spike never reads updated_at
// so the exact value does not affect any assertion.
var fixtureNow = time.Date(2026, 6, 30, 12, 0, 0, 0, time.UTC)

// tileByID is a test helper.
func tileByID(b Board, id string) (Tile, bool) {
	for _, t := range b.Tiles {
		if t.ID == id {
			return t, true
		}
	}
	return Tile{}, false
}

// TestFourAnchorBoard reproduces the primary golden case from
// tools/helm-surface-fixture.sh (lines 63-104): one hot-hosted flagged
// bead, a stranded epic, a decision, and a warm-hosted flagged bead. The
// assertions mirror the fixture's eq/has checks exactly.
func TestFourAnchorBoard(t *testing.T) {
	anchors := []Anchor{
		{ID: "tk-flaghot", Title: "CI mystery", Kind: "flagged", Source: "flagged", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(3), Reason: "CI red, cause unknown"},
		{ID: "tk-epic", Title: "Big epic", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), Children: []Child{
			{ID: "tk-a", Status: "open"}, {ID: "tk-b", Status: "closed"},
		}},
		{ID: "sl-dec", Title: "Pick a path", Kind: "decision", Source: "decision", Rig: "signal-loom", Prefix: "sl", Priority: ptr(1)},
		{ID: "tk-flagwarm", Title: "Stale spec", Kind: "flagged", Source: "flagged", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(4), Reason: "needs a re-read"},
	}
	// Bead-host sessions: alias <pack>.<bead-id>, keyed by bead-id by the source.
	sessions := map[string]HostSession{
		"tk-flaghot":  {State: "active", Running: true},
		"tk-flagwarm": {State: "suspended", Running: false},
	}

	b := BuildBoard(anchors, sessions, fixtureNow, false, nil)

	if got := len(b.Tiles); got != 4 {
		t.Fatalf("all four anchors admitted: want 4, got %d", got)
	}
	if got := b.Tiles[0].Severity; got != SevFlagged {
		t.Errorf("top row is a flagged bead: want FLAGGED, got %s", got)
	}
	// flagged floats above the stranded epic.
	epic, _ := tileByID(b, "tk-epic")
	if !(b.Tiles[0].RankScore > epic.RankScore) {
		t.Errorf("flagged must outrank the epic: top=%d epic=%d", b.Tiles[0].RankScore, epic.RankScore)
	}
	// flagged kind count.
	flaggedCount := 0
	for _, tl := range b.Tiles {
		if tl.Kind == "flagged" {
			flaggedCount++
		}
	}
	if flaggedCount != 2 {
		t.Errorf("flagged kind present: want 2, got %d", flaggedCount)
	}

	// Liveness join.
	if fh, _ := tileByID(b, "tk-flaghot"); fh.Live != LiveHot {
		t.Errorf("hot host resolves hot: got %s", fh.Live)
	}
	if fw, _ := tileByID(b, "tk-flagwarm"); fw.Live != LiveWarm {
		t.Errorf("suspended host is warm: got %s", fw.Live)
	}
	if e, _ := tileByID(b, "tk-epic"); e.Live != LiveCold {
		t.Errorf("no host is cold: got %s", e.Live)
	}

	// Severity of the stranded epic: open work, none in progress, no host.
	if epic.Severity != SevHigh {
		t.Errorf("stranded epic is HIGH: got %s", epic.Severity)
	}
	// Decision is ELEVATED.
	if d, _ := tileByID(b, "sl-dec"); d.Severity != SevElevated {
		t.Errorf("decision is ELEVATED: got %s", d.Severity)
	}

	// frontier carries the flagged reason.
	if fh, _ := tileByID(b, "tk-flaghot"); !strings.Contains(fh.Frontier, "CI red") {
		t.Errorf("flagged frontier carries the reason: got %q", fh.Frontier)
	}

	// Counts on the epic.
	if epic.MTotal != 2 || epic.NClosed != 1 || epic.Open != 1 || epic.InProgress != 0 {
		t.Errorf("epic counts: m=%d closed=%d open=%d inprog=%d", epic.MTotal, epic.NClosed, epic.Open, epic.InProgress)
	}
}

// TestLiveHostSparesStranded reproduces the lines 106-136 golden case: two
// sibling epics with the identical stranded shape (open children, zero
// in-progress); the one with a HOT host stays NORMAL (in conversation), the
// unhosted one stays HIGH (stranded).
func TestLiveHostSparesStranded(t *testing.T) {
	anchors := []Anchor{
		{ID: "tk-hosted", Title: "Hosted epic", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), Children: []Child{
			{ID: "tk-h1", Status: "open"}, {ID: "tk-h2", Status: "open"},
		}},
		{ID: "tk-lonely", Title: "Unhosted epic", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), Children: []Child{
			{ID: "tk-l1", Status: "open"}, {ID: "tk-l2", Status: "open"},
		}},
	}
	sessions := map[string]HostSession{
		"tk-hosted": {State: "active", Running: true},
	}

	b := BuildBoard(anchors, sessions, fixtureNow, false, nil)

	hosted, _ := tileByID(b, "tk-hosted")
	if hosted.Live != LiveHot {
		t.Errorf("hosted epic resolves hot: got %s", hosted.Live)
	}
	if hosted.Severity != SevNormal {
		t.Errorf("hosted epic is NORMAL, not HIGH: got %s", hosted.Severity)
	}
	if !strings.Contains(hosted.Frontier, "in conversation") {
		t.Errorf("hosted epic frontier reads in-conversation: got %q", hosted.Frontier)
	}
	if !strings.Contains(hosted.Needs, "open to join") {
		t.Errorf("hosted epic needs is open-to-join: got %q", hosted.Needs)
	}

	lonely, _ := tileByID(b, "tk-lonely")
	if lonely.Live != LiveCold {
		t.Errorf("unhosted sibling stays cold: got %s", lonely.Live)
	}
	if lonely.Severity != SevHigh {
		t.Errorf("unhosted sibling stays HIGH: got %s", lonely.Severity)
	}
	if !strings.Contains(lonely.Frontier, "stranded") {
		t.Errorf("unhosted sibling frontier says stranded: got %q", lonely.Frontier)
	}
}

// TestDedupKeepsHigherBand verifies that an id gathered twice (e.g. an epic that
// is also flagged) survives once, in its higher (FLAGGED) band — the
// sort-then-dedup contract from gc-helm.sh lines 675-681.
func TestDedupKeepsHigherBand(t *testing.T) {
	anchors := []Anchor{
		{ID: "tk-dup", Title: "as epic", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), Children: []Child{
			{ID: "c1", Status: "open"},
		}},
		{ID: "tk-dup", Title: "as flagged", Kind: "flagged", Source: "flagged", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), Reason: "boom"},
	}
	b := BuildBoard(anchors, nil, fixtureNow, false, nil)
	if len(b.Tiles) != 1 {
		t.Fatalf("dedup by id: want 1 tile, got %d", len(b.Tiles))
	}
	if b.Tiles[0].Severity != SevFlagged {
		t.Errorf("dedup keeps the higher (FLAGGED) band: got %s", b.Tiles[0].Severity)
	}
}

// TestLowSeverity covers the empty and fully-closed LOW cases (severity lines
// 623-624) which the four-anchor case does not exercise.
func TestLowSeverity(t *testing.T) {
	anchors := []Anchor{
		{ID: "tk-empty", Title: "no children", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2)},
		{ID: "tk-done", Title: "all closed", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), Children: []Child{
			{ID: "d1", Status: "closed"}, {ID: "d2", Status: "closed"},
		}},
	}
	b := BuildBoard(anchors, nil, fixtureNow, false, nil)
	if e, _ := tileByID(b, "tk-empty"); e.Severity != SevLow {
		t.Errorf("empty epic is LOW: got %s", e.Severity)
	}
	if d, _ := tileByID(b, "tk-done"); d.Severity != SevLow {
		t.Errorf("fully closed epic is LOW: got %s", d.Severity)
	}
}

// TestRankLanesNonOverlapping asserts the integer-packing invariant: a LOW tile
// with a maximal weight can never outrank a tile one band higher.
func TestRankLanesNonOverlapping(t *testing.T) {
	// A LOW tile cannot be produced with a huge weight via the normal path
	// (LOW means m==0 or all-closed), so test the rankScore function directly.
	lowMax := rankScore(SevLow, 10_000, ptr(1)) // weight capped at 999
	normalMin := rankScore(SevNormal, 0, ptr(4))
	if lowMax >= normalMin {
		t.Errorf("severity lanes overlap: LOW(maxweight)=%d >= NORMAL(minweight)=%d", lowMax, normalMin)
	}
}

// TestInProgressNotStranded confirms an epic with an in-progress child is NORMAL
// even with no host (the default branch of severity).
func TestInProgressNotStranded(t *testing.T) {
	anchors := []Anchor{
		{ID: "tk-busy", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), Children: []Child{
			{ID: "b1", Status: "in_progress"}, {ID: "b2", Status: "open"},
		}},
	}
	b := BuildBoard(anchors, nil, fixtureNow, false, nil)
	tl := b.Tiles[0]
	if tl.Severity != SevNormal {
		t.Errorf("epic with in-progress work is NORMAL: got %s", tl.Severity)
	}
	if tl.InProgress != 1 || tl.Open != 2 {
		t.Errorf("counts: inprog=%d open=%d (want 1, 2)", tl.InProgress, tl.Open)
	}
	if !strings.Contains(tl.Frontier, "1 in-progress") {
		t.Errorf("frontier shows in-progress: got %q", tl.Frontier)
	}
}
