package source

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"reflect"
	"sort"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/board"
)

// mockSupervisor returns an httptest server speaking the subset of the supervisor
// API the source consumes. Routing mirrors the real path scoping
// (/v0/city/<city>/...). failPaths maps a path to a status code to force an
// error for partial/degradation tests.
func mockSupervisor(t *testing.T, failStatus map[string]int) *httptest.Server {
	t.Helper()
	const base = "/v0/city/testcity"
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		path := r.URL.Path
		if code, bad := failStatus[path]; bad {
			w.WriteHeader(code)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		switch {
		case path == base+"/rigs":
			writeJSON(w, `{"items":[{"name":"gc-toolkit","prefix":"tk"},{"name":"signal-loom","prefix":"sl"}]}`)
		case path == base+"/beads" && r.URL.Query().Get("type") == "epic":
			writeJSON(w, `{"items":[{"id":"tk-epic","title":"Big epic","status":"open","issue_type":"epic","priority":2}],"total":1}`)
		case path == base+"/beads" && r.URL.Query().Get("type") == "decision":
			writeJSON(w, `{"items":[{"id":"sl-dec","title":"Pick a path","status":"open","issue_type":"decision","priority":1}],"total":1}`)
		// Gates are hidden from the bare status=open scan, so the source pages
		// them separately (type=gate). Empty in the shared fixture; the
		// gate-demand case has its own test.
		case path == base+"/beads" && r.URL.Query().Get("type") == "gate":
			writeJSON(w, `{"items":[],"total":0}`)
		case path == base+"/beads/graph/tk-epic":
			writeJSON(w, `{"root":{"id":"tk-epic","status":"open","issue_type":"epic"},
				"beads":[{"id":"tk-epic","status":"open"},{"id":"tk-a","status":"open"},{"id":"tk-b","status":"closed"}],
				"deps":[{"from":"tk-epic","to":"tk-a","kind":"parent-child"},{"from":"tk-epic","to":"tk-b","kind":"parent-child"}]}`)
		// The open-bead scan. Deliberately TWO pages, so the cursor loop is
		// exercised rather than assumed, and deliberately noisy: typed kinds,
		// infra beads and an ephemeral wisp all carry the markers here, each a
		// bead the filter has to refuse for a different reason.
		case path == base+"/beads" && r.URL.Query().Get("status") == "open":
			// A cursor-keyed failure hook, so a page that dies AFTER earlier
			// ones succeeded is reachable.
			if code, bad := failStatus["cursor:"+r.URL.Query().Get("cursor")]; bad {
				w.WriteHeader(code)
				return
			}
			if r.URL.Query().Get("cursor") == "" {
				writeJSON(w, `{"items":[
					{"id":"tk-human","title":"routed out","status":"open","issue_type":"task","priority":1,
					 "metadata":{"gc.routed_to":"human"}},
					{"id":"tk-parked","title":"a sitting ended","status":"open","issue_type":"task",
					 "metadata":{"gc.takeaway":"held for your ruling","gc.takeaway_at":"2026-08-26T08:37:43Z","gc.takeaway_by":"converse"}},
					{"id":"tk-both","title":"routed AND parked","status":"open","issue_type":"bug",
					 "metadata":{"gc.routed_to":"human","gc.takeaway":"ruling owed"}},
					{"id":"tk-epic","title":"Big epic","status":"open","issue_type":"epic",
					 "metadata":{"gc.routed_to":"human"}},
					{"id":"lx-sess","title":"a session record","status":"open","issue_type":"session",
					 "metadata":{"gc.takeaway":"not work"}},
					{"id":"tk-mail","title":"agent mail","status":"open","issue_type":"message","ephemeral":true,
					 "metadata":{"gc.takeaway":"not work either"}}
				],"next_cursor":"page2"}`)
				return
			}
			writeJSON(w, `{"items":[
				{"id":"sl-kid","title":"open child of tk-human","status":"open","issue_type":"task",
				 "assignee":"polecat-live",
				 "dependencies":[{"issue_id":"sl-kid","depends_on_id":"tk-human","type":"parent-child"}]},
				{"id":"tk-plain","title":"ordinary work","status":"open","issue_type":"task"},
				{"id":"tk-cv","title":"real convoy","status":"open","issue_type":"convoy",
				 "metadata":{"gc.takeaway":"typed kinds are gathered by type"}},
				{"id":"tk-boolmd","title":"non-string metadata value","status":"open","issue_type":"task",
				 "metadata":{"gc.routed_to":"human","upstream_pr_candidate":true,"dispatch_count":3}}
			],"total":4}`)
		case path == base+"/convoys":
			// tk-inputcv mirrors the live API shape for a per-sling input
			// wrapper: title "input convoy for ...", and crucially NO `parent`
			// field (the live /convoys feed omits it). It must be excluded by
			// the title prefix alone, not by the parent check.
			writeJSON(w, `{"items":[
				{"id":"tk-cv","title":"real convoy","status":"open","issue_type":"convoy","parent":""},
				{"id":"tk-sling","title":"sling-tk-x","status":"open","issue_type":"convoy","parent":""},
				{"id":"tk-child-cv","title":"child convoy","status":"open","issue_type":"convoy","parent":"tk-epic"},
				{"id":"tk-inputcv","title":"input convoy for tk-sy3vj","status":"open","issue_type":"convoy"}
			],"total":4}`)
		case path == base+"/convoy/tk-cv":
			writeJSON(w, `{"convoy":{"id":"tk-cv","status":"open"},"children":[{"id":"cv1","status":"open"},{"id":"cv2","status":"in_progress"}],"progress":{"total":2,"closed":0}}`)
		default:
			http.Error(w, "unexpected path: "+path+"?"+r.URL.RawQuery, http.StatusNotFound)
		}
	}))
	t.Cleanup(srv.Close)
	return srv
}

