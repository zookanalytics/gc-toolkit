package cli

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
)

// The verbs a review run's steps call: what a step judges, the check of the
// output it writes, and the head's comment its round posts.

const reviewStepLong = `Prints what a review run's step judges. <bead> is the step: its run, the PR
the run judges, its branch and target, the iteration the step runs in, the head
that iteration judges, and, for a step in the run's loop, the change triage
reads at that head (services/gctk/review/step.go): since the nearest earlier
head of the branch a run passed at for the target, else the run's own repair
since its first head, else the whole PR.

With --prepare it also refuses a run that must stop with no result: its vars do
not name the record the bead that owns the PR carries (its validated head, its
target and its branch), or GitHub's PR is not open from that branch into that
target at the run's head. A shadow run needs only the PR, its branch and its
head, since its bead may be on no record. --json prints one object.

exit: 0 printed
      1 usage
      2 a read did not answer: the store, git or GitHub
      3 refused: the bead is not a review run's step, or with --prepare the run
        must stop, and the command says why`

func newReviewStepCmd(stdout, stderr io.Writer) *cobra.Command {
	var db string
	var prepare, asJSON bool
	cmd := &cobra.Command{
		Use:         "step <bead> [--prepare] [--json]",
		Short:       "what a review run's step judges: its iteration, its head and the change triage reads",
		Long:        reviewStepLong,
		Args:        cobra.ExactArgs(1),
		Annotations: map[string]string{usageExitKey: "1"},
		RunE: func(_ *cobra.Command, args []string) error {
			bead := strings.TrimSpace(args[0])
			if bead == "" {
				return errors.New("name the step's bead")
			}
			return exit(reviewStep(bead, db, prepare, asJSON, stdout, stderr))
		},
	}
	cmd.Flags().StringVar(&db, "db", "", "the store's .beads directory, else the store gc routes the bead to")
	cmd.Flags().BoolVar(&prepare, "prepare", false, "refuse a run whose vars do not name the record or whose PR moved")
	cmd.Flags().BoolVar(&asJSON, "json", false, "print one JSON object")
	return cmd
}

// prReader reads a PR, the one GitHub read the step verb makes.
type prReader interface {
	PullRequest(repo string, number int) (*gh.PullRequest, error)
}

// prReaderFor is the reader of a PR on host, gh's by default.
var prReaderFor = func(host string) prReader { return gh.New(host) }

// stepFacts is what the step verb prints.
type stepFacts struct {
	Step      string `json:"step"`
	Ref       string `json:"ref"`
	Output    string `json:"output,omitempty"`
	Iteration int    `json:"iteration"`
	Run       string `json:"run"`
	PRBead    string `json:"pr_bead"`
	PR        string `json:"pr"`
	Branch    string `json:"branch"`
	Target    string `json:"target"`
	FirstHead string `json:"first_head"`
	Head      string `json:"head"`
	Shadow    bool   `json:"shadow"`
	Change    *struct {
		From string `json:"from,omitempty"`
		Head string `json:"head"`
		Why  string `json:"why"`
	} `json:"change,omitempty"`
}

func reviewStep(bead, db string, prepare, asJSON bool, stdout, stderr io.Writer) int {
	_, l, err := storeOf(db, bead)
	if err != nil {
		fmt.Fprintf(stderr, "gctk review step: the store did not answer: %v\n", err)
		return 2
	}
	return reviewStepIn(l, bead, prepare, asJSON, review.Repos(".", os.Getenv("GC_RIG_ROOT")), stdout, stderr)
}

