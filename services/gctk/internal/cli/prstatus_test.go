package cli

import (
	"bytes"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/feedback"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus/fixture"
)

// gcStub answers a `bd show` of a bead $STUB_SHOW holds with $STUB_SHOW, each
// row carrying the anchor's `blocks` edges, $STUB_BLOCKERS, `[]` when it is
// unset, unless the row names dependencies of its own. It answers every `bd
// list` with $STUB_LIST, so a derive test drives the whole gathering path with
// no live store — the same `gc bd` seam pr-status-label.test.sh exercises
// through the shell, proven here in-process. A `bd show` of any other bead is
// the walk's read, and answers a row per id from $STUB_EDGES, a JSON object of
// each bead's dependency rows, unless $STUB_EDGES_RAW gives its whole answer.
// $STUB_EDGES_FAIL fails the walk's read past the anchor, and $STUB_LOG, when
// set, records the arguments of every call.
const gcStub = `#!/bin/sh
[ -z "$STUB_LOG" ] || printf '%s\n' "$*" >> "$STUB_LOG"
case "$2" in
  show)
    shift 2
    if printf '%s' "$STUB_SHOW" | jq -e --arg id "$1" 'any(.[]; .id == $id)' >/dev/null 2>&1; then
      printf '%s' "$STUB_SHOW" | jq -c --argjson b "${STUB_BLOCKERS:-[]}" 'map(if has("dependencies") then . else . + {dependencies: $b} end)'
      exit 0
    fi
    [ -z "$STUB_EDGES_FAIL" ] || { echo "simulated show failure" >&2; exit 1; }
    [ -z "$STUB_EDGES_RAW" ] || { printf '%s\n' "$STUB_EDGES_RAW"; exit 0; }
    ids=""
    for a in "$@"; do case "$a" in --*) ;; *) ids="$ids $a" ;; esac; done
    edges=$STUB_EDGES
    [ -n "$edges" ] || edges='{}'
    # shellcheck disable=SC2086
    printf '%s' "$edges" | jq -c --args '. as $e | [$ARGS.positional[] | {id: ., dependencies: ($e[.] // [])}]' $ids ;;
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

func derive(t *testing.T, anchor string, extra ...string) (string, int) {
	t.Helper()
	var out, errbuf bytes.Buffer
	code := Run(append([]string{"pr", "status", anchor}, extra...), "", &out, &errbuf)
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
		t.Setenv("STUB_EDGES_RAW", `[]`)
		if out, code := derive(t, "tk-missing"); code != 2 || out != "" {
			t.Fatalf("derive of a missing anchor = (%q, %d), want (%q, 2)", out, code, "")
		}
	})

	// An approved PR the merge pass would land reads merging until an open human
	// gate blocks its anchor; the gate is a hold, so the same PR then reads
	// needs-attention.
	approved := `[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request","pr_posture":"approved@abc@t","pr.machine":"settled@abc@t"}}]`
	gate := `[{"id":"tk-g","status":"open","issue_type":"gate","await_type":"human","await_id":"pr-comments.7.x","title":"answer the review","dependency_type":"blocks"}]`

	t.Run("approved and merging, no open human gate => merging", func(t *testing.T) {
		stubGC(t, approved, `[]`)
		if out, code := derive(t, "tk-a"); code != 0 || out != "merging\n" {
			t.Fatalf("derive = (%q, %d), want (%q, 0)", out, code, "merging\n")
		}
	})

	// The machine verdict and its cause are read off the anchor: a blocked
	// verdict at the posture's head holds the PR, and one whose cause is a live
	// blocker no automated actor holds counts whatever is in flight.
	t.Run("approved, blocked by the merge pass at the posture's head => needs-attention", func(t *testing.T) {
		stubGC(t, `[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request","pr_posture":"approved@abc@t","pr.machine":"blocked@abc@t","pr.machine_cause":"check-failed"}}]`, `[]`)
		if out, code := derive(t, "tk-a"); code != 0 || out != "needs-attention\n" {
			t.Fatalf("derive = (%q, %d), want (%q, 0)", out, code, "needs-attention\n")
		}
	})

	t.Run("the blocker cause beside live work => needs-attention", func(t *testing.T) {
		stubGC(t, `[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request","pr_posture":"approved@abc@t","pr.machine":"blocked@abc@t","pr.machine_cause":"blocker"}}]`,
			`[{"id":"tk-f","status":"open","metadata":{"task_kind":"finding","anchor_bead":"tk-a"}}]`)
		if out, code := derive(t, "tk-a"); code != 0 || out != "needs-attention\n" {
			t.Fatalf("derive = (%q, %d), want (%q, 0)", out, code, "needs-attention\n")
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
		t.Setenv("STUB_BLOCKERS", `[{"id":"tk-x"}]`)
		if out, code := derive(t, "tk-a"); code != 2 || out != "" {
			t.Fatalf("derive with the blocker read failing = (%q, %d), want (%q, 2)", out, code, "")
		}
	})

	// The gate read is the one reader rule, from the anchor's end: the beads its
	// `blocks` edges reach, each a dep-list row carrying the far bead's type,
	// status and await type. Only a human gate in a status other than closed
	// holds; a conversation that tracks the anchor is not among the blockers at
	// all.
	for _, tc := range []struct{ name, blockers, want string }{
		{"an in_progress human gate => needs-attention",
			`[{"id":"tk-g","status":"in_progress","issue_type":"gate","await_type":"human","dependency_type":"blocks"}]`,
			"needs-attention\n"},
		{"a closed human gate => merging",
			`[{"id":"tk-g","status":"closed","issue_type":"gate","await_type":"human","dependency_type":"blocks"}]`,
			"merging\n"},
		{"a gate with no await type => merging",
			`[{"id":"tk-g","status":"open","issue_type":"gate","dependency_type":"blocks"}]`,
			"merging\n"},
		{"a task blocking the anchor => merging",
			`[{"id":"tk-t","status":"open","issue_type":"task","dependency_type":"blocks"}]`,
			"merging\n"},
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
	// the number of gates in the store, and nothing lists visits store-wide. The
	// in-flight read names the anchor too, over bd-lib.sh's live statuses,
	// spelled out here so a change to prstatus.InFlightStatuses shows here.
	t.Run("the gate read is the anchor's own show", func(t *testing.T) {
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
			"bd list --metadata-field anchor_bead=tk-a --status open,in_progress,blocked,deferred,hooked,pinned --limit 0 --json\n",
			"bd show tk-a --json\n",
		} {
			if !strings.Contains(calls, want) {
				t.Errorf("the derive did not make the read %q; calls:\n%s", want, calls)
			}
		}
		for _, stray := range []string{"task_kind=visit", "gc.continuation_group", "-t tracks", "bd dep list"} {
			if strings.Contains(calls, stray) {
				t.Errorf("the derive made a visit read (%q); calls:\n%s", stray, calls)
			}
		}
	})
}

// --json prints the status beside what holds the PR, the values the held: labels
// carry. An open human gate blocking the anchor holds it, and a live decision
// holds it as the merge pass's stuck-blocker verdict does. A route marks no
// blocker as a person's.
func TestPRStatusDeriveHeld(t *testing.T) {
	approved := `[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request","pr_posture":"approved@abc@t","pr.machine":"settled@abc@t"}}]`
	rework := `[{"id":"tk-k","status":"in_progress","metadata":{"task_kind":"rework","anchor_bead":"tk-a"}}]`
	gate := `[{"id":"tk-g","status":"open","issue_type":"gate","await_type":"human","dependency_type":"blocks"}]`
	for _, tc := range []struct {
		name, show, list string
		env              map[string]string
		want             string
	}{
		{"nothing holds an approved PR", approved, `[]`, nil,
			`{"status":"merging","held":[],"reasons":[]}`},
		{"an open human gate on the anchor", approved, `[]`,
			map[string]string{"STUB_BLOCKERS": gate},
			`{"status":"needs-attention","held":["gate"],"reasons":[{"held":"gate","id":"tk-g","title":""}]}`},
		{"an open human gate beside the PR's rework in flight", approved, rework,
			map[string]string{"STUB_BLOCKERS": gate},
			`{"status":"needs-attention","held":["gate"],"reasons":[{"held":"gate","id":"tk-g","title":""}]}`},
		{"a closed human gate releases the PR", approved, `[]`,
			map[string]string{"STUB_BLOCKERS": `[{"id":"tk-g","status":"closed","issue_type":"gate","await_type":"human","dependency_type":"blocks"}]`},
			`{"status":"merging","held":[],"reasons":[]}`},
		{"a live blocker routed to human is no person's", approved, `[]`,
			map[string]string{"STUB_BLOCKERS": `[{"id":"tk-d","status":"open","metadata":{"gc.routed_to":"human"},"dependency_type":"blocks"}]`},
			`{"status":"merging","held":[],"reasons":[]}`},
		{"a live decision blocker", approved, `[]`,
			map[string]string{"STUB_BLOCKERS": `[{"id":"tk-d","status":"open","issue_type":"decision","metadata":{},"dependency_type":"blocks"}]`},
			`{"status":"needs-attention","held":["blocked"],"reasons":[{"held":"blocked","id":"tk-d","title":""}]}`},
		{"a decision with no status reads open", approved, `[]`,
			map[string]string{"STUB_BLOCKERS": `[{"id":"tk-d","issue_type":"decision","metadata":{},"dependency_type":"blocks"}]`},
			`{"status":"needs-attention","held":["blocked"],"reasons":[{"held":"blocked","id":"tk-d","title":""}]}`},
		{"a closed decision no longer holds", approved, `[]`,
			map[string]string{"STUB_BLOCKERS": `[{"id":"tk-d","status":"closed","issue_type":"decision","metadata":{},"dependency_type":"blocks"}]`},
			`{"status":"merging","held":[],"reasons":[]}`},
		{"a blocker a pool will claim is the city's", approved, `[]`,
			map[string]string{"STUB_BLOCKERS": `[{"id":"tk-d","status":"open","metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat"},"dependency_type":"blocks"}]`},
			`{"status":"merging","held":[],"reasons":[]}`},
		{"the merge pass's thread verdict", `[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request","pr_posture":"approved@abc@t","pr.machine":"blocked@abc@t","pr.machine_cause":"review-threads"}}]`, `[]`, nil,
			`{"status":"needs-attention","held":["review"],"reasons":[{"held":"review","id":"","title":"unresolved review threads hold the merge"}]}`},
		{"the merge pass's stuck-blocker verdict", `[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request","pr_posture":"approved@abc@t","pr.machine":"blocked@abc@t","pr.machine_cause":"blocker"}}]`, `[]`, nil,
			`{"status":"needs-attention","held":["blocked"],"reasons":[{"held":"blocked","id":"","title":"a live blocker no automated actor holds"}]}`},
		{"a failed check reads needs-attention and holds nothing", `[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request","pr_posture":"approved@abc@t","pr.machine":"blocked@abc@t","pr.machine_cause":"check-failed"}}]`, `[]`, nil,
			`{"status":"needs-attention","held":[],"reasons":[]}`},
		{"the merge freeze reads needs-attention and holds nothing", `[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request","merge_hold":"true"}}]`, `[]`, nil,
			`{"status":"needs-attention","held":[],"reasons":[]}`},
		{"a human gate on the anchor beside a person's blocker", approved, `[]`,
			map[string]string{"STUB_BLOCKERS": `[{"id":"tk-g","status":"open","issue_type":"gate","await_type":"human","dependency_type":"blocks"},{"id":"tk-d","status":"open","issue_type":"decision","metadata":{},"dependency_type":"blocks"}]`},
			`{"status":"needs-attention","held":["gate","blocked"],"reasons":[{"held":"gate","id":"tk-g","title":""},{"held":"blocked","id":"tk-d","title":""}]}`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			stubGC(t, tc.show, tc.list)
			for k, v := range tc.env {
				t.Setenv(k, v)
			}
			if out, code := derive(t, "tk-a", "--json"); code != 0 || out != tc.want+"\n" {
				t.Fatalf("derive --json = (%q, %d), want (%q, 0)", out, code, tc.want+"\n")
			}
		})
	}

	// Without --json the derive prints the status alone, the line every other
	// caller reads, and a held value reads in it as needs-attention.
	t.Run("a human gate without --json prints needs-attention", func(t *testing.T) {
		stubGC(t, approved, rework)
		t.Setenv("STUB_BLOCKERS", gate)
		if out, code := derive(t, "tk-a"); code != 0 || out != "needs-attention\n" {
			t.Fatalf("derive = (%q, %d), want (%q, 0)", out, code, "needs-attention\n")
		}
	})

	// A read the held values rest on that does not answer derives nothing, so the
	// labels stay as they are rather than flip on a guess: the anchor's edges that
	// do not decode, and an in-flight set that does not read.
	t.Run("unreadable edges => exit 2, no guess", func(t *testing.T) {
		stubGC(t, approved, rework)
		t.Setenv("STUB_BLOCKERS", `[{"dependency_type":"blocks"}]`)
		if out, code := derive(t, "tk-a", "--json"); code != 2 || out != "" {
			t.Fatalf("derive --json with a read failing = (%q, %d), want (%q, 2)", out, code, "")
		}
	})
	t.Run("unreadable in-flight set => exit 2, no guess", func(t *testing.T) {
		stubGC(t, approved, `{"error":"timeout"}`)
		if out, code := derive(t, "tk-a", "--json"); code != 2 || out != "" {
			t.Fatalf("derive --json with a read failing = (%q, %d), want (%q, 2)", out, code, "")
		}
	})
}

