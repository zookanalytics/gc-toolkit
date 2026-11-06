package gcbd

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"math/big"
	"os/exec"
	"sort"
	"strconv"
	"strings"
)

// A write's exit status settles whether it landed, except where bd leaves a
// gap (docs/warrants.md, "bd write durability"): an ordinary write that exits 0
// under a degraded Dolt server, or beside a legacy write path, may not stay
// written. bd re-reads only a claim, or a guarded update that writes nothing
// but the status and the assignee. Verify is the read the pack makes in that
// gap, before an act that cannot be undone or run again, and it is the one
// place that read lives.
//
// A write is confirmed by its witness: what the bead must read back carrying
// for the write to count as landed. bd applies one update, one close, one
// create and one dependency edit as one atomic operation each, so one thing the
// write alone wrote, read back as written, shows that all of it landed. A
// witness names something no other actor rewrites right after the write. A
// pool's claim right after a release rewrites the status, the assignee and the
// session pins, so a witness made of those would read that claim as a lost
// write.

// Want is the witness one bead must read back carrying.
type Want struct {
	// Meta names metadata keys, each with the value it must read back holding,
	// or that it must read absent.
	Meta []MetaWant
	// Status is the status the bead must read, compared without case. Empty
	// checks none.
	Status string
	// Priority is the priority the bead must read, 0 to 4. Empty checks none.
	Priority string
	// Assignee, when set, is the assignee the bead must read, empty for none.
	Assignee *string
	// Notes are texts the bead's notes must carry.
	Notes []string
	// Edges are dependency edges from the bead that must read back, or must
	// not.
	Edges []EdgeWant
}

// MetaWant is one metadata key of a witness. With Unset the key must read
// absent. Otherwise it must read back holding Value: the text a --set-metadata
// wrote, or the JSON value a create's --metadata carried. A value compares as
// its text, jq's tostring of it, because bd stores a --set-metadata text of
// null, true, false or a number as that JSON value, and a create's metadata as
// given. A number read back is also equal to a text naming the same number,
// so 1.5 reads back as written for 1.50.
type MetaWant struct {
	Key   string
	Value any
	Unset bool
}

// EdgeWant is one dependency edge of a witness: an edge from the bead onto To,
// of Type, or of any type when Type is empty. With Absent, no edge from the
// bead onto To may read back, whatever its type. A blocks edge also needs its
// far end to read back from the same store: bd stores an edge onto a bead
// another store holds without finding it, and such an edge holds nothing
// (docs/warrants.md, "bd write durability"). Any other kind is a record, which
// the edge's own row carries.
type EdgeWant struct {
	To     string
	Type   string
	Absent bool
}

