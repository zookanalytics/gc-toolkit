// Package queue orders a rig's work the way the city is expected to land it,
// so every reader that lists work in that order, the helm board among them,
// lists it one way. It composes two rules Gas City already has and adds none
// about what holds a bead, which [waits] answers:
//
//   - Execution layers, as bd graph assigns them (computeLayout in beads'
//     cmd/bd/graph.go): a bead with nothing ahead of it is in layer 0, a bead
//     that waits on others sits one layer past the latest of them, and the
//     beads of one layer can run in parallel. So nothing sits above what it
//     waits on, and what can go now comes first.
//   - Within a layer, the order the pool claims ready work in: priority, then
//     oldest, then id (Gas City's beads.SortBeadsReadyOrder, which matches bd
//     ready's default sort).
//
// Work the city does not take as things stand ([Scheduled]) comes after the
// queue, since it waits until someone routes it or its hold lifts, and so does
// work that waits on such work, so the queue holds nothing that waits on work
// the city will not take.
//
// The package sits outside internal/ so the helm board, a separate module, can
// import it.
package queue

import (
	"cmp"
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// Item is one piece of work to place.
type Item struct {
	ID        string
	Priority  int
	CreatedAt string
	// Status is its status as the store holds it. A status bd's ready set does
	// not admit, such as deferred, keeps it from going now although nothing is
	// ahead of it, so it sits in layer 1 at least.
	Status string
	// Waits are the beads it waits on now ([Waiting]). A wait on another item
	// puts it one layer past that item. A wait on any other bead, such as a
	// question a person answers, a gate or a bead in another store, puts it in
	// layer 1 at least, as bd graph places a bead that waits on one with
	// nothing ahead of it.
	Waits []string
	// Scheduled is true when the city takes it as things stand ([Scheduled]).
	Scheduled bool
}

// Place is where one piece of work sits: its id and its layer.
type Place struct {
	ID    string
	Layer int
}

// Ordered is the work in the order it is expected to land.
type Ordered struct {
	// Queue is the work the city takes as things stand.
	Queue []Place
	// NotScheduled is the work after the queue: work the city does not take
	// as things stand, and work that waits on such work at any depth.
	NotScheduled []Place
}

// Waiting is what a bead waits on now: each wait behind its status, as waits
// answers it, once and in waits' order, less any bead whose work is the bead's
// own. Such a bead is one anchorOf names the bead as the anchor of, a review or
// a rework of its pull request, whose row the bead's own row speaks for.
func Waiting(h waits.Holds, anchorOf func(id string) string) []string {
	var out []string
	for _, w := range h.Waits {
		if w.ID == "" || w.ID == h.ID || slices.Contains(out, w.ID) || anchorOf(w.ID) == h.ID {
			continue
		}
		out = append(out, w.ID)
	}
	return out
}

// Scheduled reports whether the city takes a piece of work as things stand:
// it is in flight (waits' answer), or no dispatch hold holds it and it is
// armed to start by itself, routed to a pool or an agent, or assigned to one.
// A dispatch hold is one of Gas City's hold labels, hold:mayor and
// hold:external, read as its HasDispatchHold reads a label, trimmed and in any
// case. Gas City serves a bead that carries one to no worker, and the
// deferred-dispatch pass slings no armed bead while one holds it, so its route,
// arm or assignee waits for the hold to lift. Work in flight is underway, so it
// counts whatever it carries.
func Scheduled(h waits.Holds, routedTo, assignee string, labels []string) bool {
	if h.InFlight != "" {
		return true
	}
	return !hasDispatchHold(labels) && ((h.Arm != nil && strings.TrimSpace(h.Arm.Target) != "") ||
		strings.TrimSpace(routedTo) != "" || strings.TrimSpace(assignee) != "")
}

// dispatchHolds are Gas City's hold labels (DispatchHoldLabels in its package
// beadmeta).
var dispatchHolds = []string{"hold:mayor", "hold:external"}

// hasDispatchHold reports whether labels carry a dispatch hold, comparing each
// label as HasDispatchHold does.
func hasDispatchHold(labels []string) bool {
	for _, l := range labels {
		for _, hold := range dispatchHolds {
			if strings.EqualFold(strings.TrimSpace(l), hold) {
				return true
			}
		}
	}
	return false
}

// canGo reports whether a status lets a bead go now: open, which bd's ready
// set admits, or a claim (in_progress, hooked), which is work going already.
func canGo(status string) bool {
	switch strings.ToLower(strings.TrimSpace(status)) {
	case "open", "in_progress", "hooked":
		return true
	}
	return false
}

// Order places the items: the queue first and the work after it, each by
// layer, then priority, then oldest, then id. An item named twice is placed
// once, as its first naming gives it.
func Order(items []Item) Ordered {
	byID := map[string]Item{}
	var ids []string
	for _, it := range items {
		if _, dup := byID[it.ID]; dup || it.ID == "" {
			continue
		}
		byID[it.ID] = it
		ids = append(ids, it.ID)
	}
	slices.Sort(ids)
	layer := layers(byID, ids)
	after := notScheduled(byID, ids)

	var out Ordered
	for _, id := range ids {
		p := Place{ID: id, Layer: layer[id]}
		if after[id] {
			out.NotScheduled = append(out.NotScheduled, p)
		} else {
			out.Queue = append(out.Queue, p)
		}
	}
	less := func(a, b Place) int {
		x, y := byID[a.ID], byID[b.ID]
		return cmp.Or(cmp.Compare(a.Layer, b.Layer), cmp.Compare(x.Priority, y.Priority),
			cmp.Compare(x.CreatedAt, y.CreatedAt), cmp.Compare(a.ID, b.ID))
	}
	slices.SortFunc(out.Queue, less)
	slices.SortFunc(out.NotScheduled, less)
	return out
}

// layers assigns each item its layer, as bd graph's computeLayout does: an
// item takes its layer once every item it waits on has one, and passes over
// the rest until a pass assigns nothing more. Each wait on a bead that is no
// item counts as one on a bead in layer 0, and a status that keeps an item
// from going counts the same. An item a pass never reaches, on a cycle of
// waits or behind one, sits one layer past the latest layer it could read,
// and in layer 1 at least, since it waits on something.
func layers(byID map[string]Item, ids []string) map[string]int {
	layer := map[string]int{}
	floor := func(it Item) int {
		if !canGo(it.Status) {
			return 1
		}
		for _, w := range it.Waits {
			if _, ok := byID[w]; !ok && w != it.ID {
				return 1
			}
		}
		return 0
	}
	for changed := true; changed; {
		changed = false
		for _, id := range ids {
			if _, done := layer[id]; done {
				continue
			}
			it := byID[id]
			l, ready := floor(it), true
			for _, w := range it.Waits {
				if _, ok := byID[w]; !ok || w == id {
					continue
				}
				wl, ok := layer[w]
				if !ok {
					ready = false
					break
				}
				l = max(l, wl+1)
			}
			if ready {
				layer[id] = l
				changed = true
			}
		}
	}
	for _, id := range ids {
		if _, done := layer[id]; done {
			continue
		}
		l := 1
		for _, w := range byID[id].Waits {
			if wl, ok := layer[w]; ok {
				l = max(l, wl+1)
			}
		}
		layer[id] = l
	}
	return layer
}

// notScheduled marks each item that comes after the queue: one the city does
// not take as things stand ([Scheduled]), and one that waits on such an item
// at any depth.
func notScheduled(byID map[string]Item, ids []string) map[string]bool {
	after := map[string]bool{}
	for _, id := range ids {
		after[id] = !byID[id].Scheduled
	}
	for changed := true; changed; {
		changed = false
		for _, id := range ids {
			if after[id] {
				continue
			}
			for _, w := range byID[id].Waits {
				if w != id && after[w] {
					after[id] = true
					changed = true
					break
				}
			}
		}
	}
	return after
}
