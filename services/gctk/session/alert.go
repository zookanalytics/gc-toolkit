package session

import (
	"cmp"
	"context"
	"encoding/json"
	"fmt"
	"maps"
	"slices"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
)

// The Gas City events the prompt alert reads, and the reason of the escalation
// it acts on. Gas City's work ladder records work.escalated with reason
// nudge_refused when a pool seat refuses its third nudge in a row because it
// waits at a pending interaction or its runtime is unavailable, and again
// every sixth refusal after, about hourly ((*ladderPass).nudge in
// cmd/gc/work_ladder_lane.go and refusalAlerts in internal/workladder/decide.go
// at gastownhall/gascity 6dce31bbb6). Its controller records session.pending
// when a session gains a pending interaction, a permission prompt or a
// question, and session.pending_cleared when that interaction is gone, once
// per transition (SessionPendingPayload and SessionPendingClearedPayload in
// internal/api/event_payloads.go there).
const (
	escalatedType = "work.escalated"
	pendingType   = "session.pending"
	clearedType   = "session.pending_cleared"
	nudgeRefused  = "nudge_refused"
)

const (
	// EscalationWindow is how far back a pass reads Gas City's escalations.
	// While a prompt stays up, Gas City escalates its seat about hourly, so a
	// pass that runs on any event inside the window still sees the escalation
	// whose own run failed.
	EscalationWindow = 2 * time.Hour
	// AlertDeadline bounds a pass from its start: its wait for the lock, its
	// reads and its mail. SendBound bounds each message.
	AlertDeadline = 120 * time.Second
	SendBound     = 30 * time.Second
	// CommandCap is how many characters of a prompt's command a mail carries.
	CommandCap = 2000
)

// AlertCity is Gas City as the prompt alert reaches it: the event log, the
// roster and mail.
type AlertCity interface {
	Events(ctx context.Context, typ string, since time.Duration) ([]gascity.Event, error)
	Agents() ([]gascity.Agent, error)
	SendMail(ctx context.Context, m gascity.MailSend) (gascity.MailSent, error)
}

// PromptAlert is the pass: it opens an incident for each prompt Gas City has
// escalated the seat that waits at it for, mails its alert once to each
// recipient, and once the prompt clears, mails each recipient the alert
// reached one note.
type PromptAlert struct {
	City AlertCity
	// Recipient is the city's escalation recipient, GC_ESCALATION_RECIPIENT or
	// human, which every message goes to. Its messages request its turn when
	// it is not human, as core's escalate.sh requests one.
	Recipient string
	// Agents names each agent that gets a copy of every message, by the name
	// its pack gives it, such as mechanik, or its qualified name. A copy
	// requests no turn, so the agent reads it at its next turn.
	Agents []string
	// State is the directory the ledger and the lock live in.
	State string
	Now   func() time.Time
}

// Mailed is a prompt the pass mailed about, and each address that got it.
type Mailed struct {
	Session string   `json:"session"`
	Request string   `json:"request"`
	To      []string `json:"to"`
}

// Waiting is a prompt the ledger holds open after the pass: escalated, and not
// yet cleared.
type Waiting struct {
	Session  string    `json:"session"`
	Request  string    `json:"request"`
	Appeared time.Time `json:"appeared"`
}

// AlertRecord is what a pass did, which the verb prints.
type AlertRecord struct {
	Read    time.Time `json:"read"`
	Alerted []Mailed  `json:"alerted"`
	Noted   []Mailed  `json:"noted,omitempty"`
	Waiting []Waiting `json:"waiting,omitempty"`
}

// Summary is the record in one line.
func (rec *AlertRecord) Summary() string {
	var parts []string
	for _, m := range rec.Alerted {
		parts = append(parts, fmt.Sprintf("alerted %s to the prompt session %s waits at", strings.Join(m.To, ", "), m.Session))
	}
	for _, m := range rec.Noted {
		parts = append(parts, fmt.Sprintf("told %s the prompt of session %s cleared", strings.Join(m.To, ", "), m.Session))
	}
	switch {
	case len(parts) > 0:
	case len(rec.Waiting) > 0:
		parts = append(parts, fmt.Sprintf("mailed nothing new: %d escalated prompts still wait, each alerted already", len(rec.Waiting)))
	default:
		parts = append(parts, "no session waits at a prompt Gas City escalated")
	}
	return strings.Join(parts, "; ")
}

