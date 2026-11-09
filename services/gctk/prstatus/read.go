package prstatus

import (
	"errors"
	"fmt"
	"slices"
	"strings"
)

// Row is a bead as [Read] reads it: its id and its metadata, each value as the
// store holds it, rendered the way `(.metadata[k] // "") | tostring` renders it.
type Row struct {
	ID       string
	Metadata map[string]string
}

// Store is the reads [Read] gathers through: one reader's adapter onto the bead
// store. It holds no rule. [Read] decides which beads to read and over which
// statuses, and an adapter only carries out each read. Each read answers for
// every id it is given, and returns an error when any of them did not read,
// because a bead nothing read proves nothing about what holds a PR.
type Store interface {
	// Beads returns the row of each id the store holds. An id it holds no row
	// for is left out.
	Beads(ids []string) (map[string]Row, error)
	// Anchored returns, for each id, the beads whose metadata.anchor_bead names
	// it, at any of statuses.
	Anchored(ids []string, statuses []string) (map[string][]Row, error)
	// Blockers returns, for each id, the far bead of each of its `blocks` edges,
	// open and closed, with its metadata. It is the read [Holding] walks
	// ([ReadBlockers]).
	Blockers(ids []string) (map[string][]Blocker, error)
}

// ErrUnresolved reports an anchor the store holds no row for. Nothing about it
// was read, so it has no answer.
var ErrUnresolved = errors.New("the anchor does not resolve")

// Read gathers the [Facts] the city records about each anchor's PR: the anchor's
// own row, its in-flight set over [InFlightStatuses], and what holds it that
// only a person moves, which [Holding] reads through its `blocks` edges: the
// open human gates, and the beads a person owes the next move on. It is the one
// place that decides what is read, so every reader that asks what holds a PR, or
// where a PR stands, gives Read its own [Store] and decides from the same facts.
//
// The reads are batched across the anchors: one each for the rows, the
// in-flight sets and the anchors' own edges, then one per level of the walk past
// those edges. A read that fails returns nothing and its error. An anchor the
// store holds no row for, or one whose walk ran past its bound, has no answer:
// the map leaves it out, the error names it, wrapping [ErrUnresolved] or
// [ErrWalkBound], and the other anchors keep theirs.
func Read(anchors []string, s Store) (map[string]Facts, error) {
	var ids []string
	for _, a := range anchors {
		if !slices.Contains(ids, a) {
			ids = append(ids, a)
		}
	}
	facts := make(map[string]Facts, len(ids))
	if len(ids) == 0 {
		return facts, nil
	}
	rows, err := s.Beads(ids)
	if err != nil {
		return nil, err
	}
	var resolved, unresolved []string
	for _, id := range ids {
		if _, ok := rows[id]; ok {
			resolved = append(resolved, id)
		} else {
			unresolved = append(unresolved, id)
		}
	}
	var errs []error
	if len(unresolved) > 0 {
		errs = append(errs, fmt.Errorf("%w: %s", ErrUnresolved, strings.Join(unresolved, " ")))
	}
	if len(resolved) == 0 {
		return facts, errors.Join(errs...)
	}
	inFlight, err := s.Anchored(resolved, InFlightStatuses)
	if err != nil {
		return nil, err
	}
	own, err := s.Blockers(resolved)
	if err != nil {
		return nil, err
	}
	// The walk's first level is the anchors' own edges, already read.
	holds, err := Holding(resolved, func(level []string) (map[string][]Blocker, error) {
		out := make(map[string][]Blocker, len(level))
		var rest []string
		for _, id := range level {
			if b, ok := own[id]; ok {
				out[id] = b
			} else {
				rest = append(rest, id)
			}
		}
		if len(rest) > 0 {
			more, err := s.Blockers(rest)
			if err != nil {
				return nil, err
			}
			for _, id := range rest {
				out[id] = more[id]
			}
		}
		return out, nil
	})
	if err != nil {
		if !errors.Is(err, ErrWalkBound) {
			return nil, err
		}
		errs = append(errs, err)
	}
	for _, id := range resolved {
		h, walked := holds[id]
		if !walked {
			continue
		}
		f := RowFacts(rows[id].Metadata)
		f.Gates, f.Owed, f.InFlightCount = h.Gates, h.Owed, len(inFlight[id])
		facts[id] = f
	}
	return facts, errors.Join(errs...)
}

// RowFacts are the facts a bead's own row records, read off its metadata: its
// holds, the posture, the machine verdict with its cause and sentence, the
// thread count and the draft-stage markers. [Read] adds what it gathers beside
// the row to them: the gates, the beads a person owes and the in-flight count.
// [Holding] weighs a merge anchor it reaches by its row's facts, and the helm
// board reads a row that is no PR, or whose PR has no answer, by them alone.
func RowFacts(md map[string]string) Facts {
	return Facts{
		MergeHold:           md["merge_hold"],
		RebaseHold:          md["rebase_hold"],
		PRPosture:           md["pr_posture"],
		PRMachine:           md["pr.machine"],
		PRMachineCause:      md["pr.machine_cause"],
		PRMachineReason:     md["pr.machine_reason"],
		PRUnansweredThreads: md["pr.unanswered_threads"],
		OpenedAsDraft:       md["opened_as_draft"],
		DraftReadied:        md["draft_readied"],
	}
}
