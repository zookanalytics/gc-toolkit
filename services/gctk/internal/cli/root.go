package cli

import (
	"errors"
	"fmt"
	"io"
	"strconv"

	"github.com/spf13/cobra"
)

// The command tree is cobra's (docs/gctk-architecture.md, "Compositions"). Each
// domain verb is one command, `gctk <noun> <verb>`, and cobra generates its help
// from its flags and its Long text. A command parses its flags, builds what it
// asks, asks or acts, and prints the result.
//
// A command's own exit code leaves through exitStatus. Any other error Execute
// returns is cobra refusing the invocation, such as an unknown verb, a flag that
// does not parse or a wrong count of arguments, and the RunE of a group called
// with no verb returns one too. Run prints such an error with the usage of the
// command it reached, and exits with that command's usage code: 2, or the code
// the command's usageExitKey annotation names.

// usageExitKey is the annotation of a command whose usage error exits with a
// code other than 2, because its callers read 2 as something else.
const usageExitKey = "gctk.usage-exit"

// exitStatus carries a command's own exit code out of cobra's Execute, which
// returns only an error.
type exitStatus int

func (e exitStatus) Error() string { return "exit status " + strconv.Itoa(int(e)) }

// exit is what a RunE returns for code: nil for 0, so cobra reads it as
// success, and the code otherwise.
func exit(code int) error {
	if code == 0 {
		return nil
	}
	return exitStatus(code)
}

// errNoVerb is what a group command returns when it is called with no verb.
var errNoVerb = errors.New("name a verb")

// Run builds gctk's command tree, runs args through it and returns the process
// exit code. version is what `gctk version` prints.
func Run(args []string, version string, stdout, stderr io.Writer) int {
	root := newRoot(version, stdout, stderr)
	root.SetArgs(args)
	cmd, err := root.ExecuteC()
	var status exitStatus
	switch {
	case err == nil:
		return 0
	case errors.As(err, &status):
		return int(status)
	}
	if cmd == nil {
		cmd = root
	}
	fmt.Fprintf(stderr, "%s: %v\n\n%s", cmd.CommandPath(), err, cmd.UsageString())
	return usageExit(cmd)
}

// usageExit is the exit code of a usage error in cmd: the code the nearest
// usageExitKey annotation names, else 2.
func usageExit(cmd *cobra.Command) int {
	for c := cmd; c != nil; c = c.Parent() {
		if v, ok := c.Annotations[usageExitKey]; ok {
			if n, err := strconv.Atoi(v); err == nil {
				return n
			}
		}
	}
	return 2
}

func newRoot(version string, stdout, stderr io.Writer) *cobra.Command {
	root := &cobra.Command{
		Use:   "gctk",
		Short: "gc-toolkit's command-line interface",
		Long: `gctk is gc-toolkit's command-line interface: the documented, structured
surface through which agents act on a city. Each command is one verb of the
form gctk <noun> <verb>, called by an agent, a hook or an order
(docs/gctk-architecture.md).`,
		Args:          cobra.NoArgs,
		SilenceErrors: true,
		SilenceUsage:  true,
		RunE:          func(*cobra.Command, []string) error { return errNoVerb },
	}
	root.CompletionOptions.DisableDefaultCmd = true
	root.SetOut(stdout)
	root.SetErr(stderr)
	root.AddCommand(
		newBeadCmd(stdout, stderr),
		newEpicCmd(stdout, stderr),
		newLifecycleCmd(stdout, stderr),
		newMergeCmd(stdout, stderr),
		newPRCmd(stdout, stderr),
		newRigCmd(stdout, stderr),
		newSessionCmd(stdout, stderr),
		newVersionCmd(version, stdout),
	)
	return root
}

// group returns a noun's command, which holds its verbs and runs none itself.
func group(use, short, long string, verbs ...*cobra.Command) *cobra.Command {
	g := &cobra.Command{
		Use:   use,
		Short: short,
		Long:  long,
		Args:  cobra.NoArgs,
		RunE:  func(*cobra.Command, []string) error { return errNoVerb },
	}
	g.AddCommand(verbs...)
	return g
}

func newVersionCmd(version string, stdout io.Writer) *cobra.Command {
	return &cobra.Command{
		Use:   "version",
		Short: "the revision this binary was built from",
		Long: `Prints the revision this binary was built from: the tree hash of
services/gctk the build order stamps, else the toolchain's commit, with -dirty
for a modified tree, else unknown. doctor/check-cadence-live compares it against
the checkout.`,
		Args: cobra.NoArgs,
		RunE: func(*cobra.Command, []string) error {
			fmt.Fprintln(stdout, version)
			return nil
		},
	}
}

// newLifecycleCmd and newMergeCmd keep their own flag parsing and usage text:
// both retire with the merge member (docs/gctk-architecture.md, "The
// re-implementation register"), so they join the tree as they are.
func newLifecycleCmd(stdout, stderr io.Writer) *cobra.Command {
	return &cobra.Command{
		Use:   "lifecycle",
		Short: "anchor lifecycle transitions (lifecycle/lifecycle.toml)",
		Long: `The anchor state machine's transitions, over lifecycle/lifecycle.toml. It
parses its own verbs and flags: gctk lifecycle with no verb prints them.`,
		DisableFlagParsing: true,
		RunE: func(_ *cobra.Command, args []string) error {
			return exit(Lifecycle(args, stdout, stderr))
		},
	}
}

func newMergeCmd(stdout, stderr io.Writer) *cobra.Command {
	return &cobra.Command{
		Use:   "merge",
		Short: "the merge cadence's arm 2, the single writer of merged truth",
		Long: `The merge cadence's arm 2, the single writer of merged truth, which
assets/scripts/merge.sh hands its calls to. It reads its own flags, --deadline
and --cursor, which pace one pass.`,
		DisableFlagParsing: true,
		RunE: func(_ *cobra.Command, args []string) error {
			return exit(Merge(args, stdout, stderr))
		},
	}
}
