package mail

import (
	"cmp"
	"context"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
)

const (
	// FindingScript is the writer of a mail's finding, in the pack's scripts
	// directory.
	FindingScript = "patrol-finding.sh"
	// FindingScope is the scope the witness's findings are filed and
	// deduplicated in.
	FindingScope = "witness-findings"
	// Refused is the writer's exit when a live finding in the scope shares the
	// new one's key or subject, which it lists.
	Refused = 3
	// Notice is the subject prefix a NOTICE mail carries, which the finding's
	// title drops.
	Notice = "NOTICE: "
	// FindingBound bounds a filing's mail reads and writes, from its start.
	FindingBound = 2 * time.Minute
)

// FindingCity is Gas City as a mail's finding reaches it: one message, its
// archive and its read mark, and the pack's scripts.
type FindingCity interface {
	MailPeek(ctx context.Context, id string) (gascity.Message, error)
	MailArchive(ctx context.Context, id string) error
	MailMarkUnread(ctx context.Context, id string) error
	Script(name string, args ...string) gascity.Result
}

// Ask is the finding a mail is filed as: the mail, the key naming the
// situation it reports, the bead it is about when it names one, a note the
// filer adds, and whether it is filed beside a live finding that shares its
// key or subject.
type Ask struct {
	Mail, Key, About, Note string
	Distinct               bool
}

// Filed is what one filing did: whether the finding was filed, whether the
// mail was then archived, whether the writer refused it because a live
// finding shares its key or subject, what the writer printed, and why nothing
// was filed or archived when that is so.
type Filed struct {
	Filed, Archived, Refused bool
	Output                   string
	Why                      string
}

// Finding files one mail as a patrol finding: the record a NOTICE leaves
// before it is archived. It reads the mail without marking it read, files the
// finding through the writer, and archives the mail only once the finding is
// filed. When nothing is filed it marks the mail unread, so the next turn that
// reads the mailbox meets it again.
type Finding struct {
	City FindingCity
}

// File files the mail the ask names.
func (f *Finding) File(ctx context.Context, a Ask) Filed {
	msg, err := f.City.MailPeek(ctx, a.Mail)
	if err != nil {
		return f.unfiled(ctx, a.Mail, Filed{Why: err.Error()})
	}
	msg.ID = cmp.Or(msg.ID, a.Mail)
	args := []string{"--scope", FindingScope, "--key", a.Key, "--about", a.About}
	if a.Distinct {
		args = append(args, "--distinct")
	}
	args = append(args, "--title", Title(msg), "--message", Text(msg, a.Note))
	res := f.City.Script(FindingScript, args...)
	if why := res.Failure(); why != "" {
		return f.unfiled(ctx, a.Mail, Filed{Refused: res.Code == Refused, Output: res.Output, Why: FindingScript + " filed nothing: " + why})
	}
	out := Filed{Filed: true, Output: res.Output}
	if err := f.City.MailArchive(ctx, a.Mail); err != nil {
		out.Why = err.Error()
		return out
	}
	out.Archived = true
	return out
}

// unfiled marks the mail unread again, since reading it to file it may have
// marked it read, and says so when that fails too.
func (f *Finding) unfiled(ctx context.Context, mail string, out Filed) Filed {
	if err := f.City.MailMarkUnread(ctx, mail); err != nil {
		out.Why += "; and the mail was not marked unread: " + err.Error()
	}
	return out
}

// Title is a mail's finding's title: its subject without the NOTICE prefix.
func Title(msg gascity.Message) string {
	return cmp.Or(strings.TrimPrefix(msg.Subject, Notice), msg.Subject)
}

// Text is a mail's finding's text: the mail's body, verbatim, then a Source
// section naming the mail, its sender, when it was sent and its subject, and a
// Witness section holding the note when there is one.
func Text(msg gascity.Message, note string) string {
	sent := "unknown"
	if !msg.CreatedAt.IsZero() {
		sent = msg.CreatedAt.UTC().Format(time.RFC3339)
	}
	text := msg.Body + "\n\n## Source\nMail " + msg.ID + " from " + cmp.Or(msg.From, "unknown") + ", sent " + sent + ". Subject: " + msg.Subject
	if note != "" {
		text += "\n\n## Witness\n" + note
	}
	return text
}
