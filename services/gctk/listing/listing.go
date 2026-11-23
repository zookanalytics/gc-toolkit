// Package listing reads a bead store once for a reader that asks several
// domains about the same beads, the helm board and the landing order's label
// writes among them, and answers that reader from the one read. A Listing is a
// ledger pass (docs/gctk-architecture.md, "The ledger"): it lists every live
// bead in the store, reads each bead beyond them at most once, and every
// question asked of it answers from those rows. It gives each bead as a Bead,
// whose keys it decodes through its declarations, so the reader spells no key
// and parses no value. It answers what holds a bead through waits, and it is
// prstatus's Store and queue's, so a pull request's facts, what a person owes
// and the order work lands in come from the same rows the reader lays out. It
// asks the pr domain's evaluator about a PR on Gas Town's pending record over
// those rows too, with the read the one-PR update saved on the PR's bead
// ([Listing.PRAnswers]), and derives the labels each open PR shows from both
// ([Listing.PRLabels]).
//
// The package sits outside internal/ so the helm board, which lies outside
// services/gctk, can import it, while the ledger stays internal.
package listing

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"sync"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/prstatus"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
	"github.com/zookanalytics/gc-toolkit/services/gctk/standing/person"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// Bead is one bead as a listing read it: its row's own fields, its own edges,
// the keys a reader takes from it, and the domains' answers that are the
// bead's own.
type Bead struct {
	ID          string
	Title       string
	Description string
	// Status is lower-cased. IssueType is as the row writes it.
	Status    string
	IssueType string
	Assignee  string
	AwaitType string
	Priority  int
	Labels    []string
	CreatedAt string
	ClosedAt  string
	// EphemeralPlane is true for a bead the store keeps in its ephemeral
	// plane, a wisp or a row stored with no history, such as a patrol's
	// molecule or an order run's tracking bead, and Template for a template
	// molecule. bd's listing leaves both out unless asked.
	EphemeralPlane bool
	Template       bool
	// Edges is each of its own edges, in the row's order.
	Edges []Edge
	// Anchor is the merge anchor it is a child of, empty on a bead that is no
	// anchor's child.
	Anchor string
	// RoutedTo is the pool or agent it is routed to.
	RoutedTo string
	// WorkOutcome is how its work ended, as the bead reports it.
	WorkOutcome string
	// MergeResult is its lifecycle state as a merge anchor, empty on a bead
	// that is none.
	MergeResult string
	// PRNumber and PRURL name its open pull request.
	PRNumber string
	PRURL    string
	// Epic is its contract and latest ruling, empty on a bead that records
	// none.
	Epic Epic
	// Handback is the latest hand-back a conversation's sitting recorded on
	// it, and HandbackAt when, each empty on a bead that records none.
	Handback   string
	HandbackAt string
	// Run is true for one of a run's own beads, its root or a step poured under
	// it ([waits.IsRootOrStep]).
	Run bool
}

// Edge is one of a bead's own edges: the far bead and the edge's type.
type Edge struct {
	ID   string
	Type string
}

// Epic is an epic's contract and its latest ruling, each as its key holds it.
type Epic struct {
	Handle           string
	Hypothesis       string
	Boundaries       string
	ClosureCondition string
	Indicators       string
	Ruling           string
	RulingReason     string
	RulingAt         string
}

// Listing is one pass's read of a store.
type Listing struct {
	pass *ledger.Ledger
	live []*ledger.Record
	// beads is each bead decoded, by id, and closed each parent's closed beads
	// as closedUnder read them, which the store answers only by a read of its
	// own.
	mu     sync.Mutex
	beads  map[string]Bead
	closed map[string][]Bead
}

// Read lists the store at db, a store's .beads directory, once: every live
// bead it holds. With db empty it reads the store gc routes a read of the
// first of ids to, as [ledger.Open] does, and the store gc resolves when ids
// names none. A read that fails returns its error and no listing. Every read of
// the store the listing makes, then and for each question asked of it later,
// ends when ctx does, and the processes it started end with it.
func Read(ctx context.Context, db string, ids ...string) (*Listing, error) {
	l, err := ledger.OpenContext(ctx, db, ids...)
	if err != nil {
		return nil, err
	}
	return read(l)
}

// Over lists the store l reads through once, as Read does. A caller that
// holds a pass over the store hands it over, such as a run of the landing
// order, and the listing answers from the rows that pass kept.
func Over(l *ledger.Ledger) (*Listing, error) { return read(l) }

// read lists every live bead through a pass over l.
func read(l *ledger.Ledger) (*Listing, error) {
	ls := &Listing{pass: l.Pass(), beads: map[string]Bead{}, closed: map[string][]Bead{}}
	live, err := ls.pass.Find(ledger.Every())
	if err != nil {
		return nil, err
	}
	ls.live = live
	for _, r := range live {
		if _, err := ls.bead(r); err != nil {
			return nil, err
		}
	}
	return ls, nil
}

