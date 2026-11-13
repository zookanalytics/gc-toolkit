package prstatus

import (
	"errors"
	"fmt"
	"slices"
	"strings"
	"testing"
)

func gate(id string) Blocker {
	return Blocker{ID: id, Title: "ask " + id, Status: "open", IssueType: "gate", AwaitType: "human"}
}

func task(id string) Blocker {
	return Blocker{ID: id, Status: "open", IssueType: "task"}
}

func closed(b Blocker) Blocker {
	b.Status = "closed"
	return b
}

// graph is a store's `blocks` edges, as a read answers them. Each read is
// recorded, so a test can tell what the walk asked for and how often.
type graph struct {
	edges map[string][]Blocker
	reads [][]string
}

func (g *graph) read(ids []string) (map[string][]Blocker, error) {
	g.reads = append(g.reads, slices.Clone(ids))
	out := make(map[string][]Blocker, len(ids))
	for _, id := range ids {
		out[id] = g.edges[id]
	}
	return out, nil
}

func gateIDs(gates []Blocker) []string {
	out := []string{}
	for _, g := range gates {
		out = append(out, g.ID)
	}
	return out
}

func TestHoldingGates(t *testing.T) {
	for _, tc := range []struct {
		name  string
		edges map[string][]Blocker
		want  []string
	}{
		{"nothing blocks the bead", nil, []string{}},
		{"a gate on the bead", map[string][]Blocker{"a": {gate("g")}}, []string{"g"}},
		{"a gate on a rework the bead waits on",
			map[string][]Blocker{"a": {task("rw")}, "rw": {gate("g")}}, []string{"g"}},
		{"a gate two beads away",
			map[string][]Blocker{"a": {task("rw")}, "rw": {task("t")}, "t": {gate("g")}}, []string{"g"}},
		{"gates nearest first",
			map[string][]Blocker{"a": {task("rw"), gate("near")}, "rw": {gate("far")}}, []string{"near", "far"}},
		{"a gate reached by two paths reads once",
			map[string][]Blocker{"a": {task("x"), task("y")}, "x": {gate("g")}, "y": {gate("g")}}, []string{"g"}},
		{"a closed gate holds nothing", map[string][]Blocker{"a": {closed(gate("g"))}}, []string{}},
		{"a gate behind a closed blocker holds nothing",
			map[string][]Blocker{"a": {closed(task("rw"))}, "rw": {gate("g")}}, []string{}},
		{"a gate that awaits no person holds nothing itself",
			map[string][]Blocker{"a": {{ID: "t", Status: "open", IssueType: "gate", AwaitType: "timer"}}}, []string{}},
		{"an open gate that awaits no person is still walked through",
			map[string][]Blocker{"a": {{ID: "t", Status: "open", IssueType: "gate", AwaitType: "timer"}}, "t": {gate("g")}}, []string{"g"}},
		{"what a human gate waits on is named beside it",
			map[string][]Blocker{"a": {gate("g")}, "g": {task("t")}, "t": {gate("behind")}}, []string{"g", "behind"}},
		{"a blocker with no status reads open",
			map[string][]Blocker{"a": {{ID: "rw"}}, "rw": {{ID: "g", IssueType: "gate", AwaitType: "human"}}}, []string{"g"}},
		{"status and issue type read in any case",
			map[string][]Blocker{"a": {{ID: "g", Status: "IN_PROGRESS", IssueType: "GATE", AwaitType: "human"},
				{ID: "c", Status: "CLOSED", IssueType: "gate", AwaitType: "human"}}}, []string{"g"}},
		{"a cycle ends",
			map[string][]Blocker{"a": {task("b")}, "b": {task("a"), gate("g")}}, []string{"g"}},
		{"a bead that blocks itself ends", map[string][]Blocker{"a": {task("a")}}, []string{}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			g := &graph{edges: tc.edges}
			got, err := HoldingGates([]string{"a"}, g.read)
			if err != nil {
				t.Fatal(err)
			}
			if ids := gateIDs(got["a"]); !slices.Equal(ids, tc.want) {
				t.Errorf("gates of a = %v, want %v", ids, tc.want)
			}
		})
	}
}

