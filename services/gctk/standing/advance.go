package standing

import (
	"sort"

	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// Advance is how far the city carries an open bead as things stand, without a
// person: it advances, or it is stuck on the bead that stops it.
type Advance struct {
	Advancing bool
	// On is the bead that stops a stuck bead, the bead itself included. Why is
	// the word that says why: the ask, for a bead that is itself what a person
	// owes, and otherwise the rule of the answer that names On, such as
	// own-wait for a human gate the bead waits on, or not-scheduled for work
	// nobody takes.
	On  string
	Why string
}

// Frontier is where a bead stands by the beads it waits on: ready when nothing
// holds it, advancing when every wait behind what holds it advances, and stuck
// when one does not.
type Frontier string

const (
	FrontierReady     Frontier = "ready"
	FrontierAdvancing Frontier = "advancing"
	FrontierStuck     Frontier = "stuck"
)

// Advance is how far the city carries an open bead, for each the read answered,
// and false for a closed bead and for one it did not answer. A bead advances
// when it is queued and every bead it waits on advances, and an epic or a
// Delivery the members rule placed advances when every open member does. Any
// other bead is stuck: on the bead its rule names, when the rule is about
// another bead (own-wait, further-along, parked and answers); a queued bead on
// what stops the first of its waits that does not advance, and such an epic or
// Delivery on what stops the first of its open members that does not; and any
// other bead on itself. A bead the read holds no answer for, and a bead met
// again on the way down from itself, a cycle, are stuck on themselves, unread,
// and a bead behind a waits-for wait, which the store cannot judge yet, is
// stuck on that wait, unread.
func (r *Reading) Advance(id string) (Advance, bool) {
	a, ok := r.advances[id]
	return a, ok
}

// Frontier is where a bead the read was asked about stands by the beads it
// waits on, and false for a closed bead and for one it was not asked about or
// did not answer. It is ready when waits answers that nothing holds it, and
// otherwise advancing when every wait behind that answer advances and stuck
// when one does not, a waits-for wait among them, or when waits could not
// answer what holds it.
func (r *Reading) Frontier(id string) (Frontier, bool) {
	b, ok := r.beads[id]
	if !ok || !r.asked[id] || !isOpen(b) {
		return "", false
	}
	h, ok := r.holds[id]
	if !ok {
		return FrontierStuck, true
	}
	if h.Status == waits.Clear {
		return FrontierReady, true
	}
	if !r.behind(h.Waits, map[string]bool{}).Advancing {
		return FrontierStuck, true
	}
	return FrontierAdvancing, true
}

// advanceAll reads how far the city carries each open bead answered, by id, so
// a bead's advance does not turn on the order its readers asked in.
func (r *Reading) advanceAll() {
	ids := make([]string, 0, len(r.answers))
	for id, a := range r.answers {
		if a.Rule != RuleClosed {
			ids = append(ids, id)
		}
	}
	sort.Strings(ids)
	for _, id := range ids {
		r.advance(id, map[string]bool{})
	}
}

// advance is a bead's advance, read once ([Reading.Advance]). on names the
// beads whose advance is being read beneath which this one is asked.
func (r *Reading) advance(id string, on map[string]bool) Advance {
	if adv, ok := r.advances[id]; ok {
		return adv
	}
	a, ok := r.answers[id]
	if !ok || on[id] {
		return stuck(id, string(RuleUnread))
	}
	if a.Rule == RuleClosed {
		// A closed bead holds nothing, so a bead that waits on it is not stuck
		// on it.
		return Advance{Advancing: true}
	}
	on[id] = true
	defer delete(on, id)
	var adv Advance
	switch a.Rule {
	case RuleAsk:
		adv = stuck(id, string(a.Ask))
	case RuleOwnWait, RuleFurtherAlong, RuleParked, RuleAnswers:
		adv = stuck(id, string(a.Rule))
		if len(a.Names) > 0 {
			adv.On = a.Names[0].ID
		}
	case RuleMembers:
		_, open := r.members(id)
		if len(open) == 0 {
			adv = stuck(id, string(a.Rule))
		} else {
			members := make([]waits.Wait, 0, len(open))
			for _, m := range open {
				members = append(members, waits.Wait{ID: m})
			}
			adv = r.behind(members, on)
		}
	case RuleStaying, RuleInFlight, RuleScheduled:
		// The rule names the waits behind what holds the bead.
		adv = r.behind(r.holds[id].Waits, on)
	default:
		adv = stuck(id, string(a.Rule))
	}
	r.advances[id] = adv
	return adv
}

// behind is the advance of a bead that advances while each bead ws names does:
// what stops the first that does not, and advancing when each does. A wait the
// store cannot judge yet ([waits.Wait.Unjudged]) holds the bead whatever its
// bead's own advance, so it reads unread.
func (r *Reading) behind(ws []waits.Wait, on map[string]bool) Advance {
	for _, w := range ws {
		if w.Unjudged() {
			return stuck(w.ID, string(RuleUnread))
		}
		if adv := r.advance(w.ID, on); !adv.Advancing {
			return adv
		}
	}
	return Advance{Advancing: true}
}

func stuck(on, why string) Advance { return Advance{On: on, Why: why} }
