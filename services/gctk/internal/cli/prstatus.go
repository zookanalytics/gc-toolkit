package cli

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/feedback"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/prstatus"
)

// `gctk pr status <bead>` is how the shell asks what holds a PR and where it
// stands: assets/scripts/pr-status-label.sh for the PR's labels, and gc-helm.sh
// engage for what holds the bead it engages. It is the pr noun's status verb,
// in the words the PR's status: label shows (docs/gctk-architecture.md, "The
// rule that names a verb").
//
// prstatus.Read gathers the facts through prstatus's Store over one pass of the
// store gc routes the bead to (prstatus.Over), and nothing here decides: the
// helm board asks the same package through its listing, over the same Store,
// so the labels, engage and the board read one definition. For a PR on Gas
// Town's pending record it asks the pr domain's evaluator through the same
// pass, the read the one-PR update saved on the bead among it (pr.FromStore),
// as the rig board asks it through its listing, so they give one answer, none
// of them reads GitHub, and a run reads each bead once.
//
// The pass reads the store and never the supervisor's copy, whose rows carry
// no await type, await id or close time (beads.Bead in Gas City's
// internal/beads/beads.go), and a sign-off words the Approve clause of its
// headline from this status (converse-signoff.sh), which no later read
// corrects.

// prStatusProg is the name warnings carry: the script whose derivation this is,
// because its callers grep those lines and the language behind the command is
// invisible to them.
const prStatusProg = "pr-status-label"

const prStatusLong = `Prints where the PR the bead owns stands, in the words its status: label
shows: working, merging, needs-review or needs-attention. The bead is the PR's
anchor. With --json it prints one object instead:
{"status": <that value>, "held": [<gate, review, blocked>], "reasons":
[{"held", "id", "title"}]}. held is what holds the PR, in the order the held:
labels take, and reasons is each thing behind it. A reason's id is empty where
the PR's own review threads hold it. Both lists are empty arrays when nothing
holds the PR.

For a bead whose PR is on Gas Town's pending record, the status renders the pr
domain's evaluator over the store as it stands, the read the one-PR update
(gctk pr refresh) saved on the bead among it, so the command reads no GitHub,
and each condition not met follows the status on a line of its own, as
<kind>: <detail>. A saved read that is absent, or is not of the PR at the head
the store holds, names one condition, github-unread, in place of GitHub's, and
the PR reads working until the PR watch's next pass reads it, or
needs-attention while something only a person clears holds it. For such a bead, held and
reasons name the gates and the beads a person owes that hold it, and the
review threads the saved read finds waiting on the city's answer while no
work of the city's acts on them. Its --json object also carries "ready", the
"head" and "target" the evaluator judged, the saved read's while it is
current, and "conditions": [{"kind", "detail", "id", "value"}], an empty
array when the PR is ready.

exit: 0 printed
      1 usage
      2 a read did not resolve, so nothing was derived: a caller leaves the
        labels as they are rather than flipping them blind`

func newPRCmd(stdout, stderr io.Writer) *cobra.Command {
	asJSON := false
	status := &cobra.Command{
		Use:         "status <bead>",
		Short:       "where the PR stands: working, merging, needs-review or needs-attention",
		Long:        prStatusLong,
		Args:        cobra.ExactArgs(1),
		Annotations: map[string]string{usageExitKey: "1"},
		RunE: func(_ *cobra.Command, args []string) error {
			anchor := strings.TrimSpace(args[0])
			if anchor == "" {
				return errors.New("name the bead whose PR this is")
			}
			return exit(prStatus(anchor, asJSON, stdout, stderr))
		},
	}
	status.Flags().BoolVar(&asJSON, "json", false, "print the status with what holds the PR, as one JSON object")
	return group("pr", "a bead's pull request",
		"The pull request a bead owns: where it stands, what its title and body say, the account of the change "+
			"they carry, GitHub's side of it saved on the bead, its record from publication to the verified merge, "+
			"its draft between rounds of the city's work, the withdrawal of approvals a material change leaves "+
			"behind, a review round's answers on it, and the push of a converse sitting that edits its branch.",
		status, newPRComposeCmd(stdout, stderr), newPRSummaryCmd(stdout, stderr),
		newPRPollCmd(stdout, stderr), newPRCompareCmd(stdout, stderr), newPRRefreshCmd(stdout, stderr),
		newPRRecordCmd(stdout, stderr), newPRReconcileCmd(stdout, stderr),
		newPRDraftCmd(stdout, stderr), newPRWithdrawCmd(stdout, stderr), newPRAnswerCmd(stdout, stderr),
		newPRPushCmd(stdout, stderr))
}

