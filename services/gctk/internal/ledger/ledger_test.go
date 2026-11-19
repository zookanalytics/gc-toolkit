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

func TestAnActThatTitlesTheBeadTitlesItInTheSameWrite(t *testing.T) {
	s := fake.New()
	s.Put(fake.Bead{ID: "b-1", Title: "filed before the work", Status: "open"})
	l := New(s)
	w := l.Write("b-1")
	w.Title("fix: name what the work became")
	testText.Set(w, "now")
	if err := l.Commit(w); err != nil {
		t.Fatal(err)
	}
	want := []string{"--title", "fix: name what the work became", "--set-metadata", "test.ledger.text=now"}
	if writes := s.Writes(); len(writes) != 1 || !slices.Equal(writes[0].Args, want) {
		t.Fatalf("writes = %+v, want one update %q", writes, want)
	}
	if row, _ := s.Row("b-1"); row.Title != "fix: name what the work became" || row.Metadata["test.ledger.text"] != "now" {
		t.Errorf("row = %+v", row)
	}

	w = l.Write("b-1")
	w.Title("fix: a title alone")
	if err := l.Commit(w); err != nil {
		t.Errorf("a write that only titles the bead = %v", err)
	}
	if writes := s.Writes(); len(writes) != 2 || !slices.Equal(writes[1].Args, []string{"--title", "fix: a title alone"}) {
		t.Errorf("writes = %+v", writes)
	}
}

// A new bead is one create, which carries its type, its description, its keys
// and the edge from each bead it blocks, so it lands whole or not at all.
func TestAFilingIsOneCreateCarryingItsKeysAndEdges(t *testing.T) {
	s := fake.New()
	s.IDPrefix = "b"
	s.Put(fake.Bead{ID: "b-1", Status: "blocked"})
	l := New(s)
	f := l.File("withdraw the approvals", "task")
	f.Description("why")
	testText.Set(f, "now")
	f.Blocks("b-1")
	id, err := l.Create(f)
	if err != nil {
		t.Fatal(err)
	}
	creates := s.Creates()
	want := []string{"-t", "task", "--description", "why", "--metadata", `{"test.ledger.text":"now"}`, "--deps", "blocks:b-1"}
	if len(creates) != 1 || creates[0].ID != id || creates[0].Title != "withdraw the approvals" || !slices.Equal(creates[0].Args, want) {
		t.Fatalf("creates = %+v, want one create %q", creates, want)
	}
	owner, _ := s.Row("b-1")
	if !slices.ContainsFunc(owner.Edges, func(e gcbd.Edge) bool { return e.Type == gcbd.EdgeBlocks && e.ID == id }) {
		t.Fatalf("the bead the filing blocks has edges %+v, without one onto %s", owner.Edges, id)
	}
	if len(s.Writes()) != 0 {
		t.Fatalf("a filing wrote an update: %+v", s.Writes())
	}
}

// The bead a filing was found from is the new bead's own discovered-from edge,
// in the create's one --deps list after the beads it blocks, and no wait.
func TestAFilingFoundFromABeadCarriesItsDiscoveredFromEdge(t *testing.T) {
	s := fake.New()
	s.IDPrefix = "b"
	s.Put(fake.Bead{ID: "b-1", Status: "blocked"})
	s.Put(fake.Bead{ID: "src", Status: "closed"})
	l := New(s)
	f := l.File("ask", "task")
	f.Blocks("b-1")
	f.From("src")
	id, err := l.Create(f)
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{"-t", "task", "--deps", "blocks:b-1,discovered-from:src"}; !slices.Equal(s.Creates()[0].Args, want) {
		t.Fatalf("the create carried %q, want %q", s.Creates()[0].Args, want)
	}
	row, _ := s.Row(id)
	if len(row.Edges) != 1 || row.Edges[0].Type != "discovered-from" || row.Edges[0].ID != "src" {
		t.Fatalf("the new bead's edges are %+v, want only its discovered-from edge onto src", row.Edges)
	}
}