func writeJSON(w http.ResponseWriter, body string) { _, _ = w.Write([]byte(body)) }

func newTestSource(t *testing.T, srv *httptest.Server) *SupervisorSource {
	// withSupervisorGCClient is not optional hygiene: without it this source
	// shells out to the real `gc` for session liveness, against whatever city
	// happens to be running on the developer's box.
	return NewSupervisorSource(WithBaseURL(srv.URL), WithCity("testcity"), WithHTTPClient(srv.Client()),
		withSupervisorGCClient(&fakeGC{sessions: map[string]string{"polecat-live": "active"}}))
}

func anchorByID(res *Result, id string) (have bool, kind, rig string, mTotal, nClosed int) {
	for _, a := range res.Anchors {
		if a.ID == id {
			closed := 0
			for _, c := range a.Children {
				if c.Status == "closed" {
					closed++
				}
			}
			return true, a.Kind, a.Rig, len(a.Children), closed
		}
	}
	return false, "", "", 0, 0
}

func TestGatherMapsAllKinds(t *testing.T) {
	srv := mockSupervisor(t, nil)
	res, err := newTestSource(t, srv).Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	if res.Partial {
		t.Errorf("unexpected partial: %v", res.PartialErrors)
	}
	// Three typed anchors plus five metadata-keyed ones; tk-both is admitted
	// under BOTH kinds.
	if len(res.Anchors) != 8 {
		ids := []string{}
		for _, a := range res.Anchors {
			ids = append(ids, a.ID+":"+a.Kind)
		}
		t.Fatalf("want 8 anchors, got %d: %v", len(res.Anchors), ids)
	}

	// Epic: rig resolved from prefix, direct children rolled up incl. closed.
	if ok, kind, rig, m, closed := anchorByID(res, "tk-epic"); !ok || kind != "epic" || rig != "gc-toolkit" || m != 2 || closed != 1 {
		t.Errorf("epic anchor wrong: ok=%v kind=%s rig=%s m=%d closed=%d", ok, kind, rig, m, closed)
	}
	// Decision: rig from the sl prefix.
	if ok, kind, rig, _, _ := anchorByID(res, "sl-dec"); !ok || kind != "decision" || rig != "signal-loom" {
		t.Errorf("decision anchor wrong: ok=%v kind=%s rig=%s", ok, kind, rig)
	}
	// Convoy: only the owned, floating, non-sling convoy; 2 children.
	if ok, kind, _, m, _ := anchorByID(res, "tk-cv"); !ok || kind != "convoy" || m != 2 {
		t.Errorf("convoy anchor wrong: ok=%v kind=%s m=%d", ok, kind, m)
	}
	if ok, _, _, _, _ := anchorByID(res, "tk-sling"); ok {
		t.Error("sling- convoy must be filtered out")
	}
	if ok, _, _, _, _ := anchorByID(res, "tk-child-cv"); ok {
		t.Error("non-floating (parented) convoy must be filtered out")
	}
	// The per-sling "input convoy for ..." machine wrapper carries no parent in
	// the live feed, so only the title-prefix filter excludes it.
	if ok, _, _, _, _ := anchorByID(res, "tk-inputcv"); ok {
		t.Error("input convoy machine wrapper must be filtered out")
	}
}

