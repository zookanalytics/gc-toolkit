package server

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/closed"
	"github.com/zookanalytics/gc-toolkit/services/helm/internal/source"
)

// closedFake is a fakeSource that ALSO satisfies source.ClosedSource, so the
// route can be exercised without a store. It records the cutoff it was handed,
// which is the only way to prove ?since= is actually spent.
type closedFake struct {
	fakeSource
	calls  atomic.Int32
	cutoff atomic.Pointer[time.Time]
	rows   []closed.Disposition
	err    error
}

func (c *closedFake) GatherClosed(_ context.Context, cutoff time.Time) ([]closed.Disposition, error) {
	c.calls.Add(1)
	cp := cutoff
	c.cutoff.Store(&cp)
	if c.err != nil {
		return nil, c.err
	}
	return c.rows, nil
}

func newClosedFake() *closedFake {
	return &closedFake{
		fakeSource: fakeSource{result: &source.Result{}},
		rows: []closed.Disposition{
			{Rig: "gc-toolkit", Visit: "tk-v1", ClosedAt: time.Date(2026, 8, 24, 4, 0, 0, 0, time.UTC),
				Outcome: "routed", Subject: "tk-s", SubjectTitle: "a subject", Takeaway: "routed — work is out"},
		},
	}
}

func getClosed(t *testing.T, s *Server, target string) *httptest.ResponseRecorder {
	t.Helper()
	rr := httptest.NewRecorder()
	s.Handler().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, target, nil))
	return rr
}

// TestClosedServesTheEnvelope covers the happy path and the wire shape. The
// route returns the {generated_at,since,cutoff,total,rows} envelope, mirroring
// GET /helm, while the CLI emits the bare array — the same split board already
// has, so a consumer of one reads the other without a second convention.
func TestClosedServesTheEnvelope(t *testing.T) {
	src := newClosedFake()
	s := New(src, 0)

	rr := getClosed(t, s, "/helm/closed")
	if rr.Code != http.StatusOK {
		t.Fatalf("status = %d, body %s", rr.Code, rr.Body.String())
	}
	var got closed.Dispositions
	if err := json.Unmarshal(rr.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode: %v (body %s)", err, rr.Body.String())
	}
	if got.Since != "24h" {
		t.Errorf("Since = %q, want the 24h default echoed back", got.Since)
	}
	if got.Total != 1 || len(got.Rows) != 1 {
		t.Fatalf("Total=%d rows=%d, want 1/1", got.Total, len(got.Rows))
	}
	if got.Rows[0].Takeaway != "routed — work is out" {
		t.Errorf("takeaway = %q", got.Rows[0].Takeaway)
	}
	if got.Cutoff.IsZero() {
		t.Error("Cutoff is zero; a window width alone does not say WHICH window")
	}
}

// TestClosedSpendsTheSinceParameter proves ?since= reaches the gather. A route
// that parsed it and then gathered a fixed window would pass every shape check
// while answering the wrong question.
func TestClosedSpendsTheSinceParameter(t *testing.T) {
	src := newClosedFake()
	s := New(src, 0)
	before := time.Now().UTC()

	if rr := getClosed(t, s, "/helm/closed?since=7d"); rr.Code != http.StatusOK {
		t.Fatalf("status = %d", rr.Code)
	}
	cutoff := src.cutoff.Load()
	if cutoff == nil {
		t.Fatal("the gather was never called")
	}
	age := before.Sub(*cutoff)
	if age < 7*24*time.Hour-time.Minute || age > 7*24*time.Hour+time.Minute {
		t.Errorf("cutoff is %v back, want ~7d", age)
	}
}

// TestClosedRefusesABadWindow — a mis-spelled window must be a 400, never a
// silent widening to the default: an operator who asked for "2w" and got 24h
// back would read a short list as a quiet fortnight.
func TestClosedRefusesABadWindow(t *testing.T) {
	src := newClosedFake()
	s := New(src, 0)

	rr := getClosed(t, s, "/helm/closed?since=2w")
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400 (body %s)", rr.Code, rr.Body.String())
	}
	if src.calls.Load() != 0 {
		t.Error("the gather ran on a window that was never valid")
	}

	if rr := getClosed(t, s, "/helm/closed?limit=-3"); rr.Code != http.StatusBadRequest {
		t.Errorf("limit=-3 status = %d, want 400", rr.Code)
	}
	if rr := getClosed(t, s, "/helm/closed?limit=abc"); rr.Code != http.StatusBadRequest {
		t.Errorf("limit=abc status = %d, want 400", rr.Code)
	}
}

// TestClosedFailsLoudly — 502 and no rows, never an empty list. "Nothing was
// decided" and "we could not look" are opposite answers, and only one of them
// means the window was quiet.
func TestClosedFailsLoudly(t *testing.T) {
	src := newClosedFake()
	src.err = errors.New("dolt wedged")
	s := New(src, 0)

	rr := getClosed(t, s, "/helm/closed")
	if rr.Code != http.StatusBadGateway {
		t.Fatalf("status = %d, want 502 (body %s)", rr.Code, rr.Body.String())
	}
	var body map[string]string
	if err := json.Unmarshal(rr.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if body["error"] == "" {
		t.Error("a 502 must say why")
	}
	if _, isView := body["rows"]; isView {
		t.Error("a failure must not be shaped like an answer")
	}
}

// TestClosedIsNotImplementedWithoutTheCapability — under a backend that cannot
// select visits by metadata or bound a window server-side, the route says so
// rather than 404ing, so an operator learns why instead of thinking it vanished.
// Same rule POST /helm/open follows for a missing visit tool.
func TestClosedIsNotImplementedWithoutTheCapability(t *testing.T) {
	// The plain fakeSource satisfies source.Source and NOT source.ClosedSource.
	s := New(newFake(), 0)
	rr := getClosed(t, s, "/helm/closed")
	if rr.Code != http.StatusNotImplemented {
		t.Fatalf("status = %d, want 501 (body %s)", rr.Code, rr.Body.String())
	}
	if rr.Body.Len() == 0 {
		t.Error("a 501 must carry a reason")
	}
}

// TestClosedIsNotCached is the deliberate difference from GET /helm. The board
// is one standing question re-asked on every glance, so a TTL is free; this
// answers an EXPLICIT window, and a cached answer would be the previous
// ?since= returned without saying so.
func TestClosedIsNotCached(t *testing.T) {
	src := newClosedFake()
	s := New(src, time.Hour) // a TTL long enough that a cache would certainly hit

	for range 3 {
		if rr := getClosed(t, s, "/helm/closed"); rr.Code != http.StatusOK {
			t.Fatalf("status = %d", rr.Code)
		}
	}
	if n := src.calls.Load(); n != 3 {
		t.Errorf("gathered %d times over 3 requests; the window must be re-read each time", n)
	}
}

// TestClosedRouteBeatsTheSPACatchAll — /helm/closed is an exact pattern, so it
// reaches this handler whatever the bundle does with unknown paths.
func TestClosedRouteBeatsTheSPACatchAll(t *testing.T) {
	src := newClosedFake()
	s := New(src, 0, WithSPA(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusTeapot)
	})))
	rr := getClosed(t, s, "/helm/closed")
	if rr.Code != http.StatusOK {
		t.Fatalf("status = %d; the SPA swallowed the route", rr.Code)
	}
}
