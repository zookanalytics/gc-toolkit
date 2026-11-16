// Package doctor is the doctor domain: one run of gc doctor recorded as one
// Gas City event, gc-toolkit.doctor.ran, whose payload says which checks fail
// and since when, which the run did not measure, which the operator accepted,
// and each monitor order's last good run. Gas City keeps no doctor result, so
// the event log is the record, and its newest event is what doctor found last
// (specs/tk-1tfzr71.158/design.md, section 5).
package doctor

import (
	"cmp"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
)

// EventType is the type of the event a run records.
const EventType = "gc-toolkit.doctor.ran"

// Actor is the actor a run's event names.
const Actor = "gctk"

const (
	// Deadline is how long a run lets gc doctor work before it ends it: several
	// times the minutes a whole run takes, and short of the order's timeout by
	// the event log's three calls.
	Deadline = 20 * time.Minute
	// CallBound bounds each read and write of the event log a run makes.
	CallBound = 2 * time.Minute

	// window is how far back a run reads the monitors' runs when no previous
	// run says where to start, and the most it reads.
	window = 24 * time.Hour
	// overlap is how far before the previous run's start a run reads the
	// monitors' runs from, so a run recorded while that one read is not missed.
	overlap = 10 * time.Minute
	// messageCap bounds each message the event carries, so the event stays a few
	// kilobytes however long a check's message runs.
	messageCap = 300
	// notChecked opens the message of each stand-in doctor's store gate reports
	// in place of a check it did not run (StoreNotRunningMessage and
	// StoreSuspendedMessage in internal/doctor/store_liveness.go at
	// gastownhall/gascity c7eb6d2f43).
	notChecked = "not checked:"
	// completed is the event Gas City records for an order's good run.
	completed = "order.completed"
)

// Monitors are the orders whose job is to notice a problem, whose last good
// run a run records: the doctor order itself, core's spawn-storm-detect,
// orphan-sweep and reaper, and the dolt pack's mol-dog-doctor, mol-dog-backup
// and dolt-health. A good run is the newest order.completed Gas City recorded
// for the order, which it records when an exec order's run exits 0 and when a
// formula order pours its wisp (dispatchExec in cmd/gc/order_dispatch.go at
// gastownhall/gascity c7eb6d2f43). Whether a monitor is late or failing is
// Gas City's verdict, in its order-firing-current and order-outcome-healthy
// checks, which reach a run as checks.
var Monitors = []string{"doctor-run", "spawn-storm-detect", "orphan-sweep", "reaper", "mol-dog-doctor", "mol-dog-backup", "dolt-health"}

// Record is a run's event payload.
type Record struct {
	// Started and Finished bound the run.
	Started  time.Time `json:"started"`
	Finished time.Time `json:"finished"`
	// Completed is whether gc doctor exited 0 or 1 and printed a report that
	// reads, within the deadline. Why says why it did not.
	Completed bool   `json:"completed"`
	Why       string `json:"why,omitempty"`
	// Measured is the start of the run that measured the lists below: this
	// run's, or, when this run did not complete, the start of the run whose
	// lists it carries, absent when no run has measured any.
	Measured *time.Time `json:"measured,omitempty"`
	// Failing, NotMeasured and Accepted together are every result doctor
	// reported that is not ok or that it did not measure, each by name.
	Failing     []Check      `json:"failing"`
	NotMeasured []Unmeasured `json:"not_measured"`
	Accepted    []Accepted   `json:"accepted"`
	// Monitors is each monitor order's last good run, and MonitorsUnread why
	// this run's read of them failed, when it did. Monitors are then the
	// previous run's.
	Monitors       []Monitor `json:"monitors"`
	MonitorsUnread string    `json:"monitors_unread,omitempty"`
}

// Check is a result that is not ok: what doctor said of it, the start of the
// first of the runs in a row that measured it failing, and how many runs that
// is, its streak.
type Check struct {
	Name        string    `json:"name"`
	Status      string    `json:"status"`
	Severity    string    `json:"severity"`
	Message     string    `json:"message"`
	FirstFailed time.Time `json:"first_failed"`
	Streak      int       `json:"streak"`
}

