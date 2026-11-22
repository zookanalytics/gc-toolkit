package reaction

import (
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// wantSling fails the test unless a sling or a check came to code, saying
// text, with nothing slung unless it slung.
func (w *world) wantSling(code int, why string, got int, said, what string) {
	w.t.Helper()
	if got != code || !strings.Contains(said, why) {
		w.t.Errorf("%s: exit %d saying %q; want %d saying %q", what, got, said, code, why)
	}
	if n := len(w.slings()); (code == 0) != (n > 0) && !strings.HasPrefix(what, "(CHECK") {
		w.t.Errorf("%s: %d sling(s) for exit %d", what, n, code)
	}
}

// A bead nobody has decided on is slung as a run of mol-first-reaction at the
// rig's proactive pool, under the rig.
func TestASlingOfABeadNobodyDecidedOnSlingsAReaction(t *testing.T) {
	w := newWorld(t)
	w.put(input("tk-plain", nil))
	code, said := w.sling("tk-plain")
	w.wantSling(0, "", code, said, "(SLING-GO)")
	w.has("SLING gc-toolkit/gc-toolkit.proactive tk-plain --on mol-first-reaction --rig gc-toolkit", "(SLING-GO) as a run of the formula at the rig's proactive pool")
	w.saidHas("slung a first reaction on tk-plain", "(SLING-GO) saying so")
}

// A bead its store does not hold, or a row that does not read, decides
// nothing: the sling fails, and nothing is slung.
func TestABeadTheStoreDoesNotHoldIsAnErrorNotARefusal(t *testing.T) {
	w := newWorld(t)
	code, said := w.sling("tk-nosuch")
	w.wantSling(1, "could not read tk-nosuch's own row: its store does not hold it", code, said, "(SUBJECT-ABSENT)")
	w.put(input("tk-plain", nil))
	w.store.FindErr = errors.New("gc bd list exited 1: database is locked")
	code, said = w.sling("tk-plain")
	w.wantSling(1, "could not read tk-plain's own row (gc bd list exited 1", code, said, "(SUBJECT-READS)")
}

// A standing record and a feedback pattern take no first reaction in any
// state, so each is refused with 6, naming its kind.
func TestAKindThatTakesNoReactionIsRefusedWithSix(t *testing.T) {
	for _, kind := range append(slices.Clone(standingKinds), feedbackPattern) {
		w := newWorld(t)
		w.put(input("tk-kind", func(b *fake.Bead) { b.Metadata["task_kind"] = kind }))
		code, said := w.sling("tk-kind")
		why := "it is a standing record (task_kind=" + kind + ")"
		if kind == feedbackPattern {
			why = "it is a feedback pattern, which the feedback distiller dispatches"
		}
		w.wantSling(Excluded, why, code, said, "(KIND-SKIP) "+kind)
	}
	if len(standingKinds) == 0 {
		t.Error("(KIND) the domain names no standing kind")
	}
}

// The standing kinds are the ones assets/scripts/standing-kinds.sh defines, as
// jq reads its definition, so a kind added there fails this test until the Go
// copy names it too.
func TestTheStandingKindsAreTheOnesTheScriptsDefine(t *testing.T) {
	lib, err := filepath.Abs("../../../assets/scripts/standing-kinds.sh")
	if err != nil {
		t.Fatal(err)
	}
	text, err := os.ReadFile(lib)
	if err != nil {
		t.Fatalf("standing-kinds.sh is not in this checkout: %v", err)
	}
	_, rest, ok := strings.Cut(string(text), "STANDING_KINDS_JQ='")
	defs, _, closed := strings.Cut(rest, "'")
	if !ok || !closed {
		t.Fatal("standing-kinds.sh holds no STANDING_KINDS_JQ definition")
	}
	out, err := exec.Command("jq", "-nc", defs+" standing_kinds").Output()
	if err != nil {
		t.Fatalf("jq over standing-kinds.sh's standing_kinds: %v", err)
	}
	var shell []string
	if err := json.Unmarshal(out, &shell); err != nil {
		t.Fatalf("jq answered %q for standing_kinds: %v", out, err)
	}
	slices.Sort(shell)
	if got := slices.Sorted(slices.Values(standingKinds)); !slices.Equal(got, shell) {
		t.Errorf("(KIND-SHARED) standingKinds names %q; standing-kinds.sh defines %q", got, shell)
	}
}

// A bead whose next move is decided already is refused with 5: a status other
// than open, an assignee, a route, the human park route among them, an arm, a
// capped one included, and a dispatch hold in any case, named as the bead
// spells it. The kind is read first.
func TestADecidedRowIsRefusedWithFive(t *testing.T) {
	arm := map[string]string{"gc.dispatch_when_ready": "gc-toolkit/gc-toolkit.polecat", "gc.dispatch_when_ready_args": "[]",
		"gc.dispatch_when_ready_armed_by": "gc-toolkit/gc-toolkit.mechanik", "gc.dispatch_when_ready_armed_at": "2026-10-01T00:00:00Z"}
	for name, c := range map[string]struct {
		edit func(*fake.Bead)
		why  string
	}{
		"routed":     {func(b *fake.Bead) { b.Metadata["gc.routed_to"] = "gc-toolkit/gc-toolkit.polecat" }, "it already has a dispatch path (gc.routed_to=gc-toolkit/gc-toolkit.polecat)"},
		"human park": {func(b *fake.Bead) { b.Metadata["gc.routed_to"] = "human" }, "gc.routed_to=human"},
		"armed":      {func(b *fake.Bead) { b.Metadata = arm }, "it already has a dispatch path (an arm to gc-toolkit/gc-toolkit.polecat)"},
		"capped arm": {func(b *fake.Bead) { b.Metadata = arm; b.Metadata["gc.dispatch_when_ready_fail_count"] = "3" }, "an arm to gc-toolkit/gc-toolkit.polecat"},
		"closed":     {func(b *fake.Bead) { b.Status = "closed" }, "its status is closed, and a first reaction takes only an open bead"},
		"started":    {func(b *fake.Bead) { b.Status = "in_progress" }, "its status is in_progress"},
		"assigned":   {func(b *fake.Bead) { b.Assignee = "gc-toolkit/gc-toolkit.polecat-3" }, "it is assigned to gc-toolkit/gc-toolkit.polecat-3, whose next move it is"},
		"held":       {func(b *fake.Bead) { b.Labels = []string{"learning", "hold:mayor"} }, "it is held (hold:mayor)"},
		"held outside": {func(b *fake.Bead) { b.Labels = []string{"Hold:External"} },
			"it is held (Hold:External): hold:mayor keeps it for the operator's placement sitting"},
		"standing and closed": {func(b *fake.Bead) { b.Status = "closed"; b.Metadata["task_kind"] = standingKinds[0] }, "it is a standing record"},
	} {
		w := newWorld(t)
		w.put(input("tk-row", c.edit))
		code, said := w.sling("tk-row")
		want := Decided
		if name == "standing and closed" {
			want = Excluded
		}
		w.wantSling(want, c.why, code, said, "(ROW) "+name)
	}
}

// What decides nothing about a bead's next move is no refusal: dispatch-path
// keys left blank, the execution route a pour leaves, a wait on open work, and
// the retired placement marker.
func TestWhatDecidesNothingIsNoRefusal(t *testing.T) {
	for name, edit := range map[string]func(*fake.Bead){
		"blank keys":         func(b *fake.Bead) { b.Metadata["gc.routed_to"] = " "; b.Metadata["gc.dispatch_when_ready"] = " " },
		"an execution route": func(b *fake.Bead) { b.Metadata["gc.execution_routed_to"] = "gc-toolkit/gc-toolkit.polecat" },
		"a wait on work":     func(b *fake.Bead) { b.Edges = []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "tk-work", Status: "open"}} },
		"the old marker":     func(b *fake.Bead) { b.Metadata["placement"] = "pending" },
	} {
		w := newWorld(t)
		w.put(fake.Bead{ID: "tk-work", Title: "open work", Status: "open", IssueType: "task"}, input("tk-free", edit))
		code, said := w.sling("tk-free")
		w.wantSling(0, "", code, said, "(PATH-GO) "+name)
	}
}

