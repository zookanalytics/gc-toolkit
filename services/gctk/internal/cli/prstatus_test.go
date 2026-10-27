package cli

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// gcStub answers `bd show` with $STUB_SHOW, the anchor's incoming tracks edges
// (`bd dep list`) with $STUB_TRACKERS, the beads stamped with the anchor (the
// `bd list` selecting gc.continuation_group) with $STUB_STAMPED, `[]` when either
// is unset, and every other `bd list` with $STUB_LIST, so a derive test drives
// the whole gathering path with no live store — the same `gc bd` seam
// pr-status-label.test.sh exercises through the shell, proven here in-process.
// $STUB_TRACKERS_FAIL and $STUB_STAMPED_FAIL fail one visit read each, and
// $STUB_LOG, when set, records the arguments of every call.
const gcStub = `#!/bin/sh
[ -z "$STUB_LOG" ] || printf '%s\n' "$*" >> "$STUB_LOG"
case "$2" in
  show) printf '%s\n' "$STUB_SHOW" ;;
  dep)
    [ -z "$STUB_TRACKERS_FAIL" ] || { echo "simulated dep list failure" >&2; exit 1; }
    printf '%s\n' "${STUB_TRACKERS:-[]}" ;;
  list)
    case "$*" in
      *gc.continuation_group=*)
        [ -z "$STUB_STAMPED_FAIL" ] || { echo "simulated list failure" >&2; exit 1; }
        printf '%s\n' "${STUB_STAMPED:-[]}" ;;
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

	// An approved PR the merge pass would land reads merging until an open visit
	// covers its anchor; the visit is a hold, so the same PR then reads
	// needs-attention.
	approved := `[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request","pr_posture":"approved@abc@t","pr.machine":"settled@abc@t"}}]`
	stamped := `[{"id":"tk-v","status":"open","metadata":{"task_kind":"visit","gc.continuation_group":"tk-a"}}]`

	t.Run("approved and merging, no open visit => merging", func(t *testing.T) {
		stubGC(t, approved, `[]`)
		if out, code := derive(t, "tk-a"); code != 0 || out != "merging\n" {
			t.Fatalf("derive = (%q, %d), want (%q, 0)", out, code, "merging\n")
		}
	})

	// The machine verdict and its cause are read off the anchor: a blocked
	// verdict at the posture's head holds the PR, and an unrouted blocker holds
	// it whatever is in flight.
	t.Run("approved, blocked by the merge pass at the posture's head => needs-attention", func(t *testing.T) {
		stubGC(t, `[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request","pr_posture":"approved@abc@t","pr.machine":"blocked@abc@t","pr.machine_cause":"check-failed"}}]`, `[]`)
		if out, code := derive(t, "tk-a"); code != 0 || out != "needs-attention\n" {
			t.Fatalf("derive = (%q, %d), want (%q, 0)", out, code, "needs-attention\n")
		}
	})

	t.Run("an unrouted blocker beside live work => needs-attention", func(t *testing.T) {
		stubGC(t, `[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request","pr_posture":"approved@abc@t","pr.machine":"blocked@abc@t","pr.machine_cause":"blocker"}}]`,
			`[{"id":"tk-f","status":"open","metadata":{"task_kind":"finding","anchor_bead":"tk-a"}}]`)
		if out, code := derive(t, "tk-a"); code != 0 || out != "needs-attention\n" {
			t.Fatalf("derive = (%q, %d), want (%q, 0)", out, code, "needs-attention\n")
		}
	})

	t.Run("an open visit stamped with the anchor => needs-attention", func(t *testing.T) {
		stubGC(t, approved, `[]`)
		t.Setenv("STUB_STAMPED", stamped)
		if out, code := derive(t, "tk-a"); code != 0 || out != "needs-attention\n" {
			t.Fatalf("derive = (%q, %d), want (%q, 0)", out, code, "needs-attention\n")
		}
	})

	t.Run("an open visit outranks live work => needs-attention", func(t *testing.T) {
		stubGC(t, approved, `[{"id":"tk-k","metadata":{"task_kind":"rework","anchor_bead":"tk-a"}}]`)
		t.Setenv("STUB_STAMPED", stamped)
		if out, code := derive(t, "tk-a"); code != 0 || out != "needs-attention\n" {
			t.Fatalf("derive = (%q, %d), want (%q, 0)", out, code, "needs-attention\n")
		}
	})

	for _, fail := range []string{"STUB_TRACKERS_FAIL", "STUB_STAMPED_FAIL"} {
		t.Run("unreadable visit read ("+fail+") => exit 2, no guess", func(t *testing.T) {
			stubGC(t, approved, `[]`)
			t.Setenv(fail, "1")
			if out, code := derive(t, "tk-a"); code != 2 || out != "" {
				t.Fatalf("derive with a visit read failing = (%q, %d), want (%q, 2)", out, code, "")
			}
		})
	}

	// The visit read is the finalize gate's, from the anchor's end: the beads whose
	// tracks edge names the anchor (dep-list rows, which carry the far bead and the
	// edge type), and the beads stamped with the anchor, each judged by its own
	// edges in the `gc bd list` spelling, {type, depends_on_id}. A visit covers the
	// bead its tracks edge names, and its stamp only when it has no tracks edge.
	for _, tc := range []struct{ name, trackers, stamped, want string }{
		{"an open visit whose tracks edge names the anchor => needs-attention",
			`[{"id":"tk-v","status":"open","metadata":{"task_kind":"visit"},"dependency_type":"tracks"}]`, ``,
			"needs-attention\n"},
		{"an in_progress visit tracking the anchor => needs-attention",
			`[{"id":"tk-v","status":"in_progress","metadata":{"task_kind":"visit","gc.continuation_group":"tk-other"},"dependency_type":"tracks"}]`, ``,
			"needs-attention\n"},
		{"a closed visit tracking the anchor => merging",
			`[{"id":"tk-v","status":"closed","metadata":{"task_kind":"visit"},"dependency_type":"tracks"}]`, ``,
			"merging\n"},
		{"a non-visit bead tracking the anchor => merging",
			`[{"id":"tk-r","status":"open","metadata":{"task_kind":"reaction"},"dependency_type":"tracks"}]`, ``,
			"merging\n"},
		{"an in_progress visit stamped with the anchor, no tracks edge => needs-attention",
			``, `[{"id":"tk-v","status":"in_progress","metadata":{"task_kind":"visit","gc.continuation_group":"tk-a"}}]`,
			"needs-attention\n"},
		{"an anchor stamp beside a tracks edge to another bead => merging",
			``, `[{"id":"tk-v","status":"open","metadata":{"task_kind":"visit","gc.continuation_group":"tk-a"},"dependencies":[{"issue_id":"tk-v","depends_on_id":"tk-other","type":"tracks"}]}]`,
			"merging\n"},
		{"an edge of another type leaves the stamp to cover => needs-attention",
			``, `[{"id":"tk-v","status":"open","metadata":{"task_kind":"visit","gc.continuation_group":"tk-a"},"dependencies":[{"issue_id":"tk-v","depends_on_id":"tk-other","type":"blocks"}]}]`,
			"needs-attention\n"},
		{"a non-visit bead stamped with the anchor => merging",
			``, `[{"id":"tk-s","status":"open","metadata":{"gc.continuation_group":"tk-a"}}]`,
			"merging\n"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			stubGC(t, approved, `[]`)
			t.Setenv("STUB_TRACKERS", tc.trackers)
			t.Setenv("STUB_STAMPED", tc.stamped)
			if out, code := derive(t, "tk-a"); code != 0 || out != tc.want {
				t.Fatalf("derive = (%q, %d), want (%q, 0)", out, code, tc.want)
			}
		})
	}

	// Both visit reads name the anchor, so the cost follows the anchor rather than
	// the number of open visits in the store, and neither lists every open visit.
	t.Run("the visit reads are scoped to the anchor", func(t *testing.T) {
		stubGC(t, approved, `[]`)
		log := filepath.Join(t.TempDir(), "gc.log")
		t.Setenv("STUB_LOG", log)
		if out, code := derive(t, "tk-a"); code != 0 || out != "merging\n" {
			t.Fatalf("derive = (%q, %d), want (%q, 0)", out, code, "merging\n")
		}
		raw, err := os.ReadFile(log)
		if err != nil {
			t.Fatal(err)
		}
		calls := string(raw)
		for _, want := range []string{
			"bd dep list tk-a --direction=up -t tracks --json\n",
			"bd list --metadata-field gc.continuation_group=tk-a --status open,in_progress --limit 0 --json\n",
		} {
			if !strings.Contains(calls, want) {
				t.Errorf("the derive did not make the read %q; calls:\n%s", want, calls)
			}
		}
		if strings.Contains(calls, "task_kind=visit") {
			t.Errorf("the derive listed the open visits store-wide; calls:\n%s", calls)
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