// Unmeasured is a result the run did not measure, and why: timed_out for a
// check doctor abandoned at its per-check timeout, or the message of the
// stand-in doctor's store gate reported in its place. A check that was failing
// keeps the time it first failed and its streak.
type Unmeasured struct {
	Name        string     `json:"name"`
	Why         string     `json:"why"`
	FirstFailed *time.Time `json:"first_failed,omitempty"`
	Streak      int        `json:"streak,omitempty"`
}

// Accepted is a failing result the accepted file accepts, with its entry.
type Accepted struct {
	Check
	Entry Entry `json:"entry"`
}

// Monitor is a monitor order's last good run. Order is the order's name, or
// its run in one rig, <order>:rig:<rig>, as Gas City names a rig-scoped
// order's events (ScopedName in internal/orders/order.go at
// gastownhall/gascity c7eb6d2f43). LastGood is absent when no good run is
// known.
type Monitor struct {
	Order    string     `json:"order"`
	LastGood *time.Time `json:"last_good,omitempty"`
}

// City is Gas City as a run reaches it: its doctor and its event log.
type City interface {
	Doctor(ctx context.Context) gascity.DoctorRun
	Events(ctx context.Context, typ string, since time.Duration) ([]gascity.Event, error)
	Emit(ctx context.Context, e gascity.Emit) error
}

// Runner runs gc doctor and records each run.
type Runner struct {
	City City
	Now  func() time.Time
}

// Outcome is what a run did: the record it composed, whether the event
// carrying it was recorded, and each thing that failed, any of which makes the
// run's exit non-zero. Record is nil when the run recorded nothing.
type Outcome struct {
	Record   *Record
	Recorded bool
	Failures []string
}

// Run runs gc doctor once and records the run as one event. It reads the
// previous run's event first, because a failing check carries the time it
// first failed and its streak from it. When that read fails it runs no doctor
// and records nothing, so the last record stands.
func (r *Runner) Run(accepted []Entry) Outcome {
	start := r.now()
	prev, err := r.previous()
	if err != nil {
		return Outcome{Failures: []string{fmt.Sprintf("the previous run's event did not read, so no doctor ran and nothing was recorded: %v", err)}}
	}
	ctx, cancel := context.WithTimeout(context.Background(), Deadline)
	ran := r.City.Doctor(ctx)
	cancel()

	rec := &Record{Started: start}
	var fails []string
	if why := incomplete(ran); why != "" {
		rec.Why = why
		carry(rec, prev)
		fails = append(fails, "doctor did not complete: "+why)
	} else {
		rec.Completed = true
		rec.Measured = &start
		measure(rec, ran.Results, prev, accepted)
	}
	monitors, err := r.monitors(prev)
	if err != nil {
		rec.Monitors = monitorList(lastGood(prev))
		rec.MonitorsUnread = err.Error()
		fails = append(fails, "the monitors' runs did not read, so the previous run's stand: "+err.Error())
	} else {
		rec.Monitors = monitors
	}
	rec.Finished = r.now()

	payload, err := json.Marshal(rec)
	if err == nil {
		ctx, cancel := context.WithTimeout(context.Background(), CallBound)
		err = r.City.Emit(ctx, gascity.Emit{Type: EventType, Actor: Actor, Message: rec.Summary(), Payload: payload})
		cancel()
	}
	if err != nil {
		fails = append(fails, "the run's event was not recorded: "+err.Error())
	}
	return Outcome{Record: rec, Recorded: err == nil, Failures: fails}
}

// Summary is the record in one line, the event's message.
func (rec *Record) Summary() string {
	if !rec.Completed {
		return "doctor did not complete: " + rec.Why
	}
	return fmt.Sprintf("doctor ran: %d failing, %d not measured, %d accepted", len(rec.Failing), len(rec.NotMeasured), len(rec.Accepted))
}

