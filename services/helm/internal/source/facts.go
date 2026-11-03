package source

import (
	"context"
	"os"
	"sort"
	"strings"
	"time"

	"github.com/steveyegge/beads"
	"github.com/zookanalytics/gc-toolkit/services/helm/internal/board"
)

// This file gathers the CROSS-ANCHOR joins in [board.Facts] — the live-workflow
// map and session liveness — and the conversations, which reach the board both
// as anchors the fold moves onto their beads and as the sittings record. They
// are what let the board tell work in flight from work abandoned, and a bead a
// person is talking about from one nobody is.
//
// All of them are BEST-EFFORT. Each failure is recorded as a partial error and
// leaves its part empty; a board with no liveness join is narrower — nothing
// reads as in flight or in session — but it is not wrong about what it does
// show, and that is a far better failure than aborting a gather over a session
// list.

// liveStatuses is the "still open" set these joins query. A conversation a
// sitting has claimed is in_progress, and so is a live graph.v2 root, so
// in_progress counts as open here.
var liveStatuses = []beads.Status{beads.StatusOpen, beads.StatusInProgress}

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

// rigConversations gathers one rig's conversations: every open one, as an
// anchor the fold moves onto its bead ([board.KindConversation]) and as a
// sitting, plus those closed inside the window, as sittings alone.
//
// A conversation is a task that tracks the one bead it is about, assigned to
// `human` while it waits in the operator's queue and to an alias that names its
// own id while a sitting holds it (assets/scripts/conversation.sh). It carries
// no pack marker, so the query cuts by type and status and the shape is read
// here: the assignee off the row, and the edges from one batched read of every
// candidate's own dependencies. That read names the conversation's `tracks`
// edge and its `replies-to` edges whichever store holds the gate a reply
// names. bd's close leaves a task's assignee and edges as they were, so a
// closed conversation keeps its shape, and the closed pass finds it the same
// way.
//
// The two passes fail INDEPENDENTLY. The open pass is what holds a bead, so
// losing the closed pass must not cost the board its held state, and losing
// the open pass must not suppress the record of what just finished. A failed
// edge read leaves no conversation from either, because without its edges no
// task can be told for one. Each failure narrows the board and says so in
// partial_errors.
//
// A CLOSED pass is bounded on the query rather than in the renderer: closed
// tasks accumulate forever, and a gather that read them all to throw most away
// would grow without limit against a store the whole city shares.
func (s *BeadsSource) rigConversations(ctx context.Context, st beadStore, r rigRef, g *gatherState, now time.Time) ([]board.Anchor, []board.Sitting) {
	task := beads.IssueType("task")
	open, err := st.SearchIssues(ctx, "", beads.IssueFilter{
		IssueType: &task,
		Statuses:  liveStatuses,
		SkipWisps: true,
		Lite:      true,
	})
	if err != nil {
		g.note(true, []string{"conversations@" + r.name + ": " + err.Error()})
	}
	open = conversationCandidates(open)

	var done []*beads.Issue
	if window := sittingWindow(); window > 0 {
		cutoff := now.Add(-window)
		status := beads.StatusClosed
		done, err = st.SearchIssues(ctx, "", beads.IssueFilter{
			IssueType:   &task,
			Status:      &status,
			ClosedAfter: &cutoff,
			SkipWisps:   true,
			Lite:        true,
		})
		if err != nil {
			g.note(true, []string{"closed-conversations@" + r.name + ": " + err.Error()})
		}
		done = conversationCandidates(done)
	}

	ids := make([]string, 0, len(open)+len(done))
	for _, iss := range append(append([]*beads.Issue{}, open...), done...) {
		ids = append(ids, iss.ID)
	}
	if ids = uniqueStrings(ids); len(ids) == 0 {
		return nil, nil
	}
	recs, err := st.GetDependencyRecordsForIssues(ctx, ids)
	if err != nil {
		g.note(true, []string{"conversation-edges@" + r.name + ": " + err.Error()})
		return nil, nil
	}

	var anchors []board.Anchor
	var sittings []board.Sitting
	for _, iss := range open {
		subject, replies, ok := conversationEdges(recs[iss.ID])
		if !ok {
			continue
		}
		a := newAnchor(iss, board.KindConversation, r)
		a.Subjects, a.RepliesTo, a.Assignee = []string{subject}, replies, iss.Assignee
		anchors = append(anchors, a)
		sittings = append(sittings, newSitting(iss, r, subject))
	}
	for _, iss := range done {
		if subject, _, ok := conversationEdges(recs[iss.ID]); ok {
			sittings = append(sittings, newSitting(iss, r, subject))
		}
	}
	s.attributeTakeaways(ctx, st, r, g, sittings, now)
	return anchors, sittings
}

