package arm_test

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"slices"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/arm"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	rtfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
)

// run runs one pass and returns each arm's line by its bead.
func (w *world) run(dry bool) (map[string]arm.Line, arm.Summary) {
	w.t.Helper()
	got := map[string]arm.Line{}
	sum, err := w.arms.StartArmed(arm.StartOptions{DryRun: dry, Rig: "rig"}, func(l arm.Line) {
		if _, twice := got[l.ID]; twice {
			w.t.Errorf("%s has two lines", l.ID)
		}
		got[l.ID] = l
	})
	if err != nil {
		w.t.Fatal(err)
	}
	return got, sum
}

// act checks one line's action and case, and that its why says says.
func act(t *testing.T, lines map[string]arm.Line, id, action, kase, says string) {
	t.Helper()
	l, ok := lines[id]
	switch {
	case !ok:
		t.Errorf("%s has no line", id)
	case l.Start.Action != action || l.Start.Case != kase:
		t.Errorf("%s: %s/%s (%s); want %s/%s", id, l.Start.Action, l.Start.Case, l.Start.Why, action, kase)
	case !strings.Contains(l.Start.Why, says):
		t.Errorf("%s: why = %q; want it to say %q", id, l.Start.Why, says)
	}
}

func (w *world) slungBeads() []string {
	var out []string
	for _, s := range w.rt.Slings() {
		out = append(out, s.Bead)
	}
	return out
}

func (w *world) attempts(id string) string {
	v, _ := w.meta(id, "gc.dispatch_when_ready_fail_count")
	return v
}

func blocks(id string) gcbd.Edge { return gcbd.Edge{Type: gcbd.EdgeBlocks, ID: id, Status: "open"} }

// An arm on a bead that has closed, or that carries a merge_result because
// another path delivered its work, retires whatever holds the bead: the arm
// is cleared with a note that names the case, and nothing is slung. A dry run
// reports each retire and writes nothing.
func TestStartRetiresTheArmOfAClosedOrDeliveredBead(t *testing.T) {
	w := newWorld(t)
	w.put(fake.Bead{ID: "closed", Status: "closed", Metadata: armedBead("mol-x", nil)})
	w.put(fake.Bead{ID: "pr", Metadata: armedBead("mol-polecat-work", map[string]string{"merge_result": "pull_request"})})
	w.put(fake.Bead{ID: "gate", Metadata: armedBead("mol-polecat-work", map[string]string{"merge_result": "pre_open_gate"})})
	w.put(fake.Bead{ID: "blocker"})
	w.put(fake.Bead{ID: "behind", Metadata: armedBead("mol-polecat-work", map[string]string{"merge_result": "pull_request"}),
		Edges: []gcbd.Edge{blocks("blocker")}})
	w.store.List("behind", "blocker")
	w.store.Mark("behind")
	w.store.MakeReady("pr", "gate")

	lines, _ := w.run(true)
	for _, id := range []string{"pr", "gate", "behind"} {
		act(t, lines, id, arm.ActRetire, "delivered", "merge_result=")
	}
	act(t, lines, "closed", arm.ActRetire, "closed", "closed with a dispatch still armed")
	if n := len(w.store.Writes()); n != 0 {
		t.Errorf("the dry run wrote %d times", n)
	}

	lines, sum := w.run(false)
	act(t, lines, "pr", arm.ActRetire, "delivered", "merge_result=pull_request")
	act(t, lines, "gate", arm.ActRetire, "delivered", "merge_result=pre_open_gate")
	act(t, lines, "behind", arm.ActRetire, "delivered", "merge_result=pull_request")
	act(t, lines, "closed", arm.ActRetire, "closed", "none is owed")
	for _, id := range []string{"closed", "pr", "gate", "behind"} {
		if w.armed(id) {
			t.Errorf("%s is still armed", id)
		}
	}
	if n := w.notes("gate"); !strings.Contains(n, "deferred-dispatch: dispatch record cleared at 2026-11-13T12:00:00Z: another path already delivered its work (merge_result=pre_open_gate)") {
		t.Errorf("gate's note = %q", n)
	}
	if s := w.rt.Slings(); len(s) != 0 {
		t.Errorf("slung %v", s)
	}
	if sum[arm.ActRetire] != 4 || sum.Failed() != 0 {
		t.Errorf("summary = %v", sum)
	}
}

