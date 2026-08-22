// Package server exposes the Helm board over HTTP with a small server-side
// TTL cache. It is transport-agnostic: [Server.Handler] returns an
// [http.Handler] that the cmd wires onto a unix socket (the proxy_process
// contract). Requests arrive path-stripped — the service mounted at
// /v0/city/<c>/svc/helm is reached as GET /helm (and the bare mount as
// GET /).
package server

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/board"
	"github.com/zookanalytics/gc-toolkit/services/helm/internal/source"
)

// Server computes and serves the Helm board, caching the computed board for
// a TTL so polling clients do not re-drive the supervisor gather on every hit.
type Server struct {
	src source.Source
	ttl time.Duration
	now func() time.Time
	spa http.Handler

	// opener files visits for POST /helm/open; nil disables the route (it
	// then answers 503 rather than 404 — see handleOpen).
	opener   Opener
	openGate *openGate

	mu     sync.Mutex
	cached *board.Board
	expiry time.Time
}

// An Option configures a Server at construction.
type Option func(*Server)

// WithSPA serves the embedded single-page app beneath the board routes: the
// app shell at the mount root for browsers, plus its assets. A nil handler is
// ignored, which leaves the JSON-only routing this service had before the app
// existed — so a bundle that fails to load degrades the UI without taking the
// board's consumers down with it.
func WithSPA(h http.Handler) Option {
	return func(s *Server) {
		if h != nil {
			s.spa = h
		}
	}
}

// WithOpener enables the board's one write route, POST /helm/open, which files
// a visit on a bead by shelling out to `gc-helm.sh open` (see open.go).
//
// It is an Option rather than a constructor argument because the write surface
// is genuinely optional: a helm-svc that cannot locate the script still serves
// the whole board, and says so honestly when the route is called. A nil opener
// is ignored, which keeps the read-only behaviour this service had before the
// route existed.
func WithOpener(o Opener) Option {
	return func(s *Server) {
		if o != nil {
			s.opener = o
		}
	}
}

// New builds a Server. ttl<=0 disables caching (every request recomputes).
func New(src source.Source, ttl time.Duration, opts ...Option) *Server {
	s := &Server{src: src, ttl: ttl, now: time.Now, openGate: newOpenGate()}
	for _, opt := range opts {
		opt(s)
	}
	return s
}

// Handler returns the HTTP routes: GET /helm (and bare /) serve the board;
// GET /healthz is the liveness probe (no gather); POST /helm/open files a visit
// on a bead. With [WithSPA] the bare mount also serves the app shell to
// browsers, and its assets beneath.
//
// /helm/open is registered as its own exact pattern, which ServeMux prefers
// over the "/" catch-all — so it reaches [Server.handleOpen] rather than the
// SPA handler, whatever the bundle does with unknown paths.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", s.handleHealth)
	mux.HandleFunc("/helm", s.handleBoard)
	mux.HandleFunc("/helm/open", s.handleOpen)
	mux.HandleFunc("/", s.handleRoot)
	return mux
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_, _ = w.Write([]byte(`{"status":"ok"}`))
}

// handleRoot serves the bare mount and, with an SPA wired, everything beneath
// it that is not a board route.
//
// The bare mount answers two audiences at one URL. It has always returned the
// board JSON — the operator curls it, and it is the address of the whole
// service — and the SPA has to live at that same mount because the supervisor
// gives a workspace-service exactly one path. So the representation follows
// the request: a browser navigation (Accept: text/html) gets the app shell,
// every other client (curl, fetch, a script, Accept: */*) gets the JSON it got
// before. Nothing that already reads this mount changes behaviour, and
// /helm — the contract U7 mirrors and U8/U9 consume — is JSON unconditionally,
// on its own route, whatever the Accept header says.
//
// Without an SPA the whole mount stays JSON, and any other path 404s so the
// catch-all does not mask routing mistakes.
func (s *Server) handleRoot(w http.ResponseWriter, r *http.Request) {
	if s.spa == nil {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		s.handleBoard(w, r)
		return
	}
	if r.URL.Path == "/" && !wantsHTML(r) {
		s.handleBoard(w, r)
		return
	}
	s.spa.ServeHTTP(w, r)
}

// wantsHTML reports whether the client asked for an HTML document. Browsers
// send "text/html,application/xhtml+xml,…" on a navigation; curl and fetch()
// default to */*, which is not a request for HTML and so keeps the JSON.
func wantsHTML(r *http.Request) bool {
	for _, part := range strings.Split(r.Header.Get("Accept"), ",") {
		// Drop any ";q=…" and other parameters before comparing.
		mediaType := strings.ToLower(strings.TrimSpace(part))
		if i := strings.IndexByte(mediaType, ';'); i >= 0 {
			mediaType = strings.TrimSpace(mediaType[:i])
		}
		if mediaType == "text/html" || mediaType == "application/xhtml+xml" {
			return true
		}
	}
	return false
}

func (s *Server) handleBoard(w http.ResponseWriter, r *http.Request) {
	b, err := s.Board(r.Context())
	if err != nil {
		log.Printf("helm: board gather failed: %v", err)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadGateway)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": "board unavailable: " + err.Error()})
		return
	}
	w.Header().Set("Content-Type", "application/json")
	enc := json.NewEncoder(w)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(b); err != nil {
		log.Printf("helm: encode failed: %v", err)
	}
}

// Board returns the cached board when fresh, otherwise gathers and computes a new
// one. The lock is held across the gather so concurrent misses do not stampede
// the supervisor; a follow-up can add stale-while-revalidate.
func (s *Server) Board(ctx context.Context) (*board.Board, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.cached != nil && s.ttl > 0 && s.now().Before(s.expiry) {
		return s.cached, nil
	}

	res, err := s.src.Gather(ctx)
	if err != nil {
		return nil, err
	}
	b := board.BuildBoard(res.Anchors, s.now(), res.Partial, res.PartialErrors, res.Facts)
	s.cached = &b
	s.expiry = s.now().Add(s.ttl)
	return &b, nil
}