// conversationCandidates keeps the tasks whose assignee is one a conversation
// carries ([conversationAssignee]). Their edges decide the rest of the shape.
func conversationCandidates(in []*beads.Issue) []*beads.Issue {
	out := make([]*beads.Issue, 0, len(in))
	for _, iss := range in {
		if iss != nil && conversationAssignee(iss.Assignee, iss.ID) {
			out = append(out, iss)
		}
	}
	return out
}

// conversationAssignee reports whether assignee is one a conversation carries:
// `human`, or the alias that names the task's own id, bare, as its `c-`
// fallback, or qualified by the session's rig and template binding
// (`<rig>/<binding>.<alias>`). It is the rule conversation.sh's
// conversation_assignee applies, so the board and the scripts read one shape.
func conversationAssignee(assignee, id string) bool {
	if assignee == "" || id == "" {
		return false
	}
	if assignee == "human" {
		return true
	}
	for _, alias := range []string{id, "c-" + id} {
		if assignee == alias || strings.HasSuffix(assignee, "/"+alias) || strings.HasSuffix(assignee, "."+alias) {
			return true
		}
	}
	return false
}

// conversationEdges reads a conversation's subject and replies off its own
// edges: ok only when exactly one `tracks` edge names a bead, which is the
// subject, and replies is every gate its `replies-to` edges name.
func conversationEdges(ds []*beads.Dependency) (subject string, replies []string, ok bool) {
	var tracked []string
	for _, d := range ds {
		if d == nil {
			continue
		}
		switch string(d.Type) {
		case "tracks":
			tracked = append(tracked, d.DependsOnID)
		case "replies-to":
			replies = append(replies, d.DependsOnID)
		}
	}
	if tracked = uniqueStrings(tracked); len(tracked) != 1 {
		return "", nil, false
	}
	return tracked[0], uniqueStrings(replies), true
}

// newSitting projects one conversation task onto the board's record of a
// sitting. A closed conversation's close reason is the sentence its ending
// wrote, which the card reads when the sitting left no takeaway.
func newSitting(iss *beads.Issue, r rigRef, subject string) board.Sitting {
	md := decodeMetadata(iss.Metadata)
	st := board.Sitting{
		ID:       iss.ID,
		Rig:      r.name,
		Subject:  subject,
		Title:    iss.Title,
		Status:   string(iss.Status),
		Assignee: iss.Assignee,
		Session:  md["gc.session_name"],
		FiledAt:  iss.CreatedAt.UTC(),
		OpenedAt: iss.CreatedAt,
	}
	// A conversation exists from the moment it is filed, but the SITTING starts
	// when a converse session claims it, and a conversation can wait in the
	// operator's queue for as long as they leave it there. The claim stamp is
	// the truer start; the creation time is the fallback for one no sitting has
	// claimed.
	if claimed, ok := parseStamp(md["gc.claimed_at"]); ok {
		st.OpenedAt = claimed
	}
	if iss.Status == beads.StatusClosed {
		st.OutcomeReason = strings.TrimSpace(iss.CloseReason)
	}
	if iss.ClosedAt != nil {
		st.ClosedAt = iss.ClosedAt.UTC()
	}
	return st
}