// An open human gate holds a bead until a person answers it, on the bead or
// on an ancestor of work not yet started, so the sling refuses the bead with
// 5, naming the gate and the ancestor it is on. A gate a person answered, and a
// gate of another await type, is no refusal.
func TestAPersonsOpenGateIsRefusedWithFive(t *testing.T) {
	gate := func(id, status, await string) fake.Bead {
		return fake.Bead{ID: id, Title: "rule on it", Status: status, IssueType: "gate", AwaitType: await, AwaitID: "polecat-blocked"}
	}
	w := newWorld(t)
	w.put(gate("tk-gate-open", "open", "human"), gate("tk-gate-up", "open", "human"),
		gate("tk-gate-shut", "closed", "human"), gate("tk-gate-timer", "open", "timer"))
	w.put(fake.Bead{ID: "tk-gepic", Title: "the gated epic", Status: "open", IssueType: "epic",
		Edges: []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "tk-gate-up", Status: "open"}}})
	w.put(input("tk-gated", func(b *fake.Bead) {
		b.Edges = []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "tk-gate-open", Title: "rule on it", Status: "open"}}
	}),
		input("tk-under", func(b *fake.Bead) {
			b.Edges = []gcbd.Edge{{Type: gcbd.EdgeParentChild, ID: "tk-gepic", Status: "open"}}
		}),
		input("tk-answered", func(b *fake.Bead) {
			b.Edges = []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "tk-gate-shut", Status: "closed", ClosedAt: "2026-11-16T00:00:00Z"}}
		}),
		input("tk-timer", func(b *fake.Bead) {
			b.Edges = []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "tk-gate-timer", Status: "open"}}
		}))
	w.store.List("tk-under", "tk-gepic")
	code, said := w.sling("tk-gated")
	w.wantSling(Decided, "it waits on a person's answer (open human gate tk-gate-open)", code, said, "(GATE-SKIP)")
	code, said = w.sling("tk-under")
	w.wantSling(Decided, "open human gate tk-gate-up on tk-gepic", code, said, "(GATE-SKIP) on the epic")
	for _, b := range []string{"tk-answered", "tk-timer"} {
		w.reset()
		code, said = w.sling(b)
		w.wantSling(0, "", code, said, "(GATE-GO) "+b)
	}
	// A bead whose waits-for edge the store cannot judge lists each spawner
	// among its waits, whatever its status, and a closed gate among them asks
	// a person nothing.
	w.put(input("tk-spawned", func(b *fake.Bead) {
		b.Edges = []gcbd.Edge{{Type: gcbd.EdgeWaitsFor, ID: "tk-gate-shut", Status: "closed"}}
	}))
	w.reset()
	code, said = w.sling("tk-spawned")
	w.wantSling(0, "", code, said, "(GATE-GO) a closed gate among its waits")
}

