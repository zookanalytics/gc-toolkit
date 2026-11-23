package cli

import (
	"errors"
	"fmt"
	"io"
	"regexp"
	"strconv"
	"strings"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
)

const reviewImagesLong = `Shows on a pull request each image its change adds, changes, moves or removes,
a changed one before and after (services/gctk/review/images.go). The change is
the diff a review reads, from the merge base of --base and --oid to --oid, in
the clone --repo names (default: here). A regular file is an image by its
extension: png, jpg, jpeg, gif, svg or webp, in any case.

Each image is drawn from the committed file, at the address GitHub serves it
from in the PR's repository at a commit: a before at the merge base, an after
at --oid. A reader's own session loads it, from a private repository too, and
nothing is uploaded, so both commits must be on GitHub, as a PR's base and head
are. The images group by directory, and within one by the stem their names
share once the parts that vary across the directory's images drop, such as a
theme, a device or a browser. A change that shows more than four images closes
each group, so the page shows one line a group until a reader opens it. Each
comment fits GitHub's limit on a comment's length, and a change too long for
one takes several, each saying which it is.

Each comment posts through the writer of the city's PR posts, pr-post.sh in the
directory GCTK_SCRIPTS_DIR names, and the command prints what the writer
printed, then a last line naming what it posted: how many comments, on which
PR, how many images of each kind, in how many groups, at which commit. --pr must
be a pull request of the repository the clone's origin names. With --dry-run
the command prints each comment and posts nothing.

exit: 0 posted, or printed with --dry-run
      1 a commit or the clone's origin did not read, --pr is a pull request of
        another repository, or a comment did not post, which names the
        comments that did
      2 usage
      3 the change touches no image, so nothing posted`

// pullRequestURL is a pull request's address on its host.
var pullRequestURL = regexp.MustCompile(`^https://([^/]+)/([^/]+/[^/]+)/pull/([0-9]+)/?$`)

func newReviewImagesCmd(stdout, stderr io.Writer) *cobra.Command {
	var pr, base, oid, repo string
	var dryRun bool
	cmd := &cobra.Command{
		Use:   "images --pr <url> --base <ref> --oid <commit> [--repo <dir>] [--dry-run]",
		Short: "show on a PR each image its change adds or changes, a changed one before and after",
		Long:  reviewImagesLong,
		Args:  cobra.NoArgs,
		RunE: func(*cobra.Command, []string) error {
			switch {
			case base == "":
				return errors.New("--base names the ref the change is reviewed against")
			case oid == "":
				return errors.New("--oid names the reviewed commit")
			}
			m := pullRequestURL.FindStringSubmatch(strings.TrimSpace(pr))
			if m == nil {
				return fmt.Errorf("--pr %q is not a pull request's address, https://<host>/<owner>/<name>/pull/<number>", pr)
			}
			number, err := strconv.Atoi(m[3])
			if err != nil || number <= 0 {
				return fmt.Errorf("--pr %q names no pull request number", pr)
			}
			return exit(reviewImages(imagesCall{dir: repo, host: m[1], repo: m[2], number: number, pr: pr,
				base: base, oid: oid, dryRun: dryRun}, stdout, stderr))
		},
	}
	f := cmd.Flags()
	f.StringVar(&pr, "pr", "", "the pull request to post on, as its address")
	f.StringVar(&base, "base", "", "the ref the change is reviewed against, such as origin/main")
	f.StringVar(&oid, "oid", "", "the reviewed commit")
	f.StringVar(&repo, "repo", ".", "the clone that holds both commits")
	f.BoolVar(&dryRun, "dry-run", false, "print each comment and post nothing")
	return cmd
}

// imagesCall is one `gctk review images`: the clone, the PR as its host, its
// repository and its number, and the change.
type imagesCall struct {
	dir, host, repo, pr, base, oid string
	number                         int
	dryRun                         bool
}

func reviewImages(c imagesCall, stdout, stderr io.Writer) int {
	show, err := review.ShowImages(c.dir, c.pr, c.host, c.repo, c.number, c.base, c.oid)
	if err != nil {
		fmt.Fprintf(stderr, "gctk review images: %v\n", err)
		if errors.Is(err, review.ErrNoImages) {
			return 3
		}
		return 1
	}
	if c.dryRun {
		for i, b := range show.Comments {
			fmt.Fprintf(stdout, "== comment %d of %d\n%s\n", i+1, len(show.Comments), b)
		}
		fmt.Fprintf(stdout, "gctk review images: would post %s\n", show.Summary())
		return 0
	}
	printed, err := show.Post(gascity.New().In(c.dir))
	for _, out := range printed {
		fmt.Fprintln(stdout, out)
	}
	if err != nil {
		fmt.Fprintf(stderr, "gctk review images: %v\n", err)
		return 1
	}
	fmt.Fprintf(stdout, "gctk review images: posted %s\n", show.Summary())
	return 0
}
