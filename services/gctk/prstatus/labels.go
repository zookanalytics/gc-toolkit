package prstatus

import "strings"

// The labels a PR shows on GitHub, as their one writer spells them
// (assets/scripts/pr-status-label.sh): one `status:` label for where the PR
// stands, and a `held:` label for each thing that holds it. The writer keeps
// every label under either prefix, so it takes off one whose value it did not
// derive, whether or not it names that value.
const (
	statusLabelPrefix = "status: "
	heldLabelPrefix   = "held: "
)

// liveStates are the states the status: label shows, and holds the values the
// held: label shows, each in the writer's order.
var (
	liveStates = []State{Working, Merging, NeedsReview, NeedsAttention}
	holds      = []Hold{HeldGate, HeldReview, HeldBlocked}
)

// Labels returns the labels a PR that stands at s, held by held, shows: its
// status: label first, then a held: label for each held value.
func Labels(s State, held []Hold) []string {
	out := []string{statusLabelPrefix + string(s)}
	for _, h := range held {
		out = append(out, heldLabelPrefix+string(h))
	}
	return out
}

// IsLabel reports whether the writer keeps the label named: one under the
// status: or the held: prefix.
func IsLabel(name string) bool {
	return strings.HasPrefix(name, statusLabelPrefix) || strings.HasPrefix(name, heldLabelPrefix)
}

// LabelNames returns every label the writer names: a status: label for each
// live state, then a held: label for each held value.
func LabelNames() []string {
	var out []string
	for _, s := range liveStates {
		out = append(out, statusLabelPrefix+string(s))
	}
	for _, h := range holds {
		out = append(out, heldLabelPrefix+string(h))
	}
	return out
}
