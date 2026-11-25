// Package note is a note on a bead, which `gctk bead note` writes: the one way
// an agent puts a note on a bead.
//
// The note lands on the bead's notes as its writer wrote it, in the one write
// bd's own append makes. Asked to notify, because the note changes what the
// work on the bead should do, it then finds whoever is working the bead now:
// the bead's own assignee, and the holder of each member of each live run that
// works the bead, through the run link waits holds, since a bead whose work
// runs on a poured workflow reads open and unassigned while the workflow's
// steps are claimed. It sends each one the note with Gas City's immediate
// nudge, which Gas City delivers into a running turn where the session's agent
// takes typed input mid-turn, and otherwise at the turn's end. Whether anyone
// is working the bead is this package's to find out, never the writer's.
package note

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"strings"
	"unicode/utf8"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// NudgeMax is the most bytes a note's nudge carries. Gas City types a nudge
// into the session's input box, and Claude Code takes typed input of more than
// 800 characters as a paste, which reaches its model as pasted material rather
// than as its user's words. So the nudge stays one typed message, and the note
// holds the text whole.
const NudgeMax = 800

// Request is one note on Bead: Text, as the notes record it. Notify asks that
// whoever is working the bead now is told of it, because it changes what that
// work should do.
type Request struct {
	Bead, Text string
	Notify     bool
}

// City is Gas City as a note's notice reaches it: the session list that names
// the sessions working the bead, and the immediate nudge that tells each one.
type City interface {
	NudgeNow(session, message, bead string) gascity.Result
	Sessions(ctx context.Context) ([]gascity.Session, error)
}

// Notes is the note's verb over one store.
type Notes struct {
	Ledger *ledger.Ledger
	City   City
	// By names who wrote the note, in the nudge, host when it names no one.
	By string
	// Self is the names this session goes by, its session name, its session id
	// and its alias: a session working the bead under one of them is this one,
	// which has the note already.
	Self []string
}

// Refusal is a note refused before anything was written.
type Refusal struct{ Msg string }

func (e *Refusal) Error() string { return e.Msg }

func refuse(format string, args ...any) error {
	return &Refusal{Msg: fmt.Sprintf(format, args...)}
}

// Refused reports whether err is a note refused before anything was written.
func Refused(err error) bool {
	var r *Refusal
	return errors.As(err, &r)
}

// Untold is a note that landed but whose notice may not have reached every
// session working the bead: who works it did not read, or a nudge did not land.
type Untold struct{ Msg string }

func (e *Untold) Error() string { return e.Msg }

// IsUntold reports whether err is a note that landed and whose nudges did not
// all land.
func IsUntold(err error) bool {
	var u *Untold
	return errors.As(err, &u)
}

// Note appends req's text to the bead's notes, and with req.Notify then nudges
// each session working the bead with it. It returns one line for the note and,
// with req.Notify, one for each session it decided on, or one that says why
// nobody was told. A *Refusal wrote nothing. An *Untold landed the note, and
// its lines are returned with it. Any other error wrote nothing.
func (n *Notes) Note(req Request) ([]string, error) {
	bead := strings.TrimSpace(req.Bead)
	if strings.TrimSpace(req.Text) == "" {
		return nil, refuse("the note is empty, so there is nothing to put on %s. Nothing was written", bead)
	}
	w := n.Ledger.Write(bead)
	w.Note(req.Text)
	if err := n.Ledger.Commit(w); err != nil {
		return nil, fmt.Errorf("the note did not land on %s's notes (%v), so nothing was written", bead, err)
	}
	lines := []string{"noted " + bead}
	if !req.Notify {
		return lines, nil
	}
	return n.notify(bead, req.Text, lines)
}

// notify tells each session working the bead of the note that landed on it,
// adding a line to lines for each session it decided on.
func (n *Notes) notify(bead, text string, lines []string) ([]string, error) {
	byHand := fmt.Sprintf("gc session nudge <session> --delivery immediate --reference-bead %s \"<what the note changes, and that %s's notes hold it>\"", bead, bead)
	row, err := n.read(bead)
	if err == nil && row == nil {
		err = errors.New("the store does not hold it")
	}
	if err != nil {
		return lines, &Untold{Msg: fmt.Sprintf("the note is on %s's notes, but %s did not read (%v), so nobody was told. Tell each session working %s: %s", bead, bead, err, bead, byHand)}
	}
	if row.Status() == "closed" {
		return append(lines, bead+" is closed, so no work on it runs, and nobody was told"), nil
	}
	holders, err := n.holders(row)
	if err != nil {
		return lines, &Untold{Msg: fmt.Sprintf("the note is on %s's notes, but who works %s now did not read (%v), so nobody was told. Tell each session working %s: %s", bead, bead, err, bead, byHand)}
	}
	if len(holders) == 0 {
		return append(lines, "nobody works "+bead+" now, so the note waits for whoever picks it up"), nil
	}
	list, err := n.City.Sessions(context.Background())
	if err != nil {
		return lines, &Untold{Msg: fmt.Sprintf("the note is on %s's notes, but gc session list did not read (%v), so nobody was told. Tell each session working %s, which these name (%s): %s", bead, err, bead, strings.Join(holders, ", "), byHand)}
	}
	var sent, failed []string
	for _, h := range holders {
		if n.mine(h) {
			lines = append(lines, "kept "+h+": this session holds work on "+bead+", and has the note")
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
			case n.mine(id):
				lines = append(lines, "kept "+id+": this session holds work on "+bead+", and has the note")
			case s.Provider == "":
				lines = append(lines, "skipped "+id+": it runs no agent to read a nudge")
			default:
				res := n.City.NudgeNow(id, n.message(bead, text), bead)
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
		return lines, &Untold{Msg: fmt.Sprintf("the note is on %s's notes, but the nudge to %s did not land, so that work may build on without it. Send it again: %s", bead, strings.Join(failed, ", "), byHand)}
	}
	return lines, nil
}

// message is the nudge that tells a session of the note: who wrote it, that it
// changes what the session's work on the bead should do, where the bead's notes
// hold it whole, and the note on one line, cut to fit within NudgeMax.
func (n *Notes) message(bead, text string) string {
	head := fmt.Sprintf("%s put a note on %s that changes what your work on it should do. Its notes hold the note in full (gc bd show %s), so read them and build on it from here. The note: ", n.by(), bead, bead)
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
func (n *Notes) holders(row *ledger.Record) ([]string, error) {
	var out []string
	add := func(h string) {
		if h != "" && !slices.Contains(out, h) {
			out = append(out, h)
		}
	}
	add(row.Assignee())
	up, err := n.Ledger.Dependents(row.ID, "tracks")
	if err != nil {
		return nil, err
	}
	runs, err := waits.LiveRunsOf(n.Ledger, row.ID, up)
	if err != nil {
		return nil, err
	}
	for _, run := range runs {
		held, err := waits.RunHolders(n.Ledger, run.Root)
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
func (n *Notes) read(id string) (*ledger.Record, error) {
	rows, err := n.Ledger.Find(ledger.ByID(id).WithClosed())
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
func (n *Notes) mine(name string) bool {
	return name != "" && slices.Contains(n.Self, name)
}

func (n *Notes) by() string {
	if b := strings.TrimSpace(n.By); b != "" {
		return b
	}
	return "host"
}
