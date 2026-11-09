package ledger

import (
	"errors"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
)

type record struct {
	Check  string `json:"check"`
	Result string `json:"result"`
}

// The keys these tests declare, once, as a domain would at its package's start.
var (
	testText   = Declare("test.ledger.text", String, "a plain value", Alias("test.ledger.old_text"))
	testRecord = Declare("test.ledger.record", JSON[record](), "a JSON value")
	testShell  = ReadOnly("test.ledger.shell", String, "a key shell writes")
)

func TestOneActIsOneWrite(t *testing.T) {
	s := fake.New()
	s.Put(fake.Bead{ID: "b-1", Status: "open", Metadata: map[string]string{"test.ledger.old_text": "stale"}})
	l := New(s)
	w := l.Write("b-1")
	testText.Set(w, "now")
	testRecord.Set(w, record{Check: "test", Result: "pass"})
	testText.Clear(l.Write("b-1")) // a second write that is never committed changes nothing
	if err := l.Commit(w); err != nil {
		t.Fatal(err)
	}
	writes := s.Writes()
	want := []string{"--set-metadata", "test.ledger.text=now", "--set-metadata", `test.ledger.record={"check":"test","result":"pass"}`}
	if len(writes) != 1 || !slices.Equal(writes[0].Args, want) {
		t.Fatalf("writes = %+v, want one update %q", writes, want)
	}
	snap, err := l.Read("b-1")
	if err != nil {
		t.Fatal(err)
	}
	r, _ := snap.Record("b-1")
	if v, ok, err := testText.Get(r); err != nil || !ok || v != "now" {
		t.Errorf("text = %q, %v, %v; want the current spelling's value", v, ok, err)
	}
	if v, ok, err := testRecord.Get(r); err != nil || !ok || v != (record{Check: "test", Result: "pass"}) {
		t.Errorf("record = %+v, %v, %v", v, ok, err)
	}
}

func TestAKeyReadsItsAliasAndClearsBoth(t *testing.T) {
	s := fake.New()
	s.Put(fake.Bead{ID: "b-1", Status: "open", Metadata: map[string]string{"test.ledger.old_text": "older", "test.ledger.record": "{not json"}})
	l := New(s)
	snap, err := l.Read("b-1")
	if err != nil {
		t.Fatal(err)
	}
	r, _ := snap.Record("b-1")
	if v, ok, _ := testText.Get(r); !ok || v != "older" {
		t.Errorf("text = %q, %v; want the alias's value", v, ok)
	}
	if _, ok, err := testRecord.Get(r); !ok || err == nil {
		t.Errorf("a value that does not decode = %v, %v; want held and an error", ok, err)
	}
	if _, ok, err := testShell.Get(r); ok || err != nil {
		t.Errorf("an absent key = %v, %v", ok, err)
	}
	w := l.Write("b-1")
	testText.Clear(w)
	if err := l.Commit(w); err != nil {
		t.Fatal(err)
	}
	want := []string{"--unset-metadata", "test.ledger.text", "--unset-metadata", "test.ledger.old_text"}
	if got := s.Writes()[0].Args; !slices.Equal(got, want) {
		t.Errorf("clear = %q, want %q", got, want)
	}
}

func TestAWriteThatCannotLandFails(t *testing.T) {
	s := fake.New()
	s.Put(fake.Bead{ID: "b-1", Status: "open"})
	l := New(s)

	w := l.Write("b-1")
	testShell.Set(w, "x")
	testText.Set(w, "y")
	if err := l.Commit(w); err == nil || !strings.Contains(err.Error(), "read-only") {
		t.Errorf("a read-only key's write = %v", err)
	}
	if err := l.Commit(l.Write("b-1")); err == nil {
		t.Error("an empty write landed")
	}
	s.UpdateErr = errors.New("dolt timeout")
	w = l.Write("b-1")
	testText.Set(w, "y")
	if err := l.Commit(w); err == nil || !strings.Contains(err.Error(), "did not land") {
		t.Errorf("a refused update = %v", err)
	}
	if len(s.Writes()) != 0 {
		t.Errorf("a refused write was recorded: %+v", s.Writes())
	}
}

