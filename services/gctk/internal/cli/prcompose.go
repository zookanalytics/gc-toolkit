package cli

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
)

// `gctk pr compose <bead>` is how the refinery's merge-push step asks what the
// title and body of a PR it opens should say. With --edit it brings an open
// PR's title and body to that composition itself, as the refinery's merge-push
// step does on a PR it publishes onto and a review run's push does. The pr
// package composes and edits; this command parses the request and prints the
// result.

const prComposeLong = `Prints the title and body a PR the bead owns opens with, as the bead says
they should be. The title is the bead's own, opened with a conventional-commit
type when it does not open with one, then its id. The body carries two marked
sections:

  summary        the managed summary region: what the change does (the bead's
                 PR summary, else its dispatch text) and the refinery
                 handoff's facts at --head
  branch-beads   every bead whose work is on the bead's branch, once there is
                 more than the PR's own

--target is the branch the PR opens into, or is open into: the base the
caller resolved for the PR's create, or read the open PR's base against. The
summary region names it, and never the bead's own target or merged_target,
since a bead with no target opens into the rig's default branch and a
retargeted bead's merged_target names its earlier base.

--gates is the gate set the bead's check set resolves to at --head, as
gctk review checks --resolve <set> --through open-as-draft --with-phase prints
it, empty for none. Without it a region that must be written is not: the body
printed carries none, and --edit leaves the PR's as it stands.

It prints one JSON object: {"title", "body", "summary", "branch_beads",
"branch_bead_count"}. summary and branch_beads are each section's outcome:
written (the body carries it), needs-gates (the summary region, given no
--gates), single (one bead's work, so no section) or unread (the beads on the
branch did not read). title is empty when the bead's title has no words.

With --edit the PR is open, and the command brings its title and body to the
composition in place of printing it. It reads the title and body the PR shows,
composes with that body as the one published, and edits, in one request, the
title when it differs in more than spacing and the body when a section is
written, and nothing when neither moved. Each section is read by its markers
and kept current while the text people add stays as it is. The summary region
is rewritten only when it no longer says what the bead says at --head, so text
a summary carries, a collapsed section included, reads as itself. A bead whose
title has no words leaves the PR's title as it stands. The PR is the one --pr
names, else the one the bead's record names, else the one it records for the
refinery to reuse (existing_pr), in the rig's own repository, the one the
origin of the clone it runs in names ($GC_RIG_ROOT, else the working
directory), and open from the bead's branch.
It prints one line saying what it edited, and names on stderr each section it
left as it stands: one the body carries no markers it can read for, as in a
hand-written body, the summary region when it must be written and no --gates
gave the gate set it names, and the branch-beads section when its beads did
not read.

exit: 0 printed; with --edit, the PR shows the composition, edited or already,
        but for each section named on stderr as left as it stands
      1 usage, or with --edit a PR outside the rig's own repository
      2 the bead or the store holding it did not read: nothing is printed;
        with --edit, GitHub did not answer or refused the edit, so the PR may
        show either text, and a retry is safe
      3 with --edit, refused: the bead names no PR, or its PR is not open, or
        not open from the bead's branch; nothing was changed`

type prComposeOpts struct {
	head, target, gates, pr string
	edit                    bool
}

func newPRComposeCmd(stdout, stderr io.Writer) *cobra.Command {
	var o prComposeOpts
	cmd := &cobra.Command{
		Use:         "compose <bead>",
		Short:       "the PR's conventional-commit title and its body's managed sections, from the bead that owns it",
		Long:        prComposeLong,
		Args:        cobra.ExactArgs(1),
		Annotations: map[string]string{usageExitKey: "1"},
		RunE: func(c *cobra.Command, args []string) error {
			req, err := o.request(c)
			if err != nil {
				return err
			}
			bead := strings.TrimSpace(args[0])
			if bead == "" {
				return errors.New("name the bead that owns the PR")
			}
			if o.edit {
				return exit(prComposeEdit(bead, strings.TrimSpace(o.pr), req, stdout, stderr))
			}
			return exit(prCompose(bead, req, stdout, stderr))
		},
	}
	f := cmd.Flags()
	f.StringVar(&o.head, "head", "", "the commit the PR opens at, or carries now")
	f.StringVar(&o.target, "target", "", "the branch the PR opens into, or is open into")
	f.StringVar(&o.gates, "gates", "", "the gates the bead's check set resolves to at --head, one <check>\\t<phase> per line")
	f.BoolVar(&o.edit, "edit", false, "edit the open PR's title and body to the composition where they differ, reading the body from the PR")
	f.StringVar(&o.pr, "pr", "", "with --edit, the PR's URL, when the bead's record names none yet")
	return cmd
}

