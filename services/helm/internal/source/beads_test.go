package source

import (
	"context"
	"encoding/json"
	"errors"
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
	closed   bool
}

// SearchIssues answers both gather shapes: the type-keyed anchor queries, and
// the metadata-keyed ones tk-2v08m added. It APPLIES the filters rather than
// trusting them, because every one of them is load-bearing — a fake that
// returned its fixtures regardless would let the gather ask a wrong question
// and still pass.
func (f *fakeStore) SearchIssues(_ context.Context, _ string, filter beads.IssueFilter) ([]*beads.Issue, error) {
	// An id-keyed read is the one shape with no status scope, and that is the
	// point of it: the sitting gather resolves a subject bead whether or not it
	// has since closed. It is matched first so the scope rule below stays a
	// rule about the SEARCHES.
	if len(filter.IDs) > 0 {
		return f.searchByIDs(filter)
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
	//   Statuses=[open,inprog]   the JOIN queries (visits, workflow roots and
	//                            steps) — a CLAIMED visit is a held conversation,
	//                            not a finished one, and a claimed step is the
	//                            normal state of a live molecule.
	//
	// Anything else — no scope at all, or a widened one — is refused, so the
	// filter stays load-bearing rather than decorative.
	switch {
	case filter.Status != nil && *filter.Status == beads.StatusOpen && len(filter.Statuses) == 0:
	case filter.Status != nil && *filter.Status == beads.StatusClosed && len(filter.Statuses) == 0:
		if filter.ClosedAfter == nil {
			return nil, errors.New("a closed-bead query must bound its window with ClosedAfter")
		}
	case filter.Status == nil && slices.Equal(filter.Statuses, []beads.Status{beads.StatusOpen, beads.StatusInProgress}):
	default:
		return nil, errors.New("expected status=open (anchors), statuses=[open,in_progress] (joins) or status=closed+ClosedAfter (closed rows)")
	}
	if filter.IssueType != nil {
		kind := string(*filter.IssueType)
		if err, bad := f.failType[kind]; bad {
			return nil, err
		}
		return f.matching(f.issues[kind], filter), nil
	}
	out, err := f.searchByMetadata(filter)
	if err != nil {
		return nil, err
	}
	return f.matching(out, filter), nil
}

// searchByIDs models `id IN (...)`, which is what the shared SQL builder emits
// for IssueFilter.IDs.
func (f *fakeStore) searchByIDs(filter beads.IssueFilter) ([]*beads.Issue, error) {
	if err, bad := f.failMeta["__ids__"]; bad {
		return nil, err
	}
	want := map[string]bool{}
	for _, id := range filter.IDs {
		want[id] = true
	}
	var out []*beads.Issue
	for _, kind := range slices.Sorted(maps.Keys(f.issues)) { // deterministic order
		for _, iss := range f.issues[kind] {
			if want[iss.ID] {
				out = append(out, iss)
			}
		}
	}
	return out, nil
}

// matching applies the status and closed-window predicates the library applies
// in SQL. Without it the fake would hand an open-visit query the closed visits
// too: the two sitting passes could not be told apart, and the done pass would
// re-return every OPEN anchor as a closed one.
func (f *fakeStore) matching(in []*beads.Issue, filter beads.IssueFilter) []*beads.Issue {
	var out []*beads.Issue
	for _, iss := range in {
		if filter.Status != nil && iss.Status != *filter.Status {
			continue
		}
		if len(filter.Statuses) > 0 && !slices.Contains(filter.Statuses, iss.Status) {
			continue
		}
		if filter.ClosedAfter != nil && (iss.ClosedAt == nil || !iss.ClosedAt.After(*filter.ClosedAfter)) {
			continue
		}
		out = append(out, iss)
	}
	return out
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
	// not gathering anchors at all — they read visit beads and molecule steps,
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

func (f *fakeStore) GetDependenciesWithMetadata(_ context.Context, id string) ([]*beads.IssueWithDependencyMetadata, error) {
	if err, bad := f.failDeps[id]; bad {
		return nil, err
	}
	return f.depsDown[id], nil
}

func (f *fakeStore) GetDependentsWithMetadata(_ context.Context, id string) ([]*beads.IssueWithDependencyMetadata, error) {
	if err, bad := f.failDeps[id]; bad {
		return nil, err
	}
	return f.depsUp[id], nil
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
				issue("tk-cv", "real convoy", "convoy", 2, testNow.Add(-time.Hour), ""),
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
			// (tk-a9k0l, tk-2cyxo). The `tracks` edge is the visit convoy
			// pointing at the same bead: not a child.
			"tk-parked": {
				withDepType(child("tk-p1", "open", testNow, ""), "parent-child"),
				withDepType(child("tk-p2", "closed", testNow.Add(-24*time.Hour), ""), "parent-child"),
				withDepType(child("tk-visit", "open", testNow, ""), "tracks"),
			},
		},
		depsDown: map[string][]*beads.IssueWithDependencyMetadata{
			"tk-cv": {
				withDepType(child("tk-m1", "in_progress", testNow, ""), "tracks"),
				// A convoy's own blocks-edges are not membership.
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
			// An epic is banded by a child roll-up that already says whether
			// its work is moving, so its edges are deliberately NOT read.
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
	convoys  []convoyRow
	members  map[string]string // convoy id -> single tracked member
	err      error             // when set, every call fails with it
	memberN  int               // ConvoyMember call count
}

func (f *fakeGC) Sessions(context.Context) (map[string]string, error) {
	if f.err != nil {
		return nil, f.err
	}
	return f.sessions, nil
}

func (f *fakeGC) Convoys(context.Context) ([]convoyRow, error) {
	if f.err != nil {
		return nil, f.err
	}
	return f.convoys, nil
}

func (f *fakeGC) ConvoyMember(_ context.Context, id string) (string, error) {
	f.memberN++
	if f.err != nil {
		return "", f.err
	}
	return f.members[id], nil
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
		t.Errorf("children: got %v, want [tk-p1 tk-p2] — the tracks edge is membership, not a child", gotKids)
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
// the per-anchor dependency read.
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
// `epic` and `convoy` deliberately do not pay it: they are banded by a child
// roll-up that already reports whether their work is moving.
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
		{"tk-epic", "epic", nil, nil,
			"an epic is banded by its roll-up; it does not pay the extra read"},
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

// TestWaitingEdgeFailureIsUnknownNotEmpty is the fail-closed half of the read
// above: WHICH kinds pay it is pinned there, what a FAILED payment reports is
// pinned here.
//
// The per-anchor dependency query can fail on its own — a Dolt timeout, a
// schema skew — while the anchor query that found the row succeeded. The row is
// still gathered, because dropping it would hide work, so the only trace of the
// failure is what this reports about its edges. Report an empty set and the
// anchor is indistinguishable from one that genuinely has no waits, which is
// precisely the state board.ruled reads as "every recorded wait has landed":
// the answered row stands down because its graph could not be read (tk-fhd705).
func TestWaitingEdgeFailureIsUnknownNotEmpty(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	st := populatedStore()
	// Only the decision's read fails. The other two kinds that spend the edges
	// are the control: one anchor's failure must not mark the rest unknown, or
	// a single slow query quietly re-elevates half the board.
	st.failDeps = map[string]error{"tk-dec": errors.New("dolt timeout")}
	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": st})

	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	i, ok := findAnchor(res, "tk-dec")
	if !ok {
		t.Fatal("an anchor whose edge read fails must still appear")
	}
	dec := res.Anchors[i]
	if len(dec.WaitingOn) != 0 || len(dec.WaitingOnClosed) != 0 {
		t.Errorf("a failed read invents no edges: %v / %v", dec.WaitingOn, dec.WaitingOnClosed)
	}
	if !dec.WaitingUnknown {
		t.Error("a failed edge read must report UNKNOWN, not an empty wait set — " +
			"board.ruled cannot tell the two apart without it, and stands the row down")
	}
	if !res.Partial {
		t.Error("a failed edge read must set partial")
	}

	for _, id := range []string{"tk-human", "tk-parked"} {
		j, ok := findAnchor(res, id)
		if !ok {
			t.Fatalf("%s: anchor missing", id)
		}
		if res.Anchors[j].WaitingUnknown {
			t.Errorf("%s: one anchor's failed read must not mark another unknown", id)
		}
		if len(res.Anchors[j].WaitingOn) == 0 {
			t.Errorf("%s: the control anchors must still carry their real edges", id)
		}
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
		if strings.HasPrefix(e, "parked-visits@gc-toolkit") {
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
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk", "signal-loom": "sl"})
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
		"gc-toolkit":  populatedStore(),
		"signal-loom": broken,
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
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk", "signal-loom": ""})
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
	// Sorted by name, so gc-toolkit precedes signal-loom deterministically.
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
		{"hyphen.yaml", "issue-prefix: sl\n", "sl"},
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
		issue("tk-visit1", "visit: tk-epic — operator pick", "task", 2, testNow,
			`{"task_kind":"visit","gc.continuation_group":"tk-epic"}`),
		issue("tk-root1", "mol-polecat-work", "task", 2, testNow,
			`{"gc.input_convoy_id":"tk-icv1","gc.session_name":"gc-toolkit__polecat-lx-live"}`),
		// A root with NO session of its own: the name has to come off its steps.
		issue("tk-root2", "mol-polecat-work", "task", 2, testNow,
			`{"gc.input_convoy_id":"tk-icv2"}`),
		issue("tk-step2", "implement", "task", 2, testNow,
			`{"gc.root_bead_id":"tk-root2","gc.session_name":"gc-toolkit__polecat-lx-steps"}`),
		// A HUSK: an open root whose session is long gone. Joining on root
		// existence alone would flip it to "in flight".
		issue("tk-root3", "mol-polecat-work", "task", 2, testNow,
			`{"gc.input_convoy_id":"tk-icv3","gc.session_name":"gc-toolkit__polecat-lx-dead"}`),
	)
	return st
}

func liveGC() *fakeGC {
	return &fakeGC{
		sessions: map[string]string{
			"gc-toolkit__polecat-lx-live":  "active",
			"gc-toolkit__polecat-lx-steps": "active",
			"gc-toolkit__polecat-lx-dead":  "archived",
		},
		members: map[string]string{
			"tk-icv1": "tk-work1",
			"tk-icv2": "tk-work2",
			"tk-icv3": "tk-work3",
		},
	}
}

// TestGatherJoinsVisitsAndInflight is the whole point of the join gather: an
// open visit marks its subject held, and a LIVE workflow root resolves through
// its input convoy to the work bead it stands over.
func TestGatherJoinsVisitsAndInflight(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	gc := liveGC()
	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": joinStore()}, withGCClient(gc))

	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}

	if !res.Facts.Visits["tk-epic"] {
		t.Errorf("an open visit marks its subject held: visits=%v", res.Facts.Visits)
	}
	if got := res.Facts.Inflight["tk-work1"]; len(got) != 1 || got[0] != "gc-toolkit__polecat-lx-live" {
		t.Errorf("root with its own session_name resolves: got %v", got)
	}
	if got := res.Facts.Inflight["tk-work2"]; len(got) != 1 || got[0] != "gc-toolkit__polecat-lx-steps" {
		t.Errorf("root without a session_name falls back to its steps: got %v", got)
	}
	if got, ok := res.Facts.Inflight["tk-work3"]; ok {
		t.Errorf("a husk (archived session) must not read as in flight: got %v", got)
	}
	// Liveness is filtered BEFORE the convoy reads, so the husk costs no
	// subprocess at all — that bound is what keeps the gather proportional to
	// live polecats rather than to the husk pile.
	if gc.memberN != 2 {
		t.Errorf("convoy status called %d times, want 2 (live roots only)", gc.memberN)
	}
	if res.Facts.OwnerState["gc-toolkit__polecat-lx-live"] != "active" {
		t.Errorf("session states carried: %v", res.Facts.OwnerState)
	}
}

// TestGatherCarriesPrefixesAndDescription pins the two anchor-side inputs the
// cross-rig scan needs: every rig's prefix/name, and the anchor's prose.
func TestGatherCarriesPrefixesAndDescription(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk", "signal-loom": "sl"})
	src := newBeadsTestSource(t, root, map[string]*fakeStore{
		"gc-toolkit": populatedStore(), "signal-loom": {},
	})
	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	if !slices.Equal(res.Facts.Prefixes, []string{"sl", "tk"}) {
		t.Errorf("prefixes = %v, want [sl tk]", res.Facts.Prefixes)
	}
	if !slices.Equal(res.Facts.RigNames, []string{"gc-toolkit", "signal-loom"}) {
		t.Errorf("rig names = %v, want [gc-toolkit signal-loom]", res.Facts.RigNames)
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

// TestConvoyOwnershipJoin: `gc convoy list` decides whether a convoy is a normal
// row or the unowned-orphan exception, and an ABSENT answer must not be read as
// "unowned" — that would flag every convoy in the city the first time the call
// failed.
func TestConvoyOwnershipJoin(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})

	t.Run("unowned convoy flips kind", func(t *testing.T) {
		gc := liveGC()
		gc.convoys = []convoyRow{{ID: "tk-cv", Owned: false, Progress: &convoyProgress{Closed: 1, Total: 2}}}
		src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": populatedStore()}, withGCClient(gc))
		res, err := src.Gather(context.Background())
		if err != nil {
			t.Fatalf("Gather: %v", err)
		}
		i, ok := findAnchor(res, "tk-cv")
		if !ok {
			t.Fatal("tk-cv missing")
		}
		a := res.Anchors[i]
		if a.Kind != "unowned" || a.Source != "unowned" {
			t.Errorf("an unowned convoy is the orphan exception: kind=%q source=%q", a.Kind, a.Source)
		}
		if a.Owned == nil || *a.Owned {
			t.Errorf("owned=false carried: %v", a.Owned)
		}
		if a.Progress == nil || a.Progress.Total != 2 || a.Progress.Closed != 1 {
			t.Errorf("progress carried: %+v", a.Progress)
		}
	})

	t.Run("owned convoy stays a convoy", func(t *testing.T) {
		gc := liveGC()
		gc.convoys = []convoyRow{{ID: "tk-cv", Owned: true}}
		src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": populatedStore()}, withGCClient(gc))
		res, _ := src.Gather(context.Background())
		i, _ := findAnchor(res, "tk-cv")
		if res.Anchors[i].Kind != "convoy" {
			t.Errorf("kind = %q, want convoy", res.Anchors[i].Kind)
		}
		if res.Anchors[i].Owned == nil || !*res.Anchors[i].Owned {
			t.Errorf("owned=true carried: %v", res.Anchors[i].Owned)
		}
	})

	t.Run("absent ownership is not an orphan", func(t *testing.T) {
		gc := liveGC() // no convoy rows at all
		src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": populatedStore()}, withGCClient(gc))
		res, _ := src.Gather(context.Background())
		i, _ := findAnchor(res, "tk-cv")
		if res.Anchors[i].Kind != "convoy" {
			t.Errorf("an unlisted convoy keeps kind convoy, got %q", res.Anchors[i].Kind)
		}
		if res.Anchors[i].Owned != nil {
			t.Errorf("owned stays null when unknown, got %v", res.Anchors[i].Owned)
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
	// Visits do NOT come from gc, so they survive.
	if !res.Facts.Visits["tk-epic"] {
		t.Error("the visit join reads beads, not gc, so it must survive")
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
	if err := os.WriteFile(filepath.Join(hq, "config.yaml"), []byte("issue_prefix: lx\n"), 0o644); err != nil {
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
	if !slices.Contains(prefixes, "lx") {
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
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk", "signal-loom": "sl"})
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
	if !slices.Equal(tried, []string{"gc-toolkit", "signal-loom"}) {
		t.Errorf("Probe must try every rig before giving up, tried %v", tried)
	}
}

// TestBeadsProbeSucceedsOnOneReadableRig pins Probe's success condition to
// Gather's. Gather returns a board as long as ONE rig could be read, so a Probe
// that demanded all of them would refuse a backend that serves fine.
func TestBeadsProbeSucceedsOnOneReadableRig(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk", "signal-loom": "sl"})
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
	// it must not have looked past signal-loom.
	if !slices.Equal(tried, []string{"gc-toolkit", "signal-loom"}) {
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

// --- sittings --------------------------------------------------------------

// visitBead builds an OPEN visit bead: a sitting a converse session is holding.
func visitBead(id, title, meta string, created time.Time) *beads.Issue {
	i := issue(id, title, "task", 2, created, meta)
	i.CreatedAt = created
	return i
}

// closedVisitBead builds a FINISHED sitting. The close stamp is what the
// window filters on, so it is set explicitly rather than derived.
func closedVisitBead(id, title, meta string, created, closed time.Time) *beads.Issue {
	i := visitBead(id, title, meta, created)
	i.Status = beads.StatusClosed
	i.UpdatedAt = closed
	i.ClosedAt = &closed
	return i
}

// sittingStore is one subject visited three times, plus a fourth sitting whose
// close fell outside the window.
//
// The subject carries ONE takeaway, stamped at 09:55 — inside the middle
// sitting's span and outside the other two. That is the whole attribution
// question in fixture form: the takeaway on a bead belongs to the sitting that
// wrote it, and a subject visited more than once has sittings that did not.
func sittingStore() *fakeStore {
	at := func(h, m int) time.Time { return time.Date(2026, 8, 1, h, m, 0, 0, time.UTC) }
	return &fakeStore{failMeta: map[string]error{}, issues: map[string][]*beads.Issue{
		"task": {
			issue("tk-parked", "the subject three sittings talked about", "task", 2, at(9, 55),
				`{"gc.takeaway":"routed to the polecat pool","gc.takeaway_at":"2026-08-01T09:55:00Z","gc.takeaway_by":"converse"}`),
			issue("tk-quiet", "a subject nobody reached a takeaway on", "task", 2, at(7, 0), `{}`),
			issue("tk-settled", "a subject whose only sitting ended inside the window", "task", 2, at(9, 30), `{}`),

			visitBead("tk-sit-open", "visit: tk-parked — still talking",
				`{"task_kind":"visit","gc.continuation_group":"tk-parked","gc.claimed_at":"2026-08-01T11:00:00Z","gc.session_name":"gc-toolkit__converse-1"}`,
				at(10, 45)),
			closedVisitBead("tk-sit-recent", "visit: tk-parked — routed the work",
				`{"task_kind":"visit","gc.continuation_group":"tk-parked","gc.outcome":"diagnosed","gc.claimed_at":"2026-08-01T09:00:00Z","gc.session_name":"gc-toolkit__converse-2"}`,
				at(8, 55), at(10, 0)),
			closedVisitBead("tk-sit-earlier", "visit: tk-parked — nothing to do yet",
				`{"task_kind":"visit","gc.continuation_group":"tk-parked","gc.outcome":"folded","gc.claimed_at":"2026-08-01T06:00:00Z"}`,
				at(5, 55), at(7, 0)),
			// The Held control: one sitting, closed, inside the window. Nothing
			// holds tk-settled, and only a closed-sitting leak into the visit
			// join could say otherwise.
			closedVisitBead("tk-sit-settled", "visit: tk-settled — done and closed",
				`{"task_kind":"visit","gc.continuation_group":"tk-settled","gc.outcome":"benign","gc.claimed_at":"2026-08-01T09:30:00Z"}`,
				at(9, 25), at(9, 45)),
			// Closed 4 days before the pinned clock: inside the store, outside
			// any default window.
			closedVisitBead("tk-sit-old", "visit: tk-quiet — long since done",
				`{"task_kind":"visit","gc.continuation_group":"tk-quiet","gc.outcome":"moot"}`,
				time.Date(2026, 7, 28, 8, 0, 0, 0, time.UTC), time.Date(2026, 7, 28, 9, 0, 0, 0, time.UTC)),
		},
	}}
}

func sittingsByID(res *Result) map[string]board.Sitting {
	out := map[string]board.Sitting{}
	for _, s := range res.Facts.Sittings {
		out[s.ID] = s
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

// TestGatherRecordsSittings: the record carries running sittings and those
// closed inside the window, and nothing older.
func TestGatherRecordsSittings(t *testing.T) {
	got := sittingsByID(gatherSittings(t))

	for _, want := range []string{"tk-sit-open", "tk-sit-recent", "tk-sit-earlier"} {
		if _, ok := got[want]; !ok {
			t.Errorf("%s missing from the sitting record: got %v", want, slices.Sorted(maps.Keys(got)))
		}
	}
	if _, ok := got["tk-sit-old"]; ok {
		t.Error("a sitting closed outside the window must not be gathered — the window is what bounds an unbounded read")
	}

	open := got["tk-sit-open"]
	if open.Status != "open" || !open.ClosedAt.IsZero() {
		t.Errorf("a running sitting has no close stamp: status=%q closed=%v", open.Status, open.ClosedAt)
	}
	if want := time.Date(2026, 8, 1, 11, 0, 0, 0, time.UTC); !open.OpenedAt.Equal(want) {
		t.Errorf("OpenedAt = %v, want the gc.claimed_at stamp %v", open.OpenedAt, want)
	}
	if open.Session != "gc-toolkit__converse-1" || open.Subject != "tk-parked" || open.Rig != "gc-toolkit" {
		t.Errorf("sitting identity: %+v", open)
	}

	done := got["tk-sit-recent"]
	if done.Status != "closed" || done.Outcome != "diagnosed" {
		t.Errorf("a closed sitting carries the justification it closed on: status=%q outcome=%q", done.Status, done.Outcome)
	}
	if want := time.Date(2026, 8, 1, 10, 0, 0, 0, time.UTC); !done.ClosedAt.Equal(want) {
		t.Errorf("ClosedAt = %v, want %v", done.ClosedAt, want)
	}

	// A visit that never got a claim stamp still has to say when it started.
	if fallback := got["tk-sit-old"]; fallback.ID != "" {
		t.Fatal("guarded above")
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

// TestSittingWindowIsConfigurable: the knob widens the closed half, and zero
// turns it off without touching the running half.
func TestSittingWindowIsConfigurable(t *testing.T) {
	t.Setenv("GC_HELM_SITTINGS_WINDOW", "120h")
	if _, ok := sittingsByID(gatherSittings(t))["tk-sit-old"]; !ok {
		t.Error("a wider window reaches further back")
	}

	t.Setenv("GC_HELM_SITTINGS_WINDOW", "0s")
	got := sittingsByID(gatherSittings(t))
	if _, ok := got["tk-sit-recent"]; ok {
		t.Error("a zero window gathers no closed sittings")
	}
	if _, ok := got["tk-sit-open"]; !ok {
		t.Error("a zero window must not cost the board its RUNNING sittings")
	}

	t.Setenv("GC_HELM_SITTINGS_WINDOW", "not-a-duration")
	if _, ok := sittingsByID(gatherSittings(t))["tk-sit-recent"]; !ok {
		t.Error("an unparseable window falls back to the default rather than emptying the section")
	}
}

// TestOnlyRunningSittingsHoldTheirAnchor: Tile.Held is a claim about a LIVE
// conversation, so the closed half of the record must not feed it.
func TestOnlyRunningSittingsHoldTheirAnchor(t *testing.T) {
	res := gatherSittings(t)
	if !res.Facts.Visits["tk-parked"] {
		t.Error("a subject with a running sitting is held")
	}
	if res.Facts.Visits["tk-settled"] {
		t.Error("a subject whose only sitting has CLOSED is not held — the conversation ended")
	}
	if res.Facts.Visits["tk-quiet"] {
		t.Error("a subject whose sitting fell outside the window is not held either")
	}
}

// TestSittingPassesDegradeIndependently: neither half of the record may take
// the other down, and Tile.Held must survive losing the closed pass.
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
	if len(got) != 4 {
		t.Errorf("an unreadable subject narrows the rows, it does not drop them: got %d", len(got))
	}
	if s := got["tk-sit-recent"]; s.Takeaway != "" || s.Outcome != "diagnosed" {
		t.Errorf("the sitting keeps what it owns and loses only the joined headline: %+v", s)
	}
	if !res.Partial {
		t.Error("a failed subject read is reported as partial")
	}
}

// ── The done pass ────────────────────────────────────────────────────────
//
// The anchor queries ask for open beads, so a closing anchor leaves the board
// on the next gather unless something else keeps it. These pin the second pass
// that does, and the two things that bound it.

// doneStore is one rig's worth of recently closed anchors: one inside the
// window, one outside it, and one inside it that the operator has dismissed.
func doneStore() *fakeStore {
	return &fakeStore{
		issues: map[string][]*beads.Issue{
			"epic": {
				issue("tk-live", "still open", "epic", 2, testNow.Add(-time.Hour), ""),
				closedIssue("tk-fresh", "closed yesterday", "epic", 2,
					testNow.Add(-24*time.Hour), testNow.Add(-24*time.Hour), ""),
				closedIssue("tk-ancient", "closed last month", "epic", 2,
					testNow.Add(-30*24*time.Hour), testNow.Add(-30*24*time.Hour), ""),
				closedIssue("tk-gone", "closed yesterday, dismissed since", "epic", 2,
					testNow.Add(-24*time.Hour), testNow.Add(-24*time.Hour),
					`{"gc.dismissed_at":"2026-08-01T09:00:00Z","gc.dismissed_by":"operator"}`),
			},
			"bug": {
				closedIssue("tk-subject", "a conversation subject that closed", "bug", 2,
					testNow.Add(-2*time.Hour), testNow.Add(-2*time.Hour),
					`{"gc.takeaway":"settled — nothing further"}`),
				// Dismissed while it was closed, then REOPENED. It is live work
				// again and the stale marker must not follow it.
				issue("tk-reopened", "dismissed, then reopened", "bug", 1, testNow.Add(-time.Hour),
					`{"gc.takeaway":"back open","gc.dismissed_at":"2026-07-30T09:00:00Z"}`),
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

func TestGatherBoundsAndDismissesTheDoneBand(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": doneStore()})

	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	if _, ok := findAnchor(res, "tk-ancient"); ok {
		t.Error("the window bounds the pass: an anchor closed a month ago is history, not layout")
	}
	if _, ok := findAnchor(res, "tk-gone"); ok {
		t.Error("gc.dismissed_at is the operator's explicit clear; a dismissed row must not come back")
	}
}

// The marker retires a DONE row and nothing else. A dismissed anchor that is
// later reopened is live work, and hiding it would be the same disappearance
// the band exists to stop, with a stale marker as the cause.
func TestDismissMarkerDoesNotHideALiveAnchor(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": doneStore()})

	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	i, ok := findAnchor(res, "tk-reopened")
	if !ok {
		t.Fatal("a reopened anchor carrying a stale gc.dismissed_at is live work and belongs on the board")
	}
	if !res.Anchors[i].ClosedAt.IsZero() {
		t.Error("...and reads as live, not DONE")
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
