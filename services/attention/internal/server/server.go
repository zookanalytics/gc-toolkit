// Package server exposes the attention board over HTTP with a small server-side
// TTL cache. It is transport-agnostic: [Server.Handler] returns an
// [http.Handler] that the cmd wires onto a unix socket (the proxy_process
// contract). Requests arrive path-stripped — the service mounted at
// /v0/city/<c>/svc/attention is reached as GET /attention (and the bare mount as
// GET /).
package server

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/attention/internal/board"
	"github.com/zookanalytics/gc-toolkit/services/attention/internal/source"
)

// Server computes and serves the attention board, caching the computed board for
// a TTL so polling clients do not re-drive the supervisor gather on every hit.
type Server struct {
	src source.Source
	ttl time.Duration
	now func() time.Time

	mu     sync.Mutex
	cached *board.Board
	expiry time.Time
}

// New builds a Server. ttl<=0 disables caching (every request recomputes).
func New(src source.Source, ttl time.Duration) *Server {
	return &Server{src: src, ttl: ttl, now: time.Now}
}

// Handler returns the HTTP routes: GET /attention (and bare /) serve the board;
// GET /healthz is the liveness probe (no gather).
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", s.handleHealth)
	mux.HandleFunc("/attention", s.handleBoard)
	mux.HandleFunc("/", s.handleRoot)
	return mux
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_, _ = w.Write([]byte(`{"status":"ok"}`))
}

// handleRoot serves the board at the bare mount but 404s any other path so the
// catch-all does not mask routing mistakes.
func (s *Server) handleRoot(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	s.handleBoard(w, r)
}

func (s *Server) handleBoard(w http.ResponseWriter, r *http.Request) {
	b, err := s.Board(r.Context())
	if err != nil {
		log.Printf("attention: board gather failed: %v", err)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadGateway)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": "board unavailable: " + err.Error()})
		return
	}
	w.Header().Set("Content-Type", "application/json")
	enc := json.NewEncoder(w)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(b); err != nil {
		log.Printf("attention: encode failed: %v", err)
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
	b := board.BuildBoard(res.Anchors, res.Sessions, s.now(), res.Partial, res.PartialErrors)
	s.cached = &b
	s.expiry = s.now().Add(s.ttl)
	return &b, nil
}
