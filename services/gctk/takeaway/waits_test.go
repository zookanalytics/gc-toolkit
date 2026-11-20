package takeaway

import (
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
)

// task puts an open task with its title.
func task(w *world, id string, meta map[string]string) {
	w.put(fake.Bead{ID: id, Title: "work " + id, Status: "open", IssueType: "task", Metadata: meta})
}

// Each named wait becomes a blocks edge from the bead onto it, once each,
// after the headline lands, and a call that names none writes no edge (EDGE,
// EDGEMANY, EDGESTAMP, EDGENONE).
func TestEachWaitIsAnEdgeAfterTheHeadline(t *testing.T) {
	w := newWorld(t)
	task(w, "tk-blk1", nil)
	task(w, "tk-blk2", nil)
	code, _, err := w.take(Request{Bead: "tk-a", Text: "routed — the fix is slung", By: "converse", WaitingOn: []string{"tk-blk1", "tk-blk2", "tk-blk1"}})
	if code != 0 {
		t.Fatalf("exits %d (%v)", code, err)
	}
	if got := w.lines("DEP-ADD "); !slices.Equal(got, []string{"DEP-ADD tk-a tk-blk1 --type blocks", "DEP-ADD tk-a tk-blk2 --type blocks"}) {
		t.Errorf("(EDGE) the edges are %q, want one per wait", got)
	}
	has(t, w.update("tk-a"), "--set-metadata gc.takeaway=routed — the fix is slung", "(EDGESTAMP) the headline")
	w.before("UPDATE tk-a", "DEP-ADD ", "(EDGESTAMP) the headline comes before its edges")
	if !w.saidAny("waiting-on edge: tk-a depends on tk-blk1") {
		t.Errorf("(EDGE) the edge is unsaid: %q", w.said)
	}
	w = newWorld(t)
	if code, _, _ := w.take(Request{Bead: "tk-a", Text: "no edges here"}); code != 0 || len(w.lines("DEP-ADD ")) != 0 {
		t.Errorf("(EDGENONE) a headline that names no wait exits %d and writes %q", code, w.lines("DEP-ADD "))
	}
}

// A bead never waits on itself: the wait is skipped and said (EDGESELF).
func TestABeadNeverWaitsOnItself(t *testing.T) {
	w := newWorld(t)
	if code, _, err := w.take(Request{Bead: "tk-a", Text: "self", WaitingOn: []string{"tk-a"}}); code != 0 {
		t.Fatalf("exits %d (%v)", code, err)
	}
	if n := len(w.lines("DEP-ADD ")); n != 0 || !w.saidAny("--waiting-on tk-a is the bead itself") {
		t.Errorf("(EDGESELF) %d edges, and the skip said %q", n, w.said)
	}
}

// An edge that does not land never costs the headline, which lands first, and
// fails the verb, so a caller that holds on the edge does not take the wait as
// wired. A bead the store does not hold takes no edge, since one onto it
// would hold nothing (EDGEFAIL).
func TestAnEdgeThatDoesNotLandFailsTheVerbAfterTheHeadline(t *testing.T) {
	w := newWorld(t)
	code, out, err := w.take(Request{Bead: "tk-a", Text: "held for review", WaitingOn: []string{"tk-nope"}})
	if code != 4 || out != "" {
		t.Fatalf("(EDGEFAIL) exits %d with %q, want 4", code, out)
	}
	if w.row("tk-a").Metadata["gc.takeaway"] != "held for review" {
		t.Error("(EDGEFAIL) the headline was lost with the edge")
	}
	if !w.saidAny("could not wire --waiting-on tk-nope") || !w.saidAny("gc bd dep add tk-a tk-nope -t blocks") {
		t.Errorf("(EDGEFAIL) the failed edge and its repair are unsaid: %q", w.said)
	}
	has(t, errText(err), "a --waiting-on edge on tk-a did not land", "(EDGEFAIL) the error")
	w = newWorld(t)
	task(w, "tk-blk1", nil)
	w.store.EdgeErr = errBroken
	if code, _, _ := w.take(Request{Bead: "tk-a", Text: "held", WaitingOn: []string{"tk-blk1"}}); code != 4 {
		t.Errorf("(EDGEFAIL) an edge the store refused exits %d, want 4", code)
	}
}