// A bead a filing waits on is the new bead's own blocks edge onto it, in the
// create's one --deps list after the beads it blocks, so the new bead lands
// with its wait or not at all, and no update follows.
func TestAFilingThatWaitsOnABeadCarriesTheWaitInItsCreate(t *testing.T) {
	s := fake.New()
	s.IDPrefix = "b"
	s.Put(fake.Bead{ID: "b-1", Status: "blocked"})
	s.Put(fake.Bead{ID: "b-2", Status: "open"})
	s.Put(fake.Bead{ID: "src", Status: "closed"})
	l := New(s)
	f := l.File("ask", "task")
	f.Blocks("b-1")
	f.BlockedBy("b-2")
	f.From("src")
	id, err := l.Create(f)
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{"-t", "task", "--deps", "blocks:b-1,blocked-by:b-2,discovered-from:src"}; !slices.Equal(s.Creates()[0].Args, want) {
		t.Fatalf("the create carried %q, want %q", s.Creates()[0].Args, want)
	}
	row, _ := s.Row(id)
	if !slices.ContainsFunc(row.Edges, func(e gcbd.Edge) bool { return e.Type == gcbd.EdgeBlocks && e.ID == "b-2" }) {
		t.Fatalf("the new bead's edges are %+v, without its blocks edge onto b-2", row.Edges)
	}
	if len(s.Writes()) != 0 {
		t.Fatalf("a filing wrote an update: %+v", s.Writes())
	}
}

// A filing whose wait edge would hold nothing files nothing, whether it waits
// on the bead or blocks it, and its error is ErrNotHeld and names that bead
// alone: a bead the store does not hold, and a bead the store holds that
// carries another id prefix than the one the store gives the new bead, which bd
// keeps as an edge into another store.
func TestAFilingWhoseWaitEdgeWouldHoldNothingFilesNothing(t *testing.T) {
	for _, c := range []struct {
		name, far, why string
		blocks         bool
	}{
		{"a wait on a bead the store does not hold", "b-gone", "the store holds no bead b-gone", false},
		{"a wait on a bead of another prefix that the store holds", "rb-held", "rb-held does not carry the id prefix b,", false},
		{"a block of a bead of another prefix that the store holds", "rb-held", "rb-held does not carry the id prefix b,", true},
	} {
		t.Run(c.name, func(t *testing.T) {
			s := fake.New()
			s.IDPrefix = "b"
			s.Put(fake.Bead{ID: "b-1", Status: "blocked"})
			s.Put(fake.Bead{ID: "b-2", Status: "open"})
			s.Put(fake.Bead{ID: "rb-held", Status: "open"})
			l := New(s)
			f := l.File("ask", "task")
			f.Blocks("b-1")
			f.BlockedBy("b-2")
			if c.blocks {
				f.Blocks(c.far)
			} else {
				f.BlockedBy(c.far)
			}
			_, err := l.Create(f)
			var refused *NotHeld
			if !errors.Is(err, ErrNotHeld) || !errors.As(err, &refused) || !strings.Contains(err.Error(), c.why) ||
				strings.Contains(err.Error(), "b-1") || strings.Contains(err.Error(), "b-2") {
				t.Fatalf("the filing = %v; want ErrNotHeld naming %s alone, saying %q", err, c.far, c.why)
			}
			if len(s.Creates())+len(s.Writes()) != 0 {
				t.Fatalf("a refused filing wrote: creates %+v, writes %+v", s.Creates(), s.Writes())
			}
		})
	}
}

