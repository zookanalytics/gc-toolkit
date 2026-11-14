package arm_test

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/arm"
	rtfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

const (
	pool    = "rig/rig.polecat"
	armedAt = "2026-11-13T06:19:00Z"
)

// world is one store and one Gas City for a test: the fake store, the fake
// runtime, and the arm's verbs over them, on a clock the test moves.
type world struct {
	t     *testing.T
	store *fake.Store
	rt    *rtfake.Runtime
	arms  *arm.Arms
	now   time.Time
}

func newWorld(t *testing.T) *world {
	t.Helper()
	t.Setenv("GC_MAX_DISPATCH_SLING_FAILURES", "")
	w := &world{t: t, store: fake.New(), now: time.Date(2026, 11, 13, 12, 0, 0, 0, time.UTC)}
	w.rt = &rtfake.Runtime{Formulas: map[string]string{pool: "mol-polecat-work"}}
	w.arms = &arm.Arms{Ledger: ledger.New(w.store), Runtime: w.rt, Locks: t.TempDir(),
		Now: func() time.Time { return w.now }, Actor: "the-test", Wait: 300 * time.Millisecond}
	return w
}

// put adds an open bead with meta and edges.
func (w *world) put(b fake.Bead) {
	if b.Status == "" {
		b.Status = "open"
	}
	w.store.Put(b)
}

// armedBead is meta for a bead armed for pool, on formula when one is named.
func armedBead(formula string, extra map[string]string) map[string]string {
	args := "[]"
	if formula != "" {
		args = `["--on","` + formula + `"]`
	}
	m := map[string]string{
		"gc.dispatch_when_ready":          pool,
		"gc.dispatch_when_ready_args":     args,
		"gc.dispatch_when_ready_armed_by": "a-session",
		"gc.dispatch_when_ready_armed_at": armedAt,
		"gc.dispatch_when_ready_reason":   "waits for unit 1",
	}
	for k, v := range extra {
		m[k] = v
	}
	return m
}

func (w *world) meta(id, key string) (string, bool) {
	w.t.Helper()
	row, ok := w.store.Row(id)
	if !ok {
		w.t.Fatalf("the store holds no %s", id)
	}
	v, held := row.Metadata[key]
	return v, held
}

func (w *world) notes(id string) string {
	row, _ := w.store.Row(id)
	return row.Notes
}

func (w *world) armed(id string) bool {
	_, held := w.meta(id, "gc.dispatch_when_ready")
	return held
}

// The arm is one write: every key, no attempts, and a note that keeps the
// prefix the validating closer and the sign-off read. With no --on it records
// the target's default formula.
func TestArmWritesTheArmInOneWrite(t *testing.T) {
	w := newWorld(t)
	w.put(fake.Bead{ID: "b"})
	said, err := w.arms.Arm(arm.Request{ID: "b", Target: pool, Reason: "waits for the base"})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(said, "armed b for "+pool+" on mol-polecat-work") || !strings.Contains(said, "Nothing holds it now") {
		t.Errorf("arm said %q", said)
	}
	writes := w.store.Writes()
	if len(writes) != 1 {
		t.Fatalf("%d writes, want one", len(writes))
	}
	if args, _ := w.meta("b", "gc.dispatch_when_ready_args"); args != `["--on","mol-polecat-work"]` {
		t.Errorf("args = %q, want the target's default formula named", args)
	}
	if at, _ := w.meta("b", "gc.dispatch_when_ready_armed_at"); at != "2026-11-13T12:00:00.000000000Z" {
		t.Errorf("armed at = %q, want the time to the nanosecond", at)
	}
	if by, _ := w.meta("b", "gc.dispatch_when_ready_armed_by"); by != "the-test" {
		t.Errorf("armed by = %q", by)
	}
	if n := w.notes("b"); !strings.HasPrefix(n, "deferred-dispatch: dispatch armed by the-test at 2026-11-13T12:00:00.000000000Z, for "+pool+" on mol-polecat-work: waits for the base.") {
		t.Errorf("note = %q", n)
	}
	if _, err := os.ReadDir(w.arms.Locks); err != nil {
		t.Fatal(err)
	}
	if left, _ := filepath.Glob(filepath.Join(w.arms.Locks, "*")); len(left) != 0 {
		t.Errorf("the arm left lock files behind: %v", left)
	}
}

