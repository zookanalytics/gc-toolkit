package worktree

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

var (
	hq    = gascity.Rig{Name: "city", Path: "/city", Prefix: "hq", HQ: true}
	tools = gascity.Rig{Name: "tools", Path: "/city/rigs/tools", Prefix: "tk"}
)

// city is the runtime and the stores the look reads. Its listed sessions are a
// controller session, a live polecat hq-live, and a refinery that carries its
// alias.
type city struct {
	*gcfake.Roster
	*gcfake.EventLog
	stores  map[string]*fake.Store
	openErr map[string]error
}

func newCity() *city {
	return &city{
		Roster: &gcfake.Roster{
			SessionList: []gascity.Session{
				{ID: "hq-ctl", Alias: "control-dispatcher", State: "active"},
				{ID: "hq-live", SessionName: "tools__polecat-hq-live", AgentName: "tools/gc-toolkit.polecat-1", State: "active"},
				{ID: "hq-ref", Alias: "tools/gc-toolkit.refinery", State: "asleep"},
			},
			RigList: []gascity.Rig{hq, tools},
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

func (c *city) salvage(t *testing.T) Outcome {
	t.Helper()
	return (&Salvage{City: c, Open: c.open, Now: func() time.Time { return t0 }}).Run()
}

func (c *city) put(b fake.Bead) {
	if b.Title == "" {
		b.Title = b.ID
	}
	if b.IssueType == "" {
		b.IssueType = "task"
	}
	c.stores[tools.Store()].Put(b)
}

func meta(kv ...string) map[string]string {
	m := map[string]string{}
	for i := 0; i+1 < len(kv); i += 2 {
		m[kv[i]] = kv[i+1]
	}
	return m
}

func found(rec *Record) []string {
	out := []string{}
	for _, o := range rec.Found {
		out = append(out, o.Bead)
	}
	return out
}

// A claim whose session no live session answers to is orphaned work, and so
// is a bead Gas City released, which still names the session that held it.
// The look records one event naming each, with the tree and branch it names.
func TestADeadOwnersWorkIsFound(t *testing.T) {
	c := newCity()
	c.put(fake.Bead{ID: "tk-claim", Status: "in_progress", Assignee: "hq-dead",
		Metadata: meta("gc.session_id", "hq-dead", "gc.session_name", "tools__polecat-hq-dead", "work_dir", "/wt/tk-claim", "branch", "polecat/tk-claim")})
	c.put(fake.Bead{ID: "tk-released", Status: "open", Metadata: meta("gc.session_id", "hq-gone", "gc.session_name", "tools__polecat-hq-gone")})
	out := c.salvage(t)
	if len(out.Failures) > 0 || !out.Recorded {
		t.Fatalf("failures %v, recorded %v", out.Failures, out.Recorded)
	}
	want := []Orphan{
		{Rig: "tools", Bead: "tk-claim", Status: "in_progress", Assignee: "hq-dead", SessionID: "hq-dead", SessionName: "tools__polecat-hq-dead", WorkDir: "/wt/tk-claim", Branch: "polecat/tk-claim"},
		{Rig: "tools", Bead: "tk-released", Status: "open", SessionID: "hq-gone", SessionName: "tools__polecat-hq-gone"},
	}
	if !reflect.DeepEqual(out.Record.Found, want) {
		t.Fatalf("found %+v", out.Record.Found)
	}
	got := c.Emitted()
	if len(got) != 1 || got[0].Type != EventType || got[0].Actor != Actor || got[0].Message != "beads whose owner no live session answers to: tk-claim, tk-released" {
		t.Fatalf("emitted %+v", got)
	}
	var rec Record
	if err := json.Unmarshal(got[0].Payload, &rec); err != nil || !reflect.DeepEqual(rec.Found, want) {
		t.Errorf("payload %s: %v", got[0].Payload, err)
	}
}

// An owner is live when a live session answers to any identity it goes by: a
// claim whose session died but whose alias a live session now carries stays
// with that session, and so does a bead that names a live session by its
// runtime name or a rig-qualified form of its alias.
func TestAnOwnerAnyLiveSessionAnswersToIsLive(t *testing.T) {
	c := newCity()
	c.put(fake.Bead{ID: "tk-live", Status: "in_progress", Assignee: "hq-live", Metadata: meta("gc.session_id", "hq-live")})
	c.put(fake.Bead{ID: "tk-alias", Status: "open", Assignee: "tools/gc-toolkit.refinery", Metadata: meta("gc.session_id", "hq-dead")})
	c.put(fake.Bead{ID: "tk-name", Status: "in_progress", Metadata: meta("gc.session_name", "tools__polecat-hq-live")})
	c.put(fake.Bead{ID: "tk-bare", Status: "in_progress", Assignee: "other/control-dispatcher"})
	c.put(fake.Bead{ID: "tk-unowned", Status: "open"})
	out := c.salvage(t)
	if len(out.Failures) > 0 || out.Recorded || len(found(out.Record)) != 0 || len(c.Emitted()) != 0 {
		t.Fatalf("outcome %+v", out)
	}
}

// The reader leaves out what is no session's lost work: work in a PR on its way
// to its target, a conversation, a topology root, a kind bd's listing hides, a
// wisp, a template, and a bead that is neither open nor in progress.
func TestTheReaderLeavesOutWhatIsNoLostWork(t *testing.T) {
	c := newCity()
	dead := func(id string, kv ...string) fake.Bead {
		return fake.Bead{ID: id, Status: "in_progress", Assignee: "hq-dead", Metadata: meta(append([]string{"gc.session_id", "hq-dead"}, kv...)...)}
	}
	for _, mr := range []string{"pre_open_gate", "pull_request", "pull_request_pending", "pull_request_head_changed"} {
		c.put(dead("tk-"+mr, "merge_result", mr))
	}
	c.put(dead("tk-merged", "merge_result", "merged"))
	c.put(fake.Bead{ID: "tk-asked", Status: "open", Assignee: "human"})
	c.put(fake.Bead{ID: "tk-sitting", Status: "in_progress", Assignee: "tools/gc-toolkit.tk-sitting", Metadata: meta("gc.session_id", "hq-dead")})
	c.put(fake.Bead{ID: "tk-sitting2", Status: "in_progress", Assignee: "c-tk-sitting2"})
	for _, kind := range []string{"workflow", "scope", "spec"} {
		c.put(dead("tk-"+kind, "gc.kind", kind))
	}
	c.put(dead("tk-step", "gc.kind", "step"))
	for _, typ := range []string{"gate", "message", "agent", "role"} {
		b := dead("tk-" + typ)
		b.IssueType = typ
		c.put(b)
	}
	wisp := dead("tk-wisp")
	wisp.Ephemeral = true
	c.put(wisp)
	tmpl := dead("tk-template")
	tmpl.Template = true
	c.put(tmpl)
	for _, st := range []string{"blocked", "deferred", "closed"} {
		b := dead("tk-" + st)
		b.Status = st
		c.put(b)
	}
	out := c.salvage(t)
	if len(out.Failures) > 0 {
		t.Fatal(out.Failures)
	}
	if got := found(out.Record); !reflect.DeepEqual(got, []string{"tk-merged", "tk-step"}) {
		t.Fatalf("found %v", got)
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

// The reader reads a rig's store through one bounded selection, its open and
// in-progress beads that bd's listing shows, and after it only by ids, or by a
// key that marks a live run, for what holds the beads it found. So rows outside
// that set, however many the store holds, add neither a read nor a row to the
// pass, though each names a dead owner: closed, blocked and deferred beads, and
// wisps, templates, gates and infrastructure beads. Every read runs under the
// look's deadline.
func TestTheReadIsBoundedAndKeepsItsBudget(t *testing.T) {
	type pass struct {
		finds []gcbd.Query
		rows  []int
		left  time.Duration
	}
	look := func(noise int) pass {
		c := newCity()
		c.put(fake.Bead{ID: "tk-claim", Status: "in_progress", Assignee: "hq-dead", Metadata: meta("gc.session_id", "hq-dead")})
		c.put(fake.Bead{ID: "tk-released", Status: "open", Metadata: meta("gc.session_id", "hq-gone")})
		for i := range noise {
			for _, b := range []fake.Bead{
				{ID: fmt.Sprintf("tk-closed-%d", i), Status: "closed"},
				{ID: fmt.Sprintf("tk-blocked-%d", i), Status: "blocked"},
				{ID: fmt.Sprintf("tk-deferred-%d", i), Status: "deferred"},
				{ID: fmt.Sprintf("tk-wisp-%d", i), Status: "in_progress", Ephemeral: true},
				{ID: fmt.Sprintf("tk-template-%d", i), Status: "in_progress", IssueType: "molecule", Template: true},
				{ID: fmt.Sprintf("tk-gate-%d", i), Status: "open", IssueType: "gate"},
				{ID: fmt.Sprintf("tk-agent-%d", i), Status: "open", IssueType: "agent"},
				{ID: fmt.Sprintf("tk-message-%d", i), Status: "open", IssueType: "message"},
			} {
				b.Assignee, b.Metadata = "hq-dead", meta("gc.session_id", "hq-dead")
				c.put(b)
			}
		}
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
		out := (&Salvage{City: c, Open: open, Now: func() time.Time { return t0 }}).Run()
		if len(out.Failures) > 0 || !reflect.DeepEqual(found(out.Record), []string{"tk-claim", "tk-released"}) {
			t.Fatalf("with %d unrelated rows of each kind: failures %v, found %v", noise, out.Failures, found(out.Record))
		}
		p.finds, p.rows = s.Finds(), s.rows
		return p
	}
	quiet, noisy := look(0), look(50)
	want := gcbd.Query{Every: true, Statuses: []string{"open", "in_progress"}, Listed: true}
	if len(quiet.finds) == 0 || !reflect.DeepEqual(quiet.finds[0], want) || quiet.rows[0] != 2 {
		t.Fatalf("the reads = %+v of %v rows; want the first %+v, of the two candidates", quiet.finds, quiet.rows, want)
	}
	for _, q := range quiet.finds[1:] {
		if q.Every || (len(q.IDs) == 0 && q.HasKey == "") {
			t.Errorf("a read after the rig's = %+v; want a read by ids or by a key", q)
		}
	}
	if !reflect.DeepEqual(noisy.finds, quiet.finds) || !reflect.DeepEqual(noisy.rows, quiet.rows) {
		t.Errorf("unrelated rows changed the pass: reads %+v of %v rows, want %+v of %v", noisy.finds, noisy.rows, quiet.finds, quiet.rows)
	}
	if noisy.left <= 0 || noisy.left > Deadline {
		t.Errorf("the rig was read with %s left; want every read under the look's deadline of %s", noisy.left, Deadline)
	}
}

// A bead a person holds through an open human gate is theirs, whether the gate
// is its own wait or holds it through its parent, and a gate a person answered
// holds nothing.
func TestABeadAPersonHoldsIsLeftOut(t *testing.T) {
	c := newCity()
	s := c.stores[tools.Store()]
	gate := func(id, status string) {
		c.put(fake.Bead{ID: id, Status: status, IssueType: "gate", AwaitType: "human", AwaitID: "polecat-blocked"})
	}
	gate("tk-gate", "open")
	gate("tk-answered", "closed")
	c.put(fake.Bead{ID: "tk-machine", Status: "open", IssueType: "gate", AwaitType: "timer"})
	c.put(fake.Bead{ID: "tk-held", Status: "in_progress", Assignee: "hq-dead", Metadata: meta("gc.session_id", "hq-dead"),
		Edges: []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "tk-gate", Status: "open"}}})
	s.List("tk-held", "tk-gate")
	s.Mark("tk-held")
	c.put(fake.Bead{ID: "tk-parent", Status: "open", IssueType: "epic", Edges: []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "tk-gate", Status: "open"}}})
	s.List("tk-parent", "tk-gate")
	s.Mark("tk-parent")
	c.put(fake.Bead{ID: "tk-child", Status: "open", Metadata: meta("gc.session_id", "hq-dead"),
		Edges: []gcbd.Edge{{Type: gcbd.EdgeParentChild, ID: "tk-parent", Status: "open"}}})
	s.List("tk-child", "tk-parent")
	s.Mark("tk-child")
	c.put(fake.Bead{ID: "tk-ruled", Status: "in_progress", Assignee: "hq-dead", Metadata: meta("gc.session_id", "hq-dead"),
		Edges: []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "tk-answered", Status: "closed", ClosedAt: "2026-11-16T20:00:00Z"}}})
	c.put(fake.Bead{ID: "tk-timed", Status: "in_progress", Assignee: "hq-dead", Metadata: meta("gc.session_id", "hq-dead"),
		Edges: []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "tk-machine", Status: "open"}}})
	s.List("tk-timed", "tk-machine")
	s.Mark("tk-timed")
	out := c.salvage(t)
	if len(out.Failures) > 0 {
		t.Fatal(out.Failures)
	}
	if got := found(out.Record); !reflect.DeepEqual(got, []string{"tk-ruled", "tk-timed"}) {
		t.Fatalf("found %v", got)
	}
}

