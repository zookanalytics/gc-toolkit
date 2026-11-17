package memory

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	gfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
)

// left is each note's fate: name:kept or name:gone.
func left(dir string, names ...string) string {
	var out []string
	for _, n := range names {
		if exists(filepath.Join(dir, n)) {
			out = append(out, n+":kept")
		} else {
			out = append(out, n+":gone")
		}
	}
	return strings.Join(out, " ")
}

// A wait ends once its pattern's fix reaches the default branch, as origin/HEAD
// names it: the unit leaves with its text kept and its pointers. A fix on its
// way, an open pattern, a changed note, a merge off the default branch and a
// checkout whose origin/HEAD names no branch keep theirs. A wait that ended
// with no fix makes its unit due, as old as the day it ended, with why.
func TestSettleEndsTheWaitsThatAreDone(t *testing.T) {
	c := newCity(t)
	m := c.rig("s", "tk")
	c.rig("o", "sl")
	c.rig("n", "nl")
	onMain, offMain := origin(t, c.checkout("s"), "main")
	onTrunk, offTrunk := origin(t, c.checkout("o"), "trunk")
	gitEnv(t)
	gitIn(t, c.checkout("n"), "init", "-q", "-b", "main")
	for _, n := range []string{"a", "b", "c", "d", "e", "f", "g", "i", "y", "w", "x", "m"} {
		write(t, filepath.Join(m, n+".md"), n+" lesson.\n")
	}
	write(t, filepath.Join(m, "hub-h.md"), "- (no file) An entry on P1.\n")
	write(t, filepath.Join(m, "MEMORY.md"), "# Memory Index\n\n- [A](a.md) — a\n- [H](hub-h.md) — h\n- [D](d.md) — d\n")
	s := c.store("s")
	for _, p := range []string{"tk-p1", "tk-p2", "tk-p3", "tk-p4", "tk-p5", "tk-p6", "tk-p7", "tk-p8"} {
		s.Put(openPattern(p))
	}
	c.store("o").Put(fake.Bead{ID: "sl-x", Status: "open"})
	c.store("o").Put(fake.Bead{ID: "sl-y", Status: "open"})
	c.store("n").Put(fake.Bead{ID: "nl-w", Status: "open"})
	ds := c.due()
	waits := map[string]string{"a": "tk-p1", "i": "tk-p1", "b": "tk-p2", "c": "tk-p3", "d": "tk-p4", "f": "tk-p5",
		"g": "tk-p6", "x": "tk-p7", "m": "tk-p8", "e": "sl-x", "y": "sl-y", "w": "nl-w"}
	var decisions []string
	for n, p := range waits {
		decisions = append(decisions, refOf(ds, n+".md")+" waits "+p)
	}
	decisions = append(decisions, entryRef(ds, "An entry on P1")+" waits tk-p1")
	if a := c.apply(decisions...); len(a.Failed) > 0 {
		t.Fatal(a.Failed)
	}
	write(t, filepath.Join(m, "i.md"), "i lesson, changed after it was judged.\n")

	s.Put(closedPattern("tk-p1", "proposal_bead", "tk-f1"))
	s.Put(merged("tk-f1", onMain, "main"))
	p2 := closedPattern("tk-p2")
	p2.Edges = []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "tk-f2"}}
	s.Put(p2)
	s.Put(merged("tk-f2", offMain, "integration/tk-l1"))
	s.Put(fake.Bead{ID: "tk-l1", Status: "open"})
	p3 := closedPattern("tk-p3")
	p3.ClosedAt = "2026-11-13T09:00:00Z"
	p3.CloseReason = `dismissed: the hold's window passed with no line matching '^\t- used' in C:\new`
	s.Put(p3)
	s.Put(closedPattern("tk-p5", "proposal_bead", "tk-f5"))
	s.Put(fake.Bead{ID: "tk-f5", Status: "blocked", Metadata: map[string]string{"merge_result": "pull_request_pending"}})
	s.Put(closedPattern("tk-p6", "proposal_bead", "tk-f6"))
	s.Put(fake.Bead{ID: "tk-f6", Status: "closed", Metadata: map[string]string{"merge_result": "pull_request", "task_kind": "prompt-update"}})
	s.Put(closedPattern("tk-p7", "proposal_bead", "tk-f7"))
	s.Put(merged("tk-f7", offMain, "main"))
	s.Put(closedPattern("tk-p8", "eng_bead", "tk-f8"))
	s.Put(merged("tk-f8", onMain, "main", "merge_result", "mr_merged"))
	c.store("o").Put(merged("sl-x", onTrunk, "trunk"))
	c.store("o").Put(merged("sl-y", offTrunk, "main"))
	c.store("n").Put(merged("nl-w", onMain, "main"))

	got := c.settle()
	if got.Left != 4 || got.Due != 2 {
		t.Errorf("left %d, due %d; want 4 removed with a fix landed and 2 due again", got.Left, got.Due)
	}
	if want := "a.md:gone b.md:kept c.md:kept d.md:kept e.md:gone f.md:kept g.md:kept i.md:kept y.md:kept " +
		"w.md:kept x.md:kept m.md:gone hub-h.md:gone"; left(m, "a.md", "b.md", "c.md", "d.md", "e.md", "f.md", "g.md",
		"i.md", "y.md", "w.md", "x.md", "m.md", "hub-h.md") != want {
		t.Errorf("left %q\nwant %q", left(m, "a.md", "b.md", "c.md", "d.md", "e.md", "f.md", "g.md", "i.md", "y.md",
			"w.md", "x.md", "m.md", "hub-h.md"), want)
	}
	n := c.checkout("n")
	if !said(got.Failed, "the origin/HEAD of "+n+" names no branch, so no merge there is taken as landed and each wait on one stays; set it with git -C '"+n+"' remote set-head origin --auto") {
		t.Errorf("failed %q; want the repair named", got.Failed)
	}
	if read(t, filepath.Join(c.state(m), "removed", "a.md@"+sum("a lesson.\n"))) != "a lesson.\n" {
		t.Error("a.md's text is not kept")
	}
	if idx := read(t, filepath.Join(m, "MEMORY.md")); idx != "# Memory Index\n\n- [D](d.md) — d\n" {
		t.Errorf("the index reads %q; want the pointers to a.md and hub-h.md gone", idx)
	}
	ds = c.due()
	if names(ds) != "c.md:date g.md:date i.md:changed" {
		t.Errorf("due %q", names(ds))
	}
	if ds[0].Created != "2026-11-13T00:00:00Z" ||
		ds[0].Prior != `waited on tk-p3, which closed with no fix landed: dismissed: the hold's window passed with no line matching '^\t- used' in C:\new` {
		t.Errorf("c.md = %+v; want as old as the day its pattern closed, saying why in the close reason's words, backslashes and all", ds[0])
	}
	if ds[1].Prior != "waited on tk-p6, which closed with no fix landed" {
		t.Errorf("g.md's prior %q", ds[1].Prior)
	}

	// A merge into an effort's branch lands with the effort's landing bead, and
	// a fix on its way lands once its merge reaches the default branch.
	s.Put(merged("tk-l1", onMain, "main"))
	s.Put(merged("tk-f5", onMain, "main"))
	c.settle()
	if got := left(m, "b.md", "f.md"); got != "b.md:gone f.md:gone" {
		t.Errorf("left %q once the landing bead and the fix merged", got)
	}
}