// A wait in another store is refused before anything is written: an id's
// prefix names its store, and bd stores an edge onto another store's bead
// without finding it, so the edge holds nothing (XSTORE).
func TestAWaitInAnotherStoreIsRefused(t *testing.T) {
	w := newWorld(t)
	code, _, err := w.take(Request{Bead: "tk-a", Text: "held for the other rig's fix", WaitingOn: []string{"gc-blk9"}})
	if code != 2 || len(w.log) != 0 {
		t.Fatalf("(XSTORE) exits %d with %q written, want 2 and nothing", code, w.log)
	}
	has(t, errText(err), "--waiting-on gc-blk9 lives in another store than tk-a", "(XSTORE) the refusal")
}

// A landed rider rode the bead's own branch and has put its work there, proven
// by a state a push precedes: it closed, the refinery holds it, or its PR waits
// on the pending record. The bead's own merge lands it, so it takes no edge,
// and a headline whose every wait is one takes the settled mark. A shared
// branch without that proof keeps its edge, and so does a wait on another
// branch, one with no branch, or any wait of a bead with no branch (EDGERIDE,
// EDGERECORD, EDGECLOSED, EDGEUNLANDED, EDGESEP, EDGENOBR, EDGENOSUBJ,
// EDGEMIX).
func TestALandedRiderTakesNoEdge(t *testing.T) {
	setup := func(t *testing.T) *world {
		w := newWorld(t)
		branch := map[string]string{"branch": "polecat/tk-a"}
		task(w, "tk-a", branch)
		w.put(fake.Bead{ID: "tk-w-handed", Title: "handed off", Status: "open", IssueType: "task", Assignee: "tk/gc-toolkit.refinery", Metadata: branch})
		task(w, "tk-w-rec", map[string]string{"branch": "polecat/tk-a", "merge_result": "pull_request_pending"})
		w.put(fake.Bead{ID: "tk-w-merged", Title: "merged", Status: "closed", IssueType: "task", Metadata: branch})
		w.put(fake.Bead{ID: "tk-w-pend", Title: "in flight", Status: "in_progress", IssueType: "task", Assignee: "polecat-2", Metadata: branch})
		task(w, "tk-w-diff", map[string]string{"branch": "polecat/tk-w-diff"})
		task(w, "tk-w-nobr", nil)
		return w
	}
	for _, c := range []struct {
		name, bead string
		waits      []string
		edges      []string
		settled    bool
	}{
		{"EDGERIDE", "tk-a", []string{"tk-w-handed"}, nil, true},
		{"EDGERECORD", "tk-a", []string{"tk-w-rec"}, nil, true},
		{"EDGECLOSED", "tk-a", []string{"tk-w-merged"}, nil, true},
		{"EDGEUNLANDED", "tk-a", []string{"tk-w-pend"}, []string{"tk-w-pend"}, false},
		{"EDGESEP", "tk-a", []string{"tk-w-diff"}, []string{"tk-w-diff"}, false},
		{"EDGENOBR", "tk-a", []string{"tk-w-nobr"}, []string{"tk-w-nobr"}, false},
		{"EDGENOSUBJ", "tk-b", []string{"tk-w-handed"}, []string{"tk-w-handed"}, false},
		{"EDGEMIX", "tk-a", []string{"tk-w-handed", "tk-w-diff"}, []string{"tk-w-diff"}, false},
	} {
		t.Run(c.name, func(t *testing.T) {
			w := setup(t)
			if code, _, err := w.take(Request{Bead: c.bead, Text: "routed", By: "converse", WaitingOn: c.waits}); code != 0 {
				t.Fatalf("exits %d (%v)", code, err)
			}
			var edges []string
			for _, l := range w.lines("DEP-ADD ") {
				edges = append(edges, strings.Fields(l)[2])
			}
			if !slices.Equal(edges, c.edges) {
				t.Errorf("the edges are onto %q, want %q", edges, c.edges)
			}
			mark := "--set-metadata gc.takeaway_settled= "
			if c.settled {
				mark = "--set-metadata gc.takeaway_settled=1"
			}
			has(t, w.update(c.bead)+" ", mark, "the settled mark")
			if len(c.edges) < len(c.waits) && !w.saidAny("is a landed rider on "+c.bead+"'s own branch") {
				t.Errorf("a rider's skip is unsaid: %q", w.said)
			}
		})
	}
}

