// Package gcbd is the `gc bd` subprocess seam.
//
// gctk shells out to `gc` exactly as the shell scripts it replaces did, rather
// than linking the beads library. That keeps the observability, the stub
// surface and the permissions surface identical across the port: the same
// invocations appear in the same logs, and the same test stubs serve them.
//
// The accessors mirror the jq expressions the scripts used, including their
// corners. `(.x // "") | tostring` treats BOTH null and false as absent, so a
// metadata value of false reads as the empty string here too — matching the
// scripts is the point, not improving on them.
package gcbd

import (
	"bytes"
	"encoding/json"
	"errors"
	"os/exec"
	"strings"
)

// Bead is one row of `gc bd show --json`, decoded far enough for the fields the
// cadence reads. Metadata values keep their JSON types so Meta can reproduce
// jq's tostring.
type Bead struct {
	ID       string         `json:"id"`
	Status   string         `json:"status"`
	Assignee any            `json:"assignee"`
	Notes    any            `json:"notes"`
	Metadata map[string]any `json:"metadata"`
}

// Scrub strips the control characters that break `--json` parsing, keeping LF
// alone. It must accept exactly what the shell fallback accepts — lifecycle.sh
// scrubs with `tr -d '\000-\011\013-\037'` — because a caller cannot tell which
// implementation answered, and a raw TAB or CR is just as invalid inside a JSON
// string as any other C0 byte.
func Scrub(b []byte) []byte {
	return bytes.Map(func(r rune) rune {
		switch {
		case r == '\n':
			return r
		case r < 0x20:
			return -1
		default:
			return r
		}
	}, b)
}

// jqString reproduces `(v // "") | tostring`.
func jqString(v any) string {
	switch t := v.(type) {
	case nil:
		return ""
	case bool:
		if !t {
			return "" // `//` treats false as absent
		}
		return "true"
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

// Meta returns metadata[key] the way the scripts read it.
func (b *Bead) Meta(key string) string {
	if b == nil || b.Metadata == nil {
		return ""
	}
	return jqString(b.Metadata[key])
}

// AssigneeString returns `.assignee // "" | tostring`.
func (b *Bead) AssigneeString() string { return jqString(b.Assignee) }

// NotesString returns `.notes // "" | tostring`.
func (b *Bead) NotesString() string { return jqString(b.Notes) }

// StatusLower returns `.status // "" | tostring | ascii_downcase`.
func (b *Bead) StatusLower() string { return strings.ToLower(b.Status) }

// Client runs `gc` subcommands. bin is the binary name resolved through PATH,
// which is what puts the test stubs in the path of every call.
type Client struct{ bin string }

// New returns a Client bound to the `gc` on PATH.
func New() *Client { return &Client{bin: "gc"} }

// Show reads one bead. A bead that cannot be read — `gc` failed, the payload
// did not decode, or the id resolved to nothing — returns nil, and every caller
// treats that as "refuse to act blind" rather than as an empty bead.
//
// `bd show --json` answers with an ARRAY when any id resolves and an OBJECT
// when none does, at rc=0 either way, so a non-array payload is a miss and not
// a parse bug.
func (c *Client) Show(id string) *Bead {
	cmd := exec.Command(c.bin, "bd", "show", id, "--json")
	out, err := cmd.Output()
	if err != nil {
		return nil
	}
	dec := json.NewDecoder(bytes.NewReader(Scrub(out)))
	dec.UseNumber()
	var rows []Bead
	if err := dec.Decode(&rows); err != nil || len(rows) == 0 {
		return nil
	}
	return &rows[0]
}

// Update runs one `gc bd update`, returning its combined output. Callers pass
// the whole transition in a single call: a partial write is the failure mode
// the atomic update exists to prevent.
func (c *Client) Update(id string, args ...string) (string, error) {
	full := append([]string{"bd", "update", id}, args...)
	cmd := exec.Command(c.bin, full...)
	out, err := cmd.CombinedOutput()
	return strings.TrimRight(string(out), "\n"), err
}

// ExitCode reports the exit status behind an Update error. A command that could
// not be run at all reports 127, which is the status a shell caller would have
// seen for the same failure.
func ExitCode(err error) int {
	if err == nil {
		return 0
	}
	var ee *exec.ExitError
	if errors.As(err, &ee) {
		return ee.ExitCode()
	}
	return 127
}
