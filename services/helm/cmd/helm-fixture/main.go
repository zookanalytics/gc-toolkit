// Command helm-fixture serves the Helm board on fixture data: the app this
// commit embeds, a board answer read from a file, one rig's document read from a
// file at the rig board's routes, and canned answers for the write verbs (see
// package fixture). The serve command the rig declares runs it, and a demo
// capture of the board passes that command to demo-screenshot.sh as its --serve
// command, as docs/review-demo.md shows, so the capture shows the board the
// reviewed commit builds and never reaches the live city. A live copy of the
// board runs the same command (assets/scripts/ui-copy.sh).
//
// It is a command of its own rather than a helm-svc subcommand. helm-svc links
// the beads library and, through Dolt, cgo and ICU, so a cold build takes minutes
// (assets/scripts/gc-build.sh), longer than the 30 s the engine waits for a
// --serve command to answer. This command imports package fixture, the app's
// package and the standard library only, so `go run` starts it in seconds with
// no cgo flags, and it links nothing that could read or write a city.
//
// Usage:
//
//	helm-fixture [--board <file>] [--rig-board <file>] [--answers <dir>] [--addr <host:port>]
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

// defaultBoard is the contract sample TestBoardFixture writes from the Go types,
// relative to the module root, the directory the command runs from.
const defaultBoard = "web/src/board.fixture.json"

// defaultRigBoard is the document the rig read builds from the committed
// gc-toolkit fixture, which TestFixtureBoard holds, relative to the module root.
const defaultRigBoard = "internal/rigboard/testdata/gc-toolkit.board.json"

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
	board := flags.String("board", defaultBoard,
		"the board answer to serve at /helm, in the shape web/src/contract.ts names")
	rigBoard := flags.String("rig-board", defaultRigBoard,
		"one rig's document to serve at /helm/rigs/{rig}, in the shape web/src/rigboard/document.gen.ts names")
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
			logger.Print("no address to listen on: pass --addr, or set PORT, which demo-screenshot.sh's --port 0 sets")
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

	body, err := os.ReadFile(*board)
	if err != nil {
		logger.Printf("read the board answer: %v", err)
		return 1
	}
	rig, err := os.ReadFile(*rigBoard)
	if err != nil {
		logger.Printf("read the rig document: %v", err)
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
	h, err := fixture.Handler(body, rig, answers, spa)
	if err != nil {
		logger.Printf("%s, %s: %v", *board, *rigBoard, err)
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
	logger.Printf("serving %s and %s with %d canned answer(s) on http://%s", *board, *rigBoard, len(answers), ln.Addr())
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
