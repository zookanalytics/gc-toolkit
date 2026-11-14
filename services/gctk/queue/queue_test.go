package queue

import (
	"errors"
	"fmt"
	"math/rand/v2"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// store is a [Store] over fixed answers. A bead it holds a row for and no
// answer about what holds it reads as clear. Each read is recorded, so a test
// can tell what Order asked for, and fail names a read that errors.
type store struct {
	rows   map[string]Row
	holds  map[string]waits.Holds
	failed map[string]error
	fail   string
	calls  []string
}

func (s *store) record(read string, ids []string) error {
	s.calls = append(s.calls, read+" "+strings.Join(ids, " "))
	if s.fail == read {
		return fmt.Errorf("%s did not read", read)
	}
	return nil
}

func (s *store) Rows(ids []string) (map[string]Row, error) {
	if err := s.record("rows", ids); err != nil {
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

func (s *store) Holds(ids []string) (map[string]waits.Holds, map[string]error, error) {
	if err := s.record("holds", ids); err != nil {
		return nil, nil, err
	}
	holds, failed := map[string]waits.Holds{}, map[string]error{}
	for _, id := range ids {
		if err := s.failed[id]; err != nil {
			failed[id] = err
			continue
		}
		h, ok := s.holds[id]
		if !ok {
			h = waits.Holds{ID: id, Status: waits.Clear}
		}
		holds[id] = h
	}
	return holds, failed, nil
}

func ids(ps []Place) []string {
	out := []string{}
	for _, p := range ps {
		out = append(out, p.ID)
	}
	return out
}

func placeOf(o Ordered, id string) (Place, bool) {
	for _, p := range append(slices.Clone(o.Queue), o.NotScheduled...) {
		if p.ID == id {
			return p, true
		}
	}
	return Place{}, false
}

func layerOf(o Ordered, id string) int {
	if p, ok := placeOf(o, id); ok {
		return p.Layer
	}
	return -1
}

// TestOrderGathersItsOwnInputs places work named by id, and reads through the
// store everything a place depends on: each piece's row and what holds it, and
// the anchor of each bead it waits on.
func TestOrderGathersItsOwnInputs(t *testing.T) {
	polecat := "gc-toolkit/gc-toolkit.polecat"
	wait := func(id string) waits.Wait { return waits.Wait{ID: id, Type: "blocks", Status: "open"} }
	// tk-pr's own rework waits on nothing ahead of it, and tk-w1 waits on
	// tk-pr. Armed tk-w2 waits on question tk-q, which is no work named.
	// tk-held is routed and held for the Product Owner, and assigned tk-behind
	// waits on it.
	read := func() *store {
		return &store{
			rows: map[string]Row{
				"tk-pr":     {ID: "tk-pr", Status: "open", Priority: 2, CreatedAt: "2026-01-01", RoutedTo: polecat},
				"tk-rework": {ID: "tk-rework", Status: "open", Priority: 2, CreatedAt: "2026-01-09", Anchor: "tk-pr"},
				"tk-w1":     {ID: "tk-w1", Status: "open", Priority: 2, CreatedAt: "2026-01-02", RoutedTo: polecat},
				"tk-q":      {ID: "tk-q", Status: "open", Priority: 1, CreatedAt: "2026-01-01"},
				"tk-w2":     {ID: "tk-w2", Status: "open", Priority: 1, CreatedAt: "2026-01-03"},
				"tk-held":   {ID: "tk-held", Status: "open", Priority: 1, CreatedAt: "2026-01-04", RoutedTo: polecat, Labels: []string{"hold:mayor"}},
				"tk-behind": {ID: "tk-behind", Status: "open", Priority: 0, CreatedAt: "2026-01-05", Assignee: "gc-toolkit/gc-toolkit.mechanik"},
			},
			holds: map[string]waits.Holds{
				"tk-pr":     {ID: "tk-pr", Status: waits.Blocked, Waits: []waits.Wait{wait("tk-rework")}},
				"tk-w1":     {ID: "tk-w1", Status: waits.Blocked, Waits: []waits.Wait{wait("tk-pr")}},
				"tk-w2":     {ID: "tk-w2", Status: waits.Blocked, Waits: []waits.Wait{wait("tk-q")}, Arm: &waits.Arm{Target: polecat}},
				"tk-behind": {ID: "tk-behind", Status: waits.Blocked, Waits: []waits.Wait{wait("tk-held")}},
			},
		}
	}
	named := []string{"tk-w1", "tk-pr", "tk-w2", "tk-held", "tk-behind"}

	t.Run("each place comes from the store's rows and waits' answers", func(t *testing.T) {
		s := read()
		o, err := Order(named, s)
		if err != nil {
			t.Fatal(err)
		}
		if got, want := ids(o.Queue), []string{"tk-pr", "tk-w2", "tk-w1"}; !slices.Equal(got, want) {
			t.Errorf("queue = %v, want %v: tk-pr's own rework puts nothing ahead of it", got, want)
		}
		if got, want := ids(o.NotScheduled), []string{"tk-held", "tk-behind"}; !slices.Equal(got, want) {
			t.Errorf("not scheduled = %v, want %v", got, want)
		}
		for id, want := range map[string]Place{
			"tk-pr":     {ID: "tk-pr", Layer: 0, Scheduled: true},
			"tk-w1":     {ID: "tk-w1", Layer: 1, Scheduled: true},
			"tk-w2":     {ID: "tk-w2", Layer: 1, Scheduled: true},
			"tk-held":   {ID: "tk-held", Layer: 0, Scheduled: false},
			"tk-behind": {ID: "tk-behind", Layer: 1, Scheduled: true},
		} {
			if got, _ := placeOf(o, id); got != want {
				t.Errorf("%s is placed %+v, want %+v", id, got, want)
			}
		}
		if len(o.Unread) != 0 {
			t.Errorf("unread = %v, want none", o.Unread)
		}
		want := []string{
			"rows tk-w1 tk-pr tk-w2 tk-held tk-behind",
			"holds tk-w1 tk-pr tk-w2 tk-held tk-behind",
			"rows tk-rework tk-q",
		}
		if !slices.Equal(s.calls, want) {
			t.Errorf("reads = %q, want %q: the waits' beads not yet read, once each", s.calls, want)
		}
	})

	t.Run("work the store holds no row for, or whose waits it could not answer, has no place", func(t *testing.T) {
		s := read()
		s.rows["tk-after"] = Row{ID: "tk-after", Status: "open", Priority: 2, CreatedAt: "2026-01-06", RoutedTo: polecat}
		s.holds["tk-after"] = waits.Holds{ID: "tk-after", Status: waits.Blocked, Waits: []waits.Wait{wait("tk-w1")}}
		s.failed = map[string]error{"tk-w1": errors.New("its edges did not decode")}
		o, err := Order([]string{"tk-gone", "tk-w1", "tk-after"}, s)
		if err != nil {
			t.Fatal(err)
		}
		if !slices.Equal(o.Unread, []string{"tk-gone", "tk-w1"}) {
			t.Errorf("unread = %v, want tk-gone and tk-w1, in the order named", o.Unread)
		}
		if got := ids(o.Queue); !slices.Equal(got, []string{"tk-after"}) || layerOf(o, "tk-after") != 1 {
			t.Errorf("queue = %+v, want tk-after in layer 1, behind a bead that is no work placed", o.Queue)
		}
		if s.calls[1] != "holds tk-w1 tk-after" {
			t.Errorf("reads = %q, want waits asked about the work the store holds alone", s.calls)
		}
	})

	t.Run("a read that fails returns its error and no order", func(t *testing.T) {
		for _, read1 := range []string{"rows", "holds"} {
			s := read()
			s.fail = read1
			o, err := Order(named, s)
			if err == nil || len(o.Queue)+len(o.NotScheduled)+len(o.Unread) != 0 {
				t.Errorf("a failed %s read gave %+v, %v; want its error and no order", read1, o, err)
			}
		}
	})

	t.Run("work named twice is placed once, and nothing named reads nothing", func(t *testing.T) {
		s := read()
		o, err := Order([]string{"tk-pr", "", "tk-pr"}, s)
		if err != nil || !slices.Equal(ids(o.Queue), []string{"tk-pr"}) || s.calls[0] != "rows tk-pr" {
			t.Errorf("Order = %+v, %v after reads %q; want tk-pr once", o, err, s.calls)
		}
		s = read()
		if o, err := Order(nil, s); err != nil || len(o.Queue)+len(o.NotScheduled)+len(o.Unread) != 0 || len(s.calls) != 0 {
			t.Errorf("Order of nothing = %+v, %v after reads %q", o, err, s.calls)
		}
	})
}

func TestOrder(t *testing.T) {
	work := func(id string, p int, created string, waits ...string) item {
		return item{id: id, priority: p, createdAt: created, status: "open", waits: waits, scheduled: true}
	}

	t.Run("what can go now comes first, then each layer in the pool's claim order", func(t *testing.T) {
		o := order([]item{
			work("tk-c", 2, "2026-01-03", "tk-a"),
			work("tk-b", 1, "2026-01-05"),
			work("tk-a", 2, "2026-01-01"),
			work("tk-d", 0, "2026-01-09", "tk-c"),
			work("tk-e", 2, "2026-01-01"),
		})
		if got, want := ids(o.Queue), []string{"tk-b", "tk-a", "tk-e", "tk-c", "tk-d"}; !slices.Equal(got, want) {
			t.Errorf("queue = %v, want %v", got, want)
		}
		for id, want := range map[string]int{"tk-a": 0, "tk-b": 0, "tk-e": 0, "tk-c": 1, "tk-d": 2} {
			if got := layerOf(o, id); got != want {
				t.Errorf("%s is in layer %d, want %d", id, got, want)
			}
		}
	})

	t.Run("a bead sits one layer past the latest of what it waits on", func(t *testing.T) {
		o := order([]item{
			work("tk-a", 2, "2026-01-01"),
			work("tk-b", 2, "2026-01-02", "tk-a"),
			work("tk-c", 2, "2026-01-03", "tk-b"),
			work("tk-d", 0, "2026-01-04", "tk-a", "tk-c"),
		})
		if got := layerOf(o, "tk-d"); got != 3 {
			t.Errorf("tk-d is in layer %d, want 3, past tk-c", got)
		}
		if got, want := ids(o.Queue), []string{"tk-a", "tk-b", "tk-c", "tk-d"}; !slices.Equal(got, want) {
			t.Errorf("queue = %v, want %v: a P0 never sits above what it waits on", got, want)
		}
	})

	t.Run("a wait on a bead that is no item puts it in layer 1", func(t *testing.T) {
		o := order([]item{
			work("tk-a", 2, "2026-01-01", "tk-question"),
			work("tk-b", 3, "2026-01-02"),
			work("tk-c", 2, "2026-01-03", "tk-a"),
		})
		for id, want := range map[string]int{"tk-a": 1, "tk-b": 0, "tk-c": 2} {
			if got := layerOf(o, id); got != want {
				t.Errorf("%s is in layer %d, want %d", id, got, want)
			}
		}
		if got, want := ids(o.Queue), []string{"tk-b", "tk-a", "tk-c"}; !slices.Equal(got, want) {
			t.Errorf("queue = %v, want %v", got, want)
		}
	})

	t.Run("a status that keeps a bead from going puts it in layer 1, and a claim goes", func(t *testing.T) {
		deferred := work("tk-a", 0, "2026-01-01")
		deferred.status = "deferred"
		claimed := work("tk-b", 2, "2026-01-02")
		claimed.status = "in_progress"
		hooked := work("tk-c", 2, "2026-01-03")
		hooked.status = " Hooked "
		o := order([]item{deferred, claimed, hooked})
		for id, want := range map[string]int{"tk-a": 1, "tk-b": 0, "tk-c": 0} {
			if got := layerOf(o, id); got != want {
				t.Errorf("%s is in layer %d, want %d", id, got, want)
			}
		}
	})

	t.Run("work nobody scheduled, and work behind it, comes after the queue", func(t *testing.T) {
		unrouted := work("tk-a", 1, "2026-01-01")
		unrouted.scheduled = false
		o := order([]item{
			unrouted,
			work("tk-b", 1, "2026-01-02", "tk-a"),
			work("tk-c", 1, "2026-01-03", "tk-b"),
			work("tk-d", 3, "2026-01-04"),
		})
		if got, want := ids(o.Queue), []string{"tk-d"}; !slices.Equal(got, want) {
			t.Errorf("queue = %v, want %v", got, want)
		}
		if got, want := ids(o.NotScheduled), []string{"tk-a", "tk-b", "tk-c"}; !slices.Equal(got, want) {
			t.Errorf("not scheduled = %v, want %v", got, want)
		}
		if p, _ := placeOf(o, "tk-b"); !p.Scheduled {
			t.Errorf("tk-b is placed %+v, want it scheduled itself though it sits after the queue", p)
		}
	})

	t.Run("a cycle of waits ends, its beads in layer 1 at least", func(t *testing.T) {
		o := order([]item{
			work("tk-a", 2, "2026-01-01", "tk-b"),
			work("tk-b", 2, "2026-01-02", "tk-a"),
			work("tk-c", 2, "2026-01-03", "tk-c"),
		})
		if len(o.Queue) != 3 {
			t.Fatalf("queue = %+v, want all three", o.Queue)
		}
		for _, id := range []string{"tk-a", "tk-b"} {
			if got := layerOf(o, id); got < 1 {
				t.Errorf("%s is in layer %d, want 1 at least", id, got)
			}
		}
		if got := layerOf(o, "tk-c"); got != 0 {
			t.Errorf("tk-c waits only on itself and is in layer %d, want 0", got)
		}
	})
}

// TestNothingSitsAboveWhatItWaitsOn places many random graphs of waits, with
// beads nobody scheduled among them, and holds every placement to the rule:
// within the queue and after it, a bead comes after every item it waits on,
// and nothing in the queue waits on work after it.
func TestNothingSitsAboveWhatItWaitsOn(t *testing.T) {
	r := rand.New(rand.NewPCG(1, 2))
	for round := range 200 {
		n := 2 + r.IntN(30)
		var items []item
		for i := range n {
			it := item{id: fmt.Sprintf("tk-%02d", i), priority: r.IntN(4), createdAt: fmt.Sprintf("2026-01-%02d", 1+r.IntN(28)),
				status: "open", scheduled: r.IntN(5) > 0}
			if r.IntN(8) == 0 {
				it.status = "deferred"
			}
			for j := range i {
				if r.IntN(6) == 0 {
					it.waits = append(it.waits, fmt.Sprintf("tk-%02d", j))
				}
			}
			if r.IntN(7) == 0 {
				it.waits = append(it.waits, "tk-question")
			}
			items = append(items, it)
		}
		r.Shuffle(len(items), func(i, j int) { items[i], items[j] = items[j], items[i] })
		o := order(items)
		byID := map[string]item{}
		for _, it := range items {
			byID[it.id] = it
		}
		if len(o.Queue)+len(o.NotScheduled) != n {
			t.Fatalf("round %d placed %d of %d", round, len(o.Queue)+len(o.NotScheduled), n)
		}
		for _, list := range [][]Place{o.Queue, o.NotScheduled} {
			at := map[string]int{}
			for i, p := range list {
				at[p.ID] = i
			}
			for i, p := range list {
				if p.Scheduled != byID[p.ID].scheduled {
					t.Fatalf("round %d: %s is placed scheduled %v, want its own %v", round, p.ID, p.Scheduled, byID[p.ID].scheduled)
				}
				for _, w := range byID[p.ID].waits {
					if j, ok := at[w]; ok && j > i {
						t.Fatalf("round %d: %s sits above %s, which it waits on", round, p.ID, w)
					}
				}
			}
		}
		after := map[string]bool{}
		for _, p := range o.NotScheduled {
			after[p.ID] = true
		}
		for _, p := range o.Queue {
			for _, w := range byID[p.ID].waits {
				if after[w] {
					t.Fatalf("round %d: %s is in the queue and waits on %s, which is not scheduled", round, p.ID, w)
				}
			}
		}
		for _, p := range o.NotScheduled {
			it := byID[p.ID]
			if it.scheduled && !slices.ContainsFunc(it.waits, func(w string) bool { return after[w] }) {
				t.Fatalf("round %d: %s is scheduled and waits on nothing after the queue, yet sits after it", round, p.ID)
			}
		}
	}
}

func TestWaiting(t *testing.T) {
	h := waits.Holds{ID: "tk-pr", Waits: []waits.Wait{
		{ID: "tk-rework"}, {ID: "tk-a"}, {ID: "tk-a", Ancestor: "tk-p"}, {ID: "tk-pr"}, {ID: "tk-b"},
	}}
	anchorOf := func(id string) string {
		if id == "tk-rework" {
			return "tk-pr"
		}
		return ""
	}
	if got, want := waiting(h, anchorOf), []string{"tk-a", "tk-b"}; !slices.Equal(got, want) {
		t.Errorf("waiting = %v, want %v: each wait once, less its own rework and itself", got, want)
	}
}

func TestScheduled(t *testing.T) {
	armed := waits.Holds{Arm: &waits.Arm{Target: "gc-toolkit/gc-toolkit.polecat"}}
	for _, c := range []struct {
		name               string
		h                  waits.Holds
		routedTo, assignee string
		labels             []string
		want               bool
	}{
		{name: "in flight", h: waits.Holds{InFlight: "status in_progress"}, want: true},
		{name: "armed", h: armed, want: true},
		{name: "routed", routedTo: "gc-toolkit/gc-toolkit.polecat", want: true},
		{name: "assigned", assignee: "gc-toolkit/gc-toolkit.mechanik", want: true},
		{name: "an arm that names no target sends nothing", h: waits.Holds{Arm: &waits.Arm{Target: " "}}, want: false},
		{name: "nothing", routedTo: " ", assignee: "", want: false},
		{name: "armed and held for the Product Owner", h: armed, labels: []string{"hold:mayor"}, want: false},
		{name: "routed and held outside the store", routedTo: "gc-toolkit/gc-toolkit.polecat", labels: []string{"hold:external"}, want: false},
		{name: "assigned and held, in any spelling", assignee: "gc-toolkit/gc-toolkit.mechanik", labels: []string{"learning", " Hold:Mayor "}, want: false},
		{name: "in flight and held", h: waits.Holds{InFlight: "status in_progress"}, labels: []string{"hold:mayor"}, want: true},
		{name: "routed, with a label that is no hold", routedTo: "gc-toolkit/gc-toolkit.polecat", labels: []string{"learning", "hold:mayor-later"}, want: true},
	} {
		if got := scheduled(c.h, c.routedTo, c.assignee, c.labels); got != c.want {
			t.Errorf("%s: scheduled = %v, want %v", c.name, got, c.want)
		}
	}
}
