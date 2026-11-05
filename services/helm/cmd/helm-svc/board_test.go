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

// builtSittings is the record as the board hands it to a renderer, each sitting
// with the state and headline the board derived.
func builtSittings(in []board.Sitting, owners ...string) []board.Sitting {
	state := map[string]string{}
	for _, o := range owners {
		state[o] = "active"
	}
	return board.BuildBoard(nil, renderNow, false, nil, board.Facts{Sittings: in, OwnerState: state}).Sittings
}

// sittingRow is the rendered line of one sitting.
func sittingRow(t *testing.T, out, id string) string {
	t.Helper()
	for _, line := range strings.Split(out, "\n") {
		if strings.Contains(line, id+" ") {
			return line
		}
	}
	t.Fatalf("no row for %s:\n%s", id, out)
	return ""
}

// TestRenderSittingsShowsBothHalves: a running sitting and a closed one, each
// saying the thing the operator asked the section for — where it stands, or what
// it concluded. A closed sitting that left no takeaway shows why it closed.
func TestRenderSittingsShowsBothHalves(t *testing.T) {
	var buf bytes.Buffer
	renderSittings(&buf, builtSittings([]board.Sitting{
		{ID: "tk-live", Rig: "gc-toolkit", Subject: "tk-anchor", Title: "still talking",
			Status: "in_progress", Assignee: "tk-live", Session: "gc-toolkit__converse-1", OpenedAt: minsAgo(41)},
		{ID: "tk-done", Rig: "gc-toolkit", Subject: "tk-other", Title: "a long escalation subject",
			Status: "closed", OutcomeReason: "the re-offer loop was the routing", OpenedAt: minsAgo(90), ClosedAt: minsAgo(20),
			Takeaway: "the re-offer loop was the routing, not the bead"},
		{ID: "tk-dismissed", Rig: "gc-toolkit", Subject: "tk-third", Title: "a third",
			Status: "closed", OutcomeReason: "dismissed by the operator", OpenedAt: minsAgo(80), ClosedAt: minsAgo(10)},
	}, "tk-live"), renderNow)
	out := buf.String()

	for _, want := range []string{
		"1 in session · 0 waiting · 2 closed recently",
		"tk-live", "tk-anchor", "41m",
		"tk-done", "20m",
		"the re-offer loop was the routing, not the bead",
		"dismissed by the operator",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("rendered sittings missing %q:\n%s", want, out)
		}
	}
	if strings.Contains(out, "OUTCOME") {
		t.Errorf("the record has no outcome column:\n%s", out)
	}
	// The takeaway is preferred over the close reason and the title: it is what
	// the sitting concluded.
	done, _, _ := strings.Cut(out[strings.Index(out, "tk-done"):], "\n")
	if strings.Contains(done, "a long escalation subject") || strings.HasSuffix(done, "the re-offer loop was the routing") {
		t.Errorf("a sitting with a takeaway renders it, not its title or close reason: %q", done)
	}
}

// TestRenderSittingsFallsBackToTheSubjectTitle: a sitting that left no
// attributable takeaway and no close reason shows the subject's title — the
// topic — as its headline, never the conversation's own title. Only a subject
// the gather could not read at all drops to the conversation's title.
func TestRenderSittingsFallsBackToTheSubjectTitle(t *testing.T) {
	var buf bytes.Buffer
	renderSittings(&buf, builtSittings([]board.Sitting{{
		ID: "tk-bare", Rig: "gc-toolkit", Subject: "tk-anchor",
		SubjectTitle: "helm returns the raw script path",
		Title:        "operator pick from the board",
		Status:       "in_progress", OpenedAt: minsAgo(60),
	}}), renderNow)
	out := buf.String()

	if !strings.Contains(out, "helm returns the raw script path") {
		t.Errorf("no takeaway falls back to the subject title (the topic):\n%s", out)
	}
	if strings.Contains(out, "operator pick from the board") {
		t.Errorf("the conversation's title must not be the headline once the subject has one:\n%s", out)
	}

	// Only an unreadable subject — no title at all — drops to the conversation's title.
	var last bytes.Buffer
	renderSittings(&last, builtSittings([]board.Sitting{{
		ID: "tk-none", Rig: "gc-toolkit", Subject: "tk-anchor",
		Title: "operator pick from the board", Status: "in_progress", OpenedAt: minsAgo(60),
	}}), renderNow)
	if !strings.Contains(last.String(), "operator pick from the board") {
		t.Errorf("an unread subject still says what it was called, via the conversation's title:\n%s", last.String())
	}
}

