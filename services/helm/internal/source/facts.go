package source

import (
	"context"
	"sort"
	"sync"

	"github.com/steveyegge/beads"
	"github.com/zookanalytics/gc-toolkit/services/helm/internal/board"
)

// This file gathers the three CROSS-ANCHOR joins in [board.Facts] — visit
// presence, the live-workflow map, and session liveness. They are what let the
// board tell work in flight from work abandoned, and gc-helm.sh computes the
// same three (gather_visits, gather_inflight, and its OWNER_MAP) before it
// ranks anything.
//
// All three are BEST-EFFORT. Each failure is recorded as a partial error and
// leaves its map empty; a board with no liveness join is narrower — nothing
// reads as held or in flight — but it is not wrong about what it does show, and
// that is a far better failure than aborting a gather over a session list.

// liveStatuses is the "still open" set these joins query. A CLAIMED visit is a
// held conversation, not a finished one, so in_progress counts as open here
// exactly as it does in gc-helm.sh's snapshot.
var liveStatuses = []beads.Status{beads.StatusOpen, beads.StatusInProgress}

// visitSubjects returns the anchor ids that an open visit bead names — the
// conversation-is-held fact behind Tile.Held.
//
// THE SUBJECT COMES OFF THE `tracks` EDGE FIRST and the gc.continuation_group
// stamp only as a fallback, which is why the query hydrates dependencies. Both
// are written by the same visit-opener call and they do not always both land:
// on su-ab9je (2026-08-20, bead tk-d6ddn) the stamp landed EMPTY while the edge
// carried the subject. Re-measured 2026-08-24 over gc-toolkit's last seven days
// — 49 closed visits, 49 with the edge, 44 with the stamp.
//
// This read used to consult the stamp ALONE, while gc-helm.sh's gather_visits
// read both, so the same anchor could show held on the bash board and unheld
// here — the "fixed on one board, not the other" class this service's
// consolidation exists to end. It matters more than a glyph: a held anchor is
// never stranded, so a missed visit promotes a conversation that is actively
// being had to HIGH and tells the operator to go attend to it.
func (s *BeadsSource) visitSubjects(ctx context.Context, st beadStore, r rigRef, g *gatherState) []string {
	issues, err := st.SearchIssues(ctx, "", beads.IssueFilter{
		Statuses:            liveStatuses,
		MetadataFields:      map[string]string{"task_kind": "visit"},
		SkipWisps:           true,
		IncludeDependencies: true,
	})
	if err != nil {
		g.note(true, []string{"visits@" + r.name + ": " + err.Error()})
		return nil
	}
	var out []string
	for _, iss := range issues {
		if iss == nil {
			continue
		}
		if subj := subjectOf(iss); subj != "" {
			out = append(out, subj)
		}
	}
	return out
}

// workflowRoot is one graph.v2 molecule root as the in-flight join needs it:
// the convoy that names its work bead, plus every session stamped on the root
// or on its steps.
type workflowRoot struct {
	convoyID string
	sessions []string
}

// workflowRoots finds this rig's live-candidate graph.v2 roots.
//
// A root carries gc.input_convoy_id; the work bead it stands over is that
// convoy's single tracked member. The session name is read from the root,
// falling back to its STEP beads: roots stamp gc.session_name at claim time,
// but not every root in the store carries one, and the steps do.
func (s *BeadsSource) workflowRoots(ctx context.Context, st beadStore, r rigRef, g *gatherState) []workflowRoot {
	roots, err := st.SearchIssues(ctx, "", beads.IssueFilter{
		Statuses:       liveStatuses,
		HasMetadataKey: "gc.input_convoy_id",
		SkipWisps:      true,
	})
	if err != nil {
		g.note(true, []string{"workflow-roots@" + r.name + ": " + err.Error()})
		return nil
	}
	if len(roots) == 0 {
		return nil
	}

	steps, err := st.SearchIssues(ctx, "", beads.IssueFilter{
		Statuses:       liveStatuses,
		HasMetadataKey: "gc.root_bead_id",
		SkipWisps:      true,
	})
	if err != nil {
		// The root's own gc.session_name still resolves some molecules, so a
		// failed step read narrows the join rather than voiding it.
		g.note(true, []string{"workflow-steps@" + r.name + ": " + err.Error()})
	}

	byRoot := map[string][]string{}
	for _, iss := range steps {
		if iss == nil {
			continue
		}
		md := decodeMetadata(iss.Metadata)
		root, sess := md["gc.root_bead_id"], md["gc.session_name"]
		if root != "" && sess != "" {
			byRoot[root] = append(byRoot[root], sess)
		}
	}

	var out []workflowRoot
	for _, iss := range roots {
		if iss == nil {
			continue
		}
		md := decodeMetadata(iss.Metadata)
		convoy := md["gc.input_convoy_id"]
		if convoy == "" {
			continue
		}
		names := uniqueStrings(append([]string{md["gc.session_name"]}, byRoot[iss.ID]...))
		if len(names) == 0 {
			continue
		}
		out = append(out, workflowRoot{convoyID: convoy, sessions: names})
	}
	return out
}

