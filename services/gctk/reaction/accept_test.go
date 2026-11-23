package reaction

import (
	"encoding/json"
	"errors"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	rtfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// acceptWorld is an acceptance's surroundings: a store holding tk-anc, which
// carries the recommendation mol-fix and hold:mayor, and its open
// recommendation gate tk-g1; a city whose root holds the acceptance locks; and
// one log of every write, disarm and sling across them, in order.
type acceptWorld struct {
	t     *testing.T
	store *fake.Store
	rt    *rtfake.Runtime
	r     *Reactions

	mu       sync.Mutex
	log      []string
	said     []string
	sessions []gascity.Session

	// disarmErr fails the disarm, slingCode is the exit a sling answers, and
	// pour, when set, is the root the sling pours, which may carry a failure's
	// marks, even when the sling exits non-zero.
	disarmErr error
	slingCode int
	pour      *fake.Bead
}

func newAcceptWorld(t *testing.T) *acceptWorld {
	t.Helper()
	w := &acceptWorld{t: t, store: fake.New()}
	w.store.CloseTime = "2026-11-20T06:00:00Z"
	w.store.Put(fake.Bead{ID: "tk-anc", Title: "the subject", Status: "open", IssueType: "task", Labels: []string{"hold:mayor"},
		Metadata: map[string]string{"gc.recommended_formula": "mol-fix"},
		Edges:    []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "tk-g1", Status: "open"}}})
	w.store.Put(fake.Bead{ID: "tk-g1", Title: "take mol-fix?", Status: "open", IssueType: "gate", AwaitType: "human",
		AwaitID: GateKey, CreatedAt: "2026-11-20T01:00:00Z"})
	w.store.OnWrite = func(kind, id string, args []string) {
		w.add(strings.ToUpper(kind) + " " + id + " " + strings.Join(args, " "))
	}
	w.rt = &rtfake.Runtime{Root: t.TempDir()}
	w.rt.OnSling = func(s gascity.Sling) gascity.SlingResult {
		w.add("SLING " + s.Bead + " --on " + s.Formula + " --title " + s.Title + " --rig " + s.Rig + " target=" + s.Target + " vars=" + strings.Join(s.Vars, ","))
		if w.pour != nil {
			root := *w.pour
			root.Title = s.Title
			w.store.Put(root)
		}
		if w.slingCode != 0 {
			return gascity.SlingResult{Result: gascity.Result{Code: w.slingCode, Output: "gc sling: simulated"}}
		}
		return gascity.SlingResult{}
	}
	w.r = &Reactions{
		Ledger:  ledger.New(w.store),
		Runtime: w.rt,
		Rig:     "gc-toolkit",
		Now:     func() time.Time { return time.Date(2026, 11, 20, 6, 0, 0, 0, time.UTC) },
		Log:     func(line string) { w.mu.Lock(); w.said = append(w.said, line); w.mu.Unlock() },
		Disarm: func(id, reason string) (string, error) {
			w.add("DISARM " + id)
			if w.disarmErr != nil {
				return "", w.disarmErr
			}
			return id + " carries no arm, so nothing was written", nil
		},
		Sessions: func() ([]gascity.Session, error) { return w.sessions, nil },
	}
	return w
}

func (w *acceptWorld) add(line string) {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.log = append(w.log, strings.TrimSpace(line))
}

func (w *acceptWorld) lines() []string {
	w.mu.Lock()
	defer w.mu.Unlock()
	return slices.Clone(w.log)
}

func (w *acceptWorld) index(prefix string) int {
	return slices.IndexFunc(w.lines(), func(l string) bool { return strings.HasPrefix(l, prefix) })
}

func (w *acceptWorld) row(id string) fake.Bead {
	r, _ := w.store.Row(id)
	return r
}

func (w *acceptWorld) accept(req AcceptRequest) (Accepted, error) {
	if req.Bead == "" {
		req.Bead = "tk-anc"
	}
	return w.r.Accept(req)
}

// code is the exit an acceptance's error gives, 0 for none.
func code(t *testing.T, err error) int {
	t.Helper()
	if err == nil {
		return 0
	}
	var u *Unaccepted
	if !errors.As(err, &u) {
		t.Fatalf("error %v is no Unaccepted", err)
	}
	return u.Code
}