// The gate comes back with the fields a caller names it by.
func TestHoldingGatesKeepTheTitle(t *testing.T) {
	g := &graph{edges: map[string][]Blocker{"a": {task("rw")}, "rw": {gate("g")}}}
	got, err := HoldingGates([]string{"a"}, g.read)
	if err != nil {
		t.Fatal(err)
	}
	if len(got["a"]) != 1 || got["a"][0].Title != "ask g" {
		t.Errorf("gates of a = %+v, want the one titled %q", got["a"], "ask g")
	}
}

// The walks of several anchors read each level once and each bead once, and a gate
// holds only the roots that reach it.
func TestHoldingGatesOverManyRoots(t *testing.T) {
	g := &graph{edges: map[string][]Blocker{
		"a":  {task("rw")},
		"b":  {task("rw"), gate("own")},
		"c":  {task("other")},
		"rw": {gate("shared")},
	}}
	got, err := HoldingGates([]string{"a", "b", "c", "b"}, g.read)
	if err != nil {
		t.Fatal(err)
	}
	for root, want := range map[string][]string{"a": {"shared"}, "b": {"own", "shared"}, "c": {}} {
		if ids := gateIDs(got[root]); !slices.Equal(ids, want) {
			t.Errorf("gates of %s = %v, want %v", root, ids, want)
		}
	}
	read := map[string]int{}
	for _, ids := range g.reads {
		for _, id := range ids {
			read[id]++
		}
	}
	for id, n := range read {
		if n != 1 {
			t.Errorf("%s read %d times, want once: %v", id, n, g.reads)
		}
	}
	// a, b and c; then own, rw and other; then shared.
	if len(g.reads) != 3 {
		t.Errorf("%d reads, want one per level: %v", len(g.reads), g.reads)
	}
}

func TestHoldingGatesFailClosed(t *testing.T) {
	t.Run("a read that fails answers nothing", func(t *testing.T) {
		boom := errors.New("store down")
		calls := 0
		got, err := HoldingGates([]string{"a"}, func(ids []string) (map[string][]Blocker, error) {
			calls++
			if calls == 2 {
				return nil, boom
			}
			return map[string][]Blocker{"a": {gate("near"), task("rw")}}, nil
		})
		if !errors.Is(err, boom) || got != nil {
			t.Errorf("(%v, %v), want (nil, the read's error): the gates past it are unknown", got, err)
		}
	})

	t.Run("a chain past the bound reads as unresolved", func(t *testing.T) {
		g := &graph{edges: map[string][]Blocker{}}
		for i := 0; i <= walkDepth; i++ {
			g.edges[fmt.Sprintf("n%d", i)] = []Blocker{task(fmt.Sprintf("n%d", i+1))}
		}
		got, err := HoldingGates([]string{"n0"}, g.read)
		if _, answered := got["n0"]; answered || !errors.Is(err, ErrWalkBound) {
			t.Errorf("(%v, %v), want no answer for n0 and ErrWalkBound", got, err)
		}
		if len(g.reads) != walkDepth {
			t.Errorf("%d reads, want the bound's %d", len(g.reads), walkDepth)
		}
	})

	t.Run("a chain at the bound reads whole", func(t *testing.T) {
		g := &graph{edges: map[string][]Blocker{}}
		for i := 0; i < walkDepth-1; i++ {
			g.edges[fmt.Sprintf("n%d", i)] = []Blocker{task(fmt.Sprintf("n%d", i+1))}
		}
		g.edges[fmt.Sprintf("n%d", walkDepth-1)] = nil
		if _, err := HoldingGates([]string{"n0"}, g.read); err != nil {
			t.Errorf("a walk of %d levels: %v", walkDepth, err)
		}
	})

	t.Run("a fan past the bound reads as unresolved", func(t *testing.T) {
		wide := make([]Blocker, 0, walkBeads+1)
		for i := 0; i <= walkBeads; i++ {
			wide = append(wide, task(fmt.Sprintf("t%d", i)))
		}
		g := &graph{edges: map[string][]Blocker{"a": wide}}
		if _, err := HoldingGates([]string{"a"}, g.read); !errors.Is(err, ErrWalkBound) {
			t.Errorf("err = %v, want ErrWalkBound", err)
		}
		if len(g.reads) != 1 {
			t.Errorf("%d reads, want only the root's: the bound stops what the walk reads next", len(g.reads))
		}
	})
}

