// Package fake is the store adapter's in-memory fake: rows and their edges, with
// the store's blocked answers set by the test (docs/gctk-architecture.md, "The
// adapters"). A domain's tests run on it through the ledger, so every domain
// rule is tested in Go without a store. It answers the questions gcbd.Store
// asks, and holds none of the store's rules: what the listing names and what
// the store marks blocked are the test's to set, and gcbd.BlockedSet judges
// them as it judges the real store's.
package fake

import (
	"fmt"
	"maps"
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
)

// Bead is a row to put in the store: what a `gc bd show --json` row carries of
// it, with its own edges. An edge whose far bead the store does not hold is one
// into another store: Rows leaves it out, as a show does, and Find keeps it, as
// a listing does.
type Bead struct {
	ID, Title, Status, IssueType string
	Metadata                     map[string]string
	Edges                        []gcbd.Edge
}

// Write is one update the store took: the bead and the update's arguments.
type Write struct {
	ID   string
	Args []string
}

// Store is an in-memory gcbd.Store.
type Store struct {
	rows   map[string]Bead
	lost   map[string]bool
	listed map[string][]string
	marked []string
	writes []Write

	// RowsErr, BlockedErr and FindErr fail the matching read when set, and
	// UpdateErr fails every write.
	RowsErr, BlockedErr, FindErr, UpdateErr error

	finds []gcbd.Query
}

var _ gcbd.Store = (*Store)(nil)

// New returns an empty store.
func New() *Store {
	return &Store{rows: map[string]Bead{}, listed: map[string][]string{}}
}

// Put adds b, or replaces the row of the same id.
func (s *Store) Put(b Bead) {
	b.Metadata = maps.Clone(b.Metadata)
	b.Edges = slices.Clone(b.Edges)
	s.rows[b.ID] = b
}

// List makes the store's blocked listing name id, held by by: its own waits,
// or the parent it is held through.
func (s *Store) List(id string, by ...string) { s.listed[id] = slices.Clone(by) }

// Mark makes the store mark ids blocked.
func (s *Store) Mark(ids ...string) { s.marked = append(s.marked, ids...) }

// Writes returns every update the store took, in order.
func (s *Store) Writes() []Write { return slices.Clone(s.writes) }

// Row returns the bead's row as it stands, and whether the store holds it.
func (s *Store) Row(id string) (Bead, bool) {
	b, ok := s.rows[id]
	return b, ok
}

// Lose makes a read of each bead's own row fail, as a lookup that failed does,
// while the store still holds it as the far bead of another row's edge.
func (s *Store) Lose(ids ...string) {
	if s.lost == nil {
		s.lost = map[string]bool{}
	}
	for _, id := range ids {
		s.lost[id] = true
	}
}

// Rows returns the row of each bead named. A bead the store does not hold, or
// one Lose names, fails the read with a *gcbd.ReadError naming it, as
// gcbd.Client.Rows does.
func (s *Store) Rows(ids []string) ([]gcbd.Bead, error) {
	if s.RowsErr != nil {
		return nil, s.RowsErr
	}
	var out []gcbd.Bead
	for _, id := range ids {
		b, ok := s.rows[id]
		if !ok || s.lost[id] {
			return nil, &gcbd.ReadError{ID: id, Reason: "the fake store holds no row for it"}
		}
		out = append(out, s.row(b))
	}
	return out, nil
}

