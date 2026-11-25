package cli

import (
	"context"
	"errors"
	"fmt"
	"io"
	"path/filepath"
	"strings"
	"time"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/park"
	"github.com/zookanalytics/gc-toolkit/services/gctk/place"
)

// `gctk bead park` and `gctk bead place` are the operator's steering moves on a
// bead (docs/steering.md), through the park and place packages, and `gctk bead
// move-placement-hold` moves the placement queue onto hold:po. None holds
// a rule: the domain decides, and the command prints its answer.

const beadParkLong = `Parks the bead: everything under it that has not started waits on one
blocker, and work already in flight finishes. The bead takes one blocks edge,
onto the gate the text form files or onto the bead --waiting-on names, and bd
marks every bead under it blocked while that edge holds.

  gctk bead park <bead> "<text>" [--body <text>]
  gctk bead park <bead> --waiting-on <bead>

The text form files a gate titled <text>, one line of at most 140 characters
saying why the bead is parked and what releases it, which is refused rather
than cut when it is longer, and described by --body. The gate is born with its
edge in one create, in the bead's own store. Running it again with the same
text files no second gate, and a --body then becomes that gate's description.
--waiting-on parks the bead behind a bead that already exists in its store,
which is refused when it is the bead itself, closed or pinned, or under the
bead.

It refuses a closed bead, and a bead in flight: claimed (in_progress or
hooked), carrying branch, merge_result or rejection_reason, or worked by a
workflow past load-context, because its own edge would hold its merge and its
close. Park its parent instead. It prints "park <blocker> holds <bead>: <title>",
then what the park holds and what it leaves running. Closing the blocker
releases the park, and removing one bead's edge onto it (gc bd dep remove
<bead> <blocker>) releases that bead alone.

--db names the store, a store's .beads directory. Without it the park is made
in the store gc routes the bead to.

exit: 0 parked
      2 usage, or refused: nothing written
      4 a read or a write did not land, and the message says what did`

func newBeadParkCmd(stdout, stderr io.Writer) *cobra.Command {
	var db, body string
	var waitingOn []string
	cmd := &cobra.Command{
		Use:   `park <bead> ("<text>" [--body <text>] | --waiting-on <bead>) [--db <path>]`,
		Short: "hold everything under a bead that has not started, behind a gate or a bead, and leave work in flight running",
		Long:  beadParkLong,
		Args:  cobra.RangeArgs(1, 2),
		RunE: func(c *cobra.Command, args []string) error {
			const prog = "gctk bead park"
			req := park.Request{Bead: strings.TrimSpace(args[0]), Body: body, BodySet: c.Flags().Changed("body")}
			if len(args) == 2 {
				req.Text = args[1]
				if strings.TrimSpace(req.Text) == "" {
					fmt.Fprintf(stderr, "%s: park needs \"<text>\", the one-line headline saying why %s is parked and what releases it. Nothing was written\n", prog, req.Bead)
					return exit(2)
				}
			}
			if len(waitingOn) > 1 {
				fmt.Fprintf(stderr, "%s: --waiting-on names one bead to wait on, and this call names %s. Park once per bead. Nothing was written\n", prog, strings.Join(waitingOn, " and "))
				return exit(2)
			}
			if len(waitingOn) == 1 {
				if req.WaitingOn = waitingOn[0]; strings.TrimSpace(req.WaitingOn) == "" {
					return errors.New("--waiting-on requires a bead id")
				}
			}
			if _, err := park.Validate(req); err != nil {
				fmt.Fprintf(stderr, "%s: %v\n", prog, err)
				return exit(2)
			}
			l, err := ledger.Open(db, req.Bead)
			if err != nil {
				fmt.Fprintf(stderr, "%s: could not open %s's store (%v). Nothing was written\n", prog, req.Bead, err)
				return exit(4)
			}
			out, err := (&park.Parks{Ledger: l, DB: db}).Park(req)
			switch {
			case park.Refused(err):
				fmt.Fprintf(stderr, "%s: %v\n", prog, err)
				return exit(2)
			case err != nil:
				fmt.Fprintf(stderr, "%s: %v\n", prog, err)
				return exit(4)
			}
			if out.Reused {
				said := ""
				if out.Described {
					said = ", and its description is now the --body this call names"
				}
				fmt.Fprintf(stderr, "%s: %s already waits on the open gate %s under this text; no second gate filed%s\n", prog, req.Bead, out.Blocker, said)
			}
			for _, line := range out.Lines(req.Bead) {
				fmt.Fprintln(stdout, line)
			}
			return nil
		},
	}
	cmd.Flags().StringVar(&body, "body", "", "the description of the gate the text form files")
	cmd.Flags().StringArrayVar(&waitingOn, "waiting-on", nil, "park the bead behind this bead, filing no gate")
	cmd.Flags().StringVar(&db, "db", "", "the store, a store's .beads directory")
	return cmd
}