// A ready arm nothing holds is slung once, on its formula, with the arm's
// token in its root's title, after its attempt is counted in a write of its
// own, and its arm is cleared once the sling exits 0.
func TestStartSlingsAReadyArmOnce(t *testing.T) {
	w := newWorld(t)
	w.put(fake.Bead{ID: "b", Metadata: armedBead("mol-x", nil)})
	w.store.MakeReady("b")
	lines, sum := w.run(false)
	act(t, lines, "b", arm.ActStart, "", "dispatched to "+pool+" on mol-x")
	want := []gascity.Sling{{Rig: "rig", Target: pool, Bead: "b", Formula: "mol-x", Title: "mol-x arm:b@" + armedAt}}
	if got := w.rt.Slings(); !reflect.DeepEqual(got, want) {
		t.Errorf("slings = %+v, want %+v", got, want)
	}
	writes := w.store.Writes()
	if len(writes) != 2 || !slices.Contains(writes[0].Args, "gc.dispatch_when_ready_fail_count=1") || !slices.Contains(writes[1].Args, "--append-notes") {
		t.Errorf("writes = %+v; want the attempt counted, then the arm cleared with its note", writes)
	}
	if w.armed("b") {
		t.Error("the arm survived its sling")
	}
	if sum[arm.ActStart] != 1 {
		t.Errorf("summary = %v", sum)
	}
	lines, _ = w.run(false)
	if len(lines) != 0 || len(w.rt.Slings()) != 1 {
		t.Errorf("a second pass read %d arms and slung %d times; want none and one", len(lines), len(w.rt.Slings()))
	}
}

// An arm that names no formula pours its target's default, named in the sling
// so its root carries the token.
func TestStartPoursTheTargetsDefaultFormula(t *testing.T) {
	w := newWorld(t)
	w.put(fake.Bead{ID: "b", Metadata: armedBead("", nil)})
	w.store.MakeReady("b")
	w.run(false)
	if s := w.rt.Slings(); len(s) != 1 || s[0].Formula != "mol-polecat-work" || s[0].Title != "mol-polecat-work arm:b@"+armedAt {
		t.Errorf("slings = %+v", s)
	}
}

// An arm that names no formula, for a target whose agent names no default of
// its own, pours the one its pack gives it, asked about the bead through the
// rig the pass slings with.
func TestStartPoursThePacksDefaultFormula(t *testing.T) {
	w := newWorld(t)
	const inherits = "rig/rig.inherits"
	w.rt.PackFormulas = map[string]string{inherits: "mol-pack"}
	w.put(fake.Bead{ID: "b", Metadata: armedBead("", map[string]string{"gc.dispatch_when_ready": inherits})})
	w.store.MakeReady("b")
	lines, _ := w.run(false)
	act(t, lines, "b", arm.ActStart, "", "on mol-pack")
	if s := w.rt.Slings(); len(s) != 1 || s[0].Formula != "mol-pack" || s[0].Title != "mol-pack arm:b@"+armedAt {
		t.Errorf("slings = %+v", s)
	}
	if got, want := w.rt.Asks(), []gascity.Sling{{Rig: "rig", Target: inherits, Bead: "b"}}; !reflect.DeepEqual(got, want) {
		t.Errorf("asks = %+v, want %+v", got, want)
	}
}