// AlertOutcome is what a run did: its record, nil when a read the whole pass
// rests on failed, and each thing that failed, any of which makes the run's
// exit non-zero.
type AlertOutcome struct {
	Record   *AlertRecord
	Failures []string
}

// The payloads the pass reads: work.escalated's (WorkLadderPayload in
// internal/events/work_payloads.go at gastownhall/gascity 6dce31bbb6),
// session.pending's and session.pending_cleared's.
type escalationPayload struct {
	SessionID string `json:"session_id"`
	Reason    string `json:"reason"`
	seat
}

type pendingPayload struct {
	SessionID string `json:"session_id"`
	RequestID string `json:"request_id"`
	prompt
}

type clearedPayload struct {
	SessionID string `json:"session_id"`
	RequestID string `json:"request_id"`
	Reason    string `json:"reason"`
}

// refusal is one nudge_refused escalation of a seat.
type refusal struct {
	seq  int64
	at   time.Time
	seat seat
}

// pending is one prompt a session gained.
type pending struct {
	seq     int64
	at      time.Time
	request string
	prompt  prompt
}

// clears is each session's cleared prompts, oldest first.
type clears map[string][]clearedAt

type clearedAt struct {
	request string
	cleared clearing
}

// of is the first clear of the session's prompt request recorded after seq.
func (c clears) of(session, request string, seq int64) *clearing {
	for _, e := range c[session] {
		if e.request == request && e.cleared.Seq > seq {
			cl := e.cleared
			return &cl
		}
	}
	return nil
}

// recipient is an address a message goes to, and whether it requests the
// recipient's turn.
type recipient struct {
	address string
	notify  bool
}

// Run makes one pass. Its reads and mail end when ctx does, or at
// AlertDeadline from the start of the run, whichever comes first.
func (a *PromptAlert) Run(ctx context.Context) AlertOutcome {
	ctx, cancel := context.WithTimeout(ctx, AlertDeadline)
	defer cancel()
	now := a.Now().UTC().Truncate(time.Second)
	release, err := lockAlerts(ctx, a.State)
	if err != nil {
		return AlertOutcome{Failures: []string{err.Error()}}
	}
	defer release()
	led, err := readAlerts(a.State)
	if err != nil {
		return AlertOutcome{Failures: []string{err.Error() + ", so nothing was mailed"}}
	}
	escalated, err := a.City.Events(ctx, escalatedType, EscalationWindow)
	if err != nil {
		return AlertOutcome{Failures: []string{"Gas City's escalations did not read, so no prompt was judged: " + err.Error()}}
	}
	refused, failures := readRefusals(escalated)
	rec := &AlertRecord{Read: now, Alerted: []Mailed{}}
	if len(refused) == 0 && len(led) == 0 {
		return AlertOutcome{Record: rec, Failures: failures}
	}
	// The clears are read with no window, so the next pass reads a clear
	// whose own pass failed or never ran, however late it comes, and sends
	// that incident's note. With no window gc events answers the newest page
	// of clears, 500 of them (fetchCityEvents in cmd/gc/cmd_events.go at
	// gastownhall/gascity 6dce31bbb6), from the city's archived log too, which
	// its [events.rotation] archive_retain_age keeps.
	clearedEvents, err := a.City.Events(ctx, clearedType, 0)
	if err != nil {
		return AlertOutcome{Failures: append(failures, "the clears of the sessions' prompts did not read, so no prompt was judged: "+err.Error())}
	}
	cleared, bad := readClears(clearedEvents)
	failures = append(failures, bad...)
	for _, inc := range led {
		if inc.Cleared == nil {
			inc.Cleared = cleared.of(inc.Session, inc.Request, inc.PendingSeq)
		}
	}
	if len(refused) > 0 {
		// The prompts are read with no window too, the newest page as the
		// clears are. Gas City records a prompt once, when it appears, and its
		// seat's escalations repeat without it, so a prompt that has waited
		// past any window when a pass first takes its seat's escalation, at
		// the orders' first pass or after a day of failed ones, is still
		// found.
		pendingEvents, err := a.City.Events(ctx, pendingType, 0)
		if err != nil {
			failures = append(failures, "the sessions' prompts did not read, so no new prompt was alerted: "+err.Error())
		} else {
			prompts, bad := readPrompts(pendingEvents)
			failures = append(failures, bad...)
			open(led, refused, prompts, cleared)
		}
	}
	failures = append(failures, a.deliver(ctx, led, now, rec)...)
	if err := writeAlerts(a.State, led); err != nil {
		failures = append(failures, err.Error())
	}
	return AlertOutcome{Record: rec, Failures: failures}
}

