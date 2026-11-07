package board

import (
	"testing"
	"time"
)

// hypothesis is the metadata epic stewardship records on an epic of its own.
var hypothesis = map[string]string{mdEpicHypothesis: "operators rule on each epic from its landed work"}

// epicRow is a live epic anchor with the given children, carrying md as its
// metadata.
func epicRow(id, title string, md map[string]string, children ...Child) Anchor {
	return Anchor{
		ID: id, Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2),
		Title: title, Metadata: md, Children: children,
	}
}

// open and closed are a parent's view of a child, by status.
func open(id string) Child   { return Child{ID: id, Status: "open"} }
func closed(id string) Child { return Child{ID: id, Status: "closed"} }

// deliveryFamily is an epic delivered through child epics, beside a top-level
// epic whose children have all closed. Under the epic: a Delivery whose Stories
// have all closed, a child epic with a hypothesis of its own whose children have
// all closed, a Delivery with a Story still in flight, and a Delivery with no
// Stories yet.
func deliveryFamily() []Anchor {
	return []Anchor{
		epicRow("tk-ep", "an epic", hypothesis, open("tk-ep.1"), open("tk-ep.2"), open("tk-ep.3"), open("tk-ep.4")),
		epicRow("tk-ep.1", "Delivery: the first step", nil, closed("tk-ep.1.1"), closed("tk-ep.1.2")),
		epicRow("tk-ep.2", "an epic of its own", hypothesis, closed("tk-ep.2.1")),
		epicRow("tk-ep.3", "Delivery: the second step", nil, closed("tk-ep.3.1"),
			Child{ID: "tk-ep.3.2", Status: "in_progress", Assignee: "polecat-live"}),
		epicRow("tk-ep.4", "Delivery: the third step", nil),
		epicRow("tk-top", "a top-level epic", nil, closed("tk-top.1")),
	}
}

// TestALandedDeliveryWaitsForItsCheckpoint is the board fixture for a landed
// Delivery: its row names the Epic Checkpoint it waits for and is owed to the
// operator, in the gate band. A top-level epic and a child epic with a
// hypothesis of its own, each with every child closed, read as they always
// have, and so does a Delivery that has not landed.
func TestALandedDeliveryWaitsForItsCheckpoint(t *testing.T) {
	b := buildBoard(deliveryFamily(), fixtureNow, false, nil, liveOwners("polecat-live"))

	cases := []struct {
		id, why         string
		sev             Severity
		owed            bool
		section         string
		needs, frontier string
		groupParent     string
	}{
		{"tk-ep.1", "a landed Delivery waits for its epic's checkpoint",
			SevElevated, true, SectionGate,
			"landed — waits for its Epic Checkpoint", "needs-review · all 2 closed · 0 open", "tk-ep"},
		{"tk-ep.2", "a child epic with a hypothesis of its own reads as before",
			SevLow, false, SectionCleanup,
			"all 1 closed — close or extend", "needs-review · all 1 closed · 0 open", "tk-ep"},
		{"tk-top", "a top-level epic reads as before",
			SevLow, false, SectionCleanup,
			"all 1 closed — close or extend", "needs-review · all 1 closed · 0 open", ""},
		{"tk-ep.3", "a Delivery with a Story in flight has not landed",
			SevNormal, false, SectionActive,
			"in flight", "needs-review · 1 open · 1 in flight", "tk-ep"},
		{"tk-ep.4", "a Delivery with no Stories has not landed",
			SevLow, false, SectionCleanup,
			"no children — decompose or assign", "needs-review · empty — no children", "tk-ep"},
	}
	for _, tc := range cases {
		tile := mustTile(t, b, tc.id)
		if tile.Severity != tc.sev || tile.Owed != tc.owed || tile.Section != tc.section {
			t.Errorf("%s (%s): severity=%s owed=%v section=%s, want %s / %v / %s",
				tc.id, tc.why, tile.Severity, tile.Owed, tile.Section, tc.sev, tc.owed, tc.section)
		}
		if tile.Needs != tc.needs || tile.Frontier != tc.frontier {
			t.Errorf("%s (%s): needs=%q frontier=%q, want %q / %q",
				tc.id, tc.why, tile.Needs, tile.Frontier, tc.needs, tc.frontier)
		}
		if tile.GroupParent != tc.groupParent {
			t.Errorf("%s (%s): group_parent=%q, want %q", tc.id, tc.why, tile.GroupParent, tc.groupParent)
		}
	}

	var queue []string
	for _, tile := range OperatorQueue(b.Tiles) {
		queue = append(queue, tile.ID)
	}
	if len(queue) != 1 || queue[0] != "tk-ep.1" {
		t.Errorf("the operator's queue holds the landed Delivery alone: %v", queue)
	}
}

