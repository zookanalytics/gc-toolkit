package lifecycle

import "testing"

func TestSelfEdgeIsLegal(t *testing.T) {
	for _, s := range States {
		if !EdgeLegal(s, s) {
			t.Errorf("self-edge %s -> %s must be legal (idempotent re-record)", s, s)
		}
	}
}

func TestEdgesReferenceDeclaredStates(t *testing.T) {
	for _, e := range Transitions {
		if !IsState(e.From) {
			t.Errorf("edge %s>%s: %q is not a declared state", e.From, e.To, e.From)
		}
		if !IsState(e.To) {
			t.Errorf("edge %s>%s: %q is not a declared state", e.From, e.To, e.To)
		}
	}
}

func TestUndeclaredEdgesAreRefused(t *testing.T) {
	// merged is terminal: nothing leaves it, which is what makes closed-implies-
	// landed hold.
	for _, to := range States {
		if to == "merged" {
			continue
		}
		if EdgeLegal("merged", to) {
			t.Errorf("merged -> %s must be illegal", to)
		}
	}
}

func TestDetachedAndClosedStatesAreDeclaredStates(t *testing.T) {
	for _, s := range append(append([]string{}, DetachedStates...), ClosedStates...) {
		if !IsState(s) {
			t.Errorf("%q is classified but not declared", s)
		}
	}
}

func TestClosedStatesAreNotDetachedStates(t *testing.T) {
	// A detached anchor rests open for the merge cadence, and a closed state
	// ends the anchor's life, so no state can be both.
	for _, c := range ClosedStates {
		if IsDetachedState(c) {
			t.Errorf("%q is both a closed state and a detached state", c)
		}
	}
}

func TestEveryNonUnanchoredStateCanBeLeft(t *testing.T) {
	// Except the closed ones: an anchor that can be entered and never left is a
	// bead the cadence can strand.
	for _, s := range States {
		if s == "unanchored" || IsClosedState(s) {
			continue
		}
		found := false
		for _, e := range Transitions {
			if e.From == s {
				found = true
				break
			}
		}
		if !found {
			t.Errorf("%q has no outgoing edge — a bead entering it is stranded", s)
		}
	}
}
