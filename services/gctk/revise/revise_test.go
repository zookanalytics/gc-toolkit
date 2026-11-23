package revise

import (
	"errors"
	"strings"
	"sync"
	"testing"
	"time"
	"unicode/utf8"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	rtfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// city is the Gas City a revision reaches in these tests: the runtime's fake
// for the nudge, and the roster's for the session list.
type city struct {
	*rtfake.Runtime
	*rtfake.Roster
}

var _ City = city{}

// world is one revision's surroundings: a store holding the work bead tk-a,
// open and unassigned, with a live graph.v2 run beneath it whose implement
// step the live Claude session sess-live holds; a session list naming sess-live
// and the control-dispatcher; and one log of every write and nudge, in order.
type world struct {
	t      *testing.T
	store  *fake.Store
	rt     *rtfake.Runtime
	roster *rtfake.Roster
	v      *Revisions

	mu  sync.Mutex
	log []string

	nudgeFails bool
}

const by = "rig/gc-toolkit.tk-conv"

func newWorld(t *testing.T) *world {
	t.Helper()
	w := &world{t: t, store: fake.New()}
	w.store.Put(fake.Bead{ID: "tk-a", Title: "the work", Status: "open", IssueType: "task", Metadata: map[string]string{}})
	w.run("tk-a", "tk-root", "tk-convoy", "in_progress")
	w.store.Put(fake.Bead{ID: "tk-root-impl", Status: "in_progress", Assignee: "sess-live",
		Metadata: map[string]string{"gc.root_bead_id": "tk-root", "gc.step_ref": "mol-polecat-work.implement"}})
	w.store.OnWrite = func(kind, id string, args []string) { w.add(strings.ToUpper(kind) + " " + id) }
	w.roster = &rtfake.Roster{SessionList: []gascity.Session{
		{ID: "sess-live", SessionName: "rig__polecat-sess-live", AgentName: "rig/gc-toolkit.polecat-2", Provider: "claude", State: "active"},
		{ID: "sess-ctl", SessionName: "rig__control-dispatcher-sess-ctl", Alias: "rig/core.control-dispatcher", State: "active"},
	}}
	w.rt = &rtfake.Runtime{OnNudge: func(n rtfake.Nudge) gascity.Result {
		w.add("NUDGE " + n.Session + " about " + n.Bead)
		if w.nudgeFails {
			return gascity.Result{Code: 1, Output: "gc session nudge: fake refusal"}
		}
		return gascity.Result{Output: "Nudged " + n.Session + "\n"}
	}}
	w.v = &Revisions{
		Ledger: ledger.New(w.store),
		City:   city{Runtime: w.rt, Roster: w.roster},
		By:     by,
		Now:    func() time.Time { return time.Date(2026, 11, 23, 11, 0, 0, 0, time.UTC) },
	}
	return w
}

// run lays a graph.v2 run beneath bead with its root in rootStatus: its input
// convoy tracks the bead, its root names the convoy, its load-context step is
// closed under a session long gone, and its finalize step waits on the
// control-dispatcher's route, assigned to no one.
func (w *world) run(bead, root, convoy, rootStatus string) {
	w.store.Put(fake.Bead{ID: convoy, Title: "input convoy for " + bead, Status: "open", IssueType: "convoy",
		Edges: []gcbd.Edge{{Type: "tracks", ID: bead}}})
	w.store.Put(fake.Bead{ID: root, Title: "mol-polecat-work", Status: rootStatus, IssueType: "task",
		Metadata: map[string]string{"gc.kind": "workflow", "gc.input_convoy_id": convoy}})
	w.store.Put(fake.Bead{ID: root + "-load", Status: "closed", Assignee: "sess-gone",
		Metadata: map[string]string{"gc.root_bead_id": root, "gc.step_ref": "mol-polecat-work.load-context"}})
	w.store.Put(fake.Bead{ID: root + "-final", Status: "open",
		Metadata: map[string]string{"gc.root_bead_id": root, "gc.kind": "workflow-finalize", "gc.routed_to": "rig/core.control-dispatcher"}})
}

func (w *world) add(line string) {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.log = append(w.log, line)
}

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

func (w *world) notes(id string) string {
	b, _ := w.store.Row(id)
	return b.Notes
}

func has(t *testing.T, s, sub, what string) {
	t.Helper()
	if !strings.Contains(s, sub) {
		t.Errorf("%s: %q does not hold %q", what, s, sub)
	}
}

// A bead whose work runs on a workflow reads open and unassigned, and the
// revision still reaches the session holding the run's step: the note lands
// first, then that session is nudged at once about the bead, with a message
// that names the bead, says its notes hold the revision and carries it.
func TestReviseReachesTheSessionHoldingTheRun(t *testing.T) {
	w := newWorld(t)
	text := "Build the drawer on Base UI's Dialog, pinned, not a native <dialog>."
	out, err := w.v.Revise(Request{Bead: "tk-a", Text: text})
	if err != nil {
		t.Fatalf("Revise: %v", err)
	}
	has(t, w.notes("tk-a"), "## Revised in flight (2026-11-23T11:00:00Z, by "+by+")\n"+text, "the note")
	if got := strings.Join(w.log, " | "); got != "UPDATE tk-a | NUDGE sess-live about tk-a" {
		t.Errorf("the writes and nudges ran as %q, want the note and then the nudge", got)
	}
	nudges := w.rt.Nudges()
	if len(nudges) != 1 {
		t.Fatalf("%d nudges, want one: %+v", len(nudges), nudges)
	}
	msg := nudges[0].Message
	for _, want := range []string{by, "tk-a", "gc bd show tk-a", text} {
		has(t, msg, want, "the nudge")
	}
	all := strings.Join(out, "\n")
	has(t, all, "revised tk-a: the revision is on its notes", "the output")
	has(t, all, "sent to sess-live: Nudged sess-live", "the output")
}

// The nudge is one typed line within NudgeMax bytes, whatever the revision's
// length or lines, cut on a character's boundary and marked as cut, while the
// note keeps the revision whole.
func TestReviseNudgeIsOneLineWithinTheBound(t *testing.T) {
	w := newWorld(t)
	text := strings.Repeat("Keep the old endpoint working.\nAdd the new one beside it, ", 30) + "and say where they differ."
	if _, err := w.v.Revise(Request{Bead: "tk-a", Text: text}); err != nil {
		t.Fatalf("Revise: %v", err)
	}
	has(t, w.notes("tk-a"), text, "the note")
	msg := w.rt.Nudges()[0].Message
	if len(msg) > NudgeMax || strings.Contains(msg, "\n") || !strings.HasSuffix(msg, " ...") {
		t.Errorf("a long revision's nudge is %d bytes, ends %q, and must be one line within %d, marked as cut", len(msg), msg[max(len(msg)-20, 0):], NudgeMax)
	}

	w = newWorld(t)
	wide := strings.Repeat("é", NudgeMax)
	if _, err := w.v.Revise(Request{Bead: "tk-a", Text: wide}); err != nil {
		t.Fatalf("Revise: %v", err)
	}
	if msg := w.rt.Nudges()[0].Message; len(msg) > NudgeMax || !utf8.ValidString(msg) {
		t.Errorf("a revision of two-byte characters made a nudge of %d bytes, valid UTF-8 %v", len(msg), utf8.ValidString(msg))
	}
}

// A bead no session works, with no assignee and no live run, takes the note
// alone, and so does one whose only run has ended.
func TestReviseWithNoSessionWritesTheNoteAlone(t *testing.T) {
	w := newWorld(t)
	w.store.Put(fake.Bead{ID: "tk-b", Title: "not started", Status: "open", IssueType: "task"})
	w.store.Put(fake.Bead{ID: "tk-c", Title: "its run ended", Status: "open", IssueType: "task"})
	w.run("tk-c", "tk-root-c", "tk-convoy-c", "closed")
	w.store.Put(fake.Bead{ID: "tk-root-c-impl", Status: "in_progress", Assignee: "sess-live",
		Metadata: map[string]string{"gc.root_bead_id": "tk-root-c"}})
	for _, bead := range []string{"tk-b", "tk-c"} {
		out, err := w.v.Revise(Request{Bead: bead, Text: "Cover the empty case too."})
		if err != nil {
			t.Fatalf("Revise %s: %v", bead, err)
		}
		has(t, w.notes(bead), "Cover the empty case too.", bead+"'s note")
		has(t, strings.Join(out, "\n"), "no session works "+bead+" now", bead+"'s output")
	}
	if n := w.rt.Nudges(); len(n) != 0 {
		t.Errorf("nudged %+v, want none", n)
	}
}

// An empty revision, a closed bead and a bead the store does not hold are
// refused with nothing written and no nudge.
func TestReviseRefusesWithNothingWritten(t *testing.T) {
	w := newWorld(t)
	w.store.Put(fake.Bead{ID: "tk-done", Title: "landed", Status: "closed", IssueType: "task"})
	for _, req := range []Request{
		{Bead: "tk-a", Text: " \n "},
		{Bead: "tk-done", Text: "Change it."},
		{Bead: "tk-nowhere", Text: "Change it."},
	} {
		_, err := w.v.Revise(req)
		if !Refused(err) {
			t.Errorf("%+v: %v, want a refusal", req, err)
		}
	}
	if len(w.store.Writes()) != 0 || len(w.rt.Nudges()) != 0 {
		t.Errorf("a refusal wrote %+v and nudged %+v", w.store.Writes(), w.rt.Nudges())
	}
}

// A holder the session list does not name has gone, a session that runs no
// agent has no reader for a nudge, and a holder that is this session has the
// revision: none is nudged, and each is said.
func TestReviseSkipsWhatCannotReadANudge(t *testing.T) {
	w := newWorld(t)
	w.store.Put(fake.Bead{ID: "tk-root-gone", Status: "in_progress", Assignee: "sess-gone",
		Metadata: map[string]string{"gc.root_bead_id": "tk-root"}})
	w.store.Put(fake.Bead{ID: "tk-root-ralph", Status: "in_progress", Assignee: "sess-ctl",
		Metadata: map[string]string{"gc.root_bead_id": "tk-root", "gc.kind": "ralph"}})
	w.v.Self = []string{"rig__polecat-sess-live", "sess-live"}
	out, err := w.v.Revise(Request{Bead: "tk-a", Text: "Drop the second endpoint."})
	if err != nil {
		t.Fatalf("Revise: %v", err)
	}
	if n := w.rt.Nudges(); len(n) != 0 {
		t.Errorf("nudged %+v, want none", n)
	}
	all := strings.Join(out, "\n")
	has(t, all, "kept sess-live: this session holds work on tk-a", "the output")
	has(t, all, "skipped sess-gone: the session list names no session for it", "the output")
	has(t, all, "skipped sess-ctl: it runs no agent to read a nudge", "the output")
}

// A bead claimed or assigned itself is worked by its assignee, which the
// session list names by its alias, and each session is nudged once, however
// many of the run's members it holds.
func TestReviseReachesTheAssigneeOnceEach(t *testing.T) {
	w := newWorld(t)
	w.store.Put(fake.Bead{ID: "tk-a", Title: "the work", Status: "in_progress", IssueType: "task", Assignee: "rig/gc-toolkit.refinery"})
	w.store.Put(fake.Bead{ID: "tk-root-setup", Status: "open", Assignee: "sess-live",
		Metadata: map[string]string{"gc.root_bead_id": "tk-root", "gc.step_ref": "mol-polecat-work.workspace-setup"}})
	w.roster.SessionList = append(w.roster.SessionList,
		gascity.Session{ID: "sess-ref", Alias: "rig/gc-toolkit.refinery", Provider: "claude-watch", State: "active"})
	if _, err := w.v.Revise(Request{Bead: "tk-a", Text: "Land it on the integration branch."}); err != nil {
		t.Fatalf("Revise: %v", err)
	}
	if got := strings.Join(w.lines("NUDGE "), " | "); got != "NUDGE sess-ref about tk-a | NUDGE sess-live about tk-a" {
		t.Errorf("nudged %q, want the assignee's session and the run's, once each", got)
	}
}

// A revision whose note landed but which may not have reached a session
// working the bead says so: a nudge that did not land, a session list that did
// not read, and a read of the bead's runs that failed each leave the note and
// say what to send by hand.
func TestReviseSaysWhatDidNotReach(t *testing.T) {
	w := newWorld(t)
	w.nudgeFails = true
	out, err := w.v.Revise(Request{Bead: "tk-a", Text: "Use the new schema."})
	if !IsUnsent(err) {
		t.Fatalf("a failed nudge answered %v, want an unsent revision", err)
	}
	has(t, err.Error(), "gc session nudge <session> --delivery immediate --reference-bead tk-a", "the error")
	has(t, strings.Join(out, "\n"), "not sent to sess-live: exit 1", "the output")
	has(t, w.notes("tk-a"), "Use the new schema.", "the note")

	w = newWorld(t)
	w.roster.SessionsErr = errors.New("the supervisor did not answer")
	if _, err := w.v.Revise(Request{Bead: "tk-a", Text: "Use the new schema."}); !IsUnsent(err) {
		t.Errorf("an unread session list answered %v, want an unsent revision", err)
	}
	if n := w.rt.Nudges(); len(n) != 0 || !strings.Contains(w.notes("tk-a"), "Use the new schema.") {
		t.Errorf("an unread session list nudged %+v and left notes %q", n, w.notes("tk-a"))
	}

	w = newWorld(t)
	w.store.DependentsErr = errors.New("the store did not answer")
	if _, err := w.v.Revise(Request{Bead: "tk-a", Text: "Use the new schema."}); !IsUnsent(err) {
		t.Errorf("an unread run link answered %v, want an unsent revision", err)
	}
}

// A note that does not land sends nothing, since the nudge points at it.
func TestReviseSendsNothingWithoutTheNote(t *testing.T) {
	w := newWorld(t)
	w.store.UpdateErr = errors.New("the store did not answer")
	_, err := w.v.Revise(Request{Bead: "tk-a", Text: "Use the new schema."})
	if err == nil || Refused(err) || IsUnsent(err) {
		t.Fatalf("a note that did not land answered %v, want a plain failure", err)
	}
	if n := w.rt.Nudges(); len(n) != 0 {
		t.Errorf("nudged %+v with no note", n)
	}
}
