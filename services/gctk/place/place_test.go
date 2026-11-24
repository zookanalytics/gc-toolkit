package place

import (
	"errors"
	"fmt"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/arm"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	rtfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	rx "github.com/zookanalytics/gc-toolkit/services/gctk/reaction"
	"github.com/zookanalytics/gc-toolkit/services/gctk/takeaway"
)

const pool = "gc-toolkit/gc-toolkit.polecat"

// world is a placement's surroundings: a store holding the open epic tk-epic
// and the held bead tk-new, a city whose roster runs the rig's polecat pool,
// and one log of every write, script, sling and arm across them, in order.
type world struct {
	t     *testing.T
	store *fake.Store
	rt    *rtfake.Runtime
	p     *Places

	mu  sync.Mutex
	log []string

	// scriptFails fails the queue-priority.sh verb it names, slingCode is the
	// exit a sling answers, and armErr fails an arm.
	scriptFails string
	slingCode   int
	armErr      error
	arms        []arm.Request
}

func newWorld(t *testing.T) *world {
	t.Helper()
	w := &world{t: t, store: fake.New()}
	w.store.Put(fake.Bead{ID: "tk-epic", Title: "the epic", Status: "open", IssueType: "epic", Priority: 1})
	w.store.Put(fake.Bead{ID: "tk-new", Title: "new work", Status: "open", IssueType: "task", Priority: 2, Labels: []string{"hold:mayor"}})
	w.store.OnWrite = func(kind, id string, args []string) {
		w.add(strings.ToUpper(kind) + " " + id + " " + strings.Join(args, " "))
	}
	w.rt = &rtfake.Runtime{
		Root: t.TempDir(),
		Roster: []gascity.Agent{
			{QualifiedName: pool, Name: "polecat", Dir: "gc-toolkit", Scope: "rig"},
			{QualifiedName: "other/gc-toolkit.polecat", Name: "polecat", Dir: "other", Scope: "rig"},
		},
	}
	w.rt.OnScript = func(c rtfake.Call) gascity.Result {
		w.add("SCRIPT " + c.Name + " " + strings.Join(c.Args, " "))
		if len(c.Args) > 0 && c.Args[0] == w.scriptFails {
			return gascity.Result{Code: 1, Output: "queue-priority: simulated refusal"}
		}
		return gascity.Result{}
	}
	w.rt.OnSling = func(s gascity.Sling) gascity.SlingResult {
		line := "SLING " + s.Target + " " + s.Bead + " --rig " + s.Rig
		if s.Formula != "" {
			line += " --on " + s.Formula
		}
		w.add(line)
		if w.slingCode != 0 {
			return gascity.SlingResult{Result: gascity.Result{Code: w.slingCode, Output: "gc sling: simulated"}}
		}
		return gascity.SlingResult{}
	}
	w.p = &Places{
		Ledger:  ledger.New(w.store),
		Runtime: w.rt,
		Rig:     "gc-toolkit",
		DB:      "/rig/.beads",
		Now:     func() time.Time { return time.Date(2026, 11, 20, 6, 0, 0, 0, time.UTC) },
	}
	w.p.Arm = func(req arm.Request) (string, error) {
		w.mu.Lock()
		w.arms = append(w.arms, req)
		w.mu.Unlock()
		w.add("ARM " + req.ID + " --target " + req.Target + " --on " + req.Formula)
		if w.armErr != nil {
			return "", w.armErr
		}
		return "armed " + req.ID, nil
	}
	return w
}

func (w *world) add(line string) {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.log = append(w.log, strings.TrimSpace(line))
}

func (w *world) lines() []string {
	w.mu.Lock()
	defer w.mu.Unlock()
	return slices.Clone(w.log)
}

// index is the place of the first line that starts with prefix, -1 for none.
func (w *world) index(prefix string) int {
	return slices.IndexFunc(w.lines(), func(l string) bool { return strings.HasPrefix(l, prefix) })
}

func (w *world) row(id string) fake.Bead {
	r, _ := w.store.Row(id)
	return r
}

func parentOf(b fake.Bead) string {
	for _, e := range b.Edges {
		if e.Type == gcbd.EdgeParentChild {
			return e.ID
		}
	}
	return ""
}