// An open conversation about a bead puts it to the operator already, so the
// sling refuses it with 3: an open task assigned to human, or to the alias that
// names its own id, that tracks the one bead. A closed one, a task that tracks
// more than the bead, and a task assigned to anyone else are no conversation.
func TestAnOpenConversationIsRefusedWithThree(t *testing.T) {
	conv := func(id, status, assignee string, tracked ...string) fake.Bead {
		b := fake.Bead{ID: id, Title: "a conversation", Status: status, IssueType: "task", Assignee: assignee}
		for _, t := range tracked {
			b.Edges = append(b.Edges, gcbd.Edge{Type: "tracks", ID: t})
		}
		return b
	}
	w := newWorld(t)
	for _, id := range []string{"tk-talked", "tk-held", "tk-ended", "tk-shared", "tk-owed", "tk-other"} {
		w.put(input(id, nil))
	}
	w.put(conv("tk-c1", "open", "human", "tk-talked"), conv("tk-c2", "in_progress", "gc-toolkit/gc-toolkit.tk-c2", "tk-held"),
		conv("tk-c3", "closed", "human", "tk-ended"), conv("tk-c4", "open", "human", "tk-shared", "tk-other"),
		conv("tk-c5", "open", "someone", "tk-owed"))
	for bead, c := range map[string]string{"tk-talked": "tk-c1", "tk-held": "tk-c2"} {
		w.reset()
		code, said := w.sling(bead)
		w.wantSling(Reacting, "an open conversation tracks it ("+c+"), which puts it to the operator already", code, said, "(CONV-SKIP) "+bead)
	}
	for _, bead := range []string{"tk-ended", "tk-shared", "tk-owed"} {
		w.reset()
		code, said := w.sling(bead)
		w.wantSling(0, "", code, said, "(CONV-GO) "+bead)
	}
}