// A wait on a bead that is not a pattern ends with its bead: it leaves once the
// bead's merge lands, and is due when it closed with no merge or its store no
// longer holds it.
func TestAWaitOnAnotherBeadEndsWithIt(t *testing.T) {
	c := newCity(t)
	m := c.rig("r", "tk")
	onMain, _ := origin(t, c.checkout("r"), "main")
	s := c.store("r")
	for _, id := range []string{"tk-a", "tk-b", "tk-c"} {
		s.Put(fake.Bead{ID: id, Status: "open"})
	}
	for _, n := range []string{"a", "b", "c"} {
		write(t, filepath.Join(m, n+".md"), n+" lesson.\n")
	}
	ds := c.due()
	c.apply(refOf(ds, "a.md")+" waits tk-a", refOf(ds, "b.md")+" waits tk-b", refOf(ds, "c.md")+" waits tk-c")
	s = fake.New()
	c.stores[filepath.Join(c.checkout("r"), ".beads")] = s
	s.Put(merged("tk-a", onMain, "main"))
	s.Put(fake.Bead{ID: "tk-b", Status: "closed", ClosedAt: "2026-11-14T10:00:00Z", CloseReason: "not needed"})
	got := c.settle()
	if left(m, "a.md", "b.md", "c.md") != "a.md:gone b.md:kept c.md:kept" || got.Left != 1 || got.Due != 2 {
		t.Errorf("left %q, %d removed, %d due", left(m, "a.md", "b.md", "c.md"), got.Left, got.Due)
	}
	ds = c.due()
	if names(ds) != "c.md:date b.md:date" && names(ds) != "b.md:date c.md:date" {
		t.Errorf("due %q", names(ds))
	}
	for _, d := range ds {
		want := map[string]string{"b.md": "waited on tk-b, which closed with no merge: not needed",
			"c.md": "waited on tk-c, which is not in its store"}[filepath.Base(d.File)]
		if d.Prior != want {
			t.Errorf("%s prior %q, want %q", d.File, d.Prior, want)
		}
	}
}