// wantStop asserts the acceptance stopped with code and a message naming want.
func wantStop(t *testing.T, err error, c int, want string) {
	t.Helper()
	if got := code(t, err); got != c || !strings.Contains(err.Error(), want) {
		t.Fatalf("Accept = %v (exit %d), want exit %d naming %q", err, got, c, want)
	}
}

func TestAcceptDispatchesTheRecommendationOnce(t *testing.T) {
	w := newAcceptWorld(t)
	out, err := w.accept(AcceptRequest{Reason: "take it"})
	if err != nil {
		t.Fatalf("Accept: %v", err)
	}
	answer := "ruled: accepted mol-fix accept:" + out.Token
	if len(out.Token) != 16 || out.Formula != "mol-fix" {
		t.Fatalf("Accept = %+v, want mol-fix under a 16-digit token", out)
	}
	gate := w.row("tk-g1")
	if gate.Status != "closed" || gate.CloseReason != answer {
		t.Errorf("gate = %+v, want it closed with the acceptance's answer", gate)
	}
	var in acceptance
	if err := json.Unmarshal([]byte(gate.Metadata["gc.acceptance"]), &in); err != nil || in.Token != out.Token || in.Formula != "mol-fix" || in.Vars == nil {
		t.Errorf("gc.acceptance = %q, want the token, the formula and an empty vars list", gate.Metadata["gc.acceptance"])
	}
	disarm, record, resolve := w.index("DISARM tk-anc"), w.index("UPDATE tk-g1 --set-metadata gc.acceptance="), w.index("GATE-RESOLVE tk-g1 --reason "+answer)
	sling, lift, mark := w.index("SLING tk-anc --on mol-fix --title mol-fix accept:"+out.Token+" --rig gc-toolkit target="), w.index("UPDATE tk-anc --remove-label hold:mayor"),
		w.index("UPDATE tk-anc --set-metadata gc.recommended_formula_dispatched=mol-fix --unset-metadata gc.recommended_formula")
	if disarm != 0 || record < disarm || resolve < record || sling < resolve || lift < sling || mark < lift {
		t.Errorf("order %v, want the disarm first, then the record, the answer, the sling, the lift and the dispatch's record", w.lines())
	}
	anc := w.row("tk-anc")
	if anc.Metadata["gc.recommended_formula"] != "" || slices.Contains(anc.Labels, "hold:mayor") ||
		!strings.Contains(anc.Notes, "Accept dispatched mol-fix (acceptance "+out.Token+"): take it; gc.recommended_formula withdrawn.") {
		t.Errorf("tk-anc = %+v, want the recommendation withdrawn, the hold lifted and the note", anc)
	}
	_, err = w.accept(AcceptRequest{})
	wantStop(t, err, 2, "its recommendation was dispatched (mol-fix)")
	if n := len(w.rt.Slings()); n != 1 {
		t.Errorf("slings = %d, want one across two Accepts", n)
	}
}

func TestAcceptRefusesWhatItDoesNotAnswer(t *testing.T) {
	for _, tc := range []struct {
		name string
		prep func(*acceptWorld)
		code int
		want string
	}{
		{"no recommendation", func(w *acceptWorld) {
			w.store.Put(fake.Bead{ID: "tk-anc", Status: "open", IssueType: "task", Edges: []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "tk-g1"}}})
		}, 2, "discuss-only"},
		{"no gate asks it", func(w *acceptWorld) {
			w.store.Put(fake.Bead{ID: "tk-anc", Status: "open", IssueType: "task", Metadata: map[string]string{"gc.recommended_formula": "mol-fix"}})
		}, 4, "no human gate under the key first-reaction"},
		{"its gate assigned to a person", func(w *acceptWorld) {
			g := w.row("tk-g1")
			g.Assignee = "alice"
			w.store.Put(g)
		}, 4, "tk-g1 (assigned to alice) is that person's to clear"},
		{"another gate beside it", func(w *acceptWorld) {
			w.store.Put(fake.Bead{ID: "tk-rev", Title: "review it", Status: "open", IssueType: "gate", AwaitType: "human", AwaitID: "review"})
			a := w.row("tk-anc")
			a.Edges = append(a.Edges, gcbd.Edge{Type: gcbd.EdgeBlocks, ID: "tk-rev", Status: "open"})
			w.store.Put(a)
		}, 4, "another human gate still blocks tk-anc: tk-rev (review it)"},
		{"its gate answered otherwise", func(w *acceptWorld) {
			g := w.row("tk-g1")
			g.Status, g.CloseReason = "closed", "ruled: decline it"
			w.store.Put(g)
		}, 4, `was answered: "ruled: decline it". That answer stands`},
		{"a bead the store does not hold", func(w *acceptWorld) {}, 4, "bead not found: tk-gone"},
		{"a var with no key", func(w *acceptWorld) {}, 2, "--var takes <key>=<value>"},
		{"a disarm that does not land", func(w *acceptWorld) { w.disarmErr = errors.New("its lock is held") }, 4, "that disarm did not land (its lock is held)"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			w := newAcceptWorld(t)
			tc.prep(w)
			req := AcceptRequest{}
			switch tc.name {
			case "a bead the store does not hold":
				req.Bead = "tk-gone"
			case "a var with no key":
				req.Vars = []string{"=x"}
			}
			_, err := w.accept(req)
			wantStop(t, err, tc.code, tc.want)
			if len(w.rt.Slings()) != 0 || len(w.store.Resolves()) != 0 || len(w.store.Writes()) != 0 {
				t.Errorf("a refusal acted: %v", w.lines())
			}
		})
	}
}

