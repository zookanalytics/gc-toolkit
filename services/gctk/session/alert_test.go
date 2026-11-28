package session

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity/fake"
)

// p0 is when the tests' prompt appears.
var p0 = time.Date(2026, 11, 23, 20, 13, 42, 0, time.UTC)

// alertCity is the event log, the roster and mail the pass reads and sends
// through, on one clock.
type alertCity struct {
	*fake.EventLog
	*fake.Roster
	*fake.Mail
	clock     time.Time
	recipient string
	agents    []string
	state     string
}

func newAlertCity(t *testing.T) *alertCity {
	c := &alertCity{
		Roster: &fake.Roster{AgentList: []gascity.Agent{
			{QualifiedName: "gc-toolkit.mechanik", Name: "mechanik", Scope: "city"},
			{QualifiedName: "gc-toolkit/gc-toolkit.polecat", Name: "polecat", Dir: "gc-toolkit", Scope: "rig"},
		}},
		Mail:      &fake.Mail{},
		recipient: "human",
		agents:    []string{"mechanik"},
		state:     t.TempDir(),
	}
	c.EventLog = &fake.EventLog{Now: func() time.Time { return c.clock }}
	return c
}

// pass runs one pass at d after p0.
func (c *alertCity) pass(d time.Duration) AlertOutcome {
	c.clock = p0.Add(d)
	a := &PromptAlert{City: c, Recipient: c.recipient, Agents: c.agents, State: c.state, Now: func() time.Time { return c.clock }}
	return a.Run(context.Background())
}

// sent is each send since the count n of sends before it.
func (c *alertCity) sentSince(n int) []gascity.MailSend { return c.Sends()[n:] }

func pendingEv(at time.Duration, session, request string) gascity.Event {
	return gascity.Event{Type: pendingType, Ts: p0.Add(at), Actor: "controller", Subject: session, Payload: json.RawMessage(fmt.Sprintf(
		`{"session_id":%q,"template":"gc-toolkit/gc-toolkit.polecat","request_id":%q,"kind":"approval","prompt":"Bash: rm -rf build","options":["Yes","No"],"metadata":{"source":"tmux","tool_name":"Bash","command":"rm -rf build","description":"Remove the build"}}`,
		session, request))}
}

func escalationEv(at time.Duration, session, reason string) gascity.Event {
	return gascity.Event{Type: escalatedType, Ts: p0.Add(at), Actor: "controller", Subject: "tk-cp742aw", Message: reason, Payload: json.RawMessage(fmt.Sprintf(
		`{"session_id":%q,"session_name":"gc-toolkit__polecat-%s","template":"gc-toolkit/gc-toolkit.polecat","provider":"claude","bead_id":"tk-cp742aw","store_ref":"rig:gc-toolkit","generation":2,"reason":%q}`,
		session, session, reason))}
}

func clearEv(at time.Duration, session, request, reason string) gascity.Event {
	return gascity.Event{Type: clearedType, Ts: p0.Add(at), Actor: "controller", Subject: session, Payload: json.RawMessage(fmt.Sprintf(
		`{"session_id":%q,"request_id":%q,"kind":"approval","reason":%q}`, session, request, reason))}
}

func noFailures(t *testing.T, out AlertOutcome) {
	t.Helper()
	if len(out.Failures) > 0 || out.Record == nil {
		t.Fatalf("the pass failed: %q, record %+v", out.Failures, out.Record)
	}
}

func addresses(sends []gascity.MailSend) []string {
	var out []string
	for _, s := range sends {
		out = append(out, s.To)
	}
	return out
}

