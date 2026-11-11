// Package rigboard reads one rig's store once and builds the rig's board: one
// document holding every row the pages draw and the four pages as lists of
// those rows. Every state in it is the answer of one of the pack's shared
// readers, asked once per gather: services/gctk/waits for what holds a bead and
// whether it is in flight, services/gctk/prstatus for what a person owes on a
// bead and where a pull request stands, and services/gctk/conversation for what
// a conversation is. One table (table.go) turns those answers into a row's
// group and signal, and it holds no rule of its own about what holds a bead,
// whose move it is or whether work is moving.
//
// The gather reads through the gc command, never through a store library, and
// the document depends on the store's answers alone, so it can be cached whole
// per rig and dropped when a write lands.
package rigboard

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"path/filepath"
	"slices"
	"sort"
	"strings"
	"sync"

	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus"
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

// bead is one row of `gc bd list --json`, the fields the read uses.
type bead struct {
	ID           string                     `json:"id"`
	Title        string                     `json:"title"`
	Description  string                     `json:"description"`
	Status       string                     `json:"status"`
	Priority     int                        `json:"priority"`
	IssueType    string                     `json:"issue_type"`
	Assignee     string                     `json:"assignee"`
	Labels       []string                   `json:"labels"`
	Metadata     map[string]json.RawMessage `json:"metadata"`
	CreatedAt    string                     `json:"created_at"`
	ClosedAt     string                     `json:"closed_at"`
	AwaitType    string                     `json:"await_type"`
	Dependencies []edge                     `json:"dependencies"`
}

// edge is one of a bead's own dependency edges, as the listing prints it.
type edge struct {
	DependsOnID string `json:"depends_on_id"`
	Type        string `json:"type"`
}

// meta is the value of a metadata key as `(.metadata[k] // "") | tostring`
// renders it: a string as it is, any other value as its JSON text, and null or
// an absent key as "".
func (b bead) meta(k string) string {
	raw, ok := b.Metadata[k]
	if !ok {
		return ""
	}
	raw = bytes.TrimSpace(raw)
	if len(raw) == 0 || string(raw) == "null" {
		return ""
	}
	var s string
	if err := json.Unmarshal(raw, &s); err == nil {
		return s
	}
	return string(raw)
}

// metadata is every metadata value rendered as meta renders it.
func (b bead) metadata() map[string]string {
	out := make(map[string]string, len(b.Metadata))
	for k := range b.Metadata {
		out[k] = b.meta(k)
	}
	return out
}

func (b bead) status() string    { return strings.ToLower(strings.TrimSpace(b.Status)) }
func (b bead) issueType() string { return strings.ToLower(strings.TrimSpace(b.IssueType)) }
func (b bead) open() bool        { return b.status() != "closed" }

// parents are the beads its parent-child edges name.
func (b bead) parents() []string {
	var out []string
	for _, e := range b.Dependencies {
		if e.Type == "parent-child" && e.DependsOnID != "" && !slices.Contains(out, e.DependsOnID) {
			out = append(out, e.DependsOnID)
		}
	}
	return out
}

// edgesOf are the far beads of its edges of one type.
func (b bead) edgesOf(typ string) []string {
	var out []string
	for _, e := range b.Dependencies {
		if e.Type == typ && e.DependsOnID != "" && !slices.Contains(out, e.DependsOnID) {
			out = append(out, e.DependsOnID)
		}
	}
	return out
}

// HoldsReader reads one snapshot of what holds each bead named in the store:
// the answer for each bead it could answer, and the error for each it could
// not. A read that fails returns its error.
type HoldsReader func(ctx context.Context, store string, ids []string) (map[string]waits.Holds, map[string]error, error)

// ReadHolds is the production HoldsReader: one snapshot through the waits
// package. The snapshot takes no context, so a gather that runs out leaves it
// to finish on its own.
func ReadHolds(ctx context.Context, store string, ids []string) (map[string]waits.Holds, map[string]error, error) {
	type answer struct {
		holds  map[string]waits.Holds
		failed map[string]error
		err    error
	}
	ch := make(chan answer, 1)
	go func() {
		snap, err := waits.ReadStore(store, ids...)
		if err != nil {
			ch <- answer{err: err}
			return
		}
		a := answer{holds: map[string]waits.Holds{}, failed: map[string]error{}}
		for _, id := range ids {
			h, err := snap.Holds(id)
			if err != nil {
				a.failed[id] = err
				continue
			}
			a.holds[id] = h
		}
		ch <- a
	}()
	select {
	case a := <-ch:
		return a.holds, a.failed, a.err
	case <-ctx.Done():
		return nil, nil, ctx.Err()
	}
}

