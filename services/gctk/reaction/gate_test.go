package reaction

import (
	"errors"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
)

// The ruling exit files the human gate itself, under the key first-reaction
// with no quiet window, the takeaway as its title and the reason and the run in
// its message, then releases the subject held on the gate; a call by hand names
// no run, and a gate that did not file fails the exit before the release.
func TestRulingFilesItsGateThenReleases(t *testing.T) {
	w := newWorld(t)
	code, out, err := w.dispose("tk-sub", "--disposition", "ruling", "--reason", "the trade-off is the operator's",
		"--takeaway", "needs a ruling: which default", "--run", root)
	wantCode(t, code, 0, err, "(RUL) a ruling exit")
	gates := w.lines("GATE ")
	if len(gates) != 1 || !strings.HasPrefix(gates[0], "GATE --subject tk-sub --key first-reaction --message needs a ruling: which default\n") ||
		strings.Contains(gates[0], "--quiet-window") {
		t.Fatalf("(RULKEY) the gate calls were %q", gates)
	}
	if !strings.Contains(gates[0], "the trade-off is the operator's") || !strings.Contains(gates[0], "Filed by a first reaction on tk-sub (ruling, run "+root+"), which waits on it.") {
		t.Errorf("(RULRUN) the gate's message was %q", gates[0])
	}
	w.has("TAKEAWAY tk-sub needs a ruling: which default --by proactive --release --waiting-on tk-gate1", "(RUL) the subject is released, held on the gate")
	w.hasnt("--route", "(RUL) not routed")
	w.hasnt("--no-wait", "(RUL) and never called settled")
	w.hasnt("CREATE", "(RUL) and files nothing else")
	if out != "tk-sub disposed as ruling (tk-gate1)" {
		t.Errorf("(RUL) the exit reported %q", out)
	}
	w.before("GATE --subject", "TAKEAWAY", "(RULORDER) the gate before the release")

	w = newWorld(t)
	_, _, err = w.dispose("tk-sub", "--disposition", "ruling", "--reason", "the trade-off is the operator's", "--takeaway", "needs a ruling: which default")
	if err != nil || !strings.Contains(w.lines("GATE ")[0], "Filed by a first reaction on tk-sub (ruling), which waits on it.") {
		t.Errorf("(RULRUN) a ruling by hand named a run, or failed: %v %q", err, w.lines("GATE "))
	}

	w = newWorld(t)
	w.gateFails = true
	code, _, err = w.dispose("tk-sub", "--disposition", "ruling", "--reason", "r", "--takeaway", "t", "--run", root)
	wantCode(t, code, 4, err, "(RULGATE) a gate that did not file")
	w.hasnt("TAKEAWAY", "(RULGATE) the subject is not released onto a gate that does not exist")
	errHas(t, err, "re-run this command", "(RULGATE) the failure names the retry")

	w = newWorld(t)
	code, _, err = w.dispose("tk-sub", "--disposition", "ruling", "--reason", "r", "--takeaway", strings.Repeat("needs a ruling ", 12), "--run", root)
	wantCode(t, code, 2, err, "(RULCAP) a takeaway over 140 characters")
	if len(w.log) != 0 {
		t.Errorf("(RULCAP) read or wrote %q", w.log)
	}

	w = newWorld(t)
	w.subject(func(b *fake.Bead) { b.Metadata = map[string]string{"gc.origin": "operator"} })
	for _, exit := range [][]string{
		{"--disposition", "actionable", "--route", "gc-toolkit/gc-toolkit.polecat"},
		{"--disposition", "blocked", "--waiting-on", "tk-blk1"},
		{"--disposition", "ruling"},
	} {
		code, _, err := w.dispose(append([]string{"tk-sub", "--reason", "r", "--takeaway", "t", "--run", root}, exit...)...)
		wantCode(t, code, 0, err, "(ORIGIN) an operator-origin subject takes "+exit[1])
	}
}

// supersededGate puts on the subject a gate under key, at status, of issue
// type typ, that asks an older reaction's question.
func supersededGate(w *world, status, key, typ string) {
	w.store.Put(fake.Bead{ID: "tk-gate0", Title: "an older reaction asked this", Description: "an older reaction asked this",
		Status: status, IssueType: typ, AwaitType: "human", AwaitID: key})
	w.subject(func(b *fake.Bead) {
		b.Edges = append(b.Edges, gcbd.Edge{Type: gcbd.EdgeBlocks, ID: "tk-gate0", Status: status})
	})
}

