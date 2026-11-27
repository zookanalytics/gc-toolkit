package cli

import (
	"bytes"
	"errors"
	"strconv"
	"strings"
	"testing"
	"time"

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
// from that record, and the run's first triage step.
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
	s.Put(fake.Bead{ID: "tk-tri", Status: "in_progress", IssueType: "task", Metadata: map[string]string{
		"gc.root_bead_id": "tk-run", "gc.step_ref": "review-loop.iteration.1.triage", "gc.attempt": "1",
	}})
	return s
}

// withGitHub has triage's read ask GitHub from g, on every host.
func withGitHub(t *testing.T, g *ghfake.GitHub) {
	t.Helper()
	was := reviewGitHubFor
	reviewGitHubFor = func(string) review.GitHub { return g }
	t.Cleanup(func() { reviewGitHubFor = was })
}

// --stands exits 0 while the run may go on, 3 with the reason when it must
// stop with no result, and 2 when GitHub does not answer, in the lines
// review-run.sh's triage read reads. The domain's tests hold each reason a run
// stops for.
func TestReviewStepStands(t *testing.T) {
	g := ghfake.New("")
	p := &ghfake.PR{Facts: gh.PullRequest{Repository: "o/r", Number: 7, State: "OPEN", HeadRefOid: runHead,
		HeadRefName: "polecat/tk-pr", BaseRefName: "main"}}
	g.Put(p)
	withGitHub(t, g)
	run := func() (int, string, string) {
		var out, errb bytes.Buffer
		code := reviewStepIn(ledger.New(runStore()), "tk-tri", true, false, nil, &out, &errb)
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

	// At a head that already passed into the run's target, the change is none,
	// from the head to itself, which triage's read prints as nothing to judge.
	pr, _ := s.Row("tk-pr")
	pr.Metadata["review_results"] = `[{"head":"` + runHead + `","target":"main","passed":true}]`
	s.Put(pr)
	out.Reset()
	if code := reviewStepIn(ledger.New(s), "tk-tri", false, false, nil, &out, &errb); code != 0 ||
		!strings.Contains(out.String(), "change: none at "+runHead+": "+review.ChangeNone+"\n") {
		t.Errorf("triage's facts at a passed head = exit %d: %s%s", code, out.String(), errb.String())
	}
	out.Reset()
	if code := reviewStepIn(ledger.New(s), "tk-tri", false, true, nil, &out, &errb); code != 0 ||
		!strings.Contains(out.String(), `"change":{"from":"`+runHead+`","head":"`+runHead+`","why":"`+review.ChangeNone+`"}`) {
		t.Errorf("triage's JSON facts at a passed head = exit %d: %s%s", code, out.String(), errb.String())
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
	// A head ruled material stands once its withdrawal is filed on the PR's
	// bead, which the command reads through the pr domain.
	material := review.OutputRequest{Step: "tk-tri", Raw: []byte(`{"review":"triage","head":"` + runHead + `","material":true}`)}
	errb.Reset()
	if code := reviewOutputIn(ledger.New(s), material, &out, &errb); code != 3 || !strings.Contains(errb.String(), "no withdrawal for it is filed") {
		t.Errorf("a material head with no withdrawal = exit %d: %s; want 3", code, errb.String())
	}
	s.Put(fake.Bead{ID: "tk-wd", Status: "open", IssueType: "task", Metadata: map[string]string{"withdraw_head": runHead}})
	pr, _ := s.Row("tk-pr")
	pr.Edges = append(pr.Edges, gcbd.Edge{ID: "tk-wd", Type: gcbd.EdgeBlocks})
	s.Put(pr)
	if code := reviewOutputIn(ledger.New(s), material, &out, &errb); code != 0 {
		t.Errorf("a material head with its withdrawal filed = exit %d: %s", code, errb.String())
	}
}

// comment refuses an iteration whose round has written no rulings.
func TestReviewCommentExits(t *testing.T) {
	var out, errb bytes.Buffer
	if code := reviewCommentIn(ledger.New(runStore()), "tk-run", 0, &out, &errb); code != 3 {
		t.Errorf("a run with no rulings yet = exit %d; want 3", code)
	}
}

// lookStore is runStore with a round for each count in counts, each ruling that
// many correctness findings must-fix, the last calling for a fresh look, and
// that look's open step, tk-look.
func lookStore(counts ...int) *fake.Store {
	s := runStore()
	run, _ := s.Row("tk-run")
	run.Metadata["gc.var.max_attempts"] = "30"
	run.CreatedAt = "2026-11-27T10:00:00Z"
	s.Put(run)
	for i, c := range counts {
		it := strconv.Itoa(i + 1)
		look := `[]`
		if i == len(counts)-1 {
			look = `[{"head":"` + runHead + `"}]`
		}
		var findings, rulings []string
		for k := 1; k <= c; k++ {
			id := "F" + strconv.Itoa(k)
			findings = append(findings, `{"id":"`+id+`","locus":"a.go","message":"m","severity":"P1","category":"c",`+
				`"failure_scenario":"s","verification":"CONFIRMED: x"}`)
			rulings = append(rulings, `{"check":"correctness","finding":"`+id+`","ruling":"must-fix","reason":"r","commit":"`+
				runNext+`"}`)
		}
		for k, out := range []string{
			`{"review":"triage","iteration":` + it + `,"head":"` + runHead + `","checks":[{"check":"correctness","head":"` + runHead + `"}],"material":false}`,
			`{"review":"lane","iteration":` + it + `,"check":"correctness","head":"` + runHead + `","verdict":"request-changes","findings":[` +
				strings.Join(findings, ",") + `]}`,
			`{"review":"repair","iteration":` + it + `,"head":"` + runHead + `","rulings":[` + strings.Join(rulings, ",") +
				`],"pushed":"` + runNext + `","look":` + look + `}`,
		} {
			s.Put(fake.Bead{ID: "tk-out" + it + string(rune('a'+k)), Status: "closed", IssueType: "task",
				Metadata: map[string]string{"gc.root_bead_id": "tk-run", "gc.output_json": out}})
		}
	}
	s.Put(fake.Bead{ID: "tk-look", Status: "in_progress", IssueType: "task", Metadata: map[string]string{
		"gc.root_bead_id": "tk-run", "gc.attempt": strconv.Itoa(len(counts)),
		"gc.step_ref": "mol-pr-review-look.mol-pr-review.review-loop.iteration." + strconv.Itoa(len(counts)) +
			".rule-and-repair.item.1.look",
	}})
	return s
}

// failingGates is a gate filer whose every gate fails to land.
type failingGates struct{}

func (failingGates) File(string, string, string) error {
	return errors.New("human-gate.sh: the store did not answer")
}

// look reads what a fresh look judges from, and refuses a step that is no
// look. Its record says what it did, exits 3 on an output that does not stand
// and 1 on a question that did not land. The domain's tests hold what a look
// reads and what its record writes.
func TestReviewLookExits(t *testing.T) {
	var out, errb bytes.Buffer
	if code := reviewLookRead(ledger.New(lookStore(1, 1, 1)), "tk-look", nil, "", &out, &errb); code != 0 {
		t.Fatalf("the look's read = exit %d: %s", code, errb.String())
	}
	for _, want := range []string{"account: Round 3: 1 must-fix finding (1, 1, 1 by round), level. The review is not converging",
		"rule: it forces a question", "== Each round of this run", "== Earlier runs on tk-pr", "== The review's rules that changed"} {
		if !strings.Contains(out.String(), want) {
			t.Errorf("the look's read lacks %q:\n%s", want, out.String())
		}
	}
	if code := reviewLookRead(ledger.New(lookStore(1, 1, 1)), "tk-tri", nil, "", &out, &errb); code != 3 {
		t.Errorf("a read of triage's step = exit %d; want 3", code)
	}
	cont := []byte(`{"review":"look","head":"` + runHead + `","verdict":"continue","reading":"r"}`)
	out.Reset()
	req := review.OutputRequest{Step: "tk-look", Raw: cont}
	if code := reviewLookRecord(ledger.New(lookStore(2, 1, 1)), req, "", failingGates{}, time.Now(), &out, &errb); code != 0 ||
		!strings.Contains(out.String(), "sends the review on") {
		t.Errorf("a continue's record = exit %d: %s%s", code, out.String(), errb.String())
	}
	stop := []byte(`{"review":"look","head":"` + runHead + `","verdict":"stop","reading":"r","recommendation":"x","question":"q?"}`)
	if code := reviewLookRecord(ledger.New(lookStore(1, 1, 1)), review.OutputRequest{Step: "tk-look", Raw: stop}, "",
		failingGates{}, time.Now(), &out, &errb); code != 1 {
		t.Errorf("a stop whose question did not land = exit %d; want 1", code)
	}
	if code := reviewLookRecord(ledger.New(lookStore(1, 1, 1)), review.OutputRequest{Step: "tk-look", Raw: cont}, "",
		failingGates{}, time.Now(), &out, &errb); code != 3 {
		t.Errorf("a continue at a forced round with no rule = exit %d; want 3", code)
	}
	errb.Reset()
	byRule := []byte(`{"review":"look","head":"` + runHead + `","verdict":"continue","reading":"r","rules":["` + runNext + `"]}`)
	if code := reviewLookRecord(ledger.New(lookStore(1, 1, 1)), review.OutputRequest{Step: "tk-look", Raw: byRule}, "",
		failingGates{}, time.Now(), &out, &errb); code != 3 || !strings.Contains(errb.String(), "none of the review's rules") {
		t.Errorf("a continue naming a rule the read did not print = exit %d: %s; want 3", code, errb.String())
	}
}
