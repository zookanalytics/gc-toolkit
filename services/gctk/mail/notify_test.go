package mail

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	gcfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity/fake"
)

var t0 = time.Date(2026, 11, 23, 2, 0, 0, 0, time.UTC)

// city is the session list and the mail a pass reads.
type city struct {
	*gcfake.Roster
	*gcfake.Mail
}

func newCity(sessions ...gascity.Session) *city {
	return &city{
		Roster: &gcfake.Roster{SessionList: sessions},
		Mail:   &gcfake.Mail{Inboxes: map[string]gascity.Inbox{}, Queues: map[string]gascity.NudgeQueue{}},
	}
}

// sitting is a session of the listed converse agent in the rig tools, aliased
// by its conversation as engage opens one.
func sitting(id, conversation, state string) gascity.Session {
	alias := "tools/gc-toolkit." + conversation
	return gascity.Session{ID: id, Template: "tools/gc-toolkit.converse-claude-opus", State: state,
		Alias: alias, AgentName: alias, SessionName: "s-" + id, Name: alias}
}

// mail puts unread messages in a sitting's inbox, which answers to its alias
// and its id as gc's does.
func (c *city) mail(s gascity.Session, msgs ...gascity.Message) {
	c.Inboxes[s.ID] = gascity.Inbox{Addresses: []string{s.Alias, s.ID}, Unread: msgs}
}

func msg(id, from string, age time.Duration) gascity.Message {
	return gascity.Message{ID: id, From: from, CreatedAt: t0.Add(-age)}
}

func (c *city) pass(t *testing.T, state string) Outcome {
	t.Helper()
	n := &Notify{City: c, Agents: []string{"converse-claude-opus"}, State: state, Now: func() time.Time { return t0 }}
	return n.Run(context.Background())
}

func notified(t *testing.T, state string) ledger {
	t.Helper()
	l, err := readLedger(state)
	if err != nil {
		t.Fatal(err)
	}
	return l
}

func nudges(c *city) []string {
	var out []string
	for _, n := range c.Nudges() {
		out = append(out, n.Session+": "+n.Message)
	}
	return out
}

// Mail to a running session of a listed agent requests one turn, named for its
// sender, and the ledger keeps the message, so a second pass over the same
// mail requests none.
func TestNewMailRequestsOneTurn(t *testing.T) {
	s := sitting("hq-1", "tk-1", "active")
	c := newCity(s)
	c.mail(s, msg("hq-m1", "tools/gc-toolkit.tk-2", time.Minute))
	state := t.TempDir()
	out := c.pass(t, state)
	if len(out.Failures) != 0 {
		t.Fatalf("failures %q", out.Failures)
	}
	if got := nudges(c); !slices.Equal(got, []string{"hq-1: You have mail from tools/gc-toolkit.tk-2"}) {
		t.Errorf("nudges %q", got)
	}
	if len(out.Record.Woken) != 1 || out.Record.Woken[0].Agent != "tools/gc-toolkit.tk-1" ||
		!slices.Equal(out.Record.Woken[0].Messages, []string{"hq-m1"}) {
		t.Errorf("record %+v", out.Record)
	}
	if e := notified(t, state)["hq-m1"]; e.Session != "hq-1" || !e.At.Equal(t0) {
		t.Errorf("the ledger holds %+v for the message", e)
	}
	out = c.pass(t, state)
	if len(out.Failures) != 0 || len(c.Nudges()) != 1 || len(out.Record.Woken) != 0 {
		t.Errorf("the second pass nudged %q, failures %q", nudges(c), out.Failures)
	}
}

// Only a listed agent's sessions are read, so mail to an agent off the list,
// or to human, whose mailbox is no session, requests no turn.
func TestAnAgentOffTheListIsNotRead(t *testing.T) {
	polecat := gascity.Session{ID: "hq-2", Template: "tools/gc-toolkit.polecat", State: "active", Alias: "tools/gc-toolkit.polecat-1"}
	c := newCity(polecat)
	c.mail(polecat, msg("hq-m2", "human", time.Minute))
	out := c.pass(t, t.TempDir())
	if len(out.Failures) != 0 || len(c.Nudges()) != 0 || len(c.Mail.Reads()) != 0 {
		t.Errorf("reads %q, nudges %q, failures %q", c.Mail.Reads(), nudges(c), out.Failures)
	}
}

