// Package standing answers where a bead stands and whose move it is: its group
// in the helm board's words, the rule that placed it there, what a person owes
// when the bead is itself the ask, and the beads that rule names
// (docs/gctk-architecture.md, "The bead stands contract"). It computes no wait,
// no pull request's status and no place in the queue: it gathers its facts
// through a [Store] and asks waits what holds a bead, prstatus where a pull
// request stands and what a person owes along a bead's waits, queue whether the
// city takes a bead, conversation a conversation's shape, and standing/person
// the rules about one bead.
package standing

import (
	"errors"
	"fmt"
	"slices"
	"sort"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/conversation"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus"
	"github.com/zookanalytics/gc-toolkit/services/gctk/queue"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// Bead is one bead in the fields the rules read of it. Status and the issue
// type read in any case.
type Bead struct {
	ID        string
	Title     string
	Status    string
	IssueType string
	AwaitType string
	Assignee  string
	Labels    []string
	// Edges is each of its own edges.
	Edges []Edge
	// Hypothesis is an epic's hypothesis, which tells an epic from a Delivery.
	Hypothesis string
	// MergeResult is its lifecycle state as a merge anchor, and PRNumber names
	// its open pull request.
	MergeResult string
	PRNumber    string
	// Anchor is the merge anchor it is a child of. Run is true for a run's
	// root or a step poured under it, EphemeralPlane for a row of the store's
	// ephemeral plane, and Template for a template molecule.
	Anchor         string
	Run            bool
	EphemeralPlane bool
	Template       bool
}

// Edge is one of a bead's own edges: the far bead and the edge's type.
type Edge struct {
	ID   string
	Type string
}

// Store is the reads the answer gathers its facts through, one store's worth:
// queue's and prstatus's reads, the saved answers for pull requests on Gas
// Town's pending record, and the beads themselves.
type Store interface {
	queue.Store
	prstatus.Store
	// PRAnswers returns the evaluator's answer for each pull request named on
	// the pending record, and the error for each it could not answer.
	PRAnswers(ids []string) (map[string]pr.Answer, map[string]error)
	// Every returns every live bead the store holds.
	Every() []Bead
	// Find returns the bead of each id named, live or closed. An id the store
	// holds no bead for is left out.
	Find(ids []string) (map[string]Bead, error)
	// ClosedBeneath returns the closed beads whose own parent-child edge names
	// one of parents.
	ClosedBeneath(parents []string) ([]Bead, error)
}

// Stands reports whether a bead has a standing of its own. A convoy, work a
// merge anchor carries, a run's root or step, a row of the store's ephemeral
// plane and a template molecule each speak through another bead, so they have
// none, and no reader counts one as a member, a conversation or a row.
func Stands(b Bead) bool {
	return issueType(b) != "convoy" && b.Anchor == "" && !b.Run && !b.EphemeralPlane && !b.Template
}

// Reading is one read's answers: each bead's standing, and the readers'
// answers it drew on, which a caller that draws the same beads reuses rather
// than asking the readers again.
type Reading struct {
	beads   map[string]Bead
	kinds   map[string]Kind
	answers map[string]Answer
	// answeredBy is the open conversation that answers each open human gate,
	// the first that replies to it, and each open decision, the first that
	// tracks it.
	answeredBy map[string]string
	holds      map[string]waits.Holds
	unread     map[string]error
	holding    map[string]prstatus.Holds
	unwalked   map[string]bool
	facts      map[string]prstatus.Facts
	prAnswers  map[string]pr.Answer
	noFacts    map[string]bool
	order      queue.Ordered
	// places is each piece of work's place in order, by id.
	places map[string]queue.Place
}

// Read answers where each bead named stands, through one store. Every read it
// makes goes through s, and a read that fails returns its error and no answer.
// A reader that could not answer for one bead leaves that bead unread, and the
// rest are answered.
func Read(ids []string, s Store) (*Reading, error) {
	r := &Reading{beads: map[string]Bead{}, kinds: map[string]Kind{}, answers: map[string]Answer{},
		answeredBy: map[string]string{}, unwalked: map[string]bool{}, noFacts: map[string]bool{}}
	live := s.Every()
	add := func(b Bead) {
		if _, dup := r.beads[b.ID]; !dup && Stands(b) {
			r.beads[b.ID] = b
		}
	}
	for _, b := range live {
		add(b)
	}
	var missing []string
	for _, id := range ids {
		if _, ok := r.beads[id]; !ok {
			missing = append(missing, id)
		}
	}
	if len(missing) > 0 {
		found, err := s.Find(missing)
		if err != nil {
			return nil, fmt.Errorf("read the beads asked about: %w", err)
		}
		for _, id := range missing {
			if b, ok := found[id]; ok {
				add(b)
			}
		}
	}
	// An epic's closed members tell whether it waits for a ruling.
	var epics []string
	for id, b := range r.beads {
		if issueType(b) == "epic" && isOpen(b) {
			epics = append(epics, id)
		}
	}
	if len(epics) > 0 {
		sort.Strings(epics)
		closed, err := s.ClosedBeneath(epics)
		if err != nil {
			return nil, fmt.Errorf("read the closed members of the epics: %w", err)
		}
		for _, b := range closed {
			add(b)
		}
	}
	r.index()

	var open []string
	for _, id := range ids {
		if b, ok := r.beads[id]; ok && isOpen(b) {
			open = append(open, id)
		}
	}
	sort.Strings(open)
	open = slices.Compact(open)
	var err error
	if r.holds, r.unread, err = s.Holds(open); err != nil {
		return nil, fmt.Errorf("read what holds the beads: %w", err)
	}

	roots := holdingRoots(open, r.holds)
	holding, err := prstatus.Holding(roots, s.Blockers)
	if err != nil {
		if !errors.Is(err, prstatus.ErrWalkBound) {
			return nil, fmt.Errorf("read what a person owes: %w", err)
		}
		for _, root := range roots {
			if _, ok := holding[root]; !ok {
				r.unwalked[root] = true
			}
		}
	}
	r.holding = holding

	var anchors []string
	for _, id := range open {
		if hasOpenPullRequest(r.beads[id]) {
			anchors = append(anchors, id)
		}
	}
	facts, err := prstatus.Read(anchors, s)
	if err != nil {
		if !errors.Is(err, prstatus.ErrWalkBound) && !errors.Is(err, prstatus.ErrUnresolved) {
			return nil, fmt.Errorf("read the pull requests: %w", err)
		}
		for _, a := range anchors {
			if _, ok := facts[a]; !ok {
				r.noFacts[a] = true
			}
		}
	}
	r.facts = facts
	// A pull request on the pending record stands where the evaluator's answer
	// says, and one it could not answer for reads unread, as `gctk pr status`
	// derives nothing for it.
	var pending []string
	for _, a := range anchors {
		if f, ok := facts[a]; ok && pr.OnRecord(f.MergeResult) {
			pending = append(pending, a)
		}
	}
	r.prAnswers, _ = s.PRAnswers(pending)
	for _, a := range pending {
		if _, ok := r.prAnswers[a]; !ok {
			r.noFacts[a] = true
		}
	}

	if r.order, err = queue.Order(openWork(live), s); err != nil {
		return nil, fmt.Errorf("place the work: %w", err)
	}
	r.places = map[string]queue.Place{}
	for _, list := range [][]queue.Place{r.order.Queue, r.order.NotScheduled} {
		for _, p := range list {
			r.places[p.ID] = p
		}
	}

	r.answer(ids)
	return r, nil
}

// index reads what each bead is and which conversation answers each question.
func (r *Reading) index() {
	ids := make([]string, 0, len(r.beads))
	for id := range r.beads {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	for _, id := range ids {
		r.kinds[id] = r.kindOf(r.beads[id])
	}
	for _, id := range ids {
		b := r.beads[id]
		if r.kinds[id] != KindConversation || !isOpen(b) {
			continue
		}
		subj, replies, _ := conversation.Shape(conversationEdges(b))
		for _, g := range replies {
			if r.openHumanGate(g) && r.answeredBy[g] == "" {
				r.answeredBy[g] = id
			}
		}
		if r.openDecision(subj) && r.answeredBy[subj] == "" {
			r.answeredBy[subj] = id
		}
	}
}

// Answer is where a bead named stands, and false for a bead the read did not
// answer, one the store holds no bead of its own for.
func (r *Reading) Answer(id string) (Answer, bool) {
	a, ok := r.answers[id]
	return a, ok
}

// Kind is what a bead is, and "" for one the read holds no bead for.
func (r *Reading) Kind(id string) Kind { return r.kinds[id] }

// AnsweredBy is the open conversation that answers an open question: the
// first that replies to an open human gate, or the first that tracks an open
// decision. It is "" for any other bead.
func (r *Reading) AnsweredBy(id string) string { return r.answeredBy[id] }

// Holds is waits' answer about what holds an open bead named, and false for a
// bead it could not answer.
func (r *Reading) Holds(id string) (waits.Holds, bool) {
	h, ok := r.holds[id]
	return h, ok
}

// Holding is prstatus's answer about the gates and the beads a person owes
// along an open bead's waits, read at the bead whose waits hold it: the bead
// itself, or the ancestor it is held through. It is false for a bead nothing
// holds, and for one whose answer was not read.
func (r *Reading) Holding(id string) (prstatus.Holds, bool) {
	h, ok := r.holds[id]
	if !ok {
		return prstatus.Holds{}, false
	}
	hold, ok := r.holding[rootOf(id, h)]
	return hold, ok
}

// PullRequest is what the read knows of a bead's open pull request, nil when
// it has none or a reader could not answer for it.
func (r *Reading) PullRequest(id string) *PR {
	f, ok := r.facts[id]
	if !ok || r.noFacts[id] {
		return nil
	}
	p := &PR{facts: f}
	if a, ok := r.prAnswers[id]; ok {
		p.answer = &a
	}
	return p
}

// Order is queue's order for every open piece of work the store holds, work
// held for the Product Owner included.
func (r *Reading) Order() queue.Ordered { return r.order }

// ForProductOwner reports whether a bead is work held for the Product Owner:
// an open piece of work that carries hold:mayor, Gas City's hold that names the
// Product Owner as its next actor. Such work asks nothing of a person.
func (r *Reading) ForProductOwner(id string) bool {
	b, ok := r.beads[id]
	return ok && r.kinds[id] == KindWork && isOpen(b) && carriesHoldMayor(b)
}

// Parked is the gate that parks an open bead: the first wait behind its status,
// its own or an ancestor's, on a gate that is no human gate. It is false for a
// bead no such gate holds.
func (r *Reading) Parked(id string) (Ref, bool) {
	h, ok := r.holds[id]
	if !ok {
		return Ref{}, false
	}
	if w := gateHold(h); w != nil {
		return Ref{ID: w.ID, Title: w.Title}, true
	}
	return Ref{}, false
}

// PR is what a read knows of a bead's open pull request: the facts prstatus
// gathered about its anchor and, for one on Gas Town's pending record, the
// evaluator's answer. Where it stands and what holds it are rendered from the
// answer when there is one, as `gctk pr status` renders them, and derived from
// the facts otherwise.
type PR struct {
	facts  prstatus.Facts
	answer *pr.Answer
}

// State is where the pull request stands.
func (p *PR) State() prstatus.State {
	if p.answer != nil {
		return prstatus.Render(*p.answer, p.facts)
	}
	return prstatus.Derive(p.facts)
}

// Held is the held: value of each thing that holds the pull request.
func (p *PR) Held() []prstatus.Hold {
	if p.answer != nil {
		return prstatus.RenderHeld(*p.answer, p.facts)
	}
	return prstatus.Held(p.facts)
}

// Reasons is each thing that holds the pull request.
func (p *PR) Reasons() []prstatus.Reason {
	if p.answer != nil {
		return prstatus.RenderReasons(*p.answer, p.facts)
	}
	return prstatus.Reasons(p.facts)
}

// holdingRoots are the beads prstatus.Holding is asked about: each bead its
// own waits hold, and the ancestor whose waits hold a bead held through it.
func holdingRoots(ids []string, holds map[string]waits.Holds) []string {
	var roots []string
	for _, id := range ids {
		h, ok := holds[id]
		if !ok {
			continue
		}
		if root := rootOf(id, h); root != "" && !slices.Contains(roots, root) {
			roots = append(roots, root)
		}
	}
	sort.Strings(roots)
	return roots
}

// rootOf is the bead whose Holding answer a bead reads: itself while its own
// waits hold it, the ancestor waits names while it is held through one, and
// none while nothing holds it.
func rootOf(id string, h waits.Holds) string {
	switch h.Status {
	case waits.Blocked, waits.Unjudged:
		return id
	case waits.Held:
		for _, w := range h.Waits {
			if w.Ancestor != "" {
				return w.Ancestor
			}
		}
	}
	return ""
}

// hasOpenPullRequest reports whether a bead is a merge anchor whose pull
// request is open, which is what its merge_result says: pull_request on the old
// record (lifecycle/lifecycle.toml), or a value [pr.OnRecord] names on Gas
// Town's pending record.
func hasOpenPullRequest(b Bead) bool {
	return b.MergeResult == "pull_request" || pr.OnRecord(b.MergeResult)
}

// openWork is every open piece of work among the live beads that stands on its
// own, work held for the Product Owner included, by id: the work queue places.
func openWork(live []Bead) []string {
	var out []string
	for _, b := range live {
		if Stands(b) && isOpen(b) && ownKind(b) == KindWork {
			out = append(out, b.ID)
		}
	}
	slices.Sort(out)
	return out
}

func status(b Bead) string    { return strings.ToLower(strings.TrimSpace(b.Status)) }
func issueType(b Bead) string { return strings.ToLower(strings.TrimSpace(b.IssueType)) }
func isOpen(b Bead) bool      { return status(b) != "closed" }

// edgesOf are the far beads of a bead's own edges of one type, each once.
func edgesOf(b Bead, typ string) []string {
	var out []string
	for _, e := range b.Edges {
		if e.Type == typ && e.ID != "" && !slices.Contains(out, e.ID) {
			out = append(out, e.ID)
		}
	}
	return out
}

func conversationEdges(b Bead) []conversation.Edge {
	out := make([]conversation.Edge, 0, len(b.Edges))
	for _, e := range b.Edges {
		out = append(out, conversation.Edge{Type: e.Type, DependsOnID: e.ID})
	}
	return out
}

func carriesHoldMayor(b Bead) bool {
	for _, l := range b.Labels {
		if strings.EqualFold(strings.TrimSpace(l), "hold:mayor") {
			return true
		}
	}
	return false
}