// A seat Gas City escalates while it waits at a prompt gets one alert to the
// escalation recipient and one copy to the mechanik, saying who waits, since
// when, and the prompt as Gas City recorded it. Gas City's escalations of the
// same prompt after that mail nothing.
func TestOneMailPerStuckPromptAcrossEscalations(t *testing.T) {
	c := newAlertCity(t)
	c.Add(pendingEv(0, "s-1", "tmux-a"), escalationEv(22*time.Minute, "s-1", nudgeRefused))
	out := c.pass(23 * time.Minute)
	noFailures(t, out)
	sends := c.Sends()
	if got := addresses(sends); !slices.Equal(got, []string{"human", "gc-toolkit.mechanik"}) {
		t.Fatalf("mailed %q", got)
	}
	for _, s := range sends {
		if s.Notify {
			t.Errorf("the mail to %s requests its turn", s.To)
		}
		if s.Subject != "Prompt waiting: session s-1 (gc-toolkit/gc-toolkit.polecat)" || s.Dedup != "prompt-alert:s-1/tmux-a/1" {
			t.Errorf("the mail to %s is %q under %q", s.To, s.Subject, s.Dedup)
		}
		for _, want := range []string{
			"Session s-1 (gc-toolkit__polecat-s-1), agent gc-toolkit.polecat in rig gc-toolkit, holding tk-cp742aw, has waited 23m",
			"since 2026-11-23T20:13:42Z", "escalated the seat at 2026-11-23T20:35:42Z",
			"Kind: approval\nTool: Bash\nCommand: rm -rf build\nDescription: Remove the build\n",
			"gc session peek s-1", "gc session attach s-1", "not from a person",
		} {
			if !strings.Contains(s.Body, want) {
				t.Errorf("the mail to %s does not say %q:\n%s", s.To, want, s.Body)
			}
		}
	}
	if len(out.Record.Alerted) != 1 || !slices.Equal(out.Record.Alerted[0].To, []string{"human", "gc-toolkit.mechanik"}) {
		t.Errorf("record %+v", out.Record)
	}
	for _, at := range []time.Duration{84 * time.Minute, 146 * time.Minute, 208 * time.Minute} {
		c.Add(escalationEv(at, "s-1", nudgeRefused))
		out := c.pass(at + time.Minute)
		noFailures(t, out)
		if n := len(c.Sends()); n != 2 {
			t.Fatalf("the escalation at %s mailed again: %q", at, addresses(c.sentSince(2)))
		}
		if len(out.Record.Alerted) != 0 || len(out.Record.Waiting) != 1 || out.Record.Waiting[0].Session != "s-1" {
			t.Errorf("record %+v", out.Record)
		}
	}
}

// Once a prompt that was alerted clears, each recipient gets one short note
// saying it cleared, after how long, and how, as Gas City records it, and the
// incident leaves the ledger. An escalation still in the window opens no
// second alert.
func TestTheClearNoteSaysHowThePromptCleared(t *testing.T) {
	for reason, want := range map[string]string{
		"resolved":     "Gas City records it resolved: it was answered or withdrawn.",
		"session_gone": "Gas City records the session gone: it is no longer active, and the prompt went with it.",
	} {
		t.Run(reason, func(t *testing.T) {
			c := newAlertCity(t)
			c.Add(pendingEv(0, "s-1", "tmux-a"), escalationEv(22*time.Minute, "s-1", nudgeRefused))
			noFailures(t, c.pass(23*time.Minute))
			c.Add(escalationEv(84*time.Minute, "s-1", nudgeRefused), clearEv(100*time.Minute, "s-1", "tmux-a", reason))
			out := c.pass(101 * time.Minute)
			noFailures(t, out)
			notes := c.sentSince(2)
			if got := addresses(notes); !slices.Equal(got, []string{"gc-toolkit.mechanik", "human"}) {
				t.Fatalf("noted %q", got)
			}
			for _, s := range notes {
				if s.Subject != "Prompt cleared: session s-1 (gc-toolkit/gc-toolkit.polecat)" || s.Dedup != "prompt-cleared:s-1/tmux-a/1" || s.Notify {
					t.Errorf("the note to %s is %q under %q, notify %v", s.To, s.Subject, s.Dedup, s.Notify)
				}
				if !strings.Contains(s.Body, "waited at since 2026-11-23T20:13:42Z cleared at 2026-11-23T21:53:42Z, after 1h40m. "+want) {
					t.Errorf("the note to %s says:\n%s", s.To, s.Body)
				}
			}
			if len(out.Record.Noted) != 1 || len(out.Record.Waiting) != 0 {
				t.Errorf("record %+v", out.Record)
			}
			out = c.pass(102 * time.Minute)
			noFailures(t, out)
			if n := len(c.Sends()); n != 4 {
				t.Errorf("a pass after the note mailed again: %q", addresses(c.sentSince(4)))
			}
			led, err := readAlerts(c.state)
			if err != nil || len(led) != 0 {
				t.Errorf("the ledger holds %v, %v", led, err)
			}
		})
	}
}

