package gcbd

import (
	"bytes"
	"cmp"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os/exec"
	"slices"
	"strings"
)

// The store's blocked set, as the adapter reads it (docs/gctk-architecture.md,
// "The adapters"). The store's rules are the store's own: the adapter returns
// bd's answer and computes none itself. The supervisor serves no blocked set, so
// the adapter reads it through `gc bd blocked`, whose listing names, for each bead
// the store marks blocked, the bead's own live waits or, when it has none, the
// parent it is held through.
//
// Two compensations stand in for answers bd's listing cannot give, and both go
// once the bd the city runs judges a waits-for edge by its gate and fails its
// listing when a read of parents fails (tk-ssm8qns.5, then tk-ssm8qns.6):
//
//   - bd judges a waits-for edge by its spawner's status rather than by its gate,
//     in its listing and in its close rule alike. So a bead with a waits-for edge
//     of its own is answered with a *WaitsForError, taken from the bead's own
//     edges, whatever the listing says of it.
//   - The listing drops every bead held only through a parent when its read of
//     parents fails, and still exits 0. So the adapter also reads the ids the
//     store marks blocked, through `gc bd sql` with the query the listing starts
//     from, and answers a marked bead the listing leaves out with a *ReadError.
//
// The two reads are not one transaction, so a bead that changes between them can
// get a *ReadError, which the next read clears.

// marksQuery is the first read of bd's blocked listing (GetBlockedIssuesInTx in
// internal/storage/issueops/blocked.go, beads 7ef2fd05e): the ids the store marks
// blocked, from its issues table and its wisps table.
const marksQuery = "SELECT id FROM issues WHERE is_blocked = 1 AND status <> 'closed' AND status <> 'pinned' " +
	"UNION ALL SELECT id FROM wisps WHERE is_blocked = 1 AND status <> 'closed' AND status <> 'pinned'"

// The edge types that hold a bead, as bd's blocked rule reads them.
const (
	EdgeBlocks            = "blocks"
	EdgeConditionalBlocks = "conditional-blocks"
	EdgeWaitsFor          = "waits-for"
	EdgeParentChild       = "parent-child"
)

// WaitsForError answers a bead that has a waits-for edge of its own. bd judges
// such an edge by its spawner's status rather than by its gate, so neither its
// blocked listing nor its close rule answers the bead. The answer stands until
// the bd the city runs judges the gate, so it is not a failed read: a caller
// that acts holds the bead, and one that reports shows the edge as unjudged.
// Spawners are the beads its waits-for edges name, and Blocks the beads its own
// blocks and conditional-blocks edges name that the listing names live, which
// bd judges by their status as it judges any such wait.
type WaitsForError struct {
	ID       string
	Spawners []string
	Blocks   []string
}

func (e *WaitsForError) Error() string {
	return fmt.Sprintf("%s waits for %s through a waits-for edge, which bd judges by its spawner's status rather than its gate, so the store cannot say whether it holds",
		e.ID, strings.Join(e.Spawners, ", "))
}

// ReadError says one read could not answer: the store's reply failed or did not
// decode, or its blocked listing left out a bead the store marks blocked. ID
// names the bead it could not answer, and is empty when the whole read failed.
// The next read can answer, so it is never an answer about the bead.
type ReadError struct {
	ID     string
	Reason string
}

func (e *ReadError) Error() string {
	if e.ID == "" {
		return "the store's read failed: " + e.Reason
	}
	return fmt.Sprintf("the store's read could not answer %s: %s", e.ID, e.Reason)
}

// Edge is one of a bead's own edges: its type, the far bead, and the far bead's
// title, its status and, once it closed, when. A `gc bd show` row carries the far
// bead's fields, and leaves out an edge whose far bead the store does not hold.
// A `gc bd list` row carries every edge the bead has, with the far bead's id and
// the edge's type alone, so its Title, Status and ClosedAt are empty.
type Edge struct {
	Type     string
	ID       string
	Title    string
	Status   string
	ClosedAt string
}

