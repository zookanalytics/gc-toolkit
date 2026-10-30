package main

import (
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/board"
)

// glyphOf reads the first rune of the rendered line carrying id.
func glyphOf(out, id string) string {
	for _, line := range strings.Split(out, "\n") {
		if strings.Contains(line, id) {
			if r := []rune(line); len(r) > 0 {
				return string(r[0])
			}
		}
	}
	return "«no row for " + id + "»"
}

func startFailedTiles() []board.Tile {
	return []board.Tile{
		{ID: "tk-failed", Rig: "gc-toolkit", Kind: "epic", Title: "the plan", Severity: board.SevElevated,
			Section: board.SectionGate, Owed: true, Held: true, GroupRoot: "tk-failed",
			SittingState: board.SittingStartFailed, SittingStartFailure: "startup timeout",
			Frontier: "needs-review · 1 open · in conversation",
			Needs:    "start failed (startup timeout): talk the plan over", RankScore: 2_001_000},
		{ID: "tk-parked", Rig: "gc-toolkit", Kind: "epic", Title: "another plan", Severity: board.SevElevated,
			Section: board.SectionGate, Owed: true, Held: true, GroupRoot: "tk-parked",
			SittingState: board.SittingWaiting, Frontier: "needs-review · 1 open · in conversation",
			Needs: "look at it", RankScore: 2_000_000},
	}
}

// TestRenderQueueMarksAFailedStart: in the queue a row whose conversation's
// sitting failed to start leads with ✗ where any other held row leads with ●,
// and the trailer says what ✗ means and that the row leads the queue.
func TestRenderQueueMarksAFailedStart(t *testing.T) {
	tiles := startFailedTiles()
	now := time.Date(2026, 10, 26, 8, 0, 0, 0, time.UTC)
	var out strings.Builder
	renderQueue(&out, board.Board{GeneratedAt: now, Total: len(tiles), Tiles: tiles}, tiles, now, 1)
	got := out.String()

	if g := glyphOf(got, "tk-failed"); g != "✗" {
		t.Errorf("a failed start leads with ✗, got %q\n%s", g, got)
	}
	if g := glyphOf(got, "tk-parked"); g != "●" {
		t.Errorf("a held row waiting for the operator still leads with ●, got %q\n%s", g, got)
	}
	for _, want := range []string{
		"start failed (startup timeout)",
		"✗ the sitting spawned for a conversation on this bead failed to start",
		"a conversation whose sitting failed to start (✗) leads it",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("the queue render must carry %q; got:\n%s", want, got)
		}
	}
}

// TestRenderTableMarksAFailedStart: the overview's glyph is ✗ for a failed
// start too, ahead of the wants-you and held glyphs it would otherwise take,
// and the family legend explains it.
func TestRenderTableMarksAFailedStart(t *testing.T) {
	tiles := startFailedTiles()
	now := time.Date(2026, 10, 26, 8, 0, 0, 0, time.UTC)
	var out strings.Builder
	renderTable(&out, board.Board{GeneratedAt: now, Total: len(tiles), Tiles: tiles}, tiles, now, 1)
	got := out.String()

	if !strings.Contains(got, "✗ ▌ tk-failed") {
		t.Errorf("a family headed by a failed start carries ✗; got:\n%s", got)
	}
	if !strings.Contains(got, "◉ ▌ tk-parked") {
		t.Errorf("a held row that wants a person keeps ◉; got:\n%s", got)
	}
	if !strings.Contains(got, "✗ the sitting spawned for a conversation on the row failed to start") {
		t.Errorf("the family legend explains ✗; got:\n%s", got)
	}
}

// pickerLimit is the cap tmux-pick-helm.sh passes to `helm-svc board`, read off
// the script so the cut below is the picker's own.
func pickerLimit(t *testing.T) int {
	t.Helper()
	src, err := os.ReadFile("../../../../assets/scripts/tmux-pick-helm.sh")
	if err != nil {
		t.Fatalf("read the picker: %v", err)
	}
	m := regexp.MustCompile(`board --json --limit=(\d+)`).FindSubmatch(src)
	if m == nil {
		t.Fatal("found no capped board invocation in tmux-pick-helm.sh")
	}
	n, err := strconv.Atoi(string(m[1]))
	if err != nil || n <= 0 {
		t.Fatalf("the picker's cap %q is not a positive count", m[1])
	}
	return n
}

// TestPickerCutKeepsAFailedStart: the rows the picker offers are the queue view
// cut at the picker's cap. A failed start filed after every other owed row is
// among them, on a queue longer than the cap.
func TestPickerCutKeepsAFailedStart(t *testing.T) {
	limit := pickerLimit(t)
	now := time.Date(2026, 10, 26, 8, 0, 0, 0, time.UTC)
	anchors := []board.Anchor{
		{ID: "tk-subj", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk",
			Children: []board.Child{{ID: "tk-subj.1", Status: "open"}}},
		{ID: "tk-conv", Title: "talk the plan over", Kind: board.KindConversation, Source: board.KindConversation,
			Rig: "gc-toolkit", Prefix: "tk", UpdatedAt: now, Subjects: []string{"tk-subj"}, Assignee: "human"},
	}
	for i := 0; i < limit+10; i++ {
		anchors = append(anchors, board.Anchor{
			ID: fmt.Sprintf("tk-old%02d", i), Kind: "human", Source: "human", Rig: "gc-toolkit", Prefix: "tk",
			UpdatedAt: now.Add(-time.Duration(30+i) * 24 * time.Hour), Metadata: map[string]string{"gc.routed_to": "human"},
		})
	}
	b := board.BuildBoard(anchors, now, false, nil, board.Facts{
		Sittings: []board.Sitting{{ID: "tk-conv", Subject: "tk-subj", Status: "open",
			StartFailure: "never started"}},
	})

	rows := selectView(b, false, limit).rows
	if len(rows) != limit {
		t.Fatalf("fixture: the queue is longer than the picker's cap of %d; the view kept %d", limit, len(rows))
	}
	for _, r := range rows {
		if r.ID == "tk-subj" {
			if r.SittingState != board.SittingStartFailed || r.SittingStartFailure != "never started" {
				t.Errorf("the offered row reads start failed with the reason: %q %q", r.SittingState, r.SittingStartFailure)
			}
			return
		}
	}
	t.Errorf("the failed start is not among the %d rows the picker offers", limit)
}
