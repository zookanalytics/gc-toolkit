package takeaway

import (
	"errors"
	"fmt"
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

// pool is the pool a route names in these tests.
const pool = "tk/gc-toolkit.polecat"

// city is the Gas City a takeaway reaches in these tests: the runtime's fake
// for the sling, the scripts and the nudge, and the roster's for the session
// list.
type city struct {
	*rtfake.Runtime
	*rtfake.Roster
}

var _ City = city{}

// world is one takeaway's surroundings: a store holding the open bead tk-a,
// with a live run beneath it, root tk-root over convoy tk-convoy, and another
// run tk-root-other beneath another bead; a city whose session list is empty;
// the arm's disarm; and one log of every write and act across them, in order.
type world struct {
	t      *testing.T
	store  *fake.Store
	rt     *rtfake.Runtime
	roster *rtfake.Roster
	tk     *Takeaways

	mu   sync.Mutex
	log  []string
	said []string

	// Each fails its act when set: the disarm, a run cancel, a sling and a
	// nudge.
	disarmErr                           error
	cancelFails, slingFails, nudgeFails bool
	// armed says the disarm removed an arm, as gctk bead disarm says it.
	armed bool
	// fence refuses, as bd does, an update that changes the assignee of a
	// claimed bead with no --if-assignee naming the claim's holder.
	fence bool
}

func newWorld(t *testing.T) *world {
	t.Helper()
	w := &world{t: t, store: fake.New(), roster: &rtfake.Roster{}}
	w.store.Put(fake.Bead{ID: "tk-a", Title: "the bead", Status: "open", IssueType: "task", Metadata: map[string]string{}})
	w.run("tk-a", "tk-root", "tk-convoy")
	w.store.Put(fake.Bead{ID: "tk-b", Title: "another bead", Status: "open", IssueType: "task"})
	w.run("tk-b", "tk-root-other", "tk-convoy-other")
	w.store.OnWrite = func(kind, id string, args []string) {
		w.add(strings.ToUpper(kind) + " " + id + " " + strings.Join(args, " "))
		w.sync()
	}
	w.store.BeforeUpdate = func(id string, args []string) error {
		if !w.fence {
			return nil
		}
		b, _ := w.store.Row(id)
		if !slices.Contains([]string{"in_progress", "hooked"}, b.Status) || b.Assignee == "" {
			return nil
		}
		if slices.ContainsFunc(args, func(a string) bool { return strings.HasPrefix(a, "--assignee") }) &&
			!slices.Contains(args, "--if-assignee="+b.Assignee) {
			return fmt.Errorf("fake bd: %s is claimed by %s, and a write that takes a claim names its holder", id, b.Assignee)
		}
		return nil
	}
	w.rt = &rtfake.Runtime{}
	w.rt.OnScript = func(c rtfake.Call) gascity.Result {
		w.add("SCRIPT " + c.Name + " " + strings.Join(c.Args, " "))
		if w.cancelFails {
			return gascity.Result{Code: 1, Output: "run-cancel: the supervisor did not answer"}
		}
		return gascity.Result{}
	}
	w.rt.OnSling = func(s gascity.Sling) gascity.SlingResult {
		line := "SLING " + s.Target + " " + s.Bead
		if s.NoFormula {
			line += " --no-formula --no-convoy"
		}
		w.add(line)
		if w.slingFails {
			return gascity.SlingResult{Result: gascity.Result{Code: 1, Output: "gc sling: fake refusal"}}
		}
		return gascity.SlingResult{}
	}
	w.rt.OnNudge = func(n rtfake.Nudge) gascity.Result {
		w.add("NUDGE " + n.Session + " about " + n.Bead + ": " + n.Message)
		if w.nudgeFails {
			return gascity.Result{Code: 1, Output: "gc session nudge: fake refusal"}
		}
		return gascity.Result{}
	}
	w.tk = &Takeaways{
		Ledger:  ledger.New(w.store),
		City:    city{Runtime: w.rt, Roster: w.roster},
		Scripts: "/pack/scripts",
		Now:     func() time.Time { return time.Date(2026, 11, 20, 6, 0, 0, 0, time.UTC) },
		Log:     func(line string) { w.mu.Lock(); w.said = append(w.said, line); w.mu.Unlock() },
	}
	w.tk.Disarm = func(id, reason string) (string, error) {
		w.add("DISARM " + id + " " + reason)
		if w.disarmErr != nil {
			return "", w.disarmErr
		}
		if w.armed {
			return "disarmed " + id, nil
		}
		return id + " carries no arm, so nothing was written", nil
	}
	return w
}

// run lays a live graph.v2 run beneath bead: its input convoy tracks the bead,
// its root names the convoy, and its steps name the root, one claimed by a
// session that is gone and one not yet claimed.
func (w *world) run(bead, root, convoy string) {
	w.store.Put(fake.Bead{ID: convoy, Title: "input convoy for " + bead, Status: "open", IssueType: "convoy",
		Edges: []gcbd.Edge{{Type: "tracks", ID: bead}}})
	w.store.Put(fake.Bead{ID: root, Title: "mol-polecat-work", Status: "in_progress", IssueType: "task",
		Metadata: map[string]string{"gc.kind": "workflow", "gc.input_convoy_id": convoy}})
	w.store.Put(fake.Bead{ID: root + "-load", Status: "in_progress", Assignee: "polecat-dead",
		Metadata: map[string]string{"gc.root_bead_id": root, "gc.step_ref": "mol-polecat-work.load-context"}})
	w.store.Put(fake.Bead{ID: root + "-impl", Status: "open",
		Metadata: map[string]string{"gc.root_bead_id": root, "gc.step_ref": "mol-polecat-work.implement"}})
}

// put adds a bead and makes the store's blocked answers what every bead's
// edges say.
func (w *world) put(b fake.Bead) {
	w.store.Put(b)
	w.sync()
}

// sync makes the store's blocked answers for each bead what its edges say, as
// bd's blocked rule reads them: blocked by each bead a blocks edge of its names
// that is not closed.
func (w *world) sync() {
	for _, id := range []string{"tk-a", "tk-b", "tk-held", "tk-gone", "tk-mine"} {
		b, ok := w.store.Row(id)
		if !ok {
			continue
		}
		var by []string
		for _, e := range b.Edges {
			if far, held := w.store.Row(e.ID); held && e.Type == gcbd.EdgeBlocks && !strings.EqualFold(far.Status, "closed") {
				by = append(by, e.ID)
			}
		}
		if len(by) == 0 {
			w.store.Unlist(id)
			continue
		}
		w.store.List(id, by...)
		w.store.Mark(id)
	}
}

// blockOn gives bead a blocks edge onto each blocker.
func (w *world) blockOn(bead string, blockers ...string) {
	b, _ := w.store.Row(bead)
	for _, id := range blockers {
		far, _ := w.store.Row(id)
		b.Edges = append(slices.Clone(b.Edges), gcbd.Edge{Type: gcbd.EdgeBlocks, ID: id, Title: far.Title, Status: far.Status,
			IssueType: far.IssueType, AwaitType: far.AwaitType})
	}
	w.put(b)
}

func (w *world) add(line string) {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.log = append(w.log, line)
}

// take runs one takeaway and returns the code the command exits with: 0, 2 for
// a refusal that wrote nothing, 4 for a stop.
func (w *world) take(req Request) (code int, out string, err error) {
	w.t.Helper()
	out, err = w.tk.Take(req)
	switch {
	case err == nil:
		return 0, out, nil
	case Refused(err):
		return 2, out, err
	}
	return 4, out, err
}

// lines is each line of the log that begins with prefix, in order.
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

// update is the one update the log holds of bead, failing the test unless
// there is exactly one.
func (w *world) update(bead string) string {
	w.t.Helper()
	ups := w.lines("UPDATE " + bead + " ")
	if len(ups) != 1 {
		w.t.Fatalf("%d updates of %s, want one: %q", len(ups), bead, ups)
	}
	return ups[0]
}

// wrote reports whether the log holds anything but a disarm.
func (w *world) wrote() []string {
	w.mu.Lock()
	defer w.mu.Unlock()
	var out []string
	for _, l := range w.log {
		if !strings.HasPrefix(l, "DISARM ") {
			out = append(out, l)
		}
	}
	return out
}

// before fails the test unless the first log line beginning with a comes
// before the first beginning with b.
func (w *world) before(a, b, what string) {
	w.t.Helper()
	w.mu.Lock()
	defer w.mu.Unlock()
	ia, ib := -1, -1
	for i, l := range w.log {
		if ia < 0 && strings.HasPrefix(l, a) {
			ia = i
		}
		if ib < 0 && strings.HasPrefix(l, b) {
			ib = i
		}
	}
	if ia < 0 || ib < 0 || ia > ib {
		w.t.Errorf("%s: %q does not come before %q in %q", what, a, b, w.log)
	}
}

// saidAny reports whether a line the verb said holds text.
func (w *world) saidAny(text string) bool {
	w.mu.Lock()
	defer w.mu.Unlock()
	return slices.ContainsFunc(w.said, func(l string) bool { return strings.Contains(l, text) })
}

func (w *world) row(id string) fake.Bead {
	b, _ := w.store.Row(id)
	return b
}

func has(t *testing.T, s, sub, what string) {
	t.Helper()
	if !strings.Contains(s, sub) {
		t.Errorf("%s: %q does not hold %q", what, s, sub)
	}
}

func hasnt(t *testing.T, s, sub, what string) {
	t.Helper()
	if strings.Contains(s, sub) {
		t.Errorf("%s: %q holds %q", what, s, sub)
	}
}

func errText(err error) string {
	if err == nil {
		return ""
	}
	return err.Error()
}

var errBroken = errors.New("the store did not answer")
