package ledger

import (
	"encoding/json"
	"fmt"
	"slices"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
)

// The store's answers as a domain reads them: the store adapter's own types and
// edge names, so a domain tells the store's errors and edges apart through the
// ledger and never reaches the store itself.
type (
	Edge          = gcbd.Edge
	Blocking      = gcbd.Blocking
	WaitsForError = gcbd.WaitsForError
	ReadError     = gcbd.ReadError
)

// The edge types the store's blocked rule reads.
const (
	EdgeBlocks            = gcbd.EdgeBlocks
	EdgeConditionalBlocks = gcbd.EdgeConditionalBlocks
	EdgeWaitsFor          = gcbd.EdgeWaitsFor
	EdgeParentChild       = gcbd.EdgeParentChild
)

// Record is one bead as a pass read it. A domain reads its keys through the
// Keys it declared, and its status, type and edges through the methods here.
type Record struct {
	ID  string
	row *gcbd.Bead
}

// Status is the bead's status, lower-cased, "" when the row carries none.
func (r *Record) Status() string { return r.row.StatusLower() }

// IssueType is the bead's issue type, "" when the row carries none.
func (r *Record) IssueType() string { return r.row.IssueTypeString() }

// Title is the bead's title.
func (r *Record) Title() string { return r.row.Title }

// Description is the bead's description, "" when the row carries none.
func (r *Record) Description() string { return r.row.DescriptionString() }

// Priority is the bead's priority, 0 when the row carries none.
func (r *Record) Priority() int { return r.row.PriorityInt() }

// Assignee is the bead's assignee, "" when it has none.
func (r *Record) Assignee() string { return r.row.AssigneeString() }

// Labels is the bead's labels, in the row's order.
func (r *Record) Labels() []string { return r.row.LabelStrings() }

// AwaitType is what a gate awaits, "" on a bead that is no gate.
func (r *Record) AwaitType() string { return r.row.AwaitType }

// CreatedAt is when the bead was created, as the row writes the time.
func (r *Record) CreatedAt() string { return r.row.CreatedAtString() }

// ClosedAt is when the bead closed, as the row writes the time, "" while it is
// live.
func (r *Record) ClosedAt() string { return r.row.ClosedAtString() }

// EphemeralPlane reports whether the store keeps the bead in its ephemeral
// plane, a wisp or a row stored with no history, which bd's listing leaves out
// unless asked.
func (r *Record) EphemeralPlane() bool { return r.row.InEphemeralPlane() }

// Template reports whether the bead is a template molecule.
func (r *Record) Template() bool { return r.row.Template() }

// Rendered is every metadata value the row holds, each as the pack's scripts
// render it, `(.metadata[k] // "") | tostring`. It is the input of a domain
// that still spells the keys it reads, prstatus's Store among them
// (docs/gctk-architecture.md, Debt). A domain reads a key it declares through
// the declaration.
func (r *Record) Rendered() map[string]string {
	out := make(map[string]string, len(r.row.Metadata))
	for k := range r.row.Metadata {
		out[k] = r.row.Meta(k)
	}
	return out
}

// Edges is the bead's own edges. A record a snapshot read carries its wait and
// parent-child edges alone, each with the far bead's title, status and close
// time, and leaves out an edge whose far bead the store does not hold. A record
// Find returns carries every edge, with the far bead's id and the edge's type
// alone.
func (r *Record) Edges() ([]gcbd.Edge, error) { return r.row.Edges() }

