package cli

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/feedback"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/git"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
)

// `gctk review` is the review domain (docs/gctk-architecture.md, "The
// surface"): the check index at a commit, a review run's pass rule, its result
// and the asks it works. Each command builds what it reads over the adapters
// and prints the domain's answer.

func newReviewCmd(stdout, stderr io.Writer) *cobra.Command {
	return group("review", "a PR's review: the check index, a review run's pass rule, its result and its asks",
		"The review of a PR: which checks gate a change at a commit, with the rig's index laid over the pack's, "+
			"and the rig's guidance for each; whether an iteration of a review run passed; the result a run records "+
			"for the head and the target it judged; and the asks a run works on the PR's branch.",
		newReviewChecksCmd(stdout, stderr), newReviewGuidanceCmd(stdout, stderr),
		newReviewPassedCmd(stdout, stderr), newReviewRecordCmd(stdout, stderr), newReviewAskCmd(stdout, stderr))
}

const reviewChecksLong = `Prints the check index: every check a commit's review can run, with the rig's
index at the commit laid over the pack's (services/gctk/review/index.go).

With no form named, or --show, it prints the effective index as TSV, one row per
check, <name>\t<purpose>\t<phase>, leaving out a row whose phase is outside the
ordered set and naming it on stderr. --check <name> prints that one row, the
check known by its name without case. --resolve <set> --through <phase> prints
the checks of the check_set <set> that gate the transition <phase>, one per
line, or <name>\t<phase> with --with-phase: every check whose phase is at or
before it, each token as the set writes it, none, off and approval dropped, and
a token no layer declares at pre-open.

The rig's rows come from the review-checks.toml the commit --at names carries,
read in the checkout the command runs in or GC_RIG_ROOT's, fetched from origin
by id when neither holds it, and never from a working tree. The pack's rows are
the review-checks.toml at the root of the pack, two directories above
GCTK_SCRIPTS_DIR, else above the scripts directory gc names. --file <index>, or
GC_REVIEW_CHECKS_INDEX, names the whole effective index outright and stands in
for both layers, so a call that names one needs no commit.

Phases, in order: pre-open, open-as-draft, ready-for-review, merge.

exit: 0 printed
      1 the commit --at names cannot be read (no repository here holds or can
        fetch it, or there is no repository here), the rig's index there does
        not read, --check names a check no layer declares or one whose phase is
        outside the ordered set, a resolved check's phase is outside it, the
        pack's index cannot be found, or the index declares no check
      2 usage, a call that names no commit, included`

func newReviewChecksCmd(stdout, stderr io.Writer) *cobra.Command {
	var at, file, check, set, through string
	var show, withPhase bool
	cmd := &cobra.Command{
		Use:   "checks [--at <oid>] [--file <index>] [--show | --check <name> | --resolve <set> --through <phase> [--with-phase]]",
		Short: "the check index at a commit, with the rig's index laid over the pack's",
		Long:  reviewChecksLong,
		Args:  cobra.NoArgs,
		RunE: func(c *cobra.Command, _ []string) error {
			resolve := c.Flags().Changed("resolve")
			switch {
			case resolve && (show || c.Flags().Changed("check")):
				return errors.New("--resolve, --show and --check are different calls; name one")
			case !resolve && (c.Flags().Changed("through") || withPhase):
				return errors.New("--through and --with-phase go with --resolve")
			case resolve && review.PhaseRank(through) == 0:
				return fmt.Errorf("--resolve needs --through <phase>, one of %s (got %q)", review.Phases(), through)
			}
			src, err := indexSources(file)
			if err != nil {
				fmt.Fprintf(stderr, "gctk review checks: %v\n", err)
				return exit(1)
			}
			if src.Named == "" && at == "" {
				return errors.New("no commit named (--at is missing or empty) and no index named (--file, GC_REVIEW_CHECKS_INDEX); a rig's rows are read only at the commit being judged")
			}
			return exit(reviewChecks(src, at, check, set, through, resolve, withPhase, stdout, stderr))
		},
	}
	f := cmd.Flags()
	f.StringVar(&at, "at", "", "the commit whose index the rig's rows come from")
	f.StringVar(&file, "file", "", "an index named outright, which stands in for both layers")
	f.BoolVar(&show, "show", false, "print every row of the effective index (the default)")
	f.StringVar(&check, "check", "", "print the one row of this check")
	f.StringVar(&set, "resolve", "", "print the checks of this check_set that gate --through")
	f.StringVar(&through, "through", "", "the transition --resolve gates")
	f.BoolVar(&withPhase, "with-phase", false, "print each resolved check with the phase it gates at")
	return cmd
}

