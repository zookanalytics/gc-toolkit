package refinery

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"reflect"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	gcfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

var t0 = time.Date(2026, 11, 16, 23, 0, 0, 0, time.UTC)

func stamp(d time.Duration) string { return t0.Add(-d).Format(time.RFC3339) }

const ref = "tools/gc-toolkit.refinery"

var (
	hq    = gascity.Rig{Name: "city", Path: "/city", Prefix: "hq", HQ: true}
	tools = gascity.Rig{Name: "tools", Path: "/city/rigs/tools", Prefix: "tk"}
)

// city is the runtime and the stores the look reads: an HQ that no refinery
// serves, and the rig tools, which its refinery serves.
type city struct {
	*gcfake.Roster
	*gcfake.EventLog
	stores  map[string]*fake.Store
	openErr map[string]error
}

func newCity() *city {
	return &city{
		Roster: &gcfake.Roster{
			RigList: []gascity.Rig{hq, tools},
			AgentList: []gascity.Agent{
				{Name: "refinery", QualifiedName: ref, Dir: "tools"},
				{Name: "witness", QualifiedName: "tools/gc-toolkit.witness", Dir: "tools"},
				{Name: "mechanik", QualifiedName: "gc-toolkit.mechanik"},
			},
		},
		EventLog: &gcfake.EventLog{Now: func() time.Time { return t0 }},
		stores:   map[string]*fake.Store{hq.Store(): fake.New(), tools.Store(): fake.New()},
		openErr:  map[string]error{},
	}
}

func (c *city) open(_ context.Context, db string) (*ledger.Ledger, error) {
	if err := c.openErr[db]; err != nil {
		return nil, err
	}
	s, ok := c.stores[db]
	if !ok {
		return nil, fmt.Errorf("no store at %s", db)
	}
	return ledger.New(s), nil
}

func (c *city) look(t *testing.T) Outcome {
	t.Helper()
	return (&Queue{City: c, Open: c.open, Now: func() time.Time { return t0 }}).Run()
}

// handoff puts an open task assigned to the refinery that carries a branch and
// was last written age ago.
func (c *city) handoff(id string, age time.Duration, kv ...string) fake.Bead {
	m := map[string]string{"branch": "polecat/" + id}
	for i := 0; i+1 < len(kv); i += 2 {
		m[kv[i]] = kv[i+1]
	}
	b := fake.Bead{ID: id, Title: id, Status: "open", IssueType: "task", Assignee: ref, UpdatedAt: stamp(age), Metadata: m}
	c.stores[tools.Store()].Put(b)
	return b
}

func stuckIDs(rec *Record) []string {
	out := []string{}
	for _, s := range rec.Stuck {
		out = append(out, s.Bead)
	}
	return out
}

// A handoff that has sat unprepared past the bound with nothing holding it is
// stuck, and the look records one event naming it.
func TestAHandoffPastTheBoundIsStuck(t *testing.T) {
	c := newCity()
	c.handoff("tk-stuck", 5*time.Hour)
	c.handoff("tk-fresh", time.Hour)
	out := c.look(t)
	if len(out.Failures) > 0 || !out.Recorded {
		t.Fatalf("failures %v, recorded %v", out.Failures, out.Recorded)
	}
	want := []Stuck{{Rig: "tools", Bead: "tk-stuck", Refinery: ref, Since: t0.Add(-5 * time.Hour)}}
	if !reflect.DeepEqual(out.Record.Stuck, want) {
		t.Fatalf("stuck %+v", out.Record.Stuck)
	}
	got := c.Emitted()
	if len(got) != 1 || got[0].Type != EventType || got[0].Actor != Actor || !strings.Contains(got[0].Message, "tk-stuck ("+ref+")") {
		t.Fatalf("emitted %+v", got)
	}
	var rec Record
	if err := json.Unmarshal(got[0].Payload, &rec); err != nil || !reflect.DeepEqual(rec.Stuck, want) {
		t.Errorf("payload %s: %v", got[0].Payload, err)
	}
}

