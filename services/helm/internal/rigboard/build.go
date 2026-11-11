package rigboard

import (
	"cmp"
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/conversation"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// ownRow reports whether a bead is a row of its own. A bead that carries
// anchor_bead (a review, a rework, a validation, a finding) is not: its
// anchor's pull request speaks for it, and the anchor's Details lists it. Nor
// is a bead a workflow run keeps for itself: its root, which names its input
// convoy, each step poured under it, which names the root, and the convoy, a
// type bd keeps for grouping. The bead the run works speaks for the run, since
// the order workers take things is detail a working system does not expose.
func ownRow(b bead) bool {
	switch b.issueType() {
	case "convoy", "molecule":
		return false
	}
	for _, k := range []string{"anchor_bead", "gc.root_bead_id", "gc.input_convoy_id"} {
		if b.meta(k) != "" {
			return false
		}
	}
	return true
}

// index is the gathered beads by id, with what each is.
type index struct {
	g     *gathered
	beads map[string]bead
	kinds map[string]Kind
	// rows is every row's id, open rows first.
	rows []string
	// subject and replies are each conversation's, off its own edges.
	subject map[string]string
	// answeredBy is the open conversation that answers each open human gate.
	answeredBy map[string]string
	// children are the rows whose parent-child edge names each bead.
	children map[string][]string
}

func newIndex(g *gathered) *index {
	ix := &index{g: g, beads: map[string]bead{}, kinds: map[string]Kind{}, subject: map[string]string{},
		answeredBy: map[string]string{}, children: map[string][]string{}}
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
		ix.kinds[id] = ix.kindOf(ix.beads[id])
	}
	for _, id := range ix.rows {
		b := ix.beads[id]
		for _, p := range b.parents() {
			ix.children[p] = append(ix.children[p], id)
		}
		if ix.kinds[id] != KindConversation || !b.open() {
			continue
		}
		subj, replies, _ := conversation.Shape(conversationEdges(b))
		ix.subject[id] = subj
		for _, r := range replies {
			if ix.openHumanGate(r) && ix.answeredBy[r] == "" {
				ix.answeredBy[r] = id
			}
		}
	}
	return ix
}

func conversationEdges(b bead) []conversation.Edge {
	out := make([]conversation.Edge, 0, len(b.Dependencies))
	for _, e := range b.Dependencies {
		out = append(out, conversation.Edge{Type: e.Type, DependsOnID: e.DependsOnID})
	}
	return out
}

// kindOf is what a bead is. A Delivery is an epic whose parent is an epic and
// which carries no hypothesis (docs/epics.md, "What a Delivery is as a bead").
// A conversation is a task in the shape conversation.Shape reads.
func (ix *index) kindOf(b bead) Kind {
	switch b.issueType() {
	case "gate":
		return KindGate
	case "decision":
		return KindDecision
	case "epic":
		if b.meta("epic_hypothesis") == "" {
			for _, p := range b.parents() {
				if pb, ok := ix.beads[p]; ok && pb.issueType() == "epic" {
					return KindDelivery
				}
			}
		}
		return KindEpic
	}
	if conversation.IsCandidate(b.issueType(), b.Assignee, b.ID) {
		if _, _, ok := conversation.Shape(conversationEdges(b)); ok {
			return KindConversation
		}
	}
	return KindWork
}

func (ix *index) openHumanGate(id string) bool {
	b, ok := ix.beads[id]
	return ok && b.open() && prstatus.IsHumanGate(b.IssueType, b.AwaitType)
}

// container is the epic or Delivery a row sits under: the nearest one its
// parent-child edges reach through other work. It is empty for a row under
// none.
func (ix *index) container(id string) string {
	seen := map[string]bool{id: true}
	cur := id
	for {
		ps := ix.beads[cur].parents()
		if len(ps) == 0 {
			return ""
		}
		p := ps[0]
		if seen[p] {
			return ""
		}
		seen[p] = true
		if _, ok := ix.beads[p]; !ok {
			return ""
		}
		switch ix.kinds[p] {
		case KindEpic, KindDelivery:
			return p
		}
		cur = p
	}
}

