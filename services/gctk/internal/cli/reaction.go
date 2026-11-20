package cli

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
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
	return group("reaction", "a bead's first reaction: whether it takes one, its sling, the exit it takes, and the acceptance of its recommendation",
		`A first reaction is the run of mol-first-reaction every new bead gets: it reads
the bead once, writes a card on it, and takes one of five exits, which dispose
performs (docs/human-engagement.md). sling starts one on a bead nobody has
decided on, sweep starts one on each such bead in the rig, check is the
reaction's own first act, deliverable says whether the rig's proactive pool
can take one now, and accept takes the recommendation a recommend exit leaves.`,
		newReactionCheckCmd(stdout, stderr),
		newReactionSlingCmd(stdout, stderr),
		newReactionSweepCmd(stdout, stderr),
		newReactionDeliverableCmd(stdout),
		newReactionDisposeCmd(stdout, stderr),
		newReactionAcceptCmd(stdout, stderr))
}

// reactionRefusals is the refusals check and sling apply, in their order, with
// their codes, for their help.
const reactionRefusals = `A first reaction triages a bead nobody has decided on, so a bead whose next
move is someone's already is refused, by the first of these that holds:

  6  its kind takes none: a standing record or a feedback pattern
  5  its status is not open, it is assigned, it is routed or armed, or it
     carries hold:mayor or hold:external
  3  an open conversation tracks it
  3  a first reaction already runs on it
  4  a live run of another formula works it
  5  an open human gate holds it, on the bead or on an ancestor

A read that does not answer decides nothing and exits 1.

--db names the store, a store's .beads directory. Without it the subject's
store is the one gc routes the bead to.`

const reactionCheckLong = `The first act of the reaction whose run is <root>: whether <bead> takes it. It
applies sling's refusals and writes nothing. The asking run is no second
reaction, and a gate under first-reaction whose message names <root> among its
words is the run's own, which it filed before it was re-offered, so both are
passed over.

` + reactionRefusals + ` Under the check that is no refusal either: ask again
once the store answers.

exit: 0 the bead takes this reaction
      3, 4, 5 or 6 a refusal: decline the run with the message as its reason
      1 decided nothing
      2 usage`

func newReactionCheckCmd(stdout, stderr io.Writer) *cobra.Command {
	var run, db string
	cmd := &cobra.Command{
		Use:   "check <bead> --run <root> [--db <path>]",
		Short: "whether this run of mol-first-reaction may still react to its subject",
		Long:  reactionCheckLong,
		Args:  cobra.ExactArgs(1),
		RunE: func(c *cobra.Command, args []string) error {
			const prog = "gctk reaction check"
			bead := strings.TrimSpace(args[0])
			if bead == "" {
				return errors.New("name the subject: gctk reaction check <bead> --run <root>")
			}
			if err := reaction.CheckRun(run); err != nil {
				return err
			}
			r, err := reactionFor(bead, db, stderr, prog)
			if err != nil {
				fmt.Fprintf(stderr, "%s: %v. The check decides nothing; ask again once the store answers\n", prog, err)
				return exit(1)
			}
			refusal, err := r.Check(bead, run)
			var use *reaction.UsageError
			switch {
			case errors.As(err, &use):
				return err
			case err != nil:
				fmt.Fprintf(stderr, "%s: %v. The check decides nothing; ask again once the store answers\n", prog, err)
				return exit(1)
			case refusal != nil:
				fmt.Fprintf(stderr, "%s: %s: %s\n", prog, bead, refusal.Why)
				return exit(refusal.Code)
			}
			fmt.Fprintf(stdout, "%s: %s takes this first reaction (run %s): no refusal holds\n", prog, bead, run)
			return nil
		},
	}
	cmd.Flags().StringVar(&run, "run", "", "the root of the asking reaction's run, the root_bead_id its react step's claim returned")
	cmd.Flags().StringVar(&db, "db", "", "the store, a store's .beads directory")
	return cmd
}

