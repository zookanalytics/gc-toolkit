package server

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/helm/web"
)

func TestHealthz(t *testing.T) {
	s := New()
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	req.Header.Set("Accept", "text/html")
	rr := httptest.NewRecorder()
	s.Handler().ServeHTTP(rr, req)
	if rr.Code != http.StatusOK {
		t.Fatalf("healthz status = %d, want 200", rr.Code)
	}
	if got := rr.Body.String(); !strings.Contains(got, `"status":"ok"`) {
		t.Errorf("/healthz body = %q, want the JSON liveness payload", got)
	}
}

// TestUnknownPath404s: a path no route serves answers 404, and so does the bare
// mount when no app is wired.
func TestUnknownPath404s(t *testing.T) {
	s := New()
	for _, path := range []string{"/nope", "/"} {
		rr := httptest.NewRecorder()
		s.Handler().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, path, nil))
		if rr.Code != http.StatusNotFound {
			t.Errorf("GET %s status = %d, want 404", path, rr.Code)
		}
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

// TestBareMountServesTheApp: the mount root is the app's, whatever the client
// asks for.
func TestBareMountServesTheApp(t *testing.T) {
	s := New(WithSPA(stubSPA()))
	for _, accept := range []string{"text/html,application/xhtml+xml,*/*;q=0.8", "*/*", "", "application/json"} {
		req := httptest.NewRequest(http.MethodGet, "/", nil)
		if accept != "" {
			req.Header.Set("Accept", accept)
		}
		rr := httptest.NewRecorder()
		s.Handler().ServeHTTP(rr, req)
		if rr.Code != http.StatusOK || !strings.HasPrefix(rr.Body.String(), "SPA:") {
			t.Errorf("Accept %q: bare mount = %d %q, want the app", accept, rr.Code, rr.Body.String())
		}
	}
}

func TestSPAServesAssetsAndStill404sUnknownPaths(t *testing.T) {
	s := New(WithSPA(stubSPA()))

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

// TestNilSPAKeepsTheRoutes covers the degraded path: a bundle that fails to
// load leaves the bare mount answering 404 and the routes serving.
func TestNilSPAKeepsTheRoutes(t *testing.T) {
	s := New(WithSPA(nil))

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("Accept", "text/html")
	rr := httptest.NewRecorder()
	s.Handler().ServeHTTP(rr, req)
	if rr.Code != http.StatusNotFound {
		t.Errorf("bare mount without an SPA = %d, want 404", rr.Code)
	}

	rr = httptest.NewRecorder()
	s.Handler().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/assets/index-abc.js", nil))
	if rr.Code != http.StatusNotFound {
		t.Errorf("asset path without an SPA = %d, want 404", rr.Code)
	}

	rr = httptest.NewRecorder()
	s.Handler().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if rr.Code != http.StatusOK {
		t.Errorf("/healthz without an SPA = %d, want 200", rr.Code)
	}
}

// TestEmbeddedAppServesThroughTheServer wires the real bundle, so the embed,
// the handler and the routing are proven together rather than separately.
func TestEmbeddedAppServesThroughTheServer(t *testing.T) {
	spa, err := web.NewHandler()
	if err != nil {
		t.Fatalf("web.NewHandler: %v", err)
	}
	s := New(WithSPA(spa))

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
}
