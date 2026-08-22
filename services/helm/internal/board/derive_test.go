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

// liveOwners builds a Facts in which every named session is alive. Since
// tk-134d7 a child is only "moving" when its owning session is demonstrably
// live, so any case that means "work is in flight" has to say whose.
func liveOwners(names ...string) Facts {
	st := map[string]string{}
	for _, n := range names {
		st[n] = "active"
	}
	return Facts{OwnerState: st}
}

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

	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})

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
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})

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
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})
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

// TestParkedDispositionDue covers the derivation tk-2plde asks for: a parked
// conversation that routed work out of a sitting carries a `blocks` edge to
// that work, and once every blocker has closed the row is no longer "wants
// nothing" — it owes a disposition.
//
// The pre-fix board could not express this. tk-yps55 sat parked for 29 hours
// carrying "routed — tk-hgmob slung; nothing further needed here" AFTER
// tk-hgmob merged, and the next sitting was spent rediscovering that.
func TestParkedDispositionDue(t *testing.T) {
	anchors := []Anchor{
		// Every blocker closed: the wait is over.
		{ID: "tk-done", Title: "routed; nothing further needed here", Kind: "parked", Source: "parked",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1),
			Takeaway:        "routed — fix+guard ruled; tk-hgmob slung. Nothing further needed here.",
			WaitingOn:       []string{"tk-hgmob"},
			WaitingOnClosed: []string{"tk-hgmob"}},
		// One of two still open: a live hold, and it must stay quiet.
		{ID: "tk-hold", Title: "holding — awaiting the fix", Kind: "parked", Source: "parked",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1),
			Takeaway:        "holding — awaiting tk-aaa and tk-bbb",
			WaitingOn:       []string{"tk-aaa", "tk-bbb"},
			WaitingOnClosed: []string{"tk-aaa"}},
		// No edges at all — every parked row in the city before the writer
		// starts recording them. It must render exactly as it did before.
		{ID: "tk-bare", Title: "parked, no edges", Kind: "parked", Source: "parked",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1)},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})

	done, ok := tileByID(b, "tk-done")
	if !ok {
		t.Fatal("the discharged parked tile is missing")
	}
	if !done.DispositionDue {
		t.Error("every blocker closed: the row owes a disposition")
	}
	// ELEVATED, not LOW: it has to leave the floor to be seen at all, and the
	// floor is what made a finished topic look like a live hold.
	if done.Severity != SevElevated {
		t.Errorf("a discharged parked row is ELEVATED, not %s", done.Severity)
	}
	if !strings.Contains(done.Frontier, "blocker landed") {
		t.Errorf("frontier must say the wait ended: %q", done.Frontier)
	}
	// The takeaway is exactly what has gone stale — it still says the work was
	// just dispatched — so the deterministic phrase must outrank it here, and
	// ONLY here.
	if done.Needs != "blocker landed — dispose or resume" {
		t.Errorf("the stale takeaway must not answer for this row: needs=%q", done.Needs)
	}
	if done.Takeaway == nil || !strings.Contains(*done.Takeaway, "fix+guard") {
		t.Error("the takeaway itself stays on the wire for anyone reading the row")
	}
	if len(done.WaitingOnOpen) != 0 {
		t.Errorf("nothing is outstanding: %v", done.WaitingOnOpen)
	}

	hold, _ := tileByID(b, "tk-hold")
	if hold.DispositionDue {
		t.Error("one blocker still open is a LIVE hold, not a disposition")
	}
	if hold.Severity != SevLow {
		t.Errorf("a live hold stays on the floor: got %s", hold.Severity)
	}
	if len(hold.WaitingOnOpen) != 1 || hold.WaitingOnOpen[0] != "tk-bbb" {
		t.Errorf("the outstanding blocker is named: %v", hold.WaitingOnOpen)
	}
	if !strings.Contains(hold.Frontier, "waiting on 1") {
		t.Errorf("frontier counts what is outstanding: %q", hold.Frontier)
	}
	// The takeaway still answers for a row that is genuinely waiting.
	if hold.Needs != "holding — awaiting tk-aaa and tk-bbb" {
		t.Errorf("needs: %q", hold.Needs)
	}

	bare, _ := tileByID(b, "tk-bare")
	if bare.DispositionDue {
		t.Error("no edges is not a discharged wait — it is no wait at all")
	}
	if bare.Severity != SevLow || !strings.Contains(bare.Frontier, "takeaway recorded") {
		t.Errorf("an edgeless parked row is unchanged: sev=%s frontier=%q", bare.Severity, bare.Frontier)
	}
	// Non-nil empty, matching jq's `[]` rather than a JSON null.
	if bare.WaitingOn == nil || bare.WaitingOnOpen == nil {
		t.Error("the waiting lists are always emitted as arrays, never null")
	}
}