func TestTheRegistryNamesEachKeysOwnerAndReaders(t *testing.T) {
	byName := map[string]Entry{}
	for _, e := range Registry() {
		byName[e.Name] = e
	}
	if e := byName["test.ledger.text"]; e.Owner != "internal/ledger" || e.Type != "string" || !slices.Equal(e.Aliases, []string{"test.ledger.old_text"}) {
		t.Errorf("text = %+v", e)
	}
	if e := byName["test.ledger.shell"]; e.Owner != "" || !slices.Equal(e.Readers, []string{"internal/ledger"}) {
		t.Errorf("shell = %+v", e)
	}
	if e := byName["test.ledger.record"]; e.Type != "json" {
		t.Errorf("record = %+v", e)
	}
}

func TestContradictingDeclarationsStopTheBinary(t *testing.T) {
	for _, tc := range []struct {
		name   string
		decls  []*decl
		panics bool
	}{
		{"two owners", []*decl{{name: "k", typ: "string", pkg: "a"}, {name: "k", typ: "string", pkg: "b"}}, true},
		{"an owned key declared read-only", []*decl{{name: "k", typ: "string", pkg: "a"}, {name: "k", typ: "string", pkg: "b", readOnly: true}}, true},
		{"a read-only key then owned", []*decl{{name: "k", typ: "string", pkg: "b", readOnly: true}, {name: "k", typ: "string", pkg: "a"}}, true},
		{"two readers of two types", []*decl{{name: "k", typ: "string", pkg: "a", readOnly: true}, {name: "k", typ: "json", pkg: "b", readOnly: true}}, true},
		{"two readers", []*decl{{name: "k", typ: "string", pkg: "a", readOnly: true}, {name: "k", typ: "string", pkg: "b", readOnly: true}}, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			r := &declarations{byName: map[string][]*decl{}}
			panicked := func() (p bool) {
				defer func() { p = recover() != nil }()
				for _, d := range tc.decls {
					r.add(d)
				}
				return false
			}()
			if panicked != tc.panics {
				t.Errorf("panicked = %v, want %v", panicked, tc.panics)
			}
		})
	}
}

// A snapshot holds the beads named and every ancestor, and answers each with
// the store's blocked answer.
func TestASnapshotReadsTheAncestryAndTheStoresAnswers(t *testing.T) {
	s := fake.New()
	s.Put(fake.Bead{ID: "epic", Status: "open", Edges: []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "gate", Status: "open"}}})
	s.Put(fake.Bead{ID: "story", Status: "open", Edges: []gcbd.Edge{{Type: gcbd.EdgeParentChild, ID: "epic", Status: "open"}}})
	s.Put(fake.Bead{ID: "task", Status: "open", Edges: []gcbd.Edge{{Type: gcbd.EdgeParentChild, ID: "story", Status: "open"}}})
	s.Put(fake.Bead{ID: "waiter", Status: "open", Edges: []gcbd.Edge{{Type: gcbd.EdgeWaitsFor, ID: "spawner", Status: "closed"}}})
	s.Put(fake.Bead{ID: "spawner", Status: "closed"})
	s.Put(fake.Bead{ID: "gate", Status: "open"})
	s.List("epic", "gate")
	s.List("story", "epic")
	s.List("task", "story")
	s.Mark("epic", "story", "task", "waiter")
	snap, err := New(s).Read("task", "waiter")
	if err != nil {
		t.Fatal(err)
	}
	for _, id := range []string{"task", "story", "epic", "waiter"} {
		if _, ok := snap.Record(id); !ok {
			t.Errorf("the snapshot did not read %s", id)
		}
	}
	if b, err := snap.Blocking("task"); err != nil || !b.Blocked || b.Through != "story" {
		t.Errorf("task = %+v, %v; want held through story", b, err)
	}
	if b, err := snap.Blocking("epic"); err != nil || !slices.Equal(b.On, []string{"gate"}) {
		t.Errorf("epic = %+v, %v; want blocked on gate", b, err)
	}
	var wf *gcbd.WaitsForError
	if _, err := snap.Blocking("waiter"); !errors.As(err, &wf) {
		t.Errorf("waiter = %v, want the waits-for error", err)
	}
	var re *gcbd.ReadError
	if _, err := snap.Blocking("gate-not-read"); !errors.As(err, &re) {
		t.Errorf("a bead the snapshot did not read = %v, want a read error", err)
	}
	if p, _ := snap.records["task"].Parents(); !slices.Equal(p, []string{"story"}) {
		t.Errorf("task's parents = %q", p)
	}
	if st := snap.records["task"].Status(); st != "open" {
		t.Errorf("task's status = %q", st)
	}
}

