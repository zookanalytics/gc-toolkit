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
// its own, and pr-status-label.test.sh is the acceptance bar. `gates --anchor ID`
// prints the open human gates that hold the bead as a JSON array of {"id",
// "title"}, nearest first, on the same exits; gc-helm.sh engage lists them from
// it. The anchor read goes through gcbd.Show (daemon-first against the supervisor
// API, falling back to `gc bd`); the in-flight set and the blockers read through
// `gc bd`. The cli tests pin GC_NO_API, so every read answers from the same `gc
// bd` stub the shell acceptance drives.
//
// The values are decided by prstatus.Derive, prstatus.Held and
// prstatus.HoldingGates, the package exported for the helm board to derive the
// same per-bead state: one code path, so a bead's PR labels, its board liveness
// and what engage offers on it cannot disagree.

// prStatusProg is the name warnings carry: the script whose derivation this is,
// because its callers grep those lines and the language behind the command is
// invisible to them.
const prStatusProg = "pr-status-label"

const prStatusUsage = `usage: gctk pr-status derive --anchor <anchor-id> [--json]
       gctk pr-status gates --anchor <anchor-id>
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
	case "gates":
		return prStatusGates(args[1:], stdout, stderr)
	default:
		fmt.Fprint(stderr, prStatusUsage)
		return 1
	}
}

// prStatusArgs reads a verb's flags: --anchor, and --json where the verb passes
// somewhere to record it. It returns false after saying what is wrong.
func prStatusArgs(verb string, args []string, asJSON *bool, stderr io.Writer) (string, bool) {
	anchor := ""
	for i := 0; i < len(args); i++ {
		switch {
		case args[i] == "--anchor":
			if i+1 == len(args) {
				fmt.Fprintf(stderr, "%s: flag %s needs a value\n", prStatusProg, args[i])
				return "", false
			}
			i++
			anchor = args[i]
		case args[i] == "--json" && asJSON != nil:
			*asJSON = true
		default:
			fmt.Fprintf(stderr, "%s: unknown argument '%s'\n", prStatusProg, args[i])
			return "", false
		}
	}
	if anchor == "" {
		fmt.Fprintf(stderr, "%s: %s needs --anchor\n", prStatusProg, verb)
		return "", false
	}
	return anchor, true
}

// prStatusDerive gathers the facts the city records about the anchor and prints
// the state prstatus.Derive returns, and with --json the values prstatus.Held
// returns beside it: the holds, the dated posture, the machine verdict and its
// blocked cause, the count of review threads waiting on the city's answer, and
// the draft-stage markers off the anchor, the size of the anchor's in-flight
// set, whether an open human gate holds the anchor, and whether a blocker it
// waits on is a person's.
func prStatusDerive(args []string, stdout, stderr io.Writer) int {
	asJSON := false
	anchor, ok := prStatusArgs("derive", args, &asJSON, stderr)
	if !ok {
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

	// The anchor's blockers, one read, answer the holds a person owes on the
	// anchor itself: a live blocker routed to a person or a decision. They are
	// also the first level of the walk to the open human gates that hold it. A
	// conversation about the anchor tracks it and blocks nothing, so it is not
	// among them.
	blockers, ok := client.DepList(anchor, "--type", "blocks", "--json")
	if !ok {
		fmt.Fprintf(stderr, "%s: could not read the blockers of %s; cannot derive a status\n", prStatusProg, anchor)
		return 2
	}
	gates, err := prstatus.HoldingGates([]string{anchor}, blockerRead(client, map[string][]gcbd.Bead{anchor: blockers}))
	if err != nil {
		fmt.Fprintf(stderr, "%s: could not read the human gates that hold %s: %v; cannot derive a status\n", prStatusProg, anchor, err)
		return 2
	}

	facts := prstatus.Facts{
		MergeHold:           bead.Meta("merge_hold"),
		RebaseHold:          bead.Meta("rebase_hold"),
		OpenHumanGate:       len(gates[anchor]) > 0,
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

// prStatusGates prints the open human gates that hold the bead, for a caller that
// offers them. It reads only the walk's edges, none of what derive reads besides.
func prStatusGates(args []string, stdout, stderr io.Writer) int {
	anchor, ok := prStatusArgs("gates", args, nil, stderr)
	if !ok {
		return 1
	}
	gates, err := prstatus.HoldingGates([]string{anchor}, blockerRead(gcbd.New(), nil))
	if err != nil {
		fmt.Fprintf(stderr, "%s: could not read the human gates that hold %s: %v\n", prStatusProg, anchor, err)
		return 2
	}
	type gateRow struct {
		ID    string `json:"id"`
		Title string `json:"title"`
	}
	rows := make([]gateRow, 0, len(gates[anchor]))
	for _, g := range gates[anchor] {
		rows = append(rows, gateRow{g.ID, g.Title})
	}
	raw, err := json.Marshal(rows)
	if err != nil {
		fmt.Fprintf(stderr, "%s: could not encode the human gates that hold %s: %v\n", prStatusProg, anchor, err)
		return 2
	}
	fmt.Fprintf(stdout, "%s\n", raw)
	return 0
}

// blockerRead is the read prstatus.HoldingGates walks through `gc bd`: one
// client.Blockers per level, for the beads the caller has not read already.
// known holds the `blocks` rows of each bead it has.
func blockerRead(client *gcbd.Client, known map[string][]gcbd.Bead) prstatus.ReadBlockers {
	return func(ids []string) (map[string][]prstatus.Blocker, error) {
		out := make(map[string][]prstatus.Blocker, len(ids))
		var rest []string
		for _, id := range ids {
			if rows, ok := known[id]; ok {
				out[id] = asBlockers(rows)
			} else {
				rest = append(rest, id)
			}
		}
		if len(rest) == 0 {
			return out, nil
		}
		edges, ok := client.Blockers(rest)
		if !ok {
			return nil, fmt.Errorf("the blocks edges of %s did not read", strings.Join(rest, " "))
		}
		for _, id := range rest {
			out[id] = asBlockers(edges[id])
		}
		return out, nil
	}
}

// asBlockers projects `blocks` rows onto what the walk reads. A row with no status
// reads open.
func asBlockers(rows []gcbd.Bead) []prstatus.Blocker {
	out := make([]prstatus.Blocker, 0, len(rows))
	for i := range rows {
		b := &rows[i]
		out = append(out, prstatus.Blocker{
			ID:        b.ID,
			Title:     b.Title,
			Status:    b.StatusLowerOr("open"),
			IssueType: b.IssueTypeString(),
			AwaitType: b.AwaitType,
		})
	}
	return out
}

// personBlocker reports whether a live blocker among blockers, the beads the
// anchor's blocks edges name, is a person's to clear: one routed to a person, or
// a decision. A human gate is not among them, whatever its route, because
// held: gate is what counts it. A blocker with no status reads open, and only a
// closed one is not live. It is the helm board's demand test (board.demand), so
// the board's asking row and the label read one rule.
func personBlocker(blockers []gcbd.Bead) bool {
	for i := range blockers {
		b := &blockers[i]
		if b.StatusLowerOr("open") == "closed" || b.IsHumanGate() {
			continue
		}
		if b.Meta("gc.routed_to") == "human" || b.IssueTypeString() == "decision" {
			return true
		}
	}
	return false
}
