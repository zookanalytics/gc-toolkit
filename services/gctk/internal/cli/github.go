package cli

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"regexp"
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

// quoteHub is the read a quote is made from, and the mark its follow-up
// leaves on each post it follows up.
type quoteHub interface {
	Posted(repo string, number int) (*gh.Posted, error)
	AddReaction(subject, content string) error
}

// newQuoteHub is the GitHub read a quote makes, on host. A variable so a test
// can give it a fake.
var newQuoteHub = func(host string) quoteHub { return gh.NewBounded(host, quoteReadBound) }

// quoteFollowUp files the operator's follow-up for the posts a quote held on
// the item at url, number in repo, a PR when pull is true and an issue
// otherwise, and returns the bead it filed it on, "" when no post was owed one
// by the time it held the lock. It holds the record lock of the store gc
// routes the command to, which the landing order's take holds too, waiting for
// it as long as any verb other than a run does, and under it quotes the item
// again through hub, so it files for the posts no filer has followed up by
// then, and marks each through hub once its gate is filed (pr.FollowUpHeld).
// Its gates go on the bead in that store that owns the PR, else on a finding
// of its own for the item (pr.FollowUpSubject). The gates and the finding are
// filed through human-gate.sh and patrol-finding.sh in the pack's scripts
// directory, which an agent's own call of gctk names in no GCTK_SCRIPTS_DIR,
// so it is resolved as the definition of feedback resolves it. A variable so a
// test can record it.
var quoteFollowUp = func(hub quoteHub, url, repo string, number int, pull bool, held []quote.Held) (string, error) {
	db, err := gcbd.New().Route()
	if err != nil {
		return "", err
	}
	l, err := ledger.Open(db)
	if err != nil {
		return "", err
	}
	scripts, err := feedback.ScriptsDir()
	if err != nil {
		return "", err
	}
	if err := os.Setenv("GCTK_SCRIPTS_DIR", scripts); err != nil {
		return "", err
	}
	ctx, rt := context.Background(), gascity.New()
	read := func() ([]quote.Held, error) {
		p, err := hub.Posted(repo, number)
		if err != nil {
			return nil, err
		}
		q, err := quote.Of(p, "")
		if err != nil {
			return nil, err
		}
		return q.Held(), nil
	}
	subject := func() (string, error) {
		return pr.FollowUpSubject(ctx, l, findings{rt: rt}, repo, number, pull, url)
	}
	return pr.FollowUpHeld(ctx, db, recordLockWait, actGates{rt: rt}, hub, read, subject, repo, number, pull, held)
}

// findingScope is the scope a held post's finding is filed in, which
// patrol-finding.sh records on it.
const findingScope = "github-quote"

// findingFiled is the line patrol-finding.sh prints once it has filed a
// finding, or found the live one, under a key: the finding's id, then the key
// in brackets.
var findingFiled = regexp.MustCompile(`(?m)^patrol-finding: (?:filed ([A-Za-z0-9][A-Za-z0-9._-]*) for|([A-Za-z0-9][A-Za-z0-9._-]*) already tracks) \[([A-Za-z0-9._-]+)\]`)

// findings files a held post's finding through the runtime adapter, which runs
// the pack's patrol-finding.sh from the scripts directory GCTK_SCRIPTS_DIR
// names, as a task in findingScope, stopped once ctx ends. It files no first
// reaction, since the human gate the follow-up files on the finding is what
// asks the operator. A finding the script does not file is an error carrying
// why, and so is a script whose output names no finding under the key.
type findings struct{ rt gascity.Runtime }

func (f findings) File(ctx context.Context, key, title, message string) (string, error) {
	res := f.rt.Within(ctx).Script("patrol-finding.sh", "--scope", findingScope, "--key", key, "--title", title,
		"--message", message, "--type", "task", "--no-react")
	if fl := res.Failure(); fl != "" {
		return "", fmt.Errorf("patrol-finding.sh [%s]: %s", key, fl)
	}
	for _, m := range findingFiled.FindAllStringSubmatch(res.Output, -1) {
		if m[3] == key {
			return m[1] + m[2], nil
		}
	}
	return "", fmt.Errorf("patrol-finding.sh [%s] named no finding: %s", key, res.Tail())
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
operator gets one human gate for each outside account, under the key
outside-post-<login>, which a later read finds open. The gate goes on the bead
that owns the PR, and on an issue, or on a PR no bead in the store owns, on a
finding of its own for the item, which patrol-finding.sh files under the key
outside-posts.<owner>.<repo>.<number>. Once its
gate is filed or found open, each such post takes the city's EYES, the mark the
landing order's take leaves on a post it took, and no later read files a gate
for a post that carries it. The follow-up is filed under the store's record
lock, which the take holds too, and decides on the posts as GitHub holds them
once the lock is taken, so reads at once file it once. A post reaches agents
once the operator says what it says in a post of their own. On any other
repository, such as an upstream project's, nothing is held, and the block marks
all of it as another repository's text.

With --description it prints the title and the body alone. With --json it
prints the quote as one JSON object: the repository, the number, the URL,
whether it is a PR, whether the repository is the city's own, the title, and
each post with its kind, and on a post that is not held its id, URL, author,
time and text in the same inert form.

exit: 0 the quote printed, and any follow-up it owed was filed
      1 GitHub's read failed, the URL names no post the item holds, or the
        follow-up did not file or a post's mark did not land, which stderr
        names after the quote printed
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
			hub := newQuoteHub(host)
			p, err := hub.Posted(repo, number)
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
			owed := pr.Owed(held)
			if len(owed) == 0 {
				fmt.Fprintf(stderr, "gctk github quote: held %d post(s) by an outside account, each of which the "+
					"city has followed up already\n", len(held))
				return nil
			}
			bead, err := quoteFollowUp(hub, p.URL, repo, number, p.PullRequest, owed)
			switch {
			case err != nil:
				fmt.Fprintf(stderr, "gctk github quote: held %d post(s) by an outside account, and the operator's "+
					"follow-up did not complete: %v\n", len(owed), err)
				return exit(1)
			case bead == "":
				fmt.Fprintf(stderr, "gctk github quote: held %d post(s) by an outside account, each of which another "+
					"read or the landing order followed up before this one could\n", len(owed))
			default:
				fmt.Fprintf(stderr, "gctk github quote: held %d post(s) by an outside account, and the operator has "+
					"a follow-up for them\n", len(owed))
			}
			return nil
		},
	}
	c.Flags().BoolVar(&description, "description", false, "print the title and the body alone")
	c.Flags().BoolVar(&asJSON, "json", false, "print the quote as one JSON object")
	return c
}
