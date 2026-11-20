package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/rigboard"
	"github.com/zookanalytics/gc-toolkit/services/helm/internal/source"
)

// `helm-svc board --json` prints the rig board for agents: for each rig the
// city lists, the document GET /helm/rigs/{rig} answers, read by the same
// reader (rigboard.Read), so an agent and the page read one answer. People read
// the board on the web page; this command has no terminal view.
//
// WHY IT IS THE SAME BINARY. A command built on its own would be a second
// artifact that can go stale on its own, and then the agents' read and the
// page's could come from two builds of the reader. In one binary, `serve` and
// `board` read the rig board through the one reader they were built with.
//
// WHY IT DOES NOT CALL THE SERVICE. It reads the stores itself rather than
// asking the sidecar, so it answers while the service is down, and a build from
// a working tree reads the live city through that tree's reader, which is how
// a change to the board is compared with the live city before it ships. There
// is no cache: every run reads each rig it prints.

const boardUsage = `Usage:
  helm-svc board --json [--rig=NAME] [--timeout=SECONDS]

  Print the rig board as JSON: for each rig the city lists, the document the
  Helm web page draws for it (GET /helm/rigs/{rig}), from the same reader.
  People read the board on the web page; this command has no terminal view.

  --json             Print the documents as JSON. Required.
  --rig=NAME         Read only the rig named NAME.
  --timeout=SECONDS  Bound the whole read (default 120).

Output:
  {"read_at": "<when the read ended>",
   "rigs": [{"rig": "<name>", "board": <the rig's document>}, ...]}
  The rigs are in the order the city lists them. A rig whose read failed
  carries "error", the reason, in place of "board".

Exit codes:
  0  every rig was read
  2  usage error, including a call without --json or a rig the city does not
     list
  3  a read failed: the city's rig list, when nothing is printed, or a rig's
     document, when the answer is printed and names that rig with its error
`

// noTerminalView answers a call without --json: it names where the board is,
// rather than printing it.
const noTerminalView = `helm-svc board: the board has no terminal view. Read it on the Helm web page,
which the supervisor serves at /v0/city/<city>/svc/helm/ (by default
http://127.0.0.1:8372/v0/city/<city>/svc/helm/), or pass --json for each rig's
document as JSON.
`

// boardExit* are the codes a caller switches on.
const (
	boardExitOK    = 0
	boardExitUsage = 2
	boardExitRead  = 3
)

// defaultBoardTimeout bounds the whole read. Generous on purpose: the failure
// it guards against is a wedged store, and a slow read that still answers is
// worth waiting for.
const defaultBoardTimeout = 120 * time.Second

type boardOpts struct {
	json    bool
	rig     string // empty: every rig the city lists
	timeout time.Duration
}

// errHelp is the sentinel for an explicit --help, which is a success.
var errHelp = errors.New("help requested")

// parseBoardArgs accepts both `--rig=NAME` and `--rig NAME`, and the same for
// --timeout.
func parseBoardArgs(args []string) (boardOpts, error) {
	o := boardOpts{timeout: defaultBoardTimeout}
	for len(args) > 0 {
		arg := args[0]
		args = args[1:]
		name, value, hasValue := strings.Cut(arg, "=")
		valueOf := func() (string, error) {
			if hasValue {
				return value, nil
			}
			if len(args) == 0 {
				return "", fmt.Errorf("%s requires a value", name)
			}
			v := args[0]
			args = args[1:]
			return v, nil
		}
		switch name {
		case "--json":
			o.json = true
		case "--rig":
			v, err := valueOf()
			if err != nil {
				return o, err
			}
			if strings.TrimSpace(v) == "" {
				return o, fmt.Errorf("--rig requires a rig name")
			}
			o.rig = v
		case "--timeout":
			v, err := valueOf()
			if err != nil {
				return o, err
			}
			n, err := strconv.Atoi(v)
			if err != nil || n < 0 {
				return o, fmt.Errorf("--timeout must be a non-negative integer, got %q", v)
			}
			o.timeout = time.Duration(n) * time.Second
		case "-h", "--help":
			return o, errHelp
		default:
			return o, fmt.Errorf("unknown flag %q", arg)
		}
	}
	return o, nil
}