const reactionSlingLong = `Slings a first reaction on <bead>, a run of mol-first-reaction through the
rig's proactive pool, GC_RIG/gc-toolkit.proactive:

  gc sling --rig <rig> <rig>/gc-toolkit.proactive <bead> --on mol-first-reaction

unless a refusal holds. gc sling refuses a second live run of the formula on a
bead, and that refusal is 3.

` + reactionRefusals + ` So does an unset GC_RIG, a bead its store does not
hold, and a sling gc sling refuses for any other cause.

exit: 0 slung
      3, 4, 5 or 6 a refusal, nothing slung
      1 an error, nothing slung
      2 usage`

func newReactionSlingCmd(stdout, stderr io.Writer) *cobra.Command {
	var db string
	cmd := &cobra.Command{
		Use:   "sling <bead> [--db <path>]",
		Short: "sling a first reaction on a bead nobody has decided on",
		Long:  reactionSlingLong,
		Args:  cobra.ExactArgs(1),
		RunE: func(c *cobra.Command, args []string) error {
			const prog = "gctk reaction sling"
			bead := strings.TrimSpace(args[0])
			if bead == "" {
				return errors.New("name the subject: gctk reaction sling <bead>")
			}
			if strings.TrimSpace(os.Getenv("GC_RIG")) == "" {
				fmt.Fprintf(stderr, "%s: %v. No first reaction is slung\n", prog, reaction.ErrNoRig)
				return exit(1)
			}
			r, err := reactionFor(bead, db, stderr, prog)
			if err != nil {
				fmt.Fprintf(stderr, "%s: %v. No first reaction is slung\n", prog, err)
				return exit(1)
			}
			refusal, err := r.Sling(bead)
			switch {
			case err != nil:
				fmt.Fprintf(stderr, "%s: %v. No first reaction is slung\n", prog, err)
				return exit(1)
			case refusal != nil:
				fmt.Fprintf(stderr, "%s: %s: %s. No first reaction is slung\n", prog, bead, refusal.Why)
				return exit(refusal.Code)
			}
			fmt.Fprintf(stdout, "%s: slung a first reaction on %s\n", prog, bead)
			return nil
		},
	}
	cmd.Flags().StringVar(&db, "db", "", "the store, a store's .beads directory")
	return cmd
}

const reactionSweepLong = `Slings a first reaction at each bead in the rig's store that nobody has
decided on, highest priority first. Its one read is bd's ready set, unassigned
and not an epic. It keeps the raw input among it: a task, bug, feature or spike
with a description that is no workflow root, scope, spec or step, no standing
record, feedback pattern or review lane, carries no headline, no work marker
and no parent, has no route or arm, and carries no hold:mayor or hold:external.
It drops every bead a live run works, and a run map that does not read drops
nothing, which it says. Each sling applies sling's refusals again.

A slung run waits for a pool slot at no cost, so the sweep has no cap. It
starts no sling once less of its deadline is left than its slowest sling took,
each figure taken in whole seconds as its upper bound, and the next sweep takes
the rest. The deadline is GC_PROACTIVE_SWEEP_TIMEOUT, seconds alone or with an
s, m or h suffix, 300s when unset. A rig whose proactive pool cannot take a
reaction is skipped.

Each candidate gets one JSON line on stdout: its id, title, priority and
outcome, which is slung, refused (with the refusal's code and why), failed
(with why), or left for the next sweep. The summary on stderr counts each skip
by its cause. --dry-run slings nothing, and prints each candidate as
would-sling: its sling reads the refusals again.

--db names the store, a store's .beads directory. Without it the store is the
one gc resolves here.

exit: 0 swept, or no sweep in a rig whose pool cannot take a reaction
      1 nothing slung: the ready read or the candidate rule failed, GC_RIG is
        unset, or the deadline does not read
      2 usage`

