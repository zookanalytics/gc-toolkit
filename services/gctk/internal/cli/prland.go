package cli

import (
	"errors"
	"fmt"
	"io"
	"os"
	"strings"
	"time"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/git"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
)

// `gctk pr record <bead>` and `gctk pr reconcile` are the two writers of Gas
// Town's pending-through-merge record (specs/tk-1tfzr71.66/design.md, sections
// 4 and 6): the refinery publishes a PR's record, and the landing order's runs
// read it on a cooldown (orders/pr-reconcile.toml). Each command builds the pr
// domain's Landing over the adapters and prints what it did.

// recordLockWait is how long either verb waits for the store's record lock. A
// run of the landing order holds it for one record at a time, and its order's
// time limit ends any run, which frees the lock, sooner than this.
const recordLockWait = 5 * time.Minute

// runYield is how long a run leaves the lock free between two records, so a
// publication waiting for it takes it there.
const runYield = 200 * time.Millisecond

// The run's bounds: how many records a run reads, and how long it starts new
// ones. A record whose PR is open at the validated head costs about seven
// seconds, measured on 2026-11-12: five for the PR's read and the evaluator's
// six GitHub reads, and two for the store's reads and the write. Twenty of them
// fit inside the order's 300-second time limit with room for GitHub answering
// at half that speed, and the budget starts none in the last minute. A cycle
// over 50 open records then takes three runs.
const (
	defaultRunCount  = 20
	defaultRunBudget = 4 * time.Minute
)

const prRecordLong = `Records the pull request a bead owns as pending until its merge is verified,
in Gas Town's two writes: first the marker pr_reconcile_pending and the PR the
refinery may reuse, then the whole record with the bead blocked and assigned
to the refinery, merge_result=pull_request_pending, the PR's URL, number and
repository, the head the refinery validated and the target.

It takes the store's record lock across both writes, so no run of the landing
order reads the record between them, and it reads the bead under the lock
first. It writes only on a bead that is not closed and is assigned to the
refinery --refinery names, each write guarded on the status and the assignee
it read, so it writes nothing on a bead that a close or a release reached
first. The PR must be in the rig's own repository, the one the origin of the
clone it runs in names ($GC_RIG_ROOT, else the working directory).

exit: 0 recorded
      1 usage, or a PR outside the rig's own repository
      2 a read, the lock or a write did not answer, so no record landed; the
        message says whether the marker had
      3 refused: the bead is closed or not the refinery's, so nothing was
        written, or it moved between the two writes, so only the marker landed`

const prReconcileLong = `One run of the landing order over the store's pending records. It takes up to
--count of the beads that carry the marker pr_reconcile_pending, the least
recently checked first, and reads each record under the store's record lock,
from its read of the record to its last write of it, waiting while another
writer of the record holds it. It reads each PR from GitHub by its number:

  - open at the head the refinery validated: the evaluator decides whether it
    is ready, and a ready one is merged with its head pinned, or added to its
    base's merge queue with it where the base requires one; the next run reads
    it again either way
  - open at another head: back to the refinery, open, as
    pull_request_head_changed
  - merged at the validated head, with the merge commit on the freshly fetched
    target: mr_merged, and the bead closes
  - closed unmerged, merged at another head, or no longer the PR the record
    names: an exception, kept blocked behind a human gate keyed by its value
  - a lookup or a fetch that failed, or a merge commit not yet on the target:
    recorded in pr_reconcile_error, and read again by the next run

It acts only on a bead it reads under the lock as carrying the marker and,
unless the bead is closed, still assigned to the refinery --refinery names,
with each write guarded on the status and assignee it read. A bead a release
took from the refinery has its marker cleared and its PR named in a note, and
nothing else written. It starts no record past --budget. Each record's outcome
prints on a line of its own, as <bead> <action>: <detail>.

exit: 0 every record read was handled
      1 usage
      2 the listing or the lock did not answer, or a record's write failed`

func newPRRecordCmd(stdout, stderr io.Writer) *cobra.Command {
	var url, head, target, refinery, db string
	cmd := &cobra.Command{
		Use:         "record <bead> --pr <url> --head <sha> --target <branch> --refinery <address>",
		Short:       "record the PR a bead owns as pending until its merge is verified",
		Long:        prRecordLong,
		Args:        cobra.ExactArgs(1),
		Annotations: map[string]string{usageExitKey: "1"},
		RunE: func(_ *cobra.Command, args []string) error {
			bead := strings.TrimSpace(args[0])
			if bead == "" {
				return errors.New("name the bead that owns the PR")
			}
			_, repo, number, ok := record.ParseURL(url)
			if !ok {
				return fmt.Errorf("--pr %q is not a pull request's URL (https://<host>/<owner>/<repo>/pull/<number>)", url)
			}
			if refinery == "" {
				return errors.New("--refinery names the refinery's assignee")
			}
			p := record.Publication{URL: url, Repo: repo, Number: number, Head: head, Target: target}
			if err := p.Valid(); err != nil {
				return err
			}
			if !git.ValidBranch(target) {
				return fmt.Errorf("--target %q is not a branch name", target)
			}
			return exit(prRecord(bead, p, refinery, db, stdout, stderr))
		},
	}
	cmd.Flags().StringVar(&url, "pr", "", "the PR's URL")
	cmd.Flags().StringVar(&head, "head", "", "the head the refinery validated, a full commit id")
	cmd.Flags().StringVar(&target, "target", "", "the branch the PR is to merge into")
	cmd.Flags().StringVar(&refinery, "refinery", "", "the refinery's assignee, the only one a record is written for")
	cmd.Flags().StringVar(&db, "db", "", "the store's .beads directory, else the store gc routes the bead to")
	return cmd
}

