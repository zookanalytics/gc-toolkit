// Command helm-svc serves the Helm board, and prints it for agents:
//
//	helm-svc               the Attention Canvas backend sidecar (default; `serve`)
//	helm-svc board --json  each rig's board document as JSON, for agents and tooling
//	helm-svc form          the terminal conversation form gc-helm.sh opens
//
// The sidecar and `board --json` share the rig board's reader
// (internal/rigboard) rather than reimplementing it, so the document
// `board --json` prints for a rig is the one the sidecar's GET /helm/rigs/{rig}
// serves. Keeping them in one binary also keeps them from going stale
// independently — see the comment atop board.go.
//
// As the sidecar, it runs as a Gas City `proxy_process` workspace-service: the
// supervisor spawns it, hands it a unix socket path in GC_SERVICE_SOCKET, dials
// that socket as a reverse proxy, and reaches GET /healthz (liveness), the
// rig board's GET /helm/rigs and GET /helm/rigs/{rig}, the city page's GET
// /helm/city, the write routes POST /helm/{open,engage}, and the embedded web
// app (the mount root, plus its assets) over it. Requests arrive already
// path-stripped.
//
// The rig board reads each rig's store through the gc command
// (internal/rigboard), and the city page reads the supervisor's event log
// (internal/source).
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
	"syscall"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/server"
	"github.com/zookanalytics/gc-toolkit/services/helm/internal/source"
	"github.com/zookanalytics/gc-toolkit/services/helm/internal/verbs"
	"github.com/zookanalytics/gc-toolkit/services/helm/web"
)

// shutdownGrace is how long a stop gives open requests to finish. Gas City's
// proxy_process stops the board with a SIGTERM to its process group and kills
// what is left of the group 2 seconds later, so the grace ends before that.
const shutdownGrace = 1500 * time.Millisecond

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
		case "form":
			formMain(os.Args[2:])
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
  helm-svc [serve]               run the Attention Canvas backend sidecar (needs GC_SERVICE_SOCKET)
  helm-svc board --json [flags]  print each rig's board document as JSON
  helm-svc form --helm <script>  the terminal conversation form gc-helm.sh engage and attach open

"board --json" prints, for each rig, the document the sidecar's
/helm/rigs/{rig} answer serves, from the same reader. Run "helm-svc board
--help" for the board's flags.
`

func serve() {
	socket := os.Getenv("GC_SERVICE_SOCKET")
	if socket == "" {
		log.Fatal("GC_SERVICE_SOCKET is not set; run me as a proxy_process workspace-service")
	}

	// Resolve the city once. Discovery shells out to gc, and the rig board's
	// reads and the verb runner must name the same city — so resolve it here and
	// thread it, rather than have each rediscover.
	cityPath := source.DiscoverCityPath()
	srv := server.New(
		server.WithSPA(spaHandler()),
		server.WithActuator(selectActuator(cityPath)),
		server.WithRigBoard(source.NewGC(cityPath), server.RigBoardTTL),
		server.WithCityPage(source.NewEventLog(), source.NewMailCount(), server.CityPageTTL),
	)

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

	// proxy_process stops the board with a SIGTERM, and a terminal's Ctrl-C
	// sends a SIGINT. Either one ends ctx, and serveUntil then stops the board.
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	log.Printf("serving Helm board on %s", socket)
	if err := serveUntil(ctx, httpServer, ln, srv); err != nil {
		log.Fatalf("serve: %v", err)
	}
}

// serveUntil serves the board on ln until ctx ends, then stops it and returns
// once the stop is done. srv.StopGathers ends every gather in flight, a rig's
// store reads among them, and waits for each to return, while Shutdown closes
// the listener and gives every open request up to shutdownGrace to finish. It
// logs whether every open request finished within the grace, and returns an
// error only when serving failed for a reason other than the stop.
func serveUntil(ctx context.Context, hs *http.Server, ln net.Listener, srv *server.Server) error {
	served := make(chan error, 1)
	go func() { served <- hs.Serve(ln) }()
	select {
	case err := <-served:
		srv.StopGathers()
		return err
	case <-ctx.Done():
	}

	log.Print("signal received, shutting down")
	drainCtx, cancel := context.WithTimeout(context.Background(), shutdownGrace)
	defer cancel()
	drained := make(chan error, 1)
	go func() { drained <- hs.Shutdown(drainCtx) }()
	srv.StopGathers()
	if err := <-drained; err != nil {
		log.Printf("shut down with requests still open after %s: %v", shutdownGrace, err)
	} else {
		log.Print("shut down cleanly")
	}
	if err := <-served; !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}

// spaHandler builds the embedded single-page app's handler, or returns nil to
// serve the JSON routes alone.
//
// A broken bundle must not take the service down: an unreadable bundle is
// logged loudly and the service keeps serving the JSON routes the app reads.
// The embed itself is checked at compile time, so this only fires on a dist/
// that built badly.
func spaHandler() http.Handler {
	h, err := web.NewHandler()
	if err != nil {
		log.Printf("embedded web app unavailable, serving the JSON routes only: %v", err)
		return nil
	}
	return h
}

// selectActuator wires the board's write routes, POST /helm/{open,engage}, or
// returns nil to serve the board read-only.
//
// A nil actuator is NOT a failure to start. The board is the load-bearing
// contract and the write routes are additive, so an unresolvable gc-helm.sh is
// logged loudly and the service keeps serving exactly as it did before the routes
// existed — the same degradation rule [spaHandler] follows for a broken bundle.
// The routes then answer 503 with the reason rather than 404, so an operator who
// clicks an action learns why instead of thinking it vanished.
func selectActuator(cityPath string) server.Actuator {
	a, err := verbs.New(cityPath)
	if err != nil {
		log.Printf("board actuation unavailable, board is read-only: %v", err)
		return nil
	}
	log.Printf("write tool: %s", a.Script())
	return a
}
