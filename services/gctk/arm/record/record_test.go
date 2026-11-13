package record_test

import (
	"reflect"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/arm/record"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// armOf puts a bead carrying meta and reads its arm back through the ledger.
func armOf(t *testing.T, meta map[string]string) *record.Arm {
	t.Helper()
	s := fake.New()
	s.Put(fake.Bead{ID: "b", Status: "open", Metadata: meta})
	rows, err := ledger.New(s).Find(ledger.ByID("b"))
	if err != nil || len(rows) != 1 {
		t.Fatalf("find = %v, %v", rows, err)
	}
	return record.Of(rows[0])
}

func armed(extra map[string]string) map[string]string {
	m := map[string]string{
		"gc.dispatch_when_ready":          "rig/rig.polecat",
		"gc.dispatch_when_ready_armed_by": "a-session",
		"gc.dispatch_when_ready_armed_at": "2026-11-13T06:19:00Z",
		"gc.dispatch_when_ready_reason":   "waits for unit 1",
	}
	for k, v := range extra {
		m[k] = v
	}
	return m
}

// The formula a start pours comes from each form the arm's arguments are
// stored in: --on and its value, --on=<formula>, and an empty or absent list,
// which pours the target's default. Any other list is malformed, and so is one
// that does not decode.
func TestTheFormulaFromEachStoredForm(t *testing.T) {
	for _, tc := range []struct {
		name, args, formula, malformed string
	}{
		{name: "--on and its value", args: `["--on","mol-validate-close"]`, formula: "mol-validate-close"},
		{name: "--on=<formula>", args: `["--on=mol-polecat-report"]`, formula: "mol-polecat-report"},
		{name: "an empty list", args: `[]`},
		{name: "absent", args: "<absent>"},
		{name: "a list that does not decode", args: `not json`, malformed: "does not decode"},
		{name: "a value that is no list", args: `"--on mol-x"`, malformed: "does not decode"},
		{name: "--on with no value", args: `["--on"]`, malformed: "name no formula alone"},
		{name: "--on with an empty value", args: `["--on",""]`, malformed: "name no formula alone"},
		{name: "another argument beside --on", args: `["--on","mol-x","--var","a=b"]`, malformed: "name no formula alone"},
		{name: "an argument that is not --on", args: `["--merge","mr"]`, malformed: "name no formula alone"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			meta := armed(nil)
			if tc.args != "<absent>" {
				meta["gc.dispatch_when_ready_args"] = tc.args
			}
			a := armOf(t, meta)
			if a == nil {
				t.Fatal("an armed bead read no arm")
			}
			if a.Formula != tc.formula {
				t.Errorf("formula = %q, want %q", a.Formula, tc.formula)
			}
			if tc.malformed == "" && a.Malformed != "" {
				t.Errorf("malformed = %q, want none", a.Malformed)
			}
			if tc.malformed != "" && !strings.Contains(a.Malformed, tc.malformed) {
				t.Errorf("malformed = %q, want it to say %q", a.Malformed, tc.malformed)
			}
		})
	}
}

// The attempts read below, at and past the cap, which is
// GC_MAX_DISPATCH_SLING_FAILURES, 3 when it is unset or not a whole number. A
// count that does not decode is malformed.
func TestTheAttemptsAgainstTheCap(t *testing.T) {
	for _, tc := range []struct {
		name, cap, count string
		attempts         int
		capped           bool
		malformed        bool
	}{
		{name: "none", count: "<absent>"},
		{name: "below the default cap", count: "2", attempts: 2},
		{name: "at the default cap", count: "3", attempts: 3, capped: true},
		{name: "past the default cap", count: "5", attempts: 5, capped: true},
		{name: "at a cap the setting names", cap: "1", count: "1", attempts: 1, capped: true},
		{name: "below a cap the setting names", cap: "5", count: "4", attempts: 4},
		{name: "a setting that is no number", cap: "many", count: "3", attempts: 3, capped: true},
		{name: "a count that is no number", count: "two", malformed: true},
		{name: "a negative count", count: "-1", malformed: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Setenv("GC_MAX_DISPATCH_SLING_FAILURES", tc.cap)
			meta := armed(map[string]string{"gc.dispatch_when_ready_args": `["--on","mol-polecat-work"]`})
			if tc.count != "<absent>" {
				meta["gc.dispatch_when_ready_fail_count"] = tc.count
			}
			a := armOf(t, meta)
			if a.FailCount != tc.attempts || a.Capped != tc.capped || (a.Malformed != "") != tc.malformed {
				t.Errorf("arm = %+v; want %d attempts, capped %v, malformed %v", a, tc.attempts, tc.capped, tc.malformed)
			}
		})
	}
}

