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
// update` carrying every key the act sets, so the act lands whole or not at all,
// and a write that exits non-zero has failed. CommitBeforeAct also reads the
// written keys back from the store itself before an act that cannot be undone
// rests on them, and refuses the act on a mismatch. A Snapshot is one pass's
// read of the beads a question needs.
//
// The ledger is the one package above the store adapter that reaches the
// store, through gcbd.Store.
package ledger

import (
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
// adapter to the store gc resolves for this process, so every read the ledger
// makes answers from that one store: gc routes an unpinned read that names a
// bead to the store holding that bead. A store gc names none of returns the
// adapter's *ReadError.
func Open(db string) (*Ledger, error) {
	c := gcbd.New()
	if db == "" {
		where, err := c.Where()
		if err != nil {
			return nil, err
		}
		db = where
	}
	return New(c.In(db)), nil
}

// Write is one act on one bead: every key it sets or clears, made in one
// update.
type Write struct {
	id     string
	sets   []string // key=value, in the order set
	unsets []string
	wrote  map[string]string // what each set key must read back as
	err    error
}

// Write starts an act on the bead.
func (l *Ledger) Write(id string) *Write {
	return &Write{id: id, wrote: map[string]string{}}
}

func (w *Write) fail(err error) {
	if w.err == nil {
		w.err = err
	}
}

func (w *Write) set(name, text string) {
	w.sets = append(w.sets, name+"="+text)
	w.wrote[name] = text
}

func (w *Write) unset(name string) {
	if !slices.Contains(w.unsets, name) {
		w.unsets = append(w.unsets, name)
	}
}

// args is the update's arguments: every set, then every removal.
func (w *Write) args() []string {
	var args []string
	for _, s := range w.sets {
		args = append(args, "--set-metadata", s)
	}
	for _, u := range w.unsets {
		args = append(args, "--unset-metadata", u)
	}
	return args
}

// ErrMismatch is a write that read back other than written, so the act resting
// on it is refused.
var ErrMismatch = errors.New("ledger: the write did not read back as written")

// Commit makes w as one update. A write a Set refused, an empty write and an
// update that exits non-zero all fail, and nothing reads the write back: bd's
// exit status is honest for an ordinary write.
func (l *Ledger) Commit(w *Write) error {
	if w.err != nil {
		return w.err
	}
	args := w.args()
	if len(args) == 0 {
		return fmt.Errorf("ledger: a write to %s carries no key", w.id)
	}
	if out, err := l.store.Update(w.id, args...); err != nil {
		if out = strings.TrimSpace(out); out != "" {
			return fmt.Errorf("ledger: the write to %s did not land (%v): %s", w.id, err, out)
		}
		return fmt.Errorf("ledger: the write to %s did not land: %v", w.id, err)
	}
	return nil
}

// CommitBeforeAct makes w, then reads the bead back from the store itself and
// compares every key w set or cleared, for an act that cannot be undone, such
// as a close, a push, a dismissal or a sling, that rests on the write. A
// mismatch, or a read-back that does not answer, returns an error wrapping
// ErrMismatch, and the caller does not act.
func (l *Ledger) CommitBeforeAct(w *Write) error {
	if err := l.Commit(w); err != nil {
		return err
	}
	rows, err := l.store.Rows([]string{w.id})
	if err != nil {
		return fmt.Errorf("%w: %s could not be read back: %v", ErrMismatch, w.id, err)
	}
	if len(rows) != 1 || rows[0].ID != w.id {
		return fmt.Errorf("%w: %s did not read back", ErrMismatch, w.id)
	}
	r := &Record{ID: w.id, row: &rows[0]}
	for name, text := range w.wrote {
		if got, held := r.value(name); !held || got != text {
			return fmt.Errorf("%w: %s's %s reads %q", ErrMismatch, w.id, name, got)
		}
	}
	for _, name := range w.unsets {
		if got, held := r.value(name); held {
			return fmt.Errorf("%w: %s still holds %s=%q", ErrMismatch, w.id, name, got)
		}
	}
	return nil
}
