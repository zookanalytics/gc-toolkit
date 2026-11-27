package session

import (
	"context"
	"encoding/json"
	"errors"
	"reflect"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	gcfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity/fake"
)

// quietEnded puts an event Gas City records when a seat's quiet stretch ends.
func (c *city) quietEnded(typ, session string, age time.Duration) {
	payload, _ := json.Marshal(map[string]string{"session_id": session})
	c.Add(gascity.Event{Type: typ, Ts: ago(age), Subject: session, Payload: payload})
}

// A seat that prints after Gas City found it quiet has been busy only since
// then: a prompt answered or a ladder nudge after its newest write is where
// its silence is counted from, and one before that write changes nothing.
func TestASeatsSilenceRunsFromWhenGasCityLastFoundItQuiet(t *testing.T) {
	c := newCity(gascity.Session{ID: "hq-ctl", State: "active"})
	for _, id := range []string{"hq-prompt", "hq-nudge", "hq-before", "hq-other"} {
		c.seat(busy(id), pool(8*time.Hour))
		c.claim(tools, "tk-"+id[3:], "in_progress", id, id)
		c.stores[tools.Store()].SetLastWrite(id, ago(6*time.Hour))
	}
	c.quietEnded(PromptAnswered, "hq-prompt", 30*time.Minute)
	c.quietEnded(Nudged, "hq-nudge", 5*time.Hour)
	c.quietEnded(Nudged, "hq-nudge", 4*time.Hour)
	c.quietEnded(PromptAnswered, "hq-before", 7*time.Hour)
	c.quietEnded(Nudged, "hq-elsewhere", 10*time.Minute)
	out := c.progress(t)
	if len(out.Failures) > 0 {
		t.Fatal(out.Failures)
	}
	if got := stalledIDs(out.Record); !reflect.DeepEqual(got, []string{"hq-before@tk-before", "hq-nudge@tk-nudge", "hq-other@tk-other"}) {
		t.Fatalf("stalled %v", got)
	}
	from := map[string]string{}
	for _, s := range out.Record.Stalled {
		from[s.Session] = s.From + "@" + s.Since.Format(time.RFC3339)
	}
	want := map[string]string{
		"hq-nudge":  FromNudge + "@" + stamp(4*time.Hour),
		"hq-before": FromWrite + "@" + stamp(6*time.Hour),
		"hq-other":  FromWrite + "@" + stamp(6*time.Hour),
	}
	if !reflect.DeepEqual(from, want) {
		t.Errorf("from %v", from)
	}
	var types []string
	for _, r := range c.EventLog.Reads() {
		types = append(types, r.Type)
		if r.Since != 6*time.Hour+time.Minute {
			t.Errorf("read %s over %s, not back to the oldest silent seat's write", r.Type, r.Since)
		}
	}
	if !reflect.DeepEqual(types, []string{PromptAnswered, Nudged}) {
		t.Errorf("reads %v", types)
	}
}

// The event log is read only when a seat has been silent for the bound, and a
// read of it that fails judges no such seat and fails the run.
func TestTheQuietReadComesOnlyForASilentSeatAndFailsTheRun(t *testing.T) {
	c := newCity(gascity.Session{ID: "hq-ctl", State: "active"})
	c.seat(busy("hq-1"), pool(8*time.Hour))
	c.claim(tools, "tk-1", "in_progress", "hq-1", "hq-1")
	c.stores[tools.Store()].SetLastWrite("hq-1", ago(time.Hour))
	if out := c.progress(t); len(out.Failures) > 0 || len(out.Record.Stalled) != 0 || len(c.EventLog.Reads()) != 0 {
		t.Fatalf("failures %v, stalled %v, reads %v", out.Failures, out.Record.Stalled, c.EventLog.Reads())
	}
	c.stores[tools.Store()].SetLastWrite("hq-1", ago(5*time.Hour))
	c.ReadErr = map[string]error{Nudged: errors.New("gc events did not answer")}
	out := c.progress(t)
	if len(out.Record.Stalled) != 0 || out.Recorded {
		t.Fatalf("stalled %v, recorded %v", out.Record.Stalled, out.Recorded)
	}
	if len(out.Failures) != 1 || !strings.Contains(out.Failures[0], "tk-1 in tools was not judged: when Gas City last found its seat quiet did not read") {
		t.Errorf("failures %v", out.Failures)
	}
}

// report runs the act over the city with the scripts runtime given.
func (c *city) report(t *testing.T, rt *gcfake.Runtime) Acted {
	t.Helper()
	p := &Progress{City: c, Open: c.open, Now: func() time.Time { return t0 }}
	return (&Report{Look: p, Scripts: rt}).Run(context.Background())
}