func TestPlaceUnderAnEpic(t *testing.T) {
	w := newWorld(t)
	out, err := w.p.Place(Request{Bead: "tk-new", Under: "tk-epic"})
	if err != nil {
		t.Fatalf("Place: %v", err)
	}
	got := w.row("tk-new")
	if parentOf(got) != "tk-epic" || slices.Contains(got.Labels, "hold:mayor") {
		t.Errorf("tk-new = %+v, want its parent tk-epic and its hold lifted", got)
	}
	parent, settle, sling, lift := w.index("UPDATE tk-new --parent"), w.index("SCRIPT queue-priority.sh settle tk-new"),
		w.index("SLING "+pool+" tk-new"), w.index("UPDATE tk-new --remove-label hold:mayor")
	if parent < 0 || settle < parent || sling < settle || lift < sling {
		t.Errorf("order %v, want the parent, then the settle, then the sling, then the lift", w.lines())
	}
	if !strings.Contains(w.lines()[sling], "--rig gc-toolkit") {
		t.Errorf("sling %q runs under no rig", w.lines()[sling])
	}
	if !strings.Contains(w.lines()[settle], "--db /rig/.beads") {
		t.Errorf("settle %q names no store", w.lines()[settle])
	}
	// The lift and its note ride one write.
	if l := w.lines()[lift]; !strings.Contains(l, "--append-notes Placed at 2026-11-20T06:00:00Z under tk-epic at P2: slung to "+pool+". hold:mayor lifted.") {
		t.Errorf("the lift %q carries no note in the same write", l)
	}
	if want := "place: tk-new placed under tk-epic at P2: slung to " + pool + "; hold:mayor lifted"; out.Line(Request{Bead: "tk-new", Under: "tk-epic"}) != want {
		t.Errorf("line = %q, want %q", out.Line(Request{Bead: "tk-new", Under: "tk-epic"}), want)
	}
}

// bd refuses a parent-child edge beside a relates-to link on the same pair, so
// the link goes first.
func TestPlaceRemovesARelatesToLinkBeforeTheParent(t *testing.T) {
	w := newWorld(t)
	w.store.Put(fake.Bead{ID: "tk-new", Status: "open", IssueType: "task", Labels: []string{"hold:mayor"},
		Edges: []gcbd.Edge{{Type: gcbd.EdgeRelatesTo, ID: "tk-epic", Status: "open"}}})
	w.store.Put(fake.Bead{ID: "tk-epic", Status: "open", IssueType: "epic",
		Edges: []gcbd.Edge{{Type: gcbd.EdgeRelatesTo, ID: "tk-new", Status: "open"}}})
	if _, err := w.p.Place(Request{Bead: "tk-new", Under: "tk-epic"}); err != nil {
		t.Fatalf("Place: %v", err)
	}
	unrelate, parent := w.index("UNRELATE tk-new tk-epic"), w.index("UPDATE tk-new --parent tk-epic")
	if unrelate < 0 || parent < unrelate {
		t.Errorf("order %v, want the link removed before the parent is set", w.lines())
	}
}

func TestPlaceWithAShiftARouteAndAFormula(t *testing.T) {
	w := newWorld(t)
	req := Request{Bead: "tk-new", Under: "tk-epic", Shift: "+1", Route: "gc-toolkit/gc-toolkit.other", Formula: "mol-x"}
	if _, err := w.p.Place(req); err != nil {
		t.Fatalf("Place: %v", err)
	}
	move, settle := w.index("SCRIPT queue-priority.sh move tk-new --shift +1 --db /rig/.beads"), w.index("SCRIPT queue-priority.sh settle")
	if move < 0 || settle < move {
		t.Errorf("order %v, want the shift moved before the settle", w.lines())
	}
	if w.index("SLING gc-toolkit/gc-toolkit.other tk-new --rig gc-toolkit --on mol-x") < 0 {
		t.Errorf("lines %v, want the bead slung to the route on the formula", w.lines())
	}
}