// TestUnresolvedBlockerStaysQuiet pins the fail-closed direction. A blocker the
// source could not read at all — another rig's store, an `external:` ref, a
// failed query — is absent from WaitingOnClosed, and that must read as "still
// waiting", never as "everything landed". A false promotion invites the
// operator to dispose of a subject whose work is still in flight.
func TestUnresolvedBlockerStaysQuiet(t *testing.T) {
	anchors := []Anchor{
		{ID: "tk-unk", Title: "waiting on something unreadable", Kind: "parked", Source: "parked",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1),
			WaitingOn: []string{"sl-9999"}},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})
	tile, _ := tileByID(b, "tk-unk")
	if tile.DispositionDue {
		t.Error("an unresolvable blocker must not read as discharged")
	}
	if tile.Severity != SevLow {
		t.Errorf("the row keeps its pre-fix band: got %s", tile.Severity)
	}
	if len(tile.WaitingOnOpen) != 1 {
		t.Errorf("the unresolved blocker counts as outstanding: %v", tile.WaitingOnOpen)
	}
}

// TestDispositionDueIsParkedOnly: the promotion is scoped to the kind whose
// band it overrides. A `human` row carrying the same edges is already ELEVATED
// and must not acquire the parked wording.
func TestDispositionDueIsParkedOnly(t *testing.T) {
	anchors := []Anchor{
		{ID: "tk-h", Title: "operator-owned, with a discharged edge", Kind: "human", Source: "human",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1),
			WaitingOn: []string{"tk-x"}, WaitingOnClosed: []string{"tk-x"}},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})
	tile, _ := tileByID(b, "tk-h")
	if tile.DispositionDue {
		t.Error("disposition_due is a parked-row distinction")
	}
	if tile.Needs != "operator action" {
		t.Errorf("the human row keeps its own phrase: %q", tile.Needs)
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
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})
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
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})
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
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})
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
	lowMax := rankScore(SevLow, 10_000, 10_000) // weight and stale both capped at 999
	normalMin := rankScore(SevNormal, 0, 0)
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
	ancient := rankScore(SevNormal, 0, 50_000)
	ceiling := rankScore(SevNormal, 0, rankTermCap)
	if ancient != ceiling {
		t.Errorf("stale term must cap at %d: 50000d scored %d, %dd scored %d", rankTermCap, ancient, rankTermCap, ceiling)
	}
	if ancient >= rankScore(SevHigh, 0, 0) {
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
			Children: []Child{
				{ID: id + "-a", Status: "in_progress", Assignee: "polecat-live"},
				{ID: id + "-b", Status: "open"},
			}}
	}
	live := liveOwners("polecat-live")
	b := BuildBoard([]Anchor{mk("tk-fresh", daysAgo(1)), mk("tk-idle", daysAgo(40))}, fixtureNow, false, nil, live)

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
	atThreshold := BuildBoard([]Anchor{mk("tk-edge", daysAgo(staleThresholdDays))}, fixtureNow, false, nil, live)
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
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})
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
	}, fixtureNow, false, nil, Facts{})

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

