// Package ledger is the one module that turns bead rows into typed records and
// back (docs/gctk-architecture.md, "The ledger"). Nothing outside it parses a
// metadata value or spells a key's name.
//
// A domain declares each key it owns in its own package, with Declare, as an
// unexported Key that names the key, its codec and its legacy aliases, and reads
// and writes the key only through that value, so the compiler refuses any other
// package that tries. A key no domain owns yet stays in
// lifecycle/lifecycle.toml, and a domain that must read one declares it
// ReadOnly. services/gctk/key-registry.json lists every declaration, generated
// from them, and a test fails when it is stale.
//
// A verb's change of state is one Write, which Commit makes as one `gc bd
// update` carrying every key the act sets, and the title when the act gives
// the bead one, so the act lands whole or not at all.
// The update's exit decides whether the write landed: a write that exits
// non-zero has failed, and nothing reads a write back to confirm it. A new
// bead is one Filing, which Create makes as one `gc bd create` carrying its
// keys and its edges. A Snapshot is one pass's read of the beads a question
// needs.
//
// The ledger is the one package above the store adapter that reaches the
// store, through gcbd.Store.
package ledger

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
)

// Ledger reads and writes beads through a store.
type Ledger struct {
	store gcbd.Store
}

// New returns a ledger over store: the city's gcbd.Client, or a fake.
func New(store gcbd.Store) *Ledger { return &Ledger{store: store} }

// Open returns a ledger over the city's store at db, a store's .beads
// directory, through the store adapter pinned there. With db empty it pins the
// adapter to the store gc routes a read of the first of ids to
// ([gcbd.Client.Route]), so every read the ledger makes answers from that one
// store: gc routes an unpinned read that names a bead to the store holding
// that bead, and one that names none to the store it resolves here. A store gc
// names none of returns the adapter's *ReadError.
func Open(db string, ids ...string) (*Ledger, error) {
	return open(gcbd.New(), db, ids...)
}

// OpenContext is Open for a reader with a deadline: every call the ledger makes
// to the store ends when ctx does, the processes it started killed with it
// ([gcbd.Client.WithContext]), and a read it ends returns the adapter's
// *ReadError.
func OpenContext(ctx context.Context, db string, ids ...string) (*Ledger, error) {
	return open(gcbd.New().WithContext(ctx), db, ids...)
}

func open(c *gcbd.Client, db string, ids ...string) (*Ledger, error) {
	if db == "" {
		routed, err := c.Route(ids...)
		if err != nil {
			return nil, err
		}
		db = routed
	}
	return New(c.In(db)), nil
}

// ErrGuard is the error of a write whose guard no longer held: the bead had
// left the status or the assignee the write was guarded on, so bd wrote
// nothing (gcbd.ErrGuard). A domain tells it from any other failure with
// errors.Is.
var ErrGuard = gcbd.ErrGuard

// Write is one act on one bead: every key it sets or clears, the title it gives
// the bead, the status it moves the bead to, the note it appends and the guard
// it lands under, made in one update.
type Write struct {
	id     string
	title  string
	sets   []string // key=value, in the order set
	unsets []string
	status string
	note   string
	guard  *guard
	err    error
}

// guard is the status and assignee a write lands under.
type guard struct{ status, assignee string }

// Write starts an act on the bead.
func (l *Ledger) Write(id string) *Write {
	return &Write{id: id}
}

func (w *Write) fail(err error) {
	if w.err == nil {
		w.err = err
	}
}

func (w *Write) set(name, text string) {
	w.sets = append(w.sets, name+"="+text)
}

func (w *Write) unset(name string) {
	if !slices.Contains(w.unsets, name) {
		w.unsets = append(w.unsets, name)
	}
}

// Title gives the bead title in the same write. The title is the row's own
// field, which no key declares, so the act that sets it says what it means.
func (w *Write) Title(title string) { w.title = title }

// Status moves the bead to status in the same write. A move into closed is bd's
// checked close, which bd refuses while a live blocker or an open child holds
// the bead.
func (w *Write) Status(status string) { w.status = status }

// Note appends text to the bead's notes in the same write, so the act and its
// record land together or not at all. A later Note replaces an earlier one.
func (w *Write) Note(text string) { w.note = text }

// WorkRecord gives the bead the runtime's work record in the same write: its
// outcome, which reads shipped for work that landed and no-op for none, and,
// unless commit is empty, the commit that carries the work and, unless branch
// is empty, the branch that commit is on. The keys are Gas City's
// (gc.work_outcome, gc.work_commit and gc.work_branch, lifecycle/lifecycle.toml,
// [metadata.runtime_owned]), whose work-record gate reads them as a plain task
// bead closes, so no domain declares them, and the act that closes such a bead
// sets them here. Under GC_WORK_RECORD_ENFORCE the gate refuses a close that
// names no outcome, and a shipped one that names no commit or no branch, or a
// commit the branch does not reach.
func (w *Write) WorkRecord(outcome, commit, branch string) {
	w.set("gc.work_outcome", outcome)
	if commit != "" {
		w.set("gc.work_commit", commit)
		if branch != "" {
			w.set("gc.work_branch", branch)
		}
	}
}

