package gcbd

import (
	"bytes"
	"encoding/json"
	"slices"
	"strings"
)

// Query is one `gc bd list` read: the beads it names, the beads that carry a
// metadata key, the beads whose key holds one value, the beads the store lists
// under a parent, the beads whose title holds a text, the beads of one issue
// type, the beads assigned to one assignee, the beads in the statuses named,
// or, with Every, every bead, and each field set narrows the others. It reads
// every bead the query selects, wisps, gates, infrastructure beads and template
// molecules among them, since a listing hides each of those unless asked, and
// with Listed it reads only the beads the listing shows when asked for nothing
// more. It reads live beads alone unless Closed is set. The store's --parent
// filter can return a bead whose own parent-child edge names another parent, so
// a reader keeps a child by its own edge.
type Query struct {
	IDs           []string
	HasKey        string
	Key           string
	Value         string
	Parent        string
	TitleContains string
	Type          string
	Assignee      string
	Statuses      []string
	Every         bool
	Listed        bool
	Closed        bool
}

// selects reports whether q names what it reads: ids, a key, a parent, a title's
// text, an issue type, an assignee, statuses, or every bead.
func (q Query) selects() bool {
	return len(q.IDs) > 0 || q.HasKey != "" || q.Key != "" || q.Parent != "" || q.TitleContains != "" || q.Type != "" ||
		q.Assignee != "" || len(q.Statuses) > 0 || q.Every
}

// idBatch is how many ids one list read names, so a read of many beads never
// builds an argument the store refuses.
const idBatch = 200

// args is the list's arguments, less the ids.
func (q Query) args() []string {
	var args []string
	if !q.Listed {
		args = append(args, "--include-ephemeral", "--include-gates", "--include-infra", "--include-templates")
	}
	args = append(args, "--json", "--limit", "0")
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
	if q.Type != "" {
		args = append(args, "--type", q.Type)
	}
	if q.Assignee != "" {
		args = append(args, "--assignee", q.Assignee)
	}
	if len(q.Statuses) > 0 {
		// bd keeps only the last of repeated --status flags, so the statuses
		// go in one, comma-separated.
		args = append(args, "--status", strings.Join(q.Statuses, ","))
	}
	return args
}

// Find reads the beads q selects through `gc bd list`, under Blocked's strict
// contract: a non-zero exit, or a reply that is not one JSON array, fails the
// read with a *ReadError. The ids q names are read in batches of idBatch, and a
// query that selects nothing is refused before any read.
func (c *Client) Find(q Query) ([]Bead, error) {
	if !q.selects() {
		return nil, &ReadError{Reason: "a find selects no beads: name ids, a key, a key and its value, a parent, a title's text, an issue type, an assignee, statuses, or every bead"}
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
