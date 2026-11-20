package gascity

import (
	"bytes"
	"encoding/json"
	"maps"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/gcbdtest"
)

// The runtime adapter's city acceptance test pours the pack's review run with
// the gc the city runs, in a scratch city that imports this checkout's pack,
// and claims its first step as gc hook --claim does. It runs only when
// GCTK_CITY_ACCEPTANCE=1 asks for it:
//
//	GCTK_CITY_ACCEPTANCE=1 go test ./internal/gascity -run TestCityAcceptance -v

// A review run Cook attaches to a bead assigned to nobody, as the landing order
// pours a PR's run while the bead waits on the pending record, is handed out at
// its first claim, while the same run Cook attaches to a bead an agent outside
// the run is assigned is retired there, unclaimed.
func TestCityAcceptance(t *testing.T) {
	if os.Getenv("GCTK_CITY_ACCEPTANCE") != "1" {
		t.Skip("the city acceptance test runs the city's gc on a scratch city; GCTK_CITY_ACCEPTANCE=1 runs it")
	}
	for _, tool := range []string{"gc", "bd", "dolt"} {
		if _, err := exec.LookPath(tool); err != nil {
			t.Fatalf("GCTK_CITY_ACCEPTANCE asks for the city acceptance test, and %s is not on PATH", tool)
		}
	}
	pack, err := filepath.Abs("../../../..")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(pack, "formulas", "mol-pr-review.toml")); err != nil {
		t.Fatalf("no pack with the review formula at %s: %v", pack, err)
	}
	dir, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { gcbdtest.KillUnder(dir) })
	for _, kv := range os.Environ() {
		if name, _, _ := strings.Cut(kv, "="); strings.HasPrefix(name, "GC_") || strings.HasPrefix(name, "BEADS_") {
			t.Setenv(name, "")
			if err := os.Unsetenv(name); err != nil {
				t.Fatal(err)
			}
		}
	}
	t.Setenv("GC_HOME", filepath.Join(dir, "home"))
	t.Setenv("GC_NO_API", "1")
	city := filepath.Join(dir, "city")
	gc(t, dir, "init", "--template", "minimal", "--default-provider", "claude", "--skip-provider-readiness",
		"--no-start", "--name", "ca", "--prefix", "ca", city)
	appendTo(t, filepath.Join(city, "pack.toml"), "\n[imports.gc-toolkit]\nsource = \""+pack+"\"\n")
	appendTo(t, filepath.Join(city, "city.toml"), "\n[providers.codex]\nbase = \"builtin:codex\"\n\n"+
		"[providers.gemini]\nbase = \"builtin:gemini\"\n\n[daemon]\nformula_v2 = true\n")
	for _, pool := range []string{"reviewer", "repairer", "waiting-reviewer"} {
		if err := os.MkdirAll(filepath.Join(city, "agents", pool), 0o755); err != nil {
			t.Fatal(err)
		}
		appendTo(t, filepath.Join(city, "agents", pool, "agent.toml"), "scope = \"city\"\nmin_active_sessions = 0\nmax_active_sessions = 1\n")
		appendTo(t, filepath.Join(city, "agents", pool, "prompt.template.md"), "Work.\n")
	}
	t.Chdir(city)

	var created struct {
		ID string `json:"id"`
	}
	decode(t, gc(t, city, "bd", "create", "the PR's bead", "--assignee", "rig/rig.refinery", "--json"), &created)
	bead := created.ID
	vars := map[string]string{"pr_bead": bead, "head": "0123456789abcdef0123456789abcdef01234567", "target": "main",
		"branch": "polecat/" + bead, "review_target": "reviewer", "repair_target": "repairer", "binding_prefix": "gc-toolkit."}

	pour := func(bead string, vars map[string]string) string {
		t.Helper()
		res := New().In(city).Cook(Cook{Formula: "mol-pr-review", Bead: bead, Vars: vars})
		if res.Code != 0 || res.Root == "" {
			t.Fatalf("the cook attached to %s answered %+v", bead, res)
		}
		return res.Root
	}

	// The pour onto a bead assigned to nobody is handed out at its first claim.
	// Its steps go to a pool of their own, so the control's claim does not take
	// them.
	decode(t, gc(t, city, "bd", "create", "a waiting PR's bead", "--json"), &created)
	waiting := created.ID
	wvars := maps.Clone(vars)
	wvars["pr_bead"], wvars["branch"], wvars["review_target"] = waiting, "polecat/"+waiting, "waiting-reviewer"
	root := pour(waiting, wvars)
	if said, c := claimAs(t, city, "waiting-reviewer"); c.Action != "work" || c.Root != root || status(t, city, root) == "closed" {
		t.Fatalf("the run attached to a bead assigned to nobody was not handed out at its first claim: %+v, %s is %s: %s",
			c, root, status(t, city, root), said)
	}

	// The control: the pour onto a bead an agent outside the run is assigned is
	// retired at its first claim.
	attached := pour(bead, vars)
	if said, c := claimAs(t, city, "reviewer"); c.Action != "drain" || !strings.Contains(said, "skipped") || status(t, city, attached) != "closed" {
		t.Fatalf("the run attached to a bead an outside agent is assigned was not retired at its first claim: %+v, %s is %s: %s",
			c, attached, status(t, city, attached), said)
	}
}

// claim is what gc hook --claim --json answers.
type claim struct {
	Action string `json:"action"`
	Bead   string `json:"bead_id"`
	Root   string `json:"root_bead_id"`
}

// claimAs claims one item for agent in the city, whatever the claim's exit,
// since a claim that finds no work exits 1, and returns what it printed on its
// standard error and its JSON answer.
func claimAs(t *testing.T, city, agent string) (string, claim) {
	t.Helper()
	out, said, _ := run(city, "hook", agent, "--claim", "--json")
	var c claim
	decode(t, out, &c)
	return said, c
}

// status is the bead's status as the city's store reads it.
func status(t *testing.T, city, id string) string {
	t.Helper()
	var rows []struct {
		Status string `json:"status"`
	}
	decode(t, gc(t, city, "bd", "show", id, "--json"), &rows)
	if len(rows) != 1 {
		t.Fatalf("%s read as %d rows", id, len(rows))
	}
	return rows[0].Status
}

// gc runs gc in dir and returns what it printed on its standard output,
// failing the test on a non-zero exit.
func gc(t *testing.T, dir string, args ...string) string {
	t.Helper()
	out, said, err := run(dir, args...)
	if err != nil {
		t.Fatalf("gc %s: %v\n%s%s", strings.Join(args, " "), err, out, said)
	}
	return out
}

// run runs gc in dir, its standard input reading nothing, and returns what it
// printed on its standard output and on its standard error.
func run(dir string, args ...string) (string, string, error) {
	cmd := exec.Command("gc", args...)
	cmd.Dir = dir
	var out, said bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &said
	err := cmd.Run()
	return out.String(), said.String(), err
}

// decode reads out's first JSON value into v.
func decode(t *testing.T, out string, v any) {
	t.Helper()
	if i := strings.IndexAny(out, "{["); i < 0 || json.NewDecoder(strings.NewReader(out[i:])).Decode(v) != nil {
		t.Fatalf("no JSON value in %q", out)
	}
}

func appendTo(t *testing.T, path, text string) {
	t.Helper()
	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := f.WriteString(text); err != nil {
		t.Fatal(err)
	}
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}
}
