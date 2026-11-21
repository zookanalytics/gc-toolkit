package prstatus

import (
	"errors"
	"fmt"
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
	"github.com/zookanalytics/gc-toolkit/services/gctk/standing/person"
)

// machineGates are the keys of the human gates a review run's failure files:
// the landing order's, once the last two runs at a PR's head ended without a
// result, and a run's own, once its loop exhausted its attempts
// (specs/tk-1tfzr71.108/design.md, section 7). Each asks a person to look at
// the city's own machinery, not to rule on the PR.
var machineGates = []string{"review-run-failed", "review-loop-exhausted"}

// IsMachineGate reports whether a blocker is a human gate a review run's
// failure filed ([machineGates]). It holds the PR as any gate does, and reads
// as the machine's fault, never as a person's hold or a ruling owed.
func IsMachineGate(b person.Blocker) bool {
	return person.IsHumanGate(b.IssueType, b.AwaitType) && slices.Contains(machineGates, b.AwaitID)
}

// mergeResultPullRequest is the merge_result of a merge anchor whose pull
// request is open on the old record. Gas Town's pending record is the record a
// PR's bead carries from its publication to its merge, whose values
// services/gctk/pr/record declares and docs/state-machine.md ("The pending
// record") defines. On it an open pull request is [record.Pending], or
// [record.HeadChanged] while the refinery validates a head it has not.
const mergeResultPullRequest = "pull_request"

// awaitsPerson reports whether a merge anchor the walk reached is a person's to
// move by its own state: what [Derive] returns over the facts its own row
// records ([RowFacts]) and its own `blocks` edges (own). Each of those edges
// onto an open bead that is neither a human gate nor a person's to clear counts
// as work in flight on it, because the city moves that bead before the anchor's
// next move, so a pull request the city is changing or landing is no person's
// move. A blocker that waits on work of its own first ([person.Stays]), which edges
// gives the edges of, counts among the facts' Staying, so the anchor reads
// working while it does.
// Its gates and the beads a person owes count for nothing here: the walk reaches
// each of them and counts it itself, so one move is not counted twice. A
// person's move is needs-attention, and needs-review once the pull request is
// open, where the move is a review. A pre-open anchor has no pull request to
// review yet, and a bead with no merge_result is no merge anchor.
func awaitsPerson(b person.Blocker, own []person.Blocker, edges map[string][]person.Blocker) bool {
	result := b.Metadata["merge_result"]
	if result == "" {
		return false
	}
	f := RowFacts(b.Metadata)
	for _, e := range own {
		switch {
		case !e.Open() || person.IsHumanGate(e.IssueType, e.AwaitType):
		case person.Stays(e, edges[e.ID]):
			f.Staying = append(f.Staying, e)
		case !person.Clears(e):
			f.InFlightCount++
		}
	}

	// The walk reads no GitHub, so a pull request on Gas Town's pending record
	// is weighed by its row as well, less the old record's facts, which no pass
	// writes on a bead on this one and which [Render] does not read for the PR
	// itself: the machine verdict and thread count, and the draft markers. Its
	// review is a person's move only at the validated head, and only once
	// pr-facts.sh has recorded a posture, which it does not read while the pull
	// request is a draft, the city's work.
	onRecord := record.OnRecord(result)
	if onRecord {
		f.PRMachine, f.PRMachineCause, f.PRMachineReason, f.PRUnansweredThreads = "", "", "", ""
		f.OpenedAsDraft, f.DraftReadied = "", ""
	}
	switch Derive(f) {
	case NeedsAttention:
		return true
	case NeedsReview:
		if onRecord {
			posture, _ := splitDated(f.PRPosture)
			return result == record.Pending && posture != ""
		}
		return result == mergeResultPullRequest
	}
	return false
}

// ReadBlockers answers the `blocks` edges of each bead it is given: for each id,
// that bead's blockers, open and closed, and no edge of another type. It returns
// an error when any of those beads did not read, because a bead whose edges
// nothing read proves nothing about what holds it.
type ReadBlockers func(ids []string) (map[string][]person.Blocker, error)

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
// moves, each nearest first, and the beads that hold it while they wait on work
// of their own first ([person.Stays]).
type Holds struct {
	// Gates is every open human gate the walk reaches, in the order it reaches
	// them.
	Gates []person.Blocker
	// Owed is every other open bead the walk reaches that a person owes the next
	// move on: a blocker a person has to clear ([person.Clears]), such as a
	// conversation that holds a pull request's merge, or a merge anchor whose own
	// state is a person's to move ([awaitsPerson]), such as another pull request
	// that waits on a review. A merge anchor is weighed once
	// the walk has read its own edges, so it comes after the other beads at its
	// depth.
	Owed []person.Blocker
	// Staying is every bead the walk reaches that [person.Clears] reads as a
	// person's and that waits on work of its own first ([person.Stays]): a
	// conversation its sitting stays in, or a decision a ruling left waiting on
	// the work it sent. Until that work closes no person owes a move on it, so
	// it is in neither Gates nor Owed. It still holds what waits on it, such as
	// a pull request's merge, and the walk follows its edges as any other's, so
	// what holds that work counts on its own. Once the work closes, the same
	// bead is among Owed.
	Staying []person.Blocker
}

