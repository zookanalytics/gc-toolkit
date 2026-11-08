package board

import (
	"maps"
	"reflect"
	"testing"
	"time"
)

// ruledAs is md with the epic's latest ruling recorded on it, as epic
// stewardship records one (docs/epic-stewardship.md, "Recording a ruling").
func ruledAs(md map[string]string, ruling string) map[string]string {
	out := maps.Clone(md)
	if out == nil {
		out = map[string]string{}
	}
	out[mdEpicRuling] = ruling
	return out
}

// firstDraftFamily is one epic of each kind the first draft tells apart: an epic
// nobody has ruled on, with a Delivery under it, beside an epic ruled continue,
// one ruled shift and one with no hypothesis. A closed epic that was never
// ruled on, and a decision that happens to carry the hypothesis key, stand
// beside them.
func firstDraftFamily() []Anchor {
	done := epicRow("tk-done", "a closed epic never ruled on", hypothesis, closed("tk-done.1"))
	done.ClosedAt = fixtureNow.Add(-time.Hour)
	return []Anchor{
		epicRow("tk-draft", "an epic nobody has ruled on", hypothesis, open("tk-draft.1"), open("tk-del")),
		epicRow("tk-del", "Delivery: the first step", nil, open("tk-del.1")),
		epicRow("tk-cont", "an epic ruled continue", ruledAs(hypothesis, "continue"), open("tk-cont.1")),
		epicRow("tk-shift", "an epic ruled shift", ruledAs(hypothesis, "shift"), open("tk-shift.1")),
		epicRow("tk-bare", "an epic with no hypothesis", nil, open("tk-bare.1")),
		done,
		{
			ID: "tk-dec", Kind: "decision", Source: "decision", Rig: "gc-toolkit", Prefix: "tk",
			Priority: ptr(2), Title: "a decision carrying the key", Metadata: hypothesis,
		},
	}
}

// TestAFirstDraftHypothesisShowsOnItsEpicsRow: an epic that carries a
// hypothesis and no ruling says on its row that the hypothesis is a first
// draft. Any ruling ends the draft. A Delivery and an epic with no hypothesis
// have no sentence to draft, a closed epic waits for no ruling, and a row that
// is not an epic is not one whatever metadata it carries.
func TestAFirstDraftHypothesisShowsOnItsEpicsRow(t *testing.T) {
	b := buildBoard(firstDraftFamily(), fixtureNow, false, nil, Facts{})

	for _, c := range []struct {
		id, why string
		want    bool
	}{
		{"tk-draft", "an epic with a hypothesis and no ruling is a first draft", true},
		{"tk-del", "a Delivery carries no hypothesis", false},
		{"tk-cont", "a continue ruling ends the draft", false},
		{"tk-shift", "a shift ruling ends it too", false},
		{"tk-bare", "an epic with no hypothesis has no draft", false},
		{"tk-done", "a closed epic waits for no ruling", false},
		{"tk-dec", "a decision is not an epic", false},
	} {
		if got := mustTile(t, b, c.id).HypothesisFirstDraft; got != c.want {
			t.Errorf("%s (%s): hypothesis_first_draft=%v, want %v", c.id, c.why, got, c.want)
		}
	}
}

// TestAFirstDraftAsksNothingOfTheOperator: the draft rides beside what the row
// already says. An epic whose work is in flight, one whose work has all closed,
// one routed to the operator and one over a landed Delivery each read the same
// tile with a first draft as with a continue ruling, apart from the draft
// itself: the same band, owed state, section, needs, frontier and rank, and the
// board orders its rows the same.
func TestAFirstDraftAsksNothingOfTheOperator(t *testing.T) {
	routed := maps.Clone(hypothesis)
	routed[mdRoutedTo] = routedHuman
	family := func(ruling string) []Anchor {
		md := func(m map[string]string) map[string]string {
			if ruling == "" {
				return m
			}
			return ruledAs(m, ruling)
		}
		return []Anchor{
			epicRow("tk-live", "an epic with work in flight", md(hypothesis),
				Child{ID: "tk-live.1", Status: "in_progress", Assignee: "polecat-live"}),
			epicRow("tk-spent", "an epic whose work has all closed", md(hypothesis), closed("tk-spent.1")),
			epicRow("tk-asks", "an epic routed to the operator", md(routed), open("tk-asks.1")),
			epicRow("tk-land", "an epic over a landed Delivery", md(hypothesis), open("tk-land.1")),
			epicRow("tk-land.1", "Delivery: the first step", nil, closed("tk-land.1.1")),
		}
	}
	draft := buildBoard(family(""), fixtureNow, false, nil, liveOwners("polecat-live"))
	ruled := buildBoard(family("continue"), fixtureNow, false, nil, liveOwners("polecat-live"))

	if len(draft.Tiles) != len(ruled.Tiles) {
		t.Fatalf("the draft changed the rows: %d with it, %d without", len(draft.Tiles), len(ruled.Tiles))
	}
	drafts := 0
	for i := range draft.Tiles {
		d, r := draft.Tiles[i], ruled.Tiles[i]
		if d.ID != r.ID {
			t.Fatalf("row %d: %s with the draft, %s without it, so the draft reordered the board", i, d.ID, r.ID)
		}
		if d.HypothesisFirstDraft {
			drafts++
		}
		if r.HypothesisFirstDraft {
			t.Errorf("%s: a continue ruling still reads as a first draft", r.ID)
		}
		d.HypothesisFirstDraft = false
		if !reflect.DeepEqual(d, r) {
			t.Errorf("%s: the draft changed the row beyond itself:\n with draft: %+v\n ruled:      %+v", d.ID, d, r)
		}
	}
	if drafts != 4 {
		t.Errorf("%d rows read as a first draft, want the four epics carrying a hypothesis", drafts)
	}
	if asks := mustTile(t, draft, "tk-asks"); !asks.Owed || asks.Section != SectionGate {
		t.Errorf("the routed epic is the operator's move with or without a draft: owed=%v section=%s", asks.Owed, asks.Section)
	}
	if land := mustTile(t, draft, "tk-land.1"); !land.Owed || land.HypothesisFirstDraft {
		t.Errorf("the landed Delivery is owed for its checkpoint and shows no draft: owed=%v draft=%v", land.Owed, land.HypothesisFirstDraft)
	}
}
