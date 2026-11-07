package source

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

// The Delivery family the supervisor serves below: an epic carrying its
// hypothesis, with a Delivery whose Stories have all closed and a child epic
// with a hypothesis of its own whose child has closed.
const familyHypothesis = "operators rule on each epic from its landed work"

// deliverySupervisor serves the family over the supervisor API, with the
// epics' metadata on the `/beads` list as the live API carries it.
func deliverySupervisor(t *testing.T) *httptest.Server {
	t.Helper()
	const base = "/v0/city/testcity"
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		q := r.URL.Query()
		switch {
		case r.URL.Path == base+"/rigs":
			writeJSON(w, `{"items":[{"name":"gc-toolkit","prefix":"tk"}]}`)
		case r.URL.Path == base+"/beads" && q.Get("type") == "epic":
			writeJSON(w, `{"items":[
				{"id":"tk-ep","title":"an epic","status":"open","issue_type":"epic","priority":2,
				 "metadata":{"epic_hypothesis":"`+familyHypothesis+`","epic_handle":"rulings"}},
				{"id":"tk-ep.1","title":"Delivery: the first step","status":"open","issue_type":"epic","priority":2,"parent":"tk-ep"},
				{"id":"tk-ep.2","title":"an epic of its own","status":"open","issue_type":"epic","priority":2,"parent":"tk-ep",
				 "metadata":{"epic_hypothesis":"`+familyHypothesis+`"}}
			],"total":3}`)
		case r.URL.Path == base+"/beads" && (q.Get("type") == "decision" || q.Get("type") == "gate" || q.Get("status") == "open"):
			writeJSON(w, `{"items":[],"total":0}`)
		case r.URL.Path == base+"/convoys":
			writeJSON(w, `{"items":[],"total":0}`)
		case r.URL.Path == base+"/beads/graph/tk-ep":
			writeJSON(w, `{"root":{"id":"tk-ep","status":"open"},
				"beads":[{"id":"tk-ep","status":"open"},{"id":"tk-ep.1","status":"open"},{"id":"tk-ep.2","status":"open"}],
				"deps":[{"from":"tk-ep","to":"tk-ep.1","kind":"parent-child"},{"from":"tk-ep","to":"tk-ep.2","kind":"parent-child"}]}`)
		case r.URL.Path == base+"/beads/graph/tk-ep.1":
			writeJSON(w, `{"root":{"id":"tk-ep.1","status":"open"},
				"beads":[{"id":"tk-ep.1","status":"open"},{"id":"tk-ep.1.1","status":"closed"},{"id":"tk-ep.1.2","status":"closed"}],
				"deps":[{"from":"tk-ep.1","to":"tk-ep.1.1","kind":"parent-child"},{"from":"tk-ep.1","to":"tk-ep.1.2","kind":"parent-child"}]}`)
		case r.URL.Path == base+"/beads/graph/tk-ep.2":
			writeJSON(w, `{"root":{"id":"tk-ep.2","status":"open"},
				"beads":[{"id":"tk-ep.2","status":"open"},{"id":"tk-ep.2.1","status":"closed"}],
				"deps":[{"from":"tk-ep.2","to":"tk-ep.2.1","kind":"parent-child"}]}`)
		default:
			http.Error(w, "unexpected path: "+r.URL.Path+"?"+r.URL.RawQuery, http.StatusNotFound)
		}
	}))
	t.Cleanup(srv.Close)
	return srv
}

// TestSupervisorEpicRowCarriesItsMetadata: the supervisor source reads an epic's
// metadata off the `/beads` list onto its row, as the beads backend does, so
// the board can tell a Delivery from a child epic that is an epic of its own.
func TestSupervisorEpicRowCarriesItsMetadata(t *testing.T) {
	res, err := newTestSource(t, deliverySupervisor(t)).Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	if res.Partial {
		t.Errorf("unexpected partial: %v", res.PartialErrors)
	}
	for id, want := range map[string]string{"tk-ep": familyHypothesis, "tk-ep.1": "", "tk-ep.2": familyHypothesis} {
		a := anchorOf(res, id, "epic")
		if a == nil {
			t.Fatalf("%s: no epic row", id)
		}
		if got := a.Metadata["epic_hypothesis"]; got != want {
			t.Errorf("%s: epic_hypothesis=%q, want %q", id, got, want)
		}
	}
	if got := anchorOf(res, "tk-ep", "epic").Metadata["epic_handle"]; got != "rulings" {
		t.Errorf("the row carries the epic's other metadata too: epic_handle=%q", got)
	}
}
