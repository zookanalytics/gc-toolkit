package place

import (
	"context"
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// A move of the placement hold takes each live bead the placement queue holds
// on hold:mayor, the hold's earlier spelling, onto hold:po, in every store the
// city's rig list names. `gctk bead move-placement-hold` makes it.
//
// Each bead moves in one update, `gc bd update <id> --add-label hold:po
// --remove-label hold:mayor`. bd makes both label changes in the update's own
// transaction, so the bead is held before, during and after the write, and
// records each as a label event, which `gc bd history <id> --events` reads. The
// write names the one label it removes, so every other label the bead carries
// as the write lands stays on, a hold another writer added after the move read
// the bead included. A bead on hold:po alone takes no write, so a second move
// writes nothing (specs/tk-1tfzr71.233/gas-city-search.md).
//
// A move writes only a bead whose hold: labels are hold:mayor, or hold:mayor
// beside hold:po. It leaves each other bead the queue holds on hold:mayor as it
// stands, and names why and the write a person makes: a bead another hold or
// hold:cleared also labels, one whose hold:mayor is in another case, one
// assigned to an agent, and one routed to a pool or an agent, which a held bead
// never is. A route of the shape Gas City's doctor repair hold-label-routed-to
// wrote from the label is named as one that repair may have written, with the
// read of who set it, since a writer can choose the same route, and any other
// route as one a writer chose. It reads no closed bead, so a closed record
// keeps its labels.
//
// A store that does not read is named with why, and a move that leaves a store
// unread or a bead on hold:mayor has not finished: run it again once the cause
// is cleared.

// City is Gas City as a move reaches it: its rig list, whose every entry, the
// HQ and each rig, suspended or not, names one store.
type City interface {
	Rigs() ([]gascity.Rig, error)
}

// Move is the move of the placement hold over the city: its rig list, the
// opener of each store, and whether it is a dry run, which writes nothing and
// names each bead it would move.
type Move struct {
	City   City
	Open   ledger.Opener
	DryRun bool
}

// Moved is what a move found and did in each store, in the rig list's order.
type Moved struct {
	Stores []StoreMove
}

// StoreMove is one store's part of a move: the rig that names it, the store,
// why it did not read when it did not, the beads moved, or that a dry run
// would move, the beads already on hold:po alone, and the beads left for a
// person.
type StoreMove struct {
	Rig, DB string
	Unread  string
	Moved   []string
	OnPO    []string
	Left    []Left
}

// Left is a bead a move leaves on hold:mayor: why, and the write that a person
// makes before the move is run again.
type Left struct {
	ID, Why, Fix string
}

// AnyUnread reports whether a store did not read.
func (m Moved) AnyUnread() bool {
	return slices.ContainsFunc(m.Stores, func(s StoreMove) bool { return s.Unread != "" })
}

// AnyLeft reports whether a move left a bead on hold:mayor, in any store.
func (m Moved) AnyLeft() bool {
	return slices.ContainsFunc(m.Stores, func(s StoreMove) bool { return len(s.Left) > 0 })
}

// Run reads each store the rig list names and moves each bead it can. A rig
// list that does not read moves nothing and is its error.
func (m *Move) Run(ctx context.Context) (Moved, error) {
	rigs, err := m.City.Rigs()
	if err != nil {
		return Moved{}, err
	}
	var out Moved
	for _, rig := range rigs {
		out.Stores = append(out.Stores, m.store(ctx, rig))
	}
	return out, nil
}

// store moves the beads of one rig's store.
func (m *Move) store(ctx context.Context, rig gascity.Rig) StoreMove {
	s := StoreMove{Rig: rig.Name, DB: rig.Store()}
	l, err := m.Open(ctx, s.DB)
	if err != nil {
		s.Unread = err.Error()
		return s
	}
	recs, err := l.Find(ledger.Every())
	if err != nil {
		s.Unread = err.Error()
		return s
	}
	slices.SortFunc(recs, func(a, b *ledger.Record) int { return strings.Compare(a.ID, b.ID) })
	for _, r := range recs {
		if !gascity.HasPlacementHold(r.Labels()) {
			continue
		}
		if !gascity.HasHold(r.Labels(), gascity.HoldMayor) {
			s.OnPO = append(s.OnPO, r.ID)
			continue
		}
		if why, fix := left(r, s.DB); why != "" {
			s.Left = append(s.Left, Left{ID: r.ID, Why: why, Fix: fix})
			continue
		}
		if m.DryRun {
			s.Moved = append(s.Moved, r.ID)
			continue
		}
		if lw := m.move(l, r.ID, s.DB); lw != nil {
			s.Left = append(s.Left, *lw)
			continue
		}
		s.Moved = append(s.Moved, r.ID)
	}
	return s
}

// move reads the bead again and, when it still is one the move writes, swaps
// its hold in the one update that adds hold:po and removes hold:mayor. The read
// again keeps a bead whose hold a placement lifted after the store's read from
// taking hold:po. It answers the bead it leaves when it writes nothing, and nil
// once the write landed.
func (m *Move) move(l *ledger.Ledger, id, db string) *Left {
	again := "Run it again: gctk bead move-placement-hold"
	rows, err := l.Find(ledger.ByID(id))
	switch {
	case err != nil:
		return &Left{ID: id, Why: "it did not read again before its write (" + err.Error() + "), so nothing was written", Fix: again}
	case len(rows) == 0:
		return &Left{ID: id, Why: "it closed after the store's read, so nothing was written", Fix: again}
	case !gascity.HasHold(rows[0].Labels(), gascity.HoldMayor):
		return &Left{ID: id, Why: "its hold:mayor was lifted after the store's read, so nothing was written", Fix: again}
	}
	if why, fix := left(rows[0], db); why != "" {
		return &Left{ID: id, Why: why, Fix: fix}
	}
	w := l.Write(id)
	w.AddLabel(gascity.HoldPO)
	w.RemoveLabel(gascity.HoldMayor)
	if err := l.Commit(w); err != nil {
		return &Left{ID: id, Why: "its write did not land (" + err.Error() + "), so it keeps hold:mayor", Fix: again}
	}
	return nil
}

// left is why a move leaves a bead the queue holds on hold:mayor, and the
// write a person makes, or nothing when the move writes it.
func left(r *ledger.Record, db string) (why, fix string) {
	at := " --db " + shQuote(db)
	if as := strings.TrimSpace(r.Assignee()); as != "" {
		return "it is assigned to " + as + ", and a held bead is served to no one, so whether it is placed or stays held is a person's call",
			"Place it with gctk bead place, or clear its assignee: gc bd update " + r.ID + " --assignee ''" + at
	}
	if route := value(routedToKey, r); route != "" {
		unroute := "gc bd update " + r.ID + " --unset-metadata gc.routed_to" + at
		if holdRoute(route) {
			return "it is routed to " + route + ", a route Gas City's doctor repair hold-label-routed-to wrote from hold:mayor and a writer can choose as well, so whether it is placed or stays held is a person's call once they read who set the route",
				"Read who set the route: gc bd history " + r.ID + " --events" + at + ". When gc doctor --fix set it, clear it; otherwise place the bead with gctk bead place, or clear the route: " + unroute
		}
		return "it is routed to " + route + ", which a writer chose while hold:mayor holds it, so whether it is placed or stays held is a person's call",
			"Place it with gctk bead place, or clear the route: " + unroute
	}
	var other, spelled []string
	for _, l := range r.Labels() {
		if l == gascity.HoldMayor || l == gascity.HoldPO {
			continue
		}
		if t := strings.ToLower(strings.TrimSpace(l)); strings.HasPrefix(t, "hold:") {
			other = append(other, l)
		}
		if gascity.HasHold([]string{l}, gascity.HoldMayor) {
			spelled = append(spelled, l)
		}
	}
	if len(other) == 0 {
		return "", ""
	}
	fix = "Move its placement hold by hand, in one write that leaves each other label on: gc bd update " + r.ID + " --add-label hold:po"
	if slices.Contains(r.Labels(), gascity.HoldMayor) {
		fix += " --remove-label hold:mayor"
	}
	for _, l := range spelled {
		fix += " --remove-label " + shQuote(l)
	}
	if !slices.Contains(r.Labels(), gascity.HoldMayor) {
		return "it carries hold:mayor as " + strings.Join(spelled, ", ") + ", and bd removes a label by its exact text, so the move's write would leave it beside hold:po", fix + at
	}
	return "it also carries " + strings.Join(other, ", ") + ", a hold: label another writer put there, so whether it still waits for placement is a person's call", fix + at
}

// holdRoute reports whether route has the shape Gas City's doctor repair
// hold-label-routed-to wrote from hold:mayor: the label's value, mayor, or the
// binding-qualified name of the city's agent or named session called mayor,
// which carries no rig (doctor_hold_label_routed_to.go and
// boundRoutedToAliases, gastownhall/gascity 0998eac14bfe). A writer can choose
// the same route, so the shape does not show who set it.
func holdRoute(route string) bool {
	return !strings.Contains(route, "/") && (route == "mayor" || strings.HasSuffix(route, ".mayor"))
}
