package cli

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/git"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/rig"
)

// `gctk rig serve` runs a copy of the rig's UI. Like the checks, it runs the
// command its caller passes and reads no formula var: a caller reads the rig's
// ui_serve_command, and the city's ui_publish_command and ui_address_pattern,
// and passes them.

const rigServeLong = `Runs a copy of the rig's UI from the checkout the current directory sits in:
the command --command passes, with bash at the checkout's top, on a free
loopback port it is given as $PORT, inside the sandbox a demo capture runs in.
A demo capture points its engine at the copy's port, and a sitting gives the
operator the copy's address, so both reach the UI through one path.

A checkout has at most one copy. A start for a checkout whose copy runs starts
no other: it reports that copy once it answers on its port, so a start is safe
to repeat. A start whose command differs from the one that copy runs fails with
reason other-command and leaves the copy running. --publish-command and --address-pattern ask for an address: the
publish command publishes the copy's port, as $PORT, for exactly as long as it
runs, and the address is the pattern with the port for each $PORT or ${PORT}.
Either one empty means no address can be given. A copy started without them has
no address, and a start with them publishes a running copy whose publish
command ended. --check reports the copy's state and starts nothing. --stop ends
the copy's whole process group.

The sandbox is the one demo-engine-lib.sh defines, in the pack's scripts
directory, which GCTK_SCRIPTS_DIR names. The serve command cannot read the
city's directories, reach a loopback port but its own, or signal a process
outside the sandbox, and it runs with none of the variables that point a
command at the city. The publish command runs outside it. A copy ends when it is
stopped, when its serve command ends, or once the session that started it has
ended, through Gas City's orphan sweep, which reads the session's values from
the copy's leader.

It prints one JSON line on stdout: the state, the checkout, the copy's port, its
address, empty when it has none, its log, the serve command's exit status once
it has ended, and, in reason and detail, why. rig's own lines, and the last
lines of the log of a copy that failed or ended, go to stderr.

  state          exit  meaning
  running        0     the copy runs and answers on its port as its own
  not-answering  1     --check: the copy runs and does not answer on its port
                       as its own; a start waits for it to, and stops it when
                       it does not
  died           1     --check: the copy's leader has ended
  none           3     --check: no copy of the checkout runs
  none, stopped  0     --stop: no copy runs, or its process group has ended
  running        1     --stop: the copy's process group survived SIGTERM and
                       SIGKILL
  failed         1     start: no copy of the command runs
exit 2 is a usage error.

--lead runs a copy's leader over its record. A start runs it in a session of
its own, and nothing else calls it.`

// rigServeDefaultWait bounds a start's wait for its copy to answer, long enough
// for a serve command that compiles first.
const rigServeDefaultWait = 3 * time.Minute

type rigServeOpts struct {
	command   string
	publish   string
	pattern   string
	check     bool
	stop      bool
	lead      string
	timeout   time.Duration
	given     func(name string) bool
	scriptDir string
}

func newRigServeCmd(stdout, stderr io.Writer) *cobra.Command {
	o := rigServeOpts{}
	c := &cobra.Command{
		Use:   "serve",
		Short: "run a copy of the rig's UI from this checkout, report its state or stop it",
		Long:  rigServeLong,
		Args:  cobra.NoArgs,
	}
	f := c.Flags()
	f.StringVar(&o.command, "command", "", "the serve `command` to run, with the copy's port as $PORT")
	f.StringVar(&o.publish, "publish-command", "", "the `command` that publishes the copy's port, $PORT, while it runs")
	f.StringVar(&o.pattern, "address-pattern", "", "the `address` the publish command gives, with $PORT where the port goes")
	f.DurationVar(&o.timeout, "timeout", rigServeDefaultWait, "how long a start waits for the copy to answer before it stops it")
	f.BoolVar(&o.check, "check", false, "report the copy's state and start nothing")
	f.BoolVar(&o.stop, "stop", false, "end the copy's process group")
	f.StringVar(&o.lead, "lead", "", "run a copy's leader over its `record`; a start runs it")
	c.RunE = func(cmd *cobra.Command, _ []string) error {
		o.given = cmd.Flags().Changed
		o.scriptDir = os.Getenv("GCTK_SCRIPTS_DIR")
		if msg := checkRigServeOpts(o); msg != "" {
			return errors.New(msg)
		}
		if o.lead != "" {
			return exit(rig.Lead(o.lead))
		}
		return exit(rigServe(o, stdout, stderr))
	}
	return c
}

// checkRigServeOpts says why the flags do not go together, or returns "".
func checkRigServeOpts(o rigServeOpts) string {
	modes := 0
	for _, on := range []bool{o.given("command"), o.check, o.stop, o.lead != ""} {
		if on {
			modes++
		}
	}
	start := o.given("command")
	switch {
	case modes == 0:
		return "pass --command, --check or --stop"
	case modes > 1:
		return "--command, --check, --stop and --lead exclude one another"
	case start && o.command == "":
		return "--command needs the serve command"
	case o.given("lead") && o.lead == "":
		return "--lead needs a record"
	case o.given("publish-command") != o.given("address-pattern"):
		return "--publish-command and --address-pattern go together"
	case !start && (o.given("publish-command") || o.given("timeout")):
		return "only a start, with --command, takes --publish-command, --address-pattern or --timeout"
	case o.timeout <= 0:
		return fmt.Sprintf("--timeout %s is not a duration above zero, such as 90s or 3m", o.timeout)
	}
	return ""
}

// rigServe runs a start, a check or a stop for the checkout the current
// directory sits in, prints its report and returns the exit code.
func rigServe(o rigServeOpts, stdout, stderr io.Writer) int {
	say := func(format string, a ...any) {
		fmt.Fprintf(stderr, "gctk rig serve: %s\n", fmt.Sprintf(format, a...))
	}
	co, err := git.Open(".")
	if err != nil {
		say("%v", err)
		return 2
	}
	top := co.Top
	if real, err := filepath.EvalSymlinks(top); err == nil {
		top = real
	}
	copies := rig.NewCopies(co.Common)
	var rep rig.Report
	code := 0
	switch {
	case o.check:
		rep = copies.Check(top)
		switch rep.State {
		case rig.CopyRunning:
		case rig.CopyNone:
			code = 3
		default:
			code = 1
		}
	case o.stop:
		rep = copies.Stop(top)
		if rep.State == rig.CopyRunning {
			code = 1
		}
	default:
		rep = copies.Serve(top, rig.ServeOpts{
			Command:        o.command,
			Publish:        o.given("publish-command"),
			PublishCommand: o.publish,
			AddressPattern: o.pattern,
			Wait:           o.timeout,
			ScriptsDir:     o.scriptDir,
		})
		if rep.State != rig.CopyRunning {
			code = 1
		}
	}
	raw, err := json.Marshal(rep)
	if err != nil {
		say("the report did not encode: %v", err)
		return 1
	}
	fmt.Fprintf(stdout, "%s\n", raw)
	if rep.Detail != "" && rep.State != rig.CopyRunning {
		say("%s: %s", rep.State, rep.Detail)
	}
	if rep.Tail != "" {
		fmt.Fprintf(stderr, "--- the last lines of the copy's log\n%s\n", rep.Tail)
	}
	return code
}
