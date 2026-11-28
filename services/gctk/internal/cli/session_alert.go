package cli

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strings"
	"time"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/arm"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/session"
)

// gctk session prompt-alert is the prompt-alert orders' verb
// (docs/gctk-architecture.md, "The surface"), through the session package.

const sessionPromptAlertLong = `One pass of the prompt-alert orders, which run it when Gas City escalates a
pool seat (prompt-alert-on-escalation, on work.escalated) and when a session's
prompt clears (prompt-alert-on-clear, on session.pending_cleared). Gas City
holds back a pool seat's nudges while it waits at a prompt for a person, a
permission prompt or a question, and escalates the seat with reason
nudge_refused after its third refused nudge and about hourly after that. The
pass mails each such prompt once, to the escalation recipient and to each agent
--agents names, and once more when it clears.

It reads gc events --type work.escalated --since 2h. When one of them has
reason nudge_refused, or the alert ledger holds a prompt still owed mail, it
reads gc events --type session.pending_cleared with no --since, the newest
page of clears the log holds, so a later pass reads a clear whose own pass
failed. When an escalation has that reason, it reads gc events --type
session.pending --since 24h too. A prompt is
escalated when it is its session's newest, an escalation of that session came
after it, and no clear of it came after it. Its alert goes to each recipient it
has not reached, and once Gas City records its clear, a short note saying how
it cleared goes to each recipient the alert reached. A prompt that clears
before its alert went gets no note.

The escalation recipient is $GC_ESCALATION_RECIPIENT, or human when that is
unset, and its mail requests its turn when it is not human. Each name --agents
gives, an agent's name as its pack gives it or its qualified name, is mailed at
the qualified name gc agent list --json gives it, with no turn requested, so it
reads the mail at its next turn. Every send is gc mail send --json with a
--dedup key of the prompt's, so a send whose ledger write was lost is not sent
twice while its message is live.

The ledger, prompt-alert.json, and the lock every pass holds while it reads and
writes it, prompt-alert.lock, live in the city's .gc/runtime/packs/gc-toolkit.
A ledger or an escalations read that fails mails nothing. A pass ends its reads
and mail at its two-minute deadline.

The pass's record goes to standard output as JSON:

  read     when the pass read
  alerted  each prompt whose alert was mailed: session, request and to
  noted    each prompt whose note was mailed, the same way
  waiting  each escalated prompt that has not cleared: session, request and
           appeared

and a summary line to standard error.

exit: 0 every read answered and every message was mailed
      1 a read, a send or the ledger's write failed; what was not mailed is
        sent by the next pass
      2 usage
      128+N stopped by signal N`

func newSessionPromptAlertCmd(stdout, stderr io.Writer) *cobra.Command {
	var agents string
	cmd := &cobra.Command{
		Use:   "prompt-alert [--agents <names>]",
		Short: "mail the escalation recipient, and each named agent, once when Gas City escalates a pool seat that waits at a prompt, and once when the prompt clears",
		Long:  sessionPromptAlertLong,
		Args:  cobra.NoArgs,
		RunE: func(*cobra.Command, []string) error {
			names := strings.FieldsFunc(agents, func(r rune) bool { return r == ',' || r == ' ' || r == '\t' || r == '\n' })
			recipient := strings.TrimSpace(os.Getenv("GC_ESCALATION_RECIPIENT"))
			if recipient == "" {
				recipient = "human"
			}
			city := gascity.New()
			state, err := arm.LockDir(city)
			if err != nil {
				fmt.Fprintf(stderr, "gctk session prompt-alert: %v\n", err)
				return exit(1)
			}
			a := &session.PromptAlert{City: city, Recipient: recipient, Agents: names, State: state, Now: time.Now}
			ctx, release := stopOnSignal()
			out := a.Run(ctx)
			if sig := release(); sig != 0 {
				return exit(128 + int(sig))
			}
			if out.Record != nil {
				if err := json.NewEncoder(stdout).Encode(out.Record); err != nil {
					fmt.Fprintf(stderr, "gctk session prompt-alert: the record could not be printed: %v\n", err)
				}
				fmt.Fprintf(stderr, "gctk session prompt-alert: %s\n", out.Record.Summary())
			}
			for _, f := range out.Failures {
				fmt.Fprintf(stderr, "gctk session prompt-alert: %s\n", f)
			}
			if len(out.Failures) > 0 {
				return exit(1)
			}
			return nil
		},
	}
	cmd.Flags().StringVar(&agents, "agents", "", "the agents that get a copy of every message, by the name the pack gives each or its qualified name, separated by spaces or commas")
	return cmd
}