func (r *Runner) now() time.Time { return r.Now().UTC().Truncate(time.Second) }

// previous is the newest run's record, nil when there is none. An event whose
// payload does not read as a record is passed over, so one bad event cannot
// stop every later run.
func (r *Runner) previous() (*Record, error) {
	ctx, cancel := context.WithTimeout(context.Background(), CallBound)
	defer cancel()
	events, err := r.City.Events(ctx, EventType, 0)
	if err != nil {
		return nil, err
	}
	slices.SortStableFunc(events, func(a, b gascity.Event) int { return cmp.Compare(b.Seq, a.Seq) })
	for _, e := range events {
		var rec Record
		if json.Unmarshal(e.Payload, &rec) == nil && !rec.Started.IsZero() {
			return &rec, nil
		}
	}
	return nil, nil
}

// incomplete says why a doctor run did not complete, "" when it did.
func incomplete(ran gascity.DoctorRun) string {
	switch {
	case errors.Is(ran.Err, gascity.ErrDeadline):
		return fmt.Sprintf("gc doctor did not finish within %s", Deadline)
	case ran.Err != nil:
		return "gc doctor did not run: " + ran.Err.Error()
	case ran.Code != 0 && ran.Code != 1:
		return fmt.Sprintf("gc doctor exited %d: %s", ran.Code, clip(gascity.Result{Output: ran.Stderr}.Tail()))
	case ran.Results == nil:
		return fmt.Sprintf("gc doctor exited %d and printed no report that reads: %s", ran.Code, clip(gascity.Result{Output: ran.Stderr}.Tail()))
	}
	return ""
}

// history is what a check carries from the run before: the time it first
// failed and its streak.
type history struct {
	first  time.Time
	streak int
}

// histories is each check the previous run listed as failing, accepted
// included, or as not measured with a failure it carried.
func histories(prev *Record) map[string]history {
	out := map[string]history{}
	if prev == nil {
		return out
	}
	for _, c := range prev.Failing {
		out[c.Name] = history{c.FirstFailed, c.Streak}
	}
	for _, a := range prev.Accepted {
		out[a.Name] = history{a.FirstFailed, a.Streak}
	}
	for _, u := range prev.NotMeasured {
		if u.FirstFailed != nil {
			out[u.Name] = history{*u.FirstFailed, u.Streak}
		}
	}
	return out
}

// measure lists what a completed run found. A result doctor abandoned, or one
// its store gate stood in for, is not measured and keeps its history. Any
// other result that is not ok is failing: it carries its history and adds one
// to its streak, or starts one at this run. An ok result, and a check doctor
// no longer reports, are listed nowhere.
func measure(rec *Record, results []gascity.DoctorResult, prev *Record, accepted []Entry) {
	had := histories(prev)
	byName := map[string]Entry{}
	for _, e := range accepted {
		byName[e.Check] = e
	}
	rec.Failing, rec.NotMeasured, rec.Accepted = []Check{}, []Unmeasured{}, []Accepted{}
	seen := map[string]bool{}
	for _, res := range results {
		if res.Name == "" || seen[res.Name] {
			continue
		}
		seen[res.Name] = true
		h, failed := had[res.Name]
		switch {
		case res.TimedOut:
			rec.NotMeasured = append(rec.NotMeasured, unmeasured(res.Name, "timed_out", h, failed))
		case strings.HasPrefix(res.Message, notChecked):
			rec.NotMeasured = append(rec.NotMeasured, unmeasured(res.Name, clip(res.Message), h, failed))
		case res.Status == "ok":
		default:
			c := Check{Name: res.Name, Status: res.Status, Severity: res.Severity, Message: clip(res.Message), FirstFailed: rec.Started, Streak: 1}
			if failed {
				c.FirstFailed, c.Streak = h.first, h.streak+1
			}
			if e, ok := byName[res.Name]; ok && e.Accepts(c.FirstFailed, rec.Started) {
				rec.Accepted = append(rec.Accepted, Accepted{Check: c, Entry: e})
			} else {
				rec.Failing = append(rec.Failing, c)
			}
		}
	}
	slices.SortFunc(rec.Failing, func(a, b Check) int { return strings.Compare(a.Name, b.Name) })
	slices.SortFunc(rec.NotMeasured, func(a, b Unmeasured) int { return strings.Compare(a.Name, b.Name) })
	slices.SortFunc(rec.Accepted, func(a, b Accepted) int { return strings.Compare(a.Name, b.Name) })
}

