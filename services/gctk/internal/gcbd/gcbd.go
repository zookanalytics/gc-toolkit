// Package gcbd is gctk's store adapter: the one package that reaches the bead
// store (docs/gctk-architecture.md, "The adapters"). It uses `gc bd` for writes,
// for reads that must see a fresh write and for the blocked set, and the
// supervisor API for other reads. The ledger reaches it through [Store], which
// gcbd/fake implements in memory for the domains' tests. The commands that
// predate the ledger, lifecycle and merge among them, still call [Client]
// directly.
//
// A bead READ (Show) goes through the running supervisor's pooled,
// process-lifetime Dolt connection over HTTP and falls back to forking
// `gc bd show` only when that daemon is unreachable, so a read on the healthy
// path neither forks nor opens its own Dolt connection, and the cadence still
// answers when the daemon is down. The daemon read is cached and carries no
// notes, so a read that must see the bead as it stands now, appended notes
// included, takes the authoritative ShowDirect path instead. Writes (Update)
// and the Show fallback shell out to `gc` exactly as the shell scripts do,
// which keeps the observability, the stub surface and the permissions surface
// of those paths identical across the port: the same invocations appear in the
// same logs, and the same test stubs serve them.
//
// The accessors mirror the jq expressions the scripts used, including their
// corners. `(.x // "") | tostring` treats BOTH null and false as absent, so a
// metadata value of false reads as the empty string here too — matching the
// scripts is the point, not improving on them.
package gcbd

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/daemon"
)

// Bead is one row of `gc bd show --json`, decoded far enough for the fields the
// cadence reads. Metadata values keep their JSON types so Meta can reproduce
// jq's tostring. Status is a pointer because jq's `.status // "open"` tells a
// null or absent status from an empty string, so the decode has to keep that
// distinction too. Dependencies keeps its JSON shape as well, so a row shape no
// reader expects still decodes the bead, and so does IssueType, which
// IssueTypeString reads as jq's tostring. IssueType, AwaitType and AwaitID are
// the fields that make a bead a human gate (prstatus.IsHumanGate); `gc bd dep list`
// carries them on each far bead's row, and bd leaves a field out of a row when
// its value is empty. DependencyType is the edge a `gc bd show` row's
// dependency was reached by, and is empty on any other row. Description,
// Priority, Labels and CreatedAt keep their JSON shapes too, each read through
// its accessor, and so do Ephemeral, NoHistory and IsTemplate, the columns
// that put a row in the store's ephemeral plane or make it a template.
type Bead struct {
	ID           string         `json:"id"`
	Title        string         `json:"title"`
	Status       *string        `json:"status"`
	ClosedAt     any            `json:"closed_at"`
	Assignee     any            `json:"assignee"`
	Notes        any            `json:"notes"`
	Metadata     map[string]any `json:"metadata"`
	Dependencies any            `json:"dependencies"`
	IssueType    any            `json:"issue_type"`
	AwaitType    string         `json:"await_type"`
	AwaitID      string         `json:"await_id"`
	Description  any            `json:"description"`
	Priority     any            `json:"priority"`
	Labels       any            `json:"labels"`
	CreatedAt    any            `json:"created_at"`
	Ephemeral    any            `json:"ephemeral"`
	NoHistory    any            `json:"no_history"`
	IsTemplate   any            `json:"is_template"`

	DependencyType string `json:"dependency_type"`
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

// IssueTypeString returns `.issue_type // "" | tostring`.
func (b *Bead) IssueTypeString() string { return jqString(b.IssueType) }

// ClosedAtString returns `.closed_at // "" | tostring`.
func (b *Bead) ClosedAtString() string { return jqString(b.ClosedAt) }

// DescriptionString returns `.description // "" | tostring`.
func (b *Bead) DescriptionString() string { return jqString(b.Description) }

// CreatedAtString returns `.created_at // "" | tostring`.
func (b *Bead) CreatedAtString() string { return jqString(b.CreatedAt) }

// PriorityInt returns the bead's priority, 0 when the row carries none or one
// that is not a whole number.
func (b *Bead) PriorityInt() int {
	switch t := b.Priority.(type) {
	case json.Number:
		if n, err := t.Int64(); err == nil {
			return int(n)
		}
	case float64:
		if t == float64(int(t)) {
			return int(t)
		}
	}
	return 0
}

// InEphemeralPlane reports whether the store keeps the bead in its ephemeral
// plane, bd's wisps table: a wisp, or a row stored with no history. bd's
// listing leaves that plane out unless asked.
func (b *Bead) InEphemeralPlane() bool { return b.Ephemeral == true || b.NoHistory == true }

// Template reports whether the bead is a template molecule, which bd's listing
// leaves out unless asked.
func (b *Bead) Template() bool { return b.IsTemplate == true }

// LabelStrings returns the bead's labels, in the row's order, leaving out a
// label that is not a string.
func (b *Bead) LabelStrings() []string {
	list, _ := b.Labels.([]any)
	var out []string
	for _, l := range list {
		if s, ok := l.(string); ok {
			out = append(out, s)
		}
	}
	return out
}

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
// in the environment, no discoverable supervisor, or a pinned store), in which
// case Show reads straight through bin. db is the store a pinned client names
// on every call ([Client.In]), empty for the store gc resolves. ctx ends every
// call the client forks ([Client.WithContext]), and is nil for a client whose
// calls run to their end.
type Client struct {
	bin     string
	httpc   *http.Client
	baseURL string
	city    string
	db      string
	ctx     context.Context
}

// stopGrace is how long a call stopped by its context may hold its output open
// before the wait for it gives up. The stop kills every process the call
// started, so only one that left the call's process group can hold it that
// long.
const stopGrace = 2 * time.Second

// WithContext returns a client whose every forked `gc` call ends when ctx
// does. Each call runs in a process group of its own, and once ctx is done the
// whole group is killed. gc runs bd as a child that writes to the call's own
// output, so a stop that killed gc alone would leave bd reading the store and
// the call waiting on it. A call that has not started by then does not start.
// The supervisor-API read is not a forked call and keeps its own timeout.
func (c *Client) WithContext(ctx context.Context) *Client {
	p := *c
	p.ctx = ctx
	return &p
}

// In returns a client pinned to the bead store at db, a store's .beads
// directory: every `gc bd` call it makes names that store with bd's own --db
// flag, and none reads the supervisor API, whose bead route finds a bead by the
// city and its id rather than in the store named. An empty db pins nothing and
// returns c.
func (c *Client) In(db string) *Client {
	if db == "" {
		return c
	}
	p := *c
	p.db = db
	p.httpc, p.baseURL, p.city = nil, "", ""
	return &p
}

// Where is the store gc resolves for this process, from its working directory
// and its environment, as `gc bd where --json` names it: the store's .beads
// directory and its bead prefix. A read that fails or names no store returns a
// *ReadError. A reader that must answer from one store pins to it
// ([Client.In]), because gc routes an unpinned read that names a bead to the
// store holding that bead, which is another rig's when the bead is.
func (c *Client) Where() (path, prefix string, err error) {
	var stderr bytes.Buffer
	cmd := c.command("bd", "where", "--json")
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return "", "", &ReadError{Reason: "gc bd where did not name the store: " + failure(out, stderr.String())}
	}
	var where struct {
		Path   string `json:"path"`
		Prefix string `json:"prefix"`
	}
	if err := json.Unmarshal(Scrub(out), &where); err != nil || where.Path == "" {
		return "", "", &ReadError{Reason: "gc bd where named no store"}
	}
	return where.Path, where.Prefix, nil
}

