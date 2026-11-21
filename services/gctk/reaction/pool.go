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