// A live run that works a bead refuses it: 3 for a first reaction, named by its
// run, and 4 for another formula, named by its root and formula. A first
// reaction is named before a build that also works the bead. A root that
// closed, a convoy no root names and a bead no convoy tracks hold nothing.
func TestALiveRunIsRefused(t *testing.T) {
	w := newWorld(t)
	for _, id := range []string{"tk-building", "tk-reacting", "tk-both", "tk-built", "tk-retired", "tk-fresh"} {
		w.put(input(id, nil))
	}
	w.run("tk-root-building", "mol-polecat-work", "tk-building", "in_progress")
	w.run("tk-root-reacting", Formula, "tk-reacting", "in_progress")
	w.run("tk-root-both-b", "mol-polecat-work", "tk-both", "in_progress")
	w.run("tk-root-both-r", Formula, "tk-both", "in_progress")
	w.run("tk-root-built", "mol-polecat-work", "tk-built", "closed")
	w.put(fake.Bead{ID: "tk-cv-retired", Status: "closed", IssueType: "convoy", Edges: []gcbd.Edge{{Type: "tracks", ID: "tk-retired"}}})
	code, said := w.sling("tk-building")
	w.wantSling(Driven, "a live workflow already works it (tk-root-building (mol-polecat-work)), and a reaction would race work in flight", code, said, "(LIVE-SKIP)")
	code, said = w.sling("tk-reacting")
	w.wantSling(Reacting, "a first reaction already runs on it (tk-root-reacting)", code, said, "(LIVE-REACTING)")
	code, said = w.sling("tk-both")
	w.wantSling(Reacting, "tk-root-both-r", code, said, "(LIVE-ORDER) the reaction, not the build")
	for _, b := range []string{"tk-built", "tk-retired", "tk-fresh"} {
		w.reset()
		code, said = w.sling(b)
		w.wantSling(0, "", code, said, "(LIVE-NONE) "+b)
	}
}

// A read that does not answer decides nothing: the sling fails, nothing is
// slung, and the message says which read: the runs, the tracks dependents, a
// candidate conversation's own row, and what holds the bead.
func TestAReadThatDoesNotAnswerDecidesNothing(t *testing.T) {
	for name, c := range map[string]struct {
		edit func(*world)
		why  string
	}{
		"the runs": {func(w *world) { w.failFind(func(q gcbd.Query) bool { return q.Key == "gc.var.issue" }) },
			"could not read the runs that work tk-sub"},
		"the tracks dependents": {func(w *world) { w.store.DependentsErr = errors.New("gc bd dep list exited 1") },
			"could not read whether an open conversation tracks tk-sub"},
		"a conversation's row": {func(w *world) {
			w.put(fake.Bead{ID: "tk-conv", Status: "open", IssueType: "task", Assignee: "human", Edges: []gcbd.Edge{{Type: "tracks", ID: "tk-sub"}}})
			w.failFind(func(q gcbd.Query) bool { return slices.Contains(q.IDs, "tk-conv") })
		}, "could not read whether an open conversation tracks tk-sub"},
		"a conversation's row the listing leaves out": {func(w *world) {
			w.put(fake.Bead{ID: "tk-conv", Status: "open", IssueType: "task", Assignee: "human", Edges: []gcbd.Edge{{Type: "tracks", ID: "tk-sub"}}})
			w.omitFind(func(q gcbd.Query, id string) bool { return id == "tk-conv" })
		}, "the row of tk-conv, which tracks it, did not read"},
		"what holds it": {func(w *world) { w.store.BlockedErr = errors.New("gc bd blocked exited 1") },
			"could not read what holds tk-sub"},
	} {
		w := newWorld(t)
		c.edit(w)
		code, said := w.sling("tk-sub")
		w.wantSling(1, c.why, code, said, "(FAILCLOSED) "+name)
	}
}

// trackersRead is the world's store, counting each read of the beads that
// track a bead.
type trackersRead struct {
	*fake.Store
	mu    sync.Mutex
	reads map[string]int
}

func (s *trackersRead) Dependents(id, typ string) ([]gcbd.Bead, error) {
	s.mu.Lock()
	s.reads[id+" "+typ]++
	s.mu.Unlock()
	return s.Store.Dependents(id, typ)
}

