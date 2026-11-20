package reaction

import (
	"errors"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// A call that cannot be performed is refused before anything is read or
// written: a missing --reason, --takeaway or bead, an exit that is not one, a
// close of the subject, which no reaction makes, and a --run that is the
// subject or not one bead id.
func TestUsageIsRefusedBeforeAnyWrite(t *testing.T) {
	for name, args := range map[string][]string{
		"no --reason":         {"tk-sub", "--disposition", "actionable", "--takeaway", "t", "--run", root},
		"an unknown exit":     {"tk-sub", "--disposition", "sideways", "--reason", "r", "--takeaway", "t", "--run", root},
		"no --takeaway":       {"tk-sub", "--disposition", "actionable", "--reason", "r", "--run", root},
		"no bead":             {"--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--run", root},
		"superseded":          {"tk-sub", "--disposition", "superseded", "--reason", "r", "--takeaway", "t", "--run", root},
		"--run the subject":   {"tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--run", "tk-sub"},
		"--run not one id":    {"tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--run", "tk-root; rm"},
		"an empty --run":      {"tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--run", ""},
		"another exit's flag": {"tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--waiting-on", "tk-other", "--run", root},
	} {
		t.Run(name, func(t *testing.T) {
			w := newWorld(t)
			code, _, err := w.dispose(args...)
			wantCode(t, code, 2, err, name)
			if got := w.writes(); len(got) != 0 {
				t.Errorf("%s wrote %q", name, got)
			}
			if r := w.rt.Reads(); len(r) != 0 {
				t.Errorf("%s read %q of Gas City", name, r)
			}
		})
	}
	w := newWorld(t)
	_, _, err := w.dispose("tk-sub", "--disposition", "actionable", "--takeaway", "t")
	errHas(t, err, "makes a wrong call visible", "(ARGS) the refusal says why the reason is required")
	_, _, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--run", "tk-root; rm")
	errHas(t, err, "one bead id", "(RUNARG) the refusal says what --run takes")
	_, _, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--waiting-on", "tk-other")
	errHas(t, err, "--waiting-on does not belong to the actionable exit, which takes --route, --emergency, --assign", "(FLAGS) the refusal names the exit's own flags")
}

// The subject's status is read before the first write, and a subject that is
// not open takes no write whichever exit was asked for: exit 3. A row with no
// status reads as open. A subject that does not read stops the exit with
// nothing written.
func TestAnExitWritesOnlyToAnOpenSubject(t *testing.T) {
	exits := [][]string{
		{"--disposition", "actionable", "--route", "gc-toolkit/gc-toolkit.polecat"},
		{"--disposition", "actionable", "--assign", "gc-toolkit.mechanik"},
		{"--disposition", "blocked", "--waiting-on", "tk-blk1", "--then-route", "gc-toolkit/gc-toolkit.polecat"},
		{"--disposition", "close", "--route", "gc-toolkit/gc-toolkit.polecat"},
		{"--disposition", "ruling"},
		{"--disposition", "recommend", "--recommended-formula", "mol-x"},
	}
	for _, exit := range exits {
		for _, status := range []string{"closed", "in_progress", "CLOSED"} {
			w := newWorld(t)
			w.subject(func(b *fake.Bead) { b.Status = status })
			code, _, err := w.dispose(append([]string{"tk-sub", "--run", root, "--reason", "r", "--takeaway", "t"}, exit...)...)
			wantCode(t, code, 3, err, "(STATUS) "+exit[1]+" on a "+status+" subject")
			errHas(t, err, "tk-sub is "+strings.ToLower(status)+", and an exit writes only to an open subject", "(STATUS) the refusal names the status")
			if got := w.writes(); len(got) != 0 {
				t.Errorf("(STATUS) %s on a %s subject wrote %q", exit[1], status, got)
			}
		}
	}
	w := newWorld(t)
	w.subject(func(b *fake.Bead) { b.Status = "" })
	code, _, err := w.dispose("tk-sub", "--run", root, "--reason", "r", "--takeaway", "t", "--disposition", "ruling")
	wantCode(t, code, 0, err, "(STATUS) a row with no status reads as open")

	w = newWorld(t)
	w.store.FindErr = errors.New("the store did not answer")
	code, _, err = w.dispose("tk-sub", "--run", root, "--reason", "r", "--takeaway", "t", "--disposition", "actionable", "--assign", "gc-toolkit.mechanik")
	wantCode(t, code, 4, err, "(STATUSREAD) a subject that does not read")
	errHas(t, err, "could not read tk-sub", "(STATUSREAD) the failure says so")
	if got := w.writes(); len(got) != 0 {
		t.Errorf("(STATUSREAD) wrote %q", got)
	}
	w = newWorld(t)
	code, _, err = w.dispose("tk-gone", "--run", root, "--reason", "r", "--takeaway", "t", "--disposition", "ruling")
	wantCode(t, code, 4, err, "(STATUSREAD) a subject its store does not hold")
	if got := w.writes(); len(got) != 0 {
		t.Errorf("(STATUSREAD) wrote %q", got)
	}
}

// The actionable exit releases the bead to the pool in the one write it makes,
// with the route, and says nothing waits on it. The pool is asked whether it
// can claim this bead first, and one that cannot refuses the exit, naming the
// named agent's address before the operator's exits.
func TestActionableReleasesTheBeadToItsPool(t *testing.T) {
	w := newWorld(t)
	code, out, err := w.dispose("tk-sub", "--disposition", "actionable", "--reason", "states a done condition and a branch",
		"--takeaway", "routed to the polecat pool", "--route", "gc-toolkit/gc-toolkit.polecat", "--run", root)
	wantCode(t, code, 0, err, "(ACT) an actionable exit")
	w.has("TAKEAWAY tk-sub routed to the polecat pool --by proactive --release --route gc-toolkit/gc-toolkit.polecat --no-wait",
		"(ACTROUTE) the release hands the bead to the pool and says nothing waits on it, in one call")
	if n := len(w.lines("TAKEAWAY ")); n != 1 {
		t.Errorf("(ACT) the exit made %d takeaways, want 1", n)
	}
	w.hasnt("SET-STATE", "(ACT) a member is not held")
	if want := "tk-sub disposed as actionable (gc-toolkit/gc-toolkit.polecat)"; out != want {
		t.Errorf("(ACT) the exit reported %q, want %q", out, want)
	}
	if r := strings.Join(w.rt.Reads(), ","); !strings.Contains(r, "roster") {
		t.Errorf("(ACTPOOL) the exit did not ask the roster whether the pool can claim: %s", r)
	}

	w = newWorld(t)
	code, _, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--route", "gc-toolkit/gc-toolkit.nosuch", "--run", root)
	wantCode(t, code, 2, err, "(ACTPOOL) a pool that cannot claim")
	w.hasnt("TAKEAWAY", "(ACTPOOL) the bead is not released")
	errHas(t, err, "hand it with --assign", "(ACTPOOL) the refusal names the named agent's address")
	errHas(t, err, "only when the next move is the operator's", "(ACTPOOL) …keeping the operator's exits for the operator's move")

	w = newWorld(t)
	w.takeawayFails = true
	code, out, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "routed to the polecat pool", "--route", "gc-toolkit/gc-toolkit.polecat", "--run", root)
	wantCode(t, code, 4, err, "(ACTREFUSED) a release the store refuses")
	errHas(t, err, "could not write the headline on tk-sub", "(ACTREFUSED) the failure carries the takeaway's own words")
	if out != "" {
		t.Errorf("(ACTREFUSED) the exit reported %q", out)
	}

	w = newWorld(t)
	code, _, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--run", root)
	wantCode(t, code, 0, err, "(ACTRIG) with GC_RIG set the pool needs no flag")
	w.has("--route gc-toolkit/gc-toolkit.polecat", "(ACTRIG) the route defaults to the rig's polecat pool")
	w = newWorld(t)
	w.r.Rig = ""
	d := parse(t, "tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--run", root)
	err = Validate(w.rt, "", d)
	errHas(t, err, "routes to nobody", "(ACTRIG) with no rig and no --route the exit fails closed")
}

