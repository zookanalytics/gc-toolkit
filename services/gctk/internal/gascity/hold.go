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
