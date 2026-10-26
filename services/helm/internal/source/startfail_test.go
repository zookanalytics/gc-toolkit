package source

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/steveyegge/beads"
	"github.com/zookanalytics/gc-toolkit/services/helm/internal/board"
)

// The visit every case below is about, and the alias `gc-helm engage` spawns
// its sitting under, qualified the way Gas City stores it.
const (
	failVisit = "tk-vis"
	failAlias = "gc-toolkit/gc-toolkit.tk-vis"
)

// metaJSON is a bead's metadata from key, value pairs.
func metaJSON(kv ...string) string {
	m := map[string]string{}
	for i := 0; i+1 < len(kv); i += 2 {
		m[kv[i]] = kv[i+1]
	}
	b, err := json.Marshal(m)
	if err != nil {
		panic(err)
	}
	return string(b)
}

// sessionBead is a session bead the way `gc session new <template> --alias
// <alias>` leaves one in the city store: a manual session whose alias and agent
// name are the qualified alias. closed nil is a session that is still open.
func sessionBead(id, alias, state string, created time.Time, closed *time.Time) *beads.Issue {
	i := issue(id, "gc-toolkit/gc-toolkit.converse-opus", "session", 2, created, metaJSON(
		"alias", alias, "agent_name", alias, "session_name", "s-"+id,
		"session_origin", "manual", "state", state))
	i.CreatedAt = created
	if closed != nil {
		c := *closed
		i.Status = beads.StatusClosed
		i.ClosedAt = &c
		i.UpdatedAt = c
	}
	return i
}

// episodeBead is the startup-health episode Gas City keeps for a session name.
func episodeBead(id, sessionName, kind, detail string, count int, created time.Time) *beads.Issue {
	i := issue(id, "Startup health: "+sessionName, "startup-health-episode", 2, created, metaJSON(
		"startup_health_session_name", sessionName, "startup_health_kind", kind,
		"startup_health_last_detail", detail, "startup_health_consecutive", strconv.Itoa(count)))
	i.CreatedAt = created
	return i
}

// boundVisit is the visit as a failed start leaves it: in_progress under the
// sitting's alias, the binding the witness later releases.
func boundVisit(id string, created time.Time) *beads.Issue {
	i := visitBead(id, "visit: tk-subj — talk the plan over", metaJSON(
		"task_kind", "visit", "gc.routed_to", "human", "gc.continuation_group", "tk-subj"), created)
	i.Status = beads.StatusInProgress
	i.Assignee = failAlias
	return i
}

