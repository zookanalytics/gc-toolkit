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
--count of the beads that carry the marker pr_reconcile_pending, and of the
refinery's beads on the record that carry a ruling's disposition, the least
recently checked first, and reads each record under the store's record lock,
from its read of the record to its last write of it, waiting while another
writer of the record holds it. It reads each PR from GitHub by its number:

  - open at the head the refinery validated: a draft whose review result
    passed at that head and target, with no review run attached and no ask a
    run can take open, is marked ready, without waiting for CI; otherwise the
    evaluator decides whether it is ready, and a ready one is merged with its
    head pinned, or added to its base's merge queue with it where the base
    requires one; one that is not ready is owed a review run when no review
    result passed at that head and target, or an ask that nothing holds is open
    on the bead (gctk review ask), and the run pours it below; the next run
    reads it again either way
  - open at another head: back to the refinery, open, as
    pull_request_head_changed
  - merged at the validated head, with the merge commit on the freshly fetched
    target: mr_merged, and the bead closes
  - closed unmerged, merged at another head, or no longer the PR the record
    names: an exception, kept blocked behind a human gate keyed by its value
  - a lookup or a fetch that failed, or a merge commit not yet on the target:
    recorded in pr_reconcile_error, and read again by the next run

Before any of these, while the PR is open, it carries out each open
withdrawal filed on the bead (gctk pr withdraw): it waits while an approval it
would dismiss carries an inline comment the intake has not routed, dismisses
each approval that stands on a commit that does not contain the withdrawal's
head, which GitHub's compare of the two reads as neither identical nor ahead,
or which GitHub refuses to compare, with the withdrawal's reason and the
city's mark, reads the reviews again and closes the withdrawal once none
stands. When GitHub refuses a dismissal, it
files a human gate on the bead keyed approval-withdraw-refused. A compare or a
dismissal GitHub does not answer leaves the withdrawal for the next run, and
the record keeps its marker while a withdrawal is open, its changed head sent
back to the refinery included, since the withdrawal holds the bead from the
refinery until it is carried out.

A changed head goes to the refinery once no withdrawal is open on the bead and
no review run is attached to it, and the record keeps its marker until then,
so a later run reads the run's end. Gas City gives the refinery a turn for the
bead only once nothing holds it, so when only conversations and asks hold it,
the run wakes the refinery and nudges it (gc session wake, then gc session
nudge) before it clears the marker. A wake that does not land keeps the
marker, and the next run wakes the refinery again.

A PR a ruling retired is read apart from these: its bead carries the
disposition pr-dispose.sh records before it closes the PR, under the record
lock, so a run reads the disposition or has made its last write of the record
before the disposition lands. The run requests no merge for such a PR, pours no
review run, marks nothing ready, carries out no withdrawal and saves no GitHub
read. Once the PR has closed and no review run is attached, the run closes the
withdrawals and asks still open on the bead, and the bead closes onto the
ruling's successor through bead-rehome.sh, run as the refinery once the record
lock is free. The script closes it only while it still has the status and
assignee the run read under the lock and still records the ruling the run read,
so a release or a second ruling that lands once the lock is free leaves the
bead to the next run, which reads it again. A close the script holds for now,
such as one the ruling's open conversation holds, is tried again by the next
run. A retired PR that merged all the same lands as any other.

The review run is mol-pr-review, poured with gc formula cook under the record
lock, with the record's PR bead, head, target and branch as its vars, and the
pools and binding the refinery's address names (<rig>/<binding>refinery):
review_target <rig>/<binding>polecat-codex, repair_target
<rig>/<binding>polecat and binding_prefix <binding>. The pour gives each bead
it created the bead's priority, then attaches the run to the bead by the bead's
blocks edge onto its root. A run whose pr_bead var names the bead and that no
edge of the bead names, live or ended, gets that edge before the runs that ended
are counted, and a live one is attached in place of a pour. A pour whose root
the bead's store does not hold files a human gate on the bead keyed
review-run-outside-store. No run is poured while one is attached to the bead,
while another open bead names the PR's branch, such as a rework child, or while
a human gate holds the bead. A conversation on the PR holds only its merge, so
runs are poured while it is open, and the merge waits until it closes. A run
that ended without a result is poured again. When the last two runs at the
validated head both ended without one, counting only runs that ended after the
bead's last review-run-failed gate closed, it files a human gate on the bead
keyed review-run-failed instead, naming both runs and how each ended.

