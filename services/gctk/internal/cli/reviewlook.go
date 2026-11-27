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

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/feedback"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/git"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
)

// `gctk review look <step>` is the fresh look's read and record, which the
// look's step (formulas/mol-pr-review-look.toml) calls.

const reviewLookLong = `A review run's fresh look (services/gctk/review/look.go): what it reads, and
the record of what it wrote. <step> is the look's step, the bead gc hook current
names in the look's session.

With no --file it prints what the look judges from: the account of the run's
rounds up to the look's in one line, and whether the rule forces a question
there; every round of the run, with each finding a lane raised, its ruling and
the earlier finding it restates; the PR's other review runs, with their counts
and how each ended; each commit that changed the review's rules since the PR's
first run was poured, the rig's AGENTS.md, CLAUDE.md, review-checks.toml and
docs/review-*.md on origin's copy of the target and the pack's skills/review-*
and formulas/mol-pr-review*.toml; the commands that read the PR's change; and
the shape of the output.

With --file it checks the output the look wrote there and records it. The
output is one JSON object: review reading look, the head the round judged, a
verdict of continue or stop, the reading, and for a stop the recommendation and
the question. It is refused when the round called for no look, at another head,
with no reading, for a stop without its question or its recommendation, for a
continue at the run's last round by its bound, for a continue at a round the
account forces a question at that names no rule as the cause, and for a rule
that is not a full object name. A stop's question goes to a human gate on the
bead that owns the PR under review-question-not-converging (human-gate.sh, from
the scripts directory GCTK_SCRIPTS_DIR names), filed or found open there. The
step takes the look as its gc.output_json, and for a stop gc.failure_class hard
with its gc.failure_reason, so the loop ends at the round once the step closes
with gc.outcome fail. The bead that owns the PR is then noted with the look. A
record run again files no second gate and writes the same output, and notes the
look once more.

exit: 0 printed, or recorded
      1 a write did not land: what landed stands, and a record run again makes
        the rest
      2 a read did not answer
      3 refused: the bead is not a fresh look, or its output does not stand
      64 usage`

func newReviewLookCmd(stdout, stderr io.Writer) *cobra.Command {
	var db, file string
	cmd := &cobra.Command{
		Use:         "look <step> [--file <path>]",
		Short:       "a review run's fresh look: what it reads, and with --file the record of what it wrote",
		Long:        reviewLookLong,
		Args:        cobra.ExactArgs(1),
		Annotations: map[string]string{usageExitKey: "64"},
		RunE: func(_ *cobra.Command, args []string) error {
			bead := strings.TrimSpace(args[0])
			if bead == "" {
				return errors.New("name the look's step")
			}
			var raw []byte
			if file != "" {
				var err error
				if raw, err = os.ReadFile(file); err != nil {
					fmt.Fprintf(stderr, "gctk review look: %v\n", err)
					return exit(64)
				}
			}
			_, l, err := storeOf(db, bead)
			if err != nil {
				fmt.Fprintf(stderr, "gctk review look: the store did not answer: %v\n", err)
				return exit(2)
			}
			repos := review.Repos(".", os.Getenv("GC_RIG_ROOT"))
			if file == "" {
				return exit(reviewLookRead(l, bead, repos, packRoot(), stdout, stderr))
			}
			req := review.OutputRequest{Step: bead, Raw: raw, Repos: repos}
			return exit(reviewLookRecord(l, req, gates{gascity.New()}, time.Now(), stdout, stderr))
		},
	}
	cmd.Flags().StringVar(&db, "db", "", "the store's .beads directory, else the store gc routes the bead to")
	cmd.Flags().StringVar(&file, "file", "", "the JSON object the look wrote, to check and record")
	return cmd
}

// packRoot is the pack's checkout, two directories above its scripts
// directory, "" when that directory cannot be found.
func packRoot() string {
	dir, err := feedback.ScriptsDir()
	if err != nil {
		return ""
	}
	return filepath.Join(dir, "..", "..")
}

// reviewLookRead prints what the look bead names reads over l, with the rules
// that changed read in the first of repos that holds the round's head and in
// pack.
func reviewLookRead(l *ledger.Ledger, bead string, repos []string, pack string, stdout, stderr io.Writer) int {
	rd, err := review.ReadLook(l, bead)
	var notRun *review.NotARun
	switch {
	case errors.As(err, &notRun):
		fmt.Fprintf(stderr, "gctk review look: %v\n", err)
		return 3
	case err != nil:
		fmt.Fprintf(stderr, "gctk review look: the store did not answer: %v\n", err)
		return 2
	}
	since, err := rd.Since(l)
	if err != nil {
		fmt.Fprintf(stderr, "gctk review look: the store did not answer: %v\n", err)
		return 2
	}
	run := rd.Step.Run
	head := run.HeadOf(rd.Step.Iteration)
	if it := run.Iterations[rd.Step.Iteration]; it != nil && it.Triage != nil {
		head = it.Triage.Head
	}
	repo := ""
	for _, r := range repos {
		if git.HasCommit(r, head) {
			repo = r
			break
		}
	}
	rules, err := review.RulesChanged(repo, pack, run.Target, since)
	if err != nil {
		fmt.Fprintf(stderr, "gctk review look: %v\n", err)
		return 2
	}
	rd.Print(stdout, rules, since, repo)
	return 0
}

// reviewLookRecord records the look req names over l, with filer filing a
// stop's question, and says what it did.
func reviewLookRecord(l *ledger.Ledger, req review.OutputRequest, filer review.Gates, at time.Time, stdout, stderr io.Writer) int {
	got, err := review.RecordLook(l, req, filer, at)
	var refused *review.Refused
	var notRun *review.NotARun
	var unrecorded *review.LookUnrecorded
	switch {
	case errors.As(err, &refused), errors.As(err, &notRun):
		fmt.Fprintf(stderr, "gctk review look: %v; write it again\n", err)
		return 3
	case errors.As(err, &unrecorded):
		fmt.Fprintf(stderr, "gctk review look: %v; run it again\n", err)
		return 1
	case err != nil:
		fmt.Fprintf(stderr, "gctk review look: the store did not answer: %v\n", err)
		return 2
	}
	lk := got.Look
	if lk.Verdict == review.LookStop {
		fmt.Fprintf(stdout, "%s: the look at round %d stops the review for a person's answer through %s\n", got.Step,
			lk.Iteration, firstOr(got.Gate, "a gate the store did not show yet"))
		fmt.Fprintf(stdout, "%s: marked failed hard, so the loop ends at round %d once the step closes with --outcome fail\n",
			got.Step, lk.Iteration)
	} else {
		fmt.Fprintf(stdout, "%s: the look at round %d sends the review on\n", got.Step, lk.Iteration)
	}
	fmt.Fprintf(stdout, "%s: noted the look\n", got.Bead)
	return 0
}