// Which gates still ask is the one rule of a human gate: under this key, a gate,
// at any status but closed, in any case. A superseded reaction's gate the rule
// reads as open is withdrawn before the exit files its own, and a read of the
// gates that does not answer stops the exit with no gate withdrawn or filed.
func TestASupersededGateIsWithdrawnFirst(t *testing.T) {
	for _, status := range []string{"open", "pinned", "in_progress"} {
		w := newWorld(t)
		supersededGate(w, status, "first-reaction", "gate")
		code, _, err := w.dispose("tk-sub", "--disposition", "ruling", "--reason", "r", "--takeaway", "needs a ruling: which default", "--run", root)
		wantCode(t, code, 0, err, "(RULRULE) a ruling beside a gate at "+status)
		w.has("GATE --retract --subject tk-sub --key first-reaction", "(RULRULE) a superseded gate at "+status+" is withdrawn")
		w.before("GATE --retract", "GATE --subject tk-sub --key first-reaction --message", "(RULRULE) before the exit files its own")
	}
	for _, c := range []struct{ status, key, typ string }{
		{"closed", "first-reaction", "gate"}, {"CLOSED", "first-reaction", "gate"}, {"Closed", "first-reaction", "gate"},
		{"open", "another-key", "gate"}, {"open", "first-reaction", "task"},
	} {
		w := newWorld(t)
		supersededGate(w, c.status, c.key, c.typ)
		code, _, err := w.dispose("tk-sub", "--disposition", "ruling", "--reason", "r", "--takeaway", "needs a ruling: which default", "--run", root)
		wantCode(t, code, 0, err, "(RULRULE) a ruling beside "+c.typ+" "+c.key+" at "+c.status)
		w.hasnt("--retract", "(RULRULE) "+c.typ+" "+c.key+" at "+c.status+" asks nothing, so nothing is withdrawn")
	}

	w := newWorld(t)
	reads := 0
	w.store.OnFind = func(q gcbd.Query) {
		if !slices.Equal(q.IDs, []string{"tk-sub"}) {
			return
		}
		if reads++; reads == 2 {
			w.store.FindErr = errors.New("gc bd list exited 1: fake refusal")
		}
	}
	code, _, err := w.dispose("tk-sub", "--disposition", "ruling", "--reason", "r", "--takeaway", "needs a ruling: which default", "--run", root)
	wantCode(t, code, 4, err, "(RULREAD) a gate read the store refuses")
	errHas(t, err, "could not read the human gates of tk-sub", "(RULREAD) saying so")
	w.hasnt("GATE ", "(RULREAD) neither withdrawing nor filing a gate")
}

// The recommend exit files the same gate, whose message names the formula,
// and stamps gc.recommended_formula only once the gate is filed. It needs a
// formula Gas City resolves, and the ruling exit takes none.
func TestRecommendStampsItsFormulaAfterTheGate(t *testing.T) {
	w := newWorld(t)
	code, _, err := w.dispose("tk-sub", "--disposition", "recommend", "--reason", "retire the PR, supersede its anchor — operator authority",
		"--takeaway", "recommend: retire PR + supersede anchor; execute via mol-x — Accept or Discuss", "--recommended-formula", "mol-x", "--run", root)
	wantCode(t, code, 0, err, "(RECO) a recommend exit")
	w.has("--set-metadata gc.recommended_formula=mol-x", "(RECO) the formula is stamped on the subject")
	gate := w.lines("GATE ")[0]
	if !strings.HasPrefix(gate, "GATE --subject tk-sub --key first-reaction --message recommend: retire PR + supersede anchor; execute via mol-x — Accept or Discuss") ||
		!strings.Contains(gate, "It recommends mol-x, the formula Accept runs on tk-sub.") || !strings.Contains(gate, "(recommend, run "+root+")") {
		t.Errorf("(RECO) the gate was %q", gate)
	}
	w.has("--waiting-on tk-gate1", "(RECO) the gate holds the subject")
	w.before("GATE --subject", "gc.recommended_formula=mol-x", "(RECO) the recommendation lands once the gate is filed")
	w.before("GATE --subject", "TAKEAWAY", "(RECO) the gate before the release")
	if s, _ := w.store.Row("tk-sub"); s.Metadata["gc.recommended_formula"] != "mol-x" {
		t.Errorf("(RECO) the subject carries %q", s.Metadata["gc.recommended_formula"])
	}

	w = newWorld(t)
	code, _, err = w.dispose("tk-sub", "--disposition", "recommend", "--reason", "operator authority", "--takeaway", "recommend: execute via <mol>", "--run", root)
	wantCode(t, code, 2, err, "(RECO) recommend with no formula")
	errHas(t, err, "is --disposition ruling", "(RECO) naming ruling as the flagless exit")
	w = newWorld(t)
	code, _, err = w.dispose("tk-sub", "--disposition", "recommend", "--reason", "r", "--takeaway", "t", "--recommended-formula", "mol-typo", "--run", root)
	wantCode(t, code, 2, err, "(RECO) a formula that does not resolve")
	errHas(t, err, "does not resolve to a formula", "(RECO) naming it")
	if got := w.writes(); len(got) != 0 {
		t.Errorf("(RECO) wrote %q for an unresolved formula", got)
	}
	for _, exit := range []string{"ruling", "actionable", "close"} {
		w := newWorld(t)
		code, _, err := w.dispose("tk-sub", "--disposition", exit, "--reason", "r", "--takeaway", "t", "--recommended-formula", "mol-x", "--run", root)
		wantCode(t, code, 2, err, "(RECO) "+exit+" refuses --recommended-formula")
		errHas(t, err, "belongs to the recommend exit", "(RECO) pointing at the exit that carries a recommendation")
	}
	w = newWorld(t)
	code, _, err = w.dispose("tk-sub", "--disposition", "blocked", "--reason", "r", "--takeaway", "t", "--waiting-on", "tk-blk1", "--recommended-formula", "mol-x", "--run", root)
	wantCode(t, code, 2, err, "(RECO) blocked refuses --recommended-formula")

	w = newWorld(t)
	code, _, err = w.dispose("tk-sub", "--disposition", "ruling", "--reason", "r", "--takeaway", "needs a ruling: which default", "--run", root)
	wantCode(t, code, 0, err, "(RECO) a Discuss-only ruling")
	w.hasnt("gc.recommended_formula", "(RECO) a ruling stamps no recommendation")
}

