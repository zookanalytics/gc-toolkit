package waits

import (
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// The run link: which bead a workflow run works. assets/scripts/run-lib.sh is
// its one definition, and this copies the part of it that reads every live run,
// its map verb, which TestLiveRunsAgreeWithRunLibFixture holds to that file's
// fixture. Gas City pours a graph.v2 run over an input convoy: the root names the
// convoy in the key inputConvoyKey declares, and the convoy tracks the bead the
// run works. A classic molecule names no convoy and records its bead in its
// issue variable, issueVarKey. So a run works the one bead its input convoy
// tracks, or, when its root names no convoy, the bead its issue variable names.
// A convoy that tracks no bead, or more than one, names none, and so does a
// convoy the store does not return. A root whose issue variable names a bead its
// convoy does not track names none either. A run is live until its root closes.

// run is one live workflow run: its root, the input convoy the root names, and
// the bead the run works, empty when it names none.
type run struct {
	root, convoy, bead string
}

// str is a String key's value on r, trimmed, empty when r does not carry it. A
// String key's stored text always decodes.
func str(k ledger.Key[string], r *ledger.Record) string {
	v, _, _ := k.Get(r)
	return strings.TrimSpace(v)
}

// isRoot reports whether r is a run's root, as run-lib.sh's run_is_root reads
// one: a graph.v2 root as the runtime marks it, or a classic molecule.
func isRoot(r *ledger.Record) bool {
	return strings.EqualFold(str(kindKey, r), "workflow") ||
		strings.EqualFold(str(formulaContractKey, r), "graph.v2") ||
		r.IssueType() == "molecule"
}

// liveRuns reads every live run in the store, in root order, as run-lib.sh's
// map verb does: the live roots that name an input convoy, the live roots that
// record an issue, and every convoy those roots name, closed ones included.
func liveRuns(l *ledger.Ledger) ([]run, error) {
	named, err := l.Find(ledger.Carrying(inputConvoyKey))
	if err != nil {
		return nil, err
	}
	recorded, err := l.Find(ledger.Carrying(issueVarKey))
	if err != nil {
		return nil, err
	}
	var roots []*ledger.Record
	var convoyIDs []string
	seen := map[string]bool{}
	for _, r := range append(named, recorded...) {
		if seen[r.ID] || !isRoot(r) {
			continue
		}
		seen[r.ID] = true
		roots = append(roots, r)
		if c := str(inputConvoyKey, r); c != "" {
			convoyIDs = append(convoyIDs, c)
		}
	}
	convoys, err := l.Find(ledger.ByID(convoyIDs...).WithClosed())
	if err != nil {
		return nil, err
	}
	tracked := map[string][]string{}
	for _, c := range convoys {
		if c.IssueType() != "convoy" {
			continue
		}
		edges, err := c.Edges()
		if err != nil {
			return nil, &ledger.ReadError{ID: c.ID, Reason: "its edges did not decode: " + err.Error()}
		}
		var beads []string
		for _, e := range edges {
			if e.Type == "tracks" && !slices.Contains(beads, e.ID) {
				beads = append(beads, e.ID)
			}
		}
		tracked[c.ID] = beads
	}
	runs := make([]run, 0, len(roots))
	for _, r := range roots {
		runs = append(runs, runOf(r, tracked))
	}
	slices.SortFunc(runs, func(a, b run) int { return strings.Compare(a.root, b.root) })
	return runs, nil
}

// runOf is the run root is, over tracked, the beads each convoy the store
// returned tracks, as run-lib.sh's run_of reads it.
func runOf(root *ledger.Record, tracked map[string][]string) run {
	convoy, issue := str(inputConvoyKey, root), str(issueVarKey, root)
	if convoy == "" {
		return run{root: root.ID, bead: issue}
	}
	bead := ""
	if t := tracked[convoy]; len(t) == 1 {
		bead = t[0]
	}
	if issue != "" && issue != bead {
		bead = ""
	}
	return run{root: root.ID, convoy: convoy, bead: bead}
}

// pastLoadContext reports whether the live run under root has passed
// load-context: none of its open steps carries a ref ending in .load-context,
// so a formula with no such step counts as started.
func pastLoadContext(l *ledger.Ledger, root string) (bool, error) {
	steps, err := l.Find(ledger.Matching(rootBeadKey, root))
	if err != nil {
		return false, err
	}
	for _, st := range steps {
		if strings.HasSuffix(str(stepRefKey, st), ".load-context") {
			return false, nil
		}
	}
	return true, nil
}
