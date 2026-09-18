package board

import "testing"

// humanKid is a plain operator-routed bead that carries a board row of its own,
// so it can stand in for a child or blocker that is independently a tile.
func humanKid(id string) Anchor {
	return Anchor{
		ID: id, Title: "t " + id, Kind: "human", Source: "human",
		Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2),
		Metadata: map[string]string{"gc.routed_to": "human"},
	}
}

// epicWith is a roll-up epic naming the given open children.
func epicWith(id string, childIDs ...string) Anchor {
	kids := make([]Child, 0, len(childIDs))
	for _, c := range childIDs {
		kids = append(kids, Child{ID: c, Status: "open"})
	}
	return Anchor{
		ID: id, Title: "t " + id, Kind: "epic", Source: "epic",
		Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), Children: kids,
	}
}

func TestGroupRootFollowsParentChild(t *testing.T) {
	b := BuildBoard([]Anchor{epicWith("tk-epic", "tk-kid"), humanKid("tk-kid")},
		fixtureNow, false, nil, Facts{})
	if got := mustTile(t, b, "tk-kid").GroupRoot; got != "tk-epic" {
		t.Errorf("child climbs to its epic: GroupRoot=%q want tk-epic", got)
	}
	if got := mustTile(t, b, "tk-epic").GroupRoot; got != "tk-epic" {
		t.Errorf("a root is its own family: GroupRoot=%q want tk-epic", got)
	}
}

func TestGroupRootFollowsBlockedEdge(t *testing.T) {
	m := mergeAnchor("tk-pr", nil)
	m.WaitingOn = []string{"tk-rev"}
	rev := Anchor{ID: "tk-rev", Title: "Review branch polecat/tk-pr -> main", Kind: "review",
		Source: "review", Rig: "gc-toolkit", Prefix: "tk",
		Metadata: map[string]string{"anchor_bead": "tk-pr", "task_kind": "review"}}
	b := BuildBoard([]Anchor{m, rev}, fixtureNow, false, nil, Facts{})
	if got := mustTile(t, b, "tk-rev").GroupRoot; got != "tk-pr" {
		t.Errorf("a review child climbs the blocked edge to its anchor: GroupRoot=%q want tk-pr", got)
	}
}

func TestGroupRootBeadInTwoFamiliesPrefersParent(t *testing.T) {
	// tk-b is a child of tk-p AND a blocker of tk-q. Containment wins.
	q := epicWith("tk-q")
	q.WaitingOn = []string{"tk-b"}
	b := BuildBoard([]Anchor{epicWith("tk-p", "tk-b"), q, humanKid("tk-b")},
		fixtureNow, false, nil, Facts{})
	if got := mustTile(t, b, "tk-b").GroupRoot; got != "tk-p" {
		t.Errorf("a child that also blocks another anchor stays in its parent's family: GroupRoot=%q want tk-p", got)
	}
}

func TestGroupRootTopLevelEpicBlockerStaysItsOwnRoot(t *testing.T) {
	// tk-x heads its own family (has a tile child) AND blocks tk-y. It stays the
	// root of its own family; only a leaf climbs the blocked edge.
	y := epicWith("tk-y")
	y.WaitingOn = []string{"tk-x"}
	b := BuildBoard([]Anchor{epicWith("tk-x", "tk-xc"), y, humanKid("tk-xc")},
		fixtureNow, false, nil, Facts{})
	if got := mustTile(t, b, "tk-x").GroupRoot; got != "tk-x" {
		t.Errorf("a top-level epic that blocks another stays its own root: GroupRoot=%q want tk-x", got)
	}
	if got := mustTile(t, b, "tk-xc").GroupRoot; got != "tk-x" {
		t.Errorf("the epic's child stays in its family: GroupRoot=%q want tk-x", got)
	}
	if got := mustTile(t, b, "tk-y").GroupRoot; got != "tk-y" {
		t.Errorf("the blocked epic is its own root: GroupRoot=%q want tk-y", got)
	}
}

