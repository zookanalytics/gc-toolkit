package cityboard

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/doctor"
)

var t0 = time.Date(2026, 11, 16, 12, 0, 0, 0, time.UTC)

func at(d time.Duration) *time.Time {
	t := t0.Add(d)
	return &t
}

// check is a measured failing check whose streak began at t0.
func check(name, status string, streak int) doctor.Check {
	return doctor.Check{Name: name, Status: status, Severity: "blocking", Message: name + " is wrong", FirstFailed: t0, Streak: streak}
}

// run is a completed run that started at start and measured the lists it holds.
func run(start time.Time) *doctor.Record {
	return &doctor.Record{Started: start, Finished: start.Add(3 * time.Minute), Completed: true, Measured: &start,
		Failing: []doctor.Check{}, NotMeasured: []doctor.Unmeasured{}, Accepted: []doctor.Accepted{}, Monitors: []doctor.Monitor{}}
}

func names(cs []Check) []string {
	out := []string{}
	for _, c := range cs {
		out = append(out, c.Name)
	}
	return out
}

// With no run in the log the page has nothing to count: it says so, and every
// list is empty rather than null, so the page never reads a missing run as a
// city with nothing failing.
func TestNoRunRecorded(t *testing.T) {
	d := Build(nil, t0).Doctor
	if d.Ran || d.Count != 0 || d.Late || d.Failing == nil || d.NotMeasured == nil || d.Accepted == nil || d.Monitors == nil {
		t.Fatalf("no run gives %+v", d)
	}
}

// A failing check shows once two runs in a row measured it failing, and the
// lead counts what shows. A check one run found is in no list.
func TestAFailingCheckShowsFromItsSecondRun(t *testing.T) {
	rec := run(t0.Add(time.Hour))
	rec.Failing = []doctor.Check{check("a", "warning", 1), check("b", "warning", 2), check("rig:r1:beads", "warning", 5)}
	d := Build(rec, t0.Add(time.Hour)).Doctor
	if got := names(d.Failing); !reflect.DeepEqual(got, []string{"b", "rig:r1:beads"}) || d.Count != 2 {
		t.Fatalf("failing = %v, count %d", got, d.Count)
	}
	if len(d.NotMeasured)+len(d.Accepted) != 0 {
		t.Errorf("a check one run found is listed: %+v", d)
	}
	b := d.Failing[0]
	if b.FirstFailed != "2026-11-16T12:00:00Z" || b.Streak != 2 || b.Status != "warning" || b.Severity != "blocking" || b.Message != "b is wrong" || b.Unmeasured != "" || b.Accepted != nil {
		t.Errorf("b = %+v", b)
	}
}

// A check the run could not measure stays failing, counted, when it showed so
// when a run last measured it and the operator has not accepted it. Every
// other check the run did not measure is listed as not measured, with the
// failure it carries and the entry that accepts it.
func TestACheckTheRunCouldNotMeasure(t *testing.T) {
	rec := run(t0.Add(3 * time.Hour))
	accepted := &doctor.Entry{Reason: "a Gas City bug", Ruling: "the design's approval"}
	rec.NotMeasured = []doctor.Unmeasured{
		{Name: "shown", Why: "timed_out", FirstFailed: at(0), Streak: 2},
		{Name: "accepted", Why: "not checked: store not running (rig:r1)", FirstFailed: at(0), Streak: 3, Entry: accepted},
		{Name: "once", Why: "timed_out", FirstFailed: at(2 * time.Hour), Streak: 1},
		{Name: "fine", Why: "timed_out"},
	}
	d := Build(rec, t0.Add(3*time.Hour)).Doctor
	if got := names(d.Failing); !reflect.DeepEqual(got, []string{"shown"}) || d.Count != 1 {
		t.Fatalf("failing = %v, count %d", got, d.Count)
	}
	if s := d.Failing[0]; s.Unmeasured != "timed_out" || s.FirstFailed != "2026-11-16T12:00:00Z" || s.Streak != 2 || s.Status != "" {
		t.Errorf("the unmeasured failing check = %+v", s)
	}
	if got := names(d.NotMeasured); !reflect.DeepEqual(got, []string{"accepted", "once", "fine"}) {
		t.Fatalf("not measured = %v", got)
	}
	if a := d.NotMeasured[0]; a.Accepted == nil || a.Accepted.Reason != "a Gas City bug" || a.Streak != 3 {
		t.Errorf("the accepted unmeasured check = %+v", a)
	}
	if f := d.NotMeasured[2]; f.FirstFailed != "" || f.Streak != 0 || f.Accepted != nil || f.Unmeasured != "timed_out" {
		t.Errorf("a check with no failure = %+v", f)
	}
}