// The start sends only what the pool's own serve rule would serve, bd's ready
// read with its flags, and holds back what bd cannot judge: a waits-for edge of
// the bead's own and a wait edge into another store. It holds a hold label in
// any spelling, an assignee, a status other than open and an epic, and a bead
// bd does not report ready. Each arm stays, and the start names what holds it.
func TestStartHoldsWhatHoldsTheBead(t *testing.T) {
	w := newWorld(t)
	w.put(fake.Bead{ID: "blocker", Title: "the base"})
	w.put(fake.Bead{ID: "blocked", Metadata: armedBead("mol-x", nil), Edges: []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "blocker", Status: "open", Title: "the base"}}})
	w.store.List("blocked", "blocker")
	w.put(fake.Bead{ID: "park", Title: "the park"})
	w.put(fake.Bead{ID: "epic", IssueType: "epic", Edges: []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "park", Status: "open", Title: "the park"}}})
	w.store.List("epic", "park")
	w.put(fake.Bead{ID: "parked", Metadata: armedBead("mol-x", nil), Edges: []gcbd.Edge{{Type: gcbd.EdgeParentChild, ID: "epic", Status: "open"}}})
	w.store.List("parked", "epic")
	w.store.Mark("blocked", "epic", "parked")
	w.put(fake.Bead{ID: "spawner"})
	w.put(fake.Bead{ID: "unjudged", Metadata: armedBead("mol-x", nil), Edges: []gcbd.Edge{{Type: gcbd.EdgeWaitsFor, ID: "spawner", Status: "open"}}})
	w.put(fake.Bead{ID: "foreign", Metadata: armedBead("mol-x", nil), Edges: []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "xx-1"}}})
	w.put(fake.Bead{ID: "label", Metadata: armedBead("mol-x", nil), Labels: []string{" Hold:Mayor "}})
	w.put(fake.Bead{ID: "human", Metadata: armedBead("mol-x", nil), Labels: []string{"human"}})
	w.put(fake.Bead{ID: "assigned", Metadata: armedBead("mol-x", nil), Assignee: "rig/mechanik"})
	w.put(fake.Bead{ID: "deferred", Status: "deferred", Metadata: armedBead("mol-x", nil)})
	w.put(fake.Bead{ID: "an-epic", IssueType: "epic", Metadata: armedBead("mol-x", nil)})
	w.put(fake.Bead{ID: "unready", Metadata: armedBead("mol-x", nil)})
	w.store.MakeReady("unjudged", "foreign", "label", "human", "assigned", "an-epic")

	lines, sum := w.run(false)
	act(t, lines, "blocked", arm.ActHold, "blocked", `blocker "the base" holds it`)
	act(t, lines, "parked", arm.ActHold, "held", "park \"the park\" on its ancestor epic holds it")
	act(t, lines, "unjudged", arm.ActHold, "unjudged", "spawner")
	act(t, lines, "foreign", arm.ActHold, "foreign", "xx-1")
	act(t, lines, "label", arm.ActHold, "label", "Hold:Mayor")
	act(t, lines, "human", arm.ActHold, "label", "human")
	act(t, lines, "assigned", arm.ActHold, "assigned", "rig/mechanik")
	act(t, lines, "deferred", arm.ActHold, "status", "status deferred")
	act(t, lines, "an-epic", arm.ActHold, "epic", "an epic")
	act(t, lines, "unready", arm.ActHold, "unready", "bd does not report it ready")
	if s := w.rt.Slings(); len(s) != 0 {
		t.Errorf("slung %v", s)
	}
	if n := len(w.store.Writes()); n != 0 {
		t.Errorf("%d writes; a held arm takes none", n)
	}
	if sum[arm.ActHold] != 10 || sum.Failed() != 0 {
		t.Errorf("summary = %v", sum)
	}
}

// An arm that does not decode is reported in words, and nothing is slung on
// it: the pass fails, so the order's failure keeps its output.
func TestStartReportsAMalformedArm(t *testing.T) {
	w := newWorld(t)
	w.put(fake.Bead{ID: "b", Metadata: armedBead("", map[string]string{"gc.dispatch_when_ready_args": `["--merge","mr"]`})})
	w.store.MakeReady("b")
	lines, sum := w.run(false)
	act(t, lines, "b", arm.ActFail, "malformed", "name no formula alone")
	if len(w.rt.Slings()) != 0 || sum.Failed() != 1 || !w.armed("b") {
		t.Errorf("slings %v, summary %v, armed %v", w.rt.Slings(), sum, w.armed("b"))
	}
}

