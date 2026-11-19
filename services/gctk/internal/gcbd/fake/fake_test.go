package fake

import (
	"errors"
	"slices"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
)

// A row the fake returns decodes as the real store's does: its metadata, its
// status and its own edges, which the blocked set judges as it judges the real
// listing's.
func TestFakeRowsAnswerAsTheStoreDoes(t *testing.T) {
	s := New()
	s.Put(Bead{ID: "b-1", Status: "open", Metadata: map[string]string{"branch": "polecat/b-1"},
		Edges: []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "b-2", Status: "open"}}})
	s.Put(Bead{ID: "b-2", Status: "open"})
	s.List("b-1", "b-2")
	s.Mark("b-1")
	var re *gcbd.ReadError
	if rows, err := s.Rows([]string{"b-1", "b-missing"}); !errors.As(err, &re) || re.ID != "b-missing" || rows != nil {
		t.Fatalf("Rows with a bead the store does not hold = %v, %v; want a *gcbd.ReadError naming b-missing", rows, err)
	}
	rows, err := s.Rows([]string{"b-1"})
	if err != nil || len(rows) != 1 {
		t.Fatalf("Rows = %v, %v; want b-1 alone", rows, err)
	}
	if got := rows[0].Meta("branch"); got != "polecat/b-1" {
		t.Errorf("branch = %q", got)
	}
	set, err := s.Blocked()
	if err != nil {
		t.Fatal(err)
	}
	got, err := set.Answer(&rows[0])
	if err != nil || !got.Blocked || !slices.Equal(got.On, []string{"b-2"}) {
		t.Errorf("Answer = %+v, %v; want blocked on b-2", got, err)
	}
}

func TestFakeUpdateAppliesAndRecordsTheWrite(t *testing.T) {
	s := New()
	s.Put(Bead{ID: "b-1", Status: "open", Metadata: map[string]string{"old": "x"}})
	if _, err := s.Update("b-1", "--set-metadata", "k=v=w", "--unset-metadata", "old", "--status=closed"); err != nil {
		t.Fatal(err)
	}
	b, _ := s.Row("b-1")
	if b.Metadata["k"] != "v=w" || b.Metadata["old"] != "" || b.Status != "closed" {
		t.Errorf("row = %+v", b)
	}
	if w := s.Writes(); len(w) != 1 || w[0].ID != "b-1" {
		t.Errorf("writes = %+v", w)
	}
	if _, err := s.Update("b-missing", "--status", "closed"); err == nil {
		t.Error("a write to a bead the store does not hold landed")
	}
	s.UpdateErr = errors.New("down")
	if _, err := s.Update("b-1", "--status", "open"); err == nil {
		t.Error("UpdateErr did not fail the write")
	}
}