// An arm already on the bead for the same target and formula is a success
// that writes nothing, an arm that names none matching the target's default.
// Another arm is refused, and so is one that does not decode.
func TestArmOnAnArmedBead(t *testing.T) {
	w := newWorld(t)
	w.put(fake.Bead{ID: "same", Metadata: armedBead("mol-polecat-work", nil)})
	w.put(fake.Bead{ID: "default", Metadata: armedBead("", nil)})
	w.put(fake.Bead{ID: "other", Metadata: armedBead("mol-validate-close", nil)})
	w.put(fake.Bead{ID: "broken", Metadata: armedBead("", map[string]string{"gc.dispatch_when_ready_args": "nope"})})
	for _, id := range []string{"same", "default"} {
		said, err := w.arms.Arm(arm.Request{ID: id, Target: pool, Formula: "mol-polecat-work", Reason: "again"})
		if err != nil || !strings.Contains(said, "already armed") {
			t.Errorf("%s: arm = %q, %v; want already armed", id, said, err)
		}
	}
	if _, err := w.arms.Arm(arm.Request{ID: "same", Target: pool, Reason: "again"}); err != nil {
		t.Errorf("an arm naming no formula over one on the default = %v", err)
	}
	for _, id := range []string{"other", "broken"} {
		if _, err := w.arms.Arm(arm.Request{ID: id, Target: pool, Formula: "mol-polecat-work", Reason: "again"}); !arm.Refused(err) {
			t.Errorf("%s: arm = %v; want refused", id, err)
		}
	}
	if n := len(w.store.Writes()); n != 0 {
		t.Errorf("%d writes, want none", n)
	}
}

// With no --on, an arm for a target whose agent names no default formula of its
// own records the one its pack gives it, which the runtime reads by asking
// about the bead armed. An arm naming no --on over an arm that names no formula
// for that target is the same arm.
func TestArmRecordsThePacksDefaultFormula(t *testing.T) {
	w := newWorld(t)
	const inherits = "rig/rig.inherits"
	w.rt.PackFormulas = map[string]string{inherits: "mol-pack"}
	w.put(fake.Bead{ID: "b"})
	w.put(fake.Bead{ID: "old", Metadata: armedBead("", map[string]string{"gc.dispatch_when_ready": inherits})})
	if _, err := w.arms.Arm(arm.Request{ID: "b", Target: inherits, Reason: "r"}); err != nil {
		t.Fatal(err)
	}
	if args, _ := w.meta("b", "gc.dispatch_when_ready_args"); args != `["--on","mol-pack"]` {
		t.Errorf("the arm recorded %s; want the pack's formula", args)
	}
	if said, err := w.arms.Arm(arm.Request{ID: "old", Target: inherits, Reason: "again"}); err != nil || !strings.Contains(said, "already armed") {
		t.Errorf("an arm over one with no formula = %q, %v; want already armed", said, err)
	}
	for _, s := range w.rt.Asks() {
		if s.Target != inherits || (s.Bead != "b" && s.Bead != "old") {
			t.Errorf("asked %+v; want each ask to name its target and the bead armed", s)
		}
	}
}

// What arm refuses, each writing nothing.
func TestArmRefusals(t *testing.T) {
	w := newWorld(t)
	w.rt.Formulas["rig/rig.raw"] = ""
	w.put(fake.Bead{ID: "closed", Status: "closed"})
	w.put(fake.Bead{ID: "claimed", Status: "in_progress"})
	w.put(fake.Bead{ID: "routed", Metadata: map[string]string{"gc.routed_to": pool}})
	w.put(fake.Bead{ID: "deferred", Status: "deferred"})
	w.put(fake.Bead{ID: "plain"})
	w.put(fake.Bead{ID: "foreign", Edges: []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "xx-1"}}})
	for _, tc := range []struct {
		name string
		req  arm.Request
		says string
	}{
		{"a closed bead", arm.Request{ID: "closed", Target: pool, Reason: "r"}, "is closed"},
		{"a bead in progress", arm.Request{ID: "claimed", Target: pool, Reason: "r"}, "dispatched already"},
		{"a routed bead", arm.Request{ID: "routed", Target: pool, Reason: "r"}, "dispatched already"},
		{"a bead at another status", arm.Request{ID: "deferred", Target: pool, Reason: "r"}, "status deferred"},
		{"a target with no formula to pour", arm.Request{ID: "plain", Target: "rig/rig.raw", Reason: "r"}, "--no-formula --no-convoy"},
		{"a target the config does not name", arm.Request{ID: "plain", Target: "rig/rig.none", Reason: "r"}, "name one with --on"},
		{"a wait edge into another store", arm.Request{ID: "foreign", Target: pool, Reason: "r"}, "xx-1"},
		{"no target", arm.Request{ID: "plain", Reason: "r"}, "names the pool or agent"},
	} {
		_, err := w.arms.Arm(tc.req)
		if !arm.Refused(err) || !strings.Contains(err.Error(), tc.says) {
			t.Errorf("%s: arm = %v; want refused, saying %q", tc.name, err, tc.says)
		}
	}
	if _, err := w.arms.Arm(arm.Request{ID: "gone", Target: pool, Reason: "r"}); err == nil || arm.Refused(err) {
		t.Errorf("a bead the store does not hold = %v; want a read error", err)
	}
	if n := len(w.store.Writes()); n != 0 {
		t.Errorf("%d writes, want none", n)
	}
}

