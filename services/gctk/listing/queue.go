package listing

import "github.com/zookanalytics/gc-toolkit/services/gctk/queue"

var _ queue.Store = (*Listing)(nil)

// Rows implements queue.Store: the row of each bead named the store holds,
// closed or live, as the pass read it. Holds is queue's other read.
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
