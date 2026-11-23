package cli

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/arm"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/mail"
)

// gctk mail notify is the mail-notify-on-send and mail-notify-on-reply orders'
// verb (docs/gctk-architecture.md, "The surface"), through the mail package.

func newMailCmd(stdout, stderr io.Writer) *cobra.Command {
	return group("mail", "mail between sessions, and the turn it asks of its recipient",
		`Mail between sessions. Gas City owns every message and its mailbox, and it
requests a recipient's turn only when the sender asks for one.`,
		newMailNotifyCmd(stdout, stderr))
}

const mailNotifyLong = `One pass of the mail-notify-on-send and mail-notify-on-reply orders, which
run it when mail is sent or replied to. Gas City requests a recipient's turn
only when the sender passes --notify, so the pass requests it for every other
mail to the sessions of the agents --agents names.

It reads gc session list --json once, and for each session of a named agent
whose state is active, awake, asleep, creating or start-pending, it reads its
unread mail with gc mail inbox <session> --json. A message is new when its
sender is not one of the session's own addresses, as a handoff's is, and the
notify ledger does not hold it. For a session with new mail it reads gc nudge
status <session> --json, and when a mail notice is still to be delivered there,
which a sender's --notify queues, it leaves the session alone. Otherwise it
sends one gc session nudge --delivery wait-idle <session> "You have mail from
<sender>, ...", naming each new message's sender once, which reaches a running
session at its next idle boundary and wakes one that is asleep. The ledger then
holds each message nudged for while it stays unread. A session that has
finished, or is held from running, keeps its mail waiting.

The ledger, mail-notify.json, and the lock every pass holds while it reads and
writes it, mail-notify.lock, live in the city's .gc/runtime/packs/gc-toolkit. A
session list that does not read, or lists no session, reads no mail and leaves
the ledger as it is. A pass ends its reads and nudges at its two-minute
deadline.

The pass's record goes to standard output as JSON:

  read    when the pass read
  woken   each session nudged: session, agent, messages and from
  told    each session left alone because a mail notice is still queued
  failed  each session whose mail or nudges did not read, or whose nudge did
          not land, and why; its messages are tried again by the next pass

and a summary line to standard error.

exit: 0 every read answered and every nudge landed
      1 a read, a nudge or the ledger's write failed
      2 usage
      128+N stopped by signal N`

func newMailNotifyCmd(stdout, stderr io.Writer) *cobra.Command {
	var agents string
	cmd := &cobra.Command{
		Use:   "notify --agents <names>",
		Short: "request a turn for each named agent's session holding unread mail no notice has told it of",
		Long:  mailNotifyLong,
		Args:  cobra.NoArgs,
		RunE: func(*cobra.Command, []string) error {
			names := strings.FieldsFunc(agents, func(r rune) bool { return r == ',' || r == ' ' || r == '\t' || r == '\n' })
			if len(names) == 0 {
				return errors.New("--agents names no agent")
			}
			city := gascity.New()
			state, err := arm.LockDir(city)
			if err != nil {
				fmt.Fprintf(stderr, "gctk mail notify: %v\n", err)
				return exit(1)
			}
			n := &mail.Notify{City: city, Agents: names, State: state, Now: time.Now}
			ctx, release := stopOnSignal()
			out := n.Run(ctx)
			if sig := release(); sig != 0 {
				return exit(128 + int(sig))
			}
			if out.Record != nil {
				if err := json.NewEncoder(stdout).Encode(out.Record); err != nil {
					fmt.Fprintf(stderr, "gctk mail notify: the record could not be printed: %v\n", err)
				}
				fmt.Fprintf(stderr, "gctk mail notify: %s\n", out.Record.Summary())
			}
			for _, f := range out.Failures {
				fmt.Fprintf(stderr, "gctk mail notify: %s\n", f)
			}
			if len(out.Failures) > 0 {
				return exit(1)
			}
			return nil
		},
	}
	cmd.Flags().StringVar(&agents, "agents", "", "the agents whose sessions the pass reads, by the name the pack gives each or with its binding, separated by spaces or commas")
	_ = cmd.MarkFlagRequired("agents")
	return cmd
}
