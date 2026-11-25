package cli

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// The verb's exits, on a scratch origin and a clone with a branch that
// conflicts with it. Which base the merge takes is the pr domain's tests'.

// conflictingClone makes a bare origin whose main changes a line the clone's
// branch changes too, and returns the clone and the origin. The clone is made
// before main is, so its reflog of origin/main reaches back to the ref's
// making.
func conflictingClone(t *testing.T) (work, origin string) {
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
	root := t.TempDir()
	origin, work = filepath.Join(root, "origin.git"), filepath.Join(root, "work")
	up := filepath.Join(root, "up")
	run := func(dir string, args ...string) {
		t.Helper()
		if out, err := exec.Command("git", append([]string{"-C", dir}, args...)...).CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
	commit := func(dir, text string) {
		t.Helper()
		if err := os.WriteFile(filepath.Join(dir, "f.txt"), []byte(text), 0o644); err != nil {
			t.Fatal(err)
		}
		run(dir, "add", "-A")
		run(dir, "commit", "-q", "-m", text)
	}
	run(root, "init", "-q", "--bare", origin)
	run(root, "clone", "-q", origin, up)
	run(root, "clone", "-q", origin, work)
	run(up, "symbolic-ref", "HEAD", "refs/heads/main")
	commit(up, "one\n")
	run(up, "push", "-q", "origin", "HEAD:main")
	run(work, "fetch", "-q", "origin")
	run(work, "checkout", "-q", "-b", "pr", "origin/main")
	commit(work, "branch\n")
	commit(up, "main\n")
	run(up, "push", "-q", "origin", "HEAD:main")
	return work, origin
}

func bringCurrentIn(t *testing.T, dir string, args ...string) (stdout, stderr string, code int) {
	t.Helper()
	t.Chdir(dir)
	var out, errs bytes.Buffer
	code = Run(append([]string{"pr", "bring-current"}, args...), "", &out, &errs)
	return out.String(), errs.String(), code
}

func TestPRBringCurrentUsage(t *testing.T) {
	work, _ := conflictingClone(t)
	for name, args := range map[string][]string{
		"no target":           nil,
		"a blank target":      {"--target", " "},
		"no branch name":      {"--target", "a..b"},
		"an argument":         {"--target", "main", "extra"},
		"an abbreviated base": {"--target", "main", "--base", "abc1234"},
	} {
		t.Run(name, func(t *testing.T) {
			if _, _, code := bringCurrentIn(t, work, args...); code != 1 {
				t.Fatalf("exit %d, want the usage exit 1", code)
			}
		})
	}
	if _, _, code := bringCurrentIn(t, t.TempDir(), "--target", "main"); code != 1 {
		t.Fatalf("exit %d outside a checkout, want the usage exit 1", code)
	}
}

func TestPRBringCurrentExits(t *testing.T) {
	work, origin := conflictingClone(t)

	if err := os.WriteFile(filepath.Join(work, "f.txt"), []byte("edited\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, errs, code := bringCurrentIn(t, work, "--target", "main"); code != 3 || !strings.Contains(errs, "f.txt") {
		t.Fatalf("exit %d on uncommitted work, want the refusal exit 3 naming it\n%s", code, errs)
	}
	if out, err := exec.Command("git", "-C", work, "checkout", "-q", "--", "f.txt").CombinedOutput(); err != nil {
		t.Fatalf("git checkout: %v\n%s", err, out)
	}

	moved := origin + ".moved"
	if err := os.Rename(origin, moved); err != nil {
		t.Fatal(err)
	}
	if _, _, code := bringCurrentIn(t, work, "--target", "main"); code != 2 {
		t.Fatalf("exit %d when origin does not answer, want 2", code)
	}
	if err := os.Rename(moved, origin); err != nil {
		t.Fatal(err)
	}

	out, _, code := bringCurrentIn(t, work, "--target", "main")
	if code != 4 || !strings.Contains(out, "\n  f.txt\n") || !strings.Contains(out, "\nMerge origin/main at ") {
		t.Fatalf("exit %d on a conflict, want 4 with the file and the merge's message\n%s", code, out)
	}
	if _, _, code := bringCurrentIn(t, work, "--target", "main"); code != 3 {
		t.Fatalf("exit %d on an unfinished merge, want the refusal exit 3", code)
	}

	if out, err := exec.Command("git", "-C", work, "merge", "--abort").CombinedOutput(); err != nil {
		t.Fatalf("git merge --abort: %v\n%s", err, out)
	}
	if out, err := exec.Command("git", "-C", work, "reset", "-q", "--hard", "origin/main").CombinedOutput(); err != nil {
		t.Fatalf("git reset: %v\n%s", err, out)
	}
	if out, _, code := bringCurrentIn(t, work, "--target", "main"); code != 0 || !strings.Contains(out, "already holds") {
		t.Fatalf("exit %d on a HEAD that holds the target, want 0\n%s", code, out)
	}
}

func TestPRBringCurrentTakesTheBaseTheReflogCannotShow(t *testing.T) {
	work, _ := conflictingClone(t)
	git := func(args ...string) string {
		t.Helper()
		out, err := exec.Command("git", append([]string{"-C", work}, args...)...).CombinedOutput()
		if err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
		return strings.TrimSpace(string(out))
	}
	git("reflog", "expire", "--expire=now", "--all")

	if _, errs, code := bringCurrentIn(t, work, "--target", "main"); code != 3 || !strings.Contains(errs, "--base") {
		t.Fatalf("exit %d with no reflog of origin/main, want the refusal exit 3 asking for --base\n%s", code, errs)
	}
	if out, _, code := bringCurrentIn(t, work, "--target", "main", "--base", git("rev-parse", "HEAD~1")); code != 4 {
		t.Fatalf("exit %d from the base the branch was cut from, want the merge's conflict exit 4\n%s", code, out)
	}
}