func prRecord(bead string, p record.Publication, refinery, db string, stdout, stderr io.Writer) int {
	l, err := landing(db, refinery, bead)
	if err != nil {
		fmt.Fprintf(stderr, "gctk pr record: %v\n", err)
		return 2
	}
	err = l.Record(bead, p)
	var refused *pr.Refusal
	var origin *pr.OriginError
	switch {
	case err == nil:
		fmt.Fprintf(stdout, "%s: pending on %s at %s into %s\n", bead, p.URL, p.Head, p.Target)
		return 0
	case errors.As(err, &refused):
		fmt.Fprintf(stderr, "gctk pr record: %v\n", err)
		return 3
	case errors.As(err, &origin):
		fmt.Fprintf(stderr, "gctk pr record: %s: nothing written: %v\n", bead, err)
		return 1
	}
	fmt.Fprintf(stderr, "gctk pr record: %s: %v\n", bead, err)
	return 2
}

func newPRReconcileCmd(stdout, stderr io.Writer) *cobra.Command {
	var refinery, db string
	count := defaultRunCount
	budget := defaultRunBudget
	cmd := &cobra.Command{
		Use:         "reconcile --refinery <address>",
		Short:       "one run of the landing order over the store's pending records",
		Long:        prReconcileLong,
		Args:        cobra.NoArgs,
		Annotations: map[string]string{usageExitKey: "1"},
		RunE: func(*cobra.Command, []string) error {
			if refinery == "" {
				return errors.New("--refinery names the refinery's assignee")
			}
			if count < 1 {
				return fmt.Errorf("--count %d reads no record", count)
			}
			return exit(prReconcile(refinery, db, count, budget, stdout, stderr))
		},
	}
	cmd.Flags().StringVar(&refinery, "refinery", "", "the refinery's assignee, the only one a run acts for")
	cmd.Flags().StringVar(&db, "db", "", "the store's .beads directory, else the store gc resolves here")
	cmd.Flags().IntVar(&count, "count", count, "the most records one run reads")
	cmd.Flags().DurationVar(&budget, "budget", budget, "how long the run starts new records")
	return cmd
}

func prReconcile(refinery, db string, count int, budget time.Duration, stdout, stderr io.Writer) int {
	l, err := landing(db, refinery)
	if err != nil {
		fmt.Fprintf(stderr, "gctk pr reconcile: %v\n", err)
		return 2
	}
	l.Yield = runYield
	read := 0
	err = l.Reconcile(pr.Options{Count: count, Deadline: time.Now().Add(budget)}, func(o pr.RunOutcome) {
		read++
		fmt.Fprintf(stdout, "%s %s: %s\n", o.Bead, o.Action, o.Detail)
	})
	if err != nil {
		fmt.Fprintf(stderr, "gctk pr reconcile: %v\n", err)
		return 2
	}
	if read == 0 {
		fmt.Fprintln(stdout, "No pending pull-request merges.")
	}
	return 0
}

// landing builds the pr domain's Landing over the city's adapters: the store
// at db, else the one gc routes the first of ids to, the record lock in that
// store's .beads directory, GitHub through gh, the clone at $GC_RIG_ROOT else
// the working directory, the pack's definition of feedback, loaded in that
// clone, and the runtime adapter for human gates.
func landing(db, refinery string, ids ...string) (pr.Landing, error) {
	if db == "" {
		routed, err := gcbd.New().Route(ids...)
		if err != nil {
			return pr.Landing{}, err
		}
		db = routed
	}
	l, err := ledger.Open(db)
	if err != nil {
		return pr.Landing{}, err
	}
	dir := os.Getenv("GC_RIG_ROOT")
	if dir == "" {
		dir = "."
	}
	return pr.Landing{
		Ledger:   l,
		Dir:      db,
		Refinery: refinery,
		Hub:      func(host string) pr.Hub { return gh.New(host) },
		Feedback: func() (pr.Feedback, error) {
			rule, err := feedbackIn(dir)
			if err != nil {
				return nil, err
			}
			return rule, nil
		},
		Checkout: checkout{dir: dir},
		Gates:    gates{rt: gascity.New()},
		Wait:     recordLockWait,
	}, nil
}

// checkout is the rig's clone through the git adapter.
type checkout struct{ dir string }

func (c checkout) OriginURL() (string, error)             { return git.OriginURL(c.dir) }
func (c checkout) FetchBranch(branch string) error        { return git.FetchBranch(c.dir, branch) }
func (c checkout) Reaches(commit, b string) (bool, error) { return git.Reaches(c.dir, commit, b) }

// gates files human gates through the runtime adapter, which runs the pack's
// human-gate.sh from the scripts directory GCTK_SCRIPTS_DIR names. A gate the
// script does not file is an error carrying why: its exit and its last line, or
// why it did not run.
type gates struct{ rt gascity.Runtime }

func (g gates) File(subject, key, message string) error {
	res := g.rt.Script("human-gate.sh", "--subject", subject, "--key", key, "--message", message)
	if f := res.Failure(); f != "" {
		return fmt.Errorf("human gate on %s [%s]: %s", subject, key, f)
	}
	return nil
}
