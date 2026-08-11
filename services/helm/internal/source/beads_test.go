package source

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/steveyegge/beads"
)

// fakeStore is a beadStore over in-memory fixtures. It stands in for a real
// rig's Dolt-backed store so Gather is exercised without a live city.
type fakeStore struct {
	issues   map[string][]*beads.Issue                       // keyed by issue type
	depsDown map[string][]*beads.IssueWithDependencyMetadata // convoy -> tracked members
	depsUp   map[string][]*beads.IssueWithDependencyMetadata // epic -> parent-child children
	failType map[string]error                                // issue type -> forced SearchIssues error
	failDeps map[string]error                                // issue id -> forced dependency error
	closed   bool
}

func (f *fakeStore) SearchIssues(_ context.Context, _ string, filter beads.IssueFilter) ([]*beads.Issue, error) {
	if filter.IssueType == nil {
		return nil, errors.New("test fake requires an issue type filter")
	}
	kind := string(*filter.IssueType)
	if err, bad := f.failType[kind]; bad {
		return nil, err
	}
	// The source must ask for OPEN anchors only; a fake that ignored the filter
	// would let a regression through silently.
	if filter.Status == nil || *filter.Status != beads.StatusOpen {
		return nil, errors.New("expected a status=open filter on the anchor query")
	}
	return f.issues[kind], nil
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
// closed), a decision, a real convoy with a tracked member, and the two machine
// convoys that must be filtered out.
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
		},
		depsUp: map[string][]*beads.IssueWithDependencyMetadata{
			"tk-epic": {
				withDepType(child("tk-a", "open", testNow.Add(-3*24*time.Hour), `{"gc.routed_to":"human"}`), "parent-child"),
				withDepType(child("tk-b", "closed", testNow.Add(-9*24*time.Hour), ""), "parent-child"),
				// A non-parent-child edge into the same epic must not be counted.
				withDepType(child("tk-ref", "open", testNow, ""), "related"),
			},
		},
		depsDown: map[string][]*beads.IssueWithDependencyMetadata{
			"tk-cv": {
				withDepType(child("tk-m1", "in_progress", testNow, ""), "tracks"),
				// A convoy's own blocks-edges are not membership.
				withDepType(child("tk-m2", "open", testNow, ""), "blocks"),
			},
		},
	}
}

func newBeadsTestSource(t *testing.T, root string, stores map[string]*fakeStore) *BeadsSource {
	t.Helper()
	return NewBeadsSource(
		WithCityPath(root),
		withStoreOpener(func(_ context.Context, beadsDir string) (beadStore, error) {
			rig := filepath.Base(filepath.Dir(beadsDir))
			st, ok := stores[rig]
			if !ok {
				return nil, errors.New("no fixture store for rig " + rig)
			}
			return st, nil
		}),
	)
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
	if len(res.Anchors) != 3 {
		ids := []string{}
		for _, a := range res.Anchors {
			ids = append(ids, a.ID)
		}
		t.Fatalf("want 3 anchors (epic, decision, real convoy), got %d: %v", len(res.Anchors), ids)
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

// TestBeadsGatherDegradesPerRig mirrors SupervisorSource's contract: one rig
// failing must not lose the others, and it must be recorded as partial.
func TestBeadsGatherDegradesPerRig(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk", "signal-loom": "sl"})
	broken := &fakeStore{failType: map[string]error{
		"epic":     errors.New("dolt timeout"),
		"decision": errors.New("dolt timeout"),
		"convoy":   errors.New("dolt timeout"),
	}}
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
