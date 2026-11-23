package ledger

import (
	"encoding/json"
	"errors"
	"maps"
	"reflect"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
)

// A selection by key reads the key by its declared name, so the domain that
// declared it never spells it, a selection by type keeps that issue type
// alone, and a selection by id with no ids, or by type with none, reads
// nothing. None of these selections narrows the read to a status or to what
// the listing shows, so each reads every plane.
func TestFindSelectsByTheDeclaredKey(t *testing.T) {
	s := fake.New()
	s.Put(fake.Bead{ID: "root", Status: "in_progress", IssueType: "task", Metadata: map[string]string{"gc.x": "cv"},
		Edges: []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "xx-1"}}})
	s.Put(fake.Bead{ID: "old", Status: "closed", Metadata: map[string]string{"gc.x": "cv"}})
	k := Key[string]{decl: &decl{name: "gc.x", typ: "string"}, codec: String}
	l := New(s)
	ids := func(rs []*Record) []string {
		var out []string
		for _, r := range rs {
			out = append(out, r.ID)
		}
		return out
	}
	for _, tc := range []struct {
		name string
		sel  Selection
		want []string
	}{
		{"the beads that carry the key", Carrying(k), []string{"root"}},
		{"the beads whose key holds a value, closed ones too", Matching(k, "cv").WithClosed(), []string{"old", "root"}},
		{"the beads named", ByID("root", "gone"), []string{"root"}},
		{"the beads of one type", Typed("task"), []string{"root"}},
		{"every live bead", Every(), []string{"root"}},
	} {
		got, err := l.Find(tc.sel)
		if err != nil || !slices.Equal(ids(got), tc.want) {
			t.Errorf("%s = %v, %v; want %v", tc.name, ids(got), err, tc.want)
		}
	}
	asked := []gcbd.Query{{HasKey: "gc.x"}, {Key: "gc.x", Value: "cv", Closed: true}, {IDs: []string{"root", "gone"}}, {Type: "task"}, {Every: true}}
	if got := s.Finds(); !reflect.DeepEqual(got, asked) {
		t.Errorf("the store was asked %+v; want %+v", got, asked)
	}
	got, _ := l.Find(ByID("root"))
	if e, err := got[0].Edges(); err != nil || len(e) != 1 || e[0].ID != "xx-1" || got[0].IssueType() != "task" {
		t.Errorf("the record = %+v, %v; want the listing's edge into another store and the bead's type", e, err)
	}
	before := len(s.Finds())
	if rs, err := l.Find(ByID()); rs != nil || err != nil || len(s.Finds()) != before {
		t.Errorf("a selection of no ids = %v, %v after %d reads; want nothing read", rs, err, len(s.Finds())-before)
	}
	if rs, err := l.Find(Typed("")); rs != nil || err != nil || len(s.Finds()) != before {
		t.Errorf("a selection of no type = %v, %v after %d reads; want nothing read", rs, err, len(s.Finds())-before)
	}
	s.FindErr = &gcbd.ReadError{Reason: "gc bd list exited 1"}
	var re *ReadError
	if _, err := l.Find(Carrying(k)); !errors.As(err, &re) {
		t.Errorf("a find that fails = %v, want its read error", err)
	}
}

// An assignee's selection, narrowed to a status and to what the listing shows,
// asks the store for exactly that, and a selection of no assignee, or of no
// status, reads nothing.
func TestFindNarrowsByAssigneeStatusAndListing(t *testing.T) {
	s := fake.New()
	s.Put(fake.Bead{ID: "h", Status: "open", IssueType: "task", Assignee: "rig/refinery"})
	s.Put(fake.Bead{ID: "g", Status: "open", IssueType: "gate", Assignee: "rig/refinery"})
	s.Put(fake.Bead{ID: "p", Status: "in_progress", IssueType: "task", Assignee: "rig/refinery"})
	s.Put(fake.Bead{ID: "o", Status: "open", IssueType: "task", Assignee: "rig/witness"})
	l := New(s)
	got, err := l.Find(Assigned("rig/refinery").InStatus("open").Listed())
	if err != nil || !slices.Equal(recordIDs(got), []string{"h"}) {
		t.Fatalf("the refinery's open listed beads = %v, %v; want h alone", recordIDs(got), err)
	}
	if q := s.Finds()[0]; q.Assignee != "rig/refinery" || !slices.Equal(q.Statuses, []string{"open"}) || !q.Listed || q.Every {
		t.Errorf("the store was asked %+v; want the assignee, the status and the listing", q)
	}
	before := len(s.Finds())
	if rs, err := l.Find(Assigned("")); rs != nil || err != nil || len(s.Finds()) != before {
		t.Errorf("a selection of no assignee = %v, %v after %d reads; want nothing read", rs, err, len(s.Finds())-before)
	}
	if rs, err := l.Find(Every().InStatus()); rs != nil || err != nil || len(s.Finds()) != before {
		t.Errorf("a selection of no status = %v, %v after %d reads; want nothing read", rs, err, len(s.Finds())-before)
	}
}