// Each accepted check is listed apart with its entry, whatever its streak, and
// none counts.
func TestAcceptedChecksAreListedApart(t *testing.T) {
	rec := run(t0)
	rec.Accepted = []doctor.Accepted{
		{Check: check("dolt-compact-state", "warning", 1), Entry: doctor.Entry{Reason: "the compactor's retry", Ruling: "the design's approval", For: "3h"}},
		{Check: check("hold-label-routed-to", "warning", 9), Entry: doctor.Entry{Reason: "a Gas City bug", Ruling: "the design's approval"}},
	}
	d := Build(rec, t0).Doctor
	if d.Count != 0 || len(d.Failing) != 0 || !reflect.DeepEqual(names(d.Accepted), []string{"dolt-compact-state", "hold-label-routed-to"}) {
		t.Fatalf("accepted = %v, count %d", names(d.Accepted), d.Count)
	}
	if a := d.Accepted[0]; a.Accepted == nil || a.Accepted.For != "3h" || a.Message != "dolt-compact-state is wrong" || a.Streak != 1 {
		t.Errorf("accepted[0] = %+v", a)
	}
}

// The loudest status comes first, then the oldest failure, then the name, and
// a check the run could not measure, which carries no status, comes last.
func TestTheFailingOrder(t *testing.T) {
	rec := run(t0.Add(5 * time.Hour))
	newer := check("a-newer-warning", "warning", 2)
	newer.FirstFailed = t0.Add(time.Hour)
	rec.Failing = []doctor.Check{newer, check("z-warning", "warning", 3), check("m-error", "error", 2), check("b-warning", "warning", 2)}
	rec.NotMeasured = []doctor.Unmeasured{{Name: "a-unmeasured", Why: "timed_out", FirstFailed: at(-time.Hour), Streak: 4}}
	d := Build(rec, t0.Add(5*time.Hour)).Doctor
	want := []string{"m-error", "b-warning", "z-warning", "a-newer-warning", "a-unmeasured"}
	if got := names(d.Failing); !reflect.DeepEqual(got, want) || d.Count != len(want) {
		t.Fatalf("failing = %v, want %v", got, want)
	}
}

// A run is late once it started more than two hours before the read.
func TestARunIsLateAfterTwoHours(t *testing.T) {
	for _, tc := range []struct {
		since time.Duration
		late  bool
	}{{0, false}, {LateAfter - time.Second, false}, {LateAfter, false}, {LateAfter + time.Second, true}, {48 * time.Hour, true}} {
		if d := Build(run(t0), t0.Add(tc.since)).Doctor; d.Late != tc.late {
			t.Errorf("%s after its start, late = %v", tc.since, d.Late)
		}
	}
}

// A run that did not complete shows why, and the lists it carries with the
// time they were measured.
func TestARunThatDidNotComplete(t *testing.T) {
	rec := run(t0.Add(time.Hour))
	rec.Completed, rec.Why, rec.Measured = false, "gc doctor did not finish within 20m0s", at(0)
	rec.Failing = []doctor.Check{check("a", "warning", 2)}
	d := Build(rec, t0.Add(time.Hour)).Doctor
	if d.Completed || d.Why != rec.Why || d.Measured != "2026-11-16T12:00:00Z" || d.Started != "2026-11-16T13:00:00Z" || d.Count != 1 {
		t.Fatalf("the incomplete run gives %+v", d)
	}
	rec.Measured = nil
	if d := Build(rec, t0.Add(time.Hour)).Doctor; d.Measured != "" {
		t.Errorf("no measured run gives measured %q", d.Measured)
	}
}