// Work that is a named agent's own is handed to it in the form it takes work
// in. The mechanik takes Gas City's own route, after the release leaves the
// bead at rest, unassigned and unrouted, and is nudged once bd reports the bead
// ready; a bead that waits gets no nudge, since its blocker's close sends one.
func TestActionableHandsTheMechanikItsRoute(t *testing.T) {
	w := newWorld(t)
	code, out, err := w.dispose("tk-sub", "--disposition", "actionable", "--reason", "the remedy is a city.toml edit, mechanik's direct edit",
		"--takeaway", "city.toml edit routed to mechanik", "--assign", "gc-toolkit.mechanik", "--run", root)
	wantCode(t, code, 0, err, "(ACTASSIGN) an actionable exit to a named agent")
	if out != "tk-sub disposed as actionable (gc-toolkit.mechanik)" {
		t.Errorf("(ACTASSIGN) the exit reported %q", out)
	}
	w.has("TAKEAWAY tk-sub city.toml edit routed to mechanik --by proactive --release --no-wait", "(ACTASSIGN) the release leaves the bead at rest")
	for _, l := range w.lines("TAKEAWAY ") {
		if strings.Contains(l, "--assign") || strings.Contains(l, "--route") {
			t.Errorf("(ACTASSIGN) the release wrote an address: %s", l)
		}
	}
	if s := w.lines("SLING "); len(s) != 1 || s[0] != "SLING gc-toolkit.mechanik tk-sub --no-formula --no-convoy --rig gc-toolkit" {
		t.Errorf("(ACTHANDOFF) the hand-off slung %q", s)
	}
	w.before("TAKEAWAY", "SLING ", "(ACTHANDOFF) the hand-off follows the release")
	w.hasnt("ARM ", "(ACTHANDOFF) nothing is armed for a named agent")
	w.has("NUDGE gc-toolkit.mechanik tk-sub is routed to you and ready", "(ACTHANDOFF) the agent is nudged with the bead's id")
	w.before("SLING ", "NUDGE ", "(ACTHANDOFF) once the bead is routed to it")
	if r := strings.Join(w.rt.Reads(), ","); !strings.Contains(r, "named") {
		t.Errorf("(ACTASSIGN) the exit did not ask whether the agent's hook would offer the bead: %s", r)
	}

	// A bead bd does not report ready is handed over with no nudge.
	w = waitingWorld(t)
	code, _, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--assign", "gc-toolkit.mechanik", "--run", root)
	wantCode(t, code, 0, err, "(ACTWAITS) a bead bd does not report ready")
	w.has("SLING gc-toolkit.mechanik tk-sub --no-formula --no-convoy", "(ACTWAITS) it is routed to the agent")
	w.hasnt("NUDGE", "(ACTWAITS) with no nudge while a blocker holds it")

	w = newWorld(t)
	w.r.Rig = ""
	code, _, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--assign", "gc-toolkit.mechanik")
	wantCode(t, code, 0, err, "(ASSIGNRIG) a named agent needs no rig")
	w.has("SLING gc-toolkit.mechanik tk-sub --no-formula --no-convoy", "(ASSIGNRIG) it is addressed by its own name")
}

