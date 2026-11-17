package doctor

import (
	"context"
	"encoding/json"
	"errors"
	"reflect"
	"slices"
	"strings"
	"testing"
	"time"
	"unicode/utf8"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity/fake"
)

var t0 = time.Date(2026, 11, 16, 12, 0, 0, 0, time.UTC)

// city is a fake event log and doctor on a clock the test moves, whose doctor
// answers the results the test sets next.
type city struct {
	*fake.EventLog
	now     time.Time
	results []gascity.DoctorResult
	run     *gascity.DoctorRun
}

func newCity() *city {
	c := &city{now: t0}
	c.EventLog = &fake.EventLog{Now: func() time.Time { return c.now }}
	c.OnDoctor = func(context.Context) gascity.DoctorRun {
		if c.run != nil {
			return *c.run
		}
		return gascity.DoctorRun{Bounded: gascity.Bounded{Code: 1}, Results: c.results}
	}
	return c
}

// runAt runs once at at, with doctor answering results.
func (c *city) runAt(t *testing.T, at time.Time, accepted []Entry, results ...gascity.DoctorResult) Outcome {
	t.Helper()
	c.now, c.results, c.run = at, results, nil
	r := &Runner{City: c, Now: func() time.Time { return c.now }}
	return r.Run(accepted)
}

func ok(name string) gascity.DoctorResult {
	return gascity.DoctorResult{Name: name, Status: "ok", Severity: "blocking", Message: "fine"}
}

func warn(name string) gascity.DoctorResult {
	return gascity.DoctorResult{Name: name, Status: "warning", Severity: "blocking", Message: name + " is wrong"}
}

func timedOut(name string) gascity.DoctorResult {
	return gascity.DoctorResult{Name: name, Status: "error", Severity: "advisory", TimedOut: true, Message: "timed out after 1m0s and was abandoned (outcome unknown); re-run alone or raise --check-timeout"}
}

func streaks(cs []Check) map[string]string {
	out := map[string]string{}
	for _, c := range cs {
		out[c.Name] = c.FirstFailed.Format("15:04") + "/" + string(rune('0'+c.Streak))
	}
	return out
}

func names[T any](xs []T, name func(T) string) []string {
	out := []string{}
	for _, x := range xs {
		out = append(out, name(x))
	}
	return out
}

func entries(t *testing.T) []Entry {
	t.Helper()
	e, err := ParseAccepted(`
[[accepted]]
check = "hold-label-routed-to"
reason = "a Gas City bug"
ruling = "the design's approval"

[[accepted]]
check = "dolt-compact-state"
for = "3h"
reason = "the compactor's retry"
ruling = "the design's approval"
`)
	if err != nil {
		t.Fatal(err)
	}
	return e
}

// A first run lists each result that is not ok as failing from its own start,
// a streak of one, each one doctor abandoned or its store gate stood in for as
// not measured, and each failing one the accepted file names as accepted, and
// records it all as one event.
func TestAFirstRunListsWhatDoctorFound(t *testing.T) {
	c := newCity()
	out := c.runAt(t, t0, entries(t),
		ok("controller"),
		warn("orphan-sessions"),
		gascity.DoctorResult{Name: "gc-toolkit:check-recycle-capable", Status: "error", Severity: "blocking", Message: "cycle-recycle cannot fire"},
		timedOut("worktree-disk-size"),
		gascity.DoctorResult{Name: "rig:b:beads", Status: "ok", Message: "not checked: suspended (rig:b)"},
		gascity.DoctorResult{Name: "rig:a:beads", Status: "warning", Message: "not checked: store not running (rig:a) while the city's controller is running"},
		warn("hold-label-routed-to"),
		warn("dolt-compact-state"),
		warn("orphan-sessions"),
	)
	if len(out.Failures) != 0 || !out.Recorded {
		t.Fatalf("a run that completed and recorded its event answered %+v", out)
	}
	rec := out.Record
	if !rec.Completed || rec.Why != "" || rec.Measured == nil || !rec.Measured.Equal(t0) || !rec.Started.Equal(t0) {
		t.Fatalf("the record says %+v", rec)
	}
	if got := streaks(rec.Failing); !reflect.DeepEqual(got, map[string]string{"gc-toolkit:check-recycle-capable": "12:00/1", "orphan-sessions": "12:00/1"}) {
		t.Errorf("failing = %v", got)
	}
	wantUnmeasured := []Unmeasured{
		{Name: "rig:a:beads", Why: "not checked: store not running (rig:a) while the city's controller is running"},
		{Name: "rig:b:beads", Why: "not checked: suspended (rig:b)"},
		{Name: "worktree-disk-size", Why: "timed_out"},
	}
	if !reflect.DeepEqual(rec.NotMeasured, wantUnmeasured) {
		t.Errorf("not measured = %+v", rec.NotMeasured)
	}
	if got := names(rec.Accepted, func(a Accepted) string { return a.Name + ":" + a.Entry.For }); !reflect.DeepEqual(got, []string{"dolt-compact-state:3h", "hold-label-routed-to:"}) {
		t.Errorf("accepted = %v", got)
	}
	emitted := c.Emitted()
	if len(emitted) != 1 {
		t.Fatalf("emitted %d events", len(emitted))
	}
	e := emitted[0]
	if e.Type != EventType || e.Actor != Actor || e.Message != "doctor ran: 2 failing, 3 not measured, 2 accepted" {
		t.Errorf("the event is %s by %s saying %q", e.Type, e.Actor, e.Message)
	}
	var back Record
	if err := json.Unmarshal(e.Payload, &back); err != nil || !reflect.DeepEqual(names(back.Failing, func(c Check) string { return c.Name }), names(rec.Failing, func(c Check) string { return c.Name })) {
		t.Errorf("the payload does not read back as the record: %v", err)
	}
	if got := c.Reads(); !reflect.DeepEqual(got, []fake.Read{{Type: EventType}, {Type: "order.completed", Since: 24 * time.Hour}}) {
		t.Errorf("the run read %+v", got)
	}
}

