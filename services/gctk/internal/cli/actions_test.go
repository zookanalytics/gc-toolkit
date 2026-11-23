package cli

import (
	"bytes"
	"encoding/json"
	"errors"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/actions"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	gcfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	ghfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh/fake"
)

// markedCheckout is a rig's checkout whose origin is owner/repo-a on
// github.com and whose default branch, main, marks nightly.yml.
type markedCheckout struct{}

func (markedCheckout) OriginURL(string) (string, error) {
	return "https://github.com/owner/repo-a.git", nil
}
func (markedCheckout) DefaultBranch(string) (string, error) { return "main", nil }
func (markedCheckout) Grep(string, string, string, ...string) ([]string, error) {
	return []string{".github/workflows/nightly.yml"}, nil
}

// pinActionsReport makes the command report over city and hub until the test
// ends, for one rig whose checkout is markedCheckout.
func pinActionsReport(t *testing.T, city *gcfake.Runtime, hub *ghfake.GitHub) {
	t.Helper()
	city.RigList = []gascity.Rig{{Name: "rig-a", Path: "/city/rigs/rig-a", Prefix: "ra"}}
	restore := newActionsReport
	newActionsReport = func() *actions.Report {
		return &actions.Report{City: city, GitHub: hub, Checkout: markedCheckout{}, Host: "github.com", Now: time.Now}
	}
	t.Cleanup(func() { newActionsReport = restore })
}

// The report prints its outcome as one JSON object and exits 0 once each
// finding is recorded.
func TestActionsReportPrintsItsOutcome(t *testing.T) {
	city, hub := &gcfake.Runtime{}, ghfake.New("bot")
	hub.Repos = map[string]*ghfake.Repo{"owner/repo-a": {Runs: map[string][]gh.WorkflowRun{"nightly.yml": {
		{ID: 7, Number: 3, Attempt: 1, Event: "schedule", Branch: "main", HeadRepo: "owner/repo-a", Commit: strings.Repeat("a", 40),
			Conclusion: "failure", Started: time.Date(2026, 11, 20, 6, 0, 0, 0, time.UTC)},
	}}}}
	city.OnScript = func(gcfake.Call) gascity.Result {
		return gascity.Result{Output: "patrol-finding: filed ra-1 for [actions.nightly.yml]\n"}
	}
	pinActionsReport(t, city, hub)
	var out, errb bytes.Buffer
	if code := Run([]string{"actions", "report", "--rig", "rig-a"}, "test", &out, &errb); code != 0 {
		t.Fatalf("exit %d: %s", code, errb.String())
	}
	var got actions.Outcome
	if err := json.Unmarshal(out.Bytes(), &got); err != nil || strings.Count(out.String(), "\n") != 1 {
		t.Fatalf("the outcome %q is not one JSON object: %v", out.String(), err)
	}
	if got.Rig != "rig-a" || got.Branch != "main" || len(got.Workflows) != 1 || got.Workflows[0].State != actions.Failing ||
		got.Workflows[0].Recorded != "filed ra-1 for [actions.nightly.yml]" {
		t.Errorf("the outcome is %+v", got)
	}
	if calls := city.Scripts(); len(calls) != 1 || !slices.Contains(calls[0].Args, "actions.nightly.yml") {
		t.Errorf("the report ran %+v", calls)
	}
}

// A report that did not complete still prints its outcome, says why on
// standard error and exits 1, and a call that names no rig is a usage error.
func TestActionsReportFailsAndRefuses(t *testing.T) {
	city, hub := &gcfake.Runtime{}, ghfake.New("bot")
	hub.Repos = map[string]*ghfake.Repo{"owner/repo-a": {}}
	hub.Fail["WorkflowRuns"] = errors.New("gh: HTTP 502")
	pinActionsReport(t, city, hub)
	var out, errb bytes.Buffer
	if code := Run([]string{"actions", "report", "--rig", "rig-a"}, "test", &out, &errb); code != 1 ||
		!strings.Contains(out.String(), `"failure":"nightly.yml: GitHub did not answer`) || !strings.Contains(errb.String(), "gh: HTTP 502") {
		t.Errorf("exit %d, stdout %q, stderr %q", code, out.String(), errb.String())
	}
	for _, args := range [][]string{{"actions", "report"}, {"actions", "report", "--rig", ""}} {
		out.Reset()
		errb.Reset()
		if code := Run(args, "test", &out, &errb); code != 2 || out.Len() != 0 {
			t.Errorf("%q: exit %d, stdout %q, stderr %q", args, code, out.String(), errb.String())
		}
	}
	if len(city.Scripts()) != 0 {
		t.Errorf("a report that did not read called %+v", city.Scripts())
	}
}
