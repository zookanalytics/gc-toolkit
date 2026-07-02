// Command helm-svc is the Attention Canvas backend sidecar. It runs as a
// Gas City `proxy_process` workspace-service: the supervisor spawns it, hands it
// a unix socket path in GC_SERVICE_SOCKET, dials that socket as a reverse proxy,
// and reaches GET /helm (the board) and GET /healthz (liveness) over it.
// Requests arrive already path-stripped.
//
// The service sources all data through the supervisor's loopback HTTP API (a Gas
// City API) — never raw Dolt — via the internal/source.Source seam, and serves a
// ranked board ported from assets/scripts/gc-helm.sh.
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
	src := source.NewSupervisorSource()
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
