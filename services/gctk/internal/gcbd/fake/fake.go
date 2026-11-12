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
	"sync"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
)

// Bead is a row to put in the store: what a `gc bd show --json` row carries of
// it, with its own edges. An edge whose far bead the store does not hold is one
// into another store: Rows leaves it out, as a show does, and Find keeps it, as
// a listing does. ClosedAt is when a closed bead closed. An edge carries the far
// bead's fields as a show row reports them, so a closed row that names no close
// time takes the one an edge onto it names. Assignee, AwaitType, Description,
// Priority, Labels, CreatedAt and Notes are the row's own fields a listing
// carries, and Ephemeral and Template put the row in the ephemeral plane or
// make it a template.
type Bead struct {
	ID, Title, Status, IssueType, ClosedAt string
	Assignee, AwaitType, Description       string
	CreatedAt, Notes                       string
	Priority                               int
	Labels                                 []string
	Ephemeral, Template                    bool
	Metadata                               map[string]string
	Edges                                  []gcbd.Edge
}

// Write is one update the store took: the bead and the update's arguments.
type Write struct {
	ID   string
	Args []string
}

// Store is an in-memory gcbd.Store, safe for concurrent use as the city's
// store is.
type Store struct {
	mu     sync.Mutex
	rows   map[string]Bead
	lost   map[string]bool
	listed map[string][]string
	marked []string
	writes []Write

	// RowsErr, BlockedErr and FindErr fail the matching read when set, and
	// UpdateErr fails every write.
	RowsErr, BlockedErr, FindErr, UpdateErr error

	// BeforeUpdate, when set, runs ahead of each update, outside the store's
	// lock, so a test can land another writer's change between a read and a
	// write, or refuse the write with the error it returns.
	BeforeUpdate func(id string, args []string) error

	finds []gcbd.Query
}

var _ gcbd.Store = (*Store)(nil)

// New returns an empty store.
func New() *Store {
	return &Store{rows: map[string]Bead{}, listed: map[string][]string{}}
}

// Put adds b, or replaces the row of the same id.
func (s *Store) Put(b Bead) {
	s.mu.Lock()
	defer s.mu.Unlock()
	b.Metadata = maps.Clone(b.Metadata)
	b.Edges = slices.Clone(b.Edges)
	b.Labels = slices.Clone(b.Labels)
	s.rows[b.ID] = b
}

// List makes the store's blocked listing name id, held by by: its own waits, or
// one of its parents, which need not be one the store marks blocked.
func (s *Store) List(id string, by ...string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.listed[id] = slices.Clone(by)
}

// Mark makes the store mark ids blocked.
func (s *Store) Mark(ids ...string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.marked = append(s.marked, ids...)
}

// Writes returns every update the store took, in order.
func (s *Store) Writes() []Write {
	s.mu.Lock()
	defer s.mu.Unlock()
	return slices.Clone(s.writes)
}

// Row returns the bead's row as it stands, and whether the store holds it.
func (s *Store) Row(id string) (Bead, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	b, ok := s.rows[id]
	return b, ok
}

