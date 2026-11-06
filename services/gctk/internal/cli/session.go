package cli

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"unicode"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
)

// `gctk session title` gives a session the title an agent states for it, in
// the two places a title is read. Gas City's session record holds the title
// `gc session list` and the board show, and `gc session rename` writes it and
// nothing else. The agent's own session name is the terminal title Claude Code
// and Codex draw, which tmux carries to an attached client's tab once the
// session has set-titles on. Each agent sets that name only through its own
// /rename command, typed into its input box: Claude Code runs it locally, with
// no model turn, and Codex accepts it with its argument during a turn
// (codex-rs/tui/src/slash_command.rs at openai/codex rust-v0.164.0). So the
// command renames the session in Gas City, then has `gc session nudge` type
// /rename <title> into the session, delivered at once.
//
// The nudge types into whatever the input box holds (nudgeSession in
// internal/runtime/tmux/tmux.go at gastownhall/gascity 9f807760c). With a
// client attached it types onto the text there and submits the two as one
// message, and with none attached it clears the text first. So a /rename that
// lands while a person is typing in the session joins their draft. The command
// does not read the box first, and accepts that case: a session takes its
// title when it starts and when its focus moves, and rarely while a person is
// typing into it.

const sessionUsage = `usage:
  gctk session title --topic <words> [--subject <bead-id>] [--pr <n>]
                     [--session <id-or-alias>]

Gives a session a title and shows it on the session's terminal. The title is
"<subject> #<n> — <topic>", and an item not given is left out of it:
"<subject> — <topic>", "#<n> — <topic>", or the topic alone.

  --topic <words>          what the session is on, in a few words
  --subject <bead-id>      the bead the session is about, which leads the title
  --pr <n>                 the number of the pull request the session is
                           about, which follows the subject as #<n>
  --session <id-or-alias>  the session to title; default the session this runs
                           in ($GC_SESSION_ID)

An empty --subject or --pr is an item not given, so a caller can pass what it
read, which is empty when there is none.

gc session rename sets the title on the session's record, which gc session
list and the board show. For a Claude Code or Codex session, gc session nudge
then types "/rename <title>" into the session's input box at once, and the
agent runs it, so its terminal title shows the title. The nudge does not wait
for the input box to empty. A /rename that lands while a person is typing in
the session joins their draft: with a client attached, Gas City types it onto
the draft and submits the two together, and with none attached, it clears the
box first. The command skips the nudge for another provider. Each line it
prints says what it did: renamed, nudged, queued, or skipped and why.

exit: 0 renamed; the nudge was delivered, queued, or skipped as printed
      1 the rename failed, and nothing else was done
      2 usage
      3 renamed, but the nudge failed
`

// The exit codes sessionUsage states.
const (
	sessionExitDone        = 0
	sessionExitRenameFail  = 1
	sessionExitUsage       = 2
	sessionExitNudgeFailed = 3
)

type titleOpts struct {
	topic, subject, pr, session string
}

// Session dispatches `gctk session <verb>`, returning a process exit code so
// the surface stays testable in-process.
func Session(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		fmt.Fprint(stderr, sessionUsage)
		return sessionExitUsage
	}
	switch args[0] {
	case "-h", "--help", "help":
		fmt.Fprint(stdout, sessionUsage)
		return sessionExitDone
	case "title":
	default:
		fmt.Fprintf(stderr, "gctk session: unknown verb %q\n\n%s", args[0], sessionUsage)
		return sessionExitUsage
	}
	o, msg := parseTitleArgs(args[1:])
	if msg != "" {
		fmt.Fprintf(stderr, "gctk session title: %s\n\n%s", msg, sessionUsage)
		return sessionExitUsage
	}
	return sessionTitle(o, stdout, stderr)
}

// parseTitleArgs reads title's flags, or returns why they do not parse.
func parseTitleArgs(args []string) (titleOpts, string) {
	o := titleOpts{}
	set := map[string]bool{}
	for i := 0; i < len(args); i++ {
		a := args[i]
		switch a {
		case "--topic", "--subject", "--pr", "--session":
		default:
			return o, fmt.Sprintf("unknown argument %q", a)
		}
		if set[a] {
			return o, "flag " + a + " given twice"
		}
		set[a] = true
		if i+1 >= len(args) {
			return o, "flag " + a + " needs a value"
		}
		i++
		v := strings.TrimSpace(args[i])
		switch a {
		case "--topic":
			o.topic = v
		case "--subject":
			o.subject = v
		case "--pr":
			o.pr = v
		case "--session":
			o.session = v
		}
	}
	if o.topic == "" {
		return o, "--topic needs the words the title is made of"
	}
	if strings.Trim(o.pr, "0123456789") != "" {
		return o, fmt.Sprintf("--pr takes the pull request's number, such as 1409, not %q", o.pr)
	}
	// The title is typed into the agent's input box, where a newline sends
	// what came before it as a message of its own.
	for _, v := range []string{o.topic, o.subject} {
		if strings.IndexFunc(v, unicode.IsControl) >= 0 {
			return o, fmt.Sprintf("%q holds a control character, such as a newline, which the typed /rename cannot carry", v)
		}
	}
	if o.session == "" {
		o.session = strings.TrimSpace(os.Getenv("GC_SESSION_ID"))
	}
	if o.session == "" {
		return o, "no --session given, and GC_SESSION_ID names no session to default to"
	}
	return o, ""
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

// sessionTitle renames the session in Gas City, then types /rename into it,
// reporting each step on stdout.
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
		fmt.Fprintf(stdout, "skipped the /rename nudge: %s\n", why)
		return sessionExitDone
	}

	out, errText, code = runSplit("gc", "session", "nudge", id, "--delivery", "immediate", "/rename "+title, "--json")
	if code != 0 {
		fmt.Fprintf(stderr, "gctk session title: the /rename nudge failed: gc session nudge exited %d%s\n", code, detail(errText, out))
		return sessionExitNudgeFailed
	}
	var nudged struct {
		Queued  bool   `json:"queued"`
		Outcome string `json:"outcome"`
	}
	_ = json.Unmarshal([]byte(strings.TrimSpace(out)), &nudged)
	if nudged.Queued {
		fmt.Fprintf(stdout, "queued the /rename nudge: Gas City types it into %s when it can\n", id)
		return sessionExitDone
	}
	outcome := nudged.Outcome
	if outcome == "" {
		outcome = "sent"
	}
	fmt.Fprintf(stdout, "nudged %s: /rename %s\n", id, outcome)
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
		v := strings.TrimPrefix(strings.ToLower(strings.TrimSpace(b.Meta(key))), "builtin:")
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
