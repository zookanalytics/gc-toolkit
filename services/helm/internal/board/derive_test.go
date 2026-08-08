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
// tools/helm-surface-fixture.sh (lines 63-104): one hot-hosted epic, a
// stranded epic, a decision, and a warm-hosted epic. The assertions mirror
// the fixture's eq/has checks exactly.
func TestFourAnchorBoard(t *testing.T) {
	anchors := []Anchor{
		{ID: "tk-hosthot", Title: "CI mystery", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(3), Children: []Child{
			{ID: "tk-hh1", Status: "open"},
		}},
		{ID: "tk-epic", Title: "Big epic", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), Children: []Child{
			{ID: "tk-a", Status: "open"}, {ID: "tk-b", Status: "closed"},
		}},
		{ID: "sl-dec", Title: "Pick a path", Kind: "decision", Source: "decision", Rig: "signal-loom", Prefix: "sl", Priority: ptr(1)},
		{ID: "tk-hostwarm", Title: "Stale spec", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(4), Children: []Child{
			{ID: "tk-hw1", Status: "open"},
		}},
	}
	// Bead-host sessions: alias <pack>.<bead-id>, keyed by bead-id by the source.
	sessions := map[string]HostSession{
		"tk-hosthot":  {State: "active", Running: true},
		"tk-hostwarm": {State: "suspended", Running: false},
	}

	b := BuildBoard(anchors, sessions, fixtureNow, false, nil)

	if got := len(b.Tiles); got != 4 {
		t.Fatalf("all four anchors admitted: want 4, got %d", got)
	}
	if got := b.Tiles[0].Severity; got != SevHigh {
		t.Errorf("top row is the stranded epic: want HIGH, got %s", got)
	}
	// the stranded epic floats above the decision.
	epic, _ := tileByID(b, "tk-epic")
	dec, _ := tileByID(b, "sl-dec")
	if !(epic.RankScore > dec.RankScore) {
		t.Errorf("stranded epic must outrank the decision: epic=%d decision=%d", epic.RankScore, dec.RankScore)
	}

	// Liveness join.
	if fh, _ := tileByID(b, "tk-hosthot"); fh.Live != LiveHot {
		t.Errorf("hot host resolves hot: got %s", fh.Live)
	}
	if fw, _ := tileByID(b, "tk-hostwarm"); fw.Live != LiveWarm {
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
	if dec.Severity != SevElevated {
		t.Errorf("decision is ELEVATED: got %s", dec.Severity)
	}

	// frontier reflects the hot host (in conversation, not stranded).
	if fh, _ := tileByID(b, "tk-hosthot"); !strings.Contains(fh.Frontier, "in conversation") {
		t.Errorf("hot-hosted frontier reads in-conversation: got %q", fh.Frontier)
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
	b := BuildBoard(anchors, nil, fixtureNow, false, nil)
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