// failCity lays out a city with an HQ store beside one rig, and returns the
// root and the HQ store's name in the opener's map: the city directory's base.
func failCity(t *testing.T) (root, hqName string) {
	t.Helper()
	root = cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	hq := filepath.Join(root, ".beads")
	if err := os.MkdirAll(hq, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(hq, "config.yaml"), []byte("issue_prefix: hq\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	return root, filepath.Base(root)
}

func minsBefore(m int) time.Time { return testNow.Add(-time.Duration(m) * time.Minute) }

func ptime(t time.Time) *time.Time { return &t }

// gatherFailures gathers a city whose rig holds visits and whose HQ store holds
// sessions and episodes, and returns the result.
func gatherFailures(t *testing.T, visits []*beads.Issue, hq *fakeStore) *Result {
	t.Helper()
	root, hqName := failCity(t)
	rig := &fakeStore{issues: map[string][]*beads.Issue{"task": visits}}
	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": rig, hqName: hq})
	res, err := src.Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	return res
}

func hqWith(sessions []*beads.Issue, episodes ...*beads.Issue) *fakeStore {
	return &fakeStore{failType: map[string]error{}, issues: map[string][]*beads.Issue{
		"session":                sessions,
		"startup-health-episode": episodes,
	}}
}

// TestStartFailureReadsGasCitysRecord: the reason is read from the record Gas
// City keeps of the start, not inferred. A deadline is a startup timeout unless
// the episode places it in a pre_start command; no episode, or a cleared one,
// is a rollback that recorded no cause; any other failure carries the error the
// episode recorded.
func TestStartFailureReadsGasCitysRecord(t *testing.T) {
	failed := sessionBead("hq-wisp-f1", failAlias, "failed-create", minsBefore(9), ptime(minsBefore(8)))
	cases := []struct {
		name     string
		episodes []*beads.Issue
		want     string
	}{
		{"startup timeout",
			[]*beads.Issue{episodeBead("hq-ep1", "s-hq-wisp-f1", "timeout", "resuming session: context deadline exceeded", 1, minsBefore(8))},
			"startup timeout"},
		{"setup timeout",
			[]*beads.Issue{episodeBead("hq-ep1", "s-hq-wisp-f1", "timeout",
				"resuming session: running pre_start: pre_start[0]: context deadline exceeded: signal: killed", 1, minsBefore(8))},
			"setup timeout"},
		{"never started", nil, "never started"},
		{"cleared episode",
			[]*beads.Issue{episodeBead("hq-ep1", "s-hq-wisp-f1", "", "", 0, minsBefore(8))},
			"never started"},
		{"other error",
			[]*beads.Issue{episodeBead("hq-ep1", "s-hq-wisp-f1", "other", "resuming session:\n  exec: claude-pick: not found", 1, minsBefore(8))},
			"start error: resuming session: exec: claude-pick: not found"},
		// The episode of a different session name says nothing about this one.
		{"another session's episode",
			[]*beads.Issue{episodeBead("hq-ep1", "s-hq-wisp-other", "timeout", "context deadline exceeded", 1, minsBefore(8))},
			"never started"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			res := gatherFailures(t, []*beads.Issue{boundVisit(failVisit, minsBefore(10))},
				hqWith([]*beads.Issue{failed}, c.episodes...))
			if got := sittingsByID(res)[failVisit].StartFailure; got != c.want {
				t.Errorf("StartFailure = %q, want %q", got, c.want)
			}
			if res.Partial {
				t.Errorf("a whole read is not partial: %v", res.PartialErrors)
			}
		})
	}
}

// TestProviderErrorIsReadOffTheSession: a start that failed on a provider error
// a person must fix accrues no episode. The rollback writes the error's code to
// the session bead in the write that closes it, so the reason is read there,
// not taken for a create that never started.
func TestProviderErrorIsReadOffTheSession(t *testing.T) {
	for _, c := range []struct{ code, want string }{
		{"quota_exceeded", "provider error: quota_exceeded"},
		{"model_not_found", "provider error: model_not_found"},
	} {
		t.Run(c.code, func(t *testing.T) {
			failed := sessionBead("hq-wisp-f1", failAlias, "failed-create", minsBefore(9), ptime(minsBefore(8)))
			failed.Metadata = json.RawMessage(metaJSON("alias", failAlias, "agent_name", failAlias,
				"session_name", "s-hq-wisp-f1", "session_origin", "manual", "state", "failed-create",
				"session_health", "unhealthy", "session_health_reason", c.code, "provider_terminal_error", c.code))
			res := gatherFailures(t, []*beads.Issue{boundVisit(failVisit, minsBefore(10))}, hqWith([]*beads.Issue{failed}))
			if got := sittingsByID(res)[failVisit].StartFailure; got != c.want {
				t.Errorf("StartFailure = %q, want %q", got, c.want)
			}
		})
	}
}

// TestStartErrorIsBounded: the error an episode carries runs to 500 runes, and
// the reason leads a row's NEEDS, so it is clipped and says so.
func TestStartErrorIsBounded(t *testing.T) {
	long := "resuming session: " + strings.Repeat("x", 400)
	res := gatherFailures(t, []*beads.Issue{boundVisit(failVisit, minsBefore(10))}, hqWith(
		[]*beads.Issue{sessionBead("hq-wisp-f1", failAlias, "failed-create", minsBefore(9), ptime(minsBefore(8)))},
		episodeBead("hq-ep1", "s-hq-wisp-f1", "other", long, 1, minsBefore(8))))
	got := sittingsByID(res)[failVisit].StartFailure
	if !strings.HasPrefix(got, "start error: resuming session: x") || !strings.HasSuffix(got, "…") {
		t.Errorf("a long error is carried clipped, marked: %q", got)
	}
	if n := len([]rune(got)); n > len("start error: ")+startErrorMax+1 {
		t.Errorf("the reason runs to %d runes", n)
	}
}

// TestEngagingAgainClearsTheFailure: a session spawned under the visit's alias
// after the failed one is the visit engaged again, whatever became of that
// session, so the failure no longer describes the visit. A newer session that
// failed too is the visit's failure now, with its own reason.
func TestEngagingAgainClearsTheFailure(t *testing.T) {
	failed := sessionBead("hq-wisp-f1", failAlias, "failed-create", minsBefore(9), ptime(minsBefore(8)))
	timeout := episodeBead("hq-ep1", "s-hq-wisp-f1", "timeout", "context deadline exceeded", 1, minsBefore(8))
	cases := []struct {
		name  string
		newer *beads.Issue
		eps   []*beads.Issue
		want  string
	}{
		{"a newer sitting still starting",
			sessionBead("hq-wisp-n2", failAlias, "start-pending", minsBefore(2), nil), nil, ""},
		{"a newer sitting that ran and closed",
			sessionBead("hq-wisp-n2", failAlias, "closed", minsBefore(6), ptime(minsBefore(1))), nil, ""},
		{"a newer sitting that failed too",
			sessionBead("hq-wisp-n2", failAlias, "failed-create", minsBefore(6), ptime(minsBefore(5))),
			[]*beads.Issue{episodeBead("hq-ep2", "s-hq-wisp-n2", "timeout",
				"resuming session: running pre_start: pre_start[0]: context deadline exceeded", 1, minsBefore(5))},
			"setup timeout"},
		// An older session under the same alias is history, not a re-engagement.
		{"an older sitting under the alias",
			sessionBead("hq-wisp-o0", failAlias, "closed", minsBefore(30), ptime(minsBefore(20))), nil, "startup timeout"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			res := gatherFailures(t, []*beads.Issue{boundVisit(failVisit, minsBefore(40))},
				hqWith([]*beads.Issue{failed, c.newer}, append([]*beads.Issue{timeout}, c.eps...)...))
			if got := sittingsByID(res)[failVisit].StartFailure; got != c.want {
				t.Errorf("StartFailure = %q, want %q", got, c.want)
			}
		})
	}
}

