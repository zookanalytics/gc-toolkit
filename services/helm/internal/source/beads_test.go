package source

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"maps"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/steveyegge/beads"
	"github.com/zookanalytics/gc-toolkit/services/helm/internal/board"
)

// fakeStore is a beadStore over in-memory fixtures. It stands in for a real
// rig's Dolt-backed store so Gather is exercised without a live city.
type fakeStore struct {
	issues   map[string][]*beads.Issue                       // keyed by issue type
	depsDown map[string][]*beads.IssueWithDependencyMetadata // convoy -> tracked members
	depsUp   map[string][]*beads.IssueWithDependencyMetadata // epic -> parent-child children
	failType map[string]error                                // issue type -> forced SearchIssues error
	failMeta map[string]error                                // metadata key -> forced SearchIssues error
	failDeps map[string]error                                // issue id -> forced dependency error
	failIDs  map[string]error                                // issue id -> forced error from an ID search naming it
	kv       map[string]string                               // config table: `bd kv` keys, "kv."-prefixed
	failKV   error                                           // forced GetConfig error
	closed   bool

	// Read tallies, for the batched-edge-read acceptance test: the edge reads
	// must not scale with the number of anchors.
	searchN, depnN, depyN int

	// calls records every SearchIssues filter, so a test can assert the shape of
	// the query the gather asked — which pass reads lite, which reads full.
	calls []beads.IssueFilter
}

// SearchIssues answers both gather shapes: the type-keyed anchor queries, and
// the metadata-keyed ones tk-2v08m added. It APPLIES the filters rather than
// trusting them, because every one of them is load-bearing — a fake that
// returned its fixtures regardless would let the gather ask a wrong question
// and still pass.
func (f *fakeStore) SearchIssues(_ context.Context, _ string, filter beads.IssueFilter) ([]*beads.Issue, error) {
	f.searchN++
	f.calls = append(f.calls, filter)
	// An id-keyed read is the one shape with no status scope, and that is the
	// point of it: the sitting gather resolves a subject bead whether or not it
	// has since closed. It is matched first so the scope rule below stays a
	// rule about the SEARCHES.
	if len(filter.IDs) > 0 {
		out, err := f.searchByIDs(filter)
		return liteProject(out, filter), err
	}

	// Every other gather query must scope its statuses; a fake that ignored the
	// filter would let a regression through silently. Three shapes are legal:
	//
	//   Status=open              the LIVE ANCHOR queries — an anchor is an open bead.
	//   Status=closed + ClosedAfter
	//                            the closed-row passes — the DONE band and the
	//                            recently-closed sittings. The bound is half the
	//                            shape, not a refinement of it: unbounded, the
	//                            query returns every anchor the ledger ever
	//                            closed, which is the board flooded rather than
	//                            the board stable. A fake that accepted it would
	//                            leave that untested.
	//   Statuses=[open,inprog]   the JOIN queries (conversations, workflow roots
	//                            and steps) — a CLAIMED conversation is a held
	//                            one, not a finished one, and a claimed step is
	//                            the normal state of a live molecule.
	//   Statuses=bd-lib.sh's live set, keyed on task_kind=review
	//                            the live REVIEW read (readReviews), which reads
	//                            an anchor's live children the way bd-lib.sh
	//                            does. The set is spelled out here, not read from
	//                            the source, so the fake pins it to bd-lib.sh's.
	//   Statuses=the same live set, keyed on anchor_bead's presence
	//                            the IN-FLIGHT read (readInFlight), a live merge
	//                            anchor's in-flight set as `gctk pr-status
	//                            derive` reads it.
	//   ExcludeStatus=[closed], keyed on issue_type=gate
	//                            the live HUMAN GATE read, which reads every gate
	//                            that still holds the way bd-lib.sh's
	//                            HUMAN_GATE_JQ does: in every status but closed.
	//
	// Anything else — no scope at all, or a widened one — is refused, so the
	// filter stays load-bearing rather than decorative.
	reviewRead := len(filter.MetadataFields) == 1 && filter.MetadataFields["task_kind"] == "review"
	inFlightRead := len(filter.MetadataFields) == 0 && filter.HasMetadataKey == "anchor_bead"
	gateRead := filter.IssueType != nil && *filter.IssueType == beads.IssueType("gate")
	switch {
	case len(filter.ExcludeStatus) > 0:
		if !gateRead || filter.Status != nil || len(filter.Statuses) > 0 || !slices.Equal(filter.ExcludeStatus, []beads.Status{beads.StatusClosed}) {
			return nil, errors.New("a status exclusion is the live gate read alone: issue_type=gate excluding closed, with no other status scope")
		}
	case filter.Status != nil && *filter.Status == beads.StatusOpen && len(filter.Statuses) == 0:
	case filter.Status != nil && *filter.Status == beads.StatusClosed && len(filter.Statuses) == 0:
		if filter.ClosedAfter == nil {
			return nil, errors.New("a closed-bead query must bound its window with ClosedAfter")
		}
	case filter.Status == nil && slices.Equal(filter.Statuses, []beads.Status{beads.StatusOpen, beads.StatusInProgress}):
	case filter.Status == nil && (reviewRead || inFlightRead) && slices.Equal(filter.Statuses, []beads.Status{"open", "in_progress", "blocked", "deferred", "hooked", "pinned"}):
	default:
		return nil, errors.New("expected status=open (anchors), statuses=[open,in_progress] (joins), status=closed+ClosedAfter (closed rows), the live review or in-flight read, or the live gate read")
	}
	if filter.IssueType != nil {
		kind := string(*filter.IssueType)
		if err, bad := f.failType[kind]; bad {
			return nil, err
		}
		return liteProject(f.matching(f.issues[kind], filter), filter), nil
	}
	out, err := f.searchByMetadata(filter)
	if err != nil {
		return nil, err
	}
	return liteProject(f.matching(out, filter), filter), nil
}

// liteProject mirrors the library's lite SELECT: with filter.Lite set it returns
// COPIES whose six HeavyDropList columns (description, design, acceptance_criteria,
// notes, waiters, payload) are zeroed and IsLitePartial is true, so a test sees
// exactly what a lite read hands back. Copies, not mutations: the fixtures are
// shared across a gather's many reads, and a full read after a lite one must
// still find the heavy fields.
func liteProject(in []*beads.Issue, filter beads.IssueFilter) []*beads.Issue {
	if !filter.Lite {
		return in
	}
	out := make([]*beads.Issue, len(in))
	for i, iss := range in {
		if iss == nil {
			continue
		}
		c := *iss
		c.Description = ""
		c.Design = ""
		c.AcceptanceCriteria = ""
		c.Notes = ""
		c.Waiters = nil
		c.Payload = ""
		c.IsLitePartial = true
		out[i] = &c
	}
	return out
}

// searchByIDs models `id IN (...)`, which is what the shared SQL builder emits
// for IssueFilter.IDs.
func (f *fakeStore) searchByIDs(filter beads.IssueFilter) ([]*beads.Issue, error) {
	if err, bad := f.failMeta["__ids__"]; bad {
		return nil, err
	}
	want := map[string]bool{}
	for _, id := range filter.IDs {
		if err, bad := f.failIDs[id]; bad {
			return nil, err
		}
		want[id] = true
	}
	found := map[string]bool{}
	var out []*beads.Issue
	for _, kind := range slices.Sorted(maps.Keys(f.issues)) { // deterministic order
		for _, iss := range f.issues[kind] {
			if want[iss.ID] && !found[iss.ID] {
				out = append(out, iss)
				found[iss.ID] = true
			}
		}
	}
	// The far-end children and blockers live embedded in the dependency
	// fixtures, not in f.issues, so the batched gather's hydration — one
	// SearchIssues over every edge's far end — must resolve them here too, the
	// way a real store returns them from its issues table. A bead in f.issues
	// wins a collision; a fixture does not disagree with itself.
	for _, embedded := range []map[string][]*beads.IssueWithDependencyMetadata{f.depsUp, f.depsDown} {
		for _, deps := range embedded {
			for _, d := range deps {
				if d == nil || !want[d.Issue.ID] || found[d.Issue.ID] {
					continue
				}
				iss := d.Issue
				out = append(out, &iss)
				found[d.Issue.ID] = true
			}
		}
	}
	return out, nil
}

// matching applies the status, closed-window, created-window and metadata
// predicates the library applies in SQL. Without it the fake would hand an
// open-conversation query the closed ones too: the two sitting passes could not
// be told apart, and the done pass would re-return every OPEN anchor as a
// closed one. The created window and the metadata equality are what the
// failed-start read selects on (a type-keyed query, which searchByMetadata does
// not reach), so a fake that skipped them would let that read ask the wrong
// question and still find its session.
func (f *fakeStore) matching(in []*beads.Issue, filter beads.IssueFilter) []*beads.Issue {
	var out []*beads.Issue
	for _, iss := range in {
		if filter.Status != nil && iss.Status != *filter.Status {
			continue
		}
		if len(filter.Statuses) > 0 && !slices.Contains(filter.Statuses, iss.Status) {
			continue
		}
		if slices.Contains(filter.ExcludeStatus, iss.Status) {
			continue
		}
		if filter.ClosedAfter != nil && (iss.ClosedAt == nil || !iss.ClosedAt.After(*filter.ClosedAfter)) {
			continue
		}
		if filter.CreatedAfter != nil && !iss.CreatedAt.After(*filter.CreatedAfter) {
			continue
		}
		if !metadataMatches(iss, filter.MetadataFields) {
			continue
		}
		out = append(out, iss)
	}
	return out
}

// metadataMatches is IssueFilter.MetadataFields: every key equal, AND semantics.
func metadataMatches(iss *beads.Issue, want map[string]string) bool {
	if len(want) == 0 {
		return true
	}
	md := decodeMetadata(iss.Metadata)
	for k, v := range want {
		if got, ok := md[k]; !ok || got != v {
			return false
		}
	}
	return true
}

// searchByMetadata models the library's metadata predicates over the fixtures:
// HasMetadataKey is a presence test, MetadataFields an equality test, and
// ExcludeTypes drops whole issue types before either runs.
func (f *fakeStore) searchByMetadata(filter beads.IssueFilter) ([]*beads.Issue, error) {
	key := filter.HasMetadataKey
	exact := key == ""
	if exact {
		if len(filter.MetadataFields) != 1 {
			return nil, errors.New("test fake requires an issue type, a metadata key, or exactly one metadata field")
		}
		for k := range filter.MetadataFields {
			key = k
		}
	}
	if err, bad := f.failMeta[key]; bad {
		return nil, err
	}
	excluded := map[string]bool{}
	for _, t := range filter.ExcludeTypes {
		excluded[string(t)] = true
	}
	// Without the exclusion a type-agnostic ANCHOR query re-gathers every epic
	// that happens to carry the key, and the board shows it twice. Pinning it
	// here is what makes the dedup in BuildBoard a safety net rather than the
	// only thing standing between the operator and a duplicated row.
	//
	// The rule is scoped to the anchor gathers, which are the status=open ones.
	// A JOIN query (statuses=[open,in_progress]) and the closed-sitting pass are
	// not gathering anchors at all — they read conversations and molecule steps,
	// which are ordinary tasks — so demanding the exclusion there would be
	// asserting a rule that does not apply.
	if filter.Status != nil && *filter.Status == beads.StatusOpen {
		for _, want := range []string{"epic", "decision", "convoy"} {
			if !excluded[want] {
				return nil, errors.New("a metadata-keyed gather must exclude the typed anchor kinds; missing " + want)
			}
		}
	}

	var out []*beads.Issue
	for _, kind := range slices.Sorted(maps.Keys(f.issues)) { // deterministic order
		if excluded[kind] {
			continue
		}
		for _, iss := range f.issues[kind] {
			meta := decodeMetadata(iss.Metadata)
			got, present := meta[key]
			if !present {
				continue
			}
			if exact && got != filter.MetadataFields[key] {
				continue
			}
			out = append(out, iss)
		}
	}
	return f.matching(out, filter), nil
}

// GetDependencyRecordsForIssues is the OUTBOUND batched read: for each queried
// id, the raw `tracks`/`blocks` edges it owns, drawn from the same depsDown
// fixtures the per-anchor read used. A raw edge carries only the two ids and the
// type — the far-end issue is hydrated separately, which searchByIDs answers
// from the embedded fixtures.
func (f *fakeStore) GetDependencyRecordsForIssues(_ context.Context, issueIDs []string) (map[string][]*beads.Dependency, error) {
	f.depyN++
	if err := f.batchFailure(issueIDs); err != nil {
		return nil, err
	}
	out := map[string][]*beads.Dependency{}
	for _, id := range issueIDs {
		for _, d := range f.depsDown[id] {
			out[id] = append(out[id], &beads.Dependency{
				IssueID:     id,
				DependsOnID: d.Issue.ID,
				Type:        d.DependencyType,
			})
		}
	}
	return out, nil
}

// GetDependentRecordsForIssues is the INBOUND batched read: for each queried
// target, the raw edges pointing AT it (its dependents), from the depsUp
// fixtures. The dependent is the edge's SOURCE, so it lands in IssueID.
func (f *fakeStore) GetDependentRecordsForIssues(_ context.Context, targetIDs []string) (map[string][]*beads.Dependency, error) {
	f.depnN++
	if err := f.batchFailure(targetIDs); err != nil {
		return nil, err
	}
	out := map[string][]*beads.Dependency{}
	for _, target := range targetIDs {
		for _, d := range f.depsUp[target] {
			out[target] = append(out[target], &beads.Dependency{
				IssueID:     d.Issue.ID,
				DependsOnID: target,
				Type:        d.DependencyType,
			})
		}
	}
	return out, nil
}

// batchFailure models an ATOMIC batched read that fails when any queried id is
// marked in failDeps. The real read is one query over the whole set, so a
// single unreadable id fails the batch rather than that id alone — the gather's
// error handling degrades per batch, not per anchor.
func (f *fakeStore) batchFailure(ids []string) error {
	for _, id := range ids {
		if err, bad := f.failDeps[id]; bad {
			return err
		}
	}
	return nil
}

// GetConfig answers a config-table read the way the library does: "" with no
// error for a key that is not set.
func (f *fakeStore) GetConfig(_ context.Context, key string) (string, error) {
	if f.failKV != nil {
		return "", f.failKV
	}
	return f.kv[key], nil
}

func (f *fakeStore) Close() error { f.closed = true; return nil }

func issue(id, title, kind string, prio int, updated time.Time, meta string) *beads.Issue {
	i := &beads.Issue{
		ID:        id,
		Title:     title,
		Status:    beads.StatusOpen,
		IssueType: beads.IssueType(kind),
		Priority:  prio,
		UpdatedAt: updated,
	}
	if meta != "" {
		i.Metadata = json.RawMessage(meta)
	}
	return i
}

// closedIssue is issue() for the done pass: same fixture, status closed, with
// the close instant the DONE band reads. Both are set, because the library sets
// both and a fixture carrying only one would exercise a state the store cannot
// produce.
func closedIssue(id, title, kind string, prio int, updated, closed time.Time, meta string) *beads.Issue {
	i := issue(id, title, kind, prio, updated, meta)
	i.Status = beads.StatusClosed
	c := closed
	i.ClosedAt = &c
	return i
}

func child(id, status string, updated time.Time, meta string) *beads.IssueWithDependencyMetadata {
	return &beads.IssueWithDependencyMetadata{
		Issue: beads.Issue{
			ID:        id,
			Status:    beads.Status(status),
			Assignee:  "polecat-" + id,
			UpdatedAt: updated,
			Metadata:  json.RawMessage(meta),
		},
	}
}

func withDepType(c *beads.IssueWithDependencyMetadata, t string) *beads.IssueWithDependencyMetadata {
	c.DependencyType = beads.DependencyType(t)
	return c
}

func withIssueType(c *beads.IssueWithDependencyMetadata, t string) *beads.IssueWithDependencyMetadata {
	c.IssueType = beads.IssueType(t)
	return c
}

// withLabels stamps labels on an issue fixture. A convoy's ownership is read
// from its own "owned" label — the same label gascity keys the `gc convoy
// list` owned flag on.
func withLabels(iss *beads.Issue, labels ...string) *beads.Issue {
	iss.Labels = labels
	return iss
}

// cityWithRigs lays out <tmp>/rigs/<name>/.beads/config.yaml for each rig so the
// on-disk discovery path is exercised for real.
func cityWithRigs(t *testing.T, rigs map[string]string) string {
	t.Helper()
	root := t.TempDir()
	for name, prefix := range rigs {
		dir := filepath.Join(root, "rigs", name, ".beads")
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatalf("mkdir %s: %v", dir, err)
		}
		body := "dolt.mode: server\n"
		if prefix != "" {
			body += "issue_prefix: " + prefix + "\n"
		}
		if err := os.WriteFile(filepath.Join(dir, "config.yaml"), []byte(body), 0o644); err != nil {
			t.Fatalf("write config: %v", err)
		}
	}
	return root
}

var testNow = time.Date(2026, 8, 1, 12, 0, 0, 0, time.UTC)

// populatedStore is one rig's worth of fixtures: an epic with two children (one
// closed), a decision, a real convoy with a tracked member, the two machine
// convoys that must be filtered out, and the ordinary task/bug beads the
// metadata-keyed kinds are gathered from.
//
// The epic and the decision each carry one of the metadata markers on purpose.
// They are the dedup control: both are already anchors by TYPE, so a gather
// that forgot to exclude the typed kinds would admit each of them a second time
// and the board would carry a duplicate row.
func populatedStore() *fakeStore {
	return &fakeStore{
		issues: map[string][]*beads.Issue{
			"epic": {issue("tk-epic", "Big epic", "epic", 2, testNow.Add(-30*24*time.Hour), `{"gc.takeaway":"needs a decision"}`)},
			"decision": {issue("tk-dec", "Pick a path", "decision", 1, testNow.Add(-2*24*time.Hour),
				`{"gc.routed_to":"human","retries":3,"blocked":true}`)},
			"convoy": {
				withLabels(issue("tk-cv", "real convoy", "convoy", 2, testNow.Add(-time.Hour), ""), "owned"),
				issue("tk-sling", "sling-tk-x", "convoy", 2, testNow, ""),
				issue("tk-inputcv", "input convoy for tk-sy3vj", "convoy", 2, testNow, ""),
			},
			// The metadata-keyed kinds ride on ORDINARY beads — that is the
			// whole of tk-2v08m — so these fixtures are plain tasks and bugs,
			// the two types no anchor query has ever asked for.
			"task": {
				issue("tk-human", "Disposition: one PR needs the operator", "task", 1, testNow.Add(-4*24*time.Hour),
					`{"gc.routed_to":"human"}`),
				issue("tk-both", "Routed to the operator and parked", "task", 2, testNow.Add(-time.Hour),
					`{"gc.routed_to":"human","gc.takeaway":"stood down — nothing further"}`),
				issue("tk-quiet", "Carries no marker at all", "task", 2, testNow, `{"branch":"polecat/tk-quiet"}`),
			},
			"bug": {
				issue("tk-parked", "helm returns the raw script path", "bug", 2, testNow.Add(-2*24*time.Hour),
					`{"gc.takeaway":"routed — fix slung; nothing further needed here","gc.takeaway_by":"converse"}`),
				// gc.routed_to is on every pool-routed step bead in the city.
				// Only the value `human` means the operator owns it, so a
				// presence test on this key would flood the board.
				issue("tk-pooled", "Routed to a pool, not a human", "bug", 1, testNow,
					`{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}`),
			},
		},
		depsUp: map[string][]*beads.IssueWithDependencyMetadata{
			"tk-epic": {
				withDepType(child("tk-a", "open", testNow.Add(-3*24*time.Hour), `{"gc.routed_to":"human"}`), "parent-child"),
				withDepType(child("tk-b", "closed", testNow.Add(-9*24*time.Hour), ""), "parent-child"),
				// A non-parent-child edge into the same epic must not be counted.
				withDepType(child("tk-ref", "open", testNow, ""), "related"),
			},
			// A parked subject that DECOMPOSED. The canonical converse shape
			// files the work a sitting routes as a child of the subject, so
			// this is where that work lives — and the only relation that can
			// see it, since beads refuses a parent→descendant `blocks` edge
			// (tk-a9k0l, tk-2cyxo). The `tracks` edge is a conversation
			// pointing at the same bead: not a child.
			"tk-parked": {
				withDepType(child("tk-p1", "open", testNow, ""), "parent-child"),
				withDepType(child("tk-p2", "closed", testNow.Add(-24*time.Hour), ""), "parent-child"),
				withDepType(child("tk-conv", "open", testNow, ""), "tracks"),
				// The closed event `bd set-state` files under the bead whose
				// state it changed, on a parent-child edge: an audit record,
				// not a child.
				withDepType(withIssueType(child("tk-p-state", "closed", testNow, ""), "event"), "parent-child"),
			},
		},
		depsDown: map[string][]*beads.IssueWithDependencyMetadata{
			"tk-cv": {
				withDepType(child("tk-m1", "in_progress", testNow, ""), "tracks"),
				// A convoy's own blocks-edge is a WAIT, not membership: it stays
				// out of Children and is gathered into WaitingOn so the family
				// grouping can climb a blocked convoy to what it blocks.
				withDepType(child("tk-m2", "open", testNow, ""), "blocks"),
			},
			// The `--waiting-on` edges. Every kind that spends them gets one
			// here, so a gather that stops reading them for a kind is visible
			// as a missing edge rather than as a silently vacuous derivation:
			// board.ruled reads waiting_on_open, and with no edges gathered at
			// all that clause is trivially satisfied and every answered row
			// stands down whether or not its work landed.
			"tk-dec": {
				withDepType(child("tk-w1", "closed", testNow, ""), "blocks"),
				// Not a wait — only `blocks` counts.
				withDepType(child("tk-w2", "open", testNow, ""), "related"),
			},
			"tk-human":  {withDepType(child("tk-w3", "open", testNow, ""), "blocks")},
			"tk-parked": {withDepType(child("tk-w4", "closed", testNow, ""), "blocks")},
			// An epic gathers its blocks edges, so a blocked epic can join the
			// dependency family it hangs off.
			"tk-epic": {withDepType(child("tk-w5", "closed", testNow, ""), "blocks")},
		},
	}
}

