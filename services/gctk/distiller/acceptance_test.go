package distiller

import (
	"bytes"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/gcbdtest"
)

// The distiller's city acceptance test runs the feedback-distiller order with
// the gc the city runs, in a scratch city whose two rigs import this
// checkout's pack, and claims the run as the home rig's pool does. It runs
// only when GCTK_CITY_ACCEPTANCE=1 asks for it:
//
//	GCTK_CITY_ACCEPTANCE=1 go test ./distiller -run TestCityAcceptance -v

// Gas City registers the order once for the city. Its first run pours one run
// of the distiller in the store of the rig whose checkout holds the pack, which
// that rig's polecat pool claims, and its second run, while that run is open,
// pours none.
func TestCityAcceptance(t *testing.T) {
	if os.Getenv("GCTK_CITY_ACCEPTANCE") != "1" {
		t.Skip("the city acceptance test runs the city's gc on a scratch city; GCTK_CITY_ACCEPTANCE=1 runs it")
	}
	for _, tool := range []string{"gc", "bd", "dolt", "go"} {
		if _, err := exec.LookPath(tool); err != nil {
			t.Fatalf("GCTK_CITY_ACCEPTANCE asks for the city acceptance test, and %s is not on PATH", tool)
		}
	}
	pack, err := filepath.Abs("../../..")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(pack, "orders", "feedback-distiller.toml")); err != nil {
		t.Fatalf("no pack with the distiller's order at %s: %v", pack, err)
	}
	dir, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { gcbdtest.KillUnder(dir) })
	for _, kv := range os.Environ() {
		if name, _, _ := strings.Cut(kv, "="); strings.HasPrefix(name, "GC_") || strings.HasPrefix(name, "BEADS_") || name == "GCTK_BIN" {
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
	appendTo(t, filepath.Join(city, "city.toml"), "\n[providers.codex]\nbase = \"builtin:codex\"\n\n"+
		"[providers.gemini]\nbase = \"builtin:gemini\"\n\n[daemon]\nformula_v2 = true\n")
	// The order's exec line runs the city's gctk.
	build := exec.Command("go", "build", "-o", filepath.Join(city, ".gc", "services", "gctk", "bin", "gctk"), "./cmd/gctk")
	build.Dir = ".."
	if out, err := build.CombinedOutput(); err != nil {
		t.Fatalf("gctk did not build: %v\n%s", err, out)
	}
	home, web := filepath.Join(dir, "rigs", "tools"), filepath.Join(dir, "rigs", "web")
	writePack(t, home, "[pack]\nname = \"gc-toolkit\"\nschema = 2\n")
	if err := os.MkdirAll(web, 0o755); err != nil {
		t.Fatal(err)
	}
	t.Chdir(city)
	// The home rig binds the pack as tk, so its pool is tools/tk.polecat, a name
	// only the roster gives.
	for _, r := range [][3]string{{home, "tools", "tk"}, {web, "web", "gc-toolkit"}} {
		gc(t, city, "rig", "add", r[0], "--name", r[1], "--include", r[2]+"="+pack, "--default-branch", "main")
	}

	var listed struct {
		Orders []struct {
			Name string `json:"name"`
			Rig  string `json:"rig"`
		} `json:"orders"`
	}
	decode(t, gc(t, city, "order", "list", "--json"), &listed)
	var distillers []string
	for _, o := range listed.Orders {
		if o.Name == "feedback-distiller" {
			distillers = append(distillers, o.Rig)
		}
	}
	if strings.Join(distillers, ",") != "" || len(distillers) != 1 {
		t.Errorf("the distiller's order is registered for %q, want once for the city", distillers)
	}

	first := gc(t, city, "order", "run", "feedback-distiller")
	root := runs(t, city, "tools")
	if len(root) != 1 || !strings.Contains(first, "started "+root[0]) {
		t.Fatalf("the first run left the runs %v in the home rig and said %q", root, first)
	}
	if got := prefix(t, city, root[0]); got != "tk." {
		t.Errorf("the run's binding_prefix is %q, want the pool's binding, tk.", got)
	}
	for _, store := range []string{"web", ""} {
		if got := runs(t, city, store); len(got) != 0 {
			t.Errorf("the first run poured %v in the store of %q", got, store)
		}
	}
	if said, c := claimAs(t, city, "tools/tk.polecat"); c.Action != "work" || c.Root != root[0] {
		t.Fatalf("the home rig's pool did not claim the run %s: %+v: %s", root[0], c, said)
	}

	second := gc(t, city, "order", "run", "feedback-distiller")
	if got := runs(t, city, "tools"); len(got) != 1 || !strings.Contains(second, root[0]+", a run of "+Formula+", is open in rig tools") {
		t.Fatalf("the second run left the runs %v and said %q", got, second)
	}
}

// runs is the id of each live root of a distiller run in the store of rig, the
// city's own store when rig is empty.
func runs(t *testing.T, city, rig string) []string {
	t.Helper()
	args := []string{"bd"}
	if rig != "" {
		args = append(args, "--rig", rig)
	}
	args = append(args, "list", "--metadata-field", "gc.formula_name="+Formula, "--include-ephemeral", "--json", "--limit", "0")
	var rows []struct {
		ID       string            `json:"id"`
		Metadata map[string]string `json:"metadata"`
	}
	decode(t, gc(t, city, args...), &rows)
	var out []string
	for _, r := range rows {
		if r.Metadata["gc.kind"] == workflowKind {
			out = append(out, r.ID)
		}
	}
	return out
}

// prefix is the binding_prefix the run whose root is id was poured with, as
// Gas City stamps it on the root.
func prefix(t *testing.T, city, id string) string {
	t.Helper()
	var rows []struct {
		Metadata map[string]string `json:"metadata"`
	}
	decode(t, gc(t, city, "bd", "--rig", "tools", "show", id, "--json"), &rows)
	if len(rows) != 1 {
		t.Fatalf("%s read as %d rows", id, len(rows))
	}
	return rows[0].Metadata["gc.var.binding_prefix"]
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
