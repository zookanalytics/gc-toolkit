package cli

import (
	"errors"
	"fmt"
	"io"
	"strconv"
	"strings"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
)

// `gctk pr answer <run>` is a review round's post (specs/tk-1tfzr71.161/design.md,
// section 6), which the round's step calls through review-run.sh post: it
// builds the pr domain's Landing over the adapters and prints what the post did.

const prAnswerLong = `Posts the round of a review run on the pull request the run judges, which the
round's steps call through review-run.sh post (services/gctk/pr/answer.go):
triage for the posts it answers, and rule-and-repair for the rest of the round.
<run> is the run's root, or any bead poured under it, and --iteration the
iteration whose round it posts, else the latest whose round wrote its rulings,
triage's answers among them.

It answers each person's post an ask the round ruled carries, where the post
was made, and posts the head's comment (gctk review comment), or edits the
city's comment its mark finds, once the round has ruled all it will:
rule-and-repair wrote its rulings, or triage left it nothing, no check picked
and every ask the round can take answered. An inline comment gets a reply in
its thread. A review's message or a conversation comment gets a comment that
links it where its ruling owes words: declined, deferred, answered, a question,
a post that settles one, and a post made while a question it does not settle
is open. A must-fix point on such a post owes none, since the head's comment
names its commit, and a wordless answer owes none on any post, the city's
THUMBS_UP alone. A must-fix point is answered once the round has pushed its
fix.
Each post the round ruled then gets the city's THUMBS_UP, once its words are on
the PR, but a question's, which waits on its gate; its reply names the gate and
its thread stays open. A thread is resolved once each post in it carries the
city's THUMBS_UP, the city's own posts aside.

A ruling's settles names the gate of a question a person's post settles, and
with moot one the post makes moot: the call closes that gate with the post's
words and its URL as its answer, headed ruled: or moot:, and the post's reply
says so. A person's standing request for changes is dismissed with a one-line
note once each of its points carries the city's THUMBS_UP, after its author is
asked to review again. Each reply opens with a line naming its ask, so a call
run again posts nothing twice.

Every post goes through pr-post.sh, from the scripts directory GCTK_SCRIPTS_DIR
names. The PR must be in the rig's own repository, the one the origin of the
clone it runs in names ($GC_RIG_ROOT, else the working directory). It prints
what it did, one line each.

exit: 0 posted, or nothing to answer
      1 an answer did not land: what landed stands, and a call run again posts
        the rest
      2 the store or GitHub did not answer
      3 refused: the bead is not a review run's, its iteration has no rulings,
        the bead that owns the PR names none, or the PR is outside the rig's
        own repository
      64 usage`

func newPRAnswerCmd(stdout, stderr io.Writer) *cobra.Command {
	var db string
	var iteration int
	cmd := &cobra.Command{
		Use:         "answer <run> [--iteration <n>]",
		Short:       "post a review run's round on its PR: the head's comment, and each person's post answered where it was made",
		Long:        prAnswerLong,
		Args:        cobra.ExactArgs(1),
		Annotations: map[string]string{usageExitKey: "64"},
		RunE: func(_ *cobra.Command, args []string) error {
			run := strings.TrimSpace(args[0])
			if run == "" {
				return errors.New("name the review run")
			}
			if iteration < 0 {
				return fmt.Errorf("--iteration %d names no iteration", iteration)
			}
			l, err := landing(db, "", run)
			if err != nil {
				fmt.Fprintf(stderr, "gctk pr answer: %v\n", err)
				return exit(2)
			}
			return exit(prAnswer(l, run, iteration, stdout, stderr))
		},
	}
	cmd.Flags().StringVar(&db, "db", "", "the store's .beads directory, else the store gc routes the run to")
	cmd.Flags().IntVar(&iteration, "iteration", 0, "the iteration whose round to post, from 1, else the latest with rulings")
	return cmd
}

// prAnswer posts the round through l, prints what it did, and returns the
// command's exit.
func prAnswer(l pr.Landing, run string, n int, stdout, stderr io.Writer) int {
	got, err := l.AnswerRound(run, n)
	say := func(format string, args ...any) { fmt.Fprintf(stdout, got.Bead+": "+format+"\n", args...) }
	if got.Comment != "" {
		say("%s the head's comment for iteration %d of %s", got.Comment, got.Iteration, got.Run)
	}
	for _, g := range got.Settled {
		say("closed the gate %s with the post that settles its question", g)
	}
	for _, u := range got.Replied {
		say("replied to %s", u)
	}
	for _, u := range got.Marked {
		say("marked %s answered", u)
	}
	for _, u := range got.Resolved {
		say("resolved the thread of %s", u)
	}
	for _, who := range got.Requested {
		say("asked %s to review again", who)
	}
	for _, u := range got.Dismissed {
		say("dismissed %s, every point of which is answered", u)
	}
	for _, why := range got.Left {
		say("left %s", why)
	}
	var refused *pr.AnswerRefusal
	var notRun *review.NotARun
	var origin *pr.OriginError
	var unanswered *pr.Unanswered
	switch {
	case err == nil:
		if got.Comment == "" && len(got.Replied)+len(got.Marked) == 0 {
			fmt.Fprintf(stdout, "%s: nothing to answer in iteration %d\n", firstOr(got.Bead, run), got.Iteration)
		}
		return 0
	case errors.As(err, &refused), errors.As(err, &notRun), errors.As(err, &origin):
		fmt.Fprintf(stderr, "gctk pr answer: %v\n", err)
		return 3
	case errors.As(err, &unanswered):
		fmt.Fprintf(stderr, "gctk pr answer: %v\n", err)
		return 1
	}
	fmt.Fprintf(stderr, "gctk pr answer: %s: the store or GitHub did not answer: %v\n", run, err)
	return 2
}

func firstOr(s, or string) string {
	if s != "" {
		return s
	}
	return or
}

// prPosts is the writer of the city's posts, pr-post.sh, run through the
// runtime adapter from the scripts directory GCTK_SCRIPTS_DIR names, which
// carries the city's mark on every body it posts.
type prPosts struct{ rt gascity.Runtime }

func (p prPosts) Comment(host, repo string, number int, body string) error {
	return posted("comment", p.rt.Script("pr-post.sh", "comment", "--repo", host+"/"+repo, "--pr", strconv.Itoa(number), "--body", body))
}

func (p prPosts) Edit(host, repo string, id int64, body string) error {
	return posted("edit", p.rt.Script("pr-post.sh", "edit", "--repo", host+"/"+repo, "--comment", strconv.FormatInt(id, 10), "--body", body))
}

func (p prPosts) Reply(host, thread, body string) error {
	return posted("reply", p.rt.Script("pr-post.sh", "reply", "--host", host, "--thread", thread, "--body", body))
}

// posted is the error of a pr-post.sh call that did not exit 0.
func posted(verb string, res gascity.Result) error {
	if f := res.Failure(); f != "" {
		return fmt.Errorf("pr-post.sh %s: %s", verb, f)
	}
	return nil
}
