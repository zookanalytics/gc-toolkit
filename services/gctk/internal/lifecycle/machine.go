// Package lifecycle holds the anchor lifecycle state machine.
//
// lifecycle/lifecycle.toml remains the human- and doctor-readable declaration.
// This file is the executable copy, and it is the only one: the shell constants
// that assets/scripts/lifecycle.sh used to mirror are gone from the port path,
// and `gctk lifecycle --dump-machine` is what the drift test compares the TOML
// against.
package lifecycle

// Edge is one declared transition.
type Edge struct {
	From string
	To   string
}

// States, HumanStates and ClosedStates are ordered as lifecycle.toml declares
// them; --dump-machine prints them in this order, so the drift test compares
// sequences rather than sets.
var (
	States = []string{
		"unanchored",
		"pre_open_gate",
		"pull_request",
		"merged",
		"abandoned",
		"retargeted",
		"blocked",
		"refused_false_completion",
	}

	// HumanStates also route the bead to a human: a transition into one stamps
	// gc.routed_to=human in the same atomic update unless the caller named a
	// route of its own.
	HumanStates = []string{"abandoned", "retargeted", "blocked", "refused_false_completion"}

	// DetachedStates are driven by the merge cadence and offered by no queue: a
	// transition into one clears gc.routed_to in the same atomic update. A pool
	// route here is demand for work already in the merge queue, and the claim it
	// invites moves the anchor out of --status=open, where merge.sh and
	// pr-facts.sh both stop seeing it.
	DetachedStates = []string{"pre_open_gate", "pull_request"}

	// ClosedStates are the states whose legal status is closed. The pairing is
	// enforced both ways, because a closed bead on a non-terminal merge_result
	// is invisible to every open-bead consumer (component model I5).
	ClosedStates = []string{"merged"}

	// ParkRoute is the one route value no pool claims, so it parks the bead for
	// a person. A detached state may rest on it — signoff.sh routes a
	// round-capped anchor there — and a transition that finds it leaves it
	// alone rather than retracting a bead a person still owns.
	ParkRoute = "human"

	Transitions = []Edge{
		{"unanchored", "pre_open_gate"},
		{"unanchored", "pull_request"},
		{"unanchored", "merged"},
		{"unanchored", "blocked"},
		{"unanchored", "refused_false_completion"},
		{"pre_open_gate", "pull_request"},
		{"pre_open_gate", "unanchored"},
		{"pull_request", "merged"},
		{"pull_request", "abandoned"},
		{"pull_request", "retargeted"},
		{"pull_request", "unanchored"},
		{"abandoned", "unanchored"},
		{"retargeted", "pull_request"},
		{"retargeted", "unanchored"},
		{"blocked", "unanchored"},
		{"refused_false_completion", "unanchored"},
	}
)

func contains(haystack []string, needle string) bool {
	for _, s := range haystack {
		if s == needle {
			return true
		}
	}
	return false
}

// IsState reports whether name is a declared state.
func IsState(name string) bool { return contains(States, name) }

// IsHumanState reports whether a transition into name also routes to a human.
func IsHumanState(name string) bool { return contains(HumanStates, name) }

// IsDetachedState reports whether a transition into name also clears the route.
func IsDetachedState(name string) bool { return contains(DetachedStates, name) }

// IsClosedState reports whether name's legal status is closed.
func IsClosedState(name string) bool { return contains(ClosedStates, name) }

// EdgeLegal reports whether from -> to is declared. A self-edge is always
// legal: re-recording the state a bead already holds is idempotent.
func EdgeLegal(from, to string) bool {
	if from == to {
		return true
	}
	for _, e := range Transitions {
		if e.From == from && e.To == to {
			return true
		}
	}
	return false
}
