package reaction

import (
	"errors"
	"slices"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
)

// unmarkedIDs is the beads the unmarked list names, in its order.
func (w *world) unmarkedIDs() []string {
	w.t.Helper()
	beads, err := w.r.Unmarked()
	if err != nil {
		w.t.Fatal(err)
	}
	var out []string
	for _, b := range beads {
		out = append(out, b.ID)
	}
	return out
}

// The unmarked list takes the open beads nothing claims and no filer marked for
// a first reaction: raw input of any type the list allows, with or without a
// description or a headline, since a headline claims nothing. It leaves out a
// marked bead, one with a route, an arm or a dispatch hold, a member of a
// parent, a bead a live run works, and machinery by its keys and kinds. Each
// bead it leaves out is one the sweep reacts to or one something already
// claims, and the list writes nothing and slings nothing.
func TestTheUnmarkedListTakesWhatNothingClaims(t *testing.T) {
	keep := []fake.Bead{
		input("tk-raw", nil),
		input("tk-raw-bug", func(b *fake.Bead) { b.IssueType = "bug" }),
		input("tk-raw-feature", func(b *fake.Bead) { b.IssueType = "feature" }),
		input("tk-raw-spike", func(b *fake.Bead) { b.IssueType = "spike" }),
		input("tk-raw-chore", func(b *fake.Bead) { b.IssueType = "chore" }),
		input("tk-silent", func(b *fake.Bead) { b.Description = "" }),
		input("tk-read", meta("gc.takeaway", "blocked on tk-blocker, which has closed", "gc.takeaway_by", "proactive")),
		input("tk-blank", meta("gc.routed_to", " ", "gc.dispatch_when_ready", " ", "finding.scope", " ")),
		input("tk-exec-only", meta("gc.execution_routed_to", "gc-toolkit/gc-toolkit.polecat")),
	}
	drop := []fake.Bead{
		arrival("tk-held", nil),
		arrival("tk-held-read", meta("gc.takeaway", "ready to build once placed")),
		input("tk-external", func(b *fake.Bead) { b.Labels = []string{"Hold:External"} }),
		input("tk-finding", meta("finding.key", "doctor-x", "finding.scope", "deacon-findings")),
		input("tk-routed", meta("gc.routed_to", "gc-toolkit/gc-toolkit.polecat")),
		input("tk-armed", meta("gc.dispatch_when_ready", "gc-toolkit/gc-toolkit.polecat")),
		input("tk-member", func(b *fake.Bead) { b.Edges = []gcbd.Edge{{Type: gcbd.EdgeParentChild, ID: "tk-epic"}} }),
		input("tk-decision", func(b *fake.Bead) { b.IssueType = "decision" }),
		input("tk-spec", func(b *fake.Bead) { b.IssueType = "spec" }),
		input("tk-convoy", func(b *fake.Bead) { b.IssueType = "convoy" }),
		input("tk-workflow", meta("gc.kind", "workflow")),
		input("tk-scope", meta("gc.kind", "scope")),
		input("tk-step-ref", meta("gc.step_ref", "mol-polecat-work.implement")),
		input("tk-step-id", meta("gc.step_id", "react")),
		input("tk-step-root", meta("gc.root_bead_id", "tk-root-work")),
		input("tk-pattern", meta("task_kind", feedbackPattern)),
		input("tk-lane", meta("task_kind", "review")),
		input("tk-branch", meta("branch", "polecat/tk-branch")),
		input("tk-merge", meta("merge_result", "pending")),
		input("tk-workdir", meta("work_dir", "/tmp/tree")),
		input("tk-pr-url", meta("pr_url", "https://github.com/zook/repo/pull/1")),
		input("tk-pr-number", meta("pr_number", "1")),
		input("tk-check", meta("check_name", "correctness")),
		input("tk-anchored", meta("anchor_bead", "tk-anchor")),
		input("tk-building", nil),
	}
	for _, k := range standingKinds {
		drop = append(drop, input("tk-standing-"+k, meta("task_kind", k)))
	}
	w := newWorld(t)
	w.ready(keep...)
	w.ready(drop...)
	w.run("tk-root-building", "mol-polecat-work", "tk-building", "in_progress")
	got := w.unmarkedIDs()
	for _, b := range keep {
		if !slices.Contains(got, b.ID) {
			t.Errorf("(KEEP) %s is not listed", b.ID)
		}
	}
	for _, b := range drop {
		if slices.Contains(got, b.ID) {
			t.Errorf("(DROP) %s is listed", b.ID)
		}
	}
	if wr := w.writes(); len(wr) > 0 || len(w.slings()) > 0 {
		t.Errorf("(READONLY) the list wrote %v and slung %v", wr, w.slings())
	}
}

// The list runs highest priority first, as the ready read gives it. A run map
// that does not read drops nothing and says so, and a ready read that fails
// lists nothing.
func TestTheUnmarkedListReadsAsTheSweepDoes(t *testing.T) {
	w := newWorld(t)
	w.ready(input("tk-low", func(b *fake.Bead) { b.Priority = 3 }), input("tk-high", func(b *fake.Bead) { b.Priority = 0 }),
		input("tk-building", func(b *fake.Bead) { b.Priority = 1 }))
	w.run("tk-root-building", "mol-polecat-work", "tk-building", "in_progress")
	if got := w.unmarkedIDs(); !slices.Equal(got, []string{"tk-high", "tk-low"}) {
		t.Errorf("(ORDER) the list is %v; want tk-high, tk-low", got)
	}
	w.failFind(func(q gcbd.Query) bool { return q.HasKey == "gc.input_convoy_id" })
	if got := w.unmarkedIDs(); !slices.Contains(got, "tk-building") {
		t.Errorf("(RUNS-FAILOPEN) with the run map unread the list is %v", got)
	}
	w.saidHas("could not read the live runs", "(RUNS-FAILOPEN) saying a bead a live workflow drives may be listed")

	w = newWorld(t)
	w.store.ReadyErr = errors.New("gc bd ready exited 1: database is locked")
	if beads, err := w.r.Unmarked(); err == nil || beads != nil {
		t.Errorf("(READ-FAILCLOSED) a failed ready read listed %v, %v", beads, err)
	}
}