// A session's mail to itself, a handoff's among it, requests no turn, whichever
// of its addresses it was sent from, and needs no read of its nudges.
func TestMailFromTheSessionItselfRequestsNoTurn(t *testing.T) {
	s := sitting("hq-1", "tk-1", "active")
	c := newCity(s)
	c.Inboxes["hq-1"] = gascity.Inbox{
		Addresses: []string{s.Alias, s.ID, "tools/gc-toolkit.c-tk-1"},
		Unread: []gascity.Message{msg("hq-h1", s.Alias, time.Hour), msg("hq-h2", s.ID, time.Hour),
			msg("hq-h3", "tools/gc-toolkit.c-tk-1", time.Hour), msg("hq-h4", s.SessionName, time.Hour)},
	}
	out := c.pass(t, t.TempDir())
	if len(out.Failures) != 0 || len(c.Nudges()) != 0 || slices.Contains(c.Mail.Reads(), "queue hq-1") {
		t.Errorf("reads %q, nudges %q, failures %q", c.Mail.Reads(), nudges(c), out.Failures)
	}
}

// Mail already read is not in the inbox gc lists, so it requests no turn, and
// the ledger lets go of a message once it is read.
func TestReadMailRequestsNoTurnAndLeavesTheLedger(t *testing.T) {
	s := sitting("hq-1", "tk-1", "active")
	c := newCity(s)
	c.mail(s, msg("hq-m1", "human", time.Minute))
	state := t.TempDir()
	c.pass(t, state)
	c.mail(s)
	out := c.pass(t, state)
	if len(out.Failures) != 0 || len(c.Nudges()) != 1 {
		t.Errorf("nudges %q, failures %q", nudges(c), out.Failures)
	}
	if l := notified(t, state); len(l) != 0 {
		t.Errorf("the ledger still holds %+v", l)
	}
}

// A session in a state that is not wakeable keeps its mail waiting, and its
// mail is not read: one that has finished, one held from running, one whose
// create failed, and one in a state Gas City has not named yet. Each wakeable
// state is nudged.
func TestOnlyAWakeableSessionIsNudged(t *testing.T) {
	var sessions []gascity.Session
	states := []string{"draining", "drained", "archived", "closed", "closing", "suspended", "quarantined", "failed-create", "orphaned", "unheard-of"}
	for i, st := range append(slices.Clone(states), Wakeable...) {
		sessions = append(sessions, sitting("hq-"+st, "tk-"+string(rune('a'+i)), st))
	}
	c := newCity(sessions...)
	for _, s := range sessions {
		c.mail(s, msg("m-"+s.State, "human", time.Minute))
	}
	out := c.pass(t, t.TempDir())
	if len(out.Failures) != 0 {
		t.Fatalf("failures %q", out.Failures)
	}
	var got []string
	for _, n := range c.Nudges() {
		got = append(got, strings.TrimPrefix(n.Session, "hq-"))
	}
	slices.Sort(got)
	want := slices.Sorted(slices.Values(Wakeable))
	if !slices.Equal(got, want) {
		t.Errorf("nudged %q, want %q", got, want)
	}
	for _, st := range states {
		if slices.Contains(c.Mail.Reads(), "inbox hq-"+st) {
			t.Errorf("the %s session's mail was read", st)
		}
	}
}

// A mail notice still to be delivered, from the nudge queue or the
// conversation lane, will tell the session of its mail, so the pass leaves it
// alone and keeps nothing in the ledger. Once the notice is gone and the mail
// is still unread, the next pass requests the turn. A nudge of another source
// tells the session nothing of its mail.
func TestAMailNoticeStillQueuedLeavesTheSessionAlone(t *testing.T) {
	for _, q := range []gascity.NudgeQueue{
		{Pending: []gascity.QueuedNudge{{ID: "n1", Source: "mail"}}},
		{InFlight: []gascity.QueuedNudge{{ID: "op-1", Source: "gc:mail"}}},
	} {
		s := sitting("hq-1", "tk-1", "active")
		c := newCity(s)
		c.mail(s, msg("hq-m1", "human", time.Minute))
		c.Queues["hq-1"] = q
		state := t.TempDir()
		out := c.pass(t, state)
		if len(out.Failures) != 0 || len(c.Nudges()) != 0 || len(out.Record.Told) != 1 || len(notified(t, state)) != 0 {
			t.Errorf("queue %+v: nudges %q, record %+v, failures %q", q, nudges(c), out.Record, out.Failures)
		}
		c.Queues["hq-1"] = gascity.NudgeQueue{Pending: []gascity.QueuedNudge{{ID: "n2", Source: "session"}}}
		c.pass(t, state)
		if len(c.Nudges()) != 1 {
			t.Errorf("queue %+v: once the notice was gone the pass nudged %q", q, nudges(c))
		}
	}
}

