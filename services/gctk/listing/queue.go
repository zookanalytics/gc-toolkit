package listing

import (
	"slices"

	"github.com/zookanalytics/gc-toolkit/services/gctk/queue"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

var _ queue.Store = (*Listing)(nil)

// Ready implements queue.Store: the store's ready set, which the pass reads
// afresh, since readiness is the store's answer when it is asked.
func (ls *Listing) Ready() ([]string, error) { return ls.pass.ReadyIDs() }

// Worked implements queue.Store: each bead named that a live run works, by
// waits' run link over the pass, which answers the live roots from the
// listing's rows.
func (ls *Listing) Worked(ids []string) (map[string]bool, error) {
	runs, err := waits.LiveRuns(ls.pass)
	if err != nil {
		return nil, err
	}
	out := map[string]bool{}
	for _, r := range runs {
		if r.Live && r.Bead != "" && slices.Contains(ids, r.Bead) {
			out[r.Bead] = true
		}
	}
	return out, nil
}

// Rows implements queue.Store: the row of each bead named the store holds,
// closed or live, as the pass read it. Holds, Ready and Worked are queue's
// other reads.
func (ls *Listing) Rows(ids []string) (map[string]queue.Row, error) {
	recs, err := ls.byID(ids)
	if err != nil {
		return nil, err
	}
	out := make(map[string]queue.Row, len(recs))
	for id, r := range recs {
		b, err := ls.bead(r)
		if err != nil {
			return nil, err
		}
		out[id] = queue.Row{ID: b.ID, Status: b.Status, Priority: b.Priority, CreatedAt: b.CreatedAt,
			RoutedTo: b.RoutedTo, Assignee: b.Assignee, Labels: b.Labels, Anchor: b.Anchor}
	}
	return out, nil
}