func TestAcceptOfAStoreThatDoesNotAnswer(t *testing.T) {
	w := newAcceptWorld(t)
	w.store.FindErr = &gcbd.ReadError{Reason: "the store did not answer"}
	_, err := w.accept(AcceptRequest{})
	wantStop(t, err, 4, "could not verify tk-anc")
}

// A record the store refuses stops the acceptance before its answer, since a
// finish reads the input off the gate.
func TestAcceptWhoseRecordIsRefusedAnswersNothing(t *testing.T) {
	w := newAcceptWorld(t)
	w.store.BeforeUpdate = func(id string, args []string) error {
		if id == "tk-g1" {
			return errors.New("bd refused")
		}
		return nil
	}
	_, err := w.accept(AcceptRequest{})
	wantStop(t, err, 4, "could not record acceptance")
	if len(w.store.Resolves()) != 0 || len(w.rt.Slings()) != 0 {
		t.Errorf("lines %v, want no answer and no sling", w.lines())
	}
}

// The first answer to reach the gate stands: bd's resolve exits 0 on a gate
// already closed, so the read after it tells this answer from another's, and
// Accept slings nothing and reopens nothing.
func TestAcceptBesideAnAnswerThatReachedTheGateFirst(t *testing.T) {
	w := newAcceptWorld(t)
	w.store.BeforeResolve = func(id, reason string) error {
		g := w.row(id)
		g.Status, g.CloseReason = "closed", "ruled: the sitting decided otherwise"
		w.store.Put(g)
		return nil
	}
	_, err := w.accept(AcceptRequest{})
	wantStop(t, err, 4, `another answer reached tk-anc's recommendation gate first: tk-g1: "ruled: the sitting decided otherwise"`)
	if len(w.rt.Slings()) != 0 || len(w.store.Reopens()) != 0 {
		t.Errorf("slings %v, reopens %v, want neither", w.rt.Slings(), w.store.Reopens())
	}
	if g := w.row("tk-g1"); g.CloseReason != "ruled: the sitting decided otherwise" {
		t.Errorf("gate = %+v, want the first answer standing", g)
	}
}

// A gate filed between the live read and the answer holds the bead, so the
// recommendation goes back on the board rather than starting ahead of it.
func TestAcceptBesideAGateFiledAfterItsRead(t *testing.T) {
	w := newAcceptWorld(t)
	w.store.BeforeResolve = func(id, reason string) error {
		w.store.Put(fake.Bead{ID: "tk-late", Title: "a late question", Status: "open", IssueType: "gate", AwaitType: "human", AwaitID: "late"})
		a := w.row("tk-anc")
		a.Edges = append(a.Edges, gcbd.Edge{Type: gcbd.EdgeBlocks, ID: "tk-late", Status: "open"})
		w.store.Put(a)
		return nil
	}
	_, err := w.accept(AcceptRequest{})
	wantStop(t, err, 4, "a human gate filed since Accept read tk-anc blocks it: tk-late (a late question)")
	if len(w.rt.Slings()) != 0 {
		t.Errorf("slung %v ahead of the late gate", w.rt.Slings())
	}
	if g := w.row("tk-g1"); g.Status != "open" || len(w.store.Reopens()) != 1 {
		t.Errorf("gate = %+v, reopens %v; want the recommendation's gate open again", g, w.store.Reopens())
	}
}

