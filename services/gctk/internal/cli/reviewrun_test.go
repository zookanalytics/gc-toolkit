package cli

import (
	"bytes"
	"errors"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	ghfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
)

const (
	runHead = "1111111111111111111111111111111111111111"
	runNext = "2222222222222222222222222222222222222222"
)

// runStore is a store holding a PR's bead on the pending record, a run poured
// from that record, and the run's prepare and first triage steps.
func runStore() *fake.Store {
	s := fake.New()
	s.Put(fake.Bead{ID: "tk-pr", Status: "blocked", IssueType: "task", Metadata: map[string]string{
		"merge_result": "pull_request_pending", "branch": "polecat/tk-pr", "pr_head_sha": runHead,
		"merged_target": "main", "pr_url": "https://github.com/o/r/pull/7",
	}, Edges: []gcbd.Edge{{ID: "tk-run", Type: gcbd.EdgeBlocks}}})
	s.Put(fake.Bead{ID: "tk-run", Status: "open", IssueType: "task", Metadata: map[string]string{
		"gc.kind": "workflow", "gc.var.pr_bead": "tk-pr", "gc.var.head": runHead, "gc.var.target": "main",
		"gc.var.branch": "polecat/tk-pr",
	}})
	s.Put(fake.Bead{ID: "tk-prep", Status: "in_progress", IssueType: "task", Metadata: map[string]string{
		"gc.root_bead_id": "tk-run", "gc.step_ref": "mol-pr-review.prepare",
	}})
	s.Put(fake.Bead{ID: "tk-tri", Status: "in_progress", IssueType: "task", Metadata: map[string]string{
		"gc.root_bead_id": "tk-run", "gc.step_ref": "review-loop.iteration.1.triage", "gc.attempt": "1",
	}})
	return s
}

// withGitHub has a run's prepare read GitHub from g, on every host.
func withGitHub(t *testing.T, g *ghfake.GitHub) {
	t.Helper()
	was := reviewGitHubFor
	reviewGitHubFor = func(string) review.GitHub { return g }
	t.Cleanup(func() { reviewGitHubFor = was })
}

// prepare exits 0 while the run may go on, 3 with the reason when it must stop
// with no result, and 2 when GitHub does not answer, in the lines
// review-run.sh's prepare reads. The domain's tests hold each reason a run
// stops for.
func TestReviewStepPrepare(t *testing.T) {
	g := ghfake.New("")
	p := &ghfake.PR{Facts: gh.PullRequest{Repository: "o/r", Number: 7, State: "OPEN", HeadRefOid: runHead,
		HeadRefName: "polecat/tk-pr", BaseRefName: "main"}}
	g.Put(p)
	withGitHub(t, g)
	run := func() (int, string, string) {
		var out, errb bytes.Buffer
		code := reviewStepIn(ledger.New(runStore()), "tk-prep", true, false, nil, &out, &errb)
		return code, out.String(), errb.String()
	}
	if code, out, errs := run(); code != 0 || !strings.Contains(out, "first head "+runHead) || errs != "" {
		t.Errorf("a run poured from its record at the PR's head = exit %d: %s%s", code, out, errs)
	}
	p.Facts.HeadRefOid = runNext
	want := "gctk review step: run tk-run must stop with no result: the PR's head is " + runNext +
		", no longer the run's head " + runHead + "\n"
	if code, out, errs := run(); code != 3 || errs != want || out != "" {
		t.Errorf("a PR whose head moved = exit %d: %s%s; want 3 and %q", code, out, errs, want)
	}
	g.Fail["PullRequest"] = errors.New("rate limited")
	want = "gctk review step: GitHub did not answer for https://github.com/o/r/pull/7: rate limited\n"
	if code, out, errs := run(); code != 2 || errs != want || out != "" {
		t.Errorf("a GitHub that does not answer = exit %d: %s%s; want 2 and %q", code, out, errs, want)
	}
}

// A step in the loop prints the head its iteration judges and the change, and
// a bead that is no run's step is refused.
func TestReviewStepFacts(t *testing.T) {
	s := runStore()
	var out, errb bytes.Buffer
	if code := reviewStepIn(ledger.New(s), "tk-tri", false, true, nil, &out, &errb); code != 0 ||
		!strings.Contains(out.String(), `"head":"`+runHead+`"`) || !strings.Contains(out.String(), `"why":"`+review.ChangeWhole+`"`) {
		t.Errorf("triage's facts = exit %d: %s%s", code, out.String(), errb.String())
	}
	s.Put(fake.Bead{ID: "tk-x", Status: "open", IssueType: "task"})
	if code := reviewStepIn(ledger.New(s), "tk-x", false, false, nil, &out, &errb); code != 3 {
		t.Errorf("a bead that is no run's step = exit %d; want 3", code)
	}
}

// output prints an output that stands and refuses one that does not.
func TestReviewOutputExits(t *testing.T) {
	s := runStore()
	var out, errb bytes.Buffer
	ok := review.OutputRequest{Step: "tk-tri", Raw: []byte(`{"review":"triage","head":"` + runHead + `","checks":[]}`)}
	if code := reviewOutputIn(ledger.New(s), ok, &out, &errb); code != 0 || !strings.Contains(out.String(), `"iteration":1`) {
		t.Errorf("an output that stands = exit %d: %s%s", code, out.String(), errb.String())
	}
	bad := review.OutputRequest{Step: "tk-tri", Raw: []byte(`{"review":"triage","head":"` + runNext + `"}`)}
	if code := reviewOutputIn(ledger.New(s), bad, &out, &errb); code != 3 {
		t.Errorf("an output at another head = exit %d; want 3", code)
	}
}

// comment refuses an iteration whose round has written no rulings.
func TestReviewCommentExits(t *testing.T) {
	var out, errb bytes.Buffer
	if code := reviewCommentIn(ledger.New(runStore()), "tk-run", 0, &out, &errb); code != 3 {
		t.Errorf("a run with no rulings yet = exit %d; want 3", code)
	}
}
