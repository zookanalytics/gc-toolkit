package cli

import (
	"bytes"
	"encoding/json"
	"errors"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/deployment"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	gcfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	ghfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh/fake"
)

// pinDeploymentReport makes the command report over city and hub until the
// test ends, for one rig whose checkout's origin is owner/repo-a on
// github.com.
func pinDeploymentReport(t *testing.T, city *gcfake.Runtime, hub *ghfake.GitHub) {
	t.Helper()
	city.RigList = []gascity.Rig{{Name: "rig-a", Path: "/city/rigs/rig-a", Prefix: "ra"}}
	restore := newDeploymentReport
	newDeploymentReport = func() *deployment.Report {
		return &deployment.Report{City: city, GitHub: hub, Host: "github.com",
			Origin: func(string) (string, error) { return "https://github.com/owner/repo-a.git", nil }}
	}
	t.Cleanup(func() { newDeploymentReport = restore })
}

// The report prints its outcome as one JSON object and exits 0 once the
// finding is recorded, with the environment the caller names.
func TestDeploymentReportPrintsItsOutcome(t *testing.T) {
	city, hub := &gcfake.Runtime{}, ghfake.New("bot")
	hub.Repos = map[string]*ghfake.Repo{"owner/repo-a": {Deployments: map[string][]gh.Deployment{"staging": {
		{Created: time.Date(2026, 11, 20, 6, 0, 0, 0, time.UTC), Commit: strings.Repeat("a", 40), State: "FAILURE"},
	}}}}
	city.OnScript = func(gcfake.Call) gascity.Result {
		return gascity.Result{Output: "patrol-finding: filed ra-1 for [deployment.staging]\n"}
	}
	pinDeploymentReport(t, city, hub)
	var out, errb bytes.Buffer
	if code := Run([]string{"deployment", "report", "--rig", "rig-a", "--environment", "staging"}, "test", &out, &errb); code != 0 {
		t.Fatalf("exit %d: %s", code, errb.String())
	}
	var got deployment.Outcome
	if err := json.Unmarshal(out.Bytes(), &got); err != nil || strings.Count(out.String(), "\n") != 1 {
		t.Fatalf("the outcome %q is not one JSON object: %v", out.String(), err)
	}
	if got.Rig != "rig-a" || got.Environment != "staging" || got.State != deployment.Failing || got.Recorded != "filed ra-1 for [deployment.staging]" {
		t.Errorf("the outcome is %+v", got)
	}
	if calls := city.Scripts(); len(calls) != 1 || !slices.Contains(calls[0].Args, "deployment.staging") {
		t.Errorf("the report ran %+v", calls)
	}
}

// A report that did not complete still prints its outcome, says why on
// standard error and exits 1, and a call that names no rig is a usage error.
func TestDeploymentReportFailsAndRefuses(t *testing.T) {
	city, hub := &gcfake.Runtime{}, ghfake.New("bot")
	hub.Fail["Deployments"] = errors.New("gh: HTTP 502")
	pinDeploymentReport(t, city, hub)
	var out, errb bytes.Buffer
	if code := Run([]string{"deployment", "report", "--rig", "rig-a"}, "test", &out, &errb); code != 1 ||
		!strings.Contains(out.String(), `"failure":"GitHub did not answer`) || !strings.Contains(errb.String(), "gh: HTTP 502") {
		t.Errorf("exit %d, stdout %q, stderr %q", code, out.String(), errb.String())
	}
	for _, args := range [][]string{{"deployment", "report"}, {"deployment", "report", "--rig", ""}} {
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
