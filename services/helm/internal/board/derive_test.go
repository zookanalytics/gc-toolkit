package board

import (
	"fmt"
	"slices"
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
	// The board leads with the operator's queue, and the decision is the only
	// row here whose next move is a person's. The overview begins under it.
	if got := b.Tiles[0].ID; got != "sl-dec" {
		t.Errorf("the owed decision leads the board: got %s", got)
	}
	if got := b.Tiles[1].Severity; got != SevHigh {
		t.Errorf("the overview still opens on a stranded epic: want HIGH, got %s", got)
	}
	// the stranded epic still outranks the decision on rank_score.
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

// TestMetadataKindDerivation covers the two kinds tk-2v08m gathers by metadata,
// in the shape both have whenever the bead never decomposed: no roll-up, so the
// count branches below them must not run — falling through would read both as
// empty anchors and file them under LOW. The decomposed shape is
// TestParkedWithChildren.
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
	if human.Needs != "routed to you — no question recorded" {
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
	// This fixture recorded no takeaway, so both columns say so rather than
	// dressing an unfinished handoff as a conversation that concluded.
	if parked.Frontier != "conversation parked — no takeaway recorded" {
		t.Errorf("frontier: %q", parked.Frontier)
	}
	if parked.Needs != "parked for you — no question recorded" {
		t.Errorf("needs: %q", parked.Needs)
	}
}

// TestParkedWithChildren covers the defect tk-a9k0l is about: the LOW floor is
// a claim about the bead — "it wants nothing" — and open work hanging under it
// falsifies the claim.
//
// The relation only reaches this kind through `children`. A sitting that routes
// work out of a subject files that work as the subject's CHILD, and beads
// REFUSES a `blocks` edge from a parent to its own descendant, so the canonical
// converse shape carries no waiting edge at all and dispositionDue can never
// fire for it (tk-2cyxo). The source used to hand these kinds an empty child
// slice, which reported zero children AND — because a plain child bead is never
// an anchor in its own right — deleted the open child from every surface: on
// tk-z9nln the audit's remaining deliverable sat open, unassigned and unrouted,
// on no board at all.
func TestParkedWithChildren(t *testing.T) {
	anchors := []Anchor{
		// Decomposed, and the child is going nowhere.
		{ID: "tk-stranded", Title: "audit the workflow; deliverable C outstanding", Kind: "parked", Source: "parked",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1),
			Takeaway: "next sitting when the findings land", Children: []Child{
				{ID: "tk-done", Status: "closed"},
				{ID: "tk-open", Status: "open"},
			}},
		// Decomposed, and the child is being worked right now.
		{ID: "tk-moving", Title: "routed; implementation in flight", Kind: "parked", Source: "parked",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1),
			Children: []Child{{ID: "tk-wip", Status: "in_progress", Assignee: "polecat-live"}}},
		// Decomposed, and every child has landed.
		{ID: "tk-landed", Title: "routed; the work merged", Kind: "parked", Source: "parked",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1),
			Children: []Child{{ID: "tk-c1", Status: "closed"}, {ID: "tk-c2", Status: "closed"}}},
		// Never decomposed: the floor is still right for this one.
		{ID: "tk-bare", Title: "a conversation that concluded", Kind: "parked", Source: "parked",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1)},
		// The other metadata-keyed kind, decomposed: its band comes from the
		// marker, so children change the roll-up and nothing else.
		{ID: "tk-human", Title: "the operator owns this, and it decomposed", Kind: "human", Source: "human",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1),
			Children: []Child{{ID: "tk-hk", Status: "open"}}},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, liveOwners("polecat-live"))

	stranded, ok := tileByID(b, "tk-stranded")
	if !ok {
		t.Fatal("the decomposed parked tile is missing")
	}
	if stranded.MTotal != 2 || stranded.NClosed != 1 || stranded.Open != 1 {
		t.Errorf("the roll-up must be real: got %d/%d with %d open", stranded.NClosed, stranded.MTotal, stranded.Open)
	}
	if !equalIDs(stranded.OpenHeads, []string{"tk-open"}) {
		t.Errorf("the open child must be nameable from the row: %v", stranded.OpenHeads)
	}
	if stranded.Severity != SevHigh {
		t.Errorf("open work under a parked subject outranks the floor: got %s", stranded.Severity)
	}
	if !stranded.Stranded {
		t.Error("a frontier with nothing live in it is stranded, whatever kind the parent is")
	}
	if stranded.Frontier != "1 open · 0 in flight (stranded)" {
		t.Errorf("the frontier must explain the band it was given: %q", stranded.Frontier)
	}
	// The takeaway still answers for the row. It is the sitting's own sentence
	// and nothing here has made it stale — only dispositionDue overrides it.
	if stranded.Needs != "next sitting when the findings land" {
		t.Errorf("the takeaway is still the NEEDS answer: %q", stranded.Needs)
	}

	moving, _ := tileByID(b, "tk-moving")
	if moving.Severity != SevNormal {
		t.Errorf("a parked subject whose child is being worked is active: got %s", moving.Severity)
	}
	if moving.Frontier != "1 open · 1 in flight" {
		t.Errorf("frontier: %q", moving.Frontier)
	}

	// Every child closed. The band is LOW either way, so this is not about
	// ranking: it is about the row being ABLE to say the work it routed has
	// landed. Before this, "never decomposed" and "decomposed, all landed" were
	// the same MTotal=0 row and no sweep could tell them apart (tk-2cyxo).
	landed, _ := tileByID(b, "tk-landed")
	if landed.MTotal != 2 || landed.NClosed != 2 || !landed.Complete {
		t.Errorf("a finished roll-up is still reported: %d/%d complete=%v",
			landed.NClosed, landed.MTotal, landed.Complete)
	}
	if landed.Severity != SevLow {
		t.Errorf("promoting this row is tk-2cyxo's call, not this one's: got %s", landed.Severity)
	}
	if landed.Frontier != "all 2 closed · 0 open" {
		t.Errorf("the frontier stops claiming it wants nothing: %q", landed.Frontier)
	}

	bare, _ := tileByID(b, "tk-bare")
	if bare.Severity != SevLow || bare.MTotal != 0 {
		t.Errorf("a childless parked row is untouched: %s %d children", bare.Severity, bare.MTotal)
	}
	if bare.Frontier != "conversation parked — no takeaway recorded" {
		t.Errorf("…and reports what this one actually left: %q", bare.Frontier)
	}
	if bare.Needs != "parked for you — no question recorded" {
		t.Errorf("…in both columns: %q", bare.Needs)
	}

	human, _ := tileByID(b, "tk-human")
	if human.MTotal != 1 {
		t.Errorf("a human-routed bead rolls up its children too: got %d", human.MTotal)
	}
	if human.Severity != SevElevated {
		t.Errorf("…and its band still comes from the marker, not the counts: got %s", human.Severity)
	}

	// The floor was the thing hiding it: a decomposed subject has to sort above
	// one that concluded, or the promotion buys nothing on a capped board.
	if stranded.RankScore <= bare.RankScore {
		t.Errorf("a decomposed parked row outranks a floored one: %d <= %d", stranded.RankScore, bare.RankScore)
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
	if tile.Needs != "routed to you — no question recorded" {
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
	lowMax := rankScore(SevLow, 10_000, 10_000, 0) // weight and stale both capped at 999
	normalMin := rankScore(SevNormal, 0, 0, 0)
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
	ancient := rankScore(SevNormal, 0, 50_000, 0)
	ceiling := rankScore(SevNormal, 0, rankTermCap, 0)
	if ancient != ceiling {
		t.Errorf("stale term must cap at %d: 50000d scored %d, %dd scored %d", rankTermCap, ancient, rankTermCap, ceiling)
	}
	if ancient >= rankScore(SevHigh, 0, 0, 0) {
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
	if plain.Needs != "parked for you — no question recorded" {
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

// ── the stand-down rule (tk-b3rga) ───────────────────────────────────────────
//
// A decision and a human-routed bead are banded by what they ARE, and what they
// are never changes while the bead is open. So the row asked for the operator on
// the day it was filed and went on asking after they answered it: on the
// 2026-08-23 board, seven of 24 ELEVATED rows carried a takeaway recording their
// own ruling, one of them for thirty days.

// TestRuledStandsDown is the headline case: answered, nothing outstanding, so
// the row leaves the attention band and says what it now wants instead.
func TestRuledStandsDown(t *testing.T) {
	anchors := []Anchor{
		// The regression case named on the bead: ruled 2026-07-24, still
		// ELEVATED thirty days later. No waiting edges at all — "every wait
		// landed" is vacuously true, which is the common shape.
		{ID: "tk-z130v", Title: "excise the fork", Kind: "decision", Source: "decision",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(1), UpdatedAt: daysAgo(30),
			Takeaway: "ROUTED: mayor mailed to excise gc-8yr6px"},
		// The same state reached through a discharged edge.
		{ID: "tk-lpf9g", Title: "fragment vs prompt body", Kind: "decision", Source: "decision",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1),
			Takeaway:  "accepted — crux ANSWERED YES",
			WaitingOn: []string{"tk-vvnkj"}, WaitingOnClosed: []string{"tk-vvnkj"}},
		// And on the other human-gated kind.
		{ID: "tk-j5wrs", Title: "membership predicate", Kind: "human", Source: "human",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1),
			Takeaway:  "routed — design ruled; tk-vie5k slung",
			WaitingOn: []string{"tk-vie5k"}, WaitingOnClosed: []string{"tk-vie5k"}},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})

	for _, id := range []string{"tk-z130v", "tk-lpf9g", "tk-j5wrs"} {
		tile, ok := tileByID(b, id)
		if !ok {
			t.Fatalf("%s is missing from the board", id)
		}
		if tile.Severity != SevLow {
			t.Errorf("%s: an answered row stands down to LOW, got %s", id, tile.Severity)
		}
		if tile.Frontier != "ruled — takeaway recorded" {
			t.Errorf("%s frontier: %q", id, tile.Frontier)
		}
		if tile.Needs != "ruled — close or extend" {
			t.Errorf("%s needs: %q", id, tile.Needs)
		}
		// The ruling is still on the wire — the row is quieted, not censored.
		if tile.Takeaway == nil || *tile.Takeaway == "" {
			t.Errorf("%s: the takeaway must survive the stand-down", id)
		}
	}

	// LOW is not stale-bumped, which is what makes the thirty-day case stay
	// down. Land this on NORMAL instead and tk-z130v is ELEVATED again by the
	// next render.
	old, _ := tileByID(b, "tk-z130v")
	if old.StaleDays <= staleThresholdDays {
		t.Fatalf("the regression case has to BE stale for this to prove anything: %d days", old.StaleDays)
	}
	if old.Severity != SevLow {
		t.Errorf("a ruled row is not re-elevated by age: %s at %d days", old.Severity, old.StaleDays)
	}
}

// TestRuledNeedsTheWaitToHaveLanded is the guard. "Answered" is not "answered
// and the work landed": a decision whose `--waiting-on` edge is still open has
// not finished being a decision, and must keep its band.
//
// This is also what makes the wait clause non-vacuous, and it only holds
// because the gather reads waiting edges for these kinds at all — see
// source.waitingEdges.
func TestRuledNeedsTheWaitToHaveLanded(t *testing.T) {
	a := Anchor{ID: "tk-hs2e8", Title: "clean-exit rate", Kind: "decision", Source: "decision",
		Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1),
		Takeaway:  "answered NO — real bug is stranded holds, routed tk-jsyci7",
		WaitingOn: []string{"tk-jsyci7"}}
	tile := BuildBoard([]Anchor{a}, fixtureNow, false, nil, Facts{}).Tiles[0]

	if tile.Severity != SevElevated {
		t.Errorf("the routed work is still open — the row keeps its band, got %s", tile.Severity)
	}
	if tile.Frontier != "human-gated decision" {
		t.Errorf("frontier unchanged while the wait is live: %q", tile.Frontier)
	}
	if tile.Needs != "answered NO — real bug is stranded holds, routed tk-jsyci7" {
		t.Errorf("its takeaway still answers for it: %q", tile.Needs)
	}
}

