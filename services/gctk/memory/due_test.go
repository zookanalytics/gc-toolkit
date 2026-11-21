package memory

import (
	"maps"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// flow is a rig whose memory holds three notes, a collection note with a
// pointer and an entry, and an index, with the pattern tk-p1 open.
func flow(t *testing.T) (*city, string) {
	t.Helper()
	c := newCity(t)
	m := c.rig("main", "tk")
	c.store("main").Put(openPattern("tk-p1"))
	write(t, filepath.Join(m, "old.md"), "Old lesson.\n", day("2026-10-01"))
	write(t, filepath.Join(m, "mid.md"), "Mid lesson.\n", day("2026-11-05"))
	write(t, filepath.Join(m, "new.md"), "New lesson.\n", day("2026-11-10"))
	write(t, filepath.Join(m, "hub-a.md"), "Intro.\n\n- [[new]] (New): n\n- (no file) A fact of its own.\n  - its detail\n", day("2026-11-08"))
	write(t, filepath.Join(m, "MEMORY.md"), "# Memory Index\n\n- [Old](old.md) — o · [New](new.md) — n · [Mid](mid.md) — m\n- [New](new.md) — n\n- [Hub](hub-a.md) — topics\n")
	return c, m
}

// A note and an entry with text of its own are units, and a pointer is not.
// Every unit is due while the list holds none, oldest first, as old as its
// file's last change, an entry carrying its text.
func TestDueListsEachUnitOldestFirst(t *testing.T) {
	c, m := flow(t)
	ds := c.due()
	if got := names(ds); got != "old.md:new mid.md:new hub-a.md:new new.md:new" {
		t.Fatalf("due %q", got)
	}
	if ds[0].Created != "2026-10-01T12:00:00Z" || ds[0].Kind != Note || ds[0].Dir != m || ds[0].File != filepath.Join(m, "old.md") {
		t.Errorf("first = %+v", ds[0])
	}
	if ds[2].Kind != Entry || ds[2].Text != "- (no file) A fact of its own.\n  - its detail\n" {
		t.Errorf("the entry = %+v", ds[2])
	}
	want := sum(m)[:16] + "/old.md@" + sum("Old lesson.\n")[:16]
	if ds[0].Ref != want {
		t.Errorf("ref %q, want %q", ds[0].Ref, want)
	}
}

// Each decision is recorded: a date, a wait and a drop, which keeps the note's
// text, removes it and takes its pointers out of the index and the collection
// notes, the others beside them kept. Nothing judged is due.
func TestApplyRecordsEachDecision(t *testing.T) {
	c, m := flow(t)
	ds := c.due()
	ro, rm, rn, re := refOf(ds, "old.md"), refOf(ds, "mid.md"), refOf(ds, "new.md"), entryRef(ds, "A fact")
	a := c.apply(ro+" next 2026-11-20", rm+" waits tk-p1", re+" waits tk-p1", rn+" drop")
	if len(a.Failed) > 0 {
		t.Fatalf("failed: %v", a.Failed)
	}
	for _, want := range []string{"recorded " + ro + ": due again on 2026-11-20", "recorded " + rm + ": waits on tk-p1",
		"recorded " + re + ": waits on tk-p1", "removed " + rn + ", its text kept at "} {
		if !said(a.Said, want) {
			t.Errorf("said %q, want %q", a.Said, want)
		}
	}
	kept := filepath.Join(c.state(m), "removed", "new.md@"+sum("New lesson.\n"))
	if read(t, kept) != "New lesson.\n" || exists(filepath.Join(m, "new.md")) {
		t.Errorf("new.md is not removed with its text kept at %s", kept)
	}
	if got := read(t, filepath.Join(m, "MEMORY.md")); got != "# Memory Index\n\n- [Old](old.md) — o · [Mid](mid.md) — m\n- [Hub](hub-a.md) — topics\n" {
		t.Errorf("the index reads %q", got)
	}
	if got := read(t, filepath.Join(m, "hub-a.md")); strings.Contains(got, "[[new]]") || !strings.Contains(got, "A fact of its own") {
		t.Errorf("the collection note reads %q", got)
	}
	if ds := c.due(); len(ds) != 0 {
		t.Errorf("due once judged: %s", names(ds))
	}
}

// A note kept until a day is not due before it, and on it is as old as that
// day, behind the notes due before it.
func TestANoteKeptUntilADayWaitsForIt(t *testing.T) {
	c, m := flow(t)
	ds := c.due()
	c.apply(refOf(ds, "old.md")+" next 2026-11-20", refOf(ds, "mid.md")+" drop", refOf(ds, "new.md")+" drop",
		entryRef(ds, "A fact")+" drop")
	write(t, filepath.Join(m, "fresh.md"), "Fresh lesson.\n", day("2026-11-12"))
	write(t, filepath.Join(m, "later.md"), "Later lesson.\n", time.Date(2026, 11, 21, 0, 0, 0, 0, time.UTC))
	if got := names(c.due()); got != "fresh.md:new later.md:new" {
		t.Errorf("before its day: %q", got)
	}
	c.now = day("2026-11-21")
	ds = c.due()
	if got := names(ds); got != "fresh.md:new old.md:date later.md:new" {
		t.Errorf("on its day: %q", got)
	}
	if ds[1].Created != "2026-11-20T00:00:00Z" || ds[1].Prior != "kept until 2026-11-20" {
		t.Errorf("the dated note = %+v", ds[1])
	}
}

// A note changed since it was judged is due again with what it waited on, and
// a decision on a note changed since it was listed is refused, which is no
// failure, and leaves it in place and due.
func TestANoteChangedSinceItWasJudgedIsDueAgain(t *testing.T) {
	c, m := flow(t)
	ds := c.due()
	c.apply(refOf(ds, "mid.md")+" waits tk-p1", refOf(ds, "old.md")+" waits tk-p1")
	write(t, filepath.Join(m, "mid.md"), "Mid lesson, edited.\n")
	for _, d := range c.due() {
		if filepath.Base(d.File) == "mid.md" && (d.Why != DueChanged || d.Prior != "waited on tk-p1") {
			t.Errorf("mid.md = %+v; want changed, after waiting on tk-p1", d)
		}
	}
	r := refOf(c.due(), "new.md")
	write(t, filepath.Join(m, "new.md"), "New lesson, edited after the listing.\n")
	a := c.apply(r + " drop")
	if len(a.Failed) > 0 || !said(a.Said, "refused "+r) {
		t.Errorf("said %q, failed %q; want a refusal", a.Said, a.Failed)
	}
	if read(t, filepath.Join(m, "new.md")) != "New lesson, edited after the listing.\n" || dueOf(c.due(), "new.md") != DueNew {
		t.Error("the refused note did not stay in place and due")
	}
}

// ask-use adds the line that asks for one dated line a day the note is used. A
// use line does not make the note due, and any other change does.
func TestAskUseAddsTheRequestAndAUseLeavesTheNoteAlone(t *testing.T) {
	c := newCity(t)
	m := c.rig("r", "tk")
	f := filepath.Join(m, "fresh.md")
	write(t, f, "Fresh lesson.\n")
	r := refOf(c.due(), "fresh.md")
	a := c.apply(r + " next 2026-12-01 ask-use")
	if !said(a.Said, "recorded "+r+": due again on 2026-12-01, with a request to record the days it is used, one line a day") {
		t.Errorf("said %q", a.Said)
	}
	if got := lines(read(t, f)); got[len(got)-1] != useLine {
		t.Errorf("the note ends %q, want the request", got[len(got)-1])
	}
	appendTo(t, f, "used 2026-11-16: chose the lock path\n")
	if dueOf(c.due(), "fresh.md") != "" {
		t.Error("a use line made the note due")
	}
	appendTo(t, f, "A new line.\n")
	if dueOf(c.due(), "fresh.md") != DueChanged {
		t.Error("a change other than a use line did not make the note due")
	}
}

// A use recorded through Claude Code's save, which sets the note's modified
// stamp, leaves its date alone, and it comes due on that date. A change to its
// front matter alone does not bring it due either.
func TestUsesRecordedThroughSavesLeaveTheDateAlone(t *testing.T) {
	c := newCity(t)
	m := c.rig("r", "tk")
	f := filepath.Join(m, "steer.md")
	write(t, f, stamped("steer", "Take the lock path when two runs share a directory."))
	c.apply(refOf(c.due(), "steer.md") + " next 2026-12-01 ask-use")
	if got := lines(read(t, f)); got[len(got)-1] != useLine {
		t.Errorf("the stamped note ends %q", got[len(got)-1])
	}
	save(t, f, "2026-11-16T09:00:00.000Z", "used 2026-11-16: chose the lock path")
	save(t, f, "2026-11-17T10:30:00.000Z", "used 2026-11-17: took the lock path again")
	if !strings.Contains(read(t, f), "  modified: 2026-11-17T10:30:00.000Z\n") || dueOf(c.due(), "steer.md") != "" {
		t.Error("a use recorded through a save made the note due")
	}
	c.now = day("2026-12-02")
	if dueOf(c.due(), "steer.md") != DueDate {
		t.Error("the note did not come due on its date")
	}
	c.now = noon
	for _, n := range []string{"desc", "kind"} {
		write(t, filepath.Join(m, n+".md"), stamped(n, "The "+n+" lesson."))
		c.apply(refOf(c.due(), n+".md") + " next 2026-12-01")
	}
	edit := func(file, from, to string) {
		write(t, file, strings.Replace(read(t, file), from, to, 1))
	}
	edit(filepath.Join(m, "desc.md"), `description: "desc: a lesson"`, `description: "desc: a lesson its writer reworded"`)
	edit(filepath.Join(m, "kind.md"), "  type: feedback", "  type: project")
	if ds := c.due(); dueOf(ds, "desc.md") != "" || dueOf(ds, "kind.md") != "" {
		t.Errorf("a change to front matter alone made a note due: %s", names(ds))
	}
}

// A note's first save writes its front matter again, as YAML under metadata
// with one blank line before the body, and leaves its date alone.
func TestAFirstSaveLeavesTheDateAlone(t *testing.T) {
	c := newCity(t)
	m := c.rig("r", "tk")
	first := filepath.Join(m, "first.md")
	write(t, first, "---\nname: First Note\ntype: feedback\ndescription: It's the first lesson, with a comma\n---\nKeep the first path.\n")
	c.apply(refOf(c.due(), "first.md") + " next 2026-12-01 ask-use")
	write(t, first, "---\nname: first-note\ndescription: \"It's the first lesson, with a comma\"\nmetadata:\n  node_type: memory\n"+
		"  type: feedback\n  originSessionId: b089ac48-23c5-4229-8129-5ed4f2560a4a\n  modified: 2026-11-16T09:00:00.000Z\n---\n\n"+
		"Keep the first path.\n"+useLine+"\nused 2026-11-16: kept the first path\n")
	if dueOf(c.due(), "first.md") != "" {
		t.Error("the first save of a note with no stamp made it due")
	}
	c.now = day("2026-12-02")
	if dueOf(c.due(), "first.md") != DueDate {
		t.Error("it did not come due on its date")
	}
}

// A decision that does not ask again takes the request out and keeps the use
// lines; ask-use adds it back once; a wait takes it out.
func TestADecisionThatDoesNotAskAgainTakesTheRequestOut(t *testing.T) {
	c := newCity(t)
	m := c.rig("r", "tk")
	c.store("r").Put(openPattern("tk-p1"))
	f := filepath.Join(m, "steer.md")
	write(t, f, stamped("steer", "Take the lock path."))
	c.apply(refOf(c.due(), "steer.md") + " next 2026-12-01 ask-use")
	save(t, f, "2026-11-16T09:00:00.000Z", "used 2026-11-16: chose the lock path")
	save(t, f, "2026-11-17T09:00:00.000Z", "used 2026-11-17: chose it again")
	c.now = day("2026-12-02")
	r := refOf(c.due(), "steer.md")
	a := c.apply(r + " next 2026-12-15")
	if !said(a.Said, "recorded "+r+": due again on 2026-12-15; its request to record the days it is used taken out") {
		t.Errorf("said %q", a.Said)
	}
	if text := read(t, f); strings.Contains(text, useMark) || strings.Count(text, "\nused ") != 2 {
		t.Errorf("the note reads %q; want no request and both use lines", text)
	}
	c.now = day("2026-12-03")
	if dueOf(c.due(), "steer.md") != "" {
		t.Error("the note is due the day after")
	}
	c.now = day("2026-12-16")
	for range 2 {
		c.apply(refOf(c.due(), "steer.md") + " next 2027-01-15 ask-use")
	}
	if n := strings.Count(read(t, f), useMark); n != 1 {
		t.Errorf("ask-use twice left %d requests, want 1", n)
	}
	c.now = day("2027-01-16")
	a = c.apply(refOf(c.due(), "steer.md") + " waits tk-p1")
	if !said(a.Said, "waits on tk-p1; its request to record the days it is used taken out") || strings.Contains(read(t, f), useMark) {
		t.Errorf("said %q; want the wait to take the request out", a.Said)
	}
	c.now = day("2027-01-17")
	if dueOf(c.due(), "steer.md") != "" {
		t.Error("the waiting note is due")
	}
}

// A note that quotes the mark inside a line still gains the request, and a
// decision without ask-use takes out only the line that asks.
func TestANoteThatQuotesTheMarkKeepsItsLine(t *testing.T) {
	c := newCity(t)
	m := c.rig("r", "tk")
	f := filepath.Join(m, "quote.md")
	quote := "The intake starts the line it adds with `" + useMark + "`.\n"
	write(t, f, quote)
	c.apply(refOf(c.due(), "quote.md") + " next 2026-12-01 ask-use")
	if got := lines(read(t, f)); got[len(got)-1] != useLine {
		t.Errorf("the note ends %q", got[len(got)-1])
	}
	c.now = day("2026-12-02")
	a := c.apply(refOf(c.due(), "quote.md") + " next 2026-12-15")
	if !said(a.Said, "taken out") || read(t, f) != quote {
		t.Errorf("said %q, the note reads %q", a.Said, read(t, f))
	}
}

// Apply refuses a line that is no decision, and a decision it cannot carry
// out, and removes nothing for them.
func TestApplyRefusesWhatIsNoDecision(t *testing.T) {
	c, m := flow(t)
	ds := c.due()
	ro, re := refOf(ds, "old.md"), entryRef(ds, "A fact")
	a := c.apply(re+" next 2026-12-01 ask-use", "nonsense", ro+" next 2026-11-15", ro+" next 2026-02-30",
		ro+" waits zz-1", ro+" waits tk-nope", "0000000000000000/old.md@0000000000000000 drop", ro+" drop extra",
		ro+" waits", "# a comment", "")
	for _, want := range []string{"ask-use takes a whole note", "not a decision (" + decisionForm + "): nonsense",
		"not a decision (" + decisionForm + "): " + ro + " next 2026-11-15", "): " + ro + " next 2026-02-30",
		"no store of the city carries zz-1", "tk-nope is not in its store",
		"no memory directory the run reads now has that key", "): " + ro + " drop extra", "): " + ro + " waits"} {
		if !said(a.Failed, want) {
			t.Errorf("failed %q, want %q", a.Failed, want)
		}
	}
	if len(a.Failed) != 9 || !exists(filepath.Join(m, "old.md")) {
		t.Errorf("failed %d lines, want 9, and old.md kept", len(a.Failed))
	}
}

// An entry dropped leaves its collection note, which goes with its last entry,
// each text kept, and the index's pointer to it goes too.
func TestAnEntryDroppedTakesItsCollectionNoteWithTheLast(t *testing.T) {
	c, m := flow(t)
	ds := c.due()
	c.apply(refOf(ds, "new.md") + " drop")
	re := entryRef(c.due(), "A fact")
	a := c.apply(re + " drop")
	if !said(a.Said, "removed "+re) || !said(a.Said, "removed hub-a.md, which has no entries left") {
		t.Errorf("said %q", a.Said)
	}
	entry := "- (no file) A fact of its own.\n  - its detail\n"
	if read(t, filepath.Join(c.state(m), "removed", "hub-a.md@"+sum(entry))) != entry {
		t.Error("the entry's text is not kept")
	}
	kept, _ := filepath.Glob(filepath.Join(c.state(m), "removed", "hub-a.md@*"))
	if len(kept) != 2 || exists(filepath.Join(m, "hub-a.md")) {
		t.Errorf("kept %v; want the entry's and the collection note's text, and the note gone", kept)
	}
	if strings.Contains(read(t, filepath.Join(m, "MEMORY.md")), "(hub-a.md)") {
		t.Error("the index still points at the collection note")
	}
}

// A note whose name holds spaces is judged by the ref due gives it.
func TestANoteWhoseNameHoldsSpaces(t *testing.T) {
	c := newCity(t)
	m := c.rig("sp", "tk")
	c.store("sp").Put(openPattern("tk-p1"))
	write(t, filepath.Join(m, "my lesson.md"), "A spaced lesson.\n")
	write(t, filepath.Join(m, "two  spaces.md"), "Another, spaced twice.\n")
	ds := c.due()
	r1, r2 := refOf(ds, "my lesson.md"), refOf(ds, "two  spaces.md")
	if !strings.Contains(r1, "/my lesson.md@") {
		t.Errorf("ref %q", r1)
	}
	a := c.apply(r1+" waits tk-p1", r2+" drop")
	if len(a.Failed) > 0 || !said(a.Said, "recorded "+r1+": waits on tk-p1") || !said(a.Said, "removed "+r2) {
		t.Errorf("said %q, failed %q", a.Said, a.Failed)
	}
	if !exists(filepath.Join(m, "my lesson.md")) || exists(filepath.Join(m, "two  spaces.md")) || len(c.due()) != 0 {
		t.Error("the decisions did not land on the notes they named")
	}
}

// A directory that cannot be listed, or a note in it that cannot be read,
// keeps every judgment and its list as it was.
func TestADirectoryThatDoesNotReadKeepsItsJudgments(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root reads a directory its mode refuses")
	}
	c := newCity(t)
	u := c.rig("u", "tk")
	c.store("u").Put(openPattern("tk-p1"))
	write(t, filepath.Join(u, "u.md"), "u lesson.\n")
	write(t, filepath.Join(u, "w.md"), "w lesson.\n")
	ds := c.due()
	c.apply(refOf(ds, "u.md")+" waits tk-p1", refOf(ds, "w.md")+" next 2026-12-01")
	list := filepath.Join(c.state(u), listFile)
	before := read(t, list)
	if err := os.Chmod(u, 0o300); err != nil {
		t.Fatal(err)
	}
	s := c.settle()
	d, _ := c.in.Due()
	if err := os.Chmod(u, 0o700); err != nil {
		t.Fatal(err)
	}
	if !said(s.Failed, "cannot list "+u) || !said(d.Unread, "cannot list "+u) || read(t, list) != before {
		t.Errorf("settle failed %q, due unread %q; want both to say so and the list unchanged", s.Failed, d.Unread)
	}
	if len(c.due()) != 0 {
		t.Error("the judgments did not hold once it listed")
	}
	if err := os.Chmod(filepath.Join(u, "w.md"), 0); err != nil {
		t.Fatal(err)
	}
	s = c.settle()
	if err := os.Chmod(filepath.Join(u, "w.md"), 0o644); err != nil {
		t.Fatal(err)
	}
	if !said(s.Failed, "cannot read every note in "+u) || read(t, list) != before {
		t.Errorf("settle failed %q; want an unread note to stop it, the list unchanged", s.Failed)
	}
}

