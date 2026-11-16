package cli

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/git"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
)

// `gctk pr push <bead> --held-by <conversation>` is a converse sitting's push
// onto the branch of a PR on the pending record, which it edits with the
// operator on their ruling. The pr domain proves the holding, returns the PR
// to draft and orders the push (pr.Landing.Push). The push itself is the
// pack's one writer of a push onto a work's branch, branch-push.sh, from the
// scripts directory GCTK_SCRIPTS_DIR names.

const prPushLong = `Pushes the commits of a converse sitting's checkout onto the branch of the
pull request a bead owns, for the sitting that edits that branch with the
operator on their ruling. Run it in the checkout.

The push goes ahead only when the sitting holds the branch: the bead owns a PR
open on the pending record and names its branch, the conversation --held-by
names is in progress under this session, the bead waits on that conversation
through a blocks edge, no review run is attached to the bead, and no open bead
other than an ask names its branch. While that edge holds the bead, the landing
order pours no review run on it and the refinery does not take it. The proof
reads under the store's record lock, which the landing order holds from its
read of a record to its pour of a review run, and the push holds that lock to
its end, so between the proof and the push the order neither pours a run nor
marks the PR ready. Every URL the checkout's origin fetches from or pushes to
must name the PR's repository, and the checkout must hold no work its HEAD's
commit does not. Then the PR returns to draft, and the checkout's HEAD goes
onto the branch under git's lease on the tip read there, never forced, so a
push another writer made is never overwritten. --check proves the holding and
changes nothing.

Once the conversation closes, the refinery validates the head the sitting left
and the landing order pours one review run there.

exit: 0 pushed, or the branch held the checkout's HEAD already; with --check,
        the sitting holds the branch
      1 usage, a PR outside the rig's own repository, or no branch-push.sh in
        the directory GCTK_SCRIPTS_DIR names
      2 the store, GitHub, git or the push did not answer or failed, or the
        record lock stayed held as long as the verb waits, so the PR may be a
        draft and the push may not have landed; a retry is safe, since a push
        under the lease never overwrites another
      3 refused: the sitting does not hold the branch, the checkout's origin is
        not the PR's repository, the checkout holds work no commit holds, or
        the PR is not open from the bead's branch; nothing was changed
      4 the branch holds a commit the checkout's HEAD does not, such as one
        another writer pushed, so nothing was pushed and the PR may be a
        draft: bring that commit into the checkout and push again`

func newPRPushCmd(stdout, stderr io.Writer) *cobra.Command {
	var heldBy, db string
	var check bool
	cmd := &cobra.Command{
		Use:         "push <bead> --held-by <conversation> [--check]",
		Short:       "push a sitting's commits onto the branch of the PR a bead owns",
		Long:        prPushLong,
		Args:        cobra.ExactArgs(1),
		Annotations: map[string]string{usageExitKey: "1"},
		RunE: func(_ *cobra.Command, args []string) error {
			bead := strings.TrimSpace(args[0])
			if bead == "" {
				return errors.New("name the bead that owns the PR")
			}
			conv := strings.TrimSpace(heldBy)
			if conv == "" {
				return errors.New("--held-by names the conversation the sitting holds")
			}
			return exit(prPush(bead, conv, db, check, stdout, stderr))
		},
	}
	cmd.Flags().StringVar(&heldBy, "held-by", "", "the conversation the sitting holds, whose blocks edge holds the bead")
	cmd.Flags().BoolVar(&check, "check", false, "prove that the sitting holds the branch, and change nothing")
	cmd.Flags().StringVar(&db, "db", "", "the store's .beads directory, else the store gc routes the bead to")
	return cmd
}

