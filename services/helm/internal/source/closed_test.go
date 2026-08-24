package source

import (
	"context"
	"encoding/json"
	"errors"
	"testing"
	"time"

	"github.com/steveyegge/beads"
)

// visitIssue builds a closed visit bead: a close time, an outcome, and however
// it names its subject.
func visitIssue(id string, closedAt time.Time, outcome, stamp, tracks string) *beads.Issue {
	meta := map[string]string{"task_kind": "visit"}
	if outcome != "" {
		meta["gc.outcome"] = outcome
	}
	if stamp != "" {
		meta["gc.continuation_group"] = stamp
	}
	raw, _ := json.Marshal(meta)
	at := closedAt
	iss := &beads.Issue{
		ID:        id,
		Title:     "visit: " + id,
		Status:    beads.StatusClosed,
		ClosedAt:  &at,
		UpdatedAt: closedAt,
		Metadata:  raw,
	}
	if tracks != "" {
		iss.Dependencies = []*beads.Dependency{
			{IssueID: id, DependsOnID: tracks, Type: beads.DependencyType("tracks")},
		}
	}
	return iss
}

func subjectIssue(id, title, takeaway string) *beads.Issue {
	meta := map[string]string{}
	if takeaway != "" {
		meta["gc.takeaway"] = takeaway
	}
	raw, _ := json.Marshal(meta)
	return &beads.Issue{ID: id, Title: title, Status: beads.StatusOpen, Metadata: raw}
}

// TestSubjectOfPrefersTracksEdge is the case the shell suite's (VISITEDGE)
// carried before the board moved here, and it is the divergence tk-clvkf6
// closed: gc-helm.sh read a visit's subject from the `tracks` edge FIRST and
// this package read only the gc.continuation_group stamp, so the same
// conversation could show held on one board and unheld on the other.
//
// It is not a tie-breaker for an edge case. Measured over gc-toolkit's last
// seven days on 2026-08-24: 49 closed visits, 49 carrying the edge, 44 carrying
// the stamp. A stamp-only read loses five, and an anchor whose visit is missed
// is not merely unglyphed — it is never held, so it bands as STRANDED and the
// board tells the operator to go and attend to a conversation already being
// had (bead tk-d6ddn, first seen on su-ab9je 2026-08-20).
func TestSubjectOfPrefersTracksEdge(t *testing.T) {
	t.Run("edge wins over a disagreeing stamp", func(t *testing.T) {
		got := subjectOf(visitIssue("tk-v1", time.Now(), "routed", "tk-stamped", "tk-tracked"))
		if got != "tk-tracked" {
			t.Errorf("subject = %q, want the tracks edge tk-tracked", got)
		}
	})
	t.Run("an EMPTY stamp still resolves through the edge", func(t *testing.T) {
		got := subjectOf(visitIssue("tk-v2", time.Now(), "routed", "", "tk-tracked"))
		if got != "tk-tracked" {
			t.Errorf("subject = %q, want tk-tracked; this is the live shape that diverged", got)
		}
	})
	t.Run("the stamp is the fallback, not dead code", func(t *testing.T) {
		got := subjectOf(visitIssue("tk-v3", time.Now(), "routed", "tk-stamped", ""))
		if got != "tk-stamped" {
			t.Errorf("subject = %q, want the stamp tk-stamped", got)
		}
	})
	t.Run("neither is legal and renders as unlinked", func(t *testing.T) {
		if got := subjectOf(visitIssue("tk-v4", time.Now(), "routed", "", "")); got != "" {
			t.Errorf("subject = %q, want empty", got)
		}
	})
	t.Run("a non-tracks edge is not a subject", func(t *testing.T) {
		iss := visitIssue("tk-v5", time.Now(), "routed", "", "")
		iss.Dependencies = []*beads.Dependency{
			{IssueID: "tk-v5", DependsOnID: "tk-blocker", Type: beads.DependencyType("blocks")},
		}
		if got := subjectOf(iss); got != "" {
			t.Errorf("subject = %q; a blocks edge is not what a visit tracks", got)
		}
	})
}