func TestPlaceStandalone(t *testing.T) {
	w := newWorld(t)
	out, err := w.p.Place(Request{Bead: "tk-new", Standalone: true})
	if err != nil || parentOf(w.row("tk-new")) != "" || w.index("UPDATE tk-new --parent") >= 0 {
		t.Fatalf("Place = %+v, %v, lines %v; want no parent written", out, err, w.lines())
	}
	if !strings.Contains(out.Line(Request{Bead: "tk-new", Standalone: true}), "placed with no parent") {
		t.Errorf("line %q", out.Line(Request{Bead: "tk-new", Standalone: true}))
	}
}

// Gas City reads its hold trimmed and in any case, and bd removes a label by
// its exact text, so the lift removes each spelling the bead carries.
func TestPlaceLiftsEverySpellingOfTheHold(t *testing.T) {
	w := newWorld(t)
	w.store.Put(fake.Bead{ID: "tk-new", Status: "open", IssueType: "task", Labels: []string{"Hold:Mayor ", "hold:mayor", "keep"}})
	if _, err := w.p.Place(Request{Bead: "tk-new", Standalone: true}); err != nil {
		t.Fatalf("Place: %v", err)
	}
	if got := w.row("tk-new").Labels; !slices.Equal(got, []string{"keep"}) {
		t.Errorf("labels = %v, want each spelling of the hold lifted and the rest kept", got)
	}
}

// A bead a wait holds, a parent's park among them, is armed rather than slung,
// so the wait keeps holding it.
func TestPlaceArmsABeadAWaitHolds(t *testing.T) {
	for _, tc := range []struct {
		name string
		prep func(*fake.Store)
		why  string
	}{
		{"a park on its epic", func(s *fake.Store) {
			s.Put(fake.Bead{ID: "tk-park", Title: "parked", Status: "open", IssueType: "gate"})
			s.Put(fake.Bead{ID: "tk-epic", Status: "open", IssueType: "epic", Edges: []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "tk-park", Status: "open", Title: "parked"}}})
			s.List("tk-epic", "tk-park")
			s.Mark("tk-epic")
			s.List("tk-new", "tk-epic")
			s.Mark("tk-new")
		}, `tk-park "parked" on ancestor tk-epic`},
		{"a blocker of its own", func(s *fake.Store) {
			s.Put(fake.Bead{ID: "tk-blk", Title: "first", Status: "open", IssueType: "task"})
			s.Put(fake.Bead{ID: "tk-new", Status: "open", IssueType: "task", Labels: []string{"hold:mayor"},
				Edges: []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "tk-blk", Status: "open", Title: "first"}}})
			s.List("tk-new", "tk-blk")
			s.Mark("tk-new")
		}, `tk-blk "first"`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			w := newWorld(t)
			tc.prep(w.store)
			out, err := w.p.Place(Request{Bead: "tk-new", Under: "tk-epic"})
			if err != nil {
				t.Fatalf("Place: %v", err)
			}
			if w.index("SLING") >= 0 || len(w.arms) != 1 || w.arms[0].Target != pool || !strings.Contains(w.arms[0].Reason, tc.why) {
				t.Fatalf("lines %v, arms %+v; want one arm for %s naming %s, and no sling", w.lines(), w.arms, pool, tc.why)
			}
			if !strings.Contains(out.How, "armed for "+pool+", held by "+tc.why) {
				t.Errorf("how = %q", out.How)
			}
			if slices.Contains(w.row("tk-new").Labels, "hold:mayor") {
				t.Errorf("the hold stayed on an armed placement")
			}
		})
	}
}

