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

// TestFourAnchorBoard is the board's primary golden case: three epics (two
// stranded, one with a closed child) and a decision — the stranded epic opens
// the board at HIGH and outranks the ELEVATED decision.
func TestFourAnchorBoard(t *testing.T) {
	anchors := []Anchor{
		{ID: "tk-one", Title: "CI mystery", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(3), Children: []Child{
			{ID: "tk-hh1", Status: "open"},
		}},
		{ID: "tk-epic", Title: "Big epic", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), Children: []Child{
			{ID: "tk-a", Status: "open"}, {ID: "tk-b", Status: "closed"},
		}},
		{ID: "ra-dec", Title: "Pick a path", Kind: "decision", Source: "decision", Rig: "rig-a", Prefix: "ra", Priority: ptr(1)},
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
	if got := b.Tiles[0].ID; got != "ra-dec" {
		t.Errorf("the owed decision leads the board: got %s", got)
	}
	if got := b.Tiles[1].Severity; got != SevHigh {
		t.Errorf("the overview still opens on a stranded epic: want HIGH, got %s", got)
	}
	// the stranded epic still outranks the decision on rank_score.
	epic, _ := tileByID(b, "tk-epic")
	dec, _ := tileByID(b, "ra-dec")
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
	if parked.Frontier != "needs-review · conversation parked — no takeaway recorded" {
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
	if stranded.Frontier != "needs-review · 1 open · 0 in flight (stranded)" {
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
	if moving.Frontier != "needs-review · 1 open · 1 in flight" {
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
	if landed.Frontier != "needs-review · all 2 closed · 0 open" {
		t.Errorf("the frontier stops claiming it wants nothing: %q", landed.Frontier)
	}

	bare, _ := tileByID(b, "tk-bare")
	if bare.Severity != SevLow || bare.MTotal != 0 {
		t.Errorf("a childless parked row is untouched: %s %d children", bare.Severity, bare.MTotal)
	}
	if bare.Frontier != "needs-review · conversation parked — no takeaway recorded" {
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

// TestParkedWithLiveMoleculeIsActive covers the case tk-ygeufl found: a parked
// subject carries gc.takeaway — so it is gathered as the parked kind — AND has
// been re-dispatched, so a live work molecule is executing it. That molecule is
// not a tile: `gc sling` leaves the subject at open/unassigned and puts the
// in-flight state on the workflow, visible only through Facts.Inflight keyed by
// the subject's OWN id. The band must read that live execution and NOT sink the
// row to the parked LOW floor, where an actively-worked bead would read as a
// finished row to dispose of.
func TestParkedWithLiveMoleculeIsActive(t *testing.T) {
	// One anchor shape, wired to a workflow three ways, so the signal that flips
	// the band is proven to be LIVE execution and nothing else.
	parked := func(id string) Anchor {
		return Anchor{ID: id, Title: "re-dispatched after the ruling", Kind: "parked", Source: "parked",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1),
			Takeaway: "confirmed — proceed; record kept on this bead"}
	}
	f := Facts{
		// tk-live: a molecule whose session is still up. tk-drained: the same
		// wiring, but the session has gone — wfLive must stop counting it at once.
		Inflight: map[string][]string{
			"tk-live":    {"gc-toolkit__polecat-hq-live"},
			"tk-drained": {"gc-toolkit__polecat-hq-gone"},
		},
		OwnerState: map[string]string{"gc-toolkit__polecat-hq-live": "active"},
	}
	b := BuildBoard([]Anchor{parked("tk-live"), parked("tk-drained"), parked("tk-none")}, fixtureNow, false, nil, f)

	live := mustTile(t, b, "tk-live")
	if live.Severity != SevNormal {
		t.Errorf("a parked subject with a live molecule is in-flight work, not the LOW floor: got %s", live.Severity)
	}
	if live.Section != SectionActive {
		t.Errorf("…so it bands active, not cleanup: got %s", live.Section)
	}
	// The frontier speaks the row's state: a takeaway does not park a bead the
	// city is working.
	if live.Frontier != "working · in flight" {
		t.Errorf("frontier: %q", live.Frontier)
	}
	// The takeaway still answers NEEDS, exactly as it does for ruledInFlight: the
	// ruling is the best sentence the row has, and it is on the wire regardless.
	if live.Needs != "confirmed — proceed; record kept on this bead" {
		t.Errorf("the takeaway stays the NEEDS answer: %q", live.Needs)
	}

	// The discriminator: identical wiring, dead session. A molecule that drained
	// stops counting, so this row falls back to the parked floor.
	drained := mustTile(t, b, "tk-drained")
	if drained.Severity != SevLow || drained.Section != SectionCleanup {
		t.Errorf("a parked subject whose molecule drained returns to the floor: got %s / %s", drained.Severity, drained.Section)
	}

	// And with no workflow at all, the floor is still right.
	none := mustTile(t, b, "tk-none")
	if none.Severity != SevLow || none.Section != SectionCleanup {
		t.Errorf("a genuinely parked conversation is untouched: got %s / %s", none.Severity, none.Section)
	}
	if none.Frontier != "needs-review · conversation parked — takeaway recorded" {
		t.Errorf("…and still reports the parked frontier: %q", none.Frontier)
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
			WaitingOn: []string{"ra-9999"}},
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
	f := liveOwners("gc-toolkit__polecat-hq-1")
	f.Inflight = map[string][]string{"w1": {"gc-toolkit__polecat-hq-1"}}

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
	dead := Facts{Inflight: f.Inflight, OwnerState: map[string]string{"gc-toolkit__polecat-hq-1": "archived"}}
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
	f := Facts{Prefixes: []string{"tk", "ra", "rb"}, RigNames: []string{"gc-toolkit", "rig-a"}}
	a := Anchor{ID: "tk-xref", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(3),
		Description: "blocks ra-abc12 and rb-9zz, follows tk-local1 and tk-xref itself",
		Children:    []Child{{ID: "c1", Status: "open"}}}

	tl := BuildBoard([]Anchor{a}, fixtureNow, false, nil, f).Tiles[0]
	if !equalIDs(tl.CrossRigRefs, []string{"ra-abc12", "rb-9zz"}) {
		t.Errorf("cross_rig_refs = %v, want [ra-abc12 rb-9zz] (own prefix and self excluded)", tl.CrossRigRefs)
	}
	// weight = m_total(1) + prio_w(3)=1 + min(2 refs, cap)
	if tl.Weight != 1+1+2 {
		t.Errorf("weight folds the ref count: got %d, want 4", tl.Weight)
	}

	// A decision is banded by what it IS, so the scan is skipped entirely.
	dec := Anchor{ID: "ra-dec", Kind: "decision", Source: "decision", Rig: "rig-a", Prefix: "ra",
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
	if owncv.Needs != "all 1 tracked closed" {
		t.Errorf("a complete convoy reads that every tracked bead is closed: got %q", owncv.Needs)
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
		if tile.Frontier != "needs-review · ruled — takeaway recorded" {
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

// TestRuledInFlightIsInProgress covers the in-flight ruling. "Answered" is not
// "answered and the work landed", so a human-gated row whose ruling slung work
// still open is not settled — [ruled] does not fire. But it is not un-ruled
// either: the operator decided and an agent now holds the next move. It reads as
// work in progress — NORMAL, below the ELEVATED an un-answered gate gets and
// above the LOW a settled ruling sinks to — and frontier agrees with NEEDS
// rather than reporting the un-ruled "no agent will take it" (or, for a
// decision, "human-gated decision") on a row that already carries its ruling.
//
// The wait clause is only non-vacuous because the gather reads waiting edges for
// these kinds at all — see source.needsWaitingEdges. Both human-gated shapes are
// covered: a decision, and a human-routed bead (the Pino row on the bead).
func TestRuledInFlightIsInProgress(t *testing.T) {
	anchors := []Anchor{
		{ID: "tk-hs2e8", Title: "clean-exit rate", Kind: "decision", Source: "decision",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1),
			Takeaway:  "answered NO — real bug is stranded holds, routed tk-jsyci7",
			WaitingOn: []string{"tk-jsyci7"}},
		{ID: "ra-fm1xp", Title: "bring Pino back", Kind: "human", Source: "human",
			Rig: "rig-a", Prefix: "ra", Priority: ptr(1), UpdatedAt: daysAgo(1),
			Takeaway:  "ruled: bring Pino back — work slung ra-9kd2, awaiting implementation",
			WaitingOn: []string{"ra-9kd2"}},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})

	for _, c := range []struct{ id, needs string }{
		{"tk-hs2e8", "answered NO — real bug is stranded holds, routed tk-jsyci7"},
		{"ra-fm1xp", "ruled: bring Pino back — work slung ra-9kd2, awaiting implementation"},
	} {
		tile, ok := tileByID(b, c.id)
		if !ok {
			t.Fatalf("%s is missing from the board", c.id)
		}
		if tile.Severity != SevNormal {
			t.Errorf("%s: a ruled row with work in flight is in progress, got %s", c.id, tile.Severity)
		}
		if tile.Frontier != "needs-review · ruled — work in flight" {
			t.Errorf("%s frontier: %q", c.id, tile.Frontier)
		}
		// The ruling still answers, so NEEDS no longer contradicts frontier.
		if tile.Needs != c.needs {
			t.Errorf("%s needs: %q", c.id, tile.Needs)
		}
		// An agent holds the next move, so the operator is owed nothing and the
		// row leaves their queue.
		if tile.Owed {
			t.Errorf("%s: a ruled, in-flight row is not the operator's to move", c.id)
		}
		// The outstanding slung work stays named on the wire.
		if len(tile.WaitingOnOpen) != 1 {
			t.Errorf("%s: the outstanding slung work is named: %v", c.id, tile.WaitingOnOpen)
		}
	}
}

// TestRuledNeedsTheWaitsToBeLegible is the fail-closed guard for the other way
// an empty `waiting_on_open` can arise. TestRuledInFlightIsInProgress covers a
// wait that WAS read and is still open; this covers a wait set the source could
// not read at all — where neither [ruled] nor [ruledInFlight] fires, so the row
// falls to the un-ruled arm and keeps its band rather than being read as
// in-flight on a graph the board never checked.
//
// The two look identical on the anchor — WaitingOn is empty in both the
// "nothing outstanding" case and the "never learned" one — and reading the
// empty set as an answer is the hazard. A Dolt timeout or schema
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
		{"tk-z130v", "needs-review · human-gated decision", "ROUTED: mayor mailed to excise gc-8yr6px"},
		{"tk-j5wrs", "needs-review · routed to the operator — no agent will take it", "routed — design ruled; tk-vie5k slung"},
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
	if dec.Severity != SevElevated || dec.Frontier != "needs-review · human-gated decision" || dec.Needs != "operator decision" {
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
	// gone. ra-kg9z6.1.2 — one of the seven rows this rule was measured on —
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

// TestOpenDemandStaysOwed is the acceptance case for the demand verb. The verb
// files what a person owes as its own bead: `gc.demand_for` names the work it
// gates, `gc.routed_to=human` puts it on the operator's queue, and the authored
// headline is stamped as `gc.takeaway` so the board has a question to show. The
// demand carries no blocker of its own — it IS the blocker — so a fresh one
// satisfies every clause [ruled] had before [isDemand], and stood down on the
// render that first saw it. The row the verb exists to raise dropped straight
// out of the default queue.
//
// The two controls are what make the exclusion narrow rather than a hole in the
// stand-down: an ordinary answered row beside the demand still stands down, and
// the demand stops being owed the moment it closes, which is how it is answered.
func TestOpenDemandStaysOwed(t *testing.T) {
	const headline = "which of the two shapes should converse file?"
	const ruling = "file the sibling shape — it keeps the visit claimable"
	demandMD := map[string]string{
		"gc.routed_to":   "human",
		"gc.takeaway":    headline,
		"gc.demand_for":  "tk-gated",
		"gc.takeaway_at": "2026-06-30T10:00:00Z",
	}
	anchors := []Anchor{
		// A decision demand, gathered twice: once as a decision, once
		// off the `gc.routed_to=human` marker. Both rows are one bead, and the
		// dedup keeps the higher band — so both have to stay up, or the twin
		// hands the stand-down back.
		{ID: "tk-demand", Title: headline, Kind: "decision", Source: "decision",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1),
			Metadata: demandMD, Takeaway: headline, TakeawayAt: demandMD["gc.takeaway_at"]},
		{ID: "tk-demand", Title: headline, Kind: "human", Source: "human",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1),
			Metadata: demandMD, Takeaway: headline, TakeawayAt: demandMD["gc.takeaway_at"]},
		// Control: answered, no demand marker, still stands down.
		{ID: "tk-answered", Title: "an ordinary ruling", Kind: "human", Source: "human",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1),
			Metadata: map[string]string{"gc.routed_to": "human", "gc.takeaway": "routed — nothing further needed here"},
			Takeaway: "routed — nothing further needed here"},
		// Control: the same demand once answered. Closing it is what makes the
		// gated work ready, and what takes the row off the queue. Its ruling was
		// never stamped back (gc.takeaway_settled empty), so its takeaway is still
		// the QUESTION and must not ride the DONE band as if unanswered.
		{ID: "tk-discharged", Title: "an answered demand", Kind: "decision", Source: "decision",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(2),
			ClosedAt:   daysAgo(1),
			Metadata:   map[string]string{"gc.routed_to": "human", "gc.takeaway": headline, "gc.demand_for": "tk-gated"},
			Takeaway:   headline,
			TakeawayAt: "2026-06-30T10:00:00Z", TakeawayBy: "converse"},
		// Control: a closed demand whose ruling WAS stamped back over the question
		// and marked settled. Its takeaway is the answer now, so the DONE band
		// shows the ruling rather than suppressing it.
		{ID: "tk-settled", Title: "a settled demand", Kind: "decision", Source: "decision",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(2),
			ClosedAt: daysAgo(1),
			Metadata: map[string]string{"gc.routed_to": "human", "gc.takeaway": ruling, "gc.demand_for": "tk-gated", "gc.takeaway_settled": "1"},
			Takeaway: ruling},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})

	tile, ok := tileByID(b, "tk-demand")
	if !ok {
		t.Fatal("tk-demand is missing from the board")
	}
	if !tile.Owed {
		t.Error("an open demand is what a person owes — it must stay on the operator's queue")
	}
	if tile.Severity != SevElevated {
		t.Errorf("an unanswered demand keeps the human-gated band, got %s (kind %s)", tile.Severity, tile.Kind)
	}
	if tile.Needs != headline {
		t.Errorf("needs is the question itself, not a disposition: %q", tile.Needs)
	}
	if tile.Frontier == "ruled — takeaway recorded" {
		t.Errorf("frontier reads the demand as answered: %q", tile.Frontier)
	}
	// Owed rows partition ahead of the rest, oldest ask first.
	if b.Tiles[0].ID != "tk-demand" {
		t.Errorf("the demand heads the queue, got %q", b.Tiles[0].ID)
	}

	answered, ok := tileByID(b, "tk-answered")
	if !ok {
		t.Fatal("tk-answered is missing from the board")
	}
	if answered.Owed || answered.Severity != SevLow || answered.Needs != "ruled — close or extend" {
		t.Errorf("the stand-down still fires for an ordinary answered row: owed=%v %s %q",
			answered.Owed, answered.Severity, answered.Needs)
	}

	discharged, ok := tileByID(b, "tk-discharged")
	if !ok {
		t.Fatal("tk-discharged is missing from the board")
	}
	if discharged.Owed || discharged.Severity != SevDone {
		t.Errorf("a closed demand owes nothing: owed=%v %s", discharged.Owed, discharged.Severity)
	}
	// The QUESTION must not ride the wire once the demand is closed: --json
	// takeaway is where a row publishes its ruling, and a stale question there
	// reads as a decision still owed. The triple is suppressed together.
	if discharged.Takeaway != nil {
		t.Errorf("a closed unsettled demand still carries its question on the wire: %q", *discharged.Takeaway)
	}
	if discharged.TakeawayAt != nil || discharged.TakeawayBy != nil {
		t.Errorf("a suppressed takeaway must carry no timestamp or author: at=%v by=%v",
			discharged.TakeawayAt, discharged.TakeawayBy)
	}

	settled, ok := tileByID(b, "tk-settled")
	if !ok {
		t.Fatal("tk-settled is missing from the board")
	}
	if settled.Takeaway == nil || *settled.Takeaway != ruling {
		t.Errorf("a settled closed demand shows its ruling on the wire, got %v", settled.Takeaway)
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

// TestSittingTopicAndHeadlineFallback pins the two derivations a row reads off
// its subject: the topic is the subject's title, and the headline prefers the
// takeaway, then a dedup close's own outcome reason, and only then the subject
// title before it ever shows the visit bead's own generic name. Both degrade to
// the id and the visit title only when the gather could not read the subject at
// all.
func TestSittingTopicAndHeadlineFallback(t *testing.T) {
	const (
		subjTitle = "the raw script path the launcher took"
		visit     = "visit: tk-anchor — first reaction ready: accept or redirect"
		takeaway  = "routed the fix to the pool; nothing further here"
		reason    = "moot: premise died, subject already closed"
	)

	// A concluded sitting: the takeaway is the headline, the subject title the topic.
	concluded := Sitting{Subject: "tk-anchor", SubjectTitle: subjTitle, Title: visit, Takeaway: takeaway}
	if got := concluded.Headline(); got != takeaway {
		t.Errorf("a takeaway is the headline: got %q, want %q", got, takeaway)
	}
	if got := concluded.Topic(); got != subjTitle {
		t.Errorf("the topic is the subject title: got %q, want %q", got, subjTitle)
	}

	// A takeaway still wins when an outcome reason is also present.
	both := Sitting{Subject: "tk-anchor", SubjectTitle: subjTitle, Title: visit, Takeaway: takeaway, OutcomeReason: reason}
	if got := both.Headline(); got != takeaway {
		t.Errorf("a takeaway wins over the outcome reason: got %q, want %q", got, takeaway)
	}

	// A dedup close: no takeaway, but an outcome reason — the headline is the
	// reason, so the row reads as a decision instead of the bare topic.
	dedup := Sitting{Subject: "tk-anchor", SubjectTitle: subjTitle, Title: visit, OutcomeReason: reason}
	if got := dedup.Headline(); got != reason {
		t.Errorf("no takeaway but an outcome reason: the headline is the reason: got %q, want %q", got, reason)
	}

	// No takeaway, no reason, subject read: the headline is the topic, NOT the visit title.
	bare := Sitting{Subject: "tk-anchor", SubjectTitle: subjTitle, Title: visit}
	if got := bare.Headline(); got != subjTitle {
		t.Errorf("no takeaway falls back to the subject title, not the visit title: got %q, want %q", got, subjTitle)
	}
	if got := bare.Topic(); got != subjTitle {
		t.Errorf("topic is the subject title: got %q, want %q", got, subjTitle)
	}

	// Subject unread: the last resorts are the visit title and the bare id.
	unread := Sitting{Subject: "tk-anchor", Title: visit}
	if got := unread.Headline(); got != visit {
		t.Errorf("an unread subject falls back to the visit title: got %q, want %q", got, visit)
	}
	if got := unread.Topic(); got != "tk-anchor" {
		t.Errorf("an unread subject topic falls back to the id: got %q, want %q", got, "tk-anchor")
	}
}

// TestParkedChildIsNotIdleWork: an epic whose child is finished and waiting on
// a ruling must not report that child as idle work. "Assign or visit" names the
// wrong bead — the child is already assigned, to the operator.
func TestParkedChildIsNotIdleWork(t *testing.T) {
	kids := []Child{
		{ID: "ra-kg9z6.1.9", Status: "open", Metadata: map[string]string{
			"gc.routed_to": "human",
			"gc.takeaway":  "holding for your ruling",
		}},
		{ID: "ra-kg9z6.1.2", Status: "open", Metadata: map[string]string{"gc.routed_to": "human"}},
	}
	for i := 1; i <= 5; i++ {
		kids = append(kids, Child{ID: "ra-idle" + string(rune('0'+i)), Status: "open"})
	}
	anchors := []Anchor{{
		ID: "ra-kg9z6.1", Title: "the parent epic", Kind: "epic", Source: "epic",
		Rig: "rig-a", Prefix: "ra", Priority: ptr(1), Children: kids,
	}}

	tile, ok := tileByID(BuildBoard(anchors, fixtureNow, false, nil, Facts{}), "ra-kg9z6.1")
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
		if id == "ra-kg9z6.1.9" || id == "ra-kg9z6.1.2" {
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
// on the operator, the parent has no ask of its own — the asks are the
// operator's, on the children or the gates that hold them.
func TestAllChildrenParkedIsNotStranded(t *testing.T) {
	anchors := []Anchor{{
		ID: "tk-epic", Title: "everything is with the operator", Kind: "epic", Source: "epic",
		Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), Children: []Child{
			{ID: "tk-a", Status: "open", Metadata: map[string]string{"gc.routed_to": "human"}},
			{ID: "tk-b", Status: "open", Metadata: map[string]string{"gc.takeaway": "ruling owed"},
				Blockers: []Blocker{{ID: "tk-gate", Title: "parked until the ruling", Status: "open", IssueType: "gate"}}},
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

// TestTakeawayAloneDoesNotParkAChild: a child is parked when a person holds it,
// not because a sitting left a takeaway on it. With no wait, no route, no arm
// and nothing in progress, nothing will start it, so it strands its parent.
func TestTakeawayAloneDoesNotParkAChild(t *testing.T) {
	anchors := []Anchor{{
		ID: "ra-epic", Title: "a sitting concluded and routed nothing", Kind: "epic", Source: "epic",
		Rig: "rig-a", Prefix: "ra", Priority: ptr(2), Children: []Child{
			{ID: "ra-epic.1", Status: "open", Metadata: map[string]string{"gc.takeaway": "ruled — do it after sign-up"}},
		},
	}}
	tile := mustTile(t, BuildBoard(anchors, fixtureNow, false, nil, Facts{}), "ra-epic")
	if len(tile.ParkedHeads) != 0 || !equalIDs(tile.OpenHeads, []string{"ra-epic.1"}) {
		t.Errorf("the takeaway child is stranded, not parked: parked=%v open=%v", tile.ParkedHeads, tile.OpenHeads)
	}
	if !tile.Stranded || tile.Severity != SevHigh {
		t.Errorf("nothing will start it, so the epic strands: sev=%s stranded=%v", tile.Severity, tile.Stranded)
	}
	if tile.Frontier != "needs-review · 1 open · 0 in flight (stranded)" {
		t.Errorf("frontier = %q", tile.Frontier)
	}
}

// TestQueuedChildrenAreNotStranded covers an epic whose open children wait
// their turn behind a sibling in review. Each queued child is armed, so it
// starts by itself once the sibling lands: none of them is work nobody has
// picked up. The sibling carries a takeaway, an open pull request whose review
// rounds have all closed, and a sitting in progress, and it reads in review.
// Children that nothing holds and nothing will start still strand the epic.
func TestQueuedChildrenAreNotStranded(t *testing.T) {
	arm := "rig-a/gc-toolkit.polecat"
	inReview := Blocker{ID: "ra-epic.1", Title: "Platform admin", Status: "open", IssueType: "task"}
	round := Blocker{ID: "ra-rework", Title: "Rework PR #62", Status: "closed", IssueType: "task",
		RoutedTo: "rig-a/gc-toolkit.polecat"}
	waiting := []Child{
		{ID: "ra-epic.1", Status: "open", Blockers: []Blocker{round},
			Metadata: map[string]string{"gc.takeaway": "ruled; PR #62 is in rework", "merge_result": "pull_request", "pr_number": "62"}},
		{ID: "ra-epic.2", Status: "open", Blockers: []Blocker{inReview},
			Metadata: map[string]string{"gc.dispatch_when_ready": arm}},
		{ID: "ra-epic.3", Status: "open", Blockers: []Blocker{inReview},
			Metadata: map[string]string{"gc.dispatch_when_ready": arm, "gc.takeaway": "after sign-up"}},
		{ID: "ra-epic.4", Status: "open", Blockers: []Blocker{round, inReview},
			Metadata: map[string]string{"gc.dispatch_when_ready": arm}},
		{ID: "ra-epic.5", Status: "closed"},
	}
	facts := Facts{
		Sittings: []Sitting{{ID: "ra-visit", Subject: "ra-epic.1", Subjects: []string{"ra-epic.1"},
			Title: "visit: ra-epic.1 — settle the rework", Status: sittingInProgress, Session: "converse-1"}},
		Visits: map[string]bool{"ra-epic.1": true},
	}
	epic := func(kids []Child) []Anchor {
		return []Anchor{{ID: "ra-epic", Title: "Platform foundation", Kind: "epic", Source: "epic",
			Rig: "rig-a", Prefix: "ra", Priority: ptr(2), Children: kids}}
	}

	t.Run("every open child waits on something", func(t *testing.T) {
		tile := mustTile(t, BuildBoard(epic(waiting), fixtureNow, false, nil, facts), "ra-epic")
		if tile.Stranded || tile.Severity == SevHigh {
			t.Errorf("children waiting their turn do not strand the epic: sev=%s stranded=%v", tile.Severity, tile.Stranded)
		}
		if tile.Frontier != "needs-review · 1 in review · 3 queued · nothing idle" {
			t.Errorf("frontier = %q", tile.Frontier)
		}
		if tile.Needs != "nothing idle — 1 in review, 3 queued" {
			t.Errorf("needs = %q", tile.Needs)
		}
		if len(tile.OpenHeads) != 0 || len(tile.ParkedHeads) != 0 {
			t.Errorf("nothing is idle or parked: open=%v parked=%v", tile.OpenHeads, tile.ParkedHeads)
		}
		if tile.Open != 4 {
			t.Errorf("open = %d, want the honest total 4", tile.Open)
		}
	})

	t.Run("children nothing will start still strand it", func(t *testing.T) {
		kids := append(append([]Child{}, waiting...),
			Child{ID: "ra-epic.6", Status: "open"},
			Child{ID: "ra-epic.7", Status: "open", Metadata: map[string]string{"placement": "pending"}})
		tile := mustTile(t, BuildBoard(epic(kids), fixtureNow, false, nil, facts), "ra-epic")
		if !tile.Stranded || tile.Severity != SevHigh {
			t.Errorf("two children nothing will start strand the epic: sev=%s stranded=%v", tile.Severity, tile.Stranded)
		}
		if tile.Frontier != "needs-review · 2 open · 0 in flight (stranded) · 1 in review · 3 queued" {
			t.Errorf("the frontier counts the stranded ones and names the rest: %q", tile.Frontier)
		}
		if !equalIDs(tile.OpenHeads, []string{"ra-epic.6", "ra-epic.7"}) {
			t.Errorf("open_heads names only the stranded children: %v", tile.OpenHeads)
		}
	})
}

// TestNestedParentReadsItsChildren: a sub-epic carries no route and no arm of
// its own, so read by its own bead alone it would always be stranded. Nothing
// holds its bead, so its parent counts it by what its own children are doing:
// queued while they wait their turn, in flight while one moves, and stranded
// only while one is idle. The reading carries through every level.
func TestNestedParentReadsItsChildren(t *testing.T) {
	arm := map[string]string{"gc.dispatch_when_ready": "rig-a/gc-toolkit.polecat"}
	sibling := Blocker{ID: "ra-x", Title: "Platform admin", Status: "open", IssueType: "task"}
	live := liveOwners("polecat-live")
	family := func(leaf Child) []Anchor {
		return []Anchor{
			{ID: "ra-top", Kind: "epic", Source: "epic", Rig: "rig-a", Prefix: "ra",
				Children: []Child{{ID: "ra-mid", Status: "open"}, {ID: "ra-done", Status: "closed"}}},
			{ID: "ra-mid", Kind: "epic", Source: "epic", Rig: "rig-a", Prefix: "ra",
				Children: []Child{{ID: "ra-sub", Status: "open"}}},
			{ID: "ra-sub", Kind: "epic", Source: "epic", Rig: "rig-a", Prefix: "ra",
				Children: []Child{leaf}},
		}
	}
	cases := []struct {
		name          string
		leaf          Child
		wantStranded  bool
		wantFrontier  string
		wantInFlight  int
		wantOpenHeads []string
	}{
		{"its children wait their turn", Child{ID: "ra-leaf", Status: "open", Metadata: arm, Blockers: []Blocker{sibling}},
			false, "needs-review · 1 queued · nothing idle", 0, []string{}},
		{"one of its children moves", Child{ID: "ra-leaf", Status: "in_progress", Assignee: "polecat-live"},
			false, "needs-review · 1 open · 1 in flight", 1, []string{}},
		{"one of its children is idle", Child{ID: "ra-leaf", Status: "open"},
			true, "needs-review · 1 open · 0 in flight (stranded)", 0, []string{"ra-mid"}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			top := mustTile(t, BuildBoard(family(tc.leaf), fixtureNow, false, nil, live), "ra-top")
			if top.Stranded != tc.wantStranded || top.Frontier != tc.wantFrontier ||
				top.InProgressLive != tc.wantInFlight || !equalIDs(top.OpenHeads, tc.wantOpenHeads) {
				t.Errorf("stranded=%v frontier=%q in_progress_live=%d open_heads=%v, want %v / %q / %d / %v",
					top.Stranded, top.Frontier, top.InProgressLive, top.OpenHeads,
					tc.wantStranded, tc.wantFrontier, tc.wantInFlight, tc.wantOpenHeads)
			}
		})
	}

	// A sub-epic its own bead holds keeps that state: a person parked it.
	anchors := family(Child{ID: "ra-leaf", Status: "open"})
	anchors[0].Children[0].Blockers = []Blocker{{ID: "ra-gate", Title: "parked for the quarter", Status: "open", IssueType: "gate"}}
	top := mustTile(t, BuildBoard(anchors, fixtureNow, false, nil, live), "ra-top")
	if top.Stranded || !equalIDs(top.ParkedHeads, []string{"ra-mid"}) {
		t.Errorf("a parked sub-epic is parked, whatever its children do: stranded=%v parked=%v", top.Stranded, top.ParkedHeads)
	}
}

// TestAncestorWaitHoldsTheFamily: bd keeps a bead out of `bd ready` while it or
// a parent-child ancestor has an open blocker, so the children of a parked epic
// are held by the park, not stranded, and the epic names the gate that holds
// them. Work already in flight under the park keeps running and reads so. An
// epic waiting on open work holds its children the same way, queued behind it.
// A convoy's members hang off it by `tracks`, which bd does not cascade, so a
// convoy's own wait holds none of them.
func TestAncestorWaitHoldsTheFamily(t *testing.T) {
	gate := Blocker{ID: "ra-gate", Title: "parked while steer-by-epic lands", Status: "open", IssueType: "gate"}
	work := Blocker{ID: "ra-w", Title: "the platform build", Status: "open", IssueType: "task"}
	sibling := Blocker{ID: "ra-x", Title: "Platform admin", Status: "open", IssueType: "task"}
	arm := map[string]string{"gc.dispatch_when_ready": "rig-a/gc-toolkit.polecat"}
	live := liveOwners("polecat-live")
	waitsOn := func(a Anchor, b Blocker) Anchor {
		a.Blockers = []Blocker{b}
		a.WaitingOn = []string{b.ID}
		return a
	}
	epic := func(id string, kids ...Child) Anchor {
		return Anchor{ID: id, Kind: "epic", Source: "epic", Rig: "rig-a", Prefix: "ra", Children: kids}
	}

	t.Run("a parked epic holds its children", func(t *testing.T) {
		b := BuildBoard([]Anchor{waitsOn(epic("ra-e",
			Child{ID: "ra-e.1", Status: "open"},
			Child{ID: "ra-e.2", Status: "open", Metadata: arm, Blockers: []Blocker{sibling}},
		), gate)}, fixtureNow, false, nil, live)
		tile := mustTile(t, b, "ra-e")
		if tile.Stranded || tile.Severity == SevHigh || !equalIDs(tile.ParkedHeads, []string{"ra-e.1", "ra-e.2"}) {
			t.Errorf("held children are parked, not stranded: sev=%s stranded=%v parked=%v", tile.Severity, tile.Stranded, tile.ParkedHeads)
		}
		if tile.Frontier != "needs-review · 2 parked for the operator · nothing idle" {
			t.Errorf("frontier = %q", tile.Frontier)
		}
		if tile.Needs != "parked: parked while steer-by-epic lands" {
			t.Errorf("the epic names the gate that holds it: %q", tile.Needs)
		}
	})

	t.Run("work in flight under the park keeps running", func(t *testing.T) {
		b := BuildBoard([]Anchor{waitsOn(epic("ra-e",
			Child{ID: "ra-e.1", Status: "open"},
			Child{ID: "ra-e.3", Status: "in_progress", Assignee: "polecat-live"},
			Child{ID: "ra-e.4", Status: "open", Metadata: map[string]string{"merge_result": "pull_request"}},
		), gate)}, fixtureNow, false, nil, live)
		tile := mustTile(t, b, "ra-e")
		if tile.Frontier != "needs-review · 1 open · 1 in flight · 1 in review · 1 parked for the operator" {
			t.Errorf("frontier = %q", tile.Frontier)
		}
	})

	t.Run("the hold reaches through a nested parent", func(t *testing.T) {
		b := BuildBoard([]Anchor{
			waitsOn(epic("ra-e", Child{ID: "ra-s", Status: "open"}), gate),
			epic("ra-s", Child{ID: "ra-s.1", Status: "open"}),
		}, fixtureNow, false, nil, live)
		top, sub := mustTile(t, b, "ra-e"), mustTile(t, b, "ra-s")
		if !equalIDs(top.ParkedHeads, []string{"ra-s"}) || top.Stranded {
			t.Errorf("the nested parent is held: parked=%v stranded=%v", top.ParkedHeads, top.Stranded)
		}
		if sub.Stranded || !equalIDs(sub.ParkedHeads, []string{"ra-s.1"}) {
			t.Errorf("its own children are held by the park above it: parked=%v stranded=%v", sub.ParkedHeads, sub.Stranded)
		}
		if sub.Needs != "parked: parked while steer-by-epic lands" {
			t.Errorf("the nested parent names the gate that holds it: %q", sub.Needs)
		}
	})

	t.Run("one gate that holds two ancestors is named once", func(t *testing.T) {
		b := BuildBoard([]Anchor{
			waitsOn(epic("ra-e", Child{ID: "ra-s", Status: "open"}), gate),
			waitsOn(epic("ra-s", Child{ID: "ra-s.1", Status: "open"}), gate),
			epic("ra-s.1", Child{ID: "ra-s.1.1", Status: "open"}),
		}, fixtureNow, false, nil, live)
		if leaf := mustTile(t, b, "ra-s.1"); leaf.Needs != "parked: parked while steer-by-epic lands" {
			t.Errorf("needs = %q", leaf.Needs)
		}
	})

	t.Run("two gates above a bead are both counted", func(t *testing.T) {
		older := Blocker{ID: "ra-gate0", Title: "parked for the quarter", Status: "open", IssueType: "gate",
			CreatedAt: fixtureNow.Add(-2 * time.Hour)}
		newer := Blocker{ID: "ra-gate1", Title: "parked while steer-by-epic lands", Status: "open", IssueType: "gate",
			CreatedAt: fixtureNow.Add(-time.Hour)}
		b := BuildBoard([]Anchor{
			waitsOn(epic("ra-e", Child{ID: "ra-s", Status: "open"}), older),
			waitsOn(epic("ra-s", Child{ID: "ra-s.1", Status: "open"}), newer),
			epic("ra-s.1", Child{ID: "ra-s.1.1", Status: "open"}),
		}, fixtureNow, false, nil, live)
		if leaf := mustTile(t, b, "ra-s.1"); leaf.Needs != "parked: parked for the quarter and 1 more" {
			t.Errorf("needs = %q", leaf.Needs)
		}
	})

	t.Run("an epic waiting on a swept gate holds its children queued", func(t *testing.T) {
		timer := Blocker{ID: "ra-tg", Title: "Gate: timer", Status: "open", IssueType: "gate", AwaitType: "timer"}
		b := BuildBoard([]Anchor{waitsOn(epic("ra-e", Child{ID: "ra-e.1", Status: "open"}), timer)},
			fixtureNow, false, nil, live)
		tile := mustTile(t, b, "ra-e")
		if len(tile.ParkedHeads) != 0 || tile.Frontier != "needs-review · 1 queued · nothing idle" || tile.Needs != "queued behind Gate: timer" {
			t.Errorf("parked=%v frontier=%q needs=%q", tile.ParkedHeads, tile.Frontier, tile.Needs)
		}
	})

	t.Run("an epic waiting on work holds its children queued", func(t *testing.T) {
		b := BuildBoard([]Anchor{waitsOn(epic("ra-e",
			Child{ID: "ra-e.1", Status: "open"}, Child{ID: "ra-e.2", Status: "open"},
		), work)}, fixtureNow, false, nil, live)
		tile := mustTile(t, b, "ra-e")
		if tile.Stranded || tile.Frontier != "needs-review · 2 queued · nothing idle" || tile.Needs != "queued behind the platform build" {
			t.Errorf("stranded=%v frontier=%q needs=%q", tile.Stranded, tile.Frontier, tile.Needs)
		}
	})

	t.Run("a convoy's wait does not hold its members", func(t *testing.T) {
		cv := waitsOn(Anchor{ID: "ra-cv", Kind: "convoy", Source: "convoy", Rig: "rig-a", Prefix: "ra",
			Children: []Child{{ID: "ra-m1", Status: "open"}}}, gate)
		tile := mustTile(t, BuildBoard([]Anchor{cv}, fixtureNow, false, nil, live), "ra-cv")
		if !tile.Stranded || !equalIDs(tile.OpenHeads, []string{"ra-m1"}) {
			t.Errorf("a tracked member nothing holds is stranded: stranded=%v open=%v", tile.Stranded, tile.OpenHeads)
		}
	})
}

// TestSweptGateQueuesItsBead: the city's gate sweep closes a timer gate, and a
// gate on a GitHub workflow run or pull request, by itself. A child waiting on
// one waits its turn, so its epic counts it queued and does not ask the
// operator to release it. A gate that awaits a person, a park gate, which names
// no await, and a gate the sweep does not check all wait for someone to close
// them, so a child waiting on one is parked for the operator.
func TestSweptGateQueuesItsBead(t *testing.T) {
	cases := []struct {
		name, await string
		parked      bool
	}{
		{"a timer gate", "timer", false},
		{"a GitHub run gate", "gh:run", false},
		{"a GitHub pull request gate", "gh:pr", false},
		{"a human gate", "human", true},
		{"a park gate", "", true},
		{"a gate the sweep does not check", "mail", true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			gate := Blocker{ID: "ra-g", Title: "the gate", Status: "open", IssueType: "gate", AwaitType: tc.await}
			epic := Anchor{ID: "ra-e", Kind: "epic", Source: "epic", Rig: "rig-a", Prefix: "ra",
				Children: []Child{{ID: "ra-e.1", Status: "open", Blockers: []Blocker{gate}}}}
			tile := mustTile(t, BuildBoard([]Anchor{epic}, fixtureNow, false, nil, Facts{}), "ra-e")
			if tc.parked {
				if !equalIDs(tile.ParkedHeads, []string{"ra-e.1"}) || tile.Section != SectionGate ||
					tile.Needs != "1 parked for the operator — release or rule on them" {
					t.Errorf("a person releases it: parked=%v section=%s needs=%q", tile.ParkedHeads, tile.Section, tile.Needs)
				}
				return
			}
			if len(tile.ParkedHeads) != 0 || tile.Section != SectionActive || tile.Stranded ||
				tile.Frontier != "needs-review · 1 queued · nothing idle" || tile.Needs != "nothing idle — 1 queued" {
				t.Errorf("the sweep releases it: parked=%v section=%s stranded=%v frontier=%q needs=%q",
					tile.ParkedHeads, tile.Section, tile.Stranded, tile.Frontier, tile.Needs)
			}
		})
	}
}

// TestUnderHoldKeepsWhatMovesOrAsks: an ancestor's wait holds a bead that
// nothing else holds or moves, and parks one waiting its turn behind work while
// a person holds the ancestor. Live work, a pull request, a conversation and a
// person's own hold on the bead keep their state, and a bead queued behind its
// own work under a wait on work keeps its own waits.
func TestUnderHoldKeepsWhatMovesOrAsks(t *testing.T) {
	gate := Blocker{ID: "ra-gate", Title: "parked while steer-by-epic lands", Status: "open", IssueType: "gate"}
	work := Blocker{ID: "ra-w", Title: "the platform build", Status: "open", IssueType: "task"}
	own := Blocker{ID: "ra-x", Title: "Platform admin", Status: "open", IssueType: "task"}
	parked := hold{kind: stateParked, waits: []Blocker{gate}}
	queued := hold{kind: stateQueued, waits: []Blocker{work}}
	cases := []struct {
		name      string
		s         beadState
		h         hold
		want      string
		wait      string
		inherited bool
	}{
		{"nothing holds it", beadState{kind: stateStranded}, hold{}, stateStranded, "", false},
		{"stranded under a park", beadState{kind: stateStranded}, parked, stateParked, "ra-gate", true},
		{"stranded under a wait on work", beadState{kind: stateStranded}, queued, stateQueued, "ra-w", true},
		{"queued under a park", beadState{kind: stateQueued, waits: []Blocker{own}}, parked, stateParked, "ra-gate", true},
		{"queued under a wait on work", beadState{kind: stateQueued, waits: []Blocker{own}}, queued, stateQueued, "ra-x", false},
		{"parked by its own gate", beadState{kind: stateParked, waits: []Blocker{own}}, queued, stateParked, "ra-x", false},
		{"in flight", beadState{kind: stateInFlight}, parked, stateInFlight, "", false},
		{"in review", beadState{kind: stateInReview}, parked, stateInReview, "", false},
		{"in conversation", beadState{kind: stateInConversation}, parked, stateInConversation, "", false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := underHold(tc.s, tc.h)
			wait := ""
			if len(got.waits) > 0 {
				wait = got.waits[0].ID
			}
			if got.kind != tc.want || wait != tc.wait || got.inherited != tc.inherited {
				t.Errorf("state=%q wait=%q inherited=%v, want %q / %q / %v", got.kind, wait, got.inherited, tc.want, tc.wait, tc.inherited)
			}
		})
	}
}

// TestAncestorWaitHoldsARowOfItsOwn: a bead under a held epic that has a row of
// its own reads the hold on that row too, so the row and its parent's roll-up
// give one answer. A takeaway subject whose own waits have landed, under an
// epic parked at a gate, is parked and names that gate. It owes no
// disposition, because the park still holds it. Under an epic waiting on work
// it is queued behind that work. A subject in review keeps its own state.
func TestAncestorWaitHoldsARowOfItsOwn(t *testing.T) {
	gate := Blocker{ID: "ra-gate", Title: "parked while steer-by-epic lands", Status: "open", IssueType: "gate"}
	work := Blocker{ID: "ra-w", Title: "the platform build", Status: "open", IssueType: "task"}
	landed := Blocker{ID: "ra-done", Title: "the routed fix", Status: "closed", IssueType: "task"}
	family := func(epicWait Blocker, md map[string]string) []Anchor {
		full := map[string]string{"gc.takeaway": "routed the fix; nothing further here"}
		for k, v := range md {
			full[k] = v
		}
		return []Anchor{
			{ID: "ra-e", Kind: "epic", Source: "epic", Rig: "rig-a", Prefix: "ra",
				Children:  []Child{{ID: "ra-s", Status: "open", Metadata: full, Blockers: []Blocker{landed}}},
				WaitingOn: []string{epicWait.ID}, Blockers: []Blocker{epicWait}},
			{ID: "ra-s", Title: "the subject", Kind: "parked", Source: "parked", Rig: "rig-a", Prefix: "ra",
				Priority: ptr(2), UpdatedAt: daysAgo(1), Metadata: full, Takeaway: full["gc.takeaway"],
				WaitingOn: []string{landed.ID}, WaitingOnClosed: []string{landed.ID}, Blockers: []Blocker{landed}},
		}
	}

	t.Run("under a parked epic", func(t *testing.T) {
		b := BuildBoard(family(gate, nil), fixtureNow, false, nil, Facts{})
		row, epic := mustTile(t, b, "ra-s"), mustTile(t, b, "ra-e")
		if !equalIDs(epic.ParkedHeads, []string{"ra-s"}) {
			t.Errorf("the epic counts its subject parked: %v", epic.ParkedHeads)
		}
		if row.DispositionDue || row.Owed || row.Section == SectionGate {
			t.Errorf("the park still holds it, so no disposition is owed: disposition_due=%v owed=%v section=%s",
				row.DispositionDue, row.Owed, row.Section)
		}
		if row.Frontier != "needs-review · parked · held by an ancestor's wait" || row.Needs != "parked: parked while steer-by-epic lands" {
			t.Errorf("the row names the hold: frontier=%q needs=%q", row.Frontier, row.Needs)
		}
	})

	t.Run("under an epic waiting on work", func(t *testing.T) {
		row := mustTile(t, BuildBoard(family(work, nil), fixtureNow, false, nil, Facts{}), "ra-s")
		if row.DispositionDue || row.Owed {
			t.Errorf("disposition_due=%v owed=%v", row.DispositionDue, row.Owed)
		}
		if row.Frontier != "needs-review · queued · held by an ancestor's wait" || row.Needs != "queued behind the platform build" {
			t.Errorf("frontier=%q needs=%q", row.Frontier, row.Needs)
		}
	})

	t.Run("in review under a parked epic", func(t *testing.T) {
		md := map[string]string{"merge_result": "pull_request", "pr_number": "62", "branch": "polecat/ra-s"}
		row := mustTile(t, BuildBoard(family(gate, md), fixtureNow, false, nil, Facts{}), "ra-s")
		if row.DispositionDue || row.Section != SectionReview {
			t.Errorf("a pull request in review keeps its state: disposition_due=%v section=%s", row.DispositionDue, row.Section)
		}
	})

	t.Run("once the epic's wait lands", func(t *testing.T) {
		closedGate := gate
		closedGate.Status = "closed"
		anchors := family(closedGate, nil)
		anchors[0].WaitingOnClosed = []string{closedGate.ID}
		row := mustTile(t, BuildBoard(anchors, fixtureNow, false, nil, Facts{}), "ra-s")
		if !row.DispositionDue || row.Needs != "blocker landed — dispose or resume" {
			t.Errorf("nothing holds it any more, so the disposition is due: disposition_due=%v needs=%q", row.DispositionDue, row.Needs)
		}
	})
}

// TestInReviewBeadIsNotADisposition: a bead carrying a takeaway, every
// recorded wait closed, an open pull request and a sitting in progress is a
// pull request in review. Its closed waits are its finished review rounds, not
// a park that ended, so it owes no disposition. The gather admits it twice, as
// a merge anchor and by its takeaway, and the two rows read alike.
func TestInReviewBeadIsNotADisposition(t *testing.T) {
	md := map[string]string{
		"merge_result": "pull_request", "pr_number": "62", "branch": "polecat/ra-pr",
		"gc.takeaway": "Ruled: previews get an admin login. PR #62 is in rework so the demo can capture",
	}
	twin := func(kind string) Anchor {
		return Anchor{ID: "ra-pr", Title: "Platform admin", Kind: kind, Source: kind, Rig: "rig-a", Prefix: "ra",
			Priority: ptr(1), UpdatedAt: daysAgo(1), Metadata: md, Takeaway: md["gc.takeaway"],
			WaitingOn: []string{"ra-r1", "ra-r2"}, WaitingOnClosed: []string{"ra-r1", "ra-r2"},
			Blockers: []Blocker{
				{ID: "ra-r1", Title: "Review PR #62", Status: "closed", IssueType: "task", RoutedTo: "rig-a/gc-toolkit.polecat"},
				{ID: "ra-r2", Title: "Rework PR #62", Status: "closed", IssueType: "task", RoutedTo: "rig-a/gc-toolkit.polecat"},
			}}
	}
	facts := Facts{
		Sittings: []Sitting{{ID: "ra-visit", Subject: "ra-pr", Subjects: []string{"ra-pr"},
			Title: "visit: ra-pr — settle the rework", Status: sittingInProgress, Session: "converse-1"}},
		Visits: map[string]bool{"ra-pr": true},
	}

	for _, order := range [][]string{{"merge", "parked"}, {"parked", "merge"}} {
		t.Run(strings.Join(order, " then "), func(t *testing.T) {
			b := BuildBoard([]Anchor{twin(order[0]), twin(order[1])}, fixtureNow, false, nil, facts)
			if len(b.Tiles) != 1 {
				t.Fatalf("the twins are one bead: %d tiles", len(b.Tiles))
			}
			tile := b.Tiles[0]
			if tile.Kind != order[0] {
				t.Errorf("the twins tie, so the row the gather admits first stands: kind=%s", tile.Kind)
			}
			if tile.DispositionDue || tile.Needs == "blocker landed — dispose or resume" {
				t.Errorf("a pull request in review owes no disposition: disposition_due=%v needs=%q", tile.DispositionDue, tile.Needs)
			}
			if tile.Section != SectionReview {
				t.Errorf("it reads in review: section=%s", tile.Section)
			}
			if tile.Frontier != "needs-attention · PR #62" {
				t.Errorf("the frontier names the pull request, not a park: %q", tile.Frontier)
			}
			if tile.Needs != md["gc.takeaway"] {
				t.Errorf("a merge anchor spends its takeaway as NEEDS: %q", tile.Needs)
			}
			if tile.Owed {
				t.Error("nothing on the pull request is owed, and no disposition is")
			}
			if tile.VisitState != VisitEngaged {
				t.Errorf("the sitting in progress still shows: visit_state=%q", tile.VisitState)
			}
		})
	}
}

// TestTakeawayRowSpeaksItsState: a childless takeaway row says what its graph
// says it waits on, ahead of the takeaway, which stays on the wire. It names
// the wait it is queued or parked behind, and says when it starts by itself.
// Once every recorded wait has landed, it reads its live state, and a
// disposition only when nothing holds or moves it.
func TestTakeawayRowSpeaksItsState(t *testing.T) {
	work := Blocker{ID: "ra-1", Title: "Platform admin", Status: "open", IssueType: "task"}
	gate := Blocker{ID: "ra-gate", Title: "parked until the design is signed", Status: "open", IssueType: "gate"}
	landed := Blocker{ID: "ra-done", Title: "the routed fix", Status: "closed", IssueType: "task"}
	row := func(id string, md map[string]string, blockers ...Blocker) Anchor {
		full := map[string]string{"gc.takeaway": "the sitting's conclusion"}
		for k, v := range md {
			full[k] = v
		}
		a := Anchor{ID: id, Title: "t " + id, Kind: "parked", Source: "parked", Rig: "rig-a", Prefix: "ra",
			Priority: ptr(2), UpdatedAt: daysAgo(1), Metadata: full, Takeaway: full["gc.takeaway"], Blockers: blockers}
		for _, b := range blockers {
			a.WaitingOn = append(a.WaitingOn, b.ID)
			if b.Status == "closed" {
				a.WaitingOnClosed = append(a.WaitingOnClosed, b.ID)
			}
		}
		return a
	}
	arm := map[string]string{"gc.dispatch_when_ready": "rig-a/gc-toolkit.polecat"}
	anchors := []Anchor{
		row("ra-queued", arm, landed, work),
		row("ra-queued-bare", nil, work),
		row("ra-parked", arm, gate, work),
		row("ra-talk", nil, landed),
		row("ra-asked", nil, landed),
		row("ra-armed", arm, landed),
		row("ra-done", nil, landed),
	}
	facts := Facts{
		Sittings: []Sitting{
			{ID: "ra-visit", Subject: "ra-talk", Subjects: []string{"ra-talk"},
				Title: "visit: ra-talk — what next", Status: sittingInProgress, Session: "converse-1"},
			{ID: "ra-visit2", Subject: "ra-asked", Subjects: []string{"ra-asked"},
				Title: "visit: ra-asked — close it or say why not", Status: sittingOpen},
		},
		Visits: map[string]bool{"ra-talk": true, "ra-asked": true},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, facts)

	cases := []struct {
		id, frontier, needs string
		dispositionDue      bool
	}{
		{"ra-queued", "needs-review · queued · waiting on 1 · starts by itself",
			"queued behind Platform admin — starts by itself when it lands", false},
		{"ra-queued-bare", "needs-review · queued · waiting on 1", "queued behind Platform admin", false},
		{"ra-parked", "needs-review · parked · waiting on 2", "parked: parked until the design is signed", false},
		{"ra-talk", "needs-attention · in conversation", "held by an open visit: what next", false},
		{"ra-asked", "needs-attention · held by an open visit", "held by an open visit: close it or say why not", false},
		{"ra-armed", "needs-review · queued · starts by itself", "queued — starts by itself", false},
		{"ra-done", "needs-review · blocker landed", "blocker landed — dispose or resume", true},
	}
	for _, tc := range cases {
		tile := mustTile(t, b, tc.id)
		if tile.Frontier != tc.frontier || tile.Needs != tc.needs || tile.DispositionDue != tc.dispositionDue {
			t.Errorf("%s: frontier=%q needs=%q disposition_due=%v, want %q / %q / %v",
				tc.id, tile.Frontier, tile.Needs, tile.DispositionDue, tc.frontier, tc.needs, tc.dispositionDue)
		}
		if tile.Takeaway == nil || *tile.Takeaway != "the sitting's conclusion" {
			t.Errorf("%s: the takeaway stays on the wire: %v", tc.id, tile.Takeaway)
		}
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
			wantSev: SevHigh, frontier: "needs-review · 2 open · 0 in flight (stranded)", needs: "decomposed, idle — assign or visit",
		},
		{
			name: "in flight",
			anchor: Anchor{ID: "tk-f", Kind: "epic", Source: "epic", Children: []Child{
				{ID: "tk-f1", Status: "in_progress", Assignee: "polecat-live"},
			}},
			facts:   liveOwners("polecat-live"),
			wantSev: SevNormal, frontier: "needs-review · 1 open · 1 in flight", needs: "in flight",
		},
		{
			name: "dead owner",
			anchor: Anchor{ID: "tk-d", Kind: "epic", Source: "epic", Children: []Child{
				{ID: "tk-d1", Status: "in_progress", Assignee: "polecat-gone"},
			}},
			wantSev: SevHigh, frontier: "needs-review · 1 open · 1 stuck (dead owner)", needs: "dead owner — recover or reassign",
		},
		{
			name: "all closed",
			anchor: Anchor{ID: "tk-c", Kind: "epic", Source: "epic", Children: []Child{
				{ID: "tk-c1", Status: "closed"},
			}},
			wantSev: SevLow, frontier: "needs-review · all 1 closed · 0 open", needs: "all 1 closed — close or extend",
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

// TestDeriveStateReadsTheGraphNotTheMarkers covers each state a bead can be in,
// read off its own waits, route, arm and live work. A takeaway, blank or not,
// decides nothing: the state is what holds the bead, not what was said about it.
func TestDeriveStateReadsTheGraphNotTheMarkers(t *testing.T) {
	work := Blocker{ID: "ra-work", Title: "the sibling it waits behind", Status: "open", IssueType: "task"}
	gate := Blocker{ID: "ra-gate", Title: "parked until the design is signed", Status: "open", IssueType: "gate"}
	humanGate := Blocker{ID: "ra-hg", Title: "sign off the design", Status: "open", IssueType: "gate", AwaitType: "human"}
	timerGate := Blocker{ID: "ra-tg", Title: "Gate: timer", Status: "open", IssueType: "gate", AwaitType: "timer"}
	runGate := Blocker{ID: "ra-rg", Title: "Gate: gh:run release.yml", Status: "open", IssueType: "gate", AwaitType: "gh:run"}
	prGate := Blocker{ID: "ra-pg", Title: "Gate: gh:pr 42", Status: "open", IssueType: "gate", AwaitType: "gh:pr"}
	mailGate := Blocker{ID: "ra-mg", Title: "Gate: mail", Status: "open", IssueType: "gate", AwaitType: "mail"}
	decision := Blocker{ID: "ra-dec", Title: "pick a vendor", Status: "open", IssueType: "decision"}
	visitWait := Blocker{ID: "ra-visit", Title: "visit: rule on it", Status: "open", IssueType: "task", RoutedTo: routedHuman}
	landed := Blocker{ID: "ra-done", Title: "landed work", Status: "closed", IssueType: "task"}
	live := liveOwners("polecat-live")
	live.Inflight = map[string][]string{"ra-slung": {"polecat-live"}}
	sittings := Facts{
		Sittings: []Sitting{
			{ID: "ra-v1", Subject: "ra-talk", Subjects: []string{"ra-talk"}, Status: sittingInProgress, Session: "converse-1"},
			{ID: "ra-v2", Subject: "ra-asked", Subjects: []string{"ra-asked"}, Status: sittingOpen},
			{ID: "ra-v3", Subject: "ra-pr-talk", Subjects: []string{"ra-pr-talk"}, Status: sittingInProgress, Session: "converse-2"},
		},
		Visits: map[string]bool{"ra-talk": true, "ra-asked": true, "ra-pr-talk": true},
	}
	cases := []struct {
		name      string
		in        stateInput
		facts     Facts
		want      string
		selfStart bool
	}{
		{name: "nothing holds it", in: stateInput{id: "ra-a"}, want: stateStranded},
		{name: "a takeaway alone", in: stateInput{id: "ra-a", metadata: map[string]string{mdTakeaway: "ruling owed"}}, want: stateStranded},
		{name: "a blanked takeaway", in: stateInput{id: "ra-a", metadata: map[string]string{mdTakeaway: ""}}, want: stateStranded},
		{name: "only landed waits", in: stateInput{id: "ra-a", blockers: []Blocker{landed}}, want: stateStranded},
		{name: "waits on open work", in: stateInput{id: "ra-a", blockers: []Blocker{landed, work}}, want: stateQueued},
		{name: "waits on open work, armed", in: stateInput{id: "ra-a", blockers: []Blocker{work},
			metadata: map[string]string{mdDispatchWhenReady: "rig-a/gc-toolkit.polecat"}}, want: stateQueued, selfStart: true},
		{name: "an unread wait", in: stateInput{id: "ra-a", unread: 1}, want: stateQueued},
		{name: "routed to a pool", in: stateInput{id: "ra-a", metadata: map[string]string{mdRoutedTo: "rig-a/gc-toolkit.polecat"}},
			want: stateQueued, selfStart: true},
		{name: "armed with nothing open", in: stateInput{id: "ra-a", metadata: map[string]string{mdDispatchWhenReady: "rig-a/gc-toolkit.polecat"}},
			want: stateQueued, selfStart: true},
		{name: "assigned and not started", in: stateInput{id: "ra-a", status: "open", assignee: "rig-a/gc-toolkit.refinery"},
			want: stateQueued, selfStart: true},
		{name: "waits on a park gate", in: stateInput{id: "ra-a", blockers: []Blocker{gate}}, want: stateParked},
		{name: "waits on a human gate", in: stateInput{id: "ra-a", blockers: []Blocker{humanGate}}, want: stateParked},
		{name: "waits on a timer gate", in: stateInput{id: "ra-a", blockers: []Blocker{timerGate}}, want: stateQueued},
		{name: "waits on a GitHub run gate", in: stateInput{id: "ra-a", blockers: []Blocker{runGate}}, want: stateQueued},
		{name: "waits on a GitHub pull request gate", in: stateInput{id: "ra-a", blockers: []Blocker{prGate}}, want: stateQueued},
		{name: "waits on a gate the sweep does not check", in: stateInput{id: "ra-a", blockers: []Blocker{mailGate}}, want: stateParked},
		{name: "a person's gate outranks a swept one", in: stateInput{id: "ra-a", blockers: []Blocker{timerGate, gate}}, want: stateParked},
		{name: "waits on a decision", in: stateInput{id: "ra-a", blockers: []Blocker{decision}}, want: stateParked},
		{name: "waits on a visit", in: stateInput{id: "ra-a", blockers: []Blocker{visitWait}}, want: stateParked},
		{name: "a gate outranks open work", in: stateInput{id: "ra-a", blockers: []Blocker{work, gate},
			metadata: map[string]string{mdDispatchWhenReady: "rig-a/gc-toolkit.polecat"}}, want: stateParked},
		{name: "routed to the operator", in: stateInput{id: "ra-a", metadata: map[string]string{mdRoutedTo: routedHuman}}, want: stateParked},
		{name: "a visit no one has engaged", in: stateInput{id: "ra-asked"}, facts: sittings, want: stateParked},
		{name: "a live sitting", in: stateInput{id: "ra-talk", blockers: []Blocker{work}}, facts: sittings, want: stateInConversation},
		{name: "an open pull request", in: stateInput{id: "ra-pr", metadata: map[string]string{mdMergeResult: "pull_request"},
			blockers: []Blocker{landed}}, want: stateInReview},
		{name: "a pre-open gate", in: stateInput{id: "ra-pr", metadata: map[string]string{mdMergeResult: "pre_open_gate"}}, want: stateInReview},
		{name: "a pull request outranks its conversation", in: stateInput{id: "ra-pr-talk",
			metadata: map[string]string{mdMergeResult: "pull_request", mdTakeaway: "in rework"}, blockers: []Blocker{landed}},
			facts: sittings, want: stateInReview},
		{name: "a merge held for the operator is not in review", in: stateInput{id: "ra-held",
			metadata: map[string]string{mdMergeResult: "held", mdRoutedTo: routedHuman}}, want: stateParked},
		{name: "a live workflow", in: stateInput{id: "ra-slung", blockers: []Blocker{gate}}, facts: live, want: stateInFlight},
		{name: "a live claim", in: stateInput{id: "ra-a", status: "in_progress", assignee: "polecat-live"}, facts: live, want: stateInFlight},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := deriveState(tc.in, tc.facts)
			if got.kind != tc.want || got.selfStart != tc.selfStart {
				t.Errorf("state = %q (starts by itself %v), want %q (%v)", got.kind, got.selfStart, tc.want, tc.selfStart)
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
	if tile.Frontier != "needs-review · routed to the operator — no agent will take it" {
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
	if tile.Frontier != "needs-review · 1 open · 0 in flight (stranded)" {
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

// TestCapQueueKeepsEveryOwedRow: the operator's queue stays FLAT and owed-first,
// so CapQueue is a straight head-truncation — every owed row up to the limit,
// parked ones included. A parked row here is a conversation waiting on the
// operator that earned its place by age, not a straggler to ration.
func TestCapQueueKeepsEveryOwedRow(t *testing.T) {
	var tiles []Tile
	for i := 0; i < 20; i++ {
		tiles = append(tiles, Tile{ID: fmt.Sprintf("tk-p%02d", i), Kind: "parked", Owed: true})
	}
	if got := len(CapQueue(tiles, DefaultMaxRows)); got != len(tiles) {
		t.Errorf("CapQueue kept %d of %d parked rows", got, len(tiles))
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
			if parked.Frontier != "needs-review · conversation parked — no takeaway recorded" {
				t.Errorf("the frontier agrees with it: %q", parked.Frontier)
			}

			spoken, ok := tileByID(b, "tk-spoken")
			if !ok {
				t.Fatal("the control tile is missing")
			}
			if spoken.Needs != "ship it or say why not" {
				t.Errorf("a recorded takeaway is still the NEEDS answer: %q", spoken.Needs)
			}
			if spoken.Frontier != "needs-review · conversation parked — takeaway recorded" {
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
	tile := computeTile(a, fixtureNow, Facts{}, 0)

	if tile.Severity != SevDone {
		t.Errorf("a closed anchor bands DONE: got %s", tile.Severity)
	}
	if tile.Frontier != "closed 1d ago" {
		t.Errorf("frontier says when it closed: got %q", tile.Frontier)
	}
	if tile.Needs != "closed — ages out" {
		t.Errorf("needs says a closed row leaves on its own: got %q", tile.Needs)
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

	tile := computeTile(a, fixtureNow, Facts{}, 0)
	if tile.Needs != "closed — ages out" {
		t.Errorf("a closed row ages out on its own, it is not re-read: got %q", tile.Needs)
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

// CapFamilies never splits a family — a member is never shown without the root
// that heads it — and rations the closed-anchor (DONE) families on a budget of
// their own so a week of closures cannot crowd out the live board.
func TestCapFamiliesKeepsFamiliesWhole(t *testing.T) {
	tiles := []Tile{
		{ID: "a", Kind: "epic", Severity: SevHigh, Section: SectionStalled, GroupRoot: "a"},
		{ID: "a2", Kind: "human", Severity: SevElevated, Section: SectionGate, GroupRoot: "a"},
		{ID: "b", Kind: "epic", Severity: SevNormal, Section: SectionActive, GroupRoot: "b"},
		{ID: "b2", Kind: "human", Severity: SevElevated, Section: SectionGate, GroupRoot: "b"},
		{ID: "d0", Kind: "parked", Severity: SevDone, Section: SectionDone, GroupRoot: "d0"},
		{ID: "d1", Kind: "parked", Severity: SevDone, Section: SectionDone, GroupRoot: "d1"},
		{ID: "d2", Kind: "parked", Severity: SevDone, Section: SectionDone, GroupRoot: "d2"},
	}

	// A live-row budget of 2 admits family a (2 rows) whole; family b would push
	// past it, so b is dropped WHOLE, never half-shown. A done budget of 2 keeps
	// two closed families and rations the third.
	got := ids(CapFamilies(tiles, 2, 2))
	want := []string{"a", "a2", "d0", "d1"}
	if !equalIDs(got, want) {
		t.Errorf("family-whole cap: got %v, want %v (b dropped whole, d2 rationed)", got, want)
	}
	if got := len(CapFamilies(tiles, 0, 1)); got != len(tiles) {
		t.Errorf("limit<=0 stays uncapped: got %d of %d", got, len(tiles))
	}
}

// --- the PR round-trip (specs/tk-q0ml23) --------------------------------------
//
// Every case below is built from a shape the design measured on a live city,
// because the failure this surface exists to prevent is a board that reports a
// wedged pull request as nobody's problem, and only the real shapes prove it
// does not.

const (
	// A 40-hex oid, the shape the dated keys carry.
	headLive = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	headOld  = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
)

// dated builds the <value>@<oid>@<since> shape lifecycle.sh writes.
func dated(value, oid string, at time.Time) string {
	return value + "@" + oid + "@" + at.Format(time.RFC3339)
}

// prPhase names whose move a PR is in the same values and precedence as
// pr-status-label.sh's derive_value; these cases mirror that script's, since it
// stamps nothing on the bead for the board to read instead.
func TestPRPhaseMirrorsDeriveValue(t *testing.T) {
	merge := func(md map[string]string) Anchor {
		full := map[string]string{mdMergeResult: "pull_request"}
		for k, v := range md {
			full[k] = v
		}
		return Anchor{ID: "tk-x", Metadata: full}
	}
	cases := []struct {
		name string
		a    Anchor
		kids int
		want string
	}{
		{"non-merge row has no phase", Anchor{Metadata: map[string]string{}}, 0, ""},
		{"operator freeze needs attention", merge(map[string]string{mdMergeHold: "true"}), 0, PhaseNeedsAttention},
		{"rebase hold needs attention", merge(map[string]string{mdRebaseHold: "true"}), 0, PhaseNeedsAttention},
		{"approved and blocked by the merge pass with no rework needs attention", merge(map[string]string{mdPRPosture: "approved@abc@2026-01-01T00:00:00Z", mdPRMachine: "blocked@abc@2026-01-01T00:00:00Z", mdPRMachineCause: "check-failed"}), 0, PhaseNeedsAttention},
		{"approved and blocked but reworking is merging", merge(map[string]string{mdPRPosture: "approved@abc", mdPRMachine: "blocked@abc@2026-01-01T00:00:00Z", mdPRMachineCause: "check-failed"}), 1, PhaseMerging},
		{"approved and held on the blocker cause needs attention whatever is in flight", merge(map[string]string{mdPRPosture: "approved@abc", mdPRMachine: "blocked@abc@2026-01-01T00:00:00Z", mdPRMachineCause: "blocker"}), 1, PhaseNeedsAttention},
		{"approved while GitHub reports BLOCKED for a check still running is merging", merge(map[string]string{mdPRPosture: "approved@abc", "pr_merge_state": "BLOCKED@abc", mdPRMachine: "progressing@abc@2026-01-01T00:00:00Z"}), 0, PhaseMerging},
		{"open rework child is working", merge(map[string]string{mdPRPosture: "review_required@abc"}), 2, PhaseWorking},
		{"approved and mergeable is merging", merge(map[string]string{mdPRPosture: "approved@abc", mdPRMachine: "settled@abc@2026-01-01T00:00:00Z"}), 0, PhaseMerging},
		{"settled awaiting review needs review", merge(map[string]string{mdPRPosture: "review_required@abc"}), 0, PhaseNeedsReview},
		{"falsy holds do not count", merge(map[string]string{mdMergeHold: "false", mdRebaseHold: "0", mdPRPosture: "commented@abc"}), 0, PhaseNeedsReview},
		{"a draft the city opened is working until readied", merge(map[string]string{mdOpenedAsDraft: "abc"}), 0, PhaseWorking},
		{"a readied draft with nothing in flight needs review", merge(map[string]string{mdOpenedAsDraft: "abc", mdDraftReadied: "abc"}), 0, PhaseNeedsReview},
		{"a held draft needs attention", merge(map[string]string{mdOpenedAsDraft: "abc", mdMergeHold: "true"}), 0, PhaseNeedsAttention},
	}
	for _, tc := range cases {
		if got := prPhase(tc.a, Facts{}, tc.kids); got != tc.want {
			t.Errorf("%s: prPhase = %q, want %q", tc.name, got, tc.want)
		}
	}
}

// The open-rework count comes from the children the board gathers — each names
// its anchor in anchor_bead — so an anchor with one is working even with nothing
// else recorded.
func TestPRPhaseCountsOpenReworkChildFromBoard(t *testing.T) {
	anchor := mergeAnchor("tk-anc", map[string]string{mdPRPosture: "review_required@abc"})
	kid := Anchor{ID: "tk-anc.rw", Source: kindRework, Rig: "gc-toolkit", Metadata: map[string]string{mdAnchorBead: "tk-anc"}}

	b := BuildBoard([]Anchor{anchor, kid}, fixtureNow, false, nil, Facts{})
	if got := mustTile(t, b, "tk-anc").PRPhase; got != PhaseWorking {
		t.Errorf("an anchor with an open rework child is working: got %q", got)
	}
}

// A draft the city opened is not yet up for review, so the PR chip (PRPhase) and
// the row's own liveness (Phase) both read working until pr-open.sh records
// draft_readied. Its readied twin, with nothing in flight, is the settled row a
// human reviews.
func TestDraftStageReadsWorkingOnBothAxes(t *testing.T) {
	draft := mergeAnchor("tk-draft", map[string]string{mdOpenedAsDraft: "abc"})
	readied := mergeAnchor("tk-ready", map[string]string{mdOpenedAsDraft: "abc", mdDraftReadied: "abc"})

	b := BuildBoard([]Anchor{draft, readied}, fixtureNow, false, nil, Facts{})
	for _, tc := range []struct{ id, want string }{
		{"tk-draft", PhaseWorking},
		{"tk-ready", PhaseNeedsReview},
	} {
		tile := mustTile(t, b, tc.id)
		if tile.PRPhase != tc.want || tile.Phase != tc.want {
			t.Errorf("%s: PRPhase=%q Phase=%q, want both %q", tc.id, tile.PRPhase, tile.Phase, tc.want)
		}
	}
}

// An open visit on a merge anchor is a hold: the merge pass's finalize gate holds
// the PR until the visit closes. So an approved, settled PR, which reads merging
// with the merge pass next, reads needs-attention on both axes while a visit
// names it, and its needs line stops naming the merge pass. The visit fact is the
// one the held marker reads, so a visit a sitting is holding, which no wrapper
// row folds onto the anchor, holds it too. The unheld twin proves the visit is
// what moves the row.
func TestOpenVisitHoldsAMergeAnchorAtNeedsAttention(t *testing.T) {
	md := map[string]string{
		mdPRPosture: dated(postureApproved, headLive, fixtureNow.Add(-2*time.Hour)),
		mdPRMachine: dated(MachineSettled, headLive, fixtureNow.Add(-2*time.Hour)),
		mdPRNumber:  "1162",
	}
	held := mergeAnchor("tk-held", md)
	free := mergeAnchor("tk-free", md)

	b := BuildBoard([]Anchor{held, free}, fixtureNow, false, nil, Facts{Visits: map[string]bool{"tk-held": true}})

	fr := mustTile(t, b, "tk-free")
	if fr.PRPhase != PhaseMerging || fr.Phase != PhaseMerging || fr.Needs != "green — waiting on the merge pass" {
		t.Fatalf("test premise: the unheld twin is merging with the merge pass next; got pr_phase=%q phase=%q needs=%q", fr.PRPhase, fr.Phase, fr.Needs)
	}

	h := mustTile(t, b, "tk-held")
	if !h.Held {
		t.Fatalf("test premise: the visit fact holds the row; held=%v", h.Held)
	}
	if h.PRPhase != PhaseNeedsAttention || h.Phase != PhaseNeedsAttention {
		t.Errorf("a PR an open visit holds needs attention on both axes: pr_phase=%q phase=%q", h.PRPhase, h.Phase)
	}
	if h.Frontier != "needs-attention · PR #1162" {
		t.Errorf("the frontier leads with needs-attention, not working: got %q", h.Frontier)
	}
	if h.Needs != "held by an open visit" {
		t.Errorf("the needs line names the visit hold, not the merge pass: got %q", h.Needs)
	}
}

// A held merge anchor's needs line says an open visit holds it at every position
// the cadence records. The phase reads needs-attention whether the row is
// settled, progressing or waiting on an approval, and the needs line agrees
// instead of naming the merge pass, the cadence or a review. The unheld twin of
// each position proves the visit is what moves the line.
func TestHeldMergeAnchorNeedsNamesTheVisitAtEveryPosition(t *testing.T) {
	at := fixtureNow.Add(-2 * time.Hour)
	for _, pos := range []struct {
		name, posture, machine, unheld string
	}{
		{"settled and approved", postureApproved, MachineSettled, "green — waiting on the merge pass"},
		{"settled, waiting on a review", postureReviewRequired, MachineSettled, "green, waiting on your review"},
		{"settled, changes requested", postureChangesRequested, MachineSettled, "changes requested — reviewer re-review needed"},
		{"progressing", postureApproved, MachineProgressing, "in the merge cadence"},
	} {
		t.Run(pos.name, func(t *testing.T) {
			md := map[string]string{
				mdPRPosture: dated(pos.posture, headLive, at),
				mdPRMachine: dated(pos.machine, headLive, at),
				mdPRNumber:  "1162",
			}
			b := BuildBoard([]Anchor{mergeAnchor("tk-held", md), mergeAnchor("tk-free", md)}, fixtureNow, false, nil,
				Facts{Visits: map[string]bool{"tk-held": true}})
			if fr := mustTile(t, b, "tk-free"); fr.Needs != pos.unheld {
				t.Fatalf("test premise: the unheld twin reads %q; got %q", pos.unheld, fr.Needs)
			}
			h := mustTile(t, b, "tk-held")
			if h.Phase != PhaseNeedsAttention || h.Needs != "held by an open visit" {
				t.Errorf("a held row reads needs-attention and says the visit holds it: phase=%q needs=%q", h.Phase, h.Needs)
			}
		})
	}
}

// The needs line names each visit that holds the row by the question its title
// asks, from the row's own sittings. It never asserts who owes the answer, so a
// visit a sitting is in reads the same as one waiting for a person.
func TestHeldNeedsNamesEachHoldingVisitByItsQuestion(t *testing.T) {
	md := map[string]string{
		mdPRPosture: dated(postureApproved, headLive, fixtureNow.Add(-2*time.Hour)),
		mdPRMachine: dated(MachineSettled, headLive, fixtureNow.Add(-2*time.Hour)),
		mdPRNumber:  "1162",
	}
	visit := func(id, ask, status, session string) Sitting {
		return Sitting{ID: id, Title: "visit: tk-held — " + ask, Subject: "tk-held", Subjects: []string{"tk-held"},
			Status: status, Session: session}
	}
	moot := "is this PR moot now that main rewrote the code it edits?"
	merge := "may the seed audit merge?"
	for _, tc := range []struct {
		name     string
		sittings []Sitting
		want     string
	}{
		{"one visit waiting for a person", []Sitting{visit("tk-v1", moot, "open", "")},
			"held by an open visit: " + moot},
		{"one visit a sitting is in", []Sitting{visit("tk-v1", moot, "in_progress", "converse-1")},
			"held by an open visit: " + moot},
		{"two visits", []Sitting{visit("tk-v1", moot, "open", ""), visit("tk-v2", merge, "open", "")},
			"held by 2 open visits: " + moot + " · " + merge},
		{"a closed sitting names nothing", []Sitting{visit("tk-v1", moot, "open", ""), visit("tk-v0", merge, "closed", "")},
			"held by an open visit: " + moot},
	} {
		t.Run(tc.name, func(t *testing.T) {
			b := BuildBoard([]Anchor{mergeAnchor("tk-held", md)}, fixtureNow, false, nil,
				Facts{Visits: map[string]bool{"tk-held": true}, Sittings: tc.sittings})
			if h := mustTile(t, b, "tk-held"); h.Needs != tc.want {
				t.Errorf("needs = %q, want %q", h.Needs, tc.want)
			}
		})
	}
}

// A pre-PR branch links to its GitHub tree view, and the repository comes from
// a sibling row's pull request URL rather than a GitHub call: every anchor in
// one rig targets that rig's repository. This is the gap the branch link
// closes — the branch a person wants to browse before a PR exists.
func TestPRBranchLinksToGitHubViaSiblingPRURL(t *testing.T) {
	opened := mergeAnchor("tk-open", map[string]string{
		"pr_number": "42",
		"pr_url":    "https://github.com/zookanalytics/gc-toolkit/pull/42",
	})
	preopen := mergeAnchor("tk-pre", nil) // branch polecat/tk-pre, no PR yet

	b := BuildBoard([]Anchor{opened, preopen}, fixtureNow, false, nil, Facts{})

	const base = "https://github.com/zookanalytics/gc-toolkit"
	if got := mustTile(t, b, "tk-pre").PRBranchURL; got != base+"/tree/polecat/tk-pre" {
		t.Errorf("pre-PR branch link = %q, want the sibling rig's repo + tree/branch", got)
	}
	if got := mustTile(t, b, "tk-open").PRBranchURL; got != base+"/tree/polecat/tk-open" {
		t.Errorf("an opened row links its branch too: got %q", got)
	}
}

// With no pull request URL anywhere in the rig, the branch cannot be resolved to
// a repository, so it stays bare text — the state the board began in, and the
// same "nothing done" resolve_origin reports on an unresolvable origin
// (assets/scripts/pr-status-label.sh).
func TestPRBranchStaysBareWithoutARepo(t *testing.T) {
	b := BuildBoard([]Anchor{mergeAnchor("tk-pre", nil)}, fixtureNow, false, nil, Facts{})
	if got := mustTile(t, b, "tk-pre").PRBranchURL; got != "" {
		t.Errorf("no repo known: pr_branch_url = %q, want empty", got)
	}
}

func TestRepoBaseFromPRURL(t *testing.T) {
	cases := map[string]string{
		"https://github.com/zookanalytics/gc-toolkit/pull/42": "https://github.com/zookanalytics/gc-toolkit",
		"https://ghe.example.com/team/repo/pull/7":            "https://ghe.example.com/team/repo",
		"https://github.com/only-owner":                       "", // no repo segment
		"not-a-url":                                           "",
		"":                                                    "",
	}
	for in, want := range cases {
		if got := repoBaseFromPRURL(in); got != want {
			t.Errorf("repoBaseFromPRURL(%q) = %q, want %q", in, got, want)
		}
	}
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

// A closed anchor is never owed, and the merge axes are no exception. A blocked
// verdict is a live claim on the operator's time; on a bead that has closed it
// is a leftover marker, and admitting it would put a finished row at the head of
// a queue ordered by how long each has waited.
func TestClosedMergeAnchorIsNotOwed(t *testing.T) {
	a := mergeAnchor("tk-shut", map[string]string{
		"pr.machine":   dated(MachineBlocked, headLive, fixtureNow.Add(-72*time.Hour)),
		"gc.routed_to": "human",
	})
	a.ClosedAt = fixtureNow.Add(-24 * time.Hour)

	tile := computeTile(a, fixtureNow, Facts{}, 0)
	if tile.Owed {
		t.Error("a closed merge anchor is not owed, whatever markers it still carries")
	}
	if tile.Severity != SevDone {
		t.Errorf("it bands DONE like every other closed row: got %s", tile.Severity)
	}
	if tile.Needs != "closed — ages out" {
		t.Errorf("needs says a closed row leaves on its own: got %q", tile.Needs)
	}
	// The axes still travel: the row is closed, not unreadable.
	if tile.PRMachine != MachineBlocked {
		t.Errorf("pr_machine = %q, want the recorded verdict", tile.PRMachine)
	}
}

// A merged PR's anchor closes carrying its last pre-merge facts — posture still
// approved, merge state frozen at CLEAN, never restamped — so prstatus.Derive,
// reading only those live facts, still names it working. The board must not paint
// that live chip on a done row; it names the PR's resolved state off the close
// instead. A landed PR closes its anchor with merge_result=merged and reads
// "merged"; a merge anchor that reached a closed bead without that marker — a
// supersede or disposal — closed without merging and reads "closed". The per-bead
// Phase stays empty on a closed row, so the frontier keeps its age phrase. The
// live twin, with the merged anchor's identical frozen facts but still open,
// proves closedness is the only thing moving the PR axis off merging.
func TestClosedMergeAnchorShowsResolvedPRPhase(t *testing.T) {
	frozen := map[string]string{
		mdPRPosture: dated(postureApproved, headLive, fixtureNow.Add(-24*time.Hour)),
	}
	merged := mergeAnchor("tk-merged", map[string]string{
		mdPRPosture:   dated(postureApproved, headLive, fixtureNow.Add(-24*time.Hour)),
		mdMergeResult: mergeResultMerged,
		"merged_sha":  "abc123def456",
	})
	merged.ClosedAt = fixtureNow.Add(-24 * time.Hour)
	// Closed without merging: merge_result stays the default pull_request — a bare
	// close on a supersede, never transitioned to merged.
	superseded := mergeAnchor("tk-super", frozen)
	superseded.ClosedAt = fixtureNow.Add(-24 * time.Hour)
	live := mergeAnchor("tk-live", frozen) // the merged anchor's facts, still open

	b := BuildBoard([]Anchor{merged, superseded, live}, fixtureNow, false, nil, Facts{})

	if got := mustTile(t, b, "tk-live").PRPhase; got != PhaseMerging {
		t.Fatalf("test premise: the identical live anchor derives merging; got %q", got)
	}
	if got := mustTile(t, b, "tk-merged").PRPhase; got != PhaseMerged {
		t.Errorf("a merged (closed) anchor reads merged on the PR axis; got %q (the DONE-bead-shows-WORKING report)", got)
	}
	if got := mustTile(t, b, "tk-super").PRPhase; got != PhaseClosed {
		t.Errorf("a merge anchor closed without merging reads closed; got %q", got)
	}
	for _, id := range []string{"tk-merged", "tk-super"} {
		if got := mustTile(t, b, id).Phase; got != "" {
			t.Errorf("%s: a closed row carries no per-bead phase; got %q", id, got)
		}
	}
}

// A closed merge anchor is not a coverage gap either, and this is the half the
// owed test cannot cover: the queue and the coverage sentence have to empty
// together. The closed pass fills the DONE band with rows carrying the same
// axes as live ones, unrecorded positions among them, so counting those holds
// the all-clear open over an empty queue for as long as the done window keeps
// the row.
func TestClosedMergeAnchorIsNotACoverageGap(t *testing.T) {
	shut := mergeAnchor("tk-shut", nil) // nothing recorded: unknown on every axis
	shut.ClosedAt = fixtureNow.Add(-24 * time.Hour)

	done := BuildBoard([]Anchor{shut}, fixtureNow, false, nil, Facts{})
	// The axes still travel — the row is closed, not unreadable.
	if got := mustTile(t, done, "tk-shut").PRMachine; got != AxisUnknown {
		t.Errorf("the closed row keeps its axes: pr_machine = %q", got)
	}
	if c := Coverage(done.Tiles); c.Rows != 0 || !c.Complete() {
		t.Errorf("a board holding only finished pull requests owes the operator nothing: %+v", c)
	}

	live := mergeAnchor("tk-live", map[string]string{
		"pr.machine": dated(MachineSettled, headLive, fixtureNow),
		"pr_posture": dated(postureNone, headLive, fixtureNow),
	})
	c := Coverage(BuildBoard([]Anchor{live, shut}, fixtureNow, false, nil, Facts{}).Tiles)
	if c.Rows != 1 {
		t.Errorf("coverage speaks for the live rows: got %d, want 1", c.Rows)
	}
	if c.MachineUnknown != 0 {
		t.Errorf("a closed row's unread position is not a gap: got %d", c.MachineUnknown)
	}
	if c.ConversationUnknown != 1 {
		t.Errorf("the live row's unread conversation still is: got %d", c.ConversationUnknown)
	}
}

// TestPreOpenRowIsIdentifiedByBranch. An anchor at pre_open_gate has no pull
// request open, so the row is keyed on the anchor and carries the branch
// instead: as a field, because the tables with no frontier column are the ones
// the operator reads first, and in the frontier beside the age the queue is
// sorted by. A pre-open check stalled three days is the owed shape here.
func TestPreOpenRowIsIdentifiedByBranch(t *testing.T) {
	pre := mergeAnchor("tk-pre", map[string]string{
		"merge_result": "pre_open_gate",
		"check_set":    "correctness",
	})
	pre.UpdatedAt = fixtureNow.Add(-72 * time.Hour)
	tile := mustTile(t, BuildBoard([]Anchor{pre}, fixtureNow, false, nil, Facts{}), "tk-pre")

	if !tile.Owed {
		t.Fatal("a pre-open check stalled three days is owed by the operator")
	}
	if tile.PRNumber != 0 || !strings.Contains(tile.Frontier, "polecat/tk-pre") {
		t.Errorf("a pre-open row identifies itself by branch, got number=%d frontier=%q",
			tile.PRNumber, tile.Frontier)
	}
	if tile.PRBranch != "polecat/tk-pre" {
		t.Errorf("pr_branch = %q, want the branch the row is identified by", tile.PRBranch)
	}
	if !strings.Contains(tile.Frontier, "owed 3d") {
		t.Errorf("the row carries the age the queue is sorted by, got %q", tile.Frontier)
	}
}

// TestStandingVetoInSettledTailIsOwed. GitHub keeps a CHANGES_REQUESTED standing
// across pushes and the city never dismisses it, so once the cadence has run dry
// — no fix unit, review, or finding in flight — the veto is the operator's to
// clear by re-reviewing. merge.sh records `settled` in that tail, the owed rule
// reads the standing changes_requested off the posture axis, and the row names
// the re-review, dated to the head the veto stands at. A veto with a fix unit
// still in flight reads `progressing` and stays the city's move. An open PR
// leads with its number and link either way.
func TestStandingVetoInSettledTailIsOwed(t *testing.T) {
	at := fixtureNow.Add(-72 * time.Hour)
	b := BuildBoard([]Anchor{
		mergeAnchor("tk-veto", map[string]string{
			"pr.machine": dated(MachineSettled, headLive, at),
			"pr_number":  "513",
			"pr_url":     "https://github.com/zook/gc-toolkit/pull/513",
			"pr_posture": dated(postureChangesRequested, headLive, at),
		}),
		// The same standing veto WITH a fix unit in flight: merge.sh's in-flight
		// arm records `progressing` before the veto arm runs, so the row stays
		// the city's move.
		mergeAnchor("tk-veto-busy", map[string]string{
			"pr.machine": dated(MachineProgressing, headLive, at),
			"pr_number":  "514",
			"pr_url":     "https://github.com/zook/gc-toolkit/pull/514",
			"pr_posture": dated(postureChangesRequested, headLive, at),
		}),
	}, fixtureNow, false, nil, Facts{})

	veto := mustTile(t, b, "tk-veto")
	if veto.PRMachine != MachineSettled {
		t.Errorf("pr_machine = %q, want %q", veto.PRMachine, MachineSettled)
	}
	if !veto.Owed {
		t.Error("a standing CHANGES_REQUESTED in the settled tail is the operator's to clear by re-reviewing")
	}
	if !strings.Contains(veto.Needs, "re-review") {
		t.Errorf("needs names the re-review the row is owed, got %q", veto.Needs)
	}
	if veto.PRNumber != 513 || veto.PRURL == "" {
		t.Errorf("an open PR carries its number and link, got %d / %q", veto.PRNumber, veto.PRURL)
	}
	if !strings.Contains(veto.Frontier, "owed 3d") {
		t.Errorf("the row carries the age the queue is sorted by, got %q", veto.Frontier)
	}

	busy := mustTile(t, b, "tk-veto-busy")
	if busy.PRMachine != MachineProgressing {
		t.Errorf("pr_machine = %q, want %q", busy.PRMachine, MachineProgressing)
	}
	if busy.Owed {
		t.Error("a standing veto with a fix unit in flight is the city's move, not the operator's")
	}
	if !strings.Contains(busy.Needs, "merge cadence") {
		t.Errorf("needs reads as progressing, got %q", busy.Needs)
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

// TestBlockedAnchorIsOwedAndNamed. A green, APPROVED PR that merge.sh cannot land
// without a person — an unresolved required review thread, a base gone BEHIND, or
// a live blocker no automated actor holds — records `blocked` with the
// cause in pr.machine_reason. The board owes it to the operator, phases it
// needs-attention, and names the cause, so it stops reading as awaiting-review
// even though the review verdict is `approved`. That approved-and-held shape is
// the silent-hold class this fixes: approval `met` used to leave a settled row
// not owed, so nothing surfaced it.
func TestBlockedAnchorIsOwedAndNamed(t *testing.T) {
	at := fixtureNow.Add(-2 * time.Hour)
	reason := "2 unresolved review thread(s) must be resolved before this PR can merge"
	b := BuildBoard([]Anchor{
		mergeAnchor("tk-blk", map[string]string{
			"pr.machine":        dated(MachineBlocked, headLive, at),
			"pr.machine_reason": reason,
			"pr_number":         "878",
			"pr_url":            "https://github.com/zook/gc-toolkit/pull/878",
			// Approved at the live head: the state that read settled+met (not
			// owed) before, so an approved-but-held PR sat invisible.
			"pr_posture": dated(postureApproved, headLive, at),
		}),
	}, fixtureNow, false, nil, Facts{})

	blk := mustTile(t, b, "tk-blk")
	if blk.PRMachine != MachineBlocked {
		t.Errorf("pr_machine = %q, want %q", blk.PRMachine, MachineBlocked)
	}
	if blk.PRApproval != ApprovalMet {
		t.Errorf("the PR is approved: pr_approval = %q, want %q", blk.PRApproval, ApprovalMet)
	}
	if !blk.Owed {
		t.Error("an approved PR blocked by a hold no automated actor clears is owed by the operator, not settled")
	}
	if blk.PRPhase != PhaseNeedsAttention {
		t.Errorf("pr_phase = %q, want %q — a blocked PR surfaces as needs-attention, not awaiting-review", blk.PRPhase, PhaseNeedsAttention)
	}
	if !strings.Contains(blk.Needs, "blocked:") || !strings.Contains(blk.Needs, "unresolved review thread") {
		t.Errorf("needs must name the block and its cause, got %q", blk.Needs)
	}
	if !blk.PROwedSince.Equal(at) {
		t.Errorf("pr_owed_since = %v, want the blocked stamp %v", blk.PROwedSince, at)
	}
}

// TestBlockedAtAnEarlierHeadIsMerging: a blocked verdict the merge pass
// recorded at a head the PR has since left was reached about another commit, so
// an approved PR at the new head reads merging on both axes, as its status:
// label does, and the roll-up treats it as a row like any other. The owed queue
// reads the verdict by the same rule, so the row is not the operator's and its
// needs phrase does not call it blocked.
func TestBlockedAtAnEarlierHeadIsMerging(t *testing.T) {
	at := fixtureNow.Add(-2 * time.Hour)
	b := BuildBoard([]Anchor{
		mergeAnchor("tk-moved", map[string]string{
			mdPRMachine:       dated(MachineBlocked, "oldhead", at),
			mdPRMachineCause:  "check-failed",
			mdPRMachineReason: "required check(s) test failed at the head",
			mdPRPosture:       dated(postureApproved, headLive, at),
			mdPRNumber:        "877",
		}),
	}, fixtureNow, false, nil, Facts{})
	tile := mustTile(t, b, "tk-moved")
	if tile.PRPhase != PhaseMerging || tile.Phase != PhaseMerging {
		t.Errorf("a blocked verdict at an earlier head does not hold the PR: pr_phase=%q phase=%q, want merging", tile.PRPhase, tile.Phase)
	}
	if tile.Owed || !tile.PROwedSince.IsZero() {
		t.Errorf("a verdict the chip does not count owes the operator nothing: owed=%v since=%v", tile.Owed, tile.PROwedSince)
	}
	if strings.Contains(tile.Needs, "blocked") {
		t.Errorf("needs must not call a merging row blocked, got %q", tile.Needs)
	}
	if tile.PRMachine != MachineProgressing {
		t.Errorf("pr_machine = %q, want %q: the next merge pass replaces a verdict at another head", tile.PRMachine, MachineProgressing)
	}
}

// TestBlockedWithReworkInFlightIsMerging: the merge pass records a cause other
// than blocker only with nothing in flight, so an open rework child that arrives
// afterwards is the city acting on the cause. The approved row reads merging on
// both axes and stays out of the owed queue, whether or not a pool route marks
// the child: a poured rework carries none.
func TestBlockedWithReworkInFlightIsMerging(t *testing.T) {
	at := fixtureNow.Add(-2 * time.Hour)
	anchor := mergeAnchor("tk-fixing", map[string]string{
		mdPRMachine:       dated(MachineBlocked, headLive, at),
		mdPRMachineCause:  "check-failed",
		mdPRMachineReason: "required check(s) test failed at the head",
		mdPRPosture:       dated(postureApproved, headLive, at),
		mdPRNumber:        "879",
	}, Blocker{ID: "tk-fixing.rw", Title: "Rework branch polecat/tk-fixing", Status: "open", IssueType: "task"})
	kid := Anchor{ID: "tk-fixing.rw", Title: "Rework branch polecat/tk-fixing", Kind: "rework", Source: kindRework,
		Rig: "gc-toolkit", Prefix: "tk", Metadata: map[string]string{mdAnchorBead: "tk-fixing"}}

	tile := mustTile(t, BuildBoard([]Anchor{anchor, kid}, fixtureNow, false, nil, Facts{}), "tk-fixing")
	if tile.PRPhase != PhaseMerging || tile.Phase != PhaseMerging {
		t.Errorf("rework in flight on the cause leaves the PR the city's to land: pr_phase=%q phase=%q, want merging", tile.PRPhase, tile.Phase)
	}
	if tile.Owed || !tile.PROwedSince.IsZero() {
		t.Errorf("a verdict the chip does not count owes the operator nothing: owed=%v since=%v", tile.Owed, tile.PROwedSince)
	}
	if strings.Contains(tile.Needs, "blocked") {
		t.Errorf("needs must not call a merging row blocked, got %q", tile.Needs)
	}
}

// TestBlockerCauseWithAPoolRoutedBlockerIsOwed: the blocker cause holds the PR
// whatever is in flight, because the merge pass records it only once no
// automated actor holds a live blocker. A pool-routed blocker that arrives
// before the next pass does not lift that verdict: the row reads needs-attention
// on both axes, as its status: label does, so it stays in the owed queue, named
// blocked, until the pass replaces the verdict.
func TestBlockerCauseWithAPoolRoutedBlockerIsOwed(t *testing.T) {
	at := fixtureNow.Add(-2 * time.Hour)
	b := BuildBoard([]Anchor{
		mergeAnchor("tk-held", map[string]string{
			mdPRMachine:       dated(MachineBlocked, headLive, at),
			mdPRMachineCause:  "blocker",
			mdPRMachineReason: "held by unclosed rework/review bead tk-held.f (open) — a live blocker no automated actor holds",
			mdPRPosture:       dated(postureApproved, headLive, at),
			mdPRNumber:        "880",
		}, Blocker{ID: "tk-held.f", Title: "fix the finding", Status: "open",
			RoutedTo: "gc-toolkit/gc-toolkit.polecat", IssueType: "task"}),
	}, fixtureNow, false, nil, Facts{})
	tile := mustTile(t, b, "tk-held")
	if tile.PRPhase != PhaseNeedsAttention || tile.Phase != PhaseNeedsAttention {
		t.Fatalf("test premise: the blocker cause holds the chip whatever is in flight: pr_phase=%q phase=%q", tile.PRPhase, tile.Phase)
	}
	if !tile.Owed || !tile.PROwedSince.Equal(at) {
		t.Errorf("a verdict the chip counts is owed from its own stamp: owed=%v since=%v, want since %v", tile.Owed, tile.PROwedSince, at)
	}
	if !strings.Contains(tile.Needs, "blocked:") {
		t.Errorf("needs names the block the chip reads, got %q", tile.Needs)
	}
	if tile.PRMachine != MachineBlocked {
		t.Errorf("pr_machine = %q, want %q", tile.PRMachine, MachineBlocked)
	}
}

// TestBlockedWithAnUnnamedCauseIsOwed: a blocked verdict whose cause is outside
// the vocabulary is a state the derivation cannot name, so the chip reads
// needs-attention wherever the verdict was recorded and whatever is in flight.
// The owed queue reads it by the same rule, at a head the posture has left and
// with a rework child in flight alike: the row stays owed from the verdict's
// own stamp, and its needs phrase names the block.
func TestBlockedWithAnUnnamedCauseIsOwed(t *testing.T) {
	at := fixtureNow.Add(-2 * time.Hour)
	reason := "a cause this build has no word for"
	moved := mergeAnchor("tk-skew-moved", map[string]string{
		mdPRMachine:       dated(MachineBlocked, "oldhead", at),
		mdPRMachineCause:  "mystery",
		mdPRMachineReason: reason,
		mdPRPosture:       dated(postureApproved, headLive, at),
		mdPRNumber:        "881",
	})
	fixing := mergeAnchor("tk-skew-fixing", map[string]string{
		mdPRMachine:       dated(MachineBlocked, headLive, at),
		mdPRMachineCause:  "mystery",
		mdPRMachineReason: reason,
		mdPRPosture:       dated(postureApproved, headLive, at),
		mdPRNumber:        "882",
	}, Blocker{ID: "tk-skew-fixing.rw", Title: "Rework branch polecat/tk-skew-fixing", Status: "open", IssueType: "task"})
	kid := Anchor{ID: "tk-skew-fixing.rw", Title: "Rework branch polecat/tk-skew-fixing", Kind: "rework", Source: kindRework,
		Rig: "gc-toolkit", Prefix: "tk", Metadata: map[string]string{mdAnchorBead: "tk-skew-fixing"}}

	b := BuildBoard([]Anchor{moved, fixing, kid}, fixtureNow, false, nil, Facts{})
	for _, id := range []string{"tk-skew-moved", "tk-skew-fixing"} {
		tile := mustTile(t, b, id)
		if tile.PRPhase != PhaseNeedsAttention || tile.Phase != PhaseNeedsAttention {
			t.Fatalf("%s: test premise: a cause the derivation cannot name holds the chip: pr_phase=%q phase=%q", id, tile.PRPhase, tile.Phase)
		}
		if !tile.Owed || !tile.PROwedSince.Equal(at) {
			t.Errorf("%s: a verdict the chip counts is owed from its own stamp: owed=%v since=%v, want since %v", id, tile.Owed, tile.PROwedSince, at)
		}
		if tile.Needs != "blocked: "+reason {
			t.Errorf("%s: needs names the block the chip reads, got %q", id, tile.Needs)
		}
		if tile.PRMachine != MachineBlocked {
			t.Errorf("%s: pr_machine = %q, want %q", id, tile.PRMachine, MachineBlocked)
		}
	}
}

// TestBlockedReasonlessStillNeedsAttention. A blocked verdict whose reason write
// dropped still owes the row and phases it needs-attention, falling back to a
// generic sentence rather than reading as settled.
func TestBlockedReasonlessStillNeedsAttention(t *testing.T) {
	b := BuildBoard([]Anchor{
		mergeAnchor("tk-blk0", map[string]string{
			"pr.machine": dated(MachineBlocked, headLive, fixtureNow),
			"pr_number":  "876",
			"pr_url":     "https://github.com/zook/gc-toolkit/pull/876",
		}),
	}, fixtureNow, false, nil, Facts{})
	blk := mustTile(t, b, "tk-blk0")
	if !blk.Owed || blk.PRPhase != PhaseNeedsAttention {
		t.Errorf("a blocked verdict is owed and needs-attention even with no reason: owed=%v phase=%q", blk.Owed, blk.PRPhase)
	}
	if !strings.Contains(blk.Needs, "blocked") {
		t.Errorf("needs still names the block, got %q", blk.Needs)
	}
}

// TestSettledApprovedIsNotBlocked is the benign control the acceptance names: an
// approved PR merely waiting on the merge pass (settled, not blocked) is the
// city's move — not owed and not needs-attention.
func TestSettledApprovedIsNotBlocked(t *testing.T) {
	b := BuildBoard([]Anchor{
		mergeAnchor("tk-ok", map[string]string{
			"pr.machine": dated(MachineSettled, headLive, fixtureNow),
			"pr_number":  "900",
			"pr_url":     "https://github.com/zook/gc-toolkit/pull/900",
			"pr_posture": dated(postureApproved, headLive, fixtureNow),
		}),
	}, fixtureNow, false, nil, Facts{})
	ok := mustTile(t, b, "tk-ok")
	if ok.Owed {
		t.Error("an approved PR waiting on the merge pass is not owed by the operator")
	}
	if ok.PRPhase == PhaseNeedsAttention {
		t.Errorf("a settled+approved PR is not needs-attention, got phase %q", ok.PRPhase)
	}
}

// TestAskingIsOwedAndCarriesTheDemand: the city formed a question and is waiting
// on the answer. The hold is an open `blocks` edge to a demand bead with
// nothing added, and closing the bead is what ends it.
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
		// The takeaway twin of a merge anchor whose every blocker has closed.
		func() Anchor {
			a := mergeAnchor("tk-disp", map[string]string{
				"gc.takeaway": "waiting on the upstream fix",
			})
			a.Kind, a.Source = "parked", "parked"
			a.Takeaway = a.Metadata["gc.takeaway"]
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
	if busy.Frontier != "needs-review · PR #509" {
		t.Errorf("frontier names the pull request, got %q", busy.Frontier)
	}

	bare := mustTile(t, b, "tk-bare")
	if bare.Frontier != "needs-review · routed to the operator — no agent will take it" {
		t.Errorf("with no number and no branch the row says who holds it, got %q", bare.Frontier)
	}
	if bare.Needs != "routed to you — no question recorded" {
		t.Errorf("needs = %q", bare.Needs)
	}

	// A pull request the city is landing is in review, not a park that ended:
	// the blockers that closed are its review rounds. The row names the pull
	// request, and the takeaway stays its NEEDS as on every other merge anchor.
	disp := mustTile(t, b, "tk-disp")
	if disp.DispositionDue || disp.Owed {
		t.Errorf("a pull request in review owes no disposition: disposition_due=%v owed=%v", disp.DispositionDue, disp.Owed)
	}
	if disp.Frontier != "needs-review · polecat/tk-disp" {
		t.Errorf("frontier = %q, want the pull request's identity", disp.Frontier)
	}
	if disp.Needs != "waiting on the upstream fix" {
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
// pr-facts.sh can record: a partial one leaves the rest to be invented. Under the
// universal approval rule only `approved` is met; every other posture, `none`
// included, owes the approval, so none renders as a merge GitHub or the city's
// own rule will let through.
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
		{postureChangesRequested, ApprovalRequired, true,
			"GitHub keeps the veto standing across pushes; in the settled tail the operator clears it by re-reviewing"},
		{postureApproved, ApprovalMet, false, "approved"},
		{postureCommented, ApprovalRequired, true,
			"a comment-only review has not approved, and approval is universal — the merge still owes one"},
		{postureNone, ApprovalRequired, true,
			"no reviewDecision (an integration/* base, or a repo with no required-review rule) still owes the universal approval"},
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
// restarts there reports a three-day wait as new and sorts the most neglected
// row last.
func TestOwedClockHoldsAcrossPassesAndRestartsOnAHeadMove(t *testing.T) {
	blockedAt := fixtureNow.Add(-72 * time.Hour)
	held := dated(MachineBlocked, headLive, blockedAt)

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

	// A verdict is pinned to the head it judged, so one at the NEW head is a new
	// turn.
	moved := mustTile(t, BuildBoard([]Anchor{
		mergeAnchor("tk-w", map[string]string{
			"pr.machine": dated(MachineBlocked, headOld, later),
		}),
	}, later, false, nil, Facts{}), "tk-w")
	if !moved.PROwedSince.Equal(later) {
		t.Errorf("a verdict at a new head starts a fresh clock: got %v, want %v",
			moved.PROwedSince, later)
	}
}

// TestOwedSinceTakesTheEarliestCause. A row blocked three days ago and asked
// about an hour ago has been owed for three days, and the queue ranks it there.
func TestOwedSinceTakesTheEarliestCause(t *testing.T) {
	blockedAt := fixtureNow.Add(-72 * time.Hour)
	askedAt := fixtureNow.Add(-1 * time.Hour)
	a := mergeAnchor("tk-both", map[string]string{
		"pr.machine": dated(MachineBlocked, headLive, blockedAt),
	}, Blocker{ID: "tk-d", Title: "and a question", Status: "open",
		RoutedTo: "human", CreatedAt: askedAt})

	tile := mustTile(t, BuildBoard([]Anchor{a}, fixtureNow, false, nil, Facts{}), "tk-both")
	if !tile.PROwedSince.Equal(blockedAt) {
		t.Errorf("pr_owed_since = %v, want the EARLIEST cause %v", tile.PROwedSince, blockedAt)
	}
}

// TestUnrecordedPositionIsUnknownAndCountsAgainstCoverage. A missing key means
// the cadence has not written one yet, which is a fact about the city rather
// than an all-clear — and the all-clear is exactly what a quiet default would
// produce.
func TestUnrecordedPositionIsUnknownAndCountsAgainstCoverage(t *testing.T) {
	b := BuildBoard([]Anchor{
		mergeAnchor("tk-silent", nil),
		// It carries a branch, which every work bead does. That is what makes
		// the axes' merge-anchor gate load-bearing rather than decorative.
		{ID: "tk-epic", Title: "an ordinary epic", Kind: "epic", Source: "epic",
			Rig: "gc-toolkit", Prefix: "tk", Metadata: map[string]string{"branch": "polecat/tk-epic"},
			Children: []Child{{ID: "c1", Status: "open"}}},
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
	if epic.PRBranch != "" {
		t.Errorf("a non-merge row names no pull request branch, got %q", epic.PRBranch)
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

// TestConversationAxisRendersTheRecordedPosition. Phase 2a fills the axis from
// the position pr-facts.sh records against the watermarks. Each recorded value
// renders; asking wins from the demand edge ahead of any recorded position; and
// a position pinned to a head the cadence has moved past reads unknown rather
// than a stale value — the same currency check the approval clause makes.
func TestConversationAxisRendersTheRecordedPosition(t *testing.T) {
	askedAt := fixtureNow.Add(-2 * time.Hour)
	live := func(v string) map[string]string {
		return map[string]string{
			"pr.machine":      dated(MachineSettled, headLive, fixtureNow),
			"pr.conversation": dated(v, headLive, fixtureNow),
		}
	}
	cases := []struct {
		id   string
		md   map[string]string
		blk  []Blocker
		want string
	}{
		{"tk-quiet", live(ConversationQuiet), nil, ConversationQuiet},
		{"tk-out", live(ConversationOutstanding), nil, ConversationOutstanding},
		{"tk-ans", live(ConversationAnswered), nil, ConversationAnswered},
		// asking is the edge, and it renders ahead of the recorded position.
		{"tk-ask", live(ConversationOutstanding),
			[]Blocker{{ID: "tk-dem", Title: "Which base?", Status: "open",
				RoutedTo: "human", CreatedAt: askedAt}}, ConversationAsking},
		// Pinned to a head the cadence has moved past: unknown, never the stale value.
		{"tk-stale", map[string]string{
			"pr.machine":      dated(MachineSettled, headLive, fixtureNow),
			"pr.conversation": dated(ConversationOutstanding, headOld, fixtureNow),
		}, nil, ConversationUnknown},
		// Recorded, but no machine head to verify it against: unknown.
		{"tk-noref", map[string]string{
			"pr.conversation": dated(ConversationAnswered, headLive, fixtureNow),
		}, nil, ConversationUnknown},
		// A pre-open gate has no PR yet: nothing can have been said, so quiet, not
		// unknown — the gap it would otherwise hold open forever (pr-facts.sh never
		// records a conversation before the PR opens).
		{"tk-preopen", map[string]string{
			"merge_result": mergeResultPreOpenGate,
			"pr.machine":   dated(MachineProgressing, headLive, fixtureNow),
		}, nil, ConversationQuiet},
	}
	anchors := make([]Anchor, 0, len(cases))
	for _, c := range cases {
		anchors = append(anchors, mergeAnchor(c.id, c.md, c.blk...))
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})
	for _, c := range cases {
		if got := mustTile(t, b, c.id).PRConversation; got != c.want {
			t.Errorf("%s: pr_conversation = %q, want %q", c.id, got, c.want)
		}
	}
}

// TestReadableConversationIsNotACoverageGap. A recorded position is a fact, not
// a gap: only an unread axis holds the all-clear open. A settled, quiet row whose
// approval is met, with no demand, is genuinely nobody's move.
func TestReadableConversationIsNotACoverageGap(t *testing.T) {
	b := BuildBoard([]Anchor{
		mergeAnchor("tk-clear", map[string]string{
			"pr.machine":      dated(MachineSettled, headLive, fixtureNow),
			"pr.conversation": dated(ConversationQuiet, headLive, fixtureNow),
			"pr_posture":      dated(postureApproved, headLive, fixtureNow),
		}),
	}, fixtureNow, false, nil, Facts{})

	tile := mustTile(t, b, "tk-clear")
	if tile.PRConversation != ConversationQuiet {
		t.Errorf("pr_conversation = %q, want quiet", tile.PRConversation)
	}
	if tile.Owed {
		t.Error("a settled, quiet row whose approval is met is nobody's move")
	}
	if c := Coverage(b.Tiles); !c.Complete() || c.ConversationUnknown != 0 {
		t.Errorf("a recorded conversation clears the gap it would otherwise hold: %+v", c)
	}
}

// TestMachineUnknownDoesNotDoubleCountConversation. A row whose pr.machine is
// absent reads unknown on the conversation axis too — the currency check in
// prConversation pins to the machine head and cannot run without it — so
// counting the conversation would report one gap as two and blame the
// conversation for one that is the machine reference's. The machine is the gap
// to fix; the conversation follows once it is current.
func TestMachineUnknownDoesNotDoubleCountConversation(t *testing.T) {
	// An open PR with neither axis recorded: both read unknown.
	a := mergeAnchor("tk-noax", map[string]string{"pr_number": "9"})
	c := Coverage(BuildBoard([]Anchor{a}, fixtureNow, false, nil, Facts{}).Tiles)
	if c.MachineUnknown != 1 {
		t.Errorf("the absent machine is the gap: MachineUnknown = %d, want 1", c.MachineUnknown)
	}
	if c.ConversationUnknown != 0 {
		t.Errorf("the conversation is not counted while the machine head it pins to is unknown: got %d, want 0", c.ConversationUnknown)
	}
}

// TestOwedPRRowLeadsTheQueue. The owed partition and its ordering are the
// queue's own; this asserts a PR row participates in them rather than needing a
// surface of its own.
func TestOwedPRRowLeadsTheQueue(t *testing.T) {
	old := fixtureNow.Add(-96 * time.Hour)
	recent := fixtureNow.Add(-2 * time.Hour)
	b := BuildBoard([]Anchor{
		mergeAnchor("tk-new", map[string]string{"pr.machine": dated(MachineBlocked, headLive, recent)}),
		{ID: "tk-big", Title: "a container that outranks everything", Kind: "epic", Source: "epic",
			Rig: "gc-toolkit", Prefix: "tk", Children: func() []Child {
				out := make([]Child, 40)
				for i := range out {
					out[i] = Child{ID: fmt.Sprintf("k%d", i), Status: "open"}
				}
				return out
			}()},
		mergeAnchor("tk-old", map[string]string{"pr.machine": dated(MachineBlocked, headLive, old)}),
	}, fixtureNow, false, nil, Facts{})

	q := OperatorQueue(b.Tiles)
	got := []string{}
	for _, t := range q {
		got = append(got, t.ID)
	}
	if !slices.Equal(got, []string{"tk-old", "tk-new"}) {
		t.Errorf("the queue is the blocked rows, oldest-owed first: got %v", got)
	}
	if _, ok := tileByID(Board{Tiles: q}, "tk-big"); ok {
		t.Error("a container nobody is owed anything on is not in the operator's queue")
	}
}

// TestHumanRoutedMergeAnchorGathersTwiceAndCollapsesToOneRow.
//
// A merge anchor routed to a person carries `gc.routed_to=human` AND
// `merge_result`, so the gather admits it under both kinds and hands BuildBoard
// two anchors with one id. Both rows read the same metadata, so they band the
// same and tie on rank_score — which means the stable sort, not the band,
// decides which survives, and the gather's ordering is load-bearing rather than
// incidental.
//
// The row that survives has to keep both halves: the `human` kind every
// human-gate rule keys on, and the PR axes, which are what this surface adds.
// Losing either is silent — the operator just sees one fewer fact.
func TestHumanRoutedMergeAnchorGathersTwiceAndCollapsesToOneRow(t *testing.T) {
	blockedAt := fixtureNow.Add(-72 * time.Hour)
	md := map[string]string{
		"merge_result": "pull_request",
		"branch":       "polecat/tk-w",
		"gc.routed_to": "human",
		"pr.machine":   dated(MachineBlocked, headLive, blockedAt),
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
	if tile.PRMachine != MachineBlocked || !tile.PROwedSince.Equal(blockedAt) {
		t.Errorf("the surviving row lost its axes: machine=%q since=%v", tile.PRMachine, tile.PROwedSince)
	}
	if !tile.Owed {
		t.Error("and it is still owed")
	}
	// Both derivations agree it is owed, so neither ordering could drop it from
	// the queue — but they must also agree on the phrase, or the row a reader
	// sees depends on which copy won.
	if !strings.Contains(tile.Needs, "blocked") {
		t.Errorf("needs = %q, want the block named", tile.Needs)
	}
}

// TestHumanRoutedBlockerIsADemand is the one case where the demand test is
// wider than the `decision` issue type.
//
// The shape it is built from: an anchor blocks on a `bug` that was routed to a
// person and left open for days. It is not a `decision` and not a visit, so a
// narrow reading calls it an ordinary prerequisite and the waiting row stays
// out of the queue — banded LOW, under a takeaway saying the work was finished
// and only an operator could open its PR.
//
// The route is what makes it a demand: nothing but a person closes a bead held
// by a person, whether or not that wait has been expressed as a decision bead.
func TestHumanRoutedBlockerIsADemand(t *testing.T) {
	routedAt := fixtureNow.Add(-13 * 24 * time.Hour)
	a := mergeAnchor("tk-waiter", map[string]string{"pr_number": "473"},
		Blocker{
			ID: "tk-held", Title: "the fix its PR cannot open", Status: "open",
			// Routed to a person, no pool route, an ordinary work type.
			RoutedTo: "human", IssueType: "bug", CreatedAt: routedAt,
		})
	tile := mustTile(t, BuildBoard([]Anchor{a}, fixtureNow, false, nil, Facts{}), "tk-waiter")

	if !tile.Owed {
		t.Error("an anchor whose only blocker no automated actor will close is waiting on a person")
	}
	if !tile.PROwedSince.Equal(routedAt) {
		t.Errorf("pr_owed_since = %v, want the blocker's own created_at %v", tile.PROwedSince, routedAt)
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
		RoutedTo: "gc-toolkit/gc-toolkit.polecat", IssueType: "bug", CreatedAt: routedAt,
	})
	if mustTile(t, BuildBoard([]Anchor{b}, fixtureNow, false, nil, Facts{}), "tk-busy").Owed {
		t.Error("a pool-routed blocker of the same shape is the city's move, not the operator's")
	}
}

// TestHumanGatedWithLiveMoleculeIsActive covers tk-ikpyzn.5's core: a human-gated
// row — a bead routed to the operator, or a decision — that the city is actively
// working reads as in-flight, not an operator gate. Liveness falsifies "no agent
// will take this until a human moves it": an agent has. It is the un-ruled twin of
// TestRuledInFlightIsInProgress and mirrors TestParkedWithLiveMoleculeIsActive —
// one shape wired three ways, so the signal that flips the band is proven to be
// LIVE execution over the bead itself and nothing else.
func TestHumanGatedWithLiveMoleculeIsActive(t *testing.T) {
	human := func(id string) Anchor {
		return Anchor{ID: id, Title: "routed to the operator", Kind: "human", Source: "human",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1),
			Metadata: map[string]string{"gc.routed_to": "human"}}
	}
	f := Facts{
		// tk-live: a molecule whose session is up. tk-drained: the same wiring, but
		// the session has gone — wfLive must stop counting it at once.
		Inflight: map[string][]string{
			"tk-live":    {"gc-toolkit__polecat-hq-live"},
			"tk-drained": {"gc-toolkit__polecat-hq-gone"},
		},
		OwnerState: map[string]string{"gc-toolkit__polecat-hq-live": "active"},
	}
	b := BuildBoard([]Anchor{human("tk-live"), human("tk-drained"), human("tk-none"),
		{ID: "tk-dec", Title: "a call to make", Kind: "decision", Source: "decision",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1)}},
		fixtureNow, false, nil, f)

	live := mustTile(t, b, "tk-live")
	if live.Severity != SevNormal {
		t.Errorf("a human-gated bead with a live molecule is in-flight work, not an ELEVATED gate: got %s", live.Severity)
	}
	if live.Section != SectionActive {
		t.Errorf("…so it bands active, not gate: got %s", live.Section)
	}
	if live.Owed {
		t.Error("…and an agent holds the next move, so it is not the operator's to answer")
	}
	if live.Frontier != "working · human-gated — work in flight" {
		t.Errorf("frontier: %q", live.Frontier)
	}
	if live.Needs != "in flight" {
		t.Errorf("needs names the live state, not the un-ruled gate: %q", live.Needs)
	}

	// The discriminator: identical wiring, dead session. The gate stands back up.
	drained := mustTile(t, b, "tk-drained")
	if drained.Severity != SevElevated || drained.Section != SectionGate || !drained.Owed {
		t.Errorf("a drained molecule returns the human gate: %s / %s / owed=%v", drained.Severity, drained.Section, drained.Owed)
	}
	if drained.Frontier != "needs-review · routed to the operator — no agent will take it" {
		t.Errorf("drained frontier: %q", drained.Frontier)
	}

	// No workflow at all — the ordinary human gate is untouched (TestUnruledHumanGatedRowsAreUnchanged).
	none := mustTile(t, b, "tk-none")
	if none.Severity != SevElevated || !none.Owed {
		t.Errorf("a human gate with no molecule is unchanged: %s / owed=%v", none.Severity, none.Owed)
	}
	// And the decision kind is gated the same way when un-worked.
	dec := mustTile(t, b, "tk-dec")
	if dec.Severity != SevElevated || dec.Frontier != "needs-review · human-gated decision" || !dec.Owed {
		t.Errorf("an un-worked decision keeps its gate: %s / %q / owed=%v", dec.Severity, dec.Frontier, dec.Owed)
	}
}

// TestDemandFoldYieldsToLiveWork covers the 2026-09-27 epic evidence: a demand
// folded onto a subject the city is actively working must not mark it owed. The
// live signal is the subject's own roll-up (a live child), which the demand fold
// reads to decide whether an agent is on the subject — not child-to-parent state
// aggregation (tk-ikpyzn.6). The demand's ask re-surfaces on its own when the work
// drains, because the fold is re-derived every render.
func TestDemandFoldYieldsToLiveWork(t *testing.T) {
	anchors := []Anchor{
		// A subject the city is working: its child is covered by a live molecule.
		{ID: "tk-live", Title: "worked epic", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk",
			Priority: ptr(3), UpdatedAt: fixtureNow, Children: []Child{{ID: "tk-klive", Status: "open"}}},
		{ID: "tk-dem-live", Title: "demand: coord open", Kind: "human", Source: "human", Rig: "gc-toolkit", Prefix: "tk",
			Priority: ptr(2), UpdatedAt: fixtureNow,
			Metadata: map[string]string{"gc.demand_for": "tk-live", "gc.routed_to": "human"},
			Takeaway: "coord open; nothing owed"},
		// The discriminator: the same shape with an IDLE child. The demand owes.
		{ID: "tk-idle", Title: "stalled epic", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk",
			Priority: ptr(3), UpdatedAt: fixtureNow, Children: []Child{{ID: "tk-kidle", Status: "open"}}},
		{ID: "tk-dem-idle", Title: "demand: decide", Kind: "human", Source: "human", Rig: "gc-toolkit", Prefix: "tk",
			Priority: ptr(2), UpdatedAt: fixtureNow,
			Metadata: map[string]string{"gc.demand_for": "tk-idle", "gc.routed_to": "human"},
			Takeaway: "decide the layout"},
	}
	f := Facts{
		Inflight:   map[string][]string{"tk-klive": {"gc-toolkit__polecat-hq-live"}},
		OwnerState: map[string]string{"gc-toolkit__polecat-hq-live": "active"},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, f)

	live := mustTile(t, b, "tk-live")
	if live.Owed {
		t.Error("a demand whose subject the city is working must not mark it owed")
	}
	if live.Section != SectionActive {
		t.Errorf("…so the subject bands active, not gate: got %s", live.Section)
	}
	if live.Needs != "in flight" {
		t.Errorf("…and it keeps its own in-flight needs, not the demand's ask: %q", live.Needs)
	}
	// The wrapper is folded away regardless — one attention item is one row.
	if _, ok := tileByID(b, "tk-dem-live"); ok {
		t.Error("the folded demand wrapper is dropped")
	}

	idle := mustTile(t, b, "tk-idle")
	if !idle.Owed {
		t.Error("a demand whose subject has no live work owes the operator")
	}
	if idle.Section != SectionGate {
		t.Errorf("…so the subject bands gate: got %s", idle.Section)
	}
	if idle.Needs != "decide the layout" {
		t.Errorf("the demand's ask becomes the subject's needs: %q", idle.Needs)
	}
}

// A recommendation row carries the first-reaction card to the operator's accept
// point. When a subject is acceptable — a recommended formula plus an open,
// un-engaged visit — its notes (the Proposal and Decision-needed an operator
// weighs) reach the wire as Tile.Recommendation, trimmed but with the card's
// section structure intact. Off an acceptable row the field stays null, so the
// wire never carries every bead's notes.
func TestRecommendationRidesTheAcceptableRow(t *testing.T) {
	const card = "## Proposal\nDo the thing.\n\n## Decision needed\nAccept or redirect."
	subject := func(id string) Anchor {
		return Anchor{
			ID: id, Title: id, Kind: "parked", Source: "parked",
			Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), UpdatedAt: daysAgo(1),
			Metadata: map[string]string{"gc.recommended_formula": "mol-polecat-work"},
			Notes:    "\n\n" + card + "\n\n",
		}
	}
	openVisit := func(id string) Facts {
		return Facts{Sittings: []Sitting{{Subject: id, Status: "open"}}}
	}

	// Acceptable row: the card reaches the wire, trimmed, structure intact.
	tile := computeTile(subject("tk-rec"), fixtureNow, openVisit("tk-rec"), 0)
	if !tile.Acceptable {
		t.Fatal("precondition: a recommended formula + open un-engaged visit is acceptable")
	}
	if tile.Recommendation == nil {
		t.Fatal("an acceptable row carries its first-reaction card as recommendation")
	}
	if *tile.Recommendation != card {
		t.Errorf("recommendation is the notes, trimmed, card structure intact:\n got %q\nwant %q", *tile.Recommendation, card)
	}

	// Same notes, but no open visit → not acceptable → no card on the wire.
	if got := computeTile(subject("tk-rec"), fixtureNow, Facts{}, 0).Recommendation; got != nil {
		t.Errorf("off an acceptable row the wire carries no card: got %q", *got)
	}

	// Acceptable, but whitespace-only notes → null, never an empty string.
	empty := subject("tk-rec")
	empty.Notes = "   \n"
	if got := computeTile(empty, fixtureNow, openVisit("tk-rec"), 0).Recommendation; got != nil {
		t.Errorf("whitespace-only notes is null, not an empty recommendation: got %q", *got)
	}
}
