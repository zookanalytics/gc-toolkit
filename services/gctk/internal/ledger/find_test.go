package ledger

import (
	"errors"
	"slices"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
)

// A selection by key reads the key by its declared name, so the domain that
// declared it never spells it, and a selection by id with no ids reads nothing.
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
	} {
		got, err := l.Find(tc.sel)
		if err != nil || !slices.Equal(ids(got), tc.want) {
			t.Errorf("%s = %v, %v; want %v", tc.name, ids(got), err, tc.want)
		}
	}
	got, _ := l.Find(ByID("root"))
	if e, err := got[0].Edges(); err != nil || len(e) != 1 || e[0].ID != "xx-1" || got[0].IssueType() != "task" {
		t.Errorf("the record = %+v, %v; want the listing's edge into another store and the bead's type", e, err)
	}
	before := len(s.Finds())
	if rs, err := l.Find(ByID()); rs != nil || err != nil || len(s.Finds()) != before {
		t.Errorf("a selection of no ids = %v, %v after %d reads; want nothing read", rs, err, len(s.Finds())-before)
	}
	s.FindErr = &gcbd.ReadError{Reason: "gc bd list exited 1"}
	var re *ReadError
	if _, err := l.Find(Carrying(k)); !errors.As(err, &re) {
		t.Errorf("a find that fails = %v, want its read error", err)
	}
}