// A root's answer is its own. The label and engage walk one bead and the board a
// rig's anchors together, so a root reads the same in any batch as alone, at each
// bound and one past it, whatever allowance another root leaves unused and however
// much sooner another root's walk reaches the same beads.
func TestHoldingGatesAnswerARootAloneOrInABatch(t *testing.T) {
	edges := map[string][]Blocker{"none": nil, "small": {task("rw")}, "rw": {gate("small-g")}}
	// fan gives a root n blockers, the first a gate, so its walk reaches n+1 beads.
	fan := func(root string, n int) {
		edges[root] = []Blocker{gate(root + "-g")}
		for i := 1; i < n; i++ {
			edges[root] = append(edges[root], task(fmt.Sprintf("%s-t%d", root, i)))
		}
	}
	fan("at", walkBeads-1)
	fan("past", walkBeads)
	// A chain to a gate. From n2 the gate is the last of walkDepth levels, and from
	// n1 it is one level past them.
	for i := range walkDepth {
		edges[fmt.Sprintf("n%d", i)] = []Blocker{task(fmt.Sprintf("n%d", i+1))}
	}
	edges[fmt.Sprintf("n%d", walkDepth)] = []Blocker{gate("chain-g")}

	// What each root answers, and nil for a root past its bound.
	want := map[string][]string{
		"none":  {},
		"small": {"small-g"},
		"at":    {"at-g"},
		"past":  nil,
		"n2":    {"chain-g"},
		"n1":    nil,
	}
	batches := [][]string{
		{"past", "none"},
		{"none", "past"},
		{"past", "small", "at", "none"},
		{"at", "small"},
		{"n1", "n2"},
		{"n2", "n1", "past", "none"},
		{"past", "past"},
	}
	for root := range want {
		batches = append(batches, []string{root})
	}
	for _, batch := range batches {
		t.Run(strings.Join(batch, "+"), func(t *testing.T) {
			g := &graph{edges: edges}
			got, err := HoldingGates(batch, g.read)
			wantNamed := []string{}
			for _, root := range batch {
				ids, answered := got[root]
				if want[root] == nil {
					if !slices.Contains(wantNamed, root) {
						wantNamed = append(wantNamed, root)
					}
					if answered {
						t.Errorf("%s answered %v, want no answer past its bound", root, gateIDs(ids))
					}
				} else if !answered || !slices.Equal(gateIDs(ids), want[root]) {
					t.Errorf("%s answered %v (%v), want %v", root, gateIDs(ids), answered, want[root])
				}
			}
			if anyPast := len(wantNamed) > 0; anyPast != errors.Is(err, ErrWalkBound) || (!anyPast && err != nil) {
				t.Errorf("err = %v, want ErrWalkBound only with a root past its bound", err)
			}
			named := boundRoots(err)
			slices.Sort(named)
			slices.Sort(wantNamed)
			if !slices.Equal(named, wantNamed) {
				t.Errorf("err = %v names %v, want each root past its bound once: %v", err, named, wantNamed)
			}
			read := map[string]int{}
			for _, ids := range g.reads {
				for _, id := range ids {
					read[id]++
				}
			}
			for id, n := range read {
				if n != 1 {
					t.Errorf("%s read %d times, want once", id, n)
				}
			}
			if len(g.reads) > walkDepth {
				t.Errorf("%d reads, past the %d levels one call may read", len(g.reads), walkDepth)
			}
		})
	}
}

// boundRoots is the roots a walk-bound error names, read after ErrWalkBound's own
// words, so a root's name cannot match them.
func boundRoots(err error) []string {
	if err == nil {
		return nil
	}
	_, names, _ := strings.Cut(err.Error(), ErrWalkBound.Error()+": ")
	return strings.Fields(names)
}

// A bead one walk read at an earlier level costs a later walk no read, and a level
// that names only such beads reads nothing.
func TestHoldingGatesShareReadsAcrossLevels(t *testing.T) {
	g := &graph{edges: map[string][]Blocker{"a": {task("x")}, "x": {task("y")}, "b": {task("y")}, "y": {gate("g")}}}
	got, err := HoldingGates([]string{"a", "b"}, g.read)
	if err != nil {
		t.Fatal(err)
	}
	for _, root := range []string{"a", "b"} {
		if ids := gateIDs(got[root]); !slices.Equal(ids, []string{"g"}) {
			t.Errorf("gates of %s = %v, want the gate each walk reaches", root, ids)
		}
	}
	if want := [][]string{{"a", "b"}, {"x", "y"}, {"g"}}; !slices.EqualFunc(g.reads, want, slices.Equal[[]string]) {
		t.Errorf("reads = %v, want %v", g.reads, want)
	}
}

