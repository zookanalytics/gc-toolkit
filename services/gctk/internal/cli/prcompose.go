package cli

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
)

// `gctk pr compose <bead>` is how the step that opens or updates a PR asks what
// the PR's title and body should say: pr-open.sh at a create and an adoption,
// and the refinery's merge-push step at each round it lands on an open PR. The
// pr package composes; this command parses the request, reads the published
// body it names, and prints the result.

const prComposeLong = `Prints the title and body of the PR the bead owns, as the bead says they
should be. The title is the bead's own, opened with a conventional-commit type
when it does not open with one, then its id. The body carries two marked
sections, each kept current while the text people add stays as it is:

  summary        the managed summary region: what the change does (the bead's
                 PR summary, else its dispatch text) and the refinery
                 handoff's facts at --head
  branch-beads   every bead whose work is on the bead's branch, once there is
                 more than the PR's own

--body-file names the PR's body as published, - for stdin. Without it the PR
is one not opened yet, and the body is the summary region alone. A published
body's region is rewritten only when it no longer says what the bead says at
--head, read by the region's markers, so text a summary carries, a collapsed
section included, reads as itself. With --opening the PR opens, or is
adopted, at --head once its pre-open gates signed off there: the region says
so, it is rewritten whenever it differs, and a body written before the
markers existed has the region marked over its shape.

--gates is the gate set the bead's check set resolves to at --head, as
review-checks.sh --resolve --through open-as-draft --with-phase prints it,
empty for none. A region that must be written without it is left as it
stands, and its outcome says needs-gates.

It prints one JSON object: {"title", "body", "summary", "branch_beads",
"branch_bead_count"}. summary and branch_beads are each section's outcome,
empty when --sections did not ask for it: written (the body carries it, and
differs from the one published), current, unmanaged (the body carries no
section the markers let it read), needs-gates, single (one bead's work, so no
section) or unread (the beads on the branch did not read). title is empty
when the bead's title has no words.

exit: 0 printed
      1 usage
      2 the bead, or the body named, did not read: nothing is printed`

// The sections a composition takes, as --sections names them.
const (
	sectionSummary     = "summary"
	sectionBranchBeads = "branch-beads"
)

type prComposeOpts struct {
	head, bodyFile, gates, supersedes, supersededHead, sections string
	opening                                                     bool
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
			return exit(prCompose(bead, o.bodyFile, req, stdout, stderr))
		},
	}
	f := cmd.Flags()
	f.StringVar(&o.head, "head", "", "the commit the PR opens at, or carries now")
	f.StringVar(&o.bodyFile, "body-file", "", "the PR's body as published, - for stdin; without it the PR is not opened yet")
	f.BoolVar(&o.opening, "opening", false, "the PR opens, or is adopted, at --head once its pre-open gates signed off there")
	f.StringVar(&o.gates, "gates", "", "the gates the bead's check set resolves to at --head, one <check>\\t<phase> per line")
	f.StringVar(&o.supersedes, "supersedes", "", "the number of a PR closed unmerged that this one replaces (with --opening)")
	f.StringVar(&o.supersededHead, "superseded-head", "", "the head --supersedes closed at")
	f.StringVar(&o.sections, "sections", sectionSummary+","+sectionBranchBeads, "the body's sections to compose: summary, branch-beads, or both")
	return cmd
}

// request is the composition the flags ask for, or the usage error that refuses
// it.
func (o prComposeOpts) request(c *cobra.Command) (pr.Request, error) {
	req := pr.Request{Head: strings.TrimSpace(o.head), Opening: o.opening}
	for _, s := range strings.Split(o.sections, ",") {
		switch strings.TrimSpace(s) {
		case sectionSummary:
			req.Summary = true
		case sectionBranchBeads:
			req.BranchBeads = true
		default:
			return req, fmt.Errorf("--sections takes %s and %s, not %q", sectionSummary, sectionBranchBeads, s)
		}
	}
	if req.Summary && req.Head == "" {
		return req, errors.New("the summary region names the PR's head: give --head")
	}
	if c.Flags().Changed("gates") {
		req.Gates = pr.ParseGates(o.gates)
		if req.Gates == nil {
			req.Gates = []pr.Gate{}
		}
	}
	if (o.supersedes == "") != (o.supersededHead == "") {
		return req, errors.New("--supersedes and --superseded-head name one PR together")
	}
	if o.supersedes != "" {
		if !o.opening || o.bodyFile != "" {
			return req, errors.New("--supersedes names the PR a new one replaces: give it with --opening and no --body-file")
		}
		req.Supersedes = &pr.Superseded{Number: o.supersedes, Head: o.supersededHead}
	}
	return req, nil
}

// prCompose prints the composition of the bead's PR.
func prCompose(bead, bodyFile string, req pr.Request, stdout, stderr io.Writer) int {
	if bodyFile != "" {
		var raw []byte
		var err error
		if bodyFile == "-" {
			raw, err = io.ReadAll(os.Stdin)
		} else {
			raw, err = os.ReadFile(bodyFile)
		}
		if err != nil {
			fmt.Fprintf(stderr, "gctk pr compose: the body of %s's PR did not read: %v\n", bead, err)
			return 2
		}
		body := string(raw)
		req.Body = &body
	}
	got, err := pr.Compose(ledger.New(gcbd.New()), bead, req)
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
