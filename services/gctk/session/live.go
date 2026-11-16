// Package session is the session domain: what the pack asks of Gas City's
// sessions. Gas City owns every session and its record, so the domain owns no
// key and writes no bead. It answers which identities a live session answers
// to, over one read of `gc session list --json`, and which identities a bead
// names its owner by. Its look, `gctk session progress`, finds each pool seat
// whose pane prints while it has written nothing for three hours, and records
// what it found as one Gas City event, gc-toolkit.seat-progress.stalled
// (specs/tk-1tfzr71.158/design.md, sections 2 and 10).
package session

import (
	"errors"
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// deadStates are the states of a session that has ended: closed, archived,
// and failed-create, a create that rolled back. A state not named here is
// owned, by a running session or by the controller that still manages it.
var deadStates = []string{"archived", "closed", "failed-create"}

// ErrNoSessions is the error of a session list that lists no session. In a
// running city the controller's own sessions are always listed, so an empty
// list is a read that went wrong, and judged as one it would read every owner
// as dead.
var ErrNoSessions = errors.New("gc session list listed no session, so no owner can be judged live or dead")

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

// identities is each name a bead can give the session by: its id, its name,
// its runtime session name, its alias and its agent name.
func identities(s gascity.Session) []string {
	var out []string
	for _, v := range []string{s.ID, s.Name, s.SessionName, s.Alias, s.AgentName} {
		if v != "" {
			out = append(out, v)
		}
	}
	return out
}

func dead(state string) bool { return slices.Contains(deadStates, state) }

// bare is an identity with its rig qualifier removed: its last path segment.
func bare(identity string) string { return identity[strings.LastIndex(identity, "/")+1:] }

// Answers reports whether a live session answers to any identity named. An
// identity a session carries exactly is answered by the sessions that carry
// it, and is live when any of them is not in a dead state. An identity no
// session carries exactly is matched by its last path segment, so a
// rig-qualified assignee is answered by the bare alias its session registered.
// That match is looser and can make two sessions share an identity, so it too
// resolves toward life: any live match answers. The rule is the liveness
// lookup of the witness's patrol (formulas/mol-witness-patrol.toml), over every
// identity the owner goes by.
func (l *Live) Answers(names ...string) bool {
	for _, name := range names {
		if name != "" && l.answers(name) {
			return true
		}
	}
	return false
}

func (l *Live) answers(name string) bool {
	exact, loose := false, false
	for _, s := range l.sessions {
		ids := identities(s)
		switch {
		case slices.Contains(ids, name):
			exact = true
			if !dead(s.State) {
				return true
			}
		case !loose && !dead(s.State) && slices.ContainsFunc(ids, func(id string) bool { return bare(id) == bare(name) }):
			loose = true
		}
	}
	return !exact && loose
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

// Owner is the identities a bead names its holder by: the session that claimed
// it, its assignee, and the session's runtime name. Which of them a bead
// carries depends on how far it has got, and a release by Gas City clears the
// assignee and leaves the other two, so a released bead still names the
// session that held it.
type Owner struct {
	SessionID   string
	Assignee    string
	SessionName string
}

// Names is each identity the owner carries, in that order.
func (o Owner) Names() []string {
	var out []string
	for _, v := range []string{o.SessionID, o.Assignee, o.SessionName} {
		if v != "" {
			out = append(out, v)
		}
	}
	return out
}

// OwnerOf is the owner r names. A key whose value does not read is an error.
func OwnerOf(r *ledger.Record) (Owner, error) {
	o := Owner{Assignee: r.Assignee()}
	var err error
	if o.SessionID, _, err = sessionIDKey.Get(r); err != nil {
		return Owner{}, err
	}
	if o.SessionName, _, err = sessionNameKey.Get(r); err != nil {
		return Owner{}, err
	}
	return o, nil
}