// Parents is every bead its parent-child edges name, sorted and each once, none
// when it has none. The store lets a bead have several parents.
func (r *Record) Parents() ([]string, error) {
	edges, err := r.row.Edges()
	if err != nil {
		return nil, err
	}
	var out []string
	for _, e := range edges {
		if e.Type == gcbd.EdgeParentChild {
			out = append(out, e.ID)
		}
	}
	slices.Sort(out)
	return slices.Compact(out), nil
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

// heldEdge reports whether an edge's far bead the snapshot reads: a wait of the
// store's blocked rule, or the parent-child edge an ancestor is reached by.
func heldEdge(typ string) bool {
	return typ == gcbd.EdgeBlocks || typ == gcbd.EdgeConditionalBlocks ||
		typ == gcbd.EdgeWaitsFor || typ == gcbd.EdgeParentChild
}

// Read builds a snapshot of the beads named and every ancestor their
// parent-child edges reach, since the store can hold a bead through any of
// them. It reads the store's listing, not a row per bead: one read of the beads
// named, then for each generation one read of the far beads its edges name, and
// the blocked set once. A listing names an edge's far bead by its id alone, so
// each record's wait and parent-child edges carry the far bead's title, status
// and close time from that bead's own row, and an edge whose far bead the store
// does not hold is left out, as a `gc bd show` row leaves it out. A record
// carries no edge of any other type. A read that fails returns its
// *gcbd.ReadError, and so does a bead named that the store holds no row for.
func (l *Ledger) Read(ids ...string) (*Snapshot, error) { return l.ReadFrom(nil, ids...) }

// ReadFrom is Read over the rows a caller has already listed, records Find
// returned: a bead named whose row is among them is not listed again.
func (l *Ledger) ReadFrom(listed []*Record, ids ...string) (*Snapshot, error) {
	s := &Snapshot{records: map[string]*Record{}}
	rows := map[string]*gcbd.Bead{}
	for _, r := range listed {
		if r != nil && r.row != nil {
			rows[r.ID] = r.row
		}
	}
	level := slices.Compact(slices.Sorted(slices.Values(ids)))
	var unlisted []string
	for _, id := range level {
		if rows[id] == nil {
			unlisted = append(unlisted, id)
		}
	}
	if err := l.listInto(rows, unlisted); err != nil {
		return nil, err
	}
	for _, id := range level {
		if rows[id] == nil {
			return nil, &gcbd.ReadError{ID: id, Reason: "the store's listing holds no row for it"}
		}
	}
	for depth := 0; len(level) > 0; depth++ {
		if depth > maxAncestry {
			return nil, &gcbd.ReadError{Reason: fmt.Sprintf("the parent-child walk from %v passed %d levels", ids, maxAncestry)}
		}
		edges := make(map[string][]gcbd.Edge, len(level))
		var far []string
		for _, id := range level {
			e, err := rows[id].Edges()
			if err != nil {
				return nil, &gcbd.ReadError{ID: id, Reason: "its edges did not decode: " + err.Error()}
			}
			edges[id] = e
			for _, x := range e {
				if heldEdge(x.Type) && rows[x.ID] == nil && !slices.Contains(far, x.ID) {
					far = append(far, x.ID)
				}
			}
		}
		if err := l.listInto(rows, far); err != nil {
			return nil, err
		}
		var next []string
		for _, id := range level {
			r := &Record{ID: id, row: shown(rows[id], edges[id], rows)}
			s.records[id] = r
			parents, err := r.Parents()
			if err != nil {
				return nil, &gcbd.ReadError{ID: id, Reason: "its edges did not decode: " + err.Error()}
			}
			for _, p := range parents {
				if s.records[p] == nil && !slices.Contains(next, p) && !slices.Contains(level, p) {
					next = append(next, p)
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

// listInto adds the listing's row of each bead named to rows, closed beads
// included. A bead the store does not hold is left out.
func (l *Ledger) listInto(rows map[string]*gcbd.Bead, ids []string) error {
	if len(ids) == 0 {
		return nil
	}
	got, err := l.store.Find(gcbd.Query{IDs: ids, Closed: true})
	if err != nil {
		return err
	}
	for i := range got {
		rows[got[i].ID] = &got[i]
	}
	return nil
}

// shown is the row b as a snapshot reads it: its own fields, and its wait and
// parent-child edges, each with the far bead's title, issue type, await type,
// status and close time from that bead's row in rows, an edge onto a bead rows
// does not hold left out.
func shown(b *gcbd.Bead, edges []gcbd.Edge, rows map[string]*gcbd.Bead) *gcbd.Bead {
	out := *b
	deps := make([]any, 0, len(edges))
	for _, e := range edges {
		f := rows[e.ID]
		if !heldEdge(e.Type) || f == nil {
			continue
		}
		d := map[string]any{"id": e.ID, "dependency_type": e.Type, "status": f.StatusLower(), "title": f.Title,
			"issue_type": f.IssueTypeString(), "await_type": f.AwaitType}
		if f.ClosedAt != nil {
			d["closed_at"] = f.ClosedAt
		}
		deps = append(deps, d)
	}
	out.Dependencies = deps
	return &out
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