// uniqueStrings sorts and dedups, dropping empties.
func uniqueStrings(in []string) []string {
	seen := map[string]bool{}
	out := make([]string, 0, len(in))
	for _, v := range in {
		if v == "" || seen[v] {
			continue
		}
		seen[v] = true
		out = append(out, v)
	}
	sort.Strings(out)
	return out
}

// resolveInflight turns live-candidate roots into the work-bead → session-names
// map [board.Facts] wants.
//
// LIVENESS FIRST, and it is what makes this safe. An open workflow root does
// NOT mean live work: nothing finalizes a graph.v2 chain after its session
// drains, so completed workflows leave husks behind and they accumulate.
// Joining on root existence alone would flip every husk to "in flight" and
// trade a false stall for a false all-clear — strictly the worse failure on a
// board whose job is to say what needs a human. So a root is resolved only when
// one of its stamped sessions is live, which also bounds the convoy reads by
// the number of live polecats rather than by the size of the husk pile.
func resolveInflight(ctx context.Context, gc gcClient, roots []workflowRoot, ownerState map[string]string, g *gatherState) map[string][]string {
	type job struct {
		convoyID string
		sessions []string
	}
	var live []job
	for _, r := range roots {
		var alive []string
		for _, n := range r.sessions {
			if st, ok := ownerState[n]; ok && st != "archived" && st != "closed" {
				alive = append(alive, n)
			}
		}
		if len(alive) > 0 {
			live = append(live, job{convoyID: r.convoyID, sessions: alive})
		}
	}
	if len(live) == 0 {
		return nil
	}

	// One `gc convoy status` per live root. They are independent, so run them
	// concurrently under a small bound: this is the only per-item subprocess in
	// the gather and it is what a cold CLI run would otherwise serialize.
	const maxParallel = 8
	sem := make(chan struct{}, maxParallel)
	var mu sync.Mutex
	var wg sync.WaitGroup
	out := map[string][]string{}

	for _, j := range live {
		wg.Add(1)
		go func(j job) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()

			member, err := gc.ConvoyMember(ctx, j.convoyID)
			mu.Lock()
			defer mu.Unlock()
			if err != nil {
				g.note(true, []string{"convoy status " + j.convoyID + ": " + err.Error()})
				return
			}
			if member == "" {
				return // not a one-member convoy: no claim about movement
			}
			out[member] = uniqueStrings(append(out[member], j.sessions...))
		}(j)
	}
	wg.Wait()

	if len(out) == 0 {
		return nil
	}
	return out
}

// sessionStates reads the city's session liveness, or records why it could not.
func sessionStates(ctx context.Context, gc gcClient, g *gatherState) map[string]string {
	states, err := gc.Sessions(ctx)
	if err != nil {
		// Without this map EVERY claim reads as a dead owner, which would turn
		// a healthy board bright red. Say so loudly in partial_errors rather
		// than letting the degraded reading pass for a finding.
		g.note(true, []string{"session liveness unavailable (every claim will read as unowned): " + err.Error()})
		return nil
	}
	return states
}

// buildFacts assembles the three joins into the value BuildBoard consumes.
func buildFacts(visits []string, inflight map[string][]string, owners map[string]string, rigs []rigRef) board.Facts {
	f := board.Facts{
		Inflight:   inflight,
		OwnerState: owners,
	}
	if len(visits) > 0 {
		f.Visits = make(map[string]bool, len(visits))
		for _, v := range visits {
			f.Visits[v] = true
		}
	}
	for _, r := range rigs {
		if r.prefix != "" {
			f.Prefixes = append(f.Prefixes, r.prefix)
		}
		f.RigNames = append(f.RigNames, r.name)
	}
	f.Prefixes = uniqueStrings(f.Prefixes)
	f.RigNames = uniqueStrings(f.RigNames)
	return f
}
