package ledger

import (
	"slices"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
)

func recordIDs(rs []*Record) []string {
	var out []string
	for _, r := range rs {
		out = append(out, r.ID)
	}
	return out
}

// passStore is a store with live beads, one of them under an epic, a closed
// member of that epic, and a key the live beads carry.
func passStore() *fake.Store {
	s := fake.New()
	under := []gcbd.Edge{{Type: gcbd.EdgeParentChild, ID: "e"}}
	s.Put(fake.Bead{ID: "e", Status: "open", IssueType: "epic"})
	s.Put(fake.Bead{ID: "a", Status: "open", IssueType: "task", Metadata: map[string]string{"gc.x": "cv"}, Edges: under})
	s.Put(fake.Bead{ID: "b", Status: "in_progress", IssueType: "task", Metadata: map[string]string{"gc.x": "other"}})
	s.Put(fake.Bead{ID: "c", Status: "closed", IssueType: "task", Edges: under})
	return s
}

// Once a pass has read every live bead, it answers each selection of live
// beads from those rows, by id, by a key's presence and by its value, and
// reads the store again only for what they cannot answer: a closed bead, once,
// and a bead the store does not hold, once.
func TestPassAnswersLiveSelectionsFromItsListing(t *testing.T) {
	s := passStore()
	k := Key[string]{decl: &decl{name: "gc.x", typ: "string"}, codec: String}
	l := New(s).Pass()
	live, err := l.Find(Every())
	if err != nil || !slices.Equal(recordIDs(live), []string{"a", "b", "e"}) {
		t.Fatalf("every live bead = %v, %v", recordIDs(live), err)
	}
	reads := len(s.Finds())
	for _, tc := range []struct {
		name string
		sel  Selection
		want []string
	}{
		{"the live beads named", ByID("b", "a", "c"), []string{"a", "b"}},
		{"the beads that carry the key", Carrying(k), []string{"a", "b"}},
		{"the beads whose key holds a value", Matching(k, "cv"), []string{"a"}},
		{"every live bead", Every(), []string{"a", "b", "e"}},
	} {
		got, err := l.Find(tc.sel)
		if err != nil || !slices.Equal(recordIDs(got), tc.want) {
			t.Errorf("%s = %v, %v; want %v", tc.name, recordIDs(got), err, tc.want)
		}
	}
	if n := len(s.Finds()) - reads; n != 0 {
		t.Errorf("the live selections read the store %d times, want none", n)
	}
	for range 2 {
		got, err := l.Find(ByID("a", "c", "gone").WithClosed())
		if err != nil || !slices.Equal(recordIDs(got), []string{"a", "c"}) {
			t.Errorf("the beads named, closed ones too = %v, %v; want a and c", recordIDs(got), err)
		}
	}
	if finds := s.Finds()[reads:]; len(finds) != 1 || !slices.Equal(finds[0].IDs, []string{"c", "gone"}) {
		t.Errorf("the reads past the listing = %+v, want one of c and gone", finds)
	}
}

// Every read of a bead through a pass answers with the row it kept first, so
// a write that lands between two reads changes neither: not a read by id, not
// a parent's beads, and not a snapshot.
func TestPassAnswersEachBeadWithTheRowItKeptFirst(t *testing.T) {
	s := passStore()
	l := New(s).Pass()
	if _, err := l.Find(Every()); err != nil {
		t.Fatal(err)
	}
	if live, err := l.Find(Under("e")); err != nil || !slices.Equal(recordIDs(live), []string{"a"}) {
		t.Errorf("the epic's live beads = %v, %v; want a", recordIDs(live), err)
	}
	s.Put(fake.Bead{ID: "a", Status: "closed", IssueType: "task", Edges: []gcbd.Edge{{Type: gcbd.EdgeParentChild, ID: "e"}}})
	got, err := l.Find(ByID("a").WithClosed())
	if err != nil || len(got) != 1 || got[0].Status() != "open" {
		t.Fatalf("a read after the write = %+v, %v; want the row the listing kept, open", got, err)
	}
	members, err := l.Find(Under("e").WithClosed())
	if err != nil || !slices.Equal(recordIDs(members), []string{"a", "c"}) || members[0].Status() != "open" {
		t.Errorf("the epic's beads = %v, %v; want a as the listing kept it, open, and c", recordIDs(members), err)
	}
	snap, err := l.Read("a")
	if err != nil {
		t.Fatal(err)
	}
	if r, ok := snap.Record("a"); !ok || r.Status() != "open" {
		t.Errorf("the snapshot's a = %+v; want the row the listing kept", r)
	}
}

// A pass reads the store's blocked set once, and takes no write.
func TestPassReadsTheBlockedSetOnceAndTakesNoWrite(t *testing.T) {
	s := passStore()
	s.Put(fake.Bead{ID: "a", Status: "open", IssueType: "task", Edges: []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "b"}}})
	s.List("a", "b")
	s.Mark("a")
	l := New(s).Pass()
	for range 2 {
		snap, err := l.Read("a")
		if err != nil {
			t.Fatal(err)
		}
		if ans, err := snap.Blocking("a"); err != nil || !ans.Blocked {
			t.Errorf("a = %+v, %v; want blocked", ans, err)
		}
		s.BlockedErr = &gcbd.ReadError{Reason: "a second read of the blocked set"}
	}
	w := l.Write("a")
	testText.Set(w, "now")
	if err := l.Commit(w); err == nil {
		t.Error("a write through a pass landed")
	}
	if len(s.Writes()) != 0 {
		t.Errorf("the store took %+v", s.Writes())
	}
}

// A record carries the row's own fields, and renders its metadata whole as
// the scripts render it.
func TestRecordCarriesTheRowsFields(t *testing.T) {
	s := fake.New()
	s.Put(fake.Bead{ID: "w", Title: "a task", Status: "open", IssueType: "gate", AwaitType: "human", Assignee: "human",
		Description: "the whole text", Priority: 2, Labels: []string{"hold:mayor"}, CreatedAt: "2026-11-01T00:00:00Z",
		Metadata: map[string]string{"gc.routed_to": "human"}})
	got, err := New(s).Find(ByID("w"))
	if err != nil || len(got) != 1 {
		t.Fatalf("Find = %v, %v", got, err)
	}
	r := got[0]
	if r.Title() != "a task" || r.Description() != "the whole text" || r.Priority() != 2 || r.Assignee() != "human" ||
		!slices.Equal(r.Labels(), []string{"hold:mayor"}) || r.AwaitType() != "human" || r.CreatedAt() != "2026-11-01T00:00:00Z" ||
		r.ClosedAt() != "" {
		t.Errorf("record = %q %q %d %q %q %q %q %q", r.Title(), r.Description(), r.Priority(), r.Assignee(), r.Labels(),
			r.AwaitType(), r.CreatedAt(), r.ClosedAt())
	}
	if md := r.Rendered(); len(md) != 1 || md["gc.routed_to"] != "human" {
		t.Errorf("rendered = %v", md)
	}
}
