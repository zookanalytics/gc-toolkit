package board

import (
	"fmt"
	"strings"
	"testing"
)

// phaseLeaf is a childless tile whose per-bead phase the test drives directly:
// needs-review by default, needs-attention with a merge hold, and working when a
// live workflow stands over it (wired through workingFacts).
func phaseLeaf(id string, md map[string]string) Anchor {
	return Anchor{
		ID: id, Title: "t " + id, Kind: "human", Source: "human",
		Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), Metadata: md,
	}
}

// workingFacts marks each id as covered by a live workflow, so beadPhase reads
// it Working through [Facts.anchorInFlight].
func workingFacts(ids ...string) Facts {
	inflight := map[string][]string{}
	for _, id := range ids {
		inflight[id] = []string{"sess-live"}
	}
	return Facts{Inflight: inflight, OwnerState: map[string]string{"sess-live": "active"}}
}

// TestAggregatePhaseUpParentChain is the precedence golden case: a parent's
// rolled-up tri-state is working while ANY live child is, needs-attention only
// when EVERY live child is, and needs-review otherwise. The leaves keep their
// own per-bead phase; only the parent rolls up.
func TestAggregatePhaseUpParentChain(t *testing.T) {
	const (
		W = PhaseWorking
		R = PhaseNeedsReview
		A = PhaseNeedsAttention
	)
	cases := []struct {
		name     string
		children []string
		want     string
	}{
		{"any working wins", []string{W, R}, W},
		{"working dominates attention too", []string{W, A}, W},
		{"all working", []string{W, W}, W},
		{"all needs-review", []string{R, R}, R},
		{"all needs-attention is unable to move", []string{A, A}, A},
		{"a review among attention is not all-stuck", []string{R, A}, R},
		{"lone working child", []string{W}, W},
		{"lone attention child", []string{A}, A},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			anchors := make([]Anchor, 0, len(c.children)+1)
			childIDs := make([]string, 0, len(c.children))
			working := make([]string, 0)
			for i, ph := range c.children {
				id := fmt.Sprintf("tk-kid%d", i)
				childIDs = append(childIDs, id)
				switch ph {
				case W:
					anchors = append(anchors, phaseLeaf(id, nil))
					working = append(working, id)
				case A:
					anchors = append(anchors, phaseLeaf(id, map[string]string{mdMergeHold: "true"}))
				default:
					anchors = append(anchors, phaseLeaf(id, nil))
				}
			}
			anchors = append(anchors, epicWith("tk-epic", childIDs...))
			b := BuildBoard(anchors, fixtureNow, false, nil, workingFacts(working...))

			for i, ph := range c.children {
				if got := mustTile(t, b, childIDs[i]).Phase; got != ph {
					t.Fatalf("child %s phase=%q want %q — test setup does not produce the intended leaf state", childIDs[i], got, ph)
				}
			}
			if got := mustTile(t, b, "tk-epic").Phase; got != c.want {
				t.Errorf("epic rolled-up phase=%q want %q", got, c.want)
			}
		})
	}
}

// TestAggregatePhaseIsMultiLevel climbs more than one level: a sub-epic rolls up
// from its own children, and the grandparent aggregates the sub-epic's
// rolled-up state, not the sub-epic's own phase.
func TestAggregatePhaseIsMultiLevel(t *testing.T) {
	// tk-top -> tk-sub -> tk-w (working) ; tk-top -> tk-r (needs-review).
	anchors := []Anchor{
		phaseLeaf("tk-w", nil),
		phaseLeaf("tk-r", nil),
		epicWith("tk-sub", "tk-w"),
		epicWith("tk-top", "tk-sub", "tk-r"),
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, workingFacts("tk-w"))
	if got := mustTile(t, b, "tk-sub").Phase; got != PhaseWorking {
		t.Errorf("sub-epic over a working child rolls up to working: %q", got)
	}
	if got := mustTile(t, b, "tk-top").Phase; got != PhaseWorking {
		t.Errorf("grandparent sees the sub-epic's rolled-up working: %q", got)
	}
}

