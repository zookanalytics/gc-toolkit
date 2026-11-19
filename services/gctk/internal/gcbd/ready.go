package gcbd

import (
	"bytes"
	"encoding/json"
)

// ReadyQuery is one `gc bd ready` read: the beads that carry a metadata key, or
// with Every every bead, that bd reports ready, under a pool's serve rule.
// bd's readiness is its own: an open bead no wait of its own or of an ancestor
// holds, and no future defer_until. The rule's filters are the flags Gas City
// renders for a pool's routed demand (PoolDemandServeRulesForQuery in its
// internal/config/workquery.go): unassigned beads only, the issue types it
// leaves out, and the labels it leaves out, each compared exactly. ByPriority
// orders the rows highest priority first, by bd's priority sort.
type ReadyQuery struct {
	HasKey        string
	Every         bool
	Unassigned    bool
	ExcludeTypes  []string
	ExcludeLabels []string
	ByPriority    bool
}

// args is the ready read's arguments.
func (q ReadyQuery) args() []string {
	args := []string{"bd", "ready"}
	if q.HasKey != "" {
		args = append(args, "--has-metadata-key", q.HasKey)
	}
	if q.Unassigned {
		args = append(args, "--unassigned")
	}
	for _, t := range q.ExcludeTypes {
		args = append(args, "--exclude-type="+t)
	}
	for _, l := range q.ExcludeLabels {
		args = append(args, "--exclude-label", l)
	}
	if q.ByPriority {
		args = append(args, "--sort", "priority")
	}
	return append(args, "--json", "--limit", "0")
}

// Ready reads the beads q selects that bd reports ready, through `gc bd ready`,
// under Blocked's strict contract: a non-zero exit, or a reply that is not one
// JSON array, fails the read with a *ReadError. Its rows are the listing's, each
// edge naming its far bead's id and type alone. A query that names neither a
// key nor every bead is refused before any read, since bd's ready read takes
// no ids, and so is one that names both.
func (c *Client) Ready(q ReadyQuery) ([]Bead, error) {
	switch {
	case q.HasKey == "" && !q.Every:
		return nil, &ReadError{Reason: "a ready read selects the beads that carry a key, or every bead, and names neither"}
	case q.HasKey != "" && q.Every:
		return nil, &ReadError{Reason: "a ready read selects the beads that carry a key, or every bead, and names both"}
	}
	raw, err := c.strictArray(q.args()...)
	if err != nil {
		return nil, err
	}
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	var rows []Bead
	if err := dec.Decode(&rows); err != nil {
		return nil, &ReadError{Reason: "gc bd ready's rows did not decode: " + err.Error()}
	}
	for i := range rows {
		if rows[i].ID == "" {
			return nil, &ReadError{Reason: "gc bd ready returned a row with no id"}
		}
	}
	return rows, nil
}