// A read the whole look rests on that fails judges nothing and fails the run:
// the session list, a list with no session, and the rig list.
func TestAReadTheLookRestsOnFailsTheRun(t *testing.T) {
	for _, tc := range []struct {
		name string
		set  func(c *city)
		want string
	}{
		{"sessions", func(c *city) { c.SessionsErr = errors.New("gc session list did not read: exit 1") }, "the session list did not read"},
		{"empty", func(c *city) { c.SessionList = nil }, "listed no session"},
		{"rigs", func(c *city) { c.RigsErr = errors.New("gc rig list did not read: exit 1") }, "the rig list did not read"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			c := newCity()
			c.put(fake.Bead{ID: "tk-claim", Status: "in_progress", Assignee: "hq-dead", Metadata: meta("gc.session_id", "hq-dead")})
			tc.set(c)
			out := c.salvage(t)
			if out.Record != nil || out.Recorded || len(out.Failures) != 1 || !strings.Contains(out.Failures[0], tc.want) || len(c.Emitted()) != 0 {
				t.Fatalf("outcome %+v", out)
			}
		})
	}
}

// A rig whose store does not read, or whose holds do not read, is left out and
// fails the run, and what another rig's store gave is still recorded.
func TestAnUnreadRigFailsTheRunAndKeepsWhatWasFound(t *testing.T) {
	for _, tc := range []struct {
		name string
		set  func(c *city, other *fake.Store)
	}{
		{"the listing", func(c *city, other *fake.Store) { other.FindErr = &gcbd.ReadError{Reason: "gc bd list exited 1"} }},
		{"the holds", func(c *city, other *fake.Store) { other.BlockedErr = &gcbd.ReadError{Reason: "gc bd blocked exited 1"} }},
		{"the store", func(c *city, other *fake.Store) {
			c.openErr["/city/rigs/other/.beads"] = &gcbd.ReadError{Reason: "gc bd where did not name the store"}
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			c := newCity()
			other := gascity.Rig{Name: "other", Path: "/city/rigs/other", Prefix: "ot"}
			c.RigList = append(c.RigList, other)
			c.stores[other.Store()] = fake.New()
			c.stores[other.Store()].Put(fake.Bead{ID: "ot-claim", Title: "o", Status: "in_progress", IssueType: "task", Metadata: meta("gc.session_id", "hq-dead")})
			c.put(fake.Bead{ID: "tk-claim", Status: "in_progress", Assignee: "hq-dead", Metadata: meta("gc.session_id", "hq-dead")})
			tc.set(c, c.stores[other.Store()])
			out := c.salvage(t)
			if !out.Recorded || !reflect.DeepEqual(found(out.Record), []string{"tk-claim"}) {
				t.Fatalf("outcome %+v", out)
			}
			if len(out.Failures) != 1 || !strings.Contains(out.Failures[0], "the store of other did not read") || len(out.Record.Unread) != 1 {
				t.Fatalf("failures %v, unread %+v", out.Failures, out.Record.Unread)
			}
		})
	}
}

