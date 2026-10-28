package board

import (
	"fmt"
	"sort"
	"strings"
)

// A bead's state is what its next move waits on, read off its own graph and
// its live work rather than off which marker it carries. One function derives
// it, [deriveState], and every reader speaks that one answer: an anchor's
// roll-up counts its open children by state, a takeaway row's frontier names
// its own state ([rowFrontier]), its NEEDS names the wait its graph records
// ([stateNeeds]), and a disposition is due only on a stranded row
// ([dispositionDue]).
//
// The states, in the order deriveState tests them. The first that applies is
// the bead's state.
const (
	// stateInFlight: a live session has claimed the bead, or a live workflow
	// stands over it.
	stateInFlight = "in flight"
	// stateInReview: the bead carries a pull request the city is landing,
	// open or at its pre-open gate. Its review and rework rounds are part of
	// that, so a bead in review is not waiting its turn behind them.
	stateInReview = "in review"
	// stateInConversation: a live sitting holds a visit on the bead.
	stateInConversation = "in conversation"
	// stateParked: a person holds the bead. It waits on an open park or demand
	// gate, it is routed to the operator, or a visit on it waits for someone
	// to engage it.
	stateParked = "parked"
	// stateQueued: the bead waits its turn. It waits on open work, or it
	// carries a pool route, an arm or an assignee that will start it.
	stateQueued = "queued"
	// stateStranded: nothing holds the bead and nothing will start it. It has
	// no open wait, no route, no arm, and nothing in progress.
	stateStranded = "stranded"
)

// mdDispatchWhenReady is the deferred-dispatch arm: its presence means the
// bead is slung by itself once nothing holds it, and its value names the pool.
const mdDispatchWhenReady = "gc.dispatch_when_ready"

// mergeResultPullRequest is the merge_result of an anchor whose pull request is
// open.
const mergeResultPullRequest = "pull_request"

// beadState is one bead's state, with what a phrase needs to name it.
type beadState struct {
	kind string
	// waits is the open blockers behind a queued or parked bead: the work it
	// waits its turn behind, or the gates a person holds it at. Oldest first.
	waits []Blocker
	// unread counts the open waits the source recorded without a blocker it
	// could read, so a phrase can count them without naming them.
	unread int
	// selfStart says a queued bead starts without anyone acting once nothing
	// holds it: it carries a pool route, an arm, or an assignee.
	selfStart bool
}

// stateInput is the part of a bead its state is read from. A child and an
// anchor each fill it from what the gather read for them. A field the source
// did not read stays zero and reads as absent: an anchor carries no status or
// assignee, so only a live workflow puts one in flight.
type stateInput struct {
	id       string
	status   string
	assignee string
	metadata map[string]string
	blockers []Blocker
	// unread is the open waits with no blocker record behind them.
	unread int
}

// childInput is a child's [stateInput].
func childInput(c Child) stateInput {
	return stateInput{id: c.ID, status: c.Status, assignee: c.Assignee, metadata: c.Metadata, blockers: c.Blockers}
}

// anchorInput is an anchor row's own [stateInput]. waitingOpen is the anchor's
// open waits from [waitingSplit]; an id among them that no open blocker carries
// is a wait the source recorded but could not read, and counts as unread.
func anchorInput(a Anchor, waitingOpen []string) stateInput {
	read := make(map[string]bool, len(a.Blockers))
	for _, b := range a.Blockers {
		if b.Status != "closed" {
			read[b.ID] = true
		}
	}
	unread := 0
	for _, id := range waitingOpen {
		if !read[id] {
			unread++
		}
	}
	return stateInput{id: a.ID, metadata: a.Metadata, blockers: a.Blockers, unread: unread}
}

// deriveState names the state a bead is in. Live work comes first, because it
// is what moves the bead whatever else holds it. A pull request comes before a
// conversation, because the conversation about a pull request does not stop
// the city landing it. A person's hold comes before open work, because the
// work cannot start the bead while a person holds it.
func deriveState(in stateInput, f Facts) beadState {
	if (in.status == "in_progress" && f.ownerLive(in.assignee)) || f.wfLive(in.id) {
		return beadState{kind: stateInFlight}
	}
	if inReview(in.metadata) {
		return beadState{kind: stateInReview}
	}
	if engagedVisit(in.id, f.Sittings) {
		return beadState{kind: stateInConversation}
	}
	var gates, work []Blocker
	for _, b := range in.blockers {
		switch {
		case b.Status == "closed":
		case heldByPerson(b):
			gates = append(gates, b)
		default:
			work = append(work, b)
		}
	}
	if len(gates) > 0 || in.metadata[mdRoutedTo] == routedHuman || f.Visits[in.id] {
		return beadState{kind: stateParked, waits: oldestFirst(gates)}
	}
	selfStart := poolRoute(in.metadata) || in.metadata[mdDispatchWhenReady] != "" ||
		(in.assignee != "" && in.status != "in_progress")
	if len(work) > 0 || in.unread > 0 || selfStart {
		return beadState{kind: stateQueued, waits: oldestFirst(work), unread: in.unread, selfStart: selfStart}
	}
	return beadState{kind: stateStranded}
}