// waitingWorld is a world in which bd does not report the subject ready.
func waitingWorld(t *testing.T) *world {
	w := newWorld(t)
	s, _ := w.store.Row("tk-sub")
	store := fake.New()
	store.OnWrite, store.OnFind = w.store.OnWrite, w.store.OnFind
	for _, id := range []string{"tk-epic", "tk-blk1"} {
		b, _ := w.store.Row(id)
		store.Put(b)
	}
	store.Put(s)
	w.store = store
	w.r.Ledger = ledger.New(store)
	w.sync()
	return w
}

// A hand-off the agent's hook could never reach refuses the exit before
// anything is written, naming the address form; --route beside --assign is
// refused; and each exit refuses the other exits' hand-off flags.
func TestAHandOffNothingWouldOfferIsRefused(t *testing.T) {
	w := newWorld(t)
	code, _, err := w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--assign", "mechanik")
	wantCode(t, code, 2, err, "(ASSIGNNO) an agent the roster does not register")
	errHas(t, err, "exact qualified name", "(ASSIGNNO) the refusal names the address form")
	if got := w.writes(); len(got) != 0 {
		t.Errorf("(ASSIGNNO) wrote %q", got)
	}

	w = newWorld(t)
	code, _, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--route", "gc-toolkit/gc-toolkit.polecat", "--assign", "gc-toolkit.mechanik")
	wantCode(t, code, 2, err, "(ASSIGNBOTH) --route beside --assign")
	errHas(t, err, "not both", "(ASSIGNBOTH) the refusal says a bead takes one address")

	for name, args := range map[string][]string{
		"actionable --then-assign": {"--disposition", "actionable", "--then-assign", "gc-toolkit.mechanik"},
		"close --assign":           {"--disposition", "close", "--assign", "gc-toolkit.mechanik"},
		"ruling --assign":          {"--disposition", "ruling", "--assign", "gc-toolkit.mechanik"},
		"ruling --then-assign":     {"--disposition", "ruling", "--then-assign", "gc-toolkit.mechanik"},
		"blocked --assign":         {"--disposition", "blocked", "--waiting-on", "tk-blk1", "--assign", "gc-toolkit.mechanik"},
	} {
		w := newWorld(t)
		code, _, err := w.dispose(append([]string{"tk-sub", "--reason", "r", "--takeaway", "t"}, args...)...)
		wantCode(t, code, 2, err, "(ASSIGNEXIT) "+name)
		if got := w.writes(); len(got) != 0 {
			t.Errorf("(ASSIGNEXIT) %s wrote %q", name, got)
		}
	}
}

