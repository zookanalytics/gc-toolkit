package reaction

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
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	ghfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// root is the root of the reaction's run, which --run names.
const root = "tk-root"

// world is one reaction's surroundings: a store holding the subject tk-sub,
// an open member of the epic tk-epic, and its blocker tk-blk1; a city whose
// roster runs the rig's polecat and proactive pools, the mechanik and the
// rig's refinery, and which configures those agents alone, so a sling, a
// takeaway's route or an arm's default to any other target is refused as Gas
// City refuses it; a GitHub; and one log of every write and act across them,
// in order, as the shell suite's FAKE_LOG kept it.
type world struct {
	t     *testing.T
	store *fake.Store
	rt    *rtfake.Runtime
	gh    *ghfake.GitHub
	r     *Reactions

	mu   sync.Mutex
	log  []string
	said []string

	// Each fails its act when set: the takeaway (gc-helm.sh exits 4), a gate's
	// filing, a sling, a nudge and an arm.
	helmFails, gateFails, slingFails, nudgeFails bool
	armErr                                       error
	// slingCode is the exit a sling answers, 3 being a live run of the
	// formula.
	slingCode int
	// gateID is the id the next gate human-gate.sh files takes.
	gateID string
	// origin is the origin URL of the subject's rig checkout.
	origin string
}

func newWorld(t *testing.T) *world {
	t.Helper()
	w := &world{t: t, store: fake.New(), gh: ghfake.New("bot"), gateID: "tk-gate1"}
	w.gh.Repos = map[string]*ghfake.Repo{}
	w.store.Put(fake.Bead{ID: "tk-epic", Title: "the epic", Status: "open", IssueType: "epic"})
	w.store.Put(fake.Bead{ID: "tk-blk1", Title: "the blocker", Status: "open", IssueType: "task"})
	w.store.Put(fake.Bead{ID: "tk-sub", Title: "the subject", Status: "open", IssueType: "task",
		Edges: []gcbd.Edge{{Type: gcbd.EdgeParentChild, ID: "tk-epic", Status: "open"}}})
	w.store.MakeReady("tk-sub")
	w.store.OnWrite = func(kind, id string, args []string) {
		w.add(strings.ToUpper(kind) + " " + id + " " + strings.Join(args, " "))
		w.sync()
	}
	w.store.OnFind = func(q gcbd.Query) { w.add("FIND " + strings.Join(q.IDs, " ")) }
	w.rt = &rtfake.Runtime{
		Resolves: []string{"mol-x", "mol-polecat-work"},
		Roster: []gascity.Agent{
			{QualifiedName: "gc-toolkit/gc-toolkit.polecat", Name: "polecat", Dir: "gc-toolkit", Scope: "rig"},
			{QualifiedName: "gc-toolkit.mechanik", Name: "mechanik", Scope: "city"},
			{QualifiedName: "gc-toolkit/gc-toolkit.refinery", Name: "refinery", Dir: "gc-toolkit", Scope: "rig"},
			{QualifiedName: "gc-toolkit/gc-toolkit.proactive", Name: "proactive", Dir: "gc-toolkit", Scope: "rig"},
		},
		Named: []gascity.NamedSession{{Template: "mechanik"}, {Template: "refinery", Dir: "gc-toolkit"}},
		RigList: []gascity.Rig{
			{Name: "town", Path: "/town", Prefix: "hq", HQ: true},
			{Name: "gc-toolkit", Path: "/town/rigs/gc-toolkit", Prefix: "tk"},
		},
	}
	w.rt.OnScript = w.script
	// The city's preview of a sling resolves an agent its roster lists, and
	// refuses any other target as gc sling does.
	w.rt.OnPreview = func(s gascity.Sling) gascity.SlingPreview {
		for _, a := range w.rt.Roster {
			if a.QualifiedName == s.Target {
				return gascity.SlingPreview{Answered: true}
			}
		}
		return gascity.SlingPreview{Answered: true, Unresolved: true, Refused: `gc sling: agent "` + s.Target + `" not found in city.toml`}
	}
	w.rt.OnSling = func(s gascity.Sling) gascity.SlingResult {
		line := "SLING " + s.Target + " " + s.Bead
		if s.NoFormula {
			line += " --no-formula --no-convoy"
		} else {
			line += " --on " + s.Formula
		}
		if s.Rig != "" {
			line += " --rig " + s.Rig
		}
		w.add(line)
		switch {
		case !w.configured(s.Target):
			return gascity.SlingResult{Result: gascity.Result{Code: 1, Output: w.unconfigured(s.Target)}}
		case w.slingFails:
			return gascity.SlingResult{Result: gascity.Result{Code: 1, Output: "gc sling: fake refusal"}}
		case w.slingCode == 3:
			return gascity.SlingResult{Result: gascity.Result{Code: 3, Output: "gc sling: source bead tk-sub already has live workflow(s): tk-closer-root"}, Live: []string{"tk-closer-root"}}
		}
		return gascity.SlingResult{}
	}
	w.rt.OnNudge = func(n rtfake.Nudge) gascity.Result {
		w.add("NUDGE " + n.Session + " " + n.Message)
		if w.nudgeFails {
			return gascity.Result{Code: 1, Output: "gc session nudge: fake refusal"}
		}
		return gascity.Result{}
	}
	w.r = &Reactions{
		Ledger:  ledger.New(w.store),
		Runtime: w.rt,
		GitHub:  w.gh,
		Rig:     "gc-toolkit",
		Origin: func(dir string) (string, error) {
			if w.origin == "" {
				return "", errors.New("no origin")
			}
			return w.origin, nil
		},
		Now: func() time.Time { return time.Date(2026, 11, 16, 12, 0, 0, 0, time.UTC) },
		Log: func(line string) { w.mu.Lock(); w.said = append(w.said, line); w.mu.Unlock() },
	}
	w.r.Arm = func(req arm.Request) (string, error) {
		line := "ARM " + req.ID + " --target " + req.Target
		if req.Formula != "" {
			line += " --on " + req.Formula
		}
		w.add(line)
		switch {
		case req.Formula == "" && !w.configured(req.Target):
			return "", fmt.Errorf("%s's default formula could not be read (no agent in the city's config answers to %s), so name one with --on", req.Target, req.Target)
		case w.armErr != nil:
			return "", w.armErr
		}
		return "armed " + req.ID, nil
	}
	return w
}