// request is the composition the flags ask for, or the usage error that refuses
// it.
func (o prComposeOpts) request(c *cobra.Command) (pr.Request, error) {
	req := pr.Request{Head: strings.TrimSpace(o.head), Target: strings.TrimSpace(o.target)}
	if req.Head == "" {
		return req, errors.New("the summary region names the PR's head: give --head")
	}
	if req.Target == "" {
		return req, errors.New("the summary region names the branch the PR opens into: give --target")
	}
	if c.Flags().Changed("gates") {
		req.Gates = pr.ParseGates(o.gates)
		if req.Gates == nil {
			req.Gates = []pr.Gate{}
		}
	}
	if url := strings.TrimSpace(o.pr); url != "" {
		if !o.edit {
			return req, errors.New("--pr names the open PR --edit edits: give it with --edit")
		}
		if _, _, _, ok := record.ParseURL(url); !ok {
			return req, fmt.Errorf("--pr %q is not a pull request's URL (https://<host>/<owner>/<repo>/pull/<number>)", url)
		}
	}
	return req, nil
}

// prCompose prints the composition the bead's PR opens with.
func prCompose(bead string, req pr.Request, stdout, stderr io.Writer) int {
	// Every read is pinned to the store gc routes the bead to. The beads on its
	// branch are read by their keys, which name no bead, so an unpinned read of
	// them would answer from the store the caller sits in.
	l, err := ledger.Open("", bead)
	if err != nil {
		fmt.Fprintf(stderr, "gctk pr compose: the store holding %s did not resolve: %v\n", bead, err)
		return 2
	}
	got, err := pr.Compose(l, bead, req)
	if err != nil {
		fmt.Fprintf(stderr, "gctk pr compose: %s did not read: %v\n", bead, err)
		return 2
	}
	if got.Unread != nil {
		fmt.Fprintf(stderr, "gctk pr compose: the beads on %s's branch did not read: %v; the branch-beads section is left as it stands\n", bead, got.Unread)
	}
	// The body's markers are HTML comments, which the encoder would otherwise
	// escape: a reader of the JSON sees them as the PR shows them.
	enc := json.NewEncoder(stdout)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(struct {
		Title           string     `json:"title"`
		Body            string     `json:"body"`
		Summary         pr.Outcome `json:"summary"`
		BranchBeads     pr.Outcome `json:"branch_beads"`
		BranchBeadCount int        `json:"branch_bead_count"`
	}{got.Title, got.Body, got.Summary, got.BranchBeads, got.BranchBeadCount}); err != nil {
		fmt.Fprintf(stderr, "gctk pr compose: the composition of %s did not print: %v\n", bead, err)
		return 2
	}
	return 0
}

// prComposeEdit brings the title and body of the bead's open PR, the one url
// names when it names one, to its composition and says what it edited.
func prComposeEdit(bead, url string, req pr.Request, stdout, stderr io.Writer) int {
	l, err := landing("", "", bead)
	if err != nil {
		fmt.Fprintf(stderr, "gctk pr compose: the store holding %s did not resolve: %v\n", bead, err)
		return 2
	}
	got, err := l.Edit(bead, url, req)
	if err != nil {
		return editFailed(bead, err, stderr)
	}
	left := false
	if c := got.Composition; c != nil {
		if c.Unread != nil {
			fmt.Fprintf(stderr, "gctk pr compose: the beads on %s's branch did not read: %v; the branch-beads section is left as it stands\n", bead, c.Unread)
			left = true
		}
		for _, s := range []struct {
			outcome pr.Outcome
			name    string
		}{{c.Summary, "summary region"}, {c.BranchBeads, "branch-beads section"}} {
			switch s.outcome {
			case pr.Unmanaged:
				fmt.Fprintf(stderr, "gctk pr compose: the body of %s carries no %s its markers let it read, so it is left as it stands\n", got.URL, s.name)
				left = true
			case pr.NeedsGates:
				fmt.Fprintf(stderr, "gctk pr compose: the %s of %s must be written, and no --gates gave the gate set it names, so it is left as it stands\n", s.name, got.URL)
				left = true
			}
		}
	}
	switch {
	case got.Title && got.Body:
		fmt.Fprintf(stdout, "%s: edited the title and the body of %s\n", bead, got.URL)
	case got.Title:
		fmt.Fprintf(stdout, "%s: edited the title of %s\n", bead, got.URL)
	case got.Body:
		fmt.Fprintf(stdout, "%s: edited the body of %s\n", bead, got.URL)
	case left:
		fmt.Fprintf(stdout, "%s: edited nothing on %s\n", bead, got.URL)
	default:
		fmt.Fprintf(stdout, "%s: %s shows its composition already\n", bead, got.URL)
	}
	return 0
}

// editFailed says why an edit stopped, and returns its exit.
func editFailed(bead string, err error, stderr io.Writer) int {
	var refused *pr.EditRefusal
	var origin *pr.OriginError
	switch {
	case errors.As(err, &refused):
		fmt.Fprintf(stderr, "gctk pr compose: %v\n", err)
		return 3
	case errors.As(err, &origin):
		fmt.Fprintf(stderr, "gctk pr compose: %s: the PR is left as it stands: %v\n", bead, err)
		return 1
	}
	fmt.Fprintf(stderr, "gctk pr compose: %s: %v\n", bead, err)
	return 2
}