func TestAcceptCarriesItsVars(t *testing.T) {
	w := newAcceptWorld(t)
	out, err := w.accept(AcceptRequest{Vars: []string{"design_gated=false", "k=a b=c"}})
	if err != nil {
		t.Fatalf("Accept: %v", err)
	}
	if s := w.rt.Slings(); len(s) != 1 || !slices.Equal(s[0].Vars, []string{"design_gated=false", "k=a b=c"}) {
		t.Errorf("slings = %+v, want the vars on the sling", s)
	}
	var in acceptance
	_ = json.Unmarshal([]byte(w.row("tk-g1").Metadata["gc.acceptance"]), &in)
	if in.Token != out.Token || !slices.Equal(in.Vars, []string{"design_gated=false", "k=a b=c"}) {
		t.Errorf("gc.acceptance = %+v, want the vars under the token", in)
	}
}

// stopAfterAnswer leaves the world as an Accept that stopped right after its
// answer leaves it: the input recorded and the gate closed under the token.
func stopAfterAnswer(w *acceptWorld, token string, vars []string) {
	raw, _ := json.Marshal(acceptance{Token: token, Formula: "mol-fix", Vars: vars})
	g := w.row("tk-g1")
	g.Status, g.CloseReason = "closed", "ruled: accepted mol-fix accept:"+token
	g.Metadata = map[string]string{"gc.acceptance": string(raw)}
	w.store.Put(g)
}

const token = "0123456789abcdef"

func TestAcceptFinishesAnAcceptanceLeftUnfinished(t *testing.T) {
	w := newAcceptWorld(t)
	stopAfterAnswer(w, token, []string{"design_gated=false"})
	out, err := w.accept(AcceptRequest{})
	if err != nil || out.Token != token || !out.Finished || out.Root != "" {
		t.Fatalf("Accept = %+v, %v; want the acceptance finished under its token", out, err)
	}
	if s := w.rt.Slings(); len(s) != 1 || s[0].Title != "mol-fix accept:"+token || !slices.Equal(s[0].Vars, []string{"design_gated=false"}) {
		t.Errorf("slings = %+v, want one sling under the token with the recorded vars", s)
	}
	if len(w.store.Resolves()) != 0 {
		t.Errorf("a finish answered the gate again: %v", w.store.Resolves())
	}
	if a := w.row("tk-anc"); a.Metadata["gc.recommended_formula_dispatched"] != "mol-fix" || slices.Contains(a.Labels, "hold:mayor") {
		t.Errorf("tk-anc = %+v, want the dispatch recorded and the hold lifted", a)
	}
}

// A finish whose sling poured already records the dispatch and slings nothing,
// so an acceptance is dispatched once, even after the work it sent finished.
func TestAcceptFinishesWithoutASecondPour(t *testing.T) {
	w := newAcceptWorld(t)
	stopAfterAnswer(w, token, nil)
	w.store.Put(fake.Bead{ID: "tk-root", Title: "mol-fix accept:" + token, Status: "closed", IssueType: "molecule"})
	out, err := w.accept(AcceptRequest{Vars: []string{"x=1"}})
	if err != nil || out.Root != "tk-root" {
		t.Fatalf("Accept = %+v, %v; want the earlier pour recorded", out, err)
	}
	if len(w.rt.Slings()) != 0 {
		t.Errorf("slung %v beside a root that carries the token", w.rt.Slings())
	}
	if a := w.row("tk-anc"); a.Metadata["gc.recommended_formula_dispatched"] != "mol-fix" {
		t.Errorf("tk-anc = %+v, want the dispatch recorded", a)
	}
	if !slices.ContainsFunc(w.said, func(s string) bool { return strings.Contains(s, "keeps the vars it was poured with") }) {
		t.Errorf("said %v, want a word that the --var does not reach the poured root", w.said)
	}
}

