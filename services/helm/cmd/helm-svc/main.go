// Command helm-svc has TWO entry points over ONE board, plus a check on itself:
//
//	helm-svc            the Attention Canvas backend sidecar (default; `serve`)
//	helm-svc board      the terminal board — the CLI VIEW of the same data
//	helm-svc probe      can THIS binary read the city's bead stores? (see probe.go)
//
// They share the gather (internal/source) and the ranking (internal/board)
// rather than reimplementing either, which is the whole point: a fix to the
// board is a fix to both views. Keeping them in one binary also keeps them from
// going stale independently — see the comment atop board.go.
//
// As the sidecar, it runs as a
// Gas City `proxy_process` workspace-service: the supervisor spawns it, hands it
// a unix socket path in GC_SERVICE_SOCKET, dials that socket as a reverse proxy,
// and reaches GET /helm (the board), GET /healthz (liveness), POST /helm/open
// (file a visit on a bead — the one write route) and the embedded web app (the
// mount root, plus its assets) over it. Requests arrive already path-stripped.
//
// The service reads all bead state through the internal/source.Source seam —
// either the in-process beads library or the supervisor's loopback HTTP API,
// both Gas City interfaces, never raw Dolt — and serves a ranked board ported
// from assets/scripts/gc-helm.sh. See selectSource for which backend runs when.
package main

import (
	"context"
	"errors"
	"fmt"
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
	"github.com/zookanalytics/gc-toolkit/services/helm/internal/visit"
	"github.com/zookanalytics/gc-toolkit/services/helm/web"
)

// defaultCacheTTL matches the bash PoC's 45s file cache; override with
// GC_HELM_CACHE_TTL (seconds, or a Go duration like "30s").
const defaultCacheTTL = 45 * time.Second

// shutdownGrace is kept under the proxy_process SIGTERM→SIGKILL window (2s).
const shutdownGrace = 1500 * time.Millisecond

// defaultProbeTimeout bounds the startup readability probe in [selectSource];
// override with GC_HELM_PROBE_TIMEOUT.
//
// The listening socket is not created until selectSource returns, so this is
// readiness delay: an UNBOUNDED probe would turn a slow or wedged Dolt into a
// service that never starts, which is strictly worse than the behaviour it
// replaces (start, then fail every gather). Ten seconds is generous for a
// local Dolt connection and small beside the launcher's on-demand `go build`,
// which the supervisor already tolerates on a cold start. It is deliberately
// tighter than the 30s the launcher allows `-selfcheck`, whose caller is a
// shell willing to wait rather than a readiness window.
const defaultProbeTimeout = 10 * time.Second

func main() {
	log.SetFlags(0)
	log.SetPrefix("helm: ")

	// Subcommand dispatch. A BARE invocation still serves, because that is how
	// the supervisor spawns this binary and that contract predates the CLI.
	if len(os.Args) > 1 {
		switch os.Args[1] {
		case "board":
			boardMain(os.Args[2:])
			return
		case "probe":
			probeMain(os.Args[2:])
			return
		case "serve":
			os.Args = append(os.Args[:1], os.Args[2:]...)
		case "-h", "--help", "help":
			fmt.Print(topUsage)
			return
		default:
			fmt.Fprintf(os.Stderr, "helm-svc: unknown subcommand %q\n\n%s", os.Args[1], topUsage)
			os.Exit(2)
		}
	}

	serve()
}

const topUsage = `Usage:
  helm-svc [serve]        run the Attention Canvas backend sidecar (needs GC_SERVICE_SOCKET)
  helm-svc board [flags]  render the cross-rig attention board in the terminal
  helm-svc probe [flags]  report whether this binary can read the city's bead stores

Both views share one gather and one ranking. Run "helm-svc board --help" for
the board's flags, or "helm-svc probe --help" for the readability check.
`