// TestRuledNeedsTheWaitsToBeLegible is the same guard against the other way an
// empty `waiting_on_open` can arise. TestRuledNeedsTheWaitToHaveLanded covers a
// wait that WAS read and is still open; this covers a wait set the source could
// not read at all.
//
// The two look identical on the anchor — WaitingOn is empty in both the
// "nothing outstanding" case and the "never learned" one — and reading the
// empty set as an answer is the hazard. A per-anchor Dolt timeout or schema
// skew would otherwise stand an answered row down and tell the operator to
// close or extend a question whose routed work the board never checked
// (tk-fhd705). Not standing it down costs a glance; standing it down on an
// unread graph costs the thing the wait clause exists to protect.
func TestRuledNeedsTheWaitsToBeLegible(t *testing.T) {
	anchors := []Anchor{
		// The thirty-day regression case from TestRuledStandsDown, which
		// stands down on a legible empty wait set — with the read failed
		// instead, it must hold its band.
		{ID: "tk-z130v", Title: "excise the fork", Kind: "decision", Source: "decision",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(1), UpdatedAt: daysAgo(30),
			Takeaway:       "ROUTED: mayor mailed to excise gc-8yr6px",
			WaitingUnknown: true},
		// And on the other human-gated kind.
		{ID: "tk-j5wrs", Title: "membership predicate", Kind: "human", Source: "human",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1),
			Takeaway:       "routed — design ruled; tk-vie5k slung",
			WaitingUnknown: true},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})

	for _, c := range []struct{ id, frontier, needs string }{
		{"tk-z130v", "human-gated decision", "ROUTED: mayor mailed to excise gc-8yr6px"},
		{"tk-j5wrs", "routed to the operator — no agent will take it", "routed — design ruled; tk-vie5k slung"},
	} {
		tile, ok := tileByID(b, c.id)
		if !ok {
			t.Fatalf("%s is missing from the board", c.id)
		}
		if tile.Severity != SevElevated {
			t.Errorf("%s: the waits were never read — the row keeps its band, got %s", c.id, tile.Severity)
		}
		if tile.Frontier != c.frontier {
			t.Errorf("%s frontier: %q, want %q", c.id, tile.Frontier, c.frontier)
		}
		// NOT "ruled — close or extend": the board must not invite a
		// disposition it cannot support.
		if tile.Needs != c.needs {
			t.Errorf("%s needs: %q, want %q", c.id, tile.Needs, c.needs)
		}
	}
}

// TestDispositionDueSurvivesUnreadableWaits: the parked promotion needs no
// unreadable-edges clause, because it fires only on a row that HAS recorded
// waits. A failed read carries none, so it cannot reach the promotion — and the
// row keeps the LOW floor it had before any of this existed.
func TestDispositionDueSurvivesUnreadableWaits(t *testing.T) {
	a := Anchor{ID: "tk-2plde", Title: "helm returns the raw script path", Kind: "parked", Source: "parked",
		Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(2),
		Takeaway: "routed to tk-9k2ab; nothing further needed here", WaitingUnknown: true}
	tile := BuildBoard([]Anchor{a}, fixtureNow, false, nil, Facts{}).Tiles[0]

	if tile.DispositionDue {
		t.Error("an unread wait set is not a landed blocker")
	}
	if tile.Severity != SevLow {
		t.Errorf("the parked floor holds when the edges cannot be read, got %s", tile.Severity)
	}
	if tile.Needs != "routed to tk-9k2ab; nothing further needed here" {
		t.Errorf("needs: %q", tile.Needs)
	}
}

// TestUnruledHumanGatedRowsAreUnchanged: a decision or human bead with NO
// takeaway has not been answered, and nothing about it moves.
func TestUnruledHumanGatedRowsAreUnchanged(t *testing.T) {
	anchors := []Anchor{
		{ID: "tk-dec", Kind: "decision", Source: "decision", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2)},
		{ID: "tk-hum", Kind: "human", Source: "human", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2)},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})
	dec, _ := tileByID(b, "tk-dec")
	hum, _ := tileByID(b, "tk-hum")
	if dec.Severity != SevElevated || dec.Frontier != "human-gated decision" || dec.Needs != "operator decision" {
		t.Errorf("unanswered decision: %s / %q / %q", dec.Severity, dec.Frontier, dec.Needs)
	}
	if hum.Severity != SevElevated || hum.Needs != "routed to you — no question recorded" {
		t.Errorf("unanswered human row: %s / %q", hum.Severity, hum.Needs)
	}
}

// TestRuledWithChildrenIsBandedByItsRollUp: "answered" is a claim about the
// BEAD, and open work hanging under it falsifies the claim — the same reason
// the parked LOW floor stops at a decomposed subject (tk-a9k0l). A ruling must
// not become a new way to hide stranded children.
func TestRuledWithChildrenIsBandedByItsRollUp(t *testing.T) {
	// Both human-gated kinds, because each has its own short-circuit branch in
	// severity and in frontier, and a guard on one does not reach the other.
	anchors := []Anchor{
		{ID: "tk-rkids", Title: "ruled, and decomposed", Kind: "human", Source: "human",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1),
			Takeaway:  "routed — the work is filed as children",
			WaitingOn: []string{"tk-w"}, WaitingOnClosed: []string{"tk-w"},
			Children: []Child{{ID: "tk-kid", Status: "open"}}},
		{ID: "tk-dkids", Title: "a ruled decision that decomposed", Kind: "decision", Source: "decision",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1),
			Takeaway: "decided — the follow-up is filed under this bead",
			Children: []Child{{ID: "tk-dkid", Status: "open"}}},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})

	for _, id := range []string{"tk-rkids", "tk-dkids"} {
		tile, ok := tileByID(b, id)
		if !ok {
			t.Fatalf("%s is missing from the board", id)
		}
		if tile.Severity != SevHigh {
			t.Errorf("%s: open work under a ruled row still strands it, got %s", id, tile.Severity)
		}
		if !tile.Stranded {
			t.Errorf("%s: stranded is the structural claim behind that band", id)
		}
		if tile.Needs == "ruled — close or extend" {
			t.Errorf("%s: a decomposed row must not claim there is nothing left but a close", id)
		}
		if !strings.Contains(tile.Frontier, "stranded") {
			t.Errorf("%s: the frontier explains the band, got %q", id, tile.Frontier)
		}
	}
}

// TestRuledTwinDoesNotReElevate is the reason [humanGated] reads the marker and
// not just the kind. A bead carrying BOTH `gc.routed_to=human` and a takeaway is
// gathered twice, once per marker, and the dedup keeps the HIGHER band — so the
// `parked` twin's disposition-due promotion would hand back the exact band the
// stand-down just removed, on every one of these rows.
func TestRuledTwinDoesNotReElevate(t *testing.T) {
	md := map[string]string{"gc.routed_to": "human", "gc.takeaway": "routed — tk-w slung"}
	anchors := []Anchor{
		{ID: "tk-both", Title: "routed and parked", Kind: "human", Source: "human",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1), Metadata: md,
			Takeaway:  "routed — tk-w slung",
			WaitingOn: []string{"tk-w"}, WaitingOnClosed: []string{"tk-w"}},
		{ID: "tk-both", Title: "routed and parked", Kind: "parked", Source: "parked",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1), Metadata: md,
			Takeaway:  "routed — tk-w slung",
			WaitingOn: []string{"tk-w"}, WaitingOnClosed: []string{"tk-w"}},
	}
	// The same bead once more, DECOMPOSED with every child closed. This is the
	// shape that actually needs the exclusion inside dispositionDue: the
	// childless pair above is already caught by the `isRuled && mTotal == 0`
	// branch, which sits above dispDue, so it would pass with the exclusion
	// gone. sl-kg9z6.1.2 — one of the seven rows this rule was measured on —
	// is exactly this shape (5 children, all closed, 7 discharged waits).
	kidsMD := map[string]string{"gc.routed_to": "human", "gc.takeaway": "routed — all of it landed"}
	kids := []Child{{ID: "tk-k1", Status: "closed"}, {ID: "tk-k2", Status: "closed"}}
	anchors = append(anchors,
		Anchor{ID: "tk-bothkids", Title: "routed, parked, and decomposed", Kind: "human", Source: "human",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1), Metadata: kidsMD,
			Takeaway:  "routed — all of it landed",
			WaitingOn: []string{"tk-w2"}, WaitingOnClosed: []string{"tk-w2"}, Children: kids},
		Anchor{ID: "tk-bothkids", Title: "routed, parked, and decomposed", Kind: "parked", Source: "parked",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1), Metadata: kidsMD,
			Takeaway:  "routed — all of it landed",
			WaitingOn: []string{"tk-w2"}, WaitingOnClosed: []string{"tk-w2"}, Children: kids})

	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})
	if len(b.Tiles) != 2 {
		t.Fatalf("dedup by id: want 2 tiles, got %d", len(b.Tiles))
	}
	tile, ok := tileByID(b, "tk-both")
	if !ok {
		t.Fatal("tk-both is missing from the board")
	}
	if tile.Severity != SevLow {
		t.Errorf("the twin must not hand the band back: got %s (kind %s)", tile.Severity, tile.Kind)
	}
	if tile.DispositionDue {
		t.Error("a human-gated subject owes its disposition through the ruled row, not through a parked twin")
	}
	if tile.Needs != "ruled — close or extend" {
		t.Errorf("needs: %q", tile.Needs)
	}

	withKids, ok := tileByID(b, "tk-bothkids")
	if !ok {
		t.Fatal("tk-bothkids is missing from the board")
	}
	if withKids.Severity != SevLow {
		t.Errorf("a decomposed-and-finished twin stays down: got %s (kind %s)", withKids.Severity, withKids.Kind)
	}
	if withKids.DispositionDue {
		t.Error("the parked twin of a human-gated bead must not re-promote it")
	}
}