func TestGatherDegradesOnPartialFailure(t *testing.T) {
	// The /beads path (epics and decisions share it) fails; the independent
	// /convoys path still gathers and partial is recorded.
	srv := mockSupervisor(t, map[string]int{"/v0/city/testcity/beads": http.StatusInternalServerError})
	res, err := newTestSource(t, srv).Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather should not hard-fail on a partial: %v", err)
	}
	if !res.Partial {
		t.Error("expected partial=true when an endpoint fails")
	}
	if len(res.PartialErrors) == 0 {
		t.Error("expected partial errors recorded")
	}
	// The convoy path is independent of /beads, so its anchor still gathers.
	if ok, _, _, _, _ := anchorByID(res, "tk-cv"); !ok {
		t.Error("convoy anchor should still gather despite the /beads failure")
	}
	// And the epic, whose list lives under /beads, is correctly dropped.
	if ok, _, _, _, _ := anchorByID(res, "tk-epic"); ok {
		t.Error("epic anchor should be absent when the /beads list fails")
	}
}

func TestGatherErrorsOnTotalOutage(t *testing.T) {
	// A server that 500s every request stands in for a fully unreachable
	// supervisor: no fetch succeeds, so Gather must error (server -> 502) rather
	// than return an empty board that reads as "nothing needs attention".
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	t.Cleanup(srv.Close)
	if _, err := newTestSource(t, srv).Gather(context.Background()); err == nil {
		t.Error("expected an error when every fetch fails (total outage)")
	}
}

func TestDiscoverCityFromURLPrefix(t *testing.T) {
	t.Setenv("GC_HELM_CITY", "")
	t.Setenv("GC_SERVICE_URL_PREFIX", "/v0/city/loomington/svc/helm")
	if got := discoverCity(); got != "loomington" {
		t.Errorf("discoverCity from URL prefix = %q, want loomington", got)
	}
}

// TestSupervisorSourceCarriesSessionLiveness: no supervisor endpoint reports
// session state, and the derivation reads a claimed child with no known owner
// as an ORPHAN. Leaving Facts.OwnerState empty on this backend would therefore
// not narrow the board, it would INVERT it — every claim in the city would band
// HIGH. So this backend reads liveness through `gc` like the other one.
func TestSupervisorSourceCarriesSessionLiveness(t *testing.T) {
	src := newTestSource(t, mockSupervisor(t, nil))
	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	if res.Facts.OwnerState["polecat-live"] != "active" {
		t.Errorf("session states must reach Facts: %v", res.Facts.OwnerState)
	}
	// The rig roster feeds the cross-rig scan on this backend too.
	if len(res.Facts.Prefixes) == 0 || len(res.Facts.RigNames) == 0 {
		t.Errorf("rig prefixes/names must reach Facts: %v / %v", res.Facts.Prefixes, res.Facts.RigNames)
	}
}

