package rigboard

import (
	"cmp"
	"slices"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/conversation"
	"github.com/zookanalytics/gc-toolkit/services/gctk/queue"
	"github.com/zookanalytics/gc-toolkit/services/gctk/standing"
)

// ownRow reports whether a bead is a row of its own. A child of a merge anchor
// (a review, a rework, a validation, a finding) is not: its anchor's pull
// request speaks for it, and the anchor's Details lists it. Nor is a run's
// root or a step poured under it, as waits reads one, or a convoy, a type bd
// keeps for grouping, such as the input convoy a run is poured over. The bead
// the run works speaks for the run, since the order workers take things is
// detail a working system does not expose. Nor is a bead bd's listing leaves
// out unless asked: a row of the store's ephemeral plane, such as an order
// run's tracking bead, or a template molecule.
func ownRow(b bead) bool { return standing.Stands(b.Standing()) }

// index is the gathered beads by id, with what each is.
type index struct {
	g     *gathered
	beads map[string]bead
	kinds map[string]Kind
	// rows is every row's id, open rows first.
	rows []string
	// subject is each open conversation's, off its own edges.
	subject map[string]string
	// answeredBy is the open conversation that answers each open human gate,
	// the first that replies to it, and each open decision, the first that
	// tracks it.
	answeredBy map[string]string
	// handback is each open decision's newest hand-back, recorded on a
	// conversation that tracks it, open or closed.
	handback map[string]Handback
	// children are the rows whose parent-child edge names each bead.
	children map[string][]string
	// within is the epics and Deliveries each row sits under nearest
	// (containers).
	within map[string][]string
}

func newIndex(g *gathered) *index {
	ix := &index{g: g, beads: map[string]bead{}, kinds: map[string]Kind{}, subject: map[string]string{},
		answeredBy: map[string]string{}, handback: map[string]Handback{}, children: map[string][]string{},
		within: map[string][]string{}}
	for _, list := range [][]bead{g.open, g.closed} {
		for _, b := range list {
			if _, dup := ix.beads[b.ID]; dup || !ownRow(b) {
				continue
			}
			ix.beads[b.ID] = b
			ix.rows = append(ix.rows, b.ID)
		}
	}
	for _, id := range ix.rows {
		ix.kinds[id] = Kind(g.reading.Kind(id))
		if c := g.reading.AnsweredBy(id); c != "" {
			ix.answeredBy[id] = c
		}
	}
	for _, id := range ix.rows {
		ix.within[id] = ix.containers(id)
	}
	for _, id := range ix.rows {
		b := ix.beads[id]
		for _, p := range parents(b) {
			ix.children[p] = append(ix.children[p], id)
		}
		if ix.kinds[id] != KindConversation || !isOpen(b) {
			continue
		}
		subj, _, _ := conversation.Shape(conversationEdges(b))
		ix.subject[id] = subj
	}
	for _, c := range g.handedBack {
		if strings.TrimSpace(c.Handback) == "" || !conversation.IsCandidate(issueType(c), c.Assignee, c.ID) {
			continue
		}
		subj, _, ok := conversation.Shape(conversationEdges(c))
		if !ok || !ix.openDecision(subj) {
			continue
		}
		if cur, held := ix.handback[subj]; held && !newerHandback(c, cur) {
			continue
		}
		ix.handback[subj] = Handback{Conversation: c.ID, At: c.HandbackAt, Text: c.Handback}
	}
	return ix
}

// newerHandback reports whether c's hand-back was recorded after cur: at a
// later time, or at the same time on a conversation whose id sorts after it, so
// one store gives one answer. A time that does not read is older than any.
func newerHandback(c bead, cur Handback) bool {
	at, _ := time.Parse(time.RFC3339, c.HandbackAt)
	was, _ := time.Parse(time.RFC3339, cur.At)
	if !at.Equal(was) {
		return at.After(was)
	}
	return c.ID > cur.Conversation
}

