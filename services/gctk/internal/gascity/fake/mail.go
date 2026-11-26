package fake

import (
	"context"
	"slices"
	"sync"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
)

// Mail is the city's mailboxes and nudge queues in memory, safe for concurrent
// use. A nudge leaves the mail unread and the queue as they were, as Gas
// City's does.
type Mail struct {
	// Inboxes is each session's inbox, and Queues the nudges still to be
	// delivered to it, by the session a read names. A session neither names
	// reads as an empty inbox and an empty queue.
	Inboxes map[string]gascity.Inbox
	Queues  map[string]gascity.NudgeQueue
	// InboxErr and QueueErr fail the read of each session they name.
	InboxErr, QueueErr map[string]error
	// OnNudge answers a nudge, and nil answers exit 0.
	OnNudge func(Nudge) gascity.Bounded

	mu     sync.Mutex
	reads  []string
	nudges []Nudge
}

// MailInbox records the read and answers the session's inbox.
func (m *Mail) MailInbox(_ context.Context, session string) (gascity.Inbox, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.reads = append(m.reads, "inbox "+session)
	if err := m.InboxErr[session]; err != nil {
		return gascity.Inbox{}, err
	}
	in := m.Inboxes[session]
	return gascity.Inbox{Addresses: slices.Clone(in.Addresses), Unread: slices.Clone(in.Unread)}, nil
}

// NudgeQueue records the read and answers the session's queue.
func (m *Mail) NudgeQueue(_ context.Context, session string) (gascity.NudgeQueue, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.reads = append(m.reads, "queue "+session)
	if err := m.QueueErr[session]; err != nil {
		return gascity.NudgeQueue{}, err
	}
	q := m.Queues[session]
	return gascity.NudgeQueue{Pending: slices.Clone(q.Pending), InFlight: slices.Clone(q.InFlight)}, nil
}

// NudgeWaitIdle records the nudge and answers it.
func (m *Mail) NudgeWaitIdle(_ context.Context, session, message string) gascity.Bounded {
	n := Nudge{Session: session, Message: message}
	m.mu.Lock()
	m.nudges = append(m.nudges, n)
	on := m.OnNudge
	m.mu.Unlock()
	if on != nil {
		return on(n)
	}
	return gascity.Bounded{}
}

// Reads returns each inbox and queue read, as "inbox <session>" or
// "queue <session>", in order.
func (m *Mail) Reads() []string {
	m.mu.Lock()
	defer m.mu.Unlock()
	return slices.Clone(m.reads)
}

// Nudges returns each nudge sent, in order.
func (m *Mail) Nudges() []Nudge {
	m.mu.Lock()
	defer m.mu.Unlock()
	return slices.Clone(m.nudges)
}
