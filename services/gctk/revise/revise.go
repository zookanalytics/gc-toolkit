// Package revise is a revision of work in flight: a change to what the work on
// a bead should do, sent to the sessions doing that work while they run, which
// `gctk bead revise` makes.
//
// A bead whose work runs on a poured workflow reads open and unassigned while
// the workflow's steps are claimed, so the bead names no session, and the run
// reads the bead's notes only where its formula's steps read them. A revision
// appends the change to the bead's notes, where whoever takes the work next
// reads it, then finds each session working the bead now: the bead's own
// assignee, and the holder of each member of each live run that works the
// bead, through the run link waits holds. It sends each one the revision with
// Gas City's immediate nudge, which Gas City delivers into a running turn
// where the session's agent takes typed input mid-turn, and otherwise at the
// turn's end.
package revise

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// NudgeMax is the most bytes a revision's nudge carries. Gas City types a
// nudge into the session's input box, and Claude Code takes typed input of
// more than 800 characters as a paste, which reaches its model as pasted
// material rather than as its user's words. So the nudge stays one typed
// message, and the note holds the revision whole.
const NudgeMax = 800

// Request is one revision of the work on Bead: Text, the change, as the note
// records it.
type Request struct {
	Bead, Text string
}

// City is Gas City as a revision reaches it: the session list that names the
// sessions working the bead, and the immediate nudge that sends each the
// revision.
type City interface {
	NudgeNow(session, message, bead string) gascity.Result
	Sessions(ctx context.Context) ([]gascity.Session, error)
}

// Revisions is the revision's verb over one store.
type Revisions struct {
	Ledger *ledger.Ledger
	City   City
	// By names who revises the work, in the note and the nudge, host when it
	// names no one.
	By string
	// Self is the names this session goes by, its session name, its session id
	// and its alias: a session working the bead under one of them is this one,
	// which has the revision already.
	Self []string
	// Now is the clock the note's time is read from.
	Now func() time.Time
}

// Refusal is a revision refused before anything was written.
type Refusal struct{ Msg string }

func (e *Refusal) Error() string { return e.Msg }

func refuse(format string, args ...any) error {
	return &Refusal{Msg: fmt.Sprintf(format, args...)}
}

// Refused reports whether err is a revision refused before anything was
// written.
func Refused(err error) bool {
	var r *Refusal
	return errors.As(err, &r)
}

// Unsent is a revision whose note landed, but which may not have reached
// every session working the bead: who works it did not read, or a nudge did
// not land.
type Unsent struct{ Msg string }

func (e *Unsent) Error() string { return e.Msg }

// IsUnsent reports whether err is a revision whose note landed and whose
// nudges did not all land.
func IsUnsent(err error) bool {
	var u *Unsent
	return errors.As(err, &u)
}

