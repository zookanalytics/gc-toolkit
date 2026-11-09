package cli

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"unicode"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
)

// `gctk session title` gives a session the title an agent states for it, in
// the two places a title is read. Gas City's session record holds the title
// `gc session list` and the board show, and `gc session rename` writes it and
// nothing else. The agent's own session name is the terminal title Claude Code
// and Codex draw, which tmux carries to an attached client's tab once the
// session has set-titles on. Each agent sets that name only through its own
// /rename command, typed into its input box, which it runs locally with no
// model turn. So the command renames the session in Gas City, then has Gas City
// type /rename <title> into the session.
//
// It does that with `gc session submit --intent follow_up`, for either agent.
// Citations are to gastownhall/gascity 9f807760c.
//
// On a running session that queues the text, and the queue types a queued submit
// verbatim and alone (nextQueuedDeliveryGroup and isQueuedUserSubmit in
// cmd/gc/cmd_nudge.go) once the pane has been quiet for three seconds
// (defaultNudgePollQuiescence). So a session takes its title at its next
// boundary, a few seconds after the turn that ran the command ends. A nudge does
// not serve both agents: the queue delivers one as a reminder
// (formatNudgeInjectOutput in cmd/gc/cmd_nudge.go), which runs no command, and
// Gas City queues a nudge to a Codex session running a turn, because Codex's
// submit keys lead with Escape and Escape cancels the turn
// (refuseInterruptingSubmitWhileBusy in internal/runtime/tmux/tmux.go).
//
// On a session suspended or not running, the submit acts as the operator: it
// resumes the session, which lifts an operator's hold on it, and types at once
// (Manager.submit in internal/session/submit.go). Gas City reports that as
// submitted. A Claude Code session resumed this way took the title in each run
// tried, on 2.1.319. A Codex session lost the text in each run tried, on
// codex-cli 0.164.0, so its terminal keeps its old title.
//
// The typing goes into whatever the input box holds (nudgeSession in
// internal/runtime/tmux/tmux.go). With a client attached it types onto the text
// there and submits the two as one message, which goes to the model, so the
// title does not reach the terminal. With none attached it clears the text first.
// So a /rename that lands while a person is typing in the session joins their
// draft, and it lands just after a turn ends, when a person may be writing a
// reply. A /rename also starts no turn, and the session's poller confirms a
// submit by seeing a turn start, so on Claude Code, whose plain Enter it re-sends
// with no look at the box (submitAndConfirm in internal/runtime/tmux/tmux.go), it
// presses Enter again over the next two seconds and can send what a person typed
// in that time. Text it finds in the box just after that reads as a submit that
// did not take, so the queue types the /rename again about 15 seconds later
// (defaultQueuedNudgeRetryDelay in cmd/gc/cmd_nudge.go), onto that text. The
// command cannot read the box at the moment of delivery, and accepts these cases.

// sessionTitleLong is title's help.
const sessionTitleLong = `Gives a session a title and shows it on the session's terminal. The title is
"<subject> #<n> — <topic>", and an item not given is left out of it:
"<subject> — <topic>", "#<n> — <topic>", or the topic alone.

An empty --subject or --pr is an item not given, so a caller can pass what it
read, which is empty when there is none.

gc session rename sets the title on the session's record, which gc session
list and the board show. For a Claude Code or Codex session, gc session submit
--intent follow_up then has Gas City type "/rename <title>" into the session's
input box, and the agent runs it with no model turn, so its terminal title shows
the title. The command skips this for another provider. Each line it prints says
what it did: renamed, queued, submitted, or skipped and why.

On a running session the submit queues, and the terminal takes the title at the
session's next boundary, a few seconds after the turn running now ends. So a
session titling itself shows the title only after the turn that ran this
command.

On a session suspended or not running, Gas City treats the submit as the
operator's own send: it resumes the session and lifts an operator's hold on it.
So --session on a held session releases the hold and restarts the session, and
Gas City reports that as submitted. A Claude Code session resumed this way took
the title in each run tried. A Codex session lost the text in each run tried on
codex-cli 0.164.0, so its terminal title stays as it was.

Gas City does not wait for the input box to empty, and a /rename lands just
after a turn ends, when a person may be writing a reply. One that lands while a
person is typing in the session joins their draft: with a client attached, Gas
City types it onto the draft and submits the two together as one message to the
model, and the terminal title stays as it was. With none attached, it clears the
box first. Steady typing holds the /rename back, and a pause of about three
seconds lets it land. On a Claude Code session, Gas City can press Enter again
over the two seconds after the /rename runs, which sends what a person has typed
by then to the model. Text it finds in the box just after that has it type the
/rename again, onto that text, about 15 seconds later.

exit: 0 renamed; the /rename was queued, submitted, or skipped as printed
      1 the rename failed, and nothing else was done
      2 usage
      3 renamed, but the gc session submit that sends the /rename failed`

