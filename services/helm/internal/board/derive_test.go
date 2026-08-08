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
// tools/helm-surface-fixture.sh: three epics (two stranded, one with a
// closed child) and a decision. The assertions mirror the fixture's
// eq/has checks for the fields this port carries.
func TestFourAnchorBoard(t *testing.T) {
	anchors := []Anchor{
		{ID: "tk-one", Title: "CI mystery", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(3), Children: []Child{
			{ID: "tk-hh1", Status: "open"},
		}},
		{ID: "tk-epic", Title: "Big epic", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), Children: []Child{
			{ID: "tk-a", Status: "open"}, {ID: "tk-b", Status: "closed"},
		}},
		{ID: "sl-dec", Title: "Pick a path", Kind: "decision", Source: "decision", Rig: "signal-loom", Prefix: "sl", Priority: ptr(1)},
		{ID: "tk-two", Title: "Stale spec", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(4), Children: []Child{
			{ID: "tk-hw1", Status: "open"},
		}},
	}

	b := BuildBoard(anchors, fixtureNow, false, nil)

	if got := len(b.Tiles); got != 4 {
		t.Fatalf("all four anchors admitted: want 4, got %d", got)
	}
	if got := b.Tiles[0].Severity; got != SevHigh {
		t.Errorf("top row is a stranded epic: want HIGH, got %s", got)
	}
	// the stranded epic floats above the decision.
	epic, _ := tileByID(b, "tk-epic")
	dec, _ := tileByID(b, "sl-dec")
	if !(epic.RankScore > dec.RankScore) {
		t.Errorf("stranded epic must outrank the decision: epic=%d decision=%d", epic.RankScore, dec.RankScore)
	}

	// Severity of the stranded epic: open work, none in progress.
	if epic.Severity != SevHigh {
		t.Errorf("stranded epic is HIGH: got %s", epic.Severity)
	}
	if !strings.Contains(epic.Frontier, "stranded") {
		t.Errorf("stranded epic frontier says stranded: got %q", epic.Frontier)
	}
	// Decision is ELEVATED.
	if dec.Severity != SevElevated {
		t.Errorf("decision is ELEVATED: got %s", dec.Severity)
	}

	// Counts on the epic.
	if epic.MTotal != 2 || epic.NClosed != 1 || epic.Open != 1 || epic.InProgress != 0 {
		t.Errorf("epic counts: m=%d closed=%d open=%d inprog=%d", epic.MTotal, epic.NClosed, epic.Open, epic.InProgress)
	}
}

// TestDedupKeepsHigherBand verifies that an id gathered twice survives once,
// in its higher band — the sort-then-dedup contract from gc-helm.sh.
func TestDedupKeepsHigherBand(t *testing.T) {
	anchors := []Anchor{
		{ID: "tk-dup", Title: "as epic", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), Children: []Child{
			{ID: "c1", Status: "open"},
		}},
		{ID: "tk-dup", Title: "as convoy", Kind: "convoy", Source: "convoy", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), Children: []Child{
			{ID: "c2", Status: "closed"},
		}},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil)
	if len(b.Tiles) != 1 {
		t.Fatalf("dedup by id: want 1 tile, got %d", len(b.Tiles))
	}
	if b.Tiles[0].Severity != SevHigh {
		t.Errorf("dedup keeps the higher (HIGH, stranded-epic) band: got %s", b.Tiles[0].Severity)
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
	b := BuildBoard(anchors, fixtureNow, false, nil)
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
// (the default branch of severity).
func TestInProgressNotStranded(t *testing.T) {
	anchors := []Anchor{
		{ID: "tk-busy", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), Children: []Child{
			{ID: "b1", Status: "in_progress"}, {ID: "b2", Status: "open"},
		}},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil)
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