// A check failing again carries the time it first failed and adds one to its
// streak. One measured ok leaves the lists, and its next failure starts a new
// streak at that run.
func TestAFailureCarriesItsFirstTimeAndStreak(t *testing.T) {
	c := newCity()
	c.runAt(t, t0, nil, warn("a"), warn("b"))
	out := c.runAt(t, t0.Add(time.Hour), nil, warn("a"), ok("b"))
	if got := streaks(out.Record.Failing); !reflect.DeepEqual(got, map[string]string{"a": "12:00/2"}) {
		t.Fatalf("second run's failing = %v", got)
	}
	out = c.runAt(t, t0.Add(2*time.Hour), nil, warn("a"), warn("b"))
	if got := streaks(out.Record.Failing); !reflect.DeepEqual(got, map[string]string{"a": "12:00/3", "b": "14:00/1"}) {
		t.Fatalf("third run's failing = %v", got)
	}
	out = c.runAt(t, t0.Add(3*time.Hour), nil, warn("b"))
	if got := streaks(out.Record.Failing); !reflect.DeepEqual(got, map[string]string{"b": "14:00/2"}) {
		t.Fatalf("a check doctor no longer reports is still listed: %v", got)
	}
}

// A check a completed run did not measure is listed as not measured with the
// first failure and streak it had, so the run neither adds to its streak nor
// ends it, and the next run that measures it failing adds one.
func TestAnUnmeasuredCheckKeepsItsStreak(t *testing.T) {
	c := newCity()
	c.runAt(t, t0, nil, warn("a"))
	out := c.runAt(t, t0.Add(time.Hour), nil, timedOut("a"))
	if len(out.Record.Failing) != 0 || len(out.Record.NotMeasured) != 1 {
		t.Fatalf("the unmeasured run lists %+v", out.Record)
	}
	u := out.Record.NotMeasured[0]
	if u.Why != "timed_out" || u.FirstFailed == nil || !u.FirstFailed.Equal(t0) || u.Streak != 1 {
		t.Fatalf("the unmeasured check carries %+v", u)
	}
	out = c.runAt(t, t0.Add(2*time.Hour), nil, gascity.DoctorResult{Name: "a", Status: "warning", Message: "not checked: store not running"})
	if u := out.Record.NotMeasured[0]; u.FirstFailed == nil || !u.FirstFailed.Equal(t0) || u.Streak != 1 {
		t.Fatalf("a second unmeasured run carries %+v", u)
	}
	out = c.runAt(t, t0.Add(3*time.Hour), nil, warn("a"))
	if got := streaks(out.Record.Failing); !reflect.DeepEqual(got, map[string]string{"a": "12:00/2"}) {
		t.Fatalf("the next measured failure = %v", got)
	}
}