// StoreOf names the store whose bead prefix begins id, the longest such prefix
// when several do, from the stores `gc rig list --json` names, the city's
// among them: the store gc routes a read of id to when the read names no
// store. ok is false when no store's prefix begins id. A listing that fails
// or does not decode returns a *ReadError.
func (c *Client) StoreOf(id string) (path string, ok bool, err error) {
	var stderr bytes.Buffer
	cmd := c.command("rig", "list", "--json")
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return "", false, &ReadError{ID: id, Reason: "gc rig list did not name the stores: " + failure(out, stderr.String())}
	}
	var list struct {
		Rigs []struct {
			Prefix string `json:"prefix"`
			Path   string `json:"path"`
		} `json:"rigs"`
	}
	if err := json.Unmarshal(Scrub(out), &list); err != nil {
		return "", false, &ReadError{ID: id, Reason: "gc rig list did not decode: " + err.Error()}
	}
	best := ""
	for _, r := range list.Rigs {
		if r.Prefix == "" || r.Path == "" || !strings.HasPrefix(id, r.Prefix+"-") {
			continue
		}
		if !ok || len(r.Prefix) > len(best) {
			best, path, ok = r.Prefix, filepath.Join(r.Path, ".beads"), true
		}
	}
	return path, ok, nil
}

// Route names the store a read that names none pins to, so that every read of
// it answers from the store gc routes the first bead to: the store gc resolves
// for this process when no bead is named or its prefix begins the first id,
// else the store whose prefix does ([Client.StoreOf]). The resolved store
// answers when no store's prefix begins the id, and when the stores do not
// list, since a read there finds only the beads that store holds: a bead it
// does not hold is one its read cannot answer, never another store's. Only a
// read about a bead in another store than the one resolved here pays for the
// listing of stores.
func (c *Client) Route(ids ...string) (string, error) {
	path, prefix, err := c.Where()
	if err != nil {
		return "", err
	}
	if len(ids) == 0 || (prefix != "" && strings.HasPrefix(ids[0], prefix+"-")) {
		return path, nil
	}
	if other, ok, err := c.StoreOf(ids[0]); err == nil && ok {
		return other, nil
	}
	return path, nil
}