// The start reads the bead once more, under its lock, before its sling: an arm
// removed since the pass's listing is not sent, a hold label set since keeps
// the arm with no attempt counted, and a bead that closed since has its arm
// retired.
func TestStartReadsTheArmAgainBeforeItsSling(t *testing.T) {
	w := newWorld(t)
	for _, id := range []string{"withdrawn", "labelled", "closed"} {
		w.put(fake.Bead{ID: id, Metadata: armedBead("mol-x", nil)})
	}
	w.store.MakeReady("withdrawn", "labelled", "closed")
	// The start holds a bead's lock only for the steps it takes on that bead,
	// so a read made while the lock file exists is its read before the sling.
	w.store.OnFind = func(q gcbd.Query) {
		if len(q.IDs) != 1 {
			return
		}
		id := q.IDs[0]
		if _, err := os.Stat(filepath.Join(w.arms.Locks, "dispatch-"+id+".lock")); err != nil {
			return
		}
		row, _ := w.store.Row(id)
		switch id {
		case "withdrawn":
			row.Metadata = nil
		case "labelled":
			row.Labels = []string{"hold:mayor"}
		case "closed":
			row.Status = "closed"
		}
		w.store.Put(row)
	}
	lines, _ := w.run(false)
	act(t, lines, "withdrawn", arm.ActWithdrawn, "", "removed after this pass listed it")
	act(t, lines, "labelled", arm.ActHold, "label", "a read after this pass listed it found")
	act(t, lines, "closed", arm.ActRetire, "closed", "none is owed")
	if s := w.rt.Slings(); len(s) != 0 {
		t.Errorf("slung %v", s)
	}
	if !w.armed("labelled") || w.attempts("labelled") != "" {
		t.Errorf("the labelled arm: armed %v, attempts %q; want armed with none counted", w.armed("labelled"), w.attempts("labelled"))
	}
	if w.armed("closed") {
		t.Error("the closed bead kept its arm")
	}
}

// An arm removed between the pass's listing and its read of what holds the
// bead, as a stop that lands mid-pass removes it, is reported withdrawn, held or
// not, and nothing is sent.
func TestStartReportsAnArmRemovedBeforeItsHoldsRead(t *testing.T) {
	w := newWorld(t)
	w.put(fake.Bead{ID: "ready", Metadata: armedBead("mol-x", nil)})
	w.put(fake.Bead{ID: "held", Metadata: armedBead("mol-x", nil)})
	w.store.MakeReady("ready")
	w.store.OnFind = func(q gcbd.Query) {
		for _, id := range q.IDs {
			row, _ := w.store.Row(id)
			row.Metadata = nil
			w.store.Put(row)
		}
	}
	lines, sum := w.run(false)
	for _, id := range []string{"ready", "held"} {
		act(t, lines, id, arm.ActWithdrawn, "", "removed after this pass listed it")
	}
	if s := w.rt.Slings(); len(s) != 0 || sum.Failed() != 0 {
		t.Errorf("slung %v, summary %v", s, sum)
	}
}

// A sling that fails keeps the arm with its attempt counted, and fails the
// pass, so the next pass tries again.
func TestStartKeepsTheArmWhenTheSlingFails(t *testing.T) {
	w := newWorld(t)
	w.put(fake.Bead{ID: "b", Metadata: armedBead("mol-x", nil)})
	w.store.MakeReady("b")
	w.rt.OnSling = func(gascity.Sling) gascity.SlingResult {
		return gascity.SlingResult{Result: gascity.Result{Code: 1, Output: "gc sling: the target refused the pour\n"}}
	}
	lines, sum := w.run(false)
	act(t, lines, "b", arm.ActFail, "sling", "the target refused the pour")
	if !w.armed("b") || w.attempts("b") != "1" || sum.Failed() != 1 {
		t.Errorf("armed %v, attempts %q, summary %v; want armed with one attempt and a failed pass", w.armed("b"), w.attempts("b"), sum)
	}
}

// exit3 has gc sling answer exit 3, naming live as the bead's live workflows.
func exit3(live ...string) func(gascity.Sling) gascity.SlingResult {
	return func(s gascity.Sling) gascity.SlingResult {
		return gascity.SlingResult{Result: gascity.Result{Code: 3}, Live: live}
	}
}