// Edges decodes the bead's own edges, from either row shape: a show's
// {id, dependency_type} with the far bead's fields, or a listing's
// {depends_on_id, type}. A row with no edges has none. An edge with no id or no
// type cannot be told from any other, so it fails the decode.
func (b *Bead) Edges() ([]Edge, error) {
	if b.Dependencies == nil {
		return nil, nil
	}
	raw, err := json.Marshal(b.Dependencies)
	if err != nil {
		return nil, err
	}
	var deps []struct {
		ID          string `json:"id"`
		Type        string `json:"dependency_type"`
		DependsOnID string `json:"depends_on_id"`
		ListType    string `json:"type"`
		Title       any    `json:"title"`
		Status      any    `json:"status"`
		ClosedAt    any    `json:"closed_at"`
	}
	if err := json.Unmarshal(raw, &deps); err != nil {
		return nil, err
	}
	edges := make([]Edge, 0, len(deps))
	for _, d := range deps {
		id, typ := cmp.Or(d.ID, d.DependsOnID), cmp.Or(d.Type, d.ListType)
		if id == "" || typ == "" {
			return nil, fmt.Errorf("an edge of %s has no id or no type", b.ID)
		}
		edges = append(edges, Edge{Type: typ, ID: id, Title: jqString(d.Title), Status: jqString(d.Status), ClosedAt: jqString(d.ClosedAt)})
	}
	return edges, nil
}

// Blocking is the store's answer for one bead: whether it holds the bead out of
// bd ready for a wait and, when it does, what the listing names. On holds the
// bead's own live waits. Through is the parent the bead is held through, when
// it has none of its own.
type Blocking struct {
	Blocked bool
	On      []string
	Through string
}

// BlockedSet is the store's blocked set as one read gave it: the beads its
// blocked listing names, each with what holds it, and the ids it marks blocked.
type BlockedSet struct {
	listed map[string][]string
	marked map[string]bool
}

// NewBlockedSet builds a blocked set from a listing, each bead with the ids the
// listing names for it, and the ids the store marks blocked. The real store's
// read builds one, and so does a fake's, whose test sets both.
func NewBlockedSet(listed map[string][]string, marked []string) *BlockedSet {
	s := &BlockedSet{listed: make(map[string][]string, len(listed)), marked: make(map[string]bool, len(marked))}
	for id, by := range listed {
		s.listed[id] = slices.Clone(by)
	}
	for _, id := range marked {
		s.marked[id] = true
	}
	return s
}

// Answer is the store's answer for b, whose row and edges were read beside this
// set. A bead with a waits-for edge of its own gets a *WaitsForError. A bead the
// store marks blocked that the listing leaves out gets a *ReadError, and so does
// one the listing names as held by a bead its row does not reach, since the row
// and the listing then disagree. Every other bead gets the listing's answer.
func (s *BlockedSet) Answer(b *Bead) (Blocking, error) {
	edges, err := b.Edges()
	if err != nil {
		return Blocking{}, &ReadError{ID: b.ID, Reason: "its edges did not decode: " + err.Error()}
	}
	var spawners []string
	own := map[string]bool{}
	parent := ""
	for _, e := range edges {
		switch e.Type {
		case EdgeWaitsFor:
			spawners = append(spawners, e.ID)
		case EdgeBlocks, EdgeConditionalBlocks:
			own[e.ID] = true
		case EdgeParentChild:
			parent = e.ID
		}
	}
	by, listed := s.listed[b.ID]
	if len(spawners) > 0 {
		var blocks []string
		for _, id := range by {
			if own[id] {
				blocks = append(blocks, id)
			}
		}
		return Blocking{}, &WaitsForError{ID: b.ID, Spawners: spawners, Blocks: blocks}
	}
	if !listed {
		if s.marked[b.ID] {
			return Blocking{}, &ReadError{ID: b.ID, Reason: "the store marks it blocked, and its blocked listing leaves it out"}
		}
		return Blocking{}, nil
	}
	if len(by) > 0 && !slices.ContainsFunc(by, func(id string) bool { return !own[id] }) {
		return Blocking{Blocked: true, On: slices.Clone(by)}, nil
	}
	if len(by) == 1 && by[0] == parent && parent != "" {
		return Blocking{Blocked: true, Through: parent}, nil
	}
	return Blocking{}, &ReadError{ID: b.ID, Reason: fmt.Sprintf("its blocked listing names %s, which is neither a wait of its own nor its parent", strings.Join(by, ", "))}
}