// A show row leaves out an edge whose far bead the store does not hold, and a
// listing row keeps it, as bd's two reads do. Find selects by id, by a key's
// presence or by its value, by a parent, by an issue type or every bead, and
// reads closed beads only when asked.
func TestFakeFindAnswersAsTheListingDoes(t *testing.T) {
	s := New()
	s.Put(Bead{ID: "b-1", Status: "open", IssueType: "task", Metadata: map[string]string{"k": "v"},
		Edges: []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "b-2", Status: "open"}, {Type: gcbd.EdgeBlocks, ID: "xx-1", Status: "open"}}})
	s.Put(Bead{ID: "b-2", Status: "closed", Metadata: map[string]string{"k": "w"},
		Edges: []gcbd.Edge{{Type: gcbd.EdgeParentChild, ID: "b-1"}}})
	shown, err := s.Rows([]string{"b-1"})
	if err != nil {
		t.Fatal(err)
	}
	if e, _ := shown[0].Edges(); len(e) != 1 || e[0].ID != "b-2" || e[0].Status != "open" {
		t.Errorf("the show row's edges = %+v; want b-2 alone, with its status", e)
	}
	found, err := s.Find(gcbd.Query{IDs: []string{"b-1", "gone"}})
	if err != nil || len(found) != 1 {
		t.Fatalf("Find by id = %v, %v; want b-1 alone", found, err)
	}
	if e, _ := found[0].Edges(); len(e) != 2 || e[1].ID != "xx-1" || e[0].Status != "" {
		t.Errorf("the listing row's edges = %+v; want both, with no far status", e)
	}
	if found[0].IssueTypeString() != "task" {
		t.Errorf("issue type = %q", found[0].IssueTypeString())
	}
	for _, tc := range []struct {
		name string
		q    gcbd.Query
		want []string
	}{
		{"a key's presence, live beads alone", gcbd.Query{HasKey: "k"}, []string{"b-1"}},
		{"a key's presence, closed beads too", gcbd.Query{HasKey: "k", Closed: true}, []string{"b-1", "b-2"}},
		{"a key's value", gcbd.Query{Key: "k", Value: "w", Closed: true}, []string{"b-2"}},
		{"every live bead", gcbd.Query{Every: true}, []string{"b-1"}},
		{"the beads under a parent, closed ones included", gcbd.Query{Parent: "b-1", Closed: true}, []string{"b-2"}},
		{"the beads of one type", gcbd.Query{Type: "task", Closed: true}, []string{"b-1"}},
	} {
		rows, err := s.Find(tc.q)
		var got []string
		for _, r := range rows {
			got = append(got, r.ID)
		}
		if err != nil || !slices.Equal(got, tc.want) {
			t.Errorf("%s = %v, %v; want %v", tc.name, got, err, tc.want)
		}
	}
	if len(s.Finds()) != 7 {
		t.Errorf("Finds = %+v; want the seven queries", s.Finds())
	}
	s.Lose("b-2")
	var re *gcbd.ReadError
	if _, err := s.Rows([]string{"b-2"}); !errors.As(err, &re) || re.ID != "b-2" {
		t.Errorf("Rows of a lost bead = %v; want a read error naming it", err)
	}
	if rows, err := s.Find(gcbd.Query{IDs: []string{"b-2"}, Closed: true}); err != nil || len(rows) != 1 {
		t.Errorf("Find of a lost bead = %v, %v; want its row, since a list is one query", rows, err)
	}
}

// The fake's dependents of a bead are the beads with an edge of the type onto
// it, closed ones among them, each the dependent's own row with the edge's type
// and none of its edges, and a bead the store does not hold refuses the read.
func TestFakeDependentsAnswerAsTheDependentsReadDoes(t *testing.T) {
	s := New()
	s.Put(Bead{ID: "b-1", Status: "open"})
	s.Put(Bead{ID: "cv-1", Status: "open", IssueType: "convoy", Metadata: map[string]string{"gc.synthetic": "true"},
		Edges: []gcbd.Edge{{Type: "tracks", ID: "b-1"}}})
	s.Put(Bead{ID: "cv-2", Status: "closed", IssueType: "convoy", Edges: []gcbd.Edge{{Type: "tracks", ID: "b-1"}}})
	s.Put(Bead{ID: "b-2", Status: "open", Edges: []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "b-1"}}})
	rows, err := s.Dependents("b-1", "tracks")
	var got []string
	for _, r := range rows {
		got = append(got, r.ID+"/"+r.DependencyType)
		if e, _ := r.Edges(); len(e) != 0 {
			t.Errorf("%s's dependents row carries edges %+v", r.ID, e)
		}
	}
	if err != nil || !slices.Equal(got, []string{"cv-1/tracks", "cv-2/tracks"}) || rows[0].Meta("gc.synthetic") != "true" {
		t.Errorf("Dependents(b-1, tracks) = %v, %v; want both convoys, with their keys", got, err)
	}
	if rows, err := s.Dependents("gone", "tracks"); err == nil {
		t.Errorf("Dependents of a bead the store does not hold = %v; want a read error", rows)
	}
}

