package standing

import (
	"reflect"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/gate"
	"github.com/zookanalytics/gc-toolkit/services/gctk/standing/person"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// graph is a store over live beads, the blocks edges between them, the closed
// members beneath its epics and the live runs that work its beads. A bead
// waits on the open beads its blocks edges name, and nothing else holds it.
type graph struct {
	store
	blocks map[string][]person.Blocker
	closed []Bead
	runs   []waits.Run
	// beneath records the parents each read of closed members names.
	beneath *[][]string
}

// graphOf builds a graph: each bead waits on the beads waitsOn names, and
// closed are closed members of the epics their parent-child edges name.
func graphOf(live []Bead, waitsOn map[string][]string, closed ...Bead) graph {
	byID := map[string]Bead{}
	for _, b := range append(slices.Clone(live), closed...) {
		byID[b.ID] = b
	}
	g := graph{store: store{beads: live, holds: map[string]waits.Holds{}}, blocks: map[string][]person.Blocker{},
		closed: closed}
	for _, b := range live {
		h := waits.Holds{ID: b.ID, Status: waits.Clear}
		for _, on := range waitsOn[b.ID] {
			w := byID[on]
			g.blocks[b.ID] = append(g.blocks[b.ID], person.Blocker{ID: w.ID, Title: w.Title, Status: w.Status,
				IssueType: w.IssueType, AwaitType: w.AwaitType, Assignee: w.Assignee})
			if isOpen(w) {
				h.Status = waits.Blocked
				h.Waits = append(h.Waits, waits.Wait{ID: w.ID, Type: "blocks", Title: w.Title, Status: w.Status,
					IssueType: w.IssueType, AwaitType: w.AwaitType})
			}
		}
		g.holds[b.ID] = h
	}
	return g
}

func (g graph) Blockers(ids []string) (map[string][]person.Blocker, error) {
	out := map[string][]person.Blocker{}
	for _, id := range ids {
		out[id] = append([]person.Blocker{}, g.blocks[id]...)
	}
	return out, nil
}

func (g graph) ClosedBeneath(parents []string) ([]Bead, error) {
	if g.beneath != nil {
		*g.beneath = append(*g.beneath, slices.Clone(parents))
	}
	var out []Bead
	for _, b := range g.closed {
		if slices.ContainsFunc(edgesOf(b, "parent-child"), func(p string) bool { return slices.Contains(parents, p) }) {
			out = append(out, b)
		}
	}
	return out, nil
}

func (g graph) LiveRuns() ([]waits.Run, error) { return g.runs, nil }

// Worked names each bead one of the graph's live runs works.
func (g graph) Worked(ids []string) (map[string]bool, error) {
	out := map[string]bool{}
	for _, r := range g.runs {
		if r.Live && slices.Contains(ids, r.Bead) {
			out[r.Bead] = true
		}
	}
	return out, nil
}

// TestAdvance reads how far the city carries a bead, by the rule that placed
// it, and where it stands by what it waits on. Each case reads the bead asked
// about alone, and again with every bead the store holds, and both reads give
// the same answer.
func TestAdvance(t *testing.T) {
	const pool = "gc-toolkit.polecat"
	work := func(id, assignee string) Bead {
		return Bead{ID: id, Title: id, Status: "open", IssueType: "task", Assignee: assignee}
	}
	under := func(b Bead, parent string) Bead {
		b.Edges = append(b.Edges, Edge{ID: parent, Type: "parent-child"})
		return b
	}
	humanGate := Bead{ID: "tk-g", Title: "a question", Status: "open", IssueType: "gate", AwaitType: "human"}
	park := Bead{ID: "tk-park", Title: "parked until the review", Status: "open", IssueType: "gate"}
	stayGate := Bead{ID: "tk-sg", Title: "back when tk-w needs your review", Status: "open", IssueType: "gate",
		AwaitType: gate.NeedsReview}
	epic := Bead{ID: "tk-e", Title: "an epic", Status: "open", IssueType: "epic", Hypothesis: "it helps"}
	decision := Bead{ID: "tk-d", Title: "pick one", Status: "open", IssueType: "decision"}
	advancing := Advance{Advancing: true}

	cases := []struct {
		name     string
		live     []Bead
		waitsOn  map[string][]string
		closed   []Bead
		runs     []waits.Run
		asked    string
		want     Advance
		frontier Verdict
	}{
		{name: "queued work nothing holds advances, and nothing holds it",
			live: []Bead{work("tk-x", pool)}, asked: "tk-x", want: advancing, frontier: VerdictReady},
		{name: "work nobody takes is stuck on itself",
			live: []Bead{work("tk-x", "")}, asked: "tk-x", want: stuck("tk-x", "not-scheduled"), frontier: VerdictReady},
		{name: "work a live run works advances from the run's start",
			live: []Bead{work("tk-x", "")}, runs: []waits.Run{{Root: "tk-root", Bead: "tk-x", Live: true}},
			asked: "tk-x", want: advancing, frontier: VerdictReady},
		{name: "routed work held for the Product Owner waits for the Product Owner",
			live:  []Bead{{ID: "tk-x", Status: "open", IssueType: "task", Assignee: pool, Labels: []string{"hold:mayor"}}},
			asked: "tk-x", want: stuck("tk-x", "for-product-owner"), frontier: VerdictReady},
		{name: "queued work advances behind queued work",
			live: []Bead{work("tk-x", pool), work("tk-y", pool)}, waitsOn: map[string][]string{"tk-x": {"tk-y"}},
			asked: "tk-x", want: advancing, frontier: VerdictAdvancing},
		{name: "queued work behind work nobody takes is stuck on that work",
			live: []Bead{work("tk-x", pool), work("tk-w", "")}, waitsOn: map[string][]string{"tk-x": {"tk-w"}},
			asked: "tk-x", want: stuck("tk-w", "not-scheduled"), frontier: VerdictStuck},
		{name: "queued work is stuck on what stops the first wait that does not advance",
			live: []Bead{work("tk-x", pool), work("tk-a", pool), work("tk-y", pool),
				{ID: "tk-z", Title: "tk-z", Status: "deferred", IssueType: "task", Assignee: pool}},
			waitsOn: map[string][]string{"tk-x": {"tk-a", "tk-y"}, "tk-y": {"tk-z"}},
			asked:   "tk-x", want: stuck("tk-z", "status"), frontier: VerdictStuck},
		{name: "a closed wait holds nothing",
			live: []Bead{work("tk-x", pool)}, waitsOn: map[string][]string{"tk-x": {"tk-done"}},
			closed: []Bead{{ID: "tk-done", Status: "closed", IssueType: "task"}},
			asked:  "tk-x", want: advancing, frontier: VerdictReady},
		{name: "work behind a human gate is stuck on the gate, its own wait",
			live: []Bead{work("tk-x", pool), humanGate}, waitsOn: map[string][]string{"tk-x": {"tk-g"}},
			asked: "tk-x", want: stuck("tk-g", "own-wait"), frontier: VerdictStuck},
		{name: "work behind work behind a human gate is stuck on the gate further along",
			live:    []Bead{work("tk-x", pool), work("tk-y", pool), humanGate},
			waitsOn: map[string][]string{"tk-x": {"tk-y"}, "tk-y": {"tk-g"}},
			asked:   "tk-x", want: stuck("tk-g", "further-along"), frontier: VerdictStuck},
		{name: "work in your queue is stuck on itself, and what it waits on advances apart",
			live: []Bead{work("tk-x", "human"), work("tk-y", pool)}, waitsOn: map[string][]string{"tk-x": {"tk-y"}},
			asked: "tk-x", want: stuck("tk-x", "assigned-to-you"), frontier: VerdictAdvancing},
		{name: "a parked bead is stuck on the gate that parks it",
			live: []Bead{work("tk-x", pool), park}, waitsOn: map[string][]string{"tk-x": {"tk-park"}},
			asked: "tk-x", want: stuck("tk-park", "parked"), frontier: VerdictStuck},
		{name: "a gate that is no human gate is stuck on itself",
			live: []Bead{park}, asked: "tk-park", want: stuck("tk-park", "gate"), frontier: VerdictReady},
		{name: "a question is stuck on itself, and what holds it is read apart",
			live: []Bead{decision}, asked: "tk-d", want: stuck("tk-d", "question"), frontier: VerdictReady},
		{name: "a decision a ruling left waiting on the work it sent advances while that work does",
			live: []Bead{decision, work("tk-w", pool)}, waitsOn: map[string][]string{"tk-d": {"tk-w"}},
			asked: "tk-d", want: advancing, frontier: VerdictAdvancing},
		{name: "a decision a ruling left waiting on work nobody takes is stuck on that work",
			live: []Bead{decision, work("tk-w", "")}, waitsOn: map[string][]string{"tk-d": {"tk-w"}},
			asked: "tk-d", want: stuck("tk-w", "not-scheduled"), frontier: VerdictStuck},
		{name: "a conversation its sitting stays in advances while the work it sent does",
			live: []Bead{
				{ID: "tk-c", Title: "talk", Status: "open", IssueType: "task", Assignee: "gc-toolkit/gc-toolkit.tk-c",
					Edges: []Edge{{ID: "tk-s", Type: "tracks"}}},
				work("tk-s", ""), work("tk-w", pool)},
			waitsOn: map[string][]string{"tk-c": {"tk-w"}},
			asked:   "tk-c", want: advancing, frontier: VerdictAdvancing},
		{name: "a conversation that waits on its stay's gate advances while the work is out",
			live: []Bead{
				{ID: "tk-c", Title: "talk", Status: "open", IssueType: "task", Assignee: "gc-toolkit/gc-toolkit.tk-c",
					Edges: []Edge{{ID: "tk-s", Type: "tracks"}}},
				stayGate, work("tk-s", ""), work("tk-w", pool)},
			waitsOn: map[string][]string{"tk-c": {"tk-sg"}},
			asked:   "tk-c", want: advancing, frontier: VerdictAdvancing},
		{name: "the PR a staying conversation holds advances while the work is out",
			live: []Bead{
				{ID: "tk-c", Title: "talk", Status: "open", IssueType: "task", Assignee: "gc-toolkit/gc-toolkit.tk-c",
					Edges: []Edge{{ID: "tk-w", Type: "tracks"}}},
				stayGate, work("tk-w", pool)},
			waitsOn: map[string][]string{"tk-c": {"tk-sg"}, "tk-w": {"tk-c"}},
			asked:   "tk-w", want: advancing, frontier: VerdictAdvancing},
		{name: "work behind a park is stuck on the park",
			live:    []Bead{work("tk-w", pool), park},
			waitsOn: map[string][]string{"tk-w": {"tk-park"}},
			asked:   "tk-w", want: stuck("tk-park", "parked"), frontier: VerdictStuck},
		{name: "a conversation that answers a question is stuck on the question",
			live: []Bead{
				{ID: "tk-c", Title: "talk", Status: "open", IssueType: "task", Assignee: "human",
					Edges: []Edge{{ID: "tk-s", Type: "tracks"}, {ID: "tk-g", Type: "replies-to"}}},
				work("tk-s", ""), humanGate},
			asked: "tk-c", want: stuck("tk-g", "answers"), frontier: VerdictReady},
		{name: "an epic advances while every open member does",
			live:  []Bead{epic, under(work("tk-m1", pool), "tk-e"), under(work("tk-m2", pool), "tk-e")},
			asked: "tk-e", want: advancing, frontier: VerdictReady},
		{name: "an epic is stuck on what stops the first open member that does not advance",
			live: []Bead{epic, under(work("tk-m1", pool), "tk-e"), under(work("tk-m2", pool), "tk-e"),
				under(work("tk-m3", ""), "tk-e"), work("tk-w", "")},
			waitsOn: map[string][]string{"tk-m2": {"tk-w"}},
			asked:   "tk-e", want: stuck("tk-w", "not-scheduled"), frontier: VerdictReady},
		{name: "an epic's closed members leave it advancing with its open ones",
			live:   []Bead{epic, under(work("tk-m1", pool), "tk-e")},
			closed: []Bead{under(Bead{ID: "tk-m0", Status: "closed", IssueType: "task"}, "tk-e")},
			asked:  "tk-e", want: advancing, frontier: VerdictReady},
		{name: "an epic with no members is stuck on itself",
			live: []Bead{epic}, asked: "tk-e", want: stuck("tk-e", "members"), frontier: VerdictReady},
		{name: "an epic whose members are all closed waits for a ruling",
			live:   []Bead{epic},
			closed: []Bead{under(Bead{ID: "tk-m0", Status: "closed", IssueType: "task"}, "tk-e")},
			asked:  "tk-e", want: stuck("tk-e", "ruling"), frontier: VerdictReady},
		{name: "an epic's open member that is no work, such as a gate, is no member",
			live:  []Bead{epic, under(park, "tk-e")},
			asked: "tk-e", want: stuck("tk-e", "members"), frontier: VerdictReady},
		{name: "a wait with no standing of its own reads unread",
			live:    []Bead{work("tk-x", pool), {ID: "tk-step", Title: "a step", Status: "open", IssueType: "task", Run: true}},
			waitsOn: map[string][]string{"tk-x": {"tk-step"}},
			asked:   "tk-x", want: stuck("tk-step", "unread"), frontier: VerdictStuck},
		{name: "an anchor that waits on the review run that works it advances, as its own work",
			live:    []Bead{work("tk-x", pool), {ID: "tk-root", Title: "mol-pr-review", Status: "open", IssueType: "task", Run: true}},
			waitsOn: map[string][]string{"tk-x": {"tk-root"}},
			runs:    []waits.Run{{Root: "tk-root", Bead: "tk-x", Live: true}},
			asked:   "tk-x", want: advancing, frontier: VerdictAdvancing},
		{name: "an anchor that waits on its own rework advances, as its own work",
			live:    []Bead{work("tk-x", pool), {ID: "tk-rw", Title: "rework", Status: "open", IssueType: "task", Anchor: "tk-x"}},
			waitsOn: map[string][]string{"tk-x": {"tk-rw"}},
			asked:   "tk-x", want: advancing, frontier: VerdictAdvancing},
		{name: "work that waits on another bead's rework waits on that bead",
			live: []Bead{work("tk-x", pool), work("tk-y", ""),
				{ID: "tk-rw", Title: "rework", Status: "open", IssueType: "task", Anchor: "tk-y"}},
			waitsOn: map[string][]string{"tk-x": {"tk-rw"}},
			asked:   "tk-x", want: stuck("tk-y", "not-scheduled"), frontier: VerdictStuck},
		{name: "work that waits on itself through other work reads unread",
			live:    []Bead{work("tk-x", pool), work("tk-y", pool)},
			waitsOn: map[string][]string{"tk-x": {"tk-y"}, "tk-y": {"tk-x"}},
			asked:   "tk-x", want: stuck("tk-x", "unread"), frontier: VerdictStuck},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			g := graphOf(c.live, c.waitsOn, c.closed...)
			g.runs = c.runs
			var every []string
			for _, b := range c.live {
				every = append(every, b.ID)
			}
			for _, ids := range [][]string{{c.asked}, every} {
				r, err := Read(ids, g)
				if err != nil {
					t.Fatalf("asked about %v: %v", ids, err)
				}
				got, ok := r.Advance(c.asked)
				if !ok || got != c.want {
					t.Errorf("asked about %v: Advance = %+v, %v, want %+v", ids, got, ok, c.want)
				}
				if f, ok := r.Frontier(c.asked); !ok || f.Verdict != c.frontier {
					t.Errorf("asked about %v: Frontier = %+v, %v, want %q", ids, f, ok, c.frontier)
				}
			}
		})
	}
}