// TestALandedDeliveryOutranksItsTakeaway: a sentence a sitting left on a
// Delivery was written before its last Story closed, so the checkpoint the row
// waits for outranks it as NEEDS, and the sentence stays on the wire.
func TestALandedDeliveryOutranksItsTakeaway(t *testing.T) {
	anchors := deliveryFamily()
	const said = "Stories filed and routed; nothing further needed here"
	anchors[1].Takeaway = said
	anchors[1].Metadata = map[string]string{mdTakeaway: said}

	tile := mustTile(t, buildBoard(anchors, fixtureNow, false, nil, liveOwners("polecat-live")), "tk-ep.1")
	if tile.Needs != "landed — waits for its Epic Checkpoint" || !tile.Owed || tile.Section != SectionGate {
		t.Errorf("needs=%q owed=%v section=%s, want the checkpoint, owed, in the gate band", tile.Needs, tile.Owed, tile.Section)
	}
	if tile.Takeaway == nil || *tile.Takeaway != said {
		t.Errorf("the takeaway stays on the wire: %v", tile.Takeaway)
	}
}

// TestTheCheckpointsGateNamesItsQuestionOnALandedDelivery: once a checkpoint
// sitting gates the Delivery's close, the row names the gate's question, as any
// row a human gate holds does, and stays owed.
func TestTheCheckpointsGateNamesItsQuestionOnALandedDelivery(t *testing.T) {
	const ask = "Epic Checkpoint: continue, shift or close the epic?"
	anchors := append(deliveryFamily(), gateAnchor("tk-gate", ask, "tk-ep.1"))

	tile := mustTile(t, buildBoard(anchors, fixtureNow, false, nil, liveOwners("polecat-live")), "tk-ep.1")
	if tile.Needs != ask || !tile.Owed || !tile.WorkHeld || tile.Section != SectionGate {
		t.Errorf("needs=%q owed=%v work_held=%v section=%s, want the gate's question, owed and held, in the gate band",
			tile.Needs, tile.Owed, tile.WorkHeld, tile.Section)
	}
}

// TestADeliveryUnderAClosedEpicReadsAsAnEpic: no checkpoint is coming for a
// child epic whose parent has closed, so its row reads as an epic's.
func TestADeliveryUnderAClosedEpicReadsAsAnEpic(t *testing.T) {
	gone := epicRow("tk-gone", "a closed epic", nil, open("tk-gone.1"))
	gone.ClosedAt = fixtureNow.Add(-24 * time.Hour)
	anchors := []Anchor{gone, epicRow("tk-gone.1", "Delivery: left behind", nil, closed("tk-gone.1.1"))}

	tile := mustTile(t, buildBoard(anchors, fixtureNow, false, nil, Facts{}), "tk-gone.1")
	if tile.Needs != "all 1 closed — close or extend" || tile.Owed || tile.Severity != SevLow {
		t.Errorf("needs=%q owed=%v severity=%s, want an epic's row", tile.Needs, tile.Owed, tile.Severity)
	}
}

// TestALandedDeliveryWaitsOnTheOperatorInItsParent: the epic's own roll-up
// counts a landed Delivery among the children that wait on the operator, so an
// epic whose only open child is a landed Delivery is not stranded work. A
// landed child epic with a hypothesis of its own counts as before.
func TestALandedDeliveryWaitsOnTheOperatorInItsParent(t *testing.T) {
	delivery := []Anchor{
		epicRow("tk-ep", "an epic", hypothesis, open("tk-ep.1")),
		epicRow("tk-ep.1", "Delivery: the first step", nil, closed("tk-ep.1.1")),
	}
	tile := mustTile(t, buildBoard(delivery, fixtureNow, false, nil, Facts{}), "tk-ep")
	if tile.Stranded || tile.Severity == SevHigh || len(tile.ParkedHeads) != 1 || tile.ParkedHeads[0] != "tk-ep.1" {
		t.Errorf("stranded=%v severity=%s parked_heads=%v, want the Delivery waiting on the operator",
			tile.Stranded, tile.Severity, tile.ParkedHeads)
	}
	if tile.Needs != "1 parked for the operator — release or rule on them" {
		t.Errorf("needs=%q, want the child the operator owes a ruling on", tile.Needs)
	}

	ownEpic := []Anchor{
		epicRow("tk-ep", "an epic", hypothesis, open("tk-ep.2")),
		epicRow("tk-ep.2", "an epic of its own", hypothesis, closed("tk-ep.2.1")),
	}
	tile = mustTile(t, buildBoard(ownEpic, fixtureNow, false, nil, Facts{}), "tk-ep")
	if !tile.Stranded || tile.Needs != "decomposed, idle — assign or discuss" {
		t.Errorf("stranded=%v needs=%q, want the child epic counted as before", tile.Stranded, tile.Needs)
	}
}