// Only the refinery's own unprepared handoffs are in its queue: a bead with a
// merge_result, an epic, a bead with no branch, one not open, one assigned to
// another agent, and one bd's default listing hides, a wisp or a gate, are
// each passed over.
func TestOnlyTheQueuesUnpreparedHandoffsAreJudged(t *testing.T) {
	c := newCity()
	s := c.stores[tools.Store()]
	c.handoff("tk-anchor", 9*time.Hour, "merge_result", "pull_request_pending")
	epic := c.handoff("tk-epic", 9*time.Hour)
	epic.IssueType = "epic"
	s.Put(epic)
	wisp := c.handoff("tk-wisp", 9*time.Hour)
	wisp.Ephemeral = true
	s.Put(wisp)
	gate := c.handoff("tk-gate", 9*time.Hour)
	gate.IssueType = "gate"
	s.Put(gate)
	nob := c.handoff("tk-nobranch", 9*time.Hour)
	delete(nob.Metadata, "branch")
	s.Put(nob)
	busy := c.handoff("tk-claimed", 9*time.Hour)
	busy.Status = "in_progress"
	s.Put(busy)
	other := c.handoff("tk-witness", 9*time.Hour)
	other.Assignee = "tools/gc-toolkit.witness"
	s.Put(other)
	c.handoff("tk-bug", 9*time.Hour)
	out := c.look(t)
	if got := stuckIDs(out.Record); len(out.Failures) > 0 || !reflect.DeepEqual(got, []string{"tk-bug"}) {
		t.Fatalf("stuck %v, failures %v", got, out.Failures)
	}
}

// A handoff something holds is waiting, not stuck, and one whose last wait
// landed within the bound counts from that landing.
func TestAHeldHandoffIsWaiting(t *testing.T) {
	c := newCity()
	s := c.stores[tools.Store()]
	s.Put(fake.Bead{ID: "tk-unit", Title: "unit", Status: "open", IssueType: "task"})
	h := c.handoff("tk-landing", 9*time.Hour)
	h.Edges = []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "tk-unit", Status: "open"}}
	s.Put(h)
	s.List("tk-landing", "tk-unit")
	s.Mark("tk-landing")
	s.Put(fake.Bead{ID: "tk-summary", Title: "summary", Status: "closed", IssueType: "task", ClosedAt: stamp(time.Hour)})
	r := c.handoff("tk-released", 9*time.Hour)
	r.Edges = []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "tk-summary", Status: "closed", ClosedAt: stamp(time.Hour)}}
	s.Put(r)
	s.Put(fake.Bead{ID: "tk-old-wait", Title: "old", Status: "closed", IssueType: "task", ClosedAt: stamp(6 * time.Hour)})
	o := c.handoff("tk-long-free", 9*time.Hour)
	o.Edges = []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "tk-old-wait", Status: "closed", ClosedAt: stamp(6 * time.Hour)}}
	s.Put(o)
	out := c.look(t)
	if len(out.Failures) > 0 {
		t.Fatal(out.Failures)
	}
	if got := stuckIDs(out.Record); !reflect.DeepEqual(got, []string{"tk-long-free"}) {
		t.Fatalf("stuck %v", got)
	}
	if !out.Record.Stuck[0].Since.Equal(t0.Add(-6 * time.Hour)) {
		t.Errorf("since %v", out.Record.Stuck[0].Since)
	}
}

// What holds a handoff is read only for a handoff past the bound, so a queue
// that turns over costs no read of its holds.
func TestAFreshHandoffsHoldsAreNotRead(t *testing.T) {
	c := newCity()
	c.handoff("tk-fresh", 3*time.Hour)
	c.stores[tools.Store()].BlockedErr = errors.New("the holds were read")
	if out := c.look(t); len(out.Failures) > 0 || len(out.Record.Stuck) != 0 {
		t.Fatalf("outcome %+v", out)
	}
}