func conversationEdges(b bead) []conversation.Edge {
	out := make([]conversation.Edge, 0, len(b.Edges))
	for _, e := range b.Edges {
		out = append(out, conversation.Edge{Type: e.Type, DependsOnID: e.ID})
	}
	return out
}

func (ix *index) openDecision(id string) bool {
	b, ok := ix.beads[id]
	return ok && isOpen(b) && ix.kinds[id] == KindDecision
}

// containers are the epics and Deliveries a row sits under nearest. Its
// parent-child edges, and each parent's in turn, are followed through other
// rows, every parent a bead names, and each path stops at the first epic or
// Delivery it reaches. A path also stops at a parent the read did not gather
// and at a bead the walk has passed, so a cycle ends and a parent missing from
// the read costs only its own path. Each container is named once, and a row
// under none has none.
func (ix *index) containers(id string) []string {
	var out []string
	seen := map[string]bool{id: true}
	for next := []string{id}; len(next) > 0; {
		var more []string
		for _, cur := range next {
			for _, p := range parents(ix.beads[cur]) {
				if seen[p] {
					continue
				}
				seen[p] = true
				if _, ok := ix.beads[p]; !ok {
					continue
				}
				switch ix.kinds[p] {
				case KindEpic, KindDelivery:
					out = append(out, p)
				default:
					more = append(more, p)
				}
			}
		}
		next = more
	}
	return out
}

// ancestors are every epic and Delivery a row sits under at any depth, through
// every container above it, each once and nearest first.
func (ix *index) ancestors(id string) []string {
	var out []string
	for next := ix.within[id]; len(next) > 0; {
		var more []string
		for _, c := range next {
			if c == id || slices.Contains(out, c) {
				continue
			}
			out = append(out, c)
			more = append(more, ix.within[c]...)
		}
		next = more
	}
	return out
}

// built is the per-row answers build keeps while it composes the pages.
type built struct {
	ix      *index
	verdict map[string]verdict
	asks    map[string]*askAnswer
	rows    map[string]Row
	// order is the rig's open work in the Work queue's order, the queue and
	// then the work after it, and pos is each piece's place in it. after marks
	// the work after the queue, and unread is the work a reader could not
	// answer, which has no place.
	order  []string
	pos    map[string]int
	after  map[string]bool
	unread []string
	// needs is every open need, and concern is what each one concerns: itself,
	// the beads it holds, and the bead its conversation is about.
	needs   []string
	concern map[string][]string
	// held is every bead each ask holds through any chain of waits, of any kind
	// and work held for the Product Owner included, and counts marks the needs
	// that count.
	held   map[string][]string
	counts map[string]bool
}

func build(g *gathered) Document {
	ix := newIndex(g)
	bt := &built{ix: ix, verdict: map[string]verdict{}, asks: map[string]*askAnswer{}, rows: map[string]Row{},
		pos: map[string]int{}, after: map[string]bool{}, concern: map[string][]string{}, held: map[string][]string{},
		counts: map[string]bool{}}

	// Each row's ask first: a row's words read its ask.
	answers := map[string]standing.Answer{}
	for _, id := range ix.rows {
		a, ok := g.reading.Answer(id)
		if !ok {
			a = standing.Answer{Rule: standing.RuleUnread}
		}
		answers[id] = a
		if ask := bt.askWords(id, a); ask != nil {
			bt.asks[id] = ask
		}
	}
	for _, id := range ix.rows {
		bt.verdict[id] = bt.verdictOf(id, answers[id])
	}

	for _, id := range ix.rows {
		bt.rows[id] = bt.row(id)
	}
	bt.place()
	bt.linkWaits()
	bt.linkHolds()
	bt.findNeeds()
	bt.count()

	doc := Document{Rig: g.rig, Rows: bt.rows}
	doc.Epics = bt.epicsPage()
	doc.NeedsYou = bt.needsYouPage()
	doc.WorkQueue = bt.queueOf(func(string) bool { return true })
	doc.Unprioritized = bt.unprioritizedPage()
	return doc
}

