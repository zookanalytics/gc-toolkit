package git

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// repo makes a scratch clone with one commit. Git reads no config of the
// host's.
func repo(t *testing.T) string {
	t.Helper()
	cfg := filepath.Join(t.TempDir(), "gitconfig")
	if err := os.WriteFile(cfg, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	for k, v := range map[string]string{
		"GIT_CONFIG_GLOBAL": cfg, "GIT_CONFIG_NOSYSTEM": "1",
		"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.com",
		"GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.com",
	} {
		t.Setenv(k, v)
	}
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "a.txt"), []byte("one\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	for _, args := range [][]string{{"init", "-q", "-b", "main"}, {"add", "-A"}, {"commit", "-q", "-m", "one"}} {
		if out, err := exec.Command("git", append([]string{"-C", dir}, args...)...).CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
	return dir
}

func TestOpenReadsTheCheckoutFromASubdirectory(t *testing.T) {
	dir := repo(t)
	sub := filepath.Join(dir, "sub")
	if err := os.Mkdir(sub, 0o755); err != nil {
		t.Fatal(err)
	}
	c, err := Open(sub)
	if err != nil {
		t.Fatal(err)
	}
	head, _ := Output(dir, "rev-parse", "HEAD")
	tree, _ := Output(dir, "rev-parse", "HEAD^{tree}")
	top, _ := filepath.EvalSymlinks(dir)
	gotTop, _ := filepath.EvalSymlinks(c.Top)
	gotCommon, _ := filepath.EvalSymlinks(c.Common)
	if gotTop != top || gotCommon != filepath.Join(top, ".git") ||
		c.Commit != strings.TrimSpace(head) || c.Tree != strings.TrimSpace(tree) {
		t.Fatalf("Open = %+v, want top %s, its .git, HEAD %s and tree %s", c, top, head, tree)
	}
}

func TestOpenRefusesADirectoryWithNoCommit(t *testing.T) {
	repo(t)
	empty := t.TempDir()
	if out, err := exec.Command("git", "-C", empty, "init", "-q").CombinedOutput(); err != nil {
		t.Fatalf("git init: %v\n%s", err, out)
	}
	for _, dir := range []string{empty, t.TempDir()} {
		if c, err := Open(dir); err == nil {
			t.Errorf("Open(%s) = %+v, want an error", dir, c)
		}
	}
}

func TestDirtyListsWhatHEADDoesNotHold(t *testing.T) {
	dir := repo(t)
	c, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	if got, err := c.Dirty(); err != nil || got != "" {
		t.Fatalf("Dirty on a clean checkout = %q, %v", got, err)
	}
	if err := os.WriteFile(filepath.Join(dir, "new.txt"), []byte("x\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got, err := c.Dirty(); err != nil || got != "?? new.txt" {
		t.Fatalf("Dirty with an untracked file = %q, %v", got, err)
	}
}

func TestOutputCarriesGitsOwnMessage(t *testing.T) {
	dir := repo(t)
	_, err := Output(dir, "rev-parse", "--verify", "no-such-ref")
	if err == nil || !strings.Contains(err.Error(), "git rev-parse: fatal: Needed a single revision") {
		t.Fatalf("Output error = %v, want git's own message", err)
	}
}

func TestIsObjectIDTakesOnlyAFullObjectName(t *testing.T) {
	for s, want := range map[string]bool{
		strings.Repeat("a", 40):         true,
		strings.Repeat("0", 64):         true,
		strings.Repeat("a", 39):         false,
		strings.Repeat("a", 41):         false,
		strings.Repeat("A", 40):         false,
		"HEAD":                          false,
		"../" + strings.Repeat("a", 37): false,
	} {
		if got := IsObjectID(s); got != want {
			t.Errorf("IsObjectID(%q) = %v, want %v", s, got, want)
		}
	}
}