// Every scenario the readers are tested against reaches the derive as the `gc
// bd` reads return its beads, and the derive answers what prstatus.Read gathers
// from the same beads through the in-memory store: the status, the held values
// and the reasons. The answer is the definition's own, so a change to it reaches
// this reader with no edit here, and a rule kept in this command would part from
// it. The helm board's TestBoardReadsTheDefinition holds the board to the same
// scenarios the same way.
func TestPRStatusDeriveReadsTheDefinition(t *testing.T) {
	scenarios, err := fixture.Scenarios()
	if err != nil {
		t.Fatal(err)
	}
	for _, sc := range scenarios {
		t.Run(sc.Name, func(t *testing.T) {
			want, err := sc.Answer()
			if err != nil {
				t.Fatal(err)
			}
			anchor, _ := sc.Bead(sc.Anchor)
			show, err := json.Marshal([]any{storeRow(sc, anchor)})
			if err != nil {
				t.Fatal(err)
			}
			// The store's answer to the in-flight read: the beads naming the
			// anchor in anchor_bead at a status the read asks for.
			list := []any{}
			for _, b := range sc.Beads {
				if b.Metadata["anchor_bead"] == sc.Anchor && slices.Contains(prstatus.InFlightStatuses, b.Status) {
					list = append(list, storeRow(sc, b))
				}
			}
			rawList, err := json.Marshal(list)
			if err != nil {
				t.Fatal(err)
			}
			edges := map[string]any{}
			for _, b := range sc.Beads {
				if b.ID != sc.Anchor {
					edges[b.ID] = storeRow(sc, b)["dependencies"]
				}
			}
			rawEdges, err := json.Marshal(edges)
			if err != nil {
				t.Fatal(err)
			}
			stubGC(t, string(show), string(rawList))
			t.Setenv("STUB_EDGES", string(rawEdges))
			out, code := derive(t, sc.Anchor, "--json")
			var got struct {
				Status  prstatus.State    `json:"status"`
				Held    []prstatus.Hold   `json:"held"`
				Reasons []prstatus.Reason `json:"reasons"`
			}
			if code != 0 || json.Unmarshal([]byte(out), &got) != nil {
				t.Fatalf("derive --json = (%q, %d)", out, code)
			}
			if got.Status != want.Status || !slices.Equal(got.Held, want.Held) || !slices.Equal(got.Reasons, want.Reasons) {
				t.Errorf("derive --json = %+v\nthe definition gives status=%q held=%v reasons=%+v", got, want.Status, want.Held, want.Reasons)
			}
		})
	}
}

