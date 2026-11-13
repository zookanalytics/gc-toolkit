package cli

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"slices"
	"strings"
	"time"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/arm"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// `gctk bead holds <bead>...` answers what holds each bead, through the waits
// package, from one snapshot of the store (docs/gctk-architecture.md, "The
// bead holds contract"). `gctk bead arm`, `gctk bead disarm` and `gctk bead
// start-armed` are the arm's verbs, through the arm package
// (docs/deferred-dispatch.md). None holds a rule: the domain decides, and the
// command prints its answer.

const beadHoldsLong = `Prints what holds each bead named, from one read of the store: one JSON
object per line, in the order named, each bead once.

{"id", "status", "waits", "pending", "last_landed", "in_flight", "arm",
 "foreign"}

status is blocked when a wait of the bead's own holds it, held when only an
ancestor's wait holds it and its work has not started, unjudged when it has a
waits-for edge of its own, and clear otherwise. Work in flight is held only
by its own waits.

waits are the waits behind the status, each {"id", "type", "title",
"status"}, where title and status are those of the bead waited on, with its
"issue_type" and "await_type" when it has them, which tell a gate a person
answers from work, and "ancestor" naming the ancestor whose wait it is. A
waits-for wait is unjudged: the bd the city runs judges it by its spawner's
status rather than its gate, so a caller that acts holds such a bead. pending
is the bead's own waits that have not landed, and last_landed is when the
last wait that applies to it landed: its own, and for work that has not
started each live ancestor's too, "" when none has. in_flight says why the
bead is in flight: claimed, carrying branch, merge_result or
rejection_reason, or worked by a live workflow past load-context, and is ""
when it is not. arm is the arm on a bead armed to start by itself, as its
record decodes it, and null when it carries none: {"target", "formula",
"reason", "armed_by", "armed_at", "fail_count", "capped"}, where formula is
"" when the arm names none, so a start pours the target's default, fail_count
is the attempts a start has made on it, and capped says they have reached the
cap, at which a start asks a person instead. "malformed" says why a stored arm
does not decode, and a start slings no such arm. foreign is the bead's wait
edges into another store, each {"id", "type"}, which hold nothing.

A bead the store could not answer prints {"id", "error"} and no status, and
so does a bead the store does not hold.

--db names the store to read, a store's .beads directory, and every read of
the store names it with bd's own --db flag. Without it the command reads the
store gc routes a read of the first bead to, as gc routes a read that names
a bead and no store: the store gc resolves from the working directory and the
environment (gc bd where) when its prefix begins that bead's id, else the
store whose prefix does (gc rig list), and the resolved store when no store's
prefix begins it or the stores do not list. Every read names that one store,
so no read that names a bead is routed to another, and a bead named in
another store is one this store does not hold.

exit: 0 every bead answered
      1 at least one bead's read failed, and its line carries the error
      2 usage`

func newBeadCmd(stdout, stderr io.Writer) *cobra.Command {
	var db string
	holds := &cobra.Command{
		Use:   "holds [--db <path>] <bead>...",
		Short: "what holds each bead: one status, the waits behind it, its own pending waits, its arm and its edges into another store",
		Long:  beadHoldsLong,
		Args:  cobra.MinimumNArgs(1),
		RunE: func(_ *cobra.Command, args []string) error {
			var ids []string
			for _, a := range args {
				id := strings.TrimSpace(a)
				if id == "" {
					return errors.New("name each bead by its id")
				}
				if !slices.Contains(ids, id) {
					ids = append(ids, id)
				}
			}
			return exit(beadHolds(db, ids, stdout, stderr))
		},
	}
	holds.Flags().StringVar(&db, "db", "", "the store to read, a store's .beads directory")
	return group("bead", "what holds a bead, and its arm",
		"A bead's waits, what holds it, read from the store, and the arm that starts it by itself once nothing does.",
		holds, newBeadArmCmd(stdout, stderr), newBeadDisarmCmd(stdout, stderr), newBeadStartArmedCmd(stdout, stderr))
}

const beadArmLong = `Arms the bead: it starts by itself once nothing holds it, poured on the
formula --on names, or on the target's default formula, which the city's
config gives, through the pool or agent --target names. The deferred-dispatch
order's pass sends it (gctk bead start-armed). The arm is one write on the
bead, with a note that says who armed it, when, for what and why, made under
the bead's dispatch lock, which gctk bead disarm and the start hold too.

It refuses a closed bead, one already armed for another target or formula,
one already dispatched (in progress, or routed), one at any status but open,
a target that names no formula to pour, and a bead with a wait edge onto a
bead its store does not hold, an edge bd never holds a bead on. A refused arm
writes nothing. An arm already on the bead for the same target and formula is
a success that writes nothing. It prints what it did and what holds the bead
now.

--db names the store, a store's .beads directory. Without it the arm is made in
the store gc routes the bead to.

exit: 0 the bead is armed
      1 the arm was refused or could not be made, and it says why
      2 usage`