// --no-wait is the writer's answer that nothing waits on the bead, stamped as
// gc.takeaway_settled=1 in the headline's own write. Every other headline
// writes it empty, so no earlier answer stands for a later headline, and
// --no-wait beside a named wait is refused before anything is written
// (SETTLED, UNSETTLED, BOTH).
func TestNoWaitIsTheSettledMark(t *testing.T) {
	w := newWorld(t)
	w.put(fake.Bead{ID: "tk-a", Title: "the bead", Status: "open", IssueType: "task", Metadata: map[string]string{"gc.takeaway_settled": "1"}})
	if code, _, _ := w.take(Request{Bead: "tk-a", Text: "resolved — the board was right", NoWait: true}); code != 0 {
		t.Fatal("(SETTLED) a --no-wait headline did not land")
	}
	has(t, w.update("tk-a"), "--set-metadata gc.takeaway_settled=1", "(SETTLED) the headline's write")
	w = newWorld(t)
	w.put(fake.Bead{ID: "tk-a", Title: "the bead", Status: "open", IssueType: "task", Metadata: map[string]string{"gc.takeaway_settled": "1"}})
	if code, _, _ := w.take(Request{Bead: "tk-a", Text: "holding — needs a ruling"}); code != 0 {
		t.Fatal("(UNSETTLED) a headline did not land")
	}
	if got := w.row("tk-a").Metadata["gc.takeaway_settled"]; got != "" {
		t.Errorf("(UNSETTLED) an earlier settled mark stood beside a later headline: %q", got)
	}
	w = newWorld(t)
	task(w, "tk-blk1", nil)
	code, _, err := w.take(Request{Bead: "tk-a", Text: "both", NoWait: true, WaitingOn: []string{"tk-blk1"}})
	if code != 2 || len(w.log) != 0 {
		t.Errorf("(BOTH) exits %d with %q written, want 2 and nothing", code, w.log)
	}
	has(t, errText(err), "contradicts", "(BOTH) the refusal")
}

// A release that parks a bead for a person states its disposition: a named
// wait, or --no-wait. A bead an open blocker already holds needs neither, since
// that edge is its wait. A park whose blockers do not read is refused, since no
// edge that holds it can be proven, and a bare headline parks nothing, so it
// needs neither (NEITHERPARK, NEITHERPROBE, DELEGBARE, NEITHERBARE).
func TestAParkForAPersonStatesItsDisposition(t *testing.T) {
	w := newWorld(t)
	code, _, err := w.take(Request{Bead: "tk-a", Text: "parked on prose alone", By: "proactive", Release: true})
	if code != 2 || len(w.log) != 0 {
		t.Errorf("(NEITHERPARK) exits %d with %q written, want 2 and nothing", code, w.log)
	}
	has(t, errText(err), "states its disposition", "(NEITHERPARK) the refusal")

	w = newWorld(t)
	w.store.BlockedErr = errBroken
	code, _, err = w.take(Request{Bead: "tk-a", Text: "parked, store silent", Release: true})
	if code != 2 || len(w.log) != 0 {
		t.Errorf("(NEITHERPROBE) exits %d with %q written, want 2 and nothing", code, w.log)
	}
	has(t, errText(err), "could not be read", "(NEITHERPROBE) the refusal")
	has(t, errText(err), "--waiting-on", "(NEITHERPROBE) the refusal names a disposition")

	w = newWorld(t)
	task(w, "tk-child", nil)
	w.blockOn("tk-a", "tk-child")
	if code, _, err := w.take(Request{Bead: "tk-a", Text: "ruled — the work is on the child", Release: true}); code != 0 {
		t.Errorf("(DELEGBARE) a release of a bead its open blocker holds exits %d (%v)", code, err)
	}

	w = newWorld(t)
	if code, _, err := w.take(Request{Bead: "tk-a", Text: "a headline beside a gate", By: "converse"}); code != 0 {
		t.Errorf("(NEITHERBARE) a bare headline exits %d (%v)", code, err)
	}
}

