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
	"golang.org/x/sync/singleflight"
)

// Server computes and serves the Helm board, caching the computed board for
// a TTL so polling clients do not re-drive the supervisor gather on every hit.
type Server struct {
	src source.Source
	ttl time.Duration
	now func() time.Time
	spa http.Handler

	// cityPath is the city root pack health is read from, resolved once at
	// startup and passed via WithCityPath. Empty when unset (tests, or a city
	// gc could not resolve), which GatherPackHealth reads as "no pack health".
	// Discovery is a subprocess (gc), so it is NOT re-run on every board build.
	cityPath string

	// actuator runs the board's write verbs (open, accept, engage, dismiss) by
	// shelling out to gc-helm.sh; nil disables all four routes (they then answer
	// 503 rather than 404 — see runActuation).
	actuator Actuator
	gate     *actuationGate

	// mu guards cached/expiry only. It is never held across a gather: the
	// gather builds a board outside the lock and swaps it in under it, so a slow
	// build cannot block a request a fresh cache could answer.
	mu     sync.Mutex
	cached *board.Board
	expiry time.Time

	// flight coalesces concurrent cache misses into one gather, the anti-
	// stampede role the cross-gather lock used to play.
	flight singleflight.Group
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

// WithActuator enables the board's write routes, POST /helm/{open,accept,engage,
// dismiss}, each of which shells out to the matching gc-helm.sh verb (see
// actuate.go).
//
// It is an Option rather than a constructor argument because the write surface is
// genuinely optional: a helm-svc that cannot locate the script still serves the
// whole board, and says so honestly when a route is called. A nil actuator is
// ignored, which keeps the read-only behaviour this service had before the routes
// existed.
func WithActuator(a Actuator) Option {
	return func(s *Server) {
		if a != nil {
			s.actuator = a
		}
	}
}

// WithCityPath supplies the city root the board reads pack health from. The
// entrypoint resolves it once (discovery shells out to gc) and passes it here, so
// build() reuses that answer instead of re-discovering on every cache refresh. An
// empty path yields no pack-health section, which is the right answer for a city
// gc could not resolve.
func WithCityPath(p string) Option {
	return func(s *Server) { s.cityPath = p }
}

// New builds a Server. ttl<=0 disables caching (every request recomputes).
func New(src source.Source, ttl time.Duration, opts ...Option) *Server {
	s := &Server{src: src, ttl: ttl, now: time.Now, gate: newActuationGate()}
	for _, opt := range opts {
		opt(s)
	}
	return s
}

// Handler returns the HTTP routes: GET /helm (and bare /) serve the board;
// GET /healthz is the liveness probe (no gather); POST /helm/{open,accept,engage,
// dismiss} are the write routes (see actuate.go). With [WithSPA] the bare mount
// also serves the app shell to browsers, and its assets beneath.
//
// Each write route is registered as its own exact pattern, which ServeMux prefers
// over the "/" catch-all — so it reaches its handler rather than the SPA handler,
// whatever the bundle does with unknown paths.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", s.handleHealth)
	mux.HandleFunc("/helm", s.handleBoard)
	mux.HandleFunc("/helm/open", s.handleOpen)
	mux.HandleFunc("/helm/accept", s.handleAccept)
	mux.HandleFunc("/helm/engage", s.handleEngage)
	mux.HandleFunc("/helm/dismiss", s.handleDismiss)
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

// invalidateBoard drops the cached board so the next read re-gathers.
//
// Written for POST /helm/open (review of PR#421, P2): a filed visit changes the
// `held` glyph and the frontier of the row it was filed on, and this service
// serves s.cached until s.expiry. `gc-helm.sh open` busts its own on-disk cache,
// which this binary never reads, so without this the operator can act on a row
// and watch the board go on saying nothing happened for up to the TTL.
//
// Deliberately a plain invalidate rather than a re-gather: the gather is the
// expensive call, the caller is holding an HTTP request open, and the next board
// read is going to pay for it anyway.
func (s *Server) invalidateBoard() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.cached = nil
	s.expiry = time.Time{}
}

// gatherTimeout bounds one gather. A healthy gather is a few seconds; this is
// generous slack that still cuts off a supervisor that has begun timing out
// every call, so a coalesced flight cannot run unbounded. The gather runs on a
// context detached from the caller's (below) precisely so that one client
// disconnecting mid-build does not cancel the shared gather the cache and the
// other coalesced waiters depend on.
const gatherTimeout = 30 * time.Second

// Board returns the cached board when fresh, otherwise gathers and computes a
// new one. The gather runs OUTSIDE the cache lock — the lock is taken only to
// read the cache and to swap the finished board in — so a slow gather never
// blocks a request a fresh cache could answer. Concurrent misses are coalesced
// by a single-flight group, so a burst of board requests drives one gather
// rather than one per request; the old design held the lock across the gather
// for that same anti-stampede reason, at the cost of serializing every request,
// even cached ones, behind the build.
func (s *Server) Board(ctx context.Context) (*board.Board, error) {
	if b, ok := s.cachedFresh(); ok {
		return b, nil
	}
	v, err, _ := s.flight.Do("board", func() (any, error) {
		// A flight that queued behind another leader may find the cache already
		// refilled; serve it rather than gathering a second time.
		if b, ok := s.cachedFresh(); ok {
			return b, nil
		}
		gctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), gatherTimeout)
		defer cancel()
		return s.gather(gctx)
	})
	if err != nil {
		return nil, err
	}
	return v.(*board.Board), nil
}

// cachedFresh returns the cached board when it exists and is within the TTL
// window. It holds the lock only for the read.
func (s *Server) cachedFresh() (*board.Board, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.cached != nil && s.ttl > 0 && s.now().Before(s.expiry) {
		return s.cached, true
	}
	return nil, false
}

// gather drives one supervisor gather, builds the board, and swaps it into the
// cache under the lock — which it takes only for the swap, never across
// s.src.Gather.
func (s *Server) gather(ctx context.Context) (*board.Board, error) {
	res, err := s.src.Gather(ctx)
	if err != nil {
		return nil, err
	}
	now := s.now()
	b := board.BuildBoard(res.Anchors, now, res.Partial, res.PartialErrors, res.Facts)
	// Read after the gather, not inside it: pack health is a handful of small
	// local files and belongs to no Source backend, so making it part of the
	// Source interface would oblige every backend to reimplement it. The city
	// root is the one resolved at startup (WithCityPath), never re-discovered
	// here — discovery is a gc subprocess and this runs on every cache refresh.
	b.PackHealth = source.GatherPackHealth(s.cityPath, now)
	s.mu.Lock()
	s.cached = &b
	s.expiry = now.Add(s.ttl)
	s.mu.Unlock()
	return &b, nil
}