func TestPlaceRefusesWhatItDoesNotPlace(t *testing.T) {
	for _, tc := range []struct {
		name string
		req  Request
		prep func(*fake.Store)
		want string
	}{
		{"both placements", Request{Bead: "tk-new", Under: "tk-epic", Standalone: true}, nil, "two placements"},
		{"neither placement", Request{Bead: "tk-new"}, nil, "--under <parent>"},
		{"a shift with no parent", Request{Bead: "tk-new", Standalone: true, Shift: "+1"}, nil, "--shift ranks a member"},
		{"a shift that is no number", Request{Bead: "tk-new", Under: "tk-epic", Shift: "up"}, nil, "not a signed integer"},
		{"a bare route", Request{Bead: "tk-new", Standalone: true, Route: "polecat"}, nil, "not rig-qualified"},
		{"its own parent", Request{Bead: "tk-new", Under: "tk-new"}, nil, "its own parent"},
		{"a closed bead", Request{Bead: "tk-new", Standalone: true}, func(s *fake.Store) {
			s.Put(fake.Bead{ID: "tk-new", Status: "closed", IssueType: "task", Labels: []string{"hold:mayor"}})
		}, "is closed"},
		{"PR-finishing work", Request{Bead: "tk-new", Under: "tk-epic"}, func(s *fake.Store) {
			s.Put(fake.Bead{ID: "tk-new", Status: "open", IssueType: "task", Labels: []string{"hold:mayor"}, Metadata: map[string]string{"anchor_bead": "tk-anc"}})
		}, "PR-finishing work of tk-anc"},
		{"no hold and no dispatch", Request{Bead: "tk-new", Standalone: true}, func(s *fake.Store) {
			s.Put(fake.Bead{ID: "tk-new", Status: "open", IssueType: "task"})
		}, "gc bd set-state tk-new hold=mayor"},
		{"hold:external beside", Request{Bead: "tk-new", Standalone: true}, func(s *fake.Store) {
			s.Put(fake.Bead{ID: "tk-new", Status: "open", IssueType: "task", Labels: []string{"hold:mayor", " Hold:External"}})
		}, "also carries Hold:External"},
		{"a status set on purpose", Request{Bead: "tk-new", Standalone: true}, func(s *fake.Store) {
			s.Put(fake.Bead{ID: "tk-new", Status: "deferred", IssueType: "task", Labels: []string{"hold:mayor"}})
		}, "is deferred"},
		{"standalone with a parent", Request{Bead: "tk-new", Standalone: true}, func(s *fake.Store) {
			s.Put(fake.Bead{ID: "tk-new", Status: "open", IssueType: "task", Labels: []string{"hold:mayor"},
				Edges: []gcbd.Edge{{Type: gcbd.EdgeParentChild, ID: "tk-epic", Status: "open"}}})
		}, "--under tk-epic"},
		{"a closed parent", Request{Bead: "tk-new", Under: "tk-epic"}, func(s *fake.Store) {
			s.Put(fake.Bead{ID: "tk-epic", Status: "closed", IssueType: "epic"})
		}, "tk-epic is closed"},
		{"armed for another pool", Request{Bead: "tk-new", Under: "tk-epic"}, func(s *fake.Store) {
			s.Put(fake.Bead{ID: "tk-new", Status: "open", IssueType: "task", Labels: []string{"hold:mayor"},
				Metadata: map[string]string{"gc.dispatch_when_ready": "gc-toolkit/gc-toolkit.other", "gc.dispatch_when_ready_armed_at": "t"}})
		}, "gctk bead disarm tk-new --db /rig/.beads"},
		{"armed for its validating closer", Request{Bead: "tk-new", Under: "tk-epic"}, func(s *fake.Store) {
			s.Put(fake.Bead{ID: "tk-new", Status: "open", IssueType: "task", Labels: []string{"hold:mayor"},
				Metadata: map[string]string{"gc.dispatch_when_ready": "gc-toolkit/gc-toolkit.other", "gc.dispatch_when_ready_armed_at": "t",
					"gc.dispatch_when_ready_args": `["--on","mol-validate-close"]`}})
		}, "Lift its hold and keep the arm: gc bd update tk-new --remove-label 'hold:mayor' --db /rig/.beads"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			w := newWorld(t)
			if tc.prep != nil {
				tc.prep(w.store)
			}
			_, err := w.p.Place(tc.req)
			if !Refused(err) || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("Place = %v, want a refusal naming %q", err, tc.want)
			}
			if len(w.store.Writes())+len(w.rt.Slings())+len(w.arms)+len(w.rt.Scripts()) != 0 {
				t.Errorf("a refusal acted: %v", w.lines())
			}
		})
	}
}

