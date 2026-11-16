package cli

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/arm"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/git"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/reaction"
)

func newReactionCmd(stdout, stderr io.Writer) *cobra.Command {
	return group("reaction", "a bead's first reaction: the exit it takes",
		`A first reaction is the run of mol-first-reaction every new bead gets: it reads
the bead once, writes a card on it, and takes one of five exits, which dispose
performs (docs/human-engagement.md).`,
		newReactionDisposeCmd(stdout, stderr))
}

const reactionDisposeLong = `Takes one exit of a first reaction on its subject, <bead>, and leaves the
subject open: a reaction disposes a bead and never closes it.

  actionable  the bead is work: release it to a pool (--route, by default the
              rig's gc-toolkit.polecat), or hand it to the named agent whose
              work it is (--assign): the mechanik takes a route and the
              refinery the assignee, and the agent is nudged once bd reports
              the bead ready. --emergency <check> claims a red main and names
              the check failing there.
  recommend   the action is known and warrants the operator's trigger: a
              human gate under first-reaction holds the bead, and
              --recommended-formula <mol> is what the board's Accept runs.
  blocked     the bead waits: each --waiting-on <bead> becomes a blocks edge,
              --blocker "<title>" files the bead it waits on, and --then-route
              arms its dispatch for when the wait lifts, or --then-assign hands
              it to a named agent.
  close       there is nothing to do: the bead goes to a validating closer
              (mol-validate-close on --route), which re-checks the call and
              closes it or asks the operator. --waiting-on holds the bead on
              the beads whose landing ends its job, and arms the closer for
              when they close.
  ruling      only the operator can answer: a human gate under
              first-reaction holds the bead.

Intake decides whether a pool route or a --then-route arm is written at all:
only a member of an epic, PR-finishing work (anchor_bead) or an emergency the
named check confirms on the default branch's head reaches a pool, and any
other bead is held with hold:mayor for the operator's placement sitting
(docs/steering.md). A route or a hand-off nothing would claim is refused, and
so is a hand-off to the po, the deacon, the witness or the keeper.

Each exit's writes keep their order, so the write that dispatches, holds or
gates the subject comes last, and a re-run of the same call after an exit
stopped part way resumes it. --run names the reaction's run, which the gate a
ruling or a recommend files names, so the check a re-offered reaction runs
passes over it. A flag set for an exit that does not take it is refused
before anything is read.

--db names the store, a store's .beads directory. Without it the subject's
store is the one its id's prefix names in the city's rig list.

exit: 0 disposed
      2 usage, or a route or hand-off nothing would claim: nothing written
      3 the subject is not open: nothing written
      4 stopped part way: the message says what landed, and a re-run resumes`

func newReactionDisposeCmd(stdout, stderr io.Writer) *cobra.Command {
	var d reaction.Dispose
	var db string
	cmd := &cobra.Command{
		Use:   "dispose <bead> --disposition <exit> --reason <text> --takeaway <text> [--run <root>] [--by <who>] [--db <path>] [the exit's flags]",
		Short: "take one exit of a first reaction on its subject",
		Long:  reactionDisposeLong,
		Args:  cobra.ExactArgs(1),
		RunE: func(c *cobra.Command, args []string) error {
			d.Bead = strings.TrimSpace(args[0])
			d.Set = map[string]bool{}
			for _, flags := range reaction.ExitFlags {
				for _, name := range flags {
					if c.Flags().Changed(name) {
						d.Set[name] = true
					}
				}
			}
			d.Set["run"] = c.Flags().Changed("run")
			d.Set["emergency"] = c.Flags().Changed("emergency")
			return disposeReaction(&d, db, stdout, stderr)
		},
	}
	f := cmd.Flags()
	f.StringVar(&d.Disposition, "disposition", "", "the exit: actionable, recommend, blocked, close or ruling")
	f.StringVar(&d.Reason, "reason", "", "why this exit, which lands on the bead beside it")
	f.StringVar(&d.Takeaway, "takeaway", "", "the board headline, at most 140 characters")
	f.StringVar(&d.Run, "run", "", "the root of the reaction's run, the root_bead_id its react step's claim returned")
	f.StringVar(&d.By, "by", "proactive", "who disposed the bead, which the headline names")
	f.StringVar(&db, "db", "", "the store, a store's .beads directory")
	f.StringVar(&d.Route, "route", "", "actionable, close: the pool, <rig>/<agent>")
	f.StringVar(&d.Assign, "assign", "", "actionable: the named agent whose work the bead is")
	f.StringVar(&d.Emergency, "emergency", "", "actionable, blocked: the check failing on main that makes the bead an emergency")
	f.StringArrayVar(&d.WaitingOn, "waiting-on", nil, "blocked, close: a bead the subject waits on, repeatable")
	f.StringVar(&d.Blocker, "blocker", "", "blocked: the title of the bead to file and wait on")
	f.StringVar(&d.ThenRoute, "then-route", "", "blocked: the pool to dispatch to once the wait lifts, <rig>/<agent>")
	f.StringVar(&d.ThenAssign, "then-assign", "", "blocked: the named agent to hand the bead to")
	f.StringVar(&d.RecommendedFormula, "recommended-formula", "", "recommend: the formula Accept runs on the bead")
	return cmd
}

