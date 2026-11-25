package gascity

import (
	"slices"
	"strings"
)

// A hold is a label hold:<value> that says a bead's next actor or condition is
// no worker that looks at it, so Gas City serves a bead that carries one to no
// hook, pool or route-restore sweep. The value is the pack's vocabulary, and Gas
// City reads it as no agent, role or route. The gc this city runs holds a bead
// on any value but cleared (ActiveHoldValue in internal/beadmeta/hold_labels.go,
// at zookanalytics/gascity d62873fce6). Upstream Gas City holds one on
// hold:mayor and hold:external alone (specs/tk-1tfzr71.233/gas-city-search.md).
const (
	holdPrefix = "hold:"
	// clearedValue is the value `bd set-state <id> hold=cleared` leaves when it
	// releases a hold, and hold:cleared holds nothing.
	clearedValue = "cleared"
)

// HoldPO holds work for its rig's Product Owner to place, and intake holds new
// work with it (docs/steering.md). HoldMayor is the placement hold's earlier
// spelling, which a bead held before the placement queue moved to hold:po
// carries until `gctk bead move-placement-hold` moves it, so a reader of the
// queue reads both. HoldExternal holds work whose next actor or condition is
// outside the city's stores.
const (
	HoldPO       = "hold:po"
	HoldMayor    = "hold:mayor"
	HoldExternal = "hold:external"
)

// holdValue is label's value when label is a hold, as Gas City reads one: the
// label trimmed, its hold: prefix in any case, and its value trimmed, nonempty
// and not cleared in any case. Any other label, such as hold:cleared, a hold:
// with no value or a label that only contains the word, is no hold.
func holdValue(label string) (string, bool) {
	label = strings.TrimSpace(label)
	if len(label) < len(holdPrefix) || !strings.EqualFold(label[:len(holdPrefix)], holdPrefix) {
		return "", false
	}
	value := strings.TrimSpace(label[len(holdPrefix):])
	if value == "" || strings.EqualFold(value, clearedValue) {
		return "", false
	}
	return value, true
}

// isHold reports whether label is the hold hold, a hold:<value> label: a hold
// whose value is hold's value, in any case.
func isHold(label, hold string) bool {
	v, ok := holdValue(label)
	return ok && strings.EqualFold(v, strings.TrimPrefix(hold, holdPrefix))
}

// IsDispatchHold reports whether label is a hold, whatever its value.
func IsDispatchHold(label string) bool {
	_, ok := holdValue(label)
	return ok
}

// HasDispatchHold reports whether labels carry a hold, whatever its value.
func HasDispatchHold(labels []string) bool { return slices.ContainsFunc(labels, IsDispatchHold) }

// HasHold reports whether labels carry the hold hold, a hold:<value> label, in
// any spelling Gas City reads as that hold.
func HasHold(labels []string, hold string) bool {
	return slices.ContainsFunc(labels, func(label string) bool { return isHold(label, hold) })
}

// IsPlacementHold reports whether label holds its bead for placement: HoldPO,
// or HoldMayor, its earlier spelling, in any spelling Gas City reads as either.
func IsPlacementHold(label string) bool { return isHold(label, HoldPO) || isHold(label, HoldMayor) }

// HasPlacementHold reports whether labels hold their bead for placement.
func HasPlacementHold(labels []string) bool { return slices.ContainsFunc(labels, IsPlacementHold) }

// PlacementSpellings is each label among labels that holds the bead for
// placement, as written, in order. bd removes a label only by its exact text, so
// a writer that lifts the placement hold removes each of these and no other
// hold.
func PlacementSpellings(labels []string) []string {
	var out []string
	for _, l := range labels {
		if IsPlacementHold(l) && !slices.Contains(out, l) {
			out = append(out, l)
		}
	}
	return out
}
