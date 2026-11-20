package gascity

import (
	"slices"
	"strings"
)

// DispatchHoldLabels is Gas City's dispatch holds, the labels that say a bead's
// next actor is no worker that looks at it, so Gas City serves a bead that
// carries one to no hook, pool or route (DispatchHoldLabels in
// internal/beadmeta/hold_labels.go, at gastownhall/gascity e60ed864f3).
// Intake holds new work with hold:mayor (docs/steering.md).
func DispatchHoldLabels() []string { return []string{"hold:mayor", "hold:external"} }

// IsDispatchHold reports whether label is a dispatch hold, compared as Gas
// City's HasDispatchHold compares one: trimmed, and in any case.
func IsDispatchHold(label string) bool {
	label = strings.TrimSpace(label)
	return slices.ContainsFunc(DispatchHoldLabels(), func(hold string) bool { return strings.EqualFold(label, hold) })
}

// HasDispatchHold reports whether labels carry a dispatch hold.
func HasDispatchHold(labels []string) bool { return slices.ContainsFunc(labels, IsDispatchHold) }

// Spellings is each label among labels that reads as hold, trimmed and in any
// case, as written, in order. bd removes a label only by its exact text, so a
// writer that lifts a hold removes each spelling the bead carries.
func Spellings(labels []string, hold string) []string {
	var out []string
	for _, l := range labels {
		if strings.EqualFold(strings.TrimSpace(l), hold) && !slices.Contains(out, l) {
			out = append(out, l)
		}
	}
	return out
}