// TestDispositionDueSurvivesForAPlainParkedRow: the stand-down must not become
// a way to silence tk-2plde. A parked subject that is NOT human-gated keeps the
// promotion — it is in the LOW floor, where the promotion is the only thing
// that can ever make the landing visible.
func TestDispositionDueSurvivesForAPlainParkedRow(t *testing.T) {
	a := Anchor{ID: "tk-p", Title: "parked, blocker landed", Kind: "parked", Source: "parked",
		Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1),
		Takeaway:  "routed — nothing further needed here",
		WaitingOn: []string{"tk-w"}, WaitingOnClosed: []string{"tk-w"}}
	tile := BuildBoard([]Anchor{a}, fixtureNow, false, nil, Facts{}).Tiles[0]

	if !tile.DispositionDue || tile.Severity != SevElevated {
		t.Errorf("tk-2plde intact: disposition_due=%v severity=%s", tile.DispositionDue, tile.Severity)
	}
	if tile.Needs != "blocker landed — dispose or resume" {
		t.Errorf("needs: %q", tile.Needs)
	}
}

// --- sittings --------------------------------------------------------------

func sit(id, status string, opened, closed time.Time) Sitting {
	return Sitting{ID: id, Status: status, OpenedAt: opened, ClosedAt: closed}
}

// TestSittingsAreOrderedRunningFirst pins the one order both renderers spend:
// running sittings ahead of finished ones, the longest-running first, then the
// most recently closed.
func TestSittingsAreOrderedRunningFirst(t *testing.T) {
	at := func(h int) time.Time { return time.Date(2026, 8, 1, h, 0, 0, 0, time.UTC) }
	in := []Sitting{
		sit("closed-old", "closed", at(1), at(2)),
		sit("running-new", "open", at(9), time.Time{}),
		sit("closed-new", "closed", at(3), at(6)),
		sit("running-old", "in_progress", at(4), time.Time{}),
	}

	got := BuildBoard(nil, at(10), false, nil, Facts{Sittings: in}).Sittings

	var ids []string
	for _, s := range got {
		ids = append(ids, s.ID)
	}
	want := []string{"running-old", "running-new", "closed-new", "closed-old"}
	if !slices.Equal(ids, want) {
		t.Errorf("sitting order = %v, want %v", ids, want)
	}
}

// TestSittingOrderIsDeterministic: equal timestamps must not leave the order to
// map iteration, or two renders of one board disagree about the sequence.
func TestSittingOrderIsDeterministic(t *testing.T) {
	at := time.Date(2026, 8, 1, 5, 0, 0, 0, time.UTC)
	in := []Sitting{sit("b", "closed", at, at), sit("a", "closed", at, at), sit("c", "closed", at, at)}
	got := orderSittings(in)
	if got[0].ID != "a" || got[1].ID != "b" || got[2].ID != "c" {
		t.Errorf("equal stamps tie-break by id: got %v", []string{got[0].ID, got[1].ID, got[2].ID})
	}
	// The input must survive: BuildBoard's caller owns that slice.
	if in[0].ID != "b" {
		t.Error("orderSittings sorted its caller's slice in place")
	}
}

// TestCapSittingsKeepsEveryRunningOne: the cap is a bound on HISTORY. A running
// sitting is a live conversation and is never the row that gets dropped.
func TestCapSittingsKeepsEveryRunningOne(t *testing.T) {
	at := func(h int) time.Time { return time.Date(2026, 8, 1, h, 0, 0, 0, time.UTC) }
	var in []Sitting
	for i := range 5 {
		in = append(in, sit(fmt.Sprintf("run-%d", i), "open", at(i), time.Time{}))
	}
	for i := range 5 {
		in = append(in, sit(fmt.Sprintf("done-%d", i), "closed", at(i), at(i+1)))
	}

	kept, dropped := CapSittings(orderSittings(in), 2)
	if dropped != 3 {
		t.Errorf("dropped = %d, want 3", dropped)
	}
	var running, closed int
	for _, s := range kept {
		if s.Status == "closed" {
			closed++
		} else {
			running++
		}
	}
	if running != 5 || closed != 2 {
		t.Errorf("kept %d running and %d closed, want 5 and 2", running, closed)
	}

	if kept, dropped := CapSittings(in, 0); dropped != 0 || len(kept) != len(in) {
		t.Errorf("maxClosed<=0 is uncapped: kept %d dropped %d", len(kept), dropped)
	}
}

// TestBoardWithoutSittingsCarriesNone: a gather that supplied no record leaves
// the field nil rather than an empty slice, matching how Tiles reads on the wire.
func TestBoardWithoutSittingsCarriesNone(t *testing.T) {
	if got := BuildBoard(nil, time.Now(), false, nil, Facts{}).Sittings; got != nil {
		t.Errorf("Sittings = %v, want nil", got)
	}
}

// TestParkedChildIsNotIdleWork: an epic whose child is finished and waiting on
// a ruling must not report that child as idle work. "Assign or visit" names the
// wrong bead — the child is already assigned, to the operator.
func TestParkedChildIsNotIdleWork(t *testing.T) {
	kids := []Child{
		{ID: "sl-kg9z6.1.9", Status: "open", Metadata: map[string]string{
			"gc.routed_to": "human",
			"gc.takeaway":  "holding for your ruling",
		}},
		{ID: "sl-kg9z6.1.2", Status: "open", Metadata: map[string]string{"gc.routed_to": "human"}},
	}
	for i := 1; i <= 5; i++ {
		kids = append(kids, Child{ID: "sl-idle" + string(rune('0'+i)), Status: "open"})
	}
	anchors := []Anchor{{
		ID: "sl-kg9z6.1", Title: "the parent epic", Kind: "epic", Source: "epic",
		Rig: "signal-loom", Prefix: "sl", Priority: ptr(1), Children: kids,
	}}

	tile, ok := tileByID(BuildBoard(anchors, fixtureNow, false, nil, Facts{}), "sl-kg9z6.1")
	if !ok {
		t.Fatal("epic tile missing")
	}

	// The wire keeps the honest total and names the split.
	if tile.Open != 7 {
		t.Errorf("open = %d, want 7 — the total is not what changed", tile.Open)
	}
	if len(tile.ParkedHeads) != 2 {
		t.Errorf("parked_heads = %v, want the two human-routed children", tile.ParkedHeads)
	}
	for _, id := range tile.OpenHeads {
		if id == "sl-kg9z6.1.9" || id == "sl-kg9z6.1.2" {
			t.Errorf("open_heads still carries a parked child: %v", tile.OpenHeads)
		}
	}
	if len(tile.OpenHeads) != 5 {
		t.Errorf("open_heads = %v, want the five genuinely idle children", tile.OpenHeads)
	}

	// Five children really are idle, so the epic is still stranded: the split
	// differentiates the count, it does not silence it.
	if tile.Severity != SevHigh || !tile.Stranded {
		t.Errorf("five idle children are still stranded: sev=%s stranded=%v", tile.Severity, tile.Stranded)
	}
	if !strings.Contains(tile.Frontier, "5 open") || !strings.Contains(tile.Frontier, "2 parked for the operator") {
		t.Errorf("frontier must decompose the count, got %q", tile.Frontier)
	}
}

// TestAllChildrenParkedIsNotStranded: when the ONLY open children are waiting
// on the operator, the parent has no ask of its own — the asks are on the
// children's own rows.
func TestAllChildrenParkedIsNotStranded(t *testing.T) {
	anchors := []Anchor{{
		ID: "tk-epic", Title: "everything is with the operator", Kind: "epic", Source: "epic",
		Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), Children: []Child{
			{ID: "tk-a", Status: "open", Metadata: map[string]string{"gc.routed_to": "human"}},
			{ID: "tk-b", Status: "open", Metadata: map[string]string{"gc.takeaway": "ruling owed"}},
			{ID: "tk-c", Status: "closed"},
		},
	}}

	tile, ok := tileByID(BuildBoard(anchors, fixtureNow, false, nil, Facts{}), "tk-epic")
	if !ok {
		t.Fatal("epic tile missing")
	}
	if tile.Severity == SevHigh || tile.Stranded {
		t.Errorf("an epic whose every open child is parked is not stranded: sev=%s stranded=%v", tile.Severity, tile.Stranded)
	}
	if strings.Contains(tile.Needs, "idle") || strings.Contains(tile.Needs, "assign") {
		t.Errorf("needs must not send the operator to assign work that is already theirs: %q", tile.Needs)
	}
	if !strings.Contains(tile.Needs, "2 parked") {
		t.Errorf("needs must say what is actually owed, got %q", tile.Needs)
	}
	if !strings.Contains(tile.Frontier, "2 parked for the operator") || !strings.Contains(tile.Frontier, "nothing idle") {
		t.Errorf("frontier = %q", tile.Frontier)
	}
	if len(tile.OpenHeads) != 0 {
		t.Errorf("open_heads = %v, want empty", tile.OpenHeads)
	}
}

// TestParkedSplitLeavesUnparkedAnchorsUnchanged pins the no-op case: an anchor
// with no parked children must band and read exactly as it does without the
// split.
func TestParkedSplitLeavesUnparkedAnchorsUnchanged(t *testing.T) {
	cases := []struct {
		name     string
		anchor   Anchor
		facts    Facts
		wantSev  Severity
		frontier string
		needs    string
	}{
		{
			name: "stranded",
			anchor: Anchor{ID: "tk-s", Kind: "epic", Source: "epic", Children: []Child{
				{ID: "tk-s1", Status: "open"}, {ID: "tk-s2", Status: "open"},
			}},
			wantSev: SevHigh, frontier: "2 open · 0 in flight (stranded)", needs: "decomposed, idle — assign or visit",
		},
		{
			name: "in flight",
			anchor: Anchor{ID: "tk-f", Kind: "epic", Source: "epic", Children: []Child{
				{ID: "tk-f1", Status: "in_progress", Assignee: "polecat-live"},
			}},
			facts:   liveOwners("polecat-live"),
			wantSev: SevNormal, frontier: "1 open · 1 in flight", needs: "in flight",
		},
		{
			name: "dead owner",
			anchor: Anchor{ID: "tk-d", Kind: "epic", Source: "epic", Children: []Child{
				{ID: "tk-d1", Status: "in_progress", Assignee: "polecat-gone"},
			}},
			wantSev: SevHigh, frontier: "1 open · 1 stuck (dead owner)", needs: "dead owner — recover or reassign",
		},
		{
			name: "all closed",
			anchor: Anchor{ID: "tk-c", Kind: "epic", Source: "epic", Children: []Child{
				{ID: "tk-c1", Status: "closed"},
			}},
			wantSev: SevLow, frontier: "all 1 closed · 0 open", needs: "all 1 closed — close or extend",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			tile, ok := tileByID(BuildBoard([]Anchor{tc.anchor}, fixtureNow, false, nil, tc.facts), tc.anchor.ID)
			if !ok {
				t.Fatal("tile missing")
			}
			if tile.Severity != tc.wantSev {
				t.Errorf("severity = %s, want %s", tile.Severity, tc.wantSev)
			}
			if tile.Frontier != tc.frontier {
				t.Errorf("frontier = %q, want %q", tile.Frontier, tc.frontier)
			}
			if tile.Needs != tc.needs {
				t.Errorf("needs = %q, want %q", tile.Needs, tc.needs)
			}
			if len(tile.ParkedHeads) != 0 {
				t.Errorf("parked_heads = %v, want empty", tile.ParkedHeads)
			}
		})
	}
}