// An event that is not recorded fails the run, and a look that finds nothing
// records nothing.
func TestTheEvent(t *testing.T) {
	c := newCity()
	if out := c.salvage(t); len(out.Failures) > 0 || out.Recorded || out.Record == nil || len(c.Emitted()) != 0 {
		t.Fatalf("an empty look %+v", out)
	}
	c.put(fake.Bead{ID: "tk-claim", Status: "in_progress", Assignee: "hq-dead", Metadata: meta("gc.session_id", "hq-dead")})
	c.EmitErr = errors.New("gc event emit did not submit the event")
	out := c.salvage(t)
	if out.Recorded || len(out.Failures) != 1 || !strings.Contains(out.Failures[0], "was not recorded") {
		t.Fatalf("outcome %+v", out)
	}
}

// The payload's keys are the ones a reader of the event names, so a change to
// one is a change to its contract.
func TestThePayloadsKeys(t *testing.T) {
	raw, err := json.Marshal(Record{Read: t0, Found: []Orphan{{Rig: "r", Bead: "b", Status: "s", Assignee: "a", SessionID: "i", SessionName: "n", WorkDir: "w", Branch: "br"}},
		Unread: []Unread{{Rig: "r", Why: "w"}}})
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
		{shape, []string{"found", "read", "unread"}},
		{shape["found"].([]any)[0], []string{"assignee", "bead", "branch", "rig", "session_id", "session_name", "status", "work_dir"}},
		{shape["unread"].([]any)[0], []string{"rig", "why"}},
	} {
		if got := keys(tc.at); !reflect.DeepEqual(got, tc.want) {
			t.Errorf("keys %v, want %v", got, tc.want)
		}
	}
}

// A suspended rig's store is not read, as core's orphan sweep reads none.
func TestASuspendedRigIsNotRead(t *testing.T) {
	c := newCity()
	off := gascity.Rig{Name: "off", Path: "/city/rigs/off", Prefix: "of", Suspended: true}
	c.RigList = append(c.RigList, off)
	c.openErr[off.Store()] = errors.New("the suspended rig's store was opened")
	c.put(fake.Bead{ID: "tk-claim", Status: "in_progress", Assignee: "hq-dead", Metadata: meta("gc.session_id", "hq-dead")})
	out := c.salvage(t)
	if len(out.Failures) > 0 || !reflect.DeepEqual(found(out.Record), []string{"tk-claim"}) {
		t.Fatalf("outcome %+v", out)
	}
}