// configured is whether the city configures an agent at target, one its roster
// lists.
func (w *world) configured(target string) bool {
	return slices.ContainsFunc(w.rt.Roster, func(a gascity.Agent) bool { return a.QualifiedName == target })
}

// unconfigured is gc sling's refusal of a target the city configures no agent
// for, as the city's build prints it.
func (w *world) unconfigured(target string) string {
	return `gc sling: agent "` + target + `" not found in city.toml; did you mean "gc-toolkit/gc-toolkit.po"?`
}

// sync makes the store's blocked answers for the subject what its edges say,
// as bd's blocked rule reads them: blocked by each bead a blocks edge of its
// names that is not closed.
func (w *world) sync() {
	s, ok := w.store.Row("tk-sub")
	if !ok {
		return
	}
	var by []string
	for _, e := range s.Edges {
		if far, held := w.store.Row(e.ID); held && e.Type == gcbd.EdgeBlocks && !strings.EqualFold(far.Status, "closed") {
			by = append(by, e.ID)
		}
	}
	if len(by) == 0 {
		w.store.Unlist("tk-sub")
		return
	}
	w.store.List("tk-sub", by...)
	w.store.Mark("tk-sub")
}

func (w *world) add(line string) {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.log = append(w.log, line)
}

// script answers gc-helm.sh and human-gate.sh. gc-helm.sh takeaway's release
// makes its subject ready as its waits land (released), and its route, its last
// write, fails as gc sling refuses a target the city does not configure.
// human-gate.sh files a gate under its key that blocks its subject, its
// message's first line as its title and the whole message as its description,
// and prints its id, or finds the open gate under the key and prints that;
// --retract closes the open gates under the key.
func (w *world) script(c rtfake.Call) gascity.Result {
	switch c.Name {
	case "gc-helm.sh":
		w.add("HELM " + strings.Join(c.Args, " "))
		if w.helmFails {
			return gascity.Result{Code: 4, Output: "gc-helm: could not update 'tk-sub': the store refused it"}
		}
		w.released(c.Args)
		if route := flagValue(c.Args, "--route"); route != "" && !w.configured(route) {
			return gascity.Result{Code: 4, Output: w.unconfigured(route) + "\ngc-helm: takeaway: " + c.Args[1] + " is released and the run beneath it has ended, but gc sling did not route it to '" + route +
				"' (exit 1, its reason above), so it rests open, unassigned and routed to no pool. Route it once the cause is fixed: gc sling " + route + " " + c.Args[1] + " --no-formula --no-convoy\n"}
		}
		return gascity.Result{}
	case "human-gate.sh":
		w.add("GATE " + strings.Join(c.Args, " "))
		subject, key, message, retract := flagValue(c.Args, "--subject"), flagValue(c.Args, "--key"), flagValue(c.Args, "--message"), slices.Contains(c.Args, "--retract")
		open := w.openGate(subject, key)
		if retract {
			if open != "" {
				g, _ := w.store.Row(open)
				g.Status = "closed"
				w.store.Put(g)
			}
			return gascity.Result{}
		}
		if w.gateFails {
			return gascity.Result{Code: 1, Output: "human-gate: fake refusal"}
		}
		if open == "" {
			open = w.gateID
			title, _, _ := strings.Cut(message, "\n")
			w.store.Put(fake.Bead{ID: open, Title: title, Description: message, Status: "open", IssueType: "gate", AwaitType: "human", AwaitID: key})
			s, _ := w.store.Row(subject)
			s.Edges = append(slices.Clone(s.Edges), gcbd.Edge{Type: gcbd.EdgeBlocks, ID: open, Title: title, Status: "open"})
			w.store.Put(s)
			w.sync()
		}
		return gascity.Result{Output: "human-gate: a note on stderr\n" + open + "\n"}
	}
	return gascity.Result{Code: 127, Err: fmt.Errorf("no script %s", c.Name)}
}

