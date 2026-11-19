package fake

import (
	"context"
	"slices"
	"sync"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
)

// Read is one read of the event log: the type asked for and the window.
type Read struct {
	Type  string
	Since time.Duration
}

// EventLog is the city's event log and its doctor in memory, safe for
// concurrent use. An event it records joins the log, so a second run reads
// what the first recorded.
type EventLog struct {
	// Now is the log's clock: the time an emitted event takes, and the end of
	// a read's window.
	Now func() time.Time
	// OnDoctor answers a doctor run, and nil answers exit 0 with no results.
	OnDoctor func(context.Context) gascity.DoctorRun
	// ReadErr fails each read of a type it names, and EmitErr each emit.
	ReadErr map[string]error
	EmitErr error

	mu      sync.Mutex
	log     []gascity.Event
	reads   []Read
	emitted []gascity.Emit
	doctors int
}

// Add puts events in the log, numbering each after the last.
func (l *EventLog) Add(events ...gascity.Event) {
	l.mu.Lock()
	defer l.mu.Unlock()
	for _, e := range events {
		e.Seq = int64(len(l.log) + 1)
		l.log = append(l.log, e)
	}
}

// Doctor counts the run and answers it.
func (l *EventLog) Doctor(ctx context.Context) gascity.DoctorRun {
	l.mu.Lock()
	l.doctors++
	on := l.OnDoctor
	l.mu.Unlock()
	if on != nil {
		return on(ctx)
	}
	return gascity.DoctorRun{Results: []gascity.DoctorResult{}}
}

// Events records the read and answers the log's events of typ, oldest first:
// every one when since is zero, else those within since of Now.
func (l *EventLog) Events(_ context.Context, typ string, since time.Duration) ([]gascity.Event, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.reads = append(l.reads, Read{Type: typ, Since: since})
	if err := l.ReadErr[typ]; err != nil {
		return nil, err
	}
	var out []gascity.Event
	for _, e := range l.log {
		if e.Type != typ || (since > 0 && e.Ts.Before(l.Now().Add(-since))) {
			continue
		}
		out = append(out, e)
	}
	return out, nil
}

// Emit records e and adds it to the log at Now, unless EmitErr fails it.
func (l *EventLog) Emit(_ context.Context, e gascity.Emit) error {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.EmitErr != nil {
		return l.EmitErr
	}
	l.emitted = append(l.emitted, e)
	l.log = append(l.log, gascity.Event{
		Seq: int64(len(l.log) + 1), Type: e.Type, Ts: l.Now(), Actor: e.Actor,
		Subject: e.Subject, Message: e.Message, Payload: slices.Clone(e.Payload),
	})
	return nil
}

// Emitted returns each event recorded, in order.
func (l *EventLog) Emitted() []gascity.Emit {
	l.mu.Lock()
	defer l.mu.Unlock()
	return slices.Clone(l.emitted)
}

// Reads returns each read of the log, in order.
func (l *EventLog) Reads() []Read {
	l.mu.Lock()
	defer l.mu.Unlock()
	return slices.Clone(l.reads)
}

// Doctors is how many doctor runs were asked for.
func (l *EventLog) Doctors() int {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.doctors
}
