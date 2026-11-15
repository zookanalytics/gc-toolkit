package cli

import (
	"fmt"
	"io"
	"strings"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/epic"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// `gctk epic unweighed` is the read a portfolio sync weighs its epics from
// (skills/portfolio-sync/SKILL.md): each close and each shift of the rig's
// epics that no sync has weighed. The epic package holds the rule. This command
// opens the rig's store and prints the answer.

const epicUnweighedLong = `Lists, oldest first, each close and each latest shift of the rig's epics that
no portfolio sync has weighed, one line each:

  <when> <epic> closed, <weighed>: <the close's reason>
  <when> <epic> shifted, <weighed>: <the shift's reason>
  <when> <epic> shifted, <weighed>, then ruled <ruling> on <day>: <its reason>

<weighed> is "last weighed <day>", the UTC day a sync last weighed the epic,
or "never weighed". A sync weighs an epic when its note on the epic marks it
(the portfolio-sync skill), and each epic answers by its own mark, so a sitting
that ends before it marks every epic leaves the rest on the list. A change
made on or after the day of its epic's mark lists, one made on that day too,
since the sync's read of the epics comes before its mark. An epic's latest
shift is the one its epic review stamped last, so a shift that a later review
continued or closed still lists, with the ruling that followed it. A Delivery,
an epic under one of the rig's epics with no hypothesis of its own, is left
out, since its close is one of the writes of its epic's ruling.

With nothing to list it prints one line that says so. When the store does not
answer it prints nothing on stdout and says so on stderr, since a list it could
not read is not an empty one.

--rig names the rig whose epics it reads, as gc rig list names it. Without it
the command reads the store gc resolves for this session (gc bd where).

exit: 0 listed, or nothing to list
      1 the store did not answer, so what closed or shifted is unknown
      2 usage, or a rig gc rig list does not name`

// The exit codes epicUnweighedLong states.
const (
	unweighedExitDone    = 0
	unweighedExitNoStore = 1
	unweighedExitUsage   = 2
)

// unweighedNone is what the command prints when no epic has a change to weigh.
const unweighedNone = "No epic has closed or shifted since a sync last weighed it."

func newEpicUnweighedCmd(stdout, stderr io.Writer) *cobra.Command {
	var rig string
	cmd := &cobra.Command{
		Use:   "unweighed [--rig <rig>]",
		Short: "each close and each latest shift of the rig's epics that no portfolio sync has weighed, oldest first",
		Long:  epicUnweighedLong,
		Args:  cobra.NoArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			l, code := epicUnweighedOpen(strings.TrimSpace(rig), stderr)
			if l == nil {
				return exit(code)
			}
			return exit(epicUnweighed(l, stdout, stderr))
		},
	}
	cmd.Flags().StringVar(&rig, "rig", "", "the `rig` whose epics it reads; default this session's store")
	return cmd
}

// epicUnweighedOpen opens the store of the rig named, or the one gc resolves
// for this session when rig is empty, and returns nil with the exit when it
// cannot.
func epicUnweighedOpen(rig string, stderr io.Writer) (*ledger.Ledger, int) {
	db := ""
	if rig != "" {
		path, ok, err := gcbd.New().RigStore(rig)
		switch {
		case err != nil:
			fmt.Fprintf(stderr, "gctk epic unweighed: the rig's store did not resolve (%v), so what closed or shifted is unknown: run it again before you weigh any change\n", err)
			return nil, unweighedExitNoStore
		case !ok:
			fmt.Fprintf(stderr, "gctk epic unweighed: gc rig list names no rig %q: give --rig a rig it names\n", rig)
			return nil, unweighedExitUsage
		}
		db = path
	}
	l, err := ledger.Open(db)
	if err != nil {
		fmt.Fprintf(stderr, "gctk epic unweighed: the store did not resolve (%v), so what closed or shifted is unknown: run it again before you weigh any change\n", err)
		return nil, unweighedExitNoStore
	}
	return l, unweighedExitDone
}

// epicUnweighed prints the changes no sync has weighed of the epics l reads,
// one line each, or the line that says there are none.
func epicUnweighed(l *ledger.Ledger, stdout, stderr io.Writer) int {
	changes, err := epic.Unweighed(l)
	if err != nil {
		fmt.Fprintf(stderr, "gctk epic unweighed: the rig's epics did not read (%v), so what closed or shifted is unknown: run it again before you weigh any change\n", err)
		return unweighedExitNoStore
	}
	if len(changes) == 0 {
		fmt.Fprintln(stdout, unweighedNone)
		return unweighedExitDone
	}
	for _, c := range changes {
		fmt.Fprintln(stdout, unweighedLine(c))
	}
	return unweighedExitDone
}

// unweighedLine is c as one line: its time, its epic, what happened, the day a
// sync last weighed the epic, the ruling that followed a shift, and the reason,
// each control character a space.
func unweighedLine(c epic.Change) string {
	weighed := "never weighed"
	if c.Weighed != "" {
		weighed = "last weighed " + c.Weighed
	}
	if c.Then != "" {
		on := c.ThenOn
		if on == "" {
			on = "an undated day"
		}
		weighed += ", then ruled " + c.Then + " on " + on
	}
	when := c.At
	if when == "" {
		when = "undated"
	}
	reason := strings.TrimSpace(oneLine(c.Reason))
	if reason == "" {
		reason = "no reason recorded"
	}
	return oneLine(fmt.Sprintf("%s %s %s, %s: %s", when, c.Epic, c.Kind, weighed, reason))
}

// oneLine is s with each control character a space.
func oneLine(s string) string {
	return strings.Map(func(r rune) rune {
		if r < 0x20 || r == 0x7f {
			return ' '
		}
		return r
	}, s)
}