// A hand-off that does not land fails the exit with its own reason, and a
// re-run resumes it: a sling gc sling refused, a nudge that did not reach the
// agent, and a readiness read that does not answer, which leaves whether the
// agent is owed a nudge unknown.
func TestAHandOffThatDoesNotLandFailsTheExit(t *testing.T) {
	w := newWorld(t)
	w.slingFails = true
	code, _, err := w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--assign", "gc-toolkit.mechanik", "--run", root)
	wantCode(t, code, 4, err, "(HANDOFFFAIL) a hand-off gc sling refused")
	errHas(t, err, "gc sling did not hand it to gc-toolkit.mechanik (exit 1: gc sling: fake refusal)", "(HANDOFFFAIL) with gc sling's reason")
	errHas(t, err, "a re-run resumes", "(HANDOFFFAIL) saying a re-run resumes")
	w.has("TAKEAWAY tk-sub", "(HANDOFFFAIL) after the release, which stands")
	w.hasnt("NUDGE", "(HANDOFFFAIL) no agent is nudged about a bead it was not handed")

	w = newWorld(t)
	w.nudgeFails = true
	code, _, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--assign", "gc-toolkit.mechanik", "--run", root)
	wantCode(t, code, 4, err, "(HANDOFFFAIL) a nudge that did not reach the agent")
	errHas(t, err, "gc session nudge did not reach the agent (exit 1: gc session nudge: fake refusal)", "(HANDOFFFAIL) with the nudge's reason")
	w.has("SLING ", "(HANDOFFFAIL) after the route, which stands")

	w = newWorld(t)
	w.store.ReadyErr = errors.New("gc bd ready exited 1: fake refusal")
	code, _, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--assign", "gc-toolkit.mechanik", "--run", root)
	wantCode(t, code, 4, err, "(HANDOFFREAD) a readiness read that does not answer")
	errHas(t, err, "whether bd reports it ready could not be read (gc bd ready exited 1", "(HANDOFFREAD) saying the read did not answer")
	w.has("SLING ", "(HANDOFFREAD) after the route, which stands")
	w.hasnt("NUDGE", "(HANDOFFREAD) with no nudge")
}

