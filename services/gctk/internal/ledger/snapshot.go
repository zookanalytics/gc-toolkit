package ledger

import (
	"encoding/json"
	"fmt"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
)

// Record is one bead as a pass read it. A domain reads its keys through the
// Keys it declared, and its status and edges through the methods here.
type Record struct {
	ID  string
	row *gcbd.Bead
}

// Status is the bead's status, lower-cased, "" when the row carries none.
func (r *Record) Status() string { return r.row.StatusLower() }

// Edges is the bead's own edges, each with its far bead's status and close time.
func (r *Record) Edges() ([]gcbd.Edge, error) { return r.row.Edges() }

// Parent is the bead its parent-child edge names, "" when it has none.
func (r *Record) Parent() (string, error) {
	edges, err := r.row.Edges()
	if err != nil {
		return "", err
	}
	for _, e := range edges {
		if e.Type == gcbd.EdgeParentChild {
			return e.ID, nil
		}
	}
	return "", nil
}

// value is a metadata key's stored text, and whether the row holds the key. A
// string is itself, and any other JSON value is its JSON text. A null value is
// one the row does not hold.
func (r *Record) value(name string) (string, bool) {
	v, ok := r.row.Metadata[name]
	if !ok || v == nil {
		return "", false
	}
	switch t := v.(type) {
	case string:
		return t, true
	case json.Number:
		return t.String(), true
	case bool:
		if t {
			return "true", true
		}
		return "false", true
	default:
		raw, err := json.Marshal(t)
		if err != nil {
			return "", false
		}
		return string(raw), true
	}
}

// Snapshot is one pass's read: the beads a question needs, with their own edges
// and the store's blocked answers, typed through the declarations. Every caller
// that asks a question in the same pass gets the same answer from it.
type Snapshot struct {
	records map[string]*Record
	blocked *gcbd.BlockedSet
}

// maxAncestry bounds the walk up parent-child edges. A tree deeper than this is
// not one the city files, so a walk that reaches it fails rather than read on.
const maxAncestry = 32

// Read builds a snapshot of the beads named and every ancestor their
// parent-child edges reach, since the store can hold a bead through any of
// them. It reads the rows one level at a time and the blocked set once. A read
// that fails returns its *gcbd.ReadError, and so does a bead named or reached
// that the store reads no row for, since a snapshot without it can answer
// neither for it nor for a bead below it.
func (l *Ledger) Read(ids ...string) (*Snapshot, error) {
	s := &Snapshot{records: map[string]*Record{}}
	level := ids
	for depth := 0; len(level) > 0; depth++ {
		if depth > maxAncestry {
			return nil, &gcbd.ReadError{Reason: fmt.Sprintf("the parent-child walk from %v passed %d levels", ids, maxAncestry)}
		}
		rows, err := l.store.Rows(level)
		if err != nil {
			return nil, err
		}
		var next []string
		for i := range rows {
			r := &Record{ID: rows[i].ID, row: &rows[i]}
			s.records[r.ID] = r
			parent, err := r.Parent()
			if err != nil {
				return nil, &gcbd.ReadError{ID: r.ID, Reason: "its edges did not decode: " + err.Error()}
			}
			if parent != "" {
				if _, read := s.records[parent]; !read {
					next = append(next, parent)
				}
			}
		}
		level = next
	}
	blocked, err := l.store.Blocked()
	if err != nil {
		return nil, err
	}
	s.blocked = blocked
	return s, nil
}

// Record returns the bead's record, and whether the snapshot holds it.
func (s *Snapshot) Record(id string) (*Record, bool) {
	r, ok := s.records[id]
	return r, ok
}

// Blocking is the store's answer for the bead: gcbd.BlockedSet.Answer's, with
// its *gcbd.WaitsForError and *gcbd.ReadError. A bead the snapshot does not
// hold gets a *gcbd.ReadError.
func (s *Snapshot) Blocking(id string) (gcbd.Blocking, error) {
	r, ok := s.records[id]
	if !ok {
		return gcbd.Blocking{}, &gcbd.ReadError{ID: id, Reason: "the snapshot did not read it"}
	}
	return s.blocked.Answer(r.row)
}