// Directories whose real paths a character conversion would merge keep lists
// of their own, keyed by the SHA-256 of each real path, with that path beside.
func TestDirectoriesThatConvertAlikeKeepTheirOwnLists(t *testing.T) {
	c := newCity(t)
	var dirs []string
	for i, p := range []string{"x/a.b", "x/a-b", "x-a/b"} {
		name := []string{"k1", "k2", "k3"}[i]
		c.rig(name, name)
		d := filepath.Join(c.root, p)
		write(t, filepath.Join(d, "same.md"), "The same lesson.\n")
		c.claude.Dirs[c.checkout(name)] = d
		dirs = append(dirs, d)
	}
	c.settle()
	for _, d := range dirs {
		if got := read(t, filepath.Join(c.state(d), pathFile)); got != d+"\n" {
			t.Errorf("the state of %s names %q", d, got)
		}
	}
	ds := c.due()
	if len(ds) != 3 || ds[0].Ref == ds[1].Ref || ds[1].Ref == ds[2].Ref || ds[0].Ref == ds[2].Ref {
		t.Fatalf("due %+v; want three refs of their own", ds)
	}
	var r string
	for _, d := range ds {
		if d.Dir == dirs[0] {
			r = d.Ref
		}
	}
	if a := c.apply(r + " drop"); len(a.Failed) > 0 {
		t.Fatal(a.Failed)
	}
	if exists(filepath.Join(dirs[0], "same.md")) || !exists(filepath.Join(dirs[1], "same.md")) ||
		!exists(filepath.Join(dirs[2], "same.md")) || len(c.due()) != 2 {
		t.Error("the drop reached a directory it did not name")
	}
}