// A recommendation already on the subject is cleared before the gate is filed,
// and a recommend stamps its own after it, so no recommendation is older than
// the newest first-reaction gate. A set or a clear the store refuses stops the
// exit before the act, so no superseded Accept is left executable.
func TestTheRecommendationIsTrueWhenItIsRead(t *testing.T) {
	stale := func(w *world) {
		w.subject(func(b *fake.Bead) { b.Metadata = map[string]string{"gc.recommended_formula": "mol-old"} })
	}
	w := newWorld(t)
	stale(w)
	code, _, err := w.dispose("tk-sub", "--disposition", "ruling", "--reason", "on reflection this is a plain discussion", "--takeaway", "needs a ruling: which default", "--run", root)
	wantCode(t, code, 0, err, "(RECO) a ruling over a stale recommendation")
	w.has("--unset-metadata gc.recommended_formula", "(RECO) the stale recommendation is cleared")
	w.hasnt("gc.recommended_formula=", "(RECO) and no new one stamped")

	w = newWorld(t)
	stale(w)
	code, _, err = w.dispose("tk-sub", "--disposition", "recommend", "--reason", "the newer mol is the right execution", "--takeaway", "recommend: execute via mol-x", "--recommended-formula", "mol-x", "--run", root)
	wantCode(t, code, 0, err, "(RECO) a re-recommend over a stale recommendation")
	w.before("--unset-metadata gc.recommended_formula", "GATE --subject", "(RECOORDER) the older recommendation is cleared before the gate")
	w.before("GATE --subject", "gc.recommended_formula=mol-x", "(RECOORDER) and the new one stamped after it")

	refuse := func(w *world, text string) {
		w.store.BeforeUpdate = func(id string, args []string) error {
			if strings.Contains(strings.Join(args, " "), text) {
				return errors.New("Error updating: the store refused it")
			}
			return nil
		}
	}
	w = newWorld(t)
	refuse(w, "gc.recommended_formula=")
	code, _, err = w.dispose("tk-sub", "--disposition", "recommend", "--reason", "operator authority", "--takeaway", "recommend: execute via mol-x", "--recommended-formula", "mol-x", "--run", root)
	wantCode(t, code, 4, err, "(RECOGUARD) a recommendation set the store refuses")
	w.hasnt("TAKEAWAY", "(RECOGUARD) the release is withheld")
	errHas(t, err, "the store refused gc.recommended_formula=mol-x", "(RECOGUARD) naming the key")
	errHas(t, err, "The gate tk-gate1 is filed", "(RECOGUARD) saying the gate is filed")

	w = newWorld(t)
	stale(w)
	refuse(w, "--unset-metadata gc.recommended_formula")
	code, _, err = w.dispose("tk-sub", "--disposition", "ruling", "--reason", "r", "--takeaway", "needs a ruling: which default", "--run", root)
	wantCode(t, code, 4, err, "(RECOGUARD) a stale clear the store refuses")
	w.hasnt("TAKEAWAY", "(RECOGUARD) the act is withheld")
	w.hasnt("GATE ", "(RECOGUARD) and no gate is filed beside the older recommendation")
	errHas(t, err, "the store refused the clear of the earlier recommendation", "(RECOGUARD) naming the stale key")
}

