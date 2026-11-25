package cli

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/actions"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/git"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// gctk actions track is the actions-track order's verb
// (docs/gctk-architecture.md, "The surface"), through the actions package.

// newActionsTrack builds a pass over the city, its rigs' checkouts and stores,
// and github.com. A variable so a test can give it fakes.
var newActionsTrack = func() *actions.Pass {
	return &actions.Pass{
		City:          gascity.New(),
		GitHub:        gh.NewBounded("github.com", actions.ReadBound),
		Store:         func(db string) (*ledger.Ledger, error) { return ledger.Open(db) },
		Host:          "github.com",
		Origin:        git.OriginURL,
		DefaultBranch: git.DefaultBranch,
	}
}

func newActionsCmd(stdout, stderr io.Writer) *cobra.Command {
	return group("actions", "the GitHub Actions runs a push to a rig's default branch starts, and the tracker of each workflow failing there",
		`The GitHub Actions runs that a push to a rig's default branch starts, and the
tracker that sends a workflow failing there to be fixed (actions track).`,
		newActionsTrackCmd(stdout, stderr))
}

var actionsTrackLong = fmt.Sprintf(`The actions-track order's pass over one rig. It reads, in one GitHub read,
the newest %d finished runs that a push to the rig's default branch started, of
every workflow, in the repository the rig's checkout names as its origin, on
the branch origin's HEAD names there. A run of another branch, of a pull
request, or of a commit from a fork does not count.

For each workflow, by its file, the newest run that failed, ran out of time,
could not start or succeeded decides. A run that ended any other way, such as
one a newer push cancelled, decides nothing.

A workflow whose deciding run failed is a failure on the default branch, and
the pack's writer of a tracker of such a failure, %s in the scripts directory
GCTK_SCRIPTS_DIR names, keeps one bead for it under the key that its key
--target derives from the workflow's file. When its find names a bead for the
key, the pass files nothing. When none does, a run that started before the
key's tracking last ended files nothing either, since a fix may have ended the
failure it shows: the tracking ended at the latest close among the key's most
recently closed tracker and the closed beads that tracker's chain of duplicates
and supersedes edges reaches, read from the rig's store. Otherwise the pass
reads the failed run's jobs in one more GitHub read and has the writer file the
tracker: a bug naming the workflow, the run and its link, its commit, the last
success before it, its failed jobs and steps, the command that prints their
log, and how to find a tracker the failure already has. The writer files into
the store gc resolves for this process, which the order's environment makes
the rig's, and sends each tracker it files to be fixed.

Each GitHub read ends after %s.

With --dry-run it reads all that a pass reads, the writer's key and find among
it, and prints the file call it would make for each workflow, writing nothing.

It prints one JSON object: the rig, its repository and default branch, how many
of the read's runs count and when the oldest run of the read was made, and for
each workflow, in the order of its file's path, its state (failing, succeeded
or none) and deciding run, and for a failing one its key, what the pass did
(tracked, held back, filed or would file), its tracker, the close that held its
run back, what the writer said, the file call a dry run would make, or why that
workflow's pass did not complete. The object's failure joins each such reason
with any read of the rig's own that failed.

exit: 0 every read answered and the writer filed each tracker the pass found due
      1 a read failed or a tracker was not filed, as failure says
      2 usage`, actions.Window, actions.Script, actions.ReadBound)

func newActionsTrackCmd(stdout, stderr io.Writer) *cobra.Command {
	var rig string
	var dryRun bool
	c := &cobra.Command{
		Use:   "track --rig <rig>",
		Short: "file the tracker of each workflow whose newest finished push run on a rig's default branch failed, which sends it to be fixed",
		Long:  actionsTrackLong,
		Args:  cobra.NoArgs,
		RunE: func(*cobra.Command, []string) error {
			if rig == "" {
				return errors.New("--rig names no rig")
			}
			out := newActionsTrack().Run(rig, dryRun)
			if err := json.NewEncoder(stdout).Encode(out); err != nil {
				fmt.Fprintf(stderr, "gctk actions track: the outcome could not be printed: %v\n", err)
				return exit(1)
			}
			if out.Failure != "" {
				fmt.Fprintf(stderr, "gctk actions track: %s\n", out.Failure)
				return exit(1)
			}
			return nil
		},
	}
	c.Flags().StringVar(&rig, "rig", "", "the rig whose default branch to read and whose failures to file")
	c.Flags().BoolVar(&dryRun, "dry-run", false, "read all a pass reads and print each file call it would make, writing nothing")
	_ = c.MarkFlagRequired("rig")
	return c
}