func reviewChecks(src review.IndexSources, at, check, set, through string, resolve, withPhase bool, stdout, stderr io.Writer) int {
	warn := func(lines []string) {
		for _, l := range lines {
			fmt.Fprintf(stderr, "gctk review checks: %s\n", l)
		}
	}
	ix, err := review.ReadIndex(src, at)
	if err != nil {
		fmt.Fprintf(stderr, "gctk review checks: %v\n", err)
		return 1
	}
	if resolve {
		gates, warnings, err := ix.Resolve(set, through)
		warn(warnings)
		if err != nil {
			fmt.Fprintf(stderr, "gctk review checks: %v\n", err)
			return 1
		}
		for _, g := range gates {
			if withPhase {
				fmt.Fprintf(stdout, "%s\t%s\n", g.Name, g.Phase)
			} else {
				fmt.Fprintln(stdout, g.Name)
			}
		}
		return 0
	}
	if len(ix.Checks) == 0 {
		switch {
		case ix.Source != "":
			fmt.Fprintf(stderr, "gctk review checks: '%s' declares no checks\n", ix.Source)
		case src.Named != "":
			fmt.Fprintf(stderr, "gctk review checks: no readable index at '%s'\n", src.Named)
		default:
			fmt.Fprintln(stderr, "gctk review checks: no readable check index")
		}
		return 1
	}
	if check != "" {
		c, ok := ix.Lookup(check)
		if !ok {
			fmt.Fprintf(stderr, "gctk review checks: '%s' does not declare check '%s'\n", ix.Source, check)
			return 1
		}
		phase, warning, err := ix.PhaseOf(c)
		if err != nil {
			fmt.Fprintf(stderr, "gctk review checks: %v\n", err)
			return 1
		}
		if warning != "" {
			warn([]string{warning})
		}
		fmt.Fprintf(stdout, "%s\t%s\t%s\n", c.Name, c.Purpose, phase)
		return 0
	}
	rows, warnings := ix.Rows()
	warn(warnings)
	for _, r := range rows {
		fmt.Fprintf(stdout, "%s\t%s\t%s\n", r.Name, r.Purpose, r.Phase)
	}
	return 0
}

// indexSources is where the index is read: the index --file names, else the
// one GC_REVIEW_CHECKS_INDEX names, else the pack's beside the scripts
// directory, with the checkout the command runs in and GC_RIG_ROOT's as the
// repositories a commit is read in.
func indexSources(file string) (review.IndexSources, error) {
	src := review.IndexSources{Named: file, Repos: review.Repos(".", os.Getenv("GC_RIG_ROOT"))}
	if src.Named == "" {
		src.Named = os.Getenv("GC_REVIEW_CHECKS_INDEX")
	}
	if src.Named != "" {
		return src, nil
	}
	dir, err := feedback.ScriptsDir()
	if err != nil {
		return src, fmt.Errorf("the pack's index cannot be found: %w", err)
	}
	src.Pack = filepath.Join(dir, "..", "..", "review-checks.toml")
	return src, nil
}

const reviewGuidanceLong = `Prints the rig's guidance for a check at a commit: the docs/review-<check>.md
the commit --at names carries, <check> folded to lowercase, read in the checkout
the command runs in or GC_RIG_ROOT's and fetched from origin by id when neither
holds it. A commit that carries none prints nothing, the common case.

With --edits --base <branch> in place of a check, it prints the rig's review
guidance the change at --at edits, one path per line: review-checks.toml and
each docs/review-*.md among the paths the change touches from where it left
<branch> on origin, a file renamed away included.

exit: 0 printed, nothing included
      1 the commit cannot be read, the guidance there does not read, or the
        paths the change touches cannot be listed
      2 usage`

