package humangate_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/humangate"
)

// stub writes a human-gate.sh that records its arguments, one per line, and
// exits with code.
func stub(t *testing.T, code string) (dir, log string) {
	t.Helper()
	dir = t.TempDir()
	log = filepath.Join(dir, "calls")
	script := "#!/bin/sh\nfor a in \"$@\"; do printf '%s\\n' \"$a\"; done >> '" + log + "'\necho refused >&2\nexit " + code + "\n"
	if err := os.WriteFile(filepath.Join(dir, "human-gate.sh"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	return dir, log
}

func TestFileHandsTheGateToTheScript(t *testing.T) {
	dir, log := stub(t, "0")
	if err := humangate.New(dir).File("tk-1", "pull_request_closed_unmerged", "Pull request closed.\nMore."); err != nil {
		t.Fatal(err)
	}
	raw, _ := os.ReadFile(log)
	want := "--subject\ntk-1\n--key\npull_request_closed_unmerged\n--message\nPull request closed.\nMore.\n"
	if string(raw) != want {
		t.Fatalf("the script got %q, want %q", raw, want)
	}
}

func TestAGateTheScriptDoesNotFileIsAnError(t *testing.T) {
	dir, _ := stub(t, "1")
	err := humangate.New(dir).File("tk-1", "k", "m")
	if err == nil || !strings.Contains(err.Error(), "refused") {
		t.Fatalf("a refused gate read as %v", err)
	}
	if err := humangate.New(dir).File("tk-1", "", "m"); err == nil {
		t.Fatal("filed a gate with no key")
	}
}