// open adds an incident for each escalated session whose newest prompt has an
// escalation after it and no clear: the prompt Gas City escalated the seat
// for. A seat escalated before its prompt appeared waits for its next
// escalation, and a prompt that cleared before any pass took it opens nothing,
// since nobody was told it waited.
func open(led alerts, refused map[string][]refusal, prompts map[string][]pending, cleared clears) {
	for _, s := range slices.Sorted(maps.Keys(refused)) {
		if len(prompts[s]) == 0 {
			continue
		}
		p := prompts[s][len(prompts[s])-1]
		rs := refused[s]
		r := rs[len(rs)-1]
		if r.seq < p.seq || cleared.of(s, p.request, p.seq) != nil {
			continue
		}
		key := incidentKey(s, p.request, p.seq)
		if _, ok := led[key]; ok {
			continue
		}
		led[key] = &incident{
			Session: s, Request: p.request, PendingSeq: p.seq, Appeared: p.at,
			Prompt: p.prompt, Seat: r.seat, Escalated: r.at, Alerted: map[string]time.Time{},
		}
	}
}

// deliver sends what each incident owes: its alert to each recipient it has
// not reached while it is open, and once it has cleared, its note to each
// recipient its alert reached. An incident whose every note has gone leaves
// the ledger.
func (a *PromptAlert) deliver(ctx context.Context, led alerts, now time.Time, rec *AlertRecord) []string {
	if len(led) == 0 {
		return nil
	}
	to, failures := a.recipients()
	keys := slices.SortedFunc(maps.Keys(led), func(x, y string) int {
		return cmp.Or(led[x].Appeared.Compare(led[y].Appeared), cmp.Compare(x, y))
	})
	for _, key := range keys {
		inc := led[key]
		if inc.Cleared == nil {
			subject, body := inc.alert(now)
			got, bad := a.sendAll(ctx, to, inc.Alerted, "prompt-alert:"+inc.dedup(), subject, body, now)
			failures = append(failures, bad...)
			if len(got) > 0 {
				rec.Alerted = append(rec.Alerted, Mailed{Session: inc.Session, Request: inc.Request, To: got})
			}
			rec.Waiting = append(rec.Waiting, Waiting{Session: inc.Session, Request: inc.Request, Appeared: inc.Appeared})
			continue
		}
		if inc.Noted == nil {
			inc.Noted = map[string]time.Time{}
		}
		var reached []recipient
		for _, addr := range slices.Sorted(maps.Keys(inc.Alerted)) {
			reached = append(reached, a.recipientFor(addr))
		}
		subject, body := inc.note()
		got, bad := a.sendAll(ctx, reached, inc.Noted, "prompt-cleared:"+inc.dedup(), subject, body, now)
		failures = append(failures, bad...)
		if len(got) > 0 {
			rec.Noted = append(rec.Noted, Mailed{Session: inc.Session, Request: inc.Request, To: got})
		}
		if len(inc.Noted) >= len(inc.Alerted) {
			delete(led, key)
		}
	}
	return failures
}

// sendAll sends one message to each recipient sent does not hold, recording
// in sent each that took it, and answers those addresses and each send that
// failed.
func (a *PromptAlert) sendAll(ctx context.Context, to []recipient, sent map[string]time.Time, dedup, subject, body string, now time.Time) (got, failures []string) {
	for _, r := range to {
		if _, ok := sent[r.address]; ok {
			continue
		}
		send, cancel := context.WithTimeout(ctx, SendBound)
		_, err := a.City.SendMail(send, gascity.MailSend{To: r.address, Subject: subject, Body: body, Dedup: dedup, Notify: r.notify})
		cancel()
		if err != nil {
			failures = append(failures, fmt.Sprintf("%q was not mailed to %s, and the next pass sends it: %v", subject, r.address, err))
			continue
		}
		sent[r.address] = now
		got = append(got, r.address)
	}
	return got, failures
}