func newBeadArmCmd(stdout, stderr io.Writer) *cobra.Command {
	var db, target, formula, reason string
	cmd := &cobra.Command{
		Use:   "arm <bead> --target <rig>/<pool> [--on <formula>] --reason <text> [--db <path>]",
		Short: "start a bead by itself once nothing holds it, on a formula",
		Long:  beadArmLong,
		Args:  cobra.ExactArgs(1),
		RunE: func(_ *cobra.Command, args []string) error {
			id := strings.TrimSpace(args[0])
			if id == "" || strings.TrimSpace(target) == "" || strings.TrimSpace(reason) == "" {
				return errors.New("name the bead, its --target and the --reason it is armed for")
			}
			a, err := openArms(db, id, true)
			if err != nil {
				fmt.Fprintf(stderr, "gctk bead arm: %v; nothing was written\n", err)
				return exit(1)
			}
			said, err := a.Arm(arm.Request{ID: id, Target: target, Formula: formula, Reason: reason})
			if err != nil {
				fmt.Fprintf(stderr, "gctk bead arm: %s\n", strings.TrimPrefix(err.Error(), "refused: "))
				return exit(1)
			}
			fmt.Fprintln(stdout, said)
			return nil
		},
	}
	cmd.Flags().StringVar(&target, "target", "", "the pool or agent a start slings the bead to, as <rig>/<agent>")
	cmd.Flags().StringVar(&formula, "on", "", "the formula a start pours on the bead; the target's default when unnamed")
	cmd.Flags().StringVar(&reason, "reason", "", "why the bead is armed")
	cmd.Flags().StringVar(&db, "db", "", "the store, a store's .beads directory")
	return cmd
}

const beadDisarmLong = `Removes the bead's arm in one write, with a note that says when and why, under
the bead's dispatch lock. A start that is sending the bead holds the lock until
it finishes, so once disarm exits 0 no start has the bead in flight and none
will send it. A write that stops an armed bead, or sends it on another way,
runs this first, and goes on only once it exits 0. A bead that carries no arm
is a success that writes nothing.

--db names the store, a store's .beads directory. Without it the arm is removed
in the store gc routes the bead to.

exit: 0 no arm remains on the bead
      1 the arm could not be removed, and it says why
      2 usage`

func newBeadDisarmCmd(stdout, stderr io.Writer) *cobra.Command {
	var db, reason string
	cmd := &cobra.Command{
		Use:   "disarm <bead> --reason <text> [--db <path>]",
		Short: "stop an armed bead from starting by itself",
		Long:  beadDisarmLong,
		Args:  cobra.ExactArgs(1),
		RunE: func(_ *cobra.Command, args []string) error {
			id := strings.TrimSpace(args[0])
			if id == "" || strings.TrimSpace(reason) == "" {
				return errors.New("name the bead and the --reason it is disarmed for")
			}
			a, err := openArms(db, id, true)
			if err != nil {
				fmt.Fprintf(stderr, "gctk bead disarm: %v; nothing was written\n", err)
				return exit(1)
			}
			said, err := a.Disarm(id, reason)
			if err != nil {
				fmt.Fprintf(stderr, "gctk bead disarm: %v\n", err)
				return exit(1)
			}
			fmt.Fprintln(stdout, said)
			return nil
		},
	}
	cmd.Flags().StringVar(&reason, "reason", "", "why the arm is removed")
	cmd.Flags().StringVar(&db, "db", "", "the store, a store's .beads directory")
	return cmd
}

const beadStartArmedLong = `One pass over the store's armed beads, run by the deferred-dispatch order. It
prints one JSON object per armed bead: what gctk bead holds answers for it,
with "start" added, what the pass did with its arm, or with --dry-run would do:

"start": {"action", "case", "why", "formula", "roots"}

action is retire, start, sent, hold, ask, leave, withdrawn or fail:

  retire     the bead closed (case closed), or carries a merge_result, so
             another path delivered its work (case delivered): the arm is
             cleared and nothing slung, whatever holds the bead
  start      it was slung on formula, and its arm cleared
  sent       its work is sent already, so the arm is cleared and nothing
             slung: an earlier attempt's pour landed, or gc sling's exit 3
             named a live workflow on it that is not an unfinished pour; roots
             names them
  hold       something holds it, and the arm stays: a wait of its own or of
             an ancestor that has not started (blocked, held), a waits-for edge
             the store cannot judge (unjudged), a wait edge into another store
             (foreign), a hold or human label (label), an assignee (assigned),
             a status other than open (status), an epic (epic), or bd's
             readiness (unready)
  ask        a person is asked, and the arm stays: its attempts reached the cap
             (cap), or Gas City left a pour of it unfinished (unfinished), which
             roots names
  leave      left untouched for the next pass: another call holds its dispatch
             lock (locked), or the pass is near its deadline (deadline)
  withdrawn  its arm was removed after the pass listed it, and nothing was sent
  fail       a read, a write, a sling or an ask failed, or its arm does not
             decode (malformed), and the arm stays

The pass retires the arm of each closed or delivered bead first. It selects the
beads to start by bd's ready read with the pool's own serve rule, then holds
back what bd cannot judge and a hold label in any spelling. It starts each
under the bead's dispatch lock: it reads the bead once more, pours the arm's
formula with the title token arm:<bead>@<armed at>, after an earlier attempt
first searching that token, counts the attempt in one write before the sling,
and clears the arm once the sling exits 0. It starts no sling once less than
one sling's allowance is left before its deadline. A summary line goes to
stderr.

--dry-run writes, slings and asks nothing and takes no lock. --db names the
store, a store's .beads directory; without it the pass reads the store gc
resolves. GCTK_SCRIPTS_DIR names the pack's scripts, which ask a person, and
GC_RIG, when set, is the rig gc sling is given.

exit: 0 every armed bead was decided
      1 the armed beads could not be listed, or an arm's act failed
      2 usage`