// A pattern whose follow-ups were all declined, such as a prompt-update the
// operator vetoed, makes its note due at once, from the day the pattern closed,
// ahead of a note changed after that day, and writes nothing into the note.
func TestAWaitEndedWithNoFixMakesTheNoteDueFirst(t *testing.T) {
	c := newCity(t)
	m := c.rig("v", "tk")
	origin(t, c.checkout("v"), "main")
	s := c.store("v")
	s.Put(openPattern("tk-p7"))
	f := filepath.Join(m, "v.md")
	write(t, f, "---\nname: v\n---\nV lesson: do the vetoed thing.\n")
	c.apply(refOf(c.due(), "v.md") + " waits tk-p7")
	s.Put(closedPattern("tk-p7", "proposal_bead", "tk-f7"))
	s.Put(fake.Bead{ID: "tk-f7", Status: "closed", Metadata: map[string]string{"task_kind": "prompt-update",
		"merge_result": "pull_request", "pr_url": "https://example.test/pull/7"}})
	write(t, filepath.Join(m, "later.md"), "Later lesson.\n", day("2026-11-14"))
	before := read(t, f)
	c.settle()
	ds := c.due()
	if names(ds) != "v.md:date later.md:new" || ds[0].Created != "2026-11-14T00:00:00Z" {
		t.Errorf("due %q, first %+v", names(ds), ds[0])
	}
	if read(t, f) != before {
		t.Error("the settle wrote into the note")
	}
}

// A note that waits records a use through a save, and still leaves, use line
// and all, once its fix lands.
func TestAWaitingNoteThatRecordsAUseLeavesOnceItsFixLands(t *testing.T) {
	c := newCity(t)
	m := c.rig("s", "tk")
	onMain, _ := origin(t, c.checkout("s"), "main")
	s := c.store("s")
	s.Put(openPattern("tk-p1"))
	f := filepath.Join(m, "wait.md")
	write(t, f, stamped("wait", "Wait lesson."))
	c.apply(refOf(c.due(), "wait.md") + " waits tk-p1")
	save(t, f, "2026-11-16T09:00:00.000Z", "used 2026-11-16: took the wait path")
	if len(c.due()) != 0 {
		t.Fatal("a use recorded through a save brought the waiting note due")
	}
	before := read(t, f)
	s.Put(closedPattern("tk-p1", "proposal_bead", "tk-f1"))
	s.Put(merged("tk-f1", onMain, "main"))
	if got := c.settle(); got.Left != 1 || exists(f) {
		t.Fatalf("left %d, the note is there: %v", got.Left, exists(f))
	}
	if read(t, filepath.Join(c.state(m), "removed", "wait.md@"+sum(before))) != before {
		t.Error("its text, use line and all, is not kept")
	}
}

