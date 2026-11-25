package cli

import (
	"errors"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/git"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
)

// `gctk pr bring-current --target <branch>` merges the target into the
// checkout it runs in, for a review run's repair that brings a PR's branch
// current. The pr domain finds the base and makes the merge (pr.BringCurrent).

const prBringCurrentLong = `Merges the target branch, as origin holds it now, into the checkout this
runs in, to bring a PR's branch current with the branch it merges into. Run
it in the checkout, with nothing uncommitted.

git merges from its own merge base, the newest commit the branch and the
target share. When the target's history was rewritten after the branch last
took it, such as by an upstream sync, that base falls before the old history
the branch still carries, and a plain merge takes that history for the
branch's own change: it brings back what the rewrite dropped and conflicts in
files the branch never touched. So the merge goes from the commit of the
target the branch took last. Each commit the clone's reflog of
origin/<target> records the target naming, before or after an update, that
the target no longer holds and whose merge base with HEAD is newer than git's
gives a commit HEAD took from the old history. Of several, the one HEAD took
last is the one its first-parent history took in latest. When that history
does not order them, as when one merge took in two, the call refuses, and
--base names the commit. The merge then takes a commit that
supersedes that base with the target, carrying the target's tree whole, as
git merge -s ours records a merge. git merges from the base, and git show
--remerge-diff on the merge shows only what was resolved by hand. The
messages of the superseding commit and the merge name the base.

With no such commit, the target itself is merged once the reflog shows that
nothing the branch could have taken is missing from it: read back from its
newest update, while each starts where the one before it ended, it reaches
back to before the target held git's merge base. When it does not, as once
git prunes an update whose commits the ref no longer holds
(gc.reflogExpireUnreachable, 30 days by default) or in a clone made after the
branch took the target, the call refuses, and --base names the commit of the
target the branch took last for it to merge from.

exit: 0 merged, or HEAD already held the target
      1 usage, or not run in a checkout
      2 git did not answer or failed, such as the fetch: nothing was merged,
        unless git said it left its merge state
      3 refused, with the checkout as it was: it holds work no commit
        holds, or is in the middle of a merge, cherry-pick, revert, rebase
        or bisect, or HEAD shares no history with the target, or the reflog
        or HEAD's history cannot show the commit of the target the branch
        took last and no --base names it, or --base names a commit HEAD does
        not hold or one that does not hold git's merge base
      4 git stopped on conflicts and left its merge state: resolve each file
        it lists and git add it, then commit the merge with git commit -F
        <file>, the file holding the message printed and then one paragraph
        for each file resolved by hand`

func newPRBringCurrentCmd(stdout, stderr io.Writer) *cobra.Command {
	var target, base string
	cmd := &cobra.Command{
		Use:         "bring-current --target <branch> [--base <commit>]",
		Short:       "merge the target into the checkout, from the commit of it the branch took last when it was rewritten",
		Long:        prBringCurrentLong,
		Args:        cobra.NoArgs,
		Annotations: map[string]string{usageExitKey: "1"},
		RunE: func(_ *cobra.Command, _ []string) error {
			t := strings.TrimSpace(target)
			if !git.ValidBranch(t) {
				return errors.New("--target names the branch the PR merges into")
			}
			b := strings.TrimSpace(base)
			if b != "" && !git.IsObjectID(b) {
				return errors.New("--base names a commit by its full object name")
			}
			dir, err := os.Getwd()
			if err != nil {
				return fmt.Errorf("the checkout's directory did not read: %w", err)
			}
			if _, ok := git.Toplevel(dir); !ok {
				return errors.New("run it in the checkout to bring current")
			}
			return exit(prBringCurrent(dir, t, b, stdout, stderr))
		},
	}
	cmd.Flags().StringVar(&target, "target", "", "the branch the PR merges into, as origin names it")
	cmd.Flags().StringVar(&base, "base", "", "the commit of the target the branch took last, to merge from when the clone's reflog cannot show it")
	return cmd
}

func prBringCurrent(dir, target, base string, stdout, stderr io.Writer) int {
	cur, err := pr.BringCurrent(dir, target, base)
	if err != nil {
		fmt.Fprintf(stderr, "gctk pr bring-current: %v\n", err)
		var refused *pr.CurrentRefusal
		if errors.As(err, &refused) {
			return 3
		}
		return 2
	}
	if cur.Held {
		fmt.Fprintf(stdout, "HEAD already holds origin/%s at %s: nothing to merge\n", target, abbrev(cur.Tip))
		return 0
	}
	from := fmt.Sprintf("origin/%s at %s, from git's merge base %s", target, abbrev(cur.Tip), abbrev(cur.Default))
	if cur.Supersede != "" {
		from = fmt.Sprintf("%s, which supersedes %s with origin/%s at %s, from %s: origin/%s was rewritten after this branch last took it, at %s",
			abbrev(cur.Supersede), abbrev(cur.Base), target, abbrev(cur.Tip), abbrev(cur.Base), target, abbrev(cur.Base))
	}
	if len(cur.Conflicts) == 0 {
		fmt.Fprintf(stdout, "merged %s\nHEAD is %s\n", from, cur.Head)
		return 0
	}
	fmt.Fprintf(stdout, "merging %s\ngit stopped on conflicts in:\n", from)
	for _, p := range cur.Conflicts {
		fmt.Fprintf(stdout, "  %s\n", p)
	}
	fmt.Fprintf(stdout, "Resolve each and git add it, then commit the merge with git commit -F <file>, "+
		"the file holding the message below and then one paragraph for each file you resolved by hand. "+
		"git merge --abort undoes the merge.\n\n%s", cur.Message)
	return 4
}

// abbrev is the abbreviation the output names a commit by.
func abbrev(id string) string { return id[:min(len(id), 12)] }