Each check of an open PR no ruling retired, at the validated head or at
another, reads GitHub's side of it whole and saves that read on the bead as
pr_github_read, in the write that records the check: the PR's state, draft
flag, head and merge state, the required checks at that head, who approved or
asked for changes, the newest feedback in each comment space and the review
threads waiting on the city. A read that fails partway saves nothing, so the
bead keeps the last whole read.
The merge acts on the run's own read, never on the saved one.

A PR that lands on the rig's default branch has that branch's seed audit
checked at its tip as the run fetched it, once the lock is free, in a clone
that carries one (render-seed-audit.sh). The pages that no longer render as
committed go to seed-audit-reaudit.sh, which slings the branch's one re-render,
and the landing's line says what the check found. The check holds nothing, and
one that does not run is asked for again at a later landing.

It acts only on a bead it reads under the lock as carrying the marker, or as
an open or blocked bead on the record that carries a ruling's disposition,
with or without the marker, and, unless the bead is closed, still assigned to
the refinery --refinery names, with each write guarded on the status and
assignee it read. A bead a release took from the refinery has its marker
cleared and its PR named in a note, and nothing else written. It starts no
record past --budget. Each record's outcome prints on a line of its own, as
<bead> <action>: <detail>.

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
// clone, and the runtime adapter for human gates, for the city's mark, which
// `pr-post.sh mark` prints, for a review run's pour, which runs in the clone,
// so gc resolves the rig's store there, for the refinery's wake, and, where
// the clone carries one, for the seed audit, whose scripts run in the clone.
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
	rt := gascity.New()
	var audit pr.Audit
	if carriesSeedAudit(dir) {
		audit = seedAudit{rt: rt.In(dir), dir: dir}
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
		Mark:         func() (string, error) { return cityMark(rt) },
		Checkout:     checkout{dir: dir},
		Gates:        gates{rt: rt},
		Runs:         runs{rt: rt.In(dir)},
		Dispositions: dispositions{rt: rt.As(refinery)},
		Audit:        audit,
		Wake:         wakes{rt: rt},
		Wait:         recordLockWait,
	}, nil
}

// wakes wakes a session and then nudges it through the runtime adapter, the two
// calls a polecat's hand-off to the refinery makes (work-submit.sh). It makes
// the nudge whether or not the wake landed, since a session that is up gets
// its turn from the nudge alone, and an error names each call that did not
// exit 0.
type wakes struct{ rt gascity.Runtime }

func (w wakes) Wake(session, message string) error {
	var failed []string
	if f := w.rt.Wake(session).Failure(); f != "" {
		failed = append(failed, "gc session wake "+session+": "+f)
	}
	if f := w.rt.Nudge(session, message).Failure(); f != "" {
		failed = append(failed, "gc session nudge "+session+": "+f)
	}
	if len(failed) > 0 {
		return errors.New(strings.Join(failed, "; "))
	}
	return nil
}

// cityMark reads the city's mark from the writer of the city's posts, which
// owns it: `pr-post.sh mark`, from the scripts directory GCTK_SCRIPTS_DIR names.
func cityMark(rt gascity.Runtime) (string, error) {
	res := rt.Script("pr-post.sh", "mark")
	if f := res.Failure(); f != "" {
		return "", fmt.Errorf("pr-post.sh mark: %s", f)
	}
	return strings.TrimSpace(res.Output), nil
}

// checkout is the rig's clone through the git adapter.
type checkout struct{ dir string }

func (c checkout) OriginURL() (string, error)             { return git.OriginURL(c.dir) }
func (c checkout) FetchBranch(branch string) error        { return git.FetchBranch(c.dir, branch) }
func (c checkout) Reaches(commit, b string) (bool, error) { return git.Reaches(c.dir, commit, b) }
func (c checkout) DefaultBranch() (string, error)         { return git.DefaultBranch(c.dir) }
func (c checkout) Tip(branch string) (string, error)      { return git.Tip(c.dir, branch) }

// carriesSeedAudit reports whether the clone at dir is a pack that carries a
// rendered seed audit, generated/seed-audit/INDEX.md beside its pack.toml. A
// repository with none has nothing a landing can leave stale.
func carriesSeedAudit(dir string) bool {
	for _, p := range []string{"pack.toml", "generated/seed-audit/INDEX.md"} {
		if fi, err := os.Stat(filepath.Join(dir, p)); err != nil || !fi.Mode().IsRegular() {
			return false
		}
	}
	return true
}