// A route promises a claim a pool can perform, so it is refused onto a bead
// whose work is on a blocker that is no human gate, naming each and the re-run.
// A human gate leaves the route honest, a closed blocker is no wait, and a
// waits-for edge of the bead's own is a wait the store cannot judge yet, so it
// refuses the route too. A blocker read that fails lets the route through and
// says so (DELEG, DELEGWHY, GATED, DELEGDONE, DELEGWAITS, DELEGPROBE).
func TestARouteOntoWorkOnABlockerIsRefused(t *testing.T) {
	w := newWorld(t)
	task(w, "tk-child", nil)
	w.put(fake.Bead{ID: "tk-gate", Title: "a plain gate", Status: "open", IssueType: "gate"})
	w.blockOn("tk-a", "tk-child", "tk-gate")
	code, _, err := w.take(Request{Bead: "tk-a", Text: "routed — the fix is slung", By: "converse", Release: true, Route: pool})
	if code != 2 || len(w.log) != 0 {
		t.Errorf("(DELEG) exits %d with %q written, want 2 and nothing", code, w.log)
	}
	for _, want := range []string{"tk-child", "tk-gate", "--release alone", "--then-route"} {
		has(t, errText(err), want, "(DELEGWHY) the refusal")
	}

	w = newWorld(t)
	w.put(fake.Bead{ID: "tk-hgate", Title: "a ruling", Status: "open", IssueType: "gate", AwaitType: "human"})
	w.blockOn("tk-a", "tk-hgate")
	if code, _, err := w.take(Request{Bead: "tk-a", Text: "actionable — the pool takes it once ruled", Release: true, Route: pool}); code != 0 || len(w.lines("SLING "+pool+" tk-a")) != 1 {
		t.Errorf("(GATED) a bead only a human gate holds exits %d (%v) with slings %q", code, err, w.lines("SLING "))
	}

	w = newWorld(t)
	w.put(fake.Bead{ID: "tk-done", Title: "done", Status: "closed", IssueType: "task"})
	w.blockOn("tk-a", "tk-done")
	if code, _, err := w.take(Request{Bead: "tk-a", Text: "actionable — nothing outstanding", Release: true, Route: pool}); code != 0 {
		t.Errorf("(DELEGDONE) a closed blocker refused the route: %d (%v)", code, err)
	}

	w = newWorld(t)
	task(w, "tk-spawn", nil)
	a := w.row("tk-a")
	a.Edges = append(a.Edges, gcbd.Edge{Type: gcbd.EdgeWaitsFor, ID: "tk-spawn", Title: "work tk-spawn", Status: "open", IssueType: "task"})
	w.put(a)
	code, _, err = w.take(Request{Bead: "tk-a", Text: "routed — it waits for its spawner", Release: true, Route: pool})
	if code != 2 || len(w.log) != 0 {
		t.Errorf("(DELEGWAITS) exits %d with %q written, want 2 and nothing", code, w.log)
	}
	has(t, errText(err), "tk-spawn", "(DELEGWAITS) the refusal names the spawner")

	w = newWorld(t)
	w.store.BlockedErr = errBroken
	if code, _, err := w.take(Request{Bead: "tk-a", Text: "actionable — routed", Release: true, Route: pool}); code != 0 || len(w.lines("SLING ")) != 1 {
		t.Errorf("(DELEGPROBE) an unread blocker read exits %d (%v)", code, err)
	}
	if !w.saidAny("could not read the blockers on tk-a") {
		t.Errorf("(DELEGPROBE) the unchecked route is unsaid: %q", w.said)
	}
}

// A wait the call names counts against a route as an edge the bead carries
// does, since the edges are written only after the release: one that is open
// and no human gate, or whose row does not read, refuses the route before
// anything is written. One onto a human gate or a closed bead still routes,
// and its edge lands (NAMEDWAIT).
func TestAWaitTheCallNamesCountsAgainstARoute(t *testing.T) {
	w := newWorld(t)
	task(w, "tk-w-open", nil)
	code, _, err := w.take(Request{Bead: "tk-a", Text: "routed — once its fix lands", Release: true, Route: pool, WaitingOn: []string{"tk-w-open"}})
	if code != 2 || len(w.log) != 0 {
		t.Errorf("(NAMEDWAIT) exits %d with %q written, want 2 and nothing", code, w.log)
	}
	has(t, errText(err), "whose --waiting-on names tk-w-open", "(NAMEDWAIT) the refusal")
	has(t, errText(err), "Re-run without --route", "(NAMEDWAIT) the re-run")

	w = newWorld(t)
	w.put(fake.Bead{ID: "tk-hgate", Title: "a ruling", Status: "open", IssueType: "gate", AwaitType: "human"})
	if code, _, err := w.take(Request{Bead: "tk-a", Text: "routed — the pool takes it once ruled", Release: true, Route: pool, WaitingOn: []string{"tk-hgate"}}); code != 0 {
		t.Fatalf("(NAMEDWAIT) a named human gate exits %d (%v)", code, err)
	}
	if len(w.lines("DEP-ADD tk-a tk-hgate ")) != 1 || len(w.lines("SLING ")) != 1 {
		t.Errorf("(NAMEDWAIT) a named human gate wrote %q", w.log)
	}

	w = newWorld(t)
	w.put(fake.Bead{ID: "tk-w-done", Title: "done", Status: "closed", IssueType: "task"})
	if code, _, err := w.take(Request{Bead: "tk-a", Text: "routed — its wait is done", Release: true, Route: pool, WaitingOn: []string{"tk-w-done"}}); code != 0 || len(w.lines("SLING ")) != 1 {
		t.Errorf("(NAMEDWAIT) a named closed wait exits %d (%v)", code, err)
	}

	w = newWorld(t)
	code, _, err = w.take(Request{Bead: "tk-a", Text: "routed", Release: true, Route: pool, WaitingOn: []string{"tk-w-gone"}})
	if code != 2 || len(w.log) != 0 {
		t.Errorf("(NAMEDWAIT) a named wait that does not read exits %d with %q written", code, w.log)
	}
	has(t, errText(err), "The row of tk-w-gone did not read", "(NAMEDWAIT) the refusal")
}

