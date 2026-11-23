// Package mail is the mail domain: what the pack asks of Gas City's mail. Gas
// City owns every message, each mailbox and each read mark, and it requests a
// recipient's turn only for a sender who asks it to. The domain owns the notify
// ledger, the unread messages its pass has requested a turn for, and the lock
// its passes share, both in the city's .gc/runtime/packs/gc-toolkit. Its pass,
// `gctk mail notify`, which the mail-notify-on-send and mail-notify-on-reply
// orders run when mail is sent or replied to, requests a turn for each listed
// agent's session that holds unread mail no notice has told it of.
package mail

import (
	"context"
	"fmt"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
)

const (
	// Deadline bounds a pass from its start: its wait for the lock, the
	// session list, and every inbox read, queue read and nudge, so a run ends
	// inside its order's timeout.
	Deadline = 120 * time.Second
	// Parallel is how many sessions a pass reads and nudges at once.
	Parallel = 4
)

// Wakeable are the states, as gc session list prints them, of a session a pass
// may request a turn for: one running or starting, and one asleep, which the
// nudge's wake starts (StateActive and its siblings in
// internal/session/manager.go at gastownhall/gascity c377651cb318). A session
// in any other state keeps its mail waiting: one draining, drained, archived
// or closed has finished, one suspended or quarantined is held from running,
// one whose create failed is being cleaned up, and a state Gas City adds later
// is not woken until it is named here.
var Wakeable = []string{"active", "awake", "asleep", "creating", "start-pending"}

// City is Gas City as the pass reaches it: the session list, a session's
// mail, the nudges still to be delivered to it, and the nudge.
type City interface {
	Sessions(ctx context.Context) ([]gascity.Session, error)
	MailInbox(ctx context.Context, session string) (gascity.Inbox, error)
	NudgeQueue(ctx context.Context, session string) (gascity.NudgeQueue, error)
	NudgeWaitIdle(ctx context.Context, session, message string) gascity.Bounded
}

// Notify is the pass: for each session of a listed agent in a wakeable state,
// it reads the session's unread mail, and when a message from another sender
// is not in the ledger and no mail notice is still to be delivered to the
// session, it requests the session's turn with one nudge naming each new
// message's sender. It records each message it nudged for in the ledger,
// which keeps a message only while it stays unread.
type Notify struct {
	City City
	// Agents names each agent whose sessions the pass reads, by the name its
	// pack gives it, such as converse-claude-opus, or with its binding, such
	// as gc-toolkit.converse-claude-opus.
	Agents []string
	// State is the directory the ledger and the lock live in.
	State string
	Now   func() time.Time
}

// Woken is a session the pass requested a turn for: the messages it named and
// their senders.
type Woken struct {
	Session  string   `json:"session"`
	Agent    string   `json:"agent,omitempty"`
	Messages []string `json:"messages"`
	From     []string `json:"from"`
}

// Told is a session holding new mail that the pass left alone because a mail
// notice is still to be delivered to it, which a sender's own --notify queues.
type Told struct {
	Session  string   `json:"session"`
	Messages []string `json:"messages"`
}

// Failed is a session the pass could not finish, and why. Its messages stay
// out of the ledger, so the next pass tries them again.
type Failed struct {
	Session string `json:"session"`
	Why     string `json:"why"`
}

// Record is what a pass did, which the verb prints.
type Record struct {
	Read   time.Time `json:"read"`
	Woken  []Woken   `json:"woken"`
	Told   []Told    `json:"told,omitempty"`
	Failed []Failed  `json:"failed,omitempty"`
}

// Summary is the record in one line.
func (rec *Record) Summary() string {
	if len(rec.Woken) == 0 {
		return "no session holds new mail that no notice has told it of"
	}
	woken := make([]string, len(rec.Woken))
	for i, w := range rec.Woken {
		woken[i] = fmt.Sprintf("%s for %s", w.Session, strings.Join(w.Messages, ", "))
	}
	return "requested a turn for " + strings.Join(woken, "; ")
}

// Outcome is what a run did: its record, nil when a read the whole pass rests
// on failed, and each thing that failed, any of which makes the run's exit
// non-zero.
type Outcome struct {
	Record   *Record
	Failures []string
}

// visit is what the pass found and did for one session: whether its inbox
// read, every unread message it holds, and what became of its new mail.
type visit struct {
	session gascity.Session
	read    bool
	unread  []string
	woken   *Woken
	told    *Told
	failed  string
}

