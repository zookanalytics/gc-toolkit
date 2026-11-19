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

// Deliverable answers whether work routed to target, a rig-qualified pool,
// would be picked up. It answers no when the target's rig reads another store
// than the one bead lives in, since a rig's pool claims only its own store's
// beads (gc sling refuses that route as a CrossStoreRouteError), and when the
// city's roster shows the pool cannot claim: no agent is registered there, it
// is suspended, or its sessions are capped below one. A store check needs bead,
// and is skipped when it is empty. No is a positive finding only: a roster or
// rig list that does not read answers yes, because it is no evidence that the
// pool is gone. why says what the answer rests on.
func (r *Reactions) Deliverable(target, bead string) (ok bool, why string) {
	if bead != "" {
		if rigs, err := r.Runtime.Rigs(); err == nil {
			rigName, _, _ := strings.Cut(target, "/")
			targetPrefix := rigPrefix(rigs, rigName)
			if beadPrefix := prefixOf(bead); targetPrefix != "" && targetPrefix != beadPrefix {
				owner := "no rig, since none owns prefix " + beadPrefix + "-"
				for _, g := range rigs {
					if g.Prefix == beadPrefix {
						owner = g.Name
						break
					}
				}
				return false, fmt.Sprintf("%s reads the %s store (prefix %s-) but %s lives in the store of %s (prefix %s-), and a rig's pool claims only the beads of its own store, so a bead routed there is open, unassigned and offered to nobody (gc sling refuses this route as a CrossStoreRouteError)",
					target, rigName, targetPrefix, bead, owner, beadPrefix)
			}
		}
	}
	agents, err := r.Runtime.Agents()
	if err != nil {
		return true, fmt.Sprintf("the city's roster did not read (%v), so the pool at %s is taken as live: an unreadable roster is no evidence that it is gone", err, target)
	}
	var a *gascity.Agent
	for i := range agents {
		if agents[i].QualifiedName == target {
			a = &agents[i]
			break
		}
	}
	switch {
	case a == nil:
		return false, fmt.Sprintf("no agent is registered at %s in this city, so work routed there is routed to nobody", target)
	case a.Suspended:
		return false, fmt.Sprintf("the pool at %s is suspended, so work routed there sits unclaimed until it resumes", target)
	}
	if n, set := a.MaxSessions(); set && n < 1 {
		return false, fmt.Sprintf("the pool at %s runs no sessions (its maximum is %d), so nothing can claim work routed there", target, n)
	}
	return true, fmt.Sprintf("%s is registered and not suspended, and its cap only queues work routed there", target)
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
