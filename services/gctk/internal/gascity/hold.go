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
func DispatchHoldLabels() []string { return []string{HoldMayor, HoldExternal} }

// HoldMayor holds work for the Product Owner's placement, and HoldExternal holds
// work whose next actor is outside the city's stores.
const (
	HoldMayor    = "hold:mayor"
	HoldExternal = "hold:external"
)

// HasHold reports whether labels carry hold, each label compared as Gas City's
// HasDispatchHold compares one: trimmed, and in any case.
func HasHold(labels []string, hold string) bool {
	return slices.ContainsFunc(labels, func(label string) bool { return isHold(label, hold) })
}

func isHold(label, hold string) bool { return strings.EqualFold(strings.TrimSpace(label), hold) }

// IsDispatchHold reports whether label is a dispatch hold, compared as Gas
// City's HasDispatchHold compares one: trimmed, and in any case.
func IsDispatchHold(label string) bool {
	return slices.ContainsFunc(DispatchHoldLabels(), func(hold string) bool { return isHold(label, hold) })
}

// HasDispatchHold reports whether labels carry a dispatch hold.
func HasDispatchHold(labels []string) bool { return slices.ContainsFunc(labels, IsDispatchHold) }

// HumanLabel is bd's label for a bead that waits on a person, the label `bd
// human list` lists beads by. It is no dispatch hold. Gas City's routed,
// unassigned dispatch serves no bead that carries it, whether the route names a
// pool or an agent, while Gas City's assignee-scoped tiers still serve one
// (HumanLabel in internal/beadmeta/hold_labels.go and
// PoolDemandServeRulesForQuery in internal/config/workquery.go, at
// gastownhall/gascity 17d7d77ce29c).
const HumanLabel = "human"

// IsHumanLabel reports whether label is the human label, compared as Gas City's
// HasHumanLabel compares one: trimmed, and in its exact case, so Gas City serves
// a bead labeled "Human" as ordinary work.
func IsHumanLabel(label string) bool { return strings.TrimSpace(label) == HumanLabel }

// HasHumanLabel reports whether labels carry the human label.
func HasHumanLabel(labels []string) bool { return slices.ContainsFunc(labels, IsHumanLabel) }

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