func serve() {
	socket := os.Getenv("GC_SERVICE_SOCKET")
	if socket == "" {
		log.Fatal("GC_SERVICE_SOCKET is not set; run me as a proxy_process workspace-service")
	}

	ttl := cacheTTL()
	src, closeSrc := selectSource()
	defer closeSrc()
	srv := server.New(src, ttl, server.WithSPA(spaHandler()), server.WithOpener(selectOpener()))

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

// spaHandler builds the embedded single-page app's handler, or returns nil to
// serve the board JSON alone.
//
// A broken bundle must not take the service down. The board is the load-bearing
// contract — the operator curls it and the frontend units consume it — while
// the app is additive, so an unreadable bundle is logged loudly and the service
// keeps serving JSON exactly as it did before the app existed. The embed itself
// is checked at compile time, so this only fires on a dist/ that built badly.
func spaHandler() http.Handler {
	h, err := web.NewHandler()
	if err != nil {
		log.Printf("embedded web app unavailable, serving board JSON only: %v", err)
		return nil
	}
	return h
}

// selectOpener wires the board's one write route, POST /helm/open, or returns
// nil to serve the board read-only.
//
// A nil opener is NOT a failure to start. The board is the load-bearing
// contract and the write route is additive, so an unresolvable visit tool is
// logged loudly and the service keeps serving exactly as it did before the
// route existed — the same degradation rule [spaHandler] follows for a broken
// bundle. The route then answers 503 with the reason rather than 404, so an
// operator who clicks the action learns why instead of thinking it vanished.
func selectOpener() server.Opener {
	o, err := visit.New(source.DiscoverCityPath())
	if err != nil {
		log.Printf("visit filing unavailable, board is read-only: %v", err)
		return nil
	}
	log.Printf("visit tool: %s", o.Script())
	return o
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
//
// THE CHOICE IS MADE ON [source.BeadsSource.Probe], NOT Check (tk-4cqtv).
// Check resolves paths only, so the ONE failure this fallback exists for is
// invisible to it: a binary whose embedded beads library is older than the live
// stores finds every directory present, is handed the beads backend, and then
// dies inside every Gather with a schema-version mismatch. That is how a
// helm-svc reported itself healthy while all four rigs' gathers failed. Probe
// opens a store, which is where that error is raised, so the question the
// fallback answers is the question actually asked.
//
// Paying for that open at startup is affordable because it is NOT AN EXTRA
// connection: [source.BeadsSource.store] caches the handle, so the first Gather
// reuses what Probe opened. Startup pays what the first request would have paid
// anyway. Only a candidate beads backend is probed — a forced supervisor
// backend returns before this and pays nothing.
//
// A probe that fails or times out selects the supervisor, rather than refusing
// to start. A degraded board that says stale_days 0 is worth more than no board
// at all, and it preserves this entry point's contract of deciding once and
// saying so.
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
	// This deadline bounds the OPEN, not the handle it leaves behind: the beads
	// store keeps a database/sql pool and retains no context, so cancelling here
	// does not disturb the connection the first Gather goes on to reuse.
	ctx, cancel := context.WithTimeout(context.Background(), probeTimeout())
	defer cancel()
	if err := bs.Probe(ctx); err != nil {
		// bs is being discarded; release anything it managed to open. Probe
		// returns on its first success, so today this closes nothing on the
		// error path — it is here so that stays true of whoever edits Probe.
		if cerr := bs.Close(); cerr != nil {
			log.Printf("closing bead stores after a failed probe: %v", cerr)
		}
		if want == "beads" {
			// Explicitly demanded and unusable: fail loudly rather than
			// silently downgrading to a board with no staleness.
			log.Fatalf("GC_HELM_SOURCE=beads but this binary cannot read the city bead stores: %v", err)
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

// durationEnv reads an env var as either a Go duration ("30s") or a bare
// integer number of seconds, falling back to def. Anything else — including a
// negative value — is the fallback, so a typo degrades to the default rather
// than to zero.
func durationEnv(key string, def time.Duration) time.Duration {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	if d, err := time.ParseDuration(v); err == nil && d >= 0 {
		return d
	}
	if secs, err := strconv.Atoi(v); err == nil && secs >= 0 {
		return time.Duration(secs) * time.Second
	}
	return def
}

// cacheTTL reads GC_HELM_CACHE_TTL as either a Go duration ("30s") or a
// bare integer number of seconds, falling back to defaultCacheTTL. Zero is a
// meaningful setting here — it disables the cache.
func cacheTTL() time.Duration { return durationEnv("GC_HELM_CACHE_TTL", defaultCacheTTL) }

// probeTimeout reads GC_HELM_PROBE_TIMEOUT the same way, falling back to
// defaultProbeTimeout.
//
// Zero is NOT meaningful here and is coerced to the default: a zero-length
// deadline expires before the probe can open anything, so every probe would
// fail and the service would pin itself to the supervisor backend — silently
// losing the staleness lane for good, which is the opposite of a tuning knob.
func probeTimeout() time.Duration {
	if d := durationEnv("GC_HELM_PROBE_TIMEOUT", defaultProbeTimeout); d > 0 {
		return d
	}
	return defaultProbeTimeout
}
