package source

import (
	"context"
	"os"
	"path/filepath"
	"testing"
)

// TestGCExecSessionListRunsLocal holds the liveness read to gc's local path: the
// session list runs with GC_NO_API=1 in its own environment, and the city
// discovery read beside it runs without. The stub answers each subcommand with
// the GC_NO_API it was handed, as a session's state and as the city path, so
// the whole subprocess path is exercised with and without a city root.
func TestGCExecSessionListRunsLocal(t *testing.T) {
	t.Setenv("GC_NO_API", "")
	dir := t.TempDir()
	stub := filepath.Join(dir, "gc")
	script := `#!/bin/sh
case "$1 $2" in
"session list") printf '{"sessions":[{"id":"s-1","state":"%s"}]}\n' "${GC_NO_API:-unset}" ;;
"config show") printf '{"city_path":"%s"}\n' "${GC_NO_API:-unset}" ;;
*) echo "unexpected gc $*" >&2; exit 2 ;;
esac
`
	if err := os.WriteFile(stub, []byte(script), 0o755); err != nil {
		t.Fatalf("write gc stub: %v", err)
	}
	t.Setenv("GC_HELM_GC_BIN", stub)

	for _, tc := range []struct {
		name     string
		cityPath string
	}{
		{"with a city root", dir},
		{"with no city root", ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			g := newGCExec(tc.cityPath)
			sessions, err := g.Sessions(context.Background())
			if err != nil {
				t.Fatalf("Sessions: %v", err)
			}
			if got := sessions["s-1"]; got != "1" {
				t.Errorf("gc session list ran with GC_NO_API=%q, want 1", got)
			}
			got, err := g.CityPath(context.Background())
			if err != nil {
				t.Fatalf("CityPath: %v", err)
			}
			if got != "unset" {
				t.Errorf("gc config show ran with GC_NO_API=%q, want it unset", got)
			}
		})
	}
}
