package server

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/board"
	"github.com/zookanalytics/gc-toolkit/services/helm/internal/source"
	"github.com/zookanalytics/gc-toolkit/services/helm/web"
)

// fakeSource returns canned anchors and counts gather calls so cache behaviour
// is observable.
type fakeSource struct {
	calls  atomic.Int32
	result *source.Result
	err    error
}

func (f *fakeSource) Gather(context.Context) (*source.Result, error) {
	f.calls.Add(1)
	if f.err != nil {
		return nil, f.err
	}
	return f.result, nil
}

func newFake() *fakeSource {
	return &fakeSource{result: &source.Result{
		Anchors: []board.Anchor{
			{ID: "sl-dec", Kind: "decision", Source: "decision", Rig: "signal-loom"},
			{ID: "tk-epic", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Children: []board.Child{{ID: "c", Status: "open"}}},
		},
	}}
}

func TestHealthz(t *testing.T) {
	s := New(newFake(), time.Minute)
	rr := httptest.NewRecorder()
	s.Handler().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if rr.Code != http.StatusOK {
		t.Fatalf("healthz status = %d, want 200", rr.Code)
	}
}

func TestBoardEndpointRanks(t *testing.T) {
	s := New(newFake(), time.Minute)
	for _, path := range []string{"/helm", "/"} {
		rr := httptest.NewRecorder()
		s.Handler().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, path, nil))
		if rr.Code != http.StatusOK {
			t.Fatalf("%s status = %d, want 200", path, rr.Code)
		}
		var b board.Board
		if err := json.Unmarshal(rr.Body.Bytes(), &b); err != nil {
			t.Fatalf("%s: decode board: %v", path, err)
		}
		if b.Total != 2 || len(b.Tiles) != 2 {
			t.Fatalf("%s: want 2 tiles, got total=%d tiles=%d", path, b.Total, len(b.Tiles))
		}
		// The stranded epic must rank first (HIGH band dominates ELEVATED).
		if b.Tiles[0].ID != "tk-epic" || b.Tiles[0].Severity != board.SevHigh {
			t.Errorf("%s: top tile = %s/%s, want tk-epic/HIGH", path, b.Tiles[0].ID, b.Tiles[0].Severity)
		}
		if b.GeneratedAt.IsZero() {
			t.Errorf("%s: generated_at not stamped", path)
		}
	}
}

func TestUnknownPath404s(t *testing.T) {
	s := New(newFake(), time.Minute)
	rr := httptest.NewRecorder()
	s.Handler().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/nope", nil))
	if rr.Code != http.StatusNotFound {
		t.Errorf("unknown path status = %d, want 404", rr.Code)
	}
}

func TestCacheServesWithinTTL(t *testing.T) {
	f := newFake()
	s := New(f, time.Minute)
	// Pin a clock so the TTL window is deterministic.
	base := time.Date(2026, 6, 30, 12, 0, 0, 0, time.UTC)
	cur := base
	s.now = func() time.Time { return cur }

	if _, err := s.Board(context.Background()); err != nil {
		t.Fatal(err)
	}
	cur = base.Add(30 * time.Second) // still within the 1m TTL
	if _, err := s.Board(context.Background()); err != nil {
		t.Fatal(err)
	}
	if got := f.calls.Load(); got != 1 {
		t.Errorf("within TTL: gather called %d times, want 1 (cache hit)", got)
	}
	cur = base.Add(2 * time.Minute) // past the TTL
	if _, err := s.Board(context.Background()); err != nil {
		t.Fatal(err)
	}
	if got := f.calls.Load(); got != 2 {
		t.Errorf("past TTL: gather called %d times, want 2 (recompute)", got)
	}
}

func TestBoardErrorIs502(t *testing.T) {
	f := &fakeSource{err: context.DeadlineExceeded}
	s := New(f, time.Minute)
	rr := httptest.NewRecorder()
	s.Handler().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/helm", nil))
	if rr.Code != http.StatusBadGateway {
		t.Errorf("gather error status = %d, want 502", rr.Code)
	}
}

// stubSPA stands in for the embedded app so the routing matrix can be tested
// without depending on the built bundle.
func stubSPA() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/" || strings.HasPrefix(r.URL.Path, "/assets/") {
			w.Header().Set("Content-Type", "text/html; charset=utf-8")
			_, _ = w.Write([]byte("SPA:" + r.URL.Path))
			return
		}
		http.NotFound(w, r)
	})
}