// holds names, for every live anchor, the hold on the beads under it: parked
// while an open wait of the anchor or of a parent-child ancestor is a gate or a
// demand, queued while one is open work, and absent while none is open. bd keeps
// a bead out of `bd ready` while it or any parent-child ancestor has an open
// blocker, so nothing under a held anchor starts by itself until the hold
// clears, and a child nothing else holds is held rather than stranded. A
// convoy's members are its `tracks` edges, which bd does not cascade, so a
// convoy passes no hold down.
func holds(anchors []Anchor) map[string]string {
	own := make(map[string]string, len(anchors))
	parents := map[string][]string{}
	for _, a := range anchors {
		if !a.ClosedAt.IsZero() || a.Source == "convoy" || a.Source == "unowned" {
			continue
		}
		if _, seen := own[a.ID]; !seen {
			own[a.ID] = waitHold(a)
		}
		for _, c := range a.Children {
			parents[c.ID] = append(parents[c.ID], a.ID)
		}
	}
	memo := make(map[string]string, len(own))
	onPath := map[string]bool{}
	var inherited func(string) string
	inherited = func(id string) string {
		if h, ok := memo[id]; ok {
			return h
		}
		// A parent-child cycle is malformed graph; break it rather than trust
		// the edges never to loop.
		if onPath[id] {
			return ""
		}
		onPath[id] = true
		h := ""
		for _, p := range parents[id] {
			h = stronger(h, stronger(own[p], inherited(p)))
		}
		delete(onPath, id)
		memo[id] = h
		return h
	}
	out := make(map[string]string, len(own))
	for id, h := range own {
		if h = stronger(h, inherited(id)); h != "" {
			out[id] = h
		}
	}
	return out
}

// waitHold is the hold an anchor's own open waits put on everything under it:
// parked while one is a gate or a demand, and queued while one is open work,
// a wait the source recorded but could not read included.
func waitHold(a Anchor) string {
	for _, b := range a.Blockers {
		if b.Status != "closed" && heldByPerson(b) {
			return stateParked
		}
	}
	if _, open := waitingSplit(a); len(open) > 0 {
		return stateQueued
	}
	return ""
}

// stronger is the hold that outranks the other: a person's hold over a wait on
// work, and either over none.
func stronger(a, b string) string {
	switch {
	case a == stateParked || b == stateParked:
		return stateParked
	case a == stateQueued || b == stateQueued:
		return stateQueued
	}
	return ""
}

// childState names the state an open child is counted in by its parent's
// roll-up. A child whose own bead nothing holds, but which is itself a parent
// on the board, reads what its own children are doing ([subtreeStates]): a
// sub-epic whose children wait their turn is not stranded work.
func (f Facts) childState(c Child) string {
	own := deriveState(childInput(c), f).kind
	if own == stateStranded {
		if s := f.subtree[c.ID]; s != "" {
			return s
		}
	}
	return own
}

// subtreeStates names, for every live anchor with open children, the state
// those children put it in ([rollup.subtreeState]). It works bottom-up, so a
// nested parent is read through its own nested parents the same way.
func subtreeStates(anchors []Anchor, f Facts) map[string]string {
	byID := make(map[string]Anchor, len(anchors))
	for _, a := range anchors {
		if _, ok := byID[a.ID]; !ok && a.ClosedAt.IsZero() && len(a.Children) > 0 {
			byID[a.ID] = a
		}
	}
	memo := make(map[string]string, len(byID))
	onPath := map[string]bool{}
	var classify func(Child) string
	var subtree func(string) string
	subtree = func(id string) string {
		if s, ok := memo[id]; ok {
			return s
		}
		a, ok := byID[id]
		// A parent-child cycle is malformed graph; break it rather than trust
		// the edges never to loop.
		if !ok || onPath[id] {
			return ""
		}
		onPath[id] = true
		s := rollUpBy(a, f, classify).subtreeState()
		delete(onPath, id)
		memo[id] = s
		return s
	}
	classify = func(c Child) string {
		own := deriveState(childInput(c), f).kind
		if own == stateStranded {
			if s := subtree(c.ID); s != "" {
				return s
			}
		}
		return own
	}
	for id := range byID {
		subtree(id)
	}
	return memo
}

// subtreeState is the state an anchor's open children put it in: in flight
// while any is moving, stranded while any is idle, and otherwise the first
// state its waiting children are in, in [rollup.waitingCounts] order. Empty
// when no child is open.
func (r rollup) subtreeState() string {
	switch {
	case r.open == 0:
		return ""
	case len(r.liveHeads) > 0:
		return stateInFlight
	case r.idle() > 0:
		return stateStranded
	case len(r.reviewHeads) > 0:
		return stateInReview
	case len(r.conversationHeads) > 0:
		return stateInConversation
	case len(r.queuedHeads) > 0:
		return stateQueued
	case len(r.parkedHeads) > 0:
		return stateParked
	}
	return ""
}