// boardAnswer is what `board --json` prints: when the read ended, and each
// rig's part.
type boardAnswer struct {
	ReadAt string      `json:"read_at"`
	Rigs   []rigAnswer `json:"rigs"`
}

// rigAnswer is one rig's part of the answer: its document, as
// GET /helm/rigs/{rig} answers it, or the error its read returned in place of
// one.
type rigAnswer struct {
	Rig   string             `json:"rig"`
	Board *rigboard.Document `json:"board,omitempty"`
	Error string             `json:"error,omitempty"`
}

// boardReader is what the command reads through: the city's rigs as gc lists
// them, and one rig's document. runBoard reads the live city, and a test hands
// in fakes.
type boardReader struct {
	// gc returns the gc command the rig list is read through. It is called only
	// once the arguments parse, because finding the city can itself run gc.
	gc   func() rigboard.GC
	read func(ctx context.Context, rig rigboard.Rig) (rigboard.Document, error)
	now  func() time.Time
}

// runBoard is the `board` entry point over the live city. It returns a process
// exit code rather than calling os.Exit so it stays testable.
func runBoard(args []string, stdout, stderr io.Writer) int {
	r := boardReader{
		gc:   func() rigboard.GC { return source.NewGC(source.DiscoverCityPath()) },
		read: rigboard.Read,
		now:  time.Now,
	}
	return r.run(args, stdout, stderr)
}

func (r boardReader) run(args []string, stdout, stderr io.Writer) int {
	opts, err := parseBoardArgs(args)
	if errors.Is(err, errHelp) {
		fmt.Fprint(stdout, boardUsage)
		return boardExitOK
	}
	if err != nil {
		fmt.Fprintf(stderr, "helm-svc board: %v\n\n%s", err, boardUsage)
		return boardExitUsage
	}
	if !opts.json {
		// Before the read: a call that would print nothing pays for nothing.
		fmt.Fprint(stderr, noTerminalView)
		return boardExitUsage
	}

	ctx, cancel := context.WithTimeout(context.Background(), opts.timeout)
	defer cancel()

	rigs, err := rigboard.ReadRigs(ctx, r.gc())
	if err != nil {
		fmt.Fprintf(stderr, "helm-svc board: cannot list the city's rigs: %v\n", err)
		return boardExitRead
	}
	if opts.rig != "" {
		one, ok := rigNamed(rigs, opts.rig)
		if !ok {
			fmt.Fprintf(stderr, "helm-svc board: the city lists no rig named %q; its rigs are %s\n",
				opts.rig, strings.Join(rigNames(rigs), ", "))
			return boardExitUsage
		}
		rigs = []rigboard.Rig{one}
	}

	answer := boardAnswer{Rigs: make([]rigAnswer, 0, len(rigs))}
	failed := false
	for _, rig := range rigs {
		doc, err := r.read(ctx, rig)
		if err != nil {
			// A rig that could not be read is named with why, never printed as
			// a board with nothing on it.
			answer.Rigs = append(answer.Rigs, rigAnswer{Rig: rig.Name, Error: err.Error()})
			failed = true
			continue
		}
		answer.Rigs = append(answer.Rigs, rigAnswer{Rig: rig.Name, Board: &doc})
	}
	answer.ReadAt = r.now().UTC().Format(time.RFC3339)

	enc := json.NewEncoder(stdout)
	enc.SetEscapeHTML(false) // as the service's answers are encoded
	enc.SetIndent("", "  ")
	if err := enc.Encode(answer); err != nil {
		fmt.Fprintf(stderr, "helm-svc board: encoding the board: %v\n", err)
		return boardExitRead
	}
	if failed {
		return boardExitRead
	}
	return boardExitOK
}

// rigNamed finds the rig the city lists by name.
func rigNamed(rigs []rigboard.Rig, name string) (rigboard.Rig, bool) {
	for _, rig := range rigs {
		if rig.Name == name {
			return rig, true
		}
	}
	return rigboard.Rig{}, false
}

func rigNames(rigs []rigboard.Rig) []string {
	out := make([]string, 0, len(rigs))
	for _, rig := range rigs {
		out = append(out, rig.Name)
	}
	return out
}

// boardMain is the os.Exit-calling wrapper main() dispatches to.
func boardMain(args []string) {
	os.Exit(runBoard(args, os.Stdout, os.Stderr))
}