// counted is a store that keeps how many rows each of its finds returned.
type counted struct {
	*fake.Store
	rows []int
}

func (s *counted) Find(q gcbd.Query) ([]gcbd.Bead, error) {
	rows, err := s.Store.Find(q)
	s.rows = append(s.rows, len(rows))
	return rows, err
}

// unrelated puts n rows of each kind that is not in a refinery's queue, each
// past the bound and carrying a branch: a wisp, a template, a gate and an
// agent bead assigned to the refinery, a closed and a claimed bead assigned to
// it, another agent's handoff, and unassigned work.
func unrelated(s *fake.Store, n int) {
	for i := range n {
		for _, b := range []fake.Bead{
			{ID: fmt.Sprintf("tk-wisp-%d", i), Status: "open", IssueType: "task", Assignee: ref, Ephemeral: true},
			{ID: fmt.Sprintf("tk-mol-%d", i), Status: "open", IssueType: "molecule", Assignee: ref, Template: true},
			{ID: fmt.Sprintf("tk-gate-%d", i), Status: "open", IssueType: "gate", Assignee: ref},
			{ID: fmt.Sprintf("tk-agent-%d", i), Status: "open", IssueType: "agent", Assignee: ref},
			{ID: fmt.Sprintf("tk-done-%d", i), Status: "closed", IssueType: "task", Assignee: ref},
			{ID: fmt.Sprintf("tk-claimed-%d", i), Status: "in_progress", IssueType: "task", Assignee: ref},
			{ID: fmt.Sprintf("tk-witness-%d", i), Status: "open", IssueType: "task", Assignee: "tools/gc-toolkit.witness"},
			{ID: fmt.Sprintf("tk-step-%d", i), Status: "open", IssueType: "task"},
		} {
			b.Title, b.UpdatedAt, b.Metadata = b.ID, stamp(9*time.Hour), map[string]string{"branch": "polecat/" + b.ID}
			s.Put(b)
		}
	}
}

// The look reads a rig's queue through one bounded selection for each of its
// refineries, the refinery's open beads that bd's listing shows, and after it
// only by the ids of what holds a handoff past the bound. So rows of any other
// kind, however many the store holds, add neither a read nor a row to the pass,
// and every read runs under the look's deadline.
func TestTheQueueReadIsBoundedAndKeepsItsBudget(t *testing.T) {
	type pass struct {
		finds []gcbd.Query
		rows  []int
		left  time.Duration
	}
	look := func(noise int) pass {
		c := newCity()
		c.handoff("tk-stuck", 5*time.Hour)
		c.handoff("tk-fresh", time.Hour)
		unrelated(c.stores[tools.Store()], noise)
		s := &counted{Store: c.stores[tools.Store()]}
		var p pass
		open := func(ctx context.Context, db string) (*ledger.Ledger, error) {
			if db != tools.Store() {
				return c.open(ctx, db)
			}
			if d, ok := ctx.Deadline(); ok {
				p.left = time.Until(d)
			}
			return ledger.New(s), nil
		}
		out := (&Queue{City: c, Open: open, Now: func() time.Time { return t0 }}).Run()
		if len(out.Failures) > 0 || !reflect.DeepEqual(stuckIDs(out.Record), []string{"tk-stuck"}) {
			t.Fatalf("with %d unrelated rows of each kind: failures %v, stuck %v", noise, out.Failures, stuckIDs(out.Record))
		}
		p.finds, p.rows = s.Finds(), s.rows
		return p
	}
	quiet, noisy := look(0), look(50)
	want := gcbd.Query{Assignee: ref, Statuses: []string{"open"}, Listed: true}
	if len(quiet.finds) == 0 || !reflect.DeepEqual(quiet.finds[0], want) || quiet.rows[0] != 2 {
		t.Fatalf("the reads = %+v of %v rows; want the first %+v, of the two handoffs", quiet.finds, quiet.rows, want)
	}
	for _, q := range quiet.finds[1:] {
		if len(q.IDs) == 0 {
			t.Errorf("a read after the queue's = %+v; want a read by the ids of what holds the handoff past the bound", q)
		}
	}
	if !reflect.DeepEqual(noisy.finds, quiet.finds) || !reflect.DeepEqual(noisy.rows, quiet.rows) {
		t.Errorf("unrelated rows changed the pass: reads %+v of %v rows, want %+v of %v", noisy.finds, noisy.rows, quiet.finds, quiet.rows)
	}
	if noisy.left <= 0 || noisy.left > Deadline {
		t.Errorf("the queue was read with %s left; want every read under the look's deadline of %s", noisy.left, Deadline)
	}
}

