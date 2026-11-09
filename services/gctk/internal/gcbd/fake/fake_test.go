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
// presence or by its value, and reads closed beads only when asked.
func TestFakeFindAnswersAsTheListingDoes(t *testing.T) {
	s := New()
	s.Put(Bead{ID: "b-1", Status: "open", IssueType: "task", Metadata: map[string]string{"k": "v"},
		Edges: []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "b-2", Status: "open"}, {Type: gcbd.EdgeBlocks, ID: "xx-1", Status: "open"}}})
	s.Put(Bead{ID: "b-2", Status: "closed", Metadata: map[string]string{"k": "w"}})
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
	if len(s.Finds()) != 4 {
		t.Errorf("Finds = %+v; want the four queries", s.Finds())
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