// seedAudit is the clone's seed audit through the runtime adapter, which runs
// the pack's render-seed-audit.sh to check a commit and its
// seed-audit-reaudit.sh to ask for the default branch's re-render, each in the
// clone. The writer has no flag that names a checkout: it reads the default
// branch from origin/HEAD where it runs, and its gc bd calls resolve the store
// there when GC_RIG names no rig, so a clone that $GC_RIG_ROOT names apart from
// the working directory is still the one it reads.
type seedAudit struct {
	rt  gascity.Runtime
	dir string
}

// Stale checks the merge of commit into itself, which is commit's own tree, so
// every page that does not render as committed is commit's own staleness, the
// pages --base-stale-out names, on one render. A check the script did not
// complete is an error carrying why: its exit and its last line.
func (a seedAudit) Stale(commit string) ([]string, error) {
	f, err := os.CreateTemp("", "gctk-seed-audit-stale.*")
	if err != nil {
		return nil, fmt.Errorf("no file for the stale pages: %w", err)
	}
	list := f.Name()
	f.Close()
	defer os.Remove(list)
	res := a.rt.Script("render-seed-audit.sh", "--root", a.dir, "--check-merge", commit, commit, "--base-stale-out", list)
	if why := res.Failure(); why != "" {
		return nil, fmt.Errorf("render-seed-audit.sh: %s", why)
	}
	raw, err := os.ReadFile(list)
	if err != nil {
		return nil, fmt.Errorf("the stale pages did not read: %w", err)
	}
	var pages []string
	for _, p := range strings.Split(string(raw), "\n") {
		if p = strings.TrimSpace(p); p != "" {
			pages = append(pages, p)
		}
	}
	return pages, nil
}

// Reaudit hands the pages to seed-audit-reaudit.sh, which keeps one live
// re-render per branch and slings it, and returns the one line it answers with:
// the bead, its route and what it did. A writer that exits other than 0
// dispatched nothing, an error carrying why.
func (a seedAudit) Reaudit(branch, seenBy string, pages []string) (string, error) {
	args := []string{"--base", branch, "--seen-by", seenBy}
	for _, p := range pages {
		args = append(args, "--page", p)
	}
	res := a.rt.Script("seed-audit-reaudit.sh", args...)
	if why := res.Failure(); why != "" {
		return "", fmt.Errorf("seed-audit-reaudit.sh: %s", why)
	}
	return res.Tail(), nil
}

// runs pours a review run through the runtime adapter's cook. A cook that did
// not exit 0, or that named no root, is an error carrying why.
type runs struct{ rt gascity.Runtime }

func (r runs) Pour(formula string, vars map[string]string) (pr.Poured, error) {
	res := r.rt.Cook(gascity.Cook{Formula: formula, Vars: vars})
	if f := res.Failure(); f != "" {
		return pr.Poured{}, fmt.Errorf("gc formula cook %s: %s", formula, f)
	}
	if res.Root == "" {
		return pr.Poured{}, fmt.Errorf("gc formula cook %s named no root: %s", formula, res.Tail())
	}
	return pr.Poured{Root: res.Root, Beads: res.Beads}, nil
}

// dispositions closes a bead whose PR a ruling retired through the runtime
// adapter, which runs the pack's bead-rehome.sh from the scripts directory
// GCTK_SCRIPTS_DIR names, as the refinery the bead is assigned to, since the
// script closes an assigned bead only as its assignee. It names the run's
// judgment of the bead, so the script closes it only while the bead still has
// the status and assignee the run read under the record lock and still records
// the ruling the run read there. The script's exit 4 (the bead is not as the
// run judged it, or a write did not land, as when the bead moved since the
// script's own read) and exit 5 (the close is held, as by an open wait) are a
// close held for now. Any other failure, or a script that did not run, is an
// error carrying why.
type dispositions struct{ rt gascity.Runtime }

func (d dispositions) Close(x pr.Disposal) error {
	r := x.Disposition
	args := []string{"--origin", x.Bead, "--successor", r.Successor, "--kind", r.Kind, "--note", x.Note}
	if r.Store != "" {
		args = append(args, "--successor-store", r.Store)
	}
	args = append(args, "--if-status", x.Status, "--if-assignee", x.Assignee, "--if-ruled")
	res := d.rt.Script("bead-rehome.sh", args...)
	switch {
	case res.Err == nil && res.Code == 0:
		return nil
	case res.Err == nil && (res.Code == 4 || res.Code == 5):
		return &pr.HeldClose{Why: "bead-rehome.sh: " + res.Failure()}
	}
	return fmt.Errorf("bead-rehome.sh: %s", res.Failure())
}

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
