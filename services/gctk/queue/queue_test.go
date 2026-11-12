package queue

import (
	"fmt"
	"math/rand/v2"
	"slices"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

func ids(ps []Place) []string {
	out := []string{}
	for _, p := range ps {
		out = append(out, p.ID)
	}
	return out
}

func layerOf(o Ordered, id string) int {
	for _, p := range append(slices.Clone(o.Queue), o.NotScheduled...) {
		if p.ID == id {
			return p.Layer
		}
	}
	return -1
}

func TestOrder(t *testing.T) {
	work := func(id string, p int, created string, waits ...string) Item {
		return Item{ID: id, Priority: p, CreatedAt: created, Status: "open", Waits: waits, Scheduled: true}
	}

	t.Run("what can go now comes first, then each layer in the pool's claim order", func(t *testing.T) {
		o := Order([]Item{
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
		o := Order([]Item{
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
		o := Order([]Item{
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
		deferred.Status = "deferred"
		claimed := work("tk-b", 2, "2026-01-02")
		claimed.Status = "in_progress"
		hooked := work("tk-c", 2, "2026-01-03")
		hooked.Status = " Hooked "
		o := Order([]Item{deferred, claimed, hooked})
		for id, want := range map[string]int{"tk-a": 1, "tk-b": 0, "tk-c": 0} {
			if got := layerOf(o, id); got != want {
				t.Errorf("%s is in layer %d, want %d", id, got, want)
			}
		}
	})

	t.Run("work nobody scheduled, and work behind it, comes after the queue", func(t *testing.T) {
		unrouted := work("tk-a", 1, "2026-01-01")
		unrouted.Scheduled = false
		o := Order([]Item{
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
	})

	t.Run("a cycle of waits ends, its beads in layer 1 at least", func(t *testing.T) {
		o := Order([]Item{
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

	t.Run("an item named twice is placed once", func(t *testing.T) {
		o := Order([]Item{work("tk-a", 2, "2026-01-01"), work("tk-a", 0, "2026-01-09", "tk-x")})
		if len(o.Queue) != 1 || layerOf(o, "tk-a") != 0 {
			t.Errorf("queue = %+v, want tk-a once, as first named", o.Queue)
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
		var items []Item
		for i := range n {
			it := Item{ID: fmt.Sprintf("tk-%02d", i), Priority: r.IntN(4), CreatedAt: fmt.Sprintf("2026-01-%02d", 1+r.IntN(28)),
				Status: "open", Scheduled: r.IntN(5) > 0}
			if r.IntN(8) == 0 {
				it.Status = "deferred"
			}
			for j := range i {
				if r.IntN(6) == 0 {
					it.Waits = append(it.Waits, fmt.Sprintf("tk-%02d", j))
				}
			}
			if r.IntN(7) == 0 {
				it.Waits = append(it.Waits, "tk-question")
			}
			items = append(items, it)
		}
		r.Shuffle(len(items), func(i, j int) { items[i], items[j] = items[j], items[i] })
		o := Order(items)
		byID := map[string]Item{}
		for _, it := range items {
			byID[it.ID] = it
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
				for _, w := range byID[p.ID].Waits {
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
			for _, w := range byID[p.ID].Waits {
				if after[w] {
					t.Fatalf("round %d: %s is in the queue and waits on %s, which is not scheduled", round, p.ID, w)
				}
			}
		}
		for _, p := range o.NotScheduled {
			it := byID[p.ID]
			if it.Scheduled && !slices.ContainsFunc(it.Waits, func(w string) bool { return after[w] }) {
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
	if got, want := Waiting(h, anchorOf), []string{"tk-a", "tk-b"}; !slices.Equal(got, want) {
		t.Errorf("Waiting = %v, want %v: each wait once, less its own rework and itself", got, want)
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
		{name: "a notice owed is no arm", h: waits.Holds{Arm: &waits.Arm{Notify: "mechanik"}}, want: false},
		{name: "nothing", routedTo: " ", assignee: "", want: false},
		{name: "armed and held for the Product Owner", h: armed, labels: []string{"hold:mayor"}, want: false},
		{name: "routed and held outside the store", routedTo: "gc-toolkit/gc-toolkit.polecat", labels: []string{"hold:external"}, want: false},
		{name: "assigned and held, in any spelling", assignee: "gc-toolkit/gc-toolkit.mechanik", labels: []string{"learning", " Hold:Mayor "}, want: false},
		{name: "in flight and held", h: waits.Holds{InFlight: "status in_progress"}, labels: []string{"hold:mayor"}, want: true},
		{name: "routed, with a label that is no hold", routedTo: "gc-toolkit/gc-toolkit.polecat", labels: []string{"learning", "hold:mayor-later"}, want: true},
	} {
		if got := Scheduled(c.h, c.routedTo, c.assignee, c.labels); got != c.want {
			t.Errorf("%s: Scheduled = %v, want %v", c.name, got, c.want)
		}
	}
}
