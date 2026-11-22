package cli

import (
	"context"
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
// 4 and 6): the refinery publishes a PR's record, and the landing order's runs,
// every minute, decide it on the read the PR watch saved
// (orders/pr-reconcile.toml). Each command builds the pr domain's Landing over
// the adapters and prints what it did.

// recordLockWait is how long a verb other than a run waits for the store's
// record lock. A run of the landing order holds it for one act at a time, each
// stopped at actStop, and its order's time limit ends any run, which frees the
// lock, sooner than this.
const recordLockWait = 5 * time.Minute

// runYield is how long a run leaves the lock free between two acts, so a
// publication waiting for it takes it there.
const runYield = 200 * time.Millisecond

// The run's bounds (specs/tk-1tfzr71.149/design.md, section 5): no act starts
// more than actWindow into a run, and each act is stopped at actStop, with
// whatever it is making of the calls pr.Options names, the merge's re-read
// among them, and waits for the record lock no longer. A run reads GitHub only
// in the acts of the records that owe one, so it takes every such record, in a
// shuffled order, and a slow act holds the next one back by actStop at most,
// unless it started a review run's pour (pr's pourReserve) or handed a retired
// PR's bead to the disposition writer, the two calls the stop does not end
// (pr.Options).
const (
	actWindow = 45 * time.Second
	actStop   = 30 * time.Second
)

const prRecordLong = `Records the pull request a bead owns as pending until its merge is verified,
in Gas Town's two writes: first the marker pr_reconcile_pending and the PR the
refinery may reuse, then the whole record with the bead blocked and assigned
to nobody, since the refinery's work on it ends there,
merge_result=pull_request_pending, the PR's URL, number and repository, the
head the refinery validated and the target.

It takes the store's record lock across both writes, so no run of the landing
order reads the record between them, and it reads the bead under the lock
first. It writes only on a bead that is not closed and is assigned to the
refinery --refinery names, each write guarded on the status and the assignee
it read, so it writes nothing on a bead that a close or another assignment
reached first. The PR must be in the rig's own repository, the one the origin
of the clone it runs in names ($GC_RIG_ROOT, else the working directory).

exit: 0 recorded
      1 usage, or a PR outside the rig's own repository
      2 a read, the lock or a write did not answer, so no record landed; the
        message says whether the marker had
      3 refused: the bead is closed or not assigned to the refinery, so
        nothing was written, or it moved between the two writes, so only the
        marker landed`

const prReconcileLong = `One run of the landing order over the store's pending records: the beads that
carry the marker pr_reconcile_pending, and the beads on the record that carry a
ruling's disposition, an open or blocked bead only while it is assigned to
nobody or to the refinery. It is the second of the PR's two loops. The PR watch
(gctk pr poll every minute, gctk pr compare every hour) keeps the read saved on
each PR's bead current through the one-PR update (gctk pr refresh), and a run
finds and does its work from that saved read and the store alone. It reads the
store once and decides every record through that read, as the board, the
labels and gctk pr status derive a PR's status. A record that owes no act is
reported with no write and no read of GitHub, and one that owes an act is
decided again under the store's record lock before it acts. A record whose bead
holds no saved read of its PR waits for the watch's next pass, which reads such
a PR whole. A record:

  - open at the head the refinery validated: one in its base's merge queue
    owes nothing; a draft whose review result passed at that head and target,
    with no review run attached and no ask a run can take open, is marked
    ready, without waiting for CI; otherwise the evaluator decides on the
    saved read whether it is ready; one that is not ready is owed a review run
    when no review result passed at that head and target, or an ask that
    nothing holds is open on the bead (gctk review ask), and the run pours it
    below
  - ready on the saved read: the one act checked against GitHub first. With
    the record lock free, the one-PR update re-reads the PR in full, every
    part whatever its signs say, and saves what it read. The act then decides
    the record again under the lock, on what that read saved, and merges a
    ready one with the head the evaluator judged there pinned, or adds it to
    its base's merge queue with it where the base requires one. A re-read
    that finds the PR not ready leaves the saved read corrected, so the next
    run finds no merge to check
  - open at another head: open, as pull_request_head_changed, and handed to
    the refinery in the write that assigns it the bead, unless something
    the order owes holds the head (below). The saved read can lag a push, so
    the act fetches the PR's branch first. A tip at the head the saved read
    gives goes back at it. A tip that contains the validated head in the
    clone's history says the saved read lags the branch, so nothing is sent
    back until the watch saves the head. Any other tip goes back as the head
    the branch holds, and a fetch or a read that fails sends nothing back
    until the next run
  - merged at the validated head, with the merge commit on the freshly fetched
    target: mr_merged, and the bead closes
  - closed unmerged, merged at another head, or no longer the PR the record
    names: an exception, kept blocked behind a human gate keyed by its value

Every act but the merge reads of GitHub only what it changes: the exceptions,
a ready transition, a review run's pour and a retired PR's close read nothing
of GitHub first. The records that owe an act are taken in a shuffled order. No
act starts more than 45 seconds into the run, and each act is stopped at 30
seconds, with whatever GitHub call, re-read, fetch, store read or write, human
gate's filing or refinery's wake it is making: a fetch gets a SIGTERM to git's
process group, so git removes the lock files it holds in the clone, and a kill
only if it still runs 5 seconds later. The stop ends no review run's pour and
no disposition writer. A cook stopped before it attaches its run leaves a run
that this order never reads, so an act starts a pour only while 10 seconds of
its 30 remain, and otherwise leaves it to the next run, and a pour runs to its
end. The disposition writer a retired PR's bead goes to once the act frees the
lock ends the bead's branch once its close lands, and a stop between the two
would leave the branch of a closed bead that no run reads again. Each act
takes the store's record lock, waiting no longer than its 30 seconds while
another writer holds it, reads its record again under it, decides it from
that read and the saved read, and writes guarded on the status and assignee it
read there. An act that did not complete, such as a request GitHub refused or
did not answer, a re-read that did not save, a store read or a fetch that
failed, a merge commit not yet on the target or an act that was stopped,
records nothing: its difference stays on the bead, and the next run decides it
again.

Before any of these, while the saved read shows the PR open, it carries out
each open withdrawal filed on the bead (gctk pr withdraw), on the act's own
read of the PR's reviews: it waits while an approval it would dismiss carries
feedback the city has not taken, its own message or an inline comment, on the
act's own reads of the PR's reviews and review threads, since a dismissal
retires both, dismisses each approval that stands on a commit that does not
contain the withdrawal's head in the clone's history, with the withdrawal's
reason and the city's mark, reads the reviews again, and closes the withdrawal
once none stands past the ones it dismissed, so an approval given during the
act keeps the withdrawal open for the next run. Before it dismisses any, it
fetches the PR's branch into the clone, and a commit the clone still does not
hold contains no head. When GitHub refuses a dismissal, it files a human gate
on the bead keyed approval-withdraw-refused. A dismissal, or a read of the
review threads or the reviews, that GitHub does not answer, a fetch that
fails, or a read of the clone's history that does not answer, leaves the
withdrawal for the next run, and the record keeps its marker while a
withdrawal is open, its changed head sent back to the refinery included,
since the withdrawal holds the bead from the refinery until it is carried out.

A changed head goes to the refinery once no withdrawal is open on the bead and
no review run is attached to it, in the write that assigns the bead to the
refinery and clears the marker. Until then the bead stays assigned to nobody
and keeps its marker, so a later run reads the run's end, and no run attached
to the bead is ever one whose input bead the refinery is assigned. Gas City
gives the refinery a turn for the bead only once nothing holds it, so when
only conversations and asks hold it, the run assigns the bead to the
refinery, wakes the refinery and nudges it (gc session wake, then gc session
nudge), and only then clears the marker. A wake that does not land keeps the
marker, and the next run wakes the refinery again.

A PR a ruling retired is decided apart from these: its bead carries the
disposition pr-dispose.sh records before it closes the PR, under the record
lock, so an act reads the disposition or has made its last write of the record
before the disposition lands, and a ruling that lands during a merge's
re-read, with the lock free, is read by the decision under the lock. The run
requests no merge for such a PR, pours no review run, marks nothing ready and
carries out no withdrawal. Once the saved read shows the PR closed and no
review run is attached, an act closes the withdrawals and asks still open on
the bead, and the bead closes onto the ruling's successor through
bead-rehome.sh, run as the refinery once the record lock is free. The script
closes it only while it still has the status and assignee the act read under
the lock and still records the ruling the act read, so a release or a second
ruling that lands once the lock is free leaves the bead to the next run, which
reads it again. A close the script holds for now, such as one the ruling's
open conversation holds, is reported as checked, and the next run hands it
over again. A retired PR that merged all the same lands as any other.

The review run is mol-pr-review, poured with gc formula cook --attach onto the
bead under the record lock, with the record's PR bead, head, target and branch
as its vars, and the pools and binding the refinery's address names
(<rig>/<binding>refinery): review_target <rig>/<binding>polecat-codex,
repair_target <rig>/<binding>polecat and binding_prefix <binding>. No run is
poured while one is attached to the bead, while another open bead names the
PR's branch, such as a rework child, or while a human gate holds the bead. A
conversation on the PR holds only its merge, so runs are poured while it is
open, and the merge waits until it closes. A run that ended without a result
is poured again. When the last two runs at the validated head both
ended without one, counting only runs that ended after the bead's last
review-run-failed gate closed, it files a human gate on the bead keyed
review-run-failed instead, naming both runs and how each ended.

The run writes none of GitHub's side itself: the one-PR update is the one
writer of pr_github_read, pr_state and pr_last_checked_at, the merge's
re-read included. A record that owes no act gets no write.

It keeps each PR's status: and held: labels equal to what the store derives,
for every PR the store's live beads own, on the pending record or not. For
each owned PR whose bead holds a read of it, it compares the labels of the
writer's that the read saved with the ones the store derives, as gctk pr
status derives them: the PR's status and held values while it is open, and
none once it merged or closed. Where they differ, it has the labels' one
writer, pr-status-label.sh, write them, reconcile on a PR the saved read shows
open and clear on one it shows merged or closed, handing it no labels, so the
writer reads the PR's labels itself, and reads nothing of the PR first. A
label write takes its place among the acts in the shuffled order, under the
same 45 and 30 seconds, and writes nothing on the bead, so one that does not
land, or one a saved read out of date made wrong, leaves the difference for a
later run, which writes it again.

Each post on an owned PR that is feedback the city has not taken, as the
one-PR update saved it, becomes an ask: the take. For each PR whose bead owns
it on the record, is open or blocked and is assigned to nobody or to the
refinery, while the saved read shows the PR open and applied the definition of
feedback from the bead's provenance instant, an act under the record lock files
one ask on the bead for each such post (gctk review ask's filing), whose
one-line reason names the post's kind, its author, the PR, an inline comment's
file and the line it was made on, and its URL, and marks the post with the
city's EYES once its ask stands. A filing finds the ask filed before for the
same reason, so a post whose mark did not land is marked again with no second
ask, and an edit of a post files nothing new. With the lock free, once a mark
has landed, the one-PR update reads the PR's conversation again, since a
reaction moves no sign, so the saved read shows the marks. A take takes its
place among the acts in the shuffled order, under the same 45 and 30 seconds,
and its line's action is taken. Once a mark has landed it starts no post with
less than 10 of its 30 seconds left, which it keeps for that read, and leaves
the posts it did not reach for the next run, its action then left. A take that
does not complete leaves its posts untaken in the saved read, where they hold
the PR's merge, and the run exits 2.

A red check or a conflict on such a PR becomes an ask on its bead, which its
review run works, or a human gate where the city cannot go on. While the saved
read shows the PR open with its checks read at its head, an act under the
record lock reads each required check by its newest result there, a skip
aside. Once every required check passes, it withdraws each red-check gate open
on the bead (pr-fix-unmoved, pr-fix-capped, pr-fix-noncode and
pr-check-unreported, each keyed .<number>) through human-gate.sh --retract,
whatever holds the bead. Its other steps wait for the record to be pending at
the head the refinery validated, and for no hold set by hand and no human gate
to hold the bead; a conversation holds only the merge:

  - an approved PR GitHub reads DIRTY or BEHIND, whose branch no open bead but
    its asks names: an ask to merge its target in, and nothing for its checks
  - a required check that failed for a code cause: one ask for the head, then
    pr-fix-unmoved once an ask at the head closed with the head still red, and
    pr-fix-capped once three earlier heads each drew an ask
  - a deploy's failed check: pr-fix-noncode
  - a check that timed out, was cancelled, failed to start, wants an action or
    went stale: the failed jobs of the GitHub Actions run behind it re-run,
    once per head and once that run has finished, the head reading re-run
    once a suite there shows its run at an attempt above 1; then, on an
    approved PR, pr-fix-noncode for a failure at a head that reads re-run, one
    outside any Actions run, or a re-run GitHub refuses, which an unapproved
    PR asks for again at the next run
  - an approved PR whose review passed, which GitHub reads BLOCKED with no
    required check reported but a skip, behind a check suite queued with no
    check runs for ten minutes: one return to draft and ready transition per
    head, a return made since the head's first suite being the act's own, as
    its timeline reads, then pr-check-unreported ten minutes after it

It takes its place among the acts in the shuffled order, under the same 45 and
30 seconds, and its line's action is asked, rerun, restarted, gated or
withdrawn. A step that does not complete records nothing, and the run exits 2.

A PR that lands on the rig's default branch has that branch's seed audit
checked at its tip as the act fetched it, once the lock is free and inside the
run's 45 seconds, in a clone that carries one (render-seed-audit.sh). The
pages that no longer render as committed go to seed-audit-reaudit.sh, which
slings the branch's one re-render, and the landing's line says what the check
found. The check holds nothing, and one that does not run is asked for again
at a later landing.

It acts only on a bead it reads under the lock as carrying the marker, as an
open or blocked bead on the record that carries a ruling's disposition, with
or without the marker, or, for a take and for a red check or a conflict, as an
open or blocked bead that owns a PR on the record, with each write guarded on
the status and assignee it read.
A bead's assignee says who works it now: nobody while its PR waits, and the
refinery --refinery names while it validates a head. A bead assigned to anyone
else is theirs: the run writes nothing to it, requests no merge, pours no
review run, takes none of its PR's posts and files nothing for its checks, and
works it again once the assignee is gone.
Each outcome prints on a line of its own, as <bead> <action>: <detail>, where
a label write's action is labeled and a take's is taken.

exit: 0 each record, each PR's labels and each take the run took up were
        decided, and no act it started failed
      1 usage
      2 the listing did not answer, or a record, a PR's labels or a take could
        not be decided or its act did not complete: a store read or write
        failed, a call GitHub refused or did not answer, a merge's re-read did
        not save, a fetch failed, a review run the record is owed did not pour,
        the labels' writer did not exit 0, a post's ask did not file, its mark
        did not land or the read of the conversation after the marks did not
        save, or the act was stopped`

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
			return exit(prReconcile(refinery, db, stdout, stderr))
		},
	}
	cmd.Flags().StringVar(&refinery, "refinery", "", "the refinery's assignee, the only one a run acts for")
	cmd.Flags().StringVar(&db, "db", "", "the store's .beads directory, else the store gc resolves here")
	return cmd
}

