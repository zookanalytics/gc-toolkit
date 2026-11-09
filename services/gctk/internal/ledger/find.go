package ledger

import (
	"fmt"
	"slices"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
)

// Selection is the beads one Find reads: the beads named, the beads that carry a
// declared key, or the beads whose key holds one value. It reads live beads
// alone unless WithClosed widens it. A key's selection matches its current
// spelling, not its legacy aliases.
type Selection struct {
	q    gcbd.Query
	none bool
	err  error
}

// ByID selects the beads named.
func ByID(ids ...string) Selection {
	return Selection{q: gcbd.Query{IDs: slices.Clone(ids)}, none: len(ids) == 0}
}

// Carrying selects the beads that carry k.
func Carrying[T any](k Key[T]) Selection { return Selection{q: gcbd.Query{HasKey: k.decl.name}} }

// Matching selects the beads whose k holds v.
func Matching[T any](k Key[T], v T) Selection {
	text, err := k.codec.Encode(v)
	if err != nil {
		return Selection{err: fmt.Errorf("%s does not encode as %s: %w", k.decl.name, k.decl.typ, err)}
	}
	return Selection{q: gcbd.Query{Key: k.decl.name, Value: text}}
}

// WithClosed widens s to closed beads as well as live ones.
func (s Selection) WithClosed() Selection {
	s.q.Closed = true
	return s
}

// Find reads the beads s selects, in one pass, each as a Record. It reads the
// store's listing, whose rows carry each edge a bead has, with the far bead's id
// and the edge's type alone, so the Edges of a Record Find returns hold every
// edge, an edge into another store included, with an empty Status and ClosedAt.
// A bead ByID names that the store does not hold is left out. A read that fails
// returns its *ReadError, and ByID with no ids reads nothing.
func (l *Ledger) Find(s Selection) ([]*Record, error) {
	if s.err != nil {
		return nil, s.err
	}
	if s.none {
		return nil, nil
	}
	rows, err := l.store.Find(s.q)
	if err != nil {
		return nil, err
	}
	out := make([]*Record, len(rows))
	for i := range rows {
		out[i] = &Record{ID: rows[i].ID, row: &rows[i]}
	}
	return out, nil
}
