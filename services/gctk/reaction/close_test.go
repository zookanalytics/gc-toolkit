package reaction

import (
	"errors"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
)

// The close exit hands the subject to a validating closer, rig-pinned, after
// the close brief and the headline, and never closes it or releases it to a
// pool as a raw bead; a closer pool that does not run is slung to as any other
// is; a closer route gc sling refuses leaves the brief and the headline, says
// what to do, and lands when run again with a pool the city configures; a
// brief or a headline that does not land dispatches nothing; a failed sling
// names gc sling's reason; and a closer already live is the subject's closer.
func TestCloseHandsTheSubjectToItsCloser(t *testing.T) {
	w := newWorld(t)
	code, out, err := w.dispose("tk-sub", "--disposition", "close", "--reason", "already fixed, nothing to merge", "--takeaway", "close: fixed in #123", "--run", root)
	wantCode(t, code, 0, err, "(CLOSE) the close exit")
	w.has("SLING gc-toolkit/gc-toolkit.polecat tk-sub --on mol-validate-close --rig gc-toolkit", "(CLOSE) it slings the closer to the rig's polecat pool, rig-pinned")
	w.has("TAKEAWAY tk-sub close: fixed in #123 --by proactive", "(CLOSE) it sets the headline")
	w.has("UPDATE tk-sub --append-notes ## Close brief (first reaction, 2026-11-16T12:00:00Z)\nalready fixed, nothing to merge", "(CLOSEBRIEF) the brief is the reason, on the subject's notes")
	w.before("Close brief", "TAKEAWAY", "(CLOSEBRIEF) before the headline")
	w.before("TAKEAWAY", "SLING ", "(CLOSEHEAD) the headline before the closer")
	w.hasnt("--release", "(CLOSE) not released to a pool as a raw bead")
	w.hasnt("held on", "(CLOSEBRIEF) a close that waits on nothing names no hold")
	w.hasnt("--status", "(CLOSE) the subject is never closed here")
	w.hasnt("ARM ", "(CLOSE) nothing is armed")
	if out != "tk-sub disposed as close (gc-toolkit/gc-toolkit.polecat)" {
		t.Errorf("(CLOSE) the exit reported %q", out)
	}

	w = newWorld(t)
	w.r.Rig = ""
	code, _, err = w.dispose("tk-sub", "--disposition", "close", "--reason", "r", "--takeaway", "t", "--route", "gc-toolkit/gc-toolkit.polecat", "--run", root)
	wantCode(t, code, 0, err, "(CLOSE) with no rig, an explicit --route")
	if s := w.lines("SLING "); len(s) != 1 || s[0] != "SLING gc-toolkit/gc-toolkit.polecat tk-sub --on mol-validate-close" {
		t.Errorf("(CLOSE) the sling was %q, with no rig pin", s)
	}

	w = newWorld(t)
	w.rt.Roster[0].Suspended = true
	code, _, err = w.dispose("tk-sub", "--disposition", "close", "--reason", "r", "--takeaway", "t", "--run", root)
	wantCode(t, code, 0, err, "(CLOSE) a closer pool that does not run")
	w.has("SLING gc-toolkit/gc-toolkit.polecat tk-sub --on mol-validate-close --rig gc-toolkit", "(CLOSE) the closer is slung to it all the same")
	if slices.Contains(w.rt.Reads(), "roster") {
		t.Errorf("(CLOSE) the exit asked about the pool: the reads were %v", w.rt.Reads())
	}

	w = newWorld(t)
	code, _, err = w.dispose("tk-sub", "--disposition", "close", "--reason", "r", "--takeaway", "t", "--route", "gc-toolkit/gc-toolkit.nosuch", "--run", root)
	wantCode(t, code, 4, err, "(CLOSEBADROUTE) a closer route gc sling refuses")
	w.before("Close brief", "SLING gc-toolkit/gc-toolkit.nosuch", "(CLOSEBADROUTE) the brief lands before the closer's sling")
	w.before("TAKEAWAY", "SLING gc-toolkit/gc-toolkit.nosuch", "(CLOSEBADROUTE) and the headline")
	errHas(t, err, `gc sling: agent "gc-toolkit/gc-toolkit.nosuch" not found in city.toml`, "(CLOSEBADROUTE) giving gc sling's reason")
	errHas(t, err, "The close brief and the headline stand", "(CLOSEBADROUTE) saying what landed")
	errHas(t, err, "run this exit again with --route naming a pool the city configures", "(CLOSEBADROUTE) and what to do")
	code, _, err = w.dispose("tk-sub", "--disposition", "close", "--reason", "r", "--takeaway", "t", "--run", root)
	wantCode(t, code, 0, err, "(CLOSEBADROUTE) the exit run again with a pool the city configures")
	w.has("SLING gc-toolkit/gc-toolkit.polecat tk-sub --on mol-validate-close --rig gc-toolkit", "(CLOSEBADROUTE) slings the closer there")

	w = newWorld(t)
	w.store.BeforeUpdate = func(id string, args []string) error {
		if strings.Contains(strings.Join(args, " "), "--append-notes") {
			return errors.New("the store refused it")
		}
		return nil
	}
	code, _, err = w.dispose("tk-sub", "--disposition", "close", "--reason", "r", "--takeaway", "t", "--run", root)
	wantCode(t, code, 4, err, "(CLOSEBRIEF) a brief that does not land")
	w.hasnt("SLING", "(CLOSEBRIEF) no closer without its brief")
	w.hasnt("TAKEAWAY", "(CLOSEBRIEF) and no headline")

	w = newWorld(t)
	w.takeawayFails = true
	code, _, err = w.dispose("tk-sub", "--disposition", "close", "--reason", "r", "--takeaway", "t", "--run", root)
	wantCode(t, code, 4, err, "(CLOSEHEAD) a headline that does not land")
	errHas(t, err, "its headline did not land", "(CLOSEHEAD) saying so")
	w.hasnt("SLING", "(CLOSEHEAD) no closer under no headline")

	w = newWorld(t)
	w.slingFails = true
	code, _, err = w.dispose("tk-sub", "--disposition", "close", "--reason", "r", "--takeaway", "t", "--run", root)
	wantCode(t, code, 4, err, "(CLOSE) a failed sling")
	errHas(t, err, "gc sling --on mol-validate-close: exit 1: gc sling: fake refusal", "(CLOSE) naming gc sling's reason")

	w = newWorld(t)
	w.slingCode = 3
	code, _, err = w.dispose("tk-sub", "--disposition", "close", "--reason", "r", "--takeaway", "t", "--run", root)
	wantCode(t, code, 0, err, "(CLOSEREOFFER) a close whose closer is already live")
	w.saidHas("a validating closer already drives tk-sub, so no second is slung", "(CLOSEREOFFER) naming it")
	w.saidHas("tk-closer-root", "(CLOSEREOFFER) with the run gc sling named")
}

