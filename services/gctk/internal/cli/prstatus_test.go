package cli

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// gcStub answers `bd show` with $STUB_SHOW, the anchor's `blocks` blockers
// (`bd dep list`) with $STUB_BLOCKERS, `[]` when it is unset, and every `bd list`
// with $STUB_LIST, so a derive test drives the whole gathering path with no live
// store — the same `gc bd` seam pr-status-label.test.sh exercises through the
// shell, proven here in-process. $STUB_BLOCKERS_FAIL fails the blocker read,
// and $STUB_LOG, when set, records the arguments of every call.
const gcStub = `#!/bin/sh
[ -z "$STUB_LOG" ] || printf '%s\n' "$*" >> "$STUB_LOG"
case "$2" in
  show) printf '%s\n' "$STUB_SHOW" ;;
  dep)
    [ -z "$STUB_BLOCKERS_FAIL" ] || { echo "simulated dep list failure" >&2; exit 1; }
    printf '%s\n' "${STUB_BLOCKERS:-[]}" ;;
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
	t.Run("a rework child in the in-flight set => working", func(t *testing.T) {
		stubGC(t,
			`[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request"}}]`,
			`[{"id":"tk-k","metadata":{"task_kind":"rework","anchor_bead":"tk-a"}}]`)
		if out, code := derive(t, "tk-a"); code != 0 || out != "working\n" {
			t.Fatalf("derive = (%q, %d), want (%q, 0)", out, code, "working\n")
		}
	})

	t.Run("a non-rework bead in the in-flight set => working", func(t *testing.T) {
		stubGC(t,
			`[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request"}}]`,
			`[{"id":"tk-v","metadata":{"task_kind":"validation","anchor_bead":"tk-a"}}]`)
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

	t.Run("a draft the city opened, not yet readied => working", func(t *testing.T) {
		stubGC(t, `[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request","opened_as_draft":"abc123"}}]`, `[]`)
		if out, code := derive(t, "tk-a"); code != 0 || out != "working\n" {
			t.Fatalf("derive = (%q, %d), want (%q, 0)", out, code, "working\n")
		}
	})

	t.Run("a draft the city readied => needs-review", func(t *testing.T) {
		stubGC(t, `[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request","opened_as_draft":"abc123","draft_readied":"abc123"}}]`, `[]`)
		if out, code := derive(t, "tk-a"); code != 0 || out != "needs-review\n" {
			t.Fatalf("derive = (%q, %d), want (%q, 0)", out, code, "needs-review\n")
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

	// An approved PR the merge pass would land reads working until an open human
	// gate blocks its anchor; the gate is a hold, so the same PR then reads
	// needs-attention.
	approved := `[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request","pr_posture":"approved@abc@t","pr_merge_state":"CLEAN@abc"}}]`
	gate := `[{"id":"tk-g","status":"open","issue_type":"gate","await_type":"human","await_id":"pr-comments.7.x","title":"answer the review","dependency_type":"blocks"}]`

	t.Run("approved and merging, no open human gate => working", func(t *testing.T) {
		stubGC(t, approved, `[]`)
		if out, code := derive(t, "tk-a"); code != 0 || out != "working\n" {
			t.Fatalf("derive = (%q, %d), want (%q, 0)", out, code, "working\n")
		}
	})

	t.Run("an open human gate blocking the anchor => needs-attention", func(t *testing.T) {
		stubGC(t, approved, `[]`)
		t.Setenv("STUB_BLOCKERS", gate)
		if out, code := derive(t, "tk-a"); code != 0 || out != "needs-attention\n" {
			t.Fatalf("derive = (%q, %d), want (%q, 0)", out, code, "needs-attention\n")
		}
	})

	t.Run("an open human gate outranks live work => needs-attention", func(t *testing.T) {
		stubGC(t, approved, `[{"id":"tk-k","metadata":{"task_kind":"rework","anchor_bead":"tk-a"}}]`)
		t.Setenv("STUB_BLOCKERS", gate)
		if out, code := derive(t, "tk-a"); code != 0 || out != "needs-attention\n" {
			t.Fatalf("derive = (%q, %d), want (%q, 0)", out, code, "needs-attention\n")
		}
	})

	t.Run("unreadable blocker read => exit 2, no guess", func(t *testing.T) {
		stubGC(t, approved, `[]`)
		t.Setenv("STUB_BLOCKERS_FAIL", "1")
		if out, code := derive(t, "tk-a"); code != 2 || out != "" {
			t.Fatalf("derive with the blocker read failing = (%q, %d), want (%q, 2)", out, code, "")
		}
	})

	// The gate read is the one reader rule, from the anchor's end: the beads its
	// `blocks` edges reach, each a dep-list row carrying the far bead's type,
	// status and await type. Only a human gate in a status other than closed
	// holds; a visit or conversation that tracks the anchor is not among the
	// blockers at all.
	for _, tc := range []struct{ name, blockers, want string }{
		{"an in_progress human gate => needs-attention",
			`[{"id":"tk-g","status":"in_progress","issue_type":"gate","await_type":"human","dependency_type":"blocks"}]`,
			"needs-attention\n"},
		{"a closed human gate => working",
			`[{"id":"tk-g","status":"closed","issue_type":"gate","await_type":"human","dependency_type":"blocks"}]`,
			"working\n"},
		{"a gate with no await type => working",
			`[{"id":"tk-g","status":"open","issue_type":"gate","dependency_type":"blocks"}]`,
			"working\n"},
		{"a task blocking the anchor => working",
			`[{"id":"tk-t","status":"open","issue_type":"task","dependency_type":"blocks"}]`,
			"working\n"},
		{"one human gate among other blockers => needs-attention",
			`[{"id":"tk-t","status":"open","issue_type":"task","dependency_type":"blocks"},{"id":"tk-g","status":"open","issue_type":"gate","await_type":"human","dependency_type":"blocks"}]`,
			"needs-attention\n"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			stubGC(t, approved, `[]`)
			t.Setenv("STUB_BLOCKERS", tc.blockers)
			if out, code := derive(t, "tk-a"); code != 0 || out != tc.want {
				t.Fatalf("derive = (%q, %d), want (%q, 0)", out, code, tc.want)
			}
		})
	}

	// The gate read names the anchor, so the cost follows the anchor rather than
	// the number of gates in the store, and nothing lists visits store-wide.
	t.Run("the gate read is the anchor's blocker read", func(t *testing.T) {
		stubGC(t, approved, `[]`)
		log := filepath.Join(t.TempDir(), "gc.log")
		t.Setenv("STUB_LOG", log)
		if out, code := derive(t, "tk-a"); code != 0 || out != "working\n" {
			t.Fatalf("derive = (%q, %d), want (%q, 0)", out, code, "working\n")
		}
		raw, err := os.ReadFile(log)
		if err != nil {
			t.Fatal(err)
		}
		calls := string(raw)
		if want := "bd dep list tk-a --type blocks --json\n"; !strings.Contains(calls, want) {
			t.Errorf("the derive did not make the read %q; calls:\n%s", want, calls)
		}
		for _, stray := range []string{"task_kind=visit", "gc.continuation_group", "-t tracks"} {
			if strings.Contains(calls, stray) {
				t.Errorf("the derive made a visit read (%q); calls:\n%s", stray, calls)
			}
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
