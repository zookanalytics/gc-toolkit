package cli

import (
	"fmt"
	"io"
	"os"
	"strings"
	"time"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/arm"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/takeaway"
)

const beadTakeawayLong = `Writes the bead's headline, the one line its handling concluded, with when it
was written, who wrote it (--by, host when unnamed) and whether anything still
waits on it, in one update. Whitespace runs collapse to one space, and a
headline longer than 140 codepoints is refused, never cut.

--waiting-on <bead> names a bead the bead waits on, and is repeatable: each
becomes a blocks edge from the bead onto it, written after the headline. A
wait that rode the bead's own branch and has landed its work there, closed,
held by the refinery or its PR on the pending record, takes no edge, since the
bead's merge lands it. --no-wait says nothing waits on the bead, and is
stamped beside the headline, and every other headline clears that mark. The
two contradict, and a wait in another store holds nothing, so either is
refused.

--release takes the bead out of play in the same update: it reopens the bead,
assigns it to nobody, clears its route and the session pins its last executor
left, guarded on the status and the assignee it read, so a close or a claim
that lands after the read refuses it. A bead closed since keeps its close and
takes the headline alone, and any other change leaves the bead with whoever
holds it now. The release first removes the bead's arm (gctk bead disarm), and
after the update ends each run beneath the bead through the pack's
run-cancel.sh, but for a run this session holds a step of, which closes its own
chain. A closed bead keeps its disposition: the release writes the headline
alone and still ends the run beneath it. A claim a live session holds, one the
session list still names, is never taken: the headline and the waits land, the
holder is nudged to give the bead back, and the command exits 4. A release
that parks the bead for a person names --waiting-on or --no-wait, unless an
open blocker already holds the bead. It is refused on a bead whose PR waits on
the pending record, which the landing order works.

--route <rig>/<agent> sends the released bead to a pool, through gc sling with
no formula and no convoy once its run has ended, and --assign <agent> to a
named agent, as its assignee in the release's update. Either lifts the
placement hold, hold:po or its earlier spelling hold:mayor, and leaves any other
hold on, and either is refused on a closed bead and on a bead whose work is on a blocker
that is no human gate, the waits --waiting-on names among them for a route.

--db names the store, a store's .beads directory. Without it the bead's store
is the one gc routes the bead to. GCTK_SCRIPTS_DIR names the pack's scripts,
which a release needs for run-cancel.sh.

exit: 0 the headline, and any release, landed
      2 usage, or refused: nothing written
      4 stopped part way: the message says what landed and what did not`

func newBeadTakeawayCmd(stdout, stderr io.Writer) *cobra.Command {
	var req takeaway.Request
	var db string
	cmd := &cobra.Command{
		Use:   "takeaway <bead> <text> [--by <who>] [--waiting-on <bead>... | --no-wait] [--release [--route <rig>/<agent> | --assign <agent>]] [--db <path>]",
		Short: "write a bead's headline, and with --release take the bead out of play or send it on",
		Long:  beadTakeawayLong,
		Args:  cobra.ExactArgs(2),
		RunE: func(_ *cobra.Command, args []string) error {
			req.Bead, req.Text = strings.TrimSpace(args[0]), args[1]
			return beadTakeaway(req, db, stdout, stderr)
		},
	}
	f := cmd.Flags()
	f.StringVar(&req.By, "by", "host", "who wrote the headline, such as host, proactive or converse")
	f.StringArrayVar(&req.WaitingOn, "waiting-on", nil, "a bead the bead waits on, repeatable")
	f.BoolVar(&req.NoWait, "no-wait", false, "nothing waits on the bead")
	f.BoolVar(&req.Release, "release", false, "take the bead out of play: reopen it, unassign it and end the run beneath it")
	f.StringVar(&req.Route, "route", "", "with --release: the pool to send the bead to, <rig>/<agent>")
	f.StringVar(&req.Assign, "assign", "", "with --release: the named agent to send the bead to")
	f.StringVar(&db, "db", "", "the store, a store's .beads directory")
	return cmd
}

// beadTakeaway opens the bead's store, --db or else the one gc routes the bead
// to, and writes the takeaway, saying each step on stderr and what landed on
// stdout.
func beadTakeaway(req takeaway.Request, db string, stdout, stderr io.Writer) error {
	const prog = "gctk bead takeaway"
	l, err := ledger.Open(db, req.Bead)
	if err != nil {
		fmt.Fprintf(stderr, "%s: could not open %s's store (%v); nothing was written\n", prog, req.Bead, err)
		return exit(4)
	}
	t := takeaways(l, gascity.New(), db, func(line string) { fmt.Fprintf(stderr, "%s: %s\n", prog, line) })
	done, err := t.Take(req)
	switch {
	case err == nil:
		fmt.Fprintln(stdout, done)
		return nil
	case takeaway.Refused(err):
		fmt.Fprintf(stderr, "%s: %v\n", prog, err)
		return exit(2)
	}
	fmt.Fprintf(stderr, "%s: %v\n", prog, err)
	return exit(4)
}

// takeaways builds the takeaway's verb over the store l reads, with the city
// rt, the store db names for a remedy, the pack's scripts GCTK_SCRIPTS_DIR
// names, the names this session goes by and its agent address, and the arm's
// disarm under the bead's dispatch lock.
func takeaways(l *ledger.Ledger, rt *gascity.City, db string, log func(string)) *takeaway.Takeaways {
	t := &takeaway.Takeaways{
		Ledger:  l,
		City:    rt,
		DB:      db,
		Scripts: os.Getenv("GCTK_SCRIPTS_DIR"),
		Agent:   strings.TrimSpace(os.Getenv("GC_AGENT")),
		Now:     time.Now,
		Log:     log,
	}
	for _, v := range []string{"GC_SESSION_NAME", "GC_SESSION_ID", "GC_ALIAS"} {
		if s := strings.TrimSpace(os.Getenv(v)); s != "" {
			t.Self = append(t.Self, s)
		}
	}
	t.Disarm = func(id, reason string) (string, error) {
		a := &arm.Arms{Ledger: l, Runtime: rt, Now: time.Now, Actor: actor()}
		locks, err := arm.LockDir(rt)
		if err != nil {
			return "", err
		}
		a.Locks = locks
		return a.Disarm(id, reason)
	}
	return t
}