// row is one row before the asks are linked and the counts made.
func (bt *built) row(id string) Row {
	ix := bt.ix
	b := ix.beads[id]
	k := ix.kinds[id]
	v := bt.verdict[id]
	r := Row{ID: id, Kind: k, Priority: b.Priority, Title: b.Title, Status: status(b), CreatedAt: b.CreatedAt,
		Assignee: b.Assignee, Signal: v.signal, Note: v.note, Group: v.group, Line2: line2(b, k), Line3: v.line3,
		Waits: []Ref{}, WaitedOnBy: []Ref{}, Holds: []string{}}
	if a := bt.asks[id]; a != nil {
		r.Ask = a.kind
		if a.kind == AskPullRequest {
			r.Reasons = reasonsOf(ix.g.reading.PullRequest(id))
		}
	}
	if h, ok := ix.g.reading.Holds(id); ok {
		r.Waits = refsOf(h.Waits)
		if r.Waits == nil {
			r.Waits = []Ref{}
		}
	}
	r.PullRequest = pullRequestOf(b, ix.g.reading.PullRequest(id))
	if k == KindEpic {
		r.Contract = contractOf(b)
	}
	if k == KindGate || k == KindDecision {
		r.Conversation = ix.answeredBy[id]
	}
	if h, ok := ix.handback[id]; ok {
		r.Handback = &h
	}
	for _, o := range ix.g.open {
		if o.Anchor == id {
			r.Anchored = append(r.Anchored, Ref{ID: o.ID, Title: o.Title})
		}
	}
	return r
}

// line2 is an epic's hypothesis, a Delivery's aim, or the message of a gate, a
// decision or a conversation, less its first line when that line is the
// title, as assets/scripts/human-gate.sh titles a gate.
func line2(b bead, k Kind) string {
	switch k {
	case KindEpic:
		return strings.TrimSpace(b.Epic.Hypothesis)
	case KindDelivery:
		for _, l := range strings.Split(b.Description, "\n") {
			if l = strings.TrimSpace(l); strings.HasPrefix(l, "Aim:") {
				return l
			}
		}
		return ""
	case KindGate, KindDecision, KindConversation:
		d := strings.TrimSpace(b.Description)
		first, rest, _ := strings.Cut(d, "\n")
		if strings.Join(strings.Fields(first), " ") == strings.TrimSpace(b.Title) {
			return strings.TrimSpace(rest)
		}
		return d
	}
	return ""
}

func contractOf(b bead) *Contract {
	e := b.Epic
	return &Contract{
		Handle:           e.Handle,
		Hypothesis:       e.Hypothesis,
		Boundaries:       e.Boundaries,
		ClosureCondition: e.ClosureCondition,
		Indicators:       e.Indicators,
		Ruling:           e.Ruling,
		RulingReason:     e.RulingReason,
		RulingAt:         e.RulingAt,
	}
}

// isWork reports whether a row is work a Work queue lists: an open piece of
// work that is not held for the Product Owner.
func (bt *built) isWork(id string) bool {
	return bt.ix.kinds[id] == KindWork && isOpen(bt.ix.beads[id]) && !bt.forProductOwner(id)
}

// forProductOwner reports whether a row is work held for the Product Owner: an
// open piece of work that carries hold:mayor. The Unprioritized page alone
// lists it, so no view lists it and no count counts it, though the work behind
// it waits on it all the same.
func (bt *built) forProductOwner(id string) bool { return bt.ix.g.reading.ForProductOwner(id) }

