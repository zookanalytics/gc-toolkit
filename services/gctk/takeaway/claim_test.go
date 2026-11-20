package takeaway

import (
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
)

// raceOnWrite lands another writer's change to bead ahead of the first update
// of it that carries a guard, as a close or a claim that lands between the
// release's read and its write does, and logs each update attempted.
func raceOnWrite(w *world, bead string, change func(fake.Bead) fake.Bead) {
	raced := false
	w.store.BeforeUpdate = func(id string, args []string) error {
		w.add("ATTEMPT " + id + " " + strings.Join(args, " "))
		if id == bead && !raced && slices.ContainsFunc(args, func(a string) bool { return strings.HasPrefix(a, "--if-status=") }) {
			raced = true
			b, _ := w.store.Row(bead)
			w.store.Put(change(b))
		}
		return nil
	}
}

// A close that lands after the release read the bead open refuses the guarded
// park, so the close stands: the re-read finds the bead closed, which takes
// the closed bead's path, the headline alone in a second write, and the run's
// end. A route on it is never slung (RACECLOSE).
func TestACloseAfterTheReadKeepsItsClose(t *testing.T) {
	closeIt := func(b fake.Bead) fake.Bead { b.Status = "closed"; return b }
	w := newWorld(t)
	raceOnWrite(w, "tk-a", closeIt)
	code, out, err := w.take(Request{Bead: "tk-a", Text: "parked — its premise fell", By: "converse", Release: true, NoWait: true})
	if code != 0 {
		t.Fatalf("a release on a bead that closed after its read exits %d (%v), want 0", code, err)
	}
	attempts := w.lines("ATTEMPT tk-a ")
	if len(attempts) != 2 {
		t.Fatalf("%d updates attempted, want the refused park and the headline: %q", len(attempts), attempts)
	}
	has(t, attempts[0], "--if-status=open --if-assignee= --status=open", "(RACECLOSE) the park is guarded on what it read")
	for _, never := range []string{"--status", "--assignee", "--if-", "gc.routed_to"} {
		hasnt(t, attempts[1], never, "(RACECLOSE) the second write")
	}
	has(t, attempts[1], "--set-metadata gc.takeaway=parked — its premise fell", "(RACECLOSE) the second write")
	if s := w.row("tk-a").Status; s != "closed" {
		t.Errorf("(RACECLOSE) the close did not stand: the bead reads %s", s)
	}
	if len(w.lines("SCRIPT run-cancel.sh --root tk-root ")) != 1 {
		t.Errorf("(RACECLOSE) the run beneath the closed bead was not ended: %q", w.lines("SCRIPT "))
	}
	if !w.saidAny("tk-a closed after the release read it") {
		t.Errorf("(RACECLOSE) the close is unsaid: %q", w.said)
	}
	has(t, out, "anchor left closed", "(RACECLOSE) the success line")

	w = newWorld(t)
	raceOnWrite(w, "tk-a", closeIt)
	if code, _, _ := w.take(Request{Bead: "tk-a", Text: "routed — then it closed", Release: true, Route: pool}); code != 4 || len(w.lines("SLING ")) != 0 {
		t.Errorf("(RACECLOSE) a route on a bead that closed after the read exits %d with slings %q", code, w.lines("SLING "))
	}
}

// A claim that lands after the release read the bead refuses the guarded
// park, and the release takes the bead from no one who holds it now: nothing
// more is written, no edge, no run's end and no sling, and the error names who
// holds it (RACECLAIM).
func TestAClaimAfterTheReadIsNotTaken(t *testing.T) {
	claim := func(b fake.Bead) fake.Bead { b.Status, b.Assignee = "in_progress", "polecat-new"; return b }
	for _, req := range []Request{
		{Bead: "tk-a", Text: "stopped", Release: true, WaitingOn: []string{"tk-blk1"}},
		{Bead: "tk-a", Text: "stopped", Release: true, Route: pool},
	} {
		w := newWorld(t)
		task(w, "tk-blk1", nil)
		raceOnWrite(w, "tk-a", claim)
		code, _, err := w.take(req)
		if code != 4 {
			t.Fatalf("a release on a bead claimed after its read exits %d (%v), want 4", code, err)
		}
		if n := len(w.lines("ATTEMPT ")); n != 1 {
			t.Errorf("(RACECLAIM) %d updates attempted, want the refused park alone", n)
		}
		if got := w.wrote(); slices.ContainsFunc(got, func(l string) bool { return !strings.HasPrefix(l, "ATTEMPT ") }) {
			t.Errorf("(RACECLAIM) the verb wrote after the refused park: %q", got)
		}
		if b := w.row("tk-a"); b.Status != "in_progress" || b.Assignee != "polecat-new" {
			t.Errorf("(RACECLAIM) the claim was taken: the bead reads %s under %q", b.Status, b.Assignee)
		}
		has(t, errText(err), "now shows status in_progress under polecat-new", "(RACECLAIM) the error")
	}
}

