package source

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
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
		case path == base+"/beads": // flagged scan (limit, no type)
			writeJSON(w, `{"items":[
				{"id":"tk-flag","title":"CI red","status":"open","issue_type":"task","metadata":{"gc.attention":"1","gc.attention_reason":"boom"}},
				{"id":"tk-plain","title":"ignore me","status":"open","issue_type":"task","metadata":{}},
				{"id":"tk-flagclosed","title":"closed flag","status":"closed","issue_type":"task","metadata":{"gc.attention":"1"}}
			],"total":3}`)
		case path == base+"/beads/graph/tk-epic":
			writeJSON(w, `{"root":{"id":"tk-epic","status":"open","issue_type":"epic"},
				"beads":[{"id":"tk-epic","status":"open"},{"id":"tk-a","status":"open"},{"id":"tk-b","status":"closed"}],
				"deps":[{"from":"tk-epic","to":"tk-a","kind":"parent-child"},{"from":"tk-epic","to":"tk-b","kind":"parent-child"}]}`)
		case path == base+"/convoys":
			writeJSON(w, `{"items":[
				{"id":"tk-cv","title":"real convoy","status":"open","issue_type":"convoy","parent":""},
				{"id":"tk-sling","title":"sling-tk-x","status":"open","issue_type":"convoy","parent":""},
				{"id":"tk-child-cv","title":"child convoy","status":"open","issue_type":"convoy","parent":"tk-epic"}
			],"total":3}`)
		case path == base+"/convoy/tk-cv":
			writeJSON(w, `{"convoy":{"id":"tk-cv","status":"open"},"children":[{"id":"cv1","status":"open"},{"id":"cv2","status":"in_progress"}],"progress":{"total":2,"closed":0}}`)
		case path == base+"/sessions":
			writeJSON(w, `{"items":[
				{"id":"lx-1","alias":"gc-toolkit.tk-epic","template":"gc-toolkit.bead-host","state":"active","running":true},
				{"id":"lx-2","alias":"gc-toolkit/gc-toolkit.refinery","template":"gc-toolkit.refinery","state":"active","running":true}
			]}`)
		default:
			http.Error(w, "unexpected path: "+path+"?"+r.URL.RawQuery, http.StatusNotFound)
		}
	}))
	t.Cleanup(srv.Close)
	return srv
}

func writeJSON(w http.ResponseWriter, body string) { _, _ = w.Write([]byte(body)) }

func newTestSource(t *testing.T, srv *httptest.Server) *SupervisorSource {
	return NewSupervisorSource(WithBaseURL(srv.URL), WithCity("testcity"), WithHTTPClient(srv.Client()))
}

func anchorByID(res *Result, id string) (have bool, kind, rig, reason string, mTotal, nClosed int) {
	for _, a := range res.Anchors {
		if a.ID == id {
			closed := 0
			for _, c := range a.Children {
				if c.Status == "closed" {
					closed++
				}
			}
			return true, a.Kind, a.Rig, a.Reason, len(a.Children), closed
		}
	}
	return false, "", "", "", 0, 0
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
	if len(res.Anchors) != 4 {
		ids := []string{}
		for _, a := range res.Anchors {
			ids = append(ids, a.ID)
		}
		t.Fatalf("want 4 anchors (epic, decision, flagged, convoy), got %d: %v", len(res.Anchors), ids)
	}

	// Epic: rig resolved from prefix, direct children rolled up incl. closed.
	if ok, kind, rig, _, m, closed := anchorByID(res, "tk-epic"); !ok || kind != "epic" || rig != "gc-toolkit" || m != 2 || closed != 1 {
		t.Errorf("epic anchor wrong: ok=%v kind=%s rig=%s m=%d closed=%d", ok, kind, rig, m, closed)
	}
	// Decision: rig from the sl prefix.
	if ok, kind, rig, _, _, _ := anchorByID(res, "sl-dec"); !ok || kind != "decision" || rig != "signal-loom" {
		t.Errorf("decision anchor wrong: ok=%v kind=%s rig=%s", ok, kind, rig)
	}
	// Flagged: admitted with reason; closed-flag and non-flag excluded.
	if ok, kind, _, reason, _, _ := anchorByID(res, "tk-flag"); !ok || kind != "flagged" || reason != "boom" {
		t.Errorf("flagged anchor wrong: ok=%v kind=%s reason=%q", ok, kind, reason)
	}
	if ok, _, _, _, _, _ := anchorByID(res, "tk-plain"); ok {
		t.Error("non-flagged bead must not be admitted")
	}
	if ok, _, _, _, _, _ := anchorByID(res, "tk-flagclosed"); ok {
		t.Error("closed flagged bead must not be admitted")
	}
	// Convoy: only the owned, floating, non-sling convoy; 2 children.
	if ok, kind, _, _, m, _ := anchorByID(res, "tk-cv"); !ok || kind != "convoy" || m != 2 {
		t.Errorf("convoy anchor wrong: ok=%v kind=%s m=%d", ok, kind, m)
	}
	if ok, _, _, _, _, _ := anchorByID(res, "tk-sling"); ok {
		t.Error("sling- convoy must be filtered out")
	}
	if ok, _, _, _, _, _ := anchorByID(res, "tk-child-cv"); ok {
		t.Error("non-floating (parented) convoy must be filtered out")
	}

	// Sessions: bead-host alias stripped to bead-id; refinery (non-bead-host) skipped.
	if h, ok := res.Sessions["tk-epic"]; !ok || h.State != "active" || !h.Running {
		t.Errorf("tk-epic liveness wrong: %+v ok=%v", h, ok)
	}
	if _, ok := res.Sessions["refinery"]; ok {
		t.Error("non-bead-host session must not be joined")
	}
}

func TestGatherDegradesOnPartialFailure(t *testing.T) {
	// The /beads path (epics, decisions, and the flagged scan all share it)
	// fails; the independent /convoys path still gathers and partial is recorded.
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
	if ok, _, _, _, _, _ := anchorByID(res, "tk-cv"); !ok {
		t.Error("convoy anchor should still gather despite the /beads failure")
	}
	// And the epic, whose list lives under /beads, is correctly dropped.
	if ok, _, _, _, _, _ := anchorByID(res, "tk-epic"); ok {
		t.Error("epic anchor should be absent when the /beads list fails")
	}
}

func TestAliasBeadID(t *testing.T) {
	cases := map[string]string{
		"gc-toolkit.tk-flaghot":          "tk-flaghot",
		"signal-loom.sl-abc":             "sl-abc",
		"gc-toolkit/gc-toolkit.refinery": "refinery",
		"nodot":                          "nodot",
	}
	for in, want := range cases {
		if got := aliasBeadID(in); got != want {
			t.Errorf("aliasBeadID(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestDiscoverCityFromURLPrefix(t *testing.T) {
	t.Setenv("GC_ATTENTION_CITY", "")
	t.Setenv("GC_SERVICE_URL_PREFIX", "/v0/city/loomington/svc/attention")
	if got := discoverCity(); got != "loomington" {
		t.Errorf("discoverCity from URL prefix = %q, want loomington", got)
	}
}
