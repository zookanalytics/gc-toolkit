// Package session is the session domain: what the pack asks of Gas City's
// sessions. Gas City owns every session and its record, so the domain owns no
// key and writes no bead. It holds one read of `gc session list --json`, and
// the session and assignee a bead names its owner by. Its look,
// `gctk session progress`, finds each pool seat whose pane prints while it has
// written nothing for three hours, and records what it found as one Gas City
// event, gc-toolkit.seat-progress.stalled (specs/tk-1tfzr71.158/design.md,
// sections 2 and 10).
package session

import (
	"errors"
	"slices"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// ErrNoSessions is the error of a session list that lists no session. In a
// running city the controller's own sessions are always listed, so an empty
// list is a read that went wrong, and taken as the city's sessions it would
// leave every seat unjudged.
var ErrNoSessions = errors.New("gc session list listed no session, so no seat can be judged")

// Live is the city's sessions as one read of the session list gave them, every
// session that has not closed.
type Live struct {
	sessions []gascity.Session
}

// Read takes one read of the session list. A list with no session is
// ErrNoSessions.
func Read(list []gascity.Session) (*Live, error) {
	if len(list) == 0 {
		return nil, ErrNoSessions
	}
	return &Live{sessions: slices.Clone(list)}, nil
}

// Session is the listed session whose id is id.
func (l *Live) Session(id string) (gascity.Session, bool) {
	for _, s := range l.sessions {
		if s.ID == id {
			return s, true
		}
	}
	return gascity.Session{}, false
}

// Owner is what a bead names its holder by: the session that claimed it, and
// its assignee.
type Owner struct {
	SessionID string
	Assignee  string
}

// OwnerOf is the owner r names. A key whose value does not read is an error.
func OwnerOf(r *ledger.Record) (Owner, error) {
	o := Owner{Assignee: r.Assignee()}
	var err error
	if o.SessionID, _, err = sessionIDKey.Get(r); err != nil {
		return Owner{}, err
	}
	return o, nil
}