// ancestors are every epic and Delivery a row sits under at any depth, nearest
// first.
func (ix *index) ancestors(id string) []string {
	var out []string
	for c := ix.container(id); c != "" && !slices.Contains(out, c); c = ix.container(c) {
		out = append(out, c)
	}
	return out
}

// epicsOf are the epics, not Deliveries, a bead sits under or is.
func (ix *index) epicsOf(id string) []string {
	var out []string
	if ix.kinds[id] == KindEpic {
		out = append(out, id)
	}
	for _, a := range ix.ancestors(id) {
		if ix.kinds[a] == KindEpic && !slices.Contains(out, a) {
			out = append(out, a)
		}
	}
	return out
}

// built is the per-row answers build keeps while it composes the pages.
type built struct {
	ix      *index
	verdict map[string]verdict
	asks    map[string]*askAnswer
	rows    map[string]Row
}

func build(g *gathered) Document {
	ix := newIndex(g)
	bt := &built{ix: ix, verdict: map[string]verdict{}, asks: map[string]*askAnswer{}, rows: map[string]Row{}}

	// Row 2 first: an ask's words are what an own wait on it reads.
	for _, id := range ix.rows {
		b := ix.beads[id]
		k := ix.kinds[id]
		conv := ix.answeredBy[id]
		convAssignee := ""
		if conv != "" {
			convAssignee = ix.beads[conv].Assignee
		}
		members, open := 0, 0
		if k == KindEpic || k == KindDelivery {
			for _, c := range ix.children[id] {
				if ck := ix.kinds[c]; ck == KindWork || ck == KindDelivery {
					members++
					if ix.beads[c].open() {
						open++
					}
				}
			}
		}
		if a := askOf(b, k, conv, convAssignee, ix.openHumanGate, factsOf(g, id), open, members); a != nil {
			bt.asks[id] = a
		}
	}
	owedSignal := func(o prstatus.Blocker) string {
		if a, ok := bt.asks[o.ID]; ok {
			return a.words
		}
		return ""
	}
	for _, id := range ix.rows {
		in := tableInput{b: ix.beads[id], kind: ix.kinds[id], ask: bt.asks[id], facts: factsOf(g, id),
			prUnread: g.noFacts[id], owedSignal: owedSignal}
		if h, ok := g.holds[id]; ok {
			in.holds = &h
			if root := rootOf(id, h); root != "" {
				if hold, ok := g.holding[root]; ok {
					in.holding = &hold
				} else if g.unwalked[root] {
					in.unwalked = true
				}
			}
		}
		bt.verdict[id] = table(in)
	}

	for _, id := range ix.rows {
		bt.rows[id] = bt.row(id)
	}
	bt.linkAsks()
	bt.count()

	doc := Document{Rig: g.rig, Rows: bt.rows}
	doc.Epics = bt.epicsPage()
	doc.NeedsYou = bt.needsYouPage(doc.Epics)
	doc.WorkQueue = bt.workQueuePage()
	doc.Unprioritized = bt.unprioritizedPage()
	return doc
}

// rootOf is the bead whose Holding answer a row reads: itself while its own
// waits hold it, the ancestor waits names while it is held through one, and
// none while nothing holds it.
func rootOf(id string, h waits.Holds) string {
	switch h.Status {
	case waits.Blocked, waits.Unjudged:
		return id
	case waits.Held:
		return holdingAncestor(h)
	}
	return ""
}

func factsOf(g *gathered, id string) *prstatus.Facts {
	if f, ok := g.facts[id]; ok {
		return &f
	}
	return nil
}