func newReactionSweepCmd(stdout, stderr io.Writer) *cobra.Command {
	var db string
	var dryRun bool
	cmd := &cobra.Command{
		Use:   "sweep [--db <path>] [--dry-run]",
		Short: "sling a first reaction at each ready bead in the rig that nobody has decided on",
		Long:  reactionSweepLong,
		Args:  cobra.NoArgs,
		RunE: func(c *cobra.Command, args []string) error {
			const prog = "gctk reaction sweep"
			timeout := os.Getenv("GC_PROACTIVE_SWEEP_TIMEOUT")
			if timeout == "" {
				timeout = reaction.SweepTimeout
			}
			deadline, err := reaction.SweepDeadline(timeout)
			if err != nil {
				fmt.Fprintf(stderr, "%s: %v\n", prog, err)
				return exit(1)
			}
			rig := strings.TrimSpace(os.Getenv("GC_RIG"))
			if rig == "" {
				fmt.Fprintf(stderr, "%s: %v. No first reaction is slung\n", prog, reaction.ErrNoRig)
				return exit(1)
			}
			l, err := ledger.Open(db)
			if err != nil {
				fmt.Fprintf(stderr, "%s: could not open the store (%v). No first reaction is slung\n", prog, err)
				return exit(1)
			}
			r := &reaction.Reactions{Ledger: l, Runtime: gascity.New(), Rig: rig, Now: time.Now,
				Log: func(line string) { fmt.Fprintf(stderr, "%s: %s\n", prog, line) }}
			enc := json.NewEncoder(stdout)
			summary, err := r.Sweep(dryRun, deadline, func(s reaction.Swept) { _ = enc.Encode(s) })
			if err != nil {
				fmt.Fprintf(stderr, "%s: %v\n", prog, err)
				return exit(1)
			}
			fmt.Fprintf(stderr, "%s: %s\n", prog, summary)
			return nil
		},
	}
	cmd.Flags().StringVar(&db, "db", "", "the store, a store's .beads directory")
	cmd.Flags().BoolVar(&dryRun, "dry-run", false, "sling nothing, and print each candidate the sweep would sling")
	return cmd
}

const reactionDeliverableLong = `Whether the rig's proactive pool, GC_RIG/gc-toolkit.proactive, can take a
first reaction now. A slung reaction waits for a slot at no cost, but one routed
to a pool the city's roster shows absent, suspended or capped at zero waits for
nobody. No is a positive finding only: a roster that does not read answers yes,
since it is no evidence that the pool is gone. It prints yes or no, and why, on
stdout.

exit: 0 yes
      1 no`

func newReactionDeliverableCmd(stdout io.Writer) *cobra.Command {
	return &cobra.Command{
		Use:   "deliverable",
		Short: "whether this rig's proactive pool can take a first reaction now",
		Long:  reactionDeliverableLong,
		Args:  cobra.NoArgs,
		RunE: func(c *cobra.Command, args []string) error {
			rig := strings.TrimSpace(os.Getenv("GC_RIG"))
			if rig == "" {
				fmt.Fprintf(stdout, "no: %v\n", reaction.ErrNoRig)
				return exit(1)
			}
			r := &reaction.Reactions{Runtime: gascity.New(), Rig: rig}
			ok, why := r.ProactiveDeliverable()
			if !ok {
				fmt.Fprintf(stdout, "no: %s\n", why)
				return exit(1)
			}
			fmt.Fprintf(stdout, "yes: %s\n", why)
			return nil
		},
	}
}