// A pattern whose follow-ups did not read keeps its notes until they do.
func TestAPatternWhoseFollowUpsDidNotReadKeepsItsNotes(t *testing.T) {
	c := newCity(t)
	m := c.rig("s", "tk")
	onMain, _ := origin(t, c.checkout("s"), "main")
	s := c.store("s")
	s.Put(openPattern("tk-p1"))
	write(t, filepath.Join(m, "z.md"), "z lesson.\n")
	c.apply(refOf(c.due(), "z.md") + " waits tk-p1")
	s.Put(closedPattern("tk-p1", "proposal_bead", "tk-f1"))
	s.Put(merged("tk-f1", onMain, "main"))
	finds := 0
	s.OnFind = func(gcbd.Query) {
		if finds++; finds == 2 {
			s.FindErr = errors.New("the store did not answer")
		}
	}
	got := c.settle()
	if !said(got.Failed, "did not answer for the follow-ups of tk-p1") || !exists(filepath.Join(m, "z.md")) {
		t.Errorf("failed %q; want the note kept and why", got.Failed)
	}
	s.OnFind, s.FindErr = nil, nil
	c.settle()
	if exists(filepath.Join(m, "z.md")) {
		t.Error("the note stayed once the follow-ups read")
	}
}

// Nothing leaves while its text cannot be kept: the decision or the settle
// fails, the unit and its row stay, and it leaves once the text can be kept.
func TestNothingLeavesWhileItsTextCannotBeKept(t *testing.T) {
	c := newCity(t)
	m := c.rig("k", "tk")
	onMain, _ := origin(t, c.checkout("k"), "main")
	s := c.store("k")
	s.Put(openPattern("tk-p1"))
	write(t, filepath.Join(m, "k.md"), "k lesson.\n")
	write(t, filepath.Join(m, "hub-k.md"), "- (no file) An entry to drop.\n- (no file) An entry that waits.\n")
	ds := c.due()
	rd := entryRef(ds, "to drop")
	c.apply(rd+" next 2026-11-20", entryRef(ds, "that waits")+" waits tk-p1", refOf(ds, "k.md")+" waits tk-p1")
	if err := os.WriteFile(filepath.Join(c.state(m), removedDir), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	c.now = day("2026-11-21")
	a := c.apply(rd + " drop")
	if !said(a.Failed, "could not remove "+rd) || said(a.Said, "kept at") ||
		!strings.Contains(read(t, filepath.Join(m, "hub-k.md")), "An entry to drop.") ||
		!strings.Contains(read(t, filepath.Join(c.state(m), listFile)), "2026-11-20") {
		t.Errorf("said %q, failed %q; want the entry and its row to stay", a.Said, a.Failed)
	}
	s.Put(closedPattern("tk-p1", "proposal_bead", "tk-f1"))
	s.Put(merged("tk-f1", onMain, "main"))
	got := c.settle()
	if got.Left != 0 || len(got.Failed) == 0 || !exists(filepath.Join(m, "k.md")) ||
		!strings.Contains(read(t, filepath.Join(m, "hub-k.md")), "An entry that waits.") {
		t.Errorf("left %d, failed %q; want nothing removed", got.Left, got.Failed)
	}
	if err := os.Remove(filepath.Join(c.state(m), removedDir)); err != nil {
		t.Fatal(err)
	}
	if got := c.settle(); got.Left != 2 || len(got.Failed) != 0 || exists(filepath.Join(m, "k.md")) ||
		strings.Contains(read(t, filepath.Join(m, "hub-k.md")), "An entry that waits.") {
		t.Errorf("left %d, failed %q; want both to leave once their text could be kept", got.Left, got.Failed)
	}
}

// A wait that ends keeps a note an agent edits once its text is kept, before
// it goes, and the note is due as changed, after what it waited on.
func TestASettleKeepsANoteEditedWhileItIsRemoved(t *testing.T) {
	c := newCity(t)
	m := c.rig("r", "tk")
	onMain, _ := origin(t, c.checkout("r"), "main")
	s := c.store("r")
	s.Put(openPattern("tk-p1"))
	f := filepath.Join(m, "s.md")
	write(t, f, "s lesson.\n")
	c.apply(refOf(c.due(), "s.md") + " waits tk-p1")
	s.Put(closedPattern("tk-p1", "proposal_bead", "tk-f1"))
	s.Put(merged("tk-f1", onMain, "main"))
	landAt(t, "move", func(file string) { appendTo(t, file, "An edit made while it was being removed.\n") })
	if got := c.settle(); got.Left != 0 || !exists(f) {
		t.Fatalf("left %d; want the edited note kept", got.Left)
	}
	if kept, _ := filepath.Glob(filepath.Join(c.state(m), "removed", "s.md@*")); len(kept) != 0 {
		t.Errorf("text kept for a note that stayed: %v", kept)
	}
	for _, d := range c.due() {
		if d.Why != DueChanged || d.Prior != "waited on tk-p1" {
			t.Errorf("due %+v; want changed, after waiting on tk-p1", d)
		}
	}
}

// A row whose unit is gone from its directory leaves the list.
func TestARowWhoseUnitIsGoneLeavesTheList(t *testing.T) {
	c := newCity(t)
	m := c.rig("r", "tk")
	write(t, filepath.Join(m, "n.md"), "n lesson.\n")
	c.apply(refOf(c.due(), "n.md") + " next 2026-12-01")
	if err := os.Remove(filepath.Join(m, "n.md")); err != nil {
		t.Fatal(err)
	}
	c.settle()
	if strings.Contains(read(t, filepath.Join(c.state(m), listFile)), "n.md") {
		t.Error("the row of a gone note stayed")
	}
}

// Settle files one finding that names each place it cannot learn, settles the
// rest, and clears the finding once every place is learned.
func TestSettleFilesAFindingForAPlaceItCannotLearn(t *testing.T) {
	c := newCity(t)
	m := c.rig("ok", "tk")
	c.rig("none", "a")
	c.claude.Dirs[c.checkout("none")] = ""
	write(t, filepath.Join(m, "n.md"), "n lesson.\n")
	got := c.settle()
	if len(got.Places.Unknown) != 1 || got.Places.Unknown[0].Name != "none" || !said(got.Said, "ok: "+m+", 1 notes and 0 entries") {
		t.Errorf("unknown %+v, said %q", got.Places.Unknown, got.Said)
	}
	calls := c.rt.Scripts()
	if len(calls) != 1 || calls[0].Name != "patrol-finding.sh" {
		t.Fatalf("scripts %+v; want one finding", calls)
	}
	args := strings.Join(calls[0].Args, "\x00")
	for _, want := range []string{"--scope\x00memory-intake", "--key\x00memory-intake.places",
		"--title\x00Memory intake cannot learn where Claude Code keeps the memory of none",
		"- none: Claude Code 2.1.326 named no memory directory", "--type\x00bug"} {
		if !strings.Contains(args, want) {
			t.Errorf("the finding's args %q lack %q", calls[0].Args, want)
		}
	}
	c.claude.Dirs[c.checkout("none")] = m
	c.settle()
	if calls := c.rt.Scripts(); len(calls) != 2 || !strings.Contains(strings.Join(calls[1].Args, " "), "--key memory-intake.places --cleared") {
		t.Errorf("scripts %+v; want the finding cleared", calls)
	}
	c.rt.OnScript = func(gfake.Call) gascity.Result { return gascity.Result{Code: 1, Output: "could not file"} }
	if got := c.settle(); !said(got.Failed, "the finding memory-intake.places was not cleared: exit 1: could not file") {
		t.Errorf("failed %q; want the clear's failure said", got.Failed)
	}
}