// TestParkedSplitIgnoresAMovingChild: a child that is moving is neither idle nor
// parked, whatever markers it carries. A rework bead can carry a stale takeaway
// from the sitting that dispatched it while a polecat works it now.
func TestParkedSplitIgnoresAMovingChild(t *testing.T) {
	anchors := []Anchor{{
		ID: "tk-epic", Kind: "epic", Source: "epic", Children: []Child{
			{ID: "tk-live", Status: "in_progress", Assignee: "polecat-live",
				Metadata: map[string]string{"gc.takeaway": "dispatched, work routed"}},
		},
	}}
	tile, ok := tileByID(BuildBoard(anchors, fixtureNow, false, nil, liveOwners("polecat-live")), "tk-epic")
	if !ok {
		t.Fatal("tile missing")
	}
	if len(tile.ParkedHeads) != 0 {
		t.Errorf("a moving child is not parked: %v", tile.ParkedHeads)
	}
	if tile.InProgressLive != 1 || tile.Severity != SevNormal {
		t.Errorf("live child still reads as in flight: live=%d sev=%s", tile.InProgressLive, tile.Severity)
	}
}

// TestHasOwnRowReadsPresenceNotTruthiness: bd round-trips an empty metadata
// value and the decode keeps the key, so a blanked takeaway still gives the bead
// a row. This reading must match the gather's selector, or a child is an anchor
// on the board and idle work under its parent at the same time.
func TestHasOwnRowReadsPresenceNotTruthiness(t *testing.T) {
	cases := []struct {
		name string
		md   map[string]string
		want bool
	}{
		{"nil", nil, false},
		{"empty", map[string]string{}, false},
		{"routed to the operator", map[string]string{"gc.routed_to": "human"}, true},
		{"routed to an agent", map[string]string{"gc.routed_to": "gc-toolkit/gc-toolkit.polecat"}, false},
		{"takeaway present", map[string]string{"gc.takeaway": "held"}, true},
		{"takeaway blanked", map[string]string{"gc.takeaway": ""}, true},
		{"only a neighbouring key", map[string]string{"gc.takeaway_at": "2026-08-26T00:00:00Z"}, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := hasOwnRow(tc.md); got != tc.want {
				t.Errorf("hasOwnRow(%v) = %v, want %v", tc.md, got, tc.want)
			}
		})
	}
}

// TestHumanRoutedTwinBandsWithItsSibling: a bead carrying BOTH markers is
// gathered twice. The two rows are one bead, so they must band by the same rule
// — otherwise the dedup arbitrates by rank rather than by which row is truer.
func TestHumanRoutedTwinBandsWithItsSibling(t *testing.T) {
	md := map[string]string{
		"gc.routed_to": "human",
		"gc.takeaway":  "cut-short — no ruling yet; cap needs clearing",
	}
	kid := []Child{{ID: "gc-yblin", Status: "open"}}
	// Waits are UNKNOWN, as the supervisor backend reports them, so the row
	// cannot stand down and the case is about the band it keeps.
	anchors := []Anchor{
		{ID: "gc-sc8a8", Title: "held for a ruling", Kind: "human", Source: "human", Rig: "gascity", Prefix: "gc",
			Priority: ptr(1), Metadata: md, Takeaway: md["gc.takeaway"], Children: kid, WaitingUnknown: true},
		{ID: "gc-sc8a8", Title: "held for a ruling", Kind: "parked", Source: "parked", Rig: "gascity", Prefix: "gc",
			Priority: ptr(1), Metadata: md, Takeaway: md["gc.takeaway"], Children: kid, WaitingUnknown: true},
	}

	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})
	tile, ok := tileByID(b, "gc-sc8a8")
	if !ok {
		t.Fatal("tile missing")
	}
	if len(b.Tiles) != 1 {
		t.Errorf("the two rows are one bead: %d tiles", len(b.Tiles))
	}
	if tile.Severity != SevElevated {
		t.Errorf("severity = %s, want ELEVATED — the operator is the blocker, not a missing assignment", tile.Severity)
	}
	if tile.Stranded || strings.Contains(tile.Frontier, "stranded") {
		t.Errorf("a bead held for an operator ruling is not stranded: stranded=%v frontier=%q", tile.Stranded, tile.Frontier)
	}
	if tile.Frontier != "routed to the operator — no agent will take it" {
		t.Errorf("frontier = %q", tile.Frontier)
	}
	if tile.Needs != md["gc.takeaway"] {
		t.Errorf("needs must spend the takeaway: %q", tile.Needs)
	}
	// The child is re-attributed, not suppressed: still on the wire.
	if tile.Open != 1 || len(tile.OpenHeads) != 1 {
		t.Errorf("the open child must still be reported: open=%d heads=%v", tile.Open, tile.OpenHeads)
	}
}

// TestParkedWithoutTheHumanMarkerKeepsItsRollUp: a parked subject that
// decomposed is still banded by its children, because "the conversation wants
// nothing" is a claim about the bead and open work under it falsifies it. Only
// the human marker earns the exemption, because a human-routed bead never made
// that claim.
func TestParkedWithoutTheHumanMarkerKeepsItsRollUp(t *testing.T) {
	anchors := []Anchor{{
		ID: "tk-gpqyyn", Title: "a sitting that routed work", Kind: "parked", Source: "parked",
		Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(1),
		Metadata: map[string]string{"gc.takeaway": "routed; nothing further needed here"},
		Takeaway: "routed; nothing further needed here",
		Children: []Child{{ID: "tk-kid", Status: "open"}},
	}}
	tile, ok := tileByID(BuildBoard(anchors, fixtureNow, false, nil, Facts{}), "tk-gpqyyn")
	if !ok {
		t.Fatal("tile missing")
	}
	if tile.Severity != SevHigh || !tile.Stranded {
		t.Errorf("a decomposed parked subject is banded by its children: sev=%s stranded=%v", tile.Severity, tile.Stranded)
	}
	if tile.Frontier != "1 open · 0 in flight (stranded)" {
		t.Errorf("frontier = %q", tile.Frontier)
	}
}

// TestOperatorRowBeatsAHigherSeverityRow is the case the whole partition exists
// for, and it fails on a globally ranked board by construction.
//
// tk-owed is one bead routed to the operator, carrying a takeaway, subtree 1.
// tk-container is a stranded epic with 300 open children. The epic bands HIGH,
// the demand bands ELEVATED, so severity alone already files the demand second
// — and even at equal severity the epic's subtree would win the rank tiebreak
// 300 to 1.
func TestOperatorRowBeatsAHigherSeverityRow(t *testing.T) {
	kids := make([]Child, 0, 300)
	for i := 0; i < 300; i++ {
		kids = append(kids, Child{ID: fmt.Sprintf("tk-c%d", i), Status: "open"})
	}
	owedAt := "2026-06-01T00:00:00Z"
	anchors := []Anchor{
		{ID: "tk-container", Title: "big stranded epic", Kind: "epic", Source: "epic",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(1), UpdatedAt: fixtureNow, Children: kids},
		// WaitingUnknown is the shape the supervisor backend produces: a
		// takeaway whose blocker statuses are unreadable is NOT [ruled], so the
		// row is still asking.
		{ID: "tk-owed", Title: "one bead waiting on a person", Kind: "human", Source: "human",
			Rig: "gc-toolkit", Prefix: "tk", UpdatedAt: fixtureNow,
			Metadata:       map[string]string{mdRoutedTo: routedHuman, mdTakeaway: "approve the cutover or say no"},
			Takeaway:       "approve the cutover or say no",
			TakeawayAt:     owedAt,
			WaitingUnknown: true},
	}

	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})

	container, _ := tileByID(b, "tk-container")
	owed, _ := tileByID(b, "tk-owed")
	if container.Severity != SevHigh || owed.Severity != SevElevated {
		t.Fatalf("fixture no longer sets up the contest: container=%s owed=%s", container.Severity, owed.Severity)
	}
	if container.RankScore <= owed.RankScore {
		t.Fatalf("fixture no longer sets up the contest: the container must outrank the demand (%d vs %d)",
			container.RankScore, owed.RankScore)
	}

	if !owed.Owed {
		t.Error("a bead routed to the operator is owed")
	}
	if container.Owed {
		t.Error("a stranded container is not owed by anyone in particular")
	}
	if b.Tiles[0].ID != "tk-owed" {
		t.Errorf("the owed row leads the board despite ranking below the container: got %s", b.Tiles[0].ID)
	}

	// And the DEFAULT surface does not merely reorder — it REPLACES. The
	// container is not in it at all.
	q := OperatorQueue(b.Tiles)
	if len(q) != 1 || q[0].ID != "tk-owed" {
		t.Fatalf("the default surface is the queue alone: got %v", ids(q))
	}
}

// TestOperatorQueueIsOrderedByAge: the queue is a list of decisions, so it is
// ordered by how long each has been owed. Rank would order it by subtree size,
// which is what the partition is escaping.
func TestOperatorQueueIsOrderedByAge(t *testing.T) {
	human := func(id, takeawayAt string, kids int) Anchor {
		a := Anchor{ID: id, Title: id, Kind: "human", Source: "human", Rig: "gc-toolkit", Prefix: "tk",
			Metadata: map[string]string{mdRoutedTo: routedHuman, mdTakeaway: "answer me"},
			Takeaway: "answer me", UpdatedAt: fixtureNow, WaitingUnknown: true}
		if takeawayAt != "" {
			a.TakeawayAt = takeawayAt
		}
		for i := 0; i < kids; i++ {
			a.Children = append(a.Children, Child{ID: fmt.Sprintf("%s-c%d", id, i), Status: "in_progress", Assignee: "live"})
		}
		return a
	}
	// The ids run OPPOSITE to the ages on purpose: the final tiebreak in
	// [owedFirst] is id-ascending, and ids that happened to agree with the
	// ages would pass this test with the age comparison deleted.
	anchors := []Anchor{
		human("tk-a-recent", "2026-06-29T00:00:00Z", 200),
		human("tk-c-ancient", "2026-01-02T00:00:00Z", 0),
		human("tk-b-middle", "2026-05-01T00:00:00Z", 50),
	}

	b := BuildBoard(anchors, fixtureNow, false, nil, liveOwners("live"))
	q := OperatorQueue(b.Tiles)

	want := []string{"tk-c-ancient", "tk-b-middle", "tk-a-recent"}
	if got := ids(q); !equalIDs(got, want) {
		t.Errorf("queue order = %v, want oldest first %v", got, want)
	}
	// The rank order is the reverse, which is what makes this test mean
	// something: the newest row carries 200 children and outranks both.
	recent, _ := tileByID(b, "tk-a-recent")
	ancient, _ := tileByID(b, "tk-c-ancient")
	if recent.RankScore <= ancient.RankScore {
		t.Fatalf("fixture no longer inverts rank against age: recent=%d ancient=%d",
			recent.RankScore, ancient.RankScore)
	}
}