func prPush(bead, conv, db string, check bool, stdout, stderr io.Writer) int {
	dir, err := os.Getwd()
	if err != nil {
		fmt.Fprintf(stderr, "gctk pr push: the checkout's directory did not read: %v\n", err)
		return 2
	}
	var tree sittingTree
	if !check {
		if tree, err = newSittingTree(dir); err != nil {
			fmt.Fprintf(stderr, "gctk pr push: %v\n", err)
			return 1
		}
	}
	l, err := landing(db, "", bead)
	if err != nil {
		fmt.Fprintf(stderr, "gctk pr push: %v\n", err)
		return 2
	}
	self := sessionNames()
	if check {
		h, err := l.Held(bead, conv, self)
		if err != nil {
			return pushFailed(bead, err, stderr)
		}
		fmt.Fprintf(stdout, "%s: conversation %s holds its branch %s, and nothing else writes it\n", bead, h.Conversation, h.Branch)
		return 0
	}
	p, err := l.Push(bead, conv, self, tree)
	if err != nil {
		return pushFailed(bead, err, stderr)
	}
	fmt.Fprintf(stdout, "%s: pushed the checkout's HEAD onto %s; %s is a draft until the review run passes\n", bead, p.Branch, p.URL)
	return 0
}

// pushFailed says why a push or its proof stopped, and returns its exit.
func pushFailed(bead string, err error, stderr io.Writer) int {
	var refused *pr.PushRefusal
	var undraftable *pr.DraftRefusal
	var origin *pr.OriginError
	var moved *pr.Moved
	fmt.Fprintf(stderr, "gctk pr push: %v\n", err)
	switch {
	case errors.As(err, &refused), errors.As(err, &undraftable):
		return 3
	case errors.As(err, &moved):
		return 4
	case errors.As(err, &origin):
		return 1
	}
	return 2
}

// sessionNames are the names this session's claims record, the ones Gas City
// stamps as a claim's assignee.
func sessionNames() []string {
	var out []string
	for _, k := range []string{"GC_SESSION_NAME", "GC_SESSION_ID", "GC_AGENT", "GC_ALIAS"} {
		if v := strings.TrimSpace(os.Getenv(k)); v != "" {
			out = append(out, v)
		}
	}
	return out
}

// sittingTree is the checkout the verb runs in: its origin's URLs and its
// uncommitted work through the git adapter, and its push through the pack's
// branch-push.sh.
type sittingTree struct {
	dir string
	rt  gascity.Runtime
}

// newSittingTree is the checkout at dir, once the directory GCTK_SCRIPTS_DIR
// names holds the pack's pusher, so a call that cannot push changes nothing.
func newSittingTree(dir string) (sittingTree, error) {
	scripts := strings.TrimSpace(os.Getenv("GCTK_SCRIPTS_DIR"))
	if scripts == "" {
		return sittingTree{}, errors.New("GCTK_SCRIPTS_DIR names no pack scripts directory, so branch-push.sh cannot push; nothing was changed")
	}
	if fi, err := os.Stat(filepath.Join(scripts, "branch-push.sh")); err != nil || fi.IsDir() || fi.Mode()&0o111 == 0 {
		return sittingTree{}, fmt.Errorf("%s holds no runnable branch-push.sh, so nothing can push; nothing was changed", scripts)
	}
	return sittingTree{dir: dir, rt: gascity.New().In(dir)}, nil
}

func (s sittingTree) Origin() (fetch, push []string, err error) { return git.OriginURLs(s.dir) }

func (s sittingTree) Uncommitted() (string, error) {
	c, err := git.Open(s.dir)
	if err != nil {
		return "", err
	}
	return c.Dirty()
}

// Push fetches branch, so the checkout holds the tip origin holds, and then
// pushes HEAD onto it with branch-push.sh's --from-origin read: the lease is on
// the tip the script reads on origin, and a HEAD that does not descend from it
// sends nothing. Its exits 3 (the branch moved after the read) and 4 (HEAD does
// not descend from the tip) are a *pr.Moved.
func (s sittingTree) Push(branch string) error {
	if err := git.FetchTip(s.dir, branch); err != nil {
		return err
	}
	res := s.rt.Script("branch-push.sh", "--repo", s.dir, "--branch", branch, "--head", "HEAD", "--from-origin")
	switch {
	case res.Err == nil && res.Code == 0:
		return nil
	case res.Err == nil && (res.Code == 3 || res.Code == 4):
		return &pr.Moved{Branch: branch, Why: res.Tail()}
	}
	return fmt.Errorf("branch-push.sh: %s", res.Failure())
}