// An item with lines under a blank line is one entry, though it opens with a
// link to a gone note, and it leaves whole with its collection note.
func TestAnItemWithLinesUnderABlankLineIsAnEntry(t *testing.T) {
	c := newCity(t)
	m := c.rig("b", "tk")
	entry := "- [Lesson](gone.md) — the lesson\n\n  What the lesson holds, under a blank line.\n"
	write(t, filepath.Join(m, "hub-b.md"), entry)
	ds := c.due()
	if len(ds) != 1 || ds[0].Text != entry {
		t.Fatalf("due %+v; want the whole item as one entry", ds)
	}
	a := c.apply(ds[0].Ref + " drop")
	if !said(a.Said, "removed hub-b.md, which has no entries left") ||
		read(t, filepath.Join(c.state(m), "removed", "hub-b.md@"+sum(entry))) != entry {
		t.Errorf("said %q; want the entry and its note gone, its text kept whole", a.Said)
	}
}

// A drop takes out a chain of collection notes that held only pointers on to
// the note, however long, and the index's pointer into the chain.
func TestADropTakesOutAChainOfCollectionNotes(t *testing.T) {
	c := newCity(t)
	m := c.rig("r", "tk")
	write(t, filepath.Join(m, indexName), "- [A](hub-a.md) — the chain\n")
	for hub, next := range map[string]string{"a": "hub-b.md", "b": "hub-c.md", "c": "hub-d.md", "d": "gone.md"} {
		write(t, filepath.Join(m, "hub-"+hub+".md"), "- [Next]("+next+") — the next\n")
	}
	write(t, filepath.Join(m, "gone.md"), "Gone lesson.\n")
	if a := c.apply(refOf(c.due(), "gone.md") + " drop"); len(a.Failed) > 0 {
		t.Fatal(a.Failed)
	}
	for _, hub := range []string{"a", "b", "c", "d"} {
		if exists(filepath.Join(m, "hub-"+hub+".md")) {
			t.Errorf("hub-%s.md stays", hub)
		}
	}
	if got := read(t, filepath.Join(m, indexName)); got != "" {
		t.Errorf("the index reads %q; want its pointer into the chain gone", got)
	}
}

