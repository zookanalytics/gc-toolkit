package main

import (
	"bytes"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/board"
)

var renderNow = time.Date(2026, 8, 1, 12, 0, 0, 0, time.UTC)

func minsAgo(m int) time.Time { return renderNow.Add(-time.Duration(m) * time.Minute) }

// TestRenderSittingsShowsBothHalves: a running sitting and a closed one, each
// saying the thing the operator asked the section for — that it is running, or
// what it closed on.
func TestRenderSittingsShowsBothHalves(t *testing.T) {
	var buf bytes.Buffer
	renderSittings(&buf, []board.Sitting{
		{ID: "tk-live", Rig: "gc-toolkit", Subject: "tk-anchor", Title: "visit: tk-anchor — still talking",
			Status: "in_progress", Session: "gc-toolkit__converse-1", OpenedAt: minsAgo(41)},
		{ID: "tk-done", Rig: "gc-toolkit", Subject: "tk-other", Title: "visit: tk-other — a long escalation subject",
			Status: "closed", Outcome: "diagnosed", OpenedAt: minsAgo(90), ClosedAt: minsAgo(20),
			Takeaway: "the re-offer loop was the routing, not the bead"},
	}, renderNow)
	out := buf.String()

	for _, want := range []string{
		"1 running · 1 closed",
		"tk-live", "tk-anchor", "41m", "●",
		"tk-done", "diagnosed", "20m",
		"the re-offer loop was the routing, not the bead",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("rendered sittings missing %q:\n%s", want, out)
		}
	}
	// A running sitting has not concluded, so it must not display an outcome.
	live, _, _ := strings.Cut(out[strings.Index(out, "tk-live"):], "\n")
	if !strings.Contains(live, "—") {
		t.Errorf("a running sitting shows no outcome, it shows the absence: %q", live)
	}
	// The takeaway is preferred over the title: it is what the sitting concluded.
	done, _, _ := strings.Cut(out[strings.Index(out, "tk-done"):], "\n")
	if strings.Contains(done, "a long escalation subject") {
		t.Errorf("a sitting with a takeaway renders it, not its title: %q", done)
	}
}

// TestRenderSittingsFallsBackToTheTitle: a sitting that left no attributable
// takeaway still has to say what it was about.
func TestRenderSittingsFallsBackToTheTitle(t *testing.T) {
	var buf bytes.Buffer
	renderSittings(&buf, []board.Sitting{{
		ID: "tk-bare", Rig: "gc-toolkit", Subject: "tk-anchor",
		Title: "visit: tk-anchor — first reaction ready", Status: "closed",
		Outcome: "folded", OpenedAt: minsAgo(60), ClosedAt: minsAgo(30),
	}}, renderNow)

	if !strings.Contains(buf.String(), "first reaction ready") {
		t.Errorf("no takeaway falls back to the title:\n%s", buf.String())
	}
}

// TestRenderSittingsSaysWhatItElided: the cap bounds history, and an elided
// list that does not admit it reads as the whole record.
func TestRenderSittingsSaysWhatItElided(t *testing.T) {
	var in []board.Sitting
	for i := range board.DefaultMaxSittings + 4 {
		in = append(in, board.Sitting{
			ID: fmt.Sprintf("tk-c%02d", i), Rig: "gc-toolkit", Subject: "tk-anchor",
			Title: "visit", Status: "closed", Outcome: "moot",
			OpenedAt: minsAgo(600 - i), ClosedAt: minsAgo(500 - i),
		})
	}
	var buf bytes.Buffer
	renderSittings(&buf, in, renderNow)
	out := buf.String()

	if !strings.Contains(out, "4 older closed sittings not shown") {
		t.Errorf("an elided list must say so:\n%s", out)
	}
	// The count in the caption is the WHOLE record, not the shown rows: the
	// operator has to know how many there were to know 4 is a small tail.
	if !strings.Contains(out, fmt.Sprintf("%d closed recently", board.DefaultMaxSittings+4)) {
		t.Errorf("the caption counts the whole record:\n%s", out)
	}
}

// TestRenderSittingsIsSilentWhenThereAreNone keeps a quiet city quiet: an empty
// record prints no heading at all.
func TestRenderSittingsIsSilentWhenThereAreNone(t *testing.T) {
	var buf bytes.Buffer
	renderSittings(&buf, nil, renderNow)
	if buf.Len() != 0 {
		t.Errorf("an empty record renders nothing, got %q", buf.String())
	}
}

func TestShortAge(t *testing.T) {
	cases := []struct {
		stamp time.Time
		want  string
	}{
		{time.Time{}, "?"},
		{renderNow, "0m"},
		{minsAgo(59), "59m"},
		{minsAgo(60), "1h"},
		{minsAgo(47 * 60), "47h"},
		{minsAgo(48 * 60), "2d"},
		// Clock skew: a stamp in the future is 0, never a negative age.
		{renderNow.Add(time.Hour), "0m"},
	}
	for _, c := range cases {
		if got := shortAge(c.stamp, renderNow); got != c.want {
			t.Errorf("shortAge(%v) = %q, want %q", c.stamp, got, c.want)
		}
	}
}

// TestEveryRenderedViewCarriesTheConversationRecord: the sittings section
// belongs to the board, not to one of its views. `board` answers with the
// operator's queue and `board --all` with the city overview, and a running
// sitting is a conversation nobody has ended under either framing. The arms
// that print no rows are included because that is where the record is the only
// thing left to say.
func TestEveryRenderedViewCarriesTheConversationRecord(t *testing.T) {
	sittings := []board.Sitting{{
		ID: "tk-live", Rig: "gc-toolkit", Subject: "tk-anchor",
		Title: "visit: tk-anchor", Status: "in_progress", OpenedAt: minsAgo(41),
	}}
	anchors := []board.Anchor{{
		ID: "tk-owed", Title: "waiting on a person", Kind: "human", Source: "human",
		Rig: "gc-toolkit", Prefix: "tk", UpdatedAt: renderNow,
		Metadata: map[string]string{"gc.routed_to": "human"}, WaitingUnknown: true,
	}}
	full := board.BuildBoard(anchors, renderNow, false, nil, board.Facts{Sittings: sittings})
	bare := board.BuildBoard(nil, renderNow, false, nil, board.Facts{Sittings: sittings})

	for _, tc := range []struct {
		name   string
		render func(*bytes.Buffer)
	}{
		{"queue", func(w *bytes.Buffer) { renderQueue(w, full, full.Tiles, renderNow, 5) }},
		{"empty queue", func(w *bytes.Buffer) { renderQueue(w, bare, nil, renderNow, 5) }},
		{"overview", func(w *bytes.Buffer) { renderTable(w, full, full.Tiles, renderNow, 5) }},
		{"empty overview", func(w *bytes.Buffer) { renderTable(w, bare, nil, renderNow, 5) }},
	} {
		var buf bytes.Buffer
		tc.render(&buf)
		if !strings.Contains(buf.String(), "tk-live") {
			t.Errorf("the %s view drops the conversation record:\n%s", tc.name, buf.String())
		}
	}
}