// TestUndatedOwedRowSortsLast: an unknown age is not evidence of a long wait.
// The supervisor backend reads no updated_at at all, so reading "undated" as
// "oldest" would file every row from that backend ahead of every dated one.
func TestUndatedOwedRowSortsLast(t *testing.T) {
	// Ids opposite to the intended order, so the id tiebreak cannot pass this.
	anchors := []Anchor{
		{ID: "tk-a-undated", Title: "no date anywhere", Kind: "human", Source: "human", Rig: "gc-toolkit", Prefix: "tk",
			Metadata: map[string]string{mdRoutedTo: routedHuman}},
		{ID: "tk-z-dated", Title: "asked yesterday", Kind: "human", Source: "human", Rig: "gc-toolkit", Prefix: "tk",
			Metadata: map[string]string{mdRoutedTo: routedHuman}, UpdatedAt: daysAgo(1)},
	}
	q := OperatorQueue(BuildBoard(anchors, fixtureNow, false, nil, Facts{}).Tiles)
	if got := ids(q); !equalIDs(got, []string{"tk-z-dated", "tk-a-undated"}) {
		t.Errorf("queue order = %v, want the dated row first", got)
	}
}

// TestRuledRowLeavesTheQueue: [ruled] is the stand-down state — the operator
// already answered and the routed work has landed. Those rows are banded LOW
// precisely so they stop asking, and the queue has to agree with the band or
// the stand-down does nothing.
func TestRuledRowLeavesTheQueue(t *testing.T) {
	anchors := []Anchor{
		{ID: "tk-answered", Title: "already ruled", Kind: "human", Source: "human", Rig: "gc-toolkit", Prefix: "tk",
			Metadata: map[string]string{mdRoutedTo: routedHuman, mdTakeaway: "ruled: ship it"},
			Takeaway: "ruled: ship it", UpdatedAt: fixtureNow},
		{ID: "tk-asking", Title: "still asking", Kind: "human", Source: "human", Rig: "gc-toolkit", Prefix: "tk",
			Metadata: map[string]string{mdRoutedTo: routedHuman}, UpdatedAt: fixtureNow},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})
	answered, _ := tileByID(b, "tk-answered")
	if answered.Severity != SevLow {
		t.Fatalf("fixture: the answered row must be ruled/LOW, got %s", answered.Severity)
	}
	if answered.Owed {
		t.Error("a ruled row is not owed — it was answered")
	}
	if got := ids(OperatorQueue(b.Tiles)); !equalIDs(got, []string{"tk-asking"}) {
		t.Errorf("queue = %v, want only the unanswered row", got)
	}
}

// TestClosedRowLeavesTheQueue: the DONE band and the operator's queue meet on
// a closed anchor that still carries the human-routed marker. The queue is
// ordered by how long each row has been owed, so admitting one would file a
// finished row ahead of every live demand — the exact inverse of the floor the
// band gives it. The fixture makes the closed row the OLDEST, so that inversion
// is what fails here if the gate goes.
func TestClosedRowLeavesTheQueue(t *testing.T) {
	anchors := []Anchor{
		{ID: "tk-closed", Title: "answered, then closed", Kind: "human", Source: "human", Rig: "gc-toolkit", Prefix: "tk",
			Metadata:  map[string]string{mdRoutedTo: routedHuman},
			UpdatedAt: daysAgo(9), ClosedAt: daysAgo(1)},
		{ID: "tk-asking", Title: "still asking", Kind: "human", Source: "human", Rig: "gc-toolkit", Prefix: "tk",
			Metadata: map[string]string{mdRoutedTo: routedHuman}, UpdatedAt: daysAgo(2)},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})
	closed, _ := tileByID(b, "tk-closed")
	if closed.Severity != SevDone {
		t.Fatalf("fixture: the closed row must band DONE, got %s", closed.Severity)
	}
	if closed.Owed {
		t.Error("a closed row is not owed — the band is where it goes")
	}
	if got := ids(OperatorQueue(b.Tiles)); !equalIDs(got, []string{"tk-asking"}) {
		t.Errorf("queue = %v, want only the live demand", got)
	}
	// Sinking, not leaving: it is still on the board, under the live row.
	if got := ids(CityOverview(b.Tiles)); !equalIDs(got, []string{"tk-asking", "tk-closed"}) {
		t.Errorf("overview = %v, want the closed row last but present", got)
	}
}

// TestCapQueueDoesNotRationParkedRows: CapRows gives `parked` a small separate
// budget because those rows are floored to LOW and would fall off the end of a
// ranked board. Inside the queue a parked row is a conversation waiting on the
// operator and earned its place by age, so that budget would cut the queue
// exactly where it carries the most.
func TestCapQueueDoesNotRationParkedRows(t *testing.T) {
	var tiles []Tile
	for i := 0; i < DefaultMaxParked+5; i++ {
		tiles = append(tiles, Tile{ID: fmt.Sprintf("tk-p%02d", i), Kind: "parked", Owed: true})
	}
	if got := len(CapQueue(tiles, DefaultMaxRows)); got != len(tiles) {
		t.Errorf("CapQueue kept %d of %d parked rows", got, len(tiles))
	}
	if got := len(CapRows(tiles, DefaultMaxRows, DefaultMaxParked, DefaultMaxDone)); got != DefaultMaxParked {
		t.Fatalf("fixture: CapRows must ration these to %d, got %d", DefaultMaxParked, got)
	}
	if got := len(CapQueue(tiles, 3)); got != 3 {
		t.Errorf("CapQueue still honors its own limit: got %d", got)
	}
	if got := len(CapQueue(tiles, 0)); got != len(tiles) {
		t.Errorf("limit 0 is uncapped: got %d", got)
	}
}

// TestCityOverviewIsRankedNotPartitioned: Board.Tiles leaves BuildBoard
// partitioned owed-first, so the `--all` view has to sort it back. The
// partition is what the queue is for; reading it as a ranked list files the
// city's highest-ranked row behind a one-bead demand.
func TestCityOverviewIsRankedNotPartitioned(t *testing.T) {
	kids := make([]Child, 0, 300)
	for i := 0; i < 300; i++ {
		kids = append(kids, Child{ID: fmt.Sprintf("tk-c%d", i), Status: "open"})
	}
	anchors := []Anchor{
		{ID: "tk-container", Title: "big stranded epic", Kind: "epic", Source: "epic",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(1), UpdatedAt: fixtureNow, Children: kids},
		{ID: "tk-owed", Title: "one bead waiting on a person", Kind: "human", Source: "human",
			Rig: "gc-toolkit", Prefix: "tk", UpdatedAt: fixtureNow,
			Metadata:       map[string]string{mdRoutedTo: routedHuman, mdTakeaway: "approve the cutover or say no"},
			Takeaway:       "approve the cutover or say no",
			TakeawayAt:     "2026-06-01T00:00:00Z",
			WaitingUnknown: true},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})
	if got := ids(b.Tiles); !equalIDs(got, []string{"tk-owed", "tk-container"}) {
		t.Fatalf("fixture: the board is partitioned owed-first, got %v", got)
	}

	overview := CityOverview(b.Tiles)
	if got := ids(overview); !equalIDs(got, []string{"tk-container", "tk-owed"}) {
		t.Errorf("the overview is ranked, highest first: got %v", got)
	}
	// The board is shared with every other view of the same render, so the
	// re-sort may not reach back into it.
	if got := ids(b.Tiles); !equalIDs(got, []string{"tk-owed", "tk-container"}) {
		t.Errorf("CityOverview must not reorder the board it was given: got %v", got)
	}
}

// TestSilentDemandNamesItsSilence: the takeaway is the whole reason a row owed
// by a person carries a sentence, so its ABSENCE is the finding — whoever
// routed or parked the row never recorded what is owed. A generic phrase reads
// like a valid ask and leaves the operator nothing to act on. Blank counts as
// absent: collapseWS flattens whitespace-only prose to empty.
func TestSilentDemandNamesItsSilence(t *testing.T) {
	for _, tc := range []struct{ name, takeaway string }{
		{"absent", ""},
		{"blank", " \t\n "},
	} {
		t.Run(tc.name, func(t *testing.T) {
			anchors := []Anchor{
				{ID: "tk-human", Title: "Disposition: one PR needs the operator", Kind: "human", Source: "human",
					Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(1), UpdatedAt: daysAgo(4),
					Metadata: map[string]string{mdRoutedTo: routedHuman, mdTakeaway: tc.takeaway},
					Takeaway: tc.takeaway},
				{ID: "tk-parked", Title: "helm returns the raw script path", Kind: "parked", Source: "parked",
					Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1),
					Metadata: map[string]string{mdTakeaway: tc.takeaway},
					Takeaway: tc.takeaway},
				// The control. Same kind, same shape, one recorded sentence —
				// so a phrase that came from anywhere but the takeaway fails
				// here instead of passing everywhere.
				{ID: "tk-spoken", Title: "helm returns the raw script path", Kind: "parked", Source: "parked",
					Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1),
					Metadata: map[string]string{mdTakeaway: "ship it or say why not"},
					Takeaway: "ship it or say why not"},
			}
			b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})

			human, ok := tileByID(b, "tk-human")
			if !ok {
				t.Fatal("the human-routed tile is missing")
			}
			if human.Takeaway != nil {
				t.Errorf("a silent takeaway is null on the wire, not %q", *human.Takeaway)
			}
			if !human.Owed {
				t.Error("a silent demand is still owed — it is the operator's move either way")
			}
			if human.Needs != "routed to you — no question recorded" {
				t.Errorf("the human row names its silence: %q", human.Needs)
			}

			parked, ok := tileByID(b, "tk-parked")
			if !ok {
				t.Fatal("the parked tile is missing")
			}
			if parked.Needs != "parked for you — no question recorded" {
				t.Errorf("the parked row names its silence: %q", parked.Needs)
			}
			// The frontier is a claim about what the sitting left behind, so it
			// may not say "takeaway recorded" one column from NEEDS saying none
			// was.
			if parked.Frontier != "conversation parked — no takeaway recorded" {
				t.Errorf("the frontier agrees with it: %q", parked.Frontier)
			}

			spoken, ok := tileByID(b, "tk-spoken")
			if !ok {
				t.Fatal("the control tile is missing")
			}
			if spoken.Needs != "ship it or say why not" {
				t.Errorf("a recorded takeaway is still the NEEDS answer: %q", spoken.Needs)
			}
			if spoken.Frontier != "conversation parked — takeaway recorded" {
				t.Errorf("…and the frontier still says one was left: %q", spoken.Frontier)
			}
		})
	}
}

// ids is a test helper.
func ids(tiles []Tile) []string {
	out := make([]string, 0, len(tiles))
	for _, t := range tiles {
		out = append(out, t.ID)
	}
	return out
}

// ── The DONE band ────────────────────────────────────────────────────────
//
// The rule these pin: a row does not leave the operator's view because it was
// answered. A closed anchor sinks below every live band and stays there.

// closedAnchor is a live-looking anchor whose own bead has closed d days ago.
// It deliberately carries OPEN children: run through the live branches, those
// children band it HIGH and put a finished item at the top of the board.
func closedAnchor(id string, d int, children ...Child) Anchor {
	return Anchor{
		ID: id, Title: id, Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk",
		Priority: ptr(1), UpdatedAt: daysAgo(d), ClosedAt: daysAgo(d), Children: children,
	}
}

