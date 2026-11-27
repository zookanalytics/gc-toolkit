package gascity

import (
	"context"
	"strings"
	"testing"
	"time"
)

// The inbox read takes the session's addresses and its unread messages from gc
// mail inbox --json, in the shape gc prints them.
func TestMailInboxReadsTheAddressesAndTheUnreadMail(t *testing.T) {
	c, log := stubGC(t, `printf '%s\n' '{"schema_version":"1","recipient":"tools/gc-toolkit.tk-1","recipients":["tools/gc-toolkit.tk-1","hq-1"],"messages":[{"id":"hq-m1","from":"human","to":"tools/gc-toolkit.tk-1","subject":"a question","body":"…","created_at":"2026-11-23T01:01:05Z","read":false,"thread_id":"t1"}]}'
`)
	got, err := c.MailInbox(context.Background(), "hq-1")
	if err != nil {
		t.Fatal(err)
	}
	if strings.Join(got.Addresses, " ") != "tools/gc-toolkit.tk-1 hq-1" {
		t.Errorf("addresses %q", got.Addresses)
	}
	if len(got.Unread) != 1 {
		t.Fatalf("unread %+v", got.Unread)
	}
	m := got.Unread[0]
	if m.ID != "hq-m1" || m.From != "human" || m.To != "tools/gc-toolkit.tk-1" || m.Subject != "a question" || m.Read ||
		!m.CreatedAt.Equal(time.Date(2026, 11, 23, 1, 1, 5, 0, time.UTC)) {
		t.Errorf("message %+v", m)
	}
	if strings.Join(log(), " ") != "mail inbox hq-1 --json" {
		t.Errorf("gc ran with %q", log())
	}
}

// An inbox that reads with no messages is empty, whether gc prints them as an
// empty list or, as it does for a session's inbox with no unread mail, as
// null. A read that fails, or prints no messages key or one that holds no
// list, is an error.
func TestMailInboxFailsClosed(t *testing.T) {
	for _, messages := range []string{"[]", "null"} {
		c, _ := stubGC(t, `printf '%s\n' '{"schema_version":"1","recipient":"tools/gc-toolkit.tk-1","recipients":["tools/gc-toolkit.tk-1","hq-1"],"messages":`+messages+`}'`)
		if got, err := c.MailInbox(context.Background(), "hq-1"); err != nil || len(got.Unread) != 0 || len(got.Addresses) != 2 {
			t.Errorf("an empty inbox printed as %s answered %+v, %v", messages, got, err)
		}
	}
	for _, body := range []string{
		"echo 'gc mail inbox: no such session' >&2\nexit 1\n",
		"printf '%s\\n' '{\"schema_version\":\"1\",\"recipients\":[]}'\n",
		"printf '%s\\n' '{\"schema_version\":\"1\",\"recipients\":[],\"messages\":\"none\"}'\n",
		"printf 'not json\\n'\n",
	} {
		c, _ := stubGC(t, body)
		if got, err := c.MailInbox(context.Background(), "hq-1"); err == nil {
			t.Errorf("%q answered %+v and no error", body, got)
		}
	}
}

// The queue read keeps the pending and in-flight nudges, each with its source
// and the bead the queue says it is about, and leaves the dead ones out.
func TestNudgeQueueReadsWhatIsStillToBeDelivered(t *testing.T) {
	c, log := stubGC(t, `printf '%s\n' '{"schema_version":"1","command":"nudge status","agent":"tools/gc-toolkit.tk-1","session":"s-hq-1","session_id":"hq-1","counts":{"pending":1,"in_flight":1,"dead":1},"pending":[{"id":"n1","source":"mail","message":"You have mail from human","reference":{"kind":"mail","id":"hq-m1"}}],"in_flight":[{"id":"op-2","source":"gc:mail","message":"You have mail from human"}],"dead":[{"id":"n0","source":"session","message":"old"}]}'
`)
	got, err := c.NudgeQueue(context.Background(), "hq-1")
	if err != nil {
		t.Fatal(err)
	}
	if len(got.Pending) != 1 || got.Pending[0].Source != "mail" || got.Pending[0].Reference == nil || got.Pending[0].Reference.ID != "hq-m1" {
		t.Errorf("pending %+v", got.Pending)
	}
	if len(got.InFlight) != 1 || got.InFlight[0].Source != "gc:mail" || got.InFlight[0].Reference != nil {
		t.Errorf("in flight %+v", got.InFlight)
	}
	if strings.Join(log(), " ") != "nudge status hq-1 --json" {
		t.Errorf("gc ran with %q", log())
	}
}

// A queue read that fails, as gc's is when it cannot read every lane
// operation, or that prints either list missing, is an error, never an empty
// queue.
func TestNudgeQueueFailsClosed(t *testing.T) {
	for _, body := range []string{
		"echo 'gc nudge status: conversation-lane ops not all read: x' >&2\nprintf '%s\\n' '{\"schema_version\":\"1\",\"pending\":[],\"in_flight\":[]}'\nexit 1\n",
		"printf '%s\\n' '{\"schema_version\":\"1\",\"pending\":[]}'\n",
		"printf '%s\\n' '{\"schema_version\":\"1\",\"in_flight\":[]}'\n",
		"printf 'not json\\n'\n",
	} {
		c, _ := stubGC(t, body)
		if got, err := c.NudgeQueue(context.Background(), "hq-1"); err == nil {
			t.Errorf("%q answered %+v and no error", body, got)
		}
	}
}

// The nudge names its delivery, so it lands at an idle boundary whatever gc's
// default becomes, and its exit is the outcome.
func TestNudgeWaitIdleNamesItsDelivery(t *testing.T) {
	c, log := stubGC(t, "exit 0\n")
	if b := c.NudgeWaitIdle(context.Background(), "hq-1", "You have mail from human"); b.Failure() != "" {
		t.Fatalf("the nudge failed: %s", b.Failure())
	}
	if got := strings.Join(log(), "|"); got != "session|nudge|--delivery|wait-idle|hq-1|You have mail from human" {
		t.Errorf("gc ran with %q", got)
	}
	c, _ = stubGC(t, "echo 'gc session nudge: no such session' >&2\nexit 1\n")
	if b := c.NudgeWaitIdle(context.Background(), "hq-1", "x"); b.Failure() == "" {
		t.Error("a nudge that exited 1 reads as delivered")
	}
}