// TestInProgressNotStranded confirms an epic whose in-progress child has a LIVE
// owner is NORMAL (the default branch of severity).
func TestInProgressNotStranded(t *testing.T) {
	anchors := []Anchor{
		{ID: "tk-busy", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), Children: []Child{
			{ID: "b1", Status: "in_progress", Assignee: "polecat-live"}, {ID: "b2", Status: "open"},
		}},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, liveOwners("polecat-live"))
	tl := b.Tiles[0]
	if tl.Severity != SevNormal {
		t.Errorf("epic with in-progress work is NORMAL: got %s", tl.Severity)
	}
	if tl.InProgress != 1 || tl.Open != 2 {
		t.Errorf("counts: inprog=%d open=%d (want 1, 2)", tl.InProgress, tl.Open)
	}
	if tl.InProgressLive != 1 || tl.InProgressDead != 0 {
		t.Errorf("liveness split: live=%d dead=%d (want 1, 0)", tl.InProgressLive, tl.InProgressDead)
	}
	if !strings.Contains(tl.Frontier, "1 in flight") {
		t.Errorf("frontier shows in flight: got %q", tl.Frontier)
	}
}

// TestDeadOwnerIsNotMoving is the other half of that split, and the reason the
// liveness join exists: the SAME anchor whose owner has gone is not in flight —
// it is stranded work with a corpse attached, and the board must say so.
func TestDeadOwnerIsNotMoving(t *testing.T) {
	anchors := []Anchor{
		{ID: "tk-busy", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), Children: []Child{
			{ID: "b1", Status: "in_progress", Assignee: "polecat-gone"}, {ID: "b2", Status: "open"},
		}},
	}
	// "polecat-gone" is absent from OwnerState entirely — the canonical orphan.
	b := BuildBoard(anchors, fixtureNow, false, nil, liveOwners("someone-else"))
	tl := b.Tiles[0]
	if tl.InProgress != 1 {
		t.Errorf("raw in_progress still counts the claim: got %d", tl.InProgress)
	}
	if tl.InProgressLive != 0 || tl.InProgressDead != 1 || !tl.DeadOwner {
		t.Errorf("dead owner: live=%d dead=%d flag=%v (want 0, 1, true)", tl.InProgressLive, tl.InProgressDead, tl.DeadOwner)
	}
	if tl.Severity != SevHigh || !tl.Stranded {
		t.Errorf("a dead-owner-only frontier is stranded/HIGH: got %s stranded=%v", tl.Severity, tl.Stranded)
	}
	if got := []string{"b1"}; !equalIDs(tl.DeadOwnerHeads, got) {
		t.Errorf("dead_owner_heads = %v, want %v", tl.DeadOwnerHeads, got)
	}
}

// TestSlungWorkIsInFlight is the false-stranded defect the bash board fixed in
// tk-fkeft, now fixed here too: `gc sling` leaves the work bead at
// status=open/assignee=null and puts the in-flight state on the WORKFLOW, so a
// board reading only child status calls a polecat mid-implementation "stranded".
func TestSlungWorkIsInFlight(t *testing.T) {
	anchors := []Anchor{
		{ID: "tk-slung", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), Children: []Child{
			{ID: "w1", Status: "open"}, // never claimed; the workflow carries it
		}},
	}
	f := liveOwners("gc-toolkit__polecat-lx-1")
	f.Inflight = map[string][]string{"w1": {"gc-toolkit__polecat-lx-1"}}

	b := BuildBoard(anchors, fixtureNow, false, nil, f)
	tl := b.Tiles[0]
	if tl.Severity != SevNormal || tl.Stranded {
		t.Errorf("slung work is in flight, not stranded: got %s stranded=%v", tl.Severity, tl.Stranded)
	}
	if tl.InFlight != 1 || tl.InProgressLive != 1 {
		t.Errorf("in_flight=%d in_progress_live=%d (want 1, 1)", tl.InFlight, tl.InProgressLive)
	}
	if !equalIDs(tl.InFlightHeads, []string{"w1"}) {
		t.Errorf("in_flight_heads = %v, want [w1]", tl.InFlightHeads)
	}
	// A live workflow head is NOT idle, so it must not also appear in open_heads.
	if len(tl.OpenHeads) != 0 {
		t.Errorf("a head in flight must be subtracted from open_heads: got %v", tl.OpenHeads)
	}

	// The same workflow, but its session has drained: back to stranded. Liveness
	// is re-derived at derive time precisely so this flips without a re-gather.
	dead := Facts{Inflight: f.Inflight, OwnerState: map[string]string{"gc-toolkit__polecat-lx-1": "archived"}}
	if tl := BuildBoard(anchors, fixtureNow, false, nil, dead).Tiles[0]; !tl.Stranded {
		t.Errorf("a drained workflow stops counting: got severity=%s stranded=%v", tl.Severity, tl.Stranded)
	}
}

