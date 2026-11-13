package cli

import (
	"encoding/json"
	"path/filepath"
	"strings"
	"testing"
)

// The copy's own behavior, its leader included, is internal/rig's serve tests.
// These hold the verb's flags, its report and its exit codes.

func TestRigServeRefusesFlagsThatDoNotGoTogether(t *testing.T) {
	f := newRigFixture(t)
	for _, args := range [][]string{
		{"serve"},
		{"serve", "--command", "x", "--check"},
		{"serve", "--check", "--stop"},
		{"serve", "--command", ""},
		{"serve", "--command", "x", "--publish-command", "p"},
		{"serve", "--command", "x", "--address-pattern", "a"},
		{"serve", "--check", "--timeout", "1m"},
		{"serve", "--stop", "--publish-command", "p", "--address-pattern", "a"},
		{"serve", "--command", "x", "--timeout", "0s"},
		{"serve", "--lead", ""},
	} {
		if code, out, errb := f.call(args...); code != 2 || out != "" {
			t.Errorf("%v: exit %d, stdout %q, want a usage error (2) and no report\n%s", args, code, out, errb)
		}
	}
}

// --lead counts as a mode once it is given, as --command does, so an empty
// --lead says it needs a record, and one beside another mode says the two
// exclude one another.
func TestRigServeCountsLeadAsAModeOnceGiven(t *testing.T) {
	f := newRigFixture(t)
	for _, tc := range []struct {
		args []string
		want string
	}{
		{[]string{"serve", "--lead", ""}, "--lead needs a record"},
		{[]string{"serve", "--check", "--lead", ""}, "exclude one another"},
	} {
		if code, out, errb := f.call(tc.args...); code != 2 || out != "" || !strings.Contains(errb, tc.want) {
			t.Errorf("%v: exit %d, stdout %q, stderr %q, want a usage error (2) saying %q", tc.args, code, out, errb, tc.want)
		}
	}
}

// A call from a directory in no git checkout prints one JSON line, as every
// other failure does, so a caller that reads the report finds why: failed,
// with reason no-checkout, and exit 1. Exit 2 stays a usage error.
func TestRigServeFromNoCheckoutReportsWhy(t *testing.T) {
	f := newRigFixture(t)
	dir, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Setenv("GIT_CEILING_DIRECTORIES", filepath.Dir(dir))
	t.Chdir(dir)
	for _, args := range [][]string{{"serve", "--check"}, {"serve", "--stop"}, {"serve", "--command", "x"}} {
		code, out, errb := f.call(args...)
		rep := rigServeReport(t, out)
		if code != 1 || rep["state"] != "failed" || rep["reason"] != "no-checkout" || !strings.Contains(errb, "no git checkout") {
			t.Errorf("%v from no checkout: exit %d, %v %v, stderr %q, want 1, failed and no-checkout, and why", args, code, rep["state"], rep["reason"], errb)
		}
	}
}

func rigServeReport(t *testing.T, out string) map[string]any {
	t.Helper()
	var rep map[string]any
	if err := json.Unmarshal([]byte(strings.TrimSpace(out)), &rep); err != nil || strings.Count(strings.TrimSpace(out), "\n") != 0 {
		t.Fatalf("stdout is not one JSON line: %q (%v)", out, err)
	}
	return rep
}

func TestRigServeCheckAndStopWithNoCopyRunning(t *testing.T) {
	f := newRigFixture(t)
	code, out, errb := f.call("serve", "--check")
	rep := rigServeReport(t, out)
	if code != 3 || rep["state"] != "none" {
		t.Errorf("--check with no copy: exit %d, state %v, want 3 and none\n%s", code, rep["state"], errb)
	}
	if want, _ := filepath.EvalSymlinks(f.repo); rep["checkout"] != want {
		t.Errorf("checkout = %v, want the checkout's top, %s", rep["checkout"], want)
	}
	code, out, _ = f.call("serve", "--stop")
	if rep := rigServeReport(t, out); code != 0 || rep["state"] != "none" {
		t.Errorf("--stop with no copy: exit %d, state %v, want 0 and none", code, rep["state"])
	}
}

func TestRigServeStartNeedsTheSandboxsScriptsDirectory(t *testing.T) {
	f := newRigFixture(t)
	t.Setenv("GCTK_SCRIPTS_DIR", "")
	code, out, errb := f.call("serve", "--command", "exec sleep 60")
	rep := rigServeReport(t, out)
	if code != 1 || rep["state"] != "failed" || rep["reason"] != "no-sandbox" {
		t.Errorf("a start with no GCTK_SCRIPTS_DIR: exit %d, %v %v, want 1, failed and no-sandbox", code, rep["state"], rep["reason"])
	}
	if !strings.Contains(errb, "GCTK_SCRIPTS_DIR") {
		t.Errorf("stderr does not say what is missing: %q", errb)
	}
}
