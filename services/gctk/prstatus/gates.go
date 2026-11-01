package prstatus

import (
	"errors"
	"strings"
)

// Blocker is the far end of one `blocks` edge, in the fields [HoldingGates]
// reads of it. A caller fills it from its own read of the store, and passes the
// status and the issue type as they read, in any case.
type Blocker struct {
	ID        string
	Title     string
	Status    string
	IssueType string
	AwaitType string
}

// open reports whether the blocker still blocks: any status but closed, a
// blocker with no status included. It is the rule a human gate is read open by
// (HUMAN_GATE_JQ in assets/scripts/bd-lib.sh) and the one the label's blocker
// read applies.
func (b Blocker) open() bool { return !strings.EqualFold(b.Status, "closed") }

// IsHumanGate reports whether a bead of this issue type and await type is a
// human gate: Gas City's native bead for a wait a person must clear. It is the
// one reader rule bd_human_gates applies in assets/scripts/bd-lib.sh.
func IsHumanGate(issueType, awaitType string) bool {
	return strings.EqualFold(issueType, "gate") && awaitType == "human"
}

// ReadBlockers answers the `blocks` edges of each bead it is given: for each id,
// that bead's blockers, open and closed, and no edge of another type. It returns
// an error when any of those beads did not read, because a bead whose edges
// nothing read proves nothing about what holds it.
type ReadBlockers func(ids []string) (map[string][]Blocker, error)

// walkDepth and walkBeads bound one walk. A walk reads once per level, so
// walkDepth bounds its reads, and walkBeads, counted per root, bounds what those
// reads name. specs/tk-1tfzr71.34/gas-city-search.md measures both against the
// stores' `blocks` graphs.
const (
	walkDepth = 16
	walkBeads = 256
)

// ErrWalkBound reports a walk that ran past its bound, which leaves the gates
// past it unread. A caller treats it as a read that did not resolve.
var ErrWalkBound = errors.New("the blocks edges run past the walk's bound")

// HoldingGates returns, for each root, the open human gates that hold it: every
// open human gate reached from the root through `blocks` edges whose blocker is
// open, in the order the walk reaches them, nearest first. A PR's anchor is held
// by a gate on a rework it waits on as it is by a gate on itself.
//
// It reads only the edges read returns, so a conversation, which tracks its bead
// and blocks nothing, never counts, and no metadata key decides anything. An edge
// onto a closed blocker is not followed, so a gate behind it holds nothing. A
// gate that holds the root but waits on another bead is followed too, so what it
// waits on is named beside it.
//
// One walk serves every root and reads each bead once, however many edges reach
// it, so a cycle ends and a caller holding many anchors pays per level rather
// than per anchor. It returns nothing and the error from a read that fails, and
// [ErrWalkBound] past its bound, because the gates past either are unknown.
//
// This is the one reader of the human gates that hold a bead. [Facts.OpenHumanGate]
// is whether it finds any, so the `held: gate` label and the helm board's PR row
// read it, and `gctk pr-status gates` is how gc-helm.sh engage lists the gates
// to offer.
func HoldingGates(roots []string, read ReadBlockers) (map[string][]Blocker, error) {
	edges := make(map[string][]Blocker)
	seen := make(map[string]bool, len(roots))
	var level []string
	for _, r := range roots {
		if !seen[r] {
			seen[r] = true
			level = append(level, r)
		}
	}
	for depth := 0; len(level) > 0; depth++ {
		if depth == walkDepth || len(seen) > walkBeads*len(roots) {
			return nil, ErrWalkBound
		}
		rows, err := read(level)
		if err != nil {
			return nil, err
		}
		var next []string
		for _, id := range level {
			edges[id] = rows[id]
			for _, b := range rows[id] {
				if b.open() && !seen[b.ID] {
					seen[b.ID] = true
					next = append(next, b.ID)
				}
			}
		}
		level = next
	}
	gates := make(map[string][]Blocker, len(roots))
	for _, r := range roots {
		gates[r] = reachedGates(r, edges)
	}
	return gates, nil
}

// reachedGates walks the edges one read gathered from root, level by level, and
// keeps each open human gate once.
func reachedGates(root string, edges map[string][]Blocker) []Blocker {
	var gates []Blocker
	seen := map[string]bool{root: true}
	for queue := []string{root}; len(queue) > 0; queue = queue[1:] {
		for _, b := range edges[queue[0]] {
			if !b.open() || seen[b.ID] {
				continue
			}
			seen[b.ID] = true
			queue = append(queue, b.ID)
			if IsHumanGate(b.IssueType, b.AwaitType) {
				gates = append(gates, b)
			}
		}
	}
	return gates
}