// TestBoardRoutesIgnoreAccept is the load-bearing guarantee for the frontend
// units: /helm is the contract U7 mirrors and U8/U9 consume, so it stays JSON
// whatever the client asks for — including a browser navigation.
func TestBoardRoutesIgnoreAccept(t *testing.T) {
	s := New(newFake(), time.Minute, WithSPA(stubSPA()))

	req := httptest.NewRequest(http.MethodGet, "/helm", nil)
	req.Header.Set("Accept", "text/html,application/xhtml+xml,*/*;q=0.8")
	rr := httptest.NewRecorder()
	s.Handler().ServeHTTP(rr, req)
	if rr.Code != http.StatusOK {
		t.Fatalf("/helm status = %d, want 200", rr.Code)
	}
	var b board.Board
	if err := json.Unmarshal(rr.Body.Bytes(), &b); err != nil {
		t.Fatalf("/helm did not return board JSON to an HTML-preferring client: %v", err)
	}
	if b.Total != 2 {
		t.Errorf("/helm total = %d, want 2", b.Total)
	}

	req = httptest.NewRequest(http.MethodGet, "/healthz", nil)
	req.Header.Set("Accept", "text/html")
	rr = httptest.NewRecorder()
	s.Handler().ServeHTTP(rr, req)
	if rr.Code != http.StatusOK {
		t.Errorf("/healthz status = %d, want 200", rr.Code)
	}
	if got := rr.Body.String(); !strings.Contains(got, `"status":"ok"`) {
		t.Errorf("/healthz body = %q, want the JSON liveness payload", got)
	}
}

// TestBareMountNegotiates pins the two-audience rule at the mount root: the
// browser gets the app, every existing JSON caller keeps its JSON.
func TestBareMountNegotiates(t *testing.T) {
	s := New(newFake(), time.Minute, WithSPA(stubSPA()))

	cases := []struct {
		name    string
		accept  string
		wantSPA bool
	}{
		{"browser navigation", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", true},
		{"explicit html", "text/html", true},
		{"xhtml", "application/xhtml+xml", true},
		{"curl", "*/*", false},
		{"no accept header", "", false},
		{"json client", "application/json", false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "/", nil)
			if tc.accept != "" {
				req.Header.Set("Accept", tc.accept)
			}
			rr := httptest.NewRecorder()
			s.Handler().ServeHTTP(rr, req)
			if rr.Code != http.StatusOK {
				t.Fatalf("status = %d, want 200", rr.Code)
			}
			isSPA := strings.HasPrefix(rr.Body.String(), "SPA:")
			if isSPA != tc.wantSPA {
				t.Errorf("Accept %q served SPA=%v, want %v (body %q)", tc.accept, isSPA, tc.wantSPA, rr.Body.String())
			}
			if !tc.wantSPA {
				var b board.Board
				if err := json.Unmarshal(rr.Body.Bytes(), &b); err != nil {
					t.Errorf("Accept %q: bare mount stopped returning board JSON: %v", tc.accept, err)
				}
			}
		})
	}
}

func TestSPAServesAssetsAndStill404sUnknownPaths(t *testing.T) {
	s := New(newFake(), time.Minute, WithSPA(stubSPA()))

	rr := httptest.NewRecorder()
	s.Handler().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/assets/index-abc.js", nil))
	if rr.Code != http.StatusOK || !strings.HasPrefix(rr.Body.String(), "SPA:") {
		t.Errorf("asset request = %d %q, want the SPA handler", rr.Code, rr.Body.String())
	}

	rr = httptest.NewRecorder()
	s.Handler().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/nope", nil))
	if rr.Code != http.StatusNotFound {
		t.Errorf("unknown path = %d, want 404 (the catch-all must not mask routing mistakes)", rr.Code)
	}
}

// TestNilSPAKeepsJSONOnlyRouting covers the degraded path: a bundle that fails
// to load must leave the pre-app behaviour exactly as it was.
func TestNilSPAKeepsJSONOnlyRouting(t *testing.T) {
	s := New(newFake(), time.Minute, WithSPA(nil))

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("Accept", "text/html")
	rr := httptest.NewRecorder()
	s.Handler().ServeHTTP(rr, req)
	if rr.Code != http.StatusOK {
		t.Fatalf("bare mount status = %d, want 200", rr.Code)
	}
	var b board.Board
	if err := json.Unmarshal(rr.Body.Bytes(), &b); err != nil {
		t.Fatalf("without an SPA the bare mount must still serve board JSON: %v", err)
	}

	rr = httptest.NewRecorder()
	s.Handler().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/assets/index-abc.js", nil))
	if rr.Code != http.StatusNotFound {
		t.Errorf("asset path without an SPA = %d, want 404", rr.Code)
	}
}

// TestEmbeddedAppServesThroughTheServer wires the real bundle, so the embed,
// the handler and the routing are proven together rather than separately.
func TestEmbeddedAppServesThroughTheServer(t *testing.T) {
	spa, err := web.NewHandler()
	if err != nil {
		t.Fatalf("web.NewHandler: %v", err)
	}
	s := New(newFake(), time.Minute, WithSPA(spa))

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("Accept", "text/html")
	rr := httptest.NewRecorder()
	s.Handler().ServeHTTP(rr, req)
	if rr.Code != http.StatusOK {
		t.Fatalf("shell status = %d, want 200", rr.Code)
	}
	body := rr.Body.String()
	if !strings.Contains(body, `<div id="root">`) {
		t.Errorf("mount root did not serve the app shell; body = %q", body)
	}
	if !strings.Contains(body, "./assets/") {
		t.Error("shell does not reference relative assets; the bundle would 404 under a mount prefix")
	}

	rr = httptest.NewRecorder()
	s.Handler().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/helm", nil))
	var b board.Board
	if err := json.Unmarshal(rr.Body.Bytes(), &b); err != nil {
		t.Fatalf("/helm alongside the real app: %v", err)
	}
}