// TestAggregatePhaseNeedsAttentionPropagates is the same climb for the
// unable-to-move end: a sub-epic whose children all need attention rolls up to
// needs-attention, and a grandparent whose only child is that sub-epic inherits
// it.
func TestAggregatePhaseNeedsAttentionPropagates(t *testing.T) {
	anchors := []Anchor{
		phaseLeaf("tk-a1", map[string]string{mdMergeHold: "true"}),
		phaseLeaf("tk-a2", map[string]string{mdMergeHold: "true"}),
		epicWith("tk-sub", "tk-a1", "tk-a2"),
		epicWith("tk-top", "tk-sub"),
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})
	if got := mustTile(t, b, "tk-sub").Phase; got != PhaseNeedsAttention {
		t.Errorf("sub-epic whose children all need attention is needs-attention: %q", got)
	}
	if got := mustTile(t, b, "tk-top").Phase; got != PhaseNeedsAttention {
		t.Errorf("grandparent inherits the sub-epic's needs-attention: %q", got)
	}
}

// TestAggregatePhaseClosedChildren proves a closed child (no live tri-state)
// contributes nothing, and a parent whose children have all closed reads off its
// own phase again.
func TestAggregatePhaseClosedChildren(t *testing.T) {
	closed := phaseLeaf("tk-done", nil)
	closed.ClosedAt = daysAgo(1)
	// One live working child beside a closed one: the epic rolls up from the live.
	live := []Anchor{
		phaseLeaf("tk-w", nil),
		closed,
		epicWith("tk-mixed", "tk-w", "tk-done"),
	}
	b := BuildBoard(live, fixtureNow, false, nil, workingFacts("tk-w"))
	if got := mustTile(t, b, "tk-done").Phase; got != "" {
		t.Fatalf("a closed child carries no live phase: %q", got)
	}
	if got := mustTile(t, b, "tk-mixed").Phase; got != PhaseWorking {
		t.Errorf("the epic rolls up from its live child, ignoring the closed one: %q", got)
	}

	// Every child closed: the epic falls back to its own per-bead phase.
	otherClosed := phaseLeaf("tk-done2", nil)
	otherClosed.ClosedAt = daysAgo(1)
	allClosed := []Anchor{
		closed,
		otherClosed,
		epicWith("tk-drained", "tk-done", "tk-done2"),
	}
	b = BuildBoard(allClosed, fixtureNow, false, nil, Facts{})
	if got := mustTile(t, b, "tk-drained").Phase; got != PhaseNeedsReview {
		t.Errorf("an epic whose children have all closed keeps its own phase: %q", got)
	}
}

// TestAggregatedFrontierSpeaksRolledUpPhase proves the frontier leads with the
// rolled-up phase, not the parent's own — the two cannot disagree.
func TestAggregatedFrontierSpeaksRolledUpPhase(t *testing.T) {
	anchors := []Anchor{
		phaseLeaf("tk-w", nil),
		epicWith("tk-epic", "tk-w"),
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, workingFacts("tk-w"))
	epic := mustTile(t, b, "tk-epic")
	if epic.Phase != PhaseWorking {
		t.Fatalf("epic phase=%q want working", epic.Phase)
	}
	if !strings.HasPrefix(epic.Frontier, "working · ") {
		t.Errorf("frontier leads with the rolled-up phase: %q", epic.Frontier)
	}
	if strings.HasPrefix(epic.Frontier, string(PhaseNeedsReview)) {
		t.Errorf("frontier must not speak the epic's own phase: %q", epic.Frontier)
	}
}

// TestAggregatePhaseLeavesMergeAnchorOnItsOwnPhase proves the roll-up climbs the
// parent-child containment edge only. A PR's review/rework children hang off it
// by a blocked/anchor_bead edge, so they group under it but do not fold into its
// phase: the merge anchor keeps the PR round-trip phase it derives for itself.
func TestAggregatePhaseLeavesMergeAnchorOnItsOwnPhase(t *testing.T) {
	m := mergeAnchor("tk-pr", map[string]string{mdMergeHold: "true"}) // needs-attention on its own
	m.WaitingOn = []string{"tk-rev"}
	rev := Anchor{ID: "tk-rev", Title: "Review branch polecat/tk-pr -> main", Kind: "review",
		Source: "review", Rig: "gc-toolkit", Prefix: "tk",
		Metadata: map[string]string{mdAnchorBead: "tk-pr", "task_kind": "review"}}
	b := BuildBoard([]Anchor{m, rev}, fixtureNow, false, nil, Facts{})

	if got := mustTile(t, b, "tk-rev").GroupRoot; got != "tk-pr" {
		t.Fatalf("the review climbs the blocked edge to its anchor (test premise): GroupRoot=%q", got)
	}
	if got := mustTile(t, b, "tk-pr").Phase; got != PhaseNeedsAttention {
		t.Errorf("a merge anchor keeps its own phase, not a roll-up of its review child: %q", got)
	}
}