// fakeGC stands in for the `gc` CLI. Every test uses one: without it a gather
// would shell out to the real binary against the developer's live city, which
// is both slow (each call carries a 30s bound) and a test that reads whatever
// happens to be running.
type fakeGC struct {
	sessions map[string]string
	err      error // when set, every call fails with it
	// sessionsN is every external command a gather runs — session liveness is
	// the only `gc` subprocess left, convoy ownership and membership being
	// in-process store reads — which is what lets a test assert the cost of the
	// board rather than only its contents.
	sessionsN int
}

// externalCalls is every subprocess this gather made. The gather's whole
// external surface is this interface: the rest is the bead store, opened
// in-process.
func (f *fakeGC) externalCalls() int { return f.sessionsN }

func (f *fakeGC) Sessions(context.Context) (map[string]string, error) {
	f.sessionsN++
	if f.err != nil {
		return nil, f.err
	}
	return f.sessions, nil
}

func newBeadsTestSource(t *testing.T, root string, stores map[string]*fakeStore, opts ...BeadsOption) *BeadsSource {
	t.Helper()
	base := []BeadsOption{
		WithCityPath(root),
		withGCClient(&fakeGC{}),
		// A pinned clock, so a fixture's close stamp sits a fixed distance
		// inside or outside the closed-row windows instead of drifting with
		// the wall clock. A caller that needs another one appends its own.
		withClock(func() time.Time { return testNow }),
		withStoreOpener(func(_ context.Context, beadsDir string) (beadStore, error) {
			rig := filepath.Base(filepath.Dir(beadsDir))
			st, ok := stores[rig]
			if !ok {
				return nil, errors.New("no fixture store for rig " + rig)
			}
			return st, nil
		}),
	}
	return NewBeadsSource(append(base, opts...)...)
}

func findAnchor(res *Result, id string) (int, bool) {
	for i, a := range res.Anchors {
		if a.ID == id {
			return i, true
		}
	}
	return 0, false
}

// TestBeadsGatherCarriesUpdatedAtAndMetadata is the point of the whole bead: the
// two facts the HTTP source cannot see must arrive on the anchors.
func TestBeadsGatherCarriesUpdatedAtAndMetadata(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": populatedStore()})

	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	if res.Partial {
		t.Errorf("unexpected partial: %v", res.PartialErrors)
	}

	i, ok := findAnchor(res, "tk-epic")
	if !ok {
		t.Fatal("epic anchor missing")
	}
	epic := res.Anchors[i]
	if epic.UpdatedAt.IsZero() {
		t.Error("epic must carry updated_at — this is the capability the bead ships")
	}
	if got := epic.Metadata["gc.takeaway"]; got != "needs a decision" {
		t.Errorf("epic metadata not carried: %v", epic.Metadata)
	}
	if epic.Rig != "gc-toolkit" || epic.Prefix != "tk" {
		t.Errorf("rig identity: rig=%s prefix=%s", epic.Rig, epic.Prefix)
	}
	if epic.Priority == nil || *epic.Priority != 2 {
		t.Errorf("priority not carried: %v", epic.Priority)
	}

	// Children roll up all statuses, carry their own facts, and admit only the
	// parent-child edges.
	if len(epic.Children) != 2 {
		t.Fatalf("epic children: want 2 (parent-child only), got %d: %+v", len(epic.Children), epic.Children)
	}
	var closed int
	for _, c := range epic.Children {
		if c.Status == "closed" {
			closed++
		}
		if c.UpdatedAt.IsZero() {
			t.Errorf("child %s must carry updated_at", c.ID)
		}
		if c.Assignee == "" {
			t.Errorf("child %s must carry assignee (the HTTP source could not)", c.ID)
		}
	}
	if closed != 1 {
		t.Errorf("closed children must be counted: got %d, want 1", closed)
	}
	if got := epic.Children[0].Metadata["gc.routed_to"]; got != "human" {
		t.Errorf("child metadata not carried: %v", epic.Children[0].Metadata)
	}
}

// TestBeadsGatherFiltersAndKinds covers the anchor set: machine convoys out,
// tracked members in, decisions carried without a roll-up.
func TestBeadsGatherFiltersAndKinds(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": populatedStore()})

	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	// epic + decision + real convoy, then human (tk-human, tk-both) and parked
	// (tk-both, tk-parked). tk-both is gathered under both metadata kinds; that
	// is one bead, two anchors, and BuildBoard's dedup is what folds it back to
	// one row — see TestMetadataKindDedup in the board package.
	if len(res.Anchors) != 7 {
		ids := []string{}
		for _, a := range res.Anchors {
			ids = append(ids, a.ID+"/"+a.Kind)
		}
		t.Fatalf("want 7 anchors, got %d: %v", len(res.Anchors), ids)
	}
	for _, banned := range []string{"tk-sling", "tk-inputcv"} {
		if _, ok := findAnchor(res, banned); ok {
			t.Errorf("machine convoy %s must be filtered out", banned)
		}
	}

	// Convoy members come from the `tracks` edge, not `blocks`.
	i, ok := findAnchor(res, "tk-cv")
	if !ok {
		t.Fatal("convoy anchor missing")
	}
	cv := res.Anchors[i]
	if len(cv.Children) != 1 || cv.Children[0].ID != "tk-m1" {
		t.Errorf("convoy members come from tracks edges only: %+v", cv.Children)
	}

	// A decision needs no roll-up.
	i, ok = findAnchor(res, "tk-dec")
	if !ok {
		t.Fatal("decision anchor missing")
	}
	if len(res.Anchors[i].Children) != 0 {
		t.Errorf("decision should carry no children: %+v", res.Anchors[i].Children)
	}
	if got := res.Anchors[i].Metadata["gc.routed_to"]; got != "human" {
		t.Errorf("decision metadata not carried: %v", res.Anchors[i].Metadata)
	}
}

// TestBeadsGatherMetadataKinds is the point of tk-2v08m: a bead the operator
// owns is gathered because of what its METADATA says, not what its type is.
// Before this, `human` and `parked` beads were plain tasks and bugs and the
// board — keyed on epic/decision/convoy — excluded them by construction.
func TestBeadsGatherMetadataKinds(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": populatedStore()})

	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}

	kinds := map[string][]string{}
	for _, a := range res.Anchors {
		kinds[a.ID] = append(kinds[a.ID], a.Kind)
	}
	for _, c := range []struct {
		id   string
		want []string
		why  string
	}{
		{"tk-human", []string{"human"}, "gc.routed_to=human on an ordinary task is the whole bug"},
		{"tk-parked", []string{"parked"}, "gc.takeaway is a presence test — the value is free text"},
		{"tk-both", []string{"human", "parked"}, "both markers gather twice; dedup folds it, the gather does not"},
		{"tk-quiet", nil, "an unmarked task is not an anchor"},
		{"tk-pooled", nil, "gc.routed_to=<pool> is not the operator; only the value `human` is"},
		{"tk-epic", []string{"epic"}, "an epic carrying gc.takeaway stays an epic — ExcludeTypes, not luck"},
		{"tk-dec", []string{"decision"}, "a decision carrying gc.routed_to=human stays a decision"},
	} {
		got := kinds[c.id]
		if len(got) != len(c.want) {
			t.Errorf("%s: got kinds %v, want %v — %s", c.id, got, c.want, c.why)
			continue
		}
		for i := range c.want {
			if got[i] != c.want[i] {
				t.Errorf("%s: got kinds %v, want %v — %s", c.id, got, c.want, c.why)
				break
			}
		}
	}

	// The metadata kinds carry the same facts every anchor does — including a
	// child roll-up, read the same way an epic's is (tk-a9k0l). A bead with no
	// children still gathers none; the empty slice used to be hardcoded for
	// every one of them, which is a false statement of the relation rather than
	// a cheap approximation of it.
	i, ok := findAnchor(res, "tk-human")
	if !ok {
		t.Fatal("human anchor missing")
	}
	human := res.Anchors[i]
	if len(human.Children) != 0 {
		t.Errorf("a bead with no parent-child edges rolls up nothing: %+v", human.Children)
	}
	j, ok := findAnchor(res, "tk-parked")
	if !ok {
		t.Fatal("parked anchor missing")
	}
	parked := res.Anchors[j]
	if len(parked.Children) != 2 {
		t.Fatalf("a decomposed parked subject rolls up its children: %+v", parked.Children)
	}
	gotKids := []string{parked.Children[0].ID, parked.Children[1].ID}
	if gotKids[0] != "tk-p1" || gotKids[1] != "tk-p2" {
		t.Errorf("children: got %v, want [tk-p1 tk-p2] — the tracks edge is membership, and a bd audit event is a record, not a child", gotKids)
	}
	if parked.Children[0].Status != "open" || parked.Children[1].Status != "closed" {
		t.Errorf("children are read at ALL statuses so n_closed is real: %+v", parked.Children)
	}
	if human.Source != "human" {
		t.Errorf("Source drives the derivation branch: got %q", human.Source)
	}
	if human.Rig != "gc-toolkit" || human.Prefix != "tk" {
		t.Errorf("rig identity: rig=%s prefix=%s", human.Rig, human.Prefix)
	}
	if human.UpdatedAt.IsZero() {
		t.Error("a human-routed bead must carry updated_at like any other anchor")
	}
	if human.Priority == nil || *human.Priority != 1 {
		t.Errorf("priority not carried: %v", human.Priority)
	}
	if got := human.Metadata["gc.routed_to"]; got != "human" {
		t.Errorf("the marker that selected the anchor must ride on it: %v", human.Metadata)
	}
}

// TestWaitingEdgesAreGatheredForEveryKindThatSpendsThem pins WHICH kinds pay
// the batched dependency read.
//
// Three spend the answer: `parked` through board.dispositionDue, and
// `decision` / `human` through board.ruled (tk-b3rga). The last two are why
// this is not a parked-only read any more — and the failure mode of getting it
// wrong is silent rather than loud. board.ruled asks "has every recorded wait
// landed?"; with no edges gathered, waiting_on_open is empty and the answer is
// vacuously yes, so an answered decision whose routed work is still open would
// stand down anyway. Nothing errors, no field goes missing, and the only
// visible symptom is a row that quietly stopped asking too early.
//
// `epic` and `convoy` pay it for a different consumer: the dependency-family
// grouping climbs a tile to the anchor it blocks, so a blocked epic or convoy
// must gather its `blocks` edges to join the family it hangs off. A convoy's
// come from the same outbound read that already
// fetched its `tracks` members — a blocker there is a wait, not membership.
func TestWaitingEdgesAreGatheredForEveryKindThatSpendsThem(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": populatedStore()})

	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	find := func(id, kind string) (int, bool) {
		for i, a := range res.Anchors {
			if a.ID == id && a.Kind == kind {
				return i, true
			}
		}
		return 0, false
	}

	for _, c := range []struct {
		id, kind string
		want     []string
		closed   []string
		why      string
	}{
		{"tk-dec", "decision", []string{"tk-w1"}, []string{"tk-w1"},
			"a decision spends its waits through the stand-down rule"},
		{"tk-human", "human", []string{"tk-w3"}, nil,
			"so does a human-routed bead — and this one is still outstanding"},
		{"tk-parked", "parked", []string{"tk-w4"}, []string{"tk-w4"},
			"the parked read tk-2plde added is unchanged"},
		{"tk-epic", "epic", []string{"tk-w5"}, []string{"tk-w5"},
			"an epic now gathers its blocks edges for the dependency-family grouping"},
		{"tk-cv", "convoy", []string{"tk-m2"}, nil,
			"a convoy's blocks edge is a wait it now gathers, separate from its tracks members"},
	} {
		idx, ok := find(c.id, c.kind)
		if !ok {
			t.Errorf("%s/%s: anchor missing", c.id, c.kind)
			continue
		}
		a := res.Anchors[idx]
		if len(a.WaitingOn) != len(c.want) {
			t.Errorf("%s/%s: waiting_on=%v, want %v — %s", c.id, c.kind, a.WaitingOn, c.want, c.why)
		} else {
			for i := range c.want {
				if a.WaitingOn[i] != c.want[i] {
					t.Errorf("%s/%s: waiting_on=%v, want %v — %s", c.id, c.kind, a.WaitingOn, c.want, c.why)
					break
				}
			}
		}
		if len(a.WaitingOnClosed) != len(c.closed) {
			t.Errorf("%s/%s: waiting_on_closed=%v, want %v", c.id, c.kind, a.WaitingOnClosed, c.closed)
		}
	}
}

// TestReviewReworkChildrenAreAdmittedAsTiles pins the in-flight review/rework
// selector: a not-closed bead carrying metadata.anchor_bead
// with task_kind review or rework earns a tile so the operator sees the review
// or rework in flight as a member of its merge anchor's family. Open OR
// in_progress — a review is slung open, a rework is claimed — but never closed
// (its anchor carries the DONE row), and never without an anchor to join.
func TestReviewReworkChildrenAreAdmittedAsTiles(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	rev := issue("tk-rev", "Review branch polecat/tk-anc -> main", "task", 2, testNow,
		`{"task_kind":"review","anchor_bead":"tk-anc","check_name":"codex"}`)
	rwk := issue("tk-rwk", "Rework branch polecat/tk-anc", "task", 2, testNow,
		`{"task_kind":"rework","anchor_bead":"tk-anc"}`)
	rwk.Status = beads.StatusInProgress // a claimed rework runs in_progress
	orphan := issue("tk-orphan", "A review bead naming no anchor", "task", 2, testNow,
		`{"task_kind":"review"}`)
	done := issue("tk-revdone", "A review round that closed", "task", 2, testNow,
		`{"task_kind":"review","anchor_bead":"tk-anc"}`)
	done.Status = beads.StatusClosed
	closedAt := testNow.Add(-time.Hour)
	done.ClosedAt = &closedAt

	st := &fakeStore{issues: map[string][]*beads.Issue{"task": {rev, rwk, orphan, done}}}
	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": st})
	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	kindOf := func(id string) (string, bool) {
		for _, a := range res.Anchors {
			if a.ID == id {
				return a.Kind, true
			}
		}
		return "", false
	}
	if k, ok := kindOf("tk-rev"); !ok || k != "review" {
		t.Errorf("open review child: kind=%q ok=%v, want a review tile", k, ok)
	}
	if k, ok := kindOf("tk-rwk"); !ok || k != "rework" {
		t.Errorf("in_progress rework child: kind=%q ok=%v, want a rework tile", k, ok)
	}
	if _, ok := kindOf("tk-orphan"); ok {
		t.Error("a review bead with no anchor_bead cannot join a family and must be dropped")
	}
	if _, ok := kindOf("tk-revdone"); ok {
		t.Error("a closed review round is not gathered on the live pass — its anchor carries the DONE row")
	}
}

// TestReworkChildBehindASharedGateGathersTheGate is the shared-gate case read
// from the store, where board.TestGateFoldsOntoEachBeadItBlocks hands the
// derivation its waits by hand: an anchor and its rework child both wait on
// the anchor's bring-current gate. The gather reads the child's own `blocks`
// waits as it reads the anchor's, so the board lists the gate among what each
// row waits on, and the child's row asks the gate's question.
func TestReworkChildBehindASharedGateGathersTheGate(t *testing.T) {
	const ask = "Bring the branch current over the conflict?"
	waitsOnGate := func() *beads.IssueWithDependencyMetadata {
		return withDepType(child("tk-gate", "open", testNow, ""), "blocks")
	}
	st := &fakeStore{
		issues: map[string][]*beads.Issue{
			"task": {
				issue("tk-anc", "the PR", "task", 2, testNow, `{"merge_result":"pull_request","pr_number":"7"}`),
				issue("tk-rwk", "Rework branch polecat/tk-anc", "task", 2, testNow, `{"task_kind":"rework","anchor_bead":"tk-anc"}`),
			},
			"gate": {gateBead("tk-gate", ask, "human", "bring-current", time.Time{}, "")},
		},
		depsDown: map[string][]*beads.IssueWithDependencyMetadata{
			"tk-anc": {waitsOnGate(), withDepType(child("tk-rwk", "open", testNow, ""), "blocks")},
			"tk-rwk": {waitsOnGate()},
		},
		depsUp: map[string][]*beads.IssueWithDependencyMetadata{
			"tk-gate": {
				withDepType(child("tk-anc", "open", testNow, ""), "blocks"),
				withDepType(child("tk-rwk", "open", testNow, ""), "blocks"),
			},
		},
	}
	src := newBeadsTestSource(t, cityWithRigs(t, map[string]string{"gc-toolkit": "tk"}),
		map[string]*fakeStore{"gc-toolkit": st})
	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	if res.Partial {
		t.Fatalf("unexpected partial: %v", res.PartialErrors)
	}
	rwk, ok := anchorsOfKind(res, "rework")["tk-rwk"]
	if !ok {
		t.Fatal("the rework child is not gathered as a rework row")
	}
	if !slices.Equal(rwk.WaitingOn, []string{"tk-gate"}) || len(rwk.Blockers) != 1 ||
		rwk.Blockers[0].ID != "tk-gate" || rwk.Blockers[0].AwaitType != "human" || rwk.WaitingUnknown {
		t.Errorf("the gather reads the rework child's own blocks waits: waiting_on=%v blockers=%+v unknown=%v",
			rwk.WaitingOn, rwk.Blockers, rwk.WaitingUnknown)
	}

	b := board.BuildBoard(res.Anchors, testNow, res.Partial, res.PartialErrors, res.Facts)
	row := func(id string) (board.Tile, bool) {
		i := slices.IndexFunc(b.Tiles, func(tl board.Tile) bool { return tl.ID == id })
		if i < 0 {
			return board.Tile{}, false
		}
		return b.Tiles[i], true
	}
	for _, id := range []string{"tk-anc", "tk-rwk"} {
		tl, ok := row(id)
		if !ok {
			t.Errorf("%s has no row", id)
			continue
		}
		if !slices.Contains(tl.WaitingOnOpen, "tk-gate") {
			t.Errorf("%s: the row lists the gate among what its bead waits on: waiting_on_open=%v", id, tl.WaitingOnOpen)
		}
	}
	if tl, ok := row("tk-rwk"); ok && (tl.Needs != ask || !tl.Held || !tl.Owed) {
		t.Errorf("the child's row is held and owed, asking the gate's question: needs=%q held=%v owed=%v", tl.Needs, tl.Held, tl.Owed)
	}
	if _, ok := row("tk-gate"); ok {
		t.Error("a gate whose beads have rows takes no row of its own")
	}
}

