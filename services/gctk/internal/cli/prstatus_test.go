package cli

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

// gcStub answers `bd show` with $STUB_SHOW and `bd list` with $STUB_LIST, so a
// derive test drives the whole gathering path with no live store — the same
// `gc bd` seam pr-status-label.test.sh exercises through the shell, proven here
// in-process.
const gcStub = `#!/bin/sh
case "$2" in
  show) printf '%s\n' "$STUB_SHOW" ;;
  list) printf '%s\n' "$STUB_LIST" ;;
  *) echo unsupported >&2; exit 2 ;;
esac
`

func stubGC(t *testing.T, show, list string) {
	t.Helper()
	bin := t.TempDir()
	if err := os.WriteFile(filepath.Join(bin, "gc"), []byte(gcStub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STUB_SHOW", show)
	t.Setenv("STUB_LIST", list)
}

func derive(t *testing.T, anchor string) (string, int) {
	t.Helper()
	var out, errbuf bytes.Buffer
	code := PRStatus([]string{"derive", "--anchor", anchor}, &out, &errbuf)
	return out.String(), code
}

func TestPRStatusDerive(t *testing.T) {
	t.Run("open rework child => working", func(t *testing.T) {
		stubGC(t,
			`[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request"}}]`,
			`[{"id":"tk-k","metadata":{"task_kind":"rework","anchor_bead":"tk-a"}}]`)
		if out, code := derive(t, "tk-a"); code != 0 || out != "working\n" {
			t.Fatalf("derive = (%q, %d), want (%q, 0)", out, code, "working\n")
		}
	})

	t.Run("operator freeze => needs-attention", func(t *testing.T) {
		stubGC(t, `[{"id":"tk-a","status":"open","metadata":{"merge_hold":true}}]`, `[]`)
		if out, code := derive(t, "tk-a"); code != 0 || out != "needs-attention\n" {
			t.Fatalf("derive = (%q, %d), want (%q, 0)", out, code, "needs-attention\n")
		}
	})

	t.Run("nothing outstanding => needs-review", func(t *testing.T) {
		stubGC(t, `[{"id":"tk-a","status":"open","metadata":{}}]`, `[]`)
		if out, code := derive(t, "tk-a"); code != 0 || out != "needs-review\n" {
			t.Fatalf("derive = (%q, %d), want (%q, 0)", out, code, "needs-review\n")
		}
	})

	t.Run("unresolvable anchor => exit 2, no guess", func(t *testing.T) {
		stubGC(t, `[]`, `[]`)
		if out, code := derive(t, "tk-missing"); code != 2 || out != "" {
			t.Fatalf("derive of a missing anchor = (%q, %d), want (%q, 2)", out, code, "")
		}
	})
}

func TestPRStatusUsageErrors(t *testing.T) {
	var out, errbuf bytes.Buffer
	if code := PRStatus([]string{"derive"}, &out, &errbuf); code != 1 {
		t.Errorf("derive with no --anchor = %d, want 1", code)
	}
	out.Reset()
	errbuf.Reset()
	if code := PRStatus([]string{"bogus"}, &out, &errbuf); code != 1 {
		t.Errorf("unknown verb = %d, want 1", code)
	}
}
