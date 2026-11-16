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
printed within the last 90 seconds. The seat has stalled when its newest write
as that identity, to the claim's store or the city's, is three hours old or
more, counted from no earlier than the seat's last wake: last_woke_at on its
session bead, or when the session was created when that is absent.

A session list that does not read, or lists no session, judges nothing, and so
does a rig list that names no HQ, whose store holds the session beads. The
event's payload holds:

  read     when the look read
  stalled  each seat found: rig, bead, session, identity, agent, and since,
           its newest write when wrote is true, else when it woke
  unread   each rig or claim whose read failed, and why, when one did

` + lookHelpEnd

func newSessionProgressCmd(stdout, stderr io.Writer) *cobra.Command {
	return &cobra.Command{
		Use:   "progress",
		Short: "find each pool seat that prints but has written nothing for three hours, and record them as one gc-toolkit.seat-progress.stalled event",
		Long:  sessionProgressLong,
		Args:  cobra.NoArgs,
		RunE: func(*cobra.Command, []string) error {
			p := &session.Progress{City: gascity.New(), Open: ledger.OpenStore, Now: time.Now}
			out := p.Run()
			if out.Record == nil {
				return reportLook("session progress", nil, "", false, false, out.Failures, stdout, stderr)
			}
			return reportLook("session progress", out.Record, out.Record.Summary(), len(out.Record.Stalled) > 0, out.Recorded, out.Failures, stdout, stderr)
		},
	}
}