// withDesc stamps a description on an issue fixture — the one heavy TEXT column
// this source reads (crossRigRefs scans an open anchor's prose).
func withDesc(iss *beads.Issue, desc string) *beads.Issue {
	iss.Description = desc
	return iss
}

// TestClosedPassReadsLiteLivePassReadsFull pins the projection split. The live
// anchor pass reads full, so a bead's description reaches the board and
// crossRigRefs can weigh an open anchor by the other-rig ids in its prose. The
// closed/DONE pass reads lite and drops the heavy TEXT columns, because a SevDone
// row orders by recency and reads none of them. The fake honours Lite by blanking
// the HeavyDropList columns, so a dropped description on the closed anchor and a
// present one on the live anchor are the two reads.
func TestClosedPassReadsLiteLivePassReadsFull(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	store := &fakeStore{issues: map[string][]*beads.Issue{
		"epic": {
			withDesc(issue("tk-live", "live epic", "epic", 2, testNow.Add(-time.Hour), ""), "blocks ra-aa111 downstream"),
			withDesc(closedIssue("tk-done", "done epic", "epic", 2, testNow.Add(-2*24*time.Hour), testNow.Add(-24*time.Hour), ""), "closed once ra-bb222 landed"),
		},
	}}
	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": store})

	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}

	i, ok := findAnchor(res, "tk-live")
	if !ok {
		t.Fatal("live epic anchor missing")
	}
	if res.Anchors[i].Description == "" {
		t.Error("live anchor must carry its description: the live pass reads full so crossRigRefs can weigh the open anchor")
	}

	j, ok := findAnchor(res, "tk-done")
	if !ok {
		t.Fatal("closed epic anchor missing")
	}
	if got := res.Anchors[j].Description; got != "" {
		t.Errorf("closed anchor description must be dropped by the lite closed pass, got %q", got)
	}
}

// TestGatherQueryShapesHonourLite asserts the projection the gather ASKS for, per
// pass, over the recorded filters. The typed and metadata-keyed anchor queries
// read lite on the closed pass and full on the live pass; the edge hydration (an
// id-keyed read) always reads lite. The sitting and workflow-root queries read
// full and are excluded here by their distinct shape — they scope with Statuses
// (so Status is nil) or MetadataFields, never a bare Status plus IssueType or
// HasMetadataKey — and with no sittings the only id-keyed read is the hydration.
func TestGatherQueryShapesHonourLite(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	store := &fakeStore{
		issues: map[string][]*beads.Issue{
			"epic": {issue("tk-live", "live epic", "epic", 2, testNow, "")},
			// A closed merge anchor exercises the metadata-keyed closed pass.
			"task": {closedIssue("tk-done-merge", "landed", "task", 2, testNow.Add(-2*24*time.Hour), testNow.Add(-24*time.Hour), `{"merge_result":"merged"}`)},
		},
		depsUp: map[string][]*beads.IssueWithDependencyMetadata{
			// A child edge makes the gather hydrate a far end.
			"tk-live": {withDepType(child("tk-child", "open", testNow, ""), "parent-child")},
		},
	}
	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": store})

	if _, err := src.Gather(context.Background()); err != nil {
		t.Fatalf("Gather: %v", err)
	}

	var sawClosedTyped, sawLiveTyped, sawClosedMeta, sawHydrate bool
	for _, c := range store.calls {
		switch {
		case len(c.IDs) > 0: // edge hydration — the only id-keyed read with no sittings
			sawHydrate = true
			if !c.Lite {
				t.Errorf("edge hydration must read lite: %+v", c)
			}
		case c.Status == nil: // join shape (sittings, workflow roots) — not an anchor pass
			continue
		case c.IssueType != nil && *c.Status == beads.StatusClosed:
			sawClosedTyped = true
			if !c.Lite {
				t.Errorf("closed typed anchor query must read lite: type=%s", *c.IssueType)
			}
		case c.IssueType != nil && *c.Status == beads.StatusOpen:
			sawLiveTyped = true
			if c.Lite {
				t.Errorf("live typed anchor query must read full (crossRigRefs needs description): type=%s", *c.IssueType)
			}
		case c.HasMetadataKey != "" && *c.Status == beads.StatusClosed:
			sawClosedMeta = true
			if !c.Lite {
				t.Errorf("closed metadata anchor query must read lite: key=%s", c.HasMetadataKey)
			}
		case c.HasMetadataKey != "" && *c.Status == beads.StatusOpen:
			if c.Lite {
				t.Errorf("live metadata anchor query must read full: key=%s", c.HasMetadataKey)
			}
		}
	}
	if !sawClosedTyped || !sawLiveTyped {
		t.Errorf("expected both a closed and a live typed anchor query (closed=%v live=%v)", sawClosedTyped, sawLiveTyped)
	}
	if !sawClosedMeta {
		t.Error("expected a closed metadata-keyed anchor query (HasMetadataKey)")
	}
	if !sawHydrate {
		t.Error("expected an edge-hydration id-keyed query")
	}
}

// TestWaitingEdgeFailureIsUnknownNotEmpty is the fail-closed half of the read
// above: WHICH kinds pay the `blocks` read is pinned there, what a FAILED read
// reports is pinned here.
//
// The outbound edge read is ONE batched query for the whole rig+status, so it
// fails as a whole — a Dolt timeout or schema skew takes every blocks-spending
// anchor with it. The rows are still gathered, because dropping them would hide
// work, so the only trace of the failure is what they report about their edges.
// Report an empty set and a row is indistinguishable from one that genuinely has
// no waits, which is precisely the state board.ruled reads as "every recorded
// wait has landed" and stands the row down. So a failed read reports
// UNKNOWN, not empty. The inbound (parent-child) read is a SEPARATE batch and is
// unaffected: a failed wait read does not also cost an anchor its child roll-up.
func TestWaitingEdgeFailureIsUnknownNotEmpty(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	st := populatedStore()
	// The outbound batch carries every blocks-spending anchor, so marking one id
	// unreadable fails it for all of them — the atomic shape of the real read.
	st.failDeps = map[string]error{"tk-dec": errors.New("dolt timeout")}
	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": st})

	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	if !res.Partial {
		t.Error("a failed edge read must set partial")
	}
	// Every kind that spends the `blocks` read shares the one batch, so all of
	// them report UNKNOWN — never an empty set board.ruled would read as "all
	// waits landed" and stand the row down. The epic and the convoy read their
	// waits for the family grouping, and the same failed batch reaches them.
	for _, id := range []string{"tk-dec", "tk-human", "tk-parked", "tk-epic", "tk-cv"} {
		j, ok := findAnchor(res, id)
		if !ok {
			t.Fatalf("%s: an anchor whose edge read fails must still appear", id)
		}
		a := res.Anchors[j]
		if !a.WaitingUnknown {
			t.Errorf("%s: a failed edge read must report UNKNOWN, not an empty wait set — "+
				"board.ruled cannot tell the two apart without it, and stands the row down", id)
		}
		if len(a.WaitingOn) != 0 || len(a.WaitingOnClosed) != 0 {
			t.Errorf("%s: a failed read invents no edges: %v / %v", id, a.WaitingOn, a.WaitingOnClosed)
		}
	}
	// The inbound (parent-child) read is a separate batch: a failed WAIT read
	// must not cost an anchor its child roll-up. tk-parked decomposed into two
	// parent-child children, and they survive.
	if j, ok := findAnchor(res, "tk-parked"); ok {
		if len(res.Anchors[j].Children) != 2 {
			t.Errorf("tk-parked: the independent children read must survive a failed wait read: %+v",
				res.Anchors[j].Children)
		}
	}
}

// TestEdgeReadsAreBatchedNotPerAnchor is the acceptance criterion for the
// batched edge reads: the number of edge reads is fixed by the number of
// (rig × status-pass) gathers, not by how many anchors those gathers return, so
// two stores that differ ONLY in anchor count must make the SAME number of edge
// reads.
func TestEdgeReadsAreBatchedNotPerAnchor(t *testing.T) {
	build := func(n int) *fakeStore {
		st := &fakeStore{
			issues:   map[string][]*beads.Issue{},
			depsUp:   map[string][]*beads.IssueWithDependencyMetadata{},
			depsDown: map[string][]*beads.IssueWithDependencyMetadata{},
		}
		for i := 0; i < n; i++ {
			ep := fmt.Sprintf("tk-ep%d", i)
			dc := fmt.Sprintf("tk-dc%d", i)
			st.issues["epic"] = append(st.issues["epic"], issue(ep, "an epic", "epic", 2, testNow, ""))
			st.issues["decision"] = append(st.issues["decision"], issue(dc, "a decision", "decision", 2, testNow, ""))
			st.depsUp[ep] = []*beads.IssueWithDependencyMetadata{withDepType(child(ep+"-c", "open", testNow, ""), "parent-child")}
			st.depsDown[dc] = []*beads.IssueWithDependencyMetadata{withDepType(child(dc+"-w", "open", testNow, ""), "blocks")}
		}
		return st
	}
	gather := func(st *fakeStore) {
		root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
		src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": st})
		if _, err := src.Gather(context.Background()); err != nil {
			t.Fatalf("Gather: %v", err)
		}
	}

	small, large := build(3), build(60)
	gather(small)
	gather(large)

	if small.depnN != large.depnN || small.depyN != large.depyN {
		t.Errorf("edge reads scale with anchor count — the N+1 is back: "+
			"dependents %d vs %d, dependencies %d vs %d (3 vs 60 anchors per kind)",
			small.depnN, large.depnN, small.depyN, large.depyN)
	}
	// The fixed count is one batch per direction per gather pass, plus one more
	// outbound batch for the waits of the open children those anchors roll up.
	// The open pass gathers every anchor; the closed pass finds none here, so it
	// reads no edges at all — hence one inbound read and two outbound ones.
	if large.depnN != 1 || large.depyN != 2 {
		t.Errorf("expected one inbound read and two outbound ones, got dependents=%d dependencies=%d",
			large.depnN, large.depyN)
	}
}

// TestOpenChildrenCarryTheirWaits: an open child of a live anchor carries its
// own `blocks` waits, hydrated with the fields the board classifies it by, so
// the roll-up can tell a child waiting its turn from one nothing will start,
// and a gate the city resolves by itself from one a person must release. A
// closed child reads none, and a failed read degrades to no waits with a
// partial note rather than costing the anchor its row.
func TestOpenChildrenCarryTheirWaits(t *testing.T) {
	build := func() *fakeStore {
		gate := issue("tk-gate", "parked until the design is signed", "gate", 2, testNow, "")
		gate.AwaitType = "human"
		sibling := child("tk-ep.1", "open", testNow, `{"merge_result":"pull_request"}`)
		armed := child("tk-ep.2", "open", testNow, `{"gc.dispatch_when_ready":"gc-toolkit/gc-toolkit.polecat"}`)
		held := child("tk-ep.3", "open", testNow, "")
		done := child("tk-ep.4", "closed", testNow, "")
		return &fakeStore{
			issues: map[string][]*beads.Issue{
				"epic": {issue("tk-ep", "an epic", "epic", 2, testNow, "")},
				"gate": {gate},
			},
			depsUp: map[string][]*beads.IssueWithDependencyMetadata{"tk-ep": {
				withDepType(sibling, "parent-child"), withDepType(armed, "parent-child"),
				withDepType(held, "parent-child"), withDepType(done, "parent-child"),
			}},
			depsDown: map[string][]*beads.IssueWithDependencyMetadata{
				"tk-ep.2": {withDepType(child("tk-ep.1", "open", testNow, `{"merge_result":"pull_request"}`), "blocks")},
				"tk-ep.3": {withDepType(&beads.IssueWithDependencyMetadata{Issue: *gate}, "blocks")},
				"tk-ep.4": {withDepType(child("tk-ep.1", "open", testNow, ""), "blocks")},
			},
		}
	}

	res := gatherOneStore(t, build())
	j, ok := findAnchor(res, "tk-ep")
	if !ok {
		t.Fatal("the epic is missing")
	}
	waits := map[string][]board.Blocker{}
	for _, c := range res.Anchors[j].Children {
		waits[c.ID] = c.Blockers
	}
	if got := waits["tk-ep.2"]; len(got) != 1 || got[0].ID != "tk-ep.1" || got[0].Status != "open" {
		t.Errorf("the armed child waits on its open sibling: %+v", got)
	}
	if got := waits["tk-ep.3"]; len(got) != 1 || got[0].IssueType != "gate" || got[0].AwaitType != "human" ||
		got[0].Title != "parked until the design is signed" {
		t.Errorf("the held child's gate is hydrated with its type, what it awaits, and its title: %+v", got)
	}
	if len(waits["tk-ep.1"]) != 0 || len(waits["tk-ep.4"]) != 0 {
		t.Errorf("a child with no wait, and a closed child, carry none: %+v / %+v", waits["tk-ep.1"], waits["tk-ep.4"])
	}

	failing := build()
	failing.failDeps = map[string]error{"tk-ep.2": errors.New("dolt timeout")}
	res = gatherOneStore(t, failing)
	j, ok = findAnchor(res, "tk-ep")
	if !ok {
		t.Fatal("a failed child-waits read must not cost the epic its row")
	}
	if len(res.Anchors[j].Children) != 4 {
		t.Errorf("the children survive a failed waits read: %+v", res.Anchors[j].Children)
	}
	for _, c := range res.Anchors[j].Children {
		if len(c.Blockers) != 0 {
			t.Errorf("%s: a failed read invents no waits: %+v", c.ID, c.Blockers)
		}
	}
	if !res.Partial {
		t.Error("a failed child-waits read is noted partial")
	}
}

// TestBeadsGatherMetadataKindsDegradeIndependently: the metadata gathers are
// two more independently-failing kinds, not a second chance to lose the board.
func TestBeadsGatherMetadataKindsDegradeIndependently(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	st := populatedStore()
	st.failMeta = map[string]error{"gc.takeaway": errors.New("metadata query failed")}
	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": st})

	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("one failing metadata kind must not hard-fail the gather: %v", err)
	}
	if !res.Partial {
		t.Error("a failing metadata kind must set partial")
	}
	var named bool
	for _, e := range res.PartialErrors {
		if strings.HasPrefix(e, "parked-takeaways@gc-toolkit") {
			named = true
		}
	}
	if !named {
		t.Errorf("the partial error must name the kind an operator would recognise: %v", res.PartialErrors)
	}
	if _, ok := findAnchor(res, "tk-parked"); ok {
		t.Error("the failed kind must be absent, not approximated")
	}
	if _, ok := findAnchor(res, "tk-human"); !ok {
		t.Error("the other metadata kind must still gather")
	}
	if _, ok := findAnchor(res, "tk-epic"); !ok {
		t.Error("the typed kinds must still gather")
	}
}

// TestBeadsGatherDegradesPerRig mirrors SupervisorSource's contract: one rig
// failing must not lose the others, and it must be recorded as partial.
func TestBeadsGatherDegradesPerRig(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk", "rig-a": "ra"})
	broken := &fakeStore{
		failType: map[string]error{
			"epic":     errors.New("dolt timeout"),
			"decision": errors.New("dolt timeout"),
			"convoy":   errors.New("dolt timeout"),
		},
		failMeta: map[string]error{
			"gc.routed_to": errors.New("dolt timeout"),
			"gc.takeaway":  errors.New("dolt timeout"),
		},
	}
	src := newBeadsTestSource(t, root, map[string]*fakeStore{
		"gc-toolkit": populatedStore(),
		"rig-a":      broken,
	})

	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("one broken rig must not hard-fail the gather: %v", err)
	}
	if !res.Partial {
		t.Error("a failing rig must set partial")
	}
	if len(res.PartialErrors) == 0 {
		t.Error("a failing rig must record partial errors")
	}
	if _, ok := findAnchor(res, "tk-epic"); !ok {
		t.Error("the healthy rig's anchors must survive")
	}
}

// TestBeadsGatherDegradesPerAnchorKind confirms the kinds fail independently: a
// rig whose convoys error still contributes its epics.
func TestBeadsGatherDegradesPerAnchorKind(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	st := populatedStore()
	st.failType = map[string]error{"convoy": errors.New("convoy query failed")}
	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": st})

	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	if !res.Partial {
		t.Error("a failing anchor kind must set partial")
	}
	if _, ok := findAnchor(res, "tk-epic"); !ok {
		t.Error("epics must still gather when convoys fail")
	}
	if _, ok := findAnchor(res, "tk-cv"); ok {
		t.Error("the failed kind must be absent, not approximated")
	}
}

// TestBeadsGatherChildFailureKeepsAnchor pins the child-level degradation: an
// anchor whose roll-up fails is still shown, with no children, rather than
// dropped from the board.
func TestBeadsGatherChildFailureKeepsAnchor(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	st := populatedStore()
	st.failDeps = map[string]error{"tk-epic": errors.New("dep query failed")}
	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": st})

	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	i, ok := findAnchor(res, "tk-epic")
	if !ok {
		t.Fatal("an anchor whose roll-up fails must still appear")
	}
	if len(res.Anchors[i].Children) != 0 {
		t.Errorf("failed roll-up must yield no children: %+v", res.Anchors[i].Children)
	}
	if !res.Partial {
		t.Error("a failed roll-up must set partial")
	}
}

// TestBeadsGatherErrorsOnTotalOutage: if no rig can be read at all, Gather must
// error so the server answers 502 rather than serving an empty board that reads
// as "nothing needs attention".
func TestBeadsGatherErrorsOnTotalOutage(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	src := NewBeadsSource(
		WithCityPath(root),
		withGCClient(&fakeGC{}),
		withStoreOpener(func(context.Context, string) (beadStore, error) {
			return nil, errors.New("dolt unreachable")
		}),
	)
	if _, err := src.Gather(context.Background()); err == nil {
		t.Error("expected an error when no rig store can be opened")
	}
}

// TestBeadsCheckAndRigDiscovery covers the startup probe and the on-disk
// enumeration, including a rig directory with no bead store.
func TestBeadsCheckAndRigDiscovery(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk", "rig-a": ""})
	if err := os.MkdirAll(filepath.Join(root, "rigs", "not-a-rig"), 0o755); err != nil {
		t.Fatal(err)
	}

	src := NewBeadsSource(WithCityPath(root))
	if err := src.Check(); err != nil {
		t.Fatalf("Check on a real city layout: %v", err)
	}
	rigs, err := src.rigs()
	if err != nil {
		t.Fatalf("rigs: %v", err)
	}
	if len(rigs) != 2 {
		t.Fatalf("want 2 rigs with bead stores, got %d: %+v", len(rigs), rigs)
	}
	// Sorted by name, so gc-toolkit precedes rig-a deterministically.
	if rigs[0].name != "gc-toolkit" || rigs[0].prefix != "tk" {
		t.Errorf("first rig: %+v", rigs[0])
	}
	if rigs[1].prefix != "" {
		t.Errorf("a config without issue_prefix yields an empty prefix, not a guess: %+v", rigs[1])
	}

	// No city path at all, and a city with no rigs, are both Check failures —
	// that is what makes the entrypoint fall back to the HTTP source.
	if err := NewBeadsSource(WithCityPath("")).Check(); err == nil {
		t.Error("empty city path must fail Check")
	}
	if err := NewBeadsSource(WithCityPath(t.TempDir())).Check(); err == nil {
		t.Error("a city with no rigs dir must fail Check")
	}
}

