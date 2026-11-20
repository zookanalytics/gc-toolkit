// Package cityboard is the board's city page: what doctor's newest run found,
// read from the newest gc-toolkit.doctor.ran event in the city's event log,
// whose payload is gctk's doctor.Record (specs/tk-1tfzr71.158/design.md,
// section 5). It decides which checks the page shows and counts, and whether
// the run is late. A monitor order's lateness is Gas City's verdict, in its
// order checks, which reach the page as checks, so the page holds no rule for
// it.
package cityboard

import (
	"cmp"
	"context"
	"encoding/json"
	"fmt"
	"slices"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/doctor"
)

// ShowAfter is how many runs in a row must measure a check failing before the
// page shows it. A failure the next run no longer finds was in one run only,
// and the page never shows it. The streak counts only runs that measured the
// check, so a run that did not complete or did not measure it adds nothing.
const ShowAfter = 2

// LateAfter is how long after a run started the page marks it late, twice the
// doctor order's hourly cadence.
const LateAfter = 2 * time.Hour

// Event is one event of the city's log as the supervisor's events route serves
// it (WireEvent in internal/api/convoy_event_stream.go at gastownhall/gascity
// 5f7cd988a6). Payload is the event's own JSON: the route passes a custom
// event type's payload, one `gc event emit` recorded, through unchanged
// (toWireEvent there).
type Event struct {
	Seq     uint64          `json:"seq"`
	Type    string          `json:"type"`
	Ts      time.Time       `json:"ts"`
	Actor   string          `json:"actor"`
	Subject string          `json:"subject,omitempty"`
	Message string          `json:"message,omitempty"`
	Payload json.RawMessage `json:"payload,omitempty"`
}

// Log is the city's event log as the page reads it.
type Log interface {
	// Newest is the newest event of type typ, nil when the log holds none.
	Newest(ctx context.Context, typ string) (*Event, error)
}

// Read builds the city's document at now from doctor's newest recorded run.
// An event whose payload does not read as a run's record is a failed read, so
// the page keeps what it last showed and says why, rather than drawing a city
// with nothing failing.
func Read(ctx context.Context, log Log, now time.Time) (Document, error) {
	e, err := log.Newest(ctx, doctor.EventType)
	if err != nil {
		return Document{}, err
	}
	if e == nil {
		return Build(nil, now), nil
	}
	var rec doctor.Record
	if err := json.Unmarshal(e.Payload, &rec); err != nil {
		return Document{}, fmt.Errorf("the newest %s event, seq %d, holds no run's record that reads: %v", doctor.EventType, e.Seq, err)
	}
	if rec.Started.IsZero() {
		return Document{}, fmt.Errorf("the newest %s event, seq %d, holds no run's record that reads: it names no start", doctor.EventType, e.Seq)
	}
	return Build(&rec, now), nil
}

// Build is the city's document for doctor's newest run, rec, nil when the log
// holds none, as the page shows it at now.
//
// A failing check shows once two runs in a row measured it failing. A check
// the run could not measure that showed so when it was last measured stays,
// counted, with why the run could not measure it, because only a run that
// measures it ok, or the operator's acceptance, takes it off. Every other
// check the run did not measure is listed as not measured, and each check the
// operator accepted is listed apart.
func Build(rec *doctor.Record, now time.Time) Document {
	d := Doctor{Failing: []Check{}, NotMeasured: []Check{}, Accepted: []Check{}, Monitors: []Monitor{}}
	if rec == nil {
		return Document{Doctor: d}
	}
	d.Ran = true
	d.Started, d.Finished = stamp(rec.Started), stamp(rec.Finished)
	d.Late = now.Sub(rec.Started) > LateAfter
	d.Completed, d.Why = rec.Completed, rec.Why
	if rec.Measured != nil {
		d.Measured = stamp(*rec.Measured)
	}
	for _, c := range rec.Failing {
		if c.Streak >= ShowAfter {
			d.Failing = append(d.Failing, failing(c))
		}
	}
	for _, u := range rec.NotMeasured {
		c := Check{Name: u.Name, Streak: u.Streak, Unmeasured: u.Why, Accepted: acceptance(u.Entry)}
		if u.FirstFailed != nil {
			c.FirstFailed = stamp(*u.FirstFailed)
		}
		if u.Entry == nil && u.Streak >= ShowAfter {
			d.Failing = append(d.Failing, c)
		} else {
			d.NotMeasured = append(d.NotMeasured, c)
		}
	}
	for _, a := range rec.Accepted {
		c := failing(a.Check)
		c.Accepted = acceptance(&a.Entry)
		d.Accepted = append(d.Accepted, c)
	}
	slices.SortStableFunc(d.Failing, func(a, b Check) int {
		return cmp.Or(cmp.Compare(loudness(a.Status), loudness(b.Status)), cmp.Compare(a.FirstFailed, b.FirstFailed), cmp.Compare(a.Name, b.Name))
	})
	d.Count = len(d.Failing)
	for _, m := range rec.Monitors {
		row := Monitor{Order: m.Order}
		if m.LastGood != nil {
			row.LastGood = stamp(*m.LastGood)
		}
		d.Monitors = append(d.Monitors, row)
	}
	d.MonitorsUnread = rec.MonitorsUnread
	return Document{Doctor: d}
}

// failing is a measured check as the page draws it.
func failing(c doctor.Check) Check {
	return Check{Name: c.Name, Status: c.Status, Severity: c.Severity, Message: c.Message, FirstFailed: stamp(c.FirstFailed), Streak: c.Streak}
}

func acceptance(e *doctor.Entry) *Acceptance {
	if e == nil {
		return nil
	}
	return &Acceptance{Reason: e.Reason, Ruling: e.Ruling, For: e.For}
}

// loudness orders doctor's statuses: an error before a warning, and a check
// the run did not measure, which carries none, after both.
func loudness(status string) int {
	switch status {
	case "error":
		return 0
	case "warning":
		return 1
	}
	return 2
}

// stamp is t in RFC 3339 to the second, in UTC, "" for the zero time. One zone
// and one layout make the strings sort as the times do, which the order by
// first failure relies on.
func stamp(t time.Time) string {
	if t.IsZero() {
		return ""
	}
	return t.UTC().Format(time.RFC3339)
}
