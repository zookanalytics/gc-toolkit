package gascity

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

// Message is one mail message as gc prints it (mail.Message in internal/mail
// at gastownhall/gascity c377651cb318), less its body, which no reader here
// needs.
type Message struct {
	ID        string    `json:"id"`
	From      string    `json:"from"`
	To        string    `json:"to"`
	Subject   string    `json:"subject"`
	CreatedAt time.Time `json:"created_at"`
	Read      bool      `json:"read"`
}

// Inbox is what one `gc mail inbox <session> --json` answered: every address
// the session's mailbox answers to, its alias, its id and its earlier aliases
// among them, and the messages to any of them it has not read
// (doMailInboxTargetWithJSON and jsonRecipients in cmd/gc/cmd_mail.go at
// gastownhall/gascity c377651cb318).
type Inbox struct {
	Addresses []string
	Unread    []Message
}

// MailInbox reads `gc mail inbox <session> --json` once. A read that fails, or
// prints no JSON object carrying a messages list, is an error, never an empty
// inbox.
func (c *City) MailInbox(ctx context.Context, session string) (Inbox, error) {
	b := c.runBounded(ctx, c.bin, "mail", "inbox", session, "--json")
	if f := b.Failure(); f != "" {
		return Inbox{}, fmt.Errorf("gc mail inbox %s did not read: %s", session, f)
	}
	var out struct {
		Recipients []string   `json:"recipients"`
		Messages   *[]Message `json:"messages"`
	}
	if err := json.Unmarshal([]byte(strings.TrimSpace(b.Stdout)), &out); err != nil || out.Messages == nil {
		return Inbox{}, fmt.Errorf("gc mail inbox %s printed no message list that reads: %s", session, clipLine(b.Stdout))
	}
	return Inbox{Addresses: out.Recipients, Unread: *out.Messages}, nil
}

// QueuedNudge is one nudge `gc nudge status` lists for a session: its source,
// "mail" for a mail notice from the nudge queue and "gc:mail" for one the
// session's conversation lane carries, and the bead it is about where the
// queue names one (nudgequeue.Item in internal/nudgequeue/state.go,
// deliverMailNotifyLegacy in cmd/gc/cmd_nudge.go and laneNudgeItem in
// cmd/gc/nudge_lane_status.go, at gastownhall/gascity c377651cb318).
type QueuedNudge struct {
	ID        string `json:"id"`
	Source    string `json:"source"`
	Reference *struct {
		Kind string `json:"kind"`
		ID   string `json:"id"`
	} `json:"reference,omitempty"`
}

// NudgeQueue is what one `gc nudge status <session> --json` answered: the
// nudges still to be delivered to the session, those waiting and those being
// delivered now.
type NudgeQueue struct {
	Pending, InFlight []QueuedNudge
}

// NudgeQueue reads `gc nudge status <session> --json` once. gc exits 1 when it
// cannot read every one of the session's lane operations, and a read that
// fails, or prints no JSON object carrying both lists, is an error, never an
// empty queue.
func (c *City) NudgeQueue(ctx context.Context, session string) (NudgeQueue, error) {
	b := c.runBounded(ctx, c.bin, "nudge", "status", session, "--json")
	if f := b.Failure(); f != "" {
		return NudgeQueue{}, fmt.Errorf("gc nudge status %s did not read: %s", session, f)
	}
	var out struct {
		Pending  *[]QueuedNudge `json:"pending"`
		InFlight *[]QueuedNudge `json:"in_flight"`
	}
	if err := json.Unmarshal([]byte(strings.TrimSpace(b.Stdout)), &out); err != nil || out.Pending == nil || out.InFlight == nil {
		return NudgeQueue{}, fmt.Errorf("gc nudge status %s printed no nudge lists that read: %s", session, clipLine(b.Stdout))
	}
	return NudgeQueue{Pending: *out.Pending, InFlight: *out.InFlight}, nil
}

// NudgeWaitIdle runs one `gc session nudge --delivery wait-idle <session>
// <message>`, ended once ctx ends. The message arrives as a prompt at the
// session's next idle boundary and never inside a running turn. A session
// that is not running gets it queued with a wake requested for it, and a busy
// one gets it queued for that boundary (deliverSessionNudgeLegacy in
// cmd/gc/cmd_nudge.go at gastownhall/gascity c377651cb318). Its exit is the
// outcome: 0 when the nudge was delivered or queued.
func (c *City) NudgeWaitIdle(ctx context.Context, session, message string) Bounded {
	return c.runBounded(ctx, c.bin, "session", "nudge", "--delivery", "wait-idle", session, message)
}
