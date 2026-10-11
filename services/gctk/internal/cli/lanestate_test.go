package cli

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/gcbdtest"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/lane"
)

// The adapter's grammar — usage, exit codes, stderr lines, a silent stdout —
// against lane-state.sh's cmd_green and its verb dispatch. The derivation is
// internal/lane's and tested there; this drives LaneState with an injected
// store and remote, so no subprocess runs.

const lsUsage = "usage: lane-state.sh green --anchor <id> --lane <lane> [--no-remote]\n"

type lsApprover struct{ approved, ok bool }

func (a lsApprover) ApprovedReviewOnPR(string, string) (bool, bool) { return a.approved, a.ok }

// withLaneDeps points LaneState at a store decoded from the suite's fixture
// shape and at a remote approving or not, for the test's duration.
func withLaneDeps(t *testing.T, beadsJSON string, f func(*gcbdtest.Fake), approved bool) *gcbdtest.Fake {
	t.Helper()
	dec := json.NewDecoder(strings.NewReader(beadsJSON))
	dec.UseNumber()
	var beads []gcbd.Bead
	if err := dec.Decode(&beads); err != nil {
		t.Fatalf("fixture: %v", err)
	}
	fake := gcbdtest.New(beads...)
	if f != nil {
		f(fake)
	}
	prev := newLaneDeps
	newLaneDeps = func() (gcbd.Store, lane.Remote) {
		return fake, lane.Remote{Origin: lane.FixedSlug("zook/gc-toolkit"), Approver: lsApprover{approved: approved, ok: true}}
	}
	t.Cleanup(func() { newLaneDeps = prev })
	return fake
}

func runLaneState(args ...string) (stdout, stderr string, rc int) {
	var out, errb bytes.Buffer
	rc = LaneState(args, &out, &errb)
	return out.String(), errb.String(), rc
}

const lsAnchor = `[{"id":"tk-anc","status":"open","metadata":{"merge_result":"pull_request","check_set":"correctness","pr_number":"42"}}]`
const lsBacked = `[{"id":"tk-anc","status":"open","metadata":{"pr_number":"42"}},{"id":"rv-1","status":"closed","metadata":{"task_kind":"review","check_name":"correctness","anchor_bead":"tk-anc","reviewed_oid":"deadbeef","signoff_verdict":"approve","gc.outcome":"recorded"}}]`

func TestLaneStateUsageGrammar(t *testing.T) {
	// A usage error never reaches the store: the deps hook must not be called.
	prev := newLaneDeps
	newLaneDeps = func() (gcbd.Store, lane.Remote) {
		t.Fatal("a usage error built the store")
		return nil, lane.Remote{}
	}
	t.Cleanup(func() { newLaneDeps = prev })

	cases := []struct {
		name   string
		args   []string
		stderr string
	}{
		{"no args: the usage line alone", nil, lsUsage},
		{"unknown verb", []string{"red"}, "lane-state: unknown verb 'red'\n" + lsUsage},
		{"unknown verb, flags after it", []string{"GREEN", "--anchor", "a"}, "lane-state: unknown verb 'GREEN'\n" + lsUsage},
		{"unknown arg", []string{"green", "--anchor", "a", "--lane", "l", "--bogus"}, "lane-state: unknown arg '--bogus'\n" + lsUsage},
		{"a bare word is an unknown arg", []string{"green", "a"}, "lane-state: unknown arg 'a'\n" + lsUsage},
		{"--anchor with no value: usage alone", []string{"green", "--lane", "l", "--anchor"}, lsUsage},
		{"--lane with no value: usage alone", []string{"green", "--anchor", "a", "--lane"}, lsUsage},
		{"no flags at all", []string{"green"}, "lane-state: green needs --anchor and --lane\n"},
		{"missing --lane", []string{"green", "--anchor", "a"}, "lane-state: green needs --anchor and --lane\n"},
		{"missing --anchor", []string{"green", "--lane", "l", "--no-remote"}, "lane-state: green needs --anchor and --lane\n"},
		{"an empty --anchor value is a present token, then missing", []string{"green", "--anchor", "", "--lane", "l"}, "lane-state: green needs --anchor and --lane\n"},
		// `--anchor --lane` takes "--lane" as the anchor and leaves no lane.
		{"a flag consumed as a value", []string{"green", "--anchor", "--lane", "l"}, "lane-state: unknown arg 'l'\n" + lsUsage},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			out, errs, rc := runLaneState(c.args...)
			if rc != 1 || out != "" || errs != c.stderr {
				t.Fatalf("LaneState(%q) = rc %d stdout %q stderr %q; want rc 1, no stdout, stderr %q", c.args, rc, out, errs, c.stderr)
			}
		})
	}
}

