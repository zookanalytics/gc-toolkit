package cli

import (
	"fmt"
	"io"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/arm"
	"github.com/zookanalytics/gc-toolkit/services/gctk/distiller"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// gctk distiller start is the feedback-distiller order's verb
// (docs/gctk-architecture.md, "The surface"), through the distiller package.

func newDistillerCmd(stdout, stderr io.Writer) *cobra.Command {
	return group("distiller", "the feedback distiller's run",
		`The feedback distiller's run: the city's one run of mol-feedback-distiller,
in the pack's home rig (distiller start).`,
		newDistillerStartCmd(stdout, stderr))
}

const distillerStartLong = `The feedback-distiller order's start, which the order runs once a day for the
city. It reads gc rig list --json and finds the pack's home rig, the one rig,
the HQ aside, whose checkout holds a pack.toml that names the gc-toolkit pack,
and the one agent named polecat that gc agent list --json places there. Unless
the home rig's store holds a live root of a mol-feedback-distiller run, it runs
gc sling <that pool> mol-feedback-distiller --formula, which pours the run in
the home rig's store. An open run, whichever path poured it, holds the start,
so a day whose run is still going starts no second one.

From before its read of the home rig's store to the sling's end, the start holds
a lock, distiller-start.lock in the city's .gc/runtime/packs/gc-toolkit, which
it takes without waiting. A start that finds another holding it, the order's or
one made by hand, starts nothing and exits 0, since that start reads and slings.

A city where no rig's checkout holds the pack has nowhere to distill, and a
suspended home rig takes no run, as Gas City dispatches no order of a suspended
rig. Each slings nothing and exits 0. Two rigs that each hold the pack, a
pack.toml that does not read, a home rig the roster places no polecat in or
several, a lock that cannot be taken, and a read or a sling that does not
answer each sling nothing and exit 1.

The line on standard output says what the start did, or why it started
nothing, and a failure goes to standard error.

exit: 0 a run started, or nothing needed to
      1 a read failed, the home rig or its pool is not one, the lock could not
        be taken, or the sling failed
      2 usage
      128+N stopped by signal N`

func newDistillerStartCmd(stdout, stderr io.Writer) *cobra.Command {
	return &cobra.Command{
		Use:   "start",
		Short: "start the city's feedback distiller run in the pack's home rig, unless one is open there",
		Long:  distillerStartLong,
		Args:  cobra.NoArgs,
		RunE: func(*cobra.Command, []string) error {
			rt := gascity.New()
			locks, err := arm.LockDir(rt)
			if err != nil {
				fmt.Fprintf(stderr, "gctk distiller start: started nothing: %v\n", err)
				return exit(1)
			}
			s := &distiller.Starter{City: rt, Open: ledger.OpenStore, Locks: locks}
			ctx, release := stopOnSignal()
			out := s.Run(ctx)
			if sig := release(); sig != 0 {
				return exit(128 + int(sig))
			}
			if out.Failure != "" {
				fmt.Fprintf(stderr, "gctk distiller start: %s\n", out.Summary())
				return exit(1)
			}
			fmt.Fprintln(stdout, out.Summary())
			return nil
		},
	}
}