// The check and the sling each read the subject's row once and the beads that
// track it once, for every question they ask of them, and find the runs that
// work it among live roots alone. A person's gate holds the subject here, and
// a finished run's convoy tracks it, so every read the refusals make is made
// before the gate refuses it.
func TestARefusalReadsTheSubjectAndWhatTracksItOnce(t *testing.T) {
	w := newWorld(t)
	w.put(fake.Bead{ID: "tk-g", Title: "rule on it", Status: "open", IssueType: "gate", AwaitType: "human", AwaitID: "polecat-blocked"})
	w.put(input("tk-held", func(b *fake.Bead) {
		b.Edges = []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "tk-g", Title: "rule on it", Status: "open"}}
	}))
	w.run("tk-root-built", "mol-polecat-work", "tk-held", "closed")
	for what, ask := range map[string]func() (int, string){
		"the check": func() (int, string) { return w.check("tk-held", "tk-root-asking") },
		"the sling": func() (int, string) { return w.sling("tk-held") },
	} {
		counted := &trackersRead{Store: w.store, reads: map[string]int{}}
		w.r.Ledger = ledger.New(counted)
		before := len(w.store.Finds())
		code, said := ask()
		w.wantSling(Decided, "open human gate tk-g", code, said, "(READ-ONCE) "+what)
		rows := 0
		for _, q := range w.store.Finds()[before:] {
			if slices.Contains(q.IDs, "tk-held") {
				rows++
			}
			if q.Closed && (q.Key == "gc.input_convoy_id" || q.Key == "gc.var.issue") {
				t.Errorf("(READ-ONCE) %s read closed roots to find the runs (%+v)", what, q)
			}
		}
		if n := counted.reads["tk-held tracks"]; rows != 1 || n != 1 {
			t.Errorf("(READ-ONCE) %s read the subject's row %d times and what tracks it %d times; want once each", what, rows, n)
		}
	}
}

// gc sling's own refusal of a second live reaction passes through as 3, naming
// the runs it names, or none; any other failure of the sling is an error.
func TestGcSlingsOwnRefusalPassesThrough(t *testing.T) {
	w := newWorld(t)
	w.slingCode = 3
	code, said := w.sling("tk-sub")
	if code != Reacting || !strings.Contains(said, "gc sling found a first reaction already running on it (tk-closer-root)") {
		t.Errorf("(CONFLICT-LIVE) exit %d saying %q", code, said)
	}
	w.rt.OnSling = func(gascity.Sling) gascity.SlingResult {
		return gascity.SlingResult{Result: gascity.Result{Code: 3, Output: "gc sling: refused"}}
	}
	if code, said = w.sling("tk-sub"); code != Reacting || !strings.Contains(said, "gc sling refused a second live mol-first-reaction run on it") {
		t.Errorf("(CONFLICT-LIVE) an exit 3 naming no run: exit %d saying %q", code, said)
	}
	w.rt.OnSling = func(gascity.Sling) gascity.SlingResult {
		return gascity.SlingResult{Result: gascity.Result{Code: 1, Output: "gc sling: no such target"}}
	}
	if code, said = w.sling("tk-sub"); code != 1 || !strings.Contains(said, "gc sling refused or failed on tk-sub (exit 1: gc sling: no such target)") {
		t.Errorf("(SLING-FAIL) exit %d saying %q", code, said)
	}
}

// A sling in no rig has no pool to sling into, so it fails before it reads
// anything.
func TestASlingInNoRigFailsClosed(t *testing.T) {
	w := newWorld(t)
	w.r.Rig = ""
	code, said := w.sling("tk-sub")
	if code != 1 || !strings.Contains(said, "set GC_RIG") {
		t.Errorf("(SLING-FAILCLOSED) exit %d saying %q", code, said)
	}
	if len(w.lines("FIND ")) > 0 || len(w.slings()) > 0 {
		t.Errorf("(SLING-FAILCLOSED) a sling in no rig read or slung: %v", w.log)
	}
}

