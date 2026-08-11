package web

import (
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"io/fs"
	"net/http"
	"regexp"
	"strings"
)

// NewHandler returns an http.Handler over the embedded bundle: the app shell
// for the mount root, the hashed assets it references, and 404 for everything
// else. The server mounts it as the catch-all beneath /healthz and /helm.
//
// Unknown paths deliberately 404 rather than falling back to the shell. The
// app has no client-side routes yet, so an unmatched path is a routing mistake
// (a stale caller, a typo'd asset), and answering it with a 200 HTML shell
// would hide that — the same reason the board's own catch-all 404s. A later
// unit that adds client-side routing has to revisit this, and should fall back
// on HTML navigations only.
func NewHandler() (http.Handler, error) {
	dist, err := fs.Sub(distFS, "dist")
	if err != nil {
		return nil, fmt.Errorf("helm/web: sub fs: %w", err)
	}
	index, err := fs.ReadFile(dist, "index.html")
	if err != nil {
		return nil, fmt.Errorf("helm/web: read index.html: %w", err)
	}
	return &handler{
		dist:  dist,
		files: http.FileServer(http.FS(dist)),
		index: index,
		csp:   buildCSP(index),
	}, nil
}

type handler struct {
	dist  fs.FS
	files http.Handler
	index []byte
	csp   string
}

func (h *handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	setSecurityHeaders(w, h.csp)

	// Paths arrive already stripped of the service mount prefix, so the app
	// shell is "/" no matter how deep the external mount is.
	name := strings.TrimPrefix(r.URL.Path, "/")
	if name == "" || name == "index.html" {
		h.writeIndex(w)
		return
	}
	if st, err := fs.Stat(h.dist, name); err == nil && !st.IsDir() {
		// Vite emits content-hashed filenames under assets/, so those are safe
		// to cache forever; anything else revalidates.
		if strings.HasPrefix(name, "assets/") {
			w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
		} else {
			w.Header().Set("Cache-Control", "no-cache")
		}
		h.files.ServeHTTP(w, r)
		return
	}
	http.NotFound(w, r)
}

func (h *handler) writeIndex(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	// The shell names content-hashed assets, so it must never be cached: a
	// stale shell points at bundles a rebuild has already deleted.
	w.Header().Set("Cache-Control", "no-store")
	_, _ = w.Write(h.index)
}

func setSecurityHeaders(w http.ResponseWriter, csp string) {
	h := w.Header()
	h.Set("Content-Security-Policy", csp)
	h.Set("X-Content-Type-Options", "nosniff")
	h.Set("X-Frame-Options", "DENY")
	h.Set("Referrer-Policy", "same-origin")
}

var (
	inlineScriptRE = regexp.MustCompile(`(?is)<script((?:\s[^>]*)?)>(.*?)</script>`)
	srcAttrRE      = regexp.MustCompile(`(?i)\ssrc\s*=`)
)

// buildCSP computes a same-origin Content-Security-Policy, mirroring the stock
// dashboard SPA's policy (gascity internal/api/dashboardspa). Each inline
// <script> in index.html — here, the mount-prefix normalizer — is hashed and
// pinned in script-src, so the strict policy admits exactly the bundle's own
// inline code and nothing else. The hash is read from the embedded index.html
// at boot rather than hardcoded, so it always tracks the shipped bundle.
func buildCSP(index []byte) string {
	var hashes []string
	for _, m := range inlineScriptRE.FindAllSubmatch(index, -1) {
		attrs, body := m[1], m[2]
		if srcAttrRE.Match(attrs) {
			continue
		}
		sum := sha256.Sum256(body)
		hashes = append(hashes, "'sha256-"+base64.StdEncoding.EncodeToString(sum[:])+"'")
	}
	scriptSrc := "script-src 'self'"
	if len(hashes) > 0 {
		scriptSrc += " " + strings.Join(hashes, " ")
	}
	return strings.Join([]string{
		"default-src 'self'",
		scriptSrc,
		"style-src 'self' 'unsafe-inline'",
		"img-src 'self' data:",
		"font-src 'self' data:",
		"connect-src 'self'",
		"base-uri 'self'",
		"form-action 'self'",
		"frame-ancestors 'none'",
		"frame-src 'none'",
		"worker-src 'self'",
		"manifest-src 'self'",
		"object-src 'none'",
	}, "; ")
}
