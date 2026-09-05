package main

import (
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/board"
)

// The CLI half of the pack-build strip. The dashboard has its own test; this
// one exists because the two views must say the same thing, and the CLI is the
// one an operator reaches when the sidecar is the thing that is broken.

func renderedBoard(t *testing.T, b board.Board) string {
	t.Helper()
	var sb strings.Builder
	renderTable(&sb, b, b.Tiles, time.Date(2026, 8, 26, 12, 0, 0, 0, time.UTC), 1)
	return sb.String()
}

func TestPackRowsRenderAboveTheAnchors(t *testing.T) {
	out := renderedBoard(t, board.Board{
		Total: 1,
		Tiles: []board.Tile{{ID: "tk-1", Rig: "gc-toolkit", Kind: "epic", Severity: board.SevHigh, Frontier: "1 open"}},
		PackHealth: []board.PackBuild{
			{Component: "gctk", Severity: board.SevHigh, Detail: "last build FAILED (rc 1); still serving 1a2b3c4d5e6f"},
			{Component: "helm", Severity: board.SevNormal, Detail: "current at 9f1c0b7e5a4d"},
		},
	})
	packAt := strings.Index(out, "PACK")
	anchorAt := strings.Index(out, "tk-1")
	if packAt < 0 {
		t.Fatalf("no PACK rows in:\n%s", out)
	}
	if anchorAt < packAt {
		t.Errorf("the anchors render before the pack rows; the strip qualifies them:\n%s", out)
	}
	for _, want := range []string{"gctk", "last build FAILED", "helm", "current at 9f1c0b7e5a4d"} {
		if !strings.Contains(out, want) {
			t.Errorf("missing %q in:\n%s", want, out)
		}
	}
}

// The day nothing else needs attention is the day a broken build is most worth
// reading, and it is exactly the day the board returns early.
func TestPackRowsSurviveAnEmptyBoard(t *testing.T) {
	out := renderedBoard(t, board.Board{
		Total:      0,
		PackHealth: []board.PackBuild{{Component: "helm", Severity: board.SevHigh, Detail: "last build FAILED (rc 1); still serving 1a2b3c4d5e6f"}},
	})
	if !strings.Contains(out, "PACK") || !strings.Contains(out, "last build FAILED") {
		t.Errorf("an empty board dropped the pack rows:\n%s", out)
	}
	if !strings.Contains(out, "Nothing floats") {
		t.Errorf("the empty-board line is gone:\n%s", out)
	}
}

func TestNoPackRecordRendersNoStrip(t *testing.T) {
	out := renderedBoard(t, board.Board{Total: 0})
	if strings.Contains(out, "PACK ") {
		t.Errorf("a city with no build record grew a strip anyway:\n%s", out)
	}
}

// --json is the tiles array and nothing else: tmux-pick-helm.sh runs `jq
// 'length'` over it, so an envelope would turn every board into one row.
func TestJSONOutputStaysTheTilesArray(t *testing.T) {
	var out, errOut strings.Builder
	if rc := renderJSON(&out, &errOut, []board.Tile{{ID: "tk-1"}}); rc != boardExitOK {
		t.Fatalf("renderJSON = %d, want %d (%s)", rc, boardExitOK, errOut.String())
	}
	if trimmed := strings.TrimSpace(out.String()); !strings.HasPrefix(trimmed, "[") {
		t.Errorf("--json is not an array:\n%s", out.String())
	}
	if strings.Contains(out.String(), "pack_health") {
		t.Errorf("--json grew the envelope's pack_health key:\n%s", out.String())
	}
}
