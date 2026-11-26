// Package disposition answers which open bead carries a bead's work now. The
// disposition writer, assets/scripts/bead-rehome.sh, closes a duplicate, a
// folded, re-homed or not-needed bead and a bead fixed upstream with bd's own
// duplicates or supersedes edge onto the bead it names, and that bead can close
// onward the same way. The pre-existing mark of package rig and the failure
// tracker lookup of assets/scripts/preexisting-failure.sh follow that chain to
// find the bead a failure moved to.
package disposition

import (
	"fmt"
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// openStatuses are the statuses of a bead that still carries its work. A
// closed bead carries it only through the bead its edge names, and a bead in
// any other status, such as a tombstone, carries none.
var openStatuses = []string{"open", "in_progress", "blocked", "deferred", "hooked", "pinned"}

// Open reports whether status is one a bead that still carries its work holds.
func Open(status string) bool { return slices.Contains(openStatuses, status) }

// MaxEdges is the most edges a chain is followed through. A real chain is a
// fold or two long, so a longer one is a fault in the edges, and it is read as
// naming no bead that carries the work rather than walked further.
const MaxEdges = 20

// Carried is what a walk from one bead found.
type Carried struct {
	// By is the open bead that carries the work: the bead itself while it is
	// open, else the open bead its chain reaches, and "" when none does.
	By string
	// Warning says why a chain that names a further bead ended with none: an
	// edge onto a bead the store does not hold, a chain that loops, or one
	// past MaxEdges. It is "" for every other end.
	Warning string
}

// Carrier reads the open bead that carries id's work. Each bead on the chain is
// read through its listing row, which carries an edge onto a bead in another
// store, and its first duplicates or supersedes edge names the next bead. The
// chain ends with no bead at a bead that closed naming no successor, because
// the work ended there, and at a not-needed close, whose edge names the
// evidence for that ruling rather than a bead that carries the work. Such a
// close carries `not needed, per <successor> ` at the start of its close
// reason, or `: not needed, per <successor> in ` in its notes, as the
// disposition writer records it in a note when the edge was added after the
// close. A bead the store does not hold ends the chain too, and so do a loop
// and a chain past MaxEdges. A read that fails returns its error, which is
// never "none".
func Carrier(l *ledger.Ledger, id string) (Carried, error) {
	start, cur, prev := id, id, ""
	seen := map[string]bool{}
	for hops := 0; ; hops++ {
		if seen[cur] {
			return Carried{Warning: fmt.Sprintf("the chain of disposition edges from %s loops back to %s, "+
				"so it names no open bead that carries %s's work", start, cur, start)}, nil
		}
		if hops > MaxEdges {
			return Carried{Warning: fmt.Sprintf("the chain of disposition edges from %s runs past %d edges "+
				"without reaching an open bead, so it is read as naming none that carries %s's work", start, MaxEdges, start)}, nil
		}
		seen[cur] = true
		rec, held, err := read(l, cur)
		if err != nil {
			return Carried{}, err
		}
		if !held {
			if prev == "" {
				return Carried{}, nil
			}
			return Carried{Warning: fmt.Sprintf("%s names %s as its successor, but the store holds no such bead, "+
				"so the chain from %s names no open bead that carries its work", prev, cur, start)}, nil
		}
		if Open(rec.Status()) {
			return Carried{By: cur}, nil
		}
		next, err := successor(rec)
		if err != nil {
			return Carried{}, err
		}
		if next == "" || strings.HasPrefix(rec.CloseReason(), "not needed, per "+next+" ") ||
			strings.Contains(rec.Notes(), ": not needed, per "+next+" in ") {
			return Carried{}, nil
		}
		prev, cur = cur, next
	}
}

// read reads id's listing row, closed or not, and whether the store holds it.
func read(l *ledger.Ledger, id string) (*ledger.Record, bool, error) {
	recs, err := l.Find(ledger.ByID(id).WithClosed())
	if err != nil {
		return nil, false, fmt.Errorf("%s did not read: %w", id, err)
	}
	for _, r := range recs {
		if r.ID == id {
			return r, true, nil
		}
	}
	return nil, false, nil
}

// successor is the bead rec's first duplicates or supersedes edge names, "" when
// it has none.
func successor(rec *ledger.Record) (string, error) {
	edges, err := rec.Edges()
	if err != nil {
		return "", fmt.Errorf("%s's edges did not decode: %w", rec.ID, err)
	}
	for _, e := range edges {
		if (e.Type == "duplicates" || e.Type == "supersedes") && e.ID != "" {
			return e.ID, nil
		}
	}
	return "", nil
}