// prStatus prints the state prstatus.Derive returns for the facts prstatus.Read
// gathers about the anchor, and with asJSON the values prstatus.Held and
// prstatus.Reasons return beside it. For an anchor on Gas Town's pending record
// it prints the state prstatus.Render gives the evaluator's answer through the
// same pass instead (pr.FromStore), with the conditions not met, and with
// asJSON the values prstatus.RenderHeld and prstatus.RenderReasons return.
func prStatus(anchor string, asJSON bool, stdout, stderr io.Writer) int {
	l, err := ledger.Open("", anchor)
	if err != nil {
		fmt.Fprintf(stderr, "%s: could not read what holds %s: %v; cannot derive a status\n", prStatusProg, anchor, err)
		return 2
	}
	pass := l.Pass()
	facts, err := prstatus.Read([]string{anchor}, prstatus.Over(pass))
	f, answered := facts[anchor]
	if err != nil || !answered {
		if errors.Is(err, prstatus.ErrUnresolved) {
			fmt.Fprintf(stderr, "%s: anchor %s does not resolve; cannot derive a status\n", prStatusProg, anchor)
		} else {
			fmt.Fprintf(stderr, "%s: could not read what holds %s: %v; cannot derive a status\n", prStatusProg, anchor, err)
		}
		return 2
	}
	state := prstatus.Derive(f)
	var ans *pr.Answer
	if pr.OnRecord(f.MergeResult) {
		a, err := pr.FromStore(pass, anchor)
		if err != nil {
			fmt.Fprintf(stderr, "%s: could not read what the store holds about the PR %s owns: %v; cannot derive a status\n", prStatusProg, anchor, err)
			return 2
		}
		ans, state = &a, prstatus.Render(a, f)
	}
	if !asJSON {
		fmt.Fprintf(stdout, "%s\n", state)
		if ans != nil {
			for _, c := range ans.Conditions {
				fmt.Fprintf(stdout, "%s: %s\n", c.Kind, c.Detail)
			}
		}
		return 0
	}
	held, reasons := prstatus.Held(f), prstatus.Reasons(f)
	if ans != nil {
		held, reasons = prstatus.RenderHeld(*ans, f), prstatus.RenderReasons(*ans, f)
		if ans.Conditions == nil {
			ans.Conditions = []pr.Condition{}
		}
	}
	if held == nil {
		held = []prstatus.Hold{}
	}
	if reasons == nil {
		reasons = []prstatus.Reason{}
	}
	out := struct {
		Status     prstatus.State    `json:"status"`
		Held       []prstatus.Hold   `json:"held"`
		Reasons    []prstatus.Reason `json:"reasons"`
		Ready      *bool             `json:"ready,omitempty"`
		Head       string            `json:"head,omitempty"`
		Target     string            `json:"target,omitempty"`
		Conditions *[]pr.Condition   `json:"conditions,omitempty"`
	}{Status: state, Held: held, Reasons: reasons}
	if ans != nil {
		out.Ready, out.Head, out.Target, out.Conditions = &ans.Ready, ans.Head, ans.Target, &ans.Conditions
	}
	raw, err := json.Marshal(out)
	if err != nil {
		fmt.Fprintf(stderr, "%s: could not encode the derivation of %s: %v\n", prStatusProg, anchor, err)
		return 2
	}
	fmt.Fprintf(stdout, "%s\n", raw)
	return 0
}

// feedbackIn loads the pack's definition of feedback in checkout, a rig's
// clone, so the definition holds the posts that rig's default branch declares
// not for review. The landing order loads it in the clone it runs in
// (landing).
func feedbackIn(checkout string) (*feedback.Rule, error) {
	scripts, err := feedback.ScriptsDir()
	if err != nil {
		return nil, err
	}
	return feedback.Load(scripts, checkout)
}