const beadPlaceLong = `Places a bead held for placement, one carrying hold:po, or hold:mayor, its
earlier spelling, in any spelling (docs/steering.md): its parent, or none, its
dispatch, then the lift of its hold, in one order.

  gctk bead place <bead> --under <parent> [--shift <±n>] [--route <rig>/<pool>] [--on <formula>]
  gctk bead place <bead> --standalone [--route <rig>/<pool>] [--on <formula>]

It clears a route, then with --under removes a relates-to link between the
bead and the parent, sets the parent and moves --shift through
queue-priority.sh move. It settles the bead's priority (queue-priority.sh
settle), then dispatches, then lifts the placement hold with a note in one
write, and each write's exit decides whether it landed. With no --route it sends the bead
to the polecat pool of its rig, and with no --on on that pool's default
formula. While a wait holds the bead or a parent above it, such as a park on
the epic, it arms the dispatch (gctk bead arm) instead of slinging, so the run
starts once nothing holds it.

It refuses a closed bead, PR-finishing work (anchor_bead), a bead another
hold also holds, such as hold:external, a status other than open, a parent that
is closed or not in the bead's store, --standalone on a bead that has a parent,
and a bead an arm already sends to another pool or on another formula. A bead
with no placement hold is refused, or reported as placed already when a live
run, a route, an arm or an assignee shows its dispatch; a first reaction's run
shows none, since it triages the bead and works none of it. A dispatch that fails leaves
the hold on, so the bead stays in the queue. Running it again after a stop at
any write finishes the placement without a second run: it dispatches nothing
once an assignee, a merge_result, a live run or an arm shows a dispatch, and gc
sling refuses a second live run of one formula at one bead (exit 3). A run that
ends without claiming, landing or closing its bead leaves none of these, so a
stop at the lift names the lift by hand, which dispatches nothing.

--db names the store, a store's .beads directory. Without it the placement is
made in the store of the rig whose prefix begins the bead's id. GCTK_SCRIPTS_DIR
names the pack's scripts, where queue-priority.sh is.

exit: 0 placed, or placed already
      2 usage, or refused: nothing written
      4 a read, a write or the dispatch did not land, and the message says what did`

const beadMovePlacementHoldLong = `Moves the placement queue from hold:mayor, the placement hold's earlier
spelling, onto hold:po: each live bead the queue holds on hold:mayor, in the
store of the HQ and of each rig gc rig list --json names, suspended or not
(docs/steering.md, "The intake rule").

  gctk bead move-placement-hold [--dry-run]

Each bead moves through bd's set-state, gc bd set-state <bead> hold=po, which
swaps its hold label in one write and files the event bead that records it, so
the bead stays held, and a bead already on hold:po takes no write. A bead is
read again just before its write, and one whose hold:mayor was lifted since is
not written. It moves only a bead whose hold labels are hold:mayor, or
hold:mayor beside hold:po. Each other bead the queue holds on hold:mayor stays
as it is, named with why and the write a person makes: one another hold or
hold:cleared also labels, one whose hold:mayor is in another case, one assigned
to an agent, and one routed to a pool or an agent. A route of mayor, or a
binding's mayor with no rig, has the shape Gas City's doctor repair
hold-label-routed-to wrote from the label, and a writer can choose it too, so
its line names gc bd history <bead> --events to read who set it before the
route is cleared. No closed bead is read or written.

It prints a line for each store: what it moved, or with --dry-run would move,
what is on hold:po already, and each bead it left, or why the store did not
read. --dry-run writes nothing.

Exit: 0 every store read and no live bead is left on hold:mayor · 1 a bead is
left on hold:mayor, each named with the write that clears it · 2 usage · 3 the
rig list or a store did not read, so the move has not finished: run it again
once the store answers.`

func newBeadMovePlacementHoldCmd(stdout, stderr io.Writer) *cobra.Command {
	var dryRun bool
	cmd := &cobra.Command{
		Use:   "move-placement-hold [--dry-run]",
		Short: "move each live bead the placement queue holds on hold:mayor onto hold:po, in every store of the city",
		Long:  beadMovePlacementHoldLong,
		Args:  cobra.NoArgs,
		RunE: func(*cobra.Command, []string) error {
			const prog = "gctk bead move-placement-hold"
			m := &place.Move{City: gascity.New(), Open: ledger.OpenStore, DryRun: dryRun}
			out, err := m.Run(context.Background())
			if err != nil {
				fmt.Fprintf(stderr, "%s: the city's rig list did not read (%v), so no store was read and nothing was written\n", prog, err)
				return exit(3)
			}
			moved := "moved"
			if dryRun {
				moved = "would move"
			}
			for _, s := range out.Stores {
				if s.Unread != "" {
					fmt.Fprintf(stdout, "%s: %s (%s) did not read: %s\n", prog, s.Rig, s.DB, s.Unread)
					continue
				}
				fmt.Fprintf(stdout, "%s: %s: %s %d to hold:po%s; %d on hold:po already; %d left on hold:mayor\n",
					prog, s.Rig, moved, len(s.Moved), idList(s.Moved), len(s.OnPO), len(s.Left))
				for _, l := range s.Left {
					fmt.Fprintf(stdout, "%s: %s: left %s on hold:mayor: %s. %s\n", prog, s.Rig, l.ID, l.Why, l.Fix)
				}
			}
			switch {
			case out.AnyUnread():
				fmt.Fprintf(stderr, "%s: a store did not read, so the move has not finished: run it again once it answers\n", prog)
				return exit(3)
			case out.AnyLeft():
				fmt.Fprintf(stderr, "%s: a bead is left on hold:mayor: make the write each line names, then run it again\n", prog)
				return exit(1)
			}
			return nil
		},
	}
	cmd.Flags().BoolVar(&dryRun, "dry-run", false, "write nothing, and name each bead the move would move")
	return cmd
}

