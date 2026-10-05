// Package gcbd reads and writes beads for the cadence.
//
// A bead READ (Show) goes through the running supervisor's pooled,
// process-lifetime Dolt connection over HTTP and falls back to forking
// `gc bd show` only when that daemon is unreachable, so a read on the healthy
// path neither forks nor opens its own Dolt connection, and the cadence still
// answers when the daemon is down. The daemon read is cached and carries no
// notes, so a write's read-back verification — which must observe the write it
// just made and must see appended notes — takes the authoritative ShowDirect
// path instead. Writes (Update) and the Show fallback shell out to `gc`
// exactly as the shell scripts do, which keeps the observability, the stub
// surface and the permissions surface of those paths identical across the
// port: the same invocations appear in the same logs, and the same test stubs
// serve them.
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
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/daemon"
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

// Scrub strips every C0 control byte (U+0000–U+001F), the range JSON requires
// escaped inside a string; a raw one — LF and TAB alike — makes the payload
// invalid JSON. Every byte above 0x1F passes through, DEL included, which JSON
// permits raw. It accepts exactly what the scripts' control-char-scrub block
// accepts (`tr -d '\000-\037'`), so a subcommand ported from a script reads
// every payload that script read.
func Scrub(b []byte) []byte {
	return bytes.Map(func(r rune) rune {
		if r < 0x20 {
			return -1
		}
		return r
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

// daemonTimeout bounds one supervisor-API read. A loopback read from a pooled
// connection answers in well under this even under load; the bound only caps a
// wedged-but-listening daemon so a read falls back to `gc bd` rather than hang.
const daemonTimeout = 5 * time.Second

// maxDaemonBody caps the response body a read will buffer, so a runaway payload
// cannot exhaust memory. One bead is kilobytes; a megabyte is slack.
const maxDaemonBody = 1 << 20

// Client reads and writes beads. bin is the `gc` binary resolved through PATH,
// which is what puts the test stubs in the path of every subprocess call; the
// write path and the Show fallback fork it. httpc/baseURL/city carry the
// supervisor-API read path and are all empty when it is off (GC_NO_API, no city
// in the environment, or no discoverable supervisor), in which case Show reads
// straight through bin.
type Client struct {
	bin     string
	httpc   *http.Client
	baseURL string
	city    string
}

// New returns a Client whose reads prefer the supervisor API when one is
// discoverable and enabled, and whose writes and read fallback use the `gc` on
// PATH. Discovery is config-only and does not touch the network; an unreachable
// daemon shows up as a failed request at read time, which falls back.
func New() *Client {
	c := &Client{bin: "gc"}
	if base, ok := daemon.BaseURL(); ok {
		if city, ok := daemon.City(); ok {
			c.baseURL = base
			c.city = city
			c.httpc = &http.Client{Timeout: daemonTimeout}
		}
	}
	return c
}

// daemonConfigured reports whether the supervisor-API read path is wired. All
// three fields move together in New, so any one of them being empty means the
// path is off and Show goes straight to the subprocess.
func (c *Client) daemonConfigured() bool {
	return c.httpc != nil && c.baseURL != "" && c.city != ""
}

// Show reads one bead. A bead that cannot be read — no implementation could
// answer, the payload did not decode, or the id resolved to nothing — returns
// nil, and every caller treats that as "refuse to act blind" rather than as an
// empty bead.
//
// The read prefers the supervisor API: a GET against the daemon's pooled Dolt
// connection, which neither forks nor opens a connection of its own. Only a 200
// that decodes to a bead is trusted; a non-200 (including a 404 miss), a
// transport failure, or an undecodable body falls through to `gc bd show`, so
// the daemon can only make the read faster, never change its answer — the
// authoritative `gc bd` path decides whether a bead exists. When the daemon
// read path is off entirely the read goes straight to that path.
func (c *Client) Show(id string) *Bead {
	if !c.daemonConfigured() {
		return c.showViaExec(id)
	}
	b, reason := c.showViaDaemon(id)
	if b != nil {
		c.logRoute("show "+id, "api", "")
		return b
	}
	c.logRoute("show "+id, "fallback", reason)
	return c.showViaExec(id)
}

// ShowDirect reads one bead straight from `gc bd`, never the supervisor API.
// Show routes cold reads through the daemon's cached connection, but a read
// that verifies a write just made must observe that write and must carry the
// bead's notes — the daemon's cache can lag a fresh write and its bead payload
// omits notes entirely — so a verification read-back uses this authoritative
// path. Same decode and fail-closed contract as Show's fallback arm.
func (c *Client) ShowDirect(id string) *Bead { return c.showViaExec(id) }

// showViaExec reads one bead by forking `gc bd show --json`.
//
// The exit status is NOT consulted: the scripts read
// `gc bd show ... 2>/dev/null | scrub | jq -c '.[0] // empty'` with no
// pipefail, so a payload printed beside a non-zero exit is a bead there, and a
// port reads it the same way. Reporting a landed transition as UNVERIFIED
// (exit 2) because the read-back's `gc` also warned is the divergence from
// those scripts that this avoids.
//
// `bd show --json` answers with an ARRAY when any id resolves and an OBJECT
// when none does, at rc=0 either way, so a non-array payload is a miss and not
// a parse bug.
func (c *Client) showViaExec(id string) *Bead {
	cmd := exec.Command(c.bin, "bd", "show", id, "--json")
	out, err := cmd.Output()
	if err != nil {
		var ee *exec.ExitError
		if !errors.As(err, &ee) {
			return nil
		}
	}
	dec := json.NewDecoder(bytes.NewReader(Scrub(out)))
	dec.UseNumber()
	var rows []Bead
	if err := dec.Decode(&rows); err != nil || len(rows) == 0 {
		return nil
	}
	return &rows[0]
}

// showViaDaemon reads one bead over the supervisor API, returning the bead on a
// trusted 200 or (nil, reason) on anything the caller should fall back from.
// The daemon serves ONE bead object (where `gc bd show` prints a one-element
// array), so the payload decodes directly into a Bead. Scrub and UseNumber run
// here too, for the same control-byte and number-fidelity reasons the
// subprocess path needs them. A 200 that decodes to a bead with no id is a miss
// (a problem+json body slipped past the status check), not a bead.
func (c *Client) showViaDaemon(id string) (*Bead, string) {
	resp, err := c.httpc.Get(daemon.BeadURL(c.baseURL, c.city, id))
	if err != nil {
		return nil, "transport"
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, "status-" + strconv.Itoa(resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxDaemonBody))
	if err != nil {
		return nil, "read"
	}
	dec := json.NewDecoder(bytes.NewReader(Scrub(body)))
	dec.UseNumber()
	var b Bead
	if err := dec.Decode(&b); err != nil || b.ID == "" {
		return nil, "decode"
	}
	return &b, ""
}

// logRoute emits one read-routing line to stderr when GC_DEBUG is on, the proof
// an operator reads to confirm a read landed on the daemon (route=api) rather
// than forking bd (route=fallback). Quiet by default so the stderr contract the
// cadence callers read is unchanged, matching how `gc` gates its own route logs.
func (c *Client) logRoute(what, route, reason string) {
	if !gcDebug() {
		return
	}
	if reason != "" {
		fmt.Fprintf(os.Stderr, "gctk gcbd: %s route=%s reason=%s\n", what, route, reason)
		return
	}
	fmt.Fprintf(os.Stderr, "gctk gcbd: %s route=%s\n", what, route)
}

func gcDebug() bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv("GC_DEBUG"))) {
	case "", "0", "false", "no":
		return false
	default:
		return true
	}
}

// List runs `gc bd list <args>` and decodes the JSON array it prints. ok is
// false when the output does not decode as an array — the fail-closed signal
// the scripts read from `jq -e 'type == "array"'`, so a caller refuses to act
// on a miss rather than reading it as an empty result. Show's exit-status and
// preface handling applies unchanged: the status is not consulted, and the
// rig-preface line rides stderr, so stdout is the payload whatever gc warned
// about. An empty selection is a well-formed `[]` — rows nil, ok true.
func (c *Client) List(args ...string) (rows []Bead, ok bool) {
	full := append([]string{"bd", "list"}, args...)
	cmd := exec.Command(c.bin, full...)
	out, err := cmd.Output()
	if err != nil {
		var ee *exec.ExitError
		if !errors.As(err, &ee) {
			return nil, false
		}
	}
	dec := json.NewDecoder(bytes.NewReader(Scrub(out)))
	dec.UseNumber()
	if err := dec.Decode(&rows); err != nil {
		return nil, false
	}
	return rows, true
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
