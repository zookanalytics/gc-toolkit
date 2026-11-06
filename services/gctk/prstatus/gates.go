package prstatus

import (
	"errors"
	"fmt"
	"slices"
	"strings"
)

// Blocker is the far end of one `blocks` edge, in the fields [Holding] reads of
// it. A caller fills it from its own read of the store, passes the status and the
// issue type as they read, in any case, and fills the rest from the bead's
// metadata through [Blocker.WithMetadata], so every caller reads a blocker alike.
type Blocker struct {
	ID        string
	Title     string
	Status    string
	IssueType string
	AwaitType string
	// RoutedTo is gc.routed_to. A blocker routed to "human" is a person's to move.
	RoutedTo string
	// MergeResult is merge_result: set on a merge anchor, and pull_request while
	// its pull request is open.
	MergeResult string
	// Own is what a merge anchor records about its own pull request: the
	// metadata-keyed fields of [Facts], as its own label reads them. [Holding]
	// counts the rest off the blocker's own edges when it weighs whose move it is.
	Own Facts
}

// WithMetadata returns b with the fields it reads off the bead's metadata: its
// route, its merge_result, and the facts a merge anchor records about its own
// pull request. meta answers one key as the bead stores it, the raw value a
// caller passes [Facts] for an anchor.
func (b Blocker) WithMetadata(meta func(key string) string) Blocker {
	b.RoutedTo = meta("gc.routed_to")
	b.MergeResult = meta("merge_result")
	b.Own = Facts{
		MergeHold:           meta("merge_hold"),
		RebaseHold:          meta("rebase_hold"),
		PRPosture:           meta("pr_posture"),
		PRMachine:           meta("pr.machine"),
		PRMachineCause:      meta("pr.machine_cause"),
		PRUnansweredThreads: meta("pr.unanswered_threads"),
		OpenedAsDraft:       meta("opened_as_draft"),
		DraftReadied:        meta("draft_readied"),
	}
	return b
}

// open reports whether the blocker still blocks: any status but closed, a
// blocker with no status included. It is the rule a human gate is read open by
// (HUMAN_GATE_JQ in assets/scripts/bd-lib.sh) and the one the label's blocker
// read applies.
func (b Blocker) open() bool { return !strings.EqualFold(b.Status, "closed") }

// personal reports whether an open blocker other than a human gate is a person's
// to move by what it is: a decision, or a bead routed to a person. It is the helm
// board's demand test (board.demand). A human gate is not among them, whatever its
// route, because [Holds.Gates] counts it.
func (b Blocker) personal() bool {
	return b.open() && !IsHumanGate(b.IssueType, b.AwaitType) &&
		(strings.EqualFold(b.IssueType, "decision") || b.RoutedTo == "human")
}

// mergeResultPullRequest is the merge_result of an anchor whose pull request is
// open.
const mergeResultPullRequest = "pull_request"

// awaitsPerson reports whether a merge anchor the walk reached is a person's to
// move by its own state: what [Derive] returns over the facts it records
// ([Blocker.Own]) and its own `blocks` edges. Each of those edges onto an open
// bead that is neither a human gate nor a person's to move counts as work in
// flight on it, because the city moves that bead before the anchor's next move.
// Its gates and the beads a person moves count for nothing here: the walk reaches
// each of them and counts it itself, so one move is not counted twice. A person's
// move is needs-attention, and needs-review once the pull request is open, where
// the move is a review. A pre-open anchor has no pull request to review yet.
func (b Blocker) awaitsPerson(edges []Blocker) bool {
	if b.MergeResult == "" {
		return false
	}
	f := b.Own
	f.OpenHumanGate, f.PersonBlocker, f.InFlightCount = false, false, 0
	for _, e := range edges {
		if e.open() && !IsHumanGate(e.IssueType, e.AwaitType) && !e.personal() {
			f.InFlightCount++
		}
	}
	switch Derive(f) {
	case NeedsAttention:
		return true
	case NeedsReview:
		return b.MergeResult == mergeResultPullRequest
	}
	return false
}

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

// Holds is what the walk from one bead finds holding it that only a person
// moves, each in the order the walk reaches it, nearest first.
type Holds struct {
	// Gates is every open human gate the walk reaches.
	Gates []Blocker
	// Owed is every other open bead the walk reaches that a person owes the next
	// move on: a decision or a bead routed to a person ([Blocker.personal]), or a
	// merge anchor whose own state is a person's to move ([Blocker.awaitsPerson]),
	// such as another pull request that waits on a review.
	Owed []Blocker
}

// Holding returns, for each root, what holds it that only a person moves ([Holds]):
// every open human gate, and every other bead a person owes the next move on,
// reached from the root through `blocks` edges whose blocker is open. A PR's
// anchor is held by a gate on a rework it waits on as it is by a gate on itself,
// and by another pull request that rework waits on while that pull request waits
// on a person.
//
// It reads only the edges read returns, so a conversation, which tracks its bead
// and blocks nothing, never counts. An edge onto a closed blocker is not followed,
// so nothing behind it holds anything. A bead that holds the root but waits on
// another is followed too, so what it waits on is named beside it.
//
// Each root walks for itself and the walks share their reads: one read per level
// names the beads no walk has read yet, and each bead is read once, however many
// edges reach it. So a cycle ends, a caller holding many anchors pays per level
// rather than per anchor, and a root's answer is the same alone or beside others.
//
// A root whose walk runs past its bound has no answer, because what holds it past
// the bound is unknown: the map leaves it out, and the error wraps [ErrWalkBound]
// and names it, while the other roots still answer. A read that fails returns
// nothing and its error, because a bead no read reached proves nothing about any
// root.
//
// This is the one reader of what holds a bead behind its edges. [Facts.OpenHumanGate]
// is whether it finds a gate, and [Facts.PersonBlocker] whether it finds a bead a
// person owes, so the PR's held: labels and the helm board's PR row read it, and
// `gctk pr-status gates` is how gc-helm.sh engage lists the gates to offer.
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

// HoldingGates returns, for each root, the open human gates that hold it, the
// [Holds.Gates] that [Holding] reads, with the same answer, bound and errors.
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
// each open human gate and each bead a person moves by what it is once.
func (w *holdWalk) step(edges map[string][]Blocker) {
	var next []string
	for _, id := range w.level {
		if b, ok := w.weigh[id]; ok && b.awaitsPerson(edges[id]) {
			w.holds.Owed = append(w.holds.Owed, b)
		}
		for _, b := range edges[id] {
			if !b.open() || w.seen[b.ID] {
				continue
			}
			w.seen[b.ID] = true
			next = append(next, b.ID)
			switch {
			case IsHumanGate(b.IssueType, b.AwaitType):
				w.holds.Gates = append(w.holds.Gates, b)
			case b.personal():
				w.holds.Owed = append(w.holds.Owed, b)
			case b.MergeResult != "":
				w.weigh[b.ID] = b
			}
		}
	}
	w.level = next
}
