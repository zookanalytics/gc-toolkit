package cli

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/deployment"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/git"
)

// gctk deployment report is the production-deploy-report order's verb
// (docs/gctk-architecture.md, "The surface"), through the deployment package.

// newDeploymentReport builds a report over the city and github.com. A variable
// so a test can give it fakes.
var newDeploymentReport = func() *deployment.Report {
	return &deployment.Report{
		City:   gascity.New(),
		GitHub: gh.NewBounded("github.com", deployment.ReadBound),
		Host:   "github.com",
		Origin: git.OriginURL,
	}
}

func newDeploymentCmd(stdout, stderr io.Writer) *cobra.Command {
	return group("deployment", "a rig's deployments to one environment, as GitHub records them",
		`A rig's deployments to one environment, as the host that deploys its
repository records them on GitHub, and the patrol finding that carries a run of
failed ones into the rig's store (deployment report).`,
		newDeploymentReportCmd(stdout, stderr))
}

var deploymentReportLong = fmt.Sprintf(`The production-deploy-report order's pass over one rig. It reads, in one
GitHub read, the newest %d deployments of the environment, %s unless
--environment names another, in the repository the rig's checkout names as its
origin, each with its latest status and the commit statuses failing on its
commit. Every deployment of the environment counts: a city runs the report for
a rig whose repository deploys the environment from its default branch.

The newest finished deployment decides. A FAILURE or an ERROR is a failure,
and a SUCCESS a success. A deployment in any other state, such as one still in
progress or one GitHub marks INACTIVE, neither ends a run of failures nor
extends one.

A failure is reported as one patrol finding in the rig's store, through the
pack's patrol-finding.sh in the scripts directory GCTK_SCRIPTS_DIR names, under
the key deployment.<environment> and the scope deployment-report, a task at
priority %d. Its text names the newest failure, its commit and pull request,
the deployment's link and what its status and its commit's failing statuses
say, how long the run is, the success before it and the changes since, and the
run's newest failures. A report of a run that has not moved repeats that text,
and the finding counts it. A new failure changes it, and the finding notes the
change. The writer slings the finding's first reaction.

A success clears the finding's situation, with the success named as the
reason, and records nothing when no finding is live. A read that holds no
finished deployment records nothing.

GitHub carries no build log, so the finding links the deployment and quotes
its statuses, and the failing step's error is read on the host that ran it.

With --dry-run it reads GitHub and prints the writer's arguments, and writes
nothing.

It prints one JSON object: the rig, its repository, the environment, the state
(failing, succeeded or none), the newest finished deployment, the run's
length, and what the writer recorded, the arguments it would be given, or why
the report did not complete.

exit: 0 the report read and recorded what it found
      1 a read failed or the finding was not recorded, as failure says
      2 usage`, deployment.Window, deployment.Environment, deployment.Priority)

func newDeploymentReportCmd(stdout, stderr io.Writer) *cobra.Command {
	var rig, environment string
	var dryRun bool
	c := &cobra.Command{
		Use:   "report --rig <rig>",
		Short: "report a rig's failing deployments of its default branch as one patrol finding in its store, and clear it on a success",
		Long:  deploymentReportLong,
		Args:  cobra.NoArgs,
		RunE: func(*cobra.Command, []string) error {
			if rig == "" {
				return errors.New("--rig names no rig")
			}
			out := newDeploymentReport().Run(rig, environment, dryRun)
			if err := json.NewEncoder(stdout).Encode(out); err != nil {
				fmt.Fprintf(stderr, "gctk deployment report: the outcome could not be printed: %v\n", err)
				return exit(1)
			}
			if out.Failure != "" {
				fmt.Fprintf(stderr, "gctk deployment report: %s\n", out.Failure)
				return exit(1)
			}
			return nil
		},
	}
	c.Flags().StringVar(&rig, "rig", "", "the rig whose deployments to read and in whose store the finding lands")
	c.Flags().StringVar(&environment, "environment", deployment.Environment, "the deployment environment to read")
	c.Flags().BoolVar(&dryRun, "dry-run", false, "read GitHub and print the finding writer's arguments, writing nothing")
	_ = c.MarkFlagRequired("rig")
	return c
}
