package session

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
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

var t0 = time.Date(2026, 11, 16, 23, 0, 0, 0, time.UTC)

func ago(d time.Duration) time.Time { return t0.Add(-d) }

func stamp(d time.Duration) string { return ago(d).Format(time.RFC3339) }

// The city the tests run in: an HQ whose store holds the session beads, and one
// rig, tools.
var (
	hq    = gascity.Rig{Name: "city", Path: "/city", Prefix: "hq", HQ: true}
	tools = gascity.Rig{Name: "tools", Path: "/city/rigs/tools", Prefix: "tk"}
)

// city is the runtime and the stores a look reads.
type city struct {
	*gcfake.Roster
	*gcfake.EventLog
	stores  map[string]*fake.Store
	openErr map[string]error
}

func newCity(sessions ...gascity.Session) *city {
	c := &city{
		Roster:   &gcfake.Roster{SessionList: sessions, RigList: []gascity.Rig{hq, tools}},
		EventLog: &gcfake.EventLog{Now: func() time.Time { return t0 }},
		stores:   map[string]*fake.Store{hq.Store(): fake.New(), tools.Store(): fake.New()},
		openErr:  map[string]error{},
	}
	return c
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

func (c *city) progress(t *testing.T) Outcome {
	t.Helper()
	p := &Progress{City: c, Open: c.open, Now: func() time.Time { return t0 }}
	return p.Run(context.Background())
}

// seat is a pool seat's listed session and its session bead in the city store.
func (c *city) seat(s gascity.Session, meta map[string]string) {
	c.SessionList = append(c.SessionList, s)
	c.stores[hq.Store()].Put(fake.Bead{ID: s.ID, Title: s.ID, Status: "open", IssueType: "session", Metadata: meta})
}

func (c *city) claim(rig gascity.Rig, id, status, assignee, session string) {
	c.stores[rig.Store()].Put(fake.Bead{ID: id, Title: id, Status: status, IssueType: "task", Assignee: assignee,
		Metadata: map[string]string{"gc.session_id": session}})
}

func pool(woke time.Duration) map[string]string {
	return map[string]string{"pool_managed": "true", "last_woke_at": stamp(woke)}
}

func busy(id string) gascity.Session {
	return gascity.Session{ID: id, State: "active", AgentName: "tools/gc-toolkit.polecat-1", CreatedAt: ago(10 * time.Hour), LastActive: ago(30 * time.Second)}
}

func stalledIDs(rec *Record) []string {
	var out []string
	for _, s := range rec.Stalled {
		out = append(out, s.Session+"@"+s.Bead)
	}
	return out
}

// A busy pool seat that has written nothing since it woke over three hours
// ago is stalled, and the look records one event that names it.
func TestASeatSilentSinceItWokeIsStalled(t *testing.T) {
	c := newCity(gascity.Session{ID: "hq-ctl", State: "active"})
	c.seat(busy("hq-1"), pool(4*time.Hour))
	c.claim(tools, "tk-1", "in_progress", "hq-1", "hq-1")
	out := c.progress(t)
	if len(out.Failures) > 0 || !out.Recorded {
		t.Fatalf("failures %v, recorded %v", out.Failures, out.Recorded)
	}
	want := []Stalled{{Rig: "tools", Bead: "tk-1", Session: "hq-1", Identity: "hq-1", Agent: "tools/gc-toolkit.polecat-1", Since: ago(4 * time.Hour)}}
	if !reflect.DeepEqual(out.Record.Stalled, want) {
		t.Fatalf("stalled %+v", out.Record.Stalled)
	}
	got := c.Emitted()
	if len(got) != 1 || got[0].Type != EventType || got[0].Actor != Actor || !strings.Contains(got[0].Message, "hq-1 holding tk-1") {
		t.Fatalf("emitted %+v", got)
	}
	var rec Record
	if err := json.Unmarshal(got[0].Payload, &rec); err != nil || !reflect.DeepEqual(rec.Stalled, want) {
		t.Errorf("payload %s: %v", got[0].Payload, err)
	}
}

// A seat's silence runs from its newest write as its identity, in the claim's
// store or the city's, and from no earlier than its last wake.
func TestTheSilenceRunsFromTheNewestWriteSinceTheWake(t *testing.T) {
	c := newCity(gascity.Session{ID: "hq-ctl", State: "active"})
	for _, id := range []string{"hq-rig", "hq-city", "hq-old", "hq-stale"} {
		c.seat(busy(id), pool(6*time.Hour))
	}
	c.seat(busy("hq-woke"), pool(2*time.Hour))
	c.claim(tools, "tk-rig", "in_progress", "hq-rig", "hq-rig")
	c.claim(tools, "tk-city", "in_progress", "hq-city", "hq-city")
	c.claim(tools, "tk-old", "in_progress", "hq-old", "hq-old")
	c.claim(tools, "tk-stale", "in_progress", "hq-stale", "hq-stale")
	c.claim(tools, "tk-woke", "in_progress", "hq-woke", "hq-woke")
	c.stores[tools.Store()].SetLastWrite("hq-rig", ago(time.Hour))
	c.stores[hq.Store()].SetLastWrite("hq-city", ago(2*time.Hour))
	c.stores[tools.Store()].SetLastWrite("hq-old", ago(4*time.Hour))
	c.stores[hq.Store()].SetLastWrite("hq-stale", ago(5*time.Hour))
	c.stores[tools.Store()].SetLastWrite("hq-woke", ago(5*time.Hour))
	out := c.progress(t)
	if len(out.Failures) > 0 {
		t.Fatal(out.Failures)
	}
	if got := stalledIDs(out.Record); !reflect.DeepEqual(got, []string{"hq-old@tk-old", "hq-stale@tk-stale"}) {
		t.Fatalf("stalled %v", got)
	}
	if s := out.Record.Stalled[0]; !s.Wrote || !s.Since.Equal(ago(4*time.Hour)) {
		t.Errorf("hq-old %+v", s)
	}
}

// Only a busy pool seat's claim is judged: a quiet pane, a seat that is no pool
// seat, a bead not in progress, a session not listed, and a claim assigned to
// another identity than the one its seat's writes carry are each passed over.
func TestOnlyABusyPoolSeatsClaimIsJudged(t *testing.T) {
	c := newCity(gascity.Session{ID: "hq-ctl", State: "active"})
	quiet := busy("hq-quiet")
	quiet.LastActive = ago(5 * time.Minute)
	c.seat(quiet, pool(5*time.Hour))
	c.seat(busy("hq-named"), map[string]string{"last_woke_at": stamp(5 * time.Hour)})
	c.seat(busy("hq-open"), pool(5*time.Hour))
	aliased := busy("hq-alias")
	aliased.Alias = "tools/gc-toolkit.tk-9"
	c.seat(aliased, pool(5*time.Hour))
	c.claim(tools, "tk-quiet", "in_progress", "hq-quiet", "hq-quiet")
	c.claim(tools, "tk-named", "in_progress", "hq-named", "hq-named")
	c.claim(tools, "tk-open", "open", "hq-open", "hq-open")
	c.claim(tools, "tk-gone", "in_progress", "hq-gone", "hq-gone")
	c.claim(tools, "tk-by-id", "in_progress", "hq-alias", "hq-alias")
	c.claim(tools, "tk-by-alias", "in_progress", "tools/gc-toolkit.tk-9", "hq-alias")
	out := c.progress(t)
	if len(out.Failures) > 0 {
		t.Fatal(out.Failures)
	}
	if got := stalledIDs(out.Record); !reflect.DeepEqual(got, []string{"hq-alias@tk-by-alias"}) {
		t.Fatalf("stalled %v", got)
	}
	if out.Record.Stalled[0].Identity != "tools/gc-toolkit.tk-9" {
		t.Errorf("identity %q", out.Record.Stalled[0].Identity)
	}
}

// A seat whose session bead names no wake is counted from when its session was
// created.
func TestASeatWithNoWakeCountsFromItsCreation(t *testing.T) {
	c := newCity(gascity.Session{ID: "hq-ctl", State: "active"})
	young := busy("hq-young")
	young.CreatedAt = ago(time.Hour)
	c.seat(young, map[string]string{"pool_managed": "true"})
	c.seat(busy("hq-elder"), map[string]string{"pool_managed": "true"})
	c.claim(tools, "tk-young", "in_progress", "hq-young", "hq-young")
	c.claim(tools, "tk-elder", "in_progress", "hq-elder", "hq-elder")
	out := c.progress(t)
	if got := stalledIDs(out.Record); len(out.Failures) > 0 || !reflect.DeepEqual(got, []string{"hq-elder@tk-elder"}) {
		t.Fatalf("stalled %v, failures %v", got, out.Failures)
	}
}

// A look that finds no stalled seat records nothing and succeeds.
func TestNothingFoundRecordsNothing(t *testing.T) {
	c := newCity(gascity.Session{ID: "hq-ctl", State: "active"})
	c.seat(busy("hq-1"), pool(time.Hour))
	c.claim(tools, "tk-1", "in_progress", "hq-1", "hq-1")
	out := c.progress(t)
	if len(out.Failures) > 0 || out.Recorded || len(out.Record.Stalled) != 0 || len(c.Emitted()) != 0 {
		t.Fatalf("outcome %+v, emitted %+v", out, c.Emitted())
	}
}

// A read the whole look rests on that fails judges nothing and fails the run:
// the session list, a list with no session, the rig list, and a rig list with
// no HQ.
func TestAReadTheLookRestsOnFailsTheRun(t *testing.T) {
	for _, tc := range []struct {
		name string
		set  func(c *city)
		want string
	}{
		{"sessions", func(c *city) { c.SessionsErr = errors.New("gc session list did not read: exit 1") }, "the session list did not read"},
		{"empty", func(c *city) { c.SessionList = nil }, "listed no session"},
		{"rigs", func(c *city) { c.RigsErr = errors.New("gc rig list did not read: exit 1") }, "the rig list did not read"},
		{"no hq", func(c *city) { c.RigList = []gascity.Rig{tools} }, "names no HQ"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			c := newCity(gascity.Session{ID: "hq-ctl", State: "active"})
			c.seat(busy("hq-1"), pool(5*time.Hour))
			c.claim(tools, "tk-1", "in_progress", "hq-1", "hq-1")
			tc.set(c)
			out := c.progress(t)
			if out.Record != nil || out.Recorded || len(out.Failures) != 1 || !strings.Contains(out.Failures[0], tc.want) {
				t.Fatalf("outcome %+v", out)
			}
			if len(c.Emitted()) != 0 {
				t.Errorf("emitted %+v", c.Emitted())
			}
		})
	}
}