// released makes the subject of a takeaway release ready when every bead the
// release waits on has closed, as bd's ready set reads the subject once those
// wait edges land. A subject waitingWorld starts unready so reads ready only
// after its release.
func (w *world) released(args []string) {
	if len(args) < 2 || args[0] != "takeaway" || !slices.Contains(args, "--release") {
		return
	}
	waits := 0
	for i, a := range args {
		if a != "--waiting-on" || i+1 == len(args) {
			continue
		}
		if b, ok := w.store.Row(args[i+1]); !ok || !strings.EqualFold(b.Status, "closed") {
			return
		}
		waits++
	}
	if waits > 0 {
		w.store.MakeReady(args[1])
	}
}

func (w *world) openGate(subject, key string) string {
	s, _ := w.store.Row(subject)
	for _, e := range s.Edges {
		g, ok := w.store.Row(e.ID)
		if ok && e.Type == gcbd.EdgeBlocks && g.IssueType == "gate" && g.AwaitID == key && g.Status != "closed" {
			return g.ID
		}
	}
	return ""
}

func flagValue(args []string, name string) string {
	for i, a := range args {
		if a == name && i+1 < len(args) {
			return args[i+1]
		}
	}
	return ""
}

// dispose runs one exit: the call is validated as the command validates it,
// then taken. code is the exit the command would make: 0, 2 usage, 3 not
// open, 4 stopped part way.
func (w *world) dispose(args ...string) (code int, out string, err error) {
	w.t.Helper()
	d := parse(w.t, args...)
	if err := Validate(w.rt, w.r.Rig, d); err != nil {
		return 2, "", err
	}
	done, err := w.r.Dispose(d)
	var use *UsageError
	switch {
	case err == nil:
		return 0, done.String(), nil
	case errors.As(err, &use):
		return 2, "", err
	case NotOpen(err):
		return 3, "", err
	}
	return 4, "", err
}