// TestDiscoverCityPath covers the resolution DiscoverCityPath performs before a
// BeadsSource opens anything: the explicit env overrides, then the gc fallback
// that lets the CLI read a city from a plain shell setting none of them.
func TestDiscoverCityPath(t *testing.T) {
	// Env wins over gc, in declared precedence order. A gc stub that would answer
	// a different path is installed throughout, so a case that leaked past the env
	// check would return "/from/gc" — a wrong, detectable value — rather than
	// silently reaching the developer's live gc.
	t.Setenv("GC_HELM_GC_BIN", writeGCStub(t, `{"city_path":"/from/gc"}`, 0))
	for _, tc := range []struct {
		name string
		set  map[string]string
		want string
	}{
		{"GC_HELM_CITY_PATH first", map[string]string{"GC_HELM_CITY_PATH": "/from/helm", "GC_CITY_PATH": "/from/city_path", "GC_CITY": "/from/city"}, "/from/helm"},
		{"GC_CITY_PATH next", map[string]string{"GC_HELM_CITY_PATH": "", "GC_CITY_PATH": "/from/city_path", "GC_CITY": "/from/city"}, "/from/city_path"},
		{"GC_CITY last", map[string]string{"GC_HELM_CITY_PATH": "", "GC_CITY_PATH": "", "GC_CITY": "/from/city"}, "/from/city"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			for k, v := range tc.set {
				t.Setenv(k, v)
			}
			if got := DiscoverCityPath(); got != tc.want {
				t.Errorf("DiscoverCityPath: got %q, want %q", got, tc.want)
			}
		})
	}

	// None set: DiscoverCityPath asks gc. The stub stands in for
	// `gc config show --json`, and it prefixes the JSON with a warning line so the
	// real subprocess AND decodeLooseJSON's chatter-skipping are both exercised.
	t.Run("gc fallback when no env is set", func(t *testing.T) {
		t.Setenv("GC_HELM_CITY_PATH", "")
		t.Setenv("GC_CITY_PATH", "")
		t.Setenv("GC_CITY", "")
		t.Setenv("GC_HELM_GC_BIN", writeGCStub(t, "warning: city.toml is deprecated\n{\"city_path\":\"/discovered/by/gc\"}\n", 0))
		if got := DiscoverCityPath(); got != "/discovered/by/gc" {
			t.Errorf("DiscoverCityPath gc fallback: got %q, want %q", got, "/discovered/by/gc")
		}
	})

	// A gc that cannot answer — run outside any city, or absent — is the
	// fail-closed case: DiscoverCityPath yields "", the "no city" the callers
	// already handle, never a partial or a panic. The stub exits non-zero, which
	// run() surfaces as an error regardless of what it printed.
	t.Run("empty when gc fails", func(t *testing.T) {
		t.Setenv("GC_HELM_CITY_PATH", "")
		t.Setenv("GC_CITY_PATH", "")
		t.Setenv("GC_CITY", "")
		t.Setenv("GC_HELM_GC_BIN", writeGCStub(t, "gc: no city found\n", 1))
		if got := DiscoverCityPath(); got != "" {
			t.Errorf("DiscoverCityPath with a failing gc: got %q, want empty", got)
		}
	})
}

// writeGCStub writes an executable stand-in for the `gc` binary that prints
// stdout verbatim and exits with code. GC_HELM_GC_BIN points newGCExec at it, so
// DiscoverCityPath's fallback runs the stub instead of the real gc — the whole
// subprocess path, hermetically. The body is carried in a sibling file the stub
// cats, so any content (warnings, newlines) round-trips without shell quoting.
func writeGCStub(t *testing.T, stdout string, code int) string {
	t.Helper()
	dir := t.TempDir()
	payload := filepath.Join(dir, "payload")
	if err := os.WriteFile(payload, []byte(stdout), 0o644); err != nil {
		t.Fatalf("write gc stub payload: %v", err)
	}
	path := filepath.Join(dir, "gc")
	script := fmt.Sprintf("#!/bin/sh\ncat %q\nexit %d\n", payload, code)
	if err := os.WriteFile(path, []byte(script), 0o755); err != nil {
		t.Fatalf("write gc stub: %v", err)
	}
	return path
}

// TestSessionsGiveASharedKeyToItsLiveHolder: two listed sessions can carry one
// key, as when a new sitting takes the alias of one whose launch failed, and
// `gc session list` puts the newest session first. An ended state never
// replaces a live one, whichever session is listed first, and each session's
// own name and id keep its own state. A key only ended sessions hold, or only
// live ones, takes the later entry.
func TestSessionsGiveASharedKeyToItsLiveHolder(t *testing.T) {
	const alias = "gc-toolkit.converse-tk-conv"
	row := func(id, state string) string {
		return fmt.Sprintf(`{"id":%q,"alias":%q,"session_name":%q,"state":%q}`, id, alias, "s-"+id, state)
	}
	sessions := func(t *testing.T, rows ...string) map[string]string {
		t.Helper()
		t.Setenv("GC_HELM_GC_BIN", writeGCStub(t, `{"sessions":[`+strings.Join(rows, ",")+`]}`, 0))
		got, err := newGCExec("").Sessions(context.Background())
		if err != nil {
			t.Fatalf("Sessions: %v", err)
		}
		return got
	}
	for _, ended := range []string{"failed-create", "closed", "archived", ""} {
		name := ended
		if name == "" {
			name = "no state"
		}
		for _, order := range []string{"listed after", "listed first"} {
			t.Run(name+" predecessor "+order, func(t *testing.T) {
				rows := []string{row("hq-new", "active"), row("hq-old", ended)}
				if order == "listed first" {
					slices.Reverse(rows)
				}
				got := sessions(t, rows...)
				if got[alias] != "active" {
					t.Errorf("the shared alias reads %q, want its live holder's %q", got[alias], "active")
				}
				for k, want := range map[string]string{"hq-new": "active", "s-hq-new": "active", "hq-old": ended, "s-hq-old": ended} {
					if st, ok := got[k]; !ok || st != want {
						t.Errorf("%s reads %q (listed %v), want its own session's %q", k, st, ok, want)
					}
				}
			})
		}
	}
	t.Run("every holder ended", func(t *testing.T) {
		if got := sessions(t, row("hq-a", "archived"), row("hq-b", "failed-create")); got[alias] != "failed-create" {
			t.Errorf("a key only ended sessions hold reads %q, want the later entry's %q", got[alias], "failed-create")
		}
	})
	t.Run("every holder live", func(t *testing.T) {
		if got := sessions(t, row("hq-a", "active"), row("hq-b", "asleep")); got[alias] != "asleep" {
			t.Errorf("a key only live sessions hold reads %q, want the later entry's %q", got[alias], "asleep")
		}
	})
}

// TestBeadsSourceCloses verifies shutdown releases the cached handles.
func TestBeadsSourceCloses(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	st := populatedStore()
	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": st})
	if _, err := src.Gather(context.Background()); err != nil {
		t.Fatalf("Gather: %v", err)
	}
	if err := src.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}
	if !st.closed {
		t.Error("Close must release the opened store")
	}
	// Idempotent: a second Close must not panic or error.
	if err := src.Close(); err != nil {
		t.Errorf("second Close: %v", err)
	}
}

// TestBeadsStoreHandleIsReused pins the caching contract: a long-lived sidecar
// must not reconnect to Dolt on every gather.
func TestBeadsStoreHandleIsReused(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	var opens int
	st := populatedStore()
	src := NewBeadsSource(
		WithCityPath(root),
		withGCClient(&fakeGC{}),
		withStoreOpener(func(context.Context, string) (beadStore, error) {
			opens++
			return st, nil
		}),
	)
	for i := 0; i < 3; i++ {
		if _, err := src.Gather(context.Background()); err != nil {
			t.Fatalf("Gather %d: %v", i, err)
		}
	}
	if opens != 1 {
		t.Errorf("store opened %d times across 3 gathers, want 1", opens)
	}
}

// TestDecodeMetadata covers the coercion that keeps one oddly-typed bead from
// blanking the metadata of every anchor in the gather.
func TestDecodeMetadata(t *testing.T) {
	cases := []struct {
		name string
		raw  string
		want map[string]string
	}{
		{"absent", "", nil},
		{"empty object", `{}`, nil},
		{"strings", `{"branch":"polecat/tk-1"}`, map[string]string{"branch": "polecat/tk-1"}},
		{
			// `bd --set-metadata key=true` is type-inferred to a JSON boolean; a
			// strict decode would fail the whole object. A null value renders as
			// the empty string, but the KEY survives — which is what keeps
			// "absent" and "set but empty" distinguishable to a consumer.
			"non-string scalars are coerced, not fatal",
			`{"a":"x","b":true,"c":42,"d":null}`,
			map[string]string{"a": "x", "b": "true", "c": "42", "d": ""},
		},
		{"nested values keep their JSON form", `{"o":{"k":1}}`, map[string]string{"o": `{"k":1}`}},
		{"a non-object payload is ignored, not fatal", `["nope"]`, nil},
		{"malformed json is ignored, not fatal", `{"a":`, nil},
	}
	for _, c := range cases {
		got := decodeMetadata(json.RawMessage(c.raw))
		if len(got) != len(c.want) {
			t.Errorf("%s: got %v, want %v", c.name, got, c.want)
			continue
		}
		for k, v := range c.want {
			if got[k] != v {
				t.Errorf("%s: key %q = %q, want %q", c.name, k, got[k], v)
			}
		}
	}
}

// TestReadIssuePrefix covers both spellings the live configs carry, plus the
// best-effort fallbacks.
func TestReadIssuePrefix(t *testing.T) {
	dir := t.TempDir()
	write := func(name, body string) string {
		p := filepath.Join(dir, name)
		if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
		return p
	}
	cases := []struct{ name, body, want string }{
		{"underscore.yaml", "dolt.mode: server\nissue_prefix: tk\n", "tk"},
		{"hyphen.yaml", "issue-prefix: ra\n", "ra"},
		{"quoted.yaml", `issue_prefix: "gc"` + "\n", "gc"},
		{"absent.yaml", "dolt.mode: server\n", ""},
	}
	for _, c := range cases {
		if got := readIssuePrefix(write(c.name, c.body)); got != c.want {
			t.Errorf("%s: got %q, want %q", c.name, got, c.want)
		}
	}
	if got := readIssuePrefix(filepath.Join(dir, "missing.yaml")); got != "" {
		t.Errorf("missing config yields empty prefix, got %q", got)
	}
}

// --- the cross-anchor joins (tk-134d7) --------------------------------------

// joinStore is a store whose ordinary beads carry the markers the three joins
// read: an open VISIT naming its subject, a workflow ROOT pointing at its input
// convoy, and that root's STEP carrying the session name.
func joinStore() *fakeStore {
	st := populatedStore()
	st.issues["task"] = append(st.issues["task"],
		issue("tk-root1", "mol-polecat-work", "task", 2, testNow,
			`{"gc.kind":"workflow","gc.input_convoy_id":"tk-icv1","gc.session_name":"gc-toolkit__polecat-hq-live"}`),
		// A root with NO session of its own: the name has to come off its steps.
		issue("tk-root2", "mol-polecat-work", "task", 2, testNow,
			`{"gc.kind":"workflow","gc.input_convoy_id":"tk-icv2"}`),
		issue("tk-step2", "implement", "task", 2, testNow,
			`{"gc.root_bead_id":"tk-root2","gc.session_name":"gc-toolkit__polecat-hq-steps"}`),
		// A HUSK: an open root whose session is long gone. Joining on root
		// existence alone would flip it to "in flight".
		issue("tk-root3", "mol-polecat-work", "task", 2, testNow,
			`{"gc.kind":"workflow","gc.input_convoy_id":"tk-icv3","gc.session_name":"gc-toolkit__polecat-hq-dead"}`),
	)
	// Each input convoy tracks its one work bead. resolveInflight reads the
	// member from this `tracks` edge in-process, so the fixture carries the
	// edge a real convoy would rather than stubbing a `gc convoy status`.
	st.depsDown["tk-icv1"] = []*beads.IssueWithDependencyMetadata{withDepType(child("tk-work1", "in_progress", testNow, ""), "tracks")}
	st.depsDown["tk-icv2"] = []*beads.IssueWithDependencyMetadata{withDepType(child("tk-work2", "in_progress", testNow, ""), "tracks")}
	st.depsDown["tk-icv3"] = []*beads.IssueWithDependencyMetadata{withDepType(child("tk-work3", "in_progress", testNow, ""), "tracks")}
	return st
}

func liveGC() *fakeGC {
	return &fakeGC{
		sessions: map[string]string{
			"gc-toolkit__polecat-hq-live":  "active",
			"gc-toolkit__polecat-hq-steps": "active",
			"gc-toolkit__polecat-hq-dead":  "archived",
		},
	}
}

// TestGatherJoinsInflight is the whole point of the join gather: a LIVE
// workflow root resolves through its input convoy to the work bead it stands
// over.
func TestGatherJoinsInflight(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	gc := liveGC()
	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": joinStore()}, withGCClient(gc))

	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}

	if got := res.Facts.Inflight["tk-work1"]; len(got) != 1 || got[0] != "gc-toolkit__polecat-hq-live" {
		t.Errorf("root with its own session_name resolves: got %v", got)
	}
	if got := res.Facts.Inflight["tk-work2"]; len(got) != 1 || got[0] != "gc-toolkit__polecat-hq-steps" {
		t.Errorf("root without a session_name falls back to its steps: got %v", got)
	}
	if got, ok := res.Facts.Inflight["tk-work3"]; ok {
		t.Errorf("a husk (archived session) must not read as in flight: got %v", got)
	}
	// Member resolution and convoy ownership are in-process store reads now, so
	// the only subprocess a gather spends is the one session list, however many
	// roots are in flight.
	if calls := gc.externalCalls(); calls != 1 {
		t.Errorf("gather spent %d subprocesses, want 1 (session list; membership and ownership are in-process)", calls)
	}
	if res.Facts.OwnerState["gc-toolkit__polecat-hq-live"] != "active" {
		t.Errorf("session states carried: %v", res.Facts.OwnerState)
	}
}

// TestGatherAnchorOwnWorkflowCountsOnItsTile pins the in-flight join across the
// gather/board boundary for an anchor that is itself the slung work bead. Its
// input convoy tracks the anchor's own bead, so the gather keys Facts.Inflight
// by the anchor's id, and the tile built from that gather must count the live
// molecule. The board tests hand-build their Facts, so only a board fed by a
// real gather proves the producer and the reader agree on the key.
func TestGatherAnchorOwnWorkflowCountsOnItsTile(t *testing.T) {
	st := populatedStore()
	st.issues["task"] = append(st.issues["task"],
		issue("tk-slung", "Land the slung fix", "task", 2, testNow,
			`{"merge_result":"pre_open_gate","branch":"polecat/tk-slung"}`),
		issue("tk-root9", "mol-polecat-work", "task", 2, testNow,
			`{"gc.kind":"workflow","gc.input_convoy_id":"tk-icv9","gc.session_name":"gc-toolkit__polecat-hq-live"}`),
	)
	// An idle child, so a tile that missed the anchor's own molecule would band
	// stranded rather than merely read zero.
	st.depsUp["tk-slung"] = []*beads.IssueWithDependencyMetadata{
		withDepType(child("tk-kid", "open", testNow, ""), "parent-child"),
	}
	st.depsDown["tk-icv9"] = []*beads.IssueWithDependencyMetadata{withDepType(child("tk-slung", "open", testNow, ""), "tracks")}

	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": st}, withGCClient(liveGC()))
	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	if got := res.Facts.Inflight["tk-slung"]; len(got) != 1 || got[0] != "gc-toolkit__polecat-hq-live" {
		t.Fatalf("the join is keyed by the convoy's member, here the anchor's own bead: got %v", res.Facts.Inflight)
	}

	b := board.BuildBoard(res.Anchors, testNow, res.Partial, res.PartialErrors, res.Facts)
	i := slices.IndexFunc(b.Tiles, func(tl board.Tile) bool { return tl.ID == "tk-slung" })
	if i < 0 {
		t.Fatalf("the merge anchor has no tile among %d", len(b.Tiles))
	}
	tl := b.Tiles[i]
	if tl.InProgressLive != 1 || tl.InFlight != 1 || tl.Stranded {
		t.Errorf("the anchor's own live molecule counts on its tile: in_progress_live=%d in_flight=%d stranded=%v (want 1, 1, false)",
			tl.InProgressLive, tl.InFlight, tl.Stranded)
	}
}

// TestGatherCarriesPrefixesAndDescription pins the two anchor-side inputs the
// cross-rig scan needs: every rig's prefix/name, and the anchor's prose.
func TestGatherCarriesPrefixesAndDescription(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk", "rig-a": "ra"})
	src := newBeadsTestSource(t, root, map[string]*fakeStore{
		"gc-toolkit": populatedStore(), "rig-a": {},
	})
	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	if !slices.Equal(res.Facts.Prefixes, []string{"ra", "tk"}) {
		t.Errorf("prefixes = %v, want [ra tk]", res.Facts.Prefixes)
	}
	if !slices.Equal(res.Facts.RigNames, []string{"gc-toolkit", "rig-a"}) {
		t.Errorf("rig names = %v, want [gc-toolkit rig-a]", res.Facts.RigNames)
	}
	i, ok := findAnchor(res, "tk-epic")
	if !ok {
		t.Fatal("tk-epic missing")
	}
	// The takeaway triple must reach the anchor, or NEEDS falls back to the
	// deterministic phrase and the headline is silently lost.
	if res.Anchors[i].Takeaway != "needs a decision" {
		t.Errorf("takeaway carried onto the anchor: got %q", res.Anchors[i].Takeaway)
	}
}

// TestConvoyOwnershipJoin: a convoy's own "owned" label decides whether it is a
// normal row or the unowned-orphan exception. It is the same label gascity keys
// the `gc convoy list` owned flag on, read here from the convoy bead the gather
// already holds — so ownership is always determinable and there is no absent
// answer to guard against.
func TestConvoyOwnershipJoin(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})

	t.Run("owned label stays a convoy", func(t *testing.T) {
		// populatedStore's tk-cv carries the "owned" label.
		src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": populatedStore()}, withGCClient(liveGC()))
		res, err := src.Gather(context.Background())
		if err != nil {
			t.Fatalf("Gather: %v", err)
		}
		i, ok := findAnchor(res, "tk-cv")
		if !ok {
			t.Fatal("tk-cv missing")
		}
		a := res.Anchors[i]
		if a.Kind != "convoy" {
			t.Errorf("an owned convoy is a normal row: kind=%q", a.Kind)
		}
		if a.Owned == nil || !*a.Owned {
			t.Errorf("owned=true carried: %v", a.Owned)
		}
	})

	t.Run("no owned label flips kind to the orphan exception", func(t *testing.T) {
		st := populatedStore()
		st.issues["convoy"] = append(st.issues["convoy"],
			issue("tk-orphan", "unlabelled convoy", "convoy", 2, testNow, ""))
		src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": st}, withGCClient(liveGC()))
		res, err := src.Gather(context.Background())
		if err != nil {
			t.Fatalf("Gather: %v", err)
		}
		i, ok := findAnchor(res, "tk-orphan")
		if !ok {
			t.Fatal("tk-orphan missing")
		}
		a := res.Anchors[i]
		if a.Kind != "unowned" || a.Source != "unowned" {
			t.Errorf("an unowned convoy is the orphan exception: kind=%q source=%q", a.Kind, a.Source)
		}
		if a.Owned == nil || *a.Owned {
			t.Errorf("owned=false carried: %v", a.Owned)
		}
	})
}

