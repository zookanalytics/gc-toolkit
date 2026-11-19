// Package refinery is the refinery domain: what the pack asks of a rig's
// refinery queue. Its look, `gctk refinery stuck`, finds each handoff that has
// sat with a refinery, unprepared and held by nothing, far past the time a
// handoff takes to turn over, and records what it found as one Gas City event,
// gc-toolkit.refinery-queue.stuck. It writes no bead
// (specs/tk-1tfzr71.158/design.md, section 2).
package refinery

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
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// EventType is the type of the event the look records.
const EventType = "gc-toolkit.refinery-queue.stuck"

// Actor is the actor the look's event names.
const Actor = "gctk"

// Role is the name of the agent that serves a rig's refinery queue, the
// template's name whatever binding imports it.
const Role = "refinery"

const (
	// Bound is how long a handoff may sit before it is stuck. A handoff turns
	// over within a poll interval and a rebase or rework task once the fix
	// pool claims it, observed under two hours, so a bead past this bound is
	// not churn.
	Bound = 4 * time.Hour
	// Deadline bounds the look's store reads, counted from the start of its
	// run, and CallBound the record of its event. The rig list and the agent
	// list keep the runtime adapter's own bounds (gascity.RigListWait,
	// gascity.RosterWait), so a run ends inside the two minutes its order
	// gives it when those two lists answer within Deadline.
	Deadline  = 90 * time.Second
	CallBound = 20 * time.Second
)

// City is Gas City as the look reaches it: the rig list, the agent list and
// the event log.
type City interface {
	Rigs() ([]gascity.Rig, error)
	Agents() ([]gascity.Agent, error)
	Emit(ctx context.Context, e gascity.Emit) error
}

// Stuck is one handoff the look found: the refinery it is assigned to, and
// since when nothing has moved it, the later of its last write and the close
// of the last wait that held it.
type Stuck struct {
	Rig      string    `json:"rig"`
	Bead     string    `json:"bead"`
	Refinery string    `json:"refinery"`
	Since    time.Time `json:"since"`
}

// Unread is a rig whose queue did not read. A record that lists one may lack a
// handoff it would have named.
type Unread struct {
	Rig string `json:"rig"`
	Why string `json:"why"`
}

// Record is the look's event payload.
type Record struct {
	Read   time.Time `json:"read"`
	Stuck  []Stuck   `json:"stuck"`
	Unread []Unread  `json:"unread,omitempty"`
}

// Summary is the record in one line, the event's message.
func (rec *Record) Summary() string {
	if len(rec.Stuck) == 0 {
		return "no refinery handoff has sat unprepared past " + Bound.String()
	}
	beads := make([]string, len(rec.Stuck))
	for i, s := range rec.Stuck {
		beads[i] = s.Bead + " (" + s.Refinery + ")"
	}
	return fmt.Sprintf("refinery handoffs unprepared past %s with nothing holding them: %s", Bound, strings.Join(beads, ", "))
}

// Outcome is what a run did: the record it composed, nil when a read the
// whole look rests on failed, whether its event was recorded, which it is only
// when the record names a handoff, and each thing that failed, any of which
// makes the run's exit non-zero.
type Outcome struct {
	Record   *Record
	Recorded bool
	Failures []string
}

// Queue is the look over every rig's refinery queue.
type Queue struct {
	City City
	Open ledger.Opener
	Now  func() time.Time
}

