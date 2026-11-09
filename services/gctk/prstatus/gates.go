package prstatus

import (
	"errors"
	"fmt"
	"slices"
	"strings"
)

// Blocker is the far end of one `blocks` edge, in the fields [Holding] and
// [IsPersonBlocker] read of it. A [Store] fills it from its own read, and passes
// the status and the issue type as they read, in any case. Metadata is the far
// bead's metadata whole, each value as [Row.Metadata] renders it, so the
// definition decides which keys it reads: the route of any blocker, and the
// facts a merge anchor records about its own PR.
type Blocker struct {
	ID        string
	Title     string
	Status    string
	IssueType string
	AwaitType string
	Metadata  map[string]string
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

// IsPersonBlocker reports whether a blocker is a person's to clear and not a
// human gate: a live blocker routed to a person (gc.routed_to=human), or a
// decision. No automated actor will clear it, so it holds a PR as held: blocked.
// A human gate is never one, whatever its route, because held: gate is what
// counts it. A blocker with no status reads open, and only a closed one is not
// live. The helm board asks it of any bead's blockers, for the rows that ask a
// person for something.
func IsPersonBlocker(b Blocker) bool {
	if !b.open() || IsHumanGate(b.IssueType, b.AwaitType) {
		return false
	}
	return b.Metadata["gc.routed_to"] == "human" || strings.EqualFold(b.IssueType, "decision")
}

// mergeResultPullRequest is the merge_result of a merge anchor whose pull
// request is open.
const mergeResultPullRequest = "pull_request"

// awaitsPerson reports whether a merge anchor the walk reached is a person's to
// move by its own state: what [Derive] returns over the facts its own row
// records ([RowFacts]) and its own `blocks` edges. Each of those edges onto an
// open bead that is neither a human gate nor a person's to clear counts as work
// in flight on it, because the city moves that bead before the anchor's next
// move, so a pull request the city is changing or landing is no person's move.
// Its gates and the beads a person owes count for nothing here: the walk reaches
// each of them and counts it itself, so one move is not counted twice. A
// person's move is needs-attention, and needs-review once the pull request is
// open, where the move is a review. A pre-open anchor has no pull request to
// review yet, and a bead with no merge_result is no merge anchor.
func awaitsPerson(b Blocker, edges []Blocker) bool {
	result := b.Metadata["merge_result"]
	if result == "" {
		return false
	}
	f := RowFacts(b.Metadata)
	for _, e := range edges {
		if e.open() && !IsHumanGate(e.IssueType, e.AwaitType) && !IsPersonBlocker(e) {
			f.InFlightCount++
		}
	}
	switch Derive(f) {
	case NeedsAttention:
		return true
	case NeedsReview:
		return result == mergeResultPullRequest
	}
	return false
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

// ErrWalkBound reports a walk that ran past its bound, which leaves what holds
// the root past it unread. A caller treats it as a read that did not resolve.
var ErrWalkBound = errors.New("the blocks edges run past the walk's bound")

// Holds is what the walk from one bead finds holding it that only a person
// moves, each nearest first.
type Holds struct {
	// Gates is every open human gate the walk reaches, in the order it reaches
	// them.
	Gates []Blocker
	// Owed is every other open bead the walk reaches that a person owes the next
	// move on: a blocker a person has to clear ([IsPersonBlocker]), or a merge
	// anchor whose own state is a person's to move ([awaitsPerson]), such as
	// another pull request that waits on a review. A merge anchor is weighed once
	// the walk has read its own edges, so it comes after the other beads at its
	// depth.
	Owed []Blocker
}

// Holding returns, for each root, what holds it that only a person moves
// ([Holds]): every open human gate, and every other bead a person owes the next
// move on, reached from the root through `blocks` edges whose blocker is open.
// A PR's anchor is held by a gate on a rework it waits on as it is by a gate on
// itself, and by another pull request that rework waits on while that pull
// request waits on a person.
//
// It reads only the edges read returns, so a conversation, which tracks its bead
// and blocks nothing, never counts. An edge onto a closed blocker is not
// followed, so nothing behind it holds anything. A bead that holds the root but
// waits on another is followed too, so what it waits on is named beside it.
//
// Each root walks for itself and the walks share their reads: one read per level
// names the beads no walk has read yet, and each bead is read once, however many
// edges reach it. So a cycle ends, a caller holding many anchors pays per level
// rather than per anchor, and a root's answer is the same alone or beside others.
//
// A root whose walk runs past its bound has no answer, because what holds it
// past the bound is unknown: the map leaves it out, and the error wraps
// [ErrWalkBound] and names it, while the other roots still answer. A read that
// fails returns nothing and its error, because a bead no read reached proves
// nothing about any root.
//
// This is the one reader of what holds a bead through its edges. [Read] gathers
// [Facts.Gates] and [Facts.Owed] through it, so the PR's held: labels, the helm
// board's PR row and what gc-helm.sh engage offers all read its answer.
func Holding(roots []string, read ReadBlockers) (map[string]Holds, error) {
	var walks []*holdWalk
	named := make(map[string]bool, len(roots))
	for _, r := range roots {
		if !named[r] {
			named[r] = true
			walks = append(walks, &holdWalk{root: r, seen: map[string]bool{r: true}, weigh: map[string]Blocker{}, level: []string{r}})
		}
	}
	holds := make(map[string]Holds, len(walks))
	edges := make(map[string][]Blocker)
	var past []string
	for depth := 0; len(walks) > 0; depth++ {
		var unread []string
		walks = slices.DeleteFunc(walks, func(w *holdWalk) bool {
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
		walks = slices.DeleteFunc(walks, func(w *holdWalk) bool {
			w.step(edges)
			if len(w.level) > 0 {
				return false
			}
			holds[w.root] = w.holds
			return true
		})
	}
	if len(past) > 0 {
		return holds, fmt.Errorf("%w: %s", ErrWalkBound, strings.Join(past, " "))
	}
	return holds, nil
}

// HoldingGates returns, for each root, the open human gates that hold it: the
// [Holds.Gates] of [Holding], with its bound and its errors. The merge pass asks
// it for the blockers it would otherwise call stuck.
func HoldingGates(roots []string, read ReadBlockers) (map[string][]Blocker, error) {
	holds, err := Holding(roots, read)
	if holds == nil {
		return nil, err
	}
	gates := make(map[string][]Blocker, len(holds))
	for root, h := range holds {
		gates[root] = h.Gates
	}
	return gates, err
}

// holdWalk is one root's walk: the beads it has reached, the merge anchors among
// them it weighs once their own edges are read, the level it follows next, and
// what it has found holding the root.
type holdWalk struct {
	root  string
	seen  map[string]bool
	weigh map[string]Blocker
	level []string
	holds Holds
}

// step weighs each merge anchor of the walk's level by its own edges, which
// edges holds, then follows the level's open edges to the next level, keeping
// each open human gate and each blocker a person has to clear once. The whole
// level is weighed before any of its edges is followed, so no bead of the next
// level is kept ahead of an anchor of this one.
func (w *holdWalk) step(edges map[string][]Blocker) {
	for _, id := range w.level {
		if b, ok := w.weigh[id]; ok && awaitsPerson(b, edges[id]) {
			w.holds.Owed = append(w.holds.Owed, b)
		}
	}
	var next []string
	for _, id := range w.level {
		for _, b := range edges[id] {
			if !b.open() || w.seen[b.ID] {
				continue
			}
			w.seen[b.ID] = true
			next = append(next, b.ID)
			switch {
			case IsHumanGate(b.IssueType, b.AwaitType):
				w.holds.Gates = append(w.holds.Gates, b)
			case IsPersonBlocker(b):
				w.holds.Owed = append(w.holds.Owed, b)
			case b.Metadata["merge_result"] != "":
				w.weigh[b.ID] = b
			}
		}
	}
	w.level = next
}