// A close whose subject's job ends once other beads land holds the subject on
// each, after its brief and its headline, and arms the closer once, after the
// holds, slinging nothing now. A hold or an arm that does not land fails the
// exit; a wait its store does not hold, read before the first write, is
// refused with a person's close as the remedy; and a read that does not answer
// for a wait, or a subject with a wait edge into another store, writes nothing.
func TestCloseWaitsOnTheBeadsThatEndItsJob(t *testing.T) {
	retiring := func(w *world, ids ...string) {
		for _, id := range ids {
			w.store.Put(fake.Bead{ID: id, Title: "retire " + id, Status: "open", IssueType: "task"})
		}
	}
	w := newWorld(t)
	retiring(w, "tk-retire")
	code, out, err := w.dispose("tk-sub", "--disposition", "close", "--reason", "the file it reports on is retired whole by tk-retire",
		"--takeaway", "checked once tk-retire retires its code", "--waiting-on", "tk-retire", "--run", root)
	wantCode(t, code, 0, err, "(CLOSEWAIT) a close that waits")
	w.has("DEP-ADD tk-sub tk-retire --type blocks", "(CLOSEWAIT) the subject is held on the bead")
	w.has("--append-notes ## Close brief (first reaction, held on tk-retire, ", "(CLOSEWAIT) the brief names the bead it is held on")
	w.before("Close brief", "TAKEAWAY", "(CLOSEWAIT) the brief, then the headline")
	w.before("TAKEAWAY", "DEP-ADD", "(CLOSEWAIT) before the hold")
	if a := w.lines("ARM "); len(a) != 1 || a[0] != "ARM tk-sub --target gc-toolkit/gc-toolkit.polecat --on mol-validate-close" {
		t.Errorf("(CLOSEWAIT) the arms were %q", a)
	}
	w.before("DEP-ADD", "ARM ", "(CLOSEWAIT) the arm after the hold")
	w.hasnt("SLING", "(CLOSEWAIT) nothing slung now")
	if out != "tk-sub disposed as close (gc-toolkit/gc-toolkit.polecat once tk-retire closes)" {
		t.Errorf("(CLOSEWAIT) the exit reported %q", out)
	}

	w = newWorld(t)
	retiring(w, "tk-a", "tk-b")
	code, _, err = w.dispose("tk-sub", "--disposition", "close", "--reason", "r", "--takeaway", "t", "--waiting-on", "tk-a", "--waiting-on", "tk-b", "--run", root)
	wantCode(t, code, 0, err, "(CLOSEWAIT) a close that waits on two beads")
	w.has("DEP-ADD tk-sub tk-a --type blocks", "(CLOSEWAIT) held on the first")
	w.has("DEP-ADD tk-sub tk-b --type blocks", "(CLOSEWAIT) and on the second")
	if n := len(w.lines("ARM ")); n != 1 {
		t.Errorf("(CLOSEWAIT) %d arms, want 1", n)
	}
	w.has("held on tk-a,tk-b, ", "(CLOSEWAIT) a brief naming both")

	w = newWorld(t)
	retiring(w, "tk-retire")
	w.store.EdgeErr = errors.New("dependency already exists with type \"related\"")
	code, _, err = w.dispose("tk-sub", "--disposition", "close", "--reason", "r", "--takeaway", "t", "--waiting-on", "tk-retire", "--run", root)
	wantCode(t, code, 4, err, "(CLOSEWAIT) a hold that did not land")
	errHas(t, err, "gc bd dep remove tk-sub tk-retire", "(CLOSEWAIT) naming the edge that would refuse it")
	w.hasnt("ARM ", "(CLOSEWAIT) and the ungated closer is not armed")

	w = newWorld(t)
	retiring(w, "tk-retire")
	w.armErr = errors.New("tk-sub has a wait edge onto ra-elsewhere, a bead its store does not hold")
	code, _, err = w.dispose("tk-sub", "--disposition", "close", "--reason", "r", "--takeaway", "t", "--waiting-on", "tk-retire", "--run", root)
	wantCode(t, code, 4, err, "(CLOSEWAIT) a failed arm")
	errHas(t, err, "the validating closer was not armed", "(CLOSEWAIT) saying so")
	errHas(t, err, "a bead its store does not hold", "(CLOSEWAIT) carrying the arm's reason")
	errHas(t, err, "gc bd dep remove tk-sub <that bead>", "(CLOSEWAIT) naming the edge's removal")
	errHas(t, err, "--disposition ruling", "(CLOSEWAIT) and a person's close")

	for name, waits := range map[string][]string{
		"a bead in another store":         {"ra-foreign"},
		"one named after a held one":      {"tk-a", "ra-foreign"},
		"a bead this store does not hold": {"tk-gone"},
	} {
		w := newWorld(t)
		retiring(w, "tk-a")
		args := []string{"tk-sub", "--disposition", "close", "--reason", "r", "--takeaway", "t", "--run", root}
		for _, id := range waits {
			args = append(args, "--waiting-on", id)
		}
		code, _, err := w.dispose(args...)
		wantCode(t, code, 2, err, "(CLOSEWAIT) a close waiting on "+name)
		errHas(t, err, "--disposition ruling", "(CLOSEWAIT) a person's close is the remedy")
		if got := w.writes(); len(got) != 0 {
			t.Errorf("(CLOSEWAIT) a close waiting on %s wrote %q", name, got)
		}
	}

	w = newWorld(t)
	retiring(w, "tk-retire")
	w.store.Mark("tk-retire")
	code, _, err = w.dispose("tk-sub", "--disposition", "close", "--reason", "r", "--takeaway", "t", "--waiting-on", "tk-retire", "--run", root)
	wantCode(t, code, 4, err, "(CLOSEWAIT) a wait the read could not answer for")
	errHas(t, err, "could not read whether tk-sub's store holds tk-retire", "(CLOSEWAIT) saying so")
	if got := w.writes(); len(got) != 0 {
		t.Errorf("(CLOSEWAIT) wrote %q", got)
	}

	w = newWorld(t)
	retiring(w, "tk-retire")
	w.subject(func(b *fake.Bead) { b.Edges = append(b.Edges, gcbd.Edge{Type: gcbd.EdgeBlocks, ID: "ra-elsewhere"}) })
	code, _, err = w.dispose("tk-sub", "--disposition", "close", "--reason", "r", "--takeaway", "t", "--waiting-on", "tk-retire", "--run", root)
	wantCode(t, code, 4, err, "(CLOSEWAIT) a subject with a wait edge into another store")
	errHas(t, err, "carries a wait edge into another store (ra-elsewhere (blocks)), which holds nothing", "(CLOSEWAIT) naming the edge")
	errHas(t, err, "gc bd dep remove tk-sub ra-elsewhere", "(CLOSEWAIT) and its removal")
	if got := w.writes(); len(got) != 0 {
		t.Errorf("(CLOSEWAIT) wrote %q", got)
	}

	w = newWorld(t)
	code, _, err = w.dispose("tk-sub", "--disposition", "close", "--reason", "r", "--takeaway", "t", "--waiting-on", "tk-sub", "--run", root)
	wantCode(t, code, 2, err, "(CLOSEWAIT) a bead waiting on itself")
}

// No exit closes its subject: a reaction advances a bead and never finishes
// it, whatever the exit.
func TestNoExitClosesItsSubject(t *testing.T) {
	for _, exit := range [][]string{
		{"--disposition", "actionable", "--route", "gc-toolkit/gc-toolkit.polecat"},
		{"--disposition", "blocked", "--waiting-on", "tk-blk1", "--then-route", "gc-toolkit/gc-toolkit.polecat"},
		{"--disposition", "close"},
		{"--disposition", "ruling"},
		{"--disposition", "recommend", "--recommended-formula", "mol-x"},
	} {
		w := newWorld(t)
		code, _, err := w.dispose(append([]string{"tk-sub", "--reason", "r", "--takeaway", "t", "--run", root}, exit...)...)
		wantCode(t, code, 0, err, "(NEVERCLOSE) "+exit[1])
		w.hasnt("--status", "(NEVERCLOSE) "+exit[1]+" writes no status")
		if s, _ := w.store.Row("tk-sub"); s.Status != "open" {
			t.Errorf("(NEVERCLOSE) %s left the subject %s", exit[1], s.Status)
		}
	}
}