// What arm says holds the bead: a hold label in any spelling, an assignee, or
// the waits gctk bead holds names.
func TestArmSaysWhatHoldsTheBead(t *testing.T) {
	w := newWorld(t)
	w.put(fake.Bead{ID: "label", Labels: []string{" Hold:Mayor "}})
	w.put(fake.Bead{ID: "assigned", Assignee: "rig/mechanik"})
	w.put(fake.Bead{ID: "blocker", Title: "the base"})
	w.put(fake.Bead{ID: "blocked", Edges: []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "blocker", Status: "open", Title: "the base"}}})
	w.store.List("blocked", "blocker")
	w.store.Mark("blocked")
	for id, says := range map[string]string{
		"label":    "Its Hold:Mayor label holds it",
		"assigned": "It is assigned to rig/mechanik",
		"blocked":  `blocker "the base" holds it`,
	} {
		said, err := w.arms.Arm(arm.Request{ID: id, Target: pool, Reason: "r"})
		if err != nil || !strings.Contains(said, says) {
			t.Errorf("%s: arm = %q, %v; want it to say %q", id, said, err, says)
		}
	}
}

// Disarm clears the whole arm in one write with its note, and a bead with no
// arm left is a success that writes nothing.
func TestDisarm(t *testing.T) {
	w := newWorld(t)
	w.put(fake.Bead{ID: "b", Metadata: armedBead("mol-x", map[string]string{"gc.dispatch_when_ready_fail_count": "2", "other": "kept"})})
	w.put(fake.Bead{ID: "plain"})
	if said, err := w.arms.Disarm("b", "superseded by c"); err != nil || said != "disarmed b" {
		t.Fatalf("disarm = %q, %v", said, err)
	}
	row, _ := w.store.Row("b")
	if len(row.Metadata) != 1 || row.Metadata["other"] != "kept" {
		t.Errorf("after disarm = %v; want only the key that is not the arm's", row.Metadata)
	}
	if n := w.notes("b"); n != "deferred-dispatch: dispatch record cleared at 2026-11-13T12:00:00Z: superseded by c" {
		t.Errorf("note = %q", n)
	}
	if said, err := w.arms.Disarm("plain", "nothing"); err != nil || !strings.Contains(said, "carries no arm") {
		t.Errorf("disarm of an unarmed bead = %q, %v", said, err)
	}
	if _, err := w.arms.Disarm("gone", "r"); err == nil {
		t.Error("a disarm of a bead the store does not hold succeeded")
	}
	if n := len(w.store.Writes()); n != 1 {
		t.Errorf("%d writes, want one", n)
	}
}

// Arm and disarm wait for a start that holds the bead's lock, and a lock still
// held at the end of the wait is an error that names its holder and writes
// nothing.
func TestTheVerbsWaitOnTheDispatchLock(t *testing.T) {
	w := newWorld(t)
	w.put(fake.Bead{ID: "b", Metadata: armedBead("mol-x", nil)})
	path := filepath.Join(w.arms.Locks, "dispatch-b.lock")
	f, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE, 0o644)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		t.Fatal(err)
	}
	if _, err := f.WriteString("pid 4242 since 2026-11-13T12:00:00Z\n"); err != nil {
		t.Fatal(err)
	}
	if _, err := w.arms.Disarm("b", "r"); err == nil || !strings.Contains(err.Error(), "pid 4242") {
		t.Errorf("disarm under a held lock = %v; want an error naming the holder", err)
	}
	if n := len(w.store.Writes()); n != 0 {
		t.Errorf("%d writes under a held lock, want none", n)
	}
	released := make(chan struct{})
	go func() {
		time.Sleep(100 * time.Millisecond)
		_ = syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
		close(released)
	}()
	if _, err := w.arms.Disarm("b", "r"); err != nil {
		t.Errorf("disarm once the lock is released = %v", err)
	}
	<-released
	if w.armed("b") {
		t.Error("the arm survived its disarm")
	}
}

// The verbs read the target's default formula from Gas City and sling and ask
// nothing.
func TestTheVerbsAskNothingOfGasCityButTheFormula(t *testing.T) {
	w := newWorld(t)
	w.put(fake.Bead{ID: "b"})
	if _, err := w.arms.Arm(arm.Request{ID: "b", Target: pool, Formula: "mol-x", Reason: "r"}); err != nil {
		t.Fatal(err)
	}
	if _, err := w.arms.Disarm("b", "r"); err != nil {
		t.Fatal(err)
	}
	if len(w.rt.Slings()) != 0 || len(w.rt.Scripts()) != 0 {
		t.Errorf("the verbs slung %v and ran %v", w.rt.Slings(), w.rt.Scripts())
	}
	if !slices.ContainsFunc(w.store.Writes(), func(x fake.Write) bool { return x.ID == "b" }) {
		t.Error("nothing was written")
	}
}