// A pointer whose destination is in angle brackets, or escapes its spaces,
// names a note whose name holds spaces, and goes with that note.
func TestADropTakesOutAPointerToANameWithSpaces(t *testing.T) {
	c := newCity(t)
	m := c.rig("r", "tk")
	write(t, filepath.Join(m, indexName), "- [Lesson](<my lesson.md>) — the lesson\n"+
		"- [Titled](<my lesson.md> \"A title\") — again\n- [Escaped](my%20lesson.md) — again\n"+
		"- [Other](other.md) — another\n")
	write(t, filepath.Join(m, "my lesson.md"), "My lesson.\n")
	write(t, filepath.Join(m, "other.md"), "Other lesson.\n")
	if a := c.apply(refOf(c.due(), "my lesson.md") + " drop"); len(a.Failed) > 0 || exists(filepath.Join(m, "my lesson.md")) {
		t.Fatalf("failed %q; want the note gone", a.Failed)
	}
	if got := read(t, filepath.Join(m, indexName)); got != "- [Other](other.md) — another\n" {
		t.Errorf("the index reads %q; want only the pointer to the other note", got)
	}
}

// A drop is refused when the note changes after its text is kept, before it
// goes, and the text kept for it is taken back.
func TestANoteEditedWhileItIsRemovedStays(t *testing.T) {
	c := newCity(t)
	m := c.rig("r", "tk")
	f := filepath.Join(m, "d.md")
	write(t, f, "d lesson.\n")
	r := refOf(c.due(), "d.md")
	landAt(t, "move", func(file string) { appendTo(t, file, "An edit made while it was being removed.\n") })
	a := c.apply(r + " drop")
	if !said(a.Said, "refused "+r) || !strings.Contains(read(t, f), "An edit made") || dueOf(c.due(), "d.md") != DueNew {
		t.Errorf("said %q; want the note to stay with the edit, due", a.Said)
	}
	if kept, _ := filepath.Glob(filepath.Join(c.state(m), "removed", "d.md@*")); len(kept) != 0 {
		t.Errorf("text kept for a note that stayed: %v", kept)
	}
}