func newReviewGuidanceCmd(stdout, stderr io.Writer) *cobra.Command {
	var at, base string
	var edits bool
	cmd := &cobra.Command{
		Use:   "guidance (<check> | --edits --base <branch>) --at <oid>",
		Short: "the rig's guidance for a check at the reviewed commit, or the guidance a change edits",
		Long:  reviewGuidanceLong,
		Args:  cobra.MaximumNArgs(1),
		RunE: func(c *cobra.Command, args []string) error {
			if at == "" {
				return errors.New("--at <oid> names the commit whose guidance is read")
			}
			src := review.IndexSources{Repos: review.Repos(".", os.Getenv("GC_RIG_ROOT"))}
			if edits {
				if len(args) > 0 {
					return errors.New("--edits names no check")
				}
				if !git.ValidBranch(base) {
					return fmt.Errorf("--edits takes --base <branch>, the branch the change left, got %q", base)
				}
				return exit(reviewGuidanceEdits(src, base, at, stdout, stderr))
			}
			if c.Flags().Changed("base") {
				return errors.New("--base goes with --edits")
			}
			if len(args) != 1 || !review.ValidName(args[0]) {
				return fmt.Errorf("name the check whose guidance is read ([A-Za-z0-9_-]+), got %q", strings.Join(args, " "))
			}
			return exit(reviewGuidance(src, args[0], at, stdout, stderr))
		},
	}
	cmd.Flags().StringVar(&at, "at", "", "the commit whose guidance is read")
	cmd.Flags().BoolVar(&edits, "edits", false, "print the guidance the change at --at edits")
	cmd.Flags().StringVar(&base, "base", "", "with --edits, the branch the change left")
	return cmd
}

func reviewGuidance(src review.IndexSources, check, at string, stdout, stderr io.Writer) int {
	text, err := review.Guidance(src, check, at)
	if err != nil {
		fmt.Fprintf(stderr, "gctk review guidance: %v\n", err)
		return 1
	}
	if text = strings.TrimRight(text, "\n"); text != "" {
		fmt.Fprintln(stdout, text)
	}
	return 0
}

func reviewGuidanceEdits(src review.IndexSources, base, at string, stdout, stderr io.Writer) int {
	paths, err := review.GuidanceEdits(src, base, at)
	if err != nil {
		fmt.Fprintf(stderr, "gctk review guidance: %v\n", err)
		return 1
	}
	for _, p := range paths {
		fmt.Fprintln(stdout, p)
	}
	return 0
}

const reviewPassedLong = `The pass rule of a review run's loop, run as the loop's check after each
iteration. <run> is the run's root, or any bead poured under it, such as the
iteration the check runs for. It judges --iteration, else the latest iteration
any step wrote for, from what the run's steps wrote as their outputs
(services/gctk/review/run.go) and the asks open on the bead that owns the PR.

The iteration passes when triage wrote the head it judged, every lane triage
bonded wrote its verdict at that head, rule-and-repair ruled every finding and
every ask it took, ruled nothing must-fix and pushed nothing, and every ask open
on the bead that nothing holds is one the round took, with each check it sends
back run at that head. An ask that something holds, by gctk bead holds, counts
for nothing. Each finding or ask an earlier iteration ruled must-fix must name
the commit that fixes it. A finding declined by its lane's rule counts as
ruled, and so does a question put to a person through a gate.

It reads only the store. It prints the verdict and each reason the iteration
did not pass, and with --explain the iteration's lanes, verdicts, findings and
rulings and the asks on the bead.

exit: 0 passed
      1 not yet: the next iteration runs
      75 the store did not answer, so there is no verdict`

func newReviewPassedCmd(stdout, stderr io.Writer) *cobra.Command {
	var db string
	var iteration int
	var explain bool
	cmd := &cobra.Command{
		Use:   "passed <run> [--iteration <n>] [--explain]",
		Short: "whether an iteration of a review run passed: its loop's check",
		Long:  reviewPassedLong,
		Args:  cobra.ExactArgs(1),
		RunE: func(_ *cobra.Command, args []string) error {
			run := strings.TrimSpace(args[0])
			if run == "" {
				return errors.New("name the review run")
			}
			if iteration < 0 {
				return fmt.Errorf("--iteration %d names no iteration", iteration)
			}
			return exit(reviewPassed(run, db, iteration, explain, stdout, stderr))
		},
	}
	cmd.Flags().StringVar(&db, "db", "", "the store's .beads directory, else the store gc routes the run to")
	cmd.Flags().IntVar(&iteration, "iteration", 0, "the iteration to judge, from 1, else the latest")
	cmd.Flags().BoolVar(&explain, "explain", false, "print the iteration's lanes, verdicts, findings and rulings")
	return cmd
}

// passedNoVerdict is the check's exit when the store did not answer, which
// re-runs it without spending an attempt.
const passedNoVerdict = 75