// New mail from several senders takes one nudge, naming each sender once, the
// oldest message's first.
func TestSeveralSendersShareOneTurn(t *testing.T) {
	s := sitting("hq-1", "tk-1", "asleep")
	c := newCity(s)
	c.mail(s, msg("hq-m1", "human", time.Minute), msg("hq-m2", "tools/gc-toolkit.tk-2", time.Hour), msg("hq-m3", "human", 2*time.Minute))
	state := t.TempDir()
	c.pass(t, state)
	if got := nudges(c); !slices.Equal(got, []string{"hq-1: You have mail from tools/gc-toolkit.tk-2, human"}) {
		t.Errorf("nudges %q", got)
	}
	if l := notified(t, state); len(l) != 3 {
		t.Errorf("the ledger holds %+v", l)
	}
}

// A nudge that does not land leaves its messages out of the ledger, so the next
// pass tries them again, and the run fails.
func TestANudgeThatFailsIsTriedAgain(t *testing.T) {
	s := sitting("hq-1", "tk-1", "active")
	c := newCity(s)
	c.mail(s, msg("hq-m1", "human", time.Minute))
	c.OnNudge = func(gcfake.Nudge) gascity.Bounded {
		return gascity.Bounded{Code: 1, Stderr: "gc session nudge: no such session\n"}
	}
	state := t.TempDir()
	out := c.pass(t, state)
	if len(out.Failures) != 1 || !strings.Contains(out.Failures[0], "no such session") || len(out.Record.Failed) != 1 {
		t.Errorf("failures %q, record %+v", out.Failures, out.Record)
	}
	if l := notified(t, state); len(l) != 0 {
		t.Errorf("the ledger holds %+v", l)
	}
	c.OnNudge = nil
	if out := c.pass(t, state); len(out.Failures) != 0 || len(c.Nudges()) != 2 {
		t.Errorf("the next pass nudged %q, failures %q", nudges(c), out.Failures)
	}
}

// A session whose mail or nudges do not read is not nudged, keeps what the
// ledger holds for it, and fails the run, and the pass still visits every other
// session.
func TestASessionThatDoesNotReadKeepsItsLedger(t *testing.T) {
	a, b, d := sitting("hq-a", "tk-a", "active"), sitting("hq-b", "tk-b", "active"), sitting("hq-d", "tk-d", "active")
	c := newCity(a, b, d)
	c.mail(a, msg("m-a", "human", time.Minute))
	c.mail(b, msg("m-b", "human", time.Minute))
	c.mail(d, msg("m-d", "human", time.Minute))
	state := t.TempDir()
	c.pass(t, state)
	c.mail(a, msg("m-a", "human", time.Minute), msg("m-a2", "human", 0))
	c.mail(d, msg("m-d", "human", time.Minute))
	c.InboxErr = map[string]error{"hq-a": errors.New("gc mail inbox hq-a did not read: exit 1")}
	c.mail(b, msg("m-b", "human", time.Minute), msg("m-b2", "human", 0))
	c.QueueErr = map[string]error{"hq-b": errors.New("gc nudge status hq-b did not read: exit 1")}
	c.mail(d, msg("m-d", "human", time.Minute), msg("m-d2", "human", 0))
	out := c.pass(t, state)
	if len(out.Failures) != 2 || len(out.Record.Failed) != 2 {
		t.Errorf("failures %q", out.Failures)
	}
	if got := nudges(c); len(got) != 4 || got[3] != "hq-d: You have mail from human" {
		t.Errorf("nudges %q", got)
	}
	l := notified(t, state)
	for _, id := range []string{"m-a", "m-b", "m-d", "m-d2"} {
		if !l.has(id) {
			t.Errorf("the ledger lost %s: %+v", id, l)
		}
	}
	if l.has("m-a2") || l.has("m-b2") {
		t.Errorf("the ledger holds a message no nudge was sent for: %+v", l)
	}
}

// A session list that does not read nudges nothing and leaves the ledger as it
// was.
func TestASessionListThatDoesNotReadNudgesNothing(t *testing.T) {
	s := sitting("hq-1", "tk-1", "active")
	c := newCity(s)
	c.mail(s, msg("hq-m1", "human", time.Minute))
	state := t.TempDir()
	c.pass(t, state)
	before, _ := os.ReadFile(filepath.Join(state, LedgerFile))
	c.SessionsErr = errors.New("gc session list did not read: exit 1")
	c.mail(s, msg("hq-m1", "human", time.Minute), msg("hq-m2", "human", 0))
	out := c.pass(t, state)
	if out.Record != nil || len(out.Failures) != 1 || len(c.Nudges()) != 1 {
		t.Errorf("record %+v, failures %q, nudges %q", out.Record, out.Failures, nudges(c))
	}
	if after, _ := os.ReadFile(filepath.Join(state, LedgerFile)); string(after) != string(before) {
		t.Errorf("the ledger changed from %s to %s", before, after)
	}
}

