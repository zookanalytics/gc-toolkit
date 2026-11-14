package gcbd

import (
	"bytes"
	"encoding/json"
	"slices"
	"strings"
)

// Query is one `gc bd list` read: the beads it names, the beads that carry a
// metadata key, the beads whose key holds one value, the beads the store lists
// under a parent, the beads whose title holds a text, or, with Every, every
// bead. It reads every bead the query selects, wisps, gates, infrastructure
// beads and template molecules among them, since a listing hides each of those
// unless asked, and live beads alone unless Closed is set. The store's
// --parent filter can return a bead whose own parent-child edge names another
// parent, so a reader keeps a child by its own edge.
type Query struct {
	IDs           []string
	HasKey        string
	Key           string
	Value         string
	Parent        string
	TitleContains string
	Every         bool
	Closed        bool
}

// selects reports whether q names what it reads: ids, a key, a parent, a title's
// text, or every bead.
func (q Query) selects() bool {
	return len(q.IDs) > 0 || q.HasKey != "" || q.Key != "" || q.Parent != "" || q.TitleContains != "" || q.Every
}

// idBatch is how many ids one list read names, so a read of many beads never
// builds an argument the store refuses.
const idBatch = 200

// args is the list's arguments, less the ids.
func (q Query) args() []string {
	args := []string{"--include-ephemeral", "--include-gates", "--include-infra", "--include-templates", "--json", "--limit", "0"}
	if q.Closed {
		args = append(args, "--all")
	}
	if q.HasKey != "" {
		args = append(args, "--has-metadata-key", q.HasKey)
	}
	if q.Key != "" {
		args = append(args, "--metadata-field", q.Key+"="+q.Value)
	}
	if q.Parent != "" {
		args = append(args, "--parent", q.Parent)
	}
	if q.TitleContains != "" {
		args = append(args, "--title-contains", q.TitleContains)
	}
	return args
}

// Find reads the beads q selects through `gc bd list`, under Blocked's strict
// contract: a non-zero exit, or a reply that is not one JSON array, fails the
// read with a *ReadError. The ids q names are read in batches of idBatch, and a
// query that selects nothing is refused before any read.
func (c *Client) Find(q Query) ([]Bead, error) {
	if !q.selects() {
		return nil, &ReadError{Reason: "a find selects no beads: name ids, a key, a key and its value, a parent, a title's text, or every bead"}
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