// A filing a Set refused, or one that names no title, files nothing, and a
// create the store failed says the bead may have been filed.
func TestAFilingThatCannotLandFilesNothing(t *testing.T) {
	s := fake.New()
	l := New(s)
	f := l.File("t", "task")
	testShell.Set(f, "x")
	if _, err := l.Create(f); err == nil || !strings.Contains(err.Error(), "read-only") {
		t.Fatalf("a filing of a read-only key read as %v", err)
	}
	if _, err := l.Create(l.File(" ", "task")); err == nil {
		t.Fatal("a filing with no title filed")
	}
	if len(s.Creates()) != 0 {
		t.Fatalf("a refused filing reached the store: %+v", s.Creates())
	}
	s.CreateErr = errors.New("bd's create exited 1, so whether it filed the bead is unknown")
	if _, err := l.Create(l.File("t", "task")); err == nil || !strings.Contains(err.Error(), "may not have landed") {
		t.Fatalf("a failed create read as %v", err)
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

// A guarded write carries the guard, the status and the note in its one update,
// lands while the bead still has the status and assignee it is guarded on, and
// otherwise writes nothing and fails with ErrGuard.
func TestAGuardedWriteLandsOnlyOnTheBeadItWasGuardedOn(t *testing.T) {
	s := fake.New()
	s.Put(fake.Bead{ID: "b-1", Status: "blocked", Assignee: "rig/refinery"})
	l := New(s)
	w := l.Write("b-1")
	w.Guard("blocked", "rig/refinery")
	w.Status("closed")
	testText.Set(w, "landed")
	w.Note("PR #7 merged")
	if err := l.Commit(w); err != nil {
		t.Fatal(err)
	}
	want := []string{"--if-status=blocked", "--if-assignee=rig/refinery", "--status=closed",
		"--set-metadata", "test.ledger.text=landed", "--append-notes", "PR #7 merged"}
	if got := s.Writes()[0].Args; !slices.Equal(got, want) {
		t.Fatalf("the update is %q, want %q", got, want)
	}
	b, _ := s.Row("b-1")
	if b.Status != "closed" || b.Notes != "PR #7 merged" || b.Metadata["test.ledger.text"] != "landed" {
		t.Fatalf("the bead reads %+v", b)
	}

	s.Put(fake.Bead{ID: "b-2", Status: "open", Assignee: ""})
	w = l.Write("b-2")
	w.Guard("open", "rig/refinery")
	testText.Set(w, "never")
	err := l.Commit(w)
	if !errors.Is(err, ErrGuard) {
		t.Fatalf("a stale guard failed with %v, want ErrGuard", err)
	}
	if b, _ := s.Row("b-2"); b.Metadata["test.ledger.text"] != "" {
		t.Fatal("a write its guard refused landed")
	}
	if err := l.Commit(l.Write("b-2")); err == nil {
		t.Fatal("a write that changes nothing was committed")
	}
}

// A write that assigns the bead carries the assignee in its one update, after
// the status, and an assignee of "" assigns the bead to nobody, which bd's
// guard on an empty assignee then finds.
func TestAWriteAssignsTheBeadInItsOneUpdate(t *testing.T) {
	s := fake.New()
	s.Put(fake.Bead{ID: "b-1", Status: "open", Assignee: "rig/refinery"})
	l := New(s)
	w := l.Write("b-1")
	w.Guard("open", "rig/refinery")
	w.Status("blocked")
	w.Assignee("")
	testText.Set(w, "waiting")
	if err := l.Commit(w); err != nil {
		t.Fatal(err)
	}
	want := []string{"--if-status=open", "--if-assignee=rig/refinery", "--status=blocked", "--assignee=",
		"--set-metadata", "test.ledger.text=waiting"}
	if got := s.Writes()[0].Args; !slices.Equal(got, want) {
		t.Fatalf("the update is %q, want %q", got, want)
	}
	if b, _ := s.Row("b-1"); b.Status != "blocked" || b.Assignee != "" {
		t.Fatalf("the bead reads %s under %q", b.Status, b.Assignee)
	}
	w = l.Write("b-1")
	w.Guard("blocked", "")
	w.Assignee("rig/refinery")
	if err := l.Commit(w); err != nil {
		t.Fatal(err)
	}
	if got := s.Writes()[1].Args; !slices.Equal(got, []string{"--if-status=blocked", "--if-assignee=", "--assignee=rig/refinery"}) {
		t.Fatalf("an assignment alone is %q", got)
	}
	if b, _ := s.Row("b-1"); b.Assignee != "rig/refinery" {
		t.Fatalf("the bead is assigned to %q", b.Assignee)
	}
}

// A key's reading face reads the key and names it, and offers no write.
func TestAViewReadsItsKey(t *testing.T) {
	s := fake.New()
	s.Put(fake.Bead{ID: "b-1", Status: "open", Metadata: map[string]string{"test.ledger.old_text": "aliased"}})
	snap, err := New(s).Read("b-1")
	if err != nil {
		t.Fatal(err)
	}
	r, _ := snap.Record("b-1")
	v := testText.View()
	if got, ok, err := v.Get(r); err != nil || !ok || got != "aliased" || v.Name() != "test.ledger.text" {
		t.Fatalf("the view read %q, %v, %v as %s", got, ok, err, v.Name())
	}
}

// A blocker is written as the bead's blocks edge onto it, only once it carries
// the bead's id prefix and a read finds it in the store: a bead the store does
// not hold gets no edge and an error that is ErrNotHeld, and a read or an edge
// write that fails writes nothing and fails.
func TestABlockerIsWrittenOnlyOntoABeadTheStoreHolds(t *testing.T) {
	s := fake.New()
	s.Put(fake.Bead{ID: "b-1", Status: "blocked"})
	s.Put(fake.Bead{ID: "b-2", Title: "the run", Status: "open"})
	l := New(s)
	if err := l.AddBlocker("b-1", "b-2"); err != nil {
		t.Fatal(err)
	}
	b, _ := s.Row("b-1")
	if want := []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "b-2", Title: "the run", Status: "open"}}; !slices.Equal(b.Edges, want) || b.Status != "blocked" {
		t.Fatalf("the bead stands %s with edges %+v, want blocked with %+v", b.Status, b.Edges, want)
	}
	if err := l.AddBlocker("b-1", "b-elsewhere"); !errors.Is(err, ErrNotHeld) || !strings.Contains(err.Error(), "holds no bead b-elsewhere") {
		t.Errorf("an edge onto a bead the store does not hold = %v, want ErrNotHeld naming it", err)
	}
	s.FindErr = errors.New("dolt timeout")
	if err := l.AddBlocker("b-1", "b-2"); err == nil || errors.Is(err, ErrNotHeld) {
		t.Errorf("an edge whose read failed = %v, want the read's error", err)
	}
	s.FindErr, s.EdgeErr = nil, errors.New("database is locked")
	if err := l.AddBlocker("b-1", "b-2"); err == nil || !strings.Contains(err.Error(), "did not land") {
		t.Errorf("an edge the store refused = %v", err)
	}
	if b, _ := s.Row("b-1"); len(b.Edges) != 1 {
		t.Errorf("a refused or unread edge was written: %+v", b.Edges)
	}
}