// A root a gate-typed pour titled with the token counts, which a listing that
// leaves gates out would miss.
func TestAcceptFindsAGateTypedRoot(t *testing.T) {
	w := newAcceptWorld(t)
	stopAfterAnswer(w, token, nil)
	w.store.Put(fake.Bead{ID: "tk-root", Title: "mol-fix accept:" + token, Status: "open", IssueType: "gate"})
	if out, err := w.accept(AcceptRequest{}); err != nil || out.Root != "tk-root" {
		t.Fatalf("Accept = %+v, %v; want the gate-typed root found", out, err)
	}
	for _, q := range w.store.Finds() {
		if q.TitleContains != "" && q.Listed {
			t.Errorf("the token search %+v reads only what bd lists unasked, which leaves gates out", q)
		}
	}
}

func TestAcceptFinishRefusals(t *testing.T) {
	for _, tc := range []struct {
		name string
		prep func(*acceptWorld)
		vars []string
		want string
	}{
		{"vars that differ from the acceptance's", func(w *acceptWorld) { stopAfterAnswer(w, token, []string{"a=1"}) },
			[]string{"a=2"}, "was accepted with --var a=1, and this run was given --var a=2"},
		{"no recorded input", func(w *acceptWorld) {
			stopAfterAnswer(w, token, nil)
			g := w.row("tk-g1")
			g.Metadata = nil
			w.store.Put(g)
		}, nil, "records no dispatch input for acceptance " + token},
		{"a gate filed after the stop", func(w *acceptWorld) {
			stopAfterAnswer(w, token, nil)
			w.store.Put(fake.Bead{ID: "tk-late", Title: "late", Status: "open", IssueType: "gate", AwaitType: "human", AwaitID: "late"})
			a := w.row("tk-anc")
			a.Edges = append(a.Edges, gcbd.Edge{Type: gcbd.EdgeBlocks, ID: "tk-late", Status: "open"})
			w.store.Put(a)
		}, nil, "another human gate still blocks tk-anc"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			w := newAcceptWorld(t)
			tc.prep(w)
			_, err := w.accept(AcceptRequest{Vars: tc.vars})
			wantStop(t, err, 4, tc.want)
			if len(w.rt.Slings()) != 0 {
				t.Errorf("slung %v", w.rt.Slings())
			}
		})
	}
}

// A root under the token that Gas City stamped as failed, open or closed, is an
// attempt that failed and no dispatch, so the finish slings again. Any other
// root is the dispatch, one Gas City still fences among them, so the finish
// records it and slings nothing.
func TestAcceptFinishReadsARootByItsFailureStamp(t *testing.T) {
	for _, tc := range []struct {
		name   string
		root   fake.Bead
		slings int
	}{
		{"an open root that failed part way", fake.Bead{Status: "open", IssueType: "molecule", Metadata: map[string]string{"molecule_failed": "true"}}, 1},
		{"a closed root that failed part way", fake.Bead{Status: "closed", IssueType: "molecule", Metadata: map[string]string{"molecule_failed": "true"}}, 1},
		{"an open root still fenced", fake.Bead{Status: "open", IssueType: "gate", Metadata: map[string]string{"gc.instantiating": "true"}}, 0},
	} {
		t.Run(tc.name, func(t *testing.T) {
			w := newAcceptWorld(t)
			stopAfterAnswer(w, token, nil)
			root := tc.root
			root.ID, root.Title = "tk-root", "mol-fix accept:"+token
			w.store.Put(root)
			out, err := w.accept(AcceptRequest{})
			if err != nil || len(w.rt.Slings()) != tc.slings {
				t.Fatalf("Accept = %+v, %v, slings %v; want %d sling(s)", out, err, w.rt.Slings(), tc.slings)
			}
			if wantRoot := map[int]string{0: "tk-root", 1: ""}[tc.slings]; out.Root != wantRoot {
				t.Errorf("root = %q, want %q", out.Root, wantRoot)
			}
			if a := w.row("tk-anc"); a.Metadata["gc.recommended_formula_dispatched"] != "mol-fix" {
				t.Errorf("tk-anc = %+v, want the dispatch recorded", a)
			}
		})
	}
}