// A check a run did not measure carries the accepted file's entry when the
// entry accepts the failure it carries at that run, judged as a failing check
// is, so a reader can tell a failure the operator accepted from one it shows.
// One that carries no failure, or one whose entry's bound has run out, carries
// none.
func TestAnUnmeasuredCheckCarriesTheEntryThatAcceptsItsFailure(t *testing.T) {
	c := newCity()
	acc := entries(t)
	c.runAt(t, t0, acc, warn("hold-label-routed-to"), warn("dolt-compact-state"), warn("orphan-sessions"))
	out := c.runAt(t, t0.Add(time.Hour), acc, timedOut("hold-label-routed-to"), timedOut("dolt-compact-state"), timedOut("orphan-sessions"), timedOut("controller"))
	got := map[string]string{}
	for _, u := range out.Record.NotMeasured {
		got[u.Name] = "none"
		if u.Entry != nil {
			got[u.Name] = u.Entry.Reason + "/" + u.Entry.For
		}
	}
	want := map[string]string{"hold-label-routed-to": "a Gas City bug/", "dolt-compact-state": "the compactor's retry/3h", "orphan-sessions": "none", "controller": "none"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("at 1h the unmeasured entries are %v, want %v", got, want)
	}
	out = c.runAt(t, t0.Add(3*time.Hour), acc, gascity.DoctorResult{Name: "dolt-compact-state", Status: "warning", Message: "not checked: store not running"})
	if u := out.Record.NotMeasured[0]; u.Entry != nil || u.Streak != 1 || u.FirstFailed == nil || !u.FirstFailed.Equal(t0) {
		t.Fatalf("at 3h, past its entry's bound, the unmeasured check carries %+v", u)
	}
}

// A run that did not complete measured nothing: it records why, carries the
// previous run's lists and the time they were measured unchanged, and fails,
// and the next completed run counts the streak as if it had not happened.
func TestAnIncompleteRunCarriesThePreviousLists(t *testing.T) {
	c := newCity()
	c.runAt(t, t0, nil, warn("a"), timedOut("b"))
	c.now = t0.Add(time.Hour)
	c.run = &gascity.DoctorRun{Bounded: gascity.Bounded{Code: -1, Err: gascity.ErrDeadline}}
	out := (&Runner{City: c, Now: func() time.Time { return c.now }}).Run(nil)
	rec := out.Record
	if rec.Completed || rec.Why != "gc doctor did not finish within 20m0s" || !out.Recorded {
		t.Fatalf("the incomplete run answered %+v, record %+v", out, rec)
	}
	if len(out.Failures) != 1 || !strings.Contains(out.Failures[0], "did not complete") {
		t.Errorf("failures = %q", out.Failures)
	}
	if rec.Measured == nil || !rec.Measured.Equal(t0) || !rec.Started.Equal(t0.Add(time.Hour)) {
		t.Errorf("measured %v, started %v", rec.Measured, rec.Started)
	}
	if got := streaks(rec.Failing); !reflect.DeepEqual(got, map[string]string{"a": "12:00/1"}) || len(rec.NotMeasured) != 1 {
		t.Errorf("carried failing %v, not measured %+v", got, rec.NotMeasured)
	}
	if !strings.HasPrefix(c.Emitted()[1].Message, "doctor did not complete: ") {
		t.Errorf("the event says %q", c.Emitted()[1].Message)
	}
	out = c.runAt(t, t0.Add(2*time.Hour), nil, warn("a"))
	if got := streaks(out.Record.Failing); !reflect.DeepEqual(got, map[string]string{"a": "12:00/2"}) {
		t.Fatalf("the run after an incomplete one = %v", got)
	}
}

// A first run that does not complete carries nothing and records empty lists
// with no measured time.
func TestAFirstIncompleteRunListsNothing(t *testing.T) {
	c := newCity()
	c.run = &gascity.DoctorRun{Bounded: gascity.Bounded{Code: 2, Stderr: "gc doctor: no city here\n"}}
	out := (&Runner{City: c, Now: func() time.Time { return c.now }}).Run(nil)
	rec := out.Record
	if rec.Completed || rec.Measured != nil || len(rec.Failing)+len(rec.NotMeasured)+len(rec.Accepted) != 0 || rec.Failing == nil {
		t.Fatalf("record %+v", rec)
	}
	if rec.Why != "gc doctor exited 2: gc doctor: no city here" {
		t.Errorf("why = %q", rec.Why)
	}
}