// The fake's ready read of every bead answers each open bead MakeReady named
// that the rule serves, by priority when asked, and refuses a read that names
// both a key and every bead, or neither.
func TestFakeReadyReadsEveryBeadByPriority(t *testing.T) {
	s := New()
	s.Put(Bead{ID: "b-1", Status: "open", Priority: 2})
	s.Put(Bead{ID: "b-2", Status: "open", Priority: 0})
	s.Put(Bead{ID: "b-3", Status: "open", Priority: 1, Assignee: "someone"})
	s.Put(Bead{ID: "b-4", Status: "closed", Priority: 0})
	s.Put(Bead{ID: "b-5", Status: "open", Priority: 1, IssueType: "epic"})
	s.MakeReady("b-1", "b-2", "b-3", "b-4", "b-5")
	rows, err := s.Ready(gcbd.ReadyQuery{Every: true, Unassigned: true, ExcludeTypes: []string{"epic"}, ByPriority: true})
	var got []string
	for _, r := range rows {
		got = append(got, r.ID)
	}
	if err != nil || !slices.Equal(got, []string{"b-2", "b-1"}) {
		t.Errorf("the ready read by priority = %v, %v; want b-2 then b-1", got, err)
	}
	for _, q := range []gcbd.ReadyQuery{{Unassigned: true}, {HasKey: "k", Every: true}} {
		if rows, err := s.Ready(q); err == nil {
			t.Errorf("Ready(%+v) = %v; want a refusal", q, rows)
		}
	}
}

// An update that names further beads writes each of them as it writes the
// first, and writes none when one is a bead the store does not hold. An edge is
// added to the bead's row with the far bead's fields when the store holds it,
// and onto a far bead it does not hold all the same.
func TestFakeUpdateWritesEachBeadNamedAndAddsAnEdge(t *testing.T) {
	s := New()
	s.Put(Bead{ID: "b-1", Status: "open", Priority: 2})
	s.Put(Bead{ID: "b-2", Title: "two", Status: "open", Priority: 2})
	if _, err := s.Update("b-1", "b-2", "--priority=0", "--append-notes", "ranked"); err != nil {
		t.Fatal(err)
	}
	for _, id := range []string{"b-1", "b-2"} {
		if b, _ := s.Row(id); b.Priority != 0 || b.Notes != "ranked" {
			t.Errorf("%s = %+v", id, b)
		}
	}
	if w := s.Writes(); len(w) != 2 || w[1].ID != "b-2" || !slices.Equal(w[1].Args, []string{"--priority=0", "--append-notes", "ranked"}) {
		t.Errorf("writes = %+v", w)
	}
	if _, err := s.Update("b-1", "b-missing", "--priority=1"); err == nil {
		t.Error("an update naming a bead the store does not hold landed")
	}
	if b, _ := s.Row("b-1"); b.Priority != 0 {
		t.Errorf("a refused update wrote b-1: %+v", b)
	}
	if _, err := s.AddEdge("b-1", "b-2", gcbd.EdgeBlocks); err != nil {
		t.Fatal(err)
	}
	if _, err := s.AddEdge("b-1", "zz-9", gcbd.EdgeBlocks); err != nil {
		t.Fatal(err)
	}
	b, _ := s.Row("b-1")
	want := []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "b-2", Title: "two", Status: "open"}, {Type: gcbd.EdgeBlocks, ID: "zz-9"}}
	if !slices.Equal(b.Edges, want) {
		t.Errorf("edges = %+v, want %+v", b.Edges, want)
	}
	if _, err := s.AddEdge("b-missing", "b-2", gcbd.EdgeBlocks); err == nil {
		t.Error("an edge from a bead the store does not hold landed")
	}
	s.EdgeErr = errors.New("down")
	if _, err := s.AddEdge("b-1", "b-2", gcbd.EdgeBlocks); err == nil {
		t.Error("EdgeErr did not fail the edge")
	}
}