// inReview reports whether a bead carries a pull request the city is landing:
// open, or at the pre-open gate before it opens. The other merge_result values
// are a landed one, or a state a person resolves, which is routed to them.
func inReview(md map[string]string) bool {
	switch md[mdMergeResult] {
	case mergeResultPreOpenGate, mergeResultPullRequest:
		return true
	}
	return false
}

// heldByPerson reports whether an open blocker is one a person releases: a gate
// (a park gate, or a native human gate) or a demand ([demand]). No agent closes
// either, so a bead waiting on one is parked rather than queued.
func heldByPerson(b Blocker) bool {
	return b.IssueType == "gate" || demand(b)
}

// poolRoute reports whether a bead is routed to a pool, which claims it once
// nothing holds it. A route to the operator is a person's hold instead.
func poolRoute(md map[string]string) bool {
	r := md[mdRoutedTo]
	return r != "" && r != routedHuman
}

// oldestFirst orders blockers by creation, then id, so a phrase names the wait
// whose turn began first and the same graph always reads the same way.
func oldestFirst(bs []Blocker) []Blocker {
	out := append([]Blocker(nil), bs...)
	sort.SliceStable(out, func(i, j int) bool {
		if !out[i].CreatedAt.Equal(out[j].CreatedAt) {
			return out[i].CreatedAt.Before(out[j].CreatedAt)
		}
		return out[i].ID < out[j].ID
	})
	return out
}

// rowFrontier is a takeaway row's frontier phrase for its own state, counting
// the open waits it has. A queued row that starts by itself says so. With no
// wait to count, a person holds a takeaway row only through a visit: a row
// routed to the operator takes [frontier]'s human-gated phrases instead.
func rowFrontier(s beadState, nOpen int) string {
	if s.kind == stateParked && nOpen == 0 {
		return "held by an open visit"
	}
	phrase := s.kind
	if nOpen > 0 {
		phrase += fmt.Sprintf(" · waiting on %d", nOpen)
	}
	if s.kind == stateQueued && s.selfStart {
		phrase += " · starts by itself"
	}
	return phrase
}

// stateNeeds is a takeaway row's NEEDS when its graph says more than the
// takeaway does, and "" when the takeaway still answers.
//
// It answers in two cases. A queued or parked row whose waits the source read
// names the oldest of them, which the takeaway can only paraphrase as it stood
// when the sitting ended. A row whose recorded waits have all landed carries a
// takeaway written while they were open, so its live state answers instead.
// heldBy is the open-visit phrase ([visitHold]), empty when no visit covers
// the row.
func stateNeeds(s beadState, waiting, waitingOpen []string, heldBy string) string {
	switch {
	case s.kind == stateQueued && len(s.waits) > 0:
		phrase := "queued behind " + waitsPhrase(s)
		if s.selfStart {
			if len(s.waits)+s.unread > 1 {
				return phrase + " — starts by itself when they land"
			}
			return phrase + " — starts by itself when it lands"
		}
		return phrase
	case s.kind == stateParked && len(s.waits) > 0:
		return "parked: " + waitsPhrase(s)
	case len(waiting) == 0 || len(waitingOpen) > 0:
		return ""
	}
	switch s.kind {
	case stateInFlight:
		return "in flight"
	case stateInConversation, stateParked:
		if heldBy != "" {
			return heldBy
		}
		return s.kind
	case stateQueued:
		return "queued — starts by itself"
	}
	return ""
}

// waitsPhrase names the oldest wait by its title and counts the rest, never by
// bead id, so NEEDS stays prose.
func waitsPhrase(s beadState) string {
	name := collapseWS(s.waits[0].Title)
	if name == "" {
		name = "an untitled bead"
	}
	if more := len(s.waits) - 1 + s.unread; more > 0 {
		return fmt.Sprintf("%s and %d more", name, more)
	}
	return name
}

// waitingCounts lists the anchor's waiting children by state, in a fixed
// order, as "<n> <state>" for each state that has any.
func (r rollup) waitingCounts() []string {
	var out []string
	for _, s := range []struct {
		n      int
		phrase string
	}{
		{len(r.reviewHeads), stateInReview},
		{len(r.conversationHeads), stateInConversation},
		{len(r.queuedHeads), stateQueued},
		{len(r.parkedHeads), "parked for the operator"},
	} {
		if s.n > 0 {
			out = append(out, fmt.Sprintf("%d %s", s.n, s.phrase))
		}
	}
	return out
}

// waitingSuffix is [rollup.waitingCounts] as the frontier's trailing phrases,
// each led by " · ".
func (r rollup) waitingSuffix() string {
	counts := r.waitingCounts()
	if len(counts) == 0 {
		return ""
	}
	return " · " + strings.Join(counts, " · ")
}
