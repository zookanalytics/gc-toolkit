package ledger

import (
	"fmt"
	"slices"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
)

// Selection is the beads one Find reads: the beads named, the beads that carry a
// declared key, the beads whose key holds one value, the beads the store lists
// under a parent, the beads whose title holds a text, or every bead. It reads
// live beads alone unless WithClosed widens it. A key's selection matches its
// current spelling, not its legacy aliases.
type Selection struct {
	q    gcbd.Query
	none bool
	err  error
}

// ByID selects the beads named.
func ByID(ids ...string) Selection {
	return Selection{q: gcbd.Query{IDs: slices.Clone(ids)}, none: len(ids) == 0}
}

// Every selects every bead the store holds.
func Every() Selection { return Selection{q: gcbd.Query{Every: true}} }

// Under selects the beads the store lists under parent. The store's filter can
// return a bead whose own parent-child edge names another parent, so a domain
// keeps a child by its record's Parents.
func Under(parent string) Selection {
	return Selection{q: gcbd.Query{Parent: parent}, none: parent == ""}
}

// Titled selects the beads whose title holds text.
func Titled(text string) Selection {
	return Selection{q: gcbd.Query{TitleContains: text}, none: text == ""}
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
	return records(rows), nil
}

// ServeRule is a pool's serve rule as bd's ready read takes it: unassigned
// beads alone when Unassigned is set, and none of the issue types or labels it
// leaves out, each compared exactly.
type ServeRule struct {
	Unassigned    bool
	ExcludeTypes  []string
	ExcludeLabels []string
}

// Ready reads the beads that carry k that the store reports ready under rule,
// by bd's own readiness, in the order the store gives them. Each record's
// edges are the listing's, as Find's are. A read that fails returns its
// *ReadError.
func Ready[T any](l *Ledger, k Key[T], rule ServeRule) ([]*Record, error) {
	rows, err := l.store.Ready(gcbd.ReadyQuery{HasKey: k.decl.name, Unassigned: rule.Unassigned,
		ExcludeTypes: slices.Clone(rule.ExcludeTypes), ExcludeLabels: slices.Clone(rule.ExcludeLabels)})
	if err != nil {
		return nil, err
	}
	return records(rows), nil
}

func records(rows []gcbd.Bead) []*Record {
	out := make([]*Record, len(rows))
	for i := range rows {
		out[i] = &Record{ID: rows[i].ID, row: &rows[i]}
	}
	return out
}
