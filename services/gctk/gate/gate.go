// Package gate is the pack's gate types: bd gates the city closes itself, which
// no person answers (specs/tk-ai367om/design.md, section 2). It defines one,
// gctk:needs-review, a staying conversation's gate: its await id is the one
// piece of work the stay is for, and it blocks the conversation. The landing
// order resolves it once that work's PR reads needs-review or merging in its
// own right, or once the work closes, and the conversation is then ready work,
// which Gas City wakes its sitting for.
//
// The package holds the type, the rule that the city closes a gate of it, the
// gate's filing behind the checks `gctk gate create` makes, and the form of
// its resolve. The verb files the gate and the landing order resolves it, and
// nothing else writes it. It sits outside internal/, as waits and prstatus
// do, so a board can import it.
package gate

import (
	"errors"
	"fmt"
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/conversation"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// NeedsReview is the type of a stay's gate: it resolves once the PR of its
// await id's bead reads needs-review or merging in its own right, or once that
// bead closes. The gctk: prefix keeps it clear of bd's gh: types, which bd's
// checker and Gas City's sweep select by prefix.
const NeedsReview = "gctk:needs-review"

// Types are the gate types the pack defines.
var Types = []string{NeedsReview}

// CityCloses reports whether the city closes a bead of issueType and
// awaitType: a gate of a type the pack defines, which the pack's own closer
// resolves and no person answers. bd's own check and Gas City's sweep pass
// such a gate over, so a reader that would take any gate that is no human gate
// for a park asks this first.
func CityCloses(issueType, awaitType string) bool {
	return strings.EqualFold(strings.TrimSpace(issueType), "gate") && slices.Contains(Types, strings.TrimSpace(awaitType))
}

// Title is the title of the gate on work: the work and the condition that
// resolves the gate, in the operator's words.
func Title(work string) string {
	return fmt.Sprintf("Back when %s's PR needs your review, or once %s closes", work, work)
}

// ResolvedAt is a resolve's reason when the PR of work read status in its own
// right at head.
func ResolvedAt(work, status, head string) string {
	return fmt.Sprintf("%s's PR reads %s in its own right at %s", work, status, head)
}

// ResolvedClosed is a resolve's reason when work has closed.
func ResolvedClosed(work string) string { return work + " closed" }

// Gate is one open gate of a type the pack defines: its id, its type and the
// bead its await id names.
type Gate struct{ ID, Type, Work string }

// Open returns the open gates of the types the pack defines among rows, in
// their order.
func Open(rows []*ledger.Record) []Gate {
	var out []Gate
	for _, r := range rows {
		if r.Status() != "closed" && CityCloses(r.IssueType(), r.AwaitType()) {
			out = append(out, Gate{ID: r.ID, Type: strings.TrimSpace(r.AwaitType()), Work: strings.TrimSpace(r.AwaitID())})
		}
	}
	return out
}

// Promises files a stay's gate over one store, the conversation's.
type Promises struct {
	Ledger *ledger.Ledger
	// InRig reports whether a rig's store holds a bead, and not the city's own:
	// ok is false when no store's prefix begins its id.
	InRig func(id string) (rig, ok bool, err error)
	// Self is each name the caller goes by, such as its alias: a conversation
	// is promised only by the sitting it is assigned to.
	Self []string
}

// Request is one promise: the gate's type, the bead its await id names, the
// work, and the bead it blocks, the conversation.
type Request struct{ Type, Work, Conversation string }

// Filed is what a promise did: the gate that holds the conversation for the
// work, and whether it found that gate open already and filed none.
type Filed struct {
	Gate  string
	Found bool
}

// Refusal is a promise refused before anything was written.
type Refusal struct{ Msg string }

func (e *Refusal) Error() string { return e.Msg }

func refuse(format string, args ...any) error { return &Refusal{Msg: fmt.Sprintf(format, args...)} }

// Refused reports whether err is a promise refused before anything was
// written, rather than a read or a write that failed.
func Refused(err error) bool {
	var r *Refusal
	return errors.As(err, &r)
}

// walkDepth is how many levels of waits the stall check walks, the depth bd's
// dep tree stops at.
const walkDepth = 50

// Create files the gate of req.Type on req.Work that blocks req.Conversation,
// with one `bd gate create`, or finds the open one the conversation already
// waits on for that work. It refuses, writing nothing:
//
//   - a type the package does not define;
//   - a conversation that is not open or in progress under the caller's alias,
//     since the sitting runs it while it holds the conversation;
//   - work in another store than the conversation's, and work that has closed;
//   - work in the city's own store, which the landing order does not read;
//   - a conversation that waits on an open gate of this type for other work;
//   - work that waits on the conversation through another bead, which could
//     not move until something the conversation holds has landed: the stall
//     check walks the work's blocks, conditional-blocks and parent-child edges
//     in the conversation's store, at any status, past the work's own hold on
//     the conversation, as bd's cycle check would.
func (p *Promises) Create(req Request) (Filed, error) {
	if err := Validate(req); err != nil {
		return Filed{}, err
	}
	work, conv := strings.TrimSpace(req.Work), strings.TrimSpace(req.Conversation)
	rows, err := p.Ledger.Find(ledger.ByID(conv, work).WithClosed())
	if err != nil {
		return Filed{}, fmt.Errorf("%s and %s did not read: %w", conv, work, err)
	}
	c, w := byID(rows, conv), byID(rows, work)
	switch {
	case c == nil:
		return Filed{}, refuse("the store holds no %s", conv)
	case w == nil:
		return Filed{}, refuse("%s's store holds no %s", conv, work)
	}
	if err := p.holds(c); err != nil {
		return Filed{}, err
	}
	if w.Status() == "closed" {
		return Filed{}, refuse("%s has closed, so it has nothing left to bring %s back for", work, conv)
	}
	rig, ok, err := p.InRig(work)
	switch {
	case err != nil:
		return Filed{}, fmt.Errorf("the store that holds %s did not read: %w", work, err)
	case !ok:
		return Filed{}, refuse("no store the city's config names holds %s", work)
	case !rig:
		return Filed{}, refuse("%s is in the city's own store, which the landing order does not read, so nothing would resolve its gate; "+
			"stay as today, waiting on the work through an edge", work)
	}
	open, err := p.waitsOn(c)
	if err != nil {
		return Filed{}, err
	}
	for _, g := range open {
		if g.Type == req.Type && g.Work == work {
			return Filed{Gate: g.ID, Found: true}, nil
		}
	}
	for _, g := range open {
		if g.Type == req.Type {
			return Filed{}, refuse("%s already waits on the open gate %s for %s; it waits for one piece at a time, so promise %s once %s is back",
				conv, g.ID, g.Work, work, g.Work)
		}
	}
	if via, err := p.stalled(work, conv); err != nil {
		return Filed{}, err
	} else if via != "" {
		return Filed{}, refuse("%s waits on %s through %s, so it cannot move until something %s holds has landed; "+
			"settle that first, then promise %s", work, conv, via, conv, work)
	}
	id, err := p.Ledger.CreateGate(req.Type, work, conv, Title(work))
	if err != nil {
		return Filed{}, err
	}
	return Filed{Gate: id}, nil
}

// Validate refuses a promise no read of the store is needed to refuse: a type
// the package does not define, a missing bead, a conversation named as its own
// work, and work in another store than the conversation's.
func Validate(req Request) error {
	work, conv := strings.TrimSpace(req.Work), strings.TrimSpace(req.Conversation)
	switch {
	case !slices.Contains(Types, strings.TrimSpace(req.Type)):
		return refuse("%q is no gate type the pack defines; the types are %s", req.Type, strings.Join(Types, ", "))
	case work == "" || conv == "":
		return refuse("the gate needs the work's bead (--await-id) and the conversation's (--blocks)")
	case work == conv:
		return refuse("%s cannot wait on a gate for itself", conv)
	case prefixOf(work) != prefixOf(conv):
		return refuse("%s is in another store than %s, and a gate holds a conversation only on work in its own store", work, conv)
	}
	return nil
}

// holds refuses a conversation that is not open or in progress under one of
// the caller's names.
func (p *Promises) holds(c *ledger.Record) error {
	st, who := c.Status(), strings.TrimSpace(c.Assignee())
	if st != "open" && st != "in_progress" {
		return refuse("%s is %s, and a gate holds only a conversation that is open or in progress", c.ID, st)
	}
	if !conversation.IsCandidate(c.IssueType(), who, c.ID) || who == "human" {
		return refuse("%s is no conversation a sitting holds (assignee %q)", c.ID, who)
	}
	for _, self := range p.Self {
		if self = strings.TrimSpace(self); self != "" && (who == self || strings.HasSuffix(who, "/"+self) || strings.HasSuffix(who, "."+self)) {
			return nil
		}
	}
	return refuse("%s is assigned to %s, not to the caller, and only the sitting that holds it promises work for it", c.ID, who)
}

// waitsOn is the open gates of the pack's types that conversation c waits on
// through its own blocks edges.
func (p *Promises) waitsOn(c *ledger.Record) ([]Gate, error) {
	edges, err := c.Edges()
	if err != nil {
		return nil, fmt.Errorf("%s's waits did not read: %w", c.ID, err)
	}
	var ids []string
	for _, e := range edges {
		if e.Type == ledger.EdgeBlocks && !slices.Contains(ids, e.ID) {
			ids = append(ids, e.ID)
		}
	}
	if len(ids) == 0 {
		return nil, nil
	}
	rows, err := p.Ledger.Find(ledger.ByID(ids...).WithClosed())
	if err != nil {
		return nil, fmt.Errorf("what %s waits on did not read: %w", c.ID, err)
	}
	return Open(rows), nil
}

// stalled walks work's waits towards conv, level by level, along the edges
// bd's cycle check walks, within conv's store and at any status, and returns
// the bead whose edge reaches conv, or "" when none does. The work's own edge
// onto conv, its hold, is no stall, and the walk does not go on through conv.
func (p *Promises) stalled(work, conv string) (string, error) {
	frontier, seen := []string{work}, map[string]bool{work: true, conv: true}
	for level := 1; len(frontier) > 0; level++ {
		if level > walkDepth {
			return "", fmt.Errorf("the walk of %s's waits went past %d levels without reaching an end", work, walkDepth)
		}
		rows, err := p.Ledger.Find(ledger.ByID(frontier...).WithClosed())
		if err != nil {
			return "", fmt.Errorf("%s's waits did not read: %w", work, err)
		}
		var next []string
		for _, r := range rows {
			edges, err := r.Edges()
			if err != nil {
				return "", fmt.Errorf("%s's waits did not read: %w", r.ID, err)
			}
			for _, e := range edges {
				if !scheduling(e.Type) || prefixOf(e.ID) != prefixOf(conv) {
					continue
				}
				if e.ID == conv {
					if r.ID != work {
						return r.ID, nil
					}
					continue
				}
				if !seen[e.ID] {
					seen[e.ID] = true
					next = append(next, e.ID)
				}
			}
		}
		frontier = next
	}
	return "", nil
}

// scheduling reports whether an edge of type typ is one bd's cycle check
// walks: blocks, conditional-blocks and parent-child.
func scheduling(typ string) bool {
	return typ == ledger.EdgeBlocks || typ == ledger.EdgeConditionalBlocks || typ == ledger.EdgeParentChild
}

func byID(rows []*ledger.Record, id string) *ledger.Record {
	for _, r := range rows {
		if r.ID == id {
			return r
		}
	}
	return nil
}

// prefixOf is the part of id bd tells its store by: up to its first dash, the
// dash included, or "" for an id with none.
func prefixOf(id string) string {
	if i := strings.Index(id, "-"); i >= 0 {
		return id[:i+1]
	}
	return ""
}
