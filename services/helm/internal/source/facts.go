package source

import (
	"context"
	"os"
	"sort"
	"strings"
	"sync"
	"time"

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

// visitFilter selects converse sittings. task_kind is what separates a visit
// from every other bead: gc.outcome — the field a closed sitting is read for —
// is stamped on step beads, review beads and dog warrants too, so a query keyed
// on it would gather most of the city.
var visitFilter = map[string]string{"task_kind": "visit"}

// defaultSittingWindow is how far back a CLOSED sitting stays on the board.
// A day covers the shift an operator is actually reconstructing; older
// conversations are history, and history belongs to the bead, not to a board
// that re-gathers every render.
const defaultSittingWindow = 24 * time.Hour

// sittingWindow reads GC_HELM_SITTINGS_WINDOW as a Go duration ("6h", "90m").
// Zero is honoured and means running sittings only. Anything unparseable or
// negative falls back to the default rather than erroring: a malformed knob
// must not cost the board a section it would otherwise render.
func sittingWindow() time.Duration {
	v := strings.TrimSpace(os.Getenv("GC_HELM_SITTINGS_WINDOW"))
	if v == "" {
		return defaultSittingWindow
	}
	d, err := time.ParseDuration(v)
	if err != nil || d < 0 {
		return defaultSittingWindow
	}
	return d
}

// rigSittings gathers one rig's converse sittings: every open visit bead, plus
// those closed inside the window.
//
// The two passes fail INDEPENDENTLY. The open pass is what Tile.Held is derived
// from, so losing the closed pass must not cost the board its held glyphs, and
// losing the open pass must not suppress the record of what just finished.
// Either failure narrows the section and says so in partial_errors.
//
// A CLOSED pass is new ground for this gather, which has otherwise only ever
// read open beads. It is bounded on the query rather than in the renderer:
// closed visits accumulate forever, and a gather that read them all to throw
// most away would grow without limit against a store the whole city shares.
func (s *BeadsSource) rigSittings(ctx context.Context, st beadStore, r rigRef, g *gatherState, now time.Time) []board.Sitting {
	var out []board.Sitting

	open, err := st.SearchIssues(ctx, "", beads.IssueFilter{
		Statuses:       liveStatuses,
		MetadataFields: visitFilter,
		SkipWisps:      true,
	})
	if err != nil {
		g.note(true, []string{"visits@" + r.name + ": " + err.Error()})
	}
	for _, iss := range open {
		if iss != nil {
			out = append(out, newSitting(iss, r))
		}
	}

	if window := sittingWindow(); window > 0 {
		cutoff := now.Add(-window)
		status := beads.StatusClosed
		done, err := st.SearchIssues(ctx, "", beads.IssueFilter{
			Status:         &status,
			MetadataFields: visitFilter,
			ClosedAfter:    &cutoff,
			SkipWisps:      true,
		})
		if err != nil {
			g.note(true, []string{"closed-visits@" + r.name + ": " + err.Error()})
		}
		for _, iss := range done {
			if iss != nil {
				out = append(out, newSitting(iss, r))
			}
		}
	}

	s.attributeTakeaways(ctx, st, r, g, out, now)
	return out
}

// newSitting projects one visit bead onto the board's record of a sitting.
func newSitting(iss *beads.Issue, r rigRef) board.Sitting {
	md := decodeMetadata(iss.Metadata)
	st := board.Sitting{
		ID:       iss.ID,
		Rig:      r.name,
		Subject:  md["gc.continuation_group"],
		Title:    iss.Title,
		Status:   string(iss.Status),
		Outcome:  md["gc.outcome"],
		Session:  md["gc.session_name"],
		OpenedAt: iss.CreatedAt,
	}
	// A visit exists from the moment it is filed, but the CONVERSATION starts
	// when a converse session claims it, and a visit can wait in the pool for
	// as long as the pool is busy. The claim stamp is the truer start; the
	// creation time is the fallback for a sitting that has not been claimed.
	if claimed, ok := parseStamp(md["gc.claimed_at"]); ok {
		st.OpenedAt = claimed
	}
	if iss.ClosedAt != nil {
		st.ClosedAt = iss.ClosedAt.UTC()
	}
	return st
}

// attributeTakeaways fills in the headline each sitting left, reading the
// SUBJECT beads in one batch and keeping a takeaway only for the sitting whose
// span contains its timestamp (see board.Sitting.Takeaway for why the span test
// is the whole point).
//
// Failure is silent in the board's usual direction: a subject that cannot be
// read leaves its sittings showing an outcome and no headline, which is a
// narrower row rather than a wrong one. It is still recorded as partial, since
// a store that will not answer this read is a store the rest of the gather
// should be doubted on too.
func (s *BeadsSource) attributeTakeaways(ctx context.Context, st beadStore, r rigRef, g *gatherState, sittings []board.Sitting, now time.Time) {
	var ids []string
	for _, sit := range sittings {
		if sit.Subject != "" {
			ids = append(ids, sit.Subject)
		}
	}
	ids = uniqueStrings(ids)
	if len(ids) == 0 {
		return
	}

	// No status scope on purpose: a subject closed since its sitting ended
	// still owns the takeaway that sitting wrote.
	subjects, err := st.SearchIssues(ctx, "", beads.IssueFilter{IDs: ids, SkipWisps: true})
	if err != nil {
		g.note(true, []string{"sitting-subjects@" + r.name + ": " + err.Error()})
		return
	}

	type stamped struct {
		text string
		at   time.Time
	}
	byID := make(map[string]stamped, len(subjects))
	for _, iss := range subjects {
		if iss == nil {
			continue
		}
		md := decodeMetadata(iss.Metadata)
		text := md["gc.takeaway"]
		if text == "" {
			continue
		}
		// A takeaway with no readable timestamp cannot be placed in any
		// sitting's span, so it is attributed to none. Crediting the newest
		// sitting instead would be a guess, and the guess is wrong for exactly
		// the subject that has been visited more than once.
		at, ok := parseStamp(md["gc.takeaway_at"])
		if !ok {
			continue
		}
		byID[iss.ID] = stamped{text: text, at: at}
	}

	for i := range sittings {
		s := &sittings[i]
		got, ok := byID[s.Subject]
		if !ok {
			continue
		}
		end := s.ClosedAt
		if end.IsZero() {
			end = now // a running sitting is still able to write one
		}
		if got.at.Before(s.OpenedAt) || got.at.After(end) {
			continue
		}
		s.Takeaway = got.text
	}
}

// parseStamp reads one of the RFC 3339 timestamps the city writes — bead
// metadata, a build order's status record. Both are free text, so an
// unparseable value is an absence rather than an error — every caller has a
// defined behaviour for "not known".
func parseStamp(v string) (time.Time, bool) {
	v = strings.TrimSpace(v)
	if v == "" {
		return time.Time{}, false
	}
	t, err := time.Parse(time.RFC3339, v)
	if err != nil {
		return time.Time{}, false
	}
	return t.UTC(), true
}

// visitSubjects is the conversation-is-held fact behind Tile.Held: the anchors
// a RUNNING sitting names. It reads the gathered record rather than re-querying,
// so the glyph and the sittings section can never disagree about what is held.
func visitSubjects(sittings []board.Sitting) []string {
	var out []string
	for _, s := range sittings {
		if s.Status != string(beads.StatusClosed) && s.Subject != "" {
			out = append(out, s.Subject)
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

// buildFacts assembles the joins into the value BuildBoard consumes.
func buildFacts(sittings []board.Sitting, inflight map[string][]string, owners map[string]string, rigs []rigRef) board.Facts {
	f := board.Facts{
		Inflight:   inflight,
		OwnerState: owners,
		Sittings:   sittings,
	}
	if visits := visitSubjects(sittings); len(visits) > 0 {
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