func TestClosedAnchorBandsDoneNotByItsChildren(t *testing.T) {
	a := closedAnchor("tk-done", 1, Child{ID: "tk-c1", Status: "open"}, Child{ID: "tk-c2", Status: "open"})
	tile := computeTile(a, fixtureNow, Facts{})

	if tile.Severity != SevDone {
		t.Errorf("a closed anchor bands DONE: got %s", tile.Severity)
	}
	if tile.Frontier != "closed 1d ago" {
		t.Errorf("frontier says when it closed: got %q", tile.Frontier)
	}
	if tile.Needs != "closed — dismiss to clear" {
		t.Errorf("needs names the one act that clears it: got %q", tile.Needs)
	}
	if tile.ClosedAt.IsZero() {
		t.Error("closed_at reaches the wire; without it no consumer can tell the band apart")
	}
}

// A DONE row's takeaway would otherwise win the NEEDS cell, and it would be
// answering the question the row had while it was live.
func TestClosedAnchorNeedsOutranksItsTakeaway(t *testing.T) {
	a := closedAnchor("tk-tk", 2)
	a.Kind, a.Source = "parked", "parked"
	a.Takeaway = "waiting on the operator to pick a storage backend"

	tile := computeTile(a, fixtureNow, Facts{})
	if tile.Needs != "closed — dismiss to clear" {
		t.Errorf("a closed row asks to be cleared, not re-read: got %q", tile.Needs)
	}
	if tile.Takeaway == nil || *tile.Takeaway != a.Takeaway {
		t.Error("the takeaway still travels on the wire; only the NEEDS cell changes")
	}
}

// The band's whole promise is that it SINKS. A closed P1 epic with a large
// subtree is the strongest row the live lanes can build, and it must still land
// under the weakest live row there is.
func TestDoneBandSinksBelowEveryLiveRow(t *testing.T) {
	big := make([]Child, 0, 40)
	for i := range 40 {
		big = append(big, Child{ID: "tk-c" + string(rune('a'+i%26)) + string(rune('0'+i/26)), Status: "open"})
	}
	done := closedAnchor("tk-heavy", 0, big...)
	quiet := Anchor{ID: "tk-quiet", Title: "empty", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk"}

	b := BuildBoard([]Anchor{done, quiet}, fixtureNow, false, nil, Facts{})
	if b.Tiles[len(b.Tiles)-1].ID != "tk-heavy" {
		t.Fatalf("the DONE row sorts last: got order %s, %s", b.Tiles[0].ID, b.Tiles[1].ID)
	}
	heavy, _ := tileByID(b, "tk-heavy")
	if heavy.RankScore >= 0 {
		t.Errorf("the DONE lane must stay below the live floor of 0: got %d", heavy.RankScore)
	}
}

// Inside the band the useful order is recency: the row the operator just
// watched close is the one they are looking for.
func TestDoneBandOrdersByRecency(t *testing.T) {
	b := BuildBoard([]Anchor{
		closedAnchor("tk-old", 30),
		closedAnchor("tk-new", 0),
		closedAnchor("tk-mid", 3),
	}, fixtureNow, false, nil, Facts{})

	var got []string
	for _, tile := range b.Tiles {
		got = append(got, tile.ID)
	}
	want := []string{"tk-new", "tk-mid", "tk-old"}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Errorf("most recently closed first: got %v, want %v", got, want)
	}
}

// An ancient closure must not borrow out of the units lane and cross into a
// live band, the same invariant the stale term carries on the other side.
func TestDoneLaneStaysBoundedForAnAncientClosure(t *testing.T) {
	ancient := rankScore(SevDone, 0, 0, 50_000)
	floor := rankScore(SevDone, 0, 0, rankTermCap)
	if ancient != floor {
		t.Errorf("the closed term caps at %d: 50000d scored %d, %dd scored %d", rankTermCap, ancient, rankTermCap, floor)
	}
	if ancient >= rankScore(SevLow, 0, 0, 0) {
		t.Error("the oldest DONE row must still sort below the quietest live one")
	}
}

// CapRows: three budgets, because a shared one drops the whole of the band
// that sorts last — and the band that sorts last is the one whose rows were
// about to disappear on their own.
func TestCapRowsBudgetsAreSeparate(t *testing.T) {
	var tiles []Tile
	for i := range 4 {
		tiles = append(tiles, Tile{ID: "a" + string(rune('0'+i)), Kind: "epic", Severity: SevHigh})
	}
	for i := range 4 {
		tiles = append(tiles, Tile{ID: "p" + string(rune('0'+i)), Kind: "parked", Severity: SevLow})
	}
	for i := range 4 {
		tiles = append(tiles, Tile{ID: "d" + string(rune('0'+i)), Kind: "parked", Severity: SevDone})
	}

	shown := CapRows(tiles, 2, 1, 3)
	var attention, parked, done int
	for _, tile := range shown {
		switch {
		case tile.Severity == SevDone:
			done++
		case tile.Kind == "parked":
			parked++
		default:
			attention++
		}
	}
	if attention != 2 || parked != 1 || done != 3 {
		t.Errorf("each budget is spent on its own band: attention=%d parked=%d done=%d, want 2/1/3", attention, parked, done)
	}
	if got := len(CapRows(tiles, 0, 1, 1)); got != len(tiles) {
		t.Errorf("limit<=0 stays uncapped for every band: got %d of %d", got, len(tiles))
	}
}

// --- the PR round-trip (specs/tk-q0ml23) --------------------------------------
//
// Every case below is built from a shape the design measured on live gc-toolkit
// on 2026-08-28, because the failure this surface exists to prevent is a board
// that reports a wedged pull request as nobody's problem, and only the real
// shapes prove it does not.

const (
	// A 40-hex oid, the grammar the gate markers and the dated keys share.
	headLive = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	headOld  = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
)

// dated builds the <value>@<oid>@<since> shape lifecycle.sh writes.
func dated(value, oid string, at time.Time) string {
	return value + "@" + oid + "@" + at.Format(time.RFC3339)
}

// mergeAnchor is an open merge anchor as the gather produces one: the `merge`
// kind, whatever metadata the case is about, and its `blocks` blockers.
func mergeAnchor(id string, md map[string]string, blockers ...Blocker) Anchor {
	full := map[string]string{"merge_result": "pull_request", "branch": "polecat/" + id}
	for k, v := range md {
		full[k] = v
	}
	return Anchor{
		ID: id, Title: "t " + id, Kind: "merge", Source: "merge",
		Rig: "gc-toolkit", Prefix: "tk", Metadata: full, Blockers: blockers,
		UpdatedAt: fixtureNow, // touched by this very reconcile pass
	}
}

func mustTile(t *testing.T, b Board, id string) Tile {
	t.Helper()
	tile, ok := tileByID(b, id)
	if !ok {
		t.Fatalf("no tile for %s", id)
	}
	return tile
}

// TestWedgedAnchorIsOwedAndNamed covers both wedge shapes.
//
// The exception wedge is the state six of the seven wedged anchors were in, and
// five of those six had no pull request open, which is why the row is keyed on
// the anchor and carries the branch instead. The veto wedge is the seventh.
// Neither was visible as anything but "routed to a person", which reads the
// same for an anchor awaiting a ruling and for one nothing will ever move.
func TestWedgedAnchorIsOwedAndNamed(t *testing.T) {
	wedgedAt := fixtureNow.Add(-72 * time.Hour)
	anchors := []Anchor{
		mergeAnchor("tk-exc", map[string]string{
			"merge_result":   "pre_open_gate",
			"pr.machine":     dated(MachineWedgedException, headLive, wedgedAt),
			"gc.routed_to":   "human",
			"check.codex":    "exception@" + headLive,
			"blocked_reason": "signoff did not converge after 3 rework rounds (cap 3)",
		}),
		mergeAnchor("tk-veto", map[string]string{
			"pr.machine": dated(MachineWedgedVeto, headLive, wedgedAt),
			"pr_number":  "513",
			"pr_url":     "https://github.com/zook/gc-toolkit/pull/513",
			"pr_posture": dated(postureChangesRequested, headLive, wedgedAt),
		}),
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})

	exc := mustTile(t, b, "tk-exc")
	if exc.PRMachine != MachineWedgedException {
		t.Errorf("pr_machine = %q, want %q", exc.PRMachine, MachineWedgedException)
	}
	if !exc.Owed {
		t.Error("a wedged anchor is owed by the operator: nothing else will move it")
	}
	if !strings.Contains(exc.Needs, "wedged") || !strings.Contains(exc.Needs, "exception") {
		t.Errorf("needs must name the wedge and its shape, got %q", exc.Needs)
	}
	if !exc.PROwedSince.Equal(wedgedAt) {
		t.Errorf("pr_owed_since = %v, want the wedge stamp %v", exc.PROwedSince, wedgedAt)
	}
	// No PR number: the identity is the branch, which is the majority case.
	if exc.PRNumber != 0 || !strings.Contains(exc.Frontier, "polecat/tk-exc") {
		t.Errorf("a pre-open row identifies itself by branch, got number=%d frontier=%q",
			exc.PRNumber, exc.Frontier)
	}
	if !strings.Contains(exc.Frontier, "owed 3d") {
		t.Errorf("the row carries the age the queue is sorted by, got %q", exc.Frontier)
	}

	veto := mustTile(t, b, "tk-veto")
	if veto.PRMachine != MachineWedgedVeto {
		t.Errorf("pr_machine = %q, want %q", veto.PRMachine, MachineWedgedVeto)
	}
	if !veto.Owed {
		t.Error("a veto past the rework cap is owed: signoff will file nothing further")
	}
	if !strings.Contains(veto.Needs, "CHANGES_REQUESTED") {
		t.Errorf("needs must name the veto, got %q", veto.Needs)
	}
	if veto.PRNumber != 513 || veto.PRURL == "" {
		t.Errorf("an open PR carries its number and link, got %d / %q", veto.PRNumber, veto.PRURL)
	}
}

// TestProgressingIsNotOwed: an anchor an automated actor is working is the
// city's move, not the operator's.
//
// The rework child is the shape a derivation keyed on `anchor_bead` gets wrong.
// Only review children carry that key; the rework children that hold an anchor
// between rounds carry `source_review_bead` or nothing, and an anchor with an
// open rework child is as busy as one with an open review.
func TestProgressingIsNotOwed(t *testing.T) {
	anchors := []Anchor{
		mergeAnchor("tk-rev", map[string]string{
			"pr.machine": dated(MachineProgressing, headLive, fixtureNow),
		}, Blocker{ID: "tk-rev1", Title: "codex review", Status: "open",
			RoutedTo: "gc-toolkit/gc-toolkit.polecat-codex", IssueType: "task"}),
		// The recorded verdict is stale — the last gate pass saw a green gate —
		// but a pool-routed child is open right now, and that is live graph
		// truth the gather reads for free.
		mergeAnchor("tk-rew", map[string]string{
			"pr.machine": dated(MachineSettled, headLive, fixtureNow),
		}, Blocker{ID: "tk-rew1", Title: "rework: address the findings", Status: "open",
			RoutedTo: "gc-toolkit/gc-toolkit.polecat", IssueType: "task"}),
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})

	for _, id := range []string{"tk-rev", "tk-rew"} {
		tile := mustTile(t, b, id)
		if tile.PRMachine != MachineProgressing {
			t.Errorf("%s: pr_machine = %q, want %q", id, tile.PRMachine, MachineProgressing)
		}
		if tile.Owed {
			t.Errorf("%s: an anchor a pool is working is not owed by the operator", id)
		}
		if !tile.PROwedSince.IsZero() {
			t.Errorf("%s: a row nothing is owed on carries no clock, got %v", id, tile.PROwedSince)
		}
	}
}

