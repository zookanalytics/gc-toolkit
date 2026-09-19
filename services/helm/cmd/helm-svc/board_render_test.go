package main

import (
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/board"
)

// renderTable is the second renderer over the same model, and it is the one an
// operator reads at a terminal. These cover the DONE band's shape there: the
// header count, the legend line, and the row itself.

func doneBoard() (board.Board, []board.Tile) {
	now := time.Date(2026, 8, 26, 8, 0, 0, 0, time.UTC)
	tiles := []board.Tile{
		{
			ID: "tk-live", Rig: "gc-toolkit", Kind: "epic", Title: "still open",
			Severity: board.SevHigh, MTotal: 2, Open: 2, Section: board.SectionStalled,
			Frontier: "2 open · 0 in flight (stranded)", Needs: "decomposed, idle — assign or visit",
			RankScore: 3_002_000,
		},
		{
			ID: "tk-done", Rig: "gc-toolkit", Kind: "parked", Title: "answered while you were away",
			Severity: board.SevDone, MTotal: 1, NClosed: 1, Section: board.SectionDone,
			ClosedAt: now.Add(-26 * time.Hour),
			Frontier: "closed 1d ago", Needs: "closed — ages out",
			RankScore: -999_002,
		},
	}
	return board.Board{GeneratedAt: now, Total: len(tiles), Tiles: tiles}, tiles
}

// The header said "N anchors (live)". Folding a closed row into that number
// reports attention the board is not asking for.
func TestRenderTableCountsTheDoneBandSeparately(t *testing.T) {
	b, tiles := doneBoard()
	var out strings.Builder
	renderTable(&out, b, tiles, b.GeneratedAt, 1)

	if !strings.Contains(out.String(), "1 anchors (live) · 1 closed") {
		t.Errorf("header must split live from closed; got:\n%s", firstLines(out.String(), 3))
	}
}

// A recommendation row (Acceptable) marks its ask with the accept affordance and
// the legend names the verb; a discuss-only gate shows neither.
func TestRenderTableMarksAcceptableRows(t *testing.T) {
	now := time.Date(2026, 8, 26, 8, 0, 0, 0, time.UTC)
	tiles := []board.Tile{
		{
			ID: "tk-rec", Rig: "gc-toolkit", Kind: "human", Title: "a recommendation",
			Severity: board.SevElevated, Section: board.SectionGate, Owed: true, Held: true,
			Frontier: "owed", Needs: "retire the wedged PR", RankScore: 2_000_000,
			Acceptable: true, AcceptFormula: "mol-dispose-pr",
		},
		{
			ID: "tk-plain", Rig: "gc-toolkit", Kind: "human", Title: "a discuss-only gate",
			Severity: board.SevElevated, Section: board.SectionGate, Owed: true, Held: true,
			Frontier: "owed", Needs: "let's talk it through", RankScore: 1_000_000,
		},
	}
	b := board.Board{GeneratedAt: now, Total: len(tiles), Tiles: tiles}
	var out strings.Builder
	renderTable(&out, b, tiles, b.GeneratedAt, len(tiles))
	got := out.String()

	if !strings.Contains(got, "accept ▸ retire the wedged PR") {
		t.Errorf("an acceptable row marks its ask with the accept affordance; got:\n%s", got)
	}
	if strings.Contains(got, "accept ▸ let's talk it through") {
		t.Errorf("a discuss-only row must not be marked acceptable; got:\n%s", got)
	}
	if !strings.Contains(got, "gc-helm.sh accept <id>") {
		t.Errorf("the legend names the accept verb; got:\n%s", got)
	}
}

func TestRenderTableShowsTheDoneRowAndThatItAgesOut(t *testing.T) {
	b, tiles := doneBoard()
	var out strings.Builder
	renderTable(&out, b, tiles, b.GeneratedAt, 1)
	got := out.String()

	for _, want := range []string{
		"tk-done",              // the row is rendered at all
		"DONE",                 // in its own band
		"closed 1d ago",        // saying when
		"closed — ages out",    // and that it leaves on its own
		"ages out of the band", // the legend says how a row leaves
	} {
		if !strings.Contains(got, want) {
			t.Errorf("table is missing %q; got:\n%s", want, got)
		}
	}
}

