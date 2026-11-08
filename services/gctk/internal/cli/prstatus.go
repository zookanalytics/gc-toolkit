package cli

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus"
)

// `gctk pr-status` is how the shell asks what holds a PR and where it stands:
// assets/scripts/pr-status-label.sh for the PR's labels, and gc-helm.sh engage
// for what holds the bead it engages. `derive --anchor ID` prints one of
// working|merging|needs-review|needs-attention and exits 0; 1 on a usage error;
// 2 when a read did not resolve, so a caller leaves the labels as they are
// rather than flipping them blind. With --json it prints one object instead,
// {"status": <that value>, "held": [<gate, review, blocked>], "reasons":
// [{"held", "id", "title"}]}: the held values in prstatus.Held's order, and each
// thing behind them in prstatus.Reasons' order, the id empty where the PR's own
// review threads or blocked verdict hold it. Both lists are empty arrays when
// nothing holds the PR. pr-status-label.sh and engage call this and decide
// nothing themselves.
//
// prstatus.Read gathers the facts through gcbdStore and decides nothing here
// either: the helm board asks the same package through its own store, so the
// labels, engage and the board read one definition. The cli tests pin GC_NO_API,
// so every read answers from the same `gc bd` stub the shell acceptance drives.

// prStatusProg is the name warnings carry: the script whose derivation this is,
// because its callers grep those lines and the language behind the command is
// invisible to them.
const prStatusProg = "pr-status-label"

const prStatusUsage = `usage: gctk pr-status derive --anchor <anchor-id> [--json]
`

// PRStatus dispatches the subcommand's verbs, returning a process exit code so
// the surface stays testable in-process.
func PRStatus(args []string, stdout, stderr io.Writer) int {
	if len(args) > 0 && args[0] == "derive" {
		return prStatusDerive(args[1:], stdout, stderr)
	}
	fmt.Fprint(stderr, prStatusUsage)
	return 1
}

// prStatusArgs reads derive's flags, --anchor and --json. It returns false after
// saying what is wrong.
func prStatusArgs(args []string, asJSON *bool, stderr io.Writer) (string, bool) {
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
		case args[i] == "--json":
			*asJSON = true
		default:
			fmt.Fprintf(stderr, "%s: unknown argument '%s'\n", prStatusProg, args[i])
			return "", false
		}
	}
	if anchor == "" {
		fmt.Fprintf(stderr, "%s: derive needs --anchor\n", prStatusProg)
		return "", false
	}
	return anchor, true
}

// prStatusDerive prints the state prstatus.Derive returns for the facts
// prstatus.Read gathers about the anchor, and with --json the values
// prstatus.Held and prstatus.Reasons return beside it.
func prStatusDerive(args []string, stdout, stderr io.Writer) int {
	asJSON := false
	anchor, ok := prStatusArgs(args, &asJSON, stderr)
	if !ok {
		return 1
	}
	facts, err := prstatus.Read([]string{anchor}, gcbdStore{gcbd.New()})
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
	if !asJSON {
		fmt.Fprintf(stdout, "%s\n", state)
		return 0
	}
	held, reasons := prstatus.Held(f), prstatus.Reasons(f)
	if held == nil {
		held = []prstatus.Hold{}
	}
	if reasons == nil {
		reasons = []prstatus.Reason{}
	}
	raw, err := json.Marshal(struct {
		Status  prstatus.State    `json:"status"`
		Held    []prstatus.Hold   `json:"held"`
		Reasons []prstatus.Reason `json:"reasons"`
	}{state, held, reasons})
	if err != nil {
		fmt.Fprintf(stderr, "%s: could not encode the derivation of %s: %v\n", prStatusProg, anchor, err)
		return 2
	}
	fmt.Fprintf(stdout, "%s\n", raw)
	return 0
}

// gcbdStore is the [prstatus.Store] gctk reads through. An anchor's row comes
// from gcbd.Show, which prefers the supervisor API. Its in-flight set comes from
// one `gc bd list` per anchor, whose metadata filter matches a key against one
// value. A level of `blocks` edges comes from one `gc bd show` of every bead in
// it, whose rows carry each edge's far bead whole.
type gcbdStore struct{ client *gcbd.Client }

// Beads returns the row of each id gcbd.Show reads. One it cannot read is left
// out, which prstatus.Read reports as an anchor that does not resolve.
func (s gcbdStore) Beads(ids []string) (map[string]prstatus.Row, error) {
	out := make(map[string]prstatus.Row, len(ids))
	for _, id := range ids {
		if b := s.client.Show(id); b != nil {
			out[id] = prstatus.Row{ID: id, Metadata: metadataOf(b)}
		}
	}
	return out, nil
}

// Anchored lists, for each id, the beads carrying anchor_bead=<id> at any of
// statuses: one comma list, because a repeated --status keeps only the last, and
// --limit 0, so the filter sees every candidate.
func (s gcbdStore) Anchored(ids []string, statuses []string) (map[string][]prstatus.Row, error) {
	out := make(map[string][]prstatus.Row, len(ids))
	for _, id := range ids {
		rows, ok := s.client.List(
			"--metadata-field", "anchor_bead="+id,
			"--status", strings.Join(statuses, ","),
			"--limit", "0",
			"--json",
		)
		if !ok {
			return nil, fmt.Errorf("the in-flight set of %s did not read", id)
		}
		out[id] = []prstatus.Row{}
		for i := range rows {
			out[id] = append(out[id], prstatus.Row{ID: rows[i].ID, Metadata: metadataOf(&rows[i])})
		}
	}
	return out, nil
}

// Blockers reads the `blocks` edges of every id in one client.Blockers. It is
// also the read the merge pass walks to the gates that hold its blockers.
func (s gcbdStore) Blockers(ids []string) (map[string][]prstatus.Blocker, error) {
	edges, ok := s.client.Blockers(ids)
	if !ok {
		return nil, fmt.Errorf("the blocks edges of %s did not read", strings.Join(ids, " "))
	}
	out := make(map[string][]prstatus.Blocker, len(ids))
	for _, id := range ids {
		out[id] = asBlockers(edges[id])
	}
	return out, nil
}

// metadataOf renders each of a bead's metadata values as the scripts read it,
// `(.metadata[k] // "") | tostring`.
func metadataOf(b *gcbd.Bead) map[string]string {
	out := make(map[string]string, len(b.Metadata))
	for k := range b.Metadata {
		out[k] = b.Meta(k)
	}
	return out
}

// asBlockers projects `blocks` rows onto what the definition reads of them. A
// row with no status reads open.
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
			RoutedTo:  b.Meta("gc.routed_to"),
		})
	}
	return out
}