// A note an agent saves under a dropped note's name while the drop removes it
// keeps the pointers to that name, the collection note that holds them and
// the index's pointer to that collection note, and is due as new.
func TestADropKeepsThePointersToANoteSavedUnderItsName(t *testing.T) {
	c := newCity(t)
	m := c.rig("r", "tk")
	n, hub, index := filepath.Join(m, "n.md"), filepath.Join(m, "hub-a.md"), filepath.Join(m, indexName)
	write(t, index, "- [Hub](hub-a.md) — topics\n")
	write(t, hub, "- [N](n.md) — the lesson\n")
	write(t, n, "Old lesson.\n")
	r := refOf(c.due(), "n.md")
	landOn(t, "check", n, func() { saveByRename(t, n, "New lesson.\n") })
	a := c.apply(r + " drop")
	if len(a.Failed) > 0 || !said(a.Said, "removed "+r) {
		t.Fatalf("said %q, failed %q; want the judged text removed", a.Said, a.Failed)
	}
	if got := read(t, n); got != "New lesson.\n" {
		t.Errorf("n.md reads %q; want the new save", got)
	}
	if !exists(hub) || read(t, hub) != "- [N](n.md) — the lesson\n" || read(t, index) != "- [Hub](hub-a.md) — topics\n" {
		t.Error("the pointers to the new save, or to the collection note that holds them, were taken out")
	}
	if dueOf(c.due(), "n.md") != DueNew {
		t.Error("the new save is not due as new")
	}
}