// Find returns, in id order, the row of each bead q selects, in a listing's
// shape: every edge, with the far bead's id and the edge's type alone. A bead q
// names that the store does not hold is left out, as a listing leaves it out.
func (s *Store) Find(q gcbd.Query) ([]gcbd.Bead, error) {
	s.finds = append(s.finds, q)
	if s.FindErr != nil {
		return nil, s.FindErr
	}
	if len(q.IDs) == 0 && q.HasKey == "" && q.Key == "" {
		return nil, &gcbd.ReadError{Reason: "the fake store takes no find that selects no beads"}
	}
	ids := slices.Sorted(maps.Keys(s.rows))
	var out []gcbd.Bead
	for _, id := range ids {
		b := s.rows[id]
		if !q.Closed && strings.EqualFold(b.Status, "closed") {
			continue
		}
		if len(q.IDs) > 0 && !slices.Contains(q.IDs, id) {
			continue
		}
		if _, held := b.Metadata[q.HasKey]; q.HasKey != "" && !held {
			continue
		}
		if v, held := b.Metadata[q.Key]; q.Key != "" && (!held || v != q.Value) {
			continue
		}
		out = append(out, listed(b))
	}
	return out, nil
}

// Finds returns every query Find took, in order.
func (s *Store) Finds() []gcbd.Query { return slices.Clone(s.finds) }

// Blocked returns the listing and the marks the test set.
func (s *Store) Blocked() (*gcbd.BlockedSet, error) {
	if s.BlockedErr != nil {
		return nil, s.BlockedErr
	}
	return gcbd.NewBlockedSet(s.listed, s.marked), nil
}

// Update applies one update's --set-metadata, --unset-metadata and --status to
// the row, and records it. A bead the store does not hold refuses the write, as
// bd does.
func (s *Store) Update(id string, args ...string) (string, error) {
	if s.UpdateErr != nil {
		return "", s.UpdateErr
	}
	b, ok := s.rows[id]
	if !ok {
		return "", fmt.Errorf("fake store: no bead %s", id)
	}
	if b.Metadata == nil {
		b.Metadata = map[string]string{}
	}
	for i := 0; i < len(args); i++ {
		name, value, inline := strings.Cut(args[i], "=")
		if !inline {
			if i+1 >= len(args) {
				return "", fmt.Errorf("fake store: %s needs a value", name)
			}
			i++
			value = args[i]
		}
		switch name {
		case "--set-metadata":
			k, v, ok := strings.Cut(value, "=")
			if !ok {
				return "", fmt.Errorf("fake store: --set-metadata %q is not key=value", value)
			}
			b.Metadata[k] = v
		case "--unset-metadata":
			delete(b.Metadata, value)
		case "--status":
			b.Status = value
		default:
			return "", fmt.Errorf("fake store: update takes no %s", name)
		}
	}
	s.rows[id] = b
	s.writes = append(s.writes, Write{ID: id, Args: slices.Clone(args)})
	return "", nil
}

// row renders b as gcbd decodes a `gc bd show --json` row, whose edges carry
// the far bead's fields and leave out an edge whose far bead the store does not
// hold.
func (s *Store) row(b Bead) gcbd.Bead {
	deps := make([]any, 0, len(b.Edges))
	for _, e := range b.Edges {
		if _, held := s.rows[e.ID]; !held {
			continue
		}
		d := map[string]any{"id": e.ID, "dependency_type": e.Type, "status": e.Status}
		if e.Title != "" {
			d["title"] = e.Title
		}
		if e.ClosedAt != "" {
			d["closed_at"] = e.ClosedAt
		}
		deps = append(deps, d)
	}
	return bead(b, deps)
}

// listed renders b as gcbd decodes a `gc bd list --json` row, whose edges name
// the far bead and the edge's type alone, every edge included.
func listed(b Bead) gcbd.Bead {
	deps := make([]any, 0, len(b.Edges))
	for _, e := range b.Edges {
		deps = append(deps, map[string]any{"issue_id": b.ID, "depends_on_id": e.ID, "type": e.Type})
	}
	return bead(b, deps)
}

func bead(b Bead, deps []any) gcbd.Bead {
	status := b.Status
	meta := make(map[string]any, len(b.Metadata))
	for k, v := range b.Metadata {
		meta[k] = v
	}
	out := gcbd.Bead{ID: b.ID, Title: b.Title, Status: &status, Metadata: meta, Dependencies: deps}
	if b.IssueType != "" {
		out.IssueType = b.IssueType
	}
	return out
}