// A doctor run completes when it exits 0 or 1 and printed a report that reads,
// within the deadline.
func TestIncomplete(t *testing.T) {
	report := []gascity.DoctorResult{}
	for _, tc := range []struct {
		name string
		run  gascity.DoctorRun
		want string
	}{
		{"exit 0 with a report", gascity.DoctorRun{Results: report}, ""},
		{"exit 1 with a report", gascity.DoctorRun{Bounded: gascity.Bounded{Code: 1}, Results: report}, ""},
		{"the deadline", gascity.DoctorRun{Bounded: gascity.Bounded{Code: -1, Err: gascity.ErrDeadline}}, "gc doctor did not finish within 20m0s"},
		{"no start", gascity.DoctorRun{Bounded: gascity.Bounded{Code: -1, Err: errors.New("exec: gc: not found")}}, "gc doctor did not run: exec: gc: not found"},
		{"exit 2", gascity.DoctorRun{Bounded: gascity.Bounded{Code: 2, Stderr: "unknown flag\n"}, Results: report}, "gc doctor exited 2: unknown flag"},
		{"exit 1 with no report", gascity.DoctorRun{Bounded: gascity.Bounded{Code: 1, Stderr: "gc doctor: not in a city\n"}}, "gc doctor exited 1 and printed no report that reads: gc doctor: not in a city"},
	} {
		if got := incomplete(tc.run); got != tc.want {
			t.Errorf("%s: incomplete = %q, want %q", tc.name, got, tc.want)
		}
	}
}

// An entry with a bound accepts its check until the check has failed that
// long, and from then on the check is failing, with the time it first failed.
// An entry with none accepts it however long it fails.
func TestAnAcceptedBoundEnds(t *testing.T) {
	c := newCity()
	acc := entries(t)
	for h := 0; h < 3; h++ {
		out := c.runAt(t, t0.Add(time.Duration(h)*time.Hour), acc, warn("dolt-compact-state"), warn("hold-label-routed-to"))
		if len(out.Record.Failing) != 0 || len(out.Record.Accepted) != 2 {
			t.Fatalf("at %dh the run lists failing %v, accepted %d", h, streaks(out.Record.Failing), len(out.Record.Accepted))
		}
	}
	out := c.runAt(t, t0.Add(3*time.Hour), acc, warn("dolt-compact-state"), warn("hold-label-routed-to"))
	if got := streaks(out.Record.Failing); !reflect.DeepEqual(got, map[string]string{"dolt-compact-state": "12:00/4"}) {
		t.Fatalf("at 3h failing = %v", got)
	}
	if len(out.Record.Accepted) != 1 || out.Record.Accepted[0].Name != "hold-label-routed-to" || out.Record.Accepted[0].Streak != 4 {
		t.Fatalf("at 3h accepted = %+v", out.Record.Accepted)
	}
}