// A note an agent saves under a dropped note's name while its pointer is taken
// out keeps the pointer.
func TestADropKeepsAPointerWhoseNoteIsSavedWhileItGoes(t *testing.T) {
	c := newCity(t)
	m := c.rig("r", "tk")
	n, index := filepath.Join(m, "n.md"), filepath.Join(m, indexName)
	write(t, index, "- [N](n.md) — the lesson\n- [O](o.md) — another\n")
	write(t, n, "Old lesson.\n")
	write(t, filepath.Join(m, "o.md"), "Other lesson.\n")
	r := refOf(c.due(), "n.md")
	landOn(t, "check", index, func() { saveByRename(t, n, "New lesson.\n") })
	if a := c.apply(r + " drop"); len(a.Failed) > 0 {
		t.Fatal(a.Failed)
	}
	if got := read(t, index); read(t, n) != "New lesson.\n" || got != "- [N](n.md) — the lesson\n- [O](o.md) — another\n" {
		t.Errorf("the index reads %q; want the pointer to the new save kept", got)
	}
}

// stuckPointer drops n.md while an agent edits the index at each try to take
// its pointer out, so the pointer stays for the next run, and returns the city,
// the memory directory and the index.
func stuckPointer(t *testing.T) (*city, string, string) {
	t.Helper()
	c := newCity(t)
	m := c.rig("r", "tk")
	index := filepath.Join(m, indexName)
	write(t, index, "- [N](n.md) — the lesson\n- [O](o.md) — another\n")
	write(t, filepath.Join(m, "n.md"), "n lesson.\n")
	write(t, filepath.Join(m, "o.md"), "o lesson.\n")
	r := refOf(c.due(), "n.md")
	racing := true
	landOn(t, "swap", index, func() {
		if racing {
			appendTo(t, index, "- An agent's line.\n")
		}
	})
	a := c.apply(r + " drop")
	racing = false
	if !said(a.Failed, "the links in "+index+" were not taken out, and the next run tries again") ||
		exists(filepath.Join(m, "n.md")) || !strings.Contains(read(t, index), "(n.md)") {
		t.Fatalf("failed %q; want n.md removed and its pointer left for the next run", a.Failed)
	}
	if got := read(t, filepath.Join(c.state(m), goneFile)); got != "\"n.md\"\n" {
		t.Fatalf("recorded %q for the next run; want n.md", got)
	}
	return c, m, index
}

