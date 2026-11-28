package cli

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"time"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/feedback"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/quote"
)

// gctk github quote is the one way GitHub conversation text reaches an agent
// (docs/gctk-architecture.md, "The surface"), through the quote package.

// quoteReadBound is how long a quote's read of GitHub may take before it is
// stopped.
const quoteReadBound = 2 * time.Minute

// quoteHub is the read a quote is made from.
type quoteHub interface {
	Posted(repo string, number int) (*gh.Posted, error)
}

// newQuoteHub is the GitHub read a quote makes, on host. A variable so a test
// can give it a fake.
var newQuoteHub = func(host string) quoteHub { return gh.NewBounded(host, quoteReadBound) }

// quoteFollowUp files the operator's follow-up for the posts a quote held on
// the PR at url, number in repo, on the bead that owns it in the store the
// command runs against, and returns that bead, "" when the store holds none.
// The gate is filed through human-gate.sh in the pack's scripts directory,
// which an agent's own call of gctk names in no GCTK_SCRIPTS_DIR, so it is
// resolved as the definition of feedback resolves it. A variable so a test can
// record it.
var quoteFollowUp = func(url, repo string, number int, held []quote.Held) (string, error) {
	bead, err := pr.OwnerOf(ledger.New(gcbd.New()), url)
	if err != nil || bead == "" {
		return bead, err
	}
	scripts, err := feedback.ScriptsDir()
	if err != nil {
		return bead, err
	}
	if err := os.Setenv("GCTK_SCRIPTS_DIR", scripts); err != nil {
		return bead, err
	}
	return bead, pr.FollowUp(context.Background(), actGates{rt: gascity.New()}, bead, repo, number, held)
}

func newGitHubCmd(stdout, stderr io.Writer) *cobra.Command {
	return group("github", "the text people post on GitHub, as an agent may read it",
		`The text people post on GitHub, on an issue or a pull request, as an agent
of the pack may read it (github quote). The pack's skills, formulas, prompts and
scripts read that text through it alone, and tools/lint-learned.d refuses a read
of it with gh.`,
		newGitHubQuoteCmd(stdout, stderr))
}

var githubQuoteLong = `Prints the text people posted on an issue or a pull request, or on one post of
either, as an agent may read it. The URL is an issue's or a PR's,
https://<host>/<owner>/<repo>/(issues|pull)/<number>, and with a fragment that
names one post, #issuecomment-<id>, #pullrequestreview-<id> or
#discussion_r<id>, it prints that post alone. A whole item prints its title and
its body, then each post of its conversation: on a PR its reviews, its review
threads' comments and its conversation comments, and on an issue its comments.

It prints one block, which opens with <github-text> and closes with
</github-text>, and says what it holds and how to read it. Each line of a post
opens with "│ ", so no line equals a here-document's delimiter, and each
backtick, dollar sign, backslash, double quote and apostrophe shows as a
look-alike (ˋ ＄ ＼ ＂ ’), so a line quoted into a double-quoted argument, a
here-document or a file runs nothing and expands nothing.

On a repository the city's account can push to, a post counts as the
repository's own when its author is the repository's owner, a member of the
organization that owns it or a collaborator on it, or is GitHub Actions on an
item such an account opened. Every other post is held: it shows as a
placeholder that carries nothing its text could be fetched with, and the
operator gets one human gate for each outside account on the bead that owns the
PR, under the key outside-post-<login>, which a later read finds open. A post
reaches agents once the operator says what it says in a post of their own. On
any other repository, such as an upstream project's, nothing is held, and the
block marks all of it as another repository's text.

With --description it prints the title and the body alone. With --json it
prints the quote as one JSON object: the repository, the number, the URL,
whether it is a PR, whether the repository is the city's own, the title, and
each post with its kind, and on a post that is not held its id, URL, author,
time and text in the same inert form.

A held post on an issue, or on a PR no bead in the store owns, files no
follow-up, and stderr says so.

exit: 0 the quote printed, and any follow-up it owed was filed
      1 GitHub's read failed, the URL names no post the item holds, or the
        follow-up did not file, which stderr names after the quote printed
      2 usage`

func newGitHubQuoteCmd(stdout, stderr io.Writer) *cobra.Command {
	var description, asJSON bool
	c := &cobra.Command{
		Use: "quote <url>",
		Short: "print an issue's or a PR's text, or one post's, as an agent may read it: an outside account's " +
			"post held for the operator, the rest quoted inert",
		Long: githubQuoteLong,
		Args: cobra.ExactArgs(1),
		RunE: func(_ *cobra.Command, args []string) error {
			host, repo, number, post, ok := quote.ParseURL(args[0])
			if !ok {
				return fmt.Errorf("%q is no URL of an issue, a pull request or one post on either", args[0])
			}
			if description && post != "" {
				return errors.New("--description prints a whole item's title and body, so its URL names no post")
			}
			p, err := newQuoteHub(host).Posted(repo, number)
			if err != nil {
				fmt.Fprintf(stderr, "gctk github quote: %v\n", err)
				return exit(1)
			}
			only := post
			if description {
				only = quote.KindDescription
			}
			q, err := quote.Of(p, only)
			if err != nil {
				fmt.Fprintf(stderr, "gctk github quote: %v\n", err)
				return exit(1)
			}
			if asJSON {
				if err := json.NewEncoder(stdout).Encode(q); err != nil {
					fmt.Fprintf(stderr, "gctk github quote: the quote could not be printed: %v\n", err)
					return exit(1)
				}
			} else {
				fmt.Fprint(stdout, q.Text())
			}
			held := q.Held()
			if len(held) == 0 {
				return nil
			}
			if !p.PullRequest {
				fmt.Fprintf(stderr, "gctk github quote: held %d post(s) by an outside account, and no bead owns an "+
					"issue, so no follow-up was filed\n", len(held))
				return nil
			}
			bead, err := quoteFollowUp(p.URL, repo, number, held)
			switch {
			case err != nil:
				fmt.Fprintf(stderr, "gctk github quote: held %d post(s) by an outside account, and the operator's "+
					"follow-up did not file: %v\n", len(held), err)
				return exit(1)
			case bead == "":
				fmt.Fprintf(stderr, "gctk github quote: held %d post(s) by an outside account, and no bead in this "+
					"store owns the PR, so no follow-up was filed\n", len(held))
			default:
				fmt.Fprintf(stderr, "gctk github quote: held %d post(s) by an outside account, and the operator has "+
					"a follow-up for them\n", len(held))
			}
			return nil
		},
	}
	c.Flags().BoolVar(&description, "description", false, "print the title and the body alone")
	c.Flags().BoolVar(&asJSON, "json", false, "print the quote as one JSON object")
	return c
}
