package session

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"maps"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"syscall"
	"time"
)

// The alert ledger is AlertLedgerFile in the State directory: each incident
// whose alert or note is still owed, with the addresses each has reached. A
// pass writes it whole once it has mailed, through a file it renames into
// place, so a reader never sees half of one. AlertLockFile is the lock every
// pass holds from before it reads the ledger until after it writes it, so the
// orders' runs, and a run by hand, never mail one prompt twice. The lock is the
// kernel's advisory lock on the file, which the kernel releases when its holder
// ends however it ends, and Go opens the file close-on-exec, so the gc commands
// a pass runs do not carry it.
const (
	AlertLedgerFile = "prompt-alert.json"
	AlertLockFile   = "prompt-alert.lock"
)

// alertLockPoll is how often a pass that finds the lock held tries it again.
const alertLockPoll = 100 * time.Millisecond

// incident is one prompt a seat waits at that Gas City escalated the seat for:
// the session, the prompt's request id and the seq of the session.pending
// that recorded it, since Gas City's request id for a pane's prompt is a hash
// of its text and a later prompt can carry it again. It keeps what the mail
// says, which addresses its alert and its note have reached and when, and the
// prompt's clear once Gas City records it.
type incident struct {
	Session    string               `json:"session"`
	Request    string               `json:"request"`
	PendingSeq int64                `json:"pending_seq"`
	Appeared   time.Time            `json:"appeared"`
	Prompt     prompt               `json:"prompt"`
	Seat       seat                 `json:"seat"`
	Escalated  time.Time            `json:"escalated"`
	Alerted    map[string]time.Time `json:"alerted"`
	Cleared    *clearing            `json:"cleared,omitempty"`
	Noted      map[string]time.Time `json:"noted,omitempty"`
}

// prompt is the prompt as Gas City recorded it in session.pending: its kind,
// approval or question, Gas City's one line of it, the answers it offers, and
// what the provider adds, such as an approval's tool_name, command and
// description, or a question's header.
type prompt struct {
	Template string            `json:"template,omitempty"`
	Kind     string            `json:"kind"`
	Prompt   string            `json:"prompt,omitempty"`
	Options  []string          `json:"options,omitempty"`
	Metadata map[string]string `json:"metadata,omitempty"`
}

// seat is the pool seat as Gas City's escalation names it: its session's
// runtime name, its agent template and the bead it holds.
type seat struct {
	SessionName string `json:"session_name,omitempty"`
	Template    string `json:"template,omitempty"`
	Bead        string `json:"bead_id,omitempty"`
}

// clearing is a prompt's session.pending_cleared: its seq, when, and Gas
// City's reason, resolved, replaced or session_gone.
type clearing struct {
	Seq    int64     `json:"seq"`
	At     time.Time `json:"at"`
	Reason string    `json:"reason"`
}

type alerts map[string]*incident

// incidentKey is the ledger's key for a session's prompt.
func incidentKey(session, request string, seq int64) string {
	return fmt.Sprintf("%s/%s/%d", session, request, seq)
}

// dedup is the key Gas City's mail keeps a second live copy of the
// incident's message out of a mailbox by.
func (inc *incident) dedup() string { return incidentKey(inc.Session, inc.Request, inc.PendingSeq) }

// lines is the prompt in the mail, one fact a line: an approval's tool and
// command, a question and its options, and Gas City's one line of any prompt
// whose command it did not record.
func (p prompt) lines() string {
	var b strings.Builder
	line := func(label, value string) {
		if value != "" {
			fmt.Fprintf(&b, "%s: %s\n", label, value)
		}
	}
	line("Kind", p.Kind)
	switch p.Kind {
	case "approval":
		line("Tool", p.Metadata["tool_name"])
		line("Command", clip(p.Metadata["command"], CommandCap))
		line("Description", p.Metadata["description"])
		if p.Metadata["command"] == "" {
			line("Prompt", p.Prompt)
		}
	case "question":
		line("Header", p.Metadata["header"])
		line("Question", p.Prompt)
		if len(p.Options) > 0 {
			b.WriteString("Options:\n")
			for i, o := range p.Options {
				fmt.Fprintf(&b, "  %d. %s\n", i+1, o)
			}
		}
	default:
		line("Prompt", p.Prompt)
		if len(p.Options) > 0 {
			line("Options", strings.Join(p.Options, ", "))
		}
	}
	return b.String()
}