// A pointer the index kept changing too fast to take out goes on the next run,
// a settle or an apply, which then records nothing more for it.
func TestAPointerThatDidNotComeOutGoesOnTheNextRun(t *testing.T) {
	for verb, next := range map[string]func(*city) []string{
		"settle": func(c *city) []string { return c.settle().Failed },
		"apply":  func(c *city) []string { return c.apply(refOf(c.due(), "o.md") + " next 2026-12-01").Failed },
	} {
		t.Run(verb, func(t *testing.T) {
			c, m, index := stuckPointer(t)
			if failed := next(c); len(failed) > 0 {
				t.Fatal(failed)
			}
			want := "- [O](o.md) — another\n- An agent's line.\n- An agent's line.\n- An agent's line.\n"
			if got := read(t, index); got != want {
				t.Errorf("the index reads %q, want %q", got, want)
			}
			if exists(filepath.Join(c.state(m), goneFile)) {
				t.Error("n.md is still recorded once its pointer is out")
			}
		})
	}
}

// A drop killed at either step of its note's removal leaves the next run the
// note's name: a settle then takes out the pointer to a note that moved, keeps
// the pointer to one that stays, and records the name no more.
func TestADropKilledAtAnyStepLeavesItsPointerToTheNextRun(t *testing.T) {
	for step, want := range map[string]string{
		"move":  "- [N](n.md) — the lesson\n- [O](o.md) — another\n",
		"check": "- [O](o.md) — another\n",
	} {
		t.Run(step, func(t *testing.T) {
			c := newCity(t)
			m := c.rig("r", "tk")
			index := filepath.Join(m, indexName)
			write(t, index, "- [N](n.md) — the lesson\n- [O](o.md) — another\n")
			write(t, filepath.Join(m, "n.md"), "n lesson.\n")
			write(t, filepath.Join(m, "o.md"), "o lesson.\n")
			r := refOf(c.due(), "n.md")
			killedAt(t, step, func() { c.apply(r + " drop") })
			if s := c.settle(); len(s.Failed) > 0 {
				t.Fatal(s.Failed)
			}
			if got := read(t, index); got != want {
				t.Errorf("the index reads %q, want %q", got, want)
			}
			if exists(filepath.Join(c.state(m), goneFile)) {
				t.Error("n.md is still recorded once the settle is done")
			}
		})
	}
}