// TestRenderSittingsSaysWhatItElided: the cap bounds history, and an elided
// list that does not admit it reads as the whole record.
func TestRenderSittingsSaysWhatItElided(t *testing.T) {
	var in []board.Sitting
	for i := range board.DefaultMaxSittings + 4 {
		in = append(in, board.Sitting{
			ID: fmt.Sprintf("tk-c%02d", i), Rig: "gc-toolkit", Subject: "tk-anchor",
			Title: "a conversation", Status: "closed", OutcomeReason: "settled",
			OpenedAt: minsAgo(600 - i), ClosedAt: minsAgo(500 - i),
		})
	}
	var buf bytes.Buffer
	renderSittings(&buf, builtSittings(in), renderNow)
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

// TestRenderSittingsPrintsEachSittingsState: the section says of each sitting
// whether a session holds it, in the word the board derived, and its count line
// splits the open ones the same way. A failed start is named only when there is
// one. A sitting whose session ended reads waiting though its conversation is
// still in_progress.
func TestRenderSittingsPrintsEachSittingsState(t *testing.T) {
	sittings := []board.Sitting{
		{ID: "tk-live", Subject: "tk-a", Title: "held", Status: "in_progress", Assignee: "tk-live", OpenedAt: minsAgo(41)},
		{ID: "tk-ended", Subject: "tk-b", Title: "its session ended", Status: "in_progress", Assignee: "tk-ended", OpenedAt: minsAgo(30)},
		{ID: "tk-queued", Subject: "tk-c", Title: "in the queue", Status: "open", Assignee: "human", OpenedAt: minsAgo(20)},
		{ID: "tk-done", Subject: "tk-d", Title: "finished", Status: "closed", OpenedAt: minsAgo(90), ClosedAt: minsAgo(10)},
	}

	var buf bytes.Buffer
	renderSittings(&buf, builtSittings(sittings, "tk-live"), renderNow)
	out := buf.String()
	if !strings.Contains(out, "Sittings — 1 in session · 2 waiting · 1 closed recently\n") {
		t.Errorf("the count line splits running into in session and waiting:\n%s", out)
	}
	if strings.Contains(out, "running") || strings.Contains(out, "start failed ·") {
		t.Errorf("no running count, and no failed count with no failed start:\n%s", out)
	}
	for id, want := range map[string]struct{ word, age string }{
		"tk-live":   {"in session", "41m"},
		"tk-ended":  {"waiting", "30m"},
		"tk-queued": {"waiting", "20m"},
		"tk-done":   {"closed", "10m"},
	} {
		row := sittingRow(t, out, id)
		if !strings.HasPrefix(row, want.word+" ") {
			t.Errorf("%s reads %q, want the word %q first", id, row, want.word)
		}
		if !strings.Contains(row, " "+want.age+" ") {
			t.Errorf("%s reads %q, want the age %s: an open sitting's from its start, a closed one's from its end", id, row, want.age)
		}
	}

	failed := append(sittings, board.Sitting{ID: "tk-failed", Subject: "tk-e", Title: "never started",
		Status: "in_progress", StartFailure: "setup timeout", OpenedAt: minsAgo(5)})
	buf.Reset()
	renderSittings(&buf, builtSittings(failed, "tk-live"), renderNow)
	out = buf.String()
	if !strings.Contains(out, "Sittings — 1 in session · 2 waiting · 1 start failed · 1 closed recently\n") {
		t.Errorf("a failed start is counted apart:\n%s", out)
	}
	if row := sittingRow(t, out, "tk-failed"); !strings.HasPrefix(row, "start failed ") {
		t.Errorf("the failed start reads %q", row)
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
		Title: "talk it through", Status: "in_progress", OpenedAt: minsAgo(41),
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
