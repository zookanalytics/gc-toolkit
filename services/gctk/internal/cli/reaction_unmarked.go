package cli

import (
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/reaction"
)

// `gctk reaction unmarked` is the read a backlog refinement opens with
// (skills/backlog-refinement/SKILL.md): the beads filed with no mark a first
// reaction reads, which nothing else claims. The reaction package holds the
// rule (reaction.Unmarked). This command opens the rig's store and prints the
// answer.

const reactionUnmarkedLong = `Lists the open beads in the rig's store that no mark, owner, route, arm,
hold, wait or run claims, highest priority first, one line each:

  <bead>	P<priority>	<title>

A first reaction takes a bead its filer marked for one: hold:mayor, which files
new work into the placement queue, or a patrol finding's finding.scope. A bead
filed with neither gets no first reaction and sits in no queue, so the po's
backlog refinement opens with this list, and holds each bead the operator
agrees is new work, which the next sweep reacts to. The list starts no work.

Its one read is the sweep's, bd's ready set of unassigned beads that are not
epics, so a bead a wait holds is not listed. It leaves out a bead with a mark,
a route, an arm or a dispatch hold, a member of a parent, a bead a live run
works, and machinery by the keys and kinds machinery carries: a type other than
task, bug, feature, spike or chore, a topology root, a step, a standing record,
a feedback pattern, a review lane, and a bead whose work markers put it in
motion. A bead that carries a headline is listed, since a headline claims
nothing. A run map that does not read drops nothing, which it says on stderr.

With nothing to list it prints one line that says so. When the store does not
answer it prints nothing on stdout and says so on stderr, since a list it could
not read is not an empty one.

--rig names the rig whose store it reads, as the city's config names it (gc
config show). Without it the command reads the store gc resolves for this
session (gc bd where).

exit: 0 listed, or nothing to list
      1 the store did not answer, so what is unmarked is unknown
      2 usage, or a rig the city's config does not name`

// The exit codes reactionUnmarkedLong states.
const (
	unmarkedExitDone    = 0
	unmarkedExitNoStore = 1
	unmarkedExitUsage   = 2
)

// unmarkedNone is what the command prints when no bead is unmarked.
const unmarkedNone = "No open bead lacks both a mark and a claim: each is held, a patrol finding, owned, routed, armed, waiting or worked."

func newReactionUnmarkedCmd(stdout, stderr io.Writer) *cobra.Command {
	var rig string
	cmd := &cobra.Command{
		Use:   "unmarked [--rig <rig>]",
		Short: "the open beads filed with no mark a first reaction reads, which nothing else claims",
		Long:  reactionUnmarkedLong,
		Args:  cobra.NoArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			const prog = "gctk reaction unmarked"
			rig = strings.TrimSpace(rig)
			db := ""
			if rig != "" {
				path, ok, err := gcbd.New().RigStore(rig)
				switch {
				case err != nil:
					fmt.Fprintf(stderr, "%s: the rig's store did not resolve (%v), so what is unmarked is unknown: run it again\n", prog, err)
					return exit(unmarkedExitNoStore)
				case !ok:
					fmt.Fprintf(stderr, "%s: the city's config names no rig %q: give --rig a rig it names\n", prog, rig)
					return exit(unmarkedExitUsage)
				}
				db = path
			}
			l, err := ledger.Open(db)
			if err != nil {
				fmt.Fprintf(stderr, "%s: the store did not resolve (%v), so what is unmarked is unknown: run it again\n", prog, err)
				return exit(unmarkedExitNoStore)
			}
			r := &reaction.Reactions{Ledger: l, Runtime: gascity.New(), Rig: rig, DB: db, Now: time.Now,
				Log: func(line string) { fmt.Fprintf(stderr, "%s: %s\n", prog, line) }}
			return exit(reactionUnmarked(r, stdout, stderr))
		},
	}
	cmd.Flags().StringVar(&rig, "rig", "", "the `rig` whose store it reads; default this session's store")
	return cmd
}

// reactionUnmarked prints the unmarked beads r's store holds, one line each, or
// the line that says there are none, and returns the command's exit.
func reactionUnmarked(r *reaction.Reactions, stdout, stderr io.Writer) int {
	beads, err := r.Unmarked()
	if err != nil {
		fmt.Fprintf(stderr, "gctk reaction unmarked: the store did not answer (%v), so what is unmarked is unknown: run it again\n", err)
		return unmarkedExitNoStore
	}
	if len(beads) == 0 {
		fmt.Fprintln(stdout, unmarkedNone)
		return unmarkedExitDone
	}
	for _, b := range beads {
		fmt.Fprintf(stdout, "%s\tP%d\t%s\n", b.ID, b.Priority(), strings.TrimSpace(oneLine(b.Title())))
	}
	return unmarkedExitDone
}
