package cli

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

// gcStub answers `bd show` with $STUB_SHOW, the open-visit read (the `bd list`
// selecting task_kind=visit) with $STUB_VISITS, `[]` when unset, and every other
// `bd list` with $STUB_LIST, so a derive test drives the whole gathering path
// with no live store — the same `gc bd` seam pr-status-label.test.sh exercises
// through the shell, proven here in-process. $STUB_VISITS_FAIL fails the visit
// read alone.
const gcStub = `#!/bin/sh
case "$2" in
  show) printf '%s\n' "$STUB_SHOW" ;;
  list)
    case "$*" in
      *task_kind=visit*)
        [ -z "$STUB_VISITS_FAIL" ] || { echo "simulated list failure" >&2; exit 1; }
        printf '%s\n' "${STUB_VISITS:-[]}" ;;
      *) printf '%s\n' "$STUB_LIST" ;;
    esac ;;
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

	// An approved PR the merge pass would land reads working until an open visit
	// covers its anchor; the visit is a hold, so the same PR then reads
	// needs-attention.
	approved := `[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request","pr_posture":"approved@abc@t","pr_merge_state":"CLEAN@abc"}}]`
	visit := `[{"id":"tk-v","status":"open","metadata":{"task_kind":"visit","gc.continuation_group":"tk-a"}}]`

	t.Run("approved and merging, no open visit => working", func(t *testing.T) {
		stubGC(t, approved, `[]`)
		if out, code := derive(t, "tk-a"); code != 0 || out != "working\n" {
			t.Fatalf("derive = (%q, %d), want (%q, 0)", out, code, "working\n")
		}
	})

	t.Run("an open visit on the anchor => needs-attention", func(t *testing.T) {
		stubGC(t, approved, `[]`)
		t.Setenv("STUB_VISITS", visit)
		if out, code := derive(t, "tk-a"); code != 0 || out != "needs-attention\n" {
			t.Fatalf("derive = (%q, %d), want (%q, 0)", out, code, "needs-attention\n")
		}
	})

	t.Run("an open visit outranks live work => needs-attention", func(t *testing.T) {
		stubGC(t, approved, `[{"id":"tk-k","metadata":{"task_kind":"rework","anchor_bead":"tk-a"}}]`)
		t.Setenv("STUB_VISITS", visit)
		if out, code := derive(t, "tk-a"); code != 0 || out != "needs-attention\n" {
			t.Fatalf("derive = (%q, %d), want (%q, 0)", out, code, "needs-attention\n")
		}
	})

	t.Run("unreadable visit read => exit 2, no guess", func(t *testing.T) {
		stubGC(t, approved, `[]`)
		t.Setenv("STUB_VISITS_FAIL", "1")
		if out, code := derive(t, "tk-a"); code != 2 || out != "" {
			t.Fatalf("derive with the visit read failing = (%q, %d), want (%q, 2)", out, code, "")
		}
	})

	// The visit read answers every open visit in the store, and the shared visit
	// identity picks the ones covering the anchor: the tracks edge, or the
	// gc.continuation_group stamp only for a visit with no tracks edge. Edges ride
	// each row in the `gc bd list` spelling, {type, depends_on_id}.
	for _, tc := range []struct{ name, visits, want string }{
		{"a visit that tracks the anchor with no stamp => needs-attention",
			`[{"id":"tk-v","status":"open","metadata":{"task_kind":"visit"},"dependencies":[{"issue_id":"tk-v","depends_on_id":"tk-a","type":"tracks"}]}]`,
			"needs-attention\n"},
		{"a visit that tracks the anchor under another bead's stamp => needs-attention",
			`[{"id":"tk-v","status":"open","metadata":{"task_kind":"visit","gc.continuation_group":"tk-other"},"dependencies":[{"issue_id":"tk-v","depends_on_id":"tk-a","type":"tracks"}]}]`,
			"needs-attention\n"},
		{"visits on other beads, by stamp or by edge => working",
			`[{"id":"tk-v1","status":"open","metadata":{"task_kind":"visit","gc.continuation_group":"tk-other"}},
			  {"id":"tk-v2","status":"in_progress","metadata":{"task_kind":"visit"},"dependencies":[{"issue_id":"tk-v2","depends_on_id":"tk-other","type":"tracks"}]}]`,
			"working\n"},
		{"an anchor stamp beside a tracks edge to another bead => working",
			`[{"id":"tk-v","status":"open","metadata":{"task_kind":"visit","gc.continuation_group":"tk-a"},"dependencies":[{"issue_id":"tk-v","depends_on_id":"tk-other","type":"tracks"}]}]`,
			"working\n"},
		{"an edge of another type to the anchor => working",
			`[{"id":"tk-v","status":"open","metadata":{"task_kind":"visit"},"dependencies":[{"issue_id":"tk-v","depends_on_id":"tk-a","type":"blocks"}]}]`,
			"working\n"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			stubGC(t, approved, `[]`)
			t.Setenv("STUB_VISITS", tc.visits)
			if out, code := derive(t, "tk-a"); code != 0 || out != tc.want {
				t.Fatalf("derive = (%q, %d), want (%q, 0)", out, code, tc.want)
			}
		})
	}
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
