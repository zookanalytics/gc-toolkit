package prstatus

import (
	"errors"
	"fmt"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/standing/person"
)

// store is a [Store] over fixed answers. Each read is recorded, so a test can
// tell what Read asked for and how often, and fail names a read that errors.
type store struct {
	rows     map[string]Row
	anchored map[string][]Row
	edges    map[string][]person.Blocker
	fail     string
	calls    []string
	statuses [][]string
}

func (s *store) record(read string, ids []string) error {
	s.calls = append(s.calls, read+" "+strings.Join(ids, " "))
	if s.fail == read {
		return fmt.Errorf("%s did not read", read)
	}
	return nil
}

func (s *store) Beads(ids []string) (map[string]Row, error) {
	if err := s.record("beads", ids); err != nil {
		return nil, err
	}
	out := map[string]Row{}
	for _, id := range ids {
		if r, ok := s.rows[id]; ok {
			out[id] = r
		}
	}
	return out, nil
}

func (s *store) Anchored(ids []string, statuses []string) (map[string][]Row, error) {
	s.statuses = append(s.statuses, slices.Clone(statuses))
	if err := s.record("anchored", ids); err != nil {
		return nil, err
	}
	out := map[string][]Row{}
	for _, id := range ids {
		out[id] = s.anchored[id]
	}
	return out, nil
}

func (s *store) Blockers(ids []string) (map[string][]person.Blocker, error) {
	if err := s.record("blockers", ids); err != nil {
		return nil, err
	}
	out := map[string][]person.Blocker{}
	for _, id := range ids {
		out[id] = s.edges[id]
	}
	return out, nil
}

func row(id string, md map[string]string) Row { return Row{ID: id, Metadata: md} }

// Read gathers every fact the rule reads off the anchor's own row, the size of
// its in-flight set, and the gates and the beads a person owes that its walk
// reaches: a blocker of its own, and another PR waiting on a review that its
// rework waits for.
func TestReadGathersTheFacts(t *testing.T) {
	decider := person.Blocker{ID: "d", Title: "pick the release window", Status: "open", IssueType: "decision"}
	other := anchorBlocker("b", awaitingReview)
	s := &store{
		rows: map[string]Row{"a": row("a", map[string]string{
			"merge_hold": "true", "rebase_hold": "1",
			"merge_result": "pull_request_pending",
			"unread":       "x",
		})},
		anchored: map[string][]Row{"a": {row("rw", nil), row("rv", nil)}},
		edges:    map[string][]person.Blocker{"a": {task("rw"), decider}, "rw": {gate("g"), other}},
	}
	facts, err := Read([]string{"a"}, s)
	if err != nil {
		t.Fatal(err)
	}
	got := facts["a"]
	want := Facts{
		MergeHold: "true", RebaseHold: "1",
		Gates:         []person.Blocker{gate("g")},
		Owed:          []person.Blocker{decider, other},
		InFlightCount: 2,
		MergeResult:   "pull_request_pending",
	}
	if fmt.Sprintf("%+v", got) != fmt.Sprintf("%+v", want) {
		t.Errorf("Read gathered\n %+v\nwant\n %+v", got, want)
	}
	if len(s.statuses) != 1 || !slices.Equal(s.statuses[0], InFlightStatuses) {
		t.Errorf("the in-flight set was asked over %v, want InFlightStatuses %v", s.statuses, InFlightStatuses)
	}
}

// The reads are batched across the anchors, and the anchors' own edges are read
// once: they are the walk's first level.
func TestReadBatchesItsReads(t *testing.T) {
	s := &store{
		rows:  map[string]Row{"a": row("a", nil), "b": row("b", nil)},
		edges: map[string][]person.Blocker{"a": {task("rw")}, "b": {task("rw"), task("t")}, "rw": {gate("g")}},
	}
	facts, err := Read([]string{"a", "b", "a"}, s)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"beads a b", "anchored a b", "blockers a b", "blockers rw t", "blockers g"}
	if !slices.Equal(s.calls, want) {
		t.Errorf("reads %q, want %q", s.calls, want)
	}
	for _, id := range []string{"a", "b"} {
		if g := gateIDs(facts[id].Gates); !slices.Equal(g, []string{"g"}) {
			t.Errorf("%s: gates %v, want [g] through the rework both wait on", id, g)
		}
	}
}

