package board

import (
	"strings"
	"testing"
	"time"
)

func ptr(i int) *int { return &i }

// fixtureNow is the fixed "now" every case derives against. Anchors that leave
// UpdatedAt zero read as staleness 0, so cases predating tk-x89rn keep their
// original expectations.
var fixtureNow = time.Date(2026, 6, 30, 12, 0, 0, 0, time.UTC)

// daysAgo builds an updated_at that many days before fixtureNow.
func daysAgo(d int) time.Time { return fixtureNow.Add(-time.Duration(d) * 24 * time.Hour) }

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

// TestMetadataKindDerivation covers the two kinds tk-2v08m gathers by metadata.
// Neither carries a roll-up, so the count branches below them must not run —
// falling through would read both as empty anchors and file them under LOW.
func TestMetadataKindDerivation(t *testing.T) {
	anchors := []Anchor{
		{ID: "tk-human", Title: "Disposition: one PR needs the operator", Kind: "human", Source: "human",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(1), UpdatedAt: daysAgo(4)},
		{ID: "tk-parked", Title: "helm returns the raw script path", Kind: "parked", Source: "parked",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1)},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil)

	human, ok := tileByID(b, "tk-human")
	if !ok {
		t.Fatal("the human-routed tile is missing")
	}
	// Same band as a decision, for the same reason: no agent will take it.
	if human.Severity != SevElevated {
		t.Errorf("a human-routed bead is ELEVATED, not %s — it is human-gated the way a decision is", human.Severity)
	}
	if !strings.Contains(human.Frontier, "routed to the operator") {
		t.Errorf("frontier must say who owns it: %q", human.Frontier)
	}
	if human.Needs != "operator action" {
		t.Errorf("needs: %q", human.Needs)
	}

	parked, ok := tileByID(b, "tk-parked")
	if !ok {
		t.Fatal("the parked tile is missing")
	}
	// LOW is the whole point: the bead asks that a parked conversation NOT
	// compete for ranking with stranded epics. It has to be findable, not
	// urgent.
	if parked.Severity != SevLow {
		t.Errorf("a parked conversation is LOW, not %s", parked.Severity)
	}
	if !strings.Contains(parked.Frontier, "parked") {
		t.Errorf("frontier: %q", parked.Frontier)
	}
	// The resume GESTURE, not a sentence derived from the takeaway — that is
	// tk-x55wt's bead.
	if !strings.Contains(parked.Needs, "prefix+a") {
		t.Errorf("needs must name the resume gesture: %q", parked.Needs)
	}
}

// TestParkedNeverOutranksAttention pins the LOW band's job: a parked
// conversation at maximum priority and age must still sort under ordinary
// in-flight work, or it is competing for exactly the attention the bead says it
// should not ask for.
func TestParkedNeverOutranksAttention(t *testing.T) {
	anchors := []Anchor{
		{ID: "tk-parked", Title: "ancient parked visit", Kind: "parked", Source: "parked",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(1), UpdatedAt: daysAgo(400)},
		{ID: "tk-live", Title: "healthy in-flight epic", Kind: "epic", Source: "epic",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(4), UpdatedAt: fixtureNow, Children: []Child{
				{ID: "c1", Status: "in_progress"},
			}},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil)
	if b.Tiles[0].ID != "tk-live" {
		t.Errorf("in-flight work sorts above a parked conversation: got %q first", b.Tiles[0].ID)
	}
	parked, _ := tileByID(b, "tk-parked")
	// The NORMAL->ELEVATED stale bump is guarded on NORMAL, so age cannot
	// promote a parked row out of its band however old it gets.
	if parked.Severity != SevLow {
		t.Errorf("400 days stale must not promote a parked row: got %s", parked.Severity)
	}
	if parked.StaleDays != 400 {
		t.Errorf("the tile still reports the real age: got %d", parked.StaleDays)
	}
}

// TestMetadataKindDedup: one bead carrying both markers is gathered twice, and
// the higher band wins — the operator sees the thing they must act on, not the
// note that it was parked.
func TestMetadataKindDedup(t *testing.T) {
	anchors := []Anchor{
		{ID: "tk-both", Title: "routed and parked", Kind: "parked", Source: "parked",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1)},
		{ID: "tk-both", Title: "routed and parked", Kind: "human", Source: "human",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1)},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil)
	if len(b.Tiles) != 1 {
		t.Fatalf("dedup by id: want 1 tile, got %d", len(b.Tiles))
	}
	if b.Tiles[0].Kind != "human" || b.Tiles[0].Severity != SevElevated {
		t.Errorf("dedup keeps the higher band: got kind=%s severity=%s", b.Tiles[0].Kind, b.Tiles[0].Severity)
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
	lowMax := rankScore(SevLow, 10_000, ptr(1), 10_000) // weight and stale both capped at 999
	normalMin := rankScore(SevNormal, 0, ptr(4), 0)
	if lowMax >= normalMin {
		t.Errorf("severity lanes overlap: LOW(maxweight)=%d >= NORMAL(minweight)=%d", lowMax, normalMin)
	}
}

// TestStaleDays covers the staleness derivation restored by tk-x89rn, including
// the two cases gc-helm.sh does not have to handle: an unreadable updated_at,
// and a timestamp in the future.
func TestStaleDays(t *testing.T) {
	cases := []struct {
		name    string
		updated time.Time
		want    int
	}{
		{"zero updated_at reads as fresh, never stale", time.Time{}, 0},
		{"same instant", fixtureNow, 0},
		{"partial day floors down", fixtureNow.Add(-23 * time.Hour), 0},
		{"exactly one day", daysAgo(1), 1},
		{"two weeks", daysAgo(14), 14},
		{"future timestamp floors to 0", fixtureNow.Add(48 * time.Hour), 0},
		{"an ancient anchor reports its real age, uncapped", daysAgo(5000), 5000},
	}
	for _, c := range cases {
		if got := staleDays(c.updated, fixtureNow); got != c.want {
			t.Errorf("%s: staleDays = %d, want %d", c.name, got, c.want)
		}
	}
}