// The exit codes sessionTitleLong states.
const (
	sessionExitDone         = 0
	sessionExitRenameFail   = 1
	sessionExitUsage        = 2
	sessionExitSubmitFailed = 3
)

type titleOpts struct {
	topic, subject, pr, session string
}

func newSessionCmd(stdout, stderr io.Writer) *cobra.Command {
	o := titleOpts{}
	title := &cobra.Command{
		Use:   "title",
		Short: "give a session a title its record and its terminal show",
		Long:  sessionTitleLong,
		Args:  cobra.NoArgs,
		RunE: func(*cobra.Command, []string) error {
			if msg := checkTitleOpts(&o); msg != "" {
				return errors.New(msg)
			}
			return exit(sessionTitle(o, stdout, stderr))
		},
	}
	f := title.Flags()
	f.StringVar(&o.topic, "topic", "", "what the session is on, in a few `words`")
	f.StringVar(&o.subject, "subject", "", "the `bead` the session is about, which leads the title")
	f.StringVar(&o.pr, "pr", "", "the `number` of the pull request the session is about, which follows the subject as #<n>")
	f.StringVar(&o.session, "session", "", "the session to title, by `id-or-alias`; default the session this runs in ($GC_SESSION_ID)")
	return group("session", "actions on a session",
		"Actions on a session: give it a title its record and its terminal show.", title)
}

// checkTitleOpts trims title's flags and fills the default session, or says
// why they do not go together.
func checkTitleOpts(o *titleOpts) string {
	o.topic, o.subject = strings.TrimSpace(o.topic), strings.TrimSpace(o.subject)
	o.pr, o.session = strings.TrimSpace(o.pr), strings.TrimSpace(o.session)
	if o.topic == "" {
		return "--topic needs the words the title is made of"
	}
	if strings.Trim(o.pr, "0123456789") != "" {
		return fmt.Sprintf("--pr takes the pull request's number, such as 1409, not %q", o.pr)
	}
	// The title is typed into the agent's input box, where a newline sends
	// what came before it as a message of its own.
	for _, v := range []string{o.topic, o.subject} {
		if strings.IndexFunc(v, unicode.IsControl) >= 0 {
			return fmt.Sprintf("%q holds a control character, such as a newline, which the typed /rename cannot carry", v)
		}
	}
	if o.session == "" {
		o.session = strings.TrimSpace(os.Getenv("GC_SESSION_ID"))
	}
	if o.session == "" {
		return "no --session given, and GC_SESSION_ID names no session to default to"
	}
	return ""
}

// titleText is the title the options make: the subject, its pull request as
// #<n>, and a dash before the topic, with an item not given left out.
func titleText(o titleOpts) string {
	var lead []string
	if o.subject != "" {
		lead = append(lead, o.subject)
	}
	if o.pr != "" {
		lead = append(lead, "#"+o.pr)
	}
	if len(lead) == 0 {
		return o.topic
	}
	return strings.Join(append(lead, "—", o.topic), " ")
}