// A rig list or an agent list that does not read judges nothing and fails the
// run.
func TestAReadTheLookRestsOnFailsTheRun(t *testing.T) {
	for _, tc := range []struct {
		name string
		set  func(c *city)
		want string
	}{
		{"rigs", func(c *city) { c.RigsErr = errors.New("gc rig list did not read: exit 1") }, "the rig list did not read"},
		{"agents", func(c *city) { c.AgentsErr = errors.New("gc agent list did not read: exit 1") }, "the agent list did not read"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			c := newCity()
			c.handoff("tk-stuck", 9*time.Hour)
			tc.set(c)
			out := c.look(t)
			if out.Record != nil || out.Recorded || len(out.Failures) != 1 || !strings.Contains(out.Failures[0], tc.want) || len(c.Emitted()) != 0 {
				t.Fatalf("outcome %+v", out)
			}
		})
	}
}

// A queue whose listing, or whose holds, does not read is left out and fails
// the run, and a handoff found in another rig's queue is still recorded.
func TestAnUnreadQueueFailsTheRunAndKeepsWhatWasFound(t *testing.T) {
	for _, tc := range []struct {
		name string
		set  func(c *city, other *fake.Store)
		want string
	}{
		{"the listing", func(c *city, other *fake.Store) { other.FindErr = &gcbd.ReadError{Reason: "gc bd list exited 1"} }, "gc bd list exited 1"},
		{"the holds", func(c *city, other *fake.Store) { other.BlockedErr = &gcbd.ReadError{Reason: "gc bd blocked exited 1"} }, "what holds its handoffs past the bound did not read"},
		{"the store", func(c *city, other *fake.Store) {
			c.openErr["/city/rigs/other/.beads"] = &gcbd.ReadError{Reason: "no store"}
		}, "no store"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			c := newCity()
			other := gascity.Rig{Name: "other", Path: "/city/rigs/other", Prefix: "ot"}
			c.RigList = append(c.RigList, other)
			c.AgentList = append(c.AgentList, gascity.Agent{Name: "refinery", QualifiedName: "other/gc-toolkit.refinery", Dir: "other"})
			c.stores[other.Store()] = fake.New()
			c.stores[other.Store()].Put(fake.Bead{ID: "ot-stuck", Title: "o", Status: "open", IssueType: "task", Assignee: "other/gc-toolkit.refinery",
				UpdatedAt: stamp(9 * time.Hour), Metadata: map[string]string{"branch": "polecat/ot-stuck"}})
			c.handoff("tk-stuck", 9*time.Hour)
			tc.set(c, c.stores[other.Store()])
			out := c.look(t)
			if !out.Recorded || !reflect.DeepEqual(stuckIDs(out.Record), []string{"tk-stuck"}) {
				t.Fatalf("outcome %+v", out)
			}
			if len(out.Failures) != 1 || !strings.Contains(out.Failures[0], "the refinery queue of other did not read") || !strings.Contains(out.Failures[0], tc.want) {
				t.Fatalf("failures %v", out.Failures)
			}
		})
	}
}