// attributeTakeaways fills in the two things a row reads off its SUBJECT bead,
// from one batch read of those beads: the subject's TITLE, which is the row's
// topic and is carried onto every sitting whose subject was read; and the
// TAKEAWAY, which is kept only for the sitting whose span contains its timestamp
// (see board.Sitting.Takeaway for why the span test is the whole point). The
// title has no such span test — a subject's title is what it is about whenever
// the sitting ran, not a thing one sitting authored — so it rides every row.
//
// Failure is silent in the board's usual direction: a subject that cannot be
// read leaves its sittings showing an outcome and neither a topic nor a
// headline, which is a narrower row rather than a wrong one. It is still
// recorded as partial, since a store that will not answer this read is a store
// the rest of the gather should be doubted on too.
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
	titleByID := make(map[string]string, len(subjects))
	for _, iss := range subjects {
		if iss == nil {
			continue
		}
		titleByID[iss.ID] = iss.Title
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
		// The topic rides every row whose subject was read, before the span
		// test the takeaway must pass: a row with no attributable takeaway still
		// says what it is about.
		s.SubjectTitle = titleByID[s.Subject]
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

// workflowRoot is one graph.v2 molecule root as the in-flight join needs it:
// the root, the work bead its run works, plus every session stamped on the root
// or on its steps. The member is resolved in-process during the rig gather (see
// convoyMembers); the convoy id is kept as the key that resolution reads.
type workflowRoot struct {
	rootID   string
	convoyID string
	issue    string // the root's gc.var.issue, "" when it records none
	member   string // the bead the run works, "" when it names none
	sessions []string
}

// workflowRoots finds this rig's live-candidate graph.v2 roots.
//
// It copies the part of the rule assets/scripts/run-lib.sh defines that reads
// an input convoy, and TestWorkflowRootsAgreeWithRunLibFixture holds it to that
// file's fixture. A workflow root names its input convoy in gc.input_convoy_id,
// and the work bead its run works is that convoy's single tracked member. A
// root whose gc.var.issue names another bead is wired wrong and works none. A
// root that names no input convoy is not read here, though run-lib.sh gives
// such a root, a classic molecule among them, the bead its gc.var.issue names.
// The session name is read from the root, falling back to its STEP beads:
// roots stamp gc.session_name at claim time, but not every root in the store
// carries one, and the steps do.
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
	var convoyIDs []string
	for _, iss := range roots {
		if iss == nil {
			continue
		}
		md := decodeMetadata(iss.Metadata)
		if !isRunRoot(iss, md) {
			continue
		}
		convoy := strings.TrimSpace(md["gc.input_convoy_id"])
		if convoy == "" {
			continue
		}
		names := uniqueStrings(append([]string{md["gc.session_name"]}, byRoot[iss.ID]...))
		if len(names) == 0 {
			continue
		}
		out = append(out, workflowRoot{rootID: iss.ID, convoyID: convoy, issue: strings.TrimSpace(md["gc.var.issue"]), sessions: names})
		convoyIDs = append(convoyIDs, convoy)
	}

	// Resolve each convoy to its single tracked member from THIS rig's store,
	// in one batched read. The input convoy is minted by the sling in its
	// root's own rig, so its `tracks` edge is always local — no cross-rig read
	// and no `gc convoy status` subprocess.
	members := convoyMembers(ctx, st, r, convoyIDs, g)
	for i := range out {
		m := members[out[i].convoyID]
		if out[i].issue != "" && out[i].issue != m {
			m = ""
		}
		out[i].member = m
	}
	return out
}

// isRunRoot reports whether a bead is a workflow root, as run-lib.sh's
// run_is_root reads one: a graph.v2 root as Gas City marks it, or a classic
// molecule.
func isRunRoot(iss *beads.Issue, md map[string]string) bool {
	return strings.EqualFold(strings.TrimSpace(md["gc.kind"]), "workflow") ||
		strings.EqualFold(strings.TrimSpace(md["gc.formula_contract"]), "graph.v2") ||
		string(iss.IssueType) == "molecule"
}

// convoyMembers resolves each convoy to its SINGLE tracked member from the rig
// store, keyed by convoy id. The one-member rule is a fail-closed gate: a convoy
// that tracks any other number resolves to no entry, which resolveInflight reads
// as "no claim about movement" rather than a guess. One batched
// GetDependencyRecordsForIssues — the read this gather already spends on convoy
// anchors — serves the whole set, so the in-flight join costs no per-root
// subprocess. A failed read narrows the join and is noted partial, the same
// best-effort direction as every other join in this file.
func convoyMembers(ctx context.Context, st beadStore, r rigRef, convoyIDs []string, g *gatherState) map[string]string {
	convoyIDs = uniqueStrings(convoyIDs)
	if len(convoyIDs) == 0 {
		return nil
	}
	recs, err := st.GetDependencyRecordsForIssues(ctx, convoyIDs)
	if err != nil {
		g.note(true, []string{"convoy-members@" + r.name + ": " + err.Error()})
		return nil
	}
	out := make(map[string]string, len(convoyIDs))
	for id, ds := range recs {
		var members []string
		for _, d := range ds {
			if d != nil && string(d.Type) == "tracks" {
				members = append(members, d.DependsOnID)
			}
		}
		if members = uniqueStrings(members); len(members) == 1 {
			out[id] = members[0]
		}
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
// one of its stamped sessions is live.
//
// The work bead each convoy tracks is resolved in-process by convoyMembers
// during the rig gather, so this join reads it off the root rather than spawning
// a `gc convoy status` per live root. A root whose convoy did not resolve to
// exactly one member carries no member and makes no claim about movement,
// exactly as the one-member rule required before.
func resolveInflight(roots []workflowRoot, ownerState map[string]string) map[string][]string {
	out := map[string][]string{}
	for _, r := range roots {
		if r.member == "" {
			continue // not a one-member convoy: no claim about movement
		}
		var alive []string
		for _, n := range r.sessions {
			if st, ok := ownerState[n]; ok && st != "archived" && st != "closed" {
				alive = append(alive, n)
			}
		}
		if len(alive) == 0 {
			continue
		}
		out[r.member] = uniqueStrings(append(out[r.member], alive...))
	}
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