// place lists the rig's open work in the Work queue's order once, the order
// services/gctk/queue gave the read, so every view lists work in that one
// order: the queue, then the ready work nothing sends anywhere after it. The
// read asked for the order of every open piece of work, work held for the
// Product Owner included, so the work behind held work sits behind it in the
// queue. Held work is then left out of the order, since no view lists it. Work
// a reader could not answer has no place in it and is listed apart: work whose
// row reads unread, and work the order places nowhere, whose row can still
// read as an ask.
func (bt *built) place() {
	list := func(places []queue.Place, after bool) {
		for _, p := range places {
			if !bt.isWork(p.ID) || bt.verdict[p.ID].rule == standing.RuleUnread {
				continue
			}
			bt.pos[p.ID] = len(bt.order)
			bt.order = append(bt.order, p.ID)
			if after {
				bt.after[p.ID] = true
			}
		}
	}
	order := bt.ix.g.reading.Order()
	list(order.Queue, false)
	list(order.NotScheduled, true)
	for _, id := range bt.ix.rows {
		if _, placed := bt.pos[id]; bt.isWork(id) && !placed {
			bt.unread = append(bt.unread, id)
		}
	}
	bt.sortIDs(bt.unread)
}

// linkWaits fills what waits on each row: the open beads whose own waits name
// it.
func (bt *built) linkWaits() {
	for _, id := range bt.ix.rows {
		h, ok := bt.ix.g.reading.Holds(id)
		if !ok {
			continue
		}
		for _, w := range h.Waits {
			if w.Ancestor != "" {
				continue
			}
			if far, ok := bt.rows[w.ID]; ok {
				far.WaitedOnBy = append(far.WaitedOnBy, Ref{ID: id, Title: bt.rows[id].Title})
				bt.rows[w.ID] = far
			}
		}
	}
}

// linkHolds fills the beads each need holds through any chain of waits, each
// row that stands beneath the need, as standing answers it (Reading.Beneath).
// held takes every one of them, whatever its kind and work held for the Product
// Owner included, since whether a need counts reads every bead it holds. A
// need's Holds, the list the board draws beneath it, takes each piece of work,
// epic and Delivery among them, in the Work queue's order, less work held for
// the Product Owner.
func (bt *built) linkHolds() {
	ix := bt.ix
	for _, id := range ix.rows {
		k := ix.kinds[id]
		listed := (k == KindWork || k == KindEpic || k == KindDelivery) && !bt.forProductOwner(id)
		for _, a := range ix.g.reading.Beneath(id) {
			bt.held[a] = append(bt.held[a], id)
			if listed {
				ar := bt.rows[a]
				ar.Holds = append(ar.Holds, id)
				bt.rows[a] = ar
			}
		}
	}
	for id, r := range bt.rows {
		bt.inOrder(r.Holds)
		bt.rows[id] = r
	}
}

// inOrder sorts ids into the Work queue's order: the work it places by its
// place, then every other row by priority, then oldest, then id.
func (bt *built) inOrder(ids []string) {
	slices.SortFunc(ids, func(a, b string) int {
		pa, placedA := bt.pos[a]
		pb, placedB := bt.pos[b]
		switch {
		case placedA && placedB:
			return cmp.Compare(pa, pb)
		case placedA:
			return -1
		case placedB:
			return 1
		}
		ra, rb := bt.rows[a], bt.rows[b]
		return cmp.Or(cmp.Compare(ra.Priority, rb.Priority), cmp.Compare(ra.CreatedAt, rb.CreatedAt), cmp.Compare(a, b))
	})
}

