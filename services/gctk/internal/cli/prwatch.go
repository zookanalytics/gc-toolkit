package cli

import (
	"errors"
	"fmt"
	"io"
	"maps"
	"os"
	"slices"
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

// `gctk pr poll`, `gctk pr compare` and `gctk pr refresh` are the PR watch
// (specs/tk-1tfzr71.149/design.md, sections 1, 2, 4, 6 and 9): the pass that
// asks GitHub cheaply whether each PR the city owns moved, which
// orders/pr-poll.toml runs on a cooldown, the net's pass that reads each owned
// PR in full and compares it with the read saved on its bead, and clears the
// city's labels off the PRs no live bead owns, which orders/pr-compare.toml
// runs, and the one-PR update that reads and saves a PR that moved or differs,
// which both passes run and a webhook's rule can call for the PR an event
// names. Each builds the pr domain's Watcher over the adapters.

// watchLockWait is how long an update waits for the store's record lock. A run
// of the landing order holds it for one record at a time, and an update that
// does not get it saves nothing, so the next pass reads the PR again.
const watchLockWait = 30 * time.Second

// pollWindow is how long into a pass the pass starts another update. A pass
// in which many PRs moved can run past its order's minute, and Gas City starts
// the next pass only once it ends, or once its watchdog closes the run's record
// two minutes in, so the window bounds how long such a pass holds the next one
// back.
const pollWindow = 90 * time.Second

// compareWindow is how long into a pass of the net the pass starts another
// update, so the pass ends before its order's timeout stops it.
const compareWindow = 3 * time.Minute

const prRefreshLong = `The one-PR update: reads GitHub's side of the PR at --pr and saves it on the
live bead that owns it, as pr_github_read, the one writer of that read. A bead
owns a PR when it names it as its own and is no other bead's child: an anchor
names it in pr_url beside a merge_result, and a bead the refinery sent back to
the pool names it in existing_pr. A PR no live bead owns has nothing to save,
which it prints, exiting 0.

It reads the PR's cheap signs first, one request, and then only the parts
the signs say moved: the PR's own facts, with the required check runs at its
head when the head or the checks moved, its conversation when a comment,
review or dismissed count or when GitHub last changed the PR moved, and its
labels, which are their own signs. A read that is missing a part, or is not
current for the bead, is read whole. Under the store's record lock it reads
the bead again and writes once, guarded on the status and assignee it read,
each part read after the saved one's instant: the part when it differs from
the saved one, and its read's instant alone when it holds the same, so a read
sent before it is never saved after it. A bead on
Gas Town's pending record gets pr_state and pr_last_checked_at in the same
write. A merge state GitHub reads as UNKNOWN on an open PR is saved as read,
and the PR watch's next pass reads the PR part again, until GitHub has computed
one. It prints the bead, the PR and what it did, as <bead> <url> <action>:
<detail>.

exit: 0 saved, unchanged, or no live bead owns the PR
      1 usage, or --pr is no PR's URL
      2 a read or the write did not answer, or more than one live bead owns
        the PR, so nothing was saved`

const prPollLong = `One pass of the PR watch over the store's live beads: it lists the PRs they
own, asks GitHub for each one's cheap signs in one request for each 50 PRs in
a repository, and runs the one-PR update (gctk pr refresh) for each PR whose
signs moved from the ones saved on its bead, whose bead holds no read or one
not current for it, or that is open with a merge state GitHub had not computed
when it was saved. It takes those PRs, from every repository, in a shuffled
order, so one whose update is slow or keeps failing holds no other back, and
starts no update more than 90 seconds in. A pass in which none of these holds
writes no bead.

The signs are the PR's state and draft flag, its head, its base and the base's
tip, when GitHub last changed it, its comments, reviews and dismissed reviews
counted, its labels, every one, and its checks at the head counted by state. A
PR whose signs did not read keeps its saved signs and is asked again at the
next pass, as is a PR the 90 seconds left. Each update prints on a line of its
own, as <bead> <url> <action>: <detail>, each PR that failed as <url> failed:
<why>, and each PR left for the next pass as <url> left; the pass ends with a
line counting the PRs it asked about.

exit: 0 every owned PR was asked, and every update it started saved
      1 usage
      2 the store's listing did not read, or a PR failed: its signs or a read
        of it did not answer, its write did not land, or more than one live
        bead owns it`

const prCompareLong = `One pass of the net over the store's live beads: it lists the PRs they own,
reads each in full in one request for each 10 PRs in a repository, and runs
the one-PR update (gctk pr refresh) for each PR whose read differs from the
read saved on its bead, over each part that differs or whose cheap signs
moved, as gctk pr poll tells them. It takes those PRs in a shuffled order, as
gctk pr poll does, and starts no update more than 3 minutes in. A pass in
which no part differs or moved writes no bead.

The full read is the cheap signs gctk pr poll reads and the facts no sign
shows: the PR's merge state, its review decision, whether it is in a merge
queue and whether its base requires one, each review thread's resolution, the
time each conversation comment, review and inline comment last changed, the
reactions the city's account left on each inline comment, and the check runs
at its last commit with whether the PR requires each. It reads no post's
text, and reads a list past its first page on until it ends. It compares
those facts with the PR part, the required check runs with the checks, and
the review decision, the unresolved threads, the newest post time and the
city's reactions with the conversation. A merge state GitHub reads as UNKNOWN
differs in nothing. So a review thread resolved or reopened, the city's
reaction that answers a thread with no reply, or an edit to a post that left
the PR's updatedAt as it was, reaches the saved read within one pass.

A PR whose read failed keeps its saved read and is read again at the next
pass, as is a PR the 3 minutes left.

The pass then searches the rig's own repository, the one its clone's origin
names, for the PRs that carry a status: or held: label the labels' writer
names, 100 PRs a page, and reads on a page at a time until it has found 20
PRs no live bead owns or the results end. It has the writer
(pr-status-label.sh clear) take the city's labels off each of them, in a
shuffled order, so a PR whose clear is slow or keeps failing holds no other
back, starting none past the 3 minutes. A clear that does not land is found
by the next pass's search.

Each update prints on a line of its own, as <bead> <url> <action>: <detail>,
each PR that failed as <url> failed: <why>, each PR left for the next pass as
<url> left, and each PR whose labels came off as <url> cleared; the pass ends
with a line counting the PRs it compared and a line saying what the search
found.

exit: 0 every owned PR was read, every update it started saved, the search
        read, and every clear it started landed
      1 usage
      2 the store's listing did not read, a PR failed (its full read or a read
        the update made did not answer, its write did not land, more than one
        live bead owns it, or its clear did not land), or the search or the
        rig's origin did not read`

func newPRRefreshCmd(stdout, stderr io.Writer) *cobra.Command {
	var url, db string
	cmd := &cobra.Command{
		Use:         "refresh --pr <url>",
		Short:       "read a PR's moved parts from GitHub and save them on the bead that owns it",
		Long:        prRefreshLong,
		Args:        cobra.NoArgs,
		Annotations: map[string]string{usageExitKey: "1"},
		RunE: func(*cobra.Command, []string) error {
			url = strings.TrimSpace(url)
			if url == "" {
				return errors.New("--pr names the PR to refresh")
			}
			if _, _, _, ok := record.ParseURL(url); !ok {
				return fmt.Errorf("--pr %q is not a pull request's URL (https://<host>/<owner>/<repo>/pull/<number>)", url)
			}
			return exit(prRefresh(url, db, stdout, stderr))
		},
	}
	cmd.Flags().StringVar(&url, "pr", "", "the PR's URL")
	cmd.Flags().StringVar(&db, "db", "", "the store's .beads directory, else the store gc resolves here")
	return cmd
}

func prRefresh(url, db string, stdout, stderr io.Writer) int {
	w, err := watcher(db)
	if err != nil {
		fmt.Fprintf(stderr, "gctk pr refresh: %v\n", err)
		return 2
	}
	done, err := w.Refresh(url)
	if err != nil {
		fmt.Fprintf(stderr, "gctk pr refresh: %s: %v\n", url, err)
		return 2
	}
	fmt.Fprintln(stdout, refreshedLine(done))
	return 0
}

func newPRPollCmd(stdout, stderr io.Writer) *cobra.Command {
	var db string
	cmd := &cobra.Command{
		Use:         "poll",
		Short:       "ask GitHub whether each PR the store's beads own moved, and refresh each that did",
		Long:        prPollLong,
		Args:        cobra.NoArgs,
		Annotations: map[string]string{usageExitKey: "1"},
		RunE: func(*cobra.Command, []string) error {
			return exit(prPoll(db, stdout, stderr))
		},
	}
	cmd.Flags().StringVar(&db, "db", "", "the store's .beads directory, else the store gc resolves here")
	return cmd
}

func prPoll(db string, stdout, stderr io.Writer) int {
	return prPass("gctk pr poll", "Asked about", db, pollWindow, pr.Watcher.Poll, stdout, stderr)
}

func newPRCompareCmd(stdout, stderr io.Writer) *cobra.Command {
	var db string
	cmd := &cobra.Command{
		Use:         "compare",
		Short:       "read each PR the store's beads own in full, and refresh each that differs from its saved read",
		Long:        prCompareLong,
		Args:        cobra.NoArgs,
		Annotations: map[string]string{usageExitKey: "1"},
		RunE: func(*cobra.Command, []string) error {
			return exit(prCompare(db, stdout, stderr))
		},
	}
	cmd.Flags().StringVar(&db, "db", "", "the store's .beads directory, else the store gc resolves here")
	return cmd
}

func prCompare(db string, stdout, stderr io.Writer) int {
	return prPass("gctk pr compare", "Compared", db, compareWindow, pr.Watcher.Compare, stdout, stderr)
}

// prPass runs one pass of the watch, bounded by window, and prints what it did:
// each update, each PR that failed and each PR left for the next pass, then a
// line counting the PRs the pass read, which counted opens.
func prPass(prog, counted, db string, window time.Duration, pass func(pr.Watcher, pr.PassOptions) (pr.PassReport, error),
	stdout, stderr io.Writer) int {
	w, err := watcher(db)
	if err != nil {
		fmt.Fprintf(stderr, "%s: %v\n", prog, err)
		return 2
	}
	rep, err := pass(w, pr.PassOptions{Window: window})
	if err != nil {
		fmt.Fprintf(stderr, "%s: %v\n", prog, err)
		return 2
	}
	for _, u := range rep.Updates {
		fmt.Fprintln(stdout, refreshedLine(u))
	}
	for _, url := range slices.Sorted(maps.Keys(rep.Failed)) {
		fmt.Fprintf(stdout, "%s failed: %v\n", url, rep.Failed[url])
	}
	for _, url := range rep.Late {
		fmt.Fprintf(stdout, "%s left: the pass reached its %s, so the next pass reads it\n", url, window)
	}
	for _, url := range rep.Cleared {
		fmt.Fprintf(stdout, "%s cleared: no live bead owns it, so the labels' writer took the city's labels off\n", url)
	}
	fmt.Fprintf(stdout, "%s %d PRs in %d repositories: %d updated, %d failed, %d left for the next pass.\n",
		counted, rep.Asked, rep.Repositories, len(rep.Updates), len(rep.Failed), len(rep.Late))
	code := 0
	if s := rep.Search; s != nil {
		if s.Err != nil {
			fmt.Fprintf(stdout, "The search for the city's labels on PRs no live bead owns failed after %d pages: %v\n", s.Pages, s.Err)
			fmt.Fprintf(stderr, "%s: the search for the city's labels failed: %v\n", prog, s.Err)
			code = 2
		} else {
			pages := "pages"
			if s.Pages == 1 {
				pages = "page"
			}
			fmt.Fprintf(stdout, "Searched %s for the city's labels in %d %s: %d PRs no live bead owns found, %d cleared.\n",
				s.Repository, s.Pages, pages, s.Found, len(rep.Cleared))
		}
	}
	if len(rep.Failed) > 0 {
		fmt.Fprintf(stderr, "%s: %d PRs failed\n", prog, len(rep.Failed))
		code = 2
	}
	return code
}

// refreshedLine is an update's line: the bead, the PR and what it did.
func refreshedLine(u pr.Refreshed) string {
	bead := u.Bead
	if bead == "" {
		bead = "-"
	}
	return fmt.Sprintf("%s %s %s: %s", bead, u.URL, u.Action, u.Detail)
}

// watcher builds the pr domain's Watcher over the city's adapters: the store
// at db, else the one gc resolves here, the record lock in that store's .beads
// directory, GitHub through gh, the pack's definition of feedback, loaded in
// the clone at $GC_RIG_ROOT, else the working directory, that clone's origin,
// and the labels' writer, which the runtime adapter runs from the scripts
// directory GCTK_SCRIPTS_DIR names.
func watcher(db string) (pr.Watcher, error) {
	if db == "" {
		routed, err := gcbd.New().Route()
		if err != nil {
			return pr.Watcher{}, err
		}
		db = routed
	}
	l, err := ledger.Open(db)
	if err != nil {
		return pr.Watcher{}, err
	}
	dir := os.Getenv("GC_RIG_ROOT")
	if dir == "" {
		dir = "."
	}
	return pr.Watcher{
		Ledger: l,
		Dir:    db,
		GitHub: func(host string) pr.Watch { return gh.New(host) },
		Feedback: func() (pr.Feedback, error) {
			rule, err := feedbackIn(dir)
			if err != nil {
				return nil, err
			}
			return rule, nil
		},
		Labels: prLabels{rt: gascity.New()},
		Origin: func() (string, error) { return git.OriginURL(dir) },
		Wait:   watchLockWait,
	}, nil
}