// Live is every live bead the listing read, in the order the store listed
// them.
func (ls *Listing) Live() []Bead {
	out := make([]Bead, 0, len(ls.live))
	for _, r := range ls.live {
		b, _ := ls.bead(r) // read decoded every live bead
		out = append(out, b)
	}
	return out
}

// bead is r decoded, once.
func (ls *Listing) bead(r *ledger.Record) (Bead, error) {
	ls.mu.Lock()
	b, ok := ls.beads[r.ID]
	ls.mu.Unlock()
	if ok {
		return b, nil
	}
	b, err := beadOf(r)
	if err != nil {
		return Bead{}, err
	}
	ls.mu.Lock()
	ls.beads[r.ID] = b
	ls.mu.Unlock()
	return b, nil
}

func beadOf(r *ledger.Record) (Bead, error) {
	edges, err := r.Edges()
	if err != nil {
		return Bead{}, &ledger.ReadError{ID: r.ID, Reason: "its edges did not decode: " + err.Error()}
	}
	b := Bead{ID: r.ID, Title: r.Title(), Description: r.Description(), Status: r.Status(), IssueType: r.IssueType(),
		Assignee: r.Assignee(), AwaitType: r.AwaitType(), Priority: r.Priority(), Labels: r.Labels(),
		CreatedAt: r.CreatedAt(), ClosedAt: r.ClosedAt(), EphemeralPlane: r.EphemeralPlane(), Template: r.Template(),
		Anchor: text(anchorKey, r), RoutedTo: text(routedToKey, r), WorkOutcome: text(workOutcomeKey, r),
		MergeResult: text(record.Result, r), PRNumber: text(record.PRNumber, r), PRURL: text(record.PRURL, r),
		Epic: Epic{
			Handle: text(epicHandleKey, r), Hypothesis: text(epicHypothesisKey, r), Boundaries: text(epicBoundariesKey, r),
			ClosureCondition: text(epicClosureKey, r), Indicators: text(epicIndicatorsKey, r), Ruling: text(epicRulingKey, r),
			RulingReason: text(epicRulingReasonKey, r), RulingAt: text(epicRulingAtKey, r),
		},
		Handback: text(handbackKey, r), HandbackAt: text(handbackAtKey, r),
		Run: waits.IsRootOrStep(r)}
	for _, e := range edges {
		b.Edges = append(b.Edges, Edge{ID: e.ID, Type: e.Type})
	}
	return b, nil
}

// text is a String key's value on r as the row holds it, empty when r does not
// carry it. A String key's stored text always decodes.
func text(k interface {
	Get(*ledger.Record) (string, bool, error)
}, r *ledger.Record) string {
	v, _, _ := k.Get(r)
	return v
}

// closedReadLimit bounds how many reads of a parent's beads run at once.
const closedReadLimit = 6

// ClosedUnder reads the closed beads under each parent named, in the order of
// the parents' ids. The store lists a parent's beads, and its filter can
// return a bead whose own parent-child edge names another parent, so a bead
// counts under a parent by its own edge alone. At most closedReadLimit reads
// run at once, and a read that fails fails the whole read.
func (ls *Listing) ClosedUnder(parents []string) ([]Bead, error) {
	parents = slices.Compact(slices.Sorted(slices.Values(parents)))
	results := make([][]Bead, len(parents))
	errs := make([]error, len(parents))
	sem := make(chan struct{}, closedReadLimit)
	var wg sync.WaitGroup
	for i, p := range parents {
		wg.Add(1)
		go func() {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			results[i], errs[i] = ls.closedUnder(p)
		}()
	}
	wg.Wait()
	if err := errors.Join(errs...); err != nil {
		return nil, err
	}
	var out []Bead
	for _, rows := range results {
		out = append(out, rows...)
	}
	return out, nil
}

func (ls *Listing) closedUnder(parent string) ([]Bead, error) {
	ls.mu.Lock()
	kept, ok := ls.closed[parent]
	ls.mu.Unlock()
	if ok {
		return kept, nil
	}
	recs, err := ls.pass.Find(ledger.Under(parent).WithClosed())
	if err != nil {
		return nil, fmt.Errorf("list the closed beads under %s: %w", parent, err)
	}
	var out []Bead
	for _, r := range recs {
		if r.Status() != "closed" {
			continue
		}
		ps, err := r.Parents()
		if err != nil {
			return nil, &ledger.ReadError{ID: r.ID, Reason: "its edges did not decode: " + err.Error()}
		}
		if !slices.Contains(ps, parent) {
			continue
		}
		b, err := ls.bead(r)
		if err != nil {
			return nil, err
		}
		out = append(out, b)
	}
	ls.mu.Lock()
	ls.closed[parent] = out
	ls.mu.Unlock()
	return out, nil
}