// gathered is everything one gather read: the beads, and each reader's
// answers about them. build turns it into the document and reads nothing more.
type gathered struct {
	rig string
	// open is every bead the store lists by default and every gate, closed
	// beads aside. closed is the closed members of each open epic and
	// Delivery, and of each closed epic beneath one (readClosedMembers). far
	// is every other bead the walk of blocks edges read.
	open   []bead
	closed []bead
	far    map[string]bead
	// holds is waits' answer for each open row, and unread the error for each
	// it could not answer.
	holds  map[string]waits.Holds
	unread map[string]error
	// holding is prstatus.Holding's answer for each root asked, and
	// unwalked the roots whose walk ran past its bound.
	holding  map[string]prstatus.Holds
	unwalked map[string]bool
	// facts is prstatus.Read's answer for each bead with an open pull
	// request, and noFacts the error for each it could not answer.
	facts   map[string]prstatus.Facts
	noFacts map[string]bool
}

// closedReadLimit bounds how many closed-member reads run at once.
const closedReadLimit = 6

// Read gathers one rig's store once and builds its document. A read that
// fails returns its error and no document, so a caller never draws a board
// from a read that did not happen.
func Read(ctx context.Context, gc GC, rig Rig, readHolds HoldsReader) (Document, error) {
	g, err := gather(ctx, gc, rig, readHolds)
	if err != nil {
		return Document{}, err
	}
	return build(g), nil
}