// recipients is the escalation recipient, then each named agent by the
// qualified name the city's roster gives it, once each.
func (a *PromptAlert) recipients() ([]recipient, []string) {
	out := []recipient{a.recipientFor(a.Recipient)}
	if len(a.Agents) == 0 {
		return out, nil
	}
	agents, err := a.City.Agents()
	if err != nil {
		return out, []string{fmt.Sprintf("the city's roster did not read, so %s got no copy, and the next pass sends it: %v", strings.Join(a.Agents, ", "), err)}
	}
	var failures []string
	for _, name := range a.Agents {
		var found []string
		for _, ag := range agents {
			if (ag.QualifiedName == name || ag.Name == name) && !slices.Contains(found, ag.QualifiedName) {
				found = append(found, ag.QualifiedName)
			}
		}
		switch {
		case len(found) == 1:
			if !slices.ContainsFunc(out, func(r recipient) bool { return r.address == found[0] }) {
				out = append(out, recipient{address: found[0]})
			}
		case len(found) == 0:
			failures = append(failures, fmt.Sprintf("the city's roster names no agent %s, so it got no copy", name))
		default:
			failures = append(failures, fmt.Sprintf("the city's roster names %d agents %s (%s), so which one gets the copy is not known", len(found), name, strings.Join(found, ", ")))
		}
	}
	return out, failures
}

// recipientFor is how a message to address goes: requesting the turn of the
// escalation recipient when it is not human, and of no one else.
func (a *PromptAlert) recipientFor(address string) recipient {
	return recipient{address: address, notify: address == a.Recipient && address != "human"}
}

// readRefusals is each session's nudge_refused escalations, oldest first.
func readRefusals(events []gascity.Event) (map[string][]refusal, []string) {
	out := map[string][]refusal{}
	var failures []string
	for _, e := range events {
		var p escalationPayload
		if err := json.Unmarshal(e.Payload, &p); err != nil || p.SessionID == "" {
			failures = append(failures, fmt.Sprintf("escalation %d does not name the session it escalates, so it was not judged", e.Seq))
			continue
		}
		if p.Reason != nudgeRefused {
			continue
		}
		out[p.SessionID] = append(out[p.SessionID], refusal{seq: e.Seq, at: e.Ts.UTC(), seat: p.seat})
	}
	for s := range out {
		slices.SortFunc(out[s], func(x, y refusal) int { return cmp.Compare(x.seq, y.seq) })
	}
	return out, failures
}

// readPrompts is each session's prompts, oldest first.
func readPrompts(events []gascity.Event) (map[string][]pending, []string) {
	out := map[string][]pending{}
	var failures []string
	for _, e := range events {
		var p pendingPayload
		if err := json.Unmarshal(e.Payload, &p); err != nil || p.SessionID == "" || p.RequestID == "" {
			failures = append(failures, fmt.Sprintf("prompt %d does not name its session and request, so it was not judged", e.Seq))
			continue
		}
		out[p.SessionID] = append(out[p.SessionID], pending{seq: e.Seq, at: e.Ts.UTC(), request: p.RequestID, prompt: p.prompt})
	}
	for s := range out {
		slices.SortFunc(out[s], func(x, y pending) int { return cmp.Compare(x.seq, y.seq) })
	}
	return out, failures
}

// readClears is each session's cleared prompts, oldest first.
func readClears(events []gascity.Event) (clears, []string) {
	out := clears{}
	var failures []string
	for _, e := range events {
		var p clearedPayload
		if err := json.Unmarshal(e.Payload, &p); err != nil || p.SessionID == "" || p.RequestID == "" {
			failures = append(failures, fmt.Sprintf("clear %d does not name its session and request, so it was not judged", e.Seq))
			continue
		}
		out[p.SessionID] = append(out[p.SessionID], clearedAt{request: p.RequestID, cleared: clearing{Seq: e.Seq, At: e.Ts.UTC(), Reason: p.Reason}})
	}
	for s := range out {
		slices.SortFunc(out[s], func(x, y clearedAt) int { return cmp.Compare(x.cleared.Seq, y.cleared.Seq) })
	}
	return out, failures
}