// Each monitor's last good run is its newest order.completed, one row per rig
// for a rig-scoped run, read since the previous run began, less the overlap,
// and a monitor with none in that window keeps the previous run's.
func TestMonitorsLastGoodRun(t *testing.T) {
	c := newCity()
	at := func(d time.Duration) time.Time { return t0.Add(d) }
	c.Add(
		gascity.Event{Type: "order.completed", Subject: "mol-dog-backup", Ts: at(-25 * time.Hour)},
		gascity.Event{Type: "order.completed", Subject: "orphan-sweep", Ts: at(-30 * time.Minute)},
		gascity.Event{Type: "order.completed", Subject: "orphan-work-detect", Ts: at(-10 * time.Minute)},
		gascity.Event{Type: "order.completed", Subject: "orphan-sweep", Ts: at(-5 * time.Minute)},
		gascity.Event{Type: "order.completed", Subject: "reaper", Ts: at(-2 * time.Hour)},
		gascity.Event{Type: "order.completed", Subject: "reaper:rig:b", Ts: at(-3 * time.Hour)},
		gascity.Event{Type: "order.completed", Subject: "reaper:rig:a", Ts: at(-4 * time.Hour)},
		gascity.Event{Type: "order.completed", Subject: "pr-reconcile:rig:a", Ts: at(-1 * time.Minute)},
		gascity.Event{Type: "order.completed", Subject: "reaper-two", Ts: at(-1 * time.Minute)},
		gascity.Event{Type: "order.failed", Subject: "dolt-health", Ts: at(-1 * time.Minute)},
	)
	rows := func(ms []Monitor) []string {
		return names(ms, func(m Monitor) string {
			if m.LastGood == nil {
				return m.Order + "=none"
			}
			return m.Order + "=" + m.LastGood.Sub(t0).String()
		})
	}
	out := c.runAt(t, t0, nil)
	want := []string{"doctor-run=none", "orphan-work-detect=-10m0s", "seat-progress-detect=none", "refinery-queue-detect=none", "spawn-storm-detect=none", "orphan-sweep=-5m0s", "reaper=-2h0m0s", "reaper:rig:a=-4h0m0s", "reaper:rig:b=-3h0m0s", "mol-dog-doctor=none", "mol-dog-backup=none", "dolt-health=none"}
	if got := rows(out.Record.Monitors); !reflect.DeepEqual(got, want) {
		t.Fatalf("first run's monitors = %v", got)
	}
	c.Add(
		gascity.Event{Type: "order.completed", Subject: "orphan-sweep", Ts: at(55 * time.Minute)},
		gascity.Event{Type: "order.completed", Subject: "doctor-run", Ts: at(4 * time.Minute)},
		gascity.Event{Type: "order.completed", Subject: "seat-progress-detect", Ts: at(30 * time.Minute)},
		gascity.Event{Type: "order.completed", Subject: "mol-dog-backup", Ts: at(-24 * time.Hour)},
	)
	out = c.runAt(t, t0.Add(time.Hour), nil)
	want = []string{"doctor-run=4m0s", "orphan-work-detect=-10m0s", "seat-progress-detect=30m0s", "refinery-queue-detect=none", "spawn-storm-detect=none", "orphan-sweep=55m0s", "reaper=-2h0m0s", "reaper:rig:a=-4h0m0s", "reaper:rig:b=-3h0m0s", "mol-dog-doctor=none", "mol-dog-backup=none", "dolt-health=none"}
	if got := rows(out.Record.Monitors); !reflect.DeepEqual(got, want) {
		t.Fatalf("second run's monitors = %v", got)
	}
	if r := c.Reads(); r[len(r)-1] != (fake.Read{Type: "order.completed", Since: 70 * time.Minute}) {
		t.Errorf("the second run read the monitors' runs as %+v", r[len(r)-1])
	}
}

// When the previous run's event does not read, no doctor runs and nothing is
// recorded, so the last record stands.
func TestAnUnreadPreviousEventRecordsNothing(t *testing.T) {
	c := newCity()
	c.ReadErr = map[string]error{EventType: errors.New("gc events --type gc-toolkit.doctor.ran did not read: exit 1: no API")}
	out := c.runAt(t, t0, nil, warn("a"))
	if out.Record != nil || out.Recorded || len(out.Failures) != 1 || !strings.Contains(out.Failures[0], "no API") {
		t.Fatalf("answered %+v", out)
	}
	if c.Doctors() != 0 || len(c.Emitted()) != 0 {
		t.Fatalf("ran %d doctors and emitted %d events", c.Doctors(), len(c.Emitted()))
	}
}

// monitor is the row of the monitor order named, a row with no order when the
// list has none.
func monitor(ms []Monitor, order string) Monitor {
	for _, m := range ms {
		if m.Order == order {
			return m
		}
	}
	return Monitor{}
}

// A run whose read of the monitors' runs fails records the previous run's,
// says why, and fails. The run after it reads the whole window, so a monitor
// that ran between the two runs before it is not missed.
func TestAnUnreadMonitorsReadKeepsThePreviousRuns(t *testing.T) {
	c := newCity()
	c.Add(gascity.Event{Type: "order.completed", Subject: "reaper", Ts: t0.Add(-time.Hour)})
	c.runAt(t, t0, nil)
	c.Add(gascity.Event{Type: "order.completed", Subject: "mol-dog-backup", Ts: t0.Add(20 * time.Minute)})
	c.ReadErr = map[string]error{"order.completed": errors.New("walk budget spent")}
	out := c.runAt(t, t0.Add(time.Hour), nil, warn("a"))
	rec := out.Record
	if !out.Recorded || !rec.Completed || rec.MonitorsUnread != "walk budget spent" || len(out.Failures) != 1 {
		t.Fatalf("answered %+v, record %+v", out, rec)
	}
	if m := monitor(rec.Monitors, "reaper"); m.LastGood == nil || !m.LastGood.Equal(t0.Add(-time.Hour)) {
		t.Fatalf("monitors = %+v", rec.Monitors)
	}
	c.ReadErr = nil
	out = c.runAt(t, t0.Add(2*time.Hour), nil)
	if r := c.Reads(); r[len(r)-1] != (fake.Read{Type: "order.completed", Since: window}) {
		t.Errorf("the run after the unread one read the monitors' runs as %+v", r[len(r)-1])
	}
	if m := monitor(out.Record.Monitors, "mol-dog-backup"); m.LastGood == nil || !m.LastGood.Equal(t0.Add(20*time.Minute)) {
		t.Fatalf("the run after the unread one has monitors %+v", out.Record.Monitors)
	}
}

