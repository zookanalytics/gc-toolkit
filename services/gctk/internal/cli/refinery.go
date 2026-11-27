package cli

import (
	"io"
	"time"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/refinery"
)

// gctk refinery stuck is the refinery-queue-detect order's verb
// (docs/gctk-architecture.md, "The surface"), through the refinery package.

func newRefineryCmd(stdout, stderr io.Writer) *cobra.Command {
	return group("refinery", "a rig's refinery queue",
		`A rig's refinery queue: each handoff that has sat there unprepared, held by
nothing, past the time a handoff takes to turn over (refinery stuck).`,
		newRefineryStuckCmd(stdout, stderr))
}

const refineryStuckLong = `The refinery queue's look, which the refinery-queue-detect order runs every 30
minutes. For each rig gc rig list --json lists that is not suspended, the HQ
aside, it reads the open beads assigned to the agent named refinery that gc
agent list --json names in the rig, and records one Gas City event,
gc-toolkit.refinery-queue.stuck, when it finds a handoff stuck there. It writes
no bead. A rig whose roster names no refinery is a queue that cannot be read.

A handoff is a bead of no kind bd's default listing hides (a wisp, a template,
a gate, or an agent, role or message bead), and no epic, that carries a branch
and no merge_result. It is stuck when its last write is more than four hours
old, nothing holds it (gctk bead holds answers clear), and the close of the
last wait that held it is more than four hours old too. A handoff turns over
within a poll interval, and a rebase or rework task once the fix pool claims
it, so one past that bound is not churn.

A rig list or an agent list that does not read judges nothing. The event's
payload holds:

  read     when the look read
  stuck    each handoff found: rig, bead, refinery, and since, the later of
           its last write and the close of the last wait that held it
  unread   each rig whose queue, its address, or what holds a handoff past
           the bound did not read, and why, when one did not

With --act, which the refinery-queue-report order passes when the look's event
fires, it reads the same way, records no event, and files a human gate keyed
witness-refinery-queue on each stuck handoff, through the pack's human-gate.sh
in the directory GCTK_SCRIPTS_DIR names. An open gate holds the handoff, so
the look passes over it until a person answers the gate, and the writer files
no second gate while one is open, nor for a day after a person answers one
moot: or benign:.

` + lookHelpEnd + "\n\n" + actHelpEnd

func newRefineryStuckCmd(stdout, stderr io.Writer) *cobra.Command {
	var act bool
	cmd := &cobra.Command{
		Use:   "stuck",
		Short: "find each refinery handoff that has sat unprepared past four hours, held by nothing, and record them as one gc-toolkit.refinery-queue.stuck event",
		Long:  refineryStuckLong,
		Args:  cobra.NoArgs,
		RunE: func(*cobra.Command, []string) error {
			city := gascity.New()
			q := &refinery.Queue{City: city, Open: ledger.OpenStore, Now: time.Now}
			ctx, release := stopOnSignal()
			if act {
				acted := (&refinery.Report{Look: q, Scripts: city}).Run(ctx)
				if sig := release(); sig != 0 {
					return exit(128 + int(sig))
				}
				outputs := make([]string, len(acted.Gated))
				for i, g := range acted.Gated {
					outputs[i] = g.Output
				}
				return reportAct("refinery stuck", acted, len(acted.Gated), outputs, acted.Failures, stdout, stderr)
			}
			out := q.Run(ctx)
			if sig := release(); sig != 0 {
				return exit(128 + int(sig))
			}
			if out.Record == nil {
				return reportLook("refinery stuck", nil, "", false, false, out.Failures, stdout, stderr)
			}
			return reportLook("refinery stuck", out.Record, out.Record.Summary(), len(out.Record.Stuck) > 0, out.Recorded, out.Failures, stdout, stderr)
		},
	}
	cmd.Flags().BoolVar(&act, "act", false, "file a human gate on each stuck handoff, and record no event")
	return cmd
}
