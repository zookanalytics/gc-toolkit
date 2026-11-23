package git

import (
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"testing"
)

// Grep reads the files at the rev it names, not the working tree, and names
// each from the top of the tree whichever directory it runs in. A rev whose
// files hold no matching line answers none, and a rev the clone does not hold
// is an error.
func TestGrepReadsTheFilesAtTheRev(t *testing.T) {
	dir := repo(t)
	wf := filepath.Join(dir, ".github", "workflows")
	if err := os.MkdirAll(filepath.Join(wf, "sub"), 0o755); err != nil {
		t.Fatal(err)
	}
	for name, text := range map[string]string{
		"marked.yml":       "# gc:mark\nname: A\n",
		"crlf.yaml":        "name: B\r\n#   gc:mark \r\non: push\r\n",
		"indented.yml":     "jobs:\n  a:\n    # gc:mark\n",
		"quoted.yml":       "run: echo '# gc:mark'\n",
		"plain.yml":        "name: C\n",
		"sub/nested.yml":   "# gc:mark\n",
		"marked.yml.orig":  "# gc:mark\n",
		"../top-level.yml": "# gc:mark\n",
	} {
		if err := os.WriteFile(filepath.Join(wf, name), []byte(text), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	for _, args := range [][]string{{"add", "-A"}, {"commit", "-q", "-m", "workflows"}, {"update-ref", "refs/remotes/origin/main", "HEAD"}} {
		if out, err := exec.Command("git", append([]string{"-C", dir}, args...)...).CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
	// A mark the working tree adds after the commit is not at the rev.
	if err := os.WriteFile(filepath.Join(wf, "plain.yml"), []byte("# gc:mark\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	const pattern = `^#[[:blank:]]*gc:mark[[:space:]]*$`
	paths := []string{":(top,glob).github/workflows/*.yml", ":(top,glob).github/workflows/*.yaml"}
	for _, from := range []string{dir, wf} {
		got, err := Grep(from, "refs/remotes/origin/main", pattern, paths...)
		if err != nil {
			t.Fatal(err)
		}
		slices.Sort(got)
		if want := []string{".github/workflows/crlf.yaml", ".github/workflows/marked.yml"}; !slices.Equal(got, want) {
			t.Errorf("from %s, Grep = %q, want %q", from, got, want)
		}
	}
	if got, err := Grep(dir, "refs/remotes/origin/main", `^#[[:blank:]]*gc:none$`, paths...); err != nil || got != nil {
		t.Errorf("a rev with no matching line answered %q, %v", got, err)
	}
	if got, err := Grep(dir, "refs/remotes/origin/gone", pattern, paths...); err == nil {
		t.Errorf("a rev the clone does not hold answered %q", got)
	}
	if got, err := Grep(t.TempDir(), "HEAD", pattern, paths...); err == nil {
		t.Errorf("a directory in no clone answered %q", got)
	}
}
