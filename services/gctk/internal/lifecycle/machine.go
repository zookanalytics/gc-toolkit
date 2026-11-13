// Package lifecycle holds the anchor lifecycle state machine.
//
// lifecycle/lifecycle.toml remains the human- and doctor-readable declaration.
// This file is its one executable copy, and `gctk lifecycle --dump-machine`
// prints it for the drift test in lifecycle.test.sh to compare the TOML against.
package lifecycle

// Edge is one declared transition.
type Edge struct {
	From string
	To   string
}

// ExitSet is one write that leaving a state makes: a transition from State into
// another open state sets Key to Value in the same atomic update.
type ExitSet struct {
	State string
	Key   string
	Value string
}

// States, DetachedStates and ClosedStates are ordered as lifecycle.toml declares
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

	// ExitSets are the writes leaving a state makes, in lifecycle.toml's
	// exit_sets order. A transition from a set's State into another open state
	// writes its Key=Value in the same atomic update, unless the caller writes
	// that key itself. A transition into a closed state writes none of them.
	ExitSets = []ExitSet{
		// The rank of an anchor's PR-finishing work is approved only while the
		// anchor rests in pull_request, so the record of the rank that work
		// settled at goes unsettled when the anchor leaves it.
		{State: "pull_request", Key: "pr_finishing_settled", Value: "unsettled"},
		// The approval the rank reads counts only at the PR head pr-facts.sh
		// last read, so that head is cleared when the anchor leaves, and an
		// anchor that returns counts no approval until its PR is read again.
		{State: "pull_request", Key: "pr_head_oid", Value: ""},
	}

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

// TakeawayMax caps a takeaway in CODEPOINTS. The board spends gc.takeaway as a
// row's NEEDS cell — one line, read at a glance — so the two writers of that
// cell cap it identically: assets/scripts/gc-helm.sh carries TAKEAWAY_MAX, and
// `gctk lifecycle --dump-machine` prints this one for lifecycle.test.sh to hold
// against it.
const TakeawayMax = 140

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