// Holding returns, for each root, what holds it that only a person moves
// ([Holds]): every open human gate, and every other bead a person owes the next
// move on, reached from the root through `blocks` edges whose blocker is open,
// and beside them every bead it reaches that waits on work of its own first.
// A PR's anchor is held by a gate on a rework it waits on as it is by a gate on
// itself, and by another pull request that rework waits on while that pull
// request waits on a person.
//
// It reads only the edges read returns. A conversation tracks its bead and
// blocks nothing but an open PR's anchor, whose merge it holds, so it counts
// only there. A decision or a conversation counts as a bead a person owes, or
// as staying while it waits on work of its own first ([person.Stays]), which only its
// own edges tell, a level further on. So what the walk reaches is decided once
// it has read every edge it reached, in the order it reached each. An edge onto
// a closed blocker is not followed, so nothing behind it holds anything. A bead
// that holds the root but waits on another is followed too, so what it waits on
// is named beside it.
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
			walks = append(walks, &holdWalk{root: r, seen: map[string]bool{r: true}, weigh: map[string]person.Blocker{}, level: []string{r}})
		}
	}
	holds := make(map[string]Holds, len(walks))
	edges := make(map[string][]person.Blocker)
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
			w.settle(edges)
			holds[w.root] = w.holds
			return true
		})
	}
	if len(past) > 0 {
		return holds, fmt.Errorf("%w: %s", ErrWalkBound, strings.Join(past, " "))
	}
	return holds, nil
}

// holdWalk is one root's walk: the beads it has reached, the merge anchors among
// them it weighs once their own edges are read, the level it follows next, the
// beads a person may owe a move on in the order it found them, and what it has
// found holding the root.
type holdWalk struct {
	root  string
	seen  map[string]bool
	weigh map[string]person.Blocker
	level []string
	found []person.Blocker
	holds Holds
}

// step finds each merge anchor of the walk's level, now that edges holds its
// own edges, then follows the level's open edges to the next level, keeping
// each open human gate and finding each blocker a person has to clear, once each.
// The whole level's anchors are found before any of its edges is followed, so
// no bead of the next level is found ahead of an anchor of this one.
func (w *holdWalk) step(edges map[string][]person.Blocker) {
	for _, id := range w.level {
		if b, ok := w.weigh[id]; ok {
			w.found = append(w.found, b)
		}
	}
	var next []string
	for _, id := range w.level {
		for _, b := range edges[id] {
			if !b.Open() || w.seen[b.ID] {
				continue
			}
			w.seen[b.ID] = true
			next = append(next, b.ID)
			switch {
			case person.IsHumanGate(b.IssueType, b.AwaitType):
				w.holds.Gates = append(w.holds.Gates, b)
			case person.Clears(b):
				w.found = append(w.found, b)
			case b.Metadata["merge_result"] != "":
				w.weigh[b.ID] = b
			}
		}
	}
	w.level = next
}

// settle decides each bead the walk found, in the order it found them, once
// the walk has read the edges of every bead it reached. A merge anchor is owed
// when its own state is a person's to move ([awaitsPerson]). A blocker a person
// has to clear is owed, unless it waits on work of its own first ([person.Stays]),
// which is staying instead. Each can need edges the walk reads after it found
// the bead: a blocker's own, read a level after the walk reached it, and those
// of a blocker an anchor waits on, read a level after the anchor's own. The
// walk has read them all once it ends.
func (w *holdWalk) settle(edges map[string][]person.Blocker) {
	for _, b := range w.found {
		_, anchor := w.weigh[b.ID]
		switch {
		case anchor:
			if awaitsPerson(b, edges[b.ID], edges) {
				w.holds.Owed = append(w.holds.Owed, b)
			}
		case person.Stays(b, edges[b.ID]):
			w.holds.Staying = append(w.holds.Staying, b)
		default:
			w.holds.Owed = append(w.holds.Owed, b)
		}
	}
}