// A read that fails answers nothing, wherever it fails, because what it did not
// read could hold any of the anchors.
func TestReadFailsClosed(t *testing.T) {
	for _, read := range []string{"beads", "anchored", "blockers"} {
		t.Run(read, func(t *testing.T) {
			s := &store{rows: map[string]Row{"a": row("a", nil)}, fail: read}
			if facts, err := Read([]string{"a"}, s); err == nil || facts != nil {
				t.Errorf("(%v, %v), want (nil, an error)", facts, err)
			}
		})
	}

	t.Run("a level of the walk", func(t *testing.T) {
		s := &store{rows: map[string]Row{"a": row("a", nil)}, edges: map[string][]person.Blocker{"a": {task("rw")}}}
		calls := 0
		walk := failAt{Store: s, n: 2, calls: &calls}
		if facts, err := Read([]string{"a"}, walk); err == nil || facts != nil {
			t.Errorf("(%v, %v), want (nil, an error): the gates past the failed read are unknown", facts, err)
		}
	})
}

// failAt fails the nth Blockers read.
type failAt struct {
	Store
	n     int
	calls *int
}

func (f failAt) Blockers(ids []string) (map[string][]person.Blocker, error) {
	*f.calls++
	if *f.calls == f.n {
		return nil, errors.New("the level did not read")
	}
	return f.Store.Blockers(ids)
}

// An anchor with no row has no answer, and the others keep theirs. One that no
// read reaches costs no further read.
func TestReadLeavesOutAnAnchorWithNoRow(t *testing.T) {
	s := &store{rows: map[string]Row{"a": row("a", nil)}}
	facts, err := Read([]string{"a", "gone"}, s)
	if _, ok := facts["a"]; !ok || !errors.Is(err, ErrUnresolved) || !strings.Contains(err.Error(), "gone") {
		t.Errorf("(%v, %v), want a's answer and ErrUnresolved naming gone", facts, err)
	}
	if _, ok := facts["gone"]; ok {
		t.Error("an anchor with no row was answered")
	}

	s = &store{}
	facts, err = Read([]string{"gone"}, s)
	if len(facts) != 0 || !errors.Is(err, ErrUnresolved) {
		t.Errorf("(%v, %v), want no answer and ErrUnresolved", facts, err)
	}
	if !slices.Equal(s.calls, []string{"beads gone"}) {
		t.Errorf("reads %q, want only the row's", s.calls)
	}
}

// An anchor whose walk runs past its bound has no answer, because the gates past
// it are unknown, and the others keep theirs.
func TestReadLeavesOutAnAnchorPastTheWalksBound(t *testing.T) {
	s := &store{rows: map[string]Row{"a": row("a", nil), "deep": row("deep", nil)}, edges: map[string][]person.Blocker{"a": {gate("g")}}}
	s.edges["deep"] = []person.Blocker{task("n1")}
	for i := 1; i <= walkDepth; i++ {
		s.edges[fmt.Sprintf("n%d", i)] = []person.Blocker{task(fmt.Sprintf("n%d", i+1))}
	}
	facts, err := Read([]string{"a", "deep"}, s)
	if !errors.Is(err, ErrWalkBound) {
		t.Fatalf("err = %v, want ErrWalkBound", err)
	}
	if _, ok := facts["deep"]; ok {
		t.Error("the anchor past its bound was answered")
	}
	if g := gateIDs(facts["a"].Gates); !slices.Equal(g, []string{"g"}) {
		t.Errorf("a: gates %v, want [g]", g)
	}
}