// TestGatherDegradesWhenGCUnavailable: losing the `gc` CLI must narrow the
// board, not abort it — and must say so, because without the session map every
// claim reads as a dead owner and a healthy board would turn bright red with no
// explanation.
func TestGatherDegradesWhenGCUnavailable(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": joinStore()},
		withGCClient(&fakeGC{err: errors.New("gc binary not found")}))

	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("a missing gc must not abort the gather: %v", err)
	}
	if len(res.Anchors) == 0 {
		t.Error("anchors still gather without gc")
	}
	if !res.Partial {
		t.Error("a lost liveness join is a partial gather")
	}
	var sawSessions bool
	for _, e := range res.PartialErrors {
		if strings.Contains(e, "session liveness unavailable") {
			sawSessions = true
		}
	}
	if !sawSessions {
		t.Errorf("the degradation must name itself: %v", res.PartialErrors)
	}
	if len(res.Facts.Inflight) != 0 {
		t.Errorf("no session map means no in-flight claims: %v", res.Facts.Inflight)
	}
}

// TestDecodeLooseJSON: `gc --json` output is not reliably JSON from byte zero —
// deprecation warnings and named-session advisories precede it.
func TestDecodeLooseJSON(t *testing.T) {
	want := map[string]string{"a": "b"}
	cases := []struct {
		name string
		in   string
		ok   bool
	}{
		{"clean", `{"a":"b"}`, true},
		{"leading warning", "named_session \"x\": mode \"always\"\n{\"a\":\"b\"}", true},
		{"warning containing a brace", "warn: got {not json} here\n{\"a\":\"b\"}", true},
		{"whole-input trim handles an indented payload", "  {\"a\":\"b\"}", true},
		{"no json at all", "boom\n", false},
	}
	for _, c := range cases {
		var got map[string]string
		err := decodeLooseJSON([]byte(c.in), &got)
		if c.ok != (err == nil) {
			t.Errorf("%s: err=%v, wanted ok=%v", c.name, err, c.ok)
			continue
		}
		if c.ok && !maps.Equal(got, want) {
			t.Errorf("%s: got %v, want %v", c.name, got, want)
		}
	}
}