// The legend is where the terminal board states what the DONE band promises,
// and the band's actual promise is narrower than "nothing here leaves on its
// own": doneSince reaches back GC_HELM_DONE_WINDOW, so a row does age out on
// that clock. A legend that promises otherwise teaches the operator to stop
// looking for a row that is gone.
func TestRenderTableLegendStatesTheWindowBound(t *testing.T) {
	b, tiles := doneBoard()
	var out strings.Builder
	renderTable(&out, b, tiles, b.GeneratedAt, 1)
	got := out.String()

	if !strings.Contains(got, "GC_HELM_DONE_WINDOW") {
		t.Errorf("the legend must name the bound the band keeps; got:\n%s", got)
	}
	if strings.Contains(got, "Nothing here leaves on its own") {
		t.Errorf("the legend promises an unbounded band the window does not keep; got:\n%s", got)
	}
}

// CapFamilies fills its live budget and then adds the DONE families on top, so
// the slice it returns is a whole board rather than a count of live rows. Read
// as the numerator against the live total, it can exceed it — a header
// claiming to show more live anchors than the board holds.
func TestRenderTableCappedHeaderCountsOnlyTheLiveRowsShown(t *testing.T) {
	now := time.Date(2026, 8, 26, 8, 0, 0, 0, time.UTC)
	var tiles []board.Tile
	for i := range 3 {
		tiles = append(tiles, board.Tile{
			ID: fmt.Sprintf("tk-live%d", i), Rig: "gc-toolkit", Kind: "epic", Title: "still open",
			Severity: board.SevHigh, MTotal: 2, Open: 2, Section: board.SectionStalled, RankScore: 3_002_000 - i,
		})
	}
	for i := range 2 {
		tiles = append(tiles, board.Tile{
			ID: fmt.Sprintf("tk-done%d", i), Rig: "gc-toolkit", Kind: "epic", Title: "answered",
			Severity: board.SevDone, MTotal: 1, NClosed: 1, ClosedAt: now.Add(-26 * time.Hour),
			Section: board.SectionDone, RankScore: -999_002 - i,
		})
	}
	b := board.Board{GeneratedAt: now, Total: len(tiles), Tiles: tiles}
	shown := board.CapFamilies(tiles, 2, 2)

	var out strings.Builder
	renderTable(&out, b, shown, b.GeneratedAt, 1)
	got := out.String()

	if len(shown) <= 3 {
		t.Fatalf("fixture must cap live rows while keeping DONE rows; shown=%d", len(shown))
	}
	if !strings.Contains(got, "showing 2 of 3 anchors (live) · 2 closed") {
		t.Errorf("the live numerator must count only the live rows shown; got:\n%s", firstLines(got, 3))
	}
}

// The DONE families draw on their own budget, so they can be capped while the
// live rows are not. A header that prints the closed TOTAL beside a capped band
// reports a complete record of what closed while showing part of it.
func TestRenderTableHeaderNamesTheClosedCap(t *testing.T) {
	now := time.Date(2026, 8, 26, 8, 0, 0, 0, time.UTC)
	var tiles []board.Tile
	tiles = append(tiles, board.Tile{
		ID: "tk-live", Rig: "gc-toolkit", Kind: "epic", Title: "still open",
		Severity: board.SevHigh, MTotal: 2, Open: 2, Section: board.SectionStalled, RankScore: 3_002_000,
	})
	for i := range 4 {
		tiles = append(tiles, board.Tile{
			ID: fmt.Sprintf("tk-done%d", i), Rig: "gc-toolkit", Kind: "epic", Title: "answered",
			Severity: board.SevDone, MTotal: 1, NClosed: 1, ClosedAt: now.Add(-26 * time.Hour),
			Section: board.SectionDone, RankScore: -999_002 - i,
		})
	}
	b := board.Board{GeneratedAt: now, Total: len(tiles), Tiles: tiles}
	shown := board.CapFamilies(tiles, 50, 2)

	var out strings.Builder
	renderTable(&out, b, shown, b.GeneratedAt, 1)
	got := out.String()

	if !strings.Contains(got, "showing 2 of 4 closed") {
		t.Errorf("a capped DONE band must name both numbers; got:\n%s", firstLines(got, 3))
	}
	if strings.Contains(got, "· 4 closed") {
		t.Errorf("the closed total alone reads as a complete band; got:\n%s", firstLines(got, 3))
	}
}

