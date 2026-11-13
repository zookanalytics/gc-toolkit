package arm_test

import (
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/arm"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/gcbdtest"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// The arm's store acceptance cases run the start, the verbs and the bd the city
// runs against a scratch store (gcbdtest), so they pin what bd's readiness and
// its writes do with each shape of an arm, which the fake store only stands in
// for (docs/deferred-dispatch.md). A test cannot run Gas City's launch, so `gc
// sling` is a shim that records each call and exits as the case says, and on
// exit 3 prints the line gc sling prints, naming roots made in the store. They
// run only when GCTK_STORE_ACCEPTANCE=1 asks for them:
//
//	GCTK_STORE_ACCEPTANCE=1 go test ./arm -run TestStoreAcceptance -v

// accept is one scratch store with the start's verbs over it, the sling shim's
// files, and the record of each ask.
type accept struct {
	t     *testing.T
	s     *gcbdtest.Store
	arms  *arm.Arms
	slung string // the shim's log: one line per sling
	exit  string // the shim's exit for the next sling
	live  string // the roots the shim names on exit 3
	asks  string // the asks the pack's scripts were given
}

const acceptPool = "pa/pa.polecat"

func newAccept(t *testing.T) *accept {
	t.Helper()
	if !gcbdtest.Asked() {
		t.Skip("the store acceptance cases run the city's bd on a scratch store; GCTK_STORE_ACCEPTANCE=1 runs them")
	}
	a := &accept{t: t, s: gcbdtest.New(t, "pa")}
	work := t.TempDir()
	a.slung, a.exit, a.live, a.asks = filepath.Join(work, "slung"), filepath.Join(work, "exit"), filepath.Join(work, "live"), filepath.Join(work, "asks")
	scripts := filepath.Join(work, "scripts")
	if err := os.MkdirAll(scripts, 0o755); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"human-gate.sh", "gc-helm.sh"} {
		body := "#!/bin/sh\nprintf '" + name + " %s\\n' \"$*\" >> '" + a.asks + "'\n"
		if err := os.WriteFile(filepath.Join(scripts, name), []byte(body), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	config := `{"ok":true,"config":{"Agents":[{"Name":"polecat","Dir":"pa","DefaultSlingFormula":"mol-polecat-work"}]}}`
	a.s.Enter(t, `sling) shift
  [ "$1" = --rig ] && shift 2
  printf '%s\n' "$*" >> '`+a.slung+`'
  code=$(cat '`+a.exit+`' 2>/dev/null || echo 0)
  if [ "$code" = 3 ]; then
    printf 'gc sling: source bead %s already has live workflow(s): %s\n' "$2" "$(cat '`+a.live+`')" >&2
    printf 'gc sling: use --force to override, or gc workflow delete-source %s --apply to clean up\n' "$2" >&2
  fi
  exit "$code" ;;
config) printf '%s\n' '`+config+`'; exit 0 ;;`)
	t.Setenv("GCTK_SCRIPTS_DIR", scripts)
	t.Setenv("GC_MAX_DISPATCH_SLING_FAILURES", "")
	l, err := ledger.Open(a.s.DB())
	if err != nil {
		t.Fatal(err)
	}
	a.arms = &arm.Arms{Ledger: l, Runtime: gascity.New(), Locks: t.TempDir(), Now: time.Now, Actor: "acceptance", Wait: time.Second}
	return a
}

// bead files an open bead with bd create's further args.
func (a *accept) bead(title string, args ...string) string { return a.s.Create(title, args...) }

// armed writes an arm onto id straight through bd, as a store already holds
// one, so a case can arm a shape the verb refuses.
func (a *accept) armed(id, formula string, extra ...string) {
	a.t.Helper()
	args := []string{"update", id,
		"--set-metadata", "gc.dispatch_when_ready=" + acceptPool,
		"--set-metadata", `gc.dispatch_when_ready_args=["--on","` + formula + `"]`,
		"--set-metadata", "gc.dispatch_when_ready_armed_at=" + armedAt}
	for _, kv := range extra {
		args = append(args, "--set-metadata", kv)
	}
	a.s.Run(args...)
}

// set writes metadata onto id.
func (a *accept) set(id string, kvs ...string) {
	a.t.Helper()
	args := []string{"update", id}
	for _, kv := range kvs {
		args = append(args, "--set-metadata", kv)
	}
	a.s.Run(args...)
}

// pass runs one pass with gc sling answering code, naming live on exit 3, and
// returns each line by its bead. Each pass starts the shim's and the asks'
// logs over.
func (a *accept) pass(dry bool, code string, live ...string) map[string]arm.Line {
	a.t.Helper()
	for path, text := range map[string]string{a.exit: code, a.live: strings.Join(live, ","), a.slung: "", a.asks: ""} {
		if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
			a.t.Fatal(err)
		}
	}
	got := map[string]arm.Line{}
	if _, err := a.arms.StartArmed(arm.StartOptions{DryRun: dry}, func(l arm.Line) { got[l.ID] = l }); err != nil {
		a.t.Fatal(err)
	}
	return got
}

// slung is the beads the last pass slung, each sling's arguments in a line.
func (a *accept) slungLines() []string {
	raw, _ := os.ReadFile(a.slung)
	var out []string
	for _, l := range strings.Split(strings.TrimSpace(string(raw)), "\n") {
		if l != "" {
			out = append(out, l)
		}
	}
	return out
}

func (a *accept) slungBead(id string) bool {
	return slices.ContainsFunc(a.slungLines(), func(l string) bool { f := strings.Fields(l); return len(f) > 1 && f[1] == id })
}

func (a *accept) askLog() string {
	raw, _ := os.ReadFile(a.asks)
	return string(raw)
}

// row is the bead as the store holds it now.
func (a *accept) row(id string) (meta map[string]any, notes string) {
	a.t.Helper()
	var rows []struct {
		Metadata map[string]any `json:"metadata"`
		Notes    string         `json:"notes"`
	}
	if err := json.Unmarshal([]byte(a.s.Run("show", id, "--json")), &rows); err != nil || len(rows) != 1 {
		a.t.Fatalf("bd show %s: %v", id, err)
	}
	return rows[0].Metadata, rows[0].Notes
}

func (a *accept) isArmed(id string) bool {
	meta, _ := a.row(id)
	_, held := meta["gc.dispatch_when_ready"]
	return held
}

// The start selects armed beads by the pool's own serve rule, bd's ready read
// with Gas City's flags, and holds back what bd cannot judge, against the real
// bd: one case per shape.
func TestStoreAcceptanceWhatHoldsAnArmedBead(t *testing.T) {
	a := newAccept(t)
	free := a.bead("free")
	openBlocker, closedBlocker := a.bead("open blocker"), a.bead("closed blocker")
	a.s.Run("close", closedBlocker)
	blocked, released := a.bead("blocked"), a.bead("released")
	a.s.Edge(blocked, openBlocker, "blocks", "")
	a.s.Edge(released, closedBlocker, "blocks", "")
	conditional := a.bead("conditional")
	a.s.Edge(conditional, a.bead("conditional blocker"), "conditional-blocks", "")
	waits := a.bead("waits")
	a.s.Edge(waits, a.bead("spawner"), "waits-for", "")
	foreign := a.bead("foreign")
	a.s.Run("dep", "add", foreign, "xx-1", "--type", "blocks")
	human := a.bead("human", "--labels", "human")
	epic := a.bead("an epic", "--type", "epic")
	mayor := a.bead("held for the PO", "--labels", "hold:mayor")
	spelled := a.bead("held in another spelling", "--labels", "Hold:Mayor")
	assigned := a.bead("assigned", "--assignee", "pa/pa.refinery")
	deferred := a.bead("deferred")
	a.s.Run("update", deferred, "--status", "deferred")
	parkedEpic, park := a.bead("parked epic", "--type", "epic"), a.bead("park", "--type", "gate")
	a.s.Edge(parkedEpic, park, "blocks", "")
	unstarted, inFlight := a.bead("unstarted under the park"), a.bead("in flight under the park")
	a.s.Edge(unstarted, parkedEpic, "parent-child", "")
	a.s.Edge(inFlight, parkedEpic, "parent-child", "")
	a.set(inFlight, "branch=polecat/"+inFlight)
	for _, id := range []string{free, blocked, released, conditional, waits, foreign, human, epic, mayor, spelled, assigned, deferred, unstarted, inFlight} {
		a.armed(id, "mol-x")
	}

	lines := a.pass(false, "0")
	act(t, lines, free, arm.ActStart, "", "")
	act(t, lines, released, arm.ActStart, "", "")
	act(t, lines, blocked, arm.ActHold, "blocked", openBlocker)
	act(t, lines, conditional, arm.ActHold, "blocked", "")
	act(t, lines, waits, arm.ActHold, "unjudged", "")
	act(t, lines, foreign, arm.ActHold, "foreign", "xx-1")
	act(t, lines, human, arm.ActHold, "label", "human")
	act(t, lines, epic, arm.ActHold, "epic", "")
	act(t, lines, mayor, arm.ActHold, "label", "hold:mayor")
	act(t, lines, spelled, arm.ActHold, "label", "Hold:Mayor")
	act(t, lines, assigned, arm.ActHold, "assigned", "")
	act(t, lines, deferred, arm.ActHold, "status", "deferred")
	act(t, lines, unstarted, arm.ActHold, "held", park)
	act(t, lines, inFlight, arm.ActHold, "unready", "in flight")
	if got := len(a.slungLines()); got != 2 || !a.slungBead(free) || !a.slungBead(released) {
		t.Errorf("slung %v; want the free bead and the released one, once each", a.slungLines())
	}
	for _, id := range []string{free, released} {
		if a.isArmed(id) {
			t.Errorf("%s kept its arm after its sling", id)
		}
		if _, notes := a.row(id); !strings.Contains(notes, "deferred-dispatch: dispatch record cleared at") || !strings.Contains(notes, "dispatched to "+acceptPool+" on mol-x") {
			t.Errorf("%s's notes = %q", id, notes)
		}
	}
	for _, id := range []string{blocked, conditional, waits, foreign, human, epic, mayor, spelled, assigned, deferred, unstarted, inFlight} {
		if !a.isArmed(id) {
			t.Errorf("held %s lost its arm", id)
		}
	}
}

// An arm on a bead that closed, or that carries a merge_result, retires
// whatever holds the bead, with a note naming the case, and nothing is slung.
// A dry run reports each retire and writes nothing.
func TestStoreAcceptanceRetirements(t *testing.T) {
	a := newAccept(t)
	pr, gate, behind, closed := a.bead("delivered"), a.bead("at its gate"), a.bead("delivered behind a blocker"), a.bead("closed")
	a.s.Edge(behind, a.bead("still open"), "blocks", "")
	for id, mr := range map[string]string{pr: "pull_request", gate: "pre_open_gate", behind: "pull_request"} {
		a.armed(id, "mol-polecat-work", "merge_result="+mr)
	}
	a.armed(closed, "mol-x")
	a.s.Run("close", closed)

	lines := a.pass(true, "0")
	for _, id := range []string{pr, gate, behind} {
		act(t, lines, id, arm.ActRetire, "delivered", "merge_result=")
	}
	act(t, lines, closed, arm.ActRetire, "closed", "")
	for _, id := range []string{pr, gate, behind, closed} {
		if !a.isArmed(id) {
			t.Errorf("the dry run cleared %s's arm", id)
		}
	}

	lines = a.pass(false, "0")
	act(t, lines, pr, arm.ActRetire, "delivered", "merge_result=pull_request")
	act(t, lines, gate, arm.ActRetire, "delivered", "merge_result=pre_open_gate")
	act(t, lines, behind, arm.ActRetire, "delivered", "merge_result=pull_request")
	act(t, lines, closed, arm.ActRetire, "closed", "")
	for _, id := range []string{pr, gate, behind, closed} {
		if a.isArmed(id) {
			t.Errorf("%s kept its arm", id)
		}
	}
	if _, notes := a.row(gate); !strings.Contains(notes, "merge_result=pre_open_gate") {
		t.Errorf("the retire's note = %q; want it to name the merge_result it read", notes)
	}
	if s := a.slungLines(); len(s) != 0 {
		t.Errorf("slung %v", s)
	}
}

// arm and disarm write the arm and remove it in the real store, each with its
// note. A stop removes the arm first: once the disarm returns, answering the
// human gate that held the bead sends nothing.
func TestStoreAcceptanceTheVerbsAndTheStopsOrder(t *testing.T) {
	a := newAccept(t)
	b := a.bead("the work")
	if _, err := a.arms.Arm(arm.Request{ID: b, Target: acceptPool, Reason: "waits for the base"}); err != nil {
		t.Fatal(err)
	}
	meta, notes := a.row(b)
	if meta["gc.dispatch_when_ready"] != acceptPool || meta["gc.dispatch_when_ready_args"] != `["--on","mol-polecat-work"]` || meta["gc.dispatch_when_ready_armed_by"] != "acceptance" {
		t.Errorf("the arm wrote %v", meta)
	}
	if !strings.Contains(notes, "deferred-dispatch: dispatch armed by acceptance at ") {
		t.Errorf("the arm's note = %q", notes)
	}
	gate := a.bead("decide", "--type", "gate")
	a.s.Edge(b, gate, "blocks", "")
	lines := a.pass(false, "0")
	act(t, lines, b, arm.ActHold, "blocked", gate)
	if _, err := a.arms.Disarm(b, "stood down"); err != nil {
		t.Fatal(err)
	}
	if a.isArmed(b) {
		t.Fatal("the disarm left the arm")
	}
	if _, notes := a.row(b); !strings.Contains(notes, "deferred-dispatch: dispatch record cleared at") || !strings.Contains(notes, "stood down") {
		t.Errorf("the disarm's note = %q", notes)
	}
	a.s.Run("close", gate)
	lines = a.pass(false, "0")
	if _, read := lines[b]; read || len(a.slungLines()) != 0 {
		t.Errorf("after the stop, the pass read %v and slung %v", lines[b], a.slungLines())
	}
}

// After an earlier attempt the start searches the arm's token among the roots
// the store holds, each made as Gas City leaves it, a fenced or failed bead
// typed as a gate.
func TestStoreAcceptanceTheTokenAfterAnEarlierAttempt(t *testing.T) {
	a := newAccept(t)
	// root makes a workflow root titled with id's token for formula, closed
	// when closed is set, typed as a gate when it carries a mark.
	root := func(id, formula string, closed bool, meta ...string) string {
		args := []string{}
		if len(meta) > 0 {
			args = append(args, "--type", "gate")
		}
		r := a.bead(formula+" arm:"+id+"@"+armedAt, args...)
		if len(meta) > 0 {
			a.set(r, meta...)
		}
		if closed {
			a.s.Run("close", r, "--force")
		}
		return r
	}
	// step makes a bead poured under r, carrying meta.
	step := func(r string, meta ...string) {
		s := a.bead("a step of "+r, "--type", "gate")
		a.set(s, append([]string{"gc.root_bead_id=" + r}, meta...)...)
	}
	type tcase struct {
		id     string
		action string
		slung  bool
	}
	var cases []tcase
	add := func(title, action string, slung bool, build func(id string)) {
		id := a.bead(title)
		a.armed(id, "mol-x", "gc.dispatch_when_ready_fail_count=1")
		build(id)
		cases = append(cases, tcase{id, action, slung})
	}
	add("another formula landed", arm.ActSent, false, func(id string) { root(id, "mol-other", true) })
	add("an open failed pour", arm.ActAsk, false, func(id string) { root(id, "mol-x", false, "molecule_failed=true") })
	add("an open fenced pour", arm.ActAsk, false, func(id string) { root(id, "mol-x", false, "gc.instantiating=true") })
	add("an open root over a fenced step", arm.ActAsk, false, func(id string) { step(root(id, "mol-x", false), "gc.instantiating=true") })
	add("a closed failed pour", arm.ActStart, true, func(id string) { root(id, "mol-x", true, "molecule_failed=true") })
	add("a closed root over a fenced step", arm.ActStart, true, func(id string) { step(root(id, "mol-x", true), "gc.instantiating=true") })
	add("a root whose step alone failed", arm.ActSent, false, func(id string) { step(root(id, "mol-x", false), "molecule_failed=true") })

	lines := a.pass(false, "0")
	for _, c := range cases {
		act(t, lines, c.id, c.action, lines[c.id].Start.Case, "")
		if got := a.slungBead(c.id); got != c.slung {
			t.Errorf("%s (%s): slung %v, want %v", c.id, lines[c.id].Start.Why, got, c.slung)
		}
		if got, want := a.isArmed(c.id), c.action == arm.ActAsk; got != want {
			t.Errorf("%s (%s): armed %v, want %v", c.id, lines[c.id].Start.Why, got, want)
		}
		if c.action == arm.ActAsk && !strings.Contains(a.askLog(), "deferred-dispatch-sling-failed."+c.id) {
			t.Errorf("%s: asks %q; want a gate under its key", c.id, a.askLog())
		}
	}
}

// gc sling exits 3 only when a live workflow works the bead already. One that
// Gas City finished retires the arm; when each one named is an unfinished pour,
// the arm stays and a person is asked, naming it.
func TestStoreAcceptanceExit3(t *testing.T) {
	a := newAccept(t)
	working := a.bead("worked already")
	a.armed(working, "mol-x")
	running := a.bead("mol-x run")
	lines := a.pass(false, "3", running)
	act(t, lines, working, arm.ActSent, "", running)
	if a.isArmed(working) {
		t.Error("an exit 3 naming a working run left the arm")
	}

	stuck := a.bead("poured part way")
	a.armed(stuck, "mol-x")
	failed := a.bead("mol-x failed", "--type", "gate")
	a.set(failed, "molecule_failed=true")
	lines = a.pass(false, "3", failed)
	act(t, lines, stuck, arm.ActAsk, "unfinished", failed)
	if !a.isArmed(stuck) || !strings.Contains(a.askLog(), "gc convoy delete "+failed+" --force") {
		t.Errorf("armed %v, asks %q; want the arm kept and a gate naming the root's close", a.isArmed(stuck), a.askLog())
	}
}