// parse reads a call's flags as the command reads them.
func parse(t *testing.T, args ...string) *Dispose {
	t.Helper()
	d := &Dispose{By: "proactive", Set: map[string]bool{}}
	str := map[string]*string{
		"--disposition": &d.Disposition, "--reason": &d.Reason, "--takeaway": &d.Takeaway, "--run": &d.Run,
		"--by": &d.By, "--route": &d.Route, "--assign": &d.Assign, "--emergency": &d.Emergency,
		"--blocker": &d.Blocker, "--then-route": &d.ThenRoute, "--then-assign": &d.ThenAssign,
		"--recommended-formula": &d.RecommendedFormula,
	}
	for i := 0; i < len(args); i++ {
		a := args[i]
		if !strings.HasPrefix(a, "--") {
			d.Bead = a
			continue
		}
		if i+1 >= len(args) {
			t.Fatalf("%s needs a value", a)
		}
		i++
		v := args[i]
		d.Set[strings.TrimPrefix(a, "--")] = true
		if a == "--waiting-on" {
			d.WaitingOn = append(d.WaitingOn, v)
			continue
		}
		p, ok := str[a]
		if !ok {
			t.Fatalf("no flag %s", a)
		}
		*p = v
	}
	for _, common := range []string{"disposition", "reason", "takeaway", "by"} {
		delete(d.Set, common)
	}
	return d
}

// lines is the log's lines that open with prefix.
func (w *world) lines(prefix string) []string {
	w.mu.Lock()
	defer w.mu.Unlock()
	var out []string
	for _, l := range w.log {
		if strings.HasPrefix(l, prefix) {
			out = append(out, l)
		}
	}
	return out
}

// writes is every write and act in the log: the store's, the scripts', the
// slings, the nudges and the arms.
func (w *world) writes() []string {
	w.mu.Lock()
	defer w.mu.Unlock()
	var out []string
	for _, l := range w.log {
		if !strings.HasPrefix(l, "FIND ") {
			out = append(out, l)
		}
	}
	return out
}

// has fails the test when no log line holds text.
func (w *world) has(text, what string) {
	w.t.Helper()
	w.mu.Lock()
	defer w.mu.Unlock()
	for _, l := range w.log {
		if strings.Contains(l, text) {
			return
		}
	}
	w.t.Errorf("%s: no log line holds %q in:\n%s", what, text, strings.Join(w.log, "\n"))
}

// hasnt fails the test when a log line holds text.
func (w *world) hasnt(text, what string) {
	w.t.Helper()
	w.mu.Lock()
	defer w.mu.Unlock()
	for _, l := range w.log {
		if strings.Contains(l, text) {
			w.t.Errorf("%s: the log line %q holds %q", what, l, text)
		}
	}
}

// before fails the test unless the first log line holding a comes before the
// first holding b.
func (w *world) before(a, b, what string) {
	w.t.Helper()
	w.mu.Lock()
	defer w.mu.Unlock()
	ia := slices.IndexFunc(w.log, func(l string) bool { return strings.Contains(l, a) })
	ib := slices.IndexFunc(w.log, func(l string) bool { return strings.Contains(l, b) })
	if ia < 0 || ib < 0 || ia > ib {
		w.t.Errorf("%s: %q at %d, %q at %d, in:\n%s", what, a, ia, b, ib, strings.Join(w.log, "\n"))
	}
}

// saidHas fails the test when nothing the exit said holds text.
func (w *world) saidHas(text, what string) {
	w.t.Helper()
	w.mu.Lock()
	defer w.mu.Unlock()
	for _, l := range w.said {
		if strings.Contains(l, text) {
			return
		}
	}
	w.t.Errorf("%s: nothing said holds %q in:\n%s", what, text, strings.Join(w.said, "\n"))
}

// reset empties the log and what was said, keeping the store as it stands,
// as a re-offered reaction meets it.
func (w *world) reset() {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.log, w.said = nil, nil
}

// put replaces the subject's row with one whose fields f sets.
func (w *world) subject(f func(*fake.Bead)) {
	s, _ := w.store.Row("tk-sub")
	f(&s)
	w.store.Put(s)
	w.sync()
}

// red puts the repository zook/repo, whose main's head has a failing
// test-macos run, behind the subject's rig checkout.
func (w *world) red() {
	w.origin = "git@github.com:zook/repo.git"
	w.gh.Repos["zook/repo"] = &ghfake.Repo{DefaultBranch: "main", Checks: map[string]*gh.HeadChecks{"main": {
		SHA: "abcdef1234567890",
		Runs: []gh.RefCheckRun{
			{Name: "lint", Conclusion: "success", HeadSHA: "abcdef1234567890"},
			{Name: "test-macos", Conclusion: "failure", HeadSHA: "abcdef1234567890"},
		},
	}}}
}

func wantCode(t *testing.T, got, want int, err error, what string) {
	t.Helper()
	if got != want {
		t.Fatalf("%s: exit %d, want %d (%v)", what, got, want, err)
	}
}