// HandedBack reads every bead in the store that records a hand-back, closed or
// live: the conversations whose sittings posted one, a sitting that ended at
// its hand-off among them, since its conversation has closed. It is one read of
// the store, and a read that fails returns its error.
func (ls *Listing) HandedBack() ([]Bead, error) {
	recs, err := ls.pass.Find(ledger.Carrying(handbackKey).WithClosed())
	if err != nil {
		return nil, fmt.Errorf("list the beads that record a hand-back: %w", err)
	}
	out := make([]Bead, 0, len(recs))
	for _, r := range recs {
		b, err := ls.bead(r)
		if err != nil {
			return nil, err
		}
		out = append(out, b)
	}
	return out, nil
}

// Holds answers what holds each bead named, through waits, from the listing's
// rows: the answer for each bead it could answer, and the error for each it
// could not. A read that fails returns its error. It implements queue.Store.
func (ls *Listing) Holds(ids []string) (map[string]waits.Holds, map[string]error, error) {
	snap, err := waits.Read(ls.pass, ids...)
	if err != nil {
		return nil, nil, err
	}
	holds, failed := map[string]waits.Holds{}, map[string]error{}
	for _, id := range ids {
		h, err := snap.Holds(id)
		if err != nil {
			failed[id] = err
			continue
		}
		holds[id] = h
	}
	return holds, failed, nil
}

var _ prstatus.Store = (*Listing)(nil)

// Beads implements prstatus.Store: the row of each bead named the store holds,
// with its metadata as the listing read it.
func (ls *Listing) Beads(ids []string) (map[string]prstatus.Row, error) {
	recs, err := ls.pass.Find(ledger.ByID(ids...).WithClosed())
	if err != nil {
		return nil, err
	}
	out := make(map[string]prstatus.Row, len(recs))
	for _, r := range recs {
		out[r.ID] = prstatus.Row{ID: r.ID, Metadata: r.Rendered()}
	}
	return out, nil
}

// Anchored implements prstatus.Store over the listing's live beads, which are
// every bead the store holds at a status other than closed. A closed status
// is refused, because the listing holds no closed bead.
func (ls *Listing) Anchored(ids []string, statuses []string) (map[string][]prstatus.Row, error) {
	if slices.Contains(statuses, "closed") {
		return nil, errors.New("listing: the beads anchored at closed are not listed, since a listing holds live beads alone")
	}
	out := map[string][]prstatus.Row{}
	for _, r := range ls.live {
		a := text(anchorKey, r)
		if a == "" || !slices.Contains(ids, a) || !slices.Contains(statuses, r.Status()) {
			continue
		}
		out[a] = append(out[a], prstatus.Row{ID: r.ID, Metadata: r.Rendered()})
	}
	return out, nil
}

// Blockers implements prstatus.Store and is the read prstatus.Holding walks:
// for each bead named, the far bead of each of its blocks edges. An edge onto a
// bead the store does not hold is one into another store, which holds
// nothing.
func (ls *Listing) Blockers(ids []string) (map[string][]person.Blocker, error) {
	recs, err := ls.byID(ids)
	if err != nil {
		return nil, err
	}
	var far []string
	for _, id := range ids {
		r, ok := recs[id]
		if !ok {
			return nil, &ledger.ReadError{ID: id, Reason: "the store holds no such bead"}
		}
		f, err := blocksOf(r)
		if err != nil {
			return nil, err
		}
		far = append(far, f...)
	}
	farRecs, err := ls.byID(far)
	if err != nil {
		return nil, err
	}
	out := make(map[string][]person.Blocker, len(ids))
	for _, id := range ids {
		out[id] = []person.Blocker{}
		f, _ := blocksOf(recs[id]) // decoded above
		for _, x := range f {
			if fr, ok := farRecs[x]; ok {
				out[id] = append(out[id], blockerOf(fr))
			}
		}
	}
	return out, nil
}

// byID is each bead named the store holds, closed or live, as the pass read it.
func (ls *Listing) byID(ids []string) (map[string]*ledger.Record, error) {
	recs, err := ls.pass.Find(ledger.ByID(ids...).WithClosed())
	if err != nil {
		return nil, err
	}
	out := make(map[string]*ledger.Record, len(recs))
	for _, r := range recs {
		out[r.ID] = r
	}
	return out, nil
}

// blocksOf is the far bead of each of r's blocks edges, each once.
func blocksOf(r *ledger.Record) ([]string, error) {
	edges, err := r.Edges()
	if err != nil {
		return nil, &ledger.ReadError{ID: r.ID, Reason: "its edges did not decode: " + err.Error()}
	}
	var out []string
	for _, e := range edges {
		if e.Type == ledger.EdgeBlocks && !slices.Contains(out, e.ID) {
			out = append(out, e.ID)
		}
	}
	return out, nil
}

// blockerOf is r in the fields prstatus reads of a blocker.
func blockerOf(r *ledger.Record) person.Blocker {
	return person.Blocker{ID: r.ID, Title: r.Title(), Status: r.Status(), IssueType: r.IssueType(),
		AwaitType: r.AwaitType(), Assignee: r.Assignee(), Metadata: r.Rendered()}
}