// alert is the incident's alert: its subject and body at now.
func (inc *incident) alert(now time.Time) (string, string) {
	var b strings.Builder
	fmt.Fprintf(&b, "Session %s%s, %s, has waited %s at a prompt for a person, since %s. Gas City holds back its nudges while the prompt is up, and escalated the seat at %s.\n\n",
		inc.Session, inc.Seat.named(), inc.who(), span(now.Sub(inc.Appeared)), utc(inc.Appeared), utc(inc.Escalated))
	b.WriteString("The prompt, as Gas City recorded it:\n")
	b.WriteString(inc.Prompt.lines())
	fmt.Fprintf(&b, "\nSee it: gc session peek %s\nAnswer it in the session's terminal: gc session attach %s\n\n", inc.Session, inc.Session)
	b.WriteString("This alert is mailed once for this prompt, and a short note follows when it clears. " + sentBy + "\n")
	return "Prompt waiting: session " + inc.Session + inc.Seat.under(), b.String()
}

// note is the incident's note once it has cleared.
func (inc *incident) note() (string, string) {
	kind := inc.Prompt.Kind
	if kind == "" {
		kind = "pending"
	}
	body := fmt.Sprintf("The %s prompt that session %s%s waited at since %s cleared at %s, after %s. %s\n\n%s\n",
		kind, inc.Session, inc.Seat.under(), utc(inc.Appeared), utc(inc.Cleared.At), span(inc.Cleared.At.Sub(inc.Appeared)), how(inc.Cleared.Reason), sentBy)
	return "Prompt cleared: session " + inc.Session + inc.Seat.under(), body
}

// sentBy closes every message, so a reader never takes it for a person's.
const sentBy = "It comes from gc-toolkit's prompt-alert orders (gctk session prompt-alert), not from a person."

// who is the seat's agent, rig and bead, in words.
func (inc *incident) who() string {
	template := cmp.Or(inc.Seat.Template, inc.Prompt.Template)
	var parts []string
	if rig, agent, ok := strings.Cut(template, "/"); ok {
		parts = append(parts, "agent "+agent+" in rig "+rig)
	} else if template != "" {
		parts = append(parts, "city agent "+template)
	}
	if inc.Seat.Bead != "" {
		parts = append(parts, "holding "+inc.Seat.Bead)
	}
	if len(parts) == 0 {
		return "a session Gas City named no agent for"
	}
	return strings.Join(parts, ", ")
}

// how says how a prompt cleared, by the reason Gas City records.
func how(reason string) string {
	switch reason {
	case "resolved":
		return "Gas City records it resolved: it was answered or withdrawn."
	case "session_gone":
		return "Gas City records the session gone: it is no longer active, and the prompt went with it."
	case "replaced":
		return "Gas City records it replaced: the session now waits at a different prompt, which is alerted on its own once Gas City escalates the seat for it."
	}
	return fmt.Sprintf("Gas City records it cleared, with the reason %q.", reason)
}

// span is a duration to the minute, such as 22m or 7h15m.
func span(d time.Duration) string {
	d = d.Round(time.Minute)
	if d < time.Minute {
		return "under a minute"
	}
	h, m := int(d/time.Hour), int(d%time.Hour/time.Minute)
	switch {
	case h == 0:
		return fmt.Sprintf("%dm", m)
	case m == 0:
		return fmt.Sprintf("%dh", h)
	}
	return fmt.Sprintf("%dh%dm", h, m)
}

// utc is a time as the mail gives it, in UTC.
func utc(t time.Time) string { return t.UTC().Format(time.RFC3339) }

// clip is s cut to n characters, saying so when it cut.
func clip(s string, n int) string {
	if utf8.RuneCountInString(s) <= n {
		return s
	}
	return string([]rune(s)[:n]) + fmt.Sprintf("… (cut at %d characters)", n)
}