// storeRow is a scenario bead as `gc bd show --json` prints it: its fields, and
// each edge of its own as the far bead's row with the type of the edge.
func storeRow(sc fixture.Scenario, b fixture.Bead) map[string]any {
	row := map[string]any{"id": b.ID, "title": b.Title, "status": b.Status, "metadata": b.Metadata}
	if b.IssueType != "" {
		row["issue_type"] = b.IssueType
	}
	if b.AwaitType != "" {
		row["await_type"] = b.AwaitType
	}
	deps := []any{}
	for _, edge := range []struct {
		kind string
		ids  []string
	}{{"blocks", b.WaitsOn}, {"tracks", b.Tracks}} {
		for _, id := range edge.ids {
			if far, ok := sc.Bead(id); ok {
				dep := map[string]any{"id": far.ID, "title": far.Title, "status": far.Status, "metadata": far.Metadata, "dependency_type": edge.kind}
				if far.IssueType != "" {
					dep["issue_type"] = far.IssueType
				}
				if far.AwaitType != "" {
					dep["await_type"] = far.AwaitType
				}
				if far.Assignee != "" {
					dep["assignee"] = far.Assignee
				}
				deps = append(deps, dep)
			}
		}
	}
	row["dependencies"] = deps
	return row
}

// The walk behind the held: gate value: a gate on a rework the anchor waits on
// holds the PR, by the one read the label and engage share.
func TestPRStatusDeriveWalksToTheGate(t *testing.T) {
	unapproved := `[{"id":"tk-a","status":"open","metadata":{"merge_result":"pull_request","pr_posture":"review_required@abc@t"}}]`
	inFlight := `[{"id":"tk-rw","status":"open","metadata":{"task_kind":"rework","anchor_bead":"tk-a"}}]`
	rework := `[{"id":"tk-rw","status":"open","issue_type":"task","dependency_type":"blocks"}]`
	const openGate = `{"id":"tk-g","title":"approve the release","status":"open","issue_type":"gate","await_type":"human","dependency_type":"blocks"}`

	for _, tc := range []struct {
		name       string
		edges      string
		wantStatus string
		wantHeld   []string
	}{
		{"an open gate on the rework holds the PR",
			`{"tk-rw":[` + openGate + `]}`, "needs-attention", []string{"gate"}},
		{"resolving the gate clears the hold",
			`{"tk-rw":[{"id":"tk-g","status":"closed","issue_type":"gate","await_type":"human","dependency_type":"blocks"}]}`, "working", []string{}},
		{"a gate two beads away holds the PR",
			`{"tk-rw":[{"id":"tk-t","status":"open","issue_type":"task","dependency_type":"blocks"}],"tk-t":[` + openGate + `]}`, "needs-attention", []string{"gate"}},
		{"a conversation tracking the rework holds nothing",
			`{"tk-rw":[{"id":"tk-c","status":"open","issue_type":"task","assignee":"human","dependency_type":"tracks"}]}`, "working", []string{}},
		{"a gate the rework only tracks holds nothing",
			`{"tk-rw":[{"id":"tk-g","status":"open","issue_type":"gate","await_type":"human","dependency_type":"tracks"}]}`, "working", []string{}},
		{"a gate that awaits no person holds nothing",
			`{"tk-rw":[{"id":"tk-g","status":"open","issue_type":"gate","await_type":"timer","dependency_type":"blocks"}]}`, "working", []string{}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			stubGC(t, unapproved, inFlight)
			t.Setenv("STUB_BLOCKERS", rework)
			t.Setenv("STUB_EDGES", tc.edges)
			out, code := derive(t, "tk-a", "--json")
			var got struct {
				Status string   `json:"status"`
				Held   []string `json:"held"`
			}
			if code != 0 || json.Unmarshal([]byte(out), &got) != nil {
				t.Fatalf("derive --json = (%q, %d)", out, code)
			}
			if got.Status != tc.wantStatus || !slices.Equal(got.Held, tc.wantHeld) {
				t.Errorf("status=%q held=%v, want %q and %v", got.Status, got.Held, tc.wantStatus, tc.wantHeld)
			}
		})
	}

	t.Run("a human gate among the blockers counts once, as a gate", func(t *testing.T) {
		stubGC(t, unapproved, `[]`)
		t.Setenv("STUB_BLOCKERS", `[{"id":"tk-g","status":"open","issue_type":"gate","await_type":"human","dependency_type":"blocks","metadata":{}}]`)
		out, code := derive(t, "tk-a", "--json")
		if want := `{"status":"needs-attention","held":["gate"],"reasons":[{"held":"gate","id":"tk-g","title":""}]}` + "\n"; code != 0 || out != want {
			t.Errorf("derive --json = (%q, %d), want (%q, 0)", out, code, want)
		}
	})

	t.Run("a gate that awaits no person is no person's blocker, routed to human or not", func(t *testing.T) {
		stubGC(t, unapproved, `[]`)
		t.Setenv("STUB_BLOCKERS", `[{"id":"tk-g","status":"open","issue_type":"gate","await_type":"timer","dependency_type":"blocks","metadata":{"gc.routed_to":"human"}}]`)
		out, code := derive(t, "tk-a", "--json")
		if want := `{"status":"needs-review","held":[],"reasons":[]}` + "\n"; code != 0 || out != want {
			t.Errorf("derive --json = (%q, %d), want (%q, 0)", out, code, want)
		}
	})

	t.Run("a walk that does not read leaves the labels alone", func(t *testing.T) {
		stubGC(t, unapproved, inFlight)
		t.Setenv("STUB_BLOCKERS", rework)
		t.Setenv("STUB_EDGES_FAIL", "1")
		if out, code := derive(t, "tk-a", "--json"); code != 2 || out != "" {
			t.Errorf("derive --json = (%q, %d), want (%q, 2)", out, code, "")
		}
	})

	t.Run("one read per level, the anchor's own edges read once", func(t *testing.T) {
		stubGC(t, unapproved, inFlight)
		t.Setenv("STUB_BLOCKERS", `[{"id":"tk-x","status":"open","dependency_type":"blocks"},{"id":"tk-y","status":"open","dependency_type":"blocks"},{"id":"tk-z","status":"closed","dependency_type":"blocks"}]`)
		log := filepath.Join(t.TempDir(), "calls")
		t.Setenv("STUB_LOG", log)
		if _, code := derive(t, "tk-a"); code != 0 {
			t.Fatalf("derive exit %d", code)
		}
		raw, err := os.ReadFile(log)
		if err != nil {
			t.Fatal(err)
		}
		calls := string(raw)
		if !strings.Contains(calls, "bd show tk-x tk-y --json\n") {
			t.Errorf("the open blockers read in one show, the closed one left out: %s", calls)
		}
		if strings.Count(calls, "bd show") != 3 {
			t.Errorf("the anchor's row, its own edges and one read per level past them, each once: %s", calls)
		}
	})
}