// A bead can have several parents, and the snapshot reads the line of each, so
// the store's answer can hold the bead through any of them. Here the listing
// names the parent that holds nothing, and the store holds the bead through its
// other parent, in either order of its edges.
func TestASnapshotReadsEveryParentsLine(t *testing.T) {
	for _, order := range [][]string{{"free", "story"}, {"story", "free"}} {
		s := fake.New()
		s.Put(fake.Bead{ID: "gate", Status: "open"})
		s.Put(fake.Bead{ID: "epic", Status: "open", Edges: []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "gate", Status: "open"}}})
		s.Put(fake.Bead{ID: "story", Status: "open", Edges: []gcbd.Edge{{Type: gcbd.EdgeParentChild, ID: "epic", Status: "open"}}})
		s.Put(fake.Bead{ID: "free-epic", Status: "open"})
		s.Put(fake.Bead{ID: "free", Status: "open", Edges: []gcbd.Edge{{Type: gcbd.EdgeParentChild, ID: "free-epic", Status: "open"}}})
		var edges []gcbd.Edge
		for _, p := range order {
			edges = append(edges, gcbd.Edge{Type: gcbd.EdgeParentChild, ID: p, Status: "open"})
		}
		s.Put(fake.Bead{ID: "task", Status: "open", Edges: edges})
		s.List("epic", "gate")
		s.List("story", "epic")
		s.List("task", "free")
		s.Mark("epic", "story", "task")
		snap, err := New(s).Read("task")
		if err != nil {
			t.Fatalf("edges %v: %v", order, err)
		}
		for _, id := range []string{"task", "free", "free-epic", "story", "epic"} {
			if _, ok := snap.Record(id); !ok {
				t.Errorf("edges %v: the snapshot did not read %s", order, id)
			}
		}
		r, _ := snap.Record("task")
		if p, err := r.Parents(); err != nil || !slices.Equal(p, []string{"free", "story"}) {
			t.Errorf("edges %v: task's parents = %q, %v; want both, sorted", order, p, err)
		}
		if b, err := snap.Blocking("task"); err != nil || !b.Blocked || b.Through != "story" {
			t.Errorf("edges %v: task = %+v, %v; want held through story, the parent the store marks", order, b, err)
		}
	}
}

func TestASnapshotWhoseReadFailsIsAReadError(t *testing.T) {
	s := fake.New()
	s.Put(fake.Bead{ID: "b-1", Status: "open"})
	s.BlockedErr = &gcbd.ReadError{Reason: "gc bd blocked exited 1"}
	var re *gcbd.ReadError
	if _, err := New(s).Read("b-1"); !errors.As(err, &re) {
		t.Errorf("a blocked read that fails = %v, want its read error", err)
	}
	s.BlockedErr, s.FindErr = nil, &gcbd.ReadError{Reason: "gc bd list exited 1"}
	if _, err := New(s).Read("b-1"); !errors.As(err, &re) {
		t.Errorf("a listing read that fails = %v, want its read error", err)
	}
}

// A bead named that the store holds no row for fails the snapshot, since
// without it the snapshot can answer nothing for it. An edge onto a bead the
// listing does not return, a parent among them, is left out of the record, as a
// show row leaves it out, so the bead has no such parent. A blocked listing that
// still names that parent disagrees with the row, and the store's answer for the
// bead is then a read error.
func TestASnapshotWithoutABeadItNeedsIsAReadError(t *testing.T) {
	s := fake.New()
	s.Put(fake.Bead{ID: "orphan", Status: "open", Edges: []gcbd.Edge{{Type: gcbd.EdgeParentChild, ID: "gone-parent", Status: "open"}}})
	var re *gcbd.ReadError
	if snap, err := New(s).Read("gone"); !errors.As(err, &re) || re.ID != "gone" || snap != nil {
		t.Errorf("a bead named that the store does not hold = %v, %v; want a read error naming gone", snap, err)
	}
	snap, err := New(s).Read("orphan")
	if err != nil {
		t.Fatalf("a bead whose parent the listing does not return = %v; want its snapshot", err)
	}
	r, _ := snap.Record("orphan")
	if parents, err := r.Parents(); err != nil || len(parents) != 0 {
		t.Errorf("orphan's parents = %q, %v; want none, since the listing does not return it", parents, err)
	}
	s.List("orphan", "gone-parent")
	s.Mark("orphan")
	snap, err = New(s).Read("orphan")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := snap.Blocking("orphan"); !errors.As(err, &re) || re.ID != "orphan" {
		t.Errorf("a blocked listing naming a parent the row lacks = %v; want a read error naming orphan", err)
	}
}
