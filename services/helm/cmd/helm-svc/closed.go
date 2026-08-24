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

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/closed"
	"github.com/zookanalytics/gc-toolkit/services/helm/internal/source"
)

// `helm-svc closed` is the CLI VIEW of the closed-dispositions read — the
// second renderer over the same gather the dashboard's /helm/closed serves,
// exactly as `helm-svc board` is the second renderer over /helm.
//
// It follows board.go's three rules for the same three reasons: it lives in the
// SAME BINARY (one build, one artifact, two entry points — nothing can go stale
// independently), it does NOT call the service (this has to work when helm-svc
// is down, which is most of the point of a CLI), and its --json emits a bare
// ARRAY rather than the service's envelope (that array is what gc-helm.sh's
// `closed --json` contract promises).

const closedUsage = `Usage:
  helm-svc closed [--since 24h] [--json] [--limit=N] [--timeout=SECONDS]

  What reached a disposition inside a window, and why — the rows the
  open-only board drops when a sitting concludes and its subject closes.

  Rows are per VISIT, not per subject: a subject with three sittings that
  closed in the window is three decisions and shows three rows.

  --since DURATION   How far back to look (default 24h). Spelled the way this
                     pack spells durations — 30s, 90m, 24h, 7d, or a bare
                     integer meaning seconds.
  --json             Emit the disposition rows as a JSON array.
  --limit=N          Show only the newest N rows (0 = all/uncapped; default 50).
  --timeout=SECONDS  Bound the whole gather (default 120).

Exit codes:
  0  rendered (an empty window is a success — it says so in words)
  2  usage error
  3  the gather failed (never rendered as an empty "nothing was decided")
`

type closedOpts struct {
	json    bool
	since   string
	limit   int // -1 = unset (use the default cap); 0 = uncapped
	timeout time.Duration
}