// TestSupervisorSourceWithoutGCDegradesLoudly: losing `gc` here must narrow the
// board and SAY SO, not fail the gather — the anchors are still real.
func TestSupervisorSourceWithoutGCDegradesLoudly(t *testing.T) {
	srv := mockSupervisor(t, nil)
	src := NewSupervisorSource(WithBaseURL(srv.URL), WithCity("testcity"), WithHTTPClient(srv.Client()),
		withSupervisorGCClient(&fakeGC{err: errors.New("gc binary not found")}))

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
	var named bool
	for _, e := range res.PartialErrors {
		if strings.Contains(e, "session liveness unavailable") {
			named = true
		}
	}
	if !named {
		t.Errorf("the degradation must name itself: %v", res.PartialErrors)
	}
}

// kindsOf returns every kind the gather admitted the id under, so a bead
// carrying two markers can be told from one carrying one.
func kindsOf(res *Result, id string) []string {
	var out []string
	for _, a := range res.Anchors {
		if a.ID == id {
			out = append(out, a.Kind)
		}
	}
	sort.Strings(out)
	return out
}

func anchorOf(res *Result, id, kind string) *board.Anchor {
	for i := range res.Anchors {
		if res.Anchors[i].ID == id && res.Anchors[i].Kind == kind {
			return &res.Anchors[i]
		}
	}
	return nil
}

// TestGatherAdmitsMetadataKeyedKinds: this backend serves the board whenever
// helm-svc's embedded beads library is behind the stores' schema, so a kind it
// does not gather is a kind the operator loses.
func TestGatherAdmitsMetadataKeyedKinds(t *testing.T) {
	res, err := newTestSource(t, mockSupervisor(t, nil)).Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}

	if got := kindsOf(res, "tk-human"); !reflect.DeepEqual(got, []string{"human"}) {
		t.Errorf("tk-human kinds = %v, want [human]", got)
	}
	if got := kindsOf(res, "tk-parked"); !reflect.DeepEqual(got, []string{"parked"}) {
		t.Errorf("tk-parked kinds = %v, want [parked]", got)
	}
	// Both markers, both kinds; BuildBoard's id-dedup reconciles them.
	if got := kindsOf(res, "tk-both"); !reflect.DeepEqual(got, []string{"human", "parked"}) {
		t.Errorf("tk-both kinds = %v, want [human parked]", got)
	}

	// The takeaway triple is what the tile spends as its NEEDS sentence.
	parked := anchorOf(res, "tk-parked", "parked")
	if parked == nil {
		t.Fatal("tk-parked missing")
	}
	if parked.Takeaway != "held for your ruling" || parked.TakeawayAt == "" || parked.TakeawayBy != "converse" {
		t.Errorf("takeaway triple not carried: %q / %q / %q", parked.Takeaway, parked.TakeawayAt, parked.TakeawayBy)
	}
	// Rig and prefix resolve from the id the same way the typed kinds do.
	if parked.Rig != "gc-toolkit" || parked.Prefix != "tk" {
		t.Errorf("rig/prefix = %s/%s, want gc-toolkit/tk", parked.Rig, parked.Prefix)
	}
	// Unknown is not the same as none: board.ruled fires ON the empty set, so
	// reporting "no waits" would stand a row down on evidence nobody gathered.
	if !parked.WaitingUnknown {
		t.Error("a backend that does not resolve blocker statuses must say the edges are unknown")
	}

	// Children come from inverting the scan's own parent-child edges.
	human := anchorOf(res, "tk-human", "human")
	if human == nil {
		t.Fatal("tk-human missing")
	}
	if len(human.Children) != 1 || human.Children[0].ID != "sl-kid" {
		t.Errorf("tk-human children = %+v, want [sl-kid]", human.Children)
	}
	if human.Children[0].Assignee != "polecat-live" {
		t.Errorf("a child's assignee is half the dead-owner join: %+v", human.Children[0])
	}

	// A non-string metadata value must not blank the bead, or the whole PAGE it
	// arrived on, which is what a strict map[string]string decode would do.
	boolmd := anchorOf(res, "tk-boolmd", "human")
	if boolmd == nil {
		t.Fatal("a bead with a non-string metadata value must still be admitted")
	}
	if boolmd.Metadata["upstream_pr_candidate"] != "true" || boolmd.Metadata["dispatch_count"] != "3" {
		t.Errorf("non-string metadata must be coerced, not dropped: %v", boolmd.Metadata)
	}
}

