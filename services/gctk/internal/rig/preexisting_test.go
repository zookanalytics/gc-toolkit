package rig

import (
	"encoding/json"
	"errors"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/git"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// unreadStore is a store whose read of each bead it names fails, as a lookup
// that fails does.
type unreadStore struct {
	*fake.Store
	ids []string
}

func (s unreadStore) Find(q gcbd.Query) ([]gcbd.Bead, error) {
	for _, id := range q.IDs {
		if slices.Contains(s.ids, id) {
			return nil, &gcbd.ReadError{ID: id, Reason: "the store did not answer"}
		}
	}
	return s.Store.Find(q)
}

// world is a checkout at commitA whose record store holds a lint fail there,
// and a store holding the work bead tk-w with the trackers the cases name:
// tk-open open, tk-blocked blocked, tk-fixed closed with no successor, tk-folded
// closed onto the open tk-batch.
type world struct {
	co    *git.Checkout
	store *fake.Store
	fail  *Record
}

func newWorld(t *testing.T) *world {
	t.Helper()
	dir := t.TempDir()
	w := &world{co: &git.Checkout{Top: dir, Common: dir, Commit: commitA, Tree: treeT}, store: fake.New()}
	w.fail = rec(CheckLint, ResultFail, "", commitA, treeT)
	mustPut(t, NewStore(dir), w.fail)
	w.store.Put(fake.Bead{ID: "tk-w", Status: "in_progress", IssueType: "task"})
	w.store.Put(fake.Bead{ID: "tk-open", Status: "open", IssueType: "bug"})
	w.store.Put(fake.Bead{ID: "tk-blocked", Status: "blocked", IssueType: "bug"})
	w.store.Put(fake.Bead{ID: "tk-fixed", Status: "closed", IssueType: "bug", CloseReason: "Fixed on main"})
	w.store.Put(fake.Bead{ID: "tk-folded", Status: "closed", IssueType: "bug", CloseReason: "folded into tk-batch",
		Edges: []gcbd.Edge{{Type: "supersedes", ID: "tk-batch"}}})
	w.store.Put(fake.Bead{ID: "tk-batch", Status: "open", IssueType: "task"})
	return w
}

// markText is a mark's stored value, as the store holds it: the JSON object as
// a string.
func markText(t *testing.T, commit string, record any, trackers ...string) string {
	t.Helper()
	raw, err := json.Marshal(map[string]any{"commit": commit, "record": record, "trackers": trackers})
	if err != nil {
		t.Fatal(err)
	}
	return string(raw)
}

// mark puts a value in tk-w's key.
func (w *world) mark(key, value string) {
	b, _ := w.store.Row("tk-w")
	if b.Metadata == nil {
		b.Metadata = map[string]string{}
	}
	b.Metadata[key] = value
	w.store.Put(b)
}

func (w *world) judge(s gcbd.Store, check string) Judgment {
	return Judge(ledger.New(s), w.co, "tk-w", check)
}

func TestAMarkHoldsTheFailWhileATrackerItNamesIsOpen(t *testing.T) {
	w := newWorld(t)
	w.mark("rig_check_pre_existing.lint", markText(t, commitA, w.fail, "tk-open"))
	got := w.judge(w.store, CheckLint)
	if got.Answer != Holds || got.Line != "pre-existing, tracked by tk-open" || !slices.Equal(got.Open, []string{"tk-open"}) {
		t.Fatalf("an open tracker: %+v, want it to hold", got)
	}
	w.mark("rig_check_pre_existing.lint", markText(t, commitA, w.fail, "tk-fixed", "tk-blocked"))
	if got := w.judge(w.store, CheckLint); got.Answer != Holds || got.Line != "pre-existing, tracked by tk-blocked" {
		t.Errorf("one closed tracker and one blocked: %+v, want it to hold by the blocked one alone", got)
	}
}

// A mark judges one record: a record whose keys come in another order is the
// same one, as jq's == compares them.
func TestAMarkHoldsItsRecordWhateverTheOrderOfItsKeys(t *testing.T) {
	w := newWorld(t)
	raw, _ := json.Marshal(w.fail)
	var fields map[string]any
	_ = json.Unmarshal(raw, &fields)
	w.mark("rig_check_pre_existing.lint", markText(t, commitA, fields, "tk-open"))
	if got := w.judge(w.store, CheckLint); got.Answer != Holds {
		t.Errorf("the record as a map: %+v, want it to hold", got)
	}
}

func TestATrackerThatClosedHoldsNothing(t *testing.T) {
	w := newWorld(t)
	w.mark("rig_check_pre_existing.lint", markText(t, commitA, w.fail, "tk-fixed"))
	got := w.judge(w.store, CheckLint)
	if want := "tk-fixed is not open and no open bead carries its failure, so merge the base in"; got.Answer != NoOpenTracker ||
		!strings.Contains(got.Line, "names no open tracker, so it judges nothing: "+want) {
		t.Errorf("a fixed tracker: %+v, want no open tracker and %q", got, want)
	}
	w.mark("rig_check_pre_existing.lint", markText(t, commitA, w.fail, "tk-folded"))
	got = w.judge(w.store, CheckLint)
	if want := "tk-folded has closed, and tk-batch carries its failure now, so mark the fail against tk-batch"; got.Answer != NoOpenTracker ||
		!strings.Contains(got.Line, want) {
		t.Errorf("a folded tracker: %+v, want no open tracker and %q", got, want)
	}
}

// A tracker read that fails is not open, and is reported as unread, never as
// closed, and so is a bead that does not read.
func TestAReadThatFailsHoldsNothingAndSaysSo(t *testing.T) {
	w := newWorld(t)
	w.mark("rig_check_pre_existing.lint", markText(t, commitA, w.fail, "tk-open", "tk-fixed"))
	got := w.judge(unreadStore{Store: w.store, ids: []string{"tk-open"}}, CheckLint)
	if got.Answer != Unread || !strings.Contains(got.Line, "did not read, so nothing shows the mark still holds: tk-open did not read") ||
		!strings.Contains(got.Line, "tk-fixed is not open") {
		t.Errorf("an unread tracker beside a fixed one: %+v, want unread naming both", got)
	}
	w.mark("rig_check_pre_existing.lint", markText(t, commitA, w.fail, "tk-open", "tk-blocked"))
	if got := w.judge(unreadStore{Store: w.store, ids: []string{"tk-open"}}, CheckLint); got.Answer != Holds ||
		got.Line != "pre-existing, tracked by tk-blocked" {
		t.Errorf("an unread tracker beside an open one: %+v, want it to hold by the open one", got)
	}
	if got := w.judge(unreadStore{Store: w.store, ids: []string{"tk-w"}}, CheckLint); got.Answer != Unread ||
		!strings.Contains(got.Line, "tk-w did not read, so no pre-existing mark is known") {
		t.Errorf("a bead that does not read: %+v, want unread", got)
	}
}

func TestAMarkJudgesOnlyItsCommitAndItsRun(t *testing.T) {
	w := newWorld(t)
	if got := w.judge(w.store, CheckLint); got.Answer != NoMark || got.Line != "" {
		t.Errorf("no mark: %+v, want NoMark with no line", got)
	}
	w.mark("rig_check_pre_existing.lint", markText(t, commitB, w.fail, "tk-open"))
	if got := w.judge(w.store, CheckLint); got.Answer != NoMark {
		t.Errorf("a mark at another commit: %+v, want NoMark", got)
	}
	w.mark("rig_check_pre_existing.lint", markText(t, commitA, w.fail))
	if got := w.judge(w.store, CheckLint); got.Answer != NoMark {
		t.Errorf("a mark that names no tracker: %+v, want NoMark", got)
	}
	w.mark("rig_check_pre_existing.lint", "not json")
	if got := w.judge(w.store, CheckLint); got.Answer != NoMark {
		t.Errorf("a mark that does not decode: %+v, want NoMark", got)
	}
	other := *w.fail
	other.Command = "make lint"
	w.mark("rig_check_pre_existing.lint", markText(t, commitA, other, "tk-open"))
	if got := w.judge(w.store, CheckLint); got.Answer != AnotherRun || !strings.Contains(got.Line, "judged another run's fail") {
		t.Errorf("a mark of another run: %+v, want AnotherRun", got)
	}
}

func TestOnlyARecordedFailIsJudged(t *testing.T) {
	w := newWorld(t)
	w.mark("rig_check_pre_existing.test", markText(t, commitA, w.fail, "tk-open"))
	if got := w.judge(w.store, CheckTest); got.Answer != NoFail || !strings.Contains(got.Line, "nothing is recorded for test at "+commitA) {
		t.Errorf("nothing recorded: %+v, want NoFail", got)
	}
	mustPut(t, NewStore(w.co.Common), rec(CheckTest, ResultPass, ScopeAffected, commitA, treeT))
	if got := w.judge(w.store, CheckTest); got.Answer != NoFail || !strings.Contains(got.Line, "is a pass") {
		t.Errorf("a recorded pass: %+v, want NoFail", got)
	}
}

// setup and build have no record, so a mark of either holds the self-review's
// note of them at the commit.
func TestAMarkOfSetupOrBuildHoldsTheNote(t *testing.T) {
	w := newWorld(t)
	note := map[string]any{"commit": commitA, "setup": "pass", "build": "fail", "setup_command": "", "build_command": "make"}
	raw, _ := json.Marshal(note)
	w.mark("self_review_setup_build", string(raw))
	w.mark("rig_check_pre_existing.build", markText(t, commitA, note, "tk-open"))
	if got := w.judge(w.store, CheckBuild); got.Answer != Holds {
		t.Errorf("a build fail the note records: %+v, want it to hold", got)
	}
	if got := w.judge(w.store, CheckSetup); got.Answer != NoFail || !strings.Contains(got.Line, "records setup as pass") {
		t.Errorf("a setup the note records as a pass: %+v, want NoFail", got)
	}
	note["commit"] = commitB
	raw, _ = json.Marshal(note)
	w.mark("self_review_setup_build", string(raw))
	if got := w.judge(w.store, CheckBuild); got.Answer != NoFail || !strings.Contains(got.Line, "notes no setup and build at "+commitA) {
		t.Errorf("a note of another commit: %+v, want NoFail", got)
	}
}

func (w *world) markFail(s gcbd.Store, check, commit string, trackers ...string) (*Mark, error) {
	return MarkFail(ledger.New(s), w.co, "tk-w", check, commit, trackers)
}

// written is tk-w's mark of check as the store holds it.
func (w *world) written(t *testing.T, check string) Mark {
	t.Helper()
	b, _ := w.store.Row("tk-w")
	var m Mark
	if err := json.Unmarshal([]byte(b.Metadata["rig_check_pre_existing."+check]), &m); err != nil {
		t.Fatalf("tk-w's mark of %s does not decode: %v", check, err)
	}
	return m
}

func TestTheWriterMarksTheFailAgainstOpenTrackers(t *testing.T) {
	w := newWorld(t)
	if _, err := w.markFail(w.store, CheckLint, commitA, "tk-open"); err != nil {
		t.Fatalf("MarkFail: %v", err)
	}
	m := w.written(t, CheckLint)
	if m.Commit != commitA || !slices.Equal(m.Trackers, []string{"tk-open"}) || !sameJSON(m.Record, mustJSON(t, w.fail)) {
		t.Fatalf("the mark written: %+v, want the fail at %s tracked by tk-open", m, commitA)
	}
	if len(w.store.Writes()) != 1 {
		t.Errorf("writes = %+v, want one", w.store.Writes())
	}
	if _, err := w.markFail(w.store, CheckLint, commitA, "tk-blocked"); err != nil {
		t.Fatalf("MarkFail: %v", err)
	}
	if m := w.written(t, CheckLint); !slices.Equal(m.Trackers, []string{"tk-blocked", "tk-open"}) {
		t.Errorf("a second mark of the same fail: %v, want both trackers", m.Trackers)
	}
	other := *w.fail
	other.Command = "make lint"
	w.mark("rig_check_pre_existing.lint", markText(t, commitA, other, "tk-old"))
	if _, err := w.markFail(w.store, CheckLint, commitA, "tk-open"); err != nil {
		t.Fatalf("MarkFail: %v", err)
	}
	if m := w.written(t, CheckLint); !slices.Equal(m.Trackers, []string{"tk-open"}) || !sameJSON(m.Record, mustJSON(t, w.fail)) {
		t.Errorf("a mark over another run's: %+v, want it replaced", m)
	}
}

func TestTheWriterRefusesATrackerThatIsNotOpen(t *testing.T) {
	w := newWorld(t)
	for _, tc := range []struct{ tracker, want string }{
		{"tk-fixed", "tk-fixed is not open and no open bead carries its failure, so merge the base in"},
		{"tk-folded", "tk-folded has closed, and tk-batch carries its failure now, so mark the fail against tk-batch"},
	} {
		_, err := w.markFail(w.store, CheckLint, commitA, "tk-open", tc.tracker)
		var refused *Refusal
		if !errors.As(err, &refused) || !strings.Contains(err.Error(), tc.want) {
			t.Errorf("a mark naming %s: %v, want a refusal saying %q", tc.tracker, err, tc.want)
		}
	}
	_, err := w.markFail(unreadStore{Store: w.store, ids: []string{"tk-open"}}, CheckLint, commitA, "tk-open")
	var refused *Refusal
	if err == nil || errors.As(err, &refused) || !strings.Contains(err.Error(), "tk-open did not read") {
		t.Errorf("a tracker that does not read: %v, want an error that is no refusal", err)
	}
	if len(w.store.Writes()) != 0 {
		t.Errorf("writes = %+v, want none", w.store.Writes())
	}
}

func TestTheWriterMarksOnlyTheFailRecordedAtItsCommit(t *testing.T) {
	w := newWorld(t)
	var refused *Refusal
	if _, err := w.markFail(w.store, CheckLint, commitB, "tk-open"); !errors.As(err, &refused) ||
		!strings.Contains(err.Error(), "not at "+commitB) {
		t.Errorf("a commit the checkout is not at: %v, want a refusal", err)
	}
	if _, err := w.markFail(w.store, CheckTest, commitA, "tk-open"); !errors.As(err, &refused) ||
		!strings.Contains(err.Error(), "nothing is recorded for test") {
		t.Errorf("nothing recorded: %v, want a refusal", err)
	}
	if _, err := w.markFail(w.store, CheckBuild, commitA, "tk-open"); !errors.As(err, &refused) ||
		!strings.Contains(err.Error(), "notes no setup and build") {
		t.Errorf("a build with no note: %v, want a refusal", err)
	}
	note := map[string]any{"commit": commitA, "setup": "none", "build": "fail", "setup_command": "", "build_command": "make"}
	raw, _ := json.Marshal(note)
	w.mark("self_review_setup_build", string(raw))
	if _, err := w.markFail(w.store, CheckBuild, commitA, "tk-open"); err != nil {
		t.Fatalf("a build fail the note records: %v", err)
	}
	if m := w.written(t, CheckBuild); !sameJSON(m.Record, raw) {
		t.Errorf("the build mark's record = %s, want the note", m.Record)
	}
	w.store.UpdateErr = errors.New("the store refused the update")
	if _, err := w.markFail(w.store, CheckLint, commitA, "tk-open"); err == nil || errors.As(err, &refused) {
		t.Errorf("a write that does not land: %v, want an error that is no refusal", err)
	}
}

func mustJSON(t *testing.T, v any) json.RawMessage {
	t.Helper()
	raw, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return raw
}
