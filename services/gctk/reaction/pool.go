package reaction

import (
	"fmt"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
)

// prefixOf is a bead id's prefix, the text before its first dash, which names
// the store that holds it.
func prefixOf(id string) string {
	p, _, _ := strings.Cut(id, "-")
	return p
}

// Deliverable answers whether the bead of s, a sling about to be made, would
// be picked up where s sends it, by Gas City's own preview of that sling. It
// answers no when Gas City refuses the sling, as it refuses a target the city
// resolves no agent by and a route into a store the target does not read, and
// when the preview warns that the city, the target or the target's rig is
// suspended, or that the target's pool runs no sessions, which Gas City reads
// only from a cap of 0. No is a positive finding only: a preview that does not
// answer answers yes, because it is no evidence that the pool is gone. why
// says what the answer rests on.
//
// Two answers follow from asking the sling's own preview. A process that sets
// GC_SUSPENDED=1 is answered yes for a pool the city's state does not suspend,
// since the sling passes over that override, which does not say whether the
// controller runs the pool (targetScopeSuspension in
// internal/sling/sling_core.go at gastownhall/gascity 1feaf7eeb7). And the
// preview checks a route's store only once it finds the bead not routed to the
// target already: a bead Gas City counts as routed there, with a live tracking
// convoy, previews as going ahead with no store check (preflight in the same
// file), so a route into another store passes only when the bead's routing was
// already wrong before the question.
func (r *Reactions) Deliverable(s gascity.Sling) (ok bool, why string) {
	p := r.Runtime.Preview(s)
	switch {
	case !p.Answered:
		return true, fmt.Sprintf("Gas City's preview of the sling to %s did not answer (%s), so the pool is taken as live: a preview that does not answer is no evidence that it is gone", s.Target, p.Unanswered())
	case p.Refused != "":
		return false, fmt.Sprintf("gc sling refuses to send %s to %s (%s)", s.Bead, s.Target, p.Refused)
	}
	if warned := targetWords(s.Target, p.TargetWarnings()); len(warned) > 0 {
		return false, fmt.Sprintf("Gas City's preview of the sling warns that %s, so work sent there sits unclaimed", strings.Join(warned, " and "))
	}
	return true, fmt.Sprintf("Gas City's preview of the sling of %s to %s refuses nothing and warns of no suspension or empty pool", s.Bead, s.Target)
}

// targetWords is each of a preview's warnings about target, in words.
func targetWords(target string, warnings []string) []string {
	var out []string
	for _, w := range warnings {
		switch w {
		case gascity.CitySuspended:
			out = append(out, "the city is suspended")
		case gascity.AgentSuspended:
			out = append(out, target+" is suspended")
		case gascity.RigSuspended:
			out = append(out, "the rig of "+target+" is suspended")
		case gascity.PoolEmpty:
			out = append(out, target+" runs no sessions (its max_active_sessions is 0)")
		}
	}
	return out
}

// Assignable answers whether a bead handed to the named agent who would be
// offered by the agent's own hook. It answers no when the roster registers no
// agent by that exact name, when the agent is suspended, when the city's
// config lists no named session for it, which makes it a pool whose sessions
// each match their own identity and never the pool's name, and, when bead is
// named, when the agent is scoped to a rig whose hook reads neither bead's
// store nor the city's. No is a positive finding only: a roster that does not
// read answers yes, and a config or rig list that does not read skips its
// check. why says what the answer rests on.
func (r *Reactions) Assignable(who, bead string) (ok bool, why string) {
	agents, err := r.Runtime.Agents()
	if err != nil {
		return true, fmt.Sprintf("the city's roster did not read (%v), so %s is taken as assignable: an unreadable roster is no evidence that it is gone", err, who)
	}
	var a *gascity.Agent
	for i := range agents {
		if agents[i].QualifiedName == who {
			a = &agents[i]
			break
		}
	}
	switch {
	case a == nil:
		return false, fmt.Sprintf("no agent is registered as %s in this city, so a bead handed to it is offered to nobody (a named agent is named by its exact qualified name, such as gc-toolkit.mechanik)", who)
	case a.Suspended:
		return false, fmt.Sprintf("%s is suspended, so a bead handed to it sits unoffered until it resumes", who)
	}
	if named, err := r.Runtime.NamedSessions(); err == nil {
		found := false
		for _, s := range named {
			if (s.Template == a.Name || s.Template == who) && s.Dir == a.Dir {
				found = true
				break
			}
		}
		if !found {
			return false, fmt.Sprintf("%s is a pool, not a named session: its sessions each match their own identity and never the pool's name, so a bead handed to it is offered to nobody (route a pool instead)", who)
		}
	}
	if bead != "" && a.Scope != "city" {
		if rigs, err := r.Runtime.Rigs(); err == nil {
			own, hq, beadPrefix := rigPrefix(rigs, a.Dir), "", prefixOf(bead)
			for _, g := range rigs {
				if g.HQ {
					hq = g.Prefix
					break
				}
			}
			if own != "" && beadPrefix != own && beadPrefix != hq {
				return false, fmt.Sprintf("%s is scoped to the rig %s, so its hook reads the %s- store and the city's, but %s lives in the %s- store and is never offered to it",
					who, a.Dir, own, bead, beadPrefix)
			}
		}
	}
	what := "a registered named session that is not suspended"
	if bead != "" {
		what += ", whose hook reads the store " + bead + " lives in"
	}
	return true, who + " is " + what
}

// rigPrefix is the bead prefix of the rig named name, empty when the list names
// no such rig.
func rigPrefix(rigs []gascity.Rig, name string) string {
	for _, g := range rigs {
		if g.Name == name {
			return g.Prefix
		}
	}
	return ""
}