// A run whose event is not recorded fails, and still answers the record it
// composed.
func TestAnUnrecordedEventFailsTheRun(t *testing.T) {
	c := newCity()
	c.EmitErr = errors.New("gc event emit gc-toolkit.doctor.ran did not submit the event")
	out := c.runAt(t, t0, nil, warn("a"))
	if out.Recorded || out.Record == nil || len(out.Failures) != 1 || !strings.Contains(out.Failures[0], "was not recorded") {
		t.Fatalf("answered %+v", out)
	}
}

// The newest event whose payload reads as a record is the previous run, so an
// event of the type that does not stops no run.
func TestAnEventThatIsNoRecordIsPassedOver(t *testing.T) {
	c := newCity()
	c.runAt(t, t0, nil, warn("a"))
	c.Add(gascity.Event{Type: EventType, Ts: t0.Add(time.Minute), Payload: json.RawMessage(`{"hand":"typed"}`)})
	c.Add(gascity.Event{Type: EventType, Ts: t0.Add(2 * time.Minute)})
	out := c.runAt(t, t0.Add(time.Hour), nil, warn("a"))
	if got := streaks(out.Record.Failing); !reflect.DeepEqual(got, map[string]string{"a": "12:00/2"}) {
		t.Fatalf("failing = %v", got)
	}
}

// A message is cut to the cap at a character boundary, and the cut is marked.
func TestAMessageIsClipped(t *testing.T) {
	long := strings.Repeat("é", 400)
	got := clip(long)
	if !utf8.ValidString(got) || len(got) > messageCap+len("…") || !strings.HasSuffix(got, "…") {
		t.Fatalf("clip gave %d bytes, valid %v", len(got), utf8.ValidString(got))
	}
	if clip("  short  ") != "short" {
		t.Errorf("a short message is only trimmed")
	}
}

// The payload's keys are the ones a reader of the event names, so a change to
// one is a change to its contract.
func TestThePayloadsKeys(t *testing.T) {
	first := t0
	rec := Record{
		Started: t0, Finished: t0, Completed: false, Why: "w", Measured: &first,
		Failing:        []Check{{Name: "a"}},
		NotMeasured:    []Unmeasured{{Name: "b", Why: "timed_out", FirstFailed: &first, Streak: 1, Entry: &Entry{Reason: "r", Ruling: "u", For: "3h"}}},
		Accepted:       []Accepted{{Check: Check{Name: "c"}, Entry: Entry{Reason: "r", Ruling: "u", For: "3h"}}},
		Monitors:       []Monitor{{Order: "reaper", LastGood: &first}},
		MonitorsUnread: "m",
	}
	raw, err := json.Marshal(rec)
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
		{shape, []string{"accepted", "completed", "failing", "finished", "measured", "monitors", "monitors_unread", "not_measured", "started", "why"}},
		{shape["failing"].([]any)[0], []string{"first_failed", "message", "name", "severity", "status", "streak"}},
		{shape["not_measured"].([]any)[0], []string{"entry", "first_failed", "name", "streak", "why"}},
		{shape["not_measured"].([]any)[0].(map[string]any)["entry"], []string{"for", "reason", "ruling"}},
		{shape["accepted"].([]any)[0], []string{"entry", "first_failed", "message", "name", "severity", "status", "streak"}},
		{shape["accepted"].([]any)[0].(map[string]any)["entry"], []string{"for", "reason", "ruling"}},
		{shape["monitors"].([]any)[0], []string{"last_good", "order"}},
	} {
		if got := keys(tc.at); !reflect.DeepEqual(got, tc.want) {
			t.Errorf("keys %v, want %v", got, tc.want)
		}
	}
}