func TestLaneStateGreenExitCodes(t *testing.T) {
	t.Run("green: exit 0, nothing written", func(t *testing.T) {
		withLaneDeps(t, lsBacked, nil, false)
		out, errs, rc := runLaneState("green", "--anchor", "tk-anc", "--lane", "correctness", "--no-remote")
		if rc != 0 || out != "" || errs != "" {
			t.Fatalf("rc %d stdout %q stderr %q; want 0 and silence", rc, out, errs)
		}
	})
	t.Run("not green: exit 1, nothing written", func(t *testing.T) {
		withLaneDeps(t, lsAnchor, nil, false)
		out, errs, rc := runLaneState("green", "--anchor", "tk-anc", "--lane", "correctness", "--no-remote")
		if rc != 1 || out != "" || errs != "" {
			t.Fatalf("rc %d stdout %q stderr %q; want 1 and silence", rc, out, errs)
		}
	})
	t.Run("the remote fallback is wired through the deps hook", func(t *testing.T) {
		f := withLaneDeps(t, lsAnchor, nil, true)
		out, errs, rc := runLaneState("green", "--anchor", "tk-anc", "--lane", "correctness")
		if rc != 0 || out != "" || errs != "" {
			t.Fatalf("rc %d stdout %q stderr %q; want 0 and silence", rc, out, errs)
		}
		if !strings.Contains(f.Log(), "bd show tk-anc --json\n") {
			t.Fatalf("the fallback read no anchor; calls:\n%s", f.Log())
		}
		// --no-remote on the same store: fail-closed.
		if _, _, rc := runLaneState("green", "--anchor", "tk-anc", "--lane", "correctness", "--no-remote"); rc != 1 {
			t.Fatalf("--no-remote rc %d, want 1", rc)
		}
	})
	t.Run("flags in any order, --no-remote first", func(t *testing.T) {
		withLaneDeps(t, lsBacked, nil, false)
		if _, _, rc := runLaneState("green", "--no-remote", "--lane", "correctness", "--anchor", "tk-anc"); rc != 0 {
			t.Fatalf("rc %d, want 0", rc)
		}
	})
	t.Run("unreadable store: exit 2 with the warning", func(t *testing.T) {
		withLaneDeps(t, lsAnchor, func(f *gcbdtest.Fake) { f.ListFail = true }, false)
		out, errs, rc := runLaneState("green", "--anchor", "tk-anc", "--lane", "correctness", "--no-remote")
		if rc != 2 || out != "" || errs != "lane-state: could not read review beads on tk-anc\n" {
			t.Fatalf("rc %d stdout %q stderr %q; want 2, no stdout, the warning", rc, out, errs)
		}
	})
	t.Run("the list is the script's query", func(t *testing.T) {
		f := withLaneDeps(t, lsAnchor, nil, false)
		runLaneState("green", "--anchor", "tk-anc", "--lane", "arch", "--no-remote")
		want := "bd list --metadata-field anchor_bead=tk-anc --status=open,in_progress,blocked,deferred,hooked,pinned,closed --limit=0 --json\n"
		if f.Log() != want {
			t.Fatalf("calls:\n%s\nwant:\n%s", f.Log(), want)
		}
	})
}

// The default deps are the real store and the real git/gh seams; building them
// forks nothing (gcbd.New is config-only), so this only pins the wiring.
func TestLaneStateDefaultDeps(t *testing.T) {
	store, remote := newLaneDeps()
	if _, ok := store.(*gcbd.Client); !ok {
		t.Fatalf("store is %T, want *gcbd.Client", store)
	}
	if _, ok := remote.Origin.(lane.GitOrigin); !ok {
		t.Fatalf("origin is %T, want lane.GitOrigin", remote.Origin)
	}
	if _, ok := remote.Approver.(lane.GHApprover); !ok {
		t.Fatalf("approver is %T, want lane.GHApprover", remote.Approver)
	}
}