// TestStartFailureReadsOnlyWhatNamesAnOpenVisit: the mark belongs to an open
// visit whose alias a failed manual session carries, and to nothing else.
func TestStartFailureReadsOnlyWhatNamesAnOpenVisit(t *testing.T) {
	timeout := func(name string) *beads.Issue {
		return episodeBead("hq-ep-"+name, name, "timeout", "context deadline exceeded", 1, minsBefore(8))
	}

	t.Run("a closed visit", func(t *testing.T) {
		v := closedVisitBead(failVisit, "visit: tk-subj — done", metaJSON("task_kind", "visit", "gc.continuation_group", "tk-subj"),
			minsBefore(10), minsBefore(1))
		res := gatherFailures(t, []*beads.Issue{v}, hqWith(
			[]*beads.Issue{sessionBead("hq-wisp-f1", failAlias, "failed-create", minsBefore(9), ptime(minsBefore(8)))},
			timeout("s-hq-wisp-f1")))
		if got := sittingsByID(res)[failVisit].StartFailure; got != "" {
			t.Errorf("a closed visit is never marked: %q", got)
		}
	})

	t.Run("a failed session for another bead", func(t *testing.T) {
		res := gatherFailures(t, []*beads.Issue{boundVisit(failVisit, minsBefore(10))}, hqWith(
			[]*beads.Issue{
				sessionBead("hq-wisp-f1", "gc-toolkit/gc-toolkit.tk-other", "failed-create", minsBefore(9), ptime(minsBefore(8))),
				// The visit id as a suffix of a longer segment is another bead.
				sessionBead("hq-wisp-f2", "gc-toolkit/gc-toolkit.xtk-vis", "failed-create", minsBefore(9), ptime(minsBefore(8))),
			},
			timeout("s-hq-wisp-f1"), timeout("s-hq-wisp-f2")))
		if got := sittingsByID(res)[failVisit].StartFailure; got != "" {
			t.Errorf("a failed session whose alias names another bead does not mark this visit: %q", got)
		}
	})

	t.Run("a session that is not manual", func(t *testing.T) {
		pool := sessionBead("hq-wisp-f1", failAlias, "failed-create", minsBefore(9), ptime(minsBefore(8)))
		pool.Metadata = json.RawMessage(metaJSON("alias", failAlias, "session_name", "s-hq-wisp-f1",
			"session_origin", "ephemeral", "state", "failed-create"))
		res := gatherFailures(t, []*beads.Issue{boundVisit(failVisit, minsBefore(10))}, hqWith(
			[]*beads.Issue{pool}, timeout("s-hq-wisp-f1")))
		if got := sittingsByID(res)[failVisit].StartFailure; got != "" {
			t.Errorf("only a manual session is a sitting engage spawned: %q", got)
		}
	})

	t.Run("a session that started", func(t *testing.T) {
		res := gatherFailures(t, []*beads.Issue{boundVisit(failVisit, minsBefore(10))}, hqWith(
			[]*beads.Issue{sessionBead("hq-wisp-f1", failAlias, "closed", minsBefore(9), ptime(minsBefore(8)))},
			timeout("s-hq-wisp-f1")))
		if got := sittingsByID(res)[failVisit].StartFailure; got != "" {
			t.Errorf("a session that closed after it started did not fail to start: %q", got)
		}
	})
}

