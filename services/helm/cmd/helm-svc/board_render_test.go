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
			Frontier: "closed 1d ago", Needs: "closed — dismiss to clear",
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

func TestRenderTableShowsTheDoneRowAndHowToClearIt(t *testing.T) {
	b, tiles := doneBoard()
	var out strings.Builder
	renderTable(&out, b, tiles, b.GeneratedAt, 1)
	got := out.String()

	for _, want := range []string{
		"tk-done",                   // the row is rendered at all
		"DONE",                      // in its own band
		"closed 1d ago",             // saying when
		"closed — dismiss to clear", // and what clears it
		"gc-helm.sh dismiss <id>",   // the legend names the verb
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

// CapRows fills its live budget and then adds parked and DONE rows on top, so
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
	shown := board.CapRows(tiles, 2, 0, 2)

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

// The DONE band draws on its own budget, so it can be capped while the live
// rows are not. A header that prints the closed TOTAL beside a capped band
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
	shown := board.CapRows(tiles, 50, 0, 2)

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

// The board is read one band at a time, so each non-empty section prints a
// labeled banner and the rows in it fall under that banner.
func TestRenderTableShowsSectionBanners(t *testing.T) {
	now := time.Date(2026, 8, 26, 8, 0, 0, 0, time.UTC)
	tiles := []board.Tile{
		{ID: "tk-pr", Rig: "gc-toolkit", Kind: "merge", Title: "a PR", Severity: board.SevElevated,
			Section: board.SectionReview, PRMachine: "settled", Needs: "green — waiting on the merge pass", RankScore: 2_000_000},
		{ID: "tk-strand", Rig: "gc-toolkit", Kind: "epic", Title: "stranded", Severity: board.SevHigh,
			Section: board.SectionStalled, MTotal: 2, Open: 2, Needs: "decomposed, idle — assign or visit", RankScore: 3_000_000},
	}
	b := board.Board{GeneratedAt: now, Total: len(tiles), Tiles: tiles}
	var out strings.Builder
	renderTable(&out, b, tiles, now, 1)
	got := out.String()

	for _, want := range []string{"▌ REVIEW", "a pull request wants you", "▌ STALLED"} {
		if !strings.Contains(got, want) {
			t.Errorf("missing section banner %q; got:\n%s", want, got)
		}
	}
	// The banner order follows SectionOrder: review before stalled.
	if strings.Index(got, "▌ REVIEW") > strings.Index(got, "▌ STALLED") {
		t.Errorf("review must band before stalled; got:\n%s", got)
	}
}

// A run of rows sharing one template folds to a single line that names the count
// and lists the members, instead of N identical peer rows.
func TestRenderTableCollapsesAClusterToOneLine(t *testing.T) {
	now := time.Date(2026, 8, 26, 8, 0, 0, 0, time.UTC)
	var tiles []board.Tile
	for i := range 4 {
		tiles = append(tiles, board.Tile{
			ID: fmt.Sprintf("tk-fr%d", i), Rig: "gc-toolkit", Kind: "human", Title: "first reaction",
			Severity: board.SevElevated, Section: board.SectionGate, Owed: true,
			Needs: "first reaction ready: accept or redirect", ClusterKey: "first reaction ready: accept or redirect",
			RankScore: 2_000_000 - i,
		})
	}
	b := board.Board{GeneratedAt: now, Total: len(tiles), Tiles: tiles}
	var out strings.Builder
	renderTable(&out, b, tiles, now, 1)
	got := out.String()

	if !strings.Contains(got, "4×") {
		t.Errorf("a cluster of 4 must show its count; got:\n%s", got)
	}
	// Every member id is named on the collapsed line, so nothing is hidden.
	for i := range 4 {
		if !strings.Contains(got, fmt.Sprintf("tk-fr%d", i)) {
			t.Errorf("cluster line must list member tk-fr%d; got:\n%s", i, got)
		}
	}
	// The shared needs prints once, not four times.
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