func errHas(t *testing.T, err error, text, what string) {
	t.Helper()
	if err == nil || !strings.Contains(err.Error(), text) {
		t.Errorf("%s: the error %v does not hold %q", what, err, text)
	}
}

// put adds each bead to the store, and makes the store's blocked answer for
// each what its edges say, as sync does for the subject: blocked by each bead a
// blocks edge names that is not closed.
func (w *world) put(beads ...fake.Bead) {
	w.t.Helper()
	for _, b := range beads {
		w.store.Put(b)
	}
	for _, b := range beads {
		var by []string
		for _, e := range b.Edges {
			if far, held := w.store.Row(e.ID); held && e.Type == gcbd.EdgeBlocks && !strings.EqualFold(far.Status, "closed") {
				by = append(by, e.ID)
			}
		}
		if len(by) > 0 {
			w.store.List(b.ID, by...)
			w.store.Mark(b.ID)
		}
	}
}

// input is an open task nobody has decided on, with a description, its fields
// as f sets them.
func input(id string, f func(*fake.Bead)) fake.Bead {
	b := fake.Bead{ID: id, Title: "raw input " + id, Status: "open", IssueType: "task", Description: "a raw input bead", Metadata: map[string]string{}}
	if f != nil {
		f(&b)
	}
	return b
}

// run puts a live run of formula, rooted at root, over an input convoy that
// tracks bead, closed when status says so.
func (w *world) run(root, formula, bead, status string) {
	w.t.Helper()
	convoy := "cv-" + root
	w.put(fake.Bead{ID: convoy, Status: "open", IssueType: "convoy", Edges: []gcbd.Edge{{Type: "tracks", ID: bead}}},
		fake.Bead{ID: root, Title: formula, Status: status, IssueType: "task",
			Metadata: map[string]string{"gc.kind": "workflow", "gc.formula_name": formula, "gc.input_convoy_id": convoy}})
}

// sling runs the sling as the command does, and returns the code it would
// exit with and what it says: 0 slung, a refusal's code, or 1 for an error.
func (w *world) sling(bead string) (int, string) {
	w.t.Helper()
	refusal, err := w.r.Sling(bead)
	return outcome(refusal, err)
}

// check runs the check of the reaction whose run is run, as sling does.
func (w *world) check(bead, run string) (int, string) {
	w.t.Helper()
	refusal, err := w.r.Check(bead, run)
	var use *UsageError
	if errors.As(err, &use) {
		return 2, err.Error()
	}
	return outcome(refusal, err)
}

func outcome(refusal *Refusal, err error) (int, string) {
	switch {
	case err != nil:
		return 1, err.Error()
	case refusal != nil:
		return refusal.Code, refusal.Why
	}
	return 0, ""
}

// slings is the beads the log shows slung as a first reaction.
func (w *world) slings() []string {
	var out []string
	for _, l := range w.lines("SLING ") {
		f := strings.Fields(l)
		if len(f) >= 3 && strings.Contains(l, "--on "+Formula) {
			out = append(out, f[2])
		}
	}
	return out
}

// failing is the world's store with a find that fails when fail says so, or
// answers without the rows omit names, which a test points at one read among a
// command's reads.
type failing struct {
	*fake.Store
	fail func(gcbd.Query) bool
	omit func(q gcbd.Query, id string) bool
}

func (f failing) Find(q gcbd.Query) ([]gcbd.Bead, error) {
	if f.fail != nil && f.fail(q) {
		return nil, &gcbd.ReadError{Reason: "the fake store failed this find"}
	}
	rows, err := f.Store.Find(q)
	if f.omit != nil {
		rows = slices.DeleteFunc(rows, func(b gcbd.Bead) bool { return f.omit(q, b.ID) })
	}
	return rows, err
}

// failFind makes the reactions' finds fail the reads fail selects.
func (w *world) failFind(fail func(gcbd.Query) bool) {
	w.r.Ledger = ledger.New(failing{Store: w.store, fail: fail})
}

// omitFind makes the reactions' finds answer without each row omit names, as a
// listing does for a bead deleted since an earlier read named it.
func (w *world) omitFind(omit func(q gcbd.Query, id string) bool) {
	w.r.Ledger = ledger.New(failing{Store: w.store, omit: omit})
}
