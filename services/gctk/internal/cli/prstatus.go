package cli

import (
	"encoding/json"
	"fmt"
	"io"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus"
)

// `gctk pr-status` is the derivation assets/scripts/pr-status-label.sh reaches.
// `derive --anchor ID` prints one of working|merging|needs-review|needs-attention
// and exits 0; 1 on a usage error; 2 when a read did not resolve, so a caller
// leaves the labels as they are rather than flipping them blind. With --json it
// prints one object instead, {"status": <that value>, "held": [<gate, review,
// blocked>]}, the held values in prstatus.Held's order and an empty array when
// nothing holds the PR. pr-status-label.sh calls this and has no derivation of
// its own, and pr-status-label.test.sh is the acceptance bar. The anchor read
// goes through gcbd.Show (daemon-first against the supervisor API, falling back
// to `gc bd`); the in-flight set and the anchor's blockers read through `gc
// bd`. The cli tests pin GC_NO_API, so every read answers from the
// same `gc bd` stub the shell acceptance drives.
//
// The values are decided by prstatus.Derive and prstatus.Held, the package
// exported for the helm board to derive the same per-bead state: one code path,
// so a bead's PR labels and its board liveness cannot disagree.

// prStatusProg is the name warnings carry: the script whose derivation this is,
// because its callers grep those lines and the language behind the command is
// invisible to them.
const prStatusProg = "pr-status-label"

const prStatusUsage = `usage: gctk pr-status derive --anchor <anchor-id> [--json]
`

// PRStatus dispatches the subcommand's verbs, returning a process exit code so
// the surface stays testable in-process.
func PRStatus(args []string, stdout, stderr io.Writer) int {
	verb := ""
	if len(args) > 0 {
		verb = args[0]
	}
	switch verb {
	case "derive":
		return prStatusDerive(args[1:], stdout, stderr)
	default:
		fmt.Fprint(stderr, prStatusUsage)
		return 1
	}
}

// prStatusDerive gathers the facts the city records about the anchor and prints
// the state prstatus.Derive returns, and with --json the values prstatus.Held
// returns beside it: the holds, the dated posture, the machine verdict and its
// blocked cause, the count of review threads waiting on the city's answer, and
// the draft-stage markers off the anchor, the size of the anchor's in-flight
// set, whether an open human gate blocks the anchor, and whether a blocker it
// waits on is a person's.
func prStatusDerive(args []string, stdout, stderr io.Writer) int {
	anchor := ""
	asJSON := false
	var missing string
	next := func(i int) (string, int) {
		if i+1 < len(args) {
			return args[i+1], i + 2
		}
		missing = args[i]
		return "", len(args)
	}
	for i := 0; i < len(args); {
		switch args[i] {
		case "--anchor":
			anchor, i = next(i)
		case "--json":
			asJSON = true
			i++
		default:
			fmt.Fprintf(stderr, "%s: unknown argument '%s'\n", prStatusProg, args[i])
			return 1
		}
	}
	if missing != "" {
		fmt.Fprintf(stderr, "%s: flag %s needs a value\n", prStatusProg, missing)
		return 1
	}
	if anchor == "" {
		fmt.Fprintf(stderr, "%s: derive needs --anchor\n", prStatusProg)
		return 1
	}

	client := gcbd.New()
	bead := client.Show(anchor)
	if bead == nil {
		fmt.Fprintf(stderr, "%s: anchor %s does not resolve; cannot derive a status\n", prStatusProg, anchor)
		return 2
	}

	// The anchor's in-flight set: every bead carrying anchor_bead, any
	// task_kind, at one of prstatus.InFlightStatuses, the statuses the helm board
	// reads the same set over. metadata-field selection lists non-closed by
	// default; the explicit --status keeps it robust, one comma list because a
	// repeated flag drops earlier values, and --limit 0 so the client-side field
	// filter sees every candidate.
	rows, ok := client.List(
		"--metadata-field", "anchor_bead="+anchor,
		"--status", strings.Join(prstatus.InFlightStatuses, ","),
		"--limit", "0",
		"--json",
	)
	if !ok {
		fmt.Fprintf(stderr, "%s: could not read the in-flight set for %s; cannot derive a status\n", prStatusProg, anchor)
		return 2
	}

	// The anchor's blockers, one read, answer both holds a person owes: an open
	// human gate among them, and a live blocker routed to a person or a decision.
	// A conversation about the anchor tracks it and blocks nothing, so it is not
	// among them.
	blockers, ok := client.DepList(anchor, "--type", "blocks", "--json")
	if !ok {
		fmt.Fprintf(stderr, "%s: could not read the blockers of %s; cannot derive a status\n", prStatusProg, anchor)
		return 2
	}

	facts := prstatus.Facts{
		MergeHold:           bead.Meta("merge_hold"),
		RebaseHold:          bead.Meta("rebase_hold"),
		OpenHumanGate:       openHumanGate(blockers),
		PersonBlocker:       personBlocker(blockers),
		PRPosture:           bead.Meta("pr_posture"),
		PRMachine:           bead.Meta("pr.machine"),
		PRMachineCause:      bead.Meta("pr.machine_cause"),
		PRUnansweredThreads: bead.Meta("pr.unanswered_threads"),
		OpenedAsDraft:       bead.Meta("opened_as_draft"),
		DraftReadied:        bead.Meta("draft_readied"),
		InFlightCount:       len(rows),
	}
	state := prstatus.Derive(facts)
	if !asJSON {
		fmt.Fprintf(stdout, "%s\n", state)
		return 0
	}
	held := prstatus.Held(facts)
	if held == nil {
		held = []prstatus.Hold{}
	}
	raw, err := json.Marshal(struct {
		Status prstatus.State  `json:"status"`
		Held   []prstatus.Hold `json:"held"`
	}{state, held})
	if err != nil {
		fmt.Fprintf(stderr, "%s: could not encode the derivation of %s: %v\n", prStatusProg, anchor, err)
		return 2
	}
	fmt.Fprintf(stdout, "%s\n", raw)
	return 0
}

// openHumanGate reports whether an open human gate is among blockers, the beads
// the anchor's blocks edges name: a bead whose issue_type is gate and whose
// await_type is human, in a status other than closed. That is the one reader
// rule bd_human_gates applies (assets/scripts/bd-lib.sh) and the finalize gate
// (clause_no_open_human_gate in assets/scripts/finalize-gate.sh) holds the merge
// on.
func openHumanGate(blockers []gcbd.Bead) bool {
	for i := range blockers {
		if blockers[i].IsHumanGate() && blockers[i].StatusLowerOr("open") != "closed" {
			return true
		}
	}
	return false
}

// personBlocker reports whether a live blocker among blockers, the beads the
// anchor's blocks edges name, is a person's to clear: one routed to a person, or
// a decision. A blocker with no status reads open, and only a closed one is not
// live. It is the helm board's demand test (board.demand), so the board's asking
// row and the label read one rule.
func personBlocker(blockers []gcbd.Bead) bool {
	for i := range blockers {
		b := &blockers[i]
		if b.StatusLowerOr("open") == "closed" {
			continue
		}
		if b.Meta("gc.routed_to") == "human" || b.IssueTypeString() == "decision" {
			return true
		}
	}
	return false
}
