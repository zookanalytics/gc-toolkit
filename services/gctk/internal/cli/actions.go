package cli

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"time"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/actions"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/git"
)

// gctk actions report is the actions-failure-report order's verb
// (docs/gctk-architecture.md, "The surface"), through the actions package.

// rigCheckouts reads a rig's checkout through the git adapter.
type rigCheckouts struct{}

func (rigCheckouts) OriginURL(dir string) (string, error)     { return git.OriginURL(dir) }
func (rigCheckouts) DefaultBranch(dir string) (string, error) { return git.DefaultBranch(dir) }
func (rigCheckouts) Grep(dir, rev, pattern string, paths ...string) ([]string, error) {
	return git.Grep(dir, rev, pattern, paths...)
}

// newActionsReport builds a report over the city, its rigs' checkouts and
// github.com. A variable so a test can give it fakes.
var newActionsReport = func() *actions.Report {
	return &actions.Report{
		City:     gascity.New(),
		GitHub:   gh.NewBounded("github.com", actions.ReadBound),
		Checkout: rigCheckouts{},
		Host:     "github.com",
		Now:      time.Now,
	}
}

func newActionsCmd(stdout, stderr io.Writer) *cobra.Command {
	return group("actions", "the GitHub Actions workflows a rig marks, as their runs on its default branch stand",
		`The GitHub Actions workflows a rig marks on its default branch, and the patrol
finding that carries a workflow's run of failures there into the rig's store
(actions report).`,
		newActionsReportCmd(stdout, stderr))
}

var actionsReportLong = fmt.Sprintf(`The actions-failure-report order's pass over one rig. It finds the workflows
the rig marks: each file directly under .github/workflows that holds a line of
its own, from the line's first character, that reads

  %s

at the default branch origin's HEAD names, as the rig's checkout last fetched
it. For each, it reads the newest %d completed runs on that branch in one
GitHub read, of the repository the checkout names as its origin. A pull
request's run and a run of a fork's commit do not count.

The newest decided run decides. A run that failed, ran out of time or could not
start is a failure, and a success a success. A run that ended any other way,
such as one cancelled or skipped, neither ends a run of failures nor extends
one.

A failure is reported as one patrol finding in the rig's store, through the
pack's patrol-finding.sh in the scripts directory GCTK_SCRIPTS_DIR names, under
the key actions.<file> and the scope actions-report, a bug at priority %d. The
key writes each underscore of the file's name twice, and each byte of a
character a key does not take as an underscore and its two hex digits, so no
two workflows share a key. Its text names the newest failure and its link, its
commit, how long the run of failures is, the success before it and the changes
since, the failed jobs and steps of the newest failure, read in one more GitHub
read, the command that prints their log, and the run's newest failures. A
report of a run that has not moved repeats that text, and the finding counts
it. A new failure changes it, and the finding notes the change. The writer
slings the finding's first reaction.

A success clears the finding's situation, with the success named as the
reason, and records nothing when no finding is live. A read that holds no
decided run records nothing. A rig whose branch marks no workflow is read no
further, and GitHub is asked nothing.

Each GitHub read ends after %s. A workflow the report has not started %s
after it began is reported unread, so a pass ends inside its order's time
however many workflows the rig marks. The report takes the workflows in the
order of their files' names, from a place that moves one workflow on every
%s, and the order's passes run that far apart, so a workflow one pass
leaves unread comes first in a later one.

With --dry-run it reads the checkout and GitHub and prints the writer's
arguments for each workflow, and writes nothing.

It prints one JSON object: the rig, its repository and default branch, and for
each workflow, in the order the report took them, its file, its state (failing, succeeded or none), the newest
decided run, the length of the run of failures, and what the writer recorded,
the arguments it would be given, or why that workflow's report did not
complete. The object's failure joins each such reason with any read of the
rig's own that failed.

exit: 0 every read answered and the writer recorded what it found
      1 a read failed or a finding was not recorded, as failure says
      2 usage`, actions.Mark, actions.Window, actions.Priority, actions.ReadBound, actions.StartBound, actions.Turn)

func newActionsReportCmd(stdout, stderr io.Writer) *cobra.Command {
	var rig string
	var dryRun bool
	c := &cobra.Command{
		Use:   "report --rig <rig>",
		Short: "report each workflow a rig marks that fails on its default branch as one patrol finding in its store, and clear it on a success",
		Long:  actionsReportLong,
		Args:  cobra.NoArgs,
		RunE: func(*cobra.Command, []string) error {
			if rig == "" {
				return errors.New("--rig names no rig")
			}
			out := newActionsReport().Run(rig, dryRun)
			if err := json.NewEncoder(stdout).Encode(out); err != nil {
				fmt.Fprintf(stderr, "gctk actions report: the outcome could not be printed: %v\n", err)
				return exit(1)
			}
			if out.Failure != "" {
				fmt.Fprintf(stderr, "gctk actions report: %s\n", out.Failure)
				return exit(1)
			}
			return nil
		},
	}
	c.Flags().StringVar(&rig, "rig", "", "the rig whose marked workflows to read and in whose store the findings land")
	c.Flags().BoolVar(&dryRun, "dry-run", false, "read the checkout and GitHub and print each finding writer's arguments, writing nothing")
	_ = c.MarkFlagRequired("rig")
	return c
}