// Guard makes the write land only while the bead still has status and assignee,
// "" for unassigned, which bd checks in the write's own transaction. A write
// whose guard no longer holds writes nothing, and Commit returns an error that
// is ErrGuard.
func (w *Write) Guard(status, assignee string) { w.guard = &guard{status: status, assignee: assignee} }

// args is the update's arguments: the guard, the status, the title, every set,
// every removal, then the note.
func (w *Write) args() []string {
	var args []string
	if w.guard != nil {
		args = append(args, "--if-status="+w.guard.status, "--if-assignee="+w.guard.assignee)
	}
	if w.status != "" {
		args = append(args, "--status="+w.status)
	}
	if w.title != "" {
		args = append(args, "--title", w.title)
	}
	for _, s := range w.sets {
		args = append(args, "--set-metadata", s)
	}
	for _, u := range w.unsets {
		args = append(args, "--unset-metadata", u)
	}
	if w.note != "" {
		args = append(args, "--append-notes", w.note)
	}
	return args
}

// Filing is the filing of one new bead: its title, its type, its description,
// every key it carries, the beads it blocks, the beads it waits on and the bead
// it was found from, made in one create, so the bead lands with its keys and
// its edges or not at all.
type Filing struct {
	title, typ, description string
	keys                    map[string]string
	blocks, blockedBy       []string
	from                    string
	err                     error
}

// File starts the filing of a bead titled title, of type issueType.
func (l *Ledger) File(title, issueType string) *Filing {
	return &Filing{title: title, typ: issueType, keys: map[string]string{}}
}

// Description gives the new bead its description.
func (f *Filing) Description(text string) { f.description = text }

// Blocks makes the new bead block each bead named, by a blocks edge from that
// bead onto it, written in the create itself.
func (f *Filing) Blocks(ids ...string) { f.blocks = append(f.blocks, ids...) }

// BlockedBy makes the new bead wait on each bead named, by its own blocks edge
// onto that bead, written in the create itself, so no read finds the new bead
// without its wait. An edge onto a bead of another store holds nothing, so a
// caller names only beads the store holds.
func (f *Filing) BlockedBy(ids ...string) { f.blockedBy = append(f.blockedBy, ids...) }

// From records the bead the new one was found from, by the new bead's own
// discovered-from edge onto it, which is no wait and holds nothing.
func (f *Filing) From(id string) { f.from = id }

func (f *Filing) set(name, text string) { f.keys[name] = text }

func (f *Filing) fail(err error) {
	if f.err == nil {
		f.err = err
	}
}

// args is the create's arguments: the type, the description, the keys as one
// JSON object, then the beads the new one blocks, the beads it waits on and the
// bead it was found from, as one --deps list.
func (f *Filing) args() ([]string, error) {
	args := []string{"-t", f.typ}
	if f.description != "" {
		args = append(args, "--description", f.description)
	}
	if len(f.keys) > 0 {
		raw, err := json.Marshal(f.keys)
		if err != nil {
			return nil, err
		}
		args = append(args, "--metadata", string(raw))
	}
	deps := make([]string, 0, len(f.blocks)+len(f.blockedBy)+1)
	for _, id := range f.blocks {
		deps = append(deps, "blocks:"+id)
	}
	for _, id := range f.blockedBy {
		deps = append(deps, "blocked-by:"+id)
	}
	if f.from != "" {
		deps = append(deps, "discovered-from:"+f.from)
	}
	if len(deps) > 0 {
		args = append(args, "--deps", strings.Join(deps, ","))
	}
	return args, nil
}

// Create files f as one create and returns the new bead's id. A filing a Set
// refused, or one with no title or type, files nothing. A create the store
// failed may still have filed the bead, as gcbd.Store.Create says, so its
// error says that whether it did is unknown, and the caller finds the bead
// before it files again.
func (l *Ledger) Create(f *Filing) (string, error) {
	if f.err != nil {
		return "", f.err
	}
	if strings.TrimSpace(f.title) == "" || f.typ == "" {
		return "", errors.New("ledger: a filing names no title or no type")
	}
	args, err := f.args()
	if err != nil {
		return "", fmt.Errorf("ledger: the filing of %q did not encode: %w", f.title, err)
	}
	id, err := l.store.Create(f.title, args...)
	if err != nil {
		return "", fmt.Errorf("ledger: the filing of %q may not have landed: %w", f.title, err)
	}
	return id, nil
}

// Commit makes w as one update, whose exit decides whether it landed. A write a
// Set refused, a write that changes nothing and an update that exits non-zero
// all fail, and nothing reads the write back. A write its guard refused fails
// with an error that is ErrGuard.
func (l *Ledger) Commit(w *Write) error {
	if w.err != nil {
		return w.err
	}
	if len(w.sets)+len(w.unsets) == 0 && w.status == "" && w.title == "" && w.note == "" {
		return fmt.Errorf("ledger: a write to %s carries no key", w.id)
	}
	if out, err := l.store.Update(w.id, w.args()...); err != nil {
		if out = strings.TrimSpace(out); out != "" {
			return fmt.Errorf("ledger: the write to %s did not land (%w): %s", w.id, err, out)
		}
		return fmt.Errorf("ledger: the write to %s did not land: %w", w.id, err)
	}
	return nil
}