func TestPRStatusUsageErrors(t *testing.T) {
	for _, args := range [][]string{
		{"pr", "status"},
		{"pr", "status", ""},
		{"pr", "status", "tk-a", "tk-b"},
		{"pr", "status", "tk-a", "--all"},
	} {
		var out, errbuf bytes.Buffer
		if code := Run(args, "", &out, &errbuf); code != 1 {
			t.Errorf("gctk %q = %d, want 1", args, code)
		}
	}
	var out, errbuf bytes.Buffer
	if code := Run([]string{"pr", "bogus"}, "", &out, &errbuf); code != 2 {
		t.Errorf("a verb pr does not have = %d, want 2", code)
	}
}

// stPR is the PR st-1 owns on Gas Town's pending record.
const stPR = "https://github.com/acme/widgets/pull/7"

// savedRead is the read the one-PR update saves of st-1's PR at the head the
// refinery validated: open, approved, CLEAN, its required check passed and
// nothing waiting on the city. edit changes it before it is saved in parts.
func savedRead(t *testing.T, edit func(*pr.GitHubRead)) string {
	t.Helper()
	r := &pr.GitHubRead{ReadAt: "2026-11-15T09:00:00Z", URL: stPR, Number: 7, Repository: "acme/widgets",
		HeadBranch: "polecat/st-1", Base: "main", Head: validated, State: "OPEN", MergeState: "CLEAN",
		Checks:    []pr.RequiredRun{{Name: "test", Status: "COMPLETED", Conclusion: "SUCCESS"}},
		Approvers: []string{"operator"}, Requesters: []string{}, Awaiting: []string{}}
	if edit != nil {
		edit(r)
	}
	raw, err := json.Marshal(inParts(r))
	if err != nil {
		t.Fatal(err)
	}
	return string(raw)
}