// Run makes one pass. Each session's reads and its nudge end when ctx does,
// or at Deadline from the start of the run, whichever comes first.
func (n *Notify) Run(ctx context.Context) Outcome {
	ctx, cancel := context.WithTimeout(ctx, Deadline)
	defer cancel()
	now := n.Now().UTC().Truncate(time.Second)
	release, err := lock(ctx, n.State)
	if err != nil {
		return Outcome{Failures: []string{err.Error()}}
	}
	defer release()
	led, err := readLedger(n.State)
	if err != nil {
		return Outcome{Failures: []string{err.Error() + ", so no session was nudged"}}
	}
	list, err := n.City.Sessions(ctx)
	if err != nil {
		return Outcome{Failures: []string{"the session list did not read, so no session's mail was read: " + err.Error()}}
	}
	var sessions []gascity.Session
	for _, s := range list {
		if n.listed(s.Template) && slices.Contains(Wakeable, s.State) {
			sessions = append(sessions, s)
		}
	}
	visits := make([]visit, len(sessions))
	sem := make(chan struct{}, Parallel)
	var wg sync.WaitGroup
	for i, s := range sessions {
		wg.Add(1)
		go func() {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			visits[i] = n.visit(ctx, s, led)
		}()
	}
	wg.Wait()

	rec := &Record{Read: now, Woken: []Woken{}}
	var failures []string
	next := ledger{}
	for _, v := range visits {
		if v.read {
			for _, id := range v.unread {
				if e, ok := led[id]; ok {
					next[id] = e
				}
			}
		} else {
			for id, e := range led {
				if e.Session == v.session.ID {
					next[id] = e
				}
			}
		}
		switch {
		case v.woken != nil:
			rec.Woken = append(rec.Woken, *v.woken)
			for _, id := range v.woken.Messages {
				next[id] = entry{Session: v.session.ID, At: now}
			}
		case v.told != nil:
			rec.Told = append(rec.Told, *v.told)
		case v.failed != "":
			rec.Failed = append(rec.Failed, Failed{Session: v.session.ID, Why: v.failed})
			failures = append(failures, v.session.ID+": "+v.failed)
		}
	}
	if err := writeLedger(n.State, next); err != nil {
		failures = append(failures, err.Error())
	}
	return Outcome{Record: rec, Failures: failures}
}

// visit reads one session's mail and nudges it when it holds new mail that no
// notice has told it of.
func (n *Notify) visit(ctx context.Context, s gascity.Session, led ledger) visit {
	v := visit{session: s}
	in, err := n.City.MailInbox(ctx, s.ID)
	if err != nil {
		v.failed = "its mail did not read: " + err.Error()
		return v
	}
	v.read = true
	own := map[string]bool{}
	for _, a := range append([]string{s.ID, s.Name, s.Alias, s.AgentName, s.SessionName}, in.Addresses...) {
		if a != "" {
			own[a] = true
		}
	}
	var fresh []gascity.Message
	for _, m := range in.Unread {
		v.unread = append(v.unread, m.ID)
		if !own[m.From] && !led.has(m.ID) {
			fresh = append(fresh, m)
		}
	}
	if len(fresh) == 0 {
		return v
	}
	slices.SortStableFunc(fresh, func(a, b gascity.Message) int { return a.CreatedAt.Compare(b.CreatedAt) })
	ids := make([]string, len(fresh))
	var from []string
	for i, m := range fresh {
		ids[i] = m.ID
		if !slices.Contains(from, m.From) {
			from = append(from, m.From)
		}
	}
	q, err := n.City.NudgeQueue(ctx, s.ID)
	if err != nil {
		v.failed = "its nudges did not read, so whether a notice is still to tell it of its mail is unknown: " + err.Error()
		return v
	}
	if mailNotice(q) {
		v.told = &Told{Session: s.ID, Messages: ids}
		return v
	}
	if b := n.City.NudgeWaitIdle(ctx, s.ID, "You have mail from "+strings.Join(from, ", ")); b.Failure() != "" {
		v.failed = "the nudge did not land: " + b.Failure()
		return v
	}
	v.woken = &Woken{Session: s.ID, Agent: s.AgentName, Messages: ids, From: from}
	return v
}

// listed reports whether template, as gc session list prints it,
// <rig>/<binding>.<name> or <binding>.<name>, is an agent the pass reads.
func (n *Notify) listed(template string) bool {
	qualified := template[strings.LastIndex(template, "/")+1:]
	_, name, _ := strings.Cut(qualified, ".")
	return slices.Contains(n.Agents, qualified) || (name != "" && slices.Contains(n.Agents, name))
}

// mailNotice reports whether a mail notice is still to be delivered to the
// session, from Gas City's nudge queue or its conversation lane, either of
// which a sender's --notify fills.
func mailNotice(q gascity.NudgeQueue) bool {
	for _, item := range slices.Concat(q.Pending, q.InFlight) {
		if item.Source == "mail" || item.Source == "gc:mail" {
			return true
		}
	}
	return false
}
