// Package park is a bead's park: everything under the bead that has not
// started waits on one blocker, and work already in flight finishes
// (docs/steering.md, "A park"). `gctk bead park` makes it. The text form files a
// plain gate, titled with why the bead is parked and what releases it, born with
// its blocks edge onto the bead in one create in the bead's own store, since bd
// resolves an edge only within one store. The --waiting-on form parks the bead
// behind a bead that already exists, by the same edge. Closing the blocker
// releases the park, and removing one bead's edge onto it releases that bead
// alone.
//
// A park holds what has not started because bd marks a bead blocked while a
// parent of it is, so the edge on the bead holds every bead under it in the
// store's own answer. It refuses a bead in flight, whose own edge would hold its
// merge and its close. It asks waits which beads are in flight and which runs
// load-context still holds, the arm's record which beads are armed, and
// lifecycle the headline rule a gate's title keeps, and no domain asks it.
package park

import (
	"errors"
	"fmt"
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/arm/record"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/lifecycle"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// Parks is the park's verb over one store: the store's ledger, and the store
// the caller named, a store's .beads directory, which a remedy names, empty
// when gc routes the bead to its store.
type Parks struct {
	Ledger *ledger.Ledger
	DB     string
}

// Request is one park: the bead, and either the text that titles the gate the
// park files, with the body that describes it when BodySet says one was given,
// or the bead it waits on.
type Request struct {
	Bead, Text, Body, WaitingOn string
	BodySet                     bool
}

// Flight is a bead under the parked one that is in flight, and why, which the
// park leaves running.
type Flight struct{ ID, Why string }

// Poured is a bead under the parked one with a workflow poured for it that
// load-context still holds, and that workflow's root.
type Poured struct{ ID, Root string }

// Parked is what a park did: the blocker that holds the bead and its title,
// whether the text form found a gate already holding the bead under this text,
// and whether the call's --body became that gate's description. Held is the
// bead and every bead under it that has not started, Flight each bead under it
// in flight, and Poured each bead under it with a workflow load-context still
// holds.
type Parked struct {
	Blocker, Title    string
	Reused, Described bool
	Held              []string
	Flight            []Flight
	Poured            []Poured
}

// Refusal is a park refused for what it asks or for what the bead is, before
// anything is written.
type Refusal struct{ Msg string }

func (e *Refusal) Error() string { return e.Msg }

func refuse(format string, args ...any) error {
	return &Refusal{Msg: fmt.Sprintf(format, args...)}
}

// Refused reports whether err is a park refused before anything was written,
// rather than a read or a write that failed.
func Refused(err error) bool {
	var r *Refusal
	return errors.As(err, &r)
}

// Park parks the bead. It refuses a call naming both forms or neither, a body
// beside --waiting-on, a title that is not a headline, a closed bead, a bead in
// flight, and a bead to wait on that is the bead itself, sits in another store,
// is closed or pinned, or sits under the bead. The text form reuses an open gate
// the bead already waits on under the same title, and gives it the call's body
// as its description when it differs. It reads the bead's store once to say
// what the park holds.
func (p *Parks) Park(req Request) (Parked, error) {
	var out Parked
	req, err := Validate(req)
	if err != nil {
		return out, err
	}
	bead, err := p.read(req.Bead)
	switch {
	case err != nil:
		return out, fmt.Errorf("could not read %s (%v). Nothing was written", req.Bead, err)
	case bead == nil:
		return out, fmt.Errorf("%s does not resolve in its store%s. Nothing was written", req.Bead, p.inStore())
	case bead.Status() == "closed":
		return out, refuse("%s is closed, so nothing under it waits to start and a park would hold nothing. Nothing was written", req.Bead)
	}

	sv, err := p.survey(req.Bead)
	if err != nil {
		return out, fmt.Errorf("could not read the store that holds %s (%v) to prove that %s is not in flight, and a park edge on a bead in flight holds its merge. Re-run once the store answers. Nothing was written", req.Bead, err, req.Bead)
	}
	if sv.self != "" {
		instead := ""
		if parents, err := bead.Parents(); err == nil && len(parents) > 0 {
			instead = fmt.Sprintf(" Park %s instead, which holds what under it has not started and leaves %s running.", parents[0], req.Bead)
		}
		return out, refuse("%s is in flight (%s). Its own edge would be a live direct blocker: an open blocker of its own holds its merge, and bd refuses to close a bead that has one.%s Nothing was written", req.Bead, sv.self, instead)
	}
	out.Held, out.Flight, out.Poured = sv.held, sv.flight, sv.poured

	if req.WaitingOn != "" {
		return p.waitOn(req, sv, out)
	}
	return p.gate(req, bead, out)
}

// Validate refuses a call for what it asks, before anything is read: both
// forms or neither, a body beside --waiting-on, and a title that is not a
// headline. It returns the call with the bead and the bead to wait on trimmed
// and the title on one line.
func Validate(req Request) (Request, error) {
	req.Bead, req.WaitingOn = strings.TrimSpace(req.Bead), strings.TrimSpace(req.WaitingOn)
	textForm := req.Text != ""
	switch {
	case req.Bead == "":
		return req, refuse("park needs <bead-id>")
	case textForm && req.WaitingOn != "":
		return req, refuse("\"<text>\" and --waiting-on are the two forms of a park, and a park takes one. The text form files a gate of its own, titled with why %s is parked and what releases it; --waiting-on parks %s behind %s and files no gate. Pass one. Nothing was written", req.Bead, req.Bead, req.WaitingOn)
	case !textForm && req.WaitingOn == "":
		return req, refuse("park needs \"<text>\", one line of at most %d characters saying why %s is parked and what releases it, or --waiting-on <bead-id> to park it behind an existing bead. Nothing was written", lifecycle.TakeawayMax, req.Bead)
	case req.WaitingOn != "" && req.BodySet:
		return req, refuse("--body describes the gate the text form files, and --waiting-on files none, so the body would be dropped. Use the text form to describe a park of its own. Nothing was written")
	}
	if textForm {
		title, err := lifecycle.Headline(req.Text)
		var long *lifecycle.LongHeadline
		switch {
		case errors.As(err, &long):
			return req, refuse("the text is %d characters, and the cap is %d. It is the park gate's title, one line read wherever the gate is listed. Cut it to why the bead is parked and what releases it, and put the rest in --body. Nothing was written", long.Len, lifecycle.TakeawayMax)
		case err != nil:
			return req, refuse("park needs \"<text>\", the one-line headline of at most %d characters saying why %s is parked and what releases it. Nothing was written", lifecycle.TakeawayMax, req.Bead)
		}
		req.Text = title
	}
	return req, nil
}

// waitOn parks the bead behind req.WaitingOn, by a blocks edge onto it.
func (p *Parks) waitOn(req Request, sv survey, out Parked) (Parked, error) {
	w := req.WaitingOn
	switch {
	case w == req.Bead:
		return out, refuse("--waiting-on %s is %s itself. Nothing was written", w, req.Bead)
	case prefixOf(w) != prefixOf(req.Bead):
		return out, refuse("%s lives in another store than %s, and bd resolves an edge only within one store, so an edge onto %s would hold nothing. Park with the text form and name %s in it: gctk bead park %s \"<why it is parked and what releases it>\". Nothing was written", w, req.Bead, w, w, req.Bead)
	}
	wait, err := p.read(w)
	switch {
	case err != nil:
		return out, fmt.Errorf("could not read --waiting-on %s (%v). Nothing was written", w, err)
	case wait == nil:
		return out, fmt.Errorf("--waiting-on %s does not resolve in %s's store%s. Nothing was written", w, req.Bead, p.inStore())
	}
	if st := wait.Status(); st == "closed" || st == "pinned" {
		return out, refuse("%s is %s, so an edge onto it holds nothing. Nothing was written", w, st)
	}
	if sv.under(w) {
		return out, refuse("%s is under %s, and bd refuses an edge that makes a bead wait on its own part. Nothing was written", w, req.Bead)
	}
	if err := p.Ledger.AddBlocker(req.Bead, w); err != nil {
		return out, fmt.Errorf("%s is NOT blocked by %s: the edge did not land (%v), so nothing holds %s or anything under it. Wire it by hand: gc bd dep add %s %s -t blocks%s", req.Bead, w, err, req.Bead, req.Bead, w, p.dbFlag())
	}
	out.Blocker, out.Title = w, wait.Title()
	return out, nil
}

// gate parks the bead behind the gate its text titles: the open one already
// holding it under that title, or a new one born with its edge.
func (p *Parks) gate(req Request, bead *ledger.Record, out Parked) (Parked, error) {
	out.Title = req.Text
	open, err := p.openGate(bead, req.Text)
	if err != nil {
		return out, fmt.Errorf("could not read the gates %s waits on (%v), so whether one already parks it under this text is unknown. Nothing was written", req.Bead, err)
	}
	if open != nil {
		out.Blocker, out.Reused = open.ID, true
		if req.BodySet && open.Description() != req.Body {
			w := p.Ledger.Write(open.ID)
			w.Description(req.Body)
			if err := p.Ledger.Commit(w); err != nil {
				return out, fmt.Errorf("%s already waits on the open gate %s under this text, so the park holds, but the gate's description is not the --body this call names: the write did not land (%v). Apply it by hand: gc bd update %s --description \"<the --body text>\"%s", req.Bead, open.ID, err, open.ID, p.dbFlag())
			}
			out.Described = true
		}
		return out, nil
	}
	body := req.Body
	if !req.BodySet {
		body = "Parks " + req.Bead + ": everything under it that has not started waits on this gate, and work already in flight finishes. Closing this gate releases it. To release one bead this gate holds, remove that bead's edge: gc bd dep remove <bead> <this gate>."
	}
	f := p.Ledger.File(req.Text, "gate")
	f.Description(body)
	f.Blocks(req.Bead)
	id, cerr := p.Ledger.Create(f)
	if cerr == nil && id != "" {
		out.Blocker = id
		return out, nil
	}
	// A create whose answer was lost may have filed the gate, which was born
	// with its edge, so the bead's own row finds it under this title.
	again, err := p.read(req.Bead)
	if err == nil && again != nil {
		if found, err := p.openGate(again, req.Text); err == nil && found != nil {
			out.Blocker = found.ID
			return out, nil
		}
	}
	return out, fmt.Errorf("no gate was filed for %s (%v), and none waits on it under this text, so nothing holds %s. Re-run once the store answers", req.Bead, cerr, req.Bead)
}

// openGate is the open gate bead waits on, by a blocks edge, under exactly
// title, in the shape the text form files: no await type and no metadata, nil
// when it waits on none. A gate of another kind can carry the same title: a
// human gate is released by a person's decision, a gate with any await type by
// its condition firing, and a gate with metadata belongs to the writer that
// stamped it, so adopting one would report a park while the bead waits on
// something that is not one.
func (p *Parks) openGate(bead *ledger.Record, title string) (*ledger.Record, error) {
	edges, err := bead.Edges()
	if err != nil {
		return nil, err
	}
	var far []string
	for _, e := range edges {
		if e.Type == ledger.EdgeBlocks {
			far = append(far, e.ID)
		}
	}
	rows, err := p.Ledger.Find(ledger.ByID(far...).WithClosed())
	if err != nil {
		return nil, err
	}
	slices.SortFunc(rows, func(a, b *ledger.Record) int { return strings.Compare(a.ID, b.ID) })
	for _, r := range rows {
		if r.IssueType() == "gate" && r.Status() != "closed" && r.Title() == title && r.AwaitType() == "" && len(r.Rendered()) == 0 {
			return r, nil
		}
	}
	return nil, nil
}

// survey is what a park does to the bead and each bead under it: why the bead
// itself is in flight, empty when it is not, and the held, in-flight and
// poured beads Parked names.
type survey struct {
	self   string
	sub    []string
	held   []string
	flight []Flight
	poured []Poured
}

// under reports whether id is the parked bead or a bead under it.
func (s survey) under(id string) bool { return slices.Contains(s.sub, id) }

// survey reads the bead's store once, every live bead, and sorts the bead and
// each bead under it, through parent-child edges with any of its parents
// counting, by what a park does to it: in flight, which it leaves running;
// poured, not armed, with a workflow load-context still holds; and held, the
// bead and every other bead under it. An armed bead is held, since its start
// sends it only once nothing holds it, a park on an ancestor included.
func (p *Parks) survey(bead string) (survey, error) {
	var s survey
	pass := p.Ledger.Pass()
	live, err := pass.Find(ledger.Every())
	if err != nil {
		return s, err
	}
	children := map[string][]string{}
	for _, r := range live {
		parents, err := r.Parents()
		if err != nil {
			return s, &ledger.ReadError{ID: r.ID, Reason: "its edges did not decode: " + err.Error()}
		}
		for _, par := range parents {
			children[par] = append(children[par], r.ID)
		}
	}
	s.sub = []string{bead}
	for front := []string{bead}; len(front) > 0; {
		var next []string
		for _, id := range front {
			for _, c := range children[id] {
				if !slices.Contains(s.sub, c) {
					s.sub = append(s.sub, c)
					next = append(next, c)
				}
			}
		}
		front = next
	}
	snap, err := waits.Read(pass, s.sub...)
	if err != nil {
		return s, err
	}
	for _, id := range s.sub {
		why, err := snap.InFlight(id)
		if err != nil {
			return s, err
		}
		if id == bead {
			s.self = why
			if why == "" {
				s.held = append(s.held, id)
			}
			continue
		}
		if why != "" {
			s.flight = append(s.flight, Flight{ID: id, Why: why})
			continue
		}
		root, err := snap.AtLoadContext(id)
		if err != nil {
			return s, err
		}
		armed := false
		if rows, err := pass.Find(ledger.ByID(id)); err == nil && len(rows) == 1 {
			armed = record.Of(rows[0]) != nil
		}
		if root == "" || armed {
			s.held = append(s.held, id)
			continue
		}
		s.poured = append(s.poured, Poured{ID: id, Root: root})
	}
	return s, nil
}

// read is the bead's record in the store, closed or not, nil when the store
// does not hold it.
func (p *Parks) read(id string) (*ledger.Record, error) {
	rows, err := p.Ledger.Find(ledger.ByID(id).WithClosed())
	if err != nil {
		return nil, err
	}
	for _, r := range rows {
		if r.ID == id {
			return r, nil
		}
	}
	return nil, nil
}

// inStore names the store the caller named, for a message, empty when gc
// routed the bead to its store.
func (p *Parks) inStore() string {
	if p.DB == "" {
		return ""
	}
	return " (" + p.DB + ")"
}

// dbFlag is the --db a remedy names, empty when gc routed the bead.
func (p *Parks) dbFlag() string {
	if p.DB == "" {
		return ""
	}
	return " --db " + p.DB
}

// prefixOf is the store prefix a bead's id begins with.
func prefixOf(id string) string {
	pre, _, _ := strings.Cut(id, "-")
	return pre
}

// Lines is what a park says it did, one line each: which blocker holds the
// bead, then what it holds and what it leaves running.
func (out Parked) Lines(bead string) []string {
	lines := []string{"park " + out.Blocker + " holds " + bead + ": " + out.Title}
	held := out.Held
	if len(held) == 0 {
		held = []string{bead}
	}
	lines = append(lines, "held, not started: "+strings.Join(held, " "))
	if len(out.Flight) > 0 {
		var f []string
		for _, x := range out.Flight {
			f = append(f, x.ID+" ("+x.Why+")")
		}
		lines = append(lines, "in flight, keeps running: "+strings.Join(f, ", "))
	}
	if len(out.Poured) > 0 {
		var f []string
		for _, x := range out.Poured {
			f = append(f, x.ID+" (workflow "+x.Root+")")
		}
		lines = append(lines, "poured before the park, waiting at load-context: "+strings.Join(f, ", ")+
			". Load-context's gate refuses each one it has not let through yet, and arms its re-sling for the park's release.")
	}
	return lines
}