// A bead with no hold that a dispatch already shows is placed already, and
// nothing is written.
func TestPlaceOfABeadPlacedAlready(t *testing.T) {
	for _, tc := range []struct {
		name string
		bead fake.Bead
		want string
	}{
		{"assigned", fake.Bead{Assignee: "polecat-1"}, "assigned to polecat-1"},
		{"routed", fake.Bead{Metadata: map[string]string{"gc.routed_to": pool}}, "routed to " + pool},
		{"armed", fake.Bead{Metadata: map[string]string{"gc.dispatch_when_ready": pool, "gc.dispatch_when_ready_armed_at": "t"}}, "armed for " + pool},
		{"landing", fake.Bead{Metadata: map[string]string{"merge_result": "pull_request"}}, "merge_result=pull_request"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			w := newWorld(t)
			b := tc.bead
			b.ID, b.Status, b.IssueType = "tk-new", "open", "task"
			w.store.Put(b)
			out, err := w.p.Place(Request{Bead: "tk-new", Under: "tk-epic"})
			if err != nil || !out.Already || !strings.Contains(out.How, tc.want) {
				t.Fatalf("Place = %+v, %v; want placed already, naming %q", out, err, tc.want)
			}
			if len(w.store.Writes())+len(w.rt.Slings()) != 0 {
				t.Errorf("a placed bead was written: %v", w.lines())
			}
		})
	}
}

// liveRun pours a live run of formula for bead.
func liveRun(s *fake.Store, bead, root, formula string) {
	s.Put(fake.Bead{ID: root + "-cv", Status: "open", IssueType: "convoy", Edges: []gcbd.Edge{{Type: "tracks", ID: bead, Status: "open"}}})
	s.Put(fake.Bead{ID: root, Status: "in_progress", Metadata: map[string]string{
		"gc.kind": "workflow", "gc.input_convoy_id": root + "-cv", "gc.formula_name": formula}})
}

// A held bead with a live run is dispatched already: the next placement lifts
// its hold and dispatches nothing more. A first reaction's run is no dispatch,
// since it triages the bead and works none of it, so a placement dispatches a
// bead one is live on, and the reaction's exit then lands only its headline.
// A build's run beside a reaction's is the dispatch all the same.
func TestPlaceReadsALiveRunAsTheDispatch(t *testing.T) {
	w := newWorld(t)
	liveRun(w.store, "tk-new", "tk-r1", "mol-polecat-work")
	out, err := w.p.Place(Request{Bead: "tk-new", Under: "tk-epic"})
	if err != nil || !strings.Contains(out.How, "already dispatched (live run tk-r1)") || len(w.rt.Slings()) != 0 {
		t.Fatalf("Place = %+v, %v, slings %v; want the live run read as the dispatch", out, err, w.rt.Slings())
	}
	if slices.Contains(w.row("tk-new").Labels, "hold:mayor") {
		t.Errorf("the hold stayed on")
	}

	w = newWorld(t)
	liveRun(w.store, "tk-new", "tk-r2", "mol-first-reaction")
	if _, err := w.p.Place(Request{Bead: "tk-new", Under: "tk-epic"}); err != nil || len(w.rt.Slings()) != 1 ||
		slices.Contains(w.row("tk-new").Labels, "hold:mayor") {
		t.Fatalf("a bead a first reaction runs on: %v, slings %v; want it slung and its hold lifted", err, w.rt.Slings())
	}

	w = newWorld(t)
	liveRun(w.store, "tk-new", "tk-r3", "mol-first-reaction")
	liveRun(w.store, "tk-new", "tk-r4", "mol-polecat-work")
	if out, err := w.p.Place(Request{Bead: "tk-new", Under: "tk-epic"}); err != nil || !strings.Contains(out.How, "already dispatched (live run tk-r4)") {
		t.Fatalf("a build's run beside a reaction's: %+v, %v; want the build read as the dispatch", out, err)
	}
}

