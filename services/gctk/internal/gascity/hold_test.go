package gascity

import (
	"slices"
	"testing"
)

// A hold is any hold:<value> whose value is not cleared, the label and its
// value trimmed and the prefix and value in any case, as the gc this city runs
// reads one (beadmeta.ActiveHoldValue). No other label holds a bead.
func TestAHoldIsAnyHoldValueButCleared(t *testing.T) {
	for label, want := range map[string]bool{
		"hold:po": true, "hold:mayor": true, "hold:external": true, "hold:release-train": true,
		" Hold:PO ": true, "HOLD:MAYOR": true, "hold: po": true, "hold:mayors": true,
		"hold:cleared": false, "Hold:Cleared ": false, "hold: cleared": false,
		"hold:": false, "hold: ": false, "hold": false, "on-hold": false, "mpr-human-hold": false,
		"xhold:po": false, "human": false, "placement": false, "": false,
	} {
		if got := IsDispatchHold(label); got != want {
			t.Errorf("IsDispatchHold(%q) = %v, want %v", label, got, want)
		}
	}
	if !HasDispatchHold([]string{"learning", "hold:release-train"}) || HasDispatchHold([]string{"human", "hold:cleared"}) || HasDispatchHold(nil) {
		t.Error("HasDispatchHold misreads a bead's labels")
	}
	if !HasDispatchHold([]string{"hold:cleared", "hold:po"}) {
		t.Error("hold:cleared beside an active hold released the bead")
	}
}

// HasHold reads one hold by its value, in every spelling a hold reads in, and
// no other hold.
func TestHasHoldReadsOneHoldInAnySpelling(t *testing.T) {
	for _, c := range []struct {
		labels []string
		hold   string
		want   bool
	}{
		{[]string{"learning", " Hold:External "}, HoldExternal, true},
		{[]string{"hold: external"}, HoldExternal, true},
		{[]string{"hold:po"}, HoldExternal, false},
		{[]string{"hold:external-later", "xhold:external"}, HoldExternal, false},
		{nil, HoldExternal, false},
	} {
		if got := HasHold(c.labels, c.hold); got != c.want {
			t.Errorf("HasHold(%q, %q) = %v, want %v", c.labels, c.hold, got, c.want)
		}
	}
}

// The placement hold is hold:po or its earlier spelling hold:mayor, in any
// spelling a hold reads in, and no other hold.
func TestThePlacementHoldIsHoldPOOrHoldMayor(t *testing.T) {
	for label, want := range map[string]bool{
		"hold:po": true, " Hold:PO ": true, "hold: po": true, "hold:mayor": true, "Hold:Mayor": true,
		"hold:external": false, "hold:release-train": false, "hold:cleared": false, "hold:pos": false,
		"hold:": false, "po": false, "mayor": false,
	} {
		if got := IsPlacementHold(label); got != want {
			t.Errorf("IsPlacementHold(%q) = %v, want %v", label, got, want)
		}
	}
	if !HasPlacementHold([]string{"learning", "hold:mayor"}) || !HasPlacementHold([]string{"hold:po"}) ||
		HasPlacementHold([]string{"hold:external", "hold:cleared"}) || HasPlacementHold(nil) {
		t.Error("HasPlacementHold misreads a bead's labels")
	}
}

// The placement spellings are the labels that read as the placement hold, each
// as the bead carries it, so a lift removes each by its exact text and leaves
// every other hold on.
func TestThePlacementSpellingsAreTheLabelsThatReadAsIt(t *testing.T) {
	got := PlacementSpellings([]string{"learning", "hold:mayor", " Hold:PO", "hold:external", "hold:po", "hold:mayor", "hold:cleared"})
	if want := []string{"hold:mayor", " Hold:PO", "hold:po"}; !slices.Equal(got, want) {
		t.Fatalf("PlacementSpellings = %q, want %q", got, want)
	}
	if got := PlacementSpellings([]string{"learning", "hold:external"}); got != nil {
		t.Fatalf("PlacementSpellings of a bead with no placement hold = %q, want none", got)
	}
}