// The check is the reaction's first act: the sling's refusals, writing
// nothing, with its own run passed over, so another reaction's run refuses the
// subject with 3, a build beside its own with 4, and a subject closed since the
// sling with 5. It names the run it reads as no second reaction.
func TestTheCheckPassesOverItsOwnRun(t *testing.T) {
	w := newWorld(t)
	w.put(input("tk-reacting", nil), input("tk-both", nil), input("tk-done", func(b *fake.Bead) { b.Status = "closed" }))
	w.run("tk-root-reacting", Formula, "tk-reacting", "in_progress")
	w.run("tk-root-both-r", Formula, "tk-both", "in_progress")
	w.run("tk-root-both-b", "mol-polecat-work", "tk-both", "in_progress")
	w.run("tk-root-done", Formula, "tk-done", "in_progress")
	w.reset()
	code, said := w.check("tk-reacting", "tk-root-reacting")
	w.wantSling(0, "", code, said, "(CHECK-OWN)")
	if wr := w.writes(); len(wr) > 0 {
		t.Errorf("(CHECK-WRITES-NOTHING) the check wrote %v", wr)
	}
	code, said = w.check("tk-reacting", "tk-root-elsewhere")
	w.wantSling(Reacting, "a first reaction already runs on it (tk-root-reacting)", code, said, "(CHECK-OTHER)")
	code, said = w.check("tk-both", "tk-root-both-r")
	w.wantSling(Driven, "tk-root-both-b (mol-polecat-work)", code, said, "(CHECK-OTHER) a build beside it")
	code, said = w.check("tk-done", "tk-root-done")
	w.wantSling(Decided, "its status is closed", code, said, "(CHECK-CLOSED)")
	for _, run := range []string{"", "tk root", "tk-root;rm"} {
		if code, said = w.check("tk-reacting", run); code != 2 {
			t.Errorf("(USAGE) a check with --run %q exits %d saying %q, want a usage error", run, code, said)
		}
	}
	if len(w.slings()) > 0 {
		t.Errorf("(CHECK-WRITES-NOTHING) the check slung %v", w.slings())
	}
}

// The check passes over a gate filed under the reaction's key whose message
// names its run among its words, a sentence's last dot trimmed, which its own
// recommend or ruling exit filed. A first-reaction gate that names another run,
// one whose word only begins with the run, and a gate under another key that
// names the run, each hold the subject, and a sling, which no run asks,
// refuses the subject its own gate holds. A gate row that does not read
// decides nothing.
func TestTheCheckPassesOverItsOwnRunsGate(t *testing.T) {
	w := newWorld(t)
	gate := func(id, key, msg string) fake.Bead {
		return fake.Bead{ID: id, Title: "Recommend", Status: "open", IssueType: "gate", AwaitType: "human", AwaitID: key, Description: msg}
	}
	w.put(gate("tk-g-own", GateKey, "Recommend mol-polecat-work.\n\nFiled by a first reaction on tk-own (recommend, run tk-root-reacting.)"),
		gate("tk-g-other", GateKey, "Filed by the first reaction run tk-root-reacting2."),
		gate("tk-g-key", "polecat-blocked", "Blocked while run tk-root-reacting ran."))
	for _, b := range []struct{ id, gate string }{{"tk-own", "tk-g-own"}, {"tk-other", "tk-g-other"}, {"tk-key", "tk-g-key"}} {
		w.put(input(b.id, func(f *fake.Bead) { f.Edges = []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: b.gate, Status: "open"}} }))
	}
	code, said := w.check("tk-own", "tk-root-reacting")
	w.wantSling(0, "", code, said, "(CHECK-OWN-GATE)")
	code, said = w.check("tk-other", "tk-root-reacting")
	w.wantSling(Decided, "open human gate tk-g-other", code, said, "(CHECK-OTHER-GATE) another run's")
	code, said = w.check("tk-key", "tk-root-reacting")
	w.wantSling(Decided, "open human gate tk-g-key", code, said, "(CHECK-OTHER-GATE) another key's")
	code, said = w.sling("tk-own")
	w.wantSling(Decided, "open human gate tk-g-own", code, said, "(CHECK-OWN-GATE) a sling")
	// The snapshot of what holds the subject lists the gate's row first, and
	// the check's own read of the gate's row comes second.
	named := 0
	w.failFind(func(q gcbd.Query) bool {
		if slices.Contains(q.IDs, "tk-g-own") {
			named++
		}
		return slices.Contains(q.IDs, "tk-g-own") && named > 1
	})
	code, said = w.check("tk-own", "tk-root-reacting")
	w.wantSling(1, "could not read the human gates that hold tk-own, to pass over its own run's", code, said, "(HOLDS-READS) a gate row that does not read")
	named = 0
	w.omitFind(func(q gcbd.Query, id string) bool {
		if id == "tk-g-own" {
			named++
		}
		return id == "tk-g-own" && named > 1
	})
	code, said = w.check("tk-own", "tk-root-reacting")
	w.wantSling(1, "the gate tk-g-own did not read", code, said, "(HOLDS-READS) a gate row the listing leaves out")
}