// The act reads the seats again and files one finding for each stalled seat,
// in its claim's rig, keyed by its session and about its claim. It records no
// event, so it does not fire itself.
func TestTheActFilesAFindingForEachStalledSeatAndRecordsNoEvent(t *testing.T) {
	c := newCity(gascity.Session{ID: "hq-ctl", State: "active"})
	c.seat(busy("hq-1"), pool(4*time.Hour))
	c.claim(tools, "tk-1", "in_progress", "hq-1", "hq-1")
	c.seat(busy("hq-2"), pool(8*time.Hour))
	c.claim(hq, "hq-9", "in_progress", "hq-2", "hq-2")
	c.stores[hq.Store()].SetLastWrite("hq-2", ago(5*time.Hour))
	rt := &gcfake.Runtime{}
	out := c.report(t, rt)
	if len(out.Failures) > 0 {
		t.Fatal(out.Failures)
	}
	if len(c.Emitted()) != 0 {
		t.Errorf("the act recorded %v", c.Emitted())
	}
	calls := rt.Scripts()
	if len(calls) != 2 {
		t.Fatalf("calls %+v", calls)
	}
	for i, want := range [][]string{
		{"--rig", "city", "--scope", "witness-findings", "--key", "no-progress.hq-2", "--about", "hq-9", "--distinct"},
		{"--rig", "tools", "--scope", "witness-findings", "--key", "no-progress.hq-1", "--about", "tk-1", "--distinct"},
	} {
		if calls[i].Name != "patrol-finding.sh" || !reflect.DeepEqual(calls[i].Args[:len(want)], want) {
			t.Errorf("call %d %+v", i, calls[i])
		}
	}
	title, message := calls[1].Args[10], calls[1].Args[12]
	if calls[1].Args[9] != "--title" || title != "tools/gc-toolkit.polecat-1 prints but has written nothing for 4 hours, holding tk-1" {
		t.Errorf("title %q", title)
	}
	for _, want := range []string{"The pool seat hq-1 (tools/gc-toolkit.polecat-1) holds tk-1", "since it woke at " + stamp(4*time.Hour), "`gc session peek hq-1`"} {
		if !strings.Contains(message, want) {
			t.Errorf("message lacks %q: %s", want, message)
		}
	}
	if got := []string{out.Filed[0].Key, out.Filed[1].Key}; !reflect.DeepEqual(got, []string{"no-progress.hq-2", "no-progress.hq-1"}) {
		t.Errorf("filed %v", got)
	}
}

// A filing the writer refuses fails the run and leaves the others filed, and a
// read that does not answer files nothing.
func TestTheActFailsForAFilingThatFailsAndFilesNothingUnread(t *testing.T) {
	c := newCity(gascity.Session{ID: "hq-ctl", State: "active"})
	for _, id := range []string{"hq-1", "hq-2"} {
		c.seat(busy(id), pool(4*time.Hour))
		c.claim(tools, "tk-"+id[3:], "in_progress", id, id)
	}
	rt := &gcfake.Runtime{OnScript: func(call gcfake.Call) gascity.Result {
		if slices.Contains(call.Args, "no-progress.hq-1") {
			return gascity.Result{Code: 1, Output: "patrol-finding: could not file"}
		}
		return gascity.Result{}
	}}
	out := c.report(t, rt)
	if len(out.Filed) != 1 || out.Filed[0].Session != "hq-2" {
		t.Errorf("filed %+v", out.Filed)
	}
	if len(out.Failures) != 1 || !strings.Contains(out.Failures[0], "patrol-finding.sh filed nothing for hq-1 holding tk-1") {
		t.Errorf("failures %v", out.Failures)
	}
	c.SessionsErr = errors.New("gc session list did not answer")
	rt = &gcfake.Runtime{}
	if out := c.report(t, rt); out.Record != nil || len(out.Failures) != 1 || len(rt.Scripts()) != 0 {
		t.Errorf("record %v, failures %v, calls %v", out.Record, out.Failures, rt.Scripts())
	}
}

// A later run for a seat still stalled since the same time composes the same
// message, so the writer counts an occurrence and notes no changed text. The
// title says how long, and it is not the text the writer compares.
func TestALaterRunForTheSameStallComposesTheSameMessage(t *testing.T) {
	s := Stalled{Rig: "tools", Bead: "tk-1", Session: "hq-1", Identity: "hq-1", Since: ago(3 * time.Hour), From: FromWrite}
	first, later := FindingArgs(s, t0), FindingArgs(s, t0.Add(90*time.Minute))
	if first[len(first)-1] != later[len(later)-1] {
		t.Errorf("the message moved between runs:\n%s\n%s", first[len(first)-1], later[len(later)-1])
	}
	if !strings.Contains(first[len(first)-1], "printed in the 90 seconds before the seat-progress look read it") {
		t.Errorf("message %s", first[len(first)-1])
	}
	if first[10] == later[10] {
		t.Errorf("the title %q does not say how long", first[10])
	}
}

// The finding says what its silence is counted from.
func TestTheFindingNamesWhatItsSilenceRunsFrom(t *testing.T) {
	for from, want := range map[string]string{
		FromWrite:  "its newest write as hq-1, to the claim's store or the city's, was at ",
		FromWake:   "since it woke at ",
		FromPrompt: "since a prompt it waited at was answered at ",
		FromNudge:  "since Gas City's work ladder last reached it for a quiet pane at ",
	} {
		args := FindingArgs(Stalled{Rig: "tools", Bead: "tk-1", Session: "hq-1", Identity: "hq-1", Since: ago(3 * time.Hour), From: from}, t0)
		if message := args[len(args)-1]; !strings.Contains(message, want+stamp(3*time.Hour)) {
			t.Errorf("%s: %s", from, message)
		}
	}
}