// A rig whose store does not read is left out and fails the run, and a seat
// found in another rig is still recorded.
func TestAnUnreadRigFailsTheRunAndKeepsWhatWasFound(t *testing.T) {
	c := newCity(gascity.Session{ID: "hq-ctl", State: "active"})
	other := gascity.Rig{Name: "other", Path: "/city/rigs/other", Prefix: "ot"}
	c.RigList = append(c.RigList, other)
	c.openErr[other.Store()] = errors.New("the store's read failed: gc bd list exited 1")
	c.seat(busy("hq-1"), pool(5*time.Hour))
	c.claim(tools, "tk-1", "in_progress", "hq-1", "hq-1")
	out := c.progress(t)
	if !out.Recorded || len(out.Record.Stalled) != 1 {
		t.Fatalf("outcome %+v", out)
	}
	if len(out.Failures) != 1 || !strings.Contains(out.Failures[0], "the store of other did not read") {
		t.Fatalf("failures %v", out.Failures)
	}
	if !reflect.DeepEqual(out.Record.Unread, []Unread{{Rig: "other", Why: "the store's read failed: gc bd list exited 1"}}) {
		t.Errorf("unread %+v", out.Record.Unread)
	}
}

// A store whose write log does not read leaves the seats it would judge
// unjudged, and fails the run.
func TestAnUnreadWriteLogLeavesItsSeatsUnjudged(t *testing.T) {
	c := newCity(gascity.Session{ID: "hq-ctl", State: "active"})
	c.seat(busy("hq-1"), pool(5*time.Hour))
	c.claim(tools, "tk-1", "in_progress", "hq-1", "hq-1")
	c.stores[tools.Store()].LastWritesErr = errors.New("the store's read failed: gc bd sql exited 1")
	out := c.progress(t)
	if out.Recorded || len(out.Record.Stalled) != 0 || len(out.Failures) != 1 || !strings.Contains(out.Failures[0], "tk-1 in tools was not judged") {
		t.Fatalf("outcome %+v", out)
	}
}