// A sling can fail after its pour committed, and that pour runs, so the
// token's root decides whether the dispatch landed.
func TestAcceptReadsTheTokenRootAfterAFailedSling(t *testing.T) {
	for _, tc := range []struct {
		name  string
		code  int
		pour  *fake.Bead
		exit  int
		want  string
		reopn bool
	}{
		{"a pour that committed", 1, &fake.Bead{ID: "tk-root", Status: "open", IssueType: "molecule"}, 0, "", false},
		{"a pour still fenced", 1, &fake.Bead{ID: "tk-root", Status: "open", IssueType: "gate",
			Metadata: map[string]string{"gc.instantiating": "true"}}, 0, "", false},
		{"no pour", 1, nil, 1, "landed no pour under acceptance", true},
		{"a pour that failed part way", 1, &fake.Bead{ID: "tk-root", Status: "open", IssueType: "molecule",
			Metadata: map[string]string{"molecule_failed": "true"}}, 1, "landed no pour under acceptance", true},
		{"Gas City's launch lock", 3, nil, 1, "which Gas City's launch lock refused to start twice", true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			w := newAcceptWorld(t)
			w.slingCode, w.pour = tc.code, tc.pour
			_, err := w.accept(AcceptRequest{})
			if tc.exit == 0 {
				if err != nil {
					t.Fatalf("Accept: %v", err)
				}
				if a := w.row("tk-anc"); a.Metadata["gc.recommended_formula_dispatched"] != "mol-fix" {
					t.Errorf("tk-anc = %+v, want the dispatch recorded", a)
				}
				return
			}
			wantStop(t, err, tc.exit, tc.want)
			if got := w.row("tk-g1").Status == "open"; got != tc.reopn {
				t.Errorf("gate open = %v, want %v", got, tc.reopn)
			}
		})
	}
}

// A stop after the sling leaves the hold on, and the next Accept finishes the
// lift and the record without a second dispatch.
func TestAcceptStoppedAfterItsSlingIsFinishedWithoutASecondOne(t *testing.T) {
	w := newAcceptWorld(t)
	w.pour = &fake.Bead{ID: "tk-root", Status: "open", IssueType: "molecule"}
	w.store.BeforeUpdate = func(id string, args []string) error {
		if id == "tk-anc" && slices.Contains(args, "--remove-label") {
			return errors.New("bd refused")
		}
		return nil
	}
	_, err := w.accept(AcceptRequest{})
	wantStop(t, err, 4, "the write that lifts its hold:mayor did not land")
	if !slices.Contains(w.row("tk-anc").Labels, "hold:mayor") {
		t.Fatalf("the hold was lifted by a stopped Accept")
	}
	w.store.BeforeUpdate = nil
	out, err := w.accept(AcceptRequest{})
	if err != nil || out.Root != "tk-root" || len(w.rt.Slings()) != 1 || slices.Contains(w.row("tk-anc").Labels, "hold:mayor") {
		t.Fatalf("finish = %+v, %v, slings %v; want the lift and the record with one sling in all", out, err, w.rt.Slings())
	}
}

// Every Accept on a bead runs under its acceptance lock, and one that finds
// the lock held refuses and writes nothing.
func TestAcceptRefusesWhileAnotherHoldsTheLock(t *testing.T) {
	w := newAcceptWorld(t)
	release, _, err := w.r.acceptLock("tk-anc")
	if err != nil || release == nil {
		t.Fatalf("acceptLock = %v", err)
	}
	_, err = w.accept(AcceptRequest{})
	wantStop(t, err, 4, "another Accept on tk-anc holds its acceptance lock (pid ")
	if len(w.lines()) != 0 {
		t.Errorf("a refused Accept acted: %v", w.lines())
	}
	release()
	if _, err := w.accept(AcceptRequest{}); err != nil {
		t.Fatalf("Accept once the lock is released: %v", err)
	}
}

// Two Accepts at once on one bead dispatch once: the second finds the first
// one's lock while it slings.
func TestAcceptRacingAnotherDispatchesOnce(t *testing.T) {
	w := newAcceptWorld(t)
	var second error
	first := w.rt.OnSling
	w.rt.OnSling = func(s gascity.Sling) gascity.SlingResult {
		_, second = w.accept(AcceptRequest{})
		return first(s)
	}
	if _, err := w.accept(AcceptRequest{}); err != nil {
		t.Fatalf("first Accept: %v", err)
	}
	wantStop(t, second, 4, "holds its acceptance lock")
	if n := len(w.rt.Slings()); n != 1 {
		t.Errorf("slings = %d, want one", n)
	}
}

