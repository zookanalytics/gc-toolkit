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
// Work the city does not take as things stand comes after the queue, since it
// waits until someone routes it or its hold lifts, and so does work that waits
// on such work, so the queue holds nothing that waits on work the city will
// not take.
//
// A reader names the work to place and hands over its read of the store
// ([Store]). [Order] gathers from that read everything a place depends on:
// each piece's row, what holds it as waits answers it, and the anchor of each
// bead it waits on. So every reader that names the same work in one read gets
// the same order.
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

// Row is a bead as [Order] reads it: the fields of its row that a place
// depends on.
type Row struct {
	ID string
	// Status is its status as the store holds it. A status bd's ready set does
	// not admit, such as deferred, keeps it from going now although nothing is
	// ahead of it, so it sits in layer 1 at least.
	Status    string
	Priority  int
	CreatedAt string
	// RoutedTo is the pool or agent it is routed to, Assignee the one
	// it is assigned to, and Labels its labels, among them the hold labels.
	RoutedTo string
	Assignee string
	Labels   []string
	// Anchor is the merge anchor it is a child of, such as the anchor whose
	// pull request it reviews or reworks, and empty on a bead that is no
	// anchor's child.
	Anchor string
}

// Store is the reads [Order] gathers through: one reader's adapter onto its
// read of a bead store. It holds no rule. Order decides which beads to read,
// and an adapter only carries out each read, from the one read it adapts, so
// every question asked of it in that read gets the same answer.
type Store interface {
	// Rows returns the row of each id the store holds. An id it holds no row
	// for is left out.
	Rows(ids []string) (map[string]Row, error)
	// Holds answers what holds each id, through waits: the answer for each id
	// it could answer, and the error for each it could not. A read that fails
	// returns its error.
	Holds(ids []string) (map[string]waits.Holds, map[string]error, error)
}

// Place is where one piece of work sits: its id and its layer. Scheduled is
// true when the city takes the piece itself as things stand: it is in flight,
// or no dispatch hold holds it and it is armed to start by itself, routed to a
// pool or an agent, or assigned to one. A piece the city takes sits after the
// queue all the same while it waits on work the city does not take.
type Place struct {
	ID        string
	Layer     int
	Scheduled bool
}

// Ordered is the work in the order it is expected to land.
type Ordered struct {
	// Queue is the work the city takes as things stand.
	Queue []Place
	// NotScheduled is the work after the queue: work the city does not take
	// as things stand, and work that waits on such work at any depth.
	NotScheduled []Place
	// Unread is the work named that has no place, because the store holds no
	// row for it or what holds it could not be answered, in the order named. A
	// wait on it counts as one on a bead that is no work named.
	Unread []string
}

// Order places the work ids names: the queue first and the work after it,
// each by layer, then priority, then oldest, then id. Through s it reads each
// piece's row and what holds it, and the row of each bead the piece waits on,
// whose anchor says whether that bead's work is the piece's own. Work named
// twice is placed once. A read that fails returns its error and no order.
func Order(ids []string, s Store) (Ordered, error) {
	var named []string
	seen := map[string]bool{}
	for _, id := range ids {
		if id != "" && !seen[id] {
			seen[id] = true
			named = append(named, id)
		}
	}
	if len(named) == 0 {
		return Ordered{}, nil
	}
	rows, err := s.Rows(named)
	if err != nil {
		return Ordered{}, err
	}
	var held []string
	for _, id := range named {
		if _, ok := rows[id]; ok {
			held = append(held, id)
		}
	}
	holds, _, err := s.Holds(held)
	if err != nil {
		return Ordered{}, err
	}
	anchor := map[string]string{}
	for id, r := range rows {
		anchor[id] = r.Anchor
	}
	var far []string
	for _, id := range held {
		for _, w := range holds[id].Waits {
			if _, read := anchor[w.ID]; !read && w.ID != "" && !slices.Contains(far, w.ID) {
				far = append(far, w.ID)
			}
		}
	}
	if len(far) > 0 {
		more, err := s.Rows(far)
		if err != nil {
			return Ordered{}, err
		}
		for id, r := range more {
			anchor[id] = r.Anchor
		}
	}

	var items []item
	var unread []string
	for _, id := range named {
		r, hasRow := rows[id]
		h, answered := holds[id]
		if !hasRow || !answered {
			unread = append(unread, id)
			continue
		}
		items = append(items, item{id: id, priority: r.Priority, createdAt: r.CreatedAt, status: r.Status,
			waits:     waiting(h, func(x string) string { return anchor[x] }),
			scheduled: scheduled(h, r.RoutedTo, r.Assignee, r.Labels)})
	}
	o := order(items)
	o.Unread = unread
	return o, nil
}

