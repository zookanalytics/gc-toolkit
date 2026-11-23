package listing

import (
	"github.com/zookanalytics/gc-toolkit/services/gctk/standing"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

var _ standing.Store = (*Listing)(nil)

// Every implements standing.Store: every live bead the listing read.
func (ls *Listing) Every() []standing.Bead {
	live := ls.Live()
	out := make([]standing.Bead, 0, len(live))
	for _, b := range live {
		out = append(out, b.Standing())
	}
	return out
}

// Find implements standing.Store: each bead named, live or closed. A bead the
// listing has read already answers from that read, and the rest are read from
// the store.
func (ls *Listing) Find(ids []string) (map[string]standing.Bead, error) {
	out := make(map[string]standing.Bead, len(ids))
	var unread []string
	ls.mu.Lock()
	for _, id := range ids {
		if b, ok := ls.beads[id]; ok {
			out[id] = b.Standing()
		} else {
			unread = append(unread, id)
		}
	}
	ls.mu.Unlock()
	if len(unread) == 0 {
		return out, nil
	}
	recs, err := ls.byID(unread)
	if err != nil {
		return nil, err
	}
	for id, r := range recs {
		b, err := ls.bead(r)
		if err != nil {
			return nil, err
		}
		out[id] = b.Standing()
	}
	return out, nil
}

// ClosedBeneath implements standing.Store: the closed beads [Listing.ClosedUnder]
// reads beneath the parents.
func (ls *Listing) ClosedBeneath(parents []string) ([]standing.Bead, error) {
	rows, err := ls.ClosedUnder(parents)
	if err != nil {
		return nil, err
	}
	out := make([]standing.Bead, 0, len(rows))
	for _, b := range rows {
		out = append(out, b.Standing())
	}
	return out, nil
}

// LiveRuns implements standing.Store: every live run, through the listing's
// pass.
func (ls *Listing) LiveRuns() ([]waits.Run, error) { return waits.LiveRuns(ls.pass) }

// Standing is the bead in the fields standing reads.
func (b Bead) Standing() standing.Bead {
	edges := make([]standing.Edge, 0, len(b.Edges))
	for _, e := range b.Edges {
		edges = append(edges, standing.Edge{ID: e.ID, Type: e.Type})
	}
	return standing.Bead{ID: b.ID, Title: b.Title, Status: b.Status, IssueType: b.IssueType, AwaitType: b.AwaitType,
		Assignee: b.Assignee, Labels: b.Labels, Edges: edges, Hypothesis: b.Epic.Hypothesis, MergeResult: b.MergeResult,
		PRNumber: b.PRNumber, Anchor: b.Anchor, Run: b.Run, EphemeralPlane: b.EphemeralPlane, Template: b.Template}
}
