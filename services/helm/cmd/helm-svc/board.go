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

// `helm-svc board` is the CLI VIEW of the board — the second renderer over the
// same gather and the same derivation the dashboard serves.
//
// WHY IT IS THE SAME BINARY. The obvious alternative — a separate `helm-board`
// built alongside — re-creates exactly the failure that motivated this epic:
// helm-svc served a ten-day-stale artifact because its rebuild failed silently
// (tk-5nm0p), and a second independently-built artifact is a second thing that
// can go stale on its own. One build, one artifact, two entry points: `serve`
// and `board` cannot disagree about the board because there is only one of it.
//
// WHY IT DOES NOT CALL THE SERVICE. `prefix+b` has to work when helm-svc is
// down — that is most of the point of having a CLI — so this gathers directly
// through internal/source rather than curling the sidecar. There is no daemon
// and no cache here: a cold run pays the full gather every time, which is the
// honest cost of not depending on anything. The cheap layer for a repeat glance
// lives one level up, in assets/scripts/gc-helm.sh, which caches this
// subcommand's rendered OUTPUT for 45s — that is the only place that can tell a
// repeat glance from a first one, and it is what the tmux picker hits.
//
// THE --json CONTRACT. The output is a ranked JSON ARRAY of tiles, not the
// service's {generated_at,total,tiles} envelope, because that array is what
// assets/scripts/tmux-pick-helm.sh consumes — through gc-helm.sh, which since
// tk-clvkf6 renders it by running this. There is no longer a second board to be
// at parity WITH; what board_cli_test.go pins is this renderer's own contract,
// including the six fields the picker dereferences.

const boardUsage = `Usage:
  helm-svc board [--json] [--limit=N] [--timeout=SECONDS]

  Cross-rig human-attention board — the CLI view of the same gather and
  ranking the Helm dashboard serves.

  --json             Emit the ranked board as a JSON array (stable contract).
  --limit=N          Show only the top N rows (0 = all/uncapped; default caps at 50).
  --timeout=SECONDS  Bound the whole gather (default 120).
  --refresh          Accepted and ignored: this path has no cache to bust.

Exit codes:
  0  board rendered
  2  usage error
  3  the gather failed (never rendered as an empty "all clear")
`

// boardExit* mirror gc-helm.sh's exit codes so a caller can switch on them
// identically whichever board it ran.
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
	json    bool
	limit   int // -1 = unset (use the default cap); 0 = uncapped
	timeout time.Duration
}

// parseBoardArgs accepts the gc-helm.sh flag spellings, including both
// `--limit=N` and `--limit N`.
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
		case "--json":
			o.json = true
		case "--refresh":
			// No cache on this path; accepted so a caller can pass the bash
			// board's flags unchanged.
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

	src := source.NewBeadsSource()
	if err := src.Check(); err != nil {
		// Fail loudly. The alternative — falling back to the supervisor HTTP
		// API — would make `prefix+b` depend on a live sidecar, which is the
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
		// A failed gather is NEVER rendered as an empty board: "0 anchors" and
		// "we could not look" are opposite answers and only one of them means
		// nothing needs you.
		fmt.Fprintf(stderr, "helm-svc board: gather failed: %v\n", err)
		return boardExitGather
	}

	now := time.Now().UTC()
	b := board.BuildBoard(res.Anchors, now, res.Partial, res.PartialErrors, res.Facts)

	limit := opts.limit
	if limit < 0 {
		limit = intEnv("GC_HELM_MAX_ROWS", board.DefaultMaxRows)
	}
	shown := board.CapRows(b.Tiles, limit, intEnv("GC_HELM_MAX_PARKED", board.DefaultMaxParked))

	if opts.json {
		return renderJSON(stdout, stderr, shown)
	}
	renderTable(stdout, b, shown, now, len(res.Facts.RigNames))
	if b.Partial {
		// stderr, not stdout: the table is a contract for human eyes and the
		// JSON is one for tooling; neither should grow a diagnostic line.
		fmt.Fprintf(stderr, "helm-svc board: PARTIAL gather — %s\n", strings.Join(b.PartialErrors, "; "))
	}
	return boardExitOK
}

