// Command helm-svc is the Attention Canvas backend sidecar. It runs as a
// Gas City `proxy_process` workspace-service: the supervisor spawns it, hands it
// a unix socket path in GC_SERVICE_SOCKET, dials that socket as a reverse proxy,
// and reaches GET /helm (the board) and GET /healthz (liveness) over it.
// Requests arrive already path-stripped.
//
// The service reads all bead state through the internal/source.Source seam —
// either the in-process beads library or the supervisor's loopback HTTP API,
// both Gas City interfaces, never raw Dolt — and serves a ranked board ported
// from assets/scripts/gc-helm.sh. See selectSource for which backend runs when.
package main

import (
	"context"
	"errors"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/server"
	"github.com/zookanalytics/gc-toolkit/services/helm/internal/source"
)

// defaultCacheTTL matches the bash PoC's 45s file cache; override with
// GC_HELM_CACHE_TTL (seconds, or a Go duration like "30s").
const defaultCacheTTL = 45 * time.Second

// shutdownGrace is kept under the proxy_process SIGTERM→SIGKILL window (2s).
const shutdownGrace = 1500 * time.Millisecond

func main() {
	log.SetFlags(0)
	log.SetPrefix("helm: ")

	socket := os.Getenv("GC_SERVICE_SOCKET")
	if socket == "" {
		log.Fatal("GC_SERVICE_SOCKET is not set; run me as a proxy_process workspace-service")
	}

	ttl := cacheTTL()
	src, closeSrc := selectSource()
	defer closeSrc()
	srv := server.New(src, ttl)

	// The supervisor removes any stale socket before spawning us, so we own
	// creation. net.Listen("unix") unlinks the socket on close.
	ln, err := net.Listen("unix", socket)
	if err != nil {
		log.Fatalf("listen unix %s: %v", socket, err)
	}

	httpServer := &http.Server{
		Handler:           srv.Handler(),
		ReadHeaderTimeout: 5 * time.Second,
	}

	// proxy_process stops us with SIGTERM (then SIGKILL after 2s); shut down the
	// HTTP server cleanly within the grace window.
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()
	go func() {
		<-ctx.Done()
		log.Print("signal received, shutting down")
		shutCtx, cancel := context.WithTimeout(context.Background(), shutdownGrace)
		defer cancel()
		_ = httpServer.Shutdown(shutCtx)
	}()

	log.Printf("serving Helm board on %s (cache ttl %s)", socket, ttl)
	if err := httpServer.Serve(ln); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("serve: %v", err)
	}
	log.Print("shut down cleanly")
}

// selectSource picks the data-access backend and returns it with a cleanup
// func. Both options honour the data-access contract; they differ in what they
// can SEE (tk-x89rn):
//
//   - "beads" (default) reads each rig's own store through the in-process beads
//     library. It is the only backend that carries updated_at, so it is the only
//     one under which stale_days is real and the NORMAL→ELEVATED stale bump can
//     fire. It needs the city root on disk.
//   - "supervisor" reads the loopback HTTP API. Nothing on that API supplies
//     updated_at, so under it every tile reports stale_days 0 and no tile ever
//     ages. Kept as the fallback for an environment with no readable city root.
//
// The choice is made ONCE, at startup, and logged — never silently per request.
// A per-request fallback would let a board quietly lose its staleness lane and
// still look healthy, which is the exact failure this bead exists to end.
// GC_HELM_SOURCE forces either backend.
func selectSource() (source.Source, func()) {
	noop := func() {}
	want := strings.ToLower(strings.TrimSpace(os.Getenv("GC_HELM_SOURCE")))

	switch want {
	case "", "beads", "supervisor":
	default:
		// A typo must not quietly select a backend nobody asked for.
		log.Printf("GC_HELM_SOURCE=%q is not a known backend (want beads|supervisor); using the default", want)
		want = ""
	}

	if want == "supervisor" {
		log.Print("source: supervisor HTTP API (forced by GC_HELM_SOURCE); stale_days will be 0 — the API omits updated_at")
		return source.NewSupervisorSource(), noop
	}

	bs := source.NewBeadsSource()
	if err := bs.Check(); err != nil {
		if want == "beads" {
			// Explicitly demanded and unavailable: fail loudly rather than
			// silently downgrading to a board with no staleness.
			log.Fatalf("GC_HELM_SOURCE=beads but the city bead stores are unreadable: %v", err)
		}
		log.Printf("source: falling back to the supervisor HTTP API (%v); stale_days will be 0 — the API omits updated_at", err)
		return source.NewSupervisorSource(), noop
	}
	log.Print("source: in-process beads library over the city's per-rig stores")
	return bs, func() {
		if err := bs.Close(); err != nil {
			log.Printf("closing bead stores: %v", err)
		}
	}
}

// cacheTTL reads GC_HELM_CACHE_TTL as either a Go duration ("30s") or a
// bare integer number of seconds, falling back to defaultCacheTTL.
func cacheTTL() time.Duration {
	v := os.Getenv("GC_HELM_CACHE_TTL")
	if v == "" {
		return defaultCacheTTL
	}
	if d, err := time.ParseDuration(v); err == nil && d >= 0 {
		return d
	}
	if secs, err := strconv.Atoi(v); err == nil && secs >= 0 {
		return time.Duration(secs) * time.Second
	}
	return defaultCacheTTL
}
