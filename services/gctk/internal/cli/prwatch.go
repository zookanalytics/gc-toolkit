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

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
)

// `gctk pr poll` and `gctk pr refresh` are the PR watch
// (specs/tk-1tfzr71.149/design.md, sections 1, 4 and 6): the pass that asks
// GitHub cheaply whether each PR the city owns moved, which orders/pr-poll.toml
// runs on a cooldown, and the one-PR update that reads and saves a PR that
// did, which the pass runs and a webhook's rule can call for the PR an event
// names. Each builds the pr domain's Watcher over the adapters.

// watchLockWait is how long an update waits for the store's record lock. A run
// of the landing order holds it for one record at a time, and an update that
// does not get it saves nothing, so the next pass reads the PR again.
const watchLockWait = 30 * time.Second

// pollWindow is how long into a pass the pass starts another update, so the
// pass ends before the next one is due two minutes after it started.
const pollWindow = 90 * time.Second

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
each part read after the saved one's instant and differing from it. A bead on
Gas Town's pending record gets pr_state and pr_last_checked_at in the same
write. A merge state GitHub reads as UNKNOWN is saved with the PR part's
earlier signs, so the next pass reads it again. It prints the bead, the PR and
what it did, as <bead> <url> <action>: <detail>.

exit: 0 saved, unchanged, or no live bead owns the PR
      1 usage, or --pr is no PR's URL
      2 a read or the write did not answer, or more than one live bead owns
        the PR, so nothing was saved`

const prPollLong = `One pass of the PR watch over the store's live beads: it lists the PRs they
own, asks GitHub for each one's cheap signs in one request for each 50 PRs in
a repository, and runs the one-PR update (gctk pr refresh) for each PR whose
signs moved from the ones saved on its bead, or whose bead holds no read, or
one not current for it. It starts no update more than 90 seconds in. A pass in
which nothing moved writes no bead.

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
	w, err := watcher(db)
	if err != nil {
		fmt.Fprintf(stderr, "gctk pr poll: %v\n", err)
		return 2
	}
	rep, err := w.Poll(pr.PollOptions{Window: pollWindow})
	if err != nil {
		fmt.Fprintf(stderr, "gctk pr poll: %v\n", err)
		return 2
	}
	for _, u := range rep.Updates {
		fmt.Fprintln(stdout, refreshedLine(u))
	}
	for _, url := range slices.Sorted(maps.Keys(rep.Failed)) {
		fmt.Fprintf(stdout, "%s failed: %v\n", url, rep.Failed[url])
	}
	for _, url := range rep.Late {
		fmt.Fprintf(stdout, "%s left: the pass reached its %s, so the next pass reads it\n", url, pollWindow)
	}
	fmt.Fprintf(stdout, "Asked about %d PRs in %d repositories: %d updated, %d failed, %d left for the next pass.\n",
		rep.Asked, rep.Repositories, len(rep.Updates), len(rep.Failed), len(rep.Late))
	if len(rep.Failed) > 0 {
		fmt.Fprintf(stderr, "gctk pr poll: %d PRs failed\n", len(rep.Failed))
		return 2
	}
	return 0
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
// directory, GitHub through gh, and the pack's definition of feedback, loaded
// in the clone at $GC_RIG_ROOT, else the working directory.
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
		Wait: watchLockWait,
	}, nil
}
