package gcbd

import (
	"os"
	"strings"
	"testing"
)

// A ready read names the key its beads carry, or every bead, under the serve
// rule's flags, with bd's priority sort when it asks for one, and reads every
// row the store reports ready.
func TestAReadyReadNamesItsKeyOrEveryBead(t *testing.T) {
	log := stubWriter(t)
	t.Setenv("STUB_REPLY", `[{"id":"tk-2","priority":0},{"id":"tk-1","priority":2}]`)
	rows, err := New().In("/rig/.beads").Ready(ReadyQuery{Every: true, Unassigned: true, ExcludeTypes: []string{"epic"}, ByPriority: true})
	if err != nil || len(rows) != 2 || rows[0].ID != "tk-2" {
		t.Fatalf("Ready = %+v, %v", rows, err)
	}
	if got, want := ranArgs(t, log), "bd --db /rig/.beads ready --unassigned --exclude-type=epic --sort priority --json --limit 0"; got != want {
		t.Fatalf("the ready read of every bead ran %q, want %q", got, want)
	}
	if _, err := New().Ready(ReadyQuery{HasKey: "gc.dispatch_when_ready", Unassigned: true, ExcludeLabels: []string{"hold:mayor"}}); err != nil {
		t.Fatal(err)
	}
	if got, want := ranArgs(t, log), "bd ready --has-metadata-key gc.dispatch_when_ready --unassigned --exclude-label hold:mayor --json --limit 0"; got != want {
		t.Fatalf("the ready read of a key ran %q, want %q", got, want)
	}
}

// A ready read that names neither a key nor every bead, or names both, is
// refused before anything runs, and one that fails or answers with anything
// but one array of rows with ids is a *ReadError, never an empty set.
func TestAReadyReadThatSelectsNothingOrFailsReadsNoRows(t *testing.T) {
	log := stubWriter(t)
	for _, q := range []ReadyQuery{{Unassigned: true}, {HasKey: "k", Every: true}} {
		if rows, err := New().Ready(q); err == nil {
			t.Errorf("Ready(%+v) read %v", q, rows)
		}
	}
	if _, err := os.Stat(log); err == nil {
		t.Errorf("a refused ready read ran gc %s", ranArgs(t, log))
	}
	for _, reply := range []string{`{"error":"no store"}`, `[{"title":"no id"}]`, ``, `[][]`} {
		t.Setenv("STUB_REPLY", reply)
		if rows, err := New().Ready(ReadyQuery{Every: true}); err == nil {
			t.Errorf("the reply %q read as %v", reply, rows)
		}
	}
	t.Setenv("STUB_REPLY", `[]`)
	t.Setenv("STUB_EXIT", "1")
	if rows, err := New().Ready(ReadyQuery{Every: true}); err == nil {
		t.Errorf("a read that exited 1 read as %v", rows)
	}
}

// The dependents of a bead are read in one dep list up its edges of one type,
// each row the dependent's own with the edge's type, and a read that fails,
// bd's refusal of an id it cannot resolve among them, is a *ReadError.
func TestDependentsReadWhatHasAnEdgeOntoTheBead(t *testing.T) {
	log := stubWriter(t)
	t.Setenv("STUB_REPLY", `[{"id":"tk-cv","issue_type":"convoy","status":"open","metadata":{"gc.synthetic":"true"},"dependency_type":"tracks"}]`)
	rows, err := New().In("/rig/.beads").Dependents("tk-1", "tracks")
	if err != nil || len(rows) != 1 || rows[0].ID != "tk-cv" || rows[0].DependencyType != "tracks" || rows[0].Meta("gc.synthetic") != "true" {
		t.Fatalf("Dependents = %+v, %v", rows, err)
	}
	if got, want := ranArgs(t, log), "bd --db /rig/.beads dep list tk-1 --direction=up --type tracks --json"; got != want {
		t.Fatalf("the dependents read ran %q, want %q", got, want)
	}
	for _, reply := range []string{`{"error":"resolving tk-1: no issue found"}`, `[{"title":"no id"}]`, ``, `[][]`} {
		t.Setenv("STUB_REPLY", reply)
		if rows, err := New().Dependents("tk-1", "tracks"); err == nil {
			t.Errorf("the reply %q read as %v", reply, rows)
		}
	}
	t.Setenv("STUB_REPLY", `[]`)
	t.Setenv("STUB_EXIT", "1")
	_, err = New().Dependents("tk-1", "tracks")
	if err == nil || !strings.Contains(err.Error(), "exited 1") {
		t.Errorf("a read that exited 1 read as %v", err)
	}
	t.Setenv("STUB_EXIT", "0")
	if rows, err := New().Dependents("tk-1", "tracks"); err != nil || len(rows) != 0 {
		t.Errorf("no dependents read as %v, %v", rows, err)
	}
}
