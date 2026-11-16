package reaction

import (
	"errors"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// The blocked exit's wait rides the release as an edge, the subject is not
// also routed or called settled, and what holds the subject is read before the
// first write.
func TestBlockedWaitsOnItsBlocker(t *testing.T) {
	w := newWorld(t)
	code, out, err := w.dispose("tk-sub", "--disposition", "blocked", "--reason", "waits on the schema migration",
		"--takeaway", "held: schema migration first", "--waiting-on", "tk-blk1", "--run", root)
	wantCode(t, code, 0, err, "(BLK) a blocked exit")
	w.has("--release --waiting-on tk-blk1", "(BLK) the wait rides the release")
	w.hasnt("--route", "(BLK) a held bead is not also routed")
	w.hasnt("--no-wait", "(BLK) the named wait is not called settled")
	if out != "tk-sub disposed as blocked (tk-blk1)" {
		t.Errorf("(BLK) the exit reported %q", out)
	}
	w.has("FIND tk-blk1 tk-sub", "(BLKHOLDS) the exit reads what holds the subject and its wait")
	w.before("FIND tk-blk1 tk-sub", "HELM takeaway", "(BLKHOLDS) before its first write")

	w = newWorld(t)
	code, _, err = w.dispose("tk-sub", "--disposition", "blocked", "--reason", "r", "--takeaway", "t", "--run", root)
	wantCode(t, code, 2, err, "(BLK) blocked with no wait at all")
	errHas(t, err, "prose about it holds nothing", "(BLK) the refusal says why")

	w = newWorld(t)
	code, _, err = w.dispose("tk-sub", "--disposition", "blocked", "--reason", "r", "--takeaway", "t", "--waiting-on", "tk-sub", "--run", root)
	wantCode(t, code, 2, err, "(BLKSELF) a bead waiting on itself")
}

// A read of what holds the subject that does not answer, for the subject or for
// a bead it would wait on, writes nothing; a subject with a wait edge into
// another store takes no write, and the refusal names the edge and its removal.
func TestBlockedReadsWhatHoldsItsSubjectFirst(t *testing.T) {
	w := newWorld(t)
	w.store.BlockedErr = &gcbd.ReadError{Reason: "gc bd blocked exited 1: the store did not answer"}
	code, _, err := w.dispose("tk-sub", "--disposition", "blocked", "--reason", "r", "--takeaway", "t", "--waiting-on", "tk-blk1",
		"--then-route", "gc-toolkit/gc-toolkit.polecat", "--run", root)
	wantCode(t, code, 4, err, "(BLKHOLDS) a holds read that does not answer")
	errHas(t, err, "could not read what holds tk-sub", "(BLKHOLDS) saying so")
	if got := w.writes(); len(got) != 0 {
		t.Errorf("(BLKHOLDS) wrote %q", got)
	}

	w = newWorld(t)
	w.store.Mark("tk-blk1")
	code, _, err = w.dispose("tk-sub", "--disposition", "blocked", "--reason", "r", "--takeaway", "t", "--waiting-on", "tk-blk1", "--run", root)
	wantCode(t, code, 4, err, "(BLKHOLDS) a wait the read could not answer for")
	errHas(t, err, "could not read whether tk-sub's store holds tk-blk1", "(BLKHOLDS) saying so")
	if err != nil && strings.Contains(err.Error(), "is not a bead tk-sub's store holds") {
		t.Errorf("(BLKHOLDS) the failure says the store does not hold the bead: %v", err)
	}
	if got := w.writes(); len(got) != 0 {
		t.Errorf("(BLKHOLDS) wrote %q", got)
	}

	w = newWorld(t)
	w.subject(func(b *fake.Bead) {
		b.Edges = append(b.Edges, gcbd.Edge{Type: gcbd.EdgeBlocks, ID: "ra-elsewhere"})
	})
	code, _, err = w.dispose("tk-sub", "--disposition", "blocked", "--reason", "r", "--takeaway", "t", "--waiting-on", "tk-blk1",
		"--then-route", "gc-toolkit/gc-toolkit.polecat", "--run", root)
	wantCode(t, code, 4, err, "(BLKFOREIGN) a subject with a wait edge into another store")
	errHas(t, err, "carries a wait edge into another store (ra-elsewhere (blocks)), which holds nothing", "(BLKFOREIGN) naming the edge")
	errHas(t, err, "gc bd dep remove tk-sub ra-elsewhere", "(BLKFOREIGN) and its removal")
	if got := w.writes(); len(got) != 0 {
		t.Errorf("(BLKFOREIGN) wrote %q", got)
	}
}

// A --waiting-on the subject's store does not hold, such as one in another
// store, is refused before anything is written, so a --blocker riding along
// files nothing and an emergency's P0 lands no more than the wait does.
func TestBlockedRefusesAWaitItsStoreDoesNotHold(t *testing.T) {
	w := newWorld(t)
	code, _, err := w.dispose("tk-sub", "--disposition", "blocked", "--reason", "r", "--takeaway", "t", "--waiting-on", "ra-foreign", "--run", root)
	wantCode(t, code, 2, err, "(BLKCROSS) a blocker in another store")
	w.has("FIND ra-foreign tk-sub", "(BLKCROSS) the read of what holds the subject names it")
	errHas(t, err, "is not a bead tk-sub's store holds", "(BLKCROSS) saying the store does not hold it")
	errHas(t, err, "store that names it instead", "(BLKCROSS) naming the remedy")
	if got := w.writes(); len(got) != 0 {
		t.Errorf("(BLKCROSS) wrote %q", got)
	}

	w = newWorld(t)
	code, _, err = w.dispose("tk-sub", "--disposition", "blocked", "--reason", "r", "--takeaway", "t", "--blocker", "Migrate the seed schema", "--waiting-on", "ra-foreign", "--run", root)
	wantCode(t, code, 2, err, "(BLKCROSS) a --blocker beside a wait in another store")
	if got := w.writes(); len(got) != 0 {
		t.Errorf("(BLKCROSS) filed %q", got)
	}

	w = newWorld(t)
	w.subject(func(b *fake.Bead) { b.Edges = nil })
	w.red()
	code, _, err = w.dispose("tk-sub", "--disposition", "blocked", "--reason", "r", "--takeaway", "t", "--waiting-on", "ra-foreign",
		"--then-route", "gc-toolkit/gc-toolkit.polecat", "--emergency", "test-macos", "--run", root)
	wantCode(t, code, 2, err, "(BLKCROSS) an emergency waiting on a bead in another store")
	if reads := strings.Join(w.gh.Reads(), ","); !strings.Contains(reads, "HeadChecks") {
		t.Errorf("(BLKCROSS) the claim was not checked: %s", reads)
	}
	if got := w.writes(); len(got) != 0 {
		t.Errorf("(BLKCROSS) wrote %q", got)
	}
}

// --blocker files the missing bead and waits on it, the wait riding the bead's
// create, before the release; a title past bd's 500-byte cap is refused here.
func TestBlockedFilesItsMissingBlocker(t *testing.T) {
	w := newWorld(t)
	code, _, err := w.dispose("tk-sub", "--disposition", "blocked", "--reason", "nothing tracks the migration yet",
		"--takeaway", "held: the migration is now filed", "--blocker", "Migrate the seed schema", "--run", root)
	wantCode(t, code, 0, err, "(BLKNEW) a wait that is not a bead yet")
	creates := w.store.Creates()
	if len(creates) != 1 || creates[0].Title != "Migrate the seed schema" || !strings.Contains(strings.Join(creates[0].Args, " "), "--deps blocks:tk-sub") ||
		!strings.Contains(strings.Join(creates[0].Args, " "), "-t task") {
		t.Fatalf("(BLKNEW) the creates were %+v", creates)
	}
	w.has("--waiting-on fk-1", "(BLKNEW) the subject waits on the bead filed")
	w.before("CREATE fk-1", "HELM takeaway", "(BLKNEW) filed before the release writes the wait")

	w = newWorld(t)
	code, _, err = w.dispose("tk-sub", "--disposition", "blocked", "--reason", "r", "--takeaway", "t", "--blocker", strings.Repeat("x", 501), "--run", root)
	wantCode(t, code, 2, err, "(BLKNEW) a blocker title past 500 bytes")
	errHas(t, err, "cap is 500", "(BLKNEW) by its actual cause")
}

// lossyStore is a store whose creates land and lose their reply.
type lossyStore struct {
	*fake.Store
	lose bool
}

func (s *lossyStore) Create(title string, args ...string) (string, error) {
	id, err := s.Store.Create(title, args...)
	if err == nil && s.lose {
		return "", errors.New("bd's create exited 1, so whether it filed the bead is unknown: the store did not answer")
	}
	return id, err
}

// An exit that stops after it filed the blocker, at a release the store
// refuses or at a create that lost its reply, waits on the blocker that landed
// when it is run again, and files no second; a pending wait of the subject's
// with the blocker's title is reused, and one under another title, or of
// another edge type, is not this blocker.
func TestBlockedReusesTheBlockerAnEarlierRunFiled(t *testing.T) {
	w := newWorld(t)
	w.helmFails = true
	code, _, err := w.dispose("tk-sub", "--disposition", "blocked", "--reason", "r", "--takeaway", "t", "--blocker", "Migrate the seed schema", "--run", root)
	wantCode(t, code, 4, err, "(BLKRETRY) an exit whose release fails after the blocker is filed")
	w.helmFails = false
	code, _, err = w.dispose("tk-sub", "--disposition", "blocked", "--reason", "r", "--takeaway", "t", "--blocker", "Migrate the seed schema", "--run", root)
	wantCode(t, code, 0, err, "(BLKRETRY) the same exit run again")
	if n := len(w.store.Creates()); n != 1 {
		t.Errorf("(BLKRETRY) %d creates across both runs, want 1", n)
	}
	if h := w.lines("HELM takeaway"); !strings.Contains(h[len(h)-1], "--waiting-on fk-1") {
		t.Errorf("(BLKRETRY) the re-run's release was %q", h[len(h)-1])
	}
	w.saidHas("already tk-sub's pending wait fk-1", "(BLKRETRY) saying so")

	w = newWorld(t)
	lossy := &lossyStore{Store: w.store, lose: true}
	w.r.Ledger = ledger.New(lossy)
	code, _, err = w.dispose("tk-sub", "--disposition", "blocked", "--reason", "r", "--takeaway", "t", "--blocker", "Migrate the seed schema", "--run", root)
	wantCode(t, code, 4, err, "(BLKLOST) a create that named no bead")
	errHas(t, err, "either both landed or neither did", "(BLKLOST) saying the bead and the wait land together")
	w.hasnt("HELM takeaway", "(BLKLOST) before the release")
	lossy.lose = false
	code, _, err = w.dispose("tk-sub", "--disposition", "blocked", "--reason", "r", "--takeaway", "t", "--blocker", "Migrate the seed schema", "--run", root)
	wantCode(t, code, 0, err, "(BLKLOST) the same exit run again")
	if n := len(w.store.Creates()); n != 1 {
		t.Errorf("(BLKLOST) %d creates, want the one that landed", n)
	}
	w.has("--waiting-on fk-1", "(BLKLOST) the release names the blocker that landed")

	w = newWorld(t)
	w.store.Put(fake.Bead{ID: "tk-already", Title: "Migrate the seed schema", Status: "open", IssueType: "task"})
	w.subject(func(b *fake.Bead) {
		b.Edges = append(b.Edges, gcbd.Edge{Type: gcbd.EdgeBlocks, ID: "tk-already", Title: "Migrate the seed schema", Status: "open"})
	})
	code, _, err = w.dispose("tk-sub", "--disposition", "blocked", "--reason", "same cause", "--takeaway", "held: same migration", "--blocker", "Migrate the seed schema", "--run", root)
	wantCode(t, code, 0, err, "(BLKREUSE) a blocker the subject already waits on")
	w.hasnt("CREATE", "(BLKREUSE) no second bead is filed")
	w.has("--waiting-on tk-already", "(BLKREUSE) it waits on the one filed")
	w.saidHas("already tk-sub's pending wait tk-already", "(BLKREUSE) and says so")
	code, _, err = w.dispose("tk-sub", "--disposition", "blocked", "--reason", "r", "--takeaway", "t", "--blocker", "Migrate the seed data", "--run", root)
	wantCode(t, code, 0, err, "(BLKREUSE) a blocker under another title")
	if c := w.store.Creates(); len(c) != 1 || c[0].Title != "Migrate the seed data" {
		t.Errorf("(BLKREUSE) a pending wait under another title was taken for this blocker: %+v", c)
	}

	w = newWorld(t)
	w.store.Put(fake.Bead{ID: "tk-g9", Title: "Migrate the seed schema", Status: "open", IssueType: "gate"})
	w.subject(func(b *fake.Bead) {
		b.Edges = append(b.Edges, gcbd.Edge{Type: gcbd.EdgeWaitsFor, ID: "tk-g9", Title: "Migrate the seed schema", Status: "open"})
	})
	code, _, err = w.dispose("tk-sub", "--disposition", "blocked", "--reason", "r", "--takeaway", "t", "--blocker", "Migrate the seed schema", "--run", root)
	wantCode(t, code, 0, err, "(BLKREUSE) a wait of another edge type")
	if c := w.store.Creates(); len(c) != 1 {
		t.Errorf("(BLKREUSE) a waits-for wait was taken for the blocker: %+v", c)
	}
}

// --then-route arms the dispatch that resumes the work, a plain arm on the
// target's default, after the release writes the wait. An edge takeaway could
// not write, and an arm that did not land, each fail the exit, and nothing is
// armed after a release that did not land; a re-run arms.
func TestBlockedArmsItsDispatchLast(t *testing.T) {
	w := newWorld(t)
	code, _, err := w.dispose("tk-sub", "--disposition", "blocked", "--reason", "r", "--takeaway", "t", "--waiting-on", "tk-blk1",
		"--then-route", "gc-toolkit/gc-toolkit.polecat", "--run", root)
	wantCode(t, code, 0, err, "(BLKARM) a blocked exit with --then-route")
	if a := w.lines("ARM "); len(a) != 1 || a[0] != "ARM tk-sub --target gc-toolkit/gc-toolkit.polecat" {
		t.Errorf("(BLKARM) the arm was %q, want a plain arm on the target's default", a)
	}
	w.saidHas("armed the dispatch to gc-toolkit/gc-toolkit.polecat", "(BLKARM) the arm lands")
	w.before("HELM takeaway", "ARM ", "(BLKARM) after the release writes the wait")

	w = newWorld(t)
	w.helmFails = true
	code, out, err := w.dispose("tk-sub", "--disposition", "blocked", "--reason", "r", "--takeaway", "t", "--waiting-on", "tk-blk1",
		"--then-route", "gc-toolkit/gc-toolkit.polecat", "--run", root)
	wantCode(t, code, 4, err, "(BLKEDGE) a wait edge takeaway could not write")
	w.hasnt("ARM ", "(BLKEDGE) nothing is armed on a wait that does not exist")
	if out != "" {
		t.Errorf("(BLKEDGE) the exit reported %q", out)
	}

	w = newWorld(t)
	w.armErr = errors.New("tk-sub is dispatched already (fake refusal)")
	code, out, err = w.dispose("tk-sub", "--disposition", "blocked", "--reason", "r", "--takeaway", "t", "--waiting-on", "tk-blk1",
		"--then-route", "gc-toolkit/gc-toolkit.polecat", "--run", root)
	wantCode(t, code, 4, err, "(BLKARMFAIL) an arm that did not land")
	errHas(t, err, "nothing would route tk-sub once the wait lifts", "(BLKARMFAIL) saying what it costs")
	errHas(t, err, "dispatched already (fake refusal)", "(BLKARMFAIL) carrying the arm's cause")
	errHas(t, err, "a re-run resumes", "(BLKARMFAIL) and that a re-run resumes")
	if out != "" {
		t.Errorf("(BLKARMFAIL) the exit reported %q", out)
	}
	w.armErr = nil
	code, _, err = w.dispose("tk-sub", "--disposition", "blocked", "--reason", "r", "--takeaway", "t", "--waiting-on", "tk-blk1",
		"--then-route", "gc-toolkit/gc-toolkit.polecat", "--run", root)
	wantCode(t, code, 0, err, "(BLKARMFAIL) the re-run after a failed arm")

	w = newWorld(t)
	code, _, err = w.dispose("tk-sub", "--disposition", "blocked", "--reason", "r", "--takeaway", "t", "--waiting-on", "tk-blk1",
		"--then-route", "gc-toolkit/gc-toolkit.nosuchpool", "--run", root)
	wantCode(t, code, 2, err, "(BLKROUTE) --then-route to a pool nothing runs")
	if got := w.writes(); len(got) != 0 {
		t.Errorf("(BLKROUTE) wrote %q", got)
	}
}

// A blocked bead handed to a named agent is held on its wait and handed over
// in the agent's form after the release: the mechanik's route, the refinery's
// assignee written beside the wait. The agent is nudged only when bd reports
// the bead ready, since a blocker that closes later nudges it then.
func TestBlockedHandsTheBeadToItsAgent(t *testing.T) {
	w := waitingWorld(t)
	code, out, err := w.dispose("tk-sub", "--disposition", "blocked", "--reason", "the comment can change only once the order lands",
		"--takeaway", "held: city.toml comment waits on the order", "--waiting-on", "tk-blk1", "--then-assign", "gc-toolkit.mechanik", "--run", root)
	wantCode(t, code, 0, err, "(BLKASSIGN) a blocked exit handed to a named agent")
	if out != "tk-sub disposed as blocked (tk-blk1)" {
		t.Errorf("(BLKASSIGN) the exit reported %q", out)
	}
	w.has("--release --waiting-on tk-blk1", "(BLKASSIGN) the wait rides the release")
	for _, l := range w.lines("HELM ") {
		if strings.Contains(l, "--assign") || strings.Contains(l, "--no-wait") {
			t.Errorf("(BLKASSIGN) the release was %q", l)
		}
	}
	w.hasnt("ARM ", "(BLKASSIGN) nothing is armed for a named agent")
	w.has("SLING gc-toolkit.mechanik tk-sub --no-formula --no-convoy", "(BLKHANDOFF) the waiting bead is routed to the agent")
	w.before("HELM takeaway", "SLING ", "(BLKHANDOFF) after the release writes the wait")
	w.hasnt("NUDGE", "(BLKHANDOFF) no nudge while the bead waits")

	w = newWorld(t)
	code, _, err = w.dispose("tk-sub", "--disposition", "blocked", "--reason", "the comment waited on an order that has landed",
		"--takeaway", "held: city.toml comment waits on the order", "--waiting-on", "tk-blk1", "--then-assign", "gc-toolkit.mechanik", "--run", root)
	wantCode(t, code, 0, err, "(BLKREADY) a blocked exit whose blocker closed already")
	w.has("NUDGE gc-toolkit.mechanik tk-sub is routed to you and ready", "(BLKREADY) the mechanik is nudged")
	w.before("SLING ", "NUDGE ", "(BLKREADY) once the bead is routed to it")

	w = newWorld(t)
	w.nudgeFails = true
	code, _, err = w.dispose("tk-sub", "--disposition", "blocked", "--reason", "r", "--takeaway", "t", "--waiting-on", "tk-blk1", "--then-assign", "gc-toolkit.mechanik", "--run", root)
	wantCode(t, code, 4, err, "(HANDOFFFAIL) a --then-assign whose nudge did not reach the agent")
	errHas(t, err, "the blocked exit on tk-sub did not land. It is routed to gc-toolkit.mechanik, but gc session nudge did not reach the agent", "(HANDOFFFAIL) naming the exit")

	w = newWorld(t)
	w.slingFails = true
	code, _, err = w.dispose("tk-sub", "--disposition", "blocked", "--reason", "r", "--takeaway", "t", "--waiting-on", "tk-blk1", "--then-assign", "gc-toolkit.mechanik", "--run", root)
	wantCode(t, code, 4, err, "(HANDOFFFAIL) a --then-assign whose hand-off did not land")
	errHas(t, err, "gc sling did not hand it to gc-toolkit.mechanik", "(HANDOFFFAIL) saying the hook does not offer it")

	w = newWorld(t)
	code, _, err = w.dispose("tk-sub", "--disposition", "blocked", "--reason", "r", "--takeaway", "t", "--waiting-on", "tk-blk1",
		"--then-route", "gc-toolkit/gc-toolkit.polecat", "--then-assign", "gc-toolkit.mechanik")
	wantCode(t, code, 2, err, "(BLKASSIGN) --then-route beside --then-assign")

	w = newWorld(t)
	w.rt.Roster = w.rt.Roster[:1]
	code, _, err = w.dispose("tk-sub", "--disposition", "blocked", "--reason", "r", "--takeaway", "t", "--waiting-on", "tk-blk1", "--then-assign", "gc-toolkit/gc-toolkit.refinery")
	wantCode(t, code, 2, err, "(BLKASSIGN) a --then-assign agent the roster does not register")
	w.hasnt("HELM", "(BLKASSIGN) the bead is not released")

	w = waitingWorld(t)
	code, _, err = w.dispose("tk-sub", "--disposition", "blocked", "--reason", "the hand-off waits on the unit it brings in",
		"--takeaway", "held: bring-current waits on the unit", "--waiting-on", "tk-blk1", "--then-assign", "gc-toolkit/gc-toolkit.refinery", "--run", root)
	wantCode(t, code, 0, err, "(BLKREFINERY) a blocked exit handed to the refinery")
	w.has("--release --waiting-on tk-blk1 --assign gc-toolkit/gc-toolkit.refinery", "(BLKREFINERY) the release writes the wait and the assignee in one call")
	w.hasnt("SLING", "(BLKREFINERY) routing nothing")
	w.hasnt("NUDGE", "(BLKREFINERY) no nudge while the bead waits")

	w = newWorld(t)
	code, _, err = w.dispose("tk-sub", "--disposition", "blocked", "--reason", "the hand-off waited on a unit that has landed",
		"--takeaway", "held: bring-current waits on the unit", "--waiting-on", "tk-blk1", "--then-assign", "gc-toolkit/gc-toolkit.refinery", "--run", root)
	wantCode(t, code, 0, err, "(BLKREADY) the refinery's blocker closed already")
	w.has("NUDGE gc-toolkit/gc-toolkit.refinery tk-sub is assigned to you and ready", "(BLKREADY) the refinery is nudged")
	w.before("HELM takeaway", "NUDGE ", "(BLKREADY) once the release has assigned it")
}