// TestTheFrontierIsReadForABeadAsked: a read answers the frontier of each bead
// it was asked about, and of no other, though it answers the advance of each
// bead the frontier reads. A closed bead has neither.
func TestTheFrontierIsReadForABeadAsked(t *testing.T) {
	g := graphOf([]Bead{
		{ID: "tk-x", Status: "open", IssueType: "task", Assignee: "gc-toolkit.polecat"},
		{ID: "tk-w", Status: "open", IssueType: "task"},
		{ID: "tk-done", Status: "closed", IssueType: "task"},
	}, map[string][]string{"tk-x": {"tk-w"}})
	r, err := Read([]string{"tk-x", "tk-done"}, g)
	if err != nil {
		t.Fatal(err)
	}
	want := Frontier{Verdict: VerdictStuck, Waits: []Waited{{ID: "tk-w", Advance: stuck("tk-w", "not-scheduled")}}}
	if f, ok := r.Frontier("tk-x"); !ok || !reflect.DeepEqual(f, want) {
		t.Errorf("Frontier(tk-x) = %+v, %v, want %+v", f, ok, want)
	}
	if f, ok := r.Frontier("tk-w"); ok {
		t.Errorf("Frontier(tk-w) = %+v for a bead the read was not asked about", f)
	}
	if adv, ok := r.Advance("tk-w"); !ok || adv != stuck("tk-w", "not-scheduled") {
		t.Errorf("Advance(tk-w) = %+v, %v, want stuck on itself, not-scheduled", adv, ok)
	}
	if a, ok := r.Answer("tk-done"); !ok || a.Rule != RuleClosed {
		t.Errorf("Answer(tk-done) = %+v, %v, want closed", a, ok)
	}
	if adv, ok := r.Advance("tk-done"); ok {
		t.Errorf("Advance(tk-done) = %+v for a closed bead", adv)
	}
	if f, ok := r.Frontier("tk-done"); ok {
		t.Errorf("Frontier(tk-done) = %+v for a closed bead", f)
	}
}

