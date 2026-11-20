package waits

import (
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// The run link: which bead a workflow run works. assets/scripts/run-lib.sh is
// its one definition, and this copies the part of it that reads every live run,
// its map verb, and the part that reads the runs that work one bead, its runs
// verb, which TestRunsAgreeWithRunLibFixture holds to that file's fixture.
// LiveRunsOf reads the runs verb's answer from live roots alone, which
// run-lib.sh has no verb for. Gas City pours a graph.v2 run over an input
// convoy: the root names the convoy in the key inputConvoyKey declares, and the
// convoy tracks the bead the run works. A classic molecule names no convoy and
// records its bead in its issue variable, issueVarKey. So a run works the one
// bead its input convoy tracks, or, when its root names no convoy, the bead its
// issue variable names. A convoy that tracks no bead, or more than one, names
// none, and so does a convoy the store does not return. A root whose issue
// variable names a bead its convoy does not track names none either. A run is
// live until its root closes.

// tracks is the type of the edge a convoy tracks a bead by.
const tracks = "tracks"

// Run is one workflow run: its root, the input convoy the root names, empty
// when it names none, the bead the run works, empty when it names none, the
// formula the root records it was poured from, empty when it records none, and
// whether it is live.
type Run struct {
	Root, Convoy, Bead, Formula string
	Live                        bool
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

// IsRootOrStep reports whether r is one of a run's own beads: a run's root, as
// isRoot reads one, or a step poured under a root, which names that root.
func IsRootOrStep(r *ledger.Record) bool { return isRoot(r) || str(rootBeadKey, r) != "" }

// LiveRuns reads every live run in the store, in root order, as run-lib.sh's
// map verb does: the live roots that name an input convoy, the live roots that
// record an issue, and every convoy those roots name, closed ones included. A
// read that fails returns its *ledger.ReadError.
func LiveRuns(l *ledger.Ledger) ([]Run, error) {
	named, err := l.Find(ledger.Carrying(inputConvoyKey))
	if err != nil {
		return nil, err
	}
	recorded, err := l.Find(ledger.Carrying(issueVarKey))
	if err != nil {
		return nil, err
	}
	return runsOver(l, append(named, recorded...))
}

// RunsOf reads every run that works bead, live or not, in root order, as
// run-lib.sh's runs verb does: the convoys that track the bead, the roots
// poured over each of them and the roots that record the bead as their issue,
// closed ones included, and every convoy those roots name. A read that fails
// returns its *ledger.ReadError, and so does a bead the store does not hold.
func RunsOf(l *ledger.Ledger, bead string) ([]Run, error) {
	up, err := l.Dependents(bead, tracks)
	if err != nil {
		return nil, err
	}
	return runsWorking(l, bead, up, func(s ledger.Selection) ledger.Selection { return s.WithClosed() })
}

// LiveRunsOf reads the live runs that work bead, in root order, as RunsOf reads
// them but from live roots alone, so its cost does not grow with the closed
// beads the store holds. up is the beads with a tracks edge onto bead, as
// l.Dependents reads them, which a caller that asks its own question of them
// reads once for both. It names each live run RunsOf names, except one whose
// root the store's listing of live beads leaves out: bd leaves out a pinned
// bead, by its status or by its pinned flag, and a bead whose status the store
// adds as a done or frozen one. A read that fails returns its
// *ledger.ReadError.
func LiveRunsOf(l *ledger.Ledger, bead string, up []*ledger.Record) ([]Run, error) {
	runs, err := runsWorking(l, bead, up, func(s ledger.Selection) ledger.Selection { return s })
	if err != nil {
		return nil, err
	}
	return slices.DeleteFunc(runs, func(r Run) bool { return !r.Live }), nil
}

// runsWorking is the runs that work bead, in root order, over up, the beads
// that track it, reading the roots each convoy among up has poured over it and
// the roots that record bead as their issue, each through roots.
func runsWorking(l *ledger.Ledger, bead string, up []*ledger.Record, roots func(ledger.Selection) ledger.Selection) ([]Run, error) {
	var rows []*ledger.Record
	seen := map[string]bool{}
	for _, c := range up {
		if c.IssueType() != "convoy" || seen[c.ID] {
			continue
		}
		seen[c.ID] = true
		poured, err := l.Find(roots(ledger.Matching(inputConvoyKey, c.ID)))
		if err != nil {
			return nil, err
		}
		rows = append(rows, poured...)
	}
	recorded, err := l.Find(roots(ledger.Matching(issueVarKey, bead)))
	if err != nil {
		return nil, err
	}
	all, err := runsOver(l, append(rows, recorded...))
	if err != nil {
		return nil, err
	}
	var out []Run
	for _, r := range all {
		if r.Bead == bead {
			out = append(out, r)
		}
	}
	return out, nil
}

// runsOver is the run each root among rows is, once each, in root order, over
// one read of every convoy those roots name, closed ones included, as
// run-lib.sh's run_rows judges them.
func runsOver(l *ledger.Ledger, rows []*ledger.Record) ([]Run, error) {
	var roots []*ledger.Record
	var convoyIDs []string
	seen := map[string]bool{}
	for _, r := range rows {
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
			if e.Type == tracks && !slices.Contains(beads, e.ID) {
				beads = append(beads, e.ID)
			}
		}
		tracked[c.ID] = beads
	}
	runs := make([]Run, 0, len(roots))
	for _, r := range roots {
		runs = append(runs, runOf(r, tracked))
	}
	slices.SortFunc(runs, func(a, b Run) int { return strings.Compare(a.Root, b.Root) })
	return runs, nil
}

// runOf is the run root is, over tracked, the beads each convoy the store
// returned tracks, as run-lib.sh's run_of reads it.
func runOf(root *ledger.Record, tracked map[string][]string) Run {
	convoy, issue := str(inputConvoyKey, root), str(issueVarKey, root)
	run := Run{Root: root.ID, Convoy: convoy, Formula: str(formulaNameKey, root), Live: root.Status() != "closed"}
	if convoy == "" {
		run.Bead = issue
		return run
	}
	if t := tracked[convoy]; len(t) == 1 {
		run.Bead = t[0]
	}
	if issue != "" && issue != run.Bead {
		run.Bead = ""
	}
	return run
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
