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
// and no cache: a cold run pays the full gather every time, which is the honest
// cost and is still well inside the bash board's.
//
// THE --json CONTRACT. The output is a ranked JSON ARRAY of tiles, not the
// service's {generated_at,total,tiles} envelope, because that array is what
// assets/scripts/tmux-pick-helm.sh consumes: it runs `jq 'length'` and `.[]`
// over this output, and the envelope would make every row invisible while still
// parsing cleanly. The fields the picker dereferences are pinned by
// TestPickerFieldsPresent in main_test.go.
//
// WHAT THE DEFAULT ANSWERS. The operator's queue (board.OperatorQueue), not the
// city overview. The two are different questions and only one of them is asked
// at a keystroke: the overview ranks every anchor together, where a demand owed
// by a person carries a subtree of one and a stranded container carries
// hundreds, so the queue is buried under the overview by construction rather
// than by accident. `--all` is the overview, and it is the only way to it.

const boardUsage = `Usage:
  helm-svc board [--all] [--json] [--limit=N] [--timeout=SECONDS]

  What is owed by you, oldest first — the CLI view of the same gather and
  derivation the Helm dashboard serves.

  --all              The city overview instead: every anchor, ranked together.
  --json             Emit the rows as a JSON array (stable contract).
  --limit=N          Show only the top N rows (0 = all/uncapped; default caps at 50).
  --timeout=SECONDS  Bound the whole gather (default 120).
  --refresh          Accepted and ignored: this path has no cache to bust.

Exit codes:
  0  board rendered
  2  usage error
  3  the gather failed, or an empty queue could not be asserted (never
     rendered as an empty "all clear")
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
	all     bool
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
		case "--all":
			o.all = true
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
		limit = board.DefaultMaxRows
	}

	v := selectView(b, opts.all, limit)
	if v.unprovable {
		fmt.Fprintf(stderr, "helm-svc board: the gather was PARTIAL, so an empty queue proves nothing — %s\n",
			strings.Join(b.PartialErrors, "; "))
		return boardExitGather
	}

	if opts.json {
		return renderJSON(stdout, stderr, v.rows)
	}
	v.render(stdout, b, v.rows, now, len(res.Facts.RigNames))
	if b.Partial {
		// stderr, not stdout: the table is a contract for human eyes and the
		// JSON is one for tooling; neither should grow a diagnostic line.
		fmt.Fprintf(stderr, "helm-svc board: PARTIAL gather — %s\n", strings.Join(b.PartialErrors, "; "))
	}
	return boardExitOK
}

// boardView is the rows one run renders and the renderer that lays them out.
type boardView struct {
	rows   []board.Tile
	render func(io.Writer, board.Board, []board.Tile, time.Time, int)
	// unprovable marks an empty QUEUE that came out of a partial gather.
	// "Nothing is owed by you" is the most consequential sentence this surface
	// prints, and the rows that would have contradicted it are exactly the ones
	// the unread store was holding — so its emptiness is a failure to look, and
	// exits like one. A non-empty queue still renders: those rows were read.
	unprovable bool
}

// selectView answers the flag: the operator's queue, or the city overview.
func selectView(b board.Board, all bool, limit int) boardView {
	if all {
		return boardView{rows: board.CapRows(board.CityOverview(b.Tiles), limit, board.DefaultMaxParked, board.DefaultMaxDone), render: renderTable}
	}
	rows := board.CapQueue(board.OperatorQueue(b.Tiles), limit)
	return boardView{rows: rows, render: renderQueue, unprovable: len(rows) == 0 && b.Partial}
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

// closedRows is how many of the board's rows are the terminal DONE band. Every
// header that prints a denominator subtracts it: a closed anchor keeps a row,
// and a total that folded it in would report attention the board is not asking
// for.
func closedRows(tiles []board.Tile) int {
	var n int
	for _, t := range tiles {
		if t.Severity == board.SevDone {
			n++
		}
	}
	return n
}

// renderQueue writes the DEFAULT view: the rows owed by the operator and no
// others, plus the conversation record. The overview is one flag away and says
// so on every render.
func renderQueue(w io.Writer, b board.Board, queue []board.Tile, now time.Time, rigCount int) {
	fmt.Fprint(w, "gc-helm — what is owed by you\n")
	fmt.Fprintf(w, "%s · %d rigs · %d owed (of %d live anchors)\n\n",
		now.Format("2006-01-02T15:04:05Z"), rigCount, len(queue), b.Total-closedRows(b.Tiles))

	if len(queue) == 0 {
		// Coverage, not a bare blank line. "Nothing is owed" is a claim about
		// every store in the city, so the sentence carries what it was checked
		// against; a partial gather never reaches here (runBoard exits 3).
		fmt.Fprintf(w, "Nothing is owed by you. %d rigs checked, all reachable.\n", rigCount)
		renderSittings(w, b.Sittings, now)
		fmt.Fprint(w, "\nhelm-svc board --all (prefix+B in tmux) for the city overview.\n")
		return
	}

	renderRows(w, queue)
	fmt.Fprint(w, "\nOldest first — this queue is ordered by how long each row has been owed, not by rank\n")
	fmt.Fprint(w, "helm-svc board --all (prefix+B in tmux) for the city overview\n")
	renderSittings(w, b.Sittings, now)
	renderLegend(w)
}

// renderTable writes the city overview: the header, the ranked table, and the
// legend that says what the bands and the held glyph mean.
func renderTable(w io.Writer, b board.Board, shown []board.Tile, now time.Time, rigCount int) {
	fmt.Fprint(w, "gc-helm — cross-rig human-attention board\n")
	stamp := now.Format("2006-01-02T15:04:05Z")
	// Both sides of "showing N of M" drop the DONE band, per [closedRows].
	// CapRows returns DONE and parked rows on top of its live budget, so
	// len(shown) is a whole board and can exceed the live count it would
	// otherwise be printed against.
	done := closedRows(b.Tiles)
	var shownLive int
	for _, t := range shown {
		if t.Severity != board.SevDone {
			shownLive++
		}
	}
	live := b.Total - done
	closedSfx := ""
	if done > 0 {
		closedSfx = fmt.Sprintf(" · %d closed", done)
	}
	if len(shown) < b.Total {
		fmt.Fprintf(w, "%s · %d rigs · showing %d of %d anchors (live)%s\n\n", stamp, rigCount, shownLive, live, closedSfx)
	} else {
		fmt.Fprintf(w, "%s · %d rigs · %d anchors (live)%s\n\n", stamp, rigCount, live, closedSfx)
	}

	if b.Total == 0 {
		fmt.Fprint(w, "No open anchors need attention. (Nothing floats.)\n")
		// The conversation record still prints. A board with no anchor to act
		// on and a sitting running on it is exactly the state where the ranked
		// table alone says nothing and the sittings say everything.
		renderSittings(w, b.Sittings, now)
		return
	}

	renderRows(w, shown)
	renderSittings(w, b.Sittings, now)
	renderLegend(w)
}

// renderRows writes the table proper — the sized header and one line per tile.
// Shared by both views so a column can never mean two things.
func renderRows(w io.Writer, shown []board.Tile) {
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
}

// renderLegend writes the trailer that says what the bands, the kinds and the
// held glyph mean.
func renderLegend(w io.Writer) {
	fmt.Fprint(w, "\nLegend: HIGH=stranded/unowned · ELEVATED=open-decision/human/stale/stuck · NORMAL=active · LOW=empty/complete/childless-parked/ruled · DONE=the anchor itself closed\n")
	fmt.Fprint(w, "Kinds: epic/convoy/decision are roll-up anchors · human=routed to you · parked=a conversation with a takeaway (resume: prefix+a, then the id)\n")
	fmt.Fprint(w, "A parked row with an N/M count decomposed into children and is banded by them — the takeaway is not the whole story there\n")
	fmt.Fprint(w, "A row reading \"ruled\" was answered and its routed work has landed — close or extend it; the ruling itself is in --json takeaway\n")
	fmt.Fprint(w, "Held: ● an open visit holds this anchor's conversation (attach via the sessions picker) · blank = none\n")
	fmt.Fprint(w, "A DONE row sinks below every live band; no row leaves for being answered. gc-helm.sh dismiss <id> clears one now, and a row ages out of the band once it has been closed longer than GC_HELM_DONE_WINDOW (default 7d, 0 off).\n")
	fmt.Fprint(w, "gc-helm.sh open <id> to file a visit · react <id> to advance a takeaway-less row. Ranking is a deterministic proxy.\n")
}

// Sitting column widths. SUBJECT and OUTCOME are minimums sized to content by
// colWidth for the same reason the ID column is: a truncated bead id and a
// truncated outcome word are both unreadable, and HEADLINE is last and unpadded
// so a wide cell costs nothing.
const (
	colSubjectMin  = 12
	colAge         = 7
	colOutcomeMin  = 10
	colHeadlineMax = 96
)

// renderSittings writes the conversation record under the ranked table: which
// sittings are running, and what the recently closed ones concluded.
//
// The ranked table answers what needs doing. This answers what is being talked
// about, which is a different question and deliberately not ranked against it —
// a sitting is an event, not a demand.
func renderSittings(w io.Writer, sittings []board.Sitting, now time.Time) {
	if len(sittings) == 0 {
		return
	}
	shown, dropped := board.CapSittings(sittings, board.DefaultMaxSittings)

	var running, closed int
	for _, s := range sittings {
		if s.Status == "closed" {
			closed++
		} else {
			running++
		}
	}

	fmt.Fprintf(w, "\nSittings — %d running · %d closed recently\n", running, closed)
	fmt.Fprint(w, "● still running · AGE is time since it started, or since it ended · OUTCOME is what a closed sitting closed on\n")

	// Sized to content for the same reason the ranked table sizes its ID
	// column: an id or an outcome word loses its meaning when its tail is cut.
	idW, rigW, subjW, outW := colIDMin, colRigMin, colSubjectMin, colOutcomeMin
	for _, s := range shown {
		idW = max(idW, len([]rune(s.ID))+1)
		rigW = max(rigW, len([]rune(s.Rig))+1)
		subjW = max(subjW, len([]rune(s.Subject))+1)
		outW = max(outW, len([]rune(s.Outcome))+1)
	}

	fmt.Fprint(w, rpad(" ", colHeld)+rpad("ID", idW)+rpad("RIG", rigW)+
		rpad("SUBJECT", subjW)+rpad("AGE", colAge)+rpad("OUTCOME", outW)+"HEADLINE\n")

	for _, s := range shown {
		glyph, since, outcome := " ", s.ClosedAt, s.Outcome
		if s.Status != "closed" {
			glyph, since = "●", s.OpenedAt
		}
		if outcome == "" {
			// "—" is the same claim the N/M column makes above: this row has no
			// such value, rather than a value that happens to be empty.
			outcome = "—"
		}
		// The takeaway is what the sitting concluded; the title is what it was
		// called. Preferring the conclusion means a row says something even
		// when its title is a truncated escalation subject.
		headline := s.Takeaway
		if headline == "" {
			headline = s.Title
		}
		fmt.Fprint(w, rpad(glyph, colHeld)+rpad(s.ID, idW)+rpad(s.Rig, rigW)+
			rpad(s.Subject, subjW)+rpad(shortAge(since, now), colAge)+
			rpad(outcome, outW)+clip(headline, colHeadlineMax)+"\n")
	}

	if dropped > 0 {
		// Never a silent truncation: an elided list that does not say so reads
		// as the whole record.
		fmt.Fprintf(w, "  … %d older closed sittings not shown (--json on the service carries them all)\n", dropped)
	}
}

// shortAge renders how long ago a stamp was, in the coarsest unit that still
// says something: minutes under an hour, then hours, then days. A zero stamp is
// unknown rather than "just now", which is the distinction that keeps a sitting
// whose source could not read a timestamp from reading as the freshest row.
func shortAge(stamp, now time.Time) string {
	if stamp.IsZero() {
		return "?"
	}
	d := now.Sub(stamp)
	if d < 0 {
		d = 0
	}
	switch {
	case d < time.Hour:
		return fmt.Sprintf("%dm", int(d.Minutes()))
	case d < 48*time.Hour:
		return fmt.Sprintf("%dh", int(d.Hours()))
	default:
		return fmt.Sprintf("%dd", int(d.Hours())/24)
	}
}

// boardMain is the os.Exit-calling wrapper main() dispatches to.
func boardMain(args []string) {
	os.Exit(runBoard(args, os.Stdout, os.Stderr))
}