// gc sling exits 3 only when a live workflow works the bead already, naming
// each. One that is not an unfinished pour means the work is sent, so the arm
// retires. When each is an unfinished pour, none of them can finish, so the arm
// stays and a person is asked, naming each root and the command that closes it.
// A named root the store does not hold leaves the arm for the next pass.
func TestStartReadsExit3(t *testing.T) {
	for _, tc := range []struct {
		name   string
		live   []string
		roots  []fake.Bead
		action string
		kase   string
		says   string
	}{
		{name: "a live workflow that is working", live: []string{"r1"},
			roots:  []fake.Bead{{ID: "r1", Status: "open"}},
			action: arm.ActSent, says: "gc sling found r1 working it already"},
		{name: "a root that failed part way", live: []string{"r1"},
			roots:  []fake.Bead{{ID: "r1", Status: "open", IssueType: "gate", Metadata: map[string]string{"molecule_failed": "true"}}},
			action: arm.ActAsk, kase: "unfinished", says: "r1 (it carries molecule_failed=true)"},
		{name: "a root still fenced", live: []string{"r1"},
			roots:  []fake.Bead{{ID: "r1", Status: "open", IssueType: "gate", Metadata: map[string]string{"gc.instantiating": "true"}}},
			action: arm.ActAsk, kase: "unfinished", says: "still fenced"},
		{name: "a root activated over a fenced step", live: []string{"r1"},
			roots: []fake.Bead{{ID: "r1", Status: "open"},
				{ID: "r1.s", Status: "open", IssueType: "gate", Metadata: map[string]string{"gc.root_bead_id": "r1", "gc.instantiating": "true"}}},
			action: arm.ActAsk, kase: "unfinished", says: "fences r1.s under it"},
		{name: "an unfinished pour beside a working one", live: []string{"r1", "r2"},
			roots: []fake.Bead{{ID: "r1", Status: "open", Metadata: map[string]string{"molecule_failed": "true"}},
				{ID: "r2", Status: "open"}},
			action: arm.ActSent, says: "found r2 working it"},
		{name: "a root the store does not hold", live: []string{"r9"},
			action: arm.ActFail, kase: "read", says: "this store does not hold"},
		{name: "an exit 3 that names no workflow",
			action: arm.ActFail, kase: "sling", says: "named no live workflow"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			w := newWorld(t)
			w.put(fake.Bead{ID: "b", Metadata: armedBead("mol-x", nil)})
			for _, r := range tc.roots {
				w.put(r)
			}
			w.store.MakeReady("b")
			w.rt.OnSling = exit3(tc.live...)
			lines, _ := w.run(false)
			act(t, lines, "b", tc.action, tc.kase, tc.says)
			if got, want := w.armed("b"), tc.action != arm.ActSent; got != want {
				t.Errorf("armed = %v, want %v", got, want)
			}
			asks := w.rt.Scripts()
			if tc.action == arm.ActAsk {
				if len(asks) != 1 || asks[0].Name != "human-gate.sh" || !slices.Contains(asks[0].Args, "deferred-dispatch-sling-failed.b") ||
					!strings.Contains(strings.Join(asks[0].Args, " "), "gc convoy delete r1 --force") {
					t.Errorf("asks = %+v; want one gate naming the root and its close", asks)
				}
			} else if len(asks) != 0 {
				t.Errorf("asked %+v", asks)
			}
		})
	}
}

