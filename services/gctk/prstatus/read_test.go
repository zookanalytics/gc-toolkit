package prstatus

import (
	"errors"
	"fmt"
	"slices"
	"strings"
	"testing"
)

// store is a [Store] over fixed answers. Each read is recorded, so a test can
// tell what Read asked for and how often, and fail names a read that errors.
type store struct {
	rows     map[string]Row
	anchored map[string][]Row
	edges    map[string][]Blocker
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

func (s *store) Blockers(ids []string) (map[string][]Blocker, error) {
	if err := s.record("blockers", ids); err != nil {
		return nil, err
	}
	out := map[string][]Blocker{}
	for _, id := range ids {
		out[id] = s.edges[id]
	}
	return out, nil
}

func row(id string, md map[string]string) Row { return Row{ID: id, Metadata: md} }

// Read gathers every fact the rule reads off the anchor's own row, the size of
// its in-flight set, the far beads of its own edges and the gates its walk
// reaches.
func TestReadGathersTheFacts(t *testing.T) {
	person := Blocker{ID: "d", Title: "pick the release window", Status: "open", IssueType: "task", RoutedTo: "human"}
	s := &store{
		rows: map[string]Row{"a": row("a", map[string]string{
			"merge_hold": "true", "rebase_hold": "1",
			"pr_posture": "approved@oid@t", "pr.machine": "blocked@oid@t",
			"pr.machine_cause": CauseBlocker, "pr.machine_reason": "held by tk-x",
			"pr.unanswered_threads": "2@oid", "opened_as_draft": "o", "draft_readied": "r",
			"unread": "x",
		})},
		anchored: map[string][]Row{"a": {row("rw", nil), row("rv", nil)}},
		edges:    map[string][]Blocker{"a": {task("rw"), person}, "rw": {gate("g")}},
	}
	facts, err := Read([]string{"a"}, s)
	if err != nil {
		t.Fatal(err)
	}
	got := facts["a"]
	want := Facts{
		MergeHold: "true", RebaseHold: "1",
		Gates:     []Blocker{gate("g")},
		Blockers:  []Blocker{task("rw"), person},
		PRPosture: "approved@oid@t", PRMachine: "blocked@oid@t",
		PRMachineCause: CauseBlocker, PRMachineReason: "held by tk-x",
		PRUnansweredThreads: "2@oid", OpenedAsDraft: "o", DraftReadied: "r",
		InFlightCount: 2,
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
		edges: map[string][]Blocker{"a": {task("rw")}, "b": {task("rw"), task("t")}, "rw": {gate("g")}},
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
		s := &store{rows: map[string]Row{"a": row("a", nil)}, edges: map[string][]Blocker{"a": {task("rw")}}}
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

func (f failAt) Blockers(ids []string) (map[string][]Blocker, error) {
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
	s := &store{rows: map[string]Row{"a": row("a", nil), "deep": row("deep", nil)}, edges: map[string][]Blocker{"a": {gate("g")}}}
	s.edges["deep"] = []Blocker{task("n1")}
	for i := 1; i <= walkDepth; i++ {
		s.edges[fmt.Sprintf("n%d", i)] = []Blocker{task(fmt.Sprintf("n%d", i+1))}
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

// A person owes a live blocker routed to a person, or a live decision, and never
// a human gate, which held: gate counts.
func TestIsPersonBlocker(t *testing.T) {
	for _, tc := range []struct {
		name string
		b    Blocker
		want bool
	}{
		{"routed to a person", Blocker{ID: "d", Status: "open", IssueType: "task", RoutedTo: "human"}, true},
		{"routed to a person, in progress", Blocker{ID: "d", Status: "IN_PROGRESS", RoutedTo: "human"}, true},
		{"routed to a person, with no status", Blocker{ID: "d", RoutedTo: "human"}, true},
		{"a decision", Blocker{ID: "d", Status: "open", IssueType: "decision"}, true},
		{"a decision in any case", Blocker{ID: "d", Status: "open", IssueType: "Decision"}, true},
		{"closed", Blocker{ID: "d", Status: "closed", RoutedTo: "human"}, false},
		{"closed in any case", Blocker{ID: "d", Status: "Closed", IssueType: "decision"}, false},
		{"routed to a pool", Blocker{ID: "d", Status: "open", RoutedTo: "gc-toolkit/gc-toolkit.polecat"}, false},
		{"a task nothing routes", Blocker{ID: "d", Status: "open", IssueType: "task"}, false},
		{"a human gate routed to a person", Blocker{ID: "g", Status: "open", IssueType: "gate", AwaitType: "human", RoutedTo: "human"}, false},
		{"a timer gate routed to a person", Blocker{ID: "g", Status: "open", IssueType: "gate", AwaitType: "timer", RoutedTo: "human"}, true},
	} {
		if got := IsPersonBlocker(tc.b); got != tc.want {
			t.Errorf("%s: IsPersonBlocker(%+v) = %v, want %v", tc.name, tc.b, got, tc.want)
		}
	}
}

// Reasons names each thing behind the held values in their order: the gates
// nearest first, the thread verdict before the unanswered feedback, then each
// blocker a person owes in edge order before the stuck-blocker verdict. A bead
// is named by its id, and what is the PR's own by what it says.
func TestReasons(t *testing.T) {
	approved := Facts{PRPosture: "approved@oid@t"}
	with := func(f Facts, edit func(*Facts)) Facts { edit(&f); return f }
	d1 := Blocker{ID: "d1", Title: "first", Status: "open", RoutedTo: "human"}
	d2 := Blocker{ID: "d2", Title: "second", Status: "open", IssueType: "decision"}
	for _, tc := range []struct {
		name string
		f    Facts
		want []Reason
	}{
		{"nothing holds the PR", approved, nil},
		{"gates nearest first", with(approved, func(f *Facts) { f.Gates = []Blocker{gate("near"), gate("far")} }),
			[]Reason{{HeldGate, "near", "ask near"}, {HeldGate, "far", "ask far"}}},
		{"the thread verdict says its sentence", with(approved, func(f *Facts) {
			f.PRMachine, f.PRMachineCause, f.PRMachineReason = "blocked@oid@t", CauseReviewThreads, "2 unresolved review thread(s) must be resolved before this PR can merge"
		}), []Reason{{HeldReview, "", "2 unresolved review thread(s) must be resolved before this PR can merge"}}},
		{"…or what its cause means when it recorded none", with(approved, func(f *Facts) {
			f.PRMachine, f.PRMachineCause = "blocked@oid@t", CauseReviewThreads
		}), []Reason{{HeldReview, "", "unresolved review threads hold the merge"}}},
		{"one thread waiting on the city's answer", with(approved, func(f *Facts) { f.PRUnansweredThreads = "1@oid" }),
			[]Reason{{HeldReview, "", "1 review thread waits on the city's answer"}}},
		{"several", with(approved, func(f *Facts) { f.PRUnansweredThreads = "3@oid" }),
			[]Reason{{HeldReview, "", "3 review threads wait on the city's answer"}}},
		{"the verdict before the feedback", with(approved, func(f *Facts) {
			f.PRMachine, f.PRMachineCause, f.PRUnansweredThreads = "blocked@oid@t", CauseReviewThreads, "1@oid"
		}), []Reason{{HeldReview, "", "unresolved review threads hold the merge"}, {HeldReview, "", "1 review thread waits on the city's answer"}}},
		{"each blocker a person owes, in edge order", with(approved, func(f *Facts) { f.Blockers = []Blocker{d1, task("t"), d2} }),
			[]Reason{{HeldBlocked, "d1", "first"}, {HeldBlocked, "d2", "second"}}},
		{"the stuck-blocker verdict after them", with(approved, func(f *Facts) {
			f.Blockers = []Blocker{d1}
			f.PRMachine, f.PRMachineCause, f.PRMachineReason = "blocked@oid@t", CauseBlocker, "held by finding tk-x (open), which no automated actor holds or will claim"
		}), []Reason{{HeldBlocked, "d1", "first"}, {HeldBlocked, "", "held by finding tk-x (open), which no automated actor holds or will claim"}}},
		{"…saying what its cause means when it recorded none", with(approved, func(f *Facts) {
			f.PRMachine, f.PRMachineCause = "blocked@oid@t", CauseBlocker
		}), []Reason{{HeldBlocked, "", "a live blocker no automated actor holds"}}},
		{"a gate among the blockers counts once, as a gate", with(approved, func(f *Facts) {
			g := gate("g")
			g.RoutedTo = "human"
			f.Gates, f.Blockers = []Blocker{g}, []Blocker{g}
		}), []Reason{{HeldGate, "g", "ask g"}}},
		{"every value at once", with(approved, func(f *Facts) {
			f.Gates, f.Blockers = []Blocker{gate("g")}, []Blocker{d1}
			f.PRMachine, f.PRMachineCause = "blocked@oid@t", CauseReviewThreads
		}), []Reason{{HeldGate, "g", "ask g"}, {HeldReview, "", "unresolved review threads hold the merge"}, {HeldBlocked, "d1", "first"}}},
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