// A dispatch that fails, and each write before it, leaves the hold on, so the
// bead stays in the queue, and names the run that finishes it.
func TestPlaceStoppedPartWayKeepsTheHold(t *testing.T) {
	for _, tc := range []struct {
		name string
		prep func(*world)
		want string
	}{
		{"the route's clear", func(w *world) {
			w.store.Put(fake.Bead{ID: "tk-new", Status: "open", IssueType: "task", Labels: []string{"hold:mayor"}, Metadata: map[string]string{"gc.routed_to": "x/y"}})
			w.store.BeforeUpdate = func(id string, args []string) error { return errors.New("bd refused") }
		}, "--unset-metadata gc.routed_to && gctk bead place tk-new --under tk-epic --db /rig/.beads"},
		{"the link's removal", func(w *world) {
			w.store.Put(fake.Bead{ID: "tk-new", Status: "open", IssueType: "task", Labels: []string{"hold:mayor"},
				Edges: []gcbd.Edge{{Type: gcbd.EdgeRelatesTo, ID: "tk-epic", Status: "open"}}})
			w.store.UnrelateErr = errors.New("bd refused")
		}, "relates-to link to tk-epic did not land"},
		{"the parent", func(w *world) {
			w.store.BeforeUpdate = func(id string, args []string) error { return errors.New("bd refused") }
		}, "did not take tk-epic as its parent"},
		{"the shift", func(w *world) { w.scriptFails = "move" }, "the shift +1 on tk-new did not land"},
		{"the settle", func(w *world) { w.scriptFails = "settle" }, "did not settle at its priority"},
		{"the sling", func(w *world) { w.slingCode = 1 }, "gc sling did not send tk-new"},
		{"the arm", func(w *world) {
			w.store.Put(fake.Bead{ID: "tk-blk", Status: "open", IssueType: "task"})
			w.store.Put(fake.Bead{ID: "tk-new", Status: "open", IssueType: "task", Labels: []string{"hold:mayor"},
				Edges: []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "tk-blk", Status: "open"}}})
			w.store.List("tk-new", "tk-blk")
			w.store.Mark("tk-new")
			w.armErr = errors.New("simulated")
		}, "the arm did not land"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			w := newWorld(t)
			tc.prep(w)
			shift := ""
			if tc.name == "the shift" {
				shift = "+1"
			}
			_, err := w.p.Place(Request{Bead: "tk-new", Under: "tk-epic", Shift: shift})
			if err == nil || Refused(err) || !strings.Contains(err.Error(), tc.want) || !strings.Contains(err.Error(), "gctk bead place tk-new") {
				t.Fatalf("Place = %v, want a stop naming %q and the run that finishes it", err, tc.want)
			}
			if !slices.Contains(w.row("tk-new").Labels, "hold:mayor") {
				t.Errorf("a stop at %s lifted the hold", tc.name)
			}
		})
	}
}

// A stop at the lift names the lift by hand, which dispatches nothing, since
// another placement could dispatch the bead again once its run has ended.
func TestPlaceStoppedAtTheLiftNamesTheLiftByHand(t *testing.T) {
	w := newWorld(t)
	w.store.BeforeUpdate = func(id string, args []string) error {
		if slices.Contains(args, "--remove-label") {
			return errors.New("bd refused")
		}
		return nil
	}
	_, err := w.p.Place(Request{Bead: "tk-new", Standalone: true})
	if err == nil || !strings.Contains(err.Error(), "gc bd update tk-new --remove-label 'hold:mayor' --append-notes 'Placed at") || !strings.Contains(err.Error(), "--db /rig/.beads") {
		t.Fatalf("Place = %v, want the lift by hand named", err)
	}
	if len(w.rt.Slings()) != 1 {
		t.Errorf("slings = %v, want the one dispatch", w.rt.Slings())
	}
}

// An arm the bead carries for where this placement sends it is the dispatch an
// earlier placement made: a second run keeps it and finishes the lift.
func TestPlaceKeepsAnArmForTheSamePlacement(t *testing.T) {
	for _, tc := range []struct {
		name, args, formula string
		judged              bool
	}{
		{"the same formula", `["--on","mol-x"]`, "mol-x", false},
		{"the pool's default, which the arm verb judges", `["--on","mol-polecat-work"]`, "", true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			w := newWorld(t)
			w.store.Put(fake.Bead{ID: "tk-new", Status: "open", IssueType: "task", Labels: []string{"hold:mayor"},
				Metadata: map[string]string{"gc.dispatch_when_ready": pool, "gc.dispatch_when_ready_armed_at": "t", "gc.dispatch_when_ready_args": tc.args}})
			out, err := w.p.Place(Request{Bead: "tk-new", Under: "tk-epic", Formula: tc.formula})
			if err != nil || !strings.HasPrefix(out.How, "already armed for "+pool) || len(w.rt.Slings()) != 0 {
				t.Fatalf("Place = %+v, %v, slings %v; want the arm kept and nothing slung", out, err, w.rt.Slings())
			}
			if got := len(w.arms) == 1; got != tc.judged {
				t.Errorf("arms %+v; the arm verb judged it: %v, want %v", w.arms, got, tc.judged)
			}
			if slices.Contains(w.row("tk-new").Labels, "hold:mayor") {
				t.Errorf("the hold stayed on")
			}
		})
	}
}

