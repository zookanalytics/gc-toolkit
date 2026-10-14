package cli

import (
	"fmt"
	"io"
	"slices"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus"
)

// `gctk pr-status` is the tri-state derivation lifted out of
// assets/scripts/pr-status-label.sh's derive_value. The CLI is
// contract-preserving — `derive --anchor ID` prints one of
// working|needs-review|needs-attention and exits 0; 1 on a usage error; 2 when
// a read did not resolve, so a caller leaves the label as-is rather than
// flipping it blind — because pr-status-label.sh calls this in place of its own
// shell and pr-status-label.test.sh is the acceptance bar. The anchor read goes
// through gcbd.Show (daemon-first against the supervisor API, falling back to
// `gc bd`); the in-flight set and the open visits list through `gc bd`. The cli
// tests pin GC_NO_API, so every read answers from the same `gc bd` stub the
// shell acceptance drives.
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

// prStatusDerive gathers the facts the city records about the anchor and prints
// the state prstatus.Derive returns: the holds and the dated posture/merge-state
// off the anchor, the size of the anchor's in-flight set, and whether an open
// visit covers the anchor.
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

	// The anchor's in-flight set: every live bead carrying anchor_bead, any
	// task_kind, the membership test pr-facts.sh applies in its own arms.
	// metadata-field selection lists non-closed by default; the explicit --status
	// keeps it robust, one comma list because a repeated flag drops earlier
	// values, and --limit 0 so the client-side field filter sees every candidate.
	rows, ok := client.List(
		"--metadata-field", "anchor_bead="+anchor,
		"--status", "open,in_progress,blocked,deferred,hooked,pinned",
		"--limit", "0",
		"--json",
	)
	if !ok {
		fmt.Fprintf(stderr, "%s: could not read the in-flight set for %s; cannot derive a status\n", prStatusProg, anchor)
		return 2
	}

	// The open visits that cover the anchor. Coverage is the shared visit
	// identity the finalize gate holds the merge on: a visit covers the bead its
	// tracks edge names, and its gc.continuation_group stamp only when it has no
	// tracks edge. The stamp can land empty while the edge stands, so no metadata
	// filter selects every visit on the anchor. The read lists every visit that is
	// open or in_progress, the statuses the finalize gate holds on: a visit waiting
	// for a person, and one a sitting is holding. Each row carries its own edges,
	// and visitCovers judges it.
	visits, ok := client.List(
		"--metadata-field", "task_kind=visit",
		"--status", "open,in_progress",
		"--limit", "0",
		"--json",
	)
	if !ok {
		fmt.Fprintf(stderr, "%s: could not read the open visits on %s; cannot derive a status\n", prStatusProg, anchor)
		return 2
	}
	openVisit := false
	for i := range visits {
		if visitCovers(&visits[i], anchor) {
			openVisit = true
			break
		}
	}

	state := prstatus.Derive(prstatus.Facts{
		MergeHold:     bead.Meta("merge_hold"),
		SignoffCap:    bead.Meta("signoff_cap"),
		RebaseHold:    bead.Meta("rebase_hold"),
		OpenVisit:     openVisit,
		PRPosture:     bead.Meta("pr_posture"),
		PRMergeState:  bead.Meta("pr_merge_state"),
		InFlightCount: len(rows),
	})
	fmt.Fprintf(stdout, "%s\n", state)
	return 0
}

// visitCovers reports whether visit v covers subject by the shared visit
// identity, visit_covers in assets/scripts/visit-identity.sh: the subject its
// tracks edge names, or, for a visit with no tracks edge, its
// gc.continuation_group stamp. A stamp never widens a non-empty edge set, so a
// stale stamp beside an edge to another bead does not cover subject.
func visitCovers(v *gcbd.Bead, subject string) bool {
	if subject == "" {
		return false
	}
	tracked := v.DependsOn("tracks")
	if len(tracked) == 0 {
		return v.Meta("gc.continuation_group") == subject
	}
	return slices.Contains(tracked, subject)
}
