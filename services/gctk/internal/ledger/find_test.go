package ledger

import (
	"errors"
	"reflect"
	"slices"
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