func TestAcceptWithNoCityRoot(t *testing.T) {
	w := newAcceptWorld(t)
	w.rt.RootErr = errors.New("no city root is named")
	_, err := w.accept(AcceptRequest{})
	wantStop(t, err, 3, "cannot take tk-anc's acceptance lock")
}

// A live sitting that holds a conversation replying to the recommendation's
// gate is warned of, and Accept clears the gate anyway. The conversation the
// call names is the caller's own and is not.
func TestAcceptWarnsOfALiveSitting(t *testing.T) {
	for _, tc := range []struct {
		name, own string
		warn      bool
	}{
		{"another sitting's", "", true},
		{"the caller's own", "tk-conv", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			w := newAcceptWorld(t)
			w.store.Put(fake.Bead{ID: "tk-conv", Status: "in_progress", IssueType: "task", Assignee: "gc-toolkit/gc-toolkit.tk-conv",
				Edges: []gcbd.Edge{{Type: "tracks", ID: "tk-other", Status: "open"}, {Type: "replies-to", ID: "tk-g1", Status: "open"}}})
			w.store.Put(fake.Bead{ID: "tk-other", Status: "open", IssueType: "task"})
			w.sessions = []gascity.Session{{ID: "s-1", Alias: "gc-toolkit/gc-toolkit.tk-conv"}}
			if _, err := w.accept(AcceptRequest{Conversation: tc.own}); err != nil {
				t.Fatalf("Accept: %v", err)
			}
			warned := slices.ContainsFunc(w.said, func(s string) bool { return strings.Contains(s, "a live sitting holds conversation tk-conv") })
			if warned != tc.warn {
				t.Errorf("said %v; warned %v, want %v", w.said, warned, tc.warn)
			}
		})
	}
}

func TestAcceptSubject(t *testing.T) {
	for _, tc := range []struct {
		name, ref, want, stop string
		prep                  func(*acceptWorld)
	}{
		{"a bead", "tk-anc", "tk-anc", "", nil},
		{"the recommendation's gate", "tk-g1", "tk-anc", "", nil},
		{"a gate several beads wait on", "tk-g1", "", "is about 2 beads still waiting on it (tk-anc tk-two)", func(w *acceptWorld) {
			w.store.Put(fake.Bead{ID: "tk-two", Status: "open", IssueType: "task", Edges: []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "tk-g1"}}})
		}},
		{"a gate nothing waits on", "tk-g1", "", "nothing waits on gate tk-g1", func(w *acceptWorld) {
			w.store.Put(fake.Bead{ID: "tk-anc", Status: "closed", IssueType: "task", Edges: []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "tk-g1"}}})
		}},
		{"a conversation", "tk-conv", "tk-anc", "", func(w *acceptWorld) {
			w.store.Put(fake.Bead{ID: "tk-conv", Status: "open", IssueType: "task", Assignee: "human",
				Edges: []gcbd.Edge{{Type: "tracks", ID: "tk-anc", Status: "open"}}})
		}},
		{"a closed bead", "tk-old", "tk-new", "", func(w *acceptWorld) {
			w.store.Put(fake.Bead{ID: "tk-old", Status: "closed", IssueType: "task"})
			w.rt.OnScript = func(c rtfake.Call) gascity.Result {
				if c.Name == "gc-helm.sh" && slices.Equal(c.Args, []string{"resolve", "tk-old"}) {
					return gascity.Result{Output: "gc-helm: tk-old is closed and superseded\ntk-new\n"}
				}
				return gascity.Result{Code: 2}
			}
		}},
		{"a bead the store does not hold", "tk-gone", "", "bead not found: tk-gone", nil},
	} {
		t.Run(tc.name, func(t *testing.T) {
			w := newAcceptWorld(t)
			if tc.prep != nil {
				tc.prep(w)
			}
			got, err := w.r.Subject(tc.ref)
			if tc.stop != "" {
				wantStop(t, err, 4, tc.stop)
				return
			}
			if err != nil || got != tc.want {
				t.Fatalf("Subject(%s) = %q, %v; want %q", tc.ref, got, err, tc.want)
			}
		})
	}
}

func TestIsPRReference(t *testing.T) {
	for ref, want := range map[string]bool{"1563": true, "https://github.com/o/r/pull/12": true, "tk-anc": false, "12a": false} {
		if got := IsPRReference(ref); got != want {
			t.Errorf("IsPRReference(%q) = %v, want %v", ref, got, want)
		}
	}
}