// inParts is r, GitHub's side of a PR at one head, in the four parts the one-PR
// update saves it in, each read at r's instant.
func inParts(r *pr.GitHubRead) *pr.SavedRead {
	return &pr.SavedRead{
		PR: &pr.SavedPR{ReadAt: r.ReadAt, URL: r.URL, Number: r.Number, Repository: r.Repository,
			HeadBranch: r.HeadBranch, Base: r.Base, Head: r.Head, State: r.State, Draft: r.Draft, MergeState: r.MergeState},
		Checks: &pr.SavedChecks{ReadAt: r.ReadAt, Head: r.Head, Runs: r.Checks},
		Conversation: &pr.SavedConversation{ReadAt: r.ReadAt, Since: r.Since, Approvers: r.Approvers,
			Requesters: r.Requesters, Untaken: r.Untaken, Awaiting: r.Awaiting, Unresolved: []string{}},
		Labels: &pr.SavedLabels{ReadAt: r.ReadAt, Names: []string{}},
	}
}

// pendingStore is a store whose st-1 owns PR 7 on Gas Town's pending record, at
// the blocked status the record writes, with its record whole, a review result
// passed at the validated head and the read savedRead saves. md changes its
// metadata, where a nil value leaves the key off, deps are its own edges in a
// show's shape, and others are the store's other rows.
func pendingStore(t *testing.T, md map[string]any, deps []map[string]any, others ...map[string]any) string {
	t.Helper()
	rec := map[string]any{
		"merge_result": "pull_request_pending", "pr_url": stPR, "pr_number": "7", "pr_repo": "acme/widgets",
		"pr_head_sha": validated, "merged_target": "main", "branch": "polecat/st-1",
		"review_results": `[{"head":"` + validated + `","target":"main","passed":true}]`,
		"pr_github_read": savedRead(t, nil),
	}
	for k, v := range md {
		if v == nil {
			delete(rec, k)
			continue
		}
		rec[k] = v
	}
	row := map[string]any{"id": "st-1", "title": "the work", "status": "blocked", "metadata": rec}
	if deps != nil {
		row["dependencies"] = deps
	}
	raw, err := json.Marshal(append([]map[string]any{row}, others...))
	if err != nil {
		t.Fatal(err)
	}
	return string(raw)
}