// A clear whose own pass failed or never ran is read by the next pass that
// runs, however long after the clear, and that pass sends its note once.
func TestAClearIsNotedByTheNextPassHoweverLate(t *testing.T) {
	c := newAlertCity(t)
	c.Add(pendingEv(0, "s-1", "tmux-a"), escalationEv(22*time.Minute, "s-1", nudgeRefused))
	noFailures(t, c.pass(23*time.Minute))
	c.Add(clearEv(time.Hour, "s-1", "tmux-a", "resolved"))
	out := c.pass(26 * time.Hour)
	noFailures(t, out)
	notes := c.sentSince(2)
	if got := addresses(notes); !slices.Equal(got, []string{"gc-toolkit.mechanik", "human"}) || !strings.Contains(notes[0].Body, "cleared at 2026-11-23T21:13:42Z, after 1h. ") {
		t.Fatalf("the pass a day after the clear mailed %+v", notes)
	}
	if len(out.Record.Waiting) != 0 {
		t.Errorf("record %+v", out.Record)
	}
	noFailures(t, c.pass(27*time.Hour))
	if n := len(c.Sends()); n != 4 {
		t.Errorf("a later pass mailed %q", addresses(c.sentSince(4)))
	}
	if led, err := readAlerts(c.state); err != nil || len(led) != 0 {
		t.Errorf("the ledger holds %v, %v", led, err)
	}
}

// An escalation for any reason but nudge_refused is not about a prompt: it
// mails nothing, and with no incident open the pass reads nothing past the
// escalations.
func TestAnEscalationForAnotherReasonSendsNothing(t *testing.T) {
	c := newAlertCity(t)
	c.Add(pendingEv(0, "s-1", "tmux-a"), escalationEv(22*time.Minute, "s-1", "rate_limited_fresh_refused"))
	out := c.pass(23 * time.Minute)
	noFailures(t, out)
	if len(c.Sends()) != 0 || len(out.Record.Alerted) != 0 || len(out.Record.Waiting) != 0 {
		t.Errorf("mailed %q, record %+v", addresses(c.Sends()), out.Record)
	}
	if got := c.EventLog.Reads(); !slices.Equal(got, []fake.Read{{Type: escalatedType, Since: EscalationWindow}}) {
		t.Errorf("read %+v", got)
	}
}

// A send that fails fails the run, naming what was not mailed and to whom, and
// leaves the ledger without it, so the next pass sends it and only it.
func TestAFailedSendFailsTheRunAndTheNextPassSendsIt(t *testing.T) {
	c := newAlertCity(t)
	c.OnSend = func(s gascity.MailSend) (gascity.MailSent, error) {
		if s.To == "gc-toolkit.mechanik" {
			return gascity.MailSent{}, errors.New("gc mail send gc-toolkit.mechanik did not send: exit 1: store unavailable")
		}
		return gascity.MailSent{ID: "m-1"}, nil
	}
	c.Add(pendingEv(0, "s-1", "tmux-a"), escalationEv(22*time.Minute, "s-1", nudgeRefused))
	out := c.pass(23 * time.Minute)
	if len(out.Failures) != 1 || !strings.Contains(out.Failures[0], "was not mailed to gc-toolkit.mechanik") || !strings.Contains(out.Failures[0], "store unavailable") {
		t.Fatalf("failures %q", out.Failures)
	}
	if len(out.Record.Alerted) != 1 || !slices.Equal(out.Record.Alerted[0].To, []string{"human"}) {
		t.Errorf("record %+v", out.Record)
	}
	c.OnSend = nil
	noFailures(t, c.pass(30*time.Minute))
	if got := addresses(c.sentSince(2)); !slices.Equal(got, []string{"gc-toolkit.mechanik"}) {
		t.Errorf("the next pass mailed %q", got)
	}
	noFailures(t, c.pass(31*time.Minute))
	if n := len(c.Sends()); n != 3 {
		t.Errorf("a third pass mailed %q", addresses(c.sentSince(3)))
	}
}