// After an earlier attempt the start first searches the arm's token. A root
// found there that is not an unfinished pour means that attempt landed,
// whichever formula it poured, so the arm retires with no sling. An open
// unfinished pour there keeps the arm and asks a person. A closed unfinished
// pour holds nothing back, so the retry slings. A failure stamp under a root
// does not make the root's own pour unfinished.
func TestStartFindsAnEarlierAttemptByItsToken(t *testing.T) {
	token := "arm:b@" + armedAt
	for _, tc := range []struct {
		name   string
		roots  []fake.Bead
		action string
		kase   string
		slung  bool
	}{
		{name: "a root of another formula that landed",
			roots:  []fake.Bead{{ID: "r1", Status: "closed", Title: "mol-other " + token}},
			action: arm.ActSent},
		{name: "an open root that failed part way",
			roots:  []fake.Bead{{ID: "r1", Status: "open", IssueType: "gate", Title: "mol-x " + token, Metadata: map[string]string{"molecule_failed": "true"}}},
			action: arm.ActAsk, kase: "unfinished"},
		{name: "an open root still fenced",
			roots:  []fake.Bead{{ID: "r1", Status: "open", IssueType: "gate", Title: "mol-x " + token, Metadata: map[string]string{"gc.instantiating": "true"}}},
			action: arm.ActAsk, kase: "unfinished"},
		{name: "an open root over a step still fenced",
			roots: []fake.Bead{{ID: "r1", Status: "open", Title: "mol-x " + token},
				{ID: "r1.s", Status: "open", IssueType: "gate", Metadata: map[string]string{"gc.root_bead_id": "r1", "gc.instantiating": "true"}}},
			action: arm.ActAsk, kase: "unfinished"},
		{name: "a closed root that failed part way",
			roots:  []fake.Bead{{ID: "r1", Status: "closed", IssueType: "gate", Title: "mol-x " + token, Metadata: map[string]string{"molecule_failed": "true"}}},
			action: arm.ActStart, slung: true},
		{name: "a closed root over a step still fenced",
			roots: []fake.Bead{{ID: "r1", Status: "closed", Title: "mol-x " + token},
				{ID: "r1.s", Status: "open", IssueType: "gate", Metadata: map[string]string{"gc.root_bead_id": "r1", "gc.instantiating": "true"}}},
			action: arm.ActStart, slung: true},
		{name: "a root whose only marked bead under it failed",
			roots: []fake.Bead{{ID: "r1", Status: "open", Title: "mol-x " + token},
				{ID: "r1.f", Status: "open", Metadata: map[string]string{"gc.root_bead_id": "r1", "molecule_failed": "true"}}},
			action: arm.ActSent},
		{name: "a root of another arm on the bead",
			roots:  []fake.Bead{{ID: "r1", Status: "closed", Title: "mol-x arm:b@2026-11-01T00:00:00Z"}},
			action: arm.ActStart, slung: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			w := newWorld(t)
			w.put(fake.Bead{ID: "b", Metadata: armedBead("mol-x", map[string]string{"gc.dispatch_when_ready_fail_count": "1"})})
			for _, r := range tc.roots {
				w.put(r)
			}
			w.store.MakeReady("b")
			lines, _ := w.run(false)
			act(t, lines, "b", tc.action, tc.kase, "")
			if got := len(w.rt.Slings()) > 0; got != tc.slung {
				t.Errorf("slung = %v, want %v", got, tc.slung)
			}
			if tc.slung && w.attempts("b") != "" {
				t.Errorf("a landed retry left attempts %q", w.attempts("b"))
			}
			if tc.action == arm.ActAsk && (!w.armed("b") || w.attempts("b") != "1") {
				t.Errorf("an ask left armed %v, attempts %q; want the arm as it was", w.armed("b"), w.attempts("b"))
			}
		})
	}
	// A first attempt searches no token.
	w := newWorld(t)
	w.put(fake.Bead{ID: "b", Metadata: armedBead("mol-x", nil)})
	w.store.MakeReady("b")
	w.run(false)
	for _, q := range w.store.Finds() {
		if q.TitleContains != "" {
			t.Errorf("a first attempt searched %q", q.TitleContains)
		}
	}
}

// At the cap the start asks a person instead of slinging: a human gate on the
// bead under the arm's key with a day's quiet window, or a conversation through
// gc-helm.sh when the bead has an open child. The arm stays. An ask that does
// not reach a person fails the pass, and the next pass asks again.
func TestStartAsksAPersonAtTheCap(t *testing.T) {
	w := newWorld(t)
	capped := armedBead("mol-x", map[string]string{"gc.dispatch_when_ready_fail_count": "3"})
	w.put(fake.Bead{ID: "b", Metadata: capped})
	w.put(fake.Bead{ID: "parent", Metadata: capped})
	w.put(fake.Bead{ID: "kid", Edges: []gcbd.Edge{{Type: gcbd.EdgeParentChild, ID: "parent", Status: "open"}}})
	w.store.MakeReady("b", "parent")
	lines, sum := w.run(false)
	act(t, lines, "b", arm.ActAsk, "cap", "3 attempts have reached the cap of 3")
	act(t, lines, "parent", arm.ActAsk, "cap", "")
	if len(w.rt.Slings()) != 0 || !w.armed("b") || !w.armed("parent") || sum.Failed() != 0 {
		t.Errorf("slings %v, armed %v %v, summary %v", w.rt.Slings(), w.armed("b"), w.armed("parent"), sum)
	}
	asks := w.rt.Scripts()
	if len(asks) != 2 {
		t.Fatalf("asks = %+v", asks)
	}
	gate, convo := asks[0], asks[1]
	if gate.Name != "human-gate.sh" || !slices.Equal(gate.Args[:6], []string{"--subject", "b", "--key", "deferred-dispatch-sling-failed.b", "--quiet-window", "86400"}) ||
		!strings.Contains(gate.Args[7], "gctk bead disarm b") || !strings.Contains(gate.Args[7], "Then clear this gate") {
		t.Errorf("gate = %+v", gate)
	}
	if convo.Name != "gc-helm.sh" || convo.Args[0] != "open" || convo.Args[1] != "parent" || convo.Args[2] != "--reason" {
		t.Errorf("conversation = %+v", convo)
	}

	w.rt.OnScript = func(rtfake.Call) gascity.Result {
		return gascity.Result{Code: 1, Output: "human-gate.sh: the store refused it\n"}
	}
	lines, sum = w.run(false)
	act(t, lines, "b", arm.ActFail, "ask", "the store refused it")
	if sum.Failed() == 0 || !w.armed("b") {
		t.Errorf("summary %v, armed %v; want a failed pass and the arm kept", sum, w.armed("b"))
	}
}