// A session bead the city's store does not hold, or one whose wake does not
// read as a time, leaves its claim unjudged.
func TestAnUnreadSessionBeadLeavesItsClaimUnjudged(t *testing.T) {
	c := newCity(gascity.Session{ID: "hq-ctl", State: "active"})
	c.SessionList = append(c.SessionList, busy("hq-nobead"))
	c.seat(busy("hq-bad"), map[string]string{"pool_managed": "true", "last_woke_at": "yesterday"})
	c.claim(tools, "tk-nobead", "in_progress", "hq-nobead", "hq-nobead")
	c.claim(tools, "tk-bad", "in_progress", "hq-bad", "hq-bad")
	out := c.progress(t)
	if len(out.Failures) != 2 || len(out.Record.Unread) != 2 {
		t.Fatalf("outcome %+v", out)
	}
	if !strings.Contains(out.Failures[0], "tk-nobead") && !strings.Contains(out.Failures[1], "tk-nobead") {
		t.Errorf("failures %v", out.Failures)
	}
}

// An event that is not recorded fails the run.
func TestAnUnrecordedEventFailsTheRun(t *testing.T) {
	c := newCity(gascity.Session{ID: "hq-ctl", State: "active"})
	c.seat(busy("hq-1"), pool(5*time.Hour))
	c.claim(tools, "tk-1", "in_progress", "hq-1", "hq-1")
	c.EmitErr = errors.New("gc event emit did not submit the event")
	out := c.progress(t)
	if out.Recorded || len(out.Failures) != 1 || !strings.Contains(out.Failures[0], "was not recorded") {
		t.Fatalf("outcome %+v", out)
	}
}