// Rows reads each bead named, with its own edges, from the store itself in one
// `gc bd show`, so the read sees a write just made. A read that fails returns a
// *ReadError, and so does a bead named that the reply carries no row for, which
// the error names. bd's show leaves out a bead the store does not hold and a
// bead whose lookup failed alike, and exits 0 while it found another bead named,
// so its reply cannot tell the two apart. When it finds none, it exits 1.
func (c *Client) Rows(ids []string) ([]Bead, error) {
	if len(ids) == 0 {
		return nil, nil
	}
	raw, err := c.strictArray(append(append([]string{"bd", "show"}, ids...), "--json")...)
	if err != nil {
		return nil, err
	}
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	var rows []Bead
	if err := dec.Decode(&rows); err != nil {
		return nil, &ReadError{Reason: "gc bd show's rows did not decode: " + err.Error()}
	}
	read := make(map[string]bool, len(rows))
	for i := range rows {
		read[rows[i].ID] = true
	}
	for _, id := range ids {
		if !read[id] {
			return nil, &ReadError{ID: id, Reason: "gc bd show returned no row for it, which is its reply both for a bead the store does not hold and for one whose lookup failed"}
		}
	}
	return rows, nil
}

// Blocked reads the store's blocked set: `gc bd blocked`, then the marks it is
// checked against. A read that fails returns a *ReadError.
func (c *Client) Blocked() (*BlockedSet, error) {
	raw, err := c.strictArray("bd", "blocked", "--json")
	if err != nil {
		return nil, err
	}
	var listing []struct {
		ID        string   `json:"id"`
		BlockedBy []string `json:"blocked_by"`
	}
	if err := json.Unmarshal(raw, &listing); err != nil {
		return nil, &ReadError{Reason: "gc bd blocked's listing did not decode: " + err.Error()}
	}
	listed := make(map[string][]string, len(listing))
	for _, r := range listing {
		if r.ID == "" {
			return nil, &ReadError{Reason: "gc bd blocked listed a bead with no id"}
		}
		listed[r.ID] = r.BlockedBy
	}
	raw, err = c.strictArray("bd", "sql", "--json", marksQuery)
	if err != nil {
		return nil, err
	}
	var marks []struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(raw, &marks); err != nil {
		return nil, &ReadError{Reason: "the marks read did not decode: " + err.Error()}
	}
	marked := make([]string, 0, len(marks))
	for _, m := range marks {
		if m.ID == "" {
			return nil, &ReadError{Reason: "the marks read named a row with no id"}
		}
		marked = append(marked, m.ID)
	}
	return NewBlockedSet(listed, marked), nil
}

// strictArray runs `gc <args>` and returns the one JSON array it prints, under
// List's strict contract: a non-zero exit, a reply that is not an array, or
// anything but whitespace after the array fails the read with a *ReadError.
func (c *Client) strictArray(args ...string) (json.RawMessage, error) {
	what := "gc " + strings.Join(args[:min(len(args), 2)], " ")
	var stderr bytes.Buffer
	cmd := c.command(args...)
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		var ee *exec.ExitError
		if errors.As(err, &ee) {
			return nil, &ReadError{Reason: fmt.Sprintf("%s exited %d: %s", what, ee.ExitCode(), failure(out, stderr.String()))}
		}
		return nil, &ReadError{Reason: fmt.Sprintf("%s did not run: %v", what, err)}
	}
	dec := json.NewDecoder(bytes.NewReader(Scrub(out)))
	var raw json.RawMessage
	if err := dec.Decode(&raw); err != nil || len(raw) == 0 || raw[0] != '[' {
		return nil, &ReadError{Reason: what + " did not answer with a JSON array"}
	}
	var rest json.RawMessage
	if err := dec.Decode(&rest); err != io.EOF {
		return nil, &ReadError{Reason: what + " printed more than one JSON array"}
	}
	return raw, nil
}

// failure is what a read that exited non-zero said. bd, asked for --json,
// prints its error as a JSON object on stdout, while gc's stderr can open with
// its notice of the store it answers from, so the object's error comes first,
// and the first line of stderr, where gc itself reports a failure, comes next.
func failure(stdout []byte, stderr string) string {
	var reply struct {
		Error string `json:"error"`
	}
	if json.Unmarshal(Scrub(stdout), &reply) == nil && reply.Error != "" {
		return reply.Error
	}
	if s := firstLine(stderr); s != "" {
		return s
	}
	return "it printed no error"
}

func firstLine(s string) string {
	s = strings.TrimSpace(s)
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		return s[:i]
	}
	return s
}