// A ledger that does not read nudges nothing, since nudging past it would
// request a second turn for every message it holds.
func TestALedgerThatDoesNotReadNudgesNothing(t *testing.T) {
	s := sitting("hq-1", "tk-1", "active")
	c := newCity(s)
	c.mail(s, msg("hq-m1", "human", time.Minute))
	state := t.TempDir()
	if err := os.WriteFile(filepath.Join(state, LedgerFile), []byte("{not json"), 0o644); err != nil {
		t.Fatal(err)
	}
	out := c.pass(t, state)
	if out.Record != nil || len(out.Failures) != 1 || len(c.Nudges()) != 0 || len(c.Roster.Reads()) != 0 {
		t.Errorf("record %+v, failures %q, nudges %q, reads %q", out.Record, out.Failures, nudges(c), c.Roster.Reads())
	}
}

// Two passes at once, as the two orders' runs can be, request one turn for one
// message: the second waits for the first's lock and reads the ledger it wrote.
func TestTwoPassesAtOnceRequestOneTurn(t *testing.T) {
	s := sitting("hq-1", "tk-1", "active")
	c := newCity(s)
	c.mail(s, msg("hq-m1", "human", time.Minute))
	c.OnNudge = func(gcfake.Nudge) gascity.Bounded {
		time.Sleep(200 * time.Millisecond)
		return gascity.Bounded{}
	}
	state := t.TempDir()
	var wg sync.WaitGroup
	outs := make([]Outcome, 2)
	for i := range outs {
		wg.Add(1)
		go func() {
			defer wg.Done()
			outs[i] = c.pass(t, state)
		}()
	}
	wg.Wait()
	if len(c.Nudges()) != 1 || len(outs[0].Failures)+len(outs[1].Failures) != 0 {
		t.Errorf("nudges %q, failures %q and %q", nudges(c), outs[0].Failures, outs[1].Failures)
	}
}

// A pass whose lock another holds until its deadline fails and nudges nothing.
func TestALockHeldPastTheDeadlineFailsThePass(t *testing.T) {
	s := sitting("hq-1", "tk-1", "active")
	c := newCity(s)
	c.mail(s, msg("hq-m1", "human", time.Minute))
	state := t.TempDir()
	release, err := lock(context.Background(), state)
	if err != nil {
		t.Fatal(err)
	}
	defer release()
	ctx, cancel := context.WithTimeout(context.Background(), 300*time.Millisecond)
	defer cancel()
	n := &Notify{City: c, Agents: []string{"converse-claude-opus"}, State: state, Now: func() time.Time { return t0 }}
	out := n.Run(ctx)
	if out.Record != nil || len(out.Failures) != 1 || !strings.Contains(out.Failures[0], "stayed held") || len(c.Nudges()) != 0 {
		t.Errorf("record %+v, failures %q, nudges %q", out.Record, out.Failures, nudges(c))
	}
}

// An agent is named by the name its pack gives it, or with its binding, and a
// session's template carries its rig where it has one.
func TestAnAgentIsNamedWithOrWithoutItsBinding(t *testing.T) {
	for _, tc := range []struct {
		agents   []string
		template string
		want     bool
	}{
		{[]string{"converse-claude-opus"}, "tools/gc-toolkit.converse-claude-opus", true},
		{[]string{"gc-toolkit.converse-claude-opus"}, "tools/gc-toolkit.converse-claude-opus", true},
		{[]string{"converse-claude-opus"}, "gc-toolkit.converse-claude-opus", true},
		{[]string{"other.converse-claude-opus"}, "tools/gc-toolkit.converse-claude-opus", false},
		{[]string{"converse-claude-opus"}, "tools/gc-toolkit.converse-codex", false},
		{[]string{"converse"}, "tools/gc-toolkit.converse-claude-opus", false},
		{[]string{"converse-claude-opus"}, "", false},
	} {
		n := &Notify{Agents: tc.agents}
		if got := n.listed(tc.template); got != tc.want {
			t.Errorf("agents %q, template %q: listed %v", tc.agents, tc.template, got)
		}
	}
}