// TestHQBeadStoreIsGathered: `gc rig list` reports the city root itself as a rig
// ("hq": true) with its own issue prefix, and gc-helm.sh gathers it like any
// other. Scanning only rigs/*/ dropped it silently — and city-scope work is
// where the `gc.routed_to=human` beads live, i.e. exactly the rows the
// operator's own board exists to show.
func TestHQBeadStoreIsGathered(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	// The HQ store sits at <city>/.beads, beside rigs/, not inside it.
	hq := filepath.Join(root, ".beads")
	if err := os.MkdirAll(hq, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(hq, "config.yaml"), []byte("issue_prefix: hq\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	src := newBeadsTestSource(t, root, nil)
	rigs, err := src.rigs()
	if err != nil {
		t.Fatalf("rigs: %v", err)
	}
	var names, prefixes []string
	for _, r := range rigs {
		names = append(names, r.name)
		prefixes = append(prefixes, r.prefix)
	}
	// The HQ rig is named for the city directory, which is what `gc rig list`
	// reports for it.
	if !slices.Contains(names, filepath.Base(root)) {
		t.Errorf("the HQ store must be gathered as a rig: got %v", names)
	}
	if !slices.Contains(prefixes, "hq") {
		t.Errorf("the HQ prefix must reach Facts.Prefixes (it scopes the cross-rig scan): got %v", prefixes)
	}
	if !slices.Contains(names, "gc-toolkit") {
		t.Errorf("adding HQ must not displace the ordinary rigs: got %v", names)
	}
}

// TestCityWithoutHQStoreStillWorks: not every city root has its own .beads, and
// one that does not must gather its rigs exactly as before.
func TestCityWithoutHQStoreStillWorks(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	src := newBeadsTestSource(t, root, nil)
	rigs, err := src.rigs()
	if err != nil {
		t.Fatalf("rigs: %v", err)
	}
	if len(rigs) != 1 || rigs[0].name != "gc-toolkit" {
		t.Errorf("want exactly the one rig, got %+v", rigs)
	}
}

// TestBeadsProbeVersusCheck pins the gap between the two predicates, which is
// the whole of tk-4cqtv: on a binary whose embedded beads library is behind the
// live stores, every path still resolves — so Check passes and reports the
// backend usable — while every store OPEN fails, which is where Gather would
// have died. Probe asks the question Check cannot.
func TestBeadsProbeVersusCheck(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk", "rig-a": "ra"})
	skew := errors.New("schema version mismatch: database is at v65, binary knows up to v61")

	var tried []string
	broken := NewBeadsSource(
		WithCityPath(root),
		withGCClient(&fakeGC{}),
		withStoreOpener(func(_ context.Context, beadsDir string) (beadStore, error) {
			tried = append(tried, filepath.Base(filepath.Dir(beadsDir)))
			return nil, skew
		}),
	)

	// The defect, stated as an assertion: the cheap check is blind to this.
	if err := broken.Check(); err != nil {
		t.Fatalf("Check passes on a skewed binary — that is the premise of this test: %v", err)
	}
	err := broken.Probe(context.Background())
	if err == nil {
		t.Fatal("Probe must fail when no rig store can be opened")
	}
	// The diagnostic is what an operator reads out of the service log, so the
	// underlying error has to survive verbatim rather than be summarised away.
	if !strings.Contains(err.Error(), "v65") || !strings.Contains(err.Error(), "gc-toolkit") {
		t.Errorf("Probe must name the rig and the underlying failure, got: %v", err)
	}
	if !slices.Equal(tried, []string{"gc-toolkit", "rig-a"}) {
		t.Errorf("Probe must try every rig before giving up, tried %v", tried)
	}
}

// TestBeadsProbeSucceedsOnOneReadableRig pins Probe's success condition to
// Gather's. Gather returns a board as long as ONE rig could be read, so a Probe
// that demanded all of them would refuse a backend that serves fine.
func TestBeadsProbeSucceedsOnOneReadableRig(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk", "rig-a": "ra"})
	var tried []string
	src := NewBeadsSource(
		WithCityPath(root),
		withGCClient(&fakeGC{}),
		withStoreOpener(func(_ context.Context, beadsDir string) (beadStore, error) {
			rig := filepath.Base(filepath.Dir(beadsDir))
			tried = append(tried, rig)
			if rig == "gc-toolkit" {
				return nil, errors.New("schema version mismatch")
			}
			return populatedStore(), nil
		}),
	)
	if err := src.Probe(context.Background()); err != nil {
		t.Fatalf("one readable rig must satisfy Probe: %v", err)
	}
	// Rigs are walked in sorted order and Probe stops at the first success, so
	// it must not have looked past rig-a.
	if !slices.Equal(tried, []string{"gc-toolkit", "rig-a"}) {
		t.Errorf("Probe must stop at the first readable rig, tried %v", tried)
	}

	// A city it cannot even enumerate fails the same way Check does.
	if err := NewBeadsSource(WithCityPath("")).Probe(context.Background()); err == nil {
		t.Error("Probe with no city path must fail")
	}
}

// TestBeadsProbeHandleIsReusedByGather is the cost argument for probing at
// startup, as an assertion rather than a claim in a comment: store() caches, so
// the connection Probe opens is the one the first Gather uses. Probing moves
// the first connection earlier; it does not add one. If this ever fails, the
// entrypoint is paying twice and selectSource's "affordable" reasoning is void.
func TestBeadsProbeHandleIsReusedByGather(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	var opens int
	st := populatedStore()
	src := NewBeadsSource(
		WithCityPath(root),
		withGCClient(&fakeGC{}),
		withStoreOpener(func(context.Context, string) (beadStore, error) {
			opens++
			return st, nil
		}),
	)
	if err := src.Probe(context.Background()); err != nil {
		t.Fatalf("Probe: %v", err)
	}
	if _, err := src.Gather(context.Background()); err != nil {
		t.Fatalf("Gather: %v", err)
	}
	if opens != 1 {
		t.Errorf("probe + gather opened the store %d times, want 1 — a startup probe must not cost an extra connection", opens)
	}
}

// --- conversations and sittings ---------------------------------------------

// conversationBead builds an OPEN conversation task: assigned to `human` while
// it waits in the operator's queue, or to the alias of the sitting holding it.
// Its subject and replies are its own edges, in the store's depsDown.
func conversationBead(id, title, assignee, meta string, created time.Time) *beads.Issue {
	i := issue(id, title, "task", 2, created, meta)
	i.CreatedAt = created
	i.Assignee = assignee
	return i
}

// closedConversationBead builds a FINISHED sitting's conversation, closed with
// the reason its ending wrote. bd's close leaves the assignee as it was. The
// close stamp is what the window filters on, so it is set explicitly.
func closedConversationBead(id, title, assignee, meta, reason string, created, closed time.Time) *beads.Issue {
	i := conversationBead(id, title, assignee, meta, created)
	i.Status = beads.StatusClosed
	i.UpdatedAt = closed
	i.ClosedAt = &closed
	i.CloseReason = reason
	return i
}

// tracks is a conversation's edge onto the bead it is about; repliesTo its edge
// onto a gate it answers.
func tracks(bead string) *beads.IssueWithDependencyMetadata {
	return withDepType(child(bead, "open", testNow, ""), "tracks")
}
func repliesTo(gate string) *beads.IssueWithDependencyMetadata {
	return withDepType(child(gate, "open", testNow, ""), "replies-to")
}

// sittingStore is one subject discussed three times, a fourth conversation
// whose close fell outside the window, one waiting in the operator's queue, and
// three tasks that are not conversations.
//
// The subject carries ONE takeaway, stamped at 09:55 — inside the middle
// sitting's span and outside the other two. That is the whole attribution
// question in fixture form: the takeaway on a bead belongs to the sitting that
// wrote it, and a subject discussed more than once has sittings that did not.
func sittingStore() *fakeStore {
	at := func(h, m int) time.Time { return time.Date(2026, 8, 1, h, m, 0, 0, time.UTC) }
	open := conversationBead("tk-sit-open", "still talking", "gc-toolkit/gc-toolkit.tk-sit-open",
		`{"gc.claimed_at":"2026-08-01T11:00:00Z","gc.session_name":"gc-toolkit__converse-1"}`, at(10, 45))
	open.Status = beads.StatusInProgress
	return &fakeStore{failMeta: map[string]error{}, issues: map[string][]*beads.Issue{
		"task": {
			issue("tk-parked", "the subject three sittings talked about", "task", 2, at(9, 55),
				`{"gc.takeaway":"routed to the polecat pool","gc.takeaway_at":"2026-08-01T09:55:00Z","gc.takeaway_by":"converse"}`),
			issue("tk-quiet", "a subject nobody reached a takeaway on", "task", 2, at(7, 0), `{}`),
			issue("tk-settled", "a subject whose only sitting ended inside the window", "task", 2, at(9, 30), `{}`),
			issue("tk-asked", "a subject the operator queued a concern on", "task", 2, at(8, 0), `{}`),

			open,
			closedConversationBead("tk-sit-recent", "routed the work", "gc-toolkit/gc-toolkit.tk-sit-recent",
				`{"gc.claimed_at":"2026-08-01T09:00:00Z","gc.session_name":"gc-toolkit__converse-2"}`,
				"routed the work to the polecat pool", at(8, 55), at(10, 0)),
			closedConversationBead("tk-sit-earlier", "nothing to do yet", "human",
				`{"gc.claimed_at":"2026-08-01T06:00:00Z"}`, "dismissed by the operator", at(5, 55), at(7, 0)),
			closedConversationBead("tk-sit-settled", "done and closed", "c-tk-sit-settled",
				`{"gc.claimed_at":"2026-08-01T09:30:00Z"}`, "settled", at(9, 25), at(9, 45)),
			// Closed 4 days before the pinned clock: inside the store, outside
			// any default window.
			closedConversationBead("tk-sit-old", "long since done", "human", `{}`, "settled",
				time.Date(2026, 7, 28, 8, 0, 0, 0, time.UTC), time.Date(2026, 7, 28, 9, 0, 0, 0, time.UTC)),
			conversationBead("tk-queued", "operator pick from the board", "human", `{}`, at(8, 30)),

			// Not conversations. Work a person owes tracks nothing; a task held by
			// another task's alias is that task's; and a task tracking two beads
			// is about neither.
			conversationBead("tk-owed", "work a person owes", "human", `{}`, at(8, 0)),
			conversationBead("tk-other", "held by another alias", "gc-toolkit/gc-toolkit.tk-sit-open", `{}`, at(8, 0)),
			conversationBead("tk-two", "tracks two beads", "human", `{}`, at(8, 0)),
		},
	}, depsDown: map[string][]*beads.IssueWithDependencyMetadata{
		"tk-sit-open":    {tracks("tk-parked"), repliesTo("tk-gate")},
		"tk-sit-recent":  {tracks("tk-parked")},
		"tk-sit-earlier": {tracks("tk-parked")},
		"tk-sit-settled": {tracks("tk-settled")},
		"tk-sit-old":     {tracks("tk-quiet")},
		"tk-queued":      {tracks("tk-asked")},
		"tk-other":       {tracks("tk-quiet")},
		"tk-two":         {tracks("tk-quiet"), tracks("tk-asked")},
	}}
}

func sittingsByID(res *Result) map[string]board.Sitting {
	out := map[string]board.Sitting{}
	for _, s := range res.Facts.Sittings {
		out[s.ID] = s
	}
	return out
}

// anchorsOfKind returns the gathered anchors of one kind, by id.
func anchorsOfKind(res *Result, kind string) map[string]board.Anchor {
	out := map[string]board.Anchor{}
	for _, a := range res.Anchors {
		if a.Kind == kind {
			out[a.ID] = a
		}
	}
	return out
}

func gatherSittings(t *testing.T, opts ...BeadsOption) *Result {
	t.Helper()
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": sittingStore()}, opts...)
	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	return res
}

// TestGatherRecordsSittings: the record carries every open conversation and
// those closed inside the window, and nothing older and nothing of another
// shape. A closed conversation carries its close reason, the sentence the card
// reads when the sitting left no takeaway.
func TestGatherRecordsSittings(t *testing.T) {
	got := sittingsByID(gatherSittings(t))

	want := []string{"tk-queued", "tk-sit-earlier", "tk-sit-open", "tk-sit-recent", "tk-sit-settled"}
	if ids := slices.Sorted(maps.Keys(got)); !slices.Equal(ids, want) {
		t.Errorf("sitting record = %v, want %v", ids, want)
	}

	open := got["tk-sit-open"]
	if open.Status != "in_progress" || !open.ClosedAt.IsZero() || open.OutcomeReason != "" {
		t.Errorf("a running sitting has no close: status=%q closed=%v reason=%q", open.Status, open.ClosedAt, open.OutcomeReason)
	}
	if want := time.Date(2026, 8, 1, 11, 0, 0, 0, time.UTC); !open.OpenedAt.Equal(want) {
		t.Errorf("OpenedAt = %v, want the gc.claimed_at stamp %v", open.OpenedAt, want)
	}
	if open.Session != "gc-toolkit__converse-1" || open.Subject != "tk-parked" || open.Rig != "gc-toolkit" {
		t.Errorf("sitting identity: %+v", open)
	}

	done := got["tk-sit-recent"]
	if done.Status != "closed" || done.OutcomeReason != "routed the work to the polecat pool" {
		t.Errorf("a closed sitting carries its close reason: status=%q reason=%q", done.Status, done.OutcomeReason)
	}
	if want := time.Date(2026, 8, 1, 10, 0, 0, 0, time.UTC); !done.ClosedAt.Equal(want) {
		t.Errorf("ClosedAt = %v, want %v", done.ClosedAt, want)
	}
	// A conversation no sitting has claimed starts when it was filed.
	if q := got["tk-queued"]; !q.OpenedAt.Equal(time.Date(2026, 8, 1, 8, 30, 0, 0, time.UTC)) {
		t.Errorf("an unclaimed conversation starts at its creation: %v", q.OpenedAt)
	}
}

// TestGatherAdmitsOpenConversationsAsAnchors: each open conversation is also an
// anchor the fold moves onto its bead, carrying its subject, its replies and
// its holder. A closed one is a sitting alone, so it holds nothing.
func TestGatherAdmitsOpenConversationsAsAnchors(t *testing.T) {
	convs := anchorsOfKind(gatherSittings(t), board.KindConversation)

	if ids := slices.Sorted(maps.Keys(convs)); !slices.Equal(ids, []string{"tk-queued", "tk-sit-open"}) {
		t.Fatalf("conversation anchors = %v, want the two open ones", ids)
	}
	held := convs["tk-sit-open"]
	if !slices.Equal(held.Subjects, []string{"tk-parked"}) || !slices.Equal(held.RepliesTo, []string{"tk-gate"}) ||
		held.Assignee != "gc-toolkit/gc-toolkit.tk-sit-open" || held.Source != board.KindConversation {
		t.Errorf("a held conversation carries its subject, replies and holder: %+v", held)
	}
	if q := convs["tk-queued"]; !slices.Equal(q.Subjects, []string{"tk-asked"}) || q.Assignee != "human" {
		t.Errorf("a queued conversation carries its subject and the operator's queue: %+v", q)
	}
}

// TestConversationShapeIsTheAssigneeAndOneTracksEdge pins the assignee half of
// the shape conversation.sh defines: `human`, or the alias that names the
// task's own id, bare, as its `c-` fallback, or qualified by a session's rig and
// binding.
func TestConversationShapeIsTheAssigneeAndOneTracksEdge(t *testing.T) {
	for _, tc := range []struct {
		assignee string
		want     bool
	}{
		{"human", true},
		{"tk-c1", true},
		{"c-tk-c1", true},
		{"gc-toolkit/gc-toolkit.tk-c1", true},
		{"gc-toolkit/gc-toolkit.c-tk-c1", true},
		{"converse.tk-c1", true},
		{"", false},
		{"alice", false},
		{"gc-toolkit/gc-toolkit.tk-c2", false},
		{"tk-c11", false},
	} {
		if got := conversationAssignee(tc.assignee, "tk-c1"); got != tc.want {
			t.Errorf("conversationAssignee(%q) = %v, want %v", tc.assignee, got, tc.want)
		}
	}
}

// TestSittingTakeawayIsAttributedBySpan is the reason the takeaway is not simply
// copied off the subject: three sittings share one subject, and only the one
// that was running when the takeaway was stamped may claim it.
func TestSittingTakeawayIsAttributedBySpan(t *testing.T) {
	got := sittingsByID(gatherSittings(t))

	if want := "routed to the polecat pool"; got["tk-sit-recent"].Takeaway != want {
		t.Errorf("the sitting whose span contains gc.takeaway_at gets it: %q, want %q", got["tk-sit-recent"].Takeaway, want)
	}
	if s := got["tk-sit-earlier"]; s.Takeaway != "" {
		t.Errorf("a sitting that closed BEFORE the takeaway was stamped must not claim it: %q", s.Takeaway)
	}
	if s := got["tk-sit-open"]; s.Takeaway != "" {
		t.Errorf("a sitting that started AFTER the takeaway was stamped must not claim it: %q", s.Takeaway)
	}
}

// TestSittingCarriesSubjectTitle: the row's topic is the subject bead's title,
// carried onto every sitting that names it — the two with no attributable
// takeaway included, which is the whole point. Unlike the takeaway, the title
// has no span test: it is what the subject is about whenever the sitting ran.
func TestSittingCarriesSubjectTitle(t *testing.T) {
	got := sittingsByID(gatherSittings(t))
	const topic = "the subject three sittings talked about"
	for _, id := range []string{"tk-sit-open", "tk-sit-recent", "tk-sit-earlier"} {
		if s := got[id]; s.SubjectTitle != topic {
			t.Errorf("%s: SubjectTitle = %q, want the subject's title %q", id, s.SubjectTitle, topic)
		}
	}
	for _, id := range []string{"tk-sit-open", "tk-sit-earlier"} {
		if s := got[id]; s.Takeaway != "" {
			t.Errorf("guard: %s should carry no takeaway, got %q", id, s.Takeaway)
		}
	}
}

// TestSittingWindowIsConfigurable: the knob widens the closed half, and zero
// turns it off without touching the running half.
func TestSittingWindowIsConfigurable(t *testing.T) {
	t.Setenv("GC_HELM_SITTINGS_WINDOW", "120h")
	if _, ok := sittingsByID(gatherSittings(t))["tk-sit-old"]; !ok {
		t.Error("a wider window reaches further back")
	}

	t.Setenv("GC_HELM_SITTINGS_WINDOW", "0s")
	res := gatherSittings(t)
	got := sittingsByID(res)
	if _, ok := got["tk-sit-recent"]; ok {
		t.Error("a zero window gathers no closed sittings")
	}
	if _, ok := got["tk-sit-open"]; !ok {
		t.Error("a zero window must not cost the board its RUNNING sittings")
	}
	if _, ok := anchorsOfKind(res, board.KindConversation)["tk-sit-open"]; !ok {
		t.Error("a zero window must not cost the board the conversations that hold their beads")
	}

	t.Setenv("GC_HELM_SITTINGS_WINDOW", "not-a-duration")
	if _, ok := sittingsByID(gatherSittings(t))["tk-sit-recent"]; !ok {
		t.Error("an unparseable window falls back to the default rather than emptying the section")
	}
}

// TestSittingPassesDegradeIndependently: an unreadable subject narrows the
// rows rather than dropping them, and costs the board no conversation that
// holds a bead.
func TestSittingPassesDegradeIndependently(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	st := sittingStore()
	st.failMeta["__ids__"] = errors.New("subject read failed")
	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": st})

	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	got := sittingsByID(res)
	if len(got) != 5 {
		t.Errorf("an unreadable subject narrows the rows, it does not drop them: got %d", len(got))
	}
	if s := got["tk-sit-recent"]; s.Takeaway != "" || s.SubjectTitle != "" || s.OutcomeReason == "" {
		t.Errorf("the sitting keeps what it owns and loses only the joined headline and topic: %+v", s)
	}
	if len(anchorsOfKind(res, board.KindConversation)) != 2 {
		t.Error("an unreadable subject costs the board no conversation that holds a bead")
	}
	if !res.Partial {
		t.Error("a failed subject read is reported as partial")
	}
}

// TestConversationEdgesComeFromOneBatchedRead: the edges of every candidate
// conversation come from one batched dependency read, so the read does not
// grow with the number of conversations, and a store with none spends nothing
// on it.
func TestConversationEdgesComeFromOneBatchedRead(t *testing.T) {
	gather := func(st *fakeStore) *fakeStore {
		root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
		src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": st})
		if _, err := src.Gather(context.Background()); err != nil {
			t.Fatalf("Gather: %v", err)
		}
		return st
	}
	subject := issue("tk-rec", "a subject", "task", 2, testNow, "")
	none := gather(&fakeStore{issues: map[string][]*beads.Issue{"task": {subject}}})
	one := gather(&fakeStore{
		issues:   map[string][]*beads.Issue{"task": {subject, conversationBead("tk-c1", "one", "human", `{}`, testNow)}},
		depsDown: map[string][]*beads.IssueWithDependencyMetadata{"tk-c1": {tracks("tk-rec")}},
	})
	three := gather(&fakeStore{
		issues: map[string][]*beads.Issue{"task": {subject,
			conversationBead("tk-c1", "one", "human", `{}`, testNow),
			conversationBead("tk-c2", "two", "c-tk-c2", `{}`, testNow),
			conversationBead("tk-c3", "three", "human", `{}`, testNow),
		}},
		depsDown: map[string][]*beads.IssueWithDependencyMetadata{
			"tk-c1": {tracks("tk-rec")}, "tk-c2": {tracks("tk-rec")}, "tk-c3": {tracks("tk-rec")},
		},
	})
	if one.depyN != none.depyN+1 || three.depyN != one.depyN {
		t.Errorf("the conversations' edges must come from one batched read: none=%d, one=%d, three=%d (want one = none + 1, three = one)",
			none.depyN, one.depyN, three.depyN)
	}
}

// TestFailedConversationEdgeReadNamesNoConversation: without its edges no task
// can be told for a conversation, so a failed edge read admits none, and the
// gather reports itself partial.
func TestFailedConversationEdgeReadNamesNoConversation(t *testing.T) {
	st := sittingStore()
	st.failDeps = map[string]error{"tk-sit-open": errors.New("edge read failed")}
	res := gatherOneStore(t, st)
	if n := len(anchorsOfKind(res, board.KindConversation)); n != 0 {
		t.Errorf("a failed edge read admits no conversation: got %d", n)
	}
	if n := len(res.Facts.Sittings); n != 0 {
		t.Errorf("a failed edge read records no sitting: got %d", n)
	}
	if !res.Partial {
		t.Error("a failed conversation edge read is reported as partial")
	}
}

// gatherOneStore runs a gather over one gc-toolkit store.
func gatherOneStore(t *testing.T, st *fakeStore) *Result {
	t.Helper()
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": st})
	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	return res
}

// --- human gates ------------------------------------------------------------

// gateBead builds a gate awaiting awaitType, open unless closed is non-zero.
func gateBead(id, title, awaitType, awaitID string, closed time.Time, meta string) *beads.Issue {
	i := issue(id, title, "gate", 2, testNow, meta)
	i.AwaitType, i.AwaitID = awaitType, awaitID
	if !closed.IsZero() {
		i.Status = beads.StatusClosed
		i.ClosedAt = &closed
	}
	return i
}

// gateStore holds human gates and a gate of another kind. tk-hg blocks two
// beads; tk-legacy carries the route and takeaway a gate filed before gates
// were native was stamped with; tk-timer awaits a timer and asks nobody;
// tk-hg-recent closed inside the sittings window and tk-hg-old before it.
func gateStore(now time.Time) *fakeStore {
	st := populatedStore()
	st.issues["gate"] = []*beads.Issue{
		gateBead("tk-hg", "Bring the branch current?", "human", "bring-current", time.Time{}, ""),
		gateBead("tk-legacy", "Which base?", "human", "rebase", time.Time{},
			`{"gc.routed_to":"human","gc.takeaway":"Which base?","gc.demand_for":"tk-a"}`),
		gateBead("tk-timer", "wait an hour", "timer", "", time.Time{}, ""),
		gateBead("tk-hg-recent", "an answered question", "human", "q", now.Add(-2*time.Hour), ""),
		gateBead("tk-hg-old", "a long-answered question", "human", "q", now.Add(-72*time.Hour), ""),
	}
	st.depsUp["tk-hg"] = []*beads.IssueWithDependencyMetadata{
		withDepType(child("tk-b", "open", testNow, ""), "blocks"),
		withDepType(child("tk-a", "open", testNow, ""), "blocks"),
	}
	st.depsUp["tk-legacy"] = []*beads.IssueWithDependencyMetadata{withDepType(child("tk-a", "open", testNow, ""), "blocks")}
	st.depsUp["tk-hg-recent"] = []*beads.IssueWithDependencyMetadata{withDepType(child("tk-a", "open", testNow, ""), "blocks")}
	return st
}

// TestGatherAdmitsHumanGatesWithTheBeadsTheyBlock: a gate that awaits a person
// is a human gate, and its beads are its `blocks` dependents. A gate awaiting
// anything else asks nobody, and a gate is never admitted by the route or the
// takeaway it carries. The closed pass reads back as far as the sittings
// window.
func TestGatherAdmitsHumanGatesWithTheBeadsTheyBlock(t *testing.T) {
	src := newBeadsTestSource(t, cityWithRigs(t, map[string]string{"gc-toolkit": "tk"}),
		map[string]*fakeStore{"gc-toolkit": gateStore(testNow)})
	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	gates := anchorsOfKind(res, board.KindGate)
	if ids := slices.Sorted(maps.Keys(gates)); !slices.Equal(ids, []string{"tk-hg", "tk-hg-recent", "tk-legacy"}) {
		t.Fatalf("human gates = %v, want the open two and the one closed inside the window", ids)
	}
	if got := gates["tk-hg"].Subjects; !slices.Equal(got, []string{"tk-a", "tk-b"}) {
		t.Errorf("a gate's beads are its blocks dependents: got %v", got)
	}
	if gates["tk-hg-recent"].ClosedAt.IsZero() {
		t.Error("a gate closed inside the window is a closed row")
	}
	for _, a := range res.Anchors {
		if a.ID == "tk-legacy" && a.Kind != board.KindGate {
			t.Errorf("a gate is admitted only as a gate, not by its route or takeaway: got kind %q", a.Kind)
		}
	}
}

// TestGatherKeepsAHumanGateInEveryStatusThatHolds: a human gate holds the bead
// it blocks in every status but closed, pinned included (bd-lib.sh's
// HUMAN_GATE_JQ), so the live pass reads it in each of them. Each gate here
// blocks a plain task that has no row of its own, so the gate's own row is the
// only place the board asks its question: a gate the read missed would be a
// question off the board with nothing reported partial.
func TestGatherKeepsAHumanGateInEveryStatusThatHolds(t *testing.T) {
	st := populatedStore()
	holding := []beads.Status{
		beads.StatusOpen, beads.StatusInProgress, beads.StatusBlocked,
		beads.StatusDeferred, beads.Status("hooked"), beads.Status("pinned"),
	}
	want := map[string]string{} // gate id -> the question it asks
	for _, status := range holding {
		id, plain := "tk-g-"+string(status), "tk-plain-"+string(status)
		g := gateBead(id, "Question held while "+string(status)+"?", "human", "q-"+string(status), time.Time{}, "")
		g.Status = status
		st.issues["gate"] = append(st.issues["gate"], g)
		st.depsUp[id] = []*beads.IssueWithDependencyMetadata{withDepType(child(plain, "open", testNow, ""), "blocks")}
		want[id] = g.Title
	}

	src := newBeadsTestSource(t, cityWithRigs(t, map[string]string{"gc-toolkit": "tk"}),
		map[string]*fakeStore{"gc-toolkit": st})
	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	if res.Partial {
		t.Fatalf("unexpected partial: %v", res.PartialErrors)
	}
	gates := anchorsOfKind(res, board.KindGate)
	if ids := slices.Sorted(maps.Keys(gates)); !slices.Equal(ids, slices.Sorted(maps.Keys(want))) {
		t.Fatalf("human gates = %v, want one in each status that holds: %v", ids, slices.Sorted(maps.Keys(want)))
	}

	b := board.BuildBoard(res.Anchors, testNow, res.Partial, res.PartialErrors, res.Facts)
	for _, status := range holding {
		id := "tk-g-" + string(status)
		i := slices.IndexFunc(b.Tiles, func(tl board.Tile) bool { return tl.ID == id })
		if i < 0 {
			t.Errorf("the %s gate has no row, so its question is off the board", status)
			continue
		}
		if tl := b.Tiles[i]; tl.Needs != want[id] || !tl.Owed || tl.Section != board.SectionGate {
			t.Errorf("the %s gate's row asks its question and is owed as a gate: needs=%q owed=%v section=%q",
				status, tl.Needs, tl.Owed, tl.Section)
		}
	}
}

// ── The done pass ────────────────────────────────────────────────────────
//
// The anchor queries ask for open beads, so a closing anchor leaves the board
// on the next gather unless something else keeps it. These pin the second pass
// that does, and the two things that bound it.

// doneStore is one rig's worth of recently closed anchors: one inside the
// window, one outside it, and one inside it that carries a legacy dismiss
// marker from before the DONE band went stateless.
func doneStore() *fakeStore {
	return &fakeStore{
		issues: map[string][]*beads.Issue{
			"epic": {
				issue("tk-live", "still open", "epic", 2, testNow.Add(-time.Hour), ""),
				closedIssue("tk-fresh", "closed yesterday", "epic", 2,
					testNow.Add(-24*time.Hour), testNow.Add(-24*time.Hour), ""),
				closedIssue("tk-ancient", "closed last month", "epic", 2,
					testNow.Add(-30*24*time.Hour), testNow.Add(-30*24*time.Hour), ""),
				// A row closed inside the window that still carries the retired
				// gc.dismissed_at marker. The band reads no per-row state, so the
				// marker is inert and the row bands DONE like any other.
				closedIssue("tk-marked", "closed yesterday, carries a legacy dismiss marker", "epic", 2,
					testNow.Add(-24*time.Hour), testNow.Add(-24*time.Hour),
					`{"gc.dismissed_at":"2026-08-01T09:00:00Z","gc.dismissed_by":"operator"}`),
			},
			"bug": {
				closedIssue("tk-subject", "a conversation subject that closed", "bug", 2,
					testNow.Add(-2*time.Hour), testNow.Add(-2*time.Hour),
					`{"gc.takeaway":"settled — nothing further"}`),
			},
		},
	}
}

func TestGatherKeepsRecentlyClosedAnchors(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": doneStore()})

	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	if res.Partial {
		t.Fatalf("unexpected partial: %v", res.PartialErrors)
	}

	i, ok := findAnchor(res, "tk-fresh")
	if !ok {
		t.Fatal("an anchor that closed yesterday must still be gathered — otherwise its row vanishes the moment it is answered")
	}
	if res.Anchors[i].ClosedAt.IsZero() {
		t.Error("a closed anchor carries closed_at; the derivation bands and orders the row by it")
	}

	// The metadata-keyed kinds close too, and a conversation subject closing is
	// the case the operator actually watched happen.
	if _, ok := findAnchor(res, "tk-subject"); !ok {
		t.Error("a closed metadata-keyed anchor is gathered on the same pass")
	}

	// The live anchor must not acquire a close time from the second pass.
	j, ok := findAnchor(res, "tk-live")
	if !ok {
		t.Fatal("the open anchor is still gathered")
	}
	if !res.Anchors[j].ClosedAt.IsZero() {
		t.Error("an open anchor must read as live; a non-zero closed_at would band it DONE")
	}
}

func TestGatherBoundsTheDoneBand(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": doneStore()})

	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	if _, ok := findAnchor(res, "tk-ancient"); ok {
		t.Error("the window bounds the pass: an anchor closed a month ago is history, not layout")
	}
	// The window is the only bound. A row closed inside it stays on the pass
	// even carrying a legacy gc.dismissed_at: the band reads no per-row state,
	// so the marker is inert and the row ages out on the clock like any other.
	if _, ok := findAnchor(res, "tk-marked"); !ok {
		t.Error("a row closed inside the window bands DONE regardless of a legacy dismiss marker; the band is stateless")
	}
}

// The opt-out has to actually switch the pass off, not merely narrow it: a
// query that still runs against a store with no ClosedAfter bound is the
// unbounded read this window exists to prevent.
func TestDoneWindowOptOut(t *testing.T) {
	t.Setenv("GC_HELM_DONE_WINDOW", "0")
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": doneStore()})

	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	if _, ok := findAnchor(res, "tk-fresh"); ok {
		t.Error("GC_HELM_DONE_WINDOW=0 turns the DONE band off entirely")
	}
	if _, ok := findAnchor(res, "tk-live"); !ok {
		t.Error("...and leaves the live board untouched")
	}
}

// A gather that reads the clock again per rig measures each rig's DONE window
// from a different instant, so a row at the boundary is kept or dropped by how
// long the gather took to reach its rig rather than by the board's own clock.
// The pinned-clock fixtures cannot see that — their clock never moves — so this
// one advances on every read.
func TestDoneWindowUsesOneClockAcrossRigs(t *testing.T) {
	t.Setenv("GC_HELM_DONE_WINDOW", "24h")
	// Closed 23h before the pass clock: inside a 24h window measured at the
	// captured instant, outside one measured from any later read.
	boundary := func(prefix string) *fakeStore {
		return &fakeStore{issues: map[string][]*beads.Issue{
			"epic": {closedIssue(prefix+"-edge", "closed just inside the window", "epic", 2,
				testNow.Add(-23*time.Hour), testNow.Add(-23*time.Hour), "")},
		}}
	}
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk", "rig-a": "ra"})
	src := newBeadsTestSource(t, root, map[string]*fakeStore{
		"gc-toolkit": boundary("tk"),
		"rig-a":      boundary("ra"),
	}, withClock(advancingClock(testNow, 2*time.Hour)))

	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	for _, id := range []string{"tk-edge", "ra-edge"} {
		if _, ok := findAnchor(res, id); !ok {
			t.Errorf("%s closed inside the window at the pass clock and must be gathered; a per-rig clock read ages it out", id)
		}
	}
}

// advancingClock moves on every read, so a second read is always a later
// instant than the one the gather captured.
func advancingClock(start time.Time, step time.Duration) func() time.Time {
	var reads int
	return func() time.Time {
		t := start.Add(time.Duration(reads) * step)
		reads++
		return t
	}
}

func TestDoneSince(t *testing.T) {
	now := time.Date(2026, 8, 1, 12, 0, 0, 0, time.UTC)
	cases := []struct {
		name string
		env  string
		want time.Duration
		off  bool
	}{
		{name: "unset is the default week", want: defaultDoneWindow},
		{name: "a Go duration", env: "48h", want: 48 * time.Hour},
		{name: "bare seconds", env: "3600", want: time.Hour},
		{name: "zero switches the band off", env: "0", off: true},
		// A typo degrades to the DEFAULT, never to off, and a negative value is
		// a typo. Reading "-24h" as an opt-out would silently restore the
		// vanishing this band exists to stop; only the literal "0" does that.
		// Same reading as durationEnv in cmd/helm-svc.
		{name: "a negative duration degrades to the default", env: "-24h", want: defaultDoneWindow},
		{name: "so does an unparseable one", env: "seven days", want: defaultDoneWindow},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Setenv("GC_HELM_DONE_WINDOW", c.env)
			since, ok := doneSince(now)
			if ok == c.off {
				t.Fatalf("window enabled = %v, want %v", ok, !c.off)
			}
			if !c.off && !since.Equal(now.Add(-c.want)) {
				t.Errorf("since = %s, want %s", since, now.Add(-c.want))
			}
		})
	}
}

// TestMergeAnchorsAreGathered is the PR round-trip's gather (specs/tk-q0ml23).
//
// `doctor/check-one-anchor-per-pr` asserts one open gating anchor per pull
// request, so the anchor already IS the PR's row. A merge anchor is otherwise
// an ordinary task or bug: `merge_result` is the only marker that tells it from
// the rest of the store, and a `progressing` or `settled` anchor carries no
// human route for any other gather kind to select on.
//
// Keyed on merge_result PRESENCE, never on pr_number: an anchor at
// pre_open_gate has no pull request open, so a number-keyed query would omit
// it.
func mergeStore() *fakeStore {
	return &fakeStore{
		issues: map[string][]*beads.Issue{
			"task": {
				issue("tk-pre", "held for a person before the PR opened", "task", 1, testNow.Add(-3*24*time.Hour),
					`{"merge_result":"pre_open_gate","branch":"polecat/tk-pre","gc.routed_to":"human","pr.machine":"progressing@aaaa@2026-08-28T04:05:06Z"}`),
				issue("tk-open", "an ordinary open PR", "task", 2, testNow,
					`{"merge_result":"pull_request","pr_number":"512","branch":"polecat/tk-open"}`),
				issue("tk-talked", "an open PR a sitting talked about", "task", 2, testNow,
					`{"merge_result":"pull_request","pr_number":"513","branch":"polecat/tk-talked","gc.takeaway":"ruled; in rework"}`),
				issue("tk-quiet", "no merge_result at all", "task", 2, testNow, `{"branch":"polecat/tk-quiet"}`),
			},
		},
		depsDown: map[string][]*beads.IssueWithDependencyMetadata{
			"tk-open": {
				withDepType(child("tk-rev", "open", testNow,
					`{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat-codex","anchor_bead":"tk-open"}`), "blocks"),
				withDepType(child("tk-dem", "open", testNow, `{"gc.routed_to":"human"}`), "blocks"),
				// Not a `blocks` edge: it holds nothing and must not be read as
				// an actor or as a demand.
				withDepType(child("tk-rel", "open", testNow, `{"gc.routed_to":"gc-toolkit/x"}`), "related"),
			},
		},
	}
}

