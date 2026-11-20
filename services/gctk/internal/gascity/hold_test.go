package gascity

import "testing"

// A dispatch hold is hold:mayor or hold:external, trimmed and in any case, as
// Gas City's HasDispatchHold reads a label, and the human label is no hold.
func TestADispatchHoldIsGasCitysHoldLabelInAnyCase(t *testing.T) {
	for label, want := range map[string]bool{
		"hold:mayor": true, " Hold:External ": true, "HOLD:MAYOR": true,
		"hold:mayors": false, "human": false, "placement": false, "": false,
	} {
		if got := IsDispatchHold(label); got != want {
			t.Errorf("IsDispatchHold(%q) = %v, want %v", label, got, want)
		}
	}
	if !HasDispatchHold([]string{"learning", "Hold:Mayor"}) || HasDispatchHold([]string{"human", "learning"}) || HasDispatchHold(nil) {
		t.Error("HasDispatchHold misreads a bead's labels")
	}
	labels := DispatchHoldLabels()
	labels[0] = "changed"
	if DispatchHoldLabels()[0] != "hold:mayor" {
		t.Error("a caller's change to the hold labels reached the rule")
	}
}

// A hold's spellings are the labels that read as it, each as the bead carries
// it, so a lift can remove each by its exact text.
func TestAHoldsSpellingsAreTheLabelsThatReadAsIt(t *testing.T) {
	got := Spellings([]string{"learning", "hold:mayor", " Hold:Mayor", "hold:external", "hold:mayor"}, "hold:mayor")
	if len(got) != 2 || got[0] != "hold:mayor" || got[1] != " Hold:Mayor" {
		t.Fatalf("Spellings = %q, want the two spellings of hold:mayor as written", got)
	}
	if got := Spellings([]string{"learning"}, "hold:mayor"); got != nil {
		t.Fatalf("Spellings of a bead with no hold = %q, want none", got)
	}
}