// The arm is the presence of its target. A target that is empty, and an arm
// with no arm time, which every pour's token is made from, are malformed.
func TestTheTargetAndTheArmTime(t *testing.T) {
	if a := armOf(t, map[string]string{"gc.dispatch_when_ready_reason": "left behind"}); a != nil {
		t.Errorf("a bead with no target reads arm %+v", a)
	}
	full := armOf(t, armed(map[string]string{"gc.dispatch_when_ready_args": `["--on","mol-x"]`}))
	want := &record.Arm{Target: "rig/rig.polecat", Formula: "mol-x", Reason: "waits for unit 1", ArmedBy: "a-session", ArmedAt: "2026-11-13T06:19:00Z"}
	if !reflect.DeepEqual(full, want) {
		t.Errorf("arm = %+v, want %+v", full, want)
	}
	if a := armOf(t, armed(map[string]string{"gc.dispatch_when_ready": " "})); a == nil || !strings.Contains(a.Malformed, "no target") {
		t.Errorf("an empty target reads %+v; want it malformed for its target", a)
	}
	noTime := armed(nil)
	delete(noTime, "gc.dispatch_when_ready_armed_at")
	if a := armOf(t, noTime); a == nil || !strings.Contains(a.Malformed, "arm time") {
		t.Errorf("an arm with no arm time reads %+v; want it malformed for its arm time", a)
	}
}

// Each write is one update: the arm with every key and no attempts, the count
// of attempts alone, and the arm's whole removal.
func TestTheWrites(t *testing.T) {
	s := fake.New()
	s.Put(fake.Bead{ID: "b", Status: "open", Metadata: map[string]string{"gc.dispatch_when_ready_fail_count": "2"}})
	l := ledger.New(s)

	w := l.Write("b")
	record.Set(w, record.Arm{Target: "rig/rig.polecat", Formula: "mol-x", Reason: "why", ArmedBy: "me", ArmedAt: "2026-11-13T06:19:00Z"})
	if err := l.Commit(w); err != nil {
		t.Fatal(err)
	}
	row, _ := s.Row("b")
	wantMeta := map[string]string{
		"gc.dispatch_when_ready":          "rig/rig.polecat",
		"gc.dispatch_when_ready_args":     `["--on","mol-x"]`,
		"gc.dispatch_when_ready_armed_by": "me",
		"gc.dispatch_when_ready_armed_at": "2026-11-13T06:19:00Z",
		"gc.dispatch_when_ready_reason":   "why",
	}
	if !reflect.DeepEqual(row.Metadata, wantMeta) {
		t.Errorf("after the arm = %v, want %v", row.Metadata, wantMeta)
	}

	w = l.Write("b")
	record.SetAttempts(w, 1)
	if err := l.Commit(w); err != nil {
		t.Fatal(err)
	}
	if row, _ = s.Row("b"); row.Metadata["gc.dispatch_when_ready_fail_count"] != "1" {
		t.Errorf("the attempts = %q, want 1", row.Metadata["gc.dispatch_when_ready_fail_count"])
	}

	rows, _ := l.Find(ledger.ByID("b"))
	if !record.Present(rows[0]) {
		t.Error("an armed bead reads no arm present")
	}
	w = l.Write("b")
	record.Clear(w)
	if err := l.Commit(w); err != nil {
		t.Fatal(err)
	}
	if row, _ = s.Row("b"); len(row.Metadata) != 0 {
		t.Errorf("after the removal = %v, want no key", row.Metadata)
	}
	if n := len(s.Writes()); n != 3 {
		t.Errorf("%d writes, want one per act", n)
	}
	rows, _ = l.Find(ledger.ByID("b"))
	if record.Present(rows[0]) {
		t.Error("a disarmed bead reads an arm present")
	}

	s.Put(fake.Bead{ID: "left", Status: "open", Metadata: map[string]string{"gc.dispatch_when_ready_fail_count": "1"}})
	rows, _ = l.Find(ledger.ByID("left"))
	if !record.Present(rows[0]) || record.Of(rows[0]) != nil {
		t.Error("a bead an arm left only its count on reads no part present, or reads it as an arm")
	}
	for _, w := range s.Writes() {
		if slices.Contains(w.Args, "--append-notes") {
			t.Errorf("a record write appended a note: %v", w.Args)
		}
	}
}