// TestGatherRefusesNonWorkBeads pins the three separate reasons a bead carrying
// a marker is still not an anchor. Dropping any one of them puts a row on the
// board that is not work.
func TestGatherRefusesNonWorkBeads(t *testing.T) {
	res, err := newTestSource(t, mockSupervisor(t, nil)).Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	// Already gathered BY TYPE: re-admitting it would put the same bead on the
	// board twice under two kinds.
	if got := kindsOf(res, "tk-epic"); !reflect.DeepEqual(got, []string{"epic"}) {
		t.Errorf("tk-epic kinds = %v, want [epic] — a typed anchor must not be re-admitted", got)
	}
	if got := kindsOf(res, "tk-cv"); !reflect.DeepEqual(got, []string{"convoy"}) {
		t.Errorf("tk-cv kinds = %v, want [convoy]", got)
	}
	// Infrastructure, not work: the beads backend drops these with SkipWisps.
	// The supervisor list flags only part of the wisp side `ephemeral`.
	if got := kindsOf(res, "lx-sess"); len(got) != 0 {
		t.Errorf("a session record is not an anchor, got %v", got)
	}
	// Flagged ephemeral by the API itself.
	if got := kindsOf(res, "tk-mail"); len(got) != 0 {
		t.Errorf("an ephemeral wisp is not an anchor, got %v", got)
	}
	// And an ordinary bead with no marker stays off the board.
	if got := kindsOf(res, "tk-plain"); len(got) != 0 {
		t.Errorf("an unmarked bead is not an anchor, got %v", got)
	}
}

// TestGatherAdmitsGateBackedHumanDemand: a human demand is now a native gate
// (issue_type=gate, gc.routed_to=human, from gc-helm.sh `demand`), which the
// bare status=open scan hides. The source must page it via type=gate and admit
// it as a `human` anchor — matching the in-process backend, whose metadata-keyed
// query has no default type exclusion. A gate WITHOUT the marker is not an
// anchor: the type is not the key, the marker is.
func TestGatherAdmitsGateBackedHumanDemand(t *testing.T) {
	const base = "/v0/city/testcity"
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		q := r.URL.Query()
		switch {
		case r.URL.Path == base+"/rigs":
			writeJSON(w, `{"items":[{"name":"gc-toolkit","prefix":"tk"}]}`)
		case r.URL.Path == base+"/beads" && q.Get("type") == "gate":
			writeJSON(w, `{"items":[
				{"id":"tk-gate-demand","title":"operator: pick the backend","status":"open","issue_type":"gate","priority":1,
				 "metadata":{"gc.routed_to":"human","gc.demand_for":"tk-work","gc.demand_kind":"decision"}},
				{"id":"tk-gate-bare","title":"a gate carrying no demand marker","status":"open","issue_type":"gate"}
			],"total":2}`)
		default:
			// Every other Gather leg — the typed scans, the base open scan, the
			// convoy feed — reads empty, isolating the gate path.
			writeJSON(w, `{"items":[]}`)
		}
	}))
	t.Cleanup(srv.Close)

	res, err := newTestSource(t, srv).Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	if res.Partial {
		t.Errorf("unexpected partial: %v", res.PartialErrors)
	}
	// The gate-backed demand reaches the human filter despite being hidden from
	// the bare status=open scan — the divergence this fixes.
	if got := kindsOf(res, "tk-gate-demand"); !reflect.DeepEqual(got, []string{"human"}) {
		t.Errorf("tk-gate-demand kinds = %v, want [human] — a gate-backed human demand must gather", got)
	}
	human := anchorOf(res, "tk-gate-demand", "human")
	if human == nil {
		t.Fatal("tk-gate-demand missing")
	}
	if human.Rig != "gc-toolkit" || human.Prefix != "tk" {
		t.Errorf("rig/prefix = %s/%s, want gc-toolkit/tk", human.Rig, human.Prefix)
	}
	if got := kindsOf(res, "tk-gate-bare"); len(got) != 0 {
		t.Errorf("a gate without gc.routed_to=human is not an anchor, got %v", got)
	}
}

