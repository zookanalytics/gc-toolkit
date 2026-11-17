// Package worktree is the worktree domain: the work a dead session left in a
// rig. Its salvage reader finds each bead whose owner no live session answers
// to, and its look, `gctk worktree salvage`, records what the reader found as
// one Gas City event, gc-toolkit.orphan-work.found. The look writes no bead.
// The act that answers the event reads each bead again through the same reader
// (specs/tk-1tfzr71.158/design.md, sections 2 and 3).
package worktree

import (
	"cmp"
	"context"
	"encoding/json"
	"fmt"
	"slices"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/conversation"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus"
	"github.com/zookanalytics/gc-toolkit/services/gctk/session"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// EventType is the type of the event the look records.
const EventType = "gc-toolkit.orphan-work.found"

// Actor is the actor the look's event names.
const Actor = "gctk"

const (
	// Deadline bounds the look's reads, and CallBound the record of its event,
	// so a run ends inside the two minutes its order gives it.
	Deadline  = 90 * time.Second
	CallBound = 20 * time.Second
)

// The keys the reader reads that no domain owns: gc.kind is Gas City's
// (lifecycle/lifecycle.toml, [metadata.runtime_owned]), and work_dir the work
// formula's workspace-setup writes (lifecycle/lifecycle.toml,
// [metadata.merge_identity]).
var (
	kindKey = ledger.ReadOnly("gc.kind", ledger.String,
		"The salvage reader leaves out a topology root, whose kind is workflow, scope or spec "+
			"(WorkflowTopologyKinds in internal/beadmeta/kindsets.go at gastownhall/gascity c7eb6d2f43).")
	workDirKey = ledger.ReadOnly("work_dir", ledger.String,
		"The worktree a work bead's work is in, which the work formula's workspace-setup writes. The salvage "+
			"reader names it for each bead it finds, where the act salvages from.")
)

// topologyKinds are the kinds of a workflow's topology roots, which no agent
// claims and no salvage reaches (WorkflowTopologyKinds in
// internal/beadmeta/kindsets.go at gastownhall/gascity c7eb6d2f43).
var topologyKinds = []string{"workflow", "scope", "spec"}

// inFlightResults are the merge_result values of a bead whose work is in a PR
// on its way to its target: the old path's two values that hold a PR, and both
// values of Gas Town's pending record ([record.OnRecord]). The refinery's path
// owns such a bead, so salvage never reaches it.
var inFlightResults = []string{"pre_open_gate", "pull_request"}

// Orphan is one bead the reader found: it names an owner, and no live session
// answers to any identity the owner goes by.
type Orphan struct {
	Rig         string `json:"rig"`
	Bead        string `json:"bead"`
	Status      string `json:"status"`
	Assignee    string `json:"assignee,omitempty"`
	SessionID   string `json:"session_id,omitempty"`
	SessionName string `json:"session_name,omitempty"`
	WorkDir     string `json:"work_dir,omitempty"`
	Branch      string `json:"branch,omitempty"`
}

// Reader is the salvage reader, which the look and the act share.
type Reader struct {
	Open ledger.Opener
}

// Rig reads one rig's store for its orphaned work. A bead is a candidate when
// it is open or in progress, is of no kind bd's default listing hides, names
// an owner by its session id, its assignee or its session's runtime name, and
// is none of these, which the reader leaves out: work in a PR on its way to its
// target, a conversation, a workflow's topology root, and a bead a person holds
// through an open human gate among its waits ([waits.Holds]). A candidate is
// orphaned when no live session answers to any identity its owner goes by
// ([session.Live.Answers]). It reads the rig's open and in-progress beads that
// bd's listing shows, and then only what holds the orphans among them. A read
// that fails answers its error and no beads.
func (rd Reader) Rig(ctx context.Context, live *session.Live, rig gascity.Rig) ([]Orphan, error) {
	l, err := rd.Open(ctx, rig.Store())
	if err != nil {
		return nil, err
	}
	pass := l.Pass()
	recs, err := pass.Find(ledger.Every().InStatus("open", "in_progress").Listed())
	if err != nil {
		return nil, err
	}
	var found []Orphan
	for _, r := range recs {
		o, ok, err := candidate(r)
		if err != nil {
			return nil, err
		}
		if !ok || live.Answers(o.Names()...) {
			continue
		}
		orphan := Orphan{Rig: rig.Name, Bead: r.ID, Status: r.Status(), Assignee: o.Assignee, SessionID: o.SessionID, SessionName: o.SessionName}
		if orphan.WorkDir, _, err = workDirKey.Get(r); err != nil {
			return nil, err
		}
		if orphan.Branch, _, err = record.Branch.Get(r); err != nil {
			return nil, err
		}
		found = append(found, orphan)
	}
	if len(found) == 0 {
		return nil, nil
	}
	ids := make([]string, len(found))
	for i, o := range found {
		ids[i] = o.Bead
	}
	snap, err := waits.Read(pass, ids...)
	if err != nil {
		return nil, err
	}
	out := found[:0]
	for _, o := range found {
		h, err := snap.Holds(o.Bead)
		if err != nil {
			return nil, err
		}
		if !personHolds(h) {
			out = append(out, o)
		}
	}
	return out, nil
}

// candidate is the owner r names, and whether r is a candidate by its own row.
func candidate(r *ledger.Record) (session.Owner, bool, error) {
	if s := r.Status(); s != "open" && s != "in_progress" {
		return session.Owner{}, false, nil
	}
	if !r.ListedByDefault() {
		return session.Owner{}, false, nil
	}
	o, err := session.OwnerOf(r)
	if err != nil || len(o.Names()) == 0 {
		return o, false, err
	}
	result, _, err := record.Result.Get(r)
	if err != nil {
		return o, false, err
	}
	if slices.Contains(inFlightResults, result) || record.OnRecord(result) {
		return o, false, nil
	}
	if conversation.IsCandidate(r.IssueType(), r.Assignee(), r.ID) {
		return o, false, nil
	}
	kind, _, err := kindKey.Get(r)
	if err != nil || slices.Contains(topologyKinds, kind) {
		return o, false, err
	}
	return o, true, nil
}

// personHolds reports whether a human gate is among what holds the bead: a
// wait of its own that has not landed, or a wait that holds it, its own or an
// ancestor's. A gate a person has answered has landed, so it is neither.
func personHolds(h waits.Holds) bool {
	return slices.ContainsFunc(slices.Concat(h.Pending, h.Waits), func(w waits.Wait) bool {
		return prstatus.IsHumanGate(w.IssueType, w.AwaitType)
	})
}

// City is Gas City as the look reaches it: the session list, the rig list and
// the event log.
type City interface {
	Sessions(ctx context.Context) ([]gascity.Session, error)
	Rigs(ctx context.Context) ([]gascity.Rig, error)
	Emit(ctx context.Context, e gascity.Emit) error
}

// Salvage is the look: it runs the reader over every rig's store and records
// one event naming each bead it found. It writes no bead.
type Salvage struct {
	City City
	Open ledger.Opener
	Now  func() time.Time
}

// Unread is a rig whose store did not read. A record that lists one may lack a
// bead it would have named.
type Unread struct {
	Rig string `json:"rig"`
	Why string `json:"why"`
}

// Record is the look's event payload.
type Record struct {
	Read   time.Time `json:"read"`
	Found  []Orphan  `json:"found"`
	Unread []Unread  `json:"unread,omitempty"`
}

// Summary is the record in one line, the event's message.
func (rec *Record) Summary() string {
	if len(rec.Found) == 0 {
		return "no bead names an owner that no live session answers to"
	}
	beads := make([]string, len(rec.Found))
	for i, o := range rec.Found {
		beads[i] = o.Bead
	}
	return "beads whose owner no live session answers to: " + strings.Join(beads, ", ")
}

// Outcome is what a run did: the record it composed, nil when a read the
// whole look rests on failed, whether its event was recorded, which it is only
// when the record names a bead, and each thing that failed, any of which makes
// the run's exit non-zero.
type Outcome struct {
	Record   *Record
	Recorded bool
	Failures []string
}

// Run looks once: it reads the session list, which every judgment rests on,
// then the HQ and each rig `gc rig list --json` lists that is not suspended,
// as core's orphan sweep walks them. A session list or a rig list that does
// not read judges nothing. A rig whose store does not read is left out of the
// record and fails the run.
func (s *Salvage) Run() Outcome {
	ctx, cancel := context.WithTimeout(context.Background(), Deadline)
	defer cancel()
	now := s.Now().UTC().Truncate(time.Second)
	list, err := s.City.Sessions(ctx)
	if err != nil {
		return Outcome{Failures: []string{"the session list did not read, so no owner was judged: " + err.Error()}}
	}
	live, err := session.Read(list)
	if err != nil {
		return Outcome{Failures: []string{err.Error()}}
	}
	rigs, err := s.City.Rigs(ctx)
	if err != nil {
		return Outcome{Failures: []string{"the rig list did not read, so no owner was judged: " + err.Error()}}
	}
	rec := &Record{Read: now, Found: []Orphan{}}
	reader := Reader{Open: s.Open}
	for _, rig := range rigs {
		if rig.Suspended {
			continue
		}
		found, err := reader.Rig(ctx, live, rig)
		if err != nil {
			rec.Unread = append(rec.Unread, Unread{Rig: rig.Name, Why: err.Error()})
			continue
		}
		rec.Found = append(rec.Found, found...)
	}
	slices.SortFunc(rec.Found, func(a, b Orphan) int { return cmp.Or(cmp.Compare(a.Rig, b.Rig), cmp.Compare(a.Bead, b.Bead)) })
	out := Outcome{Record: rec}
	for _, u := range rec.Unread {
		out.Failures = append(out.Failures, fmt.Sprintf("the store of %s did not read, so its beads were not judged: %s", u.Rig, u.Why))
	}
	if len(rec.Found) == 0 {
		return out
	}
	payload, err := json.Marshal(rec)
	if err == nil {
		ctx, cancel := context.WithTimeout(context.Background(), CallBound)
		err = s.City.Emit(ctx, gascity.Emit{Type: EventType, Actor: Actor, Message: rec.Summary(), Payload: payload})
		cancel()
	}
	if err != nil {
		out.Failures = append(out.Failures, "the look's event was not recorded: "+err.Error())
		return out
	}
	out.Recorded = true
	return out
}
