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
// it, with its own edges.
type Bead struct {
	ID, Title, Status string
	Metadata          map[string]string
	Edges             []gcbd.Edge
}

// Write is one update the store took: the bead and the update's arguments.
type Write struct {
	ID   string
	Args []string
}

// Store is an in-memory gcbd.Store.
type Store struct {
	rows   map[string]Bead
	listed map[string][]string
	marked []string
	writes []Write

	// RowsErr and BlockedErr fail the matching read when set, and UpdateErr
	// fails every write.
	RowsErr, BlockedErr, UpdateErr error
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

// Rows returns the row of each bead named. A bead the store does not hold fails
// the read with a *gcbd.ReadError naming it, as gcbd.Client.Rows does.
func (s *Store) Rows(ids []string) ([]gcbd.Bead, error) {
	if s.RowsErr != nil {
		return nil, s.RowsErr
	}
	var out []gcbd.Bead
	for _, id := range ids {
		b, ok := s.rows[id]
		if !ok {
			return nil, &gcbd.ReadError{ID: id, Reason: "the fake store holds no row for it"}
		}
		out = append(out, row(b))
	}
	return out, nil
}

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

// row renders b as gcbd decodes a `gc bd show --json` row.
func row(b Bead) gcbd.Bead {
	status := b.Status
	meta := make(map[string]any, len(b.Metadata))
	for k, v := range b.Metadata {
		meta[k] = v
	}
	deps := make([]any, 0, len(b.Edges))
	for _, e := range b.Edges {
		d := map[string]any{"id": e.ID, "dependency_type": e.Type, "status": e.Status}
		if e.ClosedAt != "" {
			d["closed_at"] = e.ClosedAt
		}
		deps = append(deps, d)
	}
	return gcbd.Bead{ID: b.ID, Title: b.Title, Status: &status, Metadata: meta, Dependencies: deps}
}
