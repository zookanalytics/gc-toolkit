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
// non-zero has failed, and nothing reads a write back to confirm it. A Snapshot
// is one pass's read of the beads a question needs.
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
	file   *filing
	err    error
}

// filing is what a write that files a new bead adds: its issue type, its
// description, the beads it blocks and the bead it was found from.
type filing struct {
	issueType, description string
	blocks                 []string
	from                   string
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
// unless commit is empty, the commit that carries the work. The keys are Gas
// City's (gc.work_outcome and gc.work_commit, lifecycle/lifecycle.toml,
// [metadata.runtime_owned]), whose work-record gate reads them as a plain task
// bead closes, so no domain declares them, and the act that closes such a bead
// sets them here.
func (w *Write) WorkRecord(outcome, commit string) {
	w.set("gc.work_outcome", outcome)
	if commit != "" {
		w.set("gc.work_commit", commit)
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

// Commit makes w as one update, whose exit decides whether it landed. A write a
// Set refused, a write that changes nothing and an update that exits non-zero
// all fail, and nothing reads the write back. A write its guard refused fails
// with an error that is ErrGuard.
func (l *Ledger) Commit(w *Write) error {
	if w.err != nil {
		return w.err
	}
	if w.file != nil {
		return fmt.Errorf("ledger: a write that files a new bead lands through Filed")
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

// File starts an act that files a new bead titled title, of issue type typ.
// Its keys, its description and its edges ride the one create Filed makes.
func (l *Ledger) File(title, typ string) *Write {
	return &Write{title: title, file: &filing{issueType: typ}}
}

// Description gives the bead a write files its description.
func (w *Write) Description(text string) {
	if w.file == nil {
		w.fail(errors.New("ledger: a description rides only a write that files a new bead"))
		return
	}
	w.file.description = text
}

// Blocks makes the bead a write files block id: id gains a blocks edge onto it,
// a wait that holds id until the new bead closes.
func (w *Write) Blocks(id string) {
	if w.file == nil {
		w.fail(errors.New("ledger: a blocks edge rides only a write that files a new bead"))
		return
	}
	w.file.blocks = append(w.file.blocks, id)
}

// From records the bead a write files was found from, as its discovered-from
// edge, which is no wait and holds nothing.
func (w *Write) From(id string) {
	if w.file == nil {
		w.fail(errors.New("ledger: a discovered-from edge rides only a write that files a new bead"))
		return
	}
	w.file.from = id
}

// Filed makes w, an act File started, as one create, and returns the id the
// store gave the new bead. It gives the bead no parent, assignee or route.
// Each bead the new one blocks is read first in the ledger's store, and a bead
// the store does not hold refuses the create, because bd reports success for
// an edge onto an id its store does not hold, and the edge holds nothing. A
// create that fails may still have landed (gcbd.Store.Create), so a caller
// that retries finds the bead an earlier attempt filed before it files again.
func (l *Ledger) Filed(w *Write) (string, error) {
	if w.err != nil {
		return "", w.err
	}
	f := w.file
	switch {
	case f == nil:
		return "", errors.New("ledger: a write to a bead that exists lands through Commit")
	case w.title == "":
		return "", errors.New("ledger: a new bead needs a title")
	case len(w.unsets) > 0 || w.status != "" || w.note != "" || w.guard != nil:
		return "", errors.New("ledger: a new bead's create carries its keys, description and edges alone")
	}
	if len(f.blocks) > 0 {
		rows, err := l.store.Rows(f.blocks)
		if err != nil {
			return "", fmt.Errorf("ledger: the beads a new bead blocks did not read, so nothing was filed: %w", err)
		}
		held := map[string]bool{}
		for _, r := range rows {
			held[r.ID] = true
		}
		for _, id := range f.blocks {
			if !held[id] {
				return "", fmt.Errorf("ledger: the store holds no %s for a new bead to block, so nothing was filed", id)
			}
		}
	}
	args := []string{w.title, "-t", f.issueType}
	if f.description != "" {
		args = append(args, "--description", f.description)
	}
	if len(w.sets) > 0 {
		meta := make(map[string]string, len(w.sets))
		for _, kv := range w.sets {
			k, v, _ := strings.Cut(kv, "=")
			meta[k] = v
		}
		raw, err := json.Marshal(meta)
		if err != nil {
			return "", fmt.Errorf("ledger: a new bead's keys did not encode: %w", err)
		}
		args = append(args, "--metadata", string(raw))
	}
	var deps []string
	for _, id := range f.blocks {
		deps = append(deps, "blocks:"+id)
	}
	if f.from != "" {
		deps = append(deps, "discovered-from:"+f.from)
	}
	if len(deps) > 0 {
		args = append(args, "--deps", strings.Join(deps, ","))
	}
	id, err := l.store.Create(args...)
	if err != nil {
		return "", fmt.Errorf("ledger: the create may not have landed: %w", err)
	}
	return id, nil
}