// TestStartFailureFollowsEveryAliasForm: engage falls back to a `v-` alias for
// an id Gas City refuses, and a bead id may itself contain a dot. Both still
// name their visit; an alias with no binding prefix does too.
func TestStartFailureFollowsEveryAliasForm(t *testing.T) {
	for _, c := range []struct{ visit, alias string }{
		{"rb-62297", "rig-b/gc-toolkit.v-rb-62297"},
		{"tk-abc.3", "gc-toolkit/gc-toolkit.tk-abc.3"},
		{"tk-vis", "tk-vis"},
	} {
		t.Run(c.alias, func(t *testing.T) {
			res := gatherFailures(t, []*beads.Issue{boundVisit(c.visit, minsBefore(10))}, hqWith(
				[]*beads.Issue{sessionBead("hq-wisp-f1", c.alias, "failed-create", minsBefore(9), ptime(minsBefore(8)))},
				episodeBead("hq-ep1", "s-hq-wisp-f1", "timeout", "context deadline exceeded", 1, minsBefore(8))))
			if got := sittingsByID(res)[c.visit].StartFailure; got != "startup timeout" {
				t.Errorf("alias %q names visit %q: StartFailure = %q", c.alias, c.visit, got)
			}
		})
	}
}

// TestOpenFailedCreateRowIsRead: a rollback whose close has not landed leaves
// the row open in failed-create. The failure is recorded all the same.
func TestOpenFailedCreateRowIsRead(t *testing.T) {
	res := gatherFailures(t, []*beads.Issue{boundVisit(failVisit, minsBefore(10))}, hqWith(
		[]*beads.Issue{sessionBead("hq-wisp-f1", failAlias, "failed-create", minsBefore(9), nil)},
		episodeBead("hq-ep1", "s-hq-wisp-f1", "timeout", "context deadline exceeded", 1, minsBefore(8))))
	if got := sittingsByID(res)[failVisit].StartFailure; got != "startup timeout" {
		t.Errorf("an open failed-create row is a recorded failure: %q", got)
	}
}