// TestOpenBeadsPagesToTheEnd: tk-boolmd lives on page two. A gather that stopped
// at the first page would look healthy and silently lose every bead past the
// hundredth.
func TestOpenBeadsPagesToTheEnd(t *testing.T) {
	res, err := newTestSource(t, mockSupervisor(t, nil)).Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	if anchorOf(res, "tk-boolmd", "human") == nil {
		t.Error("an anchor on the second page must be gathered")
	}
	if res.Partial {
		t.Errorf("a complete two-page scan is not partial: %v", res.PartialErrors)
	}
}

// TestMetadataAnchorPredicateMatchesTheStoreFilter: matches() is the
// client-side reading of the same selector the beads backend hands to the
// store. If the two disagree, a bead is an anchor on one backend and absent
// from the other.
func TestMetadataAnchorPredicateMatchesTheStoreFilter(t *testing.T) {
	var human, parked metadataAnchor
	for _, ma := range metadataAnchors {
		switch ma.kind {
		case "human":
			human = ma
		case "parked":
			parked = ma
		}
	}
	if human.value == "" || parked.value != "" {
		t.Fatalf("kinds changed shape: human selects on value %q, parked on presence %q", human.value, parked.value)
	}

	// A value-keyed kind is exact: a bead routed to an AGENT is not the
	// operator's.
	if !human.matches(map[string]string{"gc.routed_to": "human"}) {
		t.Error("gc.routed_to=human must match the human kind")
	}
	if human.matches(map[string]string{"gc.routed_to": "gc-toolkit/gc-toolkit.polecat"}) {
		t.Error("a route to an agent is not a route to the operator")
	}
	if human.matches(map[string]string{}) {
		t.Error("an absent key must not match")
	}

	// A key-only kind is PRESENCE. bd round-trips an empty metadata value and
	// decodeMetadata keeps the key for one, so a blanked takeaway still marks
	// the bead parked — the reading the store filter's HasMetadataKey has.
	if !parked.matches(map[string]string{"gc.takeaway": ""}) {
		t.Error("a present-but-empty takeaway must still match: the store filter tests presence")
	}
	if parked.matches(map[string]string{"gc.takeaway_at": "2026-08-26T00:00:00Z"}) {
		t.Error("a neighbouring key must not match")
	}

	// The merge kind, also presence-keyed. Keyed on merge_result rather than on
	// pr_number because an anchor at pre_open_gate has a machine axis and no
	// number yet, and most wedged anchors are in that state — a number-keyed
	// selector would omit the majority of the condition the row exists to show.
	var merge metadataAnchor
	for _, ma := range metadataAnchors {
		if ma.kind == "merge" {
			merge = ma
		}
	}
	if merge.key != "merge_result" || merge.value != "" {
		t.Fatalf("the merge kind selects on merge_result presence, got key=%q value=%q",
			merge.key, merge.value)
	}
	if !merge.matches(map[string]string{"merge_result": "pre_open_gate"}) {
		t.Error("a pre-open anchor is a merge anchor: it has a branch, a gate set and a machine axis")
	}
	if !merge.matches(map[string]string{"merge_result": "pull_request"}) {
		t.Error("an open PR's anchor is a merge anchor")
	}
	if merge.matches(map[string]string{"pr_number": "512"}) {
		t.Error("pr_number is a field on the row, never the selector")
	}

	// The human kind comes FIRST so BuildBoard's id-dedup — which keeps the
	// first at equal rank — leaves a wedged anchor, which carries both markers,
	// on its human row instead of flipping kind between passes.
	humanAt, mergeAt := -1, -1
	for i, ma := range metadataAnchors {
		switch ma.kind {
		case "human":
			humanAt = i
		case "merge":
			mergeAt = i
		}
	}
	if humanAt < 0 || mergeAt < 0 || humanAt > mergeAt {
		t.Errorf("human must be gathered before merge: human at %d, merge at %d", humanAt, mergeAt)
	}
}