func newBeadStartArmedCmd(stdout, stderr io.Writer) *cobra.Command {
	var db string
	var dryRun bool
	cmd := &cobra.Command{
		Use:   "start-armed [--db <path>] [--dry-run]",
		Short: "start each armed bead nothing holds, once, and retire the arm a closed or delivered bead carries",
		Long:  beadStartArmedLong,
		Args:  cobra.NoArgs,
		RunE: func(*cobra.Command, []string) error {
			a, err := openArms(db, "", !dryRun)
			if err != nil {
				fmt.Fprintf(stderr, "gctk bead start-armed: %v; nothing was read or sent\n", err)
				return exit(1)
			}
			enc := json.NewEncoder(stdout)
			var encErr error
			sum, err := a.StartArmed(arm.StartOptions{DryRun: dryRun, Rig: strings.TrimSpace(os.Getenv("GC_RIG"))}, func(l arm.Line) {
				if e := enc.Encode(l); e != nil && encErr == nil {
					encErr = e
				}
			})
			if err != nil {
				fmt.Fprintf(stderr, "gctk bead start-armed: %v, and an unread queue is not an empty one\n", err)
				return exit(1)
			}
			fmt.Fprintf(stderr, "gctk bead start-armed: %s\n", sum)
			if encErr != nil {
				fmt.Fprintf(stderr, "gctk bead start-armed: a line could not be printed: %v\n", encErr)
				return exit(1)
			}
			if sum.Failed() > 0 {
				return exit(1)
			}
			return nil
		},
	}
	cmd.Flags().BoolVar(&dryRun, "dry-run", false, "say what the pass would do, and write, sling and ask nothing")
	cmd.Flags().StringVar(&db, "db", "", "the store, a store's .beads directory")
	return cmd
}

// openArms builds the arm's verbs over the store at db, or the one gc routes id
// to when db is empty. A caller that writes needs the dispatch locks' directory.
func openArms(db, id string, locks bool) (*arm.Arms, error) {
	var ids []string
	if id != "" {
		ids = []string{id}
	}
	l, err := ledger.Open(db, ids...)
	if err != nil {
		return nil, err
	}
	rt := gascity.New()
	a := &arm.Arms{Ledger: l, Runtime: rt, Now: time.Now, Actor: actor()}
	if locks {
		if a.Locks, err = arm.LockDir(rt); err != nil {
			return nil, err
		}
	}
	return a, nil
}

// actor is who a write names: the agent, else bd's actor, else the user.
func actor() string {
	for _, v := range []string{"GC_AGENT", "BEADS_ACTOR", "USER"} {
		if s := strings.TrimSpace(os.Getenv(v)); s != "" {
			return s
		}
	}
	return "unknown"
}

// failedLine is the line of a bead the store could not answer.
type failedLine struct {
	ID    string `json:"id"`
	Error string `json:"error"`
}

// beadHolds prints one line per bead, from one waits snapshot of them all,
// read from the store at db, or from the store gc resolves when db is empty.
func beadHolds(db string, ids []string, stdout, stderr io.Writer) int {
	snap, readErr := waits.ReadStore(db, ids...)
	code := 0
	for _, id := range ids {
		var line any
		h, err := waits.Holds{}, readErr
		if err == nil {
			h, err = snap.Holds(id)
		}
		if err != nil {
			line, code = failedLine{ID: id, Error: err.Error()}, 1
		} else {
			line = h
		}
		raw, err := json.Marshal(line)
		if err != nil {
			fmt.Fprintf(stderr, "gctk bead holds: could not encode the answer for %s: %v\n", id, err)
			return 1
		}
		fmt.Fprintf(stdout, "%s\n", raw)
	}
	return code
}
