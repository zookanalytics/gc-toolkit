package cli

import (
	"fmt"
	"io"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus"
)

// `gctk pr-status` is the tri-state derivation lifted out of
// assets/scripts/pr-status-label.sh's derive_value. The CLI is
// contract-preserving — `derive --anchor ID` prints one of
// working|needs-review|needs-attention and exits 0; 1 on a usage error; 2 when
// a read did not resolve, so a caller leaves the label as-is rather than
// flipping it blind — because pr-status-label.sh calls this in place of its own
// shell and pr-status-label.test.sh is the acceptance bar. gctk reads the bead
// by shelling out to `gc bd`, exactly as the script did, so the same test stubs
// serve it.
//
// The value is decided by prstatus.Derive, the package exported for the helm
// board to derive the same per-bead state: one code path, so a bead's PR label
// and its board liveness cannot disagree.

// prStatusProg is the name warnings carry: the script whose derivation this is,
// because its callers grep those lines and the language behind the command is
// invisible to them.
const prStatusProg = "pr-status-label"

const prStatusUsage = `usage: gctk pr-status derive --anchor <anchor-id>
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

// prStatusDerive gathers the anchor's refinery-computed facts and prints the
// state prstatus.Derive returns. It reads only what derive_value read: the
// holds and the dated posture/merge-state off the anchor, and the count of open
// rework children standing on it.
func prStatusDerive(args []string, stdout, stderr io.Writer) int {
	anchor := ""
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

	// The open rework children standing on this anchor. metadata-field selection
	// lists non-closed by default; the explicit --status keeps it robust, one
	// comma list because a repeated flag drops earlier values, and --limit 0 so
	// the client-side field filter sees every candidate.
	rows, ok := client.List(
		"--metadata-field", "task_kind=rework",
		"--metadata-field", "anchor_bead="+anchor,
		"--status", "open,in_progress,blocked",
		"--limit", "0",
		"--json",
	)
	if !ok {
		fmt.Fprintf(stderr, "%s: could not read rework children for %s; cannot derive a status\n", prStatusProg, anchor)
		return 2
	}

	state := prstatus.Derive(prstatus.Facts{
		MergeHold:          bead.Meta("merge_hold"),
		SignoffCap:         bead.Meta("signoff_cap"),
		RebaseHold:         bead.Meta("rebase_hold"),
		PRPosture:          bead.Meta("pr_posture"),
		PRMergeState:       bead.Meta("pr_merge_state"),
		OpenReworkChildren: len(rows),
	})
	fmt.Fprintf(stdout, "%s\n", state)
	return 0
}
