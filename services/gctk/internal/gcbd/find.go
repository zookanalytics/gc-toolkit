package gcbd

import (
	"bytes"
	"encoding/json"
	"slices"
	"strings"
)

// Query is one `gc bd list` read: the beads it names, the beads that carry a
// metadata key, or the beads whose key holds one value. It reads wisps as well
// as issues, and live beads alone unless Closed is set.
type Query struct {
	IDs    []string
	HasKey string
	Key    string
	Value  string
	Closed bool
}

// idBatch is how many ids one list read names, so a read of many beads never
// builds an argument the store refuses.
const idBatch = 200

// args is the list's arguments, less the ids.
func (q Query) args() []string {
	args := []string{"--include-ephemeral", "--json", "--limit", "0"}
	if q.Closed {
		args = append(args, "--all")
	}
	if q.HasKey != "" {
		args = append(args, "--has-metadata-key", q.HasKey)
	}
	if q.Key != "" {
		args = append(args, "--metadata-field", q.Key+"="+q.Value)
	}
	return args
}

// Find reads the beads q selects through `gc bd list`, under Blocked's strict
// contract: a non-zero exit, or a reply that is not one JSON array, fails the
// read with a *ReadError. The ids q names are read in batches of idBatch, and a
// query that selects nothing is refused before any read.
func (c *Client) Find(q Query) ([]Bead, error) {
	if len(q.IDs) == 0 && q.HasKey == "" && q.Key == "" {
		return nil, &ReadError{Reason: "a find selects no beads: name ids, a key, or a key and its value"}
	}
	if len(q.IDs) == 0 {
		return c.findOnce(q.args())
	}
	ids := slices.Compact(slices.Sorted(slices.Values(q.IDs)))
	var out []Bead
	for batch := range slices.Chunk(ids, idBatch) {
		rows, err := c.findOnce(append([]string{"--id", strings.Join(batch, ",")}, q.args()...))
		if err != nil {
			return nil, err
		}
		out = append(out, rows...)
	}
	return out, nil
}

func (c *Client) findOnce(args []string) ([]Bead, error) {
	raw, err := c.strictArray(append([]string{"bd", "list"}, args...)...)
	if err != nil {
		return nil, err
	}
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	var rows []Bead
	if err := dec.Decode(&rows); err != nil {
		return nil, &ReadError{Reason: "gc bd list's rows did not decode: " + err.Error()}
	}
	for i := range rows {
		if rows[i].ID == "" {
			return nil, &ReadError{Reason: "gc bd list returned a row with no id"}
		}
	}
	return rows, nil
}