// TestAWaitWhoseHoldsDidNotReadIsStuckOnIt: a wait waits could not answer for
// reads unread, and the bead behind it is stuck on it.
func TestAWaitWhoseHoldsDidNotReadIsStuckOnIt(t *testing.T) {
	g := graphOf([]Bead{
		{ID: "tk-x", Status: "open", IssueType: "task", Assignee: "gc-toolkit.polecat"},
		{ID: "tk-y", Status: "open", IssueType: "task", Assignee: "gc-toolkit.polecat"},
	}, map[string][]string{"tk-x": {"tk-y"}})
	delete(g.holds, "tk-y")
	r, err := Read([]string{"tk-x"}, g)
	if err != nil {
		t.Fatal(err)
	}
	if a, _ := r.Answer("tk-y"); a.Rule != RuleUnread {
		t.Errorf("Answer(tk-y) = %+v, want unread", a)
	}
	if adv, _ := r.Advance("tk-x"); adv != stuck("tk-y", "unread") {
		t.Errorf("Advance(tk-x) = %+v, want stuck on tk-y, unread", adv)
	}
}

// TestUnanswered: a bead the store does not hold, and one with no standing of
// its own, has no answer, and the read says why.
func TestUnanswered(t *testing.T) {
	g := graphOf([]Bead{{ID: "tk-x", Status: "open", IssueType: "task"}}, nil)
	g.store.beads = append(g.store.beads, Bead{ID: "tk-step", Status: "open", IssueType: "task", Run: true})
	r, err := Read([]string{"tk-step", "tk-gone"}, g)
	if err != nil {
		t.Fatal(err)
	}
	for id, want := range map[string]string{"tk-gone": "the store holds no such bead", "tk-step": "it has no standing of its own"} {
		if _, ok := r.Answer(id); ok {
			t.Errorf("Answer(%s) answered", id)
		}
		if got := r.Unanswered(id); !strings.HasPrefix(got, want) {
			t.Errorf("Unanswered(%s) = %q, want it to begin %q", id, got, want)
		}
	}
	if got := r.Unanswered("tk-x"); got != "" {
		t.Errorf("Unanswered(tk-x) = %q for a bead the read was not asked about", got)
	}
}

