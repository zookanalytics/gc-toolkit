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
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/host"
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
command ended. A start with them while the copy's publish command runs, with
another publish command or address pattern, an empty one included, fails with
reason other-publisher and leaves the copy and its publish command running.
When another mapping already publishes the copy's port, a start moves a copy it
ran to another port, and fails with reason address-taken for a copy it found,
which keeps running on its port for whoever uses it. A start that cannot stop a
copy, because its process group survives SIGTERM and SIGKILL, fails with reason
not-stopped and keeps the copy's record, so --check reports it and --stop ends
it. --check reports the copy's state and starts nothing. --stop ends the copy's
whole process group. Starts and stops of one checkout take turns: one that
finds another under way waits for it to end, and acts on the copy it left. A
check waits for neither.

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
it has ended, and, in reason and detail, why. A start that found no copy
running and ran one also prints "started": true, so its caller knows the copy
is its own to stop. A start that found the copy running prints no started key.
rig's own lines, and the last lines of the log of a copy that failed or ended,
go to stderr.

  state          exit  meaning
  running        0     the copy runs and answers on its port as its own
  not-answering  1     --check: the copy runs and does not answer on its port
                       as its own, or a start or a stop of the checkout is
                       under way and the copy's leader is not running; a
                       start waits for the copy to answer, and stops it when
                       it does not
  died           1     --check: the copy's leader has ended
  none           3     --check: no copy of the checkout runs
  none, stopped  0     --stop: no copy runs, or its process group has ended
  running        1     --stop: the copy still runs, because its process group
                       survived SIGTERM and SIGKILL, or the lock on its record
                       could not be taken
  failed         1     start: no copy of the command runs as the start asks;
                       any call from a directory in no git checkout, with
                       reason no-checkout
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
			return exit(rig.Lead(host.Local(), o.lead))
		}
		return exit(rigServe(o, stdout, stderr))
	}
	return c
}

// checkRigServeOpts says why the flags do not go together, or returns "".
func checkRigServeOpts(o rigServeOpts) string {
	modes := 0
	for _, on := range []bool{o.given("command"), o.check, o.stop, o.given("lead")} {
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
	var rep rig.Report
	var code int
	if co, err := git.Open("."); err != nil {
		rep, code = rig.Report{State: rig.CopyFailed, Reason: "no-checkout",
			Detail: fmt.Sprintf("the current directory is in no git checkout, whose top names the copy (%v)", err)}, 1
	} else {
		rep, code = rigServeIn(co, o)
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

// rigServeIn runs the start, check or stop for the checkout co, and returns
// its report and the exit code.
func rigServeIn(co *git.Checkout, o rigServeOpts) (rig.Report, int) {
	top := co.Top
	if real, err := filepath.EvalSymlinks(top); err == nil {
		top = real
	}
	copies := rig.NewCopies(co.Common, host.Local())
	switch {
	case o.check:
		rep := copies.Check(top)
		switch rep.State {
		case rig.CopyRunning:
			return rep, 0
		case rig.CopyNone:
			return rep, 3
		}
		return rep, 1
	case o.stop:
		rep := copies.Stop(top)
		if rep.State == rig.CopyRunning {
			return rep, 1
		}
		return rep, 0
	}
	rep := copies.Serve(top, rig.ServeOpts{
		Command:        o.command,
		Publish:        o.given("publish-command"),
		PublishCommand: o.publish,
		AddressPattern: o.pattern,
		Wait:           o.timeout,
		ScriptsDir:     o.scriptDir,
	})
	if rep.State != rig.CopyRunning {
		return rep, 1
	}
	return rep, 0
}