func unmeasured(name, why string, h history, failed bool) Unmeasured {
	u := Unmeasured{Name: name, Why: why}
	if failed {
		first := h.first
		u.FirstFailed, u.Streak = &first, h.streak
	}
	return u
}

// carry gives a run that did not complete the previous run's lists unchanged,
// and the time they were measured.
func carry(rec, prev *Record) {
	rec.Failing, rec.NotMeasured, rec.Accepted = []Check{}, []Unmeasured{}, []Accepted{}
	if prev == nil {
		return
	}
	rec.Measured = prev.Measured
	rec.Failing = append(rec.Failing, prev.Failing...)
	rec.NotMeasured = append(rec.NotMeasured, prev.NotMeasured...)
	rec.Accepted = append(rec.Accepted, prev.Accepted...)
}

// monitors reads the monitors' runs since the previous run began, less the
// overlap, or over the whole window when there is no previous run, and keeps
// the previous run's last good run for each monitor that has none since.
func (r *Runner) monitors(prev *Record) ([]Monitor, error) {
	since := window
	if prev != nil {
		if d := r.now().Sub(prev.Started) + overlap; d > 0 && d < window {
			since = d
		}
	}
	ctx, cancel := context.WithTimeout(context.Background(), CallBound)
	defer cancel()
	events, err := r.City.Events(ctx, completed, since)
	if err != nil {
		return nil, err
	}
	last := lastGood(prev)
	for _, e := range events {
		if e.Type != completed || monitorOf(e.Subject) == "" {
			continue
		}
		if t, ok := last[e.Subject]; !ok || e.Ts.After(t) {
			last[e.Subject] = e.Ts.UTC()
		}
	}
	return monitorList(last), nil
}

// lastGood is each last good run the previous run recorded, by the order or
// rig-scoped order it names.
func lastGood(prev *Record) map[string]time.Time {
	out := map[string]time.Time{}
	if prev == nil {
		return out
	}
	for _, m := range prev.Monitors {
		if m.LastGood != nil {
			out[m.Order] = *m.LastGood
		}
	}
	return out
}

// monitorOf is the monitor an order.completed subject names: the order
// itself, or its run in one rig. It is "" for any other order.
func monitorOf(subject string) string {
	for _, m := range Monitors {
		if subject == m || strings.HasPrefix(subject, m+":rig:") {
			return m
		}
	}
	return ""
}

// monitorList is one row per monitor in Monitors' order, one per rig for a
// monitor whose runs name rigs, with the last good run each has, and a row
// with none for a monitor no good run is known of.
func monitorList(last map[string]time.Time) []Monitor {
	out := []Monitor{}
	for _, m := range Monitors {
		var subjects []string
		for s := range last {
			if monitorOf(s) == m {
				subjects = append(subjects, s)
			}
		}
		slices.Sort(subjects)
		if len(subjects) == 0 {
			out = append(out, Monitor{Order: m})
			continue
		}
		for _, s := range subjects {
			t := last[s]
			out = append(out, Monitor{Order: s, LastGood: &t})
		}
	}
	return out
}

// clip bounds a message to messageCap bytes, cut at a character boundary and
// marked where it was cut.
func clip(s string) string {
	s = strings.TrimSpace(s)
	if len(s) <= messageCap {
		return s
	}
	cut := messageCap
	for cut > 0 && !utf8.RuneStart(s[cut]) {
		cut--
	}
	return s[:cut] + "…"
}
