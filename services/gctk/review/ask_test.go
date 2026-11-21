package review_test

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
)

// An ask is one rule that the review domain and the refinery both apply. This
// test runs refinery-lib.sh's refinery_ask, from this checkout, through jq over
// the same beads review.IsAsk classifies, so neither side can drift from the
// other, and pins each shape that names a PR's branch. The rework shapes are
// the one a queued fix unit has once Gas City's sling started its workflow,
// and the one it keeps while that workflow's steps are claimed: the work bead
// itself stays unassigned, with gc.routed_to cleared and gc.execution_routed_to
// set.

// askShape is one bead that names the PR's branch, or another, and whether it
// is an ask.
type askShape struct {
	name              string
	status, issueType string
	assignee, branch  string
	metadata          map[string]string
	ask               bool
}

func askShapes() []askShape {
	rework := map[string]string{"task_kind": "rework", "anchor_bead": prBead, "source_review_bead": "tk-review",
		"gc.routed_to": "", "gc.run_target": "", "gc.execution_routed_to": "rig/gc-toolkit.polecat"}
	return []askShape{
		{name: "an ask gctk review ask files", status: "open", issueType: "task", branch: branch,
			metadata: map[string]string{"review_checks": "correctness"}, ask: true},
		{name: "a fix unit whose workflow the sling started", status: "open", issueType: "task", branch: branch,
			metadata: rework},
		{name: "a fix unit whose workflow's steps are claimed", status: "in_progress", issueType: "task", branch: branch,
			metadata: rework},
		{name: "a rework child no one has routed or assigned", status: "open", issueType: "task", branch: branch,
			metadata: map[string]string{"task_kind": "rework", "anchor_bead": prBead}},
		{name: "a task whose workflow the sling started, with no role", status: "open", issueType: "task", branch: branch,
			metadata: map[string]string{"gc.execution_routed_to": "rig/gc-toolkit.polecat"}},
		{name: "a task routed to a pool", status: "open", issueType: "task", branch: branch,
			metadata: map[string]string{"gc.routed_to": "rig/gc-toolkit.polecat"}},
		{name: "a task assigned to a worker", status: "open", issueType: "task", branch: branch,
			assignee: "rig/gc-toolkit.polecat-1"},
		{name: "a bug that names the branch", status: "open", issueType: "bug", branch: branch},
		{name: "an ask's shape on another branch", status: "open", issueType: "task", branch: "polecat/tk-other"},
	}
}

func TestAnAskIsOneRuleTheReviewDomainAndTheRefineryApply(t *testing.T) {
	w := newWorld(t)
	var rows []map[string]any
	shapes := askShapes()
	for i, s := range shapes {
		id := "tk-shape" + string(rune('a'+i))
		md := map[string]string{"branch": s.branch}
		for k, v := range s.metadata {
			md[k] = v
		}
		w.store.Put(bead{ID: id, Status: s.status, IssueType: s.issueType, Assignee: s.assignee, Metadata: md})
		rows = append(rows, map[string]any{"id": id, "status": s.status, "issue_type": s.issueType,
			"assignee": s.assignee, "metadata": md})
	}
	shell := refineryAsk(t, rows, branch)
	for i, s := range shapes {
		id := "tk-shape" + string(rune('a'+i))
		recs, err := w.ledger().Find(ledger.ByID(id))
		if err != nil || len(recs) != 1 {
			t.Fatalf("%s: the row did not read: %v", s.name, err)
		}
		if got := review.IsAsk(recs[0], branch); got != s.ask {
			t.Errorf("%s: review.IsAsk = %t, want %t", s.name, got, s.ask)
		}
		if shell[i] != s.ask {
			t.Errorf("%s: refinery-lib.sh's refinery_ask = %t, want %t", s.name, shell[i], s.ask)
		}
	}
}

// A fix unit on the branch that blocks the PR's bead is no ask the run can
// take, so the round is not put to it and the record closes none of it.
func TestAFixUnitThatBlocksTheBeadIsNoAsk(t *testing.T) {
	w := newWorld(t)
	w.ask("tk-ask", "")
	for _, s := range askShapes()[1:3] {
		md := map[string]string{"branch": branch}
		for k, v := range s.metadata {
			md[k] = v
		}
		id := "tk-fix-" + s.status
		w.store.Put(bead{ID: id, Status: s.status, IssueType: s.issueType, Metadata: md})
		pr, _ := w.store.Row(prBead)
		pr.Edges = append(pr.Edges, gcbd.Edge{ID: id, Type: gcbd.EdgeBlocks})
		w.store.Put(pr)
	}
	asks, err := review.AsksOn(w.ledger(), prBead)
	if err != nil {
		t.Fatal(err)
	}
	if len(asks) != 1 || asks[0].ID != "tk-ask" {
		t.Fatalf("AsksOn = %+v; want only the ask, and neither fix unit", asks)
	}
}

// refineryAsk is refinery-lib.sh's refinery_ask($branch) over rows, as jq
// answers it for each.
func refineryAsk(t *testing.T, rows []map[string]any, branch string) []bool {
	t.Helper()
	lib, err := filepath.Abs("../../../assets/scripts/refinery-lib.sh")
	if err != nil {
		t.Fatal(err)
	}
	text, err := os.ReadFile(lib)
	if err != nil {
		t.Fatalf("refinery-lib.sh is not in this checkout: %v", err)
	}
	const open = "REFINERY_ASK_JQ='"
	_, rest, ok := strings.Cut(string(text), open)
	def, _, closed := strings.Cut(rest, "'")
	if !ok || !closed || !strings.Contains(def, "def refinery_ask($branch)") {
		t.Fatalf("refinery-lib.sh holds no REFINERY_ASK_JQ definition of refinery_ask")
	}
	in, err := json.Marshal(rows)
	if err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("jq", "-c", "--arg", "b", branch, def+" [ .[] | refinery_ask($b) ]")
	cmd.Stdin = strings.NewReader(string(in))
	out, err := cmd.Output()
	if err != nil {
		t.Fatalf("jq over refinery_ask: %v", err)
	}
	var got []bool
	if err := json.Unmarshal(out, &got); err != nil || len(got) != len(rows) {
		t.Fatalf("jq answered %q for %d rows: %v", out, len(rows), err)
	}
	return got
}