// TestVisitSubjectsReadsTheEdge is the same fix seen from the board's side: the
// join behind Tile.Held has to hydrate dependencies and spend them.
func TestVisitSubjectsReadsTheEdge(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	st := populatedStore()
	// An OPEN visit whose stamp never landed. Under the stamp-only read this
	// anchor was invisible to the join.
	open := visitIssue("tk-visit-open", time.Now(), "", "", "tk-epic1")
	open.Status = beads.StatusOpen
	open.ClosedAt = nil
	st.issues["task"] = append(st.issues["task"], open)

	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": st})
	g := &gatherState{rigByPrefix: map[string]string{}}
	got := src.visitSubjects(context.Background(), st, rigRef{name: "gc-toolkit", prefix: "tk"}, g)

	if !contains(got, "tk-epic1") {
		t.Errorf("visitSubjects = %v; a visit naming its subject only by the tracks edge was dropped", got)
	}
}

func contains(hay []string, want string) bool {
	for _, h := range hay {
		if h == want {
			return true
		}
	}
	return false
}

// TestGatherClosedJoinsSubjects covers the whole read: the window, the per-visit
// row, and the title/takeaway join.
func TestGatherClosedJoinsSubjects(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	now := time.Now().UTC()
	st := populatedStore()
	st.closedIssues = []*beads.Issue{
		visitIssue("tk-v-new", now.Add(-1*time.Hour), "routed", "", "tk-subj"),
		visitIssue("tk-v-old", now.Add(-3*time.Hour), "moot", "tk-subj", "tk-subj"),
	}
	st.subjects = []*beads.Issue{subjectIssue("tk-subj", "the subject", "routed — work is out")}

	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": st})
	rows, err := src.GatherClosed(context.Background(), now.Add(-24*time.Hour))
	if err != nil {
		t.Fatalf("GatherClosed: %v", err)
	}
	if len(rows) != 2 {
		t.Fatalf("got %d rows, want 2 — rows are per VISIT, so one subject with two sittings is two rows", len(rows))
	}
	for _, r := range rows {
		if r.Subject != "tk-subj" {
			t.Errorf("%s: subject = %q, want tk-subj", r.Visit, r.Subject)
		}
		if r.SubjectTitle != "the subject" {
			t.Errorf("%s: title = %q, want the subject's own title", r.Visit, r.SubjectTitle)
		}
		if r.Takeaway != "routed — work is out" {
			t.Errorf("%s: takeaway = %q, want the subject's takeaway", r.Visit, r.Takeaway)
		}
		if r.Rig != "gc-toolkit" {
			t.Errorf("%s: rig = %q", r.Visit, r.Rig)
		}
	}
}

// TestGatherClosedHonoursTheWindow proves the cutoff is spent, not decorative.
func TestGatherClosedHonoursTheWindow(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	now := time.Now().UTC()
	st := populatedStore()
	st.closedIssues = []*beads.Issue{
		visitIssue("tk-in", now.Add(-1*time.Hour), "routed", "", "tk-subj"),
		visitIssue("tk-out", now.Add(-48*time.Hour), "routed", "", "tk-subj"),
	}
	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": st})
	rows, err := src.GatherClosed(context.Background(), now.Add(-24*time.Hour))
	if err != nil {
		t.Fatalf("GatherClosed: %v", err)
	}
	if len(rows) != 1 || rows[0].Visit != "tk-in" {
		t.Fatalf("rows = %+v, want only tk-in", rows)
	}
}

// TestGatherClosedIgnoresNonVisits keeps the metadata predicate load-bearing: a
// window full of ordinary closed work is not a list of dispositions.
func TestGatherClosedIgnoresNonVisits(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	now := time.Now().UTC()
	st := populatedStore()
	ordinary := &beads.Issue{
		ID: "tk-work", Status: beads.StatusClosed, UpdatedAt: now,
		Metadata: json.RawMessage(`{"task_kind":"implementation"}`),
	}
	at := now.Add(-time.Hour)
	ordinary.ClosedAt = &at
	st.closedIssues = []*beads.Issue{ordinary, visitIssue("tk-v", now.Add(-time.Hour), "routed", "", "tk-subj")}

	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": st})
	rows, err := src.GatherClosed(context.Background(), now.Add(-24*time.Hour))
	if err != nil {
		t.Fatalf("GatherClosed: %v", err)
	}
	if len(rows) != 1 || rows[0].Visit != "tk-v" {
		t.Fatalf("rows = %+v, want only the visit", rows)
	}
}

