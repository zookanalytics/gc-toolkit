package prstatus_test

import (
	"slices"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/prstatus"
)

func blocks(id string) gcbd.Edge { return gcbd.Edge{Type: gcbd.EdgeBlocks, ID: id} }

// anchoredStore holds a PR's bead, tk-a, which waits on a review run's
// failure gate, a closed review run, a bead of another store and the
// rework anchored to it, with the other beads that name it as their anchor: a
// wisp, a gate, and closed work.
func anchoredStore() *fake.Store {
	s := fake.New()
	anchored := map[string]string{"anchor_bead": "tk-a"}
	s.Put(fake.Bead{ID: "tk-a", Title: "the change", Status: "blocked", IssueType: "task",
		Metadata: map[string]string{"merge_result": "pull_request_pending", "merge_hold": "true"},
		Edges:    []gcbd.Edge{blocks("tk-g"), blocks("tk-run"), blocks("xx-1"), blocks("tk-rw"), blocks("tk-g")}})
	s.Put(fake.Bead{ID: "tk-g", Title: "look at the review loop", Status: "open", IssueType: "gate", AwaitType: "human",
		AwaitID: "review-run-failed"})
	s.Put(fake.Bead{ID: "tk-run", Status: "closed", IssueType: "molecule", ClosedAt: "2026-11-20T10:00:00Z",
		Metadata: map[string]string{"gc.kind": "workflow", "gc.formula_name": "mol-pr-review", "gc.var.head": "h"}})
	s.Put(fake.Bead{ID: "tk-rw", Title: "rework the change", Status: "in_progress", IssueType: "task", Metadata: anchored})
	s.Put(fake.Bead{ID: "tk-wisp", Status: "open", IssueType: "task", Ephemeral: true, Metadata: anchored})
	s.Put(fake.Bead{ID: "tk-gate", Status: "open", IssueType: "gate", Metadata: anchored})
	s.Put(fake.Bead{ID: "tk-done", Status: "closed", IssueType: "task", Metadata: anchored})
	return s
}

func rowIDs(rows []*prstatus.Row) []string {
	out := []string{}
	for _, r := range rows {
		out = append(out, r.ID)
	}
	return out
}

// The Store over the ledger reads each bead named, closed ones among them; the
// beads that name an anchor at the statuses asked for, as bd's listing shows
// them, closed ones only when asked; and the far bead of each blocks edge with
// what a gate was filed under, when a bead closed and its record, leaving out
// an edge into another store. A bead it does not hold has no edges to read.
func TestOverReadsTheStore(t *testing.T) {
	s := prstatus.Over(ledger.New(anchoredStore()))
	rows, err := s.Beads([]string{"tk-a", "tk-done", "tk-gone"})
	if err != nil || len(rows) != 2 || rows["tk-a"] == nil || rows["tk-done"] == nil {
		t.Errorf("Beads = %v, %v; want tk-a and the closed tk-done", rows, err)
	}
	for _, tc := range []struct {
		statuses []string
		want     []string
	}{
		{prstatus.InFlightStatuses, []string{"tk-rw"}},
		{[]string{"open", "closed"}, []string{"tk-done"}},
	} {
		got, err := s.Anchored([]string{"tk-a"}, tc.statuses)
		if err != nil || !slices.Equal(rowIDs(got["tk-a"]), tc.want) {
			t.Errorf("Anchored over %v = %v, %v; want %v", tc.statuses, rowIDs(got["tk-a"]), err, tc.want)
		}
	}
	got, err := s.Blockers([]string{"tk-a"})
	if err != nil {
		t.Fatal(err)
	}
	var ids []string
	for _, b := range got["tk-a"] {
		ids = append(ids, b.ID)
		if b.Record == nil || b.Record.ID != b.ID {
			t.Errorf("blocker %s carries the record %+v", b.ID, b.Record)
		}
	}
	if !slices.Equal(ids, []string{"tk-g", "tk-run", "tk-rw"}) {
		t.Fatalf("Blockers = %v; want each far bead this store holds, once, in the edges' order", ids)
	}
	if g := got["tk-a"][0]; g.AwaitType != "human" || g.AwaitID != "review-run-failed" || !prstatus.IsMachineGate(g) {
		t.Errorf("the gate reads %+v; want the human gate a review run's failure filed", g)
	}
	if r := got["tk-a"][1]; r.Status != "closed" || r.ClosedAt != "2026-11-20T10:00:00Z" {
		t.Errorf("the run reads %+v; want it closed, with its close time", r)
	}
	if _, err := s.Blockers([]string{"tk-gone"}); err == nil {
		t.Error("a bead the store does not hold read as one with no blockers")
	}
}

// One run of `gctk pr status` reads what holds a PR and asks the pr domain's
// evaluator through one pass, and reads no bead twice: the anchor, the beads
// its edges name and the beads that name it as their anchor are each read
// once.
func TestOverThroughAPassReadsEachBeadOnce(t *testing.T) {
	st := anchoredStore()
	pass := ledger.New(st).Pass()
	facts, err := prstatus.Read([]string{"tk-a"}, prstatus.Over(pass))
	if err != nil {
		t.Fatal(err)
	}
	if f := facts["tk-a"]; f.InFlightCount != 1 || f.MergeHold != "true" || len(f.Gates) != 1 || len(f.Runs) != 1 || f.Runs[0].Head != "h" {
		t.Errorf("facts = %+v; want the rework in flight, the hold, the gate and the run", f)
	}
	if _, err := pr.FromStore(pass, "tk-a"); err != nil {
		t.Fatal(err)
	}
	named, anchored := map[string]int{}, 0
	for _, q := range st.Finds() {
		for _, id := range q.IDs {
			named[id]++
		}
		if q.Key != "" {
			anchored++
		}
	}
	for id, n := range named {
		if n > 1 {
			t.Errorf("%s was read %d times", id, n)
		}
	}
	if anchored != 1 {
		t.Errorf("the beads anchored to tk-a were read %d times, want once: %+v", anchored, st.Finds())
	}
}