// reactionFor is the reaction over bead's store, --db or else the one gc routes
// the bead to, in the caller's rig, saying each line to stderr.
func reactionFor(bead, db string, stderr io.Writer, prog string) (*reaction.Reactions, error) {
	l, err := ledger.Open(db, bead)
	if err != nil {
		return nil, fmt.Errorf("could not open %s's store (%v)", bead, err)
	}
	return &reaction.Reactions{Ledger: l, Runtime: gascity.New(), Rig: strings.TrimSpace(os.Getenv("GC_RIG")), DB: db, Now: time.Now,
		Log: func(line string) { fmt.Fprintf(stderr, "%s: %s\n", prog, line) }}, nil
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
store is the one gc routes the bead to.

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

// disposeReaction checks the call, opens the subject's store, --db or else the
// one gc routes the bead to, and takes the exit. The call's check and the exit
// share one runtime, so the rules that ask which rig owns a store read the
// city's rig list once between them.
func disposeReaction(d *reaction.Dispose, db string, stdout, stderr io.Writer) error {
	const prog = "gctk reaction dispose"
	rig := strings.TrimSpace(os.Getenv("GC_RIG"))
	rt := gascity.New()
	if err := reaction.Validate(rt, rig, d); err != nil {
		return err
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

const reactionAcceptLong = `Takes a first reaction's recommendation, gc.recommended_formula on <bead>:
it answers the human gate under the key first-reaction that puts the
recommendation to the operator, and nothing else, and dispatches the formula
at the bead, once. A sitting's sign-off runs it when the operator's ruling
takes the recommendation, with --conversation naming the sitting's own
conversation, which it then does not warn of as a live sitting on the bead,
and a --var for each var the ruling settled for the dispatch, such as
mol-design-convoy's design_gated=false.

It is offered while the bead carries the recommendation, its gate is open and
unassigned or closed with an acceptance an earlier Accept did not finish, and
no other open human gate blocks the bead. It runs under the bead's acceptance
lock, from before its live read of those three to its last write, and refuses
while another Accept holds it. Its first write removes the bead's arm (gctk
bead disarm). It records the acceptance's dispatch input on the gate (its
token, the formula and each --var), answers the gate
"ruled: accepted <formula> accept:<token>", and reads which answer the gate
took: bd's resolve exits 0 on a gate already closed, so that read tells this
answer from one that reached the gate first, and the first stands. It then
reads that no open human gate blocks the bead, slings the formula titled
"<formula> accept:<token>" with each --var, lifts the bead's hold:mayor, since
an Accept is a placement, and records the dispatch, withdrawing the
recommendation. A gate filed meanwhile, or a sling that poured nothing, opens
the gate again. A run that stopped after its answer leaves an unfinished
acceptance, which the next Accept finishes under the same token: it slings
only when no root carries the token, slings the vars the acceptance recorded,
and refuses a --var that differs from them.

<bead> may name the recommendation's gate, which names the one bead waiting on
it, or a conversation, which names the bead it tracks. A pull request's number
or URL, and a closed bead, name the live bead gc-helm.sh resolve names, which
needs GCTK_SCRIPTS_DIR. --db names the store, a store's .beads directory.
Without it the store is the one gc routes the bead to.

exit: 0 dispatched, or a dispatch an earlier Accept poured recorded
      1 the sling poured nothing, and the gate is open again
      2 usage, or the bead carries no recommendation
      3 the acceptance lock could not be taken
      4 refused, or a step did not land: the message says what did and what runs it again`

func newReactionAcceptCmd(stdout, stderr io.Writer) *cobra.Command {
	var req reaction.AcceptRequest
	var db string
	cmd := &cobra.Command{
		Use:   "accept <bead> [--reason <text>] [--conversation <task>] [--var <key>=<value>]... [--db <path>]",
		Short: "take a first reaction's recommendation: answer the gate that asks it and dispatch its formula at the bead, once",
		Long:  reactionAcceptLong,
		Args:  cobra.ExactArgs(1),
		RunE: func(_ *cobra.Command, args []string) error {
			const prog = "gctk reaction accept"
			ref := strings.TrimSpace(args[0])
			if ref == "" {
				return errors.New("name the bead: gctk reaction accept <bead>")
			}
			if err := reaction.CheckVars(req.Vars); err != nil {
				return acceptStopped(err, stderr, prog)
			}
			rt := gascity.New()
			if reaction.IsPRReference(ref) {
				id, err := reaction.Resolve(rt, ref)
				if err != nil {
					fmt.Fprintf(stderr, "%s: %v. Nothing dispatched\n", prog, err)
					return exit(4)
				}
				ref = id
			}
			r, err := acceptFor(ref, db, rt, stderr, prog)
			if err != nil {
				fmt.Fprintf(stderr, "%s: %v. Nothing dispatched\n", prog, err)
				return exit(4)
			}
			subject, err := r.Subject(ref)
			if err != nil {
				return acceptStopped(err, stderr, prog)
			}
			if db == "" && reactionPrefix(subject) != reactionPrefix(ref) {
				if r, err = acceptFor(subject, "", rt, stderr, prog); err != nil {
					fmt.Fprintf(stderr, "%s: %v. Nothing dispatched\n", prog, err)
					return exit(4)
				}
			}
			req.Bead = subject
			out, err := r.Accept(req)
			if err != nil {
				return acceptStopped(err, stderr, prog)
			}
			if out.Root != "" {
				fmt.Fprintf(stdout, "%s: acceptance %s had already dispatched %s at %s (root %s); recorded it, slinging nothing\n", prog, out.Token, out.Formula, subject, out.Root)
				return nil
			}
			fmt.Fprintf(stdout, "%s: dispatched %s at %s (acceptance %s)\n", prog, out.Formula, subject, out.Token)
			return nil
		},
	}
	f := cmd.Flags()
	f.StringVar(&req.Reason, "reason", "", "why the recommendation is taken, which the dispatch's note carries")
	f.StringVar(&req.Conversation, "conversation", "", "the conversation whose sitting's sign-off runs this Accept")
	f.StringArrayVar(&req.Vars, "var", nil, "a var the dispatch carries, <key>=<value>, repeatable")
	f.StringVar(&db, "db", "", "the store, a store's .beads directory")
	return cmd
}

// acceptFor builds the reaction's verbs for an acceptance on bead: its store,
// db or the one gc routes the bead to, the rig whose prefix begins its id,
// which the sling runs under, the arm's disarm, and the city's live sessions.
func acceptFor(bead, db string, rt *gascity.City, stderr io.Writer, prog string) (*reaction.Reactions, error) {
	l, err := ledger.Open(db, bead)
	if err != nil {
		return nil, fmt.Errorf("could not open %s's store (%v)", bead, err)
	}
	rig := strings.TrimSpace(os.Getenv("GC_RIG"))
	if name, _, err := rigOf(rt, bead); err == nil {
		rig = name
	}
	r := &reaction.Reactions{Ledger: l, Runtime: rt, Rig: rig, DB: db, Now: time.Now,
		Log: func(line string) { fmt.Fprintf(stderr, "%s: %s\n", prog, line) }}
	r.Disarm = func(id, reason string) (string, error) {
		a := &arm.Arms{Ledger: l, Runtime: rt, Now: time.Now, Actor: actor()}
		locks, err := arm.LockDir(rt)
		if err != nil {
			return "", err
		}
		a.Locks = locks
		said, err := a.Disarm(id, reason)
		if err == nil && strings.HasPrefix(said, "disarmed ") {
			fmt.Fprintf(stderr, "%s: %s\n", prog, said)
		}
		return said, err
	}
	r.Sessions = func() ([]gascity.Session, error) {
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		return rt.Sessions(ctx)
	}
	return r, nil
}

// acceptStopped prints why an acceptance went no further and gives its exit.
func acceptStopped(err error, stderr io.Writer, prog string) error {
	var u *reaction.Unaccepted
	if errors.As(err, &u) {
		fmt.Fprintf(stderr, "%s: %s\n", prog, u.Msg)
		return exit(u.Code)
	}
	fmt.Fprintf(stderr, "%s: %v\n", prog, err)
	return exit(4)
}

// reactionPrefix is the store prefix a bead's id begins with.
func reactionPrefix(id string) string {
	p, _, _ := strings.Cut(id, "-")
	return p
}