// Lose makes a read of each bead's own row fail, as a lookup that failed does,
// while the store still holds it as the far bead of another row's edge.
func (s *Store) Lose(ids ...string) {
	s.mu.Lock()
	defer s.mu.Unlock()
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
	s.mu.Lock()
	defer s.mu.Unlock()
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
// A parent selects the beads whose own parent-child edge names it.
func (s *Store) Find(q gcbd.Query) ([]gcbd.Bead, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.finds = append(s.finds, q)
	if s.FindErr != nil {
		return nil, s.FindErr
	}
	if len(q.IDs) == 0 && q.HasKey == "" && q.Key == "" && q.Parent == "" && !q.Every {
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
		if q.Parent != "" && !slices.ContainsFunc(b.Edges, func(e gcbd.Edge) bool {
			return e.Type == gcbd.EdgeParentChild && e.ID == q.Parent
		}) {
			continue
		}
		out = append(out, s.listing(b))
	}
	return out, nil
}

// Finds returns every query Find took, in order.
func (s *Store) Finds() []gcbd.Query {
	s.mu.Lock()
	defer s.mu.Unlock()
	return slices.Clone(s.finds)
}

// Blocked returns the listing and the marks the test set.
func (s *Store) Blocked() (*gcbd.BlockedSet, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.BlockedErr != nil {
		return nil, s.BlockedErr
	}
	return gcbd.NewBlockedSet(s.listed, s.marked), nil
}

// Update applies one update's --set-metadata, --unset-metadata, --status,
// --assignee, --append-notes and --title to the row, and records it. A bead the
// store does not hold refuses the write, as bd does. --if-status and
// --if-assignee are bd's guards: an update whose guard no longer holds writes
// nothing and fails with an error that is gcbd.ErrGuard.
func (s *Store) Update(id string, args ...string) (string, error) {
	if s.BeforeUpdate != nil {
		if err := s.BeforeUpdate(id, slices.Clone(args)); err != nil {
			return "", err
		}
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.UpdateErr != nil {
		return "", s.UpdateErr
	}
	b, ok := s.rows[id]
	if !ok {
		return "", fmt.Errorf("fake store: no bead %s", id)
	}
	b.Metadata = maps.Clone(b.Metadata)
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
		case "--assignee":
			b.Assignee = value
		case "--append-notes":
			if b.Notes != "" {
				b.Notes += "\n"
			}
			b.Notes += value
		case "--title":
			b.Title = value
		case "--if-status":
			if cur := s.rows[id].Status; cur != value {
				return "", fmt.Errorf("fake store: %s is %s, not %s: %w", id, cur, value, gcbd.ErrGuard)
			}
		case "--if-assignee":
			if cur := s.rows[id].Assignee; cur != value {
				return "", fmt.Errorf("fake store: %s is assigned %q, not %q: %w", id, cur, value, gcbd.ErrGuard)
			}
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

// listing renders b as gcbd decodes a `gc bd list --json` row, whose edges name
// the far bead and the edge's type alone, every edge included, and which carries
// the bead's own close time.
func (s *Store) listing(b Bead) gcbd.Bead {
	deps := make([]any, 0, len(b.Edges))
	for _, e := range b.Edges {
		deps = append(deps, map[string]any{"issue_id": b.ID, "depends_on_id": e.ID, "type": e.Type})
	}
	out := bead(b, deps)
	if at := s.closedAt(b); at != "" {
		out.ClosedAt = at
	}
	return out
}

// closedAt is when b closed: its own close time, or for a closed row that names
// none, the one an edge onto it names.
func (s *Store) closedAt(b Bead) string {
	if b.ClosedAt != "" || !strings.EqualFold(b.Status, "closed") {
		return b.ClosedAt
	}
	for _, id := range slices.Sorted(maps.Keys(s.rows)) {
		for _, e := range s.rows[id].Edges {
			if e.ID == b.ID && e.ClosedAt != "" {
				return e.ClosedAt
			}
		}
	}
	return ""
}

func bead(b Bead, deps []any) gcbd.Bead {
	status := b.Status
	meta := make(map[string]any, len(b.Metadata))
	for k, v := range b.Metadata {
		meta[k] = v
	}
	out := gcbd.Bead{ID: b.ID, Title: b.Title, Status: &status, Metadata: meta, Dependencies: deps,
		AwaitType: b.AwaitType, Priority: float64(b.Priority)}
	if b.IssueType != "" {
		out.IssueType = b.IssueType
	}
	if b.Assignee != "" {
		out.Assignee = b.Assignee
	}
	if b.Description != "" {
		out.Description = b.Description
	}
	if b.Notes != "" {
		out.Notes = b.Notes
	}
	if b.CreatedAt != "" {
		out.CreatedAt = b.CreatedAt
	}
	if b.Ephemeral {
		out.Ephemeral = true
	}
	if b.Template {
		out.IsTemplate = true
	}
	if len(b.Labels) > 0 {
		labels := make([]any, len(b.Labels))
		for i, l := range b.Labels {
			labels[i] = l
		}
		out.Labels = labels
	}
	return out
}