// TestMergeAnchorWithParentChildChildDivergesPhaseFromPRPhase is the two-axis
// case the leaf test above does not reach: a merge anchor that ALSO has a
// parent-child child tile. Its PRPhase stays the PR round-trip value it derives
// for itself, never rolled up; its Phase takes the child's rolled-up state. The
// two axes are free to disagree here, by design.
func TestMergeAnchorWithParentChildChildDivergesPhaseFromPRPhase(t *testing.T) {
	kid := phaseLeaf("tk-kid", nil)                                   // working, via workingFacts below
	m := mergeAnchor("tk-pr", map[string]string{mdMergeHold: "true"}) // its own PR phase: needs-attention
	m.Children = []Child{{ID: "tk-kid", Status: "open"}}              // a real parent-child child
	b := BuildBoard([]Anchor{m, kid}, fixtureNow, false, nil, workingFacts("tk-kid"))

	tile := mustTile(t, b, "tk-pr")
	if got := tile.PRPhase; got != PhaseNeedsAttention {
		t.Errorf("PRPhase keeps the PR round-trip value, unaggregated: %q want needs-attention", got)
	}
	if got := tile.Phase; got != PhaseWorking {
		t.Errorf("Phase takes the parent-child child's rolled-up state: %q want working", got)
	}
	if tile.Phase == tile.PRPhase {
		t.Errorf("the two axes must be free to diverge on a merge anchor with a parent-child child; both read %q", tile.Phase)
	}
}

// TestBlockedMergeAnchorWithParentChildChildStaysNeedsAttention is the blocked
// counterpart to the divergence case above, and the one place the two axes
// cannot disagree. When the machine calls a merge anchor blocked, classifyPhases
// lifts BOTH axes to needs-attention; the roll-up must honor that, not overwrite
// Phase with a working parent-child child. Otherwise the frontier would lead
// "working" on a row whose PR chip says the merge is blocked and owed by a
// person.
func TestBlockedMergeAnchorWithParentChildChildStaysNeedsAttention(t *testing.T) {
	kid := phaseLeaf("tk-kid", nil) // working, via workingFacts below
	m := mergeAnchor("tk-pr", map[string]string{
		"pr.machine": dated(MachineBlocked, headLive, fixtureNow),
	})
	m.Children = []Child{{ID: "tk-kid", Status: "open"}} // a real parent-child child
	b := BuildBoard([]Anchor{m, kid}, fixtureNow, false, nil, workingFacts("tk-kid"))

	if got := mustTile(t, b, "tk-kid").Phase; got != PhaseWorking {
		t.Fatalf("child phase=%q want working — test setup does not produce the intended leaf state", got)
	}
	tile := mustTile(t, b, "tk-pr")
	if got := tile.PRMachine; got != MachineBlocked {
		t.Fatalf("test premise: a blocked machine verdict, got PRMachine=%q", got)
	}
	if got := tile.PRPhase; got != PhaseNeedsAttention {
		t.Errorf("a blocked PR surfaces as needs-attention on the PR axis: %q", got)
	}
	if got := tile.Phase; got != PhaseNeedsAttention {
		t.Errorf("the roll-up must not overwrite the blocked lift with a working child: Phase=%q want needs-attention", got)
	}
	if tile.Phase != tile.PRPhase {
		t.Errorf("a blocked machine verdict holds both axes together: Phase=%q PRPhase=%q", tile.Phase, tile.PRPhase)
	}
	if !strings.HasPrefix(tile.Frontier, PhaseNeedsAttention+" · ") {
		t.Errorf("the frontier speaks the held phase, not a working child's: %q", tile.Frontier)
	}
	if strings.HasPrefix(tile.Frontier, PhaseWorking+" · ") {
		t.Errorf("the frontier must not lead working on a blocked row: %q", tile.Frontier)
	}
}

// TestAggregatePhaseIgnoresNonTileChildren keeps the roll-up scoped to child
// TILES: a roll-up epic whose children are counts, not separate board rows, has
// no child tiles and so keeps its own per-bead phase. This is the shape every
// pre-existing epic test uses, which is why they are behavior-preserved.
func TestAggregatePhaseIgnoresNonTileChildren(t *testing.T) {
	b := BuildBoard([]Anchor{epicWith("tk-epic", "tk-a", "tk-b")}, fixtureNow, false, nil, Facts{})
	if got := mustTile(t, b, "tk-epic").Phase; got != PhaseNeedsReview {
		t.Errorf("an epic with only roll-up (non-tile) children keeps its own phase: %q", got)
	}
}