// A release to a named agent writes the agent as the assignee in the one
// guarded release write, with the route left empty, and says where the bead
// went. --assign rides a release and never beside a route, and a bead whose
// work is on a blocker is refused unless the call names its waits, which gate
// the hand-off (TOAGENT, TOAGENTOK, TOAGENTREL, TOAGENTBOTH, TOAGENTBLK,
// TOAGENTWAIT).
func TestAnAssignmentReleasesTheBeadToANamedAgent(t *testing.T) {
	const agent = "gc-toolkit.mechanik"
	w := newWorld(t)
	code, out, err := w.take(Request{Bead: "tk-a", Text: "actionable — a city.toml edit, mechanik's", Release: true, Assign: agent, NoWait: true})
	if code != 0 {
		t.Fatalf("(TOAGENTOK) exits %d (%v)", code, err)
	}
	up := w.update("tk-a")
	has(t, up, "--if-status=open --if-assignee= --status=open --assignee="+agent+" ", "(TOAGENT) the guarded release write")
	has(t, up, "--set-metadata gc.routed_to= ", "(TOAGENT) the route stays empty")
	if b := w.row("tk-a"); b.Assignee != agent || b.Status != "open" {
		t.Errorf("(TOAGENT) the bead reads %s under %q", b.Status, b.Assignee)
	}
	has(t, out, "[released to "+agent+"]", "(TOAGENTOK) the success line")

	for name, req := range map[string]Request{
		"TOAGENTREL":  {Bead: "tk-a", Text: "no release", Assign: agent},
		"TOAGENTBOTH": {Bead: "tk-a", Text: "both", Release: true, Route: pool, Assign: agent},
	} {
		w = newWorld(t)
		code, _, err := w.take(req)
		if code != 2 || len(w.log) != 0 {
			t.Errorf("(%s) exits %d with %q written, want 2 and nothing", name, code, w.log)
		}
		if name == "TOAGENTBOTH" {
			has(t, errText(err), "never both", "(TOAGENTBOTH) the refusal")
		}
	}

	w = newWorld(t)
	task(w, "tk-child", nil)
	w.blockOn("tk-a", "tk-child")
	code, _, err = w.take(Request{Bead: "tk-a", Text: "assigned — the fix is mechanik's", Release: true, Assign: agent, NoWait: true})
	if code != 2 || len(w.log) != 0 {
		t.Errorf("(TOAGENTBLK) exits %d with %q written, want 2 and nothing", code, w.log)
	}
	has(t, errText(err), "tk-child", "(TOAGENTBLK) the refusal names the blocker")
	has(t, errText(err), "--then-assign", "(TOAGENTBLK) and the arm that waits on it")

	w = newWorld(t)
	task(w, "tk-child", nil)
	w.blockOn("tk-a", "tk-child")
	if code, _, err := w.take(Request{Bead: "tk-a", Text: "held — mechanik edits once the child lands", Release: true, Assign: agent, WaitingOn: []string{"tk-child"}}); code != 0 {
		t.Fatalf("(TOAGENTWAIT) exits %d (%v)", code, err)
	}
	has(t, w.update("tk-a"), "--assignee="+agent, "(TOAGENTWAIT) the release write")
	if len(w.lines("DEP-ADD tk-a tk-child ")) != 1 {
		t.Errorf("(TOAGENTWAIT) the named wait took no edge: %q", w.log)
	}
}
