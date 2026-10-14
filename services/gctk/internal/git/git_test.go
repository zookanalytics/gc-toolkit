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

// gitIn runs git in dir and fails the test on an error.
func gitIn(t *testing.T, dir string, args ...string) string {
	t.Helper()
	out, err := exec.Command("git", append([]string{"-C", dir}, args...)...).CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
	return strings.TrimSpace(string(out))
}

func TestDirtyListsAChangeConfigWouldHide(t *testing.T) {
	// hidden checks that plain `git status` leaves the change out, so the case
	// is one the flags have to catch.
	hidden := func(t *testing.T, dir string) {
		t.Helper()
		if got := gitIn(t, dir, "status", "--porcelain"); got != "" {
			t.Fatalf("plain git status listed %q; the config did not hide the change", got)
		}
	}
	t.Run("an untracked file under status.showUntrackedFiles=no", func(t *testing.T) {
		dir := repo(t)
		gitIn(t, dir, "config", "status.showUntrackedFiles", "no")
		if err := os.WriteFile(filepath.Join(dir, "foo_test.go"), []byte("package foo\n"), 0o644); err != nil {
			t.Fatal(err)
		}
		hidden(t, dir)
		c, err := Open(dir)
		if err != nil {
			t.Fatal(err)
		}
		if got, err := c.Dirty(); err != nil || got != "?? foo_test.go" {
			t.Fatalf("Dirty = %q, %v; want the untracked file", got, err)
		}
	})
	for _, key := range []string{"diff.ignoreSubmodules", "submodule.sub.ignore"} {
		t.Run("a submodule's change under "+key+"=all", func(t *testing.T) {
			inner := repo(t)
			dir := repo(t)
			gitIn(t, dir, "-c", "protocol.file.allow=always", "submodule", "add", "-q", inner, "sub")
			gitIn(t, dir, "commit", "-q", "-m", "sub")
			gitIn(t, dir, "config", key, "all")
			if err := os.WriteFile(filepath.Join(dir, "sub", "a.txt"), []byte("two\n"), 0o644); err != nil {
				t.Fatal(err)
			}
			hidden(t, dir)
			c, err := Open(dir)
			if err != nil {
				t.Fatal(err)
			}
			if got, err := c.Dirty(); err != nil || got != " M sub" {
				t.Fatalf("Dirty = %q, %v; want the submodule's change", got, err)
			}
		})
	}
}

func TestChangesSplitsTrackedChangesAndAMovedHEADFromUntrackedFiles(t *testing.T) {
	dir := repo(t)
	c, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	expect := func(step, wantMoved, wantUntracked string) {
		t.Helper()
		moved, untracked, err := c.Changes()
		if err != nil || moved != wantMoved || untracked != wantUntracked {
			t.Fatalf("%s: Changes = %q, %q, %v; want %q, %q", step, moved, untracked, err, wantMoved, wantUntracked)
		}
	}
	expect("clean", "", "")
	if err := os.WriteFile(filepath.Join(dir, "new.txt"), []byte("x\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	expect("an untracked file", "", "?? new.txt")
	if err := os.WriteFile(filepath.Join(dir, "a.txt"), []byte("changed\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	expect("an unstaged change", " M a.txt", "?? new.txt")
	gitIn(t, dir, "add", "a.txt")
	expect("a staged change", "M  a.txt", "?? new.txt")
	gitIn(t, dir, "commit", "-q", "-m", "two")
	expect("a new commit", "HEAD moved from "+c.Commit+" to "+gitIn(t, dir, "rev-parse", "HEAD"), "")
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