// parseClosedArgs accepts the gc-helm.sh flag spellings, including both
// `--since=24h` and `--since 24h`.
func parseClosedArgs(args []string) (closedOpts, error) {
	o := closedOpts{since: "24h", limit: -1, timeout: defaultBoardTimeout}

	take := func(name, raw string, rest *[]string) (string, error) {
		if raw != "" {
			return raw, nil
		}
		if len(*rest) == 0 {
			return "", fmt.Errorf("%s requires a value", name)
		}
		v := (*rest)[0]
		*rest = (*rest)[1:]
		return v, nil
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
		case "--since":
			v, err := take("--since", value, &args)
			if err != nil {
				return o, err
			}
			o.since = v
		case "--limit":
			v, err := take("--limit", value, &args)
			if err != nil {
				return o, err
			}
			n, err := strconv.Atoi(v)
			if err != nil || n < 0 {
				return o, fmt.Errorf("--limit must be a non-negative integer, got %q", v)
			}
			o.limit = n
		case "--timeout":
			v, err := take("--timeout", value, &args)
			if err != nil {
				return o, err
			}
			n, err := strconv.Atoi(v)
			if err != nil || n < 0 {
				return o, fmt.Errorf("--timeout must be a non-negative integer, got %q", v)
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

// runClosed is the `closed` entry point. Like runBoard it returns a process exit
// code rather than calling os.Exit, so it stays testable.
func runClosed(args []string, stdout, stderr io.Writer) int {
	opts, err := parseClosedArgs(args)
	if err == flagHelp {
		fmt.Fprint(stdout, closedUsage)
		return boardExitOK
	}
	if err != nil {
		fmt.Fprintf(stderr, "helm-svc closed: %v\n\n%s", err, closedUsage)
		return boardExitUsage
	}

	since, err := closed.ParseSince(opts.since)
	if err != nil {
		fmt.Fprintf(stderr, "helm-svc closed: %v\n\n%s", err, closedUsage)
		return boardExitUsage
	}

	src := source.NewBeadsSource()
	if err := src.Check(); err != nil {
		fmt.Fprintf(stderr, "helm-svc closed: cannot read the city's bead stores: %v\n", err)
		return boardExitGather
	}
	defer func() { _ = src.Close() }()

	ctx, cancel := context.WithTimeout(context.Background(), opts.timeout)
	defer cancel()

	now := time.Now().UTC()
	cutoff := now.Add(-since)
	rows, err := src.GatherClosed(ctx, cutoff)
	if err != nil {
		// A failed gather is NEVER rendered as an empty window. This surface
		// exists to tell a human what was decided; answering "nothing" because
		// Dolt was wedged is the one wrong answer it must never give.
		fmt.Fprintf(stderr, "helm-svc closed: gather failed: %v\n", err)
		return boardExitGather
	}

	limit := opts.limit
	if limit < 0 {
		limit = closed.DefaultMaxRows
	}
	view := closed.Build(closed.Input{
		Rows:   rows,
		Now:    now,
		Since:  opts.since,
		Cutoff: cutoff,
		Limit:  limit,
	})

	if opts.json {
		return renderClosedJSON(stdout, stderr, view.Rows)
	}
	renderClosedTable(stdout, view)
	return boardExitOK
}

// renderClosedJSON writes the bare rows array — the gc-helm.sh `closed --json`
// contract, and the same array-not-envelope choice `helm-svc board --json`
// makes.
func renderClosedJSON(stdout, stderr io.Writer, rows []closed.Row) int {
	if rows == nil {
		rows = []closed.Row{}
	}
	enc := json.NewEncoder(stdout)
	enc.SetEscapeHTML(false)
	enc.SetIndent("", "  ")
	if err := enc.Encode(rows); err != nil {
		fmt.Fprintf(stderr, "helm-svc closed: encoding the rows: %v\n", err)
		return boardExitGather
	}
	return boardExitOK
}

// Column widths for the closed table. SUBJECT and OUTCOME are MINIMUMS sized to
// content by colWidth, for the reason spelled out on board.go's colWidth: a
// hierarchical bead id carries its discriminator in the TAIL, so a fixed width
// renders tk-hgmob.1, .2 and .9 as three identical cells.
//
// colTitleMax and colWhyMax bound the two PROSE columns. Nothing is lost by it
// — --json carries both strings whole — but a 140-char takeaway laid out
// unbounded wraps over every row beneath it, which is how the board's NEEDS
// column had to be clipped (tk-9tbbk.1).
const (
	colClosedAt   = 18
	colSubjectMin = 11
	colOutcomeMin = 9
	colTitleMax   = 38
	colWhyMax     = 60
)

// renderClosedTable writes the human view: newest first, one row per visit.
func renderClosedTable(w io.Writer, v closed.View) {
	if v.Total == 0 {
		fmt.Fprintf(w, "No visit reached a disposition in the last %s (window opens %s).\n",
			v.Since, v.Cutoff.Format(time.RFC3339))
		// Said in words because the two answers look identical otherwise: a
		// failed read exits 3 and prints to stderr, so a reader who sees THIS
		// line knows the store was read and the window was genuinely quiet.
		fmt.Fprint(w, "That is a quiet window, not a failed read — a failed read exits 3 and says so.\n")
		return
	}

	subjW := closedColWidth(colSubjectMin, v.Rows, subjectCell)
	outW := closedColWidth(colOutcomeMin, v.Rows, outcomeCell)

	fmt.Fprint(w, rpad("CLOSED (UTC)", colClosedAt)+rpad("SUBJECT", subjW)+
		rpad("OUTCOME", outW)+rpad("TITLE", colTitleMax)+"WHY (takeaway at sign-off)\n")
	rule := func(n, width int) string { return rpad(strings.Repeat("─", n), width) }
	fmt.Fprint(w, rule(colClosedAt-1, colClosedAt)+rule(subjW-1, subjW)+
		rule(outW-1, outW)+rule(colTitleMax-1, colTitleMax)+strings.Repeat("─", 25)+"\n")

	for _, r := range v.Rows {
		// An id-less or outcome-less row still RENDERS. A closed visit is
		// terminal whether or not sign-off stamped it, and dropping the row
		// would hide the very disposition whose record is incomplete — the one
		// worth seeing.
		fmt.Fprint(w, rpad(r.ClosedAt.Format("2006-01-02 15:04"), colClosedAt)+
			rpad(subjectCell(r), subjW)+
			rpad(outcomeCell(r), outW)+
			rpad(clip(dash(r.SubjectTitle), colTitleMax-1), colTitleMax)+
			clip(dash(r.Takeaway), colWhyMax)+"\n")
	}

	fmt.Fprintf(w, "\nWindow: %s (since %s) · rows are per VISIT, so a subject with three sittings shows three.\n",
		v.Since, v.Cutoff.Format(time.RFC3339))
	if len(v.Rows) < v.Total {
		fmt.Fprintf(w, "Showing the newest %d of %d — raise --limit (0 = all) or narrow --since.\n", len(v.Rows), v.Total)
	}
	fmt.Fprint(w, "Read-only: gc.outcome comes off the closed visit, the takeaway off its subject. Nothing here is written by this view.\n")
}

// subjectCell is the subject id, or the marker for a visit that named none. A
// visit with neither a tracks edge nor a continuation-group stamp is still a
// disposition that happened, so it earns a row that says what it is missing.
func subjectCell(r closed.Row) string {
	if r.Subject == "" {
		return "(unlinked)"
	}
	return r.Subject
}

func outcomeCell(r closed.Row) string { return dash(r.Outcome) }

// dash renders an empty cell as an em-dash, so a blank column reads as "this
// row has none" rather than as a rendering fault.
func dash(s string) string {
	if s == "" {
		return "—"
	}
	return s
}

// closedColWidth is board.go's colWidth over closed rows, and it exists
// separately for the same reason the two renderers do: generics could merge
// them, but a shared type parameter would be the only thing tying two otherwise
// independent views together.
func closedColWidth(floor int, rows []closed.Row, value func(closed.Row) string) int {
	w := floor
	for _, r := range rows {
		if n := len([]rune(value(r))) + 1; n > w {
			w = n
		}
	}
	return w
}

// closedMain is the os.Exit-calling wrapper main() dispatches to.
func closedMain(args []string) { os.Exit(runClosed(args, os.Stdout, os.Stderr)) }