// An arm whose record does not decode reads as naming no formula, as an arm for
// the pool's default does, so the arm verb judges it, and its refusal stops the
// placement with the hold on and nothing written or slung.
func TestPlaceSendsAnArmTheStartCannotReadToTheArmVerb(t *testing.T) {
	w := newWorld(t)
	w.store.Put(fake.Bead{ID: "tk-new", Status: "open", IssueType: "task", Labels: []string{"hold:mayor"},
		Metadata: map[string]string{"gc.dispatch_when_ready": pool, "gc.dispatch_when_ready_armed_at": "t", "gc.dispatch_when_ready_args": `["--var","x=y"]`}})
	w.armErr = errors.New("refused: tk-new carries an arm the start cannot read (its sling arguments name no formula alone). Disarm it, then arm it again")
	_, err := w.p.Place(Request{Bead: "tk-new", Standalone: true})
	if !Refused(err) || !strings.Contains(err.Error(), "cannot read") || !strings.Contains(err.Error(), "gctk bead disarm tk-new --db /rig/.beads") {
		t.Fatalf("Place = %v, want the arm verb's refusal and the disarm named", err)
	}
	if len(w.arms) != 1 || len(w.store.Writes())+len(w.rt.Slings())+len(w.rt.Scripts()) != 0 {
		t.Errorf("arms %+v, log %v; want the arm verb asked once and nothing written, slung or run", w.arms, w.lines())
	}
	if !slices.Contains(w.row("tk-new").Labels, "hold:mayor") {
		t.Errorf("the hold was lifted")
	}
}

// gc sling's exit 3 says a live run of the formula already works the bead, and
// the placement finishes its lift.
func TestPlaceTakesALiveRunsRefusalAsTheDispatch(t *testing.T) {
	w := newWorld(t)
	w.slingCode = 3
	out, err := w.p.Place(Request{Bead: "tk-new", Under: "tk-epic", Formula: "mol-x"})
	if err != nil || out.How != "a live run of mol-x already works it, and gc sling refused to start another" {
		t.Fatalf("Place = %+v, %v", out, err)
	}
	if slices.Contains(w.row("tk-new").Labels, "hold:mayor") {
		t.Errorf("the hold stayed on")
	}
}

func TestPlaceNamesTheRigsPolecatPool(t *testing.T) {
	w := newWorld(t)
	w.rt.Roster = nil
	_, err := w.p.Place(Request{Bead: "tk-new", Standalone: true})
	if err == nil || !strings.Contains(err.Error(), "could not name the polecat pool of rig gc-toolkit") {
		t.Fatalf("Place = %v, want no pool named", err)
	}
	w = newWorld(t)
	w.rt.RosterErr = fmt.Errorf("gc agent list did not answer")
	if _, err := w.p.Place(Request{Bead: "tk-new", Standalone: true}); err == nil || len(w.store.Writes()) != 0 {
		t.Fatalf("Place over an unread roster = %v, writes %v; want nothing written", err, w.store.Writes())
	}
}