// anchorBlocker is an open bead carrying the metadata a merge anchor records on
// itself.
func anchorBlocker(id string, md map[string]string) Blocker {
	return Blocker{ID: id, Title: "pr " + id, Status: "open", IssueType: "task", Metadata: md}
}

// with returns md with each pair of keys and values added, leaving md as it was.
func with(md map[string]string, kv ...string) map[string]string {
	out := make(map[string]string, len(md)+len(kv)/2)
	for k, v := range md {
		out[k] = v
	}
	for i := 0; i+1 < len(kv); i += 2 {
		out[kv[i]] = kv[i+1]
	}
	return out
}

// awaitingReview is an open pull request the merge pass settled with no approval:
// its next move is a person's review.
var awaitingReview = map[string]string{"merge_result": "pull_request", "pr_posture": "review_required@h@t", "pr.machine": "settled@h@t"}

func decision(id string) Blocker {
	return Blocker{ID: id, Title: "decide " + id, Status: "open", IssueType: "decision"}
}

// The walk keeps the beads a person owes the next move on, other than the human
// gates it keeps apart, wherever they hold the root: on it, or behind a bead it
// waits on. A merge anchor it reaches is weighed by its own state, its own edges
// among it, so another pull request the city is changing or landing holds
// nothing.
func TestHoldingOwed(t *testing.T) {
	for _, tc := range []struct {
		name      string
		edges     map[string][]Blocker
		wantGates []string
		wantOwed  []string
	}{
		{"nothing blocks the bead", nil, []string{}, []string{}},
		{"a decision on the bead", map[string][]Blocker{"a": {decision("d")}}, []string{}, []string{"d"}},
		{"a decision behind a rework",
			map[string][]Blocker{"a": {task("rw")}, "rw": {decision("p")}}, []string{}, []string{"p"}},
		{"another pull request waiting on a review behind a rework",
			map[string][]Blocker{"a": {task("rw")}, "rw": {anchorBlocker("b", awaitingReview)}}, []string{}, []string{"b"}},
		{"another pull request the city is changing",
			map[string][]Blocker{"a": {task("rw")}, "rw": {anchorBlocker("b", awaitingReview)}, "b": {task("b.rw")}}, []string{}, []string{}},
		{"another pull request the city is landing",
			map[string][]Blocker{"a": {task("rw")}, "rw": {anchorBlocker("b", with(awaitingReview, "pr_posture", "approved@h@t"))}}, []string{}, []string{}},
		{"another pull request the merge pass blocked",
			map[string][]Blocker{"a": {task("rw")}, "rw": {anchorBlocker("b", with(awaitingReview, "pr.machine", "blocked@h@t", "pr.machine_cause", "check-failed"))}},
			[]string{}, []string{"b"}},
		{"another pull request under a merge hold",
			map[string][]Blocker{"a": {task("rw")}, "rw": {anchorBlocker("b", with(awaitingReview, "pr_posture", "approved@h@t", "merge_hold", "true"))}},
			[]string{}, []string{"b"}},
		{"another pull request review feedback holds",
			map[string][]Blocker{"a": {task("rw")}, "rw": {anchorBlocker("b", with(awaitingReview, "pr_posture", "approved@h@t", "pr.unanswered_threads", "1@h"))}},
			[]string{}, []string{"b"}},
		{"a pre-open anchor whose checks are done has no pull request to review",
			map[string][]Blocker{"a": {task("rw")}, "rw": {anchorBlocker("b", with(awaitingReview, "merge_result", "pre_open_gate"))}}, []string{}, []string{}},
		{"a pre-open anchor the merge pass blocked",
			map[string][]Blocker{"a": {task("rw")}, "rw": {anchorBlocker("b", with(awaitingReview, "merge_result", "pre_open_gate", "pr.machine", "blocked@h@t", "pr.machine_cause", "rule"))}},
			[]string{}, []string{"b"}},
		{"a bead that is no merge anchor is no review to wait on",
			map[string][]Blocker{"a": {task("rw")}, "rw": {anchorBlocker("t", with(awaitingReview, "merge_result", ""))}}, []string{}, []string{}},
		{"a pull request held only by its gate is the gate's to clear",
			map[string][]Blocker{"a": {task("rw")}, "rw": {anchorBlocker("b", with(awaitingReview, "pr_posture", "approved@h@t"))}, "b": {gate("g")}},
			[]string{"g"}, []string{}},
		{"a pull request waiting on a review and a decision is two moves",
			map[string][]Blocker{"a": {task("rw")}, "rw": {anchorBlocker("b", awaitingReview)}, "b": {decision("d")}}, []string{}, []string{"b", "d"}},
		{"a pull request waiting on a review and a gate is two moves",
			map[string][]Blocker{"a": {task("rw")}, "rw": {anchorBlocker("b", awaitingReview)}, "b": {gate("g")}}, []string{"g"}, []string{"b"}},
		{"of two stacked pull requests the review owed is the one the other waits on",
			map[string][]Blocker{"a": {task("rw")}, "rw": {anchorBlocker("b1", awaitingReview)}, "b1": {anchorBlocker("b2", awaitingReview)}},
			[]string{}, []string{"b2"}},
		{"a pull request that landed holds nothing",
			map[string][]Blocker{"a": {task("rw")}, "rw": {closed(anchorBlocker("b", with(awaitingReview, "merge_result", "merged")))}}, []string{}, []string{}},
		{"a closed decision holds nothing", map[string][]Blocker{"a": {closed(decision("d"))}}, []string{}, []string{}},
		{"a human gate counts once, as a gate",
			map[string][]Blocker{"a": {task("rw")}, "rw": {gate("g")}},
			[]string{"g"}, []string{}},
		{"owed beads nearest first",
			map[string][]Blocker{"a": {task("rw"), decision("near")}, "rw": {decision("far")}}, []string{}, []string{"near", "far"}},
		{"a pull request the bead waits on comes before a decision behind its rework",
			map[string][]Blocker{"a": {task("rw"), anchorBlocker("b", awaitingReview)}, "rw": {decision("d")}}, []string{}, []string{"b", "d"}},
		{"a pull request comes after a decision as near",
			map[string][]Blocker{"a": {anchorBlocker("b", awaitingReview), decision("d")}}, []string{}, []string{"d", "b"}},
		{"a walk back to the root weighs nothing",
			map[string][]Blocker{"a": {task("rw")}, "rw": {anchorBlocker("a", awaitingReview)}}, []string{}, []string{}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			g := &graph{edges: tc.edges}
			got, err := Holding([]string{"a"}, g.read)
			if err != nil {
				t.Fatal(err)
			}
			if ids := gateIDs(got["a"].Gates); !slices.Equal(ids, tc.wantGates) {
				t.Errorf("gates of a = %v, want %v", ids, tc.wantGates)
			}
			if ids := gateIDs(got["a"].Owed); !slices.Equal(ids, tc.wantOwed) {
				t.Errorf("owed of a = %v, want %v", ids, tc.wantOwed)
			}
		})
	}
}

