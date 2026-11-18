// Package fake is the store adapter's in-memory fake: rows and their edges, with
// the store's blocked and ready answers set by the test
// (docs/gctk-architecture.md, "The adapters"). A domain's tests run on it
// through the ledger, so every domain rule is tested in Go without a store. It
// answers the questions gcbd.Store asks, and holds none of the store's rules:
// what the listing names, what the store marks blocked and which beads it
// reports ready are the test's to set, and gcbd.BlockedSet judges the first two
// as it judges the real store's.
package fake

import (
	"encoding/json"
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
// time takes the one an edge onto it names. Assignee, AwaitType, AwaitID,
// Description, Priority, Labels, CreatedAt, CloseReason and Notes are the row's
// own fields a listing carries, and an update's --append-notes adds a line to
// Notes. Ephemeral and Template put the row in the ephemeral plane or make it a
// template.
type Bead struct {
	ID, Title, Status, IssueType, ClosedAt string
	Assignee, AwaitType, Description       string
	AwaitID, CreatedAt, CloseReason, Notes string
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

// Create is one create the store took: the bead it filed, its title and the
// create's arguments.
type Create struct {
	ID, Title string
	Args      []string
}

// Store is an in-memory gcbd.Store, safe for concurrent use as the city's
// store is.
type Store struct {
	mu      sync.Mutex
	rows    map[string]Bead
	lost    map[string]bool
	listed  map[string][]string
	marked  []string
	ready   map[string]bool
	writes  []Write
	creates []Create

	// RowsErr, BlockedErr, FindErr and ReadyErr fail the matching read when
	// set, UpdateErr fails every write and CreateErr every create.
	RowsErr, BlockedErr, FindErr, ReadyErr, UpdateErr, CreateErr error

	// OnFind, when set, runs before each find the store takes, outside the
	// store's lock, and fails nothing. A test lands another actor's write in it.
	OnFind func(q gcbd.Query)

	// BeforeUpdate, when set, runs ahead of each update, outside the store's
	// lock, so a test can land another writer's change between a read and a
	// write, or refuse the write with the error it returns.
	BeforeUpdate func(id string, args []string) error

	// IDPrefix is the id prefix the store gives a bead it files, which its
	// Prefix read answers: fk when unset.
	IDPrefix string

	// CloseTime, when set, is the close time an update that closes a bead
	// stamps on a row that names none, as bd stamps a close. With none set, an
	// update stamps nothing, and a test names a close time itself.
	CloseTime string

	// WorkRecordGate, when set, refuses an update that closes a plain task bead
	// as Gas City's work-record gate refuses it under GC_WORK_RECORD_ENFORCE,
	// which gc bd runs before it hands bd the update, so it is the door's rule
	// and not the store's: the work record the bead carries with the update's
	// keys applied names no gc.work_outcome, or one that is not shipped, no-op,
	// blocked or abandoned, or a shipped one with no gc.work_commit or no
	// gc.work_branch (Gated and ValidateOnClose in internal/workrecord/gate.go,
	// and evaluateWorkRecordCloseGate in cmd/gc/work_record_gate.go, at Gas City
	// upstream e9a628c500). The gate's last test, whether the branch reaches the
	// commit, asks a rig's checkout, which the fake does not hold. A refused
	// update writes nothing.
	WorkRecordGate bool

	finds []gcbd.Query
}

var _ gcbd.Store = (*Store)(nil)

// New returns an empty store.
func New() *Store {
	return &Store{rows: map[string]Bead{}, listed: map[string][]string{}, ready: map[string]bool{}}
}

// MakeReady makes the store report each bead named ready, as bd's readiness
// would. Which beads are ready is the test's to set, as the blocked listing is.
func (s *Store) MakeReady(ids ...string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, id := range ids {
		s.ready[id] = true
	}
}

// Ready returns, in id order, the row of each bead MakeReady named that q
// selects, in a listing's shape: an open bead that carries q's key, unassigned
// when q asks, of no type q leaves out and with no label q leaves out, each
// compared exactly, as bd's flags compare them.
func (s *Store) Ready(q gcbd.ReadyQuery) ([]gcbd.Bead, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.ReadyErr != nil {
		return nil, s.ReadyErr
	}
	if q.HasKey == "" {
		return nil, &gcbd.ReadError{Reason: "the fake store takes no ready read that names no key"}
	}
	var out []gcbd.Bead
	for _, id := range slices.Sorted(maps.Keys(s.rows)) {
		b := s.rows[id]
		if !s.ready[id] || !strings.EqualFold(b.Status, "open") {
			continue
		}
		if _, held := b.Metadata[q.HasKey]; !held {
			continue
		}
		if q.Unassigned && b.Assignee != "" {
			continue
		}
		if slices.Contains(q.ExcludeTypes, b.IssueType) {
			continue
		}
		if slices.ContainsFunc(b.Labels, func(l string) bool { return slices.Contains(q.ExcludeLabels, l) }) {
			continue
		}
		out = append(out, s.listing(b))
	}
	return out, nil
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

// Unlist leaves each bead named out of the store's blocked listing, as the store
// leaves a bead once nothing holds it.
func (s *Store) Unlist(ids ...string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, id := range ids {
		delete(s.listed, id)
	}
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
// A parent selects the beads whose own parent-child edge names it, and a type
// the beads whose issue type is that one exactly.
func (s *Store) Find(q gcbd.Query) ([]gcbd.Bead, error) {
	if s.OnFind != nil {
		s.OnFind(q)
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.finds = append(s.finds, q)
	if s.FindErr != nil {
		return nil, s.FindErr
	}
	if len(q.IDs) == 0 && q.HasKey == "" && q.Key == "" && q.Parent == "" && q.TitleContains == "" && q.Type == "" && !q.Every {
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
		if q.TitleContains != "" && !strings.Contains(b.Title, q.TitleContains) {
			continue
		}
		if q.Type != "" && b.IssueType != q.Type {
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
			if strings.EqualFold(value, "closed") && b.ClosedAt == "" {
				b.ClosedAt = s.CloseTime
			}
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
	if s.WorkRecordGate && closesStatus(args) && workRecordGated(s.rows[id]) {
		if why := workRecordRefusal(b.Metadata); why != "" {
			return "", fmt.Errorf("fake store: work-record gate (enforced): close of %s: %s", id, why)
		}
	}
	s.rows[id] = b
	s.writes = append(s.writes, Write{ID: id, Args: slices.Clone(args)})
	return "", nil
}

// closesStatus reports whether an update's arguments move the bead to closed.
func closesStatus(args []string) bool {
	closes := false
	for i := 0; i < len(args); i++ {
		if v, ok := strings.CutPrefix(args[i], "--status="); ok {
			closes = strings.EqualFold(v, "closed")
		} else if args[i] == "--status" && i+1 < len(args) {
			i++
			closes = strings.EqualFold(args[i], "closed")
		}
	}
	return closes
}

// workRecordGated reports whether the work-record gate reads the close of b: a
// task, or a bead of no type, that carries no gc.kind, gc.step_id or
// gc.step_ref.
func workRecordGated(b Bead) bool {
	if t := strings.TrimSpace(b.IssueType); t != "" && t != "task" {
		return false
	}
	for _, k := range []string{"gc.kind", "gc.step_id", "gc.step_ref"} {
		if strings.TrimSpace(b.Metadata[k]) != "" {
			return false
		}
	}
	return true
}

// workRecordRefusal is why the work-record gate refuses a close whose bead
// carries meta once the update lands, "" when it does not.
func workRecordRefusal(meta map[string]string) string {
	outcome := strings.TrimSpace(meta["gc.work_outcome"])
	switch outcome {
	case "":
		return "missing gc.work_outcome"
	case "no-op", "blocked", "abandoned":
		return ""
	case "shipped":
	default:
		return fmt.Sprintf("invalid gc.work_outcome=%q", outcome)
	}
	var missing []string
	for _, k := range []string{"gc.work_commit", "gc.work_branch"} {
		if strings.TrimSpace(meta[k]) == "" {
			missing = append(missing, k)
		}
	}
	if len(missing) > 0 {
		return "gc.work_outcome=shipped requires " + strings.Join(missing, " and ")
	}
	return ""
}

// Creates returns every create the store took, in order.
func (s *Store) Creates() []Create {
	s.mu.Lock()
	defer s.mu.Unlock()
	return slices.Clone(s.creates)
}

// Prefix answers the id prefix the store gives a bead it files.
func (s *Store) Prefix() (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.prefix(), nil
}

func (s *Store) prefix() string {
	if s.IDPrefix == "" {
		return "fk"
	}
	return s.IDPrefix
}

// Create files a bead titled title, open, as <prefix>-<n> for the nth create,
// or the first n after it whose id the store does not hold, as bd mints no id
// a store holds. It takes the create's -t, -d, --metadata, a JSON object of
// strings, and --deps, read as bd's --deps reads it: an entry blocks:<id> gives
// bead id a blocks edge onto the new bead, a bare id, depends-on:<id> and
// blocked-by:<id> name a bead the new one waits on by a blocks edge, and any
// other type, such as discovered-from, gives the new bead its own edge of that
// type. A bead --deps names that the store does not hold refuses the create.
func (s *Store) Create(title string, args ...string) (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.CreateErr != nil {
		return "", s.CreateErr
	}
	n := len(s.creates) + 1
	id := fmt.Sprintf("%s-%d", s.prefix(), n)
	for _, held := s.rows[id]; held; _, held = s.rows[id] {
		n++
		id = fmt.Sprintf("%s-%d", s.prefix(), n)
	}
	b := Bead{ID: id, Title: title, Status: "open", IssueType: "task", Metadata: map[string]string{}}
	var blocks []string
	for i := 0; i < len(args); i++ {
		name := args[i]
		if name == "--json" {
			continue
		}
		if i+1 >= len(args) {
			return "", fmt.Errorf("fake store: %s needs a value", name)
		}
		i++
		value := args[i]
		switch name {
		case "-t", "--type":
			b.IssueType = value
		case "-d", "--description":
			b.Description = value
		case "--metadata":
			var m map[string]string
			if err := json.Unmarshal([]byte(value), &m); err != nil {
				return "", fmt.Errorf("fake store: --metadata %q is not a JSON object of strings: %w", value, err)
			}
			maps.Copy(b.Metadata, m)
		case "--deps":
			for _, d := range strings.Split(value, ",") {
				typ, far, ok := strings.Cut(d, ":")
				if !ok {
					typ, far = "blocked-by", d
				}
				if _, held := s.rows[far]; !held {
					return "", fmt.Errorf("fake store: --deps names %s, which the store does not hold", far)
				}
				switch typ {
				case gcbd.EdgeBlocks:
					blocks = append(blocks, far)
				case "blocked-by", "depends-on":
					b.Edges = append(b.Edges, gcbd.Edge{Type: gcbd.EdgeBlocks, ID: far, Status: s.rows[far].Status})
				default:
					b.Edges = append(b.Edges, gcbd.Edge{Type: typ, ID: far, Status: s.rows[far].Status})
				}
			}
		default:
			return "", fmt.Errorf("fake store: create takes no %s", name)
		}
	}
	for _, far := range blocks {
		r := s.rows[far]
		r.Edges = append(slices.Clone(r.Edges), gcbd.Edge{Type: gcbd.EdgeBlocks, ID: id, Title: title, Status: "open"})
		s.rows[far] = r
	}
	s.rows[id] = b
	s.creates = append(s.creates, Create{ID: id, Title: title, Args: slices.Clone(args)})
	return id, nil
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
		AwaitType: b.AwaitType, AwaitID: b.AwaitID, Priority: float64(b.Priority)}
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
	if b.CloseReason != "" {
		out.CloseReason = b.CloseReason
	}
	if b.Notes != "" {
		out.Notes = b.Notes
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