// TestHeldAnchorIsNotStranded pins the visit glyph: a conversation IS attention,
// so an anchor someone is conversing about is not flagged for lacking it.
func TestHeldAnchorIsNotStranded(t *testing.T) {
	a := Anchor{ID: "tk-held", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2),
		Children: []Child{{ID: "c1", Status: "open"}}}

	bare := BuildBoard([]Anchor{a}, fixtureNow, false, nil, Facts{}).Tiles[0]
	if bare.Severity != SevHigh || bare.Held {
		t.Fatalf("without a visit the anchor is stranded/HIGH: got %s held=%v", bare.Severity, bare.Held)
	}

	held := BuildBoard([]Anchor{a}, fixtureNow, false, nil, Facts{Visits: map[string]bool{"tk-held": true}}).Tiles[0]
	if !held.Held || held.Severity != SevNormal || held.Stranded {
		t.Errorf("a held anchor is NORMAL and not stranded: got %s held=%v stranded=%v", held.Severity, held.Held, held.Stranded)
	}
	if held.Needs != "open to join" {
		t.Errorf("needs names the conversation: got %q", held.Needs)
	}
}

// TestTakeawayWinsNeeds: the LLM headline replaces the deterministic phrase, and
// its internal whitespace is collapsed so it cannot break the terminal table.
func TestTakeawayWinsNeeds(t *testing.T) {
	a := Anchor{ID: "tk-parked", Kind: "parked", Source: "parked", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(3),
		Takeaway: "  needs a  decision\n  from the operator ", TakeawayAt: "2026-06-01T00:00:00Z", TakeawayBy: "host"}
	tl := BuildBoard([]Anchor{a}, fixtureNow, false, nil, Facts{}).Tiles[0]

	if tl.Takeaway == nil || *tl.Takeaway != "needs a decision from the operator" {
		t.Errorf("takeaway collapsed and trimmed: got %v", tl.Takeaway)
	}
	if tl.Needs != "needs a decision from the operator" {
		t.Errorf("takeaway wins NEEDS: got %q", tl.Needs)
	}
	if tl.TakeawayBy == nil || *tl.TakeawayBy != "host" {
		t.Errorf("takeaway_by carried: got %v", tl.TakeawayBy)
	}

	// No takeaway -> the key is null, not absent, and NEEDS falls back.
	plain := BuildBoard([]Anchor{{ID: "tk-p2", Kind: "parked", Source: "parked", Rig: "gc-toolkit", Prefix: "tk"}},
		fixtureNow, false, nil, Facts{}).Tiles[0]
	if plain.Takeaway != nil {
		t.Errorf("absent takeaway is null: got %v", plain.Takeaway)
	}
	if plain.Needs != "resume: prefix+a, then the bead id" {
		t.Errorf("fallback NEEDS: got %q", plain.Needs)
	}
}