// renderJSON writes the ranked array — the gc-helm.sh --json contract.
func renderJSON(stdout, stderr io.Writer, tiles []board.Tile) int {
	if tiles == nil {
		// `[]`, never `null`: the picker runs `jq 'length'` over this and a null
		// would make an empty board an error instead of a quiet one.
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

// rpad truncates to w and pads to width, counting RUNES rather than bytes.
// gc-helm.sh's jq `rpad` measures in codepoints, and the board is full of
// multi-byte glyphs (·, —, ●), so byte-counting would ragged every column that
// contains one. The truncation is for the prose columns only — the ID and RIG
// widths are derived from their contents (colWidth), so nothing in them is ever
// long enough to lose its tail here.
func rpad(s string, w int) string {
	r := []rune(s)
	if len(r) > w {
		return string(r[:w])
	}
	return string(r) + strings.Repeat(" ", w-len(r))
}

// clip bounds a PROSE cell, counting runes, and marks the cut with an ellipsis
// so a shortened cell says it was shortened. rpad already truncates the
// fixed-width columns; this is for the last one, which has no width at all.
func clip(s string, w int) string {
	r := []rune(s)
	if len(r) <= w {
		return s
	}
	if w < 1 {
		// No room even for the marker. Unreachable from the one caller, which
		// passes a const, but a render path must not panic on arithmetic.
		return ""
	}
	return string(r[:w-1]) + "…"
}

// Column widths, in the order gc-helm.sh lays them out. ID and RIG are
// MINIMUMS rather than fixed widths — see colWidth.
//
// colNeedsMax is not a column width — NEEDS is last and unpadded — but a
// bound on how much prose one row may spend. It matters because NEEDS is
// where the LLM-authored takeaway lands: on the live board 23 takeaways
// averaged 597 characters and one ran to 1876, which is not a wide cell but a
// single row wrapping over every row beneath it (tk-9tbbk.1). It is the same
// 140 gc-helm.sh's takeaway writer now enforces at write time, so a
// conforming headline renders in full and this only fires on text stored
// before that gate existed. --json is untouched: board.Tile.Needs keeps the
// whole string for anything that reads the wire.
const (
	colHeld     = 2
	colSeverity = 9
	colIDMin    = 11
	colRigMin   = 13
	colKind     = 9
	colNM       = 7
	colFrontier = 36
	colNeedsMax = 140
)

// colWidth sizes an identifier column to the widest value on THIS board plus a
// single space of gutter, never narrower than floor.
//
// Identifiers cannot be truncated the way prose can, because a hierarchical
// bead id carries its discriminator in the TAIL. At the fixed width of 11 this
// column used to have, sl-kg9z6.4.1, .2 and .9 all rendered as "sl-kg9z6.4." —
// three distinct anchors the operator could not tell apart without going to
// another tool (tk-mtuej). Rig names lost their tails the same way:
// "shutupandlisten" rendered "shutupandlist" and butted against the next
// column.
//
// Sizing to content rather than capping with an ellipsis keeps the guarantee
// absolute — no two distinct ids ever render the same cell — and costs nothing
// in layout: NEEDS is the last column and already runs to whatever length its
// text needs, so a wide id cannot push anything off a line that was fixed.
// floor keeps a board of ordinary ids laid out exactly as it was.
func colWidth(floor int, tiles []board.Tile, value func(board.Tile) string) int {
	w := floor
	for _, t := range tiles {
		// +1 for the gutter: the cell must not butt against the next column.
		if n := len([]rune(value(t))) + 1; n > w {
			w = n
		}
	}
	return w
}

// renderTable writes the human board: the header, the ranked table, and the
// legend that says what the bands and the held glyph mean.
func renderTable(w io.Writer, b board.Board, shown []board.Tile, now time.Time, rigCount int) {
	fmt.Fprint(w, "gc-helm — cross-rig human-attention board\n")
	stamp := now.Format("2006-01-02T15:04:05Z")
	if len(shown) < b.Total {
		fmt.Fprintf(w, "%s · %d rigs · showing %d of %d anchors (live)\n\n", stamp, rigCount, len(shown), b.Total)
	} else {
		fmt.Fprintf(w, "%s · %d rigs · %d anchors (live)\n\n", stamp, rigCount, b.Total)
	}

	if b.Total == 0 {
		fmt.Fprint(w, "No open anchors need attention. (Nothing floats.)\n")
		return
	}

	// The two identifier columns are sized to what this board actually holds;
	// every other column carries prose, where a fixed width and a trimmed tail
	// are the right trade.
	idW := colWidth(colIDMin, shown, func(t board.Tile) string { return t.ID })
	rigW := colWidth(colRigMin, shown, func(t board.Tile) string { return t.Rig })

	fmt.Fprint(w, rpad(" ", colHeld)+rpad("SEV", colSeverity)+rpad("ID", idW)+
		rpad("RIG", rigW)+rpad("KIND", colKind)+rpad("N/M", colNM)+
		rpad("FRONTIER", colFrontier)+"NEEDS\n")
	rule := func(n, w int) string { return rpad(strings.Repeat("─", n), w) }
	fmt.Fprint(w, rule(1, colHeld)+rule(8, colSeverity)+rule(idW-1, idW)+
		rule(rigW-1, rigW)+rule(8, colKind)+rule(6, colNM)+
		rule(35, colFrontier)+strings.Repeat("─", 16)+"\n")

	for _, t := range shown {
		glyph := " "
		if t.Held {
			glyph = "●"
		}
		// "—" means THIS ROW has no roll-up, not that its KIND never has one: a
		// decision never does, and a human/parked bead does exactly when it
		// decomposed. Printing "—" over a real child set is what hid the open
		// children of a parked subject (tk-a9k0l); printing 0/0 for a bead that
		// owns no set at all would be a fabricated count.
		nm := fmt.Sprintf("%d/%d", t.NClosed, t.MTotal)
		if t.MTotal == 0 {
			switch t.Kind {
			case "decision", "human", "parked":
				nm = "—"
			}
		}
		fmt.Fprint(w, rpad(glyph, colHeld)+rpad(string(t.Severity), colSeverity)+
			rpad(t.ID, idW)+rpad(t.Rig, rigW)+rpad(t.Kind, colKind)+
			rpad(nm, colNM)+rpad(t.Frontier, colFrontier)+clip(t.Needs, colNeedsMax)+"\n")
	}

	fmt.Fprint(w, "\nLegend: HIGH=stranded/unowned · ELEVATED=open-decision/human/stale/stuck · NORMAL=active · LOW=empty/complete/childless-parked/ruled\n")
	fmt.Fprint(w, "Kinds: epic/convoy/decision are roll-up anchors · human=routed to you · parked=a conversation with a takeaway (resume: prefix+a, then the id)\n")
	fmt.Fprint(w, "A parked row with an N/M count decomposed into children and is banded by them — the takeaway is not the whole story there\n")
	fmt.Fprint(w, "A row reading \"ruled\" was answered and its routed work has landed — close or extend it; the ruling itself is in --json takeaway\n")
	fmt.Fprint(w, "Held: ● an open visit holds this anchor's conversation (attach via the sessions picker) · blank = none\n")
	fmt.Fprint(w, "gc-helm.sh open <id> to file a visit · react <id> to advance a takeaway-less row. Ranking is a deterministic proxy.\n")
}

// intEnv reads a non-negative integer from the environment, falling back to def.
//
// GC_HELM_MAX_ROWS and GC_HELM_MAX_PARKED are gc-helm.sh's documented knobs and
// they have to keep working now that it renders through this binary rather than
// computing its own board — a thin renderer that silently dropped two
// environment variables would be exactly the quiet behaviour change the
// consolidation is supposed to make impossible.
//
// A bad value degrades to the default rather than to zero, matching
// durationEnv and gc-helm.sh's own `case "$MAX_ROWS" in *[!0-9]*` guard: zero
// is meaningful here (uncapped for rows, no parked budget at all), so a typo
// coerced to it would silently change the board's size.
func intEnv(key string, def int) int {
	v := strings.TrimSpace(os.Getenv(key))
	if v == "" {
		return def
	}
	n, err := strconv.Atoi(v)
	if err != nil || n < 0 {
		return def
	}
	return n
}

// boardMain is the os.Exit-calling wrapper main() dispatches to.
func boardMain(args []string) {
	os.Exit(runBoard(args, os.Stdout, os.Stderr))
}
