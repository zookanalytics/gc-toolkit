package prstatus

import (
	"slices"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/standing/person"
)

// Over is the [Store] that reads through l, which `gctk pr status` and the
// listing both read through. Over a pass ([ledger.Ledger.Pass]) it reads each
// bead once however many reads name it, and a reader that asks the pr domain's
// evaluator through the same pass, as both do, reads no bead twice.
func Over(l *ledger.Ledger) Store { return ledgerStore{l: l} }

type ledgerStore struct{ l *ledger.Ledger }

// Beads reads the beads named, closed ones among them, in one read.
func (s ledgerStore) Beads(ids []string) (map[string]*Row, error) { return s.byID(ids) }

// Anchored reads, for each id, every bead whose anchor_bead names it, live
// ones alone unless statuses holds closed, and keeps the ones at one of
// statuses that bd's listing shows unless asked for more
// ([ledger.Record.ListedByDefault]), the beads `gc bd list --metadata-field
// anchor_bead=<id> --status <statuses>` lists. It narrows the selection
// itself, so a pass answers the pr evaluator's read of the same selection, in
// pr.FromStore, from the rows this read kept.
func (s ledgerStore) Anchored(ids []string, statuses []string) (map[string][]*Row, error) {
	out := make(map[string][]*Row, len(ids))
	for _, id := range ids {
		sel := ledger.Matching(anchorKey, id)
		if slices.Contains(statuses, "closed") {
			sel = sel.WithClosed()
		}
		recs, err := s.l.Find(sel)
		if err != nil {
			return nil, err
		}
		out[id] = []*Row{}
		for _, r := range recs {
			if r.ListedByDefault() && slices.Contains(statuses, r.Status()) {
				out[id] = append(out[id], r)
			}
		}
	}
	return out, nil
}

// Blockers reads the far bead of each `blocks` edge of each bead named, closed
// ones among them, in one read: the edges come off each bead's own row. An
// edge onto a bead the store does not hold is one into another store, which
// holds nothing, so it is left out. A bead named that the store does not hold
// is an error, because no row answered for its edges.
func (s ledgerStore) Blockers(ids []string) (map[string][]person.Blocker, error) {
	recs, err := s.byID(ids)
	if err != nil {
		return nil, err
	}
	blocks := make(map[string][]string, len(ids))
	var far []string
	for _, id := range ids {
		r, ok := recs[id]
		if !ok {
			return nil, &ledger.ReadError{ID: id, Reason: "the store holds no such bead"}
		}
		edges, err := r.Edges()
		if err != nil {
			return nil, &ledger.ReadError{ID: id, Reason: "its edges did not decode: " + err.Error()}
		}
		for _, e := range edges {
			if e.Type == ledger.EdgeBlocks && !slices.Contains(blocks[id], e.ID) {
				blocks[id] = append(blocks[id], e.ID)
			}
		}
		far = append(far, blocks[id]...)
	}
	farRecs, err := s.byID(far)
	if err != nil {
		return nil, err
	}
	out := make(map[string][]person.Blocker, len(ids))
	for _, id := range ids {
		out[id] = []person.Blocker{}
		for _, x := range blocks[id] {
			if r, ok := farRecs[x]; ok {
				out[id] = append(out[id], person.Blocker{ID: r.ID, Title: r.Title(), Status: r.Status(),
					IssueType: r.IssueType(), AwaitType: r.AwaitType(), AwaitID: r.AwaitID(), Assignee: r.Assignee(),
					ClosedAt: r.ClosedAt(), Record: r})
			}
		}
	}
	return out, nil
}

// byID is each bead named the store holds, closed or live.
func (s ledgerStore) byID(ids []string) (map[string]*Row, error) {
	recs, err := s.l.Find(ledger.ByID(ids...).WithClosed())
	if err != nil {
		return nil, err
	}
	out := make(map[string]*Row, len(recs))
	for _, r := range recs {
		out[r.ID] = r
	}
	return out, nil
}