func reviewStepIn(l *ledger.Ledger, bead string, prepare, asJSON bool, repos []string, stdout, stderr io.Writer) int {
	st, err := review.ReadStep(l, bead)
	var notRun *review.NotARun
	switch {
	case errors.As(err, &notRun):
		fmt.Fprintf(stderr, "gctk review step: %v\n", err)
		return 3
	case err != nil:
		fmt.Fprintf(stderr, "gctk review step: the store did not answer: %v\n", err)
		return 2
	}
	run := st.Run
	f := stepFacts{Step: st.ID, Ref: st.Ref, Output: st.Output, Iteration: st.Iteration, Run: run.Root,
		PRBead: run.PRBead, PR: st.PR(), Branch: st.Branch, Target: run.Target, FirstHead: run.Head,
		Head: run.Head, Shadow: run.Shadow}
	if prepare {
		if why := st.Mismatch(); why != "" {
			fmt.Fprintf(stderr, "gctk review step: run %s must stop with no result: %s\n", run.Root, why)
			return 3
		}
		host, repo, number, ok := record.ParseURL(st.PR())
		if !ok {
			fmt.Fprintf(stderr, "gctk review step: run %s must stop with no result: %q is not a PR's URL\n", run.Root, st.PR())
			return 3
		}
		pr, err := prReaderFor(host).PullRequest(repo, number)
		if err != nil {
			fmt.Fprintf(stderr, "gctk review step: GitHub did not answer for %s: %v\n", st.PR(), err)
			return 2
		}
		var why string
		switch {
		case pr.State != "OPEN":
			why = fmt.Sprintf("the PR is %s", strings.ToLower(pr.State))
		case pr.HeadRefOid != run.Head:
			why = fmt.Sprintf("the PR's head is %s, no longer the run's head %s", pr.HeadRefOid, run.Head)
		case pr.HeadRefName != st.Branch:
			why = fmt.Sprintf("the PR is from %s, not the branch %s", pr.HeadRefName, st.Branch)
		case pr.BaseRefName != run.Target:
			why = fmt.Sprintf("the PR merges into %s, not the run's target %s", pr.BaseRefName, run.Target)
		}
		if why != "" {
			fmt.Fprintf(stderr, "gctk review step: run %s must stop with no result: %s\n", run.Root, why)
			return 3
		}
	}
	if st.Iteration > 0 {
		f.Head = run.HeadOf(st.Iteration)
		ch, err := review.ChangeAt(run, st.Results, repos, f.Head)
		if err != nil {
			fmt.Fprintf(stderr, "gctk review step: the change at %s did not read: %v\n", f.Head, err)
			return 2
		}
		f.Change = &struct {
			From string `json:"from,omitempty"`
			Head string `json:"head"`
			Why  string `json:"why"`
		}{From: ch.From, Head: ch.Head, Why: ch.Why}
	}
	if asJSON {
		raw, _ := json.Marshal(f)
		fmt.Fprintln(stdout, string(raw))
		return 0
	}
	fmt.Fprintf(stdout, "step %s (%s)\n", f.Step, f.Ref)
	fmt.Fprintf(stdout, "run %s on %s, %s from %s into %s, first head %s\n", f.Run, f.PRBead, f.PR, f.Branch, f.Target, f.FirstHead)
	if f.Shadow {
		fmt.Fprintln(stdout, "shadow: the run writes nothing outside itself")
	}
	if st.Iteration > 0 {
		fmt.Fprintf(stdout, "iteration %d judges %s\n", f.Iteration, f.Head)
		ch := review.Change{From: f.Change.From, Head: f.Change.Head, Why: f.Change.Why}
		fmt.Fprintf(stdout, "change: %s\n", ch)
	}
	return 0
}

const reviewOutputLong = `Checks the output a review run's step wrote and prints it as Gas City keeps
it, the step's gc.output_json, which the step then writes. <bead> is the step,
and --file names the one JSON object it wrote in its shape
(services/gctk/review/run.go): triage, a lane or rule-and-repair, as its
review field says.

It fills in the iteration the step runs in and an empty list of picks,
findings or rulings, and refuses an output the run would read as not written
or as a slip: another step's shape, another iteration, another head, a pick or
a finding twice, a lane triage did not pick, a ruling of a finding no lane
raised or of an ask the round cannot take, a finding or an ask left unruled, a
must-fix with no fixing commit, a commit on a ruling that changes no code, a
question with no gate, and a fix for an ask an earlier round of the run
declined. A correctness lane's approve on a change that edits its own review
guidance (review-checks.toml, docs/review-*.md) is refused until needs_you
names the edit for the person who approves the merge, and when the paths
cannot be listed, needs_you says the edit is unchecked.

A shadow run's round fixes, pushes and files nothing, and its output carries
the comment it would have posted, which this renders, and each write it made
none of, the lines --writes names.

exit: 0 printed
      1 usage
      2 a read did not answer
      3 refused: the bead is not a step that writes an output, or the output
        does not stand, and the command says why`

func newReviewOutputCmd(stdout, stderr io.Writer) *cobra.Command {
	var db, file, writes string
	cmd := &cobra.Command{
		Use:         "output <bead> --file <path> [--writes <path>]",
		Short:       "check a review run's step output and print it as the store keeps it",
		Long:        reviewOutputLong,
		Args:        cobra.ExactArgs(1),
		Annotations: map[string]string{usageExitKey: "1"},
		RunE: func(_ *cobra.Command, args []string) error {
			bead := strings.TrimSpace(args[0])
			if bead == "" || file == "" {
				return errors.New("name the step's bead and --file, the output it wrote")
			}
			return exit(reviewOutput(bead, db, file, writes, stdout, stderr))
		},
	}
	cmd.Flags().StringVar(&db, "db", "", "the store's .beads directory, else the store gc routes the bead to")
	cmd.Flags().StringVar(&file, "file", "", "the JSON object the step wrote")
	cmd.Flags().StringVar(&writes, "writes", "", "for a shadow run's round, each write it made none of, one a line")
	return cmd
}

