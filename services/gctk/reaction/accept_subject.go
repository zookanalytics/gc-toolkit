package reaction

import (
	"fmt"
	"regexp"
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/conversation"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// prReference is a reference to a pull request: its number, or its URL.
var prReference = regexp.MustCompile(`^([0-9]+|https?://.*/pull/[0-9]+.*)$`)

// IsPRReference reports whether ref names a pull request, by its number or its
// URL, rather than a bead.
func IsPRReference(ref string) bool { return prReference.MatchString(strings.TrimSpace(ref)) }

// Resolve is the live bead a reference names, as gc-helm.sh resolve answers
// it, the one subject resolver open and engage share: the anchor that owns a
// pull request its number or URL names, or the successor a closed bead's
// disposition names. It runs that script through the runtime, so it needs the
// pack's scripts directory.
func Resolve(rt gascity.Runtime, ref string) (string, error) {
	res := rt.Script("gc-helm.sh", "resolve", ref)
	if f := res.Failure(); f != "" {
		return "", fmt.Errorf("gc-helm.sh resolve %s: %s", ref, f)
	}
	id := strings.TrimSpace(res.Tail())
	if !beadID.MatchString(id) {
		return "", fmt.Errorf("gc-helm.sh resolve %s named no bead (it printed %q)", ref, id)
	}
	return id, nil
}

// Subject is the bead an acceptance named by ref is about. A human gate names
// the one open bead that waits on it, and one that several wait on is refused,
// since an acceptance is about one bead. A conversation names the bead it
// tracks. A closed bead that is neither names the live successor its
// disposition names (Resolve). Any other bead names itself. The bead it names
// may sit in another store, which the caller then reads.
func (r *Reactions) Subject(ref string) (string, error) {
	row, err := r.readBead(ref)
	switch {
	case err != nil:
		return "", stop(4, "could not verify %s: the store did not answer (%v). Nothing dispatched", ref, err)
	case row == nil:
		return "", stop(4, "bead not found: %s, which its store does not hold. Nothing dispatched", ref)
	}
	if row.IssueType() == "gate" {
		waiting, err := r.Ledger.Dependents(ref, ledger.EdgeBlocks)
		if err != nil {
			return "", stop(4, "could not read the beads that wait on gate %s (%v). Nothing dispatched", ref, err)
		}
		var open, closed []string
		for _, w := range waiting {
			if w.Status() == "closed" {
				closed = append(closed, w.ID)
			} else {
				open = append(open, w.ID)
			}
		}
		switch len(open) {
		case 1:
			return open[0], nil
		case 0:
			was := ""
			if len(closed) > 0 {
				was = " (it was about " + strings.Join(closed, " ") + ", now closed)"
			}
			return "", stop(4, "nothing waits on gate %s%s, so there is no bead to accept a recommendation on. Clear the gate instead: gc bd gate resolve %s --reason \"moot: <why nothing waits on it>\". Nothing dispatched", ref, was, ref)
		}
		return "", stop(4, "gate %s is about %d beads still waiting on it (%s), and an acceptance is about one bead. Name the one you mean: gctk reaction accept <bead>. Nothing dispatched", ref, len(open), strings.Join(open, " "))
	}
	if conversation.IsCandidate(row.IssueType(), row.Assignee(), row.ID) {
		edges, err := row.Edges()
		if err != nil {
			return "", stop(4, "%s's edges did not decode (%v). Nothing dispatched", ref, err)
		}
		if subject, _, ok := conversation.Shape(convEdges(edges)); ok {
			return subject, nil
		}
	}
	if row.Status() == "closed" {
		id, err := Resolve(r.Runtime, ref)
		if err != nil {
			return "", stop(4, "%s is closed, and the live bead its disposition names could not be read (%v). Pass the live bead's id. Nothing dispatched", ref, err)
		}
		return id, nil
	}
	return ref, nil
}

// warnLive says, when a live sitting holds a conversation on the bead or one
// replying to the recommendation's gate, that Accept clears the gate anyway
// and that sitting learns it at its sign-off. The conversation the call names
// is the caller's own, whose sign-off runs this Accept, so it is not warned
// of. It writes nothing, and a read that does not answer is named and passed.
func (r *Reactions) warnLive(bead, own string, gates []string) {
	if r.Sessions == nil {
		return
	}
	live, err := r.Sessions()
	if err != nil {
		r.say("could not read gc session list to warn of a live sitting on %s (%v); going on", bead, err)
		return
	}
	var candidates []string
	for _, about := range append([]string{bead}, gates...) {
		typ := "tracks"
		if about != bead {
			typ = "replies-to"
		}
		rows, err := r.Ledger.Dependents(about, typ)
		if err != nil {
			r.say("could not read the conversations on %s (%v) to warn of a live sitting; going on", about, err)
			return
		}
		for _, c := range rows {
			if c.Status() != "closed" && c.ID != own && conversation.IsCandidate(c.IssueType(), c.Assignee(), c.ID) && !slices.Contains(candidates, c.ID) {
				candidates = append(candidates, c.ID)
			}
		}
	}
	rows, err := r.Ledger.Find(ledger.ByID(candidates...))
	if err != nil {
		r.say("could not read the conversations on %s (%v) to warn of a live sitting; going on", bead, err)
		return
	}
	var held []string
	for _, c := range rows {
		edges, err := c.Edges()
		if err != nil {
			continue
		}
		subject, replies, ok := conversation.Shape(convEdges(edges))
		if !ok || (subject != bead && !slices.ContainsFunc(replies, func(g string) bool { return slices.Contains(gates, g) })) {
			continue
		}
		if heldLive(c, live) {
			held = append(held, c.ID)
		}
	}
	slices.Sort(held)
	if len(held) > 0 {
		r.say("warning: a live sitting holds conversation %s on %s or replying to the recommendation's gate. Accept clears the gate anyway, and that sitting learns it at its sign-off", strings.Join(held, " "), bead)
	}
}

// heldLive reports whether a live sitting holds the conversation: its assignee
// is no one's and not the operator's queue, and names a listed session by its
// alias, its session name or its id, or is the conversation's own alias, which
// a listed session's alias names too.
func heldLive(c *ledger.Record, live []gascity.Session) bool {
	a := c.Assignee()
	if a == "" || a == "human" {
		return false
	}
	own := conversation.IsAssignee(a, c.ID)
	for _, s := range live {
		if s.Alias == a || s.SessionName == a || s.ID == a || (own && s.Alias != "" && s.Alias != "human" && conversation.IsAssignee(s.Alias, c.ID)) {
			return true
		}
	}
	return false
}

// convEdges is a record's edges as the conversation shape reads them.
func convEdges(edges []ledger.Edge) []conversation.Edge {
	out := make([]conversation.Edge, 0, len(edges))
	for _, e := range edges {
		out = append(out, conversation.Edge{Type: e.Type, DependsOnID: e.ID})
	}
	return out
}
