package gcbd

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// stubWriter puts a gc on PATH that logs its arguments one per line, prints
// STUB_REPLY and exits STUB_EXIT, and returns the log's path.
func stubWriter(t *testing.T) string {
	t.Helper()
	bin := t.TempDir()
	log := filepath.Join(bin, "args")
	stub := "#!/bin/sh\nfor a in \"$@\"; do printf '%s\\n' \"$a\"; done > '" + log + "'\nprintf '%s' \"$STUB_REPLY\"\n[ -z \"$STUB_ERR\" ] || echo \"$STUB_ERR\" >&2\nexit \"${STUB_EXIT:-0}\"\n"
	if err := os.WriteFile(filepath.Join(bin, "gc"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STUB_REPLY", "")
	t.Setenv("STUB_ERR", "")
	t.Setenv("STUB_EXIT", "0")
	return log
}

func ranArgs(t *testing.T, log string) string {
	t.Helper()
	raw, err := os.ReadFile(log)
	if err != nil {
		t.Fatal(err)
	}
	return strings.ReplaceAll(strings.TrimSpace(string(raw)), "\n", " ")
}

// A set-state names its store, the bead, the dimension's value and the reason,
// and a set-state that exits non-zero is a write that did not land, saying
// what bd said.
func TestASetStateIsOneWriteWithItsReason(t *testing.T) {
	log := stubWriter(t)
	if err := New().In("/rig/.beads").SetState("tk-1", "hold", "mayor", "held for placement"); err != nil {
		t.Fatal(err)
	}
	if got, want := ranArgs(t, log), "bd --db /rig/.beads set-state tk-1 hold=mayor --reason held for placement"; got != want {
		t.Fatalf("the set-state ran %q, want %q", got, want)
	}
	t.Setenv("STUB_ERR", "Error: issue tk-1 not found")
	t.Setenv("STUB_EXIT", "1")
	err := New().SetState("tk-1", "hold", "mayor", "")
	if err == nil || !strings.Contains(err.Error(), "not found") || !strings.Contains(err.Error(), "exited 1") {
		t.Fatalf("a refused set-state read as %v", err)
	}
	if got := ranArgs(t, log); got != "bd set-state tk-1 hold=mayor" {
		t.Fatalf("a set-state with no reason ran %q", got)
	}
}

// An edge write names its store, the two beads and the edge's type, and one bd
// refuses is a write that did not land.
func TestAnEdgeWriteIsOneDepAdd(t *testing.T) {
	log := stubWriter(t)
	if err := New().In("/rig/.beads").AddEdge("tk-1", "tk-2", EdgeBlocks); err != nil {
		t.Fatal(err)
	}
	if got, want := ranArgs(t, log), "bd --db /rig/.beads dep add tk-1 tk-2 --type blocks"; got != want {
		t.Fatalf("the edge write ran %q, want %q", got, want)
	}
	t.Setenv("STUB_ERR", `dependency already exists with type "discovered-from"`)
	t.Setenv("STUB_EXIT", "1")
	if err := New().AddEdge("tk-1", "tk-2", EdgeBlocks); err == nil || !strings.Contains(err.Error(), "discovered-from") {
		t.Fatalf("a refused edge read as %v", err)
	}
}

// The ready ids are read from bd's brief ready set, every row of it, and a read
// that fails, or answers with anything but one array of rows with ids, is a
// *ReadError and never an empty set.
func TestReadyIDsReadTheBriefReadySet(t *testing.T) {
	log := stubWriter(t)
	t.Setenv("STUB_REPLY", `[{"id":"tk-1","title":"a"},{"id":"tk-2","title":"b"}]`)
	ids, err := New().In("/rig/.beads").ReadyIDs()
	if err != nil || !slices.Equal(ids, []string{"tk-1", "tk-2"}) {
		t.Fatalf("ReadyIDs = %v, %v", ids, err)
	}
	if got, want := ranArgs(t, log), "bd --db /rig/.beads ready --brief --json --limit 0"; got != want {
		t.Fatalf("the ready read ran %q, want %q", got, want)
	}
	for _, reply := range []string{`{"error":"no store"}`, `[{"title":"no id"}]`, ``, `[][]`} {
		t.Setenv("STUB_REPLY", reply)
		if ids, err := New().ReadyIDs(); err == nil {
			t.Errorf("the reply %q read as %v", reply, ids)
		}
	}
	t.Setenv("STUB_REPLY", `[]`)
	t.Setenv("STUB_EXIT", "1")
	if ids, err := New().ReadyIDs(); err == nil {
		t.Errorf("a read that exited 1 read as %v", ids)
	}
}
