package prstatus

import (
	"errors"
	"fmt"
	"slices"
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

// walkDepth and walkBeads bound each root's walk, the same whatever else the call
// walks. A walk reads once per level, so walkDepth bounds its reads, and walkBeads
// bounds what those reads name. specs/tk-1tfzr71.34/gas-city-search.md measures
// both against the stores' `blocks` graphs.
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
// Each root walks for itself and the walks share their reads: one read per level
// names the beads no walk has read yet, and each bead is read once, however many
// edges reach it. So a cycle ends, a caller holding many anchors pays per level
// rather than per anchor, and a root's answer is the same alone or beside others.
//
// A root whose walk runs past its bound has no answer, because the gates past it
// are unknown: the map leaves it out, and the error wraps [ErrWalkBound] and names
// it, while the other roots still answer. A read that fails returns nothing and
// its error, because a bead no read reached proves nothing about any root.
//
// This is the one reader of the human gates that hold a bead. [Facts.OpenHumanGate]
// is whether it finds any, so the `held: gate` label and the helm board's PR row
// read it, and `gctk pr-status gates` is how gc-helm.sh engage lists the gates
// to offer.
func HoldingGates(roots []string, read ReadBlockers) (map[string][]Blocker, error) {
	var walks []*gateWalk
	named := make(map[string]bool, len(roots))
	for _, r := range roots {
		if !named[r] {
			named[r] = true
			walks = append(walks, &gateWalk{root: r, seen: map[string]bool{r: true}, level: []string{r}})
		}
	}
	gates := make(map[string][]Blocker, len(walks))
	edges := make(map[string][]Blocker)
	var past []string
	for depth := 0; len(walks) > 0; depth++ {
		var unread []string
		walks = slices.DeleteFunc(walks, func(w *gateWalk) bool {
			if depth == walkDepth || len(w.seen) > walkBeads {
				past = append(past, w.root)
				return true
			}
			for _, id := range w.level {
				if _, ok := edges[id]; !ok {
					edges[id] = nil
					unread = append(unread, id)
				}
			}
			return false
		})
		if len(unread) > 0 {
			rows, err := read(unread)
			if err != nil {
				return nil, err
			}
			for _, id := range unread {
				edges[id] = rows[id]
			}
		}
		walks = slices.DeleteFunc(walks, func(w *gateWalk) bool {
			w.step(edges)
			if len(w.level) > 0 {
				return false
			}
			gates[w.root] = w.gates
			return true
		})
	}
	if len(past) > 0 {
		return gates, fmt.Errorf("%w: %s", ErrWalkBound, strings.Join(past, " "))
	}
	return gates, nil
}

// gateWalk is one root's walk: the beads it has reached, the level it follows
// next, and the open human gates it has reached.
type gateWalk struct {
	root  string
	seen  map[string]bool
	level []string
	gates []Blocker
}

// step follows the open edges of the walk's level, which edges holds, to its next
// level, and keeps each open human gate once.
func (w *gateWalk) step(edges map[string][]Blocker) {
	var next []string
	for _, id := range w.level {
		for _, b := range edges[id] {
			if !b.open() || w.seen[b.ID] {
				continue
			}
			w.seen[b.ID] = true
			next = append(next, b.ID)
			if IsHumanGate(b.IssueType, b.AwaitType) {
				w.gates = append(w.gates, b)
			}
		}
	}
	w.level = next
}