// named is the seat's runtime name, in parentheses, when Gas City gave one.
func (s seat) named() string {
	if s.SessionName == "" {
		return ""
	}
	return " (" + s.SessionName + ")"
}

// under is the seat's agent template, in parentheses, when Gas City gave one.
func (s seat) under() string {
	if s.Template == "" {
		return ""
	}
	return " (" + s.Template + ")"
}

// readAlerts reads the ledger in dir. A ledger that is not there is empty, and
// one that does not read is an error, since mailing past it would send again
// every alert it records.
func readAlerts(dir string) (alerts, error) {
	path := filepath.Join(dir, AlertLedgerFile)
	raw, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return alerts{}, nil
	}
	if err != nil {
		return nil, fmt.Errorf("the prompt-alert ledger %s did not read: %w", path, err)
	}
	var file struct {
		Incidents alerts `json:"incidents"`
	}
	if err := json.Unmarshal(raw, &file); err != nil || file.Incidents == nil ||
		slices.ContainsFunc(slices.Collect(maps.Values(file.Incidents)), func(inc *incident) bool { return inc == nil || inc.Alerted == nil }) {
		return nil, fmt.Errorf("the prompt-alert ledger %s holds no incidents that read", path)
	}
	return file.Incidents, nil
}

// writeAlerts writes l to dir through a file it renames into place.
func writeAlerts(dir string, l alerts) error {
	path := filepath.Join(dir, AlertLedgerFile)
	raw, err := json.MarshalIndent(struct {
		Incidents alerts `json:"incidents"`
	}{l}, "", "  ")
	if err != nil {
		return fmt.Errorf("the prompt-alert ledger did not encode: %w", err)
	}
	tmp, err := os.CreateTemp(dir, "."+AlertLedgerFile+".*")
	if err != nil {
		return fmt.Errorf("the prompt-alert ledger %s was not written: %w", path, err)
	}
	_, werr := tmp.Write(append(raw, '\n'))
	cerr := tmp.Close()
	if err := errors.Join(werr, cerr); err != nil {
		_ = os.Remove(tmp.Name())
		return fmt.Errorf("the prompt-alert ledger %s was not written: %w", path, err)
	}
	if err := os.Rename(tmp.Name(), path); err != nil {
		_ = os.Remove(tmp.Name())
		return fmt.Errorf("the prompt-alert ledger %s was not written: %w", path, err)
	}
	return nil
}

// lockAlerts takes the passes' lock in dir, waiting while another pass holds
// it, until ctx ends. It returns the release once it holds the lock.
func lockAlerts(ctx context.Context, dir string) (func(), error) {
	if dir == "" {
		return nil, errors.New("no directory for the prompt-alert ledger and its lock was named")
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, fmt.Errorf("the directory of the prompt-alert ledger, %s, could not be made: %w", dir, err)
	}
	path := filepath.Join(dir, AlertLockFile)
	f, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE, 0o644)
	if err != nil {
		return nil, fmt.Errorf("the prompt-alert lock %s could not be opened: %w", path, err)
	}
	fd := int(f.Fd())
	for {
		err = syscall.Flock(fd, syscall.LOCK_EX|syscall.LOCK_NB)
		if err == nil {
			break
		}
		if !errors.Is(err, syscall.EWOULDBLOCK) && !errors.Is(err, syscall.EINTR) {
			_ = f.Close()
			return nil, fmt.Errorf("the prompt-alert lock %s could not be taken: %w", path, err)
		}
		select {
		case <-ctx.Done():
			_ = f.Close()
			return nil, fmt.Errorf("the prompt-alert lock %s stayed held by another pass until this one's deadline", path)
		case <-time.After(alertLockPoll):
		}
	}
	return func() {
		_ = syscall.Flock(fd, syscall.LOCK_UN)
		_ = f.Close()
	}, nil
}