// held is the bead tk-held, in progress under polecat-other, which the session
// list names, with a live run beneath it.
func held(w *world) {
	w.put(fake.Bead{ID: "tk-held", Title: "held", Status: "in_progress", IssueType: "task", Assignee: "polecat-other",
		Metadata: map[string]string{"gc.routed_to": pool, "gc.session_name": "polecat-other", "gc.session_id": "s-other"}})
	w.run("tk-held", "tk-root-held", "tk-convoy-held")
	w.roster.SessionList = []gascity.Session{{ID: "s-other", SessionName: "polecat-other", State: "active"}}
}

// A claim a live session holds is never taken: the release writes the headline
// and its waits alone, ends the run beneath the bead, nudges the holder to stop
// and give the bead back, and fails naming the holder. A route on it is never
// slung, a session list that does not read keeps the claim and nudges the
// holder by its own name, and a nudge that does not land is said (HELD,
// HELDSTORE, HELDROUTE, HELDUNREAD, HELDNUDGE).
func TestALiveHoldersClaimIsKept(t *testing.T) {
	w := newWorld(t)
	held(w)
	task(w, "tk-child", nil)
	code, out, err := w.take(Request{Bead: "tk-held", Text: "stopped — the PR it rebuilds was retired", By: "converse", Release: true, WaitingOn: []string{"tk-child"}})
	if code != 4 || out != "" {
		t.Fatalf("(HELD) exits %d with %q, want 4", code, out)
	}
	up := w.update("tk-held")
	has(t, up, "--set-metadata gc.takeaway=stopped — the PR it rebuilds was retired", "(HELD) the headline")
	for _, never := range []string{"--status", "--assignee", "--if-", "gc.routed_to", "--unset-metadata"} {
		hasnt(t, up, never, "(HELD) the write beside a live claim")
	}
	if b := w.row("tk-held"); b.Status != "in_progress" || b.Assignee != "polecat-other" || b.Metadata["gc.session_id"] != "s-other" {
		t.Errorf("(HELDSTORE) the live claim reads %s under %q with %v", b.Status, b.Assignee, b.Metadata)
	}
	if len(w.lines("DEP-ADD tk-held tk-child ")) != 1 || len(w.lines("SCRIPT run-cancel.sh --root tk-root-held ")) != 1 {
		t.Errorf("(HELD) the wait and the run's end did not land: %q", w.log)
	}
	nudges := w.lines("NUDGE ")
	want := "NUDGE s-other about tk-held: Stop work on tk-held: a takeaway --release took it out of play while you hold its claim, and its headline says why: stopped — the PR it rebuilds was retired. Give it back in one guarded write that reopens it and clears your claim and its route: /pack/scripts/hand-back.sh tk-held --set-metadata gc.routed_to="
	if !slices.Equal(nudges, []string{want}) {
		t.Errorf("(HELD) the nudges are %q, want %q", nudges, want)
	}
	has(t, errText(err), "tk-held is in_progress under polecat-other", "(HELD) the error names the holder")

	w = newWorld(t)
	held(w)
	code, _, err = w.take(Request{Bead: "tk-held", Text: "stopped — sent elsewhere", Release: true, Route: pool})
	if code != 4 || len(w.lines("SLING ")) != 0 {
		t.Errorf("(HELDROUTE) exits %d with slings %q", code, w.lines("SLING "))
	}
	has(t, errText(err), "was not released to "+pool, "(HELDROUTE) the error")

	w = newWorld(t)
	held(w)
	w.roster.SessionsErr = errBroken
	code, _, err = w.take(Request{Bead: "tk-held", Text: "stopped", Release: true, NoWait: true})
	if code != 4 {
		t.Errorf("(HELDUNREAD) exits %d, want 4", code)
	}
	hasnt(t, w.update("tk-held"), "--assignee", "(HELDUNREAD) the write")
	if got := w.lines("NUDGE polecat-other about tk-held: Stop work on tk-held"); len(got) != 1 {
		t.Errorf("(HELDUNREAD) the holder was not nudged by its own name: %q", w.lines("NUDGE "))
	}
	has(t, errText(err), "could not be read", "(HELDUNREAD) the error")

	w = newWorld(t)
	held(w)
	w.nudgeFails = true
	_, _, err = w.take(Request{Bead: "tk-held", Text: "stopped", Release: true, NoWait: true})
	has(t, errText(err), "The nudge to polecat-other did not land", "(HELDNUDGE) the error")
}

