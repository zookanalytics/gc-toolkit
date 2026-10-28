package cli

import (
	"encoding/json"
	"fmt"
	"io"
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus"
)

// `gctk pr-status` is the derivation assets/scripts/pr-status-label.sh reaches.
// `derive --anchor ID` prints one of working|merging|needs-review|needs-attention
// and exits 0; 1 on a usage error; 2 when a read did not resolve, so a caller
// leaves the labels as they are rather than flipping them blind. With --json it
// prints one object instead, {"status": <that value>, "held": [<visit, review,
// blocked>]}, the held values in prstatus.Held's order and an empty array when
// nothing holds the PR. pr-status-label.sh calls this and has no derivation of
// its own, and pr-status-label.test.sh is the acceptance bar. The anchor read
// goes through gcbd.Show (daemon-first against the supervisor API, falling back
// to `gc bd`); the in-flight set, the open visits and the anchor's blockers read
// through `gc bd`. The cli tests pin GC_NO_API, so every read answers from the
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
// set, whether an open visit covers the anchor or its work, and whether a
// blocker it waits on is a person's.
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

	openVisit, ok := openVisitCovers(client, anchor)
	if !ok {
		fmt.Fprintf(stderr, "%s: could not read the open visits on %s; cannot derive a status\n", prStatusProg, anchor)
		return 2
	}
	// A visit on the anchor already holds the PR, so the visits on its work are
	// read only when none covers the anchor itself.
	workVisit := false
	if !openVisit {
		if workVisit, ok = workOpenVisit(client, rows); !ok {
			fmt.Fprintf(stderr, "%s: could not read the open visits on the work in flight on %s; cannot derive a status\n", prStatusProg, anchor)
			return 2
		}
	}

	blockers, ok := client.DepList(anchor, "--direction=down", "-t", "blocks", "--json")
	if !ok {
		fmt.Fprintf(stderr, "%s: could not read the blockers of %s; cannot derive a status\n", prStatusProg, anchor)
		return 2
	}

	facts := prstatus.Facts{
		MergeHold:           bead.Meta("merge_hold"),
		RebaseHold:          bead.Meta("rebase_hold"),
		OpenVisit:           openVisit,
		WorkVisit:           workVisit,
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

// workOpenVisit reports whether an open visit covers the PR's own work among
// rows, the anchor's in-flight set: a row prstatus.IsWork accepts, by the rule
// the helm board applies to the same set. A row with no status reads open. ok is
// false when a visit read does not answer.
func workOpenVisit(client *gcbd.Client, rows []gcbd.Bead) (covered, ok bool) {
	for i := range rows {
		if !prstatus.IsWork(rows[i].Meta("task_kind"), rows[i].StatusLowerOr("open")) {
			continue
		}
		if covered, ok := openVisitCovers(client, rows[i].ID); !ok || covered {
			return covered, ok
		}
	}
	return false, true
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

// openVisitCovers reports whether an open or in_progress visit covers subject by
// the shared visit identity. It reads from the subject's end, with the two
// probes clause_no_open_visit in assets/scripts/finalize-gate.sh makes, so the
// cost follows the subject rather than the number of open visits in the store.
// The first read lists the beads whose tracks edge names the subject, and a
// visit among them covers it. The second lists the beads stamped with the
// subject (gc.continuation_group), and a visit among them covers it only when it
// has no tracks edge, which its own edge rows tell (visitCovers). open and
// in_progress are the statuses the finalize gate holds on: a visit waiting for a
// person, and one a sitting is holding. ok is false when either read does not
// answer, so the caller derives nothing rather than reading a failed read as no
// visit.
func openVisitCovers(client *gcbd.Client, subject string) (covered, ok bool) {
	trackers, ok := client.DepList(subject, "--direction=up", "-t", "tracks", "--json")
	if !ok {
		return false, false
	}
	for i := range trackers {
		if isOpenVisit(&trackers[i]) {
			return true, true
		}
	}
	stamped, ok := client.List(
		"--metadata-field", "gc.continuation_group="+subject,
		"--status", "open,in_progress",
		"--limit", "0",
		"--json",
	)
	if !ok {
		return false, false
	}
	for i := range stamped {
		if isOpenVisit(&stamped[i]) && visitCovers(&stamped[i], subject) {
			return true, true
		}
	}
	return false, true
}

// isOpenVisit reports whether b is a task_kind=visit bead that is open or
// in_progress. A row with no status reads open, as the finalize gate reads it.
func isOpenVisit(b *gcbd.Bead) bool {
	if b.Meta("task_kind") != "visit" {
		return false
	}
	switch b.StatusLowerOr("open") {
	case "open", "in_progress":
		return true
	}
	return false
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