// A note saved under the name of one whose pointer is left for the next run
// keeps that pointer and the judge's decision on it, and is recorded no more.
func TestAPointerLeftForTheNextRunStaysForANoteSavedUnderItsName(t *testing.T) {
	c, m, index := stuckPointer(t)
	write(t, filepath.Join(m, "n.md"), "n lesson, saved again.\n")
	if a := c.apply(refOf(c.due(), "n.md") + " next 2026-12-01"); len(a.Failed) > 0 {
		t.Fatal(a.Failed)
	}
	if got := read(t, index); !strings.Contains(got, "- [N](n.md) — the lesson\n") {
		t.Errorf("the index reads %q; want the pointer to the new save kept", got)
	}
	if ds := c.due(); dueOf(ds, "n.md") != "" {
		t.Errorf("due %s; want the decision on the new save kept", names(ds))
	}
	if exists(filepath.Join(c.state(m), goneFile)) {
		t.Error("n.md is still recorded though its name holds a note")
	}
}

// The notes recorded for the next run read back as written, whatever their
// names hold.
func TestTheNotesLeftForTheNextRunReadBack(t *testing.T) {
	state := t.TempDir()
	want := map[string]bool{"a lesson.md": true, "hub-x\ny.md": true, `say "it".md`: true}
	if err := writeGone(state, want); err != nil {
		t.Fatal(err)
	}
	got, err := readGone(state)
	if err != nil || !maps.Equal(got, want) {
		t.Errorf("read %v, %v; want %v", got, err, want)
	}
	if err := writeGone(state, nil); err != nil || exists(filepath.Join(state, goneFile)) {
		t.Errorf("an empty record left its file: %v", err)
	}
}

// A write waits for another run's lock, and gives up once its wait ends.
func TestAWriteWaitsForAnotherRunsLock(t *testing.T) {
	c := newCity(t)
	m := c.rig("r", "tk")
	write(t, filepath.Join(m, "n.md"), "n lesson.\n")
	r := refOf(c.due(), "n.md")
	release, err := c.in.lock(c.state(m), m)
	if err != nil {
		t.Fatal(err)
	}
	c.in.LockWait = 100 * time.Millisecond
	a := c.apply(r + " drop")
	release()
	if !said(a.Failed, "another run held the lock") || !exists(filepath.Join(m, "n.md")) {
		t.Errorf("failed %q; want the lock's wait to end the apply", a.Failed)
	}
	if a := c.apply(r + " drop"); len(a.Failed) > 0 || exists(filepath.Join(m, "n.md")) {
		t.Errorf("once released, failed %q", a.Failed)
	}
}

// An apply with no decision asks nothing.
func TestAnEmptyApplyAsksNothing(t *testing.T) {
	c := newCity(t)
	if a := c.apply("", "# nothing"); len(a.Said)+len(a.Failed) != 0 || len(c.claude.Asks()) != 0 {
		t.Errorf("an empty apply said %q, failed %q, asked %d", a.Said, a.Failed, len(c.claude.Asks()))
	}
}