// Revise appends req's revision to the bead's notes, then nudges each session
// working the bead with it, and returns one line for the note and one for each
// session it decided on. A *Refusal wrote nothing. An *Unsent landed the note,
// and its lines are returned with it. Any other error wrote nothing.
func (v *Revisions) Revise(req Request) ([]string, error) {
	bead, text := strings.TrimSpace(req.Bead), strings.TrimSpace(req.Text)
	if text == "" {
		return nil, refuse("the revision is empty, so there is nothing to send %s's work. Nothing was written", bead)
	}
	row, err := v.read(bead)
	if err != nil {
		return nil, fmt.Errorf("%s did not read (%v), so nothing was written", bead, err)
	}
	if row == nil {
		return nil, refuse("the store does not hold %s. Nothing was written", bead)
	}
	if row.Status() == "closed" {
		return nil, refuse("%s is closed, so no work on it runs to take a revision. Nothing was written. File what the revision asks for as new work", bead)
	}
	w := v.Ledger.Write(bead)
	w.Note(fmt.Sprintf("## Revised in flight (%s, by %s)\n%s", v.Now().UTC().Format(time.RFC3339), v.by(), text))
	if err := v.Ledger.Commit(w); err != nil {
		return nil, fmt.Errorf("the revision did not land on %s's notes (%v), so no session was sent it", bead, err)
	}
	lines := []string{"revised " + bead + ": the revision is on its notes"}
	byHand := fmt.Sprintf("gc session nudge <session> --delivery immediate --reference-bead %s \"<the revision, and that %s's notes hold it>\"", bead, bead)

	holders, err := v.holders(row)
	if err != nil {
		return lines, &Unsent{Msg: fmt.Sprintf("the revision is on %s's notes, but who works %s now did not read (%v), so no session was sent it. Send it to each session working %s: %s", bead, bead, err, bead, byHand)}
	}
	if len(holders) == 0 {
		return append(lines, "no session works "+bead+" now, so the notes are all it needs: whoever takes its work next reads them"), nil
	}
	list, err := v.City.Sessions(context.Background())
	if err != nil {
		return lines, &Unsent{Msg: fmt.Sprintf("the revision is on %s's notes, but gc session list did not read (%v), so no session was sent it. Send it to each session working %s, which these name (%s): %s", bead, err, bead, strings.Join(holders, ", "), byHand)}
	}
	var sent, failed []string
	for _, h := range holders {
		if v.mine(h) {
			lines = append(lines, "kept "+h+": this session holds work on "+bead+", and has the revision")
			continue
		}
		named := gascity.Named(list, h)
		if len(named) == 0 {
			lines = append(lines, "skipped "+h+": the session list names no session for it, so its work goes back to its pool, and whoever takes the work next reads the notes")
			continue
		}
		for _, s := range named {
			id := s.Handle()
			switch {
			case slices.Contains(sent, id), slices.Contains(failed, id):
			case v.mine(id):
				lines = append(lines, "kept "+id+": this session holds work on "+bead+", and has the revision")
			case s.Provider == "":
				lines = append(lines, "skipped "+id+": it runs no agent to read a nudge")
			default:
				res := v.City.NudgeNow(id, v.message(bead, text), bead)
				if f := res.Failure(); f != "" {
					failed = append(failed, id)
					lines = append(lines, "not sent to "+id+": "+f)
					continue
				}
				sent = append(sent, id)
				lines = append(lines, "sent to "+id+": "+res.Tail())
			}
		}
	}
	if len(failed) > 0 {
		return lines, &Unsent{Msg: fmt.Sprintf("the revision is on %s's notes, but the nudge to %s did not land, so that work may build on without it. Send it again: %s", bead, strings.Join(failed, ", "), byHand)}
	}
	return lines, nil
}

// message is the nudge that sends a session the revision: who revised the
// work, where its notes hold the revision whole, and the revision on one line,
// cut to fit within NudgeMax.
func (v *Revisions) message(bead, text string) string {
	head := fmt.Sprintf("%s revised what your work on %s should do. Its notes hold the revision in full (gc bd show %s), so read them and build on it from here. The revision: ", v.by(), bead, bead)
	body := strings.Join(strings.Fields(text), " ")
	if len(head)+len(body) <= NudgeMax {
		return head + body
	}
	const more = " ..."
	cut := max(NudgeMax-len(head)-len(more), 0)
	for cut > 0 && !utf8.RuneStart(body[cut]) {
		cut--
	}
	return head + strings.TrimSpace(body[:cut]) + more
}

// holders is each name a session holds the bead's work under, once each: the
// bead's own assignee, then the holder of each member, not closed, of each
// live run that works the bead.
func (v *Revisions) holders(row *ledger.Record) ([]string, error) {
	var out []string
	add := func(h string) {
		if h != "" && !slices.Contains(out, h) {
			out = append(out, h)
		}
	}
	add(row.Assignee())
	up, err := v.Ledger.Dependents(row.ID, "tracks")
	if err != nil {
		return nil, err
	}
	runs, err := waits.LiveRunsOf(v.Ledger, row.ID, up)
	if err != nil {
		return nil, err
	}
	for _, run := range runs {
		held, err := waits.RunHolders(v.Ledger, run.Root)
		if err != nil {
			return nil, err
		}
		for _, h := range held {
			add(h)
		}
	}
	return out, nil
}

// read is the bead's row, closed or not, nil when its store does not hold it.
func (v *Revisions) read(id string) (*ledger.Record, error) {
	rows, err := v.Ledger.Find(ledger.ByID(id).WithClosed())
	if err != nil {
		return nil, err
	}
	for _, rec := range rows {
		if rec.ID == id {
			return rec, nil
		}
	}
	return nil, nil
}

// mine reports whether name is one this session goes by.
func (v *Revisions) mine(name string) bool {
	return name != "" && slices.Contains(v.Self, name)
}

func (v *Revisions) by() string {
	if b := strings.TrimSpace(v.By); b != "" {
		return b
	}
	return "host"
}