// A claim whose holder the session list names under none of its names is
// released in the park's one guarded write, which names the holder: bd skips
// its reassign fence only for a write guarded on the holder. The bead reads
// open, unassigned and routed to no pool, its session pins gone, and no
// holder is nudged (GONE, GONESTORE).
func TestAGoneHoldersClaimIsReleasedInOneGuardedWrite(t *testing.T) {
	w := newWorld(t)
	w.fence = true
	w.put(fake.Bead{ID: "tk-gone", Title: "gone", Status: "in_progress", IssueType: "task", Assignee: "polecat-dead",
		Metadata: map[string]string{"gc.routed_to": pool, "gc.session_name": "polecat-dead", "gc.session_id": "s-dead"}})
	w.roster.SessionList = []gascity.Session{{ID: "s-other", SessionName: "polecat-other", Alias: "tk/gc-toolkit.polecat-7"}}
	code, _, err := w.take(Request{Bead: "tk-gone", Text: "stopped — its holder is gone", Release: true, NoWait: true})
	if code != 0 {
		t.Fatalf("(GONE) exits %d (%v), want 0", code, err)
	}
	has(t, w.update("tk-gone"), "--if-status=in_progress --if-assignee=polecat-dead --status=open --assignee= ", "(GONE) the one guarded write")
	b := w.row("tk-gone")
	if b.Status != "open" || b.Assignee != "" || b.Metadata["gc.routed_to"] != "" || b.Metadata["gc.session_id"] != "" || b.Metadata["gc.session_name"] != "" {
		t.Errorf("(GONESTORE) the bead reads %s under %q with %v", b.Status, b.Assignee, b.Metadata)
	}
	if n := len(w.lines("NUDGE ")); n != 0 {
		t.Errorf("(GONE) %d nudges to a holder that is gone", n)
	}
}

// A claim's holder that the list names by its alias, or by the end of one,
// which an agent address is, is a holder the list still names.
func TestAHolderListedUnderItsAliasIsLive(t *testing.T) {
	w := newWorld(t)
	w.put(fake.Bead{ID: "tk-held", Title: "held", Status: "hooked", IssueType: "task", Assignee: "gc-toolkit.polecat-7"})
	w.roster.SessionList = []gascity.Session{{ID: "s-7", Alias: "tk/gc-toolkit.polecat-7"}}
	if code, _, _ := w.take(Request{Bead: "tk-held", Text: "stopped", Release: true, NoWait: true}); code != 4 {
		t.Errorf("a hooked claim whose holder the list names by its alias's end exits %d, want 4", code)
	}
	if got := w.lines("NUDGE s-7 "); len(got) != 1 {
		t.Errorf("the holder was not nudged at its session: %q", w.lines("NUDGE "))
	}
}

// This session's own claim, under its session id or its agent address, is
// released in the one guarded write with no session list read, which here does
// not read at all (MINE).
func TestThisSessionsOwnClaimIsReleased(t *testing.T) {
	for holder, setup := range map[string]func(*Takeaways){
		"hq-me":               func(tk *Takeaways) { tk.Self = []string{"polecat-me", "hq-me"} },
		"gc-toolkit.mechanik": func(tk *Takeaways) { tk.Agent = "gc-toolkit.mechanik" },
	} {
		w := newWorld(t)
		w.fence = true
		setup(w.tk)
		w.roster.SessionsErr = errBroken
		w.put(fake.Bead{ID: "tk-mine", Title: "mine", Status: "in_progress", IssueType: "task", Assignee: holder})
		if code, _, err := w.take(Request{Bead: "tk-mine", Text: "released — this session's own", Release: true, NoWait: true}); code != 0 {
			t.Fatalf("(MINE %s) exits %d (%v), want 0", holder, code, err)
		}
		has(t, w.update("tk-mine"), "--if-status=in_progress --if-assignee="+holder+" --status=open --assignee= ", "(MINE) the one guarded write")
		if reads := w.roster.Reads(); len(reads) != 0 {
			t.Errorf("(MINE %s) the session list was read: %q", holder, reads)
		}
	}
}