// idList is the ids in parentheses, or nothing when there are none.
func idList(ids []string) string {
	if len(ids) == 0 {
		return ""
	}
	return " (" + strings.Join(ids, " ") + ")"
}

func newBeadPlaceCmd(stdout, stderr io.Writer) *cobra.Command {
	var db string
	var req place.Request
	cmd := &cobra.Command{
		Use:   "place <bead> (--under <parent> [--shift <±n>] | --standalone) [--route <rig>/<pool>] [--on <formula>] [--db <path>]",
		Short: "place a bead held for placement: its parent or none, its dispatch, then its hold lifted",
		Long:  beadPlaceLong,
		Args:  cobra.ExactArgs(1),
		RunE: func(_ *cobra.Command, args []string) error {
			const prog = "gctk bead place"
			req.Bead = strings.TrimSpace(args[0])
			if err := place.Validate(req); err != nil {
				fmt.Fprintf(stderr, "%s: %v\n", prog, err)
				return exit(2)
			}
			rt := gascity.New()
			rig, store, err := rigOf(rt, req.Bead)
			if err != nil {
				fmt.Fprintf(stderr, "%s: %v. Nothing was written\n", prog, err)
				return exit(4)
			}
			if db == "" {
				db = store
			}
			l, err := ledger.Open(db, req.Bead)
			if err != nil {
				fmt.Fprintf(stderr, "%s: could not open %s's store (%v). Nothing was written\n", prog, req.Bead, err)
				return exit(4)
			}
			a, err := openArms(db, req.Bead, true)
			if err != nil {
				fmt.Fprintf(stderr, "%s: could not reach %s's arm (%v). Nothing was written\n", prog, req.Bead, err)
				return exit(4)
			}
			p := &place.Places{Ledger: l, Runtime: rt, Arm: a.Arm, Rig: rig, DB: db, Now: time.Now,
				Log: func(line string) { fmt.Fprintf(stderr, "%s: %s\n", prog, line) }}
			out, err := p.Place(req)
			switch {
			case place.Refused(err):
				fmt.Fprintf(stderr, "%s: %v\n", prog, err)
				return exit(2)
			case err != nil:
				fmt.Fprintf(stderr, "%s: %v\n", prog, err)
				return exit(4)
			}
			fmt.Fprintln(stdout, out.Line(req))
			return nil
		},
	}
	cmd.Flags().StringVar(&req.Under, "under", "", "the epic or Delivery the bead goes under")
	cmd.Flags().BoolVar(&req.Standalone, "standalone", false, "place the bead with no parent, at its own priority")
	cmd.Flags().StringVar(&req.Shift, "shift", "", "the bead's shift against its parent, such as +1 for one level later")
	cmd.Flags().StringVar(&req.Route, "route", "", "the pool the bead is sent to, as <rig>/<pool>; the rig's polecat pool when unnamed")
	cmd.Flags().StringVar(&req.Formula, "on", "", "the formula the bead is poured on; the pool's default when unnamed")
	cmd.Flags().StringVar(&db, "db", "", "the store, a store's .beads directory")
	return cmd
}

// rigOf is the rig whose bead prefix begins id, the longest when several do,
// and its store, a .beads directory, from the rigs the city names.
func rigOf(rt gascity.Runtime, id string) (name, store string, err error) {
	rigs, err := rt.Rigs()
	if err != nil {
		return "", "", fmt.Errorf("the city's rigs did not read (%v), so the store that holds %s cannot be named", err, id)
	}
	best := ""
	for _, r := range rigs {
		if r.Prefix != "" && r.Path != "" && strings.HasPrefix(id, r.Prefix+"-") && len(r.Prefix) > len(best) {
			best, name, store = r.Prefix, r.Name, filepath.Join(r.Path, ".beads")
		}
	}
	if name == "" {
		return "", "", fmt.Errorf("no rig's store holds %s: its prefix names no rig the city names", id)
	}
	return name, store, nil
}
