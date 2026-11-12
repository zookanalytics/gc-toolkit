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
// update` carrying every key the act sets, so the act lands whole or not at all.
// The update's exit decides whether the write landed: a write that exits
// non-zero has failed, and nothing reads a write back to confirm it. A Snapshot
// is one pass's read of the beads a question needs.
//
// The ledger is the one package above the store adapter that reaches the
// store, through gcbd.Store.
package ledger

import (
	"context"
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

// Write is one act on one bead: every key it sets or clears, the status it
// moves the bead to, the note it appends and the guard it lands under, made in
// one update.
type Write struct {
	id     string
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

// Status moves the bead to status in the same write. A move into closed is bd's
// checked close, which bd refuses while a live blocker or an open child holds
// the bead.
func (w *Write) Status(status string) { w.status = status }

// Note appends text to the bead's notes in the same write. A second call
// replaces the first.
func (w *Write) Note(text string) { w.note = text }

// Guard makes the write land only while the bead still has status and assignee,
// "" for unassigned, which bd checks in the write's own transaction. A write
// whose guard no longer holds writes nothing, and Commit returns an error that
// is ErrGuard.
func (w *Write) Guard(status, assignee string) { w.guard = &guard{status: status, assignee: assignee} }

// args is the update's arguments: the guard, the status, every set, every
// removal, then the note.
func (w *Write) args() []string {
	var args []string
	if w.guard != nil {
		args = append(args, "--if-status="+w.guard.status, "--if-assignee="+w.guard.assignee)
	}
	if w.status != "" {
		args = append(args, "--status="+w.status)
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
	if len(w.sets)+len(w.unsets) == 0 && w.status == "" && w.note == "" {
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
