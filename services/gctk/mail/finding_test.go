package mail

import (
	"context"
	"errors"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
)

// mailbox is the city a filing reaches: one message, what was done to it, and
// the writer's answer.
type mailbox struct {
	msg     gascity.Message
	peekErr error
	archErr error
	answer  gascity.Result
	calls   [][]string
	done    []string
}

func (m *mailbox) MailPeek(_ context.Context, id string) (gascity.Message, error) {
	m.done = append(m.done, "peek "+id)
	return m.msg, m.peekErr
}

func (m *mailbox) MailArchive(_ context.Context, id string) error {
	m.done = append(m.done, "archive "+id)
	return m.archErr
}

func (m *mailbox) MailMarkUnread(_ context.Context, id string) error {
	m.done = append(m.done, "mark-unread "+id)
	return nil
}

func (m *mailbox) Script(name string, args ...string) gascity.Result {
	m.calls = append(m.calls, append([]string{name}, args...))
	return m.answer
}

var notice = gascity.Message{ID: "hq-m1", From: "tools/gc-toolkit.polecat", Subject: "NOTICE: main fails its pre-flight",
	Body: "The lint leg fails on main.", CreatedAt: time.Date(2026, 11, 27, 12, 0, 0, 0, time.UTC)}

// A notice becomes one finding in the witness's scope, its title the subject
// without its prefix and its text the body with where it came from and the
// witness's note, and the mail is archived only after the finding is filed.
func TestANoticeIsFiledThenArchived(t *testing.T) {
	m := &mailbox{msg: notice}
	out := (&Finding{City: m, Scripts: m}).File(context.Background(), Ask{Mail: "hq-m1", Key: "preflight-main", About: "tk-1", Note: "seen twice", Distinct: true})
	if !out.Filed || !out.Archived || out.Why != "" {
		t.Fatalf("%+v", out)
	}
	if !reflect.DeepEqual(m.done, []string{"peek hq-m1", "archive hq-m1"}) {
		t.Errorf("done %v", m.done)
	}
	want := []string{"patrol-finding.sh", "--scope", "witness-findings", "--key", "preflight-main", "--about", "tk-1", "--distinct",
		"--title", "main fails its pre-flight", "--message",
		"The lint leg fails on main.\n\n## Source\nMail hq-m1 from tools/gc-toolkit.polecat, sent 2026-11-27T12:00:00Z. Subject: NOTICE: main fails its pre-flight\n\n## Witness\nseen twice"}
	if len(m.calls) != 1 || !reflect.DeepEqual(m.calls[0], want) {
		t.Errorf("calls %q", m.calls)
	}
}

// A mail that does not read, a refusal and any other failure file nothing and
// leave the mail unread; a refusal says so, and a finding filed whose mail did
// not archive says that.
func TestAFilingThatFailsLeavesTheMailUnread(t *testing.T) {
	m := &mailbox{peekErr: errors.New("gc mail peek hq-m1 did not read")}
	if out := (&Finding{City: m, Scripts: m}).File(context.Background(), Ask{Mail: "hq-m1", Key: "k"}); out.Filed || len(m.calls) != 0 ||
		!reflect.DeepEqual(m.done, []string{"peek hq-m1", "mark-unread hq-m1"}) {
		t.Errorf("unread mail: %+v, done %v", out, m.done)
	}
	m = &mailbox{msg: notice, answer: gascity.Result{Code: Refused, Output: "patrol-finding: refused; live: tk-9"}}
	out := (&Finding{City: m, Scripts: m}).File(context.Background(), Ask{Mail: "hq-m1", Key: "k"})
	if out.Filed || !out.Refused || !strings.Contains(out.Output, "live: tk-9") || m.done[len(m.done)-1] != "mark-unread hq-m1" {
		t.Errorf("refused: %+v, done %v", out, m.done)
	}
	if got := m.calls[0]; got[6] != "" || got[7] != "--title" {
		t.Errorf("an ask about no bead passes --about empty, and no --distinct: %q", got)
	}
	m = &mailbox{msg: notice, answer: gascity.Result{Code: 1}}
	if out := (&Finding{City: m, Scripts: m}).File(context.Background(), Ask{Mail: "hq-m1", Key: "k"}); out.Filed || out.Refused || m.done[len(m.done)-1] != "mark-unread hq-m1" {
		t.Errorf("failed: %+v, done %v", out, m.done)
	}
	m = &mailbox{msg: notice, archErr: errors.New("gc mail archive hq-m1 failed")}
	if out := (&Finding{City: m, Scripts: m}).File(context.Background(), Ask{Mail: "hq-m1", Key: "k"}); !out.Filed || out.Archived || !strings.Contains(out.Why, "archive") {
		t.Errorf("not archived: %+v", out)
	}
}

// A subject without the prefix is the title whole, and a sender or a time the
// mail lacks reads as unknown.
func TestTheTitleAndTextOfAPlainMail(t *testing.T) {
	msg := gascity.Message{ID: "hq-m2", Subject: "reap the molecule", Body: "please"}
	if got := Title(msg); got != "reap the molecule" {
		t.Errorf("title %q", got)
	}
	if got := Text(msg, ""); got != "please\n\n## Source\nMail hq-m2 from unknown, sent unknown. Subject: reap the molecule" {
		t.Errorf("text %q", got)
	}
}
