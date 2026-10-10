// Package gcbd reads and writes beads for the cadence.
//
// A bead READ (Show) goes through the running supervisor's pooled,
// process-lifetime Dolt connection over HTTP and falls back to forking
// `gc bd show` only when that daemon is unreachable, so a read on the healthy
// path neither forks nor opens its own Dolt connection, and the cadence still
// answers when the daemon is down. The daemon read is cached and carries no
// notes, so a write's read-back verification — which must observe the write it
// just made and must see appended notes — takes the authoritative ShowDirect
// path instead. Writes (Create, Update) and the Show fallback shell out to `gc`
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
// jq's tostring. Status is a pointer because jq's `.status // "open"` tells a
// null or absent status from an empty string, so the decode has to keep that
// distinction too.
type Bead struct {
	ID       string         `json:"id"`
	Status   *string        `json:"status"`
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
func (b *Bead) StatusLower() string { return b.StatusLowerOr("") }

// StatusLowerOr returns `(.status // def) | ascii_downcase`. def stands in only
// for a null or absent status; an empty-string status stays empty, which is
// what jq's `//` does with it.
func (b *Bead) StatusLowerOr(def string) string {
	if b.Status == nil {
		return strings.ToLower(def)
	}
	return strings.ToLower(*b.Status)
}

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
	rows, ok := c.array(false, "bd", "show", id, "--json")
	if !ok || len(rows) == 0 {
		return nil
	}
	return &rows[0]
}