// findNeeds lists every open need, what each one concerns, and whether it
// counts. A need concerns itself, the beads it holds, and the bead its
// conversation is about unless that is work held for the Product Owner. What it
// is about is every bead it holds and that bead, held work included. Every need
// counts until counted finds it does not, and a need that leaves the count can
// take a need about it out too, so counted reads the needs again until none
// leaves.
func (bt *built) findNeeds() {
	ix := bt.ix
	about := map[string][]string{}
	for _, id := range ix.rows {
		if bt.asks[id] == nil || !isOpen(ix.beads[id]) {
			continue
		}
		bt.needs = append(bt.needs, id)
		c := append([]string{id}, bt.rows[id].Holds...)
		a := slices.Clone(bt.held[id])
		for _, x := range []string{id, bt.rows[id].Conversation} {
			s := ix.subject[x]
			if x == "" || s == "" || s == id {
				continue
			}
			if !slices.Contains(a, s) {
				a = append(a, s)
			}
			if !bt.forProductOwner(s) && !slices.Contains(c, s) {
				c = append(c, s)
			}
		}
		bt.concern[id] = c
		about[id] = a
		bt.counts[id] = true
	}
	for left := true; left; {
		left = false
		for _, id := range bt.needs {
			if bt.counts[id] && !bt.counted(id, about[id]) {
				bt.counts[id] = false
				left = true
			}
		}
	}
}

// counted reports whether a need counts, given every bead it is about. A need
// parked itself does not. A gate, a decision or a conversation does not when
// every bead it is about is parked, carries hold:mayor or is a need that does
// not count, and one about nothing counts. A pull request, or other work that
// is itself a need, counts unless it is parked itself, whatever it holds.
func (bt *built) counted(id string, about []string) bool {
	if bt.parked(id) {
		return false
	}
	switch bt.ix.kinds[id] {
	case KindGate, KindDecision, KindConversation:
		return len(about) == 0 || slices.ContainsFunc(about, bt.live)
	}
	return true
}

// live reports whether a bead a need is about keeps the need in the count: it
// is not parked, it carries no hold:mayor, and it is no need that has left the
// count.
func (bt *built) live(id string) bool {
	counts, need := bt.counts[id]
	return !bt.parked(id) && !bt.onDesk(id) && (!need || counts)
}

// parked reports whether a bead waits on a park, or an epic or a Delivery above
// it does: a wait behind its status on a gate that is no human gate, as
// standing reads the bead and each of those above it (Reading.Parked). Each is
// read for its own waits, so work in flight under a parked epic, which the
// epic's wait does not hold, is parked with it.
func (bt *built) parked(id string) bool {
	for _, x := range append([]string{id}, bt.ix.ancestors(id)...) {
		if _, ok := bt.ix.g.reading.Parked(x); ok {
			return true
		}
	}
	return false
}

// onDesk reports whether a bead is the Unprioritized page's: an open bead that
// carries hold:mayor.
func (bt *built) onDesk(id string) bool {
	b, ok := bt.ix.beads[id]
	return ok && isOpen(b) && carriesHoldMayor(b)
}

// count makes each epic's and Delivery's counts at any depth: the needs that
// count and hold or concern it, each once, and its work by where it sits, each
// row once however many paths lead to it.
func (bt *built) count() {
	ix := bt.ix
	counts := map[string]*Counts{}
	for _, id := range ix.rows {
		if k := ix.kinds[id]; k == KindEpic || k == KindDelivery {
			counts[id] = &Counts{}
		}
	}
	for _, id := range ix.rows {
		if ix.kinds[id] != KindWork {
			continue
		}
		_, placed := bt.pos[id]
		for _, a := range ix.ancestors(id) {
			c := counts[a]
			switch {
			case !isOpen(ix.beads[id]):
				c.Closed++
			case bt.after[id]:
				c.NotScheduled++
			case placed:
				c.Queue++
			}
		}
	}
	for _, n := range bt.needs {
		if !bt.counts[n] {
			continue
		}
		var counted []string
		for _, x := range bt.concern[n] {
			for _, a := range append([]string{x}, ix.ancestors(x)...) {
				if a == n || counts[a] == nil || slices.Contains(counted, a) {
					continue
				}
				counted = append(counted, a)
				counts[a].Needs++
			}
		}
	}
	for id, c := range counts {
		r := bt.rows[id]
		r.Counts = c
		bt.rows[id] = r
	}
}