// sessionTitle renames the session in Gas City, then has Gas City type /rename
// into it, reporting each step on stdout.
func sessionTitle(o titleOpts, stdout, stderr io.Writer) int {
	title := titleText(o)

	out, errText, code := runSplit("gc", "session", "rename", o.session, title, "--json")
	if code != 0 {
		fmt.Fprintf(stderr, "gctk session title: gc session rename %s failed (exit %d)%s\n", o.session, code, detail(errText, out))
		return sessionExitRenameFail
	}
	id := o.session
	var renamed struct {
		SessionID string `json:"session_id"`
	}
	if json.Unmarshal([]byte(strings.TrimSpace(out)), &renamed) == nil && renamed.SessionID != "" {
		id = renamed.SessionID
	}
	fmt.Fprintf(stdout, "renamed %s to %q\n", id, title)

	if why := renameSkip(id); why != "" {
		fmt.Fprintf(stdout, "skipped the /rename: %s\n", why)
		return sessionExitDone
	}

	out, errText, code = runSplit("gc", "session", "submit", id, "--intent", "follow_up", "/rename "+title, "--json")
	if code != 0 {
		fmt.Fprintf(stderr, "gctk session title: the /rename submit failed: gc session submit exited %d%s\n", code, detail(errText, out))
		return sessionExitSubmitFailed
	}
	var sent struct {
		Queued  bool   `json:"queued"`
		Outcome string `json:"outcome"`
	}
	_ = json.Unmarshal([]byte(strings.TrimSpace(out)), &sent)
	switch {
	case sent.Queued:
		fmt.Fprintf(stdout, "queued the /rename submit: Gas City types it into %s at the session's next boundary\n", id)
	case sent.Outcome == "submitted":
		fmt.Fprintf(stdout, "submitted /rename to %s: Gas City resumed the session for it, lifting any operator hold, and a Codex session resumed this way has lost the text in each run tried, so check its terminal title\n", id)
	default:
		// Another outcome, such as the "accepted" gc reports when its fallback
		// finds the API took the message (emitSessionSubmitAccepted in
		// cmd/gc/cmd_session.go at gastownhall/gascity 9f807760c), does not
		// say whether the session was resumed.
		fmt.Fprintf(stdout, "submitted /rename to %s: gc session submit answered %q, not queued, so check its terminal title\n", id, sent.Outcome)
	}
	return sessionExitDone
}

// renameSkip says why session id takes no typed /rename, or "" when it runs an
// agent whose /rename gctk knows.
func renameSkip(id string) string {
	b := gcbd.New().Show(id)
	if b == nil {
		return fmt.Sprintf("session %s could not be read, so its provider is unknown", id)
	}
	switch family := providerFamily(b); family {
	case "claude", "codex":
		return ""
	case "":
		return fmt.Sprintf("session %s records no provider", id)
	default:
		return fmt.Sprintf("provider %s has no /rename command gctk knows", family)
	}
}

// providerFamily is the provider family Gas City resolves for a session bead
// (ProviderFamilyFromMetadata in internal/session/submit.go at
// gastownhall/gascity 9f807760c): the builtin its provider derives from, else
// its recorded kind, else its provider's name. A name is read as
// sessionlog.ProviderFamily reads it for the two families this command types
// into: any name holding "codex" is codex, and "claude" is claude.
func providerFamily(b *gcbd.Bead) string {
	for _, key := range []string{"builtin_ancestor", "provider_kind", "provider"} {
		v := strings.ToLower(strings.TrimSpace(b.Meta(key)))
		if v == "" {
			continue
		}
		if strings.Contains(v, "codex") {
			return "codex"
		}
		return v
	}
	return ""
}

// runSplit runs a command and returns its stdout, its stderr and its exit
// code.
func runSplit(bin string, args ...string) (stdout, stderr string, code int) {
	cmd := exec.Command(bin, args...)
	var o, e bytes.Buffer
	cmd.Stdout = &o
	cmd.Stderr = &e
	err := cmd.Run()
	return o.String(), e.String(), gcbd.ExitCode(err)
}

// detail is ": <first non-empty of texts>", one line, or nothing.
func detail(texts ...string) string {
	for _, t := range texts {
		if t = strings.Join(strings.Fields(t), " "); t != "" {
			return ": " + t
		}
	}
	return ""
}
