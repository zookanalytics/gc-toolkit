package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/board"
	"github.com/zookanalytics/gc-toolkit/services/helm/internal/source"
)

// `helm-svc board --json` prints the board's rows as JSON, for agents and
// tooling: the same gather and the same derivation the web page serves. People
// read the board on the web page; this command has no terminal view.
//
// WHY IT IS THE SAME BINARY. The obvious alternative — a separate `helm-board`
// built alongside — re-creates exactly the failure that motivated this epic:
// helm-svc served a ten-day-stale artifact because its rebuild failed silently
// (tk-5nm0p), and a second independently-built artifact is a second thing that
// can go stale on its own. One build, one artifact, two entry points: `serve`
// and `board` cannot disagree about the board because there is only one of it.
//
// WHY IT DOES NOT CALL THE SERVICE. It gathers directly through
// internal/source rather than asking the sidecar, so it reads the city while
// the service is down, and a build from a working tree reads the live city
// through that tree's gather and derivation, which is how a board change is
// compared against the live city before it ships. There is no daemon and no
// cache: every run pays the full gather.
//
// THE --json CONTRACT. The output is a ranked JSON ARRAY of tiles, not the
// service's {generated_at,total,tiles} envelope: a caller counts the rows with
// `jq length` and walks them with `.[]`, and the envelope would make every row
// invisible while still parsing cleanly. An empty board is `[]`, never `null`.
//
// WHAT THE DEFAULT ANSWERS. The operator's queue (board.OperatorQueue), not the
// city overview. The two are different questions: the overview ranks every
// anchor together, where a demand owed by a person carries a subtree of one and
// a stranded container carries hundreds, so the queue is buried under the
// overview by construction rather than by accident. `--all` is the overview,
// and it is the only way to it.

const boardUsage = `Usage:
  helm-svc board --json [--all] [--limit=N] [--timeout=SECONDS]

  Print the board's rows as a JSON array: what is owed by you, oldest first
  after any conversation whose sitting failed to start. It is the same gather
  and derivation the Helm web page serves. People read the board on that page;
  this command has no terminal view.

  --json             Print the rows as a JSON array (stable contract). Required.
  --all              The city overview instead: every anchor, ranked together.
  --limit=N          Only the top N rows (0 = all/uncapped; default caps at 50).
  --timeout=SECONDS  Bound the whole gather (default 120).

Exit codes:
  0  rows printed
  2  usage error, including a call without --json
  3  the gather failed, or an empty queue could not be asserted (never
     printed as an empty array)
`

// noTerminalView answers a call without --json: it names where the board is,
// rather than printing it.
const noTerminalView = `helm-svc board: the board has no terminal view. Read it on the Helm web page,
which the supervisor serves at /v0/city/<city>/svc/helm/ (by default
http://127.0.0.1:8372/v0/city/<city>/svc/helm/), or pass --json for its rows
as a JSON array.
`

// boardExit* are the codes a caller switches on.
const (
	boardExitOK     = 0
	boardExitUsage  = 2
	boardExitGather = 3
)

// defaultBoardTimeout bounds the whole gather. Generous on purpose: the failure
// it guards against is a wedged Dolt, and cutting a slow-but-working gather
// short would report "nothing needs attention" — the one answer this board must
// never invent.
const defaultBoardTimeout = 120 * time.Second

type boardOpts struct {
	all     bool
	json    bool
	limit   int // -1 = unset (use the default cap); 0 = uncapped
	timeout time.Duration
}

// parseBoardArgs accepts both `--limit=N` and `--limit N`, and the same for
// --timeout.
func parseBoardArgs(args []string) (boardOpts, error) {
	o := boardOpts{limit: -1, timeout: defaultBoardTimeout}

	intFlag := func(name, raw string, rest *[]string) (int, error) {
		if raw == "" {
			if len(*rest) == 0 {
				return 0, fmt.Errorf("%s requires a value", name)
			}
			raw = (*rest)[0]
			*rest = (*rest)[1:]
		}
		n, err := strconv.Atoi(raw)
		if err != nil || n < 0 {
			return 0, fmt.Errorf("%s must be a non-negative integer, got %q", name, raw)
		}
		return n, nil
	}

	for len(args) > 0 {
		arg := args[0]
		args = args[1:]
		name, value, hasValue := strings.Cut(arg, "=")
		if !hasValue {
			value = ""
		}
		switch name {
		case "--all":
			o.all = true
		case "--json":
			o.json = true
		case "--limit":
			n, err := intFlag("--limit", value, &args)
			if err != nil {
				return o, err
			}
			o.limit = n
		case "--timeout":
			n, err := intFlag("--timeout", value, &args)
			if err != nil {
				return o, err
			}
			o.timeout = time.Duration(n) * time.Second
		case "-h", "--help":
			return o, flagHelp
		default:
			return o, fmt.Errorf("unknown flag %q", arg)
		}
	}
	return o, nil
}

