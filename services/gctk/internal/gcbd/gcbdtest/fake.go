// Package gcbdtest is an in-memory gcbd.Store for tests: the `gc` stub of
// assets/scripts/test-harness.sh (_write_gc_stub) without the subprocess, so a
// Go test drives a ported cadence arm against the same store semantics the
// shell suites drive and asserts the same calls.
//
// Every knob on Fake mirrors one STUB_* variable of that stub, and the
// evaluation rules (which rows a list selects, how an update coerces a value,
// which way a dependency row points) follow its jq and awk, corners included:
//
//   - Beads is STUB_STORE; Deps is STUB_DEPS ("A|TYPE|B" rows); Calls, through
//     Log, is STUB_GC_LOG, one line per call with the leading `gc` dropped.
//   - ShowFail is STUB_SHOW_FAIL; ShowHook is STUB_SHOW_HOOK.
//   - ListFail is STUB_LIST_FAIL; ListFailOn is STUB_LIST_FAIL_ON, and also
//     stands in for STUB_LIST_PARTIAL and STUB_LIST_TRAILING, whose bytes the
//     Client's strict array read turns into the same ok=false this fake
//     returns directly.
//   - DepFail collapses STUB_DEP_GARBAGE, STUB_DEP_PARTIAL and
//     STUB_DEP_TRAILING to ok=false the same way.
//   - UpdateFail is STUB_UPDATE_FAIL; CloseFail is STUB_CLOSE_FAIL; DropKeys is
//     STUB_DROP_KEYS.
//
// The Store surface has no create, close or dep add, so STUB_CREATE_*,
// STUB_ENFORCE_BLOCKS, STUB_ENFORCE_CLOSE_OWNER and STUB_DEP_FAIL have no
// counterpart here.
package gcbdtest

import (
	"encoding/json"
	"fmt"
	"regexp"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
)

// Edge is one STUB_DEPS row "From|Type|To". Orientation follows the stub: a
// blocks edge "A|blocks|B" means B depends on A (A blocks B); every other type
// means From depends on To (child A parent-childs parent B).
type Edge struct{ From, Type, To string }

// Call is one recorded Store call. Op is "show", "list", "dep list" or
// "update"; ID is the bead id where the verb takes one (show, dep list,
// update); Args is the argv after it, as rendered by ListQuery.Args or
// DepQuery.Args, or as passed to Update.
type Call struct {
	Op   string
	ID   string
	Args []string
}

// String renders the STUB_GC_LOG line for the call: "bd show <id>",
// "bd list <args>", "bd dep list <id> <args>", "bd update <id> <args>". A show
// line carries no args: the fake takes an id, not the Client's argv, so the
// `--json` the Client's own `bd show` passes is not logged here.
func (c Call) String() string {
	parts := []string{"bd", c.Op}
	if c.ID != "" {
		parts = append(parts, c.ID)
	}
	parts = append(parts, c.Args...)
	return strings.Join(parts, " ")
}

// ExitError is a refused write: what gcbd.ExitCode reads an rc from (through
// its ExitCode method) and what Update's combined output carries as Stderr,
// the way a stubbed `gc`'s stderr rides exec's CombinedOutput.
type ExitError struct {
	Code   int
	Stderr string
}

func (e *ExitError) Error() string { return fmt.Sprintf("exit status %d: %s", e.Code, e.Stderr) }

// ExitCode is the rc gcbd.ExitCode reports for this error.
func (e *ExitError) ExitCode() int { return e.Code }

