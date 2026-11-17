package cli

import (
	"encoding/json"
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/doctor"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
)

// gctk doctor run is the doctor order's verb (docs/gctk-architecture.md, "The
// surface"), through the doctor package.

func newDoctorCmd(stdout, stderr io.Writer) *cobra.Command {
	return group("doctor", "gc doctor's runs, each recorded as one Gas City event",
		`gc doctor's runs, each recorded as one Gas City event, gc-toolkit.doctor.ran,
whose newest is what doctor found last (doctor run).`,
		newDoctorRunCmd(stdout, stderr))
}

var doctorRunLong = `One run of gc doctor, recorded as one Gas City event, gc-toolkit.doctor.ran,
which the doctor-run order makes every hour. The newest such event is what
doctor found last: gc events --type gc-toolkit.doctor.ran reads them.

It runs gc doctor --json, never with --fix, and ends it if it has not finished
within ` + doctor.Deadline.String() + `. It writes no bead. The event's payload holds:

  started, finished  when the run began and ended
  completed          whether doctor exited 0 or 1 and printed a report that
                     reads, within the deadline; why says why not
  measured           when the lists below were measured: this run's start,
                     or, for a run that did not complete, the start of the run
                     whose lists it carries
  failing            each result that is not ok and that the accepted file
                     does not accept: its name, status, severity and message,
                     first_failed and streak
  not_measured       each result doctor did not measure, and why: timed_out
                     for a check doctor abandoned at its per-check timeout, or
                     the message of the stand-in its store gate reported in a
                     check's place, which opens "not checked:"
  accepted           each failing result the accepted file accepts, with its
                     entry
  monitors           each monitor order's last good run, last_good: the newest
                     order.completed Gas City recorded for it, one row per rig
                     for an order that runs in each rig
  monitors_unread    why this run's read of the monitors' runs failed, when it
                     did; monitors then holds the previous run's

How a run counts. A check's streak is the number of runs in a row that
measured it failing, and first_failed is the start of the first of them, so a
reader that shows only what two runs in a row found failing shows a check
whose streak is 2 or more. A run that did not complete measured nothing: it
records why, carries the previous run's lists unchanged, streaks and
first_failed included, and exits 1, so Gas City records order.failed as well.
A check that a completed run did not measure is listed as not measured and
keeps the streak and first_failed it had, with the accepted file's entry when
that entry accepts the failure at this run. So neither kind of run adds to a
streak or ends one. A check measured ok, or one doctor no longer reports,
leaves the lists, and its next failure starts a streak of 1.

The accepted file (--accepted; doctor/accepted.toml in the pack) names each
accepted check by the name doctor gives it, with the reason and the ruling
that accepted it. An entry with for accepts the check until it has failed that
long since first_failed, and from then on it is failing.

The monitors are ` + strings.Join(doctor.Monitors, ", ") + `. Their runs are
read from the order.completed events recorded since the previous run began, or
in the last 24 hours when there is no previous run or its read of them failed,
and a monitor with none in that window keeps the last good run the previous
event gave it.

When the previous run's event does not read, no doctor runs and nothing is
recorded, so the newest event stands. The record goes to standard output as
the event carries it, and a summary line to standard error.

exit: 0 doctor completed, and the monitors' runs were read and the event
        recorded
      1 doctor did not complete, a read failed, or the event was not recorded
      2 usage`

func newDoctorRunCmd(stdout, stderr io.Writer) *cobra.Command {
	var accepted string
	cmd := &cobra.Command{
		Use:   "run --accepted <file>",
		Short: "run gc doctor once and record the run as one gc-toolkit.doctor.ran event",
		Long:  doctorRunLong,
		Args:  cobra.NoArgs,
		RunE: func(*cobra.Command, []string) error {
			entries, err := doctor.ReadAccepted(accepted)
			if err != nil {
				fmt.Fprintf(stderr, "gctk doctor run: %v; no doctor ran and nothing was recorded\n", err)
				return exit(1)
			}
			r := &doctor.Runner{City: gascity.New(), Now: time.Now}
			out := r.Run(entries)
			if out.Record != nil {
				if err := json.NewEncoder(stdout).Encode(out.Record); err != nil {
					fmt.Fprintf(stderr, "gctk doctor run: the record could not be printed: %v\n", err)
				}
				state := "recorded"
				if !out.Recorded {
					state = "not recorded"
				}
				fmt.Fprintf(stderr, "gctk doctor run: %s, %s\n", out.Record.Summary(), state)
			}
			for _, f := range out.Failures {
				fmt.Fprintf(stderr, "gctk doctor run: %s\n", f)
			}
			if len(out.Failures) > 0 {
				return exit(1)
			}
			return nil
		},
	}
	cmd.Flags().StringVar(&accepted, "accepted", "", "the accepted file, doctor/accepted.toml in the pack")
	_ = cmd.MarkFlagRequired("accepted")
	return cmd
}