// Run looks once, over every rig that is not suspended, as core's orphan
// sweep walks them. The HQ, whose agents serve the city, has no refinery
// queue. A rig's queue is the open beads assigned to an agent named Role in
// that rig's directory, by the identity work assigned to it names, and a rig
// that no such agent serves is a queue whose address does not resolve, which
// fails the run as the witness's check reported it. A handoff in the
// queue is a bead of no kind bd's default listing hides, and no epic, that
// carries the branch its work is on and no merge_result, since a merge_result
// marks the work as past preparation. It is stuck when its last write is Bound old, nothing holds it
// ([waits.Holds]), and the close of the last wait that held it is Bound old
// too. A rig list or an agent list that does not read judges nothing. A rig
// whose queue does not read, or what holds a handoff past the bound, is left
// out of the record and fails the run.
func (q *Queue) Run() Outcome {
	ctx, cancel := context.WithTimeout(context.Background(), Deadline)
	defer cancel()
	now := q.Now().UTC().Truncate(time.Second)
	rigs, err := q.City.Rigs()
	if err != nil {
		return Outcome{Failures: []string{"the rig list did not read, so no queue was judged: " + err.Error()}}
	}
	agents, err := q.City.Agents()
	if err != nil {
		return Outcome{Failures: []string{"the agent list did not read, so no queue was judged: " + err.Error()}}
	}
	rec := &Record{Read: now, Stuck: []Stuck{}}
	for _, rig := range rigs {
		if rig.HQ || rig.Suspended {
			continue
		}
		var refineries []string
		for _, a := range agents {
			if a.Dir == rig.Name && a.Name == Role {
				refineries = append(refineries, a.QualifiedName)
			}
		}
		if len(refineries) == 0 {
			rec.Unread = append(rec.Unread, Unread{Rig: rig.Name, Why: "gc agent list names no agent " + Role + " in the rig, so no queue address resolves"})
			continue
		}
		stuck, err := q.rig(ctx, rig, refineries, now)
		if err != nil {
			rec.Unread = append(rec.Unread, Unread{Rig: rig.Name, Why: err.Error()})
			continue
		}
		rec.Stuck = append(rec.Stuck, stuck...)
	}
	slices.SortFunc(rec.Stuck, func(a, b Stuck) int { return cmp.Or(cmp.Compare(a.Rig, b.Rig), cmp.Compare(a.Bead, b.Bead)) })
	out := Outcome{Record: rec}
	for _, u := range rec.Unread {
		out.Failures = append(out.Failures, fmt.Sprintf("the refinery queue of %s did not read, so its handoffs were not judged: %s", u.Rig, u.Why))
	}
	if len(rec.Stuck) == 0 {
		return out
	}
	payload, err := json.Marshal(rec)
	if err == nil {
		ctx, cancel := context.WithTimeout(context.Background(), CallBound)
		err = q.City.Emit(ctx, gascity.Emit{Type: EventType, Actor: Actor, Message: rec.Summary(), Payload: payload})
		cancel()
	}
	if err != nil {
		out.Failures = append(out.Failures, "the look's event was not recorded: "+err.Error())
		return out
	}
	out.Recorded = true
	return out
}

// rig reads one rig's queue and returns its stuck handoffs. It reads each
// refinery's open beads that bd's listing shows, and then only what holds the
// handoffs past the bound.
func (q *Queue) rig(ctx context.Context, rig gascity.Rig, refineries []string, now time.Time) ([]Stuck, error) {
	l, err := q.Open(ctx, rig.Store())
	if err != nil {
		return nil, err
	}
	pass := l.Pass()
	var recs []*ledger.Record
	for _, ref := range refineries {
		queue, err := pass.Find(ledger.Assigned(ref).InStatus("open").Listed())
		if err != nil {
			return nil, err
		}
		recs = append(recs, queue...)
	}
	type handoff struct {
		id, refinery string
		written      time.Time
	}
	var past []handoff
	for _, r := range recs {
		if r.Status() != "open" || !r.ListedByDefault() || strings.EqualFold(r.IssueType(), "epic") || !slices.Contains(refineries, r.Assignee()) {
			continue
		}
		branch, _, err := record.Branch.Get(r)
		if err != nil {
			return nil, err
		}
		result, _, err := record.Result.Get(r)
		if err != nil {
			return nil, err
		}
		if branch == "" || result != "" {
			continue
		}
		written, ok := parseTime(r.UpdatedAt())
		if !ok {
			return nil, fmt.Errorf("the last write of handoff %s, updated_at %q, does not read as a time", r.ID, r.UpdatedAt())
		}
		if now.Sub(written) <= Bound {
			continue
		}
		past = append(past, handoff{id: r.ID, refinery: r.Assignee(), written: written})
	}
	if len(past) == 0 {
		return nil, nil
	}
	ids := make([]string, len(past))
	for i, h := range past {
		ids[i] = h.id
	}
	snap, err := waits.Read(pass, ids...)
	if err != nil {
		return nil, fmt.Errorf("what holds its handoffs past the bound did not read: %w", err)
	}
	var out []Stuck
	for _, h := range past {
		holds, err := snap.Holds(h.id)
		if err != nil {
			return nil, fmt.Errorf("what holds %s did not read: %w", h.id, err)
		}
		if holds.Status != waits.Clear {
			continue
		}
		since := h.written
		if landed, ok := parseTime(holds.LastLanded); ok && landed.After(since) {
			since = landed
		}
		if now.Sub(since) <= Bound {
			continue
		}
		out = append(out, Stuck{Rig: rig.Name, Bead: h.id, Refinery: h.refinery, Since: since})
	}
	return out, nil
}

// parseTime reads a time as bd and Gas City write one, RFC 3339 with or
// without its fraction of a second.
func parseTime(s string) (time.Time, bool) {
	t, err := time.Parse(time.RFC3339Nano, s)
	if err != nil {
		return time.Time{}, false
	}
	return t.UTC(), true
}
