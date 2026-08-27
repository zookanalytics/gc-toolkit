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
			Severity: board.SevHigh, MTotal: 2, Open: 2,
			Frontier: "2 open · 0 in flight (stranded)", Needs: "decomposed, idle — assign or visit",
			RankScore: 3_002_000,
		},
		{
			ID: "tk-done", Rig: "gc-toolkit", Kind: "parked", Title: "answered while you were away",
			Severity: board.SevDone, MTotal: 1, NClosed: 1,
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
			Severity: board.SevHigh, MTotal: 2, Open: 2, RankScore: 3_002_000 - i,
		})
	}
	for i := range 2 {
		tiles = append(tiles, board.Tile{
			ID: fmt.Sprintf("tk-done%d", i), Rig: "gc-toolkit", Kind: "epic", Title: "answered",
			Severity: board.SevDone, MTotal: 1, NClosed: 1, ClosedAt: now.Add(-26 * time.Hour),
			RankScore: -999_002 - i,
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

func firstLines(s string, n int) string {
	lines := strings.SplitN(s, "\n", n+1)
	if len(lines) > n {
		lines = lines[:n]
	}
	return strings.Join(lines, "\n")
}
