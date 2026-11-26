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
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	ghfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// pinActionsTrack makes the command pass over city, hub and an empty store
// until the test ends, for one rig whose checkout's origin is owner/repo-a on
// github.com and whose default branch is main.
func pinActionsTrack(t *testing.T, city *gcfake.Runtime, hub *ghfake.GitHub) {
	t.Helper()
	city.RigList = []gascity.Rig{{Name: "rig-a", Path: "/city/rigs/rig-a", Prefix: "ra"}}
	restore := newActionsTrack
	newActionsTrack = func() *actions.Pass {
		return &actions.Pass{City: city, GitHub: hub, Host: "github.com",
			Store:         func(string) (*ledger.Ledger, error) { return ledger.New(fake.New()), nil },
			Origin:        func(string) (string, error) { return "https://github.com/owner/repo-a.git", nil },
			DefaultBranch: func(string) (string, error) { return "main", nil }}
	}
	t.Cleanup(func() { newActionsTrack = restore })
}

// failedRun is a failed run of tests.yml that a push to main started.
var failedRun = gh.WorkflowRun{ID: 7, Number: 7, Attempt: 1, Event: "push", Branch: "main", Commit: strings.Repeat("a", 40),
	HeadRepo: "owner/repo-a", Name: "Tests", Path: ".github/workflows/tests.yml", Conclusion: "failure",
	Created: time.Date(2026, 11, 20, 6, 0, 0, 0, time.UTC), Started: time.Date(2026, 11, 20, 6, 0, 0, 0, time.UTC)}

// The pass prints its outcome as one JSON object and exits 0 once the writer
// files the tracker.
func TestActionsTrackPrintsItsOutcome(t *testing.T) {
	city, hub := &gcfake.Runtime{}, ghfake.New("bot")
	hub.Repos = map[string]*ghfake.Repo{"owner/repo-a": {Runs: []gh.WorkflowRun{failedRun}}}
	city.OnScript = func(c gcfake.Call) gascity.Result {
		switch c.Args[0] {
		case "key":
			return gascity.Result{Output: c.Args[2] + "\n"}
		case "file":
			return gascity.Result{Output: "preexisting-failure: sent ra-1 to be fixed\nra-1\n"}
		}
		return gascity.Result{}
	}
	pinActionsTrack(t, city, hub)
	var out, errb bytes.Buffer
	if code := Run([]string{"actions", "track", "--rig", "rig-a"}, "test", &out, &errb); code != 0 {
		t.Fatalf("exit %d: %s", code, errb.String())
	}
	var got actions.Outcome
	if err := json.Unmarshal(out.Bytes(), &got); err != nil || strings.Count(out.String(), "\n") != 1 {
		t.Fatalf("the outcome %q is not one JSON object: %v", out.String(), err)
	}
	if got.Rig != "rig-a" || got.Branch != "main" || len(got.Workflows) != 1 || got.Workflows[0].Did != actions.Filed ||
		got.Workflows[0].Tracker != "ra-1" {
		t.Errorf("the outcome is %+v", got)
	}
	var verbs []string
	for _, c := range city.Scripts() {
		verbs = append(verbs, c.Args[0])
	}
	if !slices.Equal(verbs, []string{"key", "find", "file"}) {
		t.Errorf("the pass ran the writer for %q", verbs)
	}
}

// A pass that did not complete still prints its outcome, says why on standard
// error and exits 1, and a call that names no rig is a usage error.
func TestActionsTrackFailsAndRefuses(t *testing.T) {
	city, hub := &gcfake.Runtime{}, ghfake.New("bot")
	hub.Fail["BranchRuns"] = errors.New("gh: HTTP 502")
	pinActionsTrack(t, city, hub)
	var out, errb bytes.Buffer
	if code := Run([]string{"actions", "track", "--rig", "rig-a"}, "test", &out, &errb); code != 1 ||
		!strings.Contains(out.String(), `"failure":"GitHub did not answer`) || !strings.Contains(errb.String(), "gh: HTTP 502") {
		t.Errorf("exit %d, stdout %q, stderr %q", code, out.String(), errb.String())
	}
	for _, args := range [][]string{{"actions", "track"}, {"actions", "track", "--rig", ""}} {
		out.Reset()
		errb.Reset()
		if code := Run(args, "test", &out, &errb); code != 2 || out.Len() != 0 {
			t.Errorf("%q: exit %d, stdout %q, stderr %q", args, code, out.String(), errb.String())
		}
	}
	if len(city.Scripts()) != 0 {
		t.Errorf("a pass that did not read ran %+v", city.Scripts())
	}
}