// array runs `gc <args>` and decodes the JSON array it prints. ok is false when
// stdout does not open with a JSON array: undecodable, empty, an object, or a
// bare null.
//
// strict is bd-lib.sh's bd_list contract, the `jq -e 'type == "array"'` test
// the scripts gate their list and dependency reads on. It refuses a non-zero
// exit whatever was printed beside it, because a store error mid-query (a dolt
// timeout) can print an empty or partial array and still exit 1. It refuses
// anything but whitespace after the array, because jq fails the whole stream
// on `[]garbage`: a caller that read the array ahead of the garbage would act
// on a view cut short. A second whole value fails too. jq -e passes `[] []`,
// but `gc bd list` prints one array, and picking one of two would be a guess.
//
// Without strict, neither the status nor what follows the array is consulted.
// That is how the scripts read `gc bd show`: `jq -c '.[0] // empty'`, its exit
// unread, prints the first array's row before it reaches what follows.
func (c *Client) array(strict bool, args ...string) ([]Bead, bool) {
	out, err := exec.Command(c.bin, args...).Output()
	if err != nil {
		var ee *exec.ExitError
		if strict || !errors.As(err, &ee) {
			return nil, false
		}
	}
	dec := json.NewDecoder(bytes.NewReader(Scrub(out)))
	dec.UseNumber()
	var raw json.RawMessage
	if err := dec.Decode(&raw); err != nil || len(raw) == 0 || raw[0] != '[' {
		return nil, false
	}
	if strict {
		var rest json.RawMessage
		if err := dec.Decode(&rest); err != io.EOF {
			return nil, false
		}
	}
	rdec := json.NewDecoder(bytes.NewReader(raw))
	rdec.UseNumber()
	var rows []Bead
	if err := rdec.Decode(&rows); err != nil {
		return nil, false
	}
	return rows, true
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

// List runs `gc bd list <args>` and decodes the JSON array it prints, under the
// strict contract of bd-lib.sh's bd_list: ok is false on a non-zero exit, on
// output that is not an array, or on anything but whitespace after the array,
// so a caller refuses to act rather than reading a failed or partial read as an
// empty result. The rig-preface line rides stderr, so stdout is the payload. An
// empty selection is a well-formed `[]` at exit 0 — rows nil, ok true.
func (c *Client) List(args ...string) (rows []Bead, ok bool) {
	return c.array(true, append([]string{"bd", "list"}, args...)...)
}

// DepList runs `gc bd dep list <id> <args>` and decodes the JSON array of
// dependency rows it prints, under List's strict contract: a caller holds on a
// failed or unreadable probe rather than reading it as "no dependencies".
func (c *Client) DepList(id string, args ...string) (rows []Bead, ok bool) {
	return c.array(true, append([]string{"bd", "dep", "list", id}, args...)...)
}

// ErrNotFiled reports a Create that filed nothing a reader can find. Either the
// metadata had no key, or bd refused the create or answered with no id, or the
// bead read back carrying none of its keys and was closed. A create whose reply
// was lost can still have landed whole, so a caller that files again first
// looks for the bead the way its own dedup does.
var ErrNotFiled = errors.New("gcbd: create filed nothing")

// ErrUnverified reports a Create whose bead was filed but whose read-back could
// not be made, or did not show every key as written. Create returns the id with
// it. The bead carries at least part of its metadata, so a caller holds off
// acting on it and retries on its next run.
var ErrUnverified = errors.New("gcbd: created bead did not read back as written")

// Create files one bead with meta in the same write and returns its id. It is
// bd_create in assets/scripts/bd-lib.sh, ported, and keeps that contract.
//
// The metadata a bead is born with is what its readers select it by: its
// task_kind, the anchor it hangs on, the key its producer dedups on. Written in
// a second update, it is missing whenever that write fails or the create's id
// never comes back, so no reader can see the bead and the producer's next run
// files a stamped twin beside it. `gc bd create --metadata` lands the payload
// in the bead's own row insert, so the bead exists with its metadata or not at
// all.
//
// args are `gc bd create`'s own: the title, -t, --status, --notes, --db and the
// rest. A non-empty body is the bead's description, sent on stdin through
// --body-file - so no argv limit bounds it. Create adds --metadata and --json.
//
// The bead is read back from the store the create wrote, through the
// authoritative ShowDirect path, and every key must read back with the value
// written. Values compare the way Meta reads them, as text, because bd keeps a
// create's string values as strings while a --set-metadata re-stamp of the same
// key can store a number. A bead that reads back carrying none of meta's keys
// is closed (gc.outcome=abandoned) so that no reader meets it, and Create
// reports ErrNotFiled. A read-back that fails, or shows only some keys as
// written, returns the id with ErrUnverified.
func (c *Client) Create(meta map[string]any, body string, args ...string) (string, error) {
	if len(meta) == 0 {
		return "", fmt.Errorf("%w: refusing to file a bead without metadata", ErrNotFiled)
	}
	payload, err := json.Marshal(meta)
	if err != nil {
		return "", fmt.Errorf("%w: metadata does not encode: %v", ErrNotFiled, err)
	}
	full := append([]string{"bd", "create"}, args...)
	if body != "" {
		full = append(full, "--body-file", "-")
	}
	full = append(full, "--metadata", string(payload), "--json")
	cmd := exec.Command(c.bin, full...)
	if body != "" {
		cmd.Stdin = strings.NewReader(body)
	}
	// The exit status is not consulted: a refusal answers with an error object
	// and a non-zero exit, and the reply alone says which it was.
	out, _ := cmd.Output()
	id, reason := createdID(out)
	if id == "" {
		if reason != "" {
			return "", fmt.Errorf("%w: bd create returned no id: %s", ErrNotFiled, reason)
		}
		return "", fmt.Errorf("%w: bd create returned no id", ErrNotFiled)
	}
	db := dbFlag(args)
	var dbArgs []string
	if db != "" {
		dbArgs = []string{"--db", db}
	}
	rows, ok := c.array(false, append(append([]string{"bd", "show", id}, dbArgs...), "--json")...)
	if !ok || len(rows) == 0 || rows[0].ID != id {
		return id, fmt.Errorf("%w: %s (unreadable)", ErrUnverified, id)
	}
	switch readBack(meta, rows[0].Metadata) {
	case "landed":
		return id, nil
	case "bare":
		note := "Unmade by gctk Create: this bead landed without the metadata its create carried, so no reader could find it. Its producer files it afresh."
		closeArgs := append(append([]string{}, dbArgs...), "--status=closed",
			"--set-metadata", "gc.outcome=abandoned", "--append-notes", note)
		if _, err := c.Update(id, closeArgs...); err != nil {
			return "", fmt.Errorf("%w: %s landed without its metadata and could not be closed: %v", ErrNotFiled, id, err)
		}
		return "", fmt.Errorf("%w: %s landed without its metadata and was closed", ErrNotFiled, id)
	default:
		return id, fmt.Errorf("%w: %s (partial)", ErrUnverified, id)
	}
}

// createdID reads the id out of a `gc bd create --json` reply: the bead as an
// object, or an array holding it. A refusal is a bare {"error": ...} object,
// whose message comes back as the reason.
func createdID(out []byte) (id, reason string) {
	dec := json.NewDecoder(bytes.NewReader(Scrub(out)))
	var v any
	if err := dec.Decode(&v); err != nil {
		return "", ""
	}
	if arr, ok := v.([]any); ok {
		if len(arr) == 0 {
			return "", ""
		}
		v = arr[0]
	}
	obj, ok := v.(map[string]any)
	if !ok {
		return "", ""
	}
	if s, ok := obj["id"].(string); ok && s != "" && s != "null" {
		return s, ""
	}
	if s, ok := obj["error"].(string); ok {
		return "", s
	}
	return "", ""
}

// dbFlag returns the store a create's args name with --db, in either spelling,
// so the read-back and the close go to the store the create wrote.
func dbFlag(args []string) string {
	db := ""
	for i, a := range args {
		if a == "--db" && i+1 < len(args) {
			db = args[i+1]
		}
		if strings.HasPrefix(a, "--db=") {
			db = strings.TrimPrefix(a, "--db=")
		}
	}
	return db
}

// readBack judges a created bead's metadata against the payload: "landed" when
// every key is present with its value as text, "bare" when none is present, and
// "partial" otherwise.
func readBack(meta, got map[string]any) string {
	present := 0
	matched := 0
	for k, v := range meta {
		g, ok := got[k]
		if !ok {
			continue
		}
		present++
		if jqString(g) == jqString(v) {
			matched++
		}
	}
	switch {
	case matched == len(meta):
		return "landed"
	case present == 0:
		return "bare"
	default:
		return "partial"
	}
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