// A bead names its owner by the session that claimed it and its assignee, each
// when it carries one.
func TestOwnerOf(t *testing.T) {
	s := fake.New()
	s.Put(fake.Bead{ID: "tk-1", Status: "open", Assignee: "rig/gc-toolkit.refinery",
		Metadata: map[string]string{"gc.session_id": "hq-a"}})
	s.Put(fake.Bead{ID: "tk-2", Status: "open"})
	recs, err := ledger.New(s).Find(ledger.ByID("tk-1", "tk-2"))
	if err != nil || len(recs) != 2 {
		t.Fatal(recs, err)
	}
	if o, err := OwnerOf(recs[0]); err != nil || o != (Owner{SessionID: "hq-a", Assignee: "rig/gc-toolkit.refinery"}) {
		t.Fatalf("owner %+v, %v", o, err)
	}
	if o, err := OwnerOf(recs[1]); err != nil || o != (Owner{}) {
		t.Errorf("an unowned bead %+v, %v", o, err)
	}
}

// The payload's keys are the ones a reader of the event names, so a change to
// one is a change to its contract.
func TestThePayloadsKeys(t *testing.T) {
	raw, err := json.Marshal(Record{Read: t0, Stalled: []Stalled{{Rig: "r", Bead: "b", Session: "s", Identity: "i", Agent: "a", Since: t0, Wrote: true}},
		Unread: []Unread{{Rig: "r", Bead: "b", Why: "w"}}})
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
		{shape, []string{"read", "stalled", "unread"}},
		{shape["stalled"].([]any)[0], []string{"agent", "bead", "identity", "rig", "session", "since", "wrote"}},
		{shape["unread"].([]any)[0], []string{"bead", "rig", "why"}},
	} {
		if got := keys(tc.at); !reflect.DeepEqual(got, tc.want) {
			t.Errorf("keys %v, want %v", got, tc.want)
		}
	}
}

// A suspended rig's store is not read, as core's orphan sweep reads none.
func TestASuspendedRigIsNotRead(t *testing.T) {
	c := newCity(gascity.Session{ID: "hq-ctl", State: "active"})
	off := gascity.Rig{Name: "off", Path: "/city/rigs/off", Prefix: "of", Suspended: true}
	c.RigList = append(c.RigList, off)
	c.openErr[off.Store()] = errors.New("the suspended rig's store was opened")
	c.seat(busy("hq-1"), pool(5*time.Hour))
	c.claim(tools, "tk-1", "in_progress", "hq-1", "hq-1")
	out := c.progress(t)
	if len(out.Failures) > 0 || !reflect.DeepEqual(stalledIDs(out.Record), []string{"hq-1@tk-1"}) {
		t.Fatalf("outcome %+v", out)
	}
}

// emitUnderContext is a city whose event, like the gc call that records it,
// does not run once its context has ended.
type emitUnderContext struct{ *city }

func (c emitUnderContext) Emit(ctx context.Context, e gascity.Emit) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	return c.city.Emit(ctx, e)
}

// The event runs under the look's context, so a look stopped before its event
// records none. The fake's reads take no context, so the look still finds a
// seat to name.
func TestALookWhoseContextEndedRecordsNoEvent(t *testing.T) {
	c := newCity(gascity.Session{ID: "hq-ctl", State: "active"})
	c.seat(busy("hq-1"), pool(4*time.Hour))
	c.claim(tools, "tk-1", "in_progress", "hq-1", "hq-1")
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	out := (&Progress{City: emitUnderContext{c}, Open: c.open, Now: func() time.Time { return t0 }}).Run(ctx)
	if len(out.Record.Stalled) != 1 || out.Recorded || len(c.Emitted()) != 0 {
		t.Fatalf("stalled %+v, recorded %v, emitted %+v", out.Record.Stalled, out.Recorded, c.Emitted())
	}
}