func prReconcile(refinery, db string, stdout, stderr io.Writer) int {
	l, err := landing(db, refinery)
	if err != nil {
		fmt.Fprintf(stderr, "gctk pr reconcile: %v\n", err)
		return 2
	}
	l.Yield = runYield
	read := 0
	err = l.Reconcile(pr.Options{Window: actWindow, Stop: actStop}, func(o pr.RunOutcome) {
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
// store's .beads directory, GitHub through gh, the PR watch's one-PR update over
// the same store for the re-read a merge makes first and for the read of the
// conversation a take makes once its marks land, each waiting for the record
// lock no longer than the act has left, the clone at $GC_RIG_ROOT else the
// working directory, the pack's definition of feedback, loaded in that clone,
// and the runtime adapter for human gates, for the city's mark, which
// `pr-post.sh mark` prints, for a review run's pour, which runs in the clone,
// so gc resolves the rig's store there, for the disposition writer, which runs
// as the refinery, for the refinery's wake, for the labels' writer, and, where
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
	rule := func() (pr.Feedback, error) {
		rule, err := feedbackIn(dir)
		if err != nil {
			return nil, err
		}
		return rule, nil
	}
	return pr.Landing{
		Ledger:   l,
		Dir:      db,
		Refinery: refinery,
		Hub:      func(ctx context.Context, host string) pr.Hub { return gh.New(host).Within(ctx) },
		Reread: func(ctx context.Context, url string) error {
			_, err := watcherWithin(ctx, l, db, rule).Reread(url)
			return err
		},
		RefreshConversation: func(ctx context.Context, url string) error {
			_, err := watcherWithin(ctx, l, db, rule).RefreshConversation(url)
			return err
		},
		Feedback:     rule,
		Mark:         func() (string, error) { return cityMark(rt) },
		Checkout:     checkout{dir: dir},
		Gates:        actGates{rt: rt},
		Runs:         runs{rt: rt.In(dir)},
		Dispositions: dispositions{rt: rt.As(refinery)},
		Audit:        audit,
		Wake:         wakes{rt: rt},
		Labels:       prLabels{rt: rt},
		Wait:         recordLockWait,
	}, nil
}

// watcherWithin is the PR watch over the store l opened at db, for an act of the
// landing order: each GitHub call and store read stops once ctx ends, and its
// wait for the record lock is no longer than what is left of ctx.
func watcherWithin(ctx context.Context, l *ledger.Ledger, db string, rule func() (pr.Feedback, error)) pr.Watcher {
	wait := watchLockWait
	if end, ok := ctx.Deadline(); ok {
		wait = min(wait, time.Until(end))
	}
	return pr.Watcher{Ledger: l.Within(ctx), Dir: db, Feedback: rule, Wait: wait,
		GitHub: func(host string) pr.Watch { return gh.New(host).Within(ctx) }}
}

// wakes wakes a session and then nudges it through the runtime adapter, the two
// calls a polecat's hand-off to the refinery makes (work-submit.sh). It makes
// the nudge whether or not the wake landed, since a session that is up gets
// its turn from the nudge alone, and an error names each call that did not
// exit 0. Both calls stop once ctx ends.
type wakes struct{ rt gascity.Runtime }

func (w wakes) Wake(ctx context.Context, session, message string) error {
	rt := w.rt.Within(ctx)
	var failed []string
	if f := rt.Wake(session).Failure(); f != "" {
		failed = append(failed, "gc session wake "+session+": "+f)
	}
	if f := rt.Nudge(session, message).Failure(); f != "" {
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

// checkout is the rig's clone through the git adapter. A fetch that a SIGTERM
// or SIGINT to this process stopped, once the signal reached git's group, ends
// this process with the status that signal gives, since the order runner or a
// terminal asked it to stop.
type checkout struct{ dir string }

func (c checkout) OriginURL() (string, error)             { return git.OriginURL(c.dir) }
func (c checkout) Reaches(commit, b string) (bool, error) { return git.Reaches(c.dir, commit, b) }
func (c checkout) DefaultBranch() (string, error)         { return git.DefaultBranch(c.dir) }
func (c checkout) Tip(branch string) (string, error)      { return git.Tip(c.dir, branch) }

func (c checkout) Contains(commit, ancestor string) (bool, error) {
	return git.Contains(c.dir, commit, ancestor)
}

func (c checkout) FetchBranch(ctx context.Context, branch string) error {
	err := git.FetchBranch(ctx, c.dir, branch)
	var stopped *git.Interrupted
	if errors.As(err, &stopped) {
		os.Exit(128 + int(stopped.Signal))
	}
	return err
}

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
	_ = f.Close()
	defer func() { _ = os.Remove(list) }()
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

func (r runs) Pour(formula, bead string, vars map[string]string) (string, error) {
	res := r.rt.Cook(gascity.Cook{Formula: formula, Bead: bead, Vars: vars})
	if f := res.Failure(); f != "" {
		return "", fmt.Errorf("gc formula cook %s --attach %s: %s", formula, bead, f)
	}
	if res.Root == "" {
		return "", fmt.Errorf("gc formula cook %s --attach %s named no root: %s", formula, bead, res.Tail())
	}
	return res.Root, nil
}

// dispositions closes a bead whose PR a ruling retired through the runtime
// adapter, which runs the pack's bead-rehome.sh from the scripts directory
// GCTK_SCRIPTS_DIR names, as the refinery, since the script closes an assigned
// bead only as its assignee, and the refinery is the one agent the order
// works an assigned bead for. It names the run's
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

// Withdraw resolves each open human gate under key that blocks subject, with
// the reason moot: message (human-gate.sh --retract). No gate open there is no
// error.
func (g gates) Withdraw(subject, key, message string) error {
	res := g.rt.Script("human-gate.sh", "--retract", "--subject", subject, "--key", key, "--message", message)
	if f := res.Failure(); f != "" {
		return fmt.Errorf("withdrawal of the human gate on %s [%s]: %s", subject, key, f)
	}
	return nil
}

// actGates files the landing order's human gates through gates, stopped once
// the act's context ends. The stop kills human-gate.sh, not a call the script
// already started (gascity.City.Within), so the create that files the gate
// with its edge onto the bead lands whole or not at all, with the message under
// bd's own head when the stop came before the script set the description. The
// next run finds the open gate under its key or files it, and files a second
// only when that create has still not landed by the time it reads the gates.
type actGates struct{ rt gascity.Runtime }

func (g actGates) File(ctx context.Context, subject, key, message string) error {
	return gates{rt: g.rt.Within(ctx)}.File(subject, key, message)
}

// Withdraw withdraws the gates under key on subject through gates, stopped once
// the act's context ends. A stop between two resolves leaves the rest open, for
// the next run's withdrawal.
func (g actGates) Withdraw(ctx context.Context, subject, key, message string) error {
	return gates{rt: g.rt.Within(ctx)}.Withdraw(subject, key, message)
}
