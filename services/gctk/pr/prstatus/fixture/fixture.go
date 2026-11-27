// Package fixture holds the scenarios each reader of prstatus is tested
// against, and a store that serves a scenario's beads: the store adapter's fake
// holding them, read through [prstatus.Over], the Store gctk's readers read
// through. A reader's test renders a scenario into the reads its own adapter
// makes, asks the reader, and compares the answer with what [prstatus.Read]
// gathers from the same beads through [NewStore]. The expected answer is the
// definition's own, so a change to the definition reaches every reader's test,
// and a reader that kept a rule of its own would part from it there. It sits
// at the binary layer, which may hold the store's fake where a domain may not,
// and outside internal/, so the helm board's tests can import it.
package fixture

import (
	_ "embed"
	"encoding/json"
	"fmt"
	"slices"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/prstatus"
	"github.com/zookanalytics/gc-toolkit/services/gctk/standing/person"
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

// NewStore serves beads as the bead store does, through [prstatus.Over]: a row
// for each bead it holds, the beads naming an anchor in anchor_bead, and each
// `blocks` edge's far bead. An edge onto a bead it does not hold is left out,
// as bd leaves out an edge onto another store's bead, and asking for the edges
// of a bead it does not hold is an error, because no row answered for it.
func NewStore(beads []Bead) prstatus.Store {
	s := fake.New()
	for _, b := range beads {
		row := fake.Bead{ID: b.ID, Title: b.Title, Status: b.Status, IssueType: b.IssueType, AwaitType: b.AwaitType,
			Assignee: b.Assignee, Metadata: b.Metadata}
		for _, w := range b.WaitsOn {
			row.Edges = append(row.Edges, gcbd.Edge{Type: gcbd.EdgeBlocks, ID: w})
		}
		for _, t := range b.Tracks {
			row.Edges = append(row.Edges, gcbd.Edge{Type: "tracks", ID: t})
		}
		s.Put(row)
	}
	return prstatus.Over(ledger.New(s))
}

// holder is the bead BlockerOf puts beside the bead it is given, whose one
// `blocks` edge names that bead.
const holder = "fixture-holder"

// BlockerOf is a bead as the far end of a `blocks` edge, with its record, as
// [NewStore] serves it.
func BlockerOf(b Bead) person.Blocker {
	got, err := NewStore([]Bead{b, {ID: holder, Status: "open", WaitsOn: []string{b.ID}}}).Blockers([]string{holder})
	if err != nil || len(got[holder]) != 1 {
		panic(fmt.Sprintf("fixture: the store did not serve %s as a blocker: %v", b.ID, err))
	}
	return got[holder][0]
}

// Answer is what the definition gathers and decides for a scenario's anchor: the
// facts [prstatus.Read] gathers through [NewStore], and the status, held values
// and reasons the definition gives for them. It is what every reader must
// answer.
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
