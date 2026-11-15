package gcbd

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
)

// rigListStub puts a `gc` on PATH that answers `rig list` with $STUB_RIGS and
// exit $STUB_RIGS_RC, and logs each call's argv to the file it returns.
func rigListStub(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	log := filepath.Join(dir, "calls")
	stub := `#!/bin/sh
printf '%s\n' "$*" >> "$STUB_LOG"
case "$1 $2" in
"rig list") printf '%s' "$STUB_RIGS"; exit "${STUB_RIGS_RC:-0}" ;;
esac
echo "stub gc: no answer for $*" >&2
exit 2
`
	if err := os.WriteFile(filepath.Join(dir, "gc"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STUB_LOG", log)
	t.Setenv("STUB_RIGS", "")
	t.Setenv("STUB_RIGS_RC", "0")
	return log
}

// A rig's store is the .beads directory under the path `gc rig list` names for
// it, the city's among them. A name the list does not give a rig is none, a
// prefix among them, and a list that fails or does not decode is a *ReadError.
func TestRigStoreNamesTheRigsBeadsDirectory(t *testing.T) {
	log := rigListStub(t)
	t.Setenv("STUB_RIGS", `{"rigs":[{"name":"city","prefix":"lx","path":"/city"},{"name":"gc-toolkit","prefix":"tk","path":"/city/rigs/gc-toolkit"}]}`)
	c := &Client{bin: "gc"}
	if path, ok, err := c.RigStore("gc-toolkit"); err != nil || !ok || path != "/city/rigs/gc-toolkit/.beads" {
		t.Errorf("RigStore(gc-toolkit) = %q, %v, %v", path, ok, err)
	}
	if path, ok, err := c.RigStore("city"); err != nil || !ok || path != "/city/.beads" {
		t.Errorf("RigStore(city) = %q, %v, %v", path, ok, err)
	}
	if path, ok, err := c.RigStore("tk"); err != nil || ok || path != "" {
		t.Errorf("RigStore(tk), a prefix and no rig's name = %q, %v, %v; want none", path, ok, err)
	}
	if got := findCalls(t, log); len(got) != 3 || got[0] != "rig list --json" {
		t.Errorf("calls = %q, want one rig list each", got)
	}
	var re *ReadError
	t.Setenv("STUB_RIGS_RC", "1")
	if _, _, err := c.RigStore("gc-toolkit"); !errors.As(err, &re) {
		t.Errorf("a rig list that failed = %v; want a *ReadError", err)
	}
	t.Setenv("STUB_RIGS_RC", "0")
	t.Setenv("STUB_RIGS", `not json`)
	if _, _, err := c.RigStore("gc-toolkit"); !errors.As(err, &re) {
		t.Errorf("a rig list that did not decode = %v; want a *ReadError", err)
	}
}