// Nothing to read reads nothing.
func TestReadOfNoAnchors(t *testing.T) {
	s := &store{}
	if facts, err := Read(nil, s); err != nil || len(facts) != 0 || len(s.calls) != 0 {
		t.Errorf("(%v, %v) after reads %q, want no answer, no error and no read", facts, err, s.calls)
	}
}

// Reasons names each thing behind the held values in their order, each by its
// bead: the gates nearest first, then each bead a person owes nearest first.
func TestReasons(t *testing.T) {
	none := Facts{}
	with := func(f Facts, edit func(*Facts)) Facts { edit(&f); return f }
	d1 := person.Blocker{ID: "d1", Title: "first", Status: "open", IssueType: "decision"}
	d2 := person.Blocker{ID: "d2", Title: "second", Status: "open", IssueType: "decision"}
	b := anchorBlocker("b", awaitingReview)
	for _, tc := range []struct {
		name string
		f    Facts
		want []Reason
	}{
		{"nothing holds the PR", none, nil},
		{"gates nearest first", with(none, func(f *Facts) { f.Gates = []person.Blocker{gate("near"), gate("far")} }),
			[]Reason{{HeldGate, "near", "ask near"}, {HeldGate, "far", "ask far"}}},
		{"each bead a person owes, nearest first", with(none, func(f *Facts) { f.Owed = []person.Blocker{d1, b, d2} }),
			[]Reason{{HeldBlocked, "d1", "first"}, {HeldBlocked, "b", "pr b"}, {HeldBlocked, "d2", "second"}}},
		{"the gates before the beads a person owes", with(none, func(f *Facts) {
			f.Gates, f.Owed = []person.Blocker{gate("g")}, []person.Blocker{d1}
		}), []Reason{{HeldGate, "g", "ask g"}, {HeldBlocked, "d1", "first"}}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got := Reasons(tc.f)
			if !slices.Equal(got, tc.want) {
				t.Errorf("Reasons = %+v, want %+v", got, tc.want)
			}
			var held []Hold
			for _, r := range got {
				if !slices.Contains(held, r.Held) {
					held = append(held, r.Held)
				}
			}
			if !slices.Equal(Held(tc.f), held) {
				t.Errorf("Held = %v, want the values of its reasons %v", Held(tc.f), held)
			}
		})
	}
}

// Read gathers the review runs an anchor's own blocks edges name, open and
// closed, with the head and the target each was poured at, which Render reads
// the run's state from. A blocker that is no review run's root is no run.
func TestReadGathersTheReviewRunsAttachedToTheAnchor(t *testing.T) {
	root := func(id, status, head string) person.Blocker {
		return person.Blocker{ID: id, Status: status, ClosedAt: map[string]string{"closed": "2026-11-12T09:10:00Z"}[status],
			Metadata: map[string]string{"gc.kind": "workflow", "gc.formula_name": "mol-pr-review",
				"gc.var.head": head, "gc.var.target": "main"}}
	}
	other := person.Blocker{ID: "w", Status: "open", Metadata: map[string]string{"gc.kind": "workflow", "gc.formula_name": "mol-polecat-work"}}
	s := &store{
		rows:  map[string]Row{"a": row("a", map[string]string{})},
		edges: map[string][]person.Blocker{"a": {root("r1", "closed", "h1"), root("r2", "open", "h2"), other}},
	}
	facts, err := Read([]string{"a"}, s)
	if err != nil {
		t.Fatal(err)
	}
	f := facts["a"]
	want := []Run{{ID: "r1", Status: "closed", Head: "h1", Target: "main", ClosedAt: "2026-11-12T09:10:00Z"},
		{ID: "r2", Status: "open", Head: "h2", Target: "main"}}
	if !slices.Equal(f.Runs, want) {
		t.Fatalf("Runs = %+v, want %+v", f.Runs, want)
	}
}