// The start begins no sling once less than one sling's allowance is left before
// its deadline, and leaves the rest armed for the next pass, untouched.
func TestStartLeavesWhatItCannotFinishBeforeItsDeadline(t *testing.T) {
	w := newWorld(t)
	for _, id := range []string{"b1", "b2", "b3"} {
		w.put(fake.Bead{ID: id, Metadata: armedBead("mol-x", nil)})
	}
	w.store.MakeReady("b1", "b2", "b3")
	w.rt.OnSling = func(gascity.Sling) gascity.SlingResult {
		w.now = w.now.Add(4 * time.Minute)
		return gascity.SlingResult{}
	}
	lines, sum := w.run(false)
	act(t, lines, "b1", arm.ActStart, "", "")
	act(t, lines, "b2", arm.ActStart, "", "")
	act(t, lines, "b3", arm.ActLeave, "deadline", "next pass")
	if !w.armed("b3") || w.attempts("b3") != "" || sum.Failed() != 0 {
		t.Errorf("b3: armed %v, attempts %q, summary %v; want it left untouched", w.armed("b3"), w.attempts("b3"), sum)
	}
}

// A dry run says what a pass would do with each arm, and writes, slings and asks
// nothing, nor takes a lock.
func TestADryRunWritesSlingsAndAsksNothing(t *testing.T) {
	w := newWorld(t)
	w.put(fake.Bead{ID: "closed", Status: "closed", Metadata: armedBead("mol-x", nil)})
	w.put(fake.Bead{ID: "ready", Metadata: armedBead("", nil)})
	w.put(fake.Bead{ID: "capped", Metadata: armedBead("mol-x", map[string]string{"gc.dispatch_when_ready_fail_count": "3"})})
	w.put(fake.Bead{ID: "landed", Metadata: armedBead("mol-x", map[string]string{"gc.dispatch_when_ready_fail_count": "1"})})
	w.put(fake.Bead{ID: "r1", Status: "closed", Title: "mol-x arm:landed@" + armedAt})
	w.store.MakeReady("ready", "capped", "landed")
	if err := os.Chmod(w.arms.Locks, 0o500); err != nil {
		t.Fatal(err)
	}
	defer os.Chmod(w.arms.Locks, 0o700)
	lines, sum := w.run(true)
	act(t, lines, "closed", arm.ActRetire, "closed", "")
	act(t, lines, "ready", arm.ActStart, "", "on mol-polecat-work")
	act(t, lines, "capped", arm.ActAsk, "cap", "")
	act(t, lines, "landed", arm.ActSent, "", "r1 landed")
	if len(w.store.Writes()) != 0 || len(w.rt.Slings()) != 0 || len(w.rt.Scripts()) != 0 || sum.Failed() != 0 {
		t.Errorf("writes %v, slings %v, asks %v, summary %v", w.store.Writes(), w.rt.Slings(), w.rt.Scripts(), sum)
	}
}

