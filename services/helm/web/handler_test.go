package web

import (
	"crypto/sha256"
	"encoding/base64"
	"io"
	"io/fs"
	"net/http"
	"net/http/httptest"
	"net/url"
	"regexp"
	"strings"
	"testing"
)

// mountPrefix is a realistic external mount: the service is reached under a
// runtime-city-named path, never at the origin root.
const mountPrefix = "/v0/city/loomington/svc/helm"

// mountProxy mimics the supervisor's service proxy (gascity
// internal/workspacesvc/manager.go, serviceSubpath): it strips the mount from
// the request path before the service sees it, and maps BOTH the bare mount
// and the mount with a trailing slash to "/". That equivalence is the reason
// the trailing-slash fix has to live in the client — the server cannot tell
// the two apart, so it cannot redirect.
func mountProxy(mount string, h http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var subpath string
		switch {
		case r.URL.Path == mount:
			subpath = "/"
		case strings.HasPrefix(r.URL.Path, mount+"/"):
			subpath = r.URL.Path[len(mount):]
		default:
			http.NotFound(w, r)
			return
		}
		r2 := r.Clone(r.Context())
		r2.URL.Path = subpath
		r2.URL.RawPath = subpath
		h.ServeHTTP(w, r2)
	})
}

func newTestServer(t *testing.T) *httptest.Server {
	t.Helper()
	h, err := NewHandler()
	if err != nil {
		t.Fatalf("NewHandler: %v", err)
	}
	srv := httptest.NewServer(mountProxy(mountPrefix, h))
	t.Cleanup(srv.Close)
	return srv
}

func getBody(t *testing.T, rawURL string) (*http.Response, []byte) {
	t.Helper()
	resp, err := http.Get(rawURL)
	if err != nil {
		t.Fatalf("GET %s: %v", rawURL, err)
	}
	t.Cleanup(func() { _ = resp.Body.Close() })
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("read %s: %v", rawURL, err)
	}
	return resp, body
}

// assetRefRE pulls the src/href values out of the shell's script and link tags.
var assetRefRE = regexp.MustCompile(`(?i)<(?:script|link)[^>]*\s(?:src|href)\s*=\s*"([^"]+)"`)

// TestAssetsResolveUnderMountPrefix is the KTD5 test: the bundle must work
// under a /svc/helm/-style prefix, not only at the origin root. It resolves
// each asset reference the way a browser does — relative to the document URL —
// and fetches the result back through the mount, so a root-absolute base
// (the known failure mode for this service) fails here rather than in
// production as a blank page.
func TestAssetsResolveUnderMountPrefix(t *testing.T) {
	srv := newTestServer(t)

	docURL, err := url.Parse(srv.URL + mountPrefix + "/")
	if err != nil {
		t.Fatalf("parse document URL: %v", err)
	}
	resp, body := getBody(t, docURL.String())
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("shell status = %d, want 200", resp.StatusCode)
	}
	if ct := resp.Header.Get("Content-Type"); !strings.HasPrefix(ct, "text/html") {
		t.Errorf("shell Content-Type = %q, want text/html", ct)
	}

	refs := assetRefRE.FindAllStringSubmatch(string(body), -1)
	if len(refs) == 0 {
		t.Fatal("shell references no assets; the bundle in dist/ is not the built app")
	}
	for _, m := range refs {
		ref := m[1]
		if strings.HasPrefix(ref, "/") {
			t.Errorf("asset %q is root-absolute and cannot resolve under a mount prefix (KTD5: vite base must stay './')", ref)
			continue
		}
		resolved, err := docURL.Parse(ref)
		if err != nil {
			t.Errorf("resolve %q: %v", ref, err)
			continue
		}
		if !strings.HasPrefix(resolved.Path, mountPrefix+"/") {
			t.Errorf("asset %q resolved to %q, outside the mount %q", ref, resolved.Path, mountPrefix)
			continue
		}
		assetResp, assetBody := getBody(t, resolved.String())
		if assetResp.StatusCode != http.StatusOK {
			t.Errorf("GET %s = %d, want 200", resolved.Path, assetResp.StatusCode)
			continue
		}
		if len(assetBody) == 0 {
			t.Errorf("GET %s returned an empty body", resolved.Path)
		}
	}
}

// TestBareMountWithoutTrailingSlashServesTheNormalizer covers the other half of
// KTD5. The proxy collapses ".../svc/helm" and ".../svc/helm/" to the same
// subpath, so the server cannot redirect the slash-less form; the shell has to
// normalize it client-side or every relative asset resolves one level too high.
func TestBareMountWithoutTrailingSlashServesTheNormalizer(t *testing.T) {
	srv := newTestServer(t)

	resp, body := getBody(t, srv.URL+mountPrefix)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("bare mount status = %d, want 200", resp.StatusCode)
	}
	if !strings.Contains(string(body), "location.replace(") {
		t.Error("shell has no trailing-slash normalizer: a slash-less mount URL will 404 its own assets")
	}
}