// TestSupervisorBackendReadsThePRAxes. This backend gathers the merge kind too —
// the selector list is shared, so a kind added on one side cannot go missing on
// the other — and the axes are read off the scanned bead's own metadata.
//
// It is NARROWER here, and that is the backend's standing posture: it cannot
// resolve a blocker's status, so it never claims `asking` and never upgrades a
// row to `progressing` on a pool-routed child.
// Every such row reads what the merge cadence recorded, which is the honest
// answer for a backend that did not read the graph.
func TestSupervisorBackendReadsThePRAxes(t *testing.T) {
	var merge metadataAnchor
	for _, ma := range metadataAnchors {
		if ma.kind == "merge" {
			merge = ma
		}
	}
	md := map[string]string{
		"merge_result": "pre_open_gate",
		"branch":       "polecat/tk-w",
		"pr.machine":   "wedged-exception@" + strings.Repeat("a", 40) + "@2026-08-28T04:05:06Z",
	}
	if !merge.matches(md) {
		t.Fatal("the scan must admit a wedged pre-open anchor")
	}
	a := (&SupervisorSource{}).metadataAnchorFor(&gatherState{}, apiBead{ID: "tk-w", Title: "wedged"},
		md, merge.kind, nil)
	if a.Metadata["pr.machine"] == "" {
		t.Error("the recorded position has to ride on the anchor, or the axis is unreadable here")
	}
	if !a.WaitingUnknown {
		t.Error("this backend cannot resolve blocker statuses and must keep saying so")
	}
	if len(a.Blockers) != 0 {
		t.Error("no edges were resolved, so none are reported")
	}
}

// TestOpenBeadsTruncationIsReported: a scan that comes back short must SAY so.
// Returning the pages already read is right — they are real anchors — but the
// caller has to learn the set is incomplete.
func TestOpenBeadsTruncationIsReported(t *testing.T) {
	srv := mockSupervisor(t, map[string]int{"cursor:page2": http.StatusInternalServerError})
	res, err := newTestSource(t, srv).Gather(context.Background())
	if err != nil {
		t.Fatalf("a half-read scan must not abort the gather: %v", err)
	}
	// Page one's anchors survive.
	if anchorOf(res, "tk-human", "human") == nil {
		t.Error("anchors from the pages that DID read must still be gathered")
	}
	// Page two's do not, and that is what has to be announced.
	if anchorOf(res, "tk-boolmd", "human") != nil {
		t.Error("the failing page cannot have contributed anchors")
	}
	if !res.Partial {
		t.Fatal("a truncated scan is a partial gather")
	}
	var named bool
	for _, e := range res.PartialErrors {
		if strings.Contains(e, "open-bead scan stopped after 1 page") {
			named = true
		}
	}
	if !named {
		t.Errorf("the truncation must name itself and where it stopped: %v", res.PartialErrors)
	}
}

// TestOpenBeadsCarriesTheSupervisorsOwnPartial: a page can be short because one
// RIG did not answer, and only the envelope says so. Dropping that flag lets a
// board missing a whole rig report itself complete.
func TestOpenBeadsCarriesTheSupervisorsOwnPartial(t *testing.T) {
	const base = "/v0/city/testcity"
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Path == base+"/beads" && r.URL.Query().Get("status") == "open" {
			writeJSON(w, `{"items":[],"partial":true,"partial_errors":["rig signal-loom: context deadline exceeded"]}`)
			return
		}
		writeJSON(w, `{"items":[]}`)
	}))
	t.Cleanup(srv.Close)

	res, err := newTestSource(t, srv).Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	if !res.Partial {
		t.Fatal("the supervisor said the read was partial; the board must repeat it")
	}
	var named bool
	for _, e := range res.PartialErrors {
		if strings.Contains(e, "rig signal-loom") {
			named = true
		}
	}
	if !named {
		t.Errorf("the rig that did not answer must be named: %v", res.PartialErrors)
	}
}