func reviewPassed(run, db string, n int, explain bool, stdout, stderr io.Writer) int {
	l, err := ledger.Open(db, run)
	if err != nil {
		fmt.Fprintf(stderr, "gctk review passed: the store did not answer: %v\n", err)
		return passedNoVerdict
	}
	return passedIn(l, run, n, explain, stdout, stderr)
}

// passedIn is the check's exit for the run over l.
func passedIn(l *ledger.Ledger, run string, n int, explain bool, stdout, stderr io.Writer) int {
	v, err := review.Passed(l, run, n)
	var notRun *review.NotARun
	switch {
	case errors.As(err, &notRun):
		fmt.Fprintf(stderr, "gctk review passed: %v\n", err)
		return 1
	case err != nil:
		fmt.Fprintf(stderr, "gctk review passed: the store did not answer: %v\n", err)
		return passedNoVerdict
	}
	if explain {
		fmt.Fprint(stdout, v.Explain())
	} else if v.Passed {
		fmt.Fprintf(stdout, "passed: iteration %d of %s\n", v.Iteration, v.Run.Root)
	} else {
		fmt.Fprintf(stdout, "not yet: iteration %d of %s\n", v.Iteration, v.Run.Root)
		for _, r := range v.Reasons {
			fmt.Fprintf(stdout, "  - %s\n", r)
		}
	}
	if v.Passed {
		return 0
	}
	return 1
}

const reviewRecordLong = `Records a review run's result: for the last head the run judged and the run's
target, {head, target, passed} in review_results on the bead that owns the PR,
replacing the entry for the same head and target, under the store's record
lock. <run> is the run's root, or any bead poured under it.

The result passes only when the run's loop passed its check at that head and no
gate the run put a question to is open. A loop that exhausted its attempts gets
a result that does not pass, and the command says so. A loop that a step's hard
failure ended (gc.final_disposition=hard_fail), one that ended any other way,
and a run that judged no head get no result.

It then closes each ask the round at that head answered, ruled declined,
deferred or answered, with its work record: shipped with the commit of the
run's must-fix ruling of it, else no-op. A shadow run (its shadow var reads
true) writes nothing, and the command prints what it would have written.

exit: 0 recorded, or the run has no result to record
      1 usage
      2 a read, the lock or a write did not answer; the command says which
        landed, and a retry replaces the same entry
      3 refused: the bead is not a review run, or its loop has not closed`

func newReviewRecordCmd(stdout, stderr io.Writer) *cobra.Command {
	var db string
	cmd := &cobra.Command{
		Use:         "record <run>",
		Short:       "record a review run's result for the head and target it judged",
		Long:        reviewRecordLong,
		Args:        cobra.ExactArgs(1),
		Annotations: map[string]string{usageExitKey: "1"},
		RunE: func(_ *cobra.Command, args []string) error {
			run := strings.TrimSpace(args[0])
			if run == "" {
				return errors.New("name the review run")
			}
			return exit(reviewRecord(run, db, stdout, stderr))
		},
	}
	cmd.Flags().StringVar(&db, "db", "", "the store's .beads directory, else the store gc routes the run to")
	return cmd
}

func reviewRecord(run, db string, stdout, stderr io.Writer) int {
	db, l, err := storeOf(db, run)
	if err != nil {
		fmt.Fprintf(stderr, "gctk review record: %v\n", err)
		return 2
	}
	got, err := review.Record(l, db, recordLockWait, run)
	var notRun *review.NotARun
	switch {
	case errors.As(err, &notRun), review.IsUnfinished(err):
		fmt.Fprintf(stderr, "gctk review record: %v; nothing written\n", err)
		return 3
	case err != nil && (got == nil || got.Result == nil):
		fmt.Fprintf(stderr, "gctk review record: %v; nothing written\n", err)
		return 2
	case err != nil:
		fmt.Fprintf(stderr, "gctk review record: %s: the result landed (%s): %v\n", got.Bead, got.Result, err)
		return 2
	}
	switch {
	case got.Result == nil:
		fmt.Fprintf(stdout, "%s: no result: %s\n", got.Bead, got.NoResult)
		return 0
	case got.Shadow:
		fmt.Fprintf(stdout, "%s: shadow run, nothing written: the result would read %s\n", got.Bead, got.Result)
	default:
		fmt.Fprintf(stdout, "%s: review %s\n", got.Bead, got.Result)
	}
	if got.Exhausted {
		fmt.Fprintf(stdout, "%s: the loop exhausted its attempts at %s\n", got.Bead, got.Result.Head)
	}
	for _, g := range got.Open {
		fmt.Fprintf(stdout, "%s: gate %s is open\n", got.Bead, g)
	}
	for _, a := range got.Closed {
		verb := "closed"
		if got.Shadow {
			verb = "would close"
		}
		fmt.Fprintf(stdout, "%s: %s ask %s, %s (%s%s)\n", got.Bead, verb, a.ID, a.Ruling, a.Outcome, commitSuffix(a.Commit))
	}
	return 0
}

