package cli

import (
	"errors"
	"fmt"
	"io"
	"strings"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
)

// `gctk pr draft <bead>` and `gctk pr withdraw <bead>` are the draft cycle's and
// the approval withdrawal's verbs (specs/tk-1tfzr71.108/design.md, sections 4
// and 5): a writer of the city returns a PR to draft before it pushes, and
// triage files the withdrawal of the approvals a material change leaves
// behind, which the landing order carries out. Each builds the pr domain's
// Landing over the adapters and prints what it did.

const prDraftLong = `Returns the pull request a bead owns to draft before a writer of the city
pushes a new head onto it, which starts a round of the city's work on the PR.
It reads the PR's draft flag first and converts the PR only when it is ready,
so a round's first push converts it and a later push changes nothing, and a
retry, a restart or a person's own toggle leaves the round to go on from where
the PR stands. A return to draft dismisses no approval. The landing order marks
the PR ready again once the review loop has passed at the head the refinery
validated.

The PR is the one --pr names, else the one the bead's record names, else the
one the bead records for the refinery to reuse (existing_pr). It must be in
the rig's own repository, the one the origin of the clone it runs in names
($GC_RIG_ROOT, else the working directory), open, and open from the bead's
branch.

exit: 0 the PR is a draft: it was ready and is converted, or was a draft
        already
      1 usage, or a PR outside the rig's own repository
      2 the store or GitHub did not answer, or the conversion was refused or
        not answered, so the PR may still be ready and a writer pushes nothing
      3 refused: the bead names no PR, or its PR is not open, or not open from
        the bead's branch; nothing was changed`

const prWithdrawLong = `Files the withdrawal of the approvals on the pull request a bead owns that
were given on a commit that does not contain --head, the head triage ruled a
material change. The withdrawal is a task bead that blocks the bead, names the
head in withdraw_head and carries --reason as its description, which each
dismissal tells its approver: the call, what it means for the PR, and where to
look. The evaluator holds the PR from the moment it is filed, and the landing
order carries it out (gctk pr reconcile): it dismisses each approval that
stands on a commit that does not contain the head, closes the withdrawal once
none stands, and asks a person through a human gate when GitHub refuses. An
approval of the head itself, or of any later head of the branch, stands.

A withdrawal for --head already filed on the bead, open or closed, is found and
not filed again. The bead must own a PR on the record. The call holds the
store's record lock, and sets the record's marker first when it carries none,
as on a bead the landing order sent back to the refinery, so the order reads
the record until the withdrawal is carried out. It prints the withdrawal's id.

exit: 0 filed, or found already filed
      1 usage
      2 the store or the lock did not answer; when the create did not answer,
        the withdrawal may have been filed, and a retry finds it
      3 refused: the store holds no such bead, it is closed, it owns no PR on
        the record, or it moved since the call read it; nothing was filed`

func newPRDraftCmd(stdout, stderr io.Writer) *cobra.Command {
	var url, db string
	cmd := &cobra.Command{
		Use:         "draft <bead> [--pr <url>]",
		Short:       "return the PR a bead owns to draft before the city pushes onto it",
		Long:        prDraftLong,
		Args:        cobra.ExactArgs(1),
		Annotations: map[string]string{usageExitKey: "1"},
		RunE: func(_ *cobra.Command, args []string) error {
			bead := strings.TrimSpace(args[0])
			if bead == "" {
				return errors.New("name the bead that owns the PR")
			}
			if _, _, _, ok := record.ParseURL(url); url != "" && !ok {
				return fmt.Errorf("--pr %q is not a pull request's URL (https://<host>/<owner>/<repo>/pull/<number>)", url)
			}
			return exit(prDraft(bead, url, db, stdout, stderr))
		},
	}
	cmd.Flags().StringVar(&url, "pr", "", "the PR's URL, when the bead's record names none yet")
	cmd.Flags().StringVar(&db, "db", "", "the store's .beads directory, else the store gc routes the bead to")
	return cmd
}

func prDraft(bead, url, db string, stdout, stderr io.Writer) int {
	l, err := landing(db, "", bead)
	if err != nil {
		fmt.Fprintf(stderr, "gctk pr draft: %v\n", err)
		return 2
	}
	d, err := l.Draft(bead, url)
	var refused *pr.DraftRefusal
	var origin *pr.OriginError
	switch {
	case err == nil && d.Converted:
		fmt.Fprintf(stdout, "%s: %s returned to draft\n", bead, d.URL)
		return 0
	case err == nil:
		fmt.Fprintf(stdout, "%s: %s is a draft already\n", bead, d.URL)
		return 0
	case errors.As(err, &refused):
		fmt.Fprintf(stderr, "gctk pr draft: %v\n", err)
		return 3
	case errors.As(err, &origin):
		fmt.Fprintf(stderr, "gctk pr draft: %s: the PR is left as it stands: %v\n", bead, err)
		return 1
	}
	fmt.Fprintf(stderr, "gctk pr draft: %s: %v\n", bead, err)
	return 2
}

func newPRWithdrawCmd(stdout, stderr io.Writer) *cobra.Command {
	var head, reason, db string
	cmd := &cobra.Command{
		Use:         "withdraw <bead> --head <oid> --reason <text>",
		Short:       "file the withdrawal of the approvals a material change leaves behind",
		Long:        prWithdrawLong,
		Args:        cobra.ExactArgs(1),
		Annotations: map[string]string{usageExitKey: "1"},
		RunE: func(_ *cobra.Command, args []string) error {
			bead := strings.TrimSpace(args[0])
			if bead == "" {
				return errors.New("name the bead that owns the PR")
			}
			if !record.IsObjectID(head) {
				return fmt.Errorf("--head %q is not a full commit id", head)
			}
			if strings.TrimSpace(reason) == "" {
				return errors.New("--reason says what the dismissal tells each approver")
			}
			return exit(prWithdraw(bead, head, reason, db, stdout, stderr))
		},
	}
	cmd.Flags().StringVar(&head, "head", "", "the head triage ruled a material change, a full commit id")
	cmd.Flags().StringVar(&reason, "reason", "", "the call, what it means for the PR, and where to look")
	cmd.Flags().StringVar(&db, "db", "", "the store's .beads directory, else the store gc routes the bead to")
	return cmd
}

func prWithdraw(bead, head, reason, db string, stdout, stderr io.Writer) int {
	l, err := landing(db, "", bead)
	if err != nil {
		fmt.Fprintf(stderr, "gctk pr withdraw: %v\n", err)
		return 2
	}
	w, err := l.Withdraw(bead, head, reason)
	var refused *pr.WithdrawRefusal
	switch {
	case err == nil:
		fmt.Fprintln(stdout, w.ID)
		if w.Filed {
			fmt.Fprintf(stderr, "gctk pr withdraw: filed %s, which holds %s until the landing order carries it out\n", w.ID, bead)
		} else {
			fmt.Fprintf(stderr, "gctk pr withdraw: %s already withdraws the approvals of %s without %s\n", w.ID, bead, head)
		}
		return 0
	case errors.As(err, &refused):
		fmt.Fprintf(stderr, "gctk pr withdraw: %v\n", err)
		return 3
	}
	fmt.Fprintf(stderr, "gctk pr withdraw: %s: %v\n", bead, err)
	return 2
}