// A blocker of another id prefix than the bead's gets no edge, even when the
// store holds it, because bd keeps an edge between two prefixes as one into
// another store: the error is ErrNotHeld and names the blocker and the prefix.
func TestABlockerOfAnotherPrefixIsRefused(t *testing.T) {
	s := fake.New()
	s.Put(fake.Bead{ID: "b-1", Status: "blocked"})
	s.Put(fake.Bead{ID: "rb-held", Status: "open"})
	l := New(s)
	err := l.AddBlocker("b-1", "rb-held")
	if !errors.Is(err, ErrNotHeld) || !strings.Contains(err.Error(), "rb-held does not carry the id prefix b,") {
		t.Fatalf("an edge onto rb-held from b-1 = %v; want ErrNotHeld naming rb-held and the prefix b", err)
	}
	if len(s.Writes()) != 0 {
		t.Fatalf("a refused edge was written: %+v", s.Writes())
	}
}

// A priority is one update naming every bead it gives the priority, and one that
// does not land fails.
func TestAPriorityIsOneUpdateOfEveryBeadNamed(t *testing.T) {
	s := fake.New()
	for _, id := range []string{"b-1", "b-2", "b-3"} {
		s.Put(fake.Bead{ID: id, Status: "open", Priority: 2})
	}
	l := New(s)
	if err := l.Prioritize(1, "b-1", "b-3"); err != nil {
		t.Fatal(err)
	}
	for id, want := range map[string]int{"b-1": 1, "b-2": 2, "b-3": 1} {
		if b, _ := s.Row(id); b.Priority != want {
			t.Errorf("%s stands at P%d, want P%d", id, b.Priority, want)
		}
	}
	if w := s.Writes(); len(w) != 2 || !slices.Equal(w[0].Args, []string{"--priority=1"}) {
		t.Errorf("writes = %+v, want one per bead named, each --priority=1", w)
	}
	if err := l.Prioritize(1); err != nil || len(s.Writes()) != 2 {
		t.Errorf("a priority of no bead = %v, and wrote %+v", err, s.Writes())
	}
	if err := l.Prioritize(0, "b-1", "b-missing"); err == nil || !strings.Contains(err.Error(), "did not land") {
		t.Errorf("a priority of a bead the store does not hold = %v", err)
	}
}