// An uncapped band is complete, and saying "showing 2 of 2" there invites the
// operator to look for rows that are already all on screen.
func TestRenderTableHeaderStaysPlainWhenTheBandIsWhole(t *testing.T) {
	b, tiles := doneBoard()
	var out strings.Builder
	renderTable(&out, b, tiles, b.GeneratedAt, 1)
	got := out.String()

	if !strings.Contains(got, "· 1 closed") || strings.Contains(got, "of 1 closed") {
		t.Errorf("a whole band names one number; got:\n%s", firstLines(got, 3))
	}
}

// The overview groups by dependency family: each family opens with a banner
// naming its root, and a ● marks a root whose next move is the operator's
// (review or gate). The within-family band is a column, not the top axis.
func TestRenderTableShowsFamilyBlocks(t *testing.T) {
	now := time.Date(2026, 8, 26, 8, 0, 0, 0, time.UTC)
	tiles := []board.Tile{
		{ID: "tk-pr", Rig: "gc-toolkit", Kind: "merge", Title: "a PR", Severity: board.SevElevated,
			Section: board.SectionReview, PRMachine: "settled", Frontier: "PR #9 · owed 2d",
			Needs: "green — waiting on the merge pass", GroupRoot: "tk-pr", RankScore: 2_000_000},
		{ID: "tk-strand", Rig: "gc-toolkit", Kind: "epic", Title: "stranded", Severity: board.SevHigh,
			Section: board.SectionStalled, MTotal: 2, Open: 2, Frontier: "2 open · 0 in flight (stranded)",
			Needs: "decomposed, idle — assign or visit", GroupRoot: "tk-strand", RankScore: 3_000_000},
	}
	b := board.Board{GeneratedAt: now, Total: len(tiles), Tiles: tiles}
	var out strings.Builder
	renderTable(&out, b, tiles, now, 1)
	got := out.String()

	for _, want := range []string{"BAND", "▌ tk-pr", "▌ tk-strand"} {
		if !strings.Contains(got, want) {
			t.Errorf("missing family block element %q; got:\n%s", want, got)
		}
	}
	// A review family wants the operator, so its header carries the ● glyph; a
	// stalled family does not.
	if !strings.Contains(got, "● ▌ tk-pr") {
		t.Errorf("a review family's header must carry the person glyph; got:\n%s", got)
	}
	if strings.Contains(got, "● ▌ tk-strand") {
		t.Errorf("a stalled family's header must not carry the person glyph; got:\n%s", got)
	}
}

// A run of rows sharing one deterministic template folds to a count line, then
// ONE line per member carrying its id and its own title — per-bead context, not
// a bare id soup. Clustering lives in the flat owed queue; the
// overview groups by family instead.
func TestRenderQueueClusterCarriesPerBeadContext(t *testing.T) {
	now := time.Date(2026, 8, 26, 8, 0, 0, 0, time.UTC)
	var tiles []board.Tile
	for i := range 4 {
		tiles = append(tiles, board.Tile{
			ID: fmt.Sprintf("tk-fr%d", i), Rig: "gc-toolkit", Kind: "human",
			Title:    fmt.Sprintf("first reaction on subject %d", i),
			Severity: board.SevElevated, Section: board.SectionGate, Owed: true,
			Needs: "first reaction ready: accept or redirect", ClusterKey: "first reaction ready: accept or redirect",
			RankScore: 2_000_000 - i,
		})
	}
	b := board.Board{GeneratedAt: now, Total: len(tiles), Tiles: tiles}
	var out strings.Builder
	renderQueue(&out, b, tiles, now, 1)
	got := out.String()

	if !strings.Contains(got, "4×") {
		t.Errorf("a cluster of 4 must show its count; got:\n%s", got)
	}
	// Every member is named with its id AND its own title, so nothing is hidden.
	for i := range 4 {
		if !strings.Contains(got, fmt.Sprintf("tk-fr%d", i)) {
			t.Errorf("cluster must list member tk-fr%d; got:\n%s", i, got)
		}
		if !strings.Contains(got, fmt.Sprintf("first reaction on subject %d", i)) {
			t.Errorf("each member carries its own title; got:\n%s", got)
		}
	}
	// The shared needs prints once, on the count line, not once per member.
	if n := strings.Count(got, "first reaction ready: accept or redirect"); n != 1 {
		t.Errorf("the shared needs prints once for the cluster, got %d occurrences", n)
	}
}

func firstLines(s string, n int) string {
	lines := strings.SplitN(s, "\n", n+1)
	if len(lines) > n {
		lines = lines[:n]
	}
	return strings.Join(lines, "\n")
}