// command is the `gc` command for args, a `bd` call, with a pinned client's
// store named ahead of the verb, where bd reads its global flags. A call that
// names its own store keeps it. A client with a context runs the call in its
// own process group and kills the group once the context is done
// ([Client.WithContext]).
func (c *Client) command(args ...string) *exec.Cmd {
	if c.db != "" && len(args) > 0 && args[0] == "bd" && !slices.Contains(args, "--db") {
		args = append([]string{"bd", "--db", c.db}, args[1:]...)
	}
	if c.ctx == nil {
		return exec.Command(c.bin, args...)
	}
	cmd := exec.CommandContext(c.ctx, c.bin, args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error { return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL) }
	cmd.WaitDelay = stopGrace
	return cmd
}

// stopped is why the client's context stopped its calls, and nil while the
// context runs.
func (c *Client) stopped() error {
	if c.ctx == nil || c.ctx.Err() == nil {
		return nil
	}
	return context.Cause(c.ctx)
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
// that decides a write or a merge from the bead's current state must observe
// the latest write and must carry the bead's notes — the daemon's cache can lag
// a fresh write and its bead payload omits notes entirely — so such a read uses
// this authoritative path. Same decode and fail-closed contract as Show's
// fallback arm.
func (c *Client) ShowDirect(id string) *Bead { return c.showViaExec(id) }

// showViaExec reads one bead by forking `gc bd show --json`.
//
// The exit status is NOT consulted: the scripts read
// `gc bd show ... 2>/dev/null | scrub | jq -c '.[0] // empty'` with no
// pipefail, so a payload printed beside a non-zero exit is a bead there, and a
// port reads it the same way.
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
	out, err := c.command(args...).Output()
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

// Blockers reads the `blocks` blockers of each bead named, open and closed, in
// one `gc bd show <ids...> --json`, under List's strict contract. A show row
// carries each edge's far bead, so one read answers a whole level of a walk over
// the edges. --brief-deps would shrink the answer, but it drops the far bead's
// await_type, and with it what tells a human gate from any other. ok is false when
// the read fails, when a bead named has no row, or when its edges do not decode,
// because a bead whose edges nothing read proves nothing about what holds it.
func (c *Client) Blockers(ids []string) (blockers map[string][]Bead, ok bool) {
	rows, ok := c.array(true, append(append([]string{"bd", "show"}, ids...), "--json")...)
	if !ok {
		return nil, false
	}
	blockers = make(map[string][]Bead, len(rows))
	for i := range rows {
		edges, ok := rows[i].blocksEdges()
		if !ok {
			return nil, false
		}
		blockers[rows[i].ID] = edges
	}
	for _, id := range ids {
		if _, read := blockers[id]; !read {
			return nil, false
		}
	}
	return blockers, true
}

// blocksEdges decodes a `gc bd show` row's dependencies and keeps the `blocks`
// ones, each the far bead of its edge. ok is false on a shape that does not read
// as those rows: an edge with no id or no type cannot be told from a blocker.
func (b *Bead) blocksEdges() (edges []Bead, ok bool) {
	if b.Dependencies == nil {
		return nil, true
	}
	raw, err := json.Marshal(b.Dependencies)
	if err != nil {
		return nil, false
	}
	var deps []Bead
	if err := json.Unmarshal(raw, &deps); err != nil {
		return nil, false
	}
	for i := range deps {
		if deps[i].ID == "" || deps[i].DependencyType == "" {
			return nil, false
		}
		if deps[i].DependencyType == "blocks" {
			edges = append(edges, deps[i])
		}
	}
	return edges, true
}

// ErrGuard is the error of an update whose --if-status or --if-assignee no
// longer held when bd checked it in the write's own transaction: bd wrote
// nothing and exited 13, its code for a guard alone refusing the write.
var ErrGuard = errors.New("the bead no longer has the status or assignee the write was guarded on")

// guardExit is bd update's exit when every failure is a stale guard.
const guardExit = 13

// Update runs one `gc bd update`, returning its combined output. Callers pass
// the whole transition in a single call: a partial write is the failure mode
// the atomic update exists to prevent. An update a guard refused returns an
// error that is ErrGuard, and still carries the exit.
func (c *Client) Update(id string, args ...string) (string, error) {
	full := append([]string{"bd", "update", id}, args...)
	cmd := c.command(full...)
	out, err := cmd.CombinedOutput()
	if err != nil && ExitCode(err) == guardExit {
		err = fmt.Errorf("%w: %w", ErrGuard, err)
	}
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