// pendingDerive runs `gctk pr status st-1` with extra over store, through the
// store stub, with a gh on PATH and a pr-post.sh in the scripts directory that
// each record their call. A PR on the pending record is derived from the store
// alone, so the test fails if either is called.
func pendingDerive(t *testing.T, store string, extra ...string) (string, int) {
	t.Helper()
	bin, scripts := t.TempDir(), t.TempDir()
	calls := filepath.Join(t.TempDir(), "calls")
	record := func(name string) string {
		return "#!/bin/sh\nprintf '" + name + " %s\\n' \"$*\" >> \"$OUTSIDE_CALLS\"\nexit 1\n"
	}
	for path, body := range map[string]string{
		filepath.Join(bin, "gc"):             storeStub,
		filepath.Join(bin, "gh"):             record("gh"),
		filepath.Join(scripts, "pr-post.sh"): record("pr-post.sh"),
	} {
		if err := os.WriteFile(path, []byte(body), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("GCTK_SCRIPTS_DIR", scripts)
	t.Setenv("OUTSIDE_CALLS", calls)
	t.Setenv("STUB_STORE", store)
	var out, errbuf bytes.Buffer
	code := Run(append([]string{"pr", "status", "st-1"}, extra...), "", &out, &errbuf)
	if raw, err := os.ReadFile(calls); err == nil {
		t.Fatalf("gctk pr status called outside the store:\n%s", raw)
	}
	return out.String(), code
}

// An anchor on Gas Town's pending record reads the evaluator's answer over the
// read the one-PR update saved on it, which prstatus renders, and the
// command prints each condition not met, once for each status. It reads
// neither GitHub nor the definition of feedback.
func TestPRStatusOnThePendingRecord(t *testing.T) {
	const other = "2222222222222222222222222222222222222222"
	noApproval := "approval: no approval stands from an account that can push to the repository\n"
	unread := func(head string) string {
		return "github-unread: GitHub's side of the PR is not read at the head the store holds, " + head + ": "
	}
	unapproved := func(r *pr.GitHubRead) { r.Approvers = []string{} }
	type derived struct {
		Status     string            `json:"status"`
		Held       []string          `json:"held"`
		Reasons    []prstatus.Reason `json:"reasons"`
		Ready      *bool             `json:"ready"`
		Head       *string           `json:"head"`
		Target     *string           `json:"target"`
		Conditions []pr.Condition    `json:"conditions"`
	}
	decode := func(t *testing.T, store string) derived {
		t.Helper()
		out, code := pendingDerive(t, store, "--json")
		var got derived
		if code != 0 || json.Unmarshal([]byte(out), &got) != nil {
			t.Fatalf("derive --json = (%q, %d)", out, code)
		}
		return got
	}
	plain := func(t *testing.T, store, want string) {
		t.Helper()
		if out, code := pendingDerive(t, store); code != 0 || out != want {
			t.Fatalf("derive = (%q, %d), want (%q, 0)", out, code, want)
		}
	}

	t.Run("a ready PR reads merging, with no condition, judged at the saved read's head", func(t *testing.T) {
		store := pendingStore(t, nil, nil)
		plain(t, store, "merging\n")
		got := decode(t, store)
		if got.Status != "merging" || got.Ready == nil || !*got.Ready || got.Head == nil || *got.Head != validated ||
			got.Target == nil || *got.Target != "main" || got.Conditions == nil || len(got.Conditions) != 0 {
			t.Fatalf("derive --json = %+v, want ready at %s into main with an empty conditions array", got, validated)
		}
	})

	t.Run("an unapproved PR the review loop has yet to pass reads working, then each condition not met", func(t *testing.T) {
		store := pendingStore(t, map[string]any{"review_results": nil, "pr_github_read": savedRead(t, unapproved)}, nil)
		plain(t, store, "working\n"+noApproval+"review: no review result passed at head "+validated+" into main\n")
	})

	t.Run("a PR waiting on an approval alone reads needs-review", func(t *testing.T) {
		plain(t, pendingStore(t, map[string]any{"pr_github_read": savedRead(t, unapproved)}, nil), "needs-review\n"+noApproval)
	})

	t.Run("a review thread waiting on the city's answer reads needs-attention, held: review", func(t *testing.T) {
		store := pendingStore(t, map[string]any{"pr_github_read": savedRead(t, func(r *pr.GitHubRead) {
			r.Awaiting = []string{"T1"}
		})}, nil)
		plain(t, store, "needs-attention\nthread: review thread T1 waits on the city's answer\n")
		got := decode(t, store)
		if !slices.Equal(got.Held, []string{"review"}) || !reflect.DeepEqual(got.Reasons,
			[]prstatus.Reason{{Held: prstatus.HeldReview, Title: "1 review thread waits on the city's answer"}}) {
			t.Fatalf("derive --json = %+v, want held: review with the thread's reason", got)
		}
	})

	t.Run("a failed required check reads needs-attention", func(t *testing.T) {
		store := pendingStore(t, map[string]any{"pr_github_read": savedRead(t, func(r *pr.GitHubRead) {
			r.Checks = []pr.RequiredRun{{Name: "test", Status: "COMPLETED", Conclusion: "FAILURE"}}
		})}, nil)
		plain(t, store, "needs-attention\ncheck-failed: required check test has a result at the head that did not pass (FAILURE)\n")
	})

	t.Run("a PR with no read saved reads working, GitHub's side unread and no head judged", func(t *testing.T) {
		store := pendingStore(t, map[string]any{"pr_github_read": nil}, nil)
		plain(t, store, "working\n"+unread(validated)+"no read of GitHub is saved on the bead\n")
		got := decode(t, store)
		if got.Status != "working" || got.Ready == nil || *got.Ready || got.Head != nil || got.Target != nil ||
			len(got.Conditions) != 1 || got.Conditions[0].Kind != pr.KindGitHubUnread {
			t.Fatalf("derive --json = %+v, want working on github-unread alone, with no head or target", got)
		}
	})

	t.Run("a head the refinery published after the read reads working until the PR watch reads it", func(t *testing.T) {
		plain(t, pendingStore(t, map[string]any{"pr_head_sha": other}, nil),
			"working\n"+unread(other)+"the read is at head "+validated+"\n")
	})

	t.Run("an unread side beside a human gate reads needs-attention, held: gate", func(t *testing.T) {
		t.Setenv("STUB_BLOCKED", `[{"id":"st-1","blocked_by":["st-g"]}]`)
		t.Setenv("STUB_MARKS", `[{"id":"st-1"}]`)
		store := pendingStore(t, map[string]any{"pr_github_read": nil},
			[]map[string]any{{"id": "st-g", "dependency_type": "blocks", "title": "which way?", "status": "open",
				"issue_type": "gate", "await_type": "human"}},
			map[string]any{"id": "st-g", "title": "which way?", "status": "open", "issue_type": "gate",
				"await_type": "human", "assignee": "human"})
		out, code := pendingDerive(t, store)
		if code != 0 || !strings.HasPrefix(out, "needs-attention\n"+unread(validated)) ||
			!strings.Contains(out, "\nwait: the bead waits on st-g") {
			t.Fatalf("derive = (%q, %d), want needs-attention on github-unread and the wait on st-g", out, code)
		}
		got := decode(t, store)
		if !slices.Equal(got.Held, []string{"gate"}) ||
			!reflect.DeepEqual(got.Reasons, []prstatus.Reason{{Held: prstatus.HeldGate, ID: "st-g", Title: "which way?"}}) {
			t.Fatalf("derive --json = %+v, want held: gate naming st-g", got)
		}
	})

	t.Run("the merge pass's verdict and thread count, left from the old record, hold nothing", func(t *testing.T) {
		store := pendingStore(t, map[string]any{"review_results": nil, "pr_github_read": savedRead(t, unapproved),
			"pr_posture": "approved@abc@t", "pr.machine": "blocked@abc@t", "pr.machine_cause": "blocker",
			"pr.unanswered_threads": "2@abc"}, nil)
		got := decode(t, store)
		if got.Status != "working" || len(got.Held) != 0 || got.Held == nil || len(got.Reasons) != 0 || got.Reasons == nil {
			t.Fatalf("derive --json = %+v, want working with nothing held", got)
		}
	})

	t.Run("a saved read that does not decode derives nothing", func(t *testing.T) {
		store := pendingStore(t, map[string]any{"pr_github_read": "{not json"}, nil)
		if out, code := pendingDerive(t, store); code != 2 || out != "" {
			t.Fatalf("derive = (%q, %d), want (\"\", 2)", out, code)
		}
	})

	t.Run("an anchor off the record reads its recorded facts, and its --json carries no answer", func(t *testing.T) {
		out, code := pendingDerive(t, `[{"id":"st-1","status":"open","metadata":{"merge_result":"pull_request"}}]`, "--json")
		if code != 0 || strings.Contains(out, `"ready"`) || strings.Contains(out, `"conditions"`) {
			t.Fatalf("derive --json = (%q, %d), want the derivation alone", out, code)
		}
	})
}

// declared is the prefix a test rig's default branch declares as a
// third-party marker of posts that are not for review, one no real repository
// declares.
const declared = "[gctk-declared]:"

// declaringRig is a rig's checkout whose default branch declares prefix in its
// not-for-review.toml, or declares nothing when prefix is empty.
func declaringRig(t *testing.T, prefix string) string {
	t.Helper()
	dir := t.TempDir()
	git := func(args ...string) {
		t.Helper()
		cmd := exec.Command("git", append([]string{"-C", dir, "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"}, args...)...)
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
	git("init", "-q")
	if prefix != "" {
		if err := os.WriteFile(filepath.Join(dir, "not-for-review.toml"), []byte("[[marker]]\nprefix = \""+prefix+"\"\n"), 0o644); err != nil {
			t.Fatal(err)
		}
		git("add", "not-for-review.toml")
	}
	git("commit", "-q", "--allow-empty", "-m", "base")
	git("update-ref", "refs/remotes/origin/main", "HEAD")
	return dir
}

// packScripts has feedback.ScriptsDir name this checkout's scripts, whose
// pr-post.sh holds the one definition of feedback, and leaves GC_RIG_ROOT
// unset, which that definition reads only outside a repository.
func packScripts(t *testing.T) {
	t.Helper()
	dir, err := filepath.Abs("../../../../assets/scripts")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(dir, "pr-post.sh")); err != nil {
		t.Fatalf("pr-post.sh is not in %s: %v", dir, err)
	}
	t.Setenv("GCTK_SCRIPTS_DIR", dir)
	t.Setenv("GC_RIG_ROOT", "")
}

// readsDeclared reports whether a loaded definition reads the declaration of
// a rig that declares declared: a post that opens with it is no feedback
// there, and feedback where nothing declares it.
func readsDeclared(t *testing.T, f pr.Feedback) bool {
	t.Helper()
	got, err := f.Untaken("zook-bot", "2026-10-01T00:00:00Z", nil, nil, []feedback.Comment{
		{ID: 1, Author: "integration", Body: declared + " a status the integration posts", CreatedAt: "2026-11-12T01:00:00Z"},
		{ID: 2, Author: "operator", Body: "one more thing", CreatedAt: "2026-11-12T01:00:00Z"},
	})
	if err != nil {
		t.Fatal(err)
	}
	ids := got.Conversation
	switch {
	case slices.Equal(ids, []int64{2}):
		return true
	case slices.Equal(ids, []int64{1, 2}):
		return false
	}
	t.Fatalf("feedback %v, want [2] where the prefix is declared or [1 2] where it is not", ids)
	return false
}