// A prompt that clears before any pass takes its escalation was never alerted,
// so nobody is told it cleared either.
func TestAPromptThatClearsBeforeAnyPassIsNotMailed(t *testing.T) {
	c := newAlertCity(t)
	c.Add(pendingEv(0, "s-1", "tmux-a"), escalationEv(22*time.Minute, "s-1", nudgeRefused), clearEv(25*time.Minute, "s-1", "tmux-a", "resolved"))
	noFailures(t, c.pass(26*time.Minute))
	if len(c.Sends()) != 0 {
		t.Errorf("mailed %q", addresses(c.Sends()))
	}
	if led, err := readAlerts(c.state); err != nil || len(led) != 0 {
		t.Errorf("the ledger holds %v, %v", led, err)
	}
}

// A seat escalated before its prompt appeared was not escalated for it, so the
// prompt waits for the seat's next escalation.
func TestAnEscalationBeforeThePromptWaitsForTheNextOne(t *testing.T) {
	c := newAlertCity(t)
	c.Add(escalationEv(-10*time.Minute, "s-1", nudgeRefused), pendingEv(0, "s-1", "tmux-a"))
	noFailures(t, c.pass(time.Minute))
	if len(c.Sends()) != 0 {
		t.Fatalf("mailed %q", addresses(c.Sends()))
	}
	c.Add(escalationEv(50*time.Minute, "s-1", nudgeRefused))
	noFailures(t, c.pass(51*time.Minute))
	if got := addresses(c.Sends()); !slices.Equal(got, []string{"human", "gc-toolkit.mechanik"}) {
		t.Errorf("mailed %q", got)
	}
}

// A prompt Gas City replaces with another is noted as replaced, and the new
// prompt is alerted once Gas City escalates the seat for it.
func TestAReplacedPromptIsNotedAndItsSuccessorAlertedOnItsOwnEscalation(t *testing.T) {
	c := newAlertCity(t)
	c.Add(pendingEv(0, "s-1", "tmux-a"), escalationEv(22*time.Minute, "s-1", nudgeRefused))
	noFailures(t, c.pass(23*time.Minute))
	c.Add(clearEv(30*time.Minute, "s-1", "tmux-a", "replaced"), pendingEv(30*time.Minute, "s-1", "tmux-b"))
	noFailures(t, c.pass(31*time.Minute))
	notes := c.sentSince(2)
	if len(notes) != 2 || !strings.HasPrefix(notes[0].Subject, "Prompt cleared:") || !strings.Contains(notes[0].Body, "Gas City records it replaced") {
		t.Fatalf("mailed %+v", notes)
	}
	c.Add(escalationEv(84*time.Minute, "s-1", nudgeRefused))
	noFailures(t, c.pass(85*time.Minute))
	alerts := c.sentSince(4)
	if len(alerts) != 2 || alerts[0].Dedup != "prompt-alert:s-1/tmux-b/4" || !strings.Contains(alerts[0].Body, "has waited 55m") {
		t.Errorf("mailed %+v", alerts)
	}
}