// sortIDs orders rows by priority, then oldest first, then by id.
func (bt *built) sortIDs(ids []string) {
	slices.SortFunc(ids, func(a, b string) int {
		ra, rb := bt.rows[a], bt.rows[b]
		return cmp.Or(cmp.Compare(ra.Priority, rb.Priority), cmp.Compare(ra.CreatedAt, rb.CreatedAt), cmp.Compare(a, b))
	})
}

// under reports whether a row sits nearest under a container: the views of an
// epic or a Delivery cover the rows it holds nearest, so a row under a
// Delivery is listed under the Delivery and not again under its epic.
func (bt *built) under(container string) func(string) bool {
	return func(id string) bool { return slices.Contains(bt.ix.within[id], container) }
}

// queueOf is a Work queue view over the work covers admits, in the one order
// place made.
func (bt *built) queueOf(covers func(string) bool) WorkQueue {
	q := WorkQueue{Queue: []string{}, NotScheduled: []string{}, Unread: []string{}}
	for _, id := range bt.order {
		switch {
		case !covers(id):
		case bt.after[id]:
			q.NotScheduled = append(q.NotScheduled, id)
		default:
			q.Queue = append(q.Queue, id)
		}
	}
	for _, id := range bt.unread {
		if covers(id) {
			q.Unread = append(q.Unread, id)
		}
	}
	return q
}

// needsOf is a container's Needs you view: each need that concerns it or a
// row it holds nearest, other than itself, with the rows it holds there.
func (bt *built) needsOf(container string) NeedsYou {
	covers := bt.under(container)
	var needs []Need
	for _, n := range bt.needs {
		if n == container || !slices.ContainsFunc(bt.concern[n], func(x string) bool { return x == container || covers(x) }) {
			continue
		}
		held := []string{}
		for _, x := range bt.rows[n].Holds {
			if covers(x) {
				held = append(held, x)
			}
		}
		needs = append(needs, Need{ID: n, Kind: bt.asks[n].need, Holds: held})
	}
	return bt.view(needs, covers)
}

// view is a Needs you view of the needs it lists: each in need order, those
// that count first, and how many of each kind count.
func (bt *built) view(needs []Need, covers func(string) bool) NeedsYou {
	bt.sortNeeds(needs, covers)
	v := NeedsYou{Counted: []Need{}, NotCounted: []Need{}}
	by := map[NeedKind]int{}
	for _, n := range needs {
		if !bt.counts[n.ID] {
			v.NotCounted = append(v.NotCounted, n)
			continue
		}
		v.Counted = append(v.Counted, n)
		by[n.Kind]++
	}
	v.Count = len(v.Counted)
	v.Kinds = kindCounts(by)
	return v
}

// kindCounts is how many needs of each kind count, in the order a view reads
// them: the five kinds every view shows, each one zero included, so a glance
// tells which is empty, then Assigned to you when one counts.
func kindCounts(by map[NeedKind]int) []KindCount {
	out := []KindCount{}
	for _, k := range []NeedKind{NeedKindPullRequest, NeedKindQuestion, NeedKindWaitsForYou, NeedKindInConversation, NeedKindRuling} {
		out = append(out, KindCount{Kind: k, Count: by[k]})
	}
	if n := by[NeedKindAssignedToYou]; n > 0 {
		out = append(out, KindCount{Kind: NeedKindAssignedToYou, Count: n})
	}
	return out
}

