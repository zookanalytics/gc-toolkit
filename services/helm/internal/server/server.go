// Package server serves the Helm board's routes over HTTP. It is
// transport-agnostic: [Server.Handler] returns an [http.Handler] that the cmd
// wires onto a unix socket (the proxy_process contract). Requests arrive
// path-stripped — the service mounted at /v0/city/<c>/svc/helm is reached as
// GET /helm/rigs (and the bare mount as GET /).
package server

import (
	"net/http"
	"time"
)

// Server serves the rig board, the city page, the board's write routes and the
// embedded app.
type Server struct {
	now func() time.Time
	spa http.Handler

	// actuator runs the board's write verbs (open, engage) by shelling out to
	// gc-helm.sh; nil disables both routes (they then answer 503 rather than
	// 404 — see runActuation).
	actuator Actuator
	gate     *actuationGate

	// rigBoard serves the rig board's routes, GET /helm/rigs and
	// GET /helm/rigs/{rig}; nil leaves them answering 503 (see rigboard.go).
	rigBoard *rigBoard

	// cityPage serves the city page's route, GET /helm/city; nil leaves it
	// answering 503 (see citypage.go).
	cityPage *cityPage
}

// An Option configures a Server at construction.
type Option func(*Server)

// WithSPA serves the embedded single-page app: the app shell at the mount
// root, plus its assets. A nil handler is ignored, which leaves the bare mount
// answering 404 and every JSON route serving — so a bundle that fails to load
// degrades the page without taking the routes down with it.
func WithSPA(h http.Handler) Option {
	return func(s *Server) {
		if h != nil {
			s.spa = h
		}
	}
}

// WithActuator enables the board's write routes, POST /helm/{open,engage},
// each of which shells out to the matching gc-helm.sh verb (see actuate.go).
//
// It is an Option rather than a constructor argument because the write surface is
// genuinely optional: a helm-svc that cannot locate the script still serves the
// whole board, and says so honestly when a route is called. A nil actuator is
// ignored, which keeps the routes read-only.
func WithActuator(a Actuator) Option {
	return func(s *Server) {
		if a != nil {
			s.actuator = a
		}
	}
}

// New builds a Server.
func New(opts ...Option) *Server {
	s := &Server{now: time.Now, gate: newActuationGate()}
	for _, opt := range opts {
		opt(s)
	}
	return s
}

// Handler returns the HTTP routes: GET /healthz is the liveness probe;
// POST /helm/{open,engage} are the write routes (see actuate.go); GET
// /helm/rigs and GET /helm/rigs/{rig} serve the rig board (see rigboard.go);
// GET /helm/city serves the city page (see citypage.go). With [WithSPA] the
// bare mount serves the app shell, and its assets beneath.
//
// Each write route is registered as its own exact pattern, which ServeMux prefers
// over the "/" catch-all — so it reaches its handler rather than the SPA handler,
// whatever the bundle does with unknown paths.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", s.handleHealth)
	mux.HandleFunc("/helm/open", s.handleOpen)
	mux.HandleFunc("/helm/engage", s.handleEngage)
	mux.HandleFunc("GET /helm/rigs", s.handleRigs)
	mux.HandleFunc("GET /helm/rigs/{rig}", s.handleRig)
	mux.HandleFunc("GET /helm/city", s.handleCity)
	mux.HandleFunc("/", s.handleRoot)
	return mux
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_, _ = w.Write([]byte(`{"status":"ok"}`))
}

// handleRoot serves the app at the bare mount and its assets beneath it. With
// no app wired, every path that is not a route 404s, so the catch-all does not
// mask routing mistakes.
func (s *Server) handleRoot(w http.ResponseWriter, r *http.Request) {
	if s.spa == nil {
		http.NotFound(w, r)
		return
	}
	s.spa.ServeHTTP(w, r)
}

// invalidate drops the rig board's cached answers, so the next read of a rig
// gathers again. A successful write changes what the stores answer, so the
// write routes call it.
func (s *Server) invalidate() {
	if s.rigBoard != nil {
		s.rigBoard.rigs.invalidate()
		s.rigBoard.docs.invalidate()
	}
}

// gatherTimeout bounds one gather of a cached answer. The gather runs on a
// context detached from the caller's, so one client disconnecting mid-read does
// not cancel the shared gather the cache and the other waiters depend on, and
// this bound keeps such a gather from running unbounded.
const gatherTimeout = 30 * time.Second