// item is one piece of work to place.
type item struct {
	id        string
	priority  int
	createdAt string
	// status is its status as the store holds it ([Row]).
	status string
	// waits are the beads it waits on now ([waiting]). A wait on another item
	// puts it one layer past that item. A wait on any other bead, such as a
	// question a person answers, a gate or a bead in another store, puts it in
	// layer 1 at least, as bd graph places a bead that waits on one with
	// nothing ahead of it.
	waits []string
	// scheduled is true when the city takes it as things stand ([scheduled]).
	scheduled bool
}

// waiting is what a bead waits on now: each wait behind its status, as waits
// answers it, once and in waits' order, less any bead whose work is the bead's
// own. Such a bead is one anchorOf names the bead as the anchor of, a review or
// a rework of its pull request, whose place the bead's own place speaks for.
func waiting(h waits.Holds, anchorOf func(id string) string) []string {
	var out []string
	for _, w := range h.Waits {
		if w.ID == "" || w.ID == h.ID || slices.Contains(out, w.ID) || anchorOf(w.ID) == h.ID {
			continue
		}
		out = append(out, w.ID)
	}
	return out
}

// scheduled reports whether the city takes a piece of work as things stand:
// it is in flight (waits' answer), or no dispatch hold holds it and it is
// armed to start by itself, routed to a pool or an agent, or assigned to one.
// A dispatch hold is one of Gas City's hold labels, hold:mayor and
// hold:external, read as its HasDispatchHold reads a label, trimmed and in any
// case. Gas City serves a bead that carries one to no worker, and the
// deferred-dispatch pass slings no armed bead while one holds it, so its route,
// arm or assignee waits for the hold to lift. Work in flight is underway, so it
// counts whatever it carries.
func scheduled(h waits.Holds, routedTo, assignee string, labels []string) bool {
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

// order places the items, each id once: the queue first and the work after
// it, each by layer, then priority, then oldest, then id.
func order(items []item) Ordered {
	byID := map[string]item{}
	var ids []string
	for _, it := range items {
		byID[it.id] = it
		ids = append(ids, it.id)
	}
	slices.Sort(ids)
	layer := layers(byID, ids)
	after := notScheduled(byID, ids)

	var out Ordered
	for _, id := range ids {
		p := Place{ID: id, Layer: layer[id], Scheduled: byID[id].scheduled}
		if after[id] {
			out.NotScheduled = append(out.NotScheduled, p)
		} else {
			out.Queue = append(out.Queue, p)
		}
	}
	less := func(a, b Place) int {
		x, y := byID[a.ID], byID[b.ID]
		return cmp.Or(cmp.Compare(a.Layer, b.Layer), cmp.Compare(x.priority, y.priority),
			cmp.Compare(x.createdAt, y.createdAt), cmp.Compare(a.ID, b.ID))
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
func layers(byID map[string]item, ids []string) map[string]int {
	layer := map[string]int{}
	floor := func(it item) int {
		if !canGo(it.status) {
			return 1
		}
		for _, w := range it.waits {
			if _, ok := byID[w]; !ok && w != it.id {
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
			for _, w := range it.waits {
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
		for _, w := range byID[id].waits {
			if wl, ok := layer[w]; ok {
				l = max(l, wl+1)
			}
		}
		layer[id] = l
	}
	return layer
}

// notScheduled marks each item that comes after the queue: one the city does
// not take as things stand ([scheduled]), and one that waits on such an item
// at any depth.
func notScheduled(byID map[string]item, ids []string) map[string]bool {
	after := map[string]bool{}
	for _, id := range ids {
		after[id] = !byID[id].scheduled
	}
	for changed := true; changed; {
		changed = false
		for _, id := range ids {
			if after[id] {
				continue
			}
			for _, w := range byID[id].waits {
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