// Gas City's request id for a pane's prompt is a hash of its text, so the same
// prompt coming back later is a new incident, alerted on its own.
func TestAPromptThatComesBackIsANewIncident(t *testing.T) {
	c := newAlertCity(t)
	c.Add(pendingEv(0, "s-1", "tmux-a"), escalationEv(22*time.Minute, "s-1", nudgeRefused))
	noFailures(t, c.pass(23*time.Minute))
	c.Add(clearEv(30*time.Minute, "s-1", "tmux-a", "resolved"))
	noFailures(t, c.pass(31*time.Minute))
	if len(c.Sends()) != 4 {
		t.Fatalf("the alert and its note mailed %q", addresses(c.Sends()))
	}
	c.Add(pendingEv(60*time.Minute, "s-1", "tmux-a"), escalationEv(82*time.Minute, "s-1", nudgeRefused))
	noFailures(t, c.pass(83*time.Minute))
	alerts := c.sentSince(4)
	if len(alerts) != 2 || alerts[0].Dedup != "prompt-alert:s-1/tmux-a/4" {
		t.Errorf("mailed %+v", alerts)
	}
}

// An escalation recipient other than human has its turn requested, as core's
// escalate.sh requests it, and a copy never does. An agent that is the
// escalation recipient gets the message once.
func TestOnlyTheEscalationRecipientIsWoken(t *testing.T) {
	c := newAlertCity(t)
	c.recipient = "gc-toolkit.mayor"
	c.Add(pendingEv(0, "s-1", "tmux-a"), escalationEv(22*time.Minute, "s-1", nudgeRefused))
	noFailures(t, c.pass(23*time.Minute))
	sends := c.Sends()
	if len(sends) != 2 || sends[0].To != "gc-toolkit.mayor" || !sends[0].Notify || sends[1].To != "gc-toolkit.mechanik" || sends[1].Notify {
		t.Errorf("mailed %+v", sends)
	}
	c = newAlertCity(t)
	c.recipient = "gc-toolkit.mechanik"
	c.Add(pendingEv(0, "s-1", "tmux-a"), escalationEv(22*time.Minute, "s-1", nudgeRefused))
	noFailures(t, c.pass(23*time.Minute))
	if sends := c.Sends(); len(sends) != 1 || sends[0].To != "gc-toolkit.mechanik" || !sends[0].Notify {
		t.Errorf("mailed %+v", sends)
	}
}

// An agent the roster does not name, or a roster that does not read, fails
// the copy and the run, and the escalation recipient is mailed all the same.
func TestACopyWithNoAddressFailsTheRunAlone(t *testing.T) {
	c := newAlertCity(t)
	c.agents = []string{"mechanik", "nobody"}
	c.Add(pendingEv(0, "s-1", "tmux-a"), escalationEv(22*time.Minute, "s-1", nudgeRefused))
	out := c.pass(23 * time.Minute)
	if len(out.Failures) != 1 || !strings.Contains(out.Failures[0], "names no agent nobody") {
		t.Errorf("failures %q", out.Failures)
	}
	if got := addresses(c.Sends()); !slices.Equal(got, []string{"human", "gc-toolkit.mechanik"}) {
		t.Errorf("mailed %q", got)
	}
	c = newAlertCity(t)
	c.AgentsErr = errors.New("gc agent list did not read the city's roster")
	c.Add(pendingEv(0, "s-1", "tmux-a"), escalationEv(22*time.Minute, "s-1", nudgeRefused))
	out = c.pass(23 * time.Minute)
	if len(out.Failures) != 1 || !strings.Contains(out.Failures[0], "roster did not read") {
		t.Errorf("failures %q", out.Failures)
	}
	if got := addresses(c.Sends()); !slices.Equal(got, []string{"human"}) {
		t.Errorf("mailed %q", got)
	}
}

// A question's mail gives the question and each answer it offers.
func TestAQuestionsMailGivesItsOptions(t *testing.T) {
	c := newAlertCity(t)
	c.Add(gascity.Event{Type: pendingType, Ts: p0, Actor: "controller", Subject: "s-1", Payload: json.RawMessage(
		`{"session_id":"s-1","request_id":"tmux-question-1","kind":"question","prompt":"Apply the four clear ones?","options":["Apply all four (Recommended)","Not today"],"metadata":{"header":"Piece 1 of 3","source":"tmux"}}`)},
		escalationEv(22*time.Minute, "s-1", nudgeRefused))
	noFailures(t, c.pass(23*time.Minute))
	if sends := c.Sends(); len(sends) != 2 || !strings.Contains(sends[0].Body,
		"Kind: question\nHeader: Piece 1 of 3\nQuestion: Apply the four clear ones?\nOptions:\n  1. Apply all four (Recommended)\n  2. Not today\n") {
		t.Errorf("mailed %+v", sends)
	}
}