// Over a store that keeps the gates, two recommends with one headline and two
// formulas leave one open gate, which names the second formula, as the subject
// does; the same recommend run again keeps its gate; and a gate whose title the
// helper cut to fit bd, or a takeaway that spans lines, is kept by a re-run.
func TestAGateExitRunTwiceKeepsOneGate(t *testing.T) {
	head := "recommend: fix the flaky suite; execute via a fix formula — discuss if the cause is upstream"
	w := newWorld(t)
	w.rt.Resolves = append(w.rt.Resolves, "mol-fix-a", "mol-fix-b")
	w.gateID = "tk-g1"
	code, _, err := w.dispose("tk-sub", "--run", "tk-root-a", "--disposition", "recommend", "--reason", "the suite's own fixture is the cause", "--takeaway", head, "--recommended-formula", "mol-fix-a")
	wantCode(t, code, 0, err, "(RECO2) the first recommend")
	w.gateID = "tk-g2"
	code, _, err = w.dispose("tk-sub", "--run", "tk-root-b", "--disposition", "recommend", "--reason", "the cause is the order of the suite's cases", "--takeaway", head, "--recommended-formula", "mol-fix-b")
	wantCode(t, code, 0, err, "(RECO2) a second recommend with another formula")
	if g, _ := w.store.Row("tk-g1"); g.Status != "closed" {
		t.Errorf("(RECO2) the first gate is %s, want withdrawn", g.Status)
	}
	g2, _ := w.store.Row("tk-g2")
	if g2.Status != "open" || !strings.Contains(g2.Description, "mol-fix-b") || strings.Contains(g2.Description, "mol-fix-a") ||
		!strings.Contains(g2.Description, "the cause is the order of the suite's cases") {
		t.Errorf("(RECO2) the open gate is %+v", g2)
	}
	if s, _ := w.store.Row("tk-sub"); s.Metadata["gc.recommended_formula"] != "mol-fix-b" {
		t.Errorf("(RECO2) the subject recommends %q", s.Metadata["gc.recommended_formula"])
	}
	w.reset()
	code, out, err := w.dispose("tk-sub", "--run", "tk-root-b", "--disposition", "recommend", "--reason", "the cause is the order of the suite's cases", "--takeaway", head, "--recommended-formula", "mol-fix-b")
	wantCode(t, code, 0, err, "(RECOAGAIN) the same recommend again")
	w.hasnt("--retract", "(RECOAGAIN) withdrawing nothing")
	if out != "tk-sub disposed as recommend (tk-g2)" {
		t.Errorf("(RECOAGAIN) the exit reported %q", out)
	}
	if !slices.Contains(strings.Fields(g2.Description), "tk-root-b),") {
		t.Errorf("(RECOCHECK) the gate's message does not name its run among its words: %q", g2.Description)
	}

	cjk := strings.Repeat("問", 134)
	w = newWorld(t)
	message := gateMessage(&Dispose{Bead: "tk-sub", Disposition: Ruling, Run: root, Reason: "r"}, cjk)
	w.store.Put(fake.Bead{ID: "tk-gcut", Title: strings.Repeat("問", 130) + "…", Description: message, Status: "open", IssueType: "gate", AwaitType: "human", AwaitID: GateKey})
	w.subject(func(b *fake.Bead) {
		b.Edges = append(b.Edges, gcbd.Edge{Type: gcbd.EdgeBlocks, ID: "tk-gcut", Status: "open"})
	})
	code, _, err = w.dispose("tk-sub", "--run", root, "--disposition", "ruling", "--reason", "r", "--takeaway", cjk)
	wantCode(t, code, 0, err, "(RULTITLE) a ruling whose gate's title the helper cut")
	w.hasnt("--retract", "(RULTITLE) withdrawing nothing, since the gate's whole brief is this exit's")

	w = newWorld(t)
	code, _, err = w.dispose("tk-sub", "--run", root, "--disposition", "ruling", "--reason", "r", "--takeaway", "needs a ruling:\nwhich default")
	wantCode(t, code, 0, err, "(RULTITLE) a takeaway that spans lines")
	if g, _ := w.store.Row("tk-gate1"); g.Title != "needs a ruling: which default" {
		t.Errorf("(RULTITLE) the gate's title is %q, want the one line the board shows", g.Title)
	}
	w.reset()
	code, _, err = w.dispose("tk-sub", "--run", root, "--disposition", "ruling", "--reason", "r", "--takeaway", "needs a ruling:\nwhich default")
	wantCode(t, code, 0, err, "(RULTITLE) the re-run")
	w.hasnt("--retract", "(RULTITLE) a re-run finds the gate it filed and withdraws nothing")
}