// disposeReaction checks the call, opens the subject's store, and takes the
// exit. The city's rig list is read once, for the store and for each rule that
// asks which rig owns a store.
func disposeReaction(d *reaction.Dispose, db string, stdout, stderr io.Writer) error {
	const prog = "gctk reaction dispose"
	rig := strings.TrimSpace(os.Getenv("GC_RIG"))
	rt := gascity.New()
	if err := reaction.Validate(rt, rig, d); err != nil {
		return err
	}
	if db == "" {
		db = subjectStore(rt, d.Bead)
	}
	l, err := ledger.Open(db, d.Bead)
	if err != nil {
		fmt.Fprintf(stderr, "%s: could not open %s's store (%v); nothing was written\n", prog, d.Bead, err)
		return exit(4)
	}
	r := &reaction.Reactions{
		Ledger:  l,
		Runtime: rt,
		GitHub:  gh.NewBounded("github.com", reaction.GitHubWait),
		Rig:     rig,
		DB:      db,
		Origin:  git.OriginURL,
		Now:     time.Now,
		Log:     func(line string) { fmt.Fprintf(stderr, "%s: %s\n", prog, line) },
	}
	r.Arm = func(req arm.Request) (string, error) {
		a := &arm.Arms{Ledger: l, Runtime: rt, Now: time.Now, Actor: actor()}
		locks, err := arm.LockDir(rt)
		if err != nil {
			return "", err
		}
		a.Locks = locks
		return a.Arm(req)
	}
	done, err := r.Dispose(d)
	var use *reaction.UsageError
	switch {
	case err == nil:
		fmt.Fprintf(stdout, "%s: %s\n", prog, done)
		return nil
	case errors.As(err, &use):
		return err
	case reaction.NotOpen(err):
		fmt.Fprintf(stderr, "%s: %s\n", prog, strings.TrimPrefix(err.Error(), "the subject is not open: "))
		return exit(3)
	}
	fmt.Fprintf(stderr, "%s: %v\n", prog, err)
	return exit(4)
}

// subjectStore is the store of the rig whose prefix is the bead's, from the city's
// rig list, empty when the list does not read or names no such rig with a
// store, so that gc routes the bead to its store instead.
func subjectStore(rt gascity.Runtime, bead string) string {
	rigs, err := rt.Rigs()
	if err != nil {
		return ""
	}
	prefix, _, _ := strings.Cut(bead, "-")
	for _, g := range rigs {
		if g.Prefix != prefix || g.Path == "" {
			continue
		}
		if fi, err := os.Stat(filepath.Join(g.Path, ".beads")); err == nil && fi.IsDir() {
			return filepath.Join(g.Path, ".beads")
		}
	}
	return ""
}
