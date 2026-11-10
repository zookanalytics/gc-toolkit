// Package fixture holds the scenarios each reader of prstatus is tested
// against, and an in-memory [prstatus.Store] that serves a scenario's beads. A
// reader's test renders a scenario into the reads its own adapter makes, asks
// the reader, and compares the answer with what [prstatus.Read] gathers from the
// same beads through [Store]. The expected answer is the definition's own, so a
// change to the definition reaches every reader's test, and a reader that kept
// a rule of its own would part from it there.
package fixture

import (
	_ "embed"
	"encoding/json"
	"fmt"
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus"
)

// Bead is one bead of a scenario's store. WaitsOn names the beads its `blocks`
// edges name, the beads it waits on, and Tracks the beads its `tracks` edges
// name, as a conversation tracks its subject.
type Bead struct {
	ID        string            `json:"id"`
	Title     string            `json:"title,omitempty"`
	Status    string            `json:"status"`
	IssueType string            `json:"issue_type,omitempty"`
	AwaitType string            `json:"await_type,omitempty"`
	Assignee  string            `json:"assignee,omitempty"`
	Metadata  map[string]string `json:"metadata,omitempty"`
	WaitsOn   []string          `json:"waits_on,omitempty"`
	Tracks    []string          `json:"tracks,omitempty"`
}

// Scenario is a store of beads and the anchor whose PR a reader is asked about.
// Want pins the status and held values the definition gives the anchor. Only
// prstatus's own test reads it, to pin the rule; a reader's test compares with
// [Scenario.Answer], which the definition computes.
type Scenario struct {
	Name   string `json:"name"`
	Anchor string `json:"anchor"`
	Want   struct {
		Status string   `json:"status"`
		Held   []string `json:"held"`
	} `json:"want"`
	Beads []Bead `json:"beads"`
}

// Bead returns the scenario's bead with that id, and whether it has one.
func (sc Scenario) Bead(id string) (Bead, bool) {
	i := slices.IndexFunc(sc.Beads, func(b Bead) bool { return b.ID == id })
	if i < 0 {
		return Bead{}, false
	}
	return sc.Beads[i], true
}

//go:embed scenarios.json
var scenarios []byte

// Scenarios returns every scenario, in the order scenarios.json lists them.
func Scenarios() ([]Scenario, error) {
	var out []Scenario
	if err := json.Unmarshal(scenarios, &out); err != nil {
		return nil, fmt.Errorf("scenarios.json: %w", err)
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("scenarios.json holds no scenario")
	}
	return out, nil
}

// Store serves a scenario's beads as a [prstatus.Store]. It answers as the bead
// store does: a row for each bead it holds, the beads naming an anchor in
// anchor_bead at the statuses asked for, and each `blocks` edge's far bead. An
// edge onto a bead it does not hold is left out, as bd leaves out an edge onto
// another store's bead. Asking for the edges of a bead it does not hold is an
// error, because no row answered for it.
type Store struct {
	beads map[string]Bead
	order []string
}

// NewStore serves beads.
func NewStore(beads []Bead) *Store {
	s := &Store{beads: make(map[string]Bead, len(beads))}
	for _, b := range beads {
		s.beads[b.ID] = b
		s.order = append(s.order, b.ID)
	}
	return s
}

// Beads returns the row of each id the store holds.
func (s *Store) Beads(ids []string) (map[string]prstatus.Row, error) {
	out := make(map[string]prstatus.Row, len(ids))
	for _, id := range ids {
		if b, ok := s.beads[id]; ok {
			out[id] = prstatus.Row{ID: b.ID, Metadata: b.Metadata}
		}
	}
	return out, nil
}

// Anchored returns, for each id, the beads whose anchor_bead names it, at any of
// statuses, in the store's order.
func (s *Store) Anchored(ids []string, statuses []string) (map[string][]prstatus.Row, error) {
	out := make(map[string][]prstatus.Row, len(ids))
	for _, id := range ids {
		for _, k := range s.order {
			b := s.beads[k]
			if b.Metadata["anchor_bead"] == id && slices.ContainsFunc(statuses, func(st string) bool { return strings.EqualFold(st, b.Status) }) {
				out[id] = append(out[id], prstatus.Row{ID: b.ID, Metadata: b.Metadata})
			}
		}
	}
	return out, nil
}

// Blockers returns, for each id, the far bead of each of its `blocks` edges.
func (s *Store) Blockers(ids []string) (map[string][]prstatus.Blocker, error) {
	out := make(map[string][]prstatus.Blocker, len(ids))
	for _, id := range ids {
		b, ok := s.beads[id]
		if !ok {
			return nil, fmt.Errorf("no row for %s", id)
		}
		out[id] = nil
		for _, w := range b.WaitsOn {
			if far, ok := s.beads[w]; ok {
				out[id] = append(out[id], BlockerOf(far))
			}
		}
	}
	return out, nil
}

// BlockerOf is a bead as the far end of a `blocks` edge.
func BlockerOf(b Bead) prstatus.Blocker {
	return prstatus.Blocker{
		ID:        b.ID,
		Title:     b.Title,
		Status:    b.Status,
		IssueType: b.IssueType,
		AwaitType: b.AwaitType,
		Assignee:  b.Assignee,
		Metadata:  b.Metadata,
	}
}

// Answer is what the definition gathers and decides for a scenario's anchor: the
// facts [prstatus.Read] gathers through [Store], and the status, held values and
// reasons the definition gives for them. It is what every reader must answer.
type Answer struct {
	Facts   prstatus.Facts
	Status  prstatus.State
	Held    []prstatus.Hold
	Reasons []prstatus.Reason
}

// Answer is the definition's [Answer] for the scenario's anchor.
func (sc Scenario) Answer() (Answer, error) {
	facts, err := prstatus.Read([]string{sc.Anchor}, NewStore(sc.Beads))
	if err != nil {
		return Answer{}, err
	}
	f, ok := facts[sc.Anchor]
	if !ok {
		return Answer{}, fmt.Errorf("%s: no answer for %s", sc.Name, sc.Anchor)
	}
	return Answer{Facts: f, Status: prstatus.Derive(f), Held: prstatus.Held(f), Reasons: prstatus.Reasons(f)}, nil
}