// TestCrossRigRefsWeighAnchor pins the prose scan: another rig's bead id in the
// body adds weight (blast radius), capped, and never matches this rig's own
// prefix, a rig NAME, or the anchor itself.
func TestCrossRigRefsWeighAnchor(t *testing.T) {
	f := Facts{Prefixes: []string{"tk", "sl", "su"}, RigNames: []string{"gc-toolkit", "signal-loom"}}
	a := Anchor{ID: "tk-xref", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(3),
		Description: "blocks sl-abc12 and su-9zz, follows tk-local1 and tk-xref itself",
		Children:    []Child{{ID: "c1", Status: "open"}}}

	tl := BuildBoard([]Anchor{a}, fixtureNow, false, nil, f).Tiles[0]
	if !equalIDs(tl.CrossRigRefs, []string{"sl-abc12", "su-9zz"}) {
		t.Errorf("cross_rig_refs = %v, want [sl-abc12 su-9zz] (own prefix and self excluded)", tl.CrossRigRefs)
	}
	// weight = m_total(1) + prio_w(3)=1 + min(2 refs, cap)
	if tl.Weight != 1+1+2 {
		t.Errorf("weight folds the ref count: got %d, want 4", tl.Weight)
	}

	// A decision is banded by what it IS, so the scan is skipped entirely.
	dec := Anchor{ID: "sl-dec", Kind: "decision", Source: "decision", Rig: "signal-loom", Prefix: "sl",
		Description: "mentions tk-abc12"}
	if refs := BuildBoard([]Anchor{dec}, fixtureNow, false, nil, f).Tiles[0].CrossRigRefs; len(refs) != 0 {
		t.Errorf("a decision is not scanned: got %v", refs)
	}

	// Single-rig city: the "other prefixes" set is empty, so nothing matches.
	// (jq's empty alternation would match a bare "-abc" here; see crossRigRefs.)
	solo := Facts{Prefixes: []string{"tk"}, RigNames: []string{"gc-toolkit"}}
	if refs := BuildBoard([]Anchor{a}, fixtureNow, false, nil, solo).Tiles[0].CrossRigRefs; len(refs) != 0 {
		t.Errorf("no other rigs, no refs: got %v", refs)
	}
}

// TestUnownedConvoyIsHigh: under the everything-is-owned law an unowned
// non-machine convoy is the orphan the observer exists to catch.
func TestUnownedConvoyIsHigh(t *testing.T) {
	no, yes := false, true
	anchors := []Anchor{
		{ID: "tk-orphan", Kind: "unowned", Source: "unowned", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(3), Owned: &no},
		{ID: "tk-owncv", Kind: "convoy", Source: "convoy", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(3), Owned: &yes,
			Children: []Child{{ID: "m1", Status: "closed"}}},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})

	orphan, _ := tileByID(b, "tk-orphan")
	if orphan.Severity != SevHigh {
		t.Errorf("unowned convoy is HIGH: got %s", orphan.Severity)
	}
	if orphan.Owned == nil || *orphan.Owned {
		t.Errorf("owned=false is carried, not dropped: got %v", orphan.Owned)
	}
	// It has no roll-up, but `empty` is reserved for anchors that should have
	// had one — an unowned convoy is excluded by construction.
	if orphan.Empty {
		t.Error("an unowned convoy is not an `empty` anchor")
	}

	owncv, _ := tileByID(b, "tk-owncv")
	if !owncv.Complete || owncv.Severity != SevLow {
		t.Errorf("an all-closed owned convoy is complete/LOW: got %s complete=%v", owncv.Severity, owncv.Complete)
	}
	if owncv.Needs != "all 1 closed — graduate" {
		t.Errorf("a complete convoy graduates: got %q", owncv.Needs)
	}
}

// TestProgressMismatch: the convoy's own closed/total claim disagreeing with the
// membership actually rolled up is a real signal, and absent progress is not one.
func TestProgressMismatch(t *testing.T) {
	kids := []Child{{ID: "m1", Status: "closed"}, {ID: "m2", Status: "open"}}
	mk := func(id string, p *Progress) Anchor {
		return Anchor{ID: id, Kind: "convoy", Source: "convoy", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(3),
			Progress: p, Children: kids}
	}
	b := BuildBoard([]Anchor{
		mk("tk-agree", &Progress{Closed: 1, Total: 2}),
		mk("tk-differ", &Progress{Closed: 0, Total: 5}),
		mk("tk-none", nil),
	}, fixtureNow, false, nil, Facts{})

	if tl, _ := tileByID(b, "tk-agree"); tl.ProgressMismatch {
		t.Error("matching progress is not a mismatch")
	}
	if tl, _ := tileByID(b, "tk-differ"); !tl.ProgressMismatch {
		t.Error("a disagreeing progress object is a mismatch")
	}
	if tl, _ := tileByID(b, "tk-none"); tl.ProgressMismatch {
		t.Error("an absent progress object makes no claim to disagree with")
	}
}

// equalIDs compares two id lists for exact contents and order.
func equalIDs(got, want []string) bool {
	if len(got) != len(want) {
		return false
	}
	for i := range got {
		if got[i] != want[i] {
			return false
		}
	}
	return true
}