// TestAskingIsOwedAndCarriesTheDemand: the city formed a question and is waiting
// on the answer. That is tk-s4fg87's hold primitive with nothing added — an open
// `blocks` edge to a demand bead — and closing the bead is what ends it.
// TestPositionYieldsToTheHandSetRoute: the PR position outranks the
// human-routed phrase only when the position is what puts the row in the queue.
//
// A person also routes a merge anchor the cadence is happily working, for a
// reason the machine axis knows nothing about. Letting the position speak there
// puts "in the merge cadence" — an agent has it — on a row sitting in the
// operator's own queue, and drops the finding that a hand-set route with no
// takeaway actually carries. Measured on the live board: two anchors at
// `pull_request` + `gc.routed_to=human` read exactly that way.
func TestPositionYieldsToTheHandSetRoute(t *testing.T) {
	anchors := []Anchor{
		// Routed to a person, and the cadence is busy. Both are true; only one
		// of them is why the row is in the queue.
		mergeAnchor("tk-busy", map[string]string{
			"pr.machine":   dated(MachineProgressing, headLive, fixtureNow),
			"gc.routed_to": "human",
			"pr_number":    "509",
		}),
		// A human state carries merge_result and nothing else to name itself by.
		mergeAnchor("tk-bare", map[string]string{
			"merge_result": "held",
			"branch":       "",
			"gc.routed_to": "human",
		}),
		// Nobody is owed this one, and no person routed it: the position is the
		// best thing the row can say.
		mergeAnchor("tk-run", map[string]string{
			"pr.machine": dated(MachineProgressing, headLive, fixtureNow),
		}),
		// A parked merge anchor whose every blocker has closed.
		func() Anchor {
			a := mergeAnchor("tk-disp", map[string]string{
				"gc.takeaway": "waiting on the upstream fix",
			})
			a.Kind, a.Source = "parked", "parked"
			a.WaitingOn = []string{"tk-gone"}
			a.WaitingOnClosed = []string{"tk-gone"}
			return a
		}(),
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})

	busy := mustTile(t, b, "tk-busy")
	if busy.Needs != "routed to you — no question recorded" {
		t.Errorf("a hand-routed row keeps its own finding, got %q", busy.Needs)
	}
	if !busy.Owed {
		t.Error("still owed: a person routed it")
	}
	// The identity is an addition, not a displacement — it is the one thing the
	// human phrase could never say.
	if busy.Frontier != "PR #509" {
		t.Errorf("frontier names the pull request, got %q", busy.Frontier)
	}

	bare := mustTile(t, b, "tk-bare")
	if bare.Frontier != "routed to the operator — no agent will take it" {
		t.Errorf("with no number and no branch the row says who holds it, got %q", bare.Frontier)
	}
	if bare.Needs != "routed to you — no question recorded" {
		t.Errorf("needs = %q", bare.Needs)
	}

	// The disposition phrase is news the identity does not carry, so it keeps
	// its row: a branch name in place of "a blocker landed" is a downgrade.
	disp := mustTile(t, b, "tk-disp")
	if disp.Frontier != "parked · blocker landed" {
		t.Errorf("frontier = %q, want the disposition phrase", disp.Frontier)
	}
	if disp.Needs != "blocker landed — dispose or resume" {
		t.Errorf("needs = %q", disp.Needs)
	}

	run := mustTile(t, b, "tk-run")
	if run.Owed {
		t.Error("an anchor the cadence is working is not the operator's move")
	}
	if run.Needs != "in the merge cadence" {
		t.Errorf("a merge row nobody is owed reports its position, got %q", run.Needs)
	}
}

func TestAskingIsOwedAndCarriesTheDemand(t *testing.T) {
	askedAt := fixtureNow.Add(-30 * time.Hour)
	anchors := []Anchor{
		mergeAnchor("tk-ask", map[string]string{
			"pr.machine": dated(MachineSettled, headLive, fixtureNow),
			"pr_posture": dated(postureNone, headLive, fixtureNow),
		}, Blocker{ID: "tk-dem", Title: "Which base should this land on?", Status: "open",
			RoutedTo: "human", IssueType: "task", CreatedAt: askedAt}),
		// A `decision` is a demand by construction, the way the board's own
		// decision kind is, and needs no route to say so.
		mergeAnchor("tk-ask2", map[string]string{
			"pr.machine": dated(MachineSettled, headLive, fixtureNow),
			"pr_posture": dated(postureNone, headLive, fixtureNow),
		}, Blocker{ID: "tk-dec", Title: "Ruling on the retarget", Status: "open",
			IssueType: "decision", CreatedAt: askedAt}),
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})

	ask := mustTile(t, b, "tk-ask")
	if !ask.Owed {
		t.Error("an anchor waiting on an answer is owed by the operator")
	}
	if !strings.Contains(ask.Needs, "Which base should this land on?") {
		t.Errorf("the row carries the demand's authored headline, got %q", ask.Needs)
	}
	// A demand outlives a head move, so it is dated at the bead's own instant
	// rather than at a head-pinned key.
	if !ask.PROwedSince.Equal(askedAt) {
		t.Errorf("pr_owed_since = %v, want the demand's created_at %v", ask.PROwedSince, askedAt)
	}
	if !mustTile(t, b, "tk-ask2").Owed {
		t.Error("a decision blocker is a demand too")
	}
}

// TestDemandBlockerIsNotProgressing is the other half of the route
// discriminator. Reading every open blocker would call an anchor busy because a
// person has not answered it yet, which inverts the one answer the row exists
// to give.
func TestDemandBlockerIsNotProgressing(t *testing.T) {
	anchors := []Anchor{
		mergeAnchor("tk-q", nil,
			Blocker{ID: "tk-dem", Title: "a question", Status: "open", RoutedTo: "human"},
			// An ordinary prerequisite: no route, no actor.
			Blocker{ID: "tk-pre", Title: "land the other thing first", Status: "open"},
			// A CLOSED pool-routed child proves nothing about now.
			Blocker{ID: "tk-old", Title: "an old review", Status: "closed",
				RoutedTo: "gc-toolkit/gc-toolkit.polecat-codex"},
		),
	}
	tile := mustTile(t, BuildBoard(anchors, fixtureNow, false, nil, Facts{}), "tk-q")
	if tile.PRMachine == MachineProgressing {
		t.Error("neither a demand, a bare prerequisite nor a closed child has an actor behind it")
	}
	if tile.PRMachine != AxisUnknown {
		t.Errorf("with nothing recorded the axis reads unknown, got %q", tile.PRMachine)
	}
}

// TestApprovalClauseIsTotalOverThePosture. The mapping has to cover every value
// pr-facts.sh can record: a partial one leaves the rest to be invented, and
// `not_required` in particular has to be reachable from an ordinary row, or the
// coverage sentence never clears for a repository with no protection rule.
func TestApprovalClauseIsTotalOverThePosture(t *testing.T) {
	at := fixtureNow.Add(-5 * time.Hour)
	cases := []struct {
		posture  string
		approval string
		owed     bool
		why      string
	}{
		{postureReviewRequired, ApprovalRequired, true,
			"GitHub is holding the merge for a review nobody has given"},
		{postureChangesRequested, ApprovalRequired, false,
			"the requirement is unmet, but answering a rejecting review is the city's move"},
		{postureApproved, ApprovalMet, false, "approved"},
		{postureCommented, ApprovalNotRequired, false, "a comment-only review does not gate the merge"},
		{postureNone, ApprovalNotRequired, false, "no protection rule and no review"},
	}
	for _, c := range cases {
		t.Run(c.posture, func(t *testing.T) {
			a := mergeAnchor("tk-"+c.posture, map[string]string{
				"pr.machine": dated(MachineSettled, headLive, fixtureNow),
				"pr_posture": dated(c.posture, headLive, at),
			})
			tile := mustTile(t, BuildBoard([]Anchor{a}, fixtureNow, false, nil, Facts{}), a.ID)
			if tile.PRApproval != c.approval {
				t.Errorf("pr_approval = %q, want %q", tile.PRApproval, c.approval)
			}
			if tile.Owed != c.owed {
				t.Errorf("owed = %v, want %v — %s", tile.Owed, c.owed, c.why)
			}
			if c.owed && !tile.PROwedSince.Equal(at) {
				t.Errorf("pr_owed_since = %v, want the posture stamp %v", tile.PROwedSince, at)
			}
		})
	}
}

// TestApprovalUnknownWhenThePostureIsStaleOrAbsent. A posture read before the
// cadence moved on says nothing about the current head, and pr.machine's own
// head is how the board learns which head that is without asking GitHub.
func TestApprovalUnknownWhenThePostureIsStaleOrAbsent(t *testing.T) {
	anchors := []Anchor{
		mergeAnchor("tk-stale", map[string]string{
			"pr.machine": dated(MachineSettled, headLive, fixtureNow),
			"pr_posture": dated(postureApproved, headOld, fixtureNow),
		}),
		mergeAnchor("tk-nopost", map[string]string{
			"pr.machine": dated(MachineSettled, headLive, fixtureNow),
		}),
		// The pre-migration shape: a posture with no instant is not in the
		// dated shape and cannot be trusted to date anything.
		mergeAnchor("tk-undated", map[string]string{
			"pr.machine": dated(MachineSettled, headLive, fixtureNow),
			"pr_posture": postureReviewRequired + "@" + headLive,
		}),
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})
	for _, id := range []string{"tk-stale", "tk-nopost", "tk-undated"} {
		tile := mustTile(t, b, id)
		if tile.PRApproval != AxisUnknown {
			t.Errorf("%s: pr_approval = %q, want unknown", id, tile.PRApproval)
		}
		if tile.Owed {
			t.Errorf("%s: an unreadable approval belongs in the coverage sentence, not on the row", id)
		}
		if !tile.PROwedSince.IsZero() {
			t.Errorf("%s: an unknown cause contributes no clock, got %v", id, tile.PROwedSince)
		}
	}
}

// TestOwedClockHoldsAcrossPassesAndRestartsOnAHeadMove. The reconcile cadence
// re-derives the same verdict at the same head every few minutes; a clock that
// restarts there reports a three-day wedge as new and sorts the most neglected
// row last.
func TestOwedClockHoldsAcrossPassesAndRestartsOnAHeadMove(t *testing.T) {
	wedgedAt := fixtureNow.Add(-72 * time.Hour)
	held := dated(MachineWedgedException, headLive, wedgedAt)

	first := mustTile(t, BuildBoard([]Anchor{
		mergeAnchor("tk-w", map[string]string{"pr.machine": held}),
	}, fixtureNow, false, nil, Facts{}), "tk-w")

	// A second pass, later, with the value lifecycle.sh's preserve rule leaves
	// untouched — and an updated_at the pass moved, which is exactly what makes
	// updated_at the wrong field to rank by.
	later := fixtureNow.Add(2 * time.Hour)
	a := mergeAnchor("tk-w", map[string]string{"pr.machine": held})
	a.UpdatedAt = later
	second := mustTile(t, BuildBoard([]Anchor{a}, later, false, nil, Facts{}), "tk-w")

	if !first.PROwedSince.Equal(second.PROwedSince) {
		t.Errorf("the clock moved across two passes at an unchanged head: %v then %v",
			first.PROwedSince, second.PROwedSince)
	}

	// A head move releases a wedge, so a wedge at the NEW head is a new turn.
	moved := mustTile(t, BuildBoard([]Anchor{
		mergeAnchor("tk-w", map[string]string{
			"pr.machine": dated(MachineWedgedException, headOld, later),
		}),
	}, later, false, nil, Facts{}), "tk-w")
	if !moved.PROwedSince.Equal(later) {
		t.Errorf("a wedge at a new head starts a fresh clock: got %v, want %v",
			moved.PROwedSince, later)
	}
}

