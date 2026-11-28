package session

import (
	"cmp"
	"context"
	"encoding/json"
	"fmt"
	"slices"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// EventType is the type of the event the seat-progress look records.
const EventType = "gc-toolkit.seat-progress.stalled"

// Actor is the actor the look's event names.
const Actor = "gctk"

const (
	// Printing is how recently a seat's pane must have printed for the seat to
	// read as busy. Gas City's work ladder reads a pane quiet for 90 seconds as
	// a quiet seat and paces it itself (idleClaimNudgeGrace in
	// cmd/gc/idle_nudge.go at gastownhall/gascity c7eb6d2f43).
	Printing = 90 * time.Second
	// Bound is how long a busy seat may go without a write before the look
	// reports it.
	Bound = 3 * time.Hour
	// PromptAnswered is the event the controller records once a seat's pending
	// interaction, such as a permission prompt, is answered or withdrawn. A
	// seat that prints after an answer has been busy only since then, so the
	// look counts Bound from the answer as well. The work.nudged event that Gas
	// City's work ladder records on reaching a quiet seat starts no such count,
	// because it shows that the notice reached the seat
	// (cmd/gc/work_ladder_notice.go), not that the seat's work moved. Both
	// types are in internal/events/events.go, at gastownhall/gascity
	// 6dce31bbb6.
	PromptAnswered = "session.pending_cleared"
	// Deadline bounds the look's session list and store reads, counted from
	// the start of its run, and CallBound the record of its event. The rig list
	// keeps the runtime adapter's own bound (gascity.RigListWait), so a run
	// ends inside the two minutes its order gives it when the session and rig
	// lists answer within Deadline.
	Deadline  = 90 * time.Second
	CallBound = 20 * time.Second
)

// What a stalled seat's silence is counted from, the latest of these.
const (
	// FromWrite is its newest write.
	FromWrite = "write"
	// FromWake is when it last woke, having written nothing since.
	FromWake = "wake"
	// FromPrompt is when a prompt it waited at was answered (PromptAnswered).
	FromPrompt = "prompt"
)

// City is Gas City as the look reaches it: the session list, the rig list and
// the event log.
type City interface {
	Sessions(ctx context.Context) ([]gascity.Session, error)
	Rigs() ([]gascity.Rig, error)
	Events(ctx context.Context, typ string, since time.Duration) ([]gascity.Event, error)
	Emit(ctx context.Context, e gascity.Emit) error
}

// Progress is the seat-progress look: it reads every rig's claims and the
// session list, and records one event naming each pool seat whose pane prints
// while it has written nothing to a store for Bound. It writes no bead.
type Progress struct {
	City City
	Open ledger.Opener
	Now  func() time.Time
}

// Stalled is one pool seat the look found: the claim it holds, the identity
// its writes carry, and since when it has printed with nothing written, which
// From names.
type Stalled struct {
	Rig      string    `json:"rig"`
	Bead     string    `json:"bead"`
	Session  string    `json:"session"`
	Identity string    `json:"identity"`
	Agent    string    `json:"agent,omitempty"`
	Since    time.Time `json:"since"`
	From     string    `json:"from"`
}

// Unread is a read the look made that failed: a rig's store, or one claim. A
// record that lists one may lack a seat it would have named.
type Unread struct {
	Rig  string `json:"rig,omitempty"`
	Bead string `json:"bead,omitempty"`
	Why  string `json:"why"`
}

// Record is the look's event payload.
type Record struct {
	Read    time.Time `json:"read"`
	Stalled []Stalled `json:"stalled"`
	Unread  []Unread  `json:"unread,omitempty"`
}

// Summary is the record in one line, the event's message.
func (rec *Record) Summary() string {
	if len(rec.Stalled) == 0 {
		return "no pool seat prints with its work standing still"
	}
	seats := make([]string, len(rec.Stalled))
	for i, s := range rec.Stalled {
		seats[i] = s.Session + " holding " + s.Bead
	}
	return fmt.Sprintf("pool seats that print but have written nothing for %s: %s", Bound, strings.Join(seats, ", "))
}

// Outcome is what a run did: the record it composed, nil when a read the
// whole look rests on failed, whether its event was recorded, which it is only
// when the record names a seat, and each thing that failed, any of which makes
// the run's exit non-zero.
type Outcome struct {
	Record   *Record
	Recorded bool
	Failures []string
}

// claim is an in-progress bead a listed session holds under the identity its
// writes carry, and the seat that holds it.
type claim struct {
	rig      gascity.Rig
	bead     string
	identity string
	seat     gascity.Session
	woke     time.Time
}

// Run looks once and records the event when the look found a seat. Its reads
// and its event end when ctx does.
func (p *Progress) Run(ctx context.Context) Outcome {
	out := p.Read(ctx)
	if out.Record == nil {
		return out
	}
	return p.finish(ctx, out)
}

// Read reads once, over the HQ and each rig that is not suspended, as core's
// orphan sweep walks them, and records nothing. A claim counts when it is in
// progress, names the session that holds it, that session is listed, and the
// claim is assigned to the identity the session's writes carry: its alias when
// it has one, and otherwise its session id (AssigneeIdentifier in
// internal/session/assignee_identities.go at gastownhall/gascity c7eb6d2f43).
// The seat counts when its session bead, in the city's store, marks it a pool
// seat and its pane printed within Printing. It is stalled when the latest of
// its newest write as that identity, to the claim's store or the city's, its
// last wake, and the last time Gas City recorded a prompt it waited at
// answered (PromptAnswered) is Bound old or more. A read that fails for one rig
// or one claim leaves it out of the record and fails the outcome. Its session
// list and its store and event reads end when ctx does.
func (p *Progress) Read(ctx context.Context) Outcome {
	reads, cancel := context.WithTimeout(ctx, Deadline)
	defer cancel()
	now := p.Now().UTC().Truncate(time.Second)
	list, err := p.City.Sessions(reads)
	if err != nil {
		return Outcome{Failures: []string{"the session list did not read, so no seat was judged: " + err.Error()}}
	}
	live, err := Read(list)
	if err != nil {
		return Outcome{Failures: []string{err.Error()}}
	}
	rigs, err := p.City.Rigs()
	if err != nil {
		return Outcome{Failures: []string{"the rig list did not read, so no seat was judged: " + err.Error()}}
	}
	hq := slices.IndexFunc(rigs, func(r gascity.Rig) bool { return r.HQ })
	if hq < 0 {
		return Outcome{Failures: []string{"gc rig list names no HQ, whose store holds the session beads, so no seat was judged"}}
	}
	rec := &Record{Read: now, Stalled: []Stalled{}}
	stores := map[string]*ledger.Ledger{}
	var claims []claim
	for _, rig := range rigs {
		if rig.Suspended && !rig.HQ {
			continue
		}
		l, found, err := p.claims(reads, rig, live)
		if err != nil {
			rec.Unread = append(rec.Unread, Unread{Rig: rig.Name, Why: err.Error()})
			continue
		}
		stores[rig.Store()] = l
		claims = append(claims, found...)
	}
	cityDB := rigs[hq].Store()
	city := stores[cityDB]
	if city == nil && len(claims) > 0 {
		for _, c := range claims {
			rec.Unread = append(rec.Unread, Unread{Rig: c.rig.Name, Bead: c.bead, Why: "the city's store, which holds its seat's session bead, did not read"})
		}
		claims = nil
	}
	claims = p.seats(city, claims, now, rec)
	p.judge(reads, stores, cityDB, claims, now, rec)
	slices.SortFunc(rec.Stalled, func(a, b Stalled) int { return cmp.Or(cmp.Compare(a.Rig, b.Rig), cmp.Compare(a.Bead, b.Bead)) })
	out := Outcome{Record: rec}
	for _, u := range rec.Unread {
		out.Failures = append(out.Failures, unreadLine(u))
	}
	return out
}

// claims reads one rig's in-progress beads that name a session, and keeps each
// one a listed session holds under the identity its writes carry.
func (p *Progress) claims(ctx context.Context, rig gascity.Rig, live *Live) (*ledger.Ledger, []claim, error) {
	l, err := p.Open(ctx, rig.Store())
	if err != nil {
		return nil, nil, err
	}
	recs, err := l.Find(ledger.Carrying(sessionIDKey))
	if err != nil {
		return nil, nil, err
	}
	var out []claim
	for _, r := range recs {
		if r.Status() != "in_progress" {
			continue
		}
		o, err := OwnerOf(r)
		if err != nil {
			return nil, nil, err
		}
		seat, ok := live.Session(o.SessionID)
		if o.SessionID == "" || !ok {
			continue
		}
		identity := cmp.Or(seat.Alias, o.SessionID)
		if o.Assignee != identity {
			continue
		}
		out = append(out, claim{rig: rig, bead: r.ID, identity: identity, seat: seat})
	}
	return l, out, nil
}

// seats keeps each claim whose session bead marks a pool seat and whose pane
// printed within Printing, with when the seat last woke: its session bead's
// last_woke_at, or when the session was created when that is absent.
func (p *Progress) seats(city *ledger.Ledger, claims []claim, now time.Time, rec *Record) []claim {
	if len(claims) == 0 {
		return nil
	}
	ids := make([]string, len(claims))
	for i, c := range claims {
		ids[i] = c.seat.ID
	}
	beads, err := city.Find(ledger.ByID(ids...))
	if err != nil {
		for _, c := range claims {
			rec.Unread = append(rec.Unread, Unread{Rig: c.rig.Name, Bead: c.bead, Why: "its seat's session bead did not read: " + err.Error()})
		}
		return nil
	}
	byID := map[string]*ledger.Record{}
	for _, b := range beads {
		byID[b.ID] = b
	}
	var out []claim
	for _, c := range claims {
		unread := func(why string) { rec.Unread = append(rec.Unread, Unread{Rig: c.rig.Name, Bead: c.bead, Why: why}) }
		sb, ok := byID[c.seat.ID]
		if !ok {
			unread("the city's store holds no open session bead " + c.seat.ID)
			continue
		}
		pool, _, err := poolManagedKey.Get(sb)
		if err != nil {
			unread(err.Error())
			continue
		}
		if pool != "true" || c.seat.LastActive.IsZero() || now.Sub(c.seat.LastActive) > Printing {
			continue
		}
		woke, held, err := lastWokeAtKey.Get(sb)
		switch {
		case err != nil:
			unread(err.Error())
			continue
		case held && woke != "":
			t, err := time.Parse(time.RFC3339, woke)
			if err != nil {
				unread(fmt.Sprintf("its session bead's last_woke_at %q does not read as a time", woke))
				continue
			}
			c.woke = t.UTC()
		case !c.seat.CreatedAt.IsZero():
			c.woke = c.seat.CreatedAt
		default:
			unread("when its seat " + c.seat.ID + " woke did not read")
			continue
		}
		out = append(out, c)
	}
	return out
}

// judge reads each seat's newest write, in its claim's store and the city's,
// and then, for a seat silent for Bound since that write or its wake, when Gas
// City last recorded a prompt it waited at answered. It records each seat
// whose silence since the latest of the three is Bound or more.
func (p *Progress) judge(ctx context.Context, stores map[string]*ledger.Ledger, cityDB string, claims []claim, now time.Time, rec *Record) {
	if len(claims) == 0 {
		return
	}
	actors := map[string][]string{}
	for _, c := range claims {
		actors[c.rig.Store()] = append(actors[c.rig.Store()], c.identity)
		if c.rig.Store() != cityDB {
			actors[cityDB] = append(actors[cityDB], c.identity)
		}
	}
	writes := map[string]map[string]time.Time{}
	failed := map[string]string{}
	for db, names := range actors {
		got, err := stores[db].LastWrites(names...)
		if err != nil {
			failed[db] = err.Error()
			continue
		}
		writes[db] = got
	}
	var silent []Stalled
	for _, c := range claims {
		why := cmp.Or(failed[c.rig.Store()], failed[cityDB])
		if why != "" {
			rec.Unread = append(rec.Unread, Unread{Rig: c.rig.Name, Bead: c.bead, Why: "the writes of " + c.identity + " did not read: " + why})
			continue
		}
		newest := writes[c.rig.Store()][c.identity]
		if t := writes[cityDB][c.identity]; t.After(newest) {
			newest = t
		}
		since, from := c.woke, FromWake
		if !newest.IsZero() && !newest.Before(c.woke) {
			since, from = newest, FromWrite
		}
		if now.Sub(since) < Bound {
			continue
		}
		silent = append(silent, Stalled{Rig: c.rig.Name, Bead: c.bead, Session: c.seat.ID, Identity: c.identity,
			Agent: c.seat.AgentName, Since: since, From: from})
	}
	if len(silent) == 0 {
		return
	}
	oldest := now
	for _, s := range silent {
		if s.Since.Before(oldest) {
			oldest = s.Since
		}
	}
	answered, err := p.answered(ctx, now.Sub(oldest)+time.Minute)
	if err != nil {
		for _, s := range silent {
			rec.Unread = append(rec.Unread, Unread{Rig: s.Rig, Bead: s.Bead, Why: "when Gas City last saw a prompt its seat waited at answered did not read: " + err.Error()})
		}
		return
	}
	for _, s := range silent {
		if at, ok := answered[s.Session]; ok && at.After(s.Since) {
			s.Since, s.From = at, FromPrompt
		}
		if now.Sub(s.Since) < Bound {
			continue
		}
		rec.Stalled = append(rec.Stalled, s)
	}
}

// answered reads, for each session, the last time within window that Gas City
// recorded a prompt it waited at answered. The window reaches back to the
// oldest silent seat's newest write or wake, before which an answer changes
// nothing. The event carries the session's id in its payload's session_id.
func (p *Progress) answered(ctx context.Context, window time.Duration) (map[string]time.Time, error) {
	events, err := p.City.Events(ctx, PromptAnswered, window)
	if err != nil {
		return nil, err
	}
	out := map[string]time.Time{}
	for _, e := range events {
		var payload struct {
			SessionID string `json:"session_id"`
		}
		if json.Unmarshal(e.Payload, &payload) != nil || payload.SessionID == "" {
			continue
		}
		if cur, ok := out[payload.SessionID]; !ok || e.Ts.After(cur) {
			out[payload.SessionID] = e.Ts.UTC()
		}
	}
	return out, nil
}

// finish records the read's event when its record names a seat.
func (p *Progress) finish(ctx context.Context, out Outcome) Outcome {
	rec := out.Record
	if len(rec.Stalled) == 0 {
		return out
	}
	payload, err := json.Marshal(rec)
	if err == nil {
		emit, cancel := context.WithTimeout(ctx, CallBound)
		err = p.City.Emit(emit, gascity.Emit{Type: EventType, Actor: Actor, Message: rec.Summary(), Payload: payload})
		cancel()
	}
	if err != nil {
		out.Failures = append(out.Failures, "the look's event was not recorded: "+err.Error())
		return out
	}
	out.Recorded = true
	return out
}

func unreadLine(u Unread) string {
	switch {
	case u.Bead != "":
		return fmt.Sprintf("%s in %s was not judged: %s", u.Bead, u.Rig, u.Why)
	default:
		return fmt.Sprintf("the store of %s did not read, so its seats were not judged: %s", u.Rig, u.Why)
	}
}