// row is one row before the asks are linked and the counts made.
func (bt *built) row(id string) Row {
	ix := bt.ix
	b := ix.beads[id]
	k := ix.kinds[id]
	v := bt.verdict[id]
	r := Row{ID: id, Kind: k, Priority: b.Priority, Title: b.Title, Status: b.status(), CreatedAt: b.CreatedAt,
		Assignee: b.Assignee, Signal: v.signal, Note: v.note, Group: v.group, Line2: line2(b, k), Line3: v.line3,
		Waits: []Ref{}, WaitedOnBy: []Ref{}, Asks: []string{}, Holds: []string{}}
	if a := bt.asks[id]; a != nil {
		r.Ask = a.kind
		if a.kind == AskPullRequest {
			r.Reasons = reasonsOf(factsOf(ix.g, id))
		}
	}
	if h, ok := ix.g.holds[id]; ok {
		r.Waits = refsOf(h.Waits)
		if r.Waits == nil {
			r.Waits = []Ref{}
		}
	}
	r.PullRequest = pullRequestOf(b, factsOf(ix.g, id))
	if k == KindEpic {
		r.Contract = contractOf(b)
	}
	if k == KindGate || k == KindDecision {
		r.Conversation = ix.answeredBy[id]
	}
	for _, o := range ix.g.open {
		if o.meta("anchor_bead") == id {
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
		return strings.TrimSpace(b.meta("epic_hypothesis"))
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
	return &Contract{
		Handle:           b.meta("epic_handle"),
		Hypothesis:       b.meta("epic_hypothesis"),
		Boundaries:       b.meta("epic_boundaries"),
		ClosureCondition: b.meta("epic_closure_condition"),
		Indicators:       b.meta("epic_indicators"),
		Ruling:           b.meta("epic_ruling"),
		RulingReason:     b.meta("epic_ruling_reason"),
		RulingAt:         b.meta("epic_ruling_at"),
	}
}

// askID is the ask a bead stands in: a conversation that answers a gate stands
// in the gate's ask, and any other ask stands in its own. It is empty for a
// bead that is no ask.
func (bt *built) askID(id string) string {
	if bt.ix.kinds[id] == KindConversation {
		for g, c := range bt.ix.answeredBy {
			if c == id {
				return g
			}
		}
	}
	if _, ok := bt.asks[id]; ok {
		return id
	}
	return ""
}

// linkAsks fills what waits on each row, the asks that stop each row's work,
// and the work each ask holds.
func (bt *built) linkAsks() {
	ix := bt.ix
	for _, id := range ix.rows {
		h, ok := ix.g.holds[id]
		if !ok {
			continue
		}
		r := bt.rows[id]
		for _, w := range h.Waits {
			if w.Ancestor != "" {
				continue
			}
			if far, ok := bt.rows[w.ID]; ok {
				far.WaitedOnBy = append(far.WaitedOnBy, Ref{ID: id, Title: r.Title})
				bt.rows[w.ID] = far
			}
			if a := bt.askID(w.ID); a != "" && !slices.Contains(r.Asks, a) {
				r.Asks = append(r.Asks, a)
			}
		}
		bt.rows[id] = r
	}
	for conv, subj := range ix.subject {
		a := bt.askID(conv)
		if r, ok := bt.rows[subj]; ok && a != "" && !slices.Contains(r.Asks, a) {
			r.Asks = append(r.Asks, a)
			bt.rows[subj] = r
		}
	}
	for _, id := range ix.rows {
		k := ix.kinds[id]
		if k != KindWork && k != KindEpic && k != KindDelivery {
			continue
		}
		h, ok := ix.g.holds[id]
		if !ok {
			continue
		}
		hold, ok := ix.g.holding[rootOf(id, h)]
		if !ok {
			continue
		}
		for _, x := range append(slices.Clone(hold.Gates), hold.Owed...) {
			a := bt.askID(x.ID)
			if a == "" || a == id {
				continue
			}
			ar := bt.rows[a]
			if !slices.Contains(ar.Holds, id) {
				ar.Holds = append(ar.Holds, id)
				bt.rows[a] = ar
			}
		}
	}
	for id, r := range bt.rows {
		bt.sortIDs(r.Asks)
		bt.sortIDs(r.Holds)
		bt.rows[id] = r
	}
}

// count makes each epic's and Delivery's counts: the work under it at any
// depth, by group.
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
		for _, a := range ix.ancestors(id) {
			c := counts[a]
			switch bt.rows[id].Group {
			case GroupWaitingOnYou:
				c.WaitingOnYou++
			case GroupQueued:
				c.Queued++
			case GroupNotMoving:
				c.NotMoving++
			case GroupClosed:
				c.Closed++
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

var groupOrder = []Group{GroupWaitingOnYou, GroupQueued, GroupNotMoving, GroupClosed}

// groupsOf splits the work rows a container holds into its groups, and the
// rows no group holds.
func (bt *built) groupsOf(container string) ([]GroupList, []string) {
	by := map[Group][]string{}
	unread := []string{}
	for _, id := range bt.ix.rows {
		if bt.ix.kinds[id] != KindWork || bt.ix.container(id) != container {
			continue
		}
		if g := bt.rows[id].Group; g != "" {
			by[g] = append(by[g], id)
		} else {
			unread = append(unread, id)
		}
	}
	lists := []GroupList{}
	for _, g := range groupOrder {
		if ids := by[g]; len(ids) > 0 {
			bt.sortIDs(ids)
			lists = append(lists, GroupList{Group: g, IDs: ids})
		}
	}
	bt.sortIDs(unread)
	return lists, unread
}

func (bt *built) epicsPage() []EpicEntry {
	var epics []string
	for _, id := range bt.ix.rows {
		if bt.ix.kinds[id] == KindEpic && bt.ix.beads[id].open() {
			epics = append(epics, id)
		}
	}
	bt.sortIDs(epics)
	out := []EpicEntry{}
	for _, e := range epics {
		entry := EpicEntry{ID: e, Asks: bt.rows[e].Asks, Deliveries: []DeliveryEntry{}}
		var dels []string
		for _, id := range bt.ix.rows {
			if bt.ix.kinds[id] == KindDelivery && bt.ix.container(id) == e {
				dels = append(dels, id)
			}
		}
		bt.sortIDs(dels)
		for _, d := range dels {
			de := DeliveryEntry{ID: d, Asks: bt.rows[d].Asks}
			de.Groups, de.Unread = bt.groupsOf(d)
			entry.Deliveries = append(entry.Deliveries, de)
		}
		entry.Groups, entry.Unread = bt.groupsOf(e)
		out = append(out, entry)
	}
	return out
}

func (bt *built) needsYouPage(epics []EpicEntry) NeedsYou {
	ix := bt.ix
	var asks []string
	for _, id := range ix.rows {
		if bt.asks[id] != nil && ix.beads[id].open() {
			asks = append(asks, id)
		}
	}
	bt.sortIDs(asks)
	epicsOfAsk := map[string][]string{}
	for _, a := range asks {
		concern := append([]string{a}, bt.rows[a].Holds...)
		for _, c := range []string{a, bt.rows[a].Conversation} {
			if s := ix.subject[c]; s != "" {
				concern = append(concern, s)
			}
		}
		var es []string
		for _, c := range concern {
			for _, e := range ix.epicsOf(c) {
				if !slices.Contains(es, e) {
					es = append(es, e)
				}
			}
		}
		epicsOfAsk[a] = es
	}
	n := NeedsYou{InConversation: []string{}, NoConversationYet: []EpicAsks{}, NoEpic: []string{}}
	for _, a := range asks {
		if len(epicsOfAsk[a]) > 0 {
			n.Count++
		}
		switch {
		case bt.asks[a].kind == AskConversation || bt.rows[a].Conversation != "":
			n.InConversation = append(n.InConversation, a)
		case len(epicsOfAsk[a]) == 0:
			n.NoEpic = append(n.NoEpic, a)
		}
	}
	for _, e := range epics {
		var under []string
		for _, a := range asks {
			if bt.asks[a].kind == AskConversation || bt.rows[a].Conversation != "" {
				continue
			}
			if slices.Contains(epicsOfAsk[a], e.ID) {
				under = append(under, a)
			}
		}
		if len(under) > 0 {
			n.NoConversationYet = append(n.NoConversationYet, EpicAsks{Epic: e.ID, Asks: under})
		}
	}
	return n
}

// The Work queue's sections, in order.
const (
	sectionInFlight     = "In flight"
	sectionPullRequest  = "Pull request"
	sectionQueued       = "Queued"
	sectionBehind       = "Waiting behind other work"
	sectionEndsOnYou    = "Ends on you"
	sectionBehindRest   = "The rest"
	sectionHeldByGate   = "Held by a gate"
	sectionDeferred     = "Deferred"
	sectionNotScheduled = "Not scheduled"
	sectionUnread       = "Unread"
)

func (bt *built) workQueuePage() []Section {
	ix := bt.ix
	by := map[outcome][]string{}
	gates := map[string][]string{}
	for _, id := range ix.rows {
		b := ix.beads[id]
		if ix.kinds[id] != KindWork || !b.open() || carriesHoldMayor(b) {
			continue
		}
		v := bt.verdict[id]
		if v.out == outHeldByGate {
			gates[v.gate] = append(gates[v.gate], id)
			continue
		}
		by[v.out] = append(by[v.out], id)
	}
	section := func(name string, out outcome) Section {
		ids := by[out]
		bt.sortIDs(ids)
		s := Section{Name: name, Rows: []Entry{}}
		for _, id := range ids {
			s.Rows = append(s.Rows, Entry{ID: id})
		}
		return s
	}
	var sections []Section
	add := func(s Section) {
		if len(s.Rows) > 0 || len(s.Parts) > 0 {
			sections = append(sections, s)
		}
	}
	add(section(sectionInFlight, outInFlight))
	add(section(sectionPullRequest, outPullRequest))
	add(section(sectionQueued, outQueued))
	behind := Section{Name: sectionBehind, Rows: []Entry{}}
	for _, p := range []Section{section(sectionEndsOnYou, outEndsOnYou), section(sectionBehindRest, outQueuedBehind)} {
		if len(p.Rows) > 0 {
			behind.Parts = append(behind.Parts, p)
		}
	}
	add(behind)
	held := Section{Name: sectionHeldByGate, Rows: []Entry{}}
	var gateIDs []string
	for g := range gates {
		gateIDs = append(gateIDs, g)
	}
	bt.sortIDs(gateIDs)
	for _, g := range gateIDs {
		bt.sortIDs(gates[g])
		held.Rows = append(held.Rows, Entry{ID: g, Children: gates[g]})
	}
	add(held)
	add(section(sectionDeferred, outNotOpen))
	add(section(sectionNotScheduled, outNotScheduled))
	add(section(sectionUnread, outUnread))
	if sections == nil {
		sections = []Section{}
	}
	return sections
}

// carriesHoldMayor reports whether a bead carries hold:mayor, the label that
// puts it on the Product Owner's desk, trimmed and in any case, as Gas City's
// HasDispatchHold compares a label.
func carriesHoldMayor(b bead) bool {
	for _, l := range b.Labels {
		if strings.EqualFold(strings.TrimSpace(l), "hold:mayor") {
			return true
		}
	}
	return false
}

func (bt *built) unprioritizedPage() []PriorityGroup {
	by := map[int][]string{}
	for _, id := range bt.ix.rows {
		if b := bt.ix.beads[id]; b.open() && carriesHoldMayor(b) {
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