// A listing that cannot be read is no empty queue, and a store with no arm
// reads none.
func TestStartListing(t *testing.T) {
	w := newWorld(t)
	if lines, sum := w.run(false); len(lines) != 0 || len(sum) != 0 {
		t.Errorf("a store with no arm = %v, %v", lines, sum)
	}
	w.store.FindErr = &gcbd.ReadError{Reason: "the store is down"}
	_, err := w.arms.StartArmed(arm.StartOptions{}, func(arm.Line) {})
	if !errors.Is(err, arm.ErrListing) {
		t.Errorf("an unreadable listing = %v; want ErrListing", err)
	}
}

// A read of what holds the arms, or of bd's ready set, that fails sends nothing
// and fails the pass, while the retires still run.
func TestStartWithAReadThatFails(t *testing.T) {
	w := newWorld(t)
	w.put(fake.Bead{ID: "b", Metadata: armedBead("mol-x", nil)})
	w.put(fake.Bead{ID: "closed", Status: "closed", Metadata: armedBead("mol-x", nil)})
	w.store.MakeReady("b")
	w.store.ReadyErr = &gcbd.ReadError{Reason: "bd ready failed"}
	lines, sum := w.run(false)
	act(t, lines, "b", arm.ActFail, "read", "bd ready failed")
	act(t, lines, "closed", arm.ActRetire, "closed", "")
	w.store.ReadyErr = nil
	w.store.BlockedErr = &gcbd.ReadError{Reason: "bd blocked failed"}
	w.put(fake.Bead{ID: "closed", Status: "closed", Metadata: armedBead("mol-x", nil)})
	lines, _ = w.run(false)
	act(t, lines, "b", arm.ActFail, "read", "bd blocked failed")
	act(t, lines, "closed", arm.ActRetire, "closed", "")
	if len(w.rt.Slings()) != 0 || sum.Failed() != 1 || !w.armed("b") {
		t.Errorf("slings %v, summary %v, armed %v", w.rt.Slings(), sum, w.armed("b"))
	}
	if l := lines["b"]; l.Holds != nil || l.Error == "" || l.Arm == nil {
		t.Errorf("the line of a bead the holds read could not answer = %+v; want its error and its arm", l)
	}
}

// A bead whose dispatch lock another call holds is left for the next pass.
func TestStartLeavesABeadAnotherCallHoldsLocked(t *testing.T) {
	w := newWorld(t)
	w.put(fake.Bead{ID: "b", Metadata: armedBead("mol-x", nil)})
	w.store.MakeReady("b")
	f, err := os.OpenFile(filepath.Join(w.arms.Locks, "dispatch-b.lock"), os.O_RDWR|os.O_CREATE, 0o644)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		t.Fatal(err)
	}
	lines, _ := w.run(false)
	act(t, lines, "b", arm.ActLeave, "locked", "next pass")
	if len(w.rt.Slings()) != 0 || !w.armed("b") {
		t.Errorf("slings %v, armed %v", w.rt.Slings(), w.armed("b"))
	}
}

// A line prints what gctk bead holds answers, with "start" added, and a bead
// the read could not answer prints its error and its arm.
func TestALinePrintsTheHoldsAnswerAndTheStart(t *testing.T) {
	w := newWorld(t)
	w.put(fake.Bead{ID: "b", Metadata: armedBead("mol-x", nil)})
	lines, _ := w.run(true)
	raw, err := json.Marshal(lines["b"])
	if err != nil {
		t.Fatal(err)
	}
	var got map[string]any
	if err := json.Unmarshal(raw, &got); err != nil {
		t.Fatal(err)
	}
	for _, k := range []string{"id", "status", "waits", "pending", "last_landed", "in_flight", "arm", "foreign", "start"} {
		if _, ok := got[k]; !ok {
			t.Errorf("the line %s has no %q", raw, k)
		}
	}
	if !strings.HasPrefix(string(raw), `{"id":"b","status":"clear"`) {
		t.Errorf("the line %s does not open as gctk bead holds' answer", raw)
	}
	failed, err := json.Marshal(arm.Line{ID: "x", Error: "the read failed", Start: arm.Act{Action: arm.ActFail, Case: "read", Why: "w"}})
	if err != nil || string(failed) != `{"id":"x","error":"the read failed","arm":null,"start":{"action":"fail","case":"read","why":"w"}}` {
		t.Errorf("a failed line = %s, %v", failed, err)
	}
}