// HoldingGates is Holding's gates, root by root, with its bound and its errors.
func TestHoldingGatesIsHoldingsGates(t *testing.T) {
	g := &graph{edges: map[string][]Blocker{"a": {task("rw"), decision("d")}, "rw": {gate("g")}, "b": nil}}
	gates, err := HoldingGates([]string{"a", "b"}, g.read)
	if err != nil {
		t.Fatal(err)
	}
	if ids := gateIDs(gates["a"]); !slices.Equal(ids, []string{"g"}) {
		t.Errorf("gates of a = %v, want only the gate", ids)
	}
	if ids, answered := gates["b"]; !answered || len(ids) != 0 {
		t.Errorf("gates of b = %v (%v), want an answer with none", ids, answered)
	}
}

// A bead is a human gate only when it is a gate whose await type is human: a
// gate of another await type, or of none, as park's gate declares, is not one,
// and neither is a task. The issue type reads in any case.
func TestIsHumanGate(t *testing.T) {
	for _, tc := range []struct {
		issueType, awaitType string
		want                 bool
	}{
		{"gate", "human", true},
		{"Gate", "human", true},
		{"gate", "", false},
		{"gate", "timer", false},
		{"task", "human", false},
	} {
		if got := IsHumanGate(tc.issueType, tc.awaitType); got != tc.want {
			t.Errorf("IsHumanGate(%q, %q) = %v, want %v", tc.issueType, tc.awaitType, got, tc.want)
		}
	}
}