// TestAWaitTheStoreCannotJudgeHolds: a waits-for wait, which the store cannot
// judge yet, leaves the bead behind it stuck on that wait, unread, whatever its
// spawner's own standing, alone or asked beside the spawner.
func TestAWaitTheStoreCannotJudgeHolds(t *testing.T) {
	g := graphOf([]Bead{
		{ID: "tk-x", Status: "open", IssueType: "task", Assignee: "gc-toolkit.polecat"},
		{ID: "tk-spawner", Status: "open", IssueType: "task", Assignee: "gc-toolkit.polecat"},
	}, nil)
	g.holds["tk-x"] = waits.Holds{ID: "tk-x", Status: waits.Unjudged,
		Waits: []waits.Wait{{ID: "tk-spawner", Type: "waits-for", Status: "open", IssueType: "task"}}}
	for _, ids := range [][]string{{"tk-x"}, {"tk-x", "tk-spawner"}} {
		r, err := Read(ids, g)
		if err != nil {
			t.Fatal(err)
		}
		if adv, _ := r.Advance("tk-spawner"); !adv.Advancing {
			t.Errorf("asked about %v: Advance(tk-spawner) = %+v, want advancing", ids, adv)
		}
		if adv, _ := r.Advance("tk-x"); adv != stuck("tk-spawner", "unread") {
			t.Errorf("asked about %v: Advance(tk-x) = %+v, want stuck on tk-spawner, unread", ids, adv)
		}
		want := Frontier{Verdict: VerdictStuck, Waits: []Waited{{ID: "tk-spawner", Advance: stuck("tk-spawner", "unread")}}}
		if f, _ := r.Frontier("tk-x"); !reflect.DeepEqual(f, want) {
			t.Errorf("asked about %v: Frontier(tk-x) = %+v, want %+v", ids, f, want)
		}
	}
}