// flagHelp is the sentinel for an explicit --help, which is a success.
var flagHelp = fmt.Errorf("help requested")

// runBoard is the `board` entry point. It returns a process exit code rather
// than calling os.Exit so it stays testable.
func runBoard(args []string, stdout, stderr io.Writer) int {
	opts, err := parseBoardArgs(args)
	if err == flagHelp {
		fmt.Fprint(stdout, boardUsage)
		return boardExitOK
	}
	if err != nil {
		fmt.Fprintf(stderr, "helm-svc board: %v\n\n%s", err, boardUsage)
		return boardExitUsage
	}
	if !opts.json {
		// Before the gather: a call that would print nothing pays for nothing.
		fmt.Fprint(stderr, noTerminalView)
		return boardExitUsage
	}

	src := source.NewBeadsSource(source.WithCityPath(source.DiscoverCityPath()))
	if err := src.Check(); err != nil {
		// Fail loudly. The alternative — falling back to the supervisor HTTP
		// API — would make this read depend on a live sidecar, which is the
		// dependency this entry point exists to avoid, and would silently drop
		// staleness (the API omits updated_at).
		fmt.Fprintf(stderr, "helm-svc board: cannot read the city's bead stores: %v\n", err)
		return boardExitGather
	}
	defer func() { _ = src.Close() }()

	ctx, cancel := context.WithTimeout(context.Background(), opts.timeout)
	defer cancel()

	res, err := src.Gather(ctx)
	if err != nil {
		// A failed gather is NEVER printed as an empty board: "0 anchors" and
		// "we could not look" are opposite answers and only one of them means
		// nothing needs you.
		fmt.Fprintf(stderr, "helm-svc board: gather failed: %v\n", err)
		return boardExitGather
	}

	b := board.BuildBoard(res.Anchors, time.Now().UTC(), res.Partial, res.PartialErrors, res.Facts)

	limit := opts.limit
	if limit < 0 {
		limit = board.DefaultMaxRows
	}

	v := selectView(b, opts.all, limit)
	if v.unprovable {
		fmt.Fprintf(stderr, "helm-svc board: the gather was PARTIAL, so an empty queue proves nothing — %s\n",
			strings.Join(b.PartialErrors, "; "))
		return boardExitGather
	}
	return renderJSON(stdout, stderr, v.rows)
}

// boardView is the rows one run prints.
type boardView struct {
	rows []board.Tile
	// unprovable marks an empty QUEUE that came out of a partial gather.
	// "Nothing is owed by you" is the most consequential answer this command
	// gives, and the rows that would have contradicted it are exactly the ones
	// the unread store was holding — so its emptiness is a failure to look, and
	// exits like one. A non-empty queue still prints: those rows were read.
	unprovable bool
}

// selectView answers the flag: the operator's queue, or the city overview.
func selectView(b board.Board, all bool, limit int) boardView {
	if all {
		return boardView{rows: board.CapFamilies(board.CityOverview(b.Tiles), limit, board.DefaultMaxDone)}
	}
	rows := board.CapQueue(board.OperatorQueue(b.Tiles), limit)
	return boardView{rows: rows, unprovable: len(rows) == 0 && b.Partial}
}

// renderJSON writes the ranked array — the --json contract.
func renderJSON(stdout, stderr io.Writer, tiles []board.Tile) int {
	if tiles == nil {
		// `[]`, never `null`: a caller counts the rows with `jq length`, and a
		// null would make an empty board an error instead of a quiet one.
		tiles = []board.Tile{}
	}
	enc := json.NewEncoder(stdout)
	enc.SetEscapeHTML(false) // matches server.handleBoard
	enc.SetIndent("", "  ")
	if err := enc.Encode(tiles); err != nil {
		fmt.Fprintf(stderr, "helm-svc board: encoding the board: %v\n", err)
		return boardExitGather
	}
	return boardExitOK
}

// boardMain is the os.Exit-calling wrapper main() dispatches to.
func boardMain(args []string) {
	os.Exit(runBoard(args, os.Stdout, os.Stderr))
}