// A placement holds the bead's acceptance lock from its read to its last
// write, as a first reaction's exit does, and refuses with nothing written
// while another holds it, naming the placement to run again.
func TestPlaceTakesTheAcceptanceLock(t *testing.T) {
	w := newWorld(t)
	unlock, holder, err := rx.LockBead(w.rt, "tk-new")
	if err != nil || unlock == nil {
		t.Fatalf("LockBead = %v, %q; want the lock", err, holder)
	}
	before := len(w.store.Writes())
	_, err = w.p.Place(Request{Bead: "tk-new", Under: "tk-epic"})
	if !Refused(err) || !strings.Contains(err.Error(), "holds its acceptance lock") ||
		!strings.Contains(err.Error(), "gctk bead place tk-new --under tk-epic") {
		t.Fatalf("a placement while the lock is held: %v; want it refused, naming the lock and the placement to run again", err)
	}
	if len(w.store.Writes()) != before || len(w.rt.Slings()) != 0 {
		t.Errorf("a placement refused for the lock wrote %v and slung %v", w.store.Writes()[before:], w.rt.Slings())
	}
	unlock()
	if _, err := w.p.Place(Request{Bead: "tk-new", Under: "tk-epic"}); err != nil || len(w.rt.Slings()) != 1 {
		t.Fatalf("once the lock is free: %v, slings %v; want it slung", err, w.rt.Slings())
	}
}

// reactionCity is the city a reaction's takeaway reaches in a test.
type reactionCity struct {
	*rtfake.Runtime
	*rtfake.Roster
}

// A first reaction that starts while a placement sends its subject on never
// undoes that placement. The placement holds the bead's acceptance lock, so
// the reaction's exit refuses with nothing written until the placement has
// finished. The exit then finds the placement's run, lands its headline alone
// and ends no run.
func TestAReactionExitLeavesAPlacementThatRacedIt(t *testing.T) {
	w := newWorld(t)
	paused, resume := make(chan struct{}), make(chan struct{})
	script := w.rt.OnScript
	w.rt.OnScript = func(c rtfake.Call) gascity.Result {
		if c.Name == "queue-priority.sh" && len(c.Args) > 0 && c.Args[0] == "settle" {
			close(paused)
			<-resume
		}
		return script(c)
	}
	w.rt.OnSling = func(s gascity.Sling) gascity.SlingResult {
		liveRun(w.store, "tk-new", "tk-build", "mol-polecat-work")
		return gascity.SlingResult{}
	}
	placed := make(chan error, 1)
	go func() {
		_, err := w.p.Place(Request{Bead: "tk-new", Under: "tk-epic"})
		placed <- err
	}()
	<-paused
	liveRun(w.store, "tk-new", "tk-react", "mol-first-reaction")
	w.store.Put(fake.Bead{ID: "tk-react-step", Status: "in_progress", Assignee: "reaction-session",
		Metadata: map[string]string{"gc.root_bead_id": "tk-react", "gc.step_ref": "mol-first-reaction.react"}})
	tk := &takeaway.Takeaways{Ledger: w.p.Ledger, City: reactionCity{w.rt, &rtfake.Roster{}}, Scripts: "/pack/scripts",
		Self: []string{"reaction-session"}, Now: w.p.Now}
	tk.Disarm = func(id, reason string) (string, error) { return "", nil }
	r := &rx.Reactions{Ledger: w.p.Ledger, Runtime: w.rt, Rig: "gc-toolkit", Takeaway: tk.Take}
	if refused, err := r.Check("tk-new", "tk-react"); err != nil || refused != nil {
		t.Fatalf("the reaction's check: %v, %v; want it to react", refused, err)
	}
	exit := &rx.Dispose{Bead: "tk-new", Disposition: rx.Actionable, Route: pool, Run: "tk-react",
		Takeaway: "ready for placement", Reason: "ready"}
	if _, err := r.Dispose(exit); err == nil || !strings.Contains(err.Error(), "holds its acceptance lock") {
		t.Fatalf("the exit while the placement runs: %v; want it refused for the lock", err)
	}
	close(resume)
	if err := <-placed; err != nil {
		t.Fatalf("the placement: %v", err)
	}
	if _, err := r.Dispose(exit); err != nil {
		t.Fatalf("the exit once the placement has finished: %v", err)
	}
	for _, c := range w.rt.Scripts() {
		if c.Name == "run-cancel.sh" {
			t.Fatalf("the exit ended a run: run-cancel.sh %s", strings.Join(c.Args, " "))
		}
	}
	row := w.row("tk-new")
	if slices.Contains(row.Labels, "hold:mayor") || row.Metadata["gc.takeaway"] != "ready for placement" {
		t.Errorf("after the exit: labels %v, headline %q; want the placement's lift kept and the headline landed",
			row.Labels, row.Metadata["gc.takeaway"])
	}
}