// TestTheFrontierReadsEachWait: the frontier names each wait behind what holds
// the bead, in waits' order, with how far the city carries it as the verdict
// reads it: the bead's own work advances, and a wait on another bead's work
// reads as that bead.
func TestTheFrontierReadsEachWait(t *testing.T) {
	const pool = "gc-toolkit.polecat"
	g := graphOf([]Bead{
		{ID: "tk-x", Status: "open", IssueType: "task", Assignee: pool},
		{ID: "tk-own", Status: "open", IssueType: "task", Anchor: "tk-x"},
		{ID: "tk-y", Status: "open", IssueType: "task", Assignee: pool},
		{ID: "tk-theirs", Status: "open", IssueType: "task", Anchor: "tk-z"},
		{ID: "tk-z", Status: "open", IssueType: "task"},
	}, map[string][]string{"tk-x": {"tk-own", "tk-y", "tk-theirs"}})
	r, err := Read([]string{"tk-x"}, g)
	if err != nil {
		t.Fatal(err)
	}
	want := Frontier{Verdict: VerdictStuck, Waits: []Waited{
		{ID: "tk-own", Advance: Advance{Advancing: true}},
		{ID: "tk-y", Advance: Advance{Advancing: true}},
		{ID: "tk-theirs", Advance: stuck("tk-z", "not-scheduled")},
	}}
	if f, ok := r.Frontier("tk-x"); !ok || !reflect.DeepEqual(f, want) {
		t.Errorf("Frontier(tk-x) = %+v, %v, want %+v", f, ok, want)
	}
}