// Fake is an in-memory gcbd.Store. Zero value usable; New seeds the beads.
// Every field is exported so a test sets the store and the knobs directly and
// reads the rows back after a write.
type Fake struct {
	Beads []gcbd.Bead
	Deps  []Edge

	// ShowFail (STUB_SHOW_FAIL): Show and ShowDirect return nil.
	ShowFail bool
	// ShowHook (STUB_SHOW_HOOK) runs before each Show/ShowDirect with the id, so
	// a test can mutate the store between reads.
	ShowHook func(id string)
	// ListFail (STUB_LIST_FAIL): every List answers ok=false.
	ListFail bool
	// ListFailOn (STUB_LIST_FAIL_ON, and the _PARTIAL/_TRAILING knobs as the
	// strict read sees them): ok=false when the rendered Args joined by spaces
	// contains it.
	ListFailOn string
	// DepFail (STUB_DEP_GARBAGE/_PARTIAL/_TRAILING): every DepList answers
	// ok=false.
	DepFail bool
	// UpdateFail (STUB_UPDATE_FAIL): ids whose every update is refused, rc 1,
	// nothing written.
	UpdateFail map[string]bool
	// CloseFail (STUB_CLOSE_FAIL): ids whose update is refused only when its
	// args carry --status=closed; a metadata-only write on the same id lands.
	CloseFail map[string]bool
	// DropKeys (STUB_DROP_KEYS): id -> keys an update silently does not write,
	// while still answering "updated". Metadata keys, and the words "assignee",
	// "status" and "description" for those fields; notes are never dropped.
	DropKeys map[string][]string

	// Calls records every Store call in order; Log renders them.
	Calls []Call

	// Descriptions holds `--description` writes by id. gcbd.Bead has no
	// description field (nothing in the cadence reads one), so the fake keeps
	// the stub's description column beside the rows rather than widening Bead.
	Descriptions map[string]string
}

// New returns a Fake seeded with beads, in store order.
func New(beads ...gcbd.Bead) *Fake {
	return &Fake{Beads: append([]gcbd.Bead(nil), beads...)}
}

var _ gcbd.Store = (*Fake)(nil)

// Log renders Calls one per line, each newline-terminated, so a test greps it
// the way the shell suites grep STUB_GC_LOG.
func (f *Fake) Log() string {
	var b strings.Builder
	for _, c := range f.Calls {
		b.WriteString(c.String())
		b.WriteByte('\n')
	}
	return b.String()
}

// Get returns a pointer into Beads for id, nil when absent: the row itself, for
// asserting what a write landed, not the copy Show hands out.
func (f *Fake) Get(id string) *gcbd.Bead {
	for i := range f.Beads {
		if f.Beads[i].ID == id {
			return &f.Beads[i]
		}
	}
	return nil
}

func (f *Fake) record(c Call) { f.Calls = append(f.Calls, c) }

// clone copies a row so a caller mutating what Show returned does not write
// the store behind the fake's back; the stub prints fresh JSON each time.
func clone(b gcbd.Bead) gcbd.Bead {
	out := b
	if b.Status != nil {
		s := *b.Status
		out.Status = &s
	}
	if b.Metadata != nil {
		out.Metadata = make(map[string]any, len(b.Metadata))
		for k, v := range b.Metadata {
			out.Metadata[k] = v
		}
	}
	return out
}

// Show mirrors `bd show <id>`: the hook runs, then STUB_SHOW_FAIL, then the row
// matching id — nil when none, as the Client reads the stub's `[]`.
func (f *Fake) Show(id string) *gcbd.Bead { return f.show(id) }

// ShowDirect is Show: the stub serves one `bd show`, whichever path asked.
func (f *Fake) ShowDirect(id string) *gcbd.Bead { return f.show(id) }

func (f *Fake) show(id string) *gcbd.Bead {
	f.record(Call{Op: "show", ID: id})
	if f.ShowHook != nil {
		f.ShowHook(id)
	}
	if f.ShowFail {
		return nil
	}
	b := f.Get(id)
	if b == nil {
		return nil
	}
	c := clone(*b)
	return &c
}