// The HQ has no refinery queue, so its store is not read, while a rig that no
// refinery serves is a queue whose address does not resolve, which fails the
// run with what the other rigs gave still recorded.
func TestARigNoRefineryServesFailsTheRun(t *testing.T) {
	c := newCity()
	c.openErr[hq.Store()] = errors.New("the HQ store was read")
	c.AgentList = append(c.AgentList, gascity.Agent{Name: "refinery", QualifiedName: "gc-toolkit.refinery"})
	c.handoff("tk-stuck", 9*time.Hour)
	if out := c.look(t); len(out.Failures) > 0 || !reflect.DeepEqual(stuckIDs(out.Record), []string{"tk-stuck"}) {
		t.Fatalf("outcome %+v", out)
	}
	bare := gascity.Rig{Name: "bare", Path: "/city/rigs/bare", Prefix: "br"}
	c.RigList = append(c.RigList, bare)
	c.openErr[bare.Store()] = errors.New("the bare rig's store was read")
	out := c.look(t)
	if !out.Recorded || !reflect.DeepEqual(stuckIDs(out.Record), []string{"tk-stuck"}) {
		t.Fatalf("outcome %+v", out)
	}
	if len(out.Failures) != 1 || !strings.Contains(out.Failures[0], "the refinery queue of bare did not read") || !strings.Contains(out.Failures[0], "no queue address resolves") {
		t.Fatalf("failures %v", out.Failures)
	}
}

// An event that is not recorded fails the run, and a look that finds nothing
// records nothing.
func TestTheEvent(t *testing.T) {
	c := newCity()
	if out := c.look(t); len(out.Failures) > 0 || out.Recorded || out.Record == nil || len(c.Emitted()) != 0 {
		t.Fatalf("an empty look %+v", out)
	}
	c.handoff("tk-stuck", 9*time.Hour)
	c.EmitErr = errors.New("gc event emit did not submit the event")
	out := c.look(t)
	if out.Recorded || len(out.Failures) != 1 || !strings.Contains(out.Failures[0], "was not recorded") {
		t.Fatalf("outcome %+v", out)
	}
}

// The payload's keys are the ones a reader of the event names, so a change to
// one is a change to its contract.
func TestThePayloadsKeys(t *testing.T) {
	raw, err := json.Marshal(Record{Read: t0, Stuck: []Stuck{{Rig: "r", Bead: "b", Refinery: "f", Since: t0}}, Unread: []Unread{{Rig: "r", Why: "w"}}})
	if err != nil {
		t.Fatal(err)
	}
	var shape map[string]any
	if err := json.Unmarshal(raw, &shape); err != nil {
		t.Fatal(err)
	}
	keys := func(v any) []string {
		var out []string
		for k := range v.(map[string]any) {
			out = append(out, k)
		}
		slices.Sort(out)
		return out
	}
	for _, tc := range []struct {
		at   any
		want []string
	}{
		{shape, []string{"read", "stuck", "unread"}},
		{shape["stuck"].([]any)[0], []string{"bead", "refinery", "rig", "since"}},
		{shape["unread"].([]any)[0], []string{"rig", "why"}},
	} {
		if got := keys(tc.at); !reflect.DeepEqual(got, tc.want) {
			t.Errorf("keys %v, want %v", got, tc.want)
		}
	}
}

// A suspended rig's queue is not read, as core's orphan sweep reads none.
func TestASuspendedRigIsNotRead(t *testing.T) {
	c := newCity()
	off := gascity.Rig{Name: "off", Path: "/city/rigs/off", Prefix: "of", Suspended: true}
	c.RigList = append(c.RigList, off)
	c.AgentList = append(c.AgentList, gascity.Agent{Name: "refinery", QualifiedName: "off/gc-toolkit.refinery", Dir: "off"})
	c.openErr[off.Store()] = errors.New("the suspended rig's store was opened")
	c.handoff("tk-stuck", 9*time.Hour)
	out := c.look(t)
	if len(out.Failures) > 0 || !reflect.DeepEqual(stuckIDs(out.Record), []string{"tk-stuck"}) {
		t.Fatalf("outcome %+v", out)
	}
}