// TestClosedMembersAreReadForAnEpicWithNoOpenMember: an epic with an open
// member waits on that member whatever closed beside it, so a read of closed
// members names only the epics answered that have no open member.
func TestClosedMembersAreReadForAnEpicWithNoOpenMember(t *testing.T) {
	member := Bead{ID: "tk-m", Status: "open", IssueType: "task", Assignee: "gc-toolkit.polecat",
		Edges: []Edge{{ID: "tk-busy", Type: "parent-child"}}}
	g := graphOf([]Bead{
		{ID: "tk-busy", Status: "open", IssueType: "epic", Hypothesis: "it helps"}, member,
		{ID: "tk-done", Status: "open", IssueType: "epic", Hypothesis: "it helped"},
		{ID: "tk-idle", Status: "open", IssueType: "epic", Hypothesis: "not asked"},
	}, nil, Bead{ID: "tk-c", Status: "closed", IssueType: "task", Edges: []Edge{{ID: "tk-done", Type: "parent-child"}}})
	var beneath [][]string
	g.beneath = &beneath
	r, err := Read([]string{"tk-busy", "tk-done"}, g)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(beneath, [][]string{{"tk-done"}}) {
		t.Errorf("closed members were read beneath %v, want [[tk-done]]", beneath)
	}
	if a, _ := r.Answer("tk-done"); a.Ask != AskRuling {
		t.Errorf("Answer(tk-done) = %+v, want the ruling its closed member leaves it waiting for", a)
	}
	if a, _ := r.Answer("tk-busy"); a.Rule != RuleMembers {
		t.Errorf("Answer(tk-busy) = %+v, want members", a)
	}
}

// A conversation that waits on its stay's gate stays, in the queued group,
// since the city closes the gate. One behind a park is parked.
func TestAConversationOnItsStaysGateStaysAndOneBehindAParkIsParked(t *testing.T) {
	conv := Bead{ID: "tk-c", Title: "talk", Status: "open", IssueType: "task", Assignee: "gc-toolkit/gc-toolkit.tk-c",
		Edges: []Edge{{ID: "tk-s", Type: "tracks"}}}
	subject := Bead{ID: "tk-s", Title: "tk-s", Status: "open", IssueType: "task"}
	for _, c := range []struct {
		name  string
		on    Bead
		rule  Rule
		group Group
	}{
		{"a stay's gate", Bead{ID: "tk-sg", Title: "back when tk-s needs your review", Status: "open", IssueType: "gate",
			AwaitType: gate.NeedsReview}, RuleStaying, GroupQueued},
		{"a park", Bead{ID: "tk-sg", Title: "parked", Status: "open", IssueType: "gate"}, RuleParked, GroupNotMoving},
	} {
		g := graphOf([]Bead{conv, subject, c.on}, map[string][]string{"tk-c": {"tk-sg"}})
		r, err := Read([]string{"tk-c"}, g)
		if err != nil {
			t.Fatal(err)
		}
		a, ok := r.Answer("tk-c")
		if !ok || a.Rule != c.rule || a.Group != c.group {
			t.Errorf("a conversation behind %s: Answer = %+v, %v; want %s in %s", c.name, a, ok, c.rule, c.group)
		}
	}
}