// The refinery lists the beads assigned to it, so it takes the assignee, which
// the release writes, and is nudged since the bead is ready; nothing is routed.
// The keeper is no target of a first reaction, and the po, the deacon and the
// witness take no bead; any other agent has no form this exit knows. Each is
// refused before anything is read or written.
func TestTheRefineryTakesTheAssigneeAndTheOthersAreRefused(t *testing.T) {
	w := newWorld(t)
	code, _, err := w.dispose("tk-sub", "--disposition", "actionable", "--reason", "the branch is ready for the merge queue",
		"--takeaway", "branch handed to the refinery", "--assign", "gc-toolkit/gc-toolkit.refinery", "--run", root)
	wantCode(t, code, 0, err, "(ACTREFINERY) an actionable exit to the refinery")
	w.has("TAKEAWAY tk-sub branch handed to the refinery --by proactive --release --assign gc-toolkit/gc-toolkit.refinery --no-wait",
		"(ACTREFINERY) the release writes the refinery as the assignee and says nothing waits")
	w.hasnt("SLING", "(ACTREFINERY) routing nothing")
	w.has("NUDGE gc-toolkit/gc-toolkit.refinery tk-sub is assigned to you and ready", "(ACTREFINERY) the refinery is nudged")
	w.before("TAKEAWAY", "NUDGE ", "(ACTREFINERY) once the release has assigned it")

	w = newWorld(t)
	w.nudgeFails = true
	code, _, err = w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--assign", "gc-toolkit/gc-toolkit.refinery", "--run", root)
	wantCode(t, code, 4, err, "(HANDOFFFAIL) an assignee whose nudge did not reach the agent")
	errHas(t, err, "It is assigned to gc-toolkit/gc-toolkit.refinery, but gc session nudge did not reach the agent", "(HANDOFFFAIL) saying the assignment stands")

	for who, says := range map[string]string{
		"gascity/gascity-keeper.keeper": "names the keeper, and a first reaction hands no bead to the keeper",
		"gc-toolkit.keeper":             "names the keeper",
		"gc-toolkit.deacon":             "names an agent that patrols its own wisps and takes no bead",
		"deacon":                        "gc mail send deacon",
		"gc-toolkit/gc-toolkit.witness": "gc mail send gc-toolkit/gc-toolkit.witness",
		"gc-toolkit/gc-toolkit.po":      "names the po, which takes no work by assignment",
		"gc-toolkit/gc-toolkit.dog":     "names no agent this exit can hand a bead to",
	} {
		w := newWorld(t)
		code, _, err := w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--assign", who, "--run", root)
		wantCode(t, code, 2, err, "--assign "+who)
		errHas(t, err, "--assign "+who+" ", "the refusal names the flag and the agent")
		errHas(t, err, says, "the refusal says why")
		if len(w.log) != 0 || len(w.rt.Reads()) != 0 {
			t.Errorf("--assign %s read or wrote %q %q", who, w.log, w.rt.Reads())
		}
	}
	w = newWorld(t)
	code, _, err = w.dispose("tk-sub", "--disposition", "blocked", "--reason", "r", "--takeaway", "t", "--waiting-on", "tk-blk1", "--then-assign", "gc-toolkit/gc-toolkit.witness", "--run", root)
	wantCode(t, code, 2, err, "(PATROL) --then-assign naming the witness")
	errHas(t, err, "--then-assign gc-toolkit/gc-toolkit.witness names an agent that patrols its own wisps", "(PATROL) naming the flag")
	w = newWorld(t)
	code, _, err = w.dispose("tk-sub", "--disposition", "blocked", "--reason", "r", "--takeaway", "t", "--waiting-on", "tk-blk1", "--then-assign", "gc-toolkit.keeper", "--run", root)
	wantCode(t, code, 2, err, "--then-assign naming the keeper")
	errHas(t, err, "--then-assign gc-toolkit.keeper names the keeper", "the refusal names the flag")
}