func TestUnknownPathIs404(t *testing.T) {
	srv := newTestServer(t)

	for _, path := range []string{"/nope", "/assets/missing.js", "/../embed.go"} {
		resp, _ := getBody(t, srv.URL+mountPrefix+path)
		if resp.StatusCode != http.StatusNotFound {
			t.Errorf("GET %s = %d, want 404", path, resp.StatusCode)
		}
	}
}

func TestAssetsAreImmutablyCachedAndShellIsNot(t *testing.T) {
	srv := newTestServer(t)

	resp, body := getBody(t, srv.URL+mountPrefix+"/")
	if got := resp.Header.Get("Cache-Control"); got != "no-store" {
		t.Errorf("shell Cache-Control = %q, want no-store", got)
	}

	m := assetRefRE.FindStringSubmatch(string(body))
	if m == nil {
		t.Fatal("shell references no assets")
	}
	docURL, err := url.Parse(srv.URL + mountPrefix + "/")
	if err != nil {
		t.Fatalf("parse document URL: %v", err)
	}
	resolved, err := docURL.Parse(m[1])
	if err != nil {
		t.Fatalf("resolve %q: %v", m[1], err)
	}
	assetResp, _ := getBody(t, resolved.String())
	if got := assetResp.Header.Get("Cache-Control"); !strings.Contains(got, "immutable") {
		t.Errorf("asset Cache-Control = %q, want an immutable long-lived cache", got)
	}
}

func TestSecurityHeaders(t *testing.T) {
	srv := newTestServer(t)

	resp, _ := getBody(t, srv.URL+mountPrefix+"/")
	for header, want := range map[string]string{
		"X-Content-Type-Options": "nosniff",
		"X-Frame-Options":        "DENY",
		"Referrer-Policy":        "same-origin",
	} {
		if got := resp.Header.Get(header); got != want {
			t.Errorf("%s = %q, want %q", header, got, want)
		}
	}
	csp := resp.Header.Get("Content-Security-Policy")
	if !strings.Contains(csp, "default-src 'self'") {
		t.Errorf("CSP = %q, want a same-origin default-src", csp)
	}
	// The shell carries an inline script (the mount normalizer), so the policy
	// must admit it by hash rather than by opening script-src to everything.
	if !strings.Contains(csp, "'sha256-") {
		t.Errorf("CSP = %q, want the inline script pinned by hash", csp)
	}
	if strings.Contains(csp, "script-src 'self' 'unsafe-inline'") {
		t.Errorf("CSP = %q, must not open script-src to arbitrary inline script", csp)
	}
}

func TestBuildCSPHashesOnlyInlineScripts(t *testing.T) {
	const inline = `console.log("hi")`
	index := []byte(`<html><head>` +
		`<script>` + inline + `</script>` +
		`<script type="module" crossorigin src="./assets/index-abc.js"></script>` +
		`</head></html>`)

	sum := sha256.Sum256([]byte(inline))
	want := "'sha256-" + base64.StdEncoding.EncodeToString(sum[:]) + "'"

	csp := buildCSP(index)
	if !strings.Contains(csp, want) {
		t.Errorf("CSP = %q, want it to pin the inline script as %s", csp, want)
	}
	if n := strings.Count(csp, "'sha256-"); n != 1 {
		t.Errorf("CSP pins %d hashes, want exactly 1 (the external script must not be hashed)", n)
	}
}

// TestEmbeddedBundleIsTheBuiltApp guards the committed-dist contract: the
// launcher never runs npm, so an empty or partial dist/ ships a broken board.
func TestEmbeddedBundleIsTheBuiltApp(t *testing.T) {
	dist, err := fs.Sub(distFS, "dist")
	if err != nil {
		t.Fatalf("sub fs: %v", err)
	}
	if _, err := fs.Stat(dist, "index.html"); err != nil {
		t.Fatalf("dist/index.html missing: %v", err)
	}
	assets, err := fs.ReadDir(dist, "assets")
	if err != nil {
		t.Fatalf("dist/assets missing: %v", err)
	}
	var js, css int
	for _, e := range assets {
		switch {
		case strings.HasSuffix(e.Name(), ".js"):
			js++
		case strings.HasSuffix(e.Name(), ".css"):
			css++
		}
	}
	if js == 0 {
		t.Error("dist/assets has no JavaScript bundle")
	}
	if css == 0 {
		t.Error("dist/assets has no stylesheet")
	}
}
