package gcbd

import (
	"bytes"
	"encoding/json"
	"fmt"
)

// SetState sets one state dimension of bead id through `gc bd set-state <id>
// <dimension>=<value> --reason <reason>`: bd records the change in an event bead
// and makes <dimension>:<value> the bead's one label for that dimension, in one
// write. An error is a write that did not land.
func (c *Client) SetState(id, dimension, value, reason string) error {
	args := []string{"bd", "set-state", id, dimension + "=" + value}
	if reason != "" {
		args = append(args, "--reason", reason)
	}
	return c.write(args...)
}

// AddEdge gives bead id an edge of type typ onto far through `gc bd dep add
// <id> <far> --type <typ>`. bd keeps one edge type per pair of beads, so it
// refuses an edge onto a bead id already has an edge of another type onto. An
// error is a write that did not land.
func (c *Client) AddEdge(id, far, typ string) error {
	return c.write("bd", "dep", "add", id, far, "--type", typ)
}

// write runs one write and says, when it exits non-zero, what it printed.
func (c *Client) write(args ...string) error {
	var stderr bytes.Buffer
	cmd := c.command(args...)
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return fmt.Errorf("gc %s %s exited %d: %s", args[0], args[1], ExitCode(err), failure(out, stderr.String()))
	}
	return nil
}

// ReadyIDs reads the id of every bead the store reports ready, through bd's
// brief ready set (`gc bd ready --brief --json --limit 0`), which leaves each
// row's free-form text out. It answers whether one bead is ready, which no
// ready read of one bead can: bd refuses --ready with --id. A non-zero exit, a
// reply that is not one JSON array, and a row with no id each fail the read with
// a *ReadError.
func (c *Client) ReadyIDs() ([]string, error) {
	raw, err := c.strictArray("bd", "ready", "--brief", "--json", "--limit", "0")
	if err != nil {
		return nil, err
	}
	var rows []struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(raw, &rows); err != nil {
		return nil, &ReadError{Reason: "gc bd ready's brief rows did not decode: " + err.Error()}
	}
	ids := make([]string, 0, len(rows))
	for _, r := range rows {
		if r.ID == "" {
			return nil, &ReadError{Reason: "gc bd ready returned a brief row with no id"}
		}
		ids = append(ids, r.ID)
	}
	return ids, nil
}
