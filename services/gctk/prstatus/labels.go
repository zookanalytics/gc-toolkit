package prstatus

import "strings"

// The labels a PR shows on GitHub: one `status:` label for where the PR
// stands, and a `held:` label for each thing that holds it. Their writer keeps
// every label under either prefix, so it takes off one whose value it did not
// derive, whether or not it names that value. The landing order and the net
// write them through the pr domain (services/gctk/pr/labels.go), and
// assets/scripts/pr-status-label.sh writes them for the old path's callers, in
// its own spelling of each label below.
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

// The colour of each family on GitHub: one for every status: label, so the
// values read as one dimension, and one for every held: label, so a hold reads
// apart from the status beside it.
const (
	statusColor = "1D76DB"
	heldColor   = "D93F0B"
)

// descriptions is what GitHub shows of each label the writer names, each
// within GitHub's 100 characters.
var descriptions = map[string]string{
	statusLabelPrefix + string(Working):        "Workflow: the city is changing the PR or readying its draft; no human input needed.",
	statusLabelPrefix + string(Merging):        "Workflow: approved, and the city is landing it; nothing known blocks the merge.",
	statusLabelPrefix + string(NeedsReview):    "Workflow: settled at the current head; awaiting a human review or re-review.",
	statusLabelPrefix + string(NeedsAttention): "Workflow: a blocker stands that the city will not clear on its own; needs a human.",
	heldLabelPrefix + string(HeldGate):         "Workflow: an open human gate holds the PR; a person clears it.",
	heldLabelPrefix + string(HeldReview):       "Workflow: review feedback the city has not answered holds the PR; a person resolves it.",
	heldLabelPrefix + string(HeldBlocked):      "Workflow: a blocker no automated actor will clear holds the PR; a person clears it.",
}

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

// Label is a label the writer names, as a repository holds it once the writer
// has made it: its name, its colour as six hex digits with no leading '#', and
// its description.
type Label struct {
	Name, Color, Description string
}

// Defined returns every label the writer names: a status: label for each live
// state, then a held: label for each held value.
func Defined() []Label {
	var out []Label
	for _, s := range liveStates {
		name := statusLabelPrefix + string(s)
		out = append(out, Label{Name: name, Color: statusColor, Description: descriptions[name]})
	}
	for _, h := range holds {
		name := heldLabelPrefix + string(h)
		out = append(out, Label{Name: name, Color: heldColor, Description: descriptions[name]})
	}
	return out
}