// List mirrors the stub's `bd list` jq over Beads in store order: status is
// `(.status // "open")` matched exactly against the comma set; each `k=v` is
// split at its FIRST `=` (no `=` makes the word both key and value) and
// compared as `(metadata[k] // "") | tostring` == v, so `k=` matches an absent
// key and a number 1 matches "1"; --has-metadata-key is map presence.
func (f *Fake) List(q gcbd.ListQuery) ([]gcbd.Bead, bool) {
	args := q.Args()
	f.record(Call{Op: "list", Args: args})
	if f.ListFail {
		return nil, false
	}
	if f.ListFailOn != "" && strings.Contains(strings.Join(args, " "), f.ListFailOn) {
		return nil, false
	}
	var statuses []string
	if st := strings.Join(q.Status, ","); st != "" {
		statuses = strings.Split(st, ",")
	}
	type kv struct{ k, v string }
	fields := make([]kv, 0, len(q.MetadataField))
	for _, fld := range q.MetadataField {
		k, v, found := strings.Cut(fld, "=")
		if !found {
			v = k
		}
		fields = append(fields, kv{k, v})
	}
	var rows []gcbd.Bead
	for i := range f.Beads {
		b := &f.Beads[i]
		if statuses != nil && !inSet(statuses, statusOr(b, "open")) {
			continue
		}
		if q.HasMetadataKey != "" {
			if _, ok := b.Metadata[q.HasMetadataKey]; !ok {
				continue
			}
		}
		match := true
		for _, fld := range fields {
			if b.Meta(fld.k) != fld.v {
				match = false
				break
			}
		}
		if !match {
			continue
		}
		rows = append(rows, clone(*b))
	}
	return rows, true
}

// statusOr is jq's `(.status // def)`, case-exact: def stands in for a null or
// absent status only, and an empty-string status stays empty.
func statusOr(b *gcbd.Bead, def string) string {
	if b.Status == nil {
		return def
	}
	return *b.Status
}

func inSet(set []string, s string) bool {
	for _, x := range set {
		if x == s {
			return true
		}
	}
	return false
}

// DepList mirrors the stub's `bd dep list <id>` awk: for each edge whose type
// matches (or every edge when q.Type is empty), a blocks edge makes issue=To,
// dependency=From and any other type issue=From, dependency=To; "down" yields
// the dependencies of id, "up" the issues depending on it, and no direction
// the From of every edge whose To is id. Rows come from Beads in store order;
// an id with no row is dropped.
func (f *Fake) DepList(id string, q gcbd.DepQuery) ([]gcbd.Bead, bool) {
	f.record(Call{Op: "dep list", ID: id, Args: q.Args()})
	if f.DepFail {
		return nil, false
	}
	want := map[string]bool{}
	for _, e := range f.Deps {
		if q.Type != "" && e.Type != q.Type {
			continue
		}
		issue, dep := e.From, e.To
		if e.Type == "blocks" {
			issue, dep = e.To, e.From
		}
		switch q.Direction {
		case "down":
			if issue == id {
				want[dep] = true
			}
		case "up":
			if dep == id {
				want[issue] = true
			}
		default:
			if e.To == id {
				want[e.From] = true
			}
		}
	}
	var rows []gcbd.Bead
	for i := range f.Beads {
		if want[f.Beads[i].ID] {
			rows = append(rows, clone(f.Beads[i]))
		}
	}
	return rows, true
}

// jsonNumber is the stub's number grammar: JSON's, stricter than jq's parser,
// so `+1`, `00`, `.5` and `NaN` stay strings.
var jsonNumber = regexp.MustCompile(`^-?(0|[1-9][0-9]*)([.][0-9]+)?([eE][-+]?[0-9]+)?$`)

// coerce types a --set-metadata value as the stub does: trimmed of
// space/TAB/CR/LF, a JSON number becomes the number (what json.Unmarshal of
// the literal yields, a float64, which Meta renders as jq's tostring renders
// the tonumber: 1.50 reads back "1.5"), true/false/null become the typed
// value, and anything else — a quoted string included — is the raw, untrimmed
// text.
func coerce(raw string) any {
	t := strings.Trim(raw, " \t\r\n")
	if jsonNumber.MatchString(t) || t == "true" || t == "false" || t == "null" {
		var v any
		if err := json.Unmarshal([]byte(t), &v); err == nil {
			return v
		}
	}
	return raw
}

