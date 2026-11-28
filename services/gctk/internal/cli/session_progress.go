package cli

import (
	"io"
	"time"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/session"
)

// gctk session progress is the seat-progress-detect order's verb
// (docs/gctk-architecture.md, "The surface"), through the session package.

const sessionProgressLong = `The seat-progress look, which the seat-progress-detect order runs every 30
minutes. It reads gc session list --json once, then the in-progress claims in
the HQ and each rig gc rig list --json lists that is not suspended, and records
one Gas City event, gc-toolkit.seat-progress.stalled, when it finds a pool seat
whose pane prints while it has written nothing for three hours, the one shape
Gas City's work ladder takes no step on. It writes no bead and ends no session.

A claim is judged when it is in progress, its gc.session_id names a listed
session, and it is assigned to the identity that session's writes carry: its
alias when it has one, and otherwise its session id. Its seat is judged when
its session bead, in the city's store, carries pool_managed=true and its pane
printed within the last 90 seconds. The seat has stalled when three hours or
more have passed since the latest of its newest write as that identity, to the
claim's store or the city's, its last wake (last_woke_at on its session bead,
or when the session was created when that is absent), and the last time Gas
City recorded its quiet stretch ending: a prompt it waited at answered
(session.pending_cleared) or its work ladder reaching it for a quiet pane
(work.nudged). A seat that prints after a quiet stretch has been busy only
since then.

A session list that does not read, or lists no session, judges nothing, and so
does a rig list that names no HQ, whose store holds the session beads. The
event's payload holds:

  read     when the look read
  stalled  each seat found: rig, bead, session, identity, agent, since, and
           from, which names what since is: write, wake, prompt or nudge
  unread   each rig or claim whose read failed, and why, when one did

With --act, which the seat-progress-report order passes when the look's event
fires, it reads the same way, records no event, and files the patrol finding
no-progress.<session> about each stalled seat's claim, in the claim's rig,
through the pack's patrol-finding.sh in the directory GCTK_SCRIPTS_DIR names.
While a finding is open under the key, the writer files no second one, and a
later run counts one more occurrence on it.

` + lookHelpEnd + "\n\n" + actHelpEnd

func newSessionProgressCmd(stdout, stderr io.Writer) *cobra.Command {
	var act bool
	cmd := &cobra.Command{
		Use:   "progress",
		Short: "find each pool seat that prints but has written nothing for three hours, and record them as one gc-toolkit.seat-progress.stalled event",
		Long:  sessionProgressLong,
		Args:  cobra.NoArgs,
		RunE: func(*cobra.Command, []string) error {
			city := gascity.New()
			p := &session.Progress{City: city, Open: ledger.OpenStore, Now: time.Now}
			ctx, release := stopOnSignal()
			if act {
				acted := (&session.Report{Look: p, Scripts: city.Within(ctx)}).Run(ctx)
				if sig := release(); sig != 0 {
					return exit(128 + int(sig))
				}
				outputs := make([]string, len(acted.Filed))
				for i, f := range acted.Filed {
					outputs[i] = f.Output
				}
				return reportAct("session progress", acted, len(acted.Filed), outputs, acted.Failures, stdout, stderr)
			}
			out := p.Run(ctx)
			if sig := release(); sig != 0 {
				return exit(128 + int(sig))
			}
			if out.Record == nil {
				return reportLook("session progress", nil, "", false, false, out.Failures, stdout, stderr)
			}
			return reportLook("session progress", out.Record, out.Record.Summary(), len(out.Record.Stalled) > 0, out.Recorded, out.Failures, stdout, stderr)
		},
	}
	cmd.Flags().BoolVar(&act, "act", false, "file the no-progress finding for each stalled seat, and record no event")
	return cmd
}