// TestGatherClosedResolvesAcrossRigs pins the reason subjects are looked up by
// asking every rig for what is still unresolved rather than by routing on the
// id prefix: a visit in one rig routinely names a bead in another.
func TestGatherClosedResolvesAcrossRigs(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk", "signal-loom": "sl"})
	now := time.Now().UTC()
	tk := populatedStore()
	tk.closedIssues = []*beads.Issue{visitIssue("tk-v", now.Add(-time.Hour), "routed", "", "sl-subj")}
	sl := &fakeStore{
		issues:   map[string][]*beads.Issue{},
		subjects: []*beads.Issue{subjectIssue("sl-subj", "a signal-loom subject", "ruled")},
	}

	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": tk, "signal-loom": sl})
	rows, err := src.GatherClosed(context.Background(), now.Add(-24*time.Hour))
	if err != nil {
		t.Fatalf("GatherClosed: %v", err)
	}
	if len(rows) != 1 {
		t.Fatalf("got %d rows, want 1", len(rows))
	}
	if rows[0].SubjectTitle != "a signal-loom subject" {
		t.Errorf("title = %q; a cross-rig subject went unresolved", rows[0].SubjectTitle)
	}
}

// TestGatherClosedFailsTotally is the contract that separates this view from the
// board. A board degrades to `partial` because the rows it did read still mean
// what they say; here a list quietly missing a wedged rig's dispositions is
// indistinguishable from a genuinely quiet window, which is the one answer this
// surface must never invent.
func TestGatherClosedFailsTotally(t *testing.T) {
	now := time.Now().UTC()

	t.Run("a failed visit scan aborts", func(t *testing.T) {
		root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk", "signal-loom": "sl"})
		good := populatedStore()
		good.closedIssues = []*beads.Issue{visitIssue("tk-v", now.Add(-time.Hour), "routed", "", "tk-subj")}
		bad := &fakeStore{issues: map[string][]*beads.Issue{}, failMeta: map[string]error{"closed": errors.New("dolt wedged")}}

		src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": good, "signal-loom": bad})
		rows, err := src.GatherClosed(context.Background(), now.Add(-24*time.Hour))
		if err == nil {
			t.Fatalf("want an error, got %d rows — a partial list reads as a quiet window", len(rows))
		}
		if rows != nil {
			t.Errorf("rows = %+v, want none rendered", rows)
		}
	})

	t.Run("a failed SUBJECT lookup aborts too", func(t *testing.T) {
		// It would only have blanked a title, which is exactly why it must not
		// pass: this view's whole payload is the subject and its takeaway.
		root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
		st := populatedStore()
		st.closedIssues = []*beads.Issue{visitIssue("tk-v", now.Add(-time.Hour), "routed", "", "tk-subj")}
		st.failMeta = map[string]error{"subjects": errors.New("dolt wedged")}

		src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": st})
		if _, err := src.GatherClosed(context.Background(), now.Add(-24*time.Hour)); err == nil {
			t.Fatal("want an error; blank titles are not a degraded answer, they are a wrong one")
		}
	})
}

// TestClosedAtFallsBackToUpdatedAt guards the sort. ClosedAt is nullable, and a
// visit closed by a path that did not stamp it would otherwise sort to the zero
// time — landing at the BOTTOM of a newest-first list, so the thing that just
// happened looks like the oldest row in the window.
func TestClosedAtFallsBackToUpdatedAt(t *testing.T) {
	now := time.Now().UTC().Truncate(time.Second)
	iss := visitIssue("tk-v", now, "routed", "", "tk-subj")
	iss.ClosedAt = nil
	if got := closedAt(iss); !got.Equal(now) {
		t.Errorf("closedAt = %v, want the update time %v", got, now)
	}
}