// Update mirrors the stub's `bd update <id>`: STUB_UPDATE_FAIL, then
// STUB_CLOSE_FAIL on a `--status=closed` arg, then the flags in the stub's
// spellings (`--set-metadata k=v`/`--set-metadata=k=v`, `--unset-metadata k`/`=k`,
// `--assignee v`/`=v`, `--status=X` only, `--append-notes X` only,
// `--description X`/`-d X`/`--description=X`), applied in the order sets,
// unsets, assignee, status, notes, description, with DropKeys skipped. The
// answer is "updated <id>" at rc 0 even for an unknown id, which writes
// nothing. A refusal returns its stderr as the output and an *ExitError.
func (f *Fake) Update(id string, args ...string) (string, error) {
	f.record(Call{Op: "update", ID: id, Args: append([]string(nil), args...)})
	if f.UpdateFail[id] {
		e := &ExitError{Code: 1, Stderr: "gc: simulated update refusal for " + id}
		return e.Stderr, e
	}
	if f.CloseFail[id] && inSet(args, "--status=closed") {
		e := &ExitError{Code: 1, Stderr: "gc: simulated close refusal for " + id}
		return e.Stderr, e
	}
	var sets, unsets []string
	var asg, note, status, desc string
	var asgSet, noteSet, descSet bool
	for i := 0; i < len(args); i++ {
		a := args[i]
		next := func() string {
			if i+1 < len(args) {
				i++
				return args[i]
			}
			i++
			return ""
		}
		switch {
		case strings.HasPrefix(a, "--description="):
			desc, descSet = strings.TrimPrefix(a, "--description="), true
		case a == "--description" || a == "-d":
			desc, descSet = next(), true
		case a == "--set-metadata":
			sets = append(sets, next())
		case strings.HasPrefix(a, "--set-metadata="):
			sets = append(sets, strings.TrimPrefix(a, "--set-metadata="))
		case a == "--unset-metadata":
			unsets = append(unsets, next())
		case strings.HasPrefix(a, "--unset-metadata="):
			unsets = append(unsets, strings.TrimPrefix(a, "--unset-metadata="))
		case strings.HasPrefix(a, "--assignee="):
			asg, asgSet = strings.TrimPrefix(a, "--assignee="), true
		case a == "--assignee":
			asg, asgSet = next(), true
		case strings.HasPrefix(a, "--status="):
			status = strings.TrimPrefix(a, "--status=")
		case a == "--append-notes":
			note, noteSet = next(), true
		}
	}
	out := "updated " + id
	b := f.Get(id)
	if b == nil {
		return out, nil
	}
	drops := f.DropKeys[id]
	kept := func(k string) bool { return !inSet(drops, k) }
	for _, s := range sets {
		k, v, found := strings.Cut(s, "=")
		if !found {
			v = k
		}
		if !kept(k) {
			continue
		}
		if b.Metadata == nil {
			b.Metadata = map[string]any{}
		}
		b.Metadata[k] = coerce(v)
	}
	for _, k := range unsets {
		if kept(k) {
			delete(b.Metadata, k)
		}
	}
	if asgSet && kept("assignee") {
		b.Assignee = asg
	}
	if status != "" && kept("status") {
		st := status
		b.Status = &st
	}
	if noteSet {
		old := b.NotesString()
		if old != "" {
			old += "\n"
		}
		b.Notes = old + note
	}
	if descSet && kept("description") {
		if f.Descriptions == nil {
			f.Descriptions = map[string]string{}
		}
		f.Descriptions[id] = desc
	}
	return out, nil
}