// typedStore is the fake store with each bead's metadata typed as bd stores
// it: a row it returns holds the JSON object put gave the bead, decoded as the
// store adapter decodes a row, in place of the strings the fake holds. The fake
// selects a bead by a key's presence, and the bead has each key its object
// has, whatever the value, as bd's row has a key it stores as a null.
type typedStore struct {
	*fake.Store
	meta map[string]map[string]any
}

func newTypedStore() *typedStore {
	return &typedStore{Store: fake.New(), meta: map[string]map[string]any{}}
}

// put adds a bead at status whose metadata is the JSON object given.
func (s *typedStore) put(t *testing.T, id, status, metadata string) {
	t.Helper()
	dec := json.NewDecoder(strings.NewReader(metadata))
	dec.UseNumber()
	var m map[string]any
	if err := dec.Decode(&m); err != nil {
		t.Fatal(err)
	}
	keys := map[string]string{}
	for k := range m {
		keys[k] = "typed"
	}
	s.Store.Put(fake.Bead{ID: id, Status: status, Metadata: keys})
	s.meta[id] = m
}

func (s *typedStore) typed(rows []gcbd.Bead, err error) ([]gcbd.Bead, error) {
	for i := range rows {
		if m, ok := s.meta[rows[i].ID]; ok {
			rows[i].Metadata = maps.Clone(m)
		}
	}
	return rows, err
}

func (s *typedStore) Find(q gcbd.Query) ([]gcbd.Bead, error) { return s.typed(s.Store.Find(q)) }

func (s *typedStore) Ready(q gcbd.ReadyQuery) ([]gcbd.Bead, error) { return s.typed(s.Store.Ready(q)) }

// A key's selection keeps the beads whose key Get reads as held. bd's row has a
// key it stores as a JSON null or a false, and the store selects that row by
// the key's presence, so Find and Ready leave out a row whose String key holds
// a null or a false, and keep one that holds an empty text or the text "false".
// A current spelling that holds false gives way to its alias, so a bead whose
// alias holds a value is kept, and a JSON flag holds false. A pass keeps the
// same beads, both when it reads the store for them and when it answers from
// the rows it holds.
func TestCarryingKeepsTheBeadsWhoseKeyHoldsAValue(t *testing.T) {
	s := newTypedStore()
	for _, b := range []struct{ id, status, metadata string }{
		{"s-value", "open", `{"test.ledger.shell":"x"}`},
		{"s-empty", "open", `{"test.ledger.shell":""}`},
		{"s-false-text", "open", `{"test.ledger.shell":"false"}`},
		{"s-true", "open", `{"test.ledger.shell":true}`},
		{"s-false", "open", `{"test.ledger.shell":false}`},
		{"s-null", "open", `{"test.ledger.shell":null}`},
		{"s-closed", "closed", `{"test.ledger.shell":"x"}`},
		{"s-closed-false", "closed", `{"test.ledger.shell":false}`},
		{"t-alias", "open", `{"test.ledger.text":false,"test.ledger.old_text":"older"}`},
		{"t-false", "open", `{"test.ledger.text":false}`},
		{"f-false", "open", `{"test.ledger.flag":false}`},
		{"f-null", "open", `{"test.ledger.flag":null}`},
	} {
		s.put(t, b.id, b.status, b.metadata)
	}
	s.MakeReady("s-value", "s-empty", "s-false-text", "s-true", "s-false", "s-null")
	held := []string{"s-empty", "s-false-text", "s-true", "s-value"}
	l := New(s)
	sorted := func(rs []*Record) []string { return slices.Sorted(slices.Values(recordIDs(rs))) }
	for _, c := range []struct {
		name string
		sel  Selection
		want []string
	}{
		{"a String key's beads", Carrying(testShell), held},
		{"a String key's beads, closed ones too", Carrying(testShell).WithClosed(), append([]string{"s-closed"}, held...)},
		{"the beads of a key with an alias", Carrying(testText), []string{"t-alias"}},
		{"a JSON flag's beads", Carrying(testFlag), []string{"f-false"}},
	} {
		for _, via := range []struct {
			name string
			l    *Ledger
		}{{"the ledger", l}, {"a pass", l.Pass()}} {
			got, err := via.l.Find(c.sel)
			if err != nil || !slices.Equal(sorted(got), c.want) {
				t.Errorf("%s, read through %s = %v, %v; want %v", c.name, via.name, sorted(got), err, c.want)
			}
		}
	}
	p := l.Pass()
	if _, err := p.Find(Every()); err != nil {
		t.Fatal(err)
	}
	before := len(s.Finds())
	if got, err := p.Find(Carrying(testShell)); err != nil || !slices.Equal(sorted(got), held) || len(s.Finds()) != before {
		t.Errorf("a pass that holds every live bead answered %v, %v after %d reads; want %v from its rows", sorted(got), err, len(s.Finds())-before, held)
	}
	if got, err := Ready(l, testShell, ServeRule{}); err != nil || !slices.Equal(sorted(got), held) {
		t.Errorf("the ready beads that carry a String key = %v, %v; want %v", sorted(got), err, held)
	}
}