func commitSuffix(commit string) string {
	if commit == "" {
		return ""
	}
	return " " + commit
}

const reviewAskLong = `Files an ask on the bead that owns a PR: a request for a change on the PR's
branch, or for a check at its next head, which the review run works. The ask is
a task bead with no parent, no route and no assignee, which blocks the bead by
its own edge, names the PR's branch in branch, carries --reason as its
description, a discovered-from edge onto --source when one is named, and the
checks it sends back in review_checks, each from the check index at the head the
refinery validated.

Before it files, it finds an ask on the bead of the same source and reason,
open or closed, and files nothing when one stands, so a filer that runs again
after its ask closed files nothing. It refuses a bead that owns no PR on the
record, and a check the index does not declare. It prints <ask> filed, or
<ask> found.

exit: 0 the ask stands: filed, or found
      1 usage
      2 a read did not answer, or the create did not, and may have filed the
        ask, which the next call finds
      3 refused, and nothing was filed`

func newReviewAskCmd(stdout, stderr io.Writer) *cobra.Command {
	var db, reason, source string
	var checks []string
	cmd := &cobra.Command{
		Use:         "ask <bead> --reason <text> [--check <name>]... [--source <bead>]",
		Short:       "file an ask on the bead that owns a PR, for its review run to work",
		Long:        reviewAskLong,
		Args:        cobra.ExactArgs(1),
		Annotations: map[string]string{usageExitKey: "1"},
		RunE: func(_ *cobra.Command, args []string) error {
			bead := strings.TrimSpace(args[0])
			if bead == "" {
				return errors.New("name the bead that owns the PR")
			}
			if strings.TrimSpace(reason) == "" {
				return errors.New("--reason says what the ask asks")
			}
			for _, c := range checks {
				if !review.ValidName(c) {
					return fmt.Errorf("--check %q is not a check's name ([A-Za-z0-9_-]+)", c)
				}
			}
			req := review.AskRequest{Bead: bead, Reason: reason, Source: strings.TrimSpace(source), Checks: checks}
			return exit(reviewAsk(req, db, stdout, stderr))
		},
	}
	cmd.Flags().StringVar(&reason, "reason", "", "what the ask asks, and why")
	cmd.Flags().StringArrayVar(&checks, "check", nil, "a check the ask sends back, once per check")
	cmd.Flags().StringVar(&source, "source", "", "the bead whose ruling or finding the ask carries")
	cmd.Flags().StringVar(&db, "db", "", "the store's .beads directory, else the store gc routes the bead to")
	return cmd
}

func reviewAsk(req review.AskRequest, db string, stdout, stderr io.Writer) int {
	_, l, err := storeOf(db, req.Bead)
	if err != nil {
		fmt.Fprintf(stderr, "gctk review ask: %v; nothing filed\n", err)
		return 2
	}
	index := func(at string) (review.Index, error) {
		src, err := indexSources("")
		if err != nil {
			return review.Index{}, err
		}
		return review.ReadIndex(src, at)
	}
	id, filed, err := review.FileAsk(l, req, index)
	var refused *review.Refusal
	switch {
	case errors.As(err, &refused):
		fmt.Fprintf(stderr, "gctk review ask: %v\n", err)
		return 3
	case err != nil:
		fmt.Fprintf(stderr, "gctk review ask: %s: %v\n", req.Bead, err)
		return 2
	case filed:
		fmt.Fprintf(stdout, "%s filed\n", id)
	default:
		fmt.Fprintf(stdout, "%s found\n", id)
	}
	return 0
}

// storeOf is the store db names, else the one gc routes id to, and a ledger
// over it.
func storeOf(db, id string) (string, *ledger.Ledger, error) {
	if db == "" {
		routed, err := gcbd.New().Route(id)
		if err != nil {
			return "", nil, err
		}
		db = routed
	}
	l, err := ledger.Open(db)
	if err != nil {
		return "", nil, err
	}
	return db, l, nil
}