func TestGroupRootCrossRigEdgeLeavesTileARoot(t *testing.T) {
	// The blocker's far end has no tile on this board, so the edge is invisible.
	m := mergeAnchor("tk-pr2", nil)
	m.WaitingOn = []string{"ex-9999"}
	b := BuildBoard([]Anchor{m}, fixtureNow, false, nil, Facts{})
	if got := mustTile(t, b, "tk-pr2").GroupRoot; got != "tk-pr2" {
		t.Errorf("a dangling/cross-rig edge leaves the tile a root: GroupRoot=%q want tk-pr2", got)
	}
}

func TestGroupRootUnownedConvoyGroupsByItsEdges(t *testing.T) {
	// The walk keys on edges, not Kind, so an unowned convoy groups as the convoy
	// it is in all three positions: a family root, a child, and a blocker.
	root := Anchor{ID: "tk-uroot", Title: "unowned root", Kind: "unowned", Source: "unowned",
		Rig: "gc-toolkit", Prefix: "tk", Children: []Child{{ID: "tk-urk", Status: "open"}}}
	asChildParent := epicWith("tk-ep", "tk-uchild")
	asChild := Anchor{ID: "tk-uchild", Title: "unowned child", Kind: "unowned", Source: "unowned",
		Rig: "gc-toolkit", Prefix: "tk"}
	m := mergeAnchor("tk-prm", nil)
	m.WaitingOn = []string{"tk-ublk"}
	asBlocker := Anchor{ID: "tk-ublk", Title: "unowned blocker", Kind: "unowned", Source: "unowned",
		Rig: "gc-toolkit", Prefix: "tk"}
	b := BuildBoard([]Anchor{root, humanKid("tk-urk"), asChildParent, asChild, m, asBlocker},
		fixtureNow, false, nil, Facts{})
	if got := mustTile(t, b, "tk-urk").GroupRoot; got != "tk-uroot" {
		t.Errorf("unowned convoy as family root: child GroupRoot=%q want tk-uroot", got)
	}
	if got := mustTile(t, b, "tk-uchild").GroupRoot; got != "tk-ep" {
		t.Errorf("unowned convoy as a child climbs to its parent: GroupRoot=%q want tk-ep", got)
	}
	if got := mustTile(t, b, "tk-ublk").GroupRoot; got != "tk-prm" {
		t.Errorf("childless unowned convoy as a blocker climbs to what it blocks: GroupRoot=%q want tk-prm", got)
	}
}

func TestGroupByFamilyOrdersFamiliesAndMembers(t *testing.T) {
	// Two families. The input is rank-ordered; the family whose strongest member
	// appears first leads. Within a family, members read in SectionOrder and the
	// root is the header.
	tiles := []Tile{
		{ID: "tk-a", Section: SectionActive, GroupRoot: "tk-a"},     // root of family A (appears first)
		{ID: "tk-a2", Section: SectionReview, GroupRoot: "tk-a"},    // member, review — must lead members
		{ID: "tk-a3", Section: SectionStalled, GroupRoot: "tk-a"},   // member, stalled
		{ID: "tk-b", Section: SectionGate, GroupRoot: "tk-b"},       // root of family B
	}
	fams := GroupByFamily(tiles)
	if len(fams) != 2 {
		t.Fatalf("want 2 families, got %d", len(fams))
	}
	if fams[0].Root.ID != "tk-a" || fams[1].Root.ID != "tk-b" {
		t.Errorf("family order by first appearance: got roots %q,%q want tk-a,tk-b", fams[0].Root.ID, fams[1].Root.ID)
	}
	got := []string{fams[0].Members[0].ID, fams[0].Members[1].ID}
	if got[0] != "tk-a2" || got[1] != "tk-a3" {
		t.Errorf("members ordered by SectionOrder (review before stalled): got %v want [tk-a2 tk-a3]", got)
	}
	if len(fams[1].Members) != 0 {
		t.Errorf("a root-only family has no members, got %d", len(fams[1].Members))
	}
}
