// Command helm-fixture serves the Helm board on fixture data: the app this
// commit embeds, one rig's document read from a file at the rig board's routes,
// the city's document read from a file at the city page's route, and canned
// answers for the write verbs (see package fixture). The serve command the rig declares runs it, and a demo
// capture of the board passes that command to demo-screenshot.sh as its --serve
// command, as docs/review-demo.md shows, so the capture shows the board the
// reviewed commit builds and never reaches the live city. The capture serves it
// as a copy that `gctk rig serve` runs, and a sitting's live copy of the board
// runs the same command through the same verb.
//
// It is a command of its own rather than a helm-svc subcommand. helm-svc reads
// the city through gc and writes through gc-helm.sh, while this command imports
// package fixture, the app's package and the standard library only, so it links
// nothing that could read or write a city, and `go run` starts it in seconds.
//
// Usage:
//
//	helm-fixture [--rig-board <file>] [--city <file>] [--answers <dir>] [--addr <host:port>]
//
// Exit: 0 after a clean shutdown on SIGTERM or SIGINT, 1 when the fixture cannot
// start or serve, 2 bad arguments.
package main

import (
	"context"
	"errors"
	"flag"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/fixture"
	"github.com/zookanalytics/gc-toolkit/services/helm/web"
)

// defaultRigBoard is the document the rig read builds from the committed
// gc-toolkit fixture, which TestFixtureBoard holds, relative to services/helm,
// the directory the command runs from.
const defaultRigBoard = "internal/rigboard/testdata/gc-toolkit.board.json"

// defaultCity is the document the city's read builds from a live city's newest
// doctor run, which TestTheLiveRunsPage holds, relative to the module root.
const defaultCity = "internal/cityboard/testdata/city.json"

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, os.Interrupt)
	defer stop()
	os.Exit(run(ctx, os.Args[1:], os.Getenv, os.Stderr, nil))
}

// run serves the fixture until ctx ends and returns the exit code. ready, when
// not nil, receives the address the fixture listens on once it accepts
// connections.
func run(ctx context.Context, args []string, getenv func(string) string, stderr io.Writer, ready chan<- string) int {
	logger := log.New(stderr, "helm-fixture: ", 0)
	flags := flag.NewFlagSet("helm-fixture", flag.ContinueOnError)
	flags.SetOutput(stderr)
	rigBoard := flags.String("rig-board", defaultRigBoard,
		"one rig's document to serve at /helm/rigs/{rig}, in the shape web/src/rigboard/document.gen.ts names")
	cityDoc := flags.String("city", defaultCity,
		"the city's document to serve at /helm/city, in the shape web/src/cityboard/document.gen.ts names")
	answersDir := flags.String("answers", "",
		"a directory of canned write answers: <verb>.json answers that verb with 200, <verb>.<status>.json with that status")
	addr := flags.String("addr", "",
		"the loopback host:port to listen on (default 127.0.0.1:$PORT)")
	if err := flags.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return 0
		}
		return 2
	}
	if flags.NArg() > 0 {
		logger.Printf("takes no arguments (got %q)", flags.Args())
		return 2
	}
	if *addr == "" {
		port := getenv("PORT")
		if port == "" {
			logger.Print("no address to listen on: pass --addr, or set PORT, which gctk rig serve sets for a copy")
			return 2
		}
		*addr = net.JoinHostPort("127.0.0.1", port)
	}
	host, _, err := net.SplitHostPort(*addr)
	if err != nil {
		logger.Printf("--addr %q is not host:port: %v", *addr, err)
		return 2
	}
	switch host {
	case "127.0.0.1", "::1", "localhost":
	default:
		logger.Printf("--addr %q is not a loopback address; the fixture serves this host only", *addr)
		return 2
	}

	rig, err := os.ReadFile(*rigBoard)
	if err != nil {
		logger.Printf("read the rig document: %v", err)
		return 1
	}
	city, err := os.ReadFile(*cityDoc)
	if err != nil {
		logger.Printf("read the city document: %v", err)
		return 1
	}
	answers := map[string]fixture.Answer{}
	if *answersDir != "" {
		if answers, err = fixture.LoadAnswers(*answersDir); err != nil {
			logger.Print(err)
			return 1
		}
	}
	spa, err := web.NewHandler()
	if err != nil {
		logger.Printf("the embedded app: %v", err)
		return 1
	}
	h, err := fixture.Handler(rig, city, answers, spa)
	if err != nil {
		logger.Printf("%s, %s: %v", *rigBoard, *cityDoc, err)
		return 1
	}

	ln, err := net.Listen("tcp", *addr)
	if err != nil {
		logger.Printf("listen on %s: %v", *addr, err)
		return 1
	}
	srv := &http.Server{Handler: h, ReadHeaderTimeout: 5 * time.Second}
	served := make(chan error, 1)
	go func() { served <- srv.Serve(ln) }()
	logger.Printf("serving %s and %s with %d canned answer(s) on http://%s", *rigBoard, *cityDoc, len(answers), ln.Addr())
	if ready != nil {
		ready <- ln.Addr().String()
	}

	select {
	case err := <-served:
		logger.Printf("serve: %v", err)
		return 1
	case <-ctx.Done():
	}
	shutCtx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutCtx); err != nil {
		logger.Printf("shut down: %v", err)
		return 1
	}
	return 0
}