// reviewFixture is a review-shaped bead as the store holds it, in status st. A
// closed one carries the close instant the library sets with the status.
func reviewFixture(id string, st beads.Status, meta string) *beads.Issue {
	iss := issue(id, "Review "+id, "task", 2, testNow, meta)
	iss.Status = st
	if st == beads.StatusClosed {
		c := testNow
		iss.ClosedAt = &c
	}
	return iss
}

// joinedTo is iss's membership edge onto its anchor, of type typ, as the inbound
// read returns it.
func joinedTo(iss *beads.Issue, typ string) *beads.IssueWithDependencyMetadata {
	return withDepType(&beads.IssueWithDependencyMetadata{Issue: *iss}, typ)
}

// gatherPreOpen gathers one gc-toolkit store and returns the result and the
// anchor id, failing the test when the anchor is missing.
func gatherPreOpen(t *testing.T, st *fakeStore, id string) (*Result, board.Anchor) {
	t.Helper()
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	res, err := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": st}).Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	i, ok := findAnchor(res, id)
	if !ok {
		t.Fatalf("anchor %s is missing", id)
	}
	return res, res.Anchors[i]
}

// reviewIDs lists an anchor's gathered reviews as id/status, sorted.
func reviewIDs(a board.Anchor) []string {
	var ids []string
	for _, r := range a.Reviews {
		ids = append(ids, r.ID+"/"+r.Status)
	}
	slices.Sort(ids)
	return ids
}

// joinedMark is the joined mark tools/anchor-edges-backfill.sh --mark leaves.
var joinedMark = map[string]string{anchorJoinedKey: "2026-10-13T12:02:03Z"}

// preOpenNeeds builds the board from a gather and returns the NEEDS line of the
// tile for anchor id, failing the test when it has none.
func preOpenNeeds(t *testing.T, res *Result, id string) string {
	t.Helper()
	b := board.BuildBoard(res.Anchors, testNow, res.Partial, res.PartialErrors, res.Facts)
	i := slices.IndexFunc(b.Tiles, func(tl board.Tile) bool { return tl.ID == id })
	if i < 0 {
		t.Fatalf("anchor %s has no tile among %d", id, len(b.Tiles))
	}
	return b.Tiles[i].Needs
}

// stalePreOpen is a merge anchor parked at pre_open_gate under check_set, last
// touched five days ago, past the stall threshold.
func stalePreOpen(id, checkSet string) *beads.Issue {
	return issue(id, "pre-open "+id, "task", 2, testNow.Add(-5*24*time.Hour),
		`{"merge_result":"pre_open_gate","check_set":"`+checkSet+`"}`)
}

// TestPreOpenReviewsInAJoinedStore: a live merge anchor at pre_open_gate carries
// its review beads, read the way bd-lib.sh reads an anchor's children in a store
// marked joined. The live ones come from the anchor_bead read, with an edge or
// without one. The closed ones come through the anchor's inbound edges of any
// type (bd-lib.sh joins a child with a `related` edge), kept only when the far
// end is a closed review naming this anchor in anchor_bead, so a closed review
// with no edge is not read. A live review the edge reaches and the anchor_bead
// read did not return, one filed between the two reads, waits for the next
// gather, as bd_anchor_children leaves it. Reviews are not roll-up children, a
// pull_request anchor gathers none, and a failed inbound read marks them
// unknown rather than empty.
func TestPreOpenReviewsInAJoinedStore(t *testing.T) {
	// Kept out of the fixture's issues table, so the anchor_bead read misses it
	// and only the edge read reaches it.
	filedLate := joinedTo(reviewFixture("rv-late", beads.StatusOpen, `{"task_kind":"review","anchor_bead":"tk-gate","check_name":"triage"}`), "related")
	approve := reviewFixture("rv-ok", beads.StatusClosed, `{"task_kind":"review","anchor_bead":"tk-gate","check_name":"correctness","reviewed_oid":"abc","signoff_verdict":"approve","gc.outcome":"recorded"}`)
	open := reviewFixture("rv-live", beads.StatusOpen, `{"task_kind":"review","anchor_bead":"tk-gate","check_name":"triage"}`)
	claimed := reviewFixture("rv-claimed", beads.StatusInProgress, `{"task_kind":"review","anchor_bead":"tk-gate","check_name":"arch"}`)
	unjoined := reviewFixture("rv-unjoined", beads.StatusClosed, `{"task_kind":"review","anchor_bead":"tk-gate","check_name":"triage","reviewed_oid":"abc","signoff_verdict":"approve"}`)
	moved := reviewFixture("rv-moved", beads.StatusClosed, `{"task_kind":"review","anchor_bead":"tk-other","check_name":"triage"}`)
	rework := reviewFixture("rw-1", beads.StatusClosed, `{"task_kind":"rework","anchor_bead":"tk-gate"}`)
	conv := reviewFixture("cv-1", beads.StatusOpen, `{}`)
	prReview := reviewFixture("rv-pr", beads.StatusClosed, `{"task_kind":"review","anchor_bead":"tk-pr","check_name":"correctness"}`)
	store := func() *fakeStore {
		return &fakeStore{
			issues: map[string][]*beads.Issue{
				"task": {
					issue("tk-gate", "pre-open, reviewed", "task", 2, testNow, `{"merge_result":"pre_open_gate","check_set":"correctness,triage,arch"}`),
					issue("tk-pr", "an open PR", "task", 2, testNow, `{"merge_result":"pull_request","pr_number":"9"}`),
					approve, open, claimed, unjoined, moved, rework, conv, prReview,
				},
			},
			depsUp: map[string][]*beads.IssueWithDependencyMetadata{
				"tk-gate": {
					joinedTo(approve, "related"), joinedTo(claimed, "related"), joinedTo(moved, "related"),
					joinedTo(rework, "related"), joinedTo(conv, "tracks"), filedLate,
				},
				"tk-pr": {joinedTo(prReview, "related")},
			},
			kv: joinedMark,
		}
	}

	res, gate := gatherPreOpen(t, store(), "tk-gate")
	if got, want := reviewIDs(gate), []string{"rv-claimed/in_progress", "rv-live/open", "rv-ok/closed"}; !slices.Equal(got, want) {
		t.Errorf("reviews = %v, want %v: the anchor's live reviews, edge or not, and its closed ones through the edge", got, want)
	}
	for _, r := range gate.Reviews {
		if r.ID == "rv-ok" && r.Metadata["signoff_verdict"] != "approve" {
			t.Errorf("a review carries the metadata its lane derives from: %v", r.Metadata)
		}
	}
	if gate.ReviewsUnknown {
		t.Error("a read that answered is not unknown")
	}
	if len(gate.Children) != 0 {
		t.Errorf("reviews joined by a related edge are no roll-up children: %+v", gate.Children)
	}
	j, ok := findAnchor(res, "tk-pr")
	if !ok {
		t.Fatal("the PR anchor is missing")
	}
	if pr := res.Anchors[j]; len(pr.Reviews) != 0 || pr.ReviewsUnknown {
		t.Errorf("a pull_request anchor gathers no reviews: %+v unknown=%v", pr.Reviews, pr.ReviewsUnknown)
	}

	failing := store()
	failing.failDeps = map[string]error{"tk-gate": errors.New("dependents unreadable")}
	if _, gate := gatherPreOpen(t, failing, "tk-gate"); !gate.ReviewsUnknown || len(gate.Reviews) != 0 {
		t.Errorf("a failed inbound read marks the reviews unknown, not empty: unknown=%v reviews=%v", gate.ReviewsUnknown, gate.Reviews)
	}

	unreadable := store()
	unreadable.failMeta = map[string]error{"task_kind": errors.New("reviews unreadable")}
	res, gate = gatherPreOpen(t, unreadable, "tk-gate")
	if !gate.ReviewsUnknown || len(gate.Reviews) != 0 {
		t.Errorf("a failed live review read marks the reviews unknown, not empty: unknown=%v reviews=%v", gate.ReviewsUnknown, reviewIDs(gate))
	}
	if want := "reviews@gc-toolkit: reviews unreadable"; !res.Partial || !slices.Contains(res.PartialErrors, want) {
		t.Errorf("partial=%v errors=%v, want %q among them", res.Partial, res.PartialErrors, want)
	}
}

// TestPreOpenLiveReviewWithNoEdgeHoldsItsLane: in a store marked joined, a live
// review the edge does not reach still holds its lane out of green, because the
// live reviews are read by anchor_bead. lane-state.sh reads it the same way, so
// the lane is not green on the board either, though a closed approve backs it.
func TestPreOpenLiveReviewWithNoEdgeHoldsItsLane(t *testing.T) {
	approve := reviewFixture("rv-ok", beads.StatusClosed, `{"task_kind":"review","anchor_bead":"tk-gate","check_name":"correctness","reviewed_oid":"abc","signoff_verdict":"approve","gc.outcome":"recorded"}`)
	rerun := reviewFixture("rv-rerun", beads.StatusOpen, `{"task_kind":"review","anchor_bead":"tk-gate","check_name":"correctness"}`)
	store := func(reviews ...*beads.Issue) *fakeStore {
		return &fakeStore{
			issues: map[string][]*beads.Issue{"task": append([]*beads.Issue{stalePreOpen("tk-gate", "correctness")}, reviews...)},
			depsUp: map[string][]*beads.IssueWithDependencyMetadata{"tk-gate": {joinedTo(approve, "related")}},
			kv:     joinedMark,
		}
	}

	res, gate := gatherPreOpen(t, store(approve, rerun), "tk-gate")
	if got, want := reviewIDs(gate), []string{"rv-ok/closed", "rv-rerun/open"}; !slices.Equal(got, want) {
		t.Errorf("reviews = %v, want %v", got, want)
	}
	if got := preOpenNeeds(t, res, "tk-gate"); !strings.HasPrefix(got, "correctness check stalled — ") {
		t.Errorf("needs = %q: an open review holds the correctness lane out of green", got)
	}
	// The approve alone greens the lane, so it is the open review that holds it.
	if res, _ := gatherPreOpen(t, store(approve), "tk-gate"); strings.Contains(preOpenNeeds(t, res, "tk-gate"), "check stalled") {
		t.Errorf("needs = %q: with no review open, the approve greens the lane", preOpenNeeds(t, res, "tk-gate"))
	}
}

// TestPreOpenReviewsInAnUnmarkedStore: the edges answer for an anchor's closed
// reviews only in a store marked joined. A store without the mark would have to
// scan its closed ledger to find them, so its reviews are unknown, and an
// anchor whose reviews are unknown fires no stall. A closed approve that names
// the anchor and has no edge backs its lane through lane-state.sh, and the board
// does not report that anchor as a check no review has run. A store without the
// mark is a state the gather reads, not a failed read. A mark that cannot be read
// reads as no mark and is noted partial.
func TestPreOpenReviewsInAnUnmarkedStore(t *testing.T) {
	store := func() *fakeStore {
		return &fakeStore{
			issues: map[string][]*beads.Issue{
				"task": {
					stalePreOpen("tk-gate", "correctness"),
					reviewFixture("rv-meta", beads.StatusClosed, `{"task_kind":"review","anchor_bead":"tk-gate","check_name":"correctness","reviewed_oid":"abc","signoff_verdict":"approve","gc.outcome":"recorded"}`),
				},
			},
		}
	}
	const neverReviewed = "correctness check stalled — no review has run"

	res, gate := gatherPreOpen(t, store(), "tk-gate")
	if !gate.ReviewsUnknown || len(gate.Reviews) != 0 {
		t.Errorf("an unmarked store's reviews are unknown, not empty: unknown=%v reviews=%v", gate.ReviewsUnknown, reviewIDs(gate))
	}
	if res.Partial {
		t.Errorf("partial errors = %v: a store without the mark is not a failed read", res.PartialErrors)
	}
	if got := preOpenNeeds(t, res, "tk-gate"); got == neverReviewed {
		t.Errorf("needs = %q: the board cannot tell the lane has no review", got)
	}
	// Marked joined, the same store's closed approve has no edge to be read by,
	// so the anchor stalls: the unknown is what keeps the false stall off.
	marked := store()
	marked.kv = joinedMark
	if res, _ := gatherPreOpen(t, marked, "tk-gate"); preOpenNeeds(t, res, "tk-gate") != neverReviewed {
		t.Errorf("needs = %q, want %q in the marked store", preOpenNeeds(t, res, "tk-gate"), neverReviewed)
	}

	unreadable := store()
	unreadable.kv = joinedMark
	unreadable.failKV = errors.New("config unreadable")
	res, gate = gatherPreOpen(t, unreadable, "tk-gate")
	if !gate.ReviewsUnknown || len(gate.Reviews) != 0 {
		t.Errorf("an unreadable mark reads as no mark: unknown=%v reviews=%v", gate.ReviewsUnknown, reviewIDs(gate))
	}
	if want := "reviews@gc-toolkit: config unreadable"; !res.Partial || !slices.Contains(res.PartialErrors, want) {
		t.Errorf("partial=%v errors=%v, want %q among them", res.Partial, res.PartialErrors, want)
	}
}

// TestReviewReadKeepsALiveRowLive: a review the live read returned can close
// before the edge read hydrates it. It is reported once, as the live read saw
// it, the way bd_anchor_children reports such a child live rather than missing
// it.
func TestReviewReadKeepsALiveRowLive(t *testing.T) {
	rv := reviewReads{known: true, live: map[string][]board.Child{
		"tk-gate": {{ID: "rv-1", Status: "open", Metadata: map[string]string{"task_kind": "review", "anchor_bead": "tk-gate"}}},
	}}
	closedSince := reviewFixture("rv-1", beads.StatusClosed, `{"task_kind":"review","anchor_bead":"tk-gate","reviewed_oid":"abc","signoff_verdict":"approve"}`)
	recs := []*beads.Dependency{{IssueID: "rv-1", DependsOnID: "tk-gate", Type: "related"}}
	got, unknown := rv.forAnchor("tk-gate", recs, map[string]*beads.Issue{"rv-1": closedSince}, true)
	if unknown || len(got) != 1 || got[0].Status != "open" {
		t.Errorf("reviews = %+v unknown=%v, want rv-1 once, still open", got, unknown)
	}
}

func TestMergeAnchorsAreGathered(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": mergeStore()})

	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}

	kinds := map[string][]string{}
	for _, a := range res.Anchors {
		kinds[a.ID] = append(kinds[a.ID], a.Kind)
	}
	// A merge anchor routed to a person carries BOTH markers and gathers twice,
	// exactly as a human+parked bead does. `human` comes FIRST so BuildBoard's
	// id-dedup — which keeps the first at equal rank — leaves it a human row
	// rather than letting the kind flip between passes.
	if got := kinds["tk-pre"]; len(got) != 2 || got[0] != "human" || got[1] != "merge" {
		t.Errorf("tk-pre kinds = %v, want [human merge] in that order", got)
	}
	if got := kinds["tk-open"]; len(got) != 1 || got[0] != "merge" {
		t.Errorf("tk-open kinds = %v, want [merge] — a detached anchor has no route to gather it", got)
	}
	// A pull request a sitting talked about carries a takeaway too and gathers
	// twice. `merge` comes FIRST, so the dedup leaves the pull request's row: the
	// takeaway does not make it a parked bead.
	if got := kinds["tk-talked"]; len(got) != 2 || got[0] != "merge" || got[1] != "parked" {
		t.Errorf("tk-talked kinds = %v, want [merge parked] in that order", got)
	}
	if got := kinds["tk-quiet"]; got != nil {
		t.Errorf("a bead with no merge_result is not a merge anchor: %v", got)
	}

	i, ok := findAnchor(res, "tk-open")
	if !ok {
		t.Fatal("merge anchor missing")
	}
	open := res.Anchors[i]
	if got := open.Metadata["pr_number"]; got != "512" {
		t.Errorf("the PR identity rides on the anchor: %v", open.Metadata)
	}

	// The blockers carry what the two axes discriminate on. The ROUTE is what
	// separates a review or rework child, which a pool will claim, from the
	// demand bead that makes the anchor `asking` — and the ids alone, which is
	// all WaitingOn carries, cannot answer either question.
	if len(open.Blockers) != 2 {
		t.Fatalf("blockers = %+v, want the two `blocks` edges only", open.Blockers)
	}
	byID := map[string]board.Blocker{}
	for _, b := range open.Blockers {
		byID[b.ID] = b
	}
	if got := byID["tk-rev"].RoutedTo; got != "gc-toolkit/gc-toolkit.polecat-codex" {
		t.Errorf("the pool route must ride on the blocker: %q", got)
	}
	if got := byID["tk-dem"].RoutedTo; got != "human" {
		t.Errorf("the demand's route must ride on it too: %q", got)
	}
	if byID["tk-rev"].Status != "open" || byID["tk-dem"].Status != "open" {
		t.Errorf("blocker statuses: %+v", open.Blockers)
	}
	// Same read, not a second one: the id slices still come out of it.
	if len(open.WaitingOn) != 2 || open.WaitingUnknown {
		t.Errorf("waiting_on = %v (unknown=%v) — the blockers and the ids are one query",
			open.WaitingOn, open.WaitingUnknown)
	}
}

// TestMergeAnchorUnreadableEdgesStayUnknown. An edge set that could not be read
// is not an anchor with no blockers: it looks identical, and the PR axes would
// silently report "nothing is holding this" for a row whose demand bead the
// store simply failed to return.
func TestMergeAnchorUnreadableEdgesStayUnknown(t *testing.T) {
	st := mergeStore()
	st.failDeps = map[string]error{"tk-open": errors.New("dolt timeout")}
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": st})

	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	i, ok := findAnchor(res, "tk-open")
	if !ok {
		t.Fatal("merge anchor missing")
	}
	if !res.Anchors[i].WaitingUnknown {
		t.Error("an unreadable edge set must say so rather than read as no blockers")
	}
	if len(res.Anchors[i].Blockers) != 0 {
		t.Errorf("nothing was read, so nothing is reported: %+v", res.Anchors[i].Blockers)
	}
	if !res.Partial {
		t.Error("the gather is degraded and the board has to say so out loud")
	}
}

// holdingGateIDs lists the gates a walk reached for an anchor, in its order.
func holdingGateIDs(a board.Anchor) []string {
	ids := []string{}
	for _, g := range a.HoldingGates {
		ids = append(ids, g.ID)
	}
	return ids
}

// blocksEdge is one `blocks` edge fixture, onto the far bead it names.
func blocksEdge(far *beads.Issue) *beads.IssueWithDependencyMetadata {
	return &beads.IssueWithDependencyMetadata{Issue: *far, DependencyType: "blocks"}
}

