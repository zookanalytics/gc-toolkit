// Package rigboard reads one rig's store once and builds the rig's board: one
// document holding every row the pages draw and the four pages as lists of
// those rows. The read is a gctk listing (services/gctk/listing), which lists
// the store once and answers every shared reader from the rows it read:
// services/gctk/waits for what holds a bead and whether it is in flight,
// services/gctk/prstatus for what a person owes on a bead and where a pull
// request stands, and services/gctk/queue for the order the rig's work is
// expected to land in. services/gctk/conversation says what a conversation
// is. Where a pull request on Gas Town's pending record stands is the pr
// domain's evaluator's answer, which the listing asks over the same rows and
// GitHub's facts about the PR, rendered through prstatus as `gctk pr status`
// renders it. One table (table.go) turns those answers into a row's group and
// signal, and it holds no rule of its own about what holds a bead, whose move
// it is or whether work is moving.
//
// The listing decodes each key the board shows, so the board spells no key.
// The document depends on the store's answers and, for each pull request on
// the pending record, GitHub's facts no older than gitHubMaxAge, so it can be
// cached whole per rig and dropped when a write lands.
package rigboard

import (
	"context"
	"errors"
	"fmt"
	"path/filepath"
	"slices"
	"sort"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/listing"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus"
	"github.com/zookanalytics/gc-toolkit/services/gctk/queue"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// GC runs one gc subcommand and decodes its JSON output into out. The service
// passes the seam internal/source/gccli.go holds, and a test passes a fake.
type GC interface {
	JSON(ctx context.Context, out any, args ...string) error
}

// Rig is one rig as the city lists it: its name and its store, a .beads
// directory.
type Rig struct {
	Name  string
	Store string
}

// ReadRigs lists the city's rigs, as `gc rig list` names them.
func ReadRigs(ctx context.Context, gc GC) ([]Rig, error) {
	var payload struct {
		Rigs []struct {
			Name string `json:"name"`
			Path string `json:"path"`
		} `json:"rigs"`
	}
	if err := gc.JSON(ctx, &payload, "rig", "list", "--json"); err != nil {
		return nil, err
	}
	var out []Rig
	for _, r := range payload.Rigs {
		if r.Name == "" || r.Path == "" {
			continue
		}
		out = append(out, Rig{Name: r.Name, Store: filepath.Join(r.Path, ".beads")})
	}
	return out, nil
}

// bead is one bead as the listing read it.
type bead = listing.Bead

// status is a bead's status, lower-cased and trimmed.
func status(b bead) string { return strings.ToLower(strings.TrimSpace(b.Status)) }

// issueType is a bead's issue type, lower-cased and trimmed.
func issueType(b bead) string { return strings.ToLower(strings.TrimSpace(b.IssueType)) }

// isOpen reports whether a bead is at any status but closed.
func isOpen(b bead) bool { return status(b) != "closed" }

// parents are the beads its parent-child edges name.
func parents(b bead) []string { return edgesOf(b, "parent-child") }

// edgesOf are the far beads of its edges of one type, each once.
func edgesOf(b bead, typ string) []string {
	var out []string
	for _, e := range b.Edges {
		if e.Type == typ && e.ID != "" && !slices.Contains(out, e.ID) {
			out = append(out, e.ID)
		}
	}
	return out
}

// gathered is everything one gather read: the beads, and each reader's
// answers about them. build turns it into the document and reads nothing more.
type gathered struct {
	rig string
	// open is every live bead the listing read. closed is the closed members
	// of each open epic and Delivery, and of each closed epic beneath one
	// (readClosedMembers).
	open   []bead
	closed []bead
	// holds is waits' answer for each open row, and unread the error for each
	// it could not answer.
	holds  map[string]waits.Holds
	unread map[string]error
	// holding is prstatus.Holding's answer for each root asked, and
	// unwalked the roots whose walk ran past its bound.
	holding  map[string]prstatus.Holds
	unwalked map[string]bool
	// facts is prstatus.Read's answer for each bead with an open pull
	// request, and answers the evaluator's answer for each of them on Gas
	// Town's pending record. noFacts holds each bead with an open pull request
	// a reader could not answer for: prstatus.Read, or the evaluator for a
	// pull request on the pending record.
	facts   map[string]prstatus.Facts
	answers map[string]pr.Answer
	noFacts map[string]bool
	// order is queue.Order's answer for every open piece of work (openWork).
	order queue.Ordered
}

// Read reads one rig's store once, through a gctk listing, and builds its
// document. A read that fails returns its error and no document, so a caller
// never draws a board from a read that did not happen. Every store call and
// every read of GitHub the read makes ends when ctx does, the processes it
// started killed with it, so a read that runs out has stopped them all when it
// returns, and it returns ctx's cause, never a document with the pull requests
// it did not finish reading.
func Read(ctx context.Context, rig Rig) (Document, error) {
	ls, err := listing.Read(ctx, rig.Store)
	if err != nil {
		return Document{}, fmt.Errorf("list the beads of %s: %w", rig.Name, err)
	}
	g, err := gather(ls, rig.Name)
	if err != nil {
		return Document{}, err
	}
	if ctx.Err() != nil {
		return Document{}, fmt.Errorf("read the board of %s: %w", rig.Name, context.Cause(ctx))
	}
	return build(g), nil
}

// gather asks each shared reader its question of the listing's rows.
func gather(ls *listing.Listing, rig string) (*gathered, error) {
	g := &gathered{rig: rig, open: ls.Live()}
	var err error
	if g.closed, err = readClosedMembers(ls, g.open); err != nil {
		return nil, err
	}

	byID := map[string]bead{}
	for _, b := range g.open {
		byID[b.ID] = b
	}
	var ids []string
	for _, b := range g.open {
		if ownRow(b) {
			ids = append(ids, b.ID)
		}
	}
	sort.Strings(ids)
	if g.holds, g.unread, err = ls.Holds(ids); err != nil {
		return nil, fmt.Errorf("read what holds the beads of %s: %w", rig, err)
	}

	roots := holdingRoots(ids, g.holds)
	holding, err := prstatus.Holding(roots, ls.Blockers)
	g.unwalked = map[string]bool{}
	if err != nil {
		if !errors.Is(err, prstatus.ErrWalkBound) {
			return nil, fmt.Errorf("read what %s owes a person: %w", rig, err)
		}
		for _, r := range roots {
			if _, ok := holding[r]; !ok {
				g.unwalked[r] = true
			}
		}
	}
	g.holding = holding

	var anchors []string
	for _, id := range ids {
		if hasOpenPullRequest(byID[id]) {
			anchors = append(anchors, id)
		}
	}
	facts, err := prstatus.Read(anchors, ls)
	g.noFacts = map[string]bool{}
	if err != nil {
		if !errors.Is(err, prstatus.ErrWalkBound) && !errors.Is(err, prstatus.ErrUnresolved) {
			return nil, fmt.Errorf("read the pull requests of %s: %w", rig, err)
		}
		for _, a := range anchors {
			if _, ok := facts[a]; !ok {
				g.noFacts[a] = true
			}
		}
	}
	g.facts = facts

	// The evaluator reads GitHub, so it runs beside the queue's read of the
	// store, and the gather waits for it on every path, so a read that returns
	// has stopped every call it started.
	var pending []string
	for _, a := range anchors {
		if f, ok := facts[a]; ok && pr.OnRecord(f.MergeResult) {
			pending = append(pending, a)
		}
	}
	evaluated := make(chan map[string]pr.Answer, 1)
	go func() { a, _ := ready(ls, pending); evaluated <- a }()

	g.order, err = queue.Order(openWork(g.open), ls)
	g.answers = <-evaluated
	if err != nil {
		return nil, fmt.Errorf("place the work of %s: %w", rig, err)
	}
	for _, a := range pending {
		if _, ok := g.answers[a]; !ok {
			g.noFacts[a] = true
		}
	}
	return g, nil
}

// gitHubMaxAge is how old an answer from GitHub the read takes about a pull
// request on Gas Town's pending record (listing.Ready). The landing order
// (orders/pr-reconcile.toml) runs every five minutes and reads GitHub for at
// most twenty such PRs a run, so at this age the board asks GitHub about a PR
// no more often than the order that lands it can. A page left open on a rig
// then spends about sixty of the account's 5,000 GraphQL points an hour on
// each such PR, where a read of GitHub with every document, once a minute,
// would spend three hundred. The cost is a board up to five minutes behind
// GitHub: an approval reads needs-review until the next read of GitHub after
// it. The store's side of the answer is read with every document.
const gitHubMaxAge = 5 * time.Minute

// ready is the evaluator's answer the gather asks for the PRs on Gas Town's
// pending record: listing.Ready at gitHubMaxAge. A PR it does not answer reads
// unread, as `gctk pr status` derives nothing for it. It is a variable so that
// the package's tests answer without GitHub.
var ready = func(ls *listing.Listing, ids []string) (map[string]pr.Answer, map[string]error) {
	return ls.Ready(ids, gitHubMaxAge)
}

// prFacts is what the read knows of a bead's open pull request: the facts
// prstatus.Read gathered about its anchor and, for a PR on Gas Town's pending
// record, the evaluator's answer. Where the PR stands and what holds it are
// rendered from the answer when there is one, as `gctk pr status` renders
// them, and derived from the facts otherwise.
type prFacts struct {
	facts  prstatus.Facts
	answer *pr.Answer
}

// prFactsOf is what the read knows of a bead's open pull request, nil when it
// has none or a reader could not answer for it.
func prFactsOf(g *gathered, id string) *prFacts {
	f, ok := g.facts[id]
	if !ok || g.noFacts[id] {
		return nil
	}
	p := &prFacts{facts: f}
	if a, ok := g.answers[id]; ok {
		p.answer = &a
	}
	return p
}

// state is where the pull request stands.
func (p *prFacts) state() prstatus.State {
	if p.answer != nil {
		return prstatus.Render(*p.answer, p.facts)
	}
	return prstatus.Derive(p.facts)
}

// held is the held: value of each thing that holds the pull request.
func (p *prFacts) held() []prstatus.Hold {
	if p.answer != nil {
		return prstatus.RenderHeld(*p.answer, p.facts)
	}
	return prstatus.Held(p.facts)
}

// reasons is each thing that holds the pull request.
func (p *prFacts) reasons() []prstatus.Reason {
	if p.answer != nil {
		return prstatus.RenderReasons(*p.answer, p.facts)
	}
	return prstatus.Reasons(p.facts)
}

// readClosedMembers reads the closed members of each open epic and Delivery,
// then the closed members of each closed epic among them, such as a Delivery
// that landed while its epic stays open, and so on until a round reads no
// closed epic it had not read. Closed work beneath a bead that is not an epic
// stays unread, since reading it would take one read per parent.
func readClosedMembers(ls *listing.Listing, open []bead) ([]bead, error) {
	var next []string
	for _, b := range open {
		if issueType(b) == "epic" {
			next = append(next, b.ID)
		}
	}
	asked := map[string]bool{}
	seen := map[string]bool{}
	var out []bead
	for len(next) > 0 {
		for _, p := range next {
			asked[p] = true
		}
		rows, err := ls.ClosedUnder(next)
		if err != nil {
			return nil, err
		}
		next = nil
		for _, r := range rows {
			if seen[r.ID] {
				continue
			}
			seen[r.ID] = true
			out = append(out, r)
			if issueType(r) == "epic" && !asked[r.ID] {
				next = append(next, r.ID)
			}
		}
	}
	return out, nil
}

// holdingRoots are the beads prstatus.Holding is asked about: each bead its
// own waits hold, and the ancestor whose waits hold a bead held through it.
func holdingRoots(ids []string, holds map[string]waits.Holds) []string {
	var roots []string
	add := func(id string) {
		if id != "" && !slices.Contains(roots, id) {
			roots = append(roots, id)
		}
	}
	for _, id := range ids {
		h, ok := holds[id]
		if !ok {
			continue
		}
		switch h.Status {
		case waits.Blocked, waits.Unjudged:
			add(id)
		case waits.Held:
			add(holdingAncestor(h))
		}
	}
	sort.Strings(roots)
	return roots
}

// holdingAncestor is the ancestor whose waits hold a held bead, as waits names
// it on each wait.
func holdingAncestor(h waits.Holds) string {
	for _, w := range h.Waits {
		if w.Ancestor != "" {
			return w.Ancestor
		}
	}
	return ""
}

// hasOpenPullRequest reports whether a bead is a merge anchor whose pull
// request is open, which is what its merge_result says: pull_request on the old
// record (lifecycle/lifecycle.toml), or a value [pr.OnRecord] names on Gas
// Town's pending record.
func hasOpenPullRequest(b bead) bool {
	return b.MergeResult == "pull_request" || pr.OnRecord(b.MergeResult)
}