// TestRankStaleLaneStaysBounded pins the other half of that split: the tile may
// report an uncapped age, but rank_score must still cap its units term, or an
// ancient anchor would borrow into the weight lane and outrank its own band.
func TestRankStaleLaneStaysBounded(t *testing.T) {
	ancient := rankScore(SevNormal, 0, ptr(4), 50_000)
	ceiling := rankScore(SevNormal, 0, ptr(4), rankTermCap)
	if ancient != ceiling {
		t.Errorf("stale term must cap at %d: 50000d scored %d, %dd scored %d", rankTermCap, ancient, rankTermCap, ceiling)
	}
	if ancient >= rankScore(SevHigh, 0, ptr(4), 0) {
		t.Error("a maximally stale NORMAL must never reach the HIGH band")
	}
}

// TestStaleBumpFires is the headline behaviour tk-x89rn restores: a NORMAL
// anchor untouched for more than STALE_DAYS is promoted to ELEVATED. Before the
// seam was widened this could never happen, because staleness was a constant 0.
func TestStaleBumpFires(t *testing.T) {
	// Identical anchors but for updated_at: one touched today, one long idle.
	mk := func(id string, upd time.Time) Anchor {
		return Anchor{ID: id, Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2),
			UpdatedAt: upd,
			Children:  []Child{{ID: id + "-a", Status: "in_progress"}, {ID: id + "-b", Status: "open"}}}
	}
	b := BuildBoard([]Anchor{mk("tk-fresh", daysAgo(1)), mk("tk-idle", daysAgo(40))}, fixtureNow, false, nil)

	fresh, _ := tileByID(b, "tk-fresh")
	idle, _ := tileByID(b, "tk-idle")

	if fresh.Severity != SevNormal {
		t.Errorf("recently-touched in-flight epic stays NORMAL: got %s", fresh.Severity)
	}
	if idle.Severity != SevElevated {
		t.Errorf("epic idle for 40d bumps NORMAL->ELEVATED: got %s", idle.Severity)
	}
	if fresh.StaleDays != 1 || idle.StaleDays != 40 {
		t.Errorf("stale_days surfaced on the tile: fresh=%d idle=%d (want 1, 40)", fresh.StaleDays, idle.StaleDays)
	}
	// The bump is a real band change, so it must reorder the board.
	if !(idle.RankScore > fresh.RankScore) {
		t.Errorf("the stale anchor must outrank the fresh one: idle=%d fresh=%d", idle.RankScore, fresh.RankScore)
	}
	// Exactly at the threshold is NOT stale — gc-helm.sh bumps on `> 14`.
	atThreshold := BuildBoard([]Anchor{mk("tk-edge", daysAgo(staleThresholdDays))}, fixtureNow, false, nil)
	if got := atThreshold.Tiles[0].Severity; got != SevNormal {
		t.Errorf("exactly %d days is not yet stale: got %s", staleThresholdDays, got)
	}
}

// TestStaleDoesNotBumpOtherBands confirms the bump is scoped to NORMAL: a
// stranded (HIGH) anchor stays HIGH and a decision stays ELEVATED, however old.
func TestStaleDoesNotBumpOtherBands(t *testing.T) {
	anchors := []Anchor{
		{ID: "tk-stranded", Kind: "epic", Source: "epic", Priority: ptr(2), UpdatedAt: daysAgo(400),
			Children: []Child{{ID: "s1", Status: "open"}}},
		{ID: "tk-dec", Kind: "decision", Source: "decision", Priority: ptr(2), UpdatedAt: daysAgo(400)},
		{ID: "tk-done", Kind: "epic", Source: "epic", Priority: ptr(2), UpdatedAt: daysAgo(400),
			Children: []Child{{ID: "d1", Status: "closed"}}},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil)
	for id, want := range map[string]Severity{"tk-stranded": SevHigh, "tk-dec": SevElevated, "tk-done": SevLow} {
		if tl, _ := tileByID(b, id); tl.Severity != want {
			t.Errorf("%s: severity %s, want %s (staleness must not move this band)", id, tl.Severity, want)
		}
	}
}

// TestTileCarriesUpdatedAt pins the distinction the wire contract depends on:
// stale_days 0 is ambiguous on its own, so updated_at rides alongside to
// separate "genuinely fresh" from "the source could not read it".
func TestTileCarriesUpdatedAt(t *testing.T) {
	b := BuildBoard([]Anchor{
		{ID: "tk-known", Kind: "epic", Source: "epic", Priority: ptr(2), UpdatedAt: fixtureNow},
		{ID: "tk-unknown", Kind: "epic", Source: "epic", Priority: ptr(2)},
	}, fixtureNow, false, nil)

	known, _ := tileByID(b, "tk-known")
	unknown, _ := tileByID(b, "tk-unknown")
	if known.StaleDays != 0 || unknown.StaleDays != 0 {
		t.Fatalf("both read stale_days 0: known=%d unknown=%d", known.StaleDays, unknown.StaleDays)
	}
	if known.UpdatedAt.IsZero() {
		t.Error("a readable updated_at must reach the tile")
	}
	if !unknown.UpdatedAt.IsZero() {
		t.Error("an unreadable updated_at must stay zero, not be approximated as now")
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
