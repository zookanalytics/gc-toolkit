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
	rows, err := s.Rows([]string{"b-1", "b-missing"})
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