func reviewOutput(bead, db, file, writes string, stdout, stderr io.Writer) int {
	raw, err := os.ReadFile(file)
	if err != nil {
		fmt.Fprintf(stderr, "gctk review output: %v\n", err)
		return 1
	}
	var lines []string
	if writes != "" {
		text, err := os.ReadFile(writes)
		if err != nil && !errors.Is(err, os.ErrNotExist) {
			fmt.Fprintf(stderr, "gctk review output: %v\n", err)
			return 1
		}
		for _, w := range strings.Split(string(text), "\n") {
			if w = strings.TrimSpace(w); w != "" {
				lines = append(lines, w)
			}
		}
	}
	_, l, err := storeOf(db, bead)
	if err != nil {
		fmt.Fprintf(stderr, "gctk review output: the store did not answer: %v\n", err)
		return 2
	}
	return reviewOutputIn(l, review.OutputRequest{Step: bead, Raw: raw, Repos: review.Repos(".", os.Getenv("GC_RIG_ROOT")),
		Writes: lines}, stdout, stderr)
}

func reviewOutputIn(l *ledger.Ledger, req review.OutputRequest, stdout, stderr io.Writer) int {
	out, err := review.Output(l, req)
	var refused *review.Refused
	var notRun *review.NotARun
	switch {
	case errors.As(err, &refused), errors.As(err, &notRun):
		fmt.Fprintf(stderr, "gctk review output: %v; write it again\n", err)
		return 3
	case err != nil:
		fmt.Fprintf(stderr, "gctk review output: the store did not answer: %v\n", err)
		return 2
	}
	fmt.Fprintln(stdout, string(out))
	return 0
}

const reviewCommentLong = `Prints the head's comment for an iteration of a review run: its mark, which
names the run and the head, each lane's verdict, approvals included, each
finding a lane raised with how the round ruled it and what the head carries for
it, and each ask the round took (services/gctk/review/comment.go). <run> is the
run's root, or any bead poured under it. It renders --iteration, else the
latest iteration whose round wrote its rulings, and prints nothing when that
iteration has nothing to answer: no lane ran there and the round took no ask.

exit: 0 printed, nothing included
      1 usage
      2 a read did not answer
      3 refused: the bead is not a review run, or the iteration's round has not
        written its rulings`

func newReviewCommentCmd(stdout, stderr io.Writer) *cobra.Command {
	var db string
	var iteration int
	cmd := &cobra.Command{
		Use:         "comment <run> [--iteration <n>]",
		Short:       "the head's comment for an iteration of a review run",
		Long:        reviewCommentLong,
		Args:        cobra.ExactArgs(1),
		Annotations: map[string]string{usageExitKey: "1"},
		RunE: func(_ *cobra.Command, args []string) error {
			run := strings.TrimSpace(args[0])
			if run == "" {
				return errors.New("name the review run")
			}
			if iteration < 0 {
				return fmt.Errorf("--iteration %d names no iteration", iteration)
			}
			_, l, err := storeOf(db, run)
			if err != nil {
				fmt.Fprintf(stderr, "gctk review comment: the store did not answer: %v\n", err)
				return exit(2)
			}
			return exit(reviewCommentIn(l, run, iteration, stdout, stderr))
		},
	}
	cmd.Flags().StringVar(&db, "db", "", "the store's .beads directory, else the store gc routes the run to")
	cmd.Flags().IntVar(&iteration, "iteration", 0, "the iteration to render, from 1, else the latest with rulings")
	return cmd
}

func reviewCommentIn(l *ledger.Ledger, id string, n int, stdout, stderr io.Writer) int {
	run, err := review.ReadRun(l, id)
	var notRun *review.NotARun
	switch {
	case errors.As(err, &notRun):
		fmt.Fprintf(stderr, "gctk review comment: %v\n", err)
		return 3
	case err != nil:
		fmt.Fprintf(stderr, "gctk review comment: the store did not answer: %v\n", err)
		return 2
	}
	if n == 0 {
		for m, it := range run.Iterations {
			if it.Repair != nil && m > n {
				n = m
			}
		}
	}
	if it := run.Iterations[n]; n == 0 || it == nil || it.Repair == nil {
		fmt.Fprintf(stderr, "gctk review comment: iteration %d of %s has no rulings yet\n", n, run.Root)
		return 3
	}
	asks, err := review.AsksOn(l, run.PRBead)
	if err != nil {
		fmt.Fprintf(stderr, "gctk review comment: the store did not answer: %v\n", err)
		return 2
	}
	fmt.Fprint(stdout, review.Comment(run, n, asks))
	return 0
}
