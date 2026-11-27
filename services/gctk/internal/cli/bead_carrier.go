package cli

import (
	"errors"
	"fmt"
	"io"
	"strings"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/disposition"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

const beadCarrierLong = `Prints the open bead that carries the bead's work now: the bead itself while
it is open, in_progress, blocked, deferred, hooked or pinned, else the open
bead its chain of duplicates and supersedes edges reaches, and nothing when
none does. The disposition writer (bead-rehome.sh) closes a duplicate, a fold,
a re-home or a fix upstream with one of those edges onto the bead it names.

The chain ends with no bead at a bead that closed naming no successor, since
the work ended there, at a not-needed close, whose edge names the evidence for
its ruling rather than a bead that carries the work, and at a bead the store
does not hold. A chain that loops, or runs past 20 edges, names no bead
either, and stderr says why. Each bead is read through its listing row, in the
store gc routes its id to, so an edge onto a bead in another rig's store is
followed there.

exit: 0 answered: the bead that carries the work, or nothing
      1 a read did not answer, which is never "none"
      2 usage`

func newBeadCarrierCmd(stdout, stderr io.Writer) *cobra.Command {
	return &cobra.Command{
		Use:   "carrier <bead>",
		Short: "the open bead that carries a bead's work now, through the edges its disposition wrote",
		Long:  beadCarrierLong,
		Args:  cobra.ExactArgs(1),
		RunE: func(_ *cobra.Command, args []string) error {
			id := strings.TrimSpace(args[0])
			if id == "" {
				return errors.New("name the bead by its id")
			}
			c, err := disposition.Carrier(ledger.New(gcbd.New()), id)
			if err != nil {
				fmt.Fprintf(stderr, "gctk bead carrier: %v\n", err)
				return exit(1)
			}
			if c.Warning != "" {
				fmt.Fprintf(stderr, "gctk bead carrier: %s\n", c.Warning)
			}
			if c.By != "" {
				fmt.Fprintln(stdout, c.By)
			}
			return nil
		},
	}
}