func gather(ctx context.Context, gc GC, rig Rig, readHolds HoldsReader) (*gathered, error) {
	g := &gathered{rig: rig.Name, far: map[string]bead{}}
	if err := gc.JSON(ctx, &g.open, "bd", "--db", rig.Store, "list", "--include-gates", "--json", "--limit", "0", "--flat"); err != nil {
		return nil, fmt.Errorf("list the open beads of %s: %w", rig.Name, err)
	}
	g.open = slices.DeleteFunc(g.open, func(b bead) bool { return b.ID == "" || !b.open() })
	var err error
	if g.closed, err = readClosedMembers(ctx, gc, rig, g.open); err != nil {
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
	if g.holds, g.unread, err = readHolds(ctx, rig.Store, ids); err != nil {
		return nil, fmt.Errorf("read what holds the beads of %s: %w", rig.Name, err)
	}

	st := &store{gc: gc, rig: rig, known: byID, far: g.far, ctx: ctx}
	roots := holdingRoots(ids, g.holds)
	holding, err := prstatus.Holding(roots, st.Blockers)
	g.unwalked = map[string]bool{}
	if err != nil {
		if !errors.Is(err, prstatus.ErrWalkBound) {
			return nil, fmt.Errorf("read what %s owes a person: %w", rig.Name, err)
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
	facts, err := prstatus.Read(anchors, st)
	g.noFacts = map[string]bool{}
	if err != nil {
		if !errors.Is(err, prstatus.ErrWalkBound) && !errors.Is(err, prstatus.ErrUnresolved) {
			return nil, fmt.Errorf("read the pull requests of %s: %w", rig.Name, err)
		}
		for _, a := range anchors {
			if _, ok := facts[a]; !ok {
				g.noFacts[a] = true
			}
		}
	}
	g.facts = facts
	return g, nil
}

// readClosedMembers reads the closed members of each open epic and Delivery,
// then the closed members of each closed epic among them, such as a Delivery
// that landed while its epic stays open, and so on until a round reads no
// closed epic it had not read. Closed work beneath a bead that is not an epic
// stays unread, since reading it would take one call per parent.
func readClosedMembers(ctx context.Context, gc GC, rig Rig, open []bead) ([]bead, error) {
	var parents []string
	for _, b := range open {
		if b.issueType() == "epic" {
			parents = append(parents, b.ID)
		}
	}
	asked := map[string]bool{}
	seen := map[string]bool{}
	var out []bead
	for len(parents) > 0 {
		for _, p := range parents {
			asked[p] = true
		}
		rows, err := readClosedChildren(ctx, gc, rig, parents)
		if err != nil {
			return nil, err
		}
		var next []string
		for _, r := range rows {
			if seen[r.ID] {
				continue
			}
			seen[r.ID] = true
			out = append(out, r)
			if r.issueType() == "epic" && !asked[r.ID] {
				next = append(next, r.ID)
			}
		}
		parents = next
	}
	return out, nil
}

// readClosedChildren reads the closed children of each parent, at most
// closedReadLimit reads at once, in the parents' order. The store's --parent
// filter also returns a bead whose parent-child edge has moved elsewhere, so a
// child is a bead whose own edge names the parent. A read that fails fails the
// whole read.
func readClosedChildren(ctx context.Context, gc GC, rig Rig, parents []string) ([]bead, error) {
	parents = slices.Sorted(slices.Values(parents))
	results := make([][]bead, len(parents))
	errs := make([]error, len(parents))
	sem := make(chan struct{}, closedReadLimit)
	var wg sync.WaitGroup
	for i, p := range parents {
		wg.Add(1)
		go func() {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			var rows []bead
			if err := gc.JSON(ctx, &rows, "bd", "--db", rig.Store, "list", "--parent", p, "--status", "closed", "--json", "--limit", "0", "--flat"); err != nil {
				errs[i] = fmt.Errorf("list the closed members of %s: %w", p, err)
				return
			}
			for _, r := range rows {
				if r.ID != "" && !r.open() && slices.Contains(r.parents(), p) {
					results[i] = append(results[i], r)
				}
			}
		}()
	}
	wg.Wait()
	if err := errors.Join(errs...); err != nil {
		return nil, err
	}
	var out []bead
	for _, rows := range results {
		out = append(out, rows...)
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
// request is open, which is what its merge_result says (lifecycle/lifecycle.toml).
func hasOpenPullRequest(b bead) bool { return b.meta("merge_result") == "pull_request" }

// store is prstatus's Store over the gathered beads. It holds no rule: each
// read answers from the beads the gather listed, and a bead it did not list is
// read through gc, once, closed beads and every type included.
type store struct {
	ctx   context.Context
	gc    GC
	rig   Rig
	known map[string]bead
	far   map[string]bead
	mu    sync.Mutex
}

// lookup returns each bead named, reading through gc the ones neither listed
// nor read before. A bead the store holds no row for is left out.
func (s *store) lookup(ids []string) (map[string]bead, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := map[string]bead{}
	var unread []string
	for _, id := range ids {
		if b, ok := s.known[id]; ok {
			out[id] = b
		} else if b, ok := s.far[id]; ok {
			out[id] = b
		} else if !slices.Contains(unread, id) {
			unread = append(unread, id)
		}
	}
	if len(unread) == 0 {
		return out, nil
	}
	var rows []bead
	if err := s.gc.JSON(s.ctx, &rows, "bd", "--db", s.rig.Store, "list", "--id", strings.Join(unread, ","),
		"--all", "--include-gates", "--include-infra", "--include-ephemeral", "--include-templates", "--json", "--limit", "0", "--flat"); err != nil {
		return nil, fmt.Errorf("read %s: %w", strings.Join(unread, " "), err)
	}
	for _, r := range rows {
		if slices.Contains(unread, r.ID) {
			s.far[r.ID] = r
			out[r.ID] = r
		}
	}
	return out, nil
}

// Beads implements prstatus.Store.
func (s *store) Beads(ids []string) (map[string]prstatus.Row, error) {
	got, err := s.lookup(ids)
	if err != nil {
		return nil, err
	}
	out := make(map[string]prstatus.Row, len(got))
	for id, b := range got {
		out[id] = prstatus.Row{ID: id, Metadata: b.metadata()}
	}
	return out, nil
}

// Anchored implements prstatus.Store over the listed beads, which hold every
// bead at a status other than closed.
func (s *store) Anchored(ids []string, statuses []string) (map[string][]prstatus.Row, error) {
	out := map[string][]prstatus.Row{}
	for _, b := range s.known {
		a := b.meta("anchor_bead")
		if a == "" || !slices.Contains(ids, a) || !slices.Contains(statuses, b.status()) {
			continue
		}
		out[a] = append(out[a], prstatus.Row{ID: b.ID, Metadata: b.metadata()})
	}
	return out, nil
}

// Blockers implements prstatus.Store and is the ReadBlockers Holding walks:
// for each bead named, the far bead of each of its blocks edges.
func (s *store) Blockers(ids []string) (map[string][]prstatus.Blocker, error) {
	beads, err := s.lookup(ids)
	if err != nil {
		return nil, err
	}
	var far []string
	for _, id := range ids {
		b, ok := beads[id]
		if !ok {
			return nil, fmt.Errorf("read %s: the store holds no such bead", id)
		}
		far = append(far, b.edgesOf("blocks")...)
	}
	farBeads, err := s.lookup(far)
	if err != nil {
		return nil, err
	}
	out := make(map[string][]prstatus.Blocker, len(ids))
	for _, id := range ids {
		out[id] = []prstatus.Blocker{}
		for _, f := range beads[id].edgesOf("blocks") {
			fb, ok := farBeads[f]
			if !ok {
				// An edge onto a bead this store does not hold is an edge into
				// another store, which holds nothing.
				continue
			}
			out[id] = append(out[id], prstatus.Blocker{ID: fb.ID, Title: fb.Title, Status: fb.Status,
				IssueType: fb.IssueType, AwaitType: fb.AwaitType, Assignee: fb.Assignee, Metadata: fb.metadata()})
		}
	}
	return out, nil
}