// TestStartFailureReadFailures: a session read that fails marks nothing it
// could not establish and says so; an episode read that fails comes after the
// failure is established, so the sitting is marked with an unread reason.
func TestStartFailureReadFailures(t *testing.T) {
	sessions := []*beads.Issue{sessionBead("hq-wisp-f1", failAlias, "failed-create", minsBefore(9), ptime(minsBefore(8)))}

	hq := hqWith(sessions)
	hq.failType["session"] = errors.New("session read timed out")
	res := gatherFailures(t, []*beads.Issue{boundVisit(failVisit, minsBefore(10))}, hq)
	if got := sittingsByID(res)[failVisit].StartFailure; got != "" {
		t.Errorf("an unread session list marks nothing: %q", got)
	}
	if !res.Partial || !strings.Contains(strings.Join(res.PartialErrors, "; "), "start-failures@") {
		t.Errorf("a failed session read is reported partial: %v", res.PartialErrors)
	}

	hq = hqWith(sessions)
	hq.failType["startup-health-episode"] = errors.New("episode read timed out")
	res = gatherFailures(t, []*beads.Issue{boundVisit(failVisit, minsBefore(10))}, hq)
	if got := sittingsByID(res)[failVisit].StartFailure; got != "reason unread" {
		t.Errorf("an unread episode still marks the established failure: %q", got)
	}
	if !res.Partial {
		t.Error("a failed episode read is reported partial")
	}
}

// TestNoHQStoreReadsNoFailures: a city without its own store has nowhere to
// read sessions from, and gathers its rigs exactly as before.
func TestNoHQStoreReadsNoFailures(t *testing.T) {
	root := cityWithRigs(t, map[string]string{"gc-toolkit": "tk"})
	rig := &fakeStore{issues: map[string][]*beads.Issue{"task": {boundVisit(failVisit, minsBefore(10))}}}
	res, err := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": rig}).Gather(context.Background())
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	if got := sittingsByID(res)[failVisit].StartFailure; got != "" || res.Partial {
		t.Errorf("no HQ store, no failure read: %q partial=%v %v", got, res.Partial, res.PartialErrors)
	}
}

// pickerCap is the row cap tmux-pick-helm.sh asks the board for, read off the
// script so the test cuts the queue where the picker does.
func pickerCap(t *testing.T) int {
	t.Helper()
	src, err := os.ReadFile("../../../../assets/scripts/tmux-pick-helm.sh")
	if err != nil {
		t.Fatalf("read the picker: %v", err)
	}
	m := regexp.MustCompile(`board --json --limit=(\d+)`).FindSubmatch(src)
	if m == nil {
		t.Fatal("found no capped board invocation in tmux-pick-helm.sh")
	}
	n, err := strconv.Atoi(string(m[1]))
	if err != nil || n <= 0 {
		t.Fatalf("the picker's cap %q is not a positive count", m[1])
	}
	return n
}