// Verify reads back every bead wants names with one `gc bd list --id`, and
// judges each one against its witness. It returns one line for each way a bead
// falls short, ordered by bead id, and nil when every bead carries its witness.
//
// scope carries the flags that chose the store the write went to (--db, --rig,
// --city, -C), so the read asks that store. The read is the authoritative
// `gc bd` path, never the supervisor's cached read, which can lag a write and
// carries no notes. It asks for every kind of row, because a plain list hides a
// gate, a wisp, a template and an infra bead even when its id is named. A list
// row carries the bead's own edges, an edge onto a bead another store holds
// among them, which `gc bd dep list` leaves out. A read that fails, or
// exits non-zero beside whatever it printed, shows nothing about any bead, so
// each bead is reported as not read back.
func (c *Client) Verify(scope []string, wants map[string]Want) []string {
	ids := make([]string, 0, len(wants))
	for id := range wants {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	if len(ids) == 0 {
		return nil
	}
	// Each blocks edge's far end is read in the same list, from the same store.
	read := append([]string{}, ids...)
	seen := map[string]bool{}
	for _, id := range ids {
		seen[id] = true
	}
	for _, id := range ids {
		for _, e := range wants[id].Edges {
			if e.Type == "blocks" && !e.Absent && !seen[e.To] {
				seen[e.To] = true
				read = append(read, e.To)
			}
		}
	}
	args := append([]string{"bd", "list", "--id", strings.Join(read, ","), "--all",
		"--include-gates", "--include-infra", "--include-templates", "--include-ephemeral",
		"--limit", "0", "--json"}, scope...)
	unread := func(why string) []string {
		out := make([]string, 0, len(ids))
		for _, id := range ids {
			out = append(out, id+" could not be read back: "+why)
		}
		return out
	}
	raw, ok := c.raw(true, args...)
	if !ok {
		return unread("gc bd list did not answer with a list")
	}
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	var rows []verifyRow
	if err := dec.Decode(&rows); err != nil {
		return unread("its rows did not decode")
	}
	byID := make(map[string]*verifyRow, len(rows))
	for i := range rows {
		byID[rows[i].ID] = &rows[i]
	}
	var misses []string
	for _, id := range ids {
		row := byID[id]
		if row == nil {
			misses = append(misses, id+" did not read back: the store returned no row for it")
			continue
		}
		misses = append(misses, row.judge(wants[id], func(far string) bool { return byID[far] != nil })...)
	}
	return misses
}

// verifyRow is one row of `gc bd list --json`, decoded far enough to judge a
// witness. Its dependencies are the bead's raw edges, each naming its far end
// as depends_on_id and its kind as type. A row in `gc bd show`'s shape names
// them id and dependency_type, and edgeEnds reads either.
type verifyRow struct {
	ID           string           `json:"id"`
	Status       *string          `json:"status"`
	Priority     any              `json:"priority"`
	Assignee     any              `json:"assignee"`
	Notes        any              `json:"notes"`
	Metadata     map[string]any   `json:"metadata"`
	Dependencies []map[string]any `json:"dependencies"`
}

// judge returns one line for each way the row falls short of w. inStore
// reports whether a bead read back from the store the row came from.
func (r *verifyRow) judge(w Want, inStore func(string) bool) []string {
	var out []string
	miss := func(format string, a ...any) {
		out = append(out, r.ID+": "+fmt.Sprintf(format, a...))
	}
	for _, m := range w.Meta {
		got, has := r.Metadata[m.Key]
		switch {
		case m.Unset:
			if has {
				miss("%s still reads %s, and the write removed it", m.Key, shown(got))
			}
		case !has:
			miss("%s reads nothing, not %s", m.Key, shown(m.Value))
		case !valueMatches(m.Value, got):
			miss("%s reads %s, not %s", m.Key, shown(got), shown(m.Value))
		}
	}
	if w.Status != "" {
		got := ""
		if r.Status != nil {
			got = *r.Status
		}
		if !strings.EqualFold(got, w.Status) {
			miss("status reads %q, not %q", got, w.Status)
		}
	}
	if w.Priority != "" {
		switch {
		case r.Priority == nil:
			miss("priority reads nothing, not %s", w.Priority)
		case !valueMatches(w.Priority, r.Priority):
			miss("priority reads %s, not %s", tostringText(r.Priority), w.Priority)
		}
	}
	if w.Assignee != nil {
		if got := jqString(r.Assignee); got != *w.Assignee {
			miss("assignee reads %q, not %q", got, *w.Assignee)
		}
	}
	notes := jqString(r.Notes)
	for _, n := range w.Notes {
		if t := strings.TrimSpace(n); t != "" && !strings.Contains(notes, t) {
			miss("its notes do not carry the text the write appended")
		}
	}
	for _, e := range w.Edges {
		found := false
		for _, d := range r.Dependencies {
			to, typ := edgeEnds(d)
			if to == e.To && (e.Absent || e.Type == "" || typ == e.Type) {
				found = true
				break
			}
		}
		switch {
		case e.Absent && found:
			miss("an edge onto %s still reads back, and the write removed it", e.To)
		case !e.Absent && !found:
			kind := e.Type
			if kind == "" {
				kind = "dependency"
			}
			miss("no %s edge onto %s reads back", kind, e.To)
		case e.Type == "blocks" && !e.Absent && !inStore(e.To):
			miss("its blocks edge onto %s reads back, but %s does not read back from this store, so the edge holds nothing", e.To, e.To)
		}
	}
	return out
}

// edgeEnds reads the far end and the kind of one dependency of a row, from a
// list row's raw edge or a show row's far bead.
func edgeEnds(d map[string]any) (to, typ string) {
	pick := func(keys ...string) string {
		for _, k := range keys {
			if s, ok := d[k].(string); ok && s != "" {
				return s
			}
		}
		return ""
	}
	return pick("depends_on_id", "id"), pick("type", "dependency_type")
}

// valueMatches reports whether got, a value read back, holds want: the same
// text, or the same number when got is one.
func valueMatches(want, got any) bool {
	w, g := tostringText(want), tostringText(got)
	if w == g {
		return true
	}
	if _, isNum := got.(json.Number); isNum {
		return sameNumber(w, g)
	}
	return false
}

// sameNumber reports whether a and b are JSON numbers of one value.
func sameNumber(a, b string) bool {
	if !json.Valid([]byte(a)) || !json.Valid([]byte(b)) {
		return false
	}
	x, ok := new(big.Rat).SetString(a)
	if !ok {
		return false
	}
	y, ok := new(big.Rat).SetString(b)
	return ok && x.Cmp(y) == 0
}

// tostringText reproduces jq's `tostring` with no `//` ahead of it: a string
// is itself, null is "null", a boolean is "true" or "false", and anything else
// is its JSON. jqString, the `(v // "") | tostring` the accessors read, folds
// false and null into "", which a witness must not do.
func tostringText(v any) string {
	switch t := v.(type) {
	case nil:
		return "null"
	case bool:
		if t {
			return "true"
		}
		return "false"
	case string:
		return t
	case json.Number:
		return t.String()
	default:
		raw, err := json.Marshal(t)
		if err != nil {
			return ""
		}
		return string(raw)
	}
}

// shown renders a value for a line a person reads: a string quoted, anything
// else as its JSON text.
func shown(v any) string {
	if s, ok := v.(string); ok {
		return strconv.Quote(s)
	}
	return tostringText(v)
}

// Write runs one `gc bd <args>` write with the streams given and returns what
// its run returned, whose ExitCode is gc bd's exit status. Its output is gc bd's
// own, so a caller reads a write here as it reads one it runs itself.
func (c *Client) Write(stdin io.Reader, stdout, stderr io.Writer, args ...string) error {
	cmd := exec.Command(c.bin, append([]string{"bd"}, args...)...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = stdin, stdout, stderr
	return cmd.Run()
}
