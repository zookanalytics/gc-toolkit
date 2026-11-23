// Package rigboard reads one rig's store once and builds the rig's board: one
// document holding every row the pages draw and the four pages as lists of
// those rows. The read is a gctk listing (services/gctk/listing), which lists
// the store once, and services/gctk/standing answers over the listing where
// each row's bead stands and whose move it is, from the shared readers'
// answers it gathers: services/gctk/waits for what holds a bead and whether it
// is in flight, services/gctk/pr/prstatus for what a person owes on a bead and
// where a pull request stands, and services/gctk/queue for the order the rig's
// work is expected to land in. services/gctk/conversation says what a
// conversation is. Where a pull request on Gas Town's pending record stands is
// the pr domain's evaluator's answer, which the listing asks over the same
// rows, with the read the one-PR update saved on the PR's bead
// (listing.PRAnswers), rendered through prstatus as `gctk pr status` renders
// it. The board keeps its words for those answers (table.go), its pages, its
// counts and its views, and holds no rule of its own about what holds a bead,
// whose move it is or whether work is moving.
//
// The listing decodes each key the board shows, so the board spells no key,
// and the document depends on the store's answers alone, so it can be cached
// whole per rig and dropped when a write lands.
package rigboard

import (
	"context"
	"fmt"
	"path/filepath"
	"slices"
	"sort"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/listing"
	"github.com/zookanalytics/gc-toolkit/services/gctk/standing"
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

// gathered is everything one gather read: the beads, and standing's reading of
// them. build turns it into the document and reads nothing more.
type gathered struct {
	rig string
	// open is every live bead the listing read. closed is the closed members
	// of each open epic and Delivery, and of each closed epic beneath one
	// (readClosedMembers).
	open   []bead
	closed []bead
	// reading is standing's answer for every row, and the readers' answers it
	// drew on, which the pages reuse.
	reading *standing.Reading
	// handedBack is every bead that records a hand-back, closed or live, read
	// only while an open decision is a row, since only a decision's Details
	// shows one.
	handedBack []bead
}

// Read reads one rig's store once, through a gctk listing, and builds its
// document. A read that fails returns its error and no document, so a caller
// never draws a board from a read that did not happen. Every store call the
// read makes ends when ctx does, the processes it started killed with it, so a
// read that runs out has stopped them all when it returns.
func Read(ctx context.Context, rig Rig) (Document, error) {
	ls, err := listing.Read(ctx, rig.Store)
	if err != nil {
		return Document{}, fmt.Errorf("list the beads of %s: %w", rig.Name, err)
	}
	g, err := gather(ls, rig.Name)
	if err != nil {
		return Document{}, err
	}
	return build(g), nil
}

// gather reads the rig's beads and asks standing where each row's bead stands.
func gather(ls *listing.Listing, rig string) (*gathered, error) {
	g := &gathered{rig: rig, open: ls.Live()}
	var err error
	if g.closed, err = readClosedMembers(ls, g.open); err != nil {
		return nil, err
	}
	if g.reading, err = standing.Read(rowIDs(g), ls); err != nil {
		return nil, fmt.Errorf("read where the beads of %s stand: %w", rig, err)
	}
	if slices.ContainsFunc(g.open, func(b bead) bool { return ownRow(b) && g.reading.Kind(b.ID) == standing.KindDecision }) {
		if g.handedBack, err = ls.HandedBack(); err != nil {
			return nil, fmt.Errorf("read the hand-backs of %s: %w", rig, err)
		}
	}
	return g, nil
}

// rowIDs is every row the board draws, live and closed, by id.
func rowIDs(g *gathered) []string {
	var ids []string
	for _, list := range [][]bead{g.open, g.closed} {
		for _, b := range list {
			if ownRow(b) {
				ids = append(ids, b.ID)
			}
		}
	}
	sort.Strings(ids)
	return slices.Compact(ids)
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