// TestMergeAnchorHoldingGatesAreWalked: a live merge anchor carries the open human
// gates that hold it, through the `blocks` edges of what it waits on, read by the
// walk the PR labels read, with each gate's own age and question. A closed
// blocker ends a path, a closed gate holds nothing, and a conversation, which
// tracks its bead, is no edge the walk follows.
func TestMergeAnchorHoldingGatesAreWalked(t *testing.T) {
	const prMeta = `{"merge_result":"pull_request","pr_number":"79"}`
	pr := func() *beads.Issue { return issue("tk-pr", "an open PR", "task", 2, testNow, prMeta) }
	rework := func() *beads.Issue {
		return issue("tk-rw", "fix the check", "task", 2, testNow, `{"task_kind":"rework","anchor_bead":"tk-pr"}`)
	}
	gate := func(id string) *beads.Issue {
		g := gateBead(id, "ask "+id, "human", "", time.Time{}, `{}`)
		g.CreatedAt = testNow.Add(-48 * time.Hour)
		return g
	}
	closed := func(i *beads.Issue) *beads.Issue {
		i.Status = beads.StatusClosed
		return i
	}
	store := func(edges map[string][]*beads.IssueWithDependencyMetadata) *fakeStore {
		return &fakeStore{issues: map[string][]*beads.Issue{"task": {pr()}}, depsDown: edges}
	}

	for _, tc := range []struct {
		name  string
		edges map[string][]*beads.IssueWithDependencyMetadata
		want  []string
	}{
		{"nothing blocks it", nil, []string{}},
		{"a gate on the anchor", map[string][]*beads.IssueWithDependencyMetadata{"tk-pr": {blocksEdge(gate("tk-g"))}}, []string{"tk-g"}},
		{"a gate on its rework", map[string][]*beads.IssueWithDependencyMetadata{
			"tk-pr": {blocksEdge(rework())}, "tk-rw": {blocksEdge(gate("tk-g"))}}, []string{"tk-g"}},
		{"a gate two beads away", map[string][]*beads.IssueWithDependencyMetadata{
			"tk-pr": {blocksEdge(rework())},
			"tk-rw": {blocksEdge(issue("tk-t", "t", "task", 2, testNow, `{}`))},
			"tk-t":  {blocksEdge(gate("tk-g"))}}, []string{"tk-g"}},
		{"a resolved gate", map[string][]*beads.IssueWithDependencyMetadata{
			"tk-pr": {blocksEdge(rework())}, "tk-rw": {blocksEdge(closed(gate("tk-g")))}}, []string{}},
		{"a gate behind a closed blocker", map[string][]*beads.IssueWithDependencyMetadata{
			"tk-pr": {blocksEdge(closed(rework()))}, "tk-rw": {blocksEdge(gate("tk-g"))}}, []string{}},
		{"a gate the rework only tracks", map[string][]*beads.IssueWithDependencyMetadata{
			"tk-pr": {blocksEdge(rework())},
			"tk-rw": {{Issue: *gate("tk-g"), DependencyType: "tracks"}}}, []string{}},
		{"a conversation tracking the anchor", map[string][]*beads.IssueWithDependencyMetadata{
			"tk-pr": {{Issue: *issue("tk-c", "c", "task", 2, testNow, `{}`), DependencyType: "tracks"}}}, []string{}},
		{"a cycle", map[string][]*beads.IssueWithDependencyMetadata{
			"tk-pr": {blocksEdge(rework())},
			"tk-rw": {blocksEdge(issue("tk-t", "t", "task", 2, testNow, `{}`))},
			"tk-t":  {blocksEdge(rework()), blocksEdge(gate("tk-g"))}}, []string{"tk-g"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			res, anchor := gatherPreOpen(t, store(tc.edges), "tk-pr")
			if got := holdingGateIDs(anchor); !slices.Equal(got, tc.want) {
				t.Errorf("holding gates = %v, want %v", got, tc.want)
			}
			if res.Partial {
				t.Errorf("a walk that read notes nothing partial: %v", res.PartialErrors)
			}
		})
	}

	t.Run("the gate comes back whole", func(t *testing.T) {
		_, anchor := gatherPreOpen(t, store(map[string][]*beads.IssueWithDependencyMetadata{
			"tk-pr": {blocksEdge(rework())}, "tk-rw": {blocksEdge(gate("tk-g"))}}), "tk-pr")
		if len(anchor.HoldingGates) != 1 {
			t.Fatalf("holding gates = %v, want one", anchor.HoldingGates)
		}
		g := anchor.HoldingGates[0]
		if g.Title != "ask tk-g" || g.IssueType != "gate" || g.AwaitType != "human" || g.Status != "open" ||
			!g.CreatedAt.Equal(testNow.Add(-48*time.Hour)) {
			t.Errorf("gate = %+v, want its title, kind, status and age", g)
		}
	})

	t.Run("a closed anchor walks nothing", func(t *testing.T) {
		doneAt := testNow.Add(-time.Hour)
		done := issue("tk-done", "landed", "task", 2, testNow, `{"merge_result":"merged"}`)
		done.Status, done.ClosedAt = beads.StatusClosed, &doneAt
		st := &fakeStore{
			issues:   map[string][]*beads.Issue{"task": {pr(), done}},
			depsDown: map[string][]*beads.IssueWithDependencyMetadata{"tk-done": {blocksEdge(gate("tk-g"))}},
		}
		res, _ := gatherPreOpen(t, st, "tk-pr")
		if i, ok := findAnchor(res, "tk-done"); ok && len(res.Anchors[i].HoldingGates) != 0 {
			t.Errorf("a closed anchor carries gates %v", holdingGateIDs(res.Anchors[i]))
		}
	})

	t.Run("a walk that fails notes partial and keeps the anchor's own waits", func(t *testing.T) {
		st := store(map[string][]*beads.IssueWithDependencyMetadata{
			"tk-pr": {blocksEdge(rework())}, "tk-rw": {blocksEdge(gate("tk-g"))}})
		st.failDeps = map[string]error{"tk-rw": errors.New("dolt timeout")}
		res, anchor := gatherPreOpen(t, st, "tk-pr")
		if len(anchor.HoldingGates) != 0 {
			t.Errorf("holding gates = %v, want none from a walk that failed", holdingGateIDs(anchor))
		}
		if !res.Partial || !slices.ContainsFunc(res.PartialErrors, func(e string) bool { return strings.HasPrefix(e, "holding-gates@") }) {
			t.Errorf("partial=%v errors=%v, want the walk's failure noted", res.Partial, res.PartialErrors)
		}
		if len(anchor.Blockers) != 1 || anchor.WaitingUnknown {
			t.Errorf("blockers=%v unknown=%v: the anchor's own edges read, so they stand", anchor.Blockers, anchor.WaitingUnknown)
		}
	})

	t.Run("a far bead that does not hydrate notes partial, as a failed edge read does", func(t *testing.T) {
		st := store(map[string][]*beads.IssueWithDependencyMetadata{
			"tk-pr": {blocksEdge(rework())}, "tk-rw": {blocksEdge(gate("tk-g"))}})
		st.failIDs = map[string]error{"tk-g": errors.New("dolt timeout")}
		res, anchor := gatherPreOpen(t, st, "tk-pr")
		if len(anchor.HoldingGates) != 0 {
			t.Errorf("holding gates = %v, want none from a walk that failed", holdingGateIDs(anchor))
		}
		if !res.Partial || !slices.ContainsFunc(res.PartialErrors, func(e string) bool { return strings.HasPrefix(e, "holding-gates@") }) {
			t.Errorf("partial=%v errors=%v, want the walk's failure noted", res.Partial, res.PartialErrors)
		}
	})

	t.Run("an anchor past the walk's bound notes partial, and another anchor keeps its gates", func(t *testing.T) {
		wide := []*beads.IssueWithDependencyMetadata{blocksEdge(gate("tk-own"))}
		for i := range 300 {
			wide = append(wide, blocksEdge(issue(fmt.Sprintf("tk-t%d", i), "t", "task", 2, testNow, `{}`)))
		}
		st := &fakeStore{
			issues: map[string][]*beads.Issue{"task": {pr(), issue("tk-pr2", "another PR", "task", 2, testNow, prMeta)}},
			depsDown: map[string][]*beads.IssueWithDependencyMetadata{
				"tk-pr":  wide,
				"tk-pr2": {blocksEdge(rework())},
				"tk-rw":  {blocksEdge(gate("tk-g"))},
			},
		}
		res, anchor := gatherPreOpen(t, st, "tk-pr")
		if got := holdingGateIDs(anchor); len(got) != 0 {
			t.Errorf("tk-pr's holding gates = %v, want none from a walk that did not finish", got)
		}
		if len(anchor.Blockers) != len(wide) {
			t.Errorf("tk-pr has %d blockers, want its own %d: its own edges read, so they stand", len(anchor.Blockers), len(wide))
		}
		i, ok := findAnchor(res, "tk-pr2")
		if !ok {
			t.Fatal("anchor tk-pr2 is missing")
		}
		if got := holdingGateIDs(res.Anchors[i]); !slices.Equal(got, []string{"tk-g"}) {
			t.Errorf("tk-pr2's holding gates = %v, want its own, whatever walk beside it passed its bound", got)
		}
		if !res.Partial || !slices.ContainsFunc(res.PartialErrors, func(e string) bool {
			return strings.HasPrefix(e, "holding-gates@") && strings.HasSuffix(e, ": tk-pr")
		}) {
			t.Errorf("partial=%v errors=%v, want the note to name tk-pr", res.Partial, res.PartialErrors)
		}
	})

	t.Run("a gate reached for one anchor holds only the anchor its blocks edge reaches", func(t *testing.T) {
		// The anchors' walks share their reads, so tk-g's row is read for tk-pr2, and
		// only the edge's type says tk-pr does not wait on it.
		st := &fakeStore{
			issues: map[string][]*beads.Issue{"task": {pr(), issue("tk-pr2", "another PR", "task", 2, testNow, prMeta)}},
			depsDown: map[string][]*beads.IssueWithDependencyMetadata{
				"tk-pr":  {{Issue: *gate("tk-g"), DependencyType: "related"}},
				"tk-pr2": {blocksEdge(gate("tk-g"))},
			},
		}
		res, anchor := gatherPreOpen(t, st, "tk-pr")
		if got := holdingGateIDs(anchor); len(got) != 0 {
			t.Errorf("tk-pr's holding gates = %v, want none: it only relates to the gate", got)
		}
		i, ok := findAnchor(res, "tk-pr2")
		if !ok {
			t.Fatal("anchor tk-pr2 is missing")
		}
		if got := holdingGateIDs(res.Anchors[i]); !slices.Equal(got, []string{"tk-g"}) {
			t.Errorf("tk-pr2's holding gates = %v, want the gate its edge reaches", got)
		}
	})

	t.Run("the walk reads per level, not per anchor", func(t *testing.T) {
		reads := func(prs int) int {
			edges := map[string][]*beads.IssueWithDependencyMetadata{"tk-rw": {blocksEdge(gate("tk-g"))}}
			rows := []*beads.Issue{}
			for i := range prs {
				id := fmt.Sprintf("tk-pr%d", i)
				rows = append(rows, issue(id, "a PR", "task", 2, testNow, prMeta))
				edges[id] = []*beads.IssueWithDependencyMetadata{blocksEdge(rework())}
			}
			st := &fakeStore{issues: map[string][]*beads.Issue{"task": rows}, depsDown: edges}
			res, anchor := gatherPreOpen(t, st, "tk-pr0")
			if got := holdingGateIDs(anchor); !slices.Equal(got, []string{"tk-g"}) {
				t.Errorf("holding gates = %v, want the shared gate (partial %v)", got, res.PartialErrors)
			}
			return st.depyN
		}
		if one, many := reads(1), reads(5); one != many {
			t.Errorf("%d outbound reads for one PR, %d for five: the walk must not scale with the anchors", one, many)
		}
	})

	t.Run("an anchor with no open blocker costs no read past its own edges", func(t *testing.T) {
		count := func(edges map[string][]*beads.IssueWithDependencyMetadata) int {
			st := store(edges)
			gatherPreOpen(t, st, "tk-pr")
			return st.depyN
		}
		bare := count(nil)
		landed := count(map[string][]*beads.IssueWithDependencyMetadata{"tk-pr": {blocksEdge(closed(rework()))}})
		if bare != landed {
			t.Errorf("%d outbound reads with no blocker, %d with a closed one: neither has anything to walk", bare, landed)
		}
		if bare != 1 {
			t.Errorf("%d outbound reads, want the pass's own: the walk starts from the anchor edges it already read", bare)
		}
	})
}

// TestMergeAnchorInFlightSetIsGathered: each live merge anchor carries its
// in-flight set, the beads `gctk pr-status derive` counts for the PR labels:
// every bead naming it in anchor_bead, any task_kind, at a live status. One read
// serves the pass, in the live pass only. So a PR whose merge pass recorded a
// thread verdict reads merging with nothing held on the board, as it does on its
// labels, while a validation pass the board shows no row for is in flight. A
// read that fails is noted partial, and the board then counts the review row it
// gathered.
func TestMergeAnchorInFlightSetIsGathered(t *testing.T) {
	at := testNow.Add(-time.Hour).Format(time.RFC3339)
	threads := `{"merge_result":"pull_request","pr_number":"9","pr_posture":"approved@abc@` + at +
		`","pr.machine":"blocked@abc@` + at + `","pr.machine_cause":"review-threads"}`
	doneAt := testNow.Add(-time.Hour)
	done := issue("tk-done", "a landed PR", "task", 2, testNow, `{"merge_result":"merged"}`)
	done.Status, done.ClosedAt = beads.StatusClosed, &doneAt
	store := func(children ...*beads.Issue) *fakeStore {
		return &fakeStore{issues: map[string][]*beads.Issue{"task": append([]*beads.Issue{
			issue("tk-pr", "an open PR", "task", 2, testNow, threads),
			issue("tk-gate", "a pre-open anchor", "task", 2, testNow, `{"merge_result":"pre_open_gate"}`),
			done,
		}, children...)}}
	}
	validation := reviewFixture("va-1", beads.StatusOpen, `{"task_kind":"validation","anchor_bead":"tk-pr"}`)
	children := []*beads.Issue{
		validation,
		reviewFixture("fi-1", beads.StatusBlocked, `{"task_kind":"finding","anchor_bead":"tk-pr"}`),
		reviewFixture("rw-closed", beads.StatusClosed, `{"task_kind":"rework","anchor_bead":"tk-pr"}`),
		reviewFixture("rv-gate", beads.StatusInProgress, `{"task_kind":"review","anchor_bead":"tk-gate"}`),
		reviewFixture("fi-gone", beads.StatusOpen, `{"task_kind":"finding","anchor_bead":"tk-done"}`),
	}
	inFlight := func(a board.Anchor) []string {
		var ids []string
		for _, c := range a.InFlight {
			ids = append(ids, c.ID+"/"+c.Status+"/"+c.Metadata["task_kind"])
		}
		slices.Sort(ids)
		return ids
	}
	pr := func(t *testing.T, b board.Board) board.Tile {
		t.Helper()
		i := slices.IndexFunc(b.Tiles, func(tl board.Tile) bool { return tl.ID == "tk-pr" })
		if i < 0 {
			t.Fatal("the PR anchor has no tile")
		}
		return b.Tiles[i]
	}

	st := store(children...)
	res, anchor := gatherPreOpen(t, st, "tk-pr")
	if got, want := inFlight(anchor), []string{"fi-1/blocked/finding", "va-1/open/validation"}; !slices.Equal(got, want) {
		t.Errorf("tk-pr in flight = %v, want %v: every live bead naming it, whatever its kind, and no closed one", got, want)
	}
	if i, ok := findAnchor(res, "tk-gate"); !ok || !slices.Equal(inFlight(res.Anchors[i]), []string{"rv-gate/in_progress/review"}) {
		t.Errorf("tk-gate in flight = %v, want its in_progress review", inFlight(res.Anchors[i]))
	}
	if i, ok := findAnchor(res, "tk-done"); !ok || res.Anchors[i].InFlight != nil {
		t.Errorf("a closed merge anchor gathers no in-flight set (found=%v)", ok)
	}
	var reads []beads.IssueFilter
	for _, c := range st.calls {
		if c.HasMetadataKey == "anchor_bead" {
			reads = append(reads, c)
		}
	}
	if len(reads) != 1 {
		t.Fatalf("in-flight reads = %d, want one for the pass whatever the number of anchors", len(reads))
	}
	if r := reads[0]; !slices.Equal(r.Statuses, anchorChildLiveStatuses) || !r.SkipWisps || !r.Lite {
		t.Errorf("the in-flight read must scope to the live statuses, skip wisps and read lite: %+v", r)
	}
	if tile := pr(t, board.BuildBoard(res.Anchors, testNow, res.Partial, res.PartialErrors, res.Facts)); tile.PRPhase != board.PhaseMerging || tile.PRHeld != nil {
		t.Errorf("a thread verdict beside a validation pass in flight: pr_phase=%q pr_held=%v, want merging and none", tile.PRPhase, tile.PRHeld)
	}

	// The twin with nothing in flight: the verdict holds the PR.
	res, _ = gatherPreOpen(t, store(), "tk-pr")
	if tile := pr(t, board.BuildBoard(res.Anchors, testNow, res.Partial, res.PartialErrors, res.Facts)); tile.PRPhase != board.PhaseNeedsAttention || !slices.Equal(tile.PRHeld, []string{"review"}) {
		t.Errorf("a thread verdict with nothing in flight: pr_phase=%q pr_held=%v, want needs-attention and [review]", tile.PRPhase, tile.PRHeld)
	}

	failing := store(reviewFixture("rv-1", beads.StatusOpen, `{"task_kind":"review","anchor_bead":"tk-pr"}`))
	failing.failMeta = map[string]error{"anchor_bead": errors.New("in-flight unreadable")}
	res, anchor = gatherPreOpen(t, failing, "tk-pr")
	if anchor.InFlight != nil {
		t.Errorf("a failed read gathers nothing: %v", inFlight(anchor))
	}
	if want := "in-flight@gc-toolkit: in-flight unreadable"; !res.Partial || !slices.Contains(res.PartialErrors, want) {
		t.Errorf("partial=%v errors=%v, want %q among them", res.Partial, res.PartialErrors, want)
	}
	if tile := pr(t, board.BuildBoard(res.Anchors, testNow, res.Partial, res.PartialErrors, res.Facts)); tile.PRPhase != board.PhaseMerging || tile.PRHeld != nil {
		t.Errorf("with the read failed, the review row still counts: pr_phase=%q pr_held=%v, want merging and none", tile.PRPhase, tile.PRHeld)
	}
}

// TestPRRowsCostNoCallPerPullRequest pins surface.md's cost argument, which is
// an acceptance criterion rather than an aspiration.
//
// Reading the conversation from GitHub for the fourteen pull requests open when
// the surface was designed took about twenty seconds against a 45-second cache
// TTL, so a cold render would spend half a cache generation inside `gh`. Worse,
// a single `gh pr list` reported mergeStateStatus=UNKNOWN for nine of those
// fourteen, because GitHub computes mergeability lazily — a surface deriving its
// state from that field would render two thirds of its rows unknown on a cold
// read and change its answer on the next one with nothing having happened.
//
// So the rows render from the bead, and the number of subprocesses a gather runs
// cannot grow with the number of pull requests. The gather's whole external
// surface is the gcClient; everything else is the store, opened in-process.
func TestPRRowsCostNoCallPerPullRequest(t *testing.T) {
	storeWith := func(n int) *fakeStore {
		anchors := make([]*beads.Issue, 0, n)
		for i := range n {
			id := fmt.Sprintf("tk-pr%02d", i)
			anchors = append(anchors, issue(id, "an open PR", "task", 2, testNow,
				fmt.Sprintf(`{"merge_result":"pull_request","pr_number":"%d","branch":"polecat/%s"}`, 500+i, id)))
		}
		return &fakeStore{issues: map[string][]*beads.Issue{"task": anchors}}
	}

	gather := func(n int) (anchors, calls int) {
		t.Helper()
		gc := &fakeGC{}
		root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
		src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": storeWith(n)},
			withGCClient(gc))
		res, err := src.Gather(context.Background())
		if err != nil {
			t.Fatalf("Gather(%d): %v", n, err)
		}
		return len(res.Anchors), gc.externalCalls()
	}

	oneAnchors, oneCalls := gather(1)
	manyAnchors, manyCalls := gather(25)

	if oneAnchors != 1 || manyAnchors != 25 {
		t.Fatalf("fixture no longer scales the rows: got %d and %d", oneAnchors, manyAnchors)
	}
	if manyCalls != oneCalls {
		t.Errorf("the gather spent %d external calls on 25 pull requests and %d on one — "+
			"a per-PR call is exactly what the bead is read to avoid", manyCalls, oneCalls)
	}
}