// A command longer than the cap is cut, and the mail says where.
func TestALongCommandIsCut(t *testing.T) {
	c := newAlertCity(t)
	long := strings.Repeat("é", CommandCap+5)
	c.Add(gascity.Event{Type: pendingType, Ts: p0, Actor: "controller", Subject: "s-1", Payload: json.RawMessage(
		`{"session_id":"s-1","request_id":"tmux-a","kind":"approval","metadata":{"tool_name":"Bash","command":"` + long + `"}}`)},
		escalationEv(22*time.Minute, "s-1", nudgeRefused))
	noFailures(t, c.pass(23*time.Minute))
	want := "Command: " + strings.Repeat("é", CommandCap) + fmt.Sprintf("… (cut at %d characters)\n", CommandCap)
	if sends := c.Sends(); len(sends) != 2 || !strings.Contains(sends[0].Body, want) {
		t.Errorf("mailed %+v", sends)
	}
}

// A ledger that does not read mails nothing, since mailing past it would send
// every alert it records again, and an event log that does not read mails
// nothing either.
func TestAReadThePassRestsOnMailsNothing(t *testing.T) {
	c := newAlertCity(t)
	if err := os.WriteFile(filepath.Join(c.state, AlertLedgerFile), []byte("{"), 0o644); err != nil {
		t.Fatal(err)
	}
	c.Add(pendingEv(0, "s-1", "tmux-a"), escalationEv(22*time.Minute, "s-1", nudgeRefused))
	if out := c.pass(23 * time.Minute); out.Record != nil || len(out.Failures) != 1 || !strings.Contains(out.Failures[0], "nothing was mailed") {
		t.Errorf("answered %+v", out)
	}
	for _, typ := range []string{escalatedType, clearedType} {
		c := newAlertCity(t)
		c.ReadErr = map[string]error{typ: errors.New("gc events did not read")}
		c.Add(pendingEv(0, "s-1", "tmux-a"), escalationEv(22*time.Minute, "s-1", nudgeRefused))
		if out := c.pass(23 * time.Minute); out.Record != nil || len(out.Failures) != 1 {
			t.Errorf("an unread %s answered %+v", typ, out)
		}
		if len(c.Sends()) != 0 {
			t.Errorf("an unread %s mailed %q", typ, addresses(c.Sends()))
		}
	}
}

// A prompts read that fails opens no incident and fails the run, and the
// clears and the mail owed for the incidents already open still go.
func TestAnUnreadPromptsReadOpensNothingNew(t *testing.T) {
	c := newAlertCity(t)
	c.Add(pendingEv(0, "s-1", "tmux-a"), escalationEv(22*time.Minute, "s-1", nudgeRefused))
	noFailures(t, c.pass(23*time.Minute))
	c.ReadErr = map[string]error{pendingType: errors.New("gc events did not read")}
	c.Add(pendingEv(30*time.Minute, "s-2", "tmux-b"), escalationEv(52*time.Minute, "s-2", nudgeRefused), clearEv(53*time.Minute, "s-1", "tmux-a", "resolved"))
	out := c.pass(54 * time.Minute)
	if len(out.Failures) != 1 || !strings.Contains(out.Failures[0], "no new prompt was alerted") {
		t.Errorf("failures %q", out.Failures)
	}
	sends := c.sentSince(2)
	if len(sends) != 2 || !strings.HasPrefix(sends[0].Subject, "Prompt cleared: session s-1") {
		t.Errorf("mailed %+v", sends)
	}
}