// TestFailedStartReadsOnTheBoardInsideThePickerCutUntilEngagedAgain is the
// whole path. An engaged visit's sitting fails to start, and Gas City records it
// as it does: the session closes as failed-create and a timeout episode names
// the session. The visit's row reads start failed with the reason. On a board
// holding more owed rows than the picker offers, every one of them older, the
// row is among the rows the picker offers. Engaging the visit again clears the
// mark.
func TestFailedStartReadsOnTheBoardInsideThePickerCutUntilEngagedAgain(t *testing.T) {
	limit := pickerCap(t)

	// The visit's subject, an epic with work under it, so the visit folds onto
	// its row; and more owed rows than the picker shows, each owed for days.
	subject := issue("tk-subj", "the plan", "epic", 2, minsBefore(60), "")
	tasks := []*beads.Issue{boundVisit(failVisit, minsBefore(10))}
	for i := 0; i < limit+5; i++ {
		tasks = append(tasks, issue(fmt.Sprintf("tk-old%02d", i), "waiting on a person", "task", 2,
			testNow.Add(-time.Duration(30+i)*24*time.Hour), metaJSON("gc.routed_to", "human")))
	}
	rig := &fakeStore{
		issues: map[string][]*beads.Issue{"epic": {subject}, "task": tasks},
		depsUp: map[string][]*beads.IssueWithDependencyMetadata{
			"tk-subj": {withDepType(child("tk-subj.1", "open", minsBefore(60), ""), "parent-child")},
		},
	}
	hq := hqWith(
		[]*beads.Issue{sessionBead("hq-wisp-f1", failAlias, "failed-create", minsBefore(9), ptime(minsBefore(8)))},
		episodeBead("hq-ep1", "s-hq-wisp-f1", "timeout", "resuming session: context deadline exceeded", 1, minsBefore(8)))

	root, hqName := failCity(t)
	src := newBeadsTestSource(t, root, map[string]*fakeStore{"gc-toolkit": rig, hqName: hq})
	offered := func() (board.Board, []board.Tile) {
		t.Helper()
		res, err := src.Gather(context.Background())
		if err != nil {
			t.Fatalf("Gather: %v", err)
		}
		b := board.BuildBoard(res.Anchors, testNow, res.Partial, res.PartialErrors, res.Facts)
		return b, board.CapQueue(board.OperatorQueue(b.Tiles), limit)
	}
	find := func(rows []board.Tile, id string) (board.Tile, bool) {
		for _, r := range rows {
			if r.ID == id {
				return r, true
			}
		}
		return board.Tile{}, false
	}

	b, rows := offered()
	if owed := len(board.OperatorQueue(b.Tiles)); owed <= limit {
		t.Fatalf("fixture: the queue holds %d owed rows, not more than the picker's %d", owed, limit)
	}
	row, ok := find(rows, "tk-subj")
	if !ok {
		t.Fatalf("the visit's row is not among the %d rows the picker offers", limit)
	}
	if row.VisitState != board.VisitStartFailed || row.VisitStartFailure != "startup timeout" {
		t.Errorf("the row reads start failed with the reason: state=%q reason=%q", row.VisitState, row.VisitStartFailure)
	}
	if !strings.HasPrefix(row.Needs, "start failed (startup timeout)") {
		t.Errorf("NEEDS leads with the failure: %q", row.Needs)
	}

	// Control: without the failure on record, the same fresh row sorts below
	// the picker's cut, which is why the cut above is a finding.
	saved := hq.issues["session"]
	hq.issues["session"] = nil
	if _, ok := find(func() []board.Tile { _, r := offered(); return r }(), "tk-subj"); ok {
		t.Error("control: with no failure recorded the fresh row should sort below the picker's cut")
	}
	hq.issues["session"] = saved

	// Engage the visit again: the witness has released the dead binding, and
	// engage spawns a fresh sitting under the visit's alias and binds the visit.
	tasks[0].Status = beads.StatusOpen
	tasks[0].Assignee = "s-hq-wisp-n2"
	hq.issues["session"] = append(hq.issues["session"],
		sessionBead("hq-wisp-n2", failAlias, "start-pending", minsBefore(1), nil))
	b, _ = offered()
	again, ok := tileOf(b, "tk-subj")
	if !ok {
		t.Fatal("the visit's row left the board")
	}
	if again.VisitState != board.VisitEngaged || again.VisitStartFailure != "" || strings.HasPrefix(again.Needs, "start failed") {
		t.Errorf("engaging the visit again clears the mark: state=%q reason=%q needs=%q",
			again.VisitState, again.VisitStartFailure, again.Needs)
	}
}

func tileOf(b board.Board, id string) (board.Tile, bool) {
	for _, t := range b.Tiles {
		if t.ID == id {
			return t, true
		}
	}
	return board.Tile{}, false
}