// sortNeeds puts a view's needs in need order: by the first place in the Work
// queue's order among the beads listed beneath each, and the need itself when
// it is work the view covers, so the top need is the one holding up the front
// of the queue. A need with no such place comes last. Ties go by priority,
// then oldest, then id.
func (bt *built) sortNeeds(needs []Need, covers func(string) bool) {
	first := map[string]int{}
	for _, n := range needs {
		best := -1
		at := n.Holds
		if covers(n.ID) {
			at = append([]string{n.ID}, n.Holds...)
		}
		for _, x := range at {
			if p, ok := bt.pos[x]; ok && (best < 0 || p < best) {
				best = p
			}
		}
		first[n.ID] = best
	}
	slices.SortFunc(needs, func(a, b Need) int {
		if fa, fb := first[a.ID], first[b.ID]; fa != fb {
			switch {
			case fa < 0:
				return 1
			case fb < 0:
				return -1
			}
			return cmp.Compare(fa, fb)
		}
		ra, rb := bt.rows[a.ID], bt.rows[b.ID]
		return cmp.Or(cmp.Compare(ra.Priority, rb.Priority), cmp.Compare(ra.CreatedAt, rb.CreatedAt), cmp.Compare(a.ID, b.ID))
	})
}

// closedOf is a container's closed work, the closed work it holds nearest, by
// priority, then oldest, then id.
func (bt *built) closedOf(container string) []string {
	covers := bt.under(container)
	out := []string{}
	for _, id := range bt.ix.rows {
		if bt.ix.kinds[id] == KindWork && !isOpen(bt.ix.beads[id]) && covers(id) {
			out = append(out, id)
		}
	}
	bt.sortIDs(out)
	return out
}

func (bt *built) epicsPage() []EpicEntry {
	var epics []string
	for _, id := range bt.ix.rows {
		if bt.ix.kinds[id] == KindEpic && isOpen(bt.ix.beads[id]) {
			epics = append(epics, id)
		}
	}
	bt.sortIDs(epics)
	out := []EpicEntry{}
	for _, e := range epics {
		entry := EpicEntry{ID: e, Needs: bt.needsOf(e), Queue: bt.queueOf(bt.under(e)), Closed: bt.closedOf(e),
			Deliveries: []DeliveryEntry{}}
		var dels []string
		for _, id := range bt.ix.rows {
			if bt.ix.kinds[id] == KindDelivery && slices.Contains(bt.ix.within[id], e) {
				dels = append(dels, id)
			}
		}
		bt.sortIDs(dels)
		for _, d := range dels {
			entry.Deliveries = append(entry.Deliveries, DeliveryEntry{ID: d, Needs: bt.needsOf(d),
				Queue: bt.queueOf(bt.under(d)), Closed: bt.closedOf(d)})
		}
		out = append(out, entry)
	}
	return out
}

// needsYouPage is every open need in the rig, each with every bead it holds,
// in need order, and how many of them count.
func (bt *built) needsYouPage() NeedsYou {
	var needs []Need
	for _, id := range bt.needs {
		needs = append(needs, Need{ID: id, Kind: bt.asks[id].need, Holds: slices.Clone(bt.rows[id].Holds)})
	}
	return bt.view(needs, func(string) bool { return true })
}

// carriesHoldMayor reports whether a bead carries hold:mayor, the label that
// puts it on the Product Owner's desk, in every spelling the work queue's order
// reads it in (queue.ForProductOwner), so a bead that hold keeps out of the
// ready work nothing sends is on the Unprioritized page.
func carriesHoldMayor(b bead) bool { return queue.ForProductOwner(b.Labels) }

func (bt *built) unprioritizedPage() []PriorityGroup {
	by := map[int][]string{}
	for _, id := range bt.ix.rows {
		if b := bt.ix.beads[id]; isOpen(b) && carriesHoldMayor(b) {
			by[b.Priority] = append(by[b.Priority], id)
		}
	}
	var ps []int
	for p := range by {
		ps = append(ps, p)
	}
	slices.Sort(ps)
	out := []PriorityGroup{}
	for _, p := range ps {
		ids := by[p]
		slices.SortFunc(ids, func(a, b string) int {
			return cmp.Or(cmp.Compare(bt.rows[b].CreatedAt, bt.rows[a].CreatedAt), cmp.Compare(a, b))
		})
		out = append(out, PriorityGroup{Priority: p, IDs: ids})
	}
	return out
}
