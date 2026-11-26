package disposition

import (
	"errors"
	"fmt"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// unread is a store whose read of each bead it names fails, as a lookup that
// fails does.
type unread struct {
	*fake.Store
	ids []string
}

func (s unread) Find(q gcbd.Query) ([]gcbd.Bead, error) {
	for _, id := range q.IDs {
		if slices.Contains(s.ids, id) {
			return nil, &gcbd.ReadError{ID: id, Reason: "the store did not answer"}
		}
	}
	return s.Store.Find(q)
}

func open(id string) fake.Bead { return fake.Bead{ID: id, Status: "open", IssueType: "task"} }

// closedTo is a bead closed with an edge of typ onto next, and the close reason
// given.
func closedTo(id, typ, next, reason string) fake.Bead {
	return fake.Bead{ID: id, Status: "closed", IssueType: "bug", CloseReason: reason,
		Edges: []gcbd.Edge{{Type: typ, ID: next}}}
}

func carrier(t *testing.T, s gcbd.Store, id string) Carried {
	t.Helper()
	got, err := Carrier(ledger.New(s), id)
	if err != nil {
		t.Fatalf("Carrier(%s): %v", id, err)
	}
	return got
}

func TestAnOpenBeadCarriesItsOwnWork(t *testing.T) {
	for _, status := range openStatuses {
		s := fake.New()
		s.Put(fake.Bead{ID: "tk-t", Status: status, IssueType: "bug"})
		if got := carrier(t, s, "tk-t"); got.By != "tk-t" || got.Warning != "" {
			t.Errorf("a %s bead: %+v, want it to carry its own work", status, got)
		}
	}
}

func TestTheChainReachesTheOpenBeadItsEdgesName(t *testing.T) {
	for _, typ := range []string{"supersedes", "duplicates"} {
		s := fake.New()
		s.Put(closedTo("tk-t", typ, "tk-batch", "folded into tk-batch"))
		s.Put(open("tk-batch"))
		if got := carrier(t, s, "tk-t"); got.By != "tk-batch" {
			t.Errorf("a %s edge: %+v, want tk-batch", typ, got)
		}
	}
	s := fake.New()
	s.Put(closedTo("tk-t", "supersedes", "tk-b1", "folded into tk-b1"))
	s.Put(closedTo("tk-b1", "supersedes", "tk-b2", "re-homed to tk-b2"))
	s.Put(fake.Bead{ID: "tk-b2", Status: "blocked", IssueType: "task"})
	if got := carrier(t, s, "tk-t"); got.By != "tk-b2" {
		t.Errorf("a chain through a closed batch: %+v, want tk-b2", got)
	}
}

// A close that names no successor ended the work, and so does a bead in a
// status no open bead holds.
func TestAChainEndsWhereTheWorkEnded(t *testing.T) {
	s := fake.New()
	s.Put(fake.Bead{ID: "tk-fixed", Status: "closed", IssueType: "bug", CloseReason: "Fixed on main"})
	if got := carrier(t, s, "tk-fixed"); got.By != "" || got.Warning != "" {
		t.Errorf("a fixed bead: %+v, want no bead and no warning", got)
	}
	s.Put(closedTo("tk-t", "supersedes", "tk-landed", "folded into tk-landed"))
	s.Put(fake.Bead{ID: "tk-landed", Status: "closed", IssueType: "task", CloseReason: "Merged"})
	if got := carrier(t, s, "tk-t"); got.By != "" {
		t.Errorf("a batch that landed: %+v, want no bead", got)
	}
	s.Put(fake.Bead{ID: "tk-gone", Status: "tombstone", IssueType: "bug"})
	if got := carrier(t, s, "tk-gone"); got.By != "" {
		t.Errorf("a tombstone: %+v, want no bead", got)
	}
}

// A not-needed close names the evidence for its ruling, never a bead that
// carries the work, whether its close reason or a later note records it.
func TestANotNeededRulingEndsTheChain(t *testing.T) {
	for _, tc := range []struct{ name, reason, notes string }{
		{"in its close reason", "not needed, per tk-visit in tk", ""},
		{"in a note of its own close", "", "Disposition 2026-10-10T08:00Z: not needed, per tk-visit in tk."},
		{"in a note recorded after an earlier close", "Closed",
			"Disposition recorded 2026-10-10T09:00Z: not needed, per tk-visit in tk. (Pointer added after the close.)"},
	} {
		s := fake.New()
		b := closedTo("tk-ruled", "supersedes", "tk-visit", tc.reason)
		b.Notes = tc.notes
		s.Put(b)
		s.Put(open("tk-visit"))
		if got := carrier(t, s, "tk-ruled"); got.By != "" {
			t.Errorf("a ruling %s: %+v, want no bead", tc.name, got)
		}
	}
	s := fake.New()
	b := closedTo("tk-moved", "supersedes", "tk-batch", "Closed")
	b.Notes = "Disposition recorded 2026-10-10T09:00Z: not needed, per tk-other in tk."
	s.Put(b)
	s.Put(open("tk-batch"))
	if got := carrier(t, s, "tk-moved"); got.By != "tk-batch" {
		t.Errorf("a ruling that names another bead: %+v, want the edge's tk-batch", got)
	}
}

// The listing row carries an edge onto a bead in another store, which a show
// row leaves out, so the walk follows it.
func TestTheChainFollowsAnEdgeIntoAnotherStore(t *testing.T) {
	s := fake.New()
	s.Put(closedTo("tk-t", "supersedes", "xr-batch", "folded into xr-batch"))
	if got := carrier(t, s, "tk-t"); got.By != "" || !strings.Contains(got.Warning, "but the store holds no such bead") {
		t.Fatalf("an edge onto a bead the store does not hold: %+v, want no bead and the warning", got)
	}
	s.Put(open("xr-batch"))
	if got := carrier(t, s, "tk-t"); got.By != "xr-batch" {
		t.Errorf("an edge onto a bead the store reads: %+v, want xr-batch", got)
	}
}

func TestABrokenChainNamesNoBeadAndSaysWhy(t *testing.T) {
	s := fake.New()
	if got := carrier(t, s, "tk-none"); got.By != "" || got.Warning != "" {
		t.Errorf("a bead the store does not hold: %+v, want no bead and no warning", got)
	}
	s.Put(closedTo("tk-folded", "supersedes", "tk-gone", "folded into tk-gone"))
	got := carrier(t, s, "tk-folded")
	if want := "tk-folded names tk-gone as its successor, but the store holds no such bead"; got.By != "" ||
		!strings.Contains(got.Warning, want) {
		t.Errorf("a dangling edge: %+v, want the warning %q", got, want)
	}
	s.Put(closedTo("tk-a", "supersedes", "tk-b", "folded into tk-b"))
	s.Put(closedTo("tk-b", "supersedes", "tk-a", "re-homed to tk-a"))
	if got := carrier(t, s, "tk-a"); got.By != "" || !strings.Contains(got.Warning, "loops back to tk-a") {
		t.Errorf("a loop: %+v, want no bead and the loop's warning", got)
	}
}

// A chain of MaxEdges reaches its bead, and a longer one names none.
func TestAChainPastTheCapNamesNoBead(t *testing.T) {
	chain := func(edges int) *fake.Store {
		s := fake.New()
		for i := range edges {
			s.Put(closedTo(fmt.Sprintf("tk-c%d", i), "supersedes", fmt.Sprintf("tk-c%d", i+1), "folded"))
		}
		s.Put(open(fmt.Sprintf("tk-c%d", edges)))
		return s
	}
	if got := carrier(t, chain(MaxEdges), "tk-c0"); got.By != fmt.Sprintf("tk-c%d", MaxEdges) {
		t.Errorf("a chain of exactly %d edges: %+v, want its open bead", MaxEdges, got)
	}
	got := carrier(t, chain(MaxEdges+2), "tk-c0")
	if got.By != "" || !strings.Contains(got.Warning, fmt.Sprintf("runs past %d edges", MaxEdges)) {
		t.Errorf("a chain past the cap: %+v, want no bead and the cap's warning", got)
	}
}

// A read that fails anywhere on the chain is an error, never "no bead".
func TestAReadThatFailsIsNoAnswer(t *testing.T) {
	s := fake.New()
	s.Put(closedTo("tk-t", "supersedes", "tk-batch", "folded into tk-batch"))
	s.Put(open("tk-batch"))
	for _, lost := range []string{"tk-t", "tk-batch"} {
		got, err := Carrier(ledger.New(unread{Store: s, ids: []string{lost}}), "tk-t")
		var re *gcbd.ReadError
		if !errors.As(err, &re) || got.By != "" {
			t.Errorf("a read of %s that fails: %+v, %v; want the read error", lost, got, err)
		}
	}
}
