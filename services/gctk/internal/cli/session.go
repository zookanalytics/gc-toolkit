package cli

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"time"
	"unicode"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/composer"
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
// The typing is kept off a message a person is writing. Gas City's nudge
// types whatever the input box holds: with a client attached it types onto the
// text and submits the two as one message, and with none attached it clears
// the text first (nudgeSession in internal/runtime/tmux/tmux.go at
// gastownhall/gascity 9f807760c). So the command reads the box first, and
// nudges only once a read finds it empty (internal/composer). The read and the
// nudge's paste are two steps, so a key a person presses between them still
// meets the nudge; only a nudge mode that refuses a box holding text would
// close that gap. The command reads the agent's pane through the tmux server
// it runs under, the one $TMUX names, because no gc command returns the text
// attributes that tell a placeholder from a draft.

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
then types "/rename <title>" into the session's input box, delivered at once,
and the agent runs it, so its terminal title shows the title. The nudge is
typed only once a read of the input box finds it empty. While the box holds
text, such as a message a person is writing, the command waits up to 3s for it
to empty, then skips the nudge. It also skips the nudge for another provider,
and for a session whose pane it cannot read through the tmux server $TMUX
names. Each line it prints says what it did: renamed, nudged, or skipped and
why.

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

// titleDraftWait bounds the wait for an input box that holds text to empty,
// and titleDraftPoll is the pause between two reads of it. A person about to
// send a message sends it within a few seconds; one still writing keeps the
// box full past them, and the title can wait for the next rename.
var (
	titleDraftWait = 3 * time.Second
	titleDraftPoll = 250 * time.Millisecond
)

// agentPaneFormat marks each pane of a session the way Gas City's tmux runtime
// does (TmuxAgentPaneMarkerFormat in internal/runtime/tmux_agent_pane.go at
// gastownhall/gascity 9f807760c): "agent" for the pane the agent runs in,
// "orphan" for a session whose agent pane is gone, and "pane" for any other.
const agentPaneFormat = "#{?#{==:#{@gc_agent},#{session_id}},agent,#{?#{@gc_agent_session},orphan,pane}}\t#{pane_id}"

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

	pane, why := titlePane(id)
	if why != "" {
		fmt.Fprintf(stdout, "skipped the /rename nudge: %s\n", why)
		return sessionExitDone
	}
	if why := awaitEmptyInput(pane); why != "" {
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
		fmt.Fprintf(stdout, "queued the /rename nudge: Gas City types it into %s when it can, after this command read the input box\n", id)
		return sessionExitDone
	}
	outcome := nudged.Outcome
	if outcome == "" {
		outcome = "sent"
	}
	fmt.Fprintf(stdout, "nudged %s: /rename %s\n", id, outcome)
	return sessionExitDone
}

// titlePane finds the tmux pane whose input box takes the /rename: the agent
// pane of session id, on the tmux server $TMUX names. why says why there is
// none to type into.
func titlePane(id string) (pane tmuxPane, why string) {
	b := gcbd.New().Show(id)
	if b == nil {
		return pane, fmt.Sprintf("session %s could not be read, so its provider is unknown", id)
	}
	switch family := providerFamily(b); family {
	case "claude", "codex":
	case "":
		return pane, fmt.Sprintf("session %s records no provider", id)
	default:
		return pane, fmt.Sprintf("provider %s has no /rename command gctk knows", family)
	}
	name := b.Meta("session_name")
	if name == "" {
		return pane, fmt.Sprintf("session %s records no runtime session name", id)
	}
	socket, _, _ := strings.Cut(os.Getenv("TMUX"), ",")
	if socket == "" {
		return pane, "this command does not run under tmux ($TMUX is unset), so the input box cannot be read"
	}
	pane.socket = socket
	out, errText, code := runSplit("tmux", "-S", socket, "list-panes", "-s", "-t", "="+name+":", "-F", agentPaneFormat)
	if code != 0 {
		return pane, fmt.Sprintf("tmux session %s is not on the tmux server at %s%s", name, socket, detail(errText, ""))
	}
	var marked, all []string
	orphan := false
	for _, row := range strings.Split(strings.TrimSpace(out), "\n") {
		mark, paneID, ok := strings.Cut(row, "\t")
		if !ok {
			continue
		}
		all = append(all, paneID)
		switch mark {
		case "agent":
			marked = append(marked, paneID)
		case "orphan":
			orphan = true
		}
	}
	switch {
	case len(marked) == 1:
		pane.id = marked[0]
	case len(marked) == 0 && !orphan && len(all) == 1:
		pane.id = all[0]
	default:
		return pane, fmt.Sprintf("tmux session %s has no one pane that is the agent's", name)
	}
	return pane, ""
}

// tmuxPane names one pane on one tmux server.
type tmuxPane struct {
	socket, id string
}

// awaitEmptyInput reads the pane's input box until it is empty, for up to
// titleDraftWait, and says why it gave up when it does.
func awaitEmptyInput(p tmuxPane) string {
	deadline := time.Now().Add(titleDraftWait)
	for {
		args := append([]string{"-S", p.socket, "capture-pane", "-t", p.id}, composer.CaptureArgs...)
		out, errText, code := runSplit("tmux", args...)
		if code != 0 {
			return "the input box could not be read" + detail(errText, "")
		}
		state := composer.Read(out)
		if state == composer.Empty {
			return ""
		}
		if !time.Now().Add(titleDraftPoll).Before(deadline) {
			if state == composer.Holding {
				return fmt.Sprintf("the input box still held text after %s, such as a message being written", titleDraftWait)
			}
			return fmt.Sprintf("no input box was on screen after %s, such as while a dialog is open", titleDraftWait)
		}
		time.Sleep(titleDraftPoll)
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