// Each monitor keeps the order the run lists them in, with its last good run
// when one is known, and the run's failure to read them passes through.
func TestTheMonitors(t *testing.T) {
	rec := run(t0)
	good := t0.Add(-10*time.Minute + 893644*time.Microsecond)
	rec.Monitors = []doctor.Monitor{{Order: "doctor-run"}, {Order: "reaper:rig:r1", LastGood: &good}}
	rec.MonitorsUnread = "gc events did not read"
	d := Build(rec, t0).Doctor
	want := []Monitor{{Order: "doctor-run"}, {Order: "reaper:rig:r1", LastGood: "2026-11-16T11:50:00Z"}}
	if !reflect.DeepEqual(d.Monitors, want) || d.MonitorsUnread != "gc events did not read" {
		t.Fatalf("monitors = %+v, unread %q", d.Monitors, d.MonitorsUnread)
	}
}

// log is an event log that answers one event, or an error.
type log struct {
	event *Event
	err   error
	asked []string
}

func (l *log) Newest(_ context.Context, typ string) (*Event, error) {
	l.asked = append(l.asked, typ)
	return l.event, l.err
}

// Read asks the log for doctor's newest run. A log that holds none gives the
// page with no run, and a failed read or a payload that is no run's record is
// an error, never a city with nothing failing.
func TestRead(t *testing.T) {
	l := &log{}
	doc, err := Read(context.Background(), l, t0)
	if err != nil || doc.Doctor.Ran || !reflect.DeepEqual(l.asked, []string{doctor.EventType}) {
		t.Fatalf("an empty log gives %+v, %v; asked %v", doc, err, l.asked)
	}
	if _, err := Read(context.Background(), &log{err: errors.New("supervisor down")}, t0); err == nil || err.Error() != "supervisor down" {
		t.Errorf("a failed read gives %v", err)
	}
	for _, payload := range []string{`"text"`, `{"failing":[]}`, ``} {
		_, err := Read(context.Background(), &log{event: &Event{Seq: 9, Payload: json.RawMessage(payload)}}, t0)
		if err == nil || !strings.Contains(err.Error(), "seq 9, holds no run's record that reads") {
			t.Errorf("payload %q gives %v", payload, err)
		}
	}
}

// readAt is the time TestTheLiveRunsPage reads the fixture's run at: about two
// hours and twenty minutes after it started, so the page marks it late.
var readAt = time.Date(2026, 11, 17, 0, 42, 0, 0, time.UTC)

// The page built from a live city's newest doctor run, the fixture
// testdata/doctor.ran.json, is the golden testdata/city.json, which the web
// page's tests and helm-fixture read. -update writes it again.
func TestTheLiveRunsPage(t *testing.T) {
	raw, err := os.ReadFile(filepath.Join("testdata", "doctor.ran.json"))
	if err != nil {
		t.Fatal(err)
	}
	var fixture struct {
		Event Event `json:"event"`
	}
	if err := json.Unmarshal(raw, &fixture); err != nil {
		t.Fatal(err)
	}
	doc, err := Read(context.Background(), &log{event: &fixture.Event}, readAt)
	if err != nil {
		t.Fatal(err)
	}
	d := doc.Doctor
	if !d.Ran || !d.Late || !d.Completed || d.Count != 15 || len(d.Failing) != 15 || len(d.Accepted) != 1 || len(d.NotMeasured) != 0 || len(d.Monitors) != 7 {
		t.Fatalf("the live run gives ran %v, late %v, count %d, accepted %d, not measured %d, monitors %d", d.Ran, d.Late, d.Count, len(d.Accepted), len(d.NotMeasured), len(d.Monitors))
	}
	if first := d.Failing[0].Name; first != "gc-toolkit:check-pour-text-current" {
		t.Errorf("the first failing check is %s, want the first error by name", first)
	}
	got, err := json.MarshalIndent(Response{ReadAt: readAt.Format(time.RFC3339), City: doc}, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	got = append(got, '\n')
	golden := filepath.Join("testdata", "city.json")
	if *update {
		if err := os.WriteFile(golden, got, 0o644); err != nil {
			t.Fatal(err)
		}
		return
	}
	want, err := os.ReadFile(golden)
	if err != nil {
		t.Fatalf("%v; go test ./internal/cityboard -run TestTheLiveRunsPage -update writes it", err)
	}
	if !bytes.Equal(got, want) {
		t.Fatalf("%s is stale: go test ./internal/cityboard -run TestTheLiveRunsPage -update writes it again", golden)
	}
}