// TestOwedSinceTakesTheEarliestCause. A row wedged three days ago and asked
// about an hour ago has been owed for three days, and the queue ranks it there.
func TestOwedSinceTakesTheEarliestCause(t *testing.T) {
	wedgedAt := fixtureNow.Add(-72 * time.Hour)
	askedAt := fixtureNow.Add(-1 * time.Hour)
	a := mergeAnchor("tk-both", map[string]string{
		"pr.machine": dated(MachineWedgedException, headLive, wedgedAt),
	}, Blocker{ID: "tk-d", Title: "and a question", Status: "open",
		RoutedTo: "human", CreatedAt: askedAt})

	tile := mustTile(t, BuildBoard([]Anchor{a}, fixtureNow, false, nil, Facts{}), "tk-both")
	if !tile.PROwedSince.Equal(wedgedAt) {
		t.Errorf("pr_owed_since = %v, want the EARLIEST cause %v", tile.PROwedSince, wedgedAt)
	}
}

// TestUnrecordedPositionIsUnknownAndCountsAgainstCoverage. A missing key means
// the cadence has not written one yet, which is a fact about the city rather
// than an all-clear — and the all-clear is exactly what a quiet default would
// produce.
func TestUnrecordedPositionIsUnknownAndCountsAgainstCoverage(t *testing.T) {
	b := BuildBoard([]Anchor{
		mergeAnchor("tk-silent", nil),
		{ID: "tk-epic", Title: "an ordinary epic", Kind: "epic", Source: "epic",
			Rig: "gc-toolkit", Prefix: "tk", Children: []Child{{ID: "c1", Status: "open"}}},
	}, fixtureNow, false, nil, Facts{})

	silent := mustTile(t, b, "tk-silent")
	if silent.PRMachine != AxisUnknown {
		t.Errorf("pr_machine = %q, want unknown", silent.PRMachine)
	}
	if !strings.Contains(silent.Needs, "unknown") {
		t.Errorf("the row says its position is unread, got %q", silent.Needs)
	}

	// A row that is not a merge anchor carries EMPTY axes, not `unknown`: "not
	// a pull request" and "a pull request nobody can read" are different
	// answers, and only the second is a gap.
	epic := mustTile(t, b, "tk-epic")
	if epic.PRMachine != "" || epic.PRConversation != "" || epic.PRApproval != "" {
		t.Errorf("a non-merge row carries no axes, got %q/%q/%q",
			epic.PRMachine, epic.PRConversation, epic.PRApproval)
	}

	c := Coverage(b.Tiles)
	if c.Rows != 1 {
		t.Errorf("coverage counts merge anchors only: got %d, want 1", c.Rows)
	}
	if c.MachineUnknown != 1 {
		t.Errorf("the unrecorded position counts against coverage: got %d", c.MachineUnknown)
	}
	if c.Complete() {
		t.Error("coverage cannot be complete while a position is unread — that is the all-clear nobody earned")
	}
}

// TestConversationAxisIsHonestlyUnknown. Its other values all resolve to
// acknowledgement watermarks nothing records yet. Shipping a guess would render
// `quiet` for a pull request the operator commented on, which is the one
// mistake this axis exists to prevent, so the field ships as `unknown` and the
// coverage sentence carries the reason.
func TestConversationAxisIsHonestlyUnknown(t *testing.T) {
	b := BuildBoard([]Anchor{
		mergeAnchor("tk-c", map[string]string{
			"pr.machine": dated(MachineSettled, headLive, fixtureNow),
			"pr_posture": dated(postureNone, headLive, fixtureNow),
		}),
	}, fixtureNow, false, nil, Facts{})

	tile := mustTile(t, b, "tk-c")
	if tile.PRConversation != ConversationUnknown {
		t.Errorf("pr_conversation = %q, want unknown in this phase", tile.PRConversation)
	}
	// This row is settled, approved-not-required and owed by nobody. It is
	// still not an all-clear, because where the conversation stands is unread.
	if tile.Owed {
		t.Error("nothing here makes the row owed")
	}
	if c := Coverage(b.Tiles); c.Complete() || c.ConversationUnknown != 1 {
		t.Errorf("the unread conversation has to reach the coverage sentence: %+v", c)
	}
}

// TestOwedPRRowLeadsTheQueue. The partition and its ordering are tk-lb3u4m's;
// this asserts a PR row participates in them rather than needing a surface of
// its own.
func TestOwedPRRowLeadsTheQueue(t *testing.T) {
	old := fixtureNow.Add(-96 * time.Hour)
	recent := fixtureNow.Add(-2 * time.Hour)
	b := BuildBoard([]Anchor{
		mergeAnchor("tk-new", map[string]string{"pr.machine": dated(MachineWedgedVeto, headLive, recent)}),
		{ID: "tk-big", Title: "a container that outranks everything", Kind: "epic", Source: "epic",
			Rig: "gc-toolkit", Prefix: "tk", Children: func() []Child {
				out := make([]Child, 40)
				for i := range out {
					out[i] = Child{ID: fmt.Sprintf("k%d", i), Status: "open"}
				}
				return out
			}()},
		mergeAnchor("tk-old", map[string]string{"pr.machine": dated(MachineWedgedException, headLive, old)}),
	}, fixtureNow, false, nil, Facts{})

	q := OperatorQueue(b.Tiles)
	got := []string{}
	for _, t := range q {
		got = append(got, t.ID)
	}
	if !slices.Equal(got, []string{"tk-old", "tk-new"}) {
		t.Errorf("the queue is the wedged rows, oldest-owed first: got %v", got)
	}
	if _, ok := tileByID(Board{Tiles: q}, "tk-big"); ok {
		t.Error("a container nobody is owed anything on is not in the operator's queue")
	}
}

// TestWedgedAnchorGathersTwiceAndCollapsesToOneRow.
//
// A wedged anchor carries `gc.routed_to=human` AND `merge_result`, so the
// gather admits it under both kinds and hands BuildBoard two anchors with one
// id. Both rows read the same metadata, so they band the same and tie on
// rank_score — which means the stable sort, not the band, decides which
// survives, and the gather's ordering is load-bearing rather than incidental.
//
// The row that survives has to keep both halves: the `human` kind every
// human-gate rule keys on, and the PR axes, which are what this surface adds.
// Losing either is silent — the operator just sees one fewer fact.
func TestWedgedAnchorGathersTwiceAndCollapsesToOneRow(t *testing.T) {
	wedgedAt := fixtureNow.Add(-72 * time.Hour)
	md := map[string]string{
		"merge_result": "pre_open_gate",
		"branch":       "polecat/tk-w",
		"gc.routed_to": "human",
		"pr.machine":   dated(MachineWedgedException, headLive, wedgedAt),
	}
	humanRow := mergeAnchor("tk-w", md)
	humanRow.Kind, humanRow.Source = "human", "human"
	mergeRow := mergeAnchor("tk-w", md)

	b := BuildBoard([]Anchor{humanRow, mergeRow}, fixtureNow, false, nil, Facts{})

	if len(b.Tiles) != 1 || b.Total != 1 {
		t.Fatalf("one bead is one row: got %d tiles (total %d)", len(b.Tiles), b.Total)
	}
	tile := b.Tiles[0]
	if tile.Kind != "human" {
		t.Errorf("kind = %q, want human — the gather orders it first so the kind cannot flip between passes", tile.Kind)
	}
	if tile.PRMachine != MachineWedgedException || !tile.PROwedSince.Equal(wedgedAt) {
		t.Errorf("the surviving row lost its axes: machine=%q since=%v", tile.PRMachine, tile.PROwedSince)
	}
	if !tile.Owed {
		t.Error("and it is still owed")
	}
	// Both derivations agree it is owed, so neither ordering could drop it from
	// the queue — but they must also agree on the phrase, or the row a reader
	// sees depends on which copy won.
	if !strings.Contains(tile.Needs, "wedged") {
		t.Errorf("needs = %q, want the wedge named", tile.Needs)
	}
}

// TestCappedAnchorBlockerIsADemandToday is the live shape this rule was
// measured against, and it is the one case where the demand test is wider than
// tk-s4fg87's three authored shapes.
//
// On live gc-toolkit, tk-j81t84 blocks on tk-dchq5: a `bug` at pre_open_gate,
// routed to a person by the convergence cap, open for thirteen days. It is not
// a `decision` and not a visit, so a narrow reading calls it an ordinary
// prerequisite and the waiting row stays out of the queue — which is where it
// had been sitting, banded LOW, with a takeaway saying the work was finished and
// only an operator could open its PR.
//
// tk-s4fg87's phase 3 converts capped anchors into exactly the decision bead a
// narrow reading would want. Until it runs, this IS that bead.
func TestCappedAnchorBlockerIsADemandToday(t *testing.T) {
	cappedAt := fixtureNow.Add(-13 * 24 * time.Hour)
	a := mergeAnchor("tk-waiter", map[string]string{"pr_number": "473"},
		Blocker{
			ID: "tk-capped", Title: "the fix its PR cannot open", Status: "open",
			// The shape signoff.sh's cap arm leaves behind: routed to a person,
			// no pool route, an ordinary work type.
			RoutedTo: "human", IssueType: "bug", CreatedAt: cappedAt,
		})
	tile := mustTile(t, BuildBoard([]Anchor{a}, fixtureNow, false, nil, Facts{}), "tk-waiter")

	if !tile.Owed {
		t.Error("an anchor whose only blocker no automated actor will close is waiting on a person")
	}
	if !tile.PROwedSince.Equal(cappedAt) {
		t.Errorf("pr_owed_since = %v, want the blocker's own created_at %v", tile.PROwedSince, cappedAt)
	}
	// Two rows in the queue can share one cause, so the waiting row has to name
	// the bead it is waiting on rather than just asserting that it waits.
	if !strings.Contains(tile.Needs, "the fix its PR cannot open") {
		t.Errorf("needs must name what it is waiting on, got %q", tile.Needs)
	}

	// A pool-routed blocker of the same shape is the control: something will
	// claim it, so nothing is owed.
	b := mergeAnchor("tk-busy", nil, Blocker{
		ID: "tk-rework", Title: "rework in flight", Status: "open",
		RoutedTo: "gc-toolkit/gc-toolkit.polecat", IssueType: "bug", CreatedAt: cappedAt,
	})
	if mustTile(t, BuildBoard([]Anchor{b}, fixtureNow, false, nil, Facts{}), "tk-busy").Owed {
		t.Error("a pool-routed blocker of the same shape is the city's move, not the operator's")
	}
}
