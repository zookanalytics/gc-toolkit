package cli

import (
	"context"
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

// gctk mail notify is the mail-notify orders' verb, and gctk mail finding the
// witness's record of a NOTICE (docs/gctk-architecture.md, "The surface"),
// through the mail package.

func newMailCmd(stdout, stderr io.Writer) *cobra.Command {
	return group("mail", "mail between sessions, the turn it asks of its recipient, and the finding a notice becomes",
		`Mail between sessions. Gas City owns every message and its mailbox, and it
requests a recipient's turn only when the sender asks for one (mail notify).
A NOTICE the witness reads becomes a patrol finding before it is archived
(mail finding).`,
		newMailNotifyCmd(stdout, stderr), newMailFindingCmd(stdout, stderr))
}

const mailFindingLong = `One mail filed as a patrol finding, the record a NOTICE leaves before the
witness archives it. It reads the mail with gc mail peek <mail> --json, which
leaves it unread, and files the finding through the pack's patrol-finding.sh,
in the directory GCTK_SCRIPTS_DIR names, in the witness-findings scope, under
--key and about the bead --about names. The finding's title is the mail's
subject without its NOTICE: prefix, and its text is the mail's body, verbatim,
then a Source section naming the mail, its sender, when it was sent and its
subject, then a Witness section holding --note when one is given.

Once the finding is filed it archives the mail. When nothing is filed it marks
the mail unread, so the next turn that reads the mailbox meets it again.

patrol-finding.sh refuses a new finding that shares its key or its subject
with a live finding in the scope, and lists those findings. When the mail
reports one of their situations, run again with that finding's --key and
--about, and the mail lands on it as an occurrence. When it reports another,
run again with --distinct.

exit: 0 filed, and the mail archived, or a line saying it was not
      1 nothing filed: the mail did not read, or the writer filed nothing
      2 usage
      3 refused: a live finding shares the key or the subject, listed above`

// mailFindingBound bounds one mail finding's reads and writes, from its start.
var mailFindingBound = mail.FindingBound

func newMailFindingCmd(stdout, stderr io.Writer) *cobra.Command {
	var a mail.Ask
	cmd := &cobra.Command{
		Use:   "finding <mail> --key <key>",
		Short: "file one mail as a patrol finding, and archive it once the finding is filed",
		Long:  mailFindingLong,
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			if a.Key == "" {
				fmt.Fprintln(stderr, "gctk mail finding: --key names the situation the mail reports, and is required")
				return exit(2)
			}
			a.Mail = args[0]
			ctx, cancel := context.WithTimeout(cmd.Context(), mailFindingBound)
			defer cancel()
			city := gascity.New()
			out := (&mail.Finding{City: city, Scripts: city.Within(ctx)}).File(ctx, a)
			if o := strings.TrimRight(out.Output, "\n"); o != "" {
				fmt.Fprintln(stdout, o)
			}
			switch {
			case out.Archived:
				fmt.Fprintf(stderr, "gctk mail finding: filed mail %s under %s and archived it\n", a.Mail, a.Key)
				return nil
			case out.Filed:
				fmt.Fprintf(stderr, "gctk mail finding: filed mail %s under %s, but it was not archived, so the next read files it again as an occurrence: %s\n", a.Mail, a.Key, out.Why)
				return nil
			case out.Refused:
				fmt.Fprintf(stderr, "gctk mail finding: nothing filed for mail %s, which stays unread: a live finding listed above shares the key or the subject. Run again with its --key and --about when the mail reports its situation, or with --distinct when it reports another (%s)\n", a.Mail, out.Why)
				return exit(mail.Refused)
			}
			fmt.Fprintf(stderr, "gctk mail finding: nothing filed for mail %s, which stays unread: %s\n", a.Mail, out.Why)
			return exit(1)
		},
	}
	cmd.Flags().StringVar(&a.Key, "key", "", "the situation the mail reports, the way every finding key names one")
	cmd.Flags().StringVar(&a.About, "about", "", "the bead the mail concerns, when it names one")
	cmd.Flags().StringVar(&a.Note, "note", "", "what you know that the sender did not, added under Witness")
	cmd.Flags().BoolVar(&a.Distinct, "distinct", false, "file it beside a live finding that shares its key or subject")
	return cmd
}

const mailNotifyLong = `One pass of the mail-notify orders, which run it when mail is sent
(mail-notify-on-send) or replied to (mail-notify-on-reply), and on a cadence
(mail-notify-reconcile) for mail whose event's run failed or never came.
Gas City requests a recipient's turn only when the sender passes --notify, so
the pass requests it for every other mail to the sessions of the agents
--agents names.

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
