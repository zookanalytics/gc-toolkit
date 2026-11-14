package git

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// clone is a clone of a repository whose main has a second commit the clone has
// not fetched, and a branch, side, whose commit main does not reach.
func clone(t *testing.T) (dir, landed, side string) {
	t.Helper()
	origin := repo(t)
	dir = filepath.Join(t.TempDir(), "clone")
	gitIn(t, filepath.Dir(dir), "clone", "-q", origin, dir)
	if err := os.WriteFile(filepath.Join(origin, "a.txt"), []byte("two\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	gitIn(t, origin, "commit", "-q", "-am", "two")
	landed = gitIn(t, origin, "rev-parse", "HEAD")
	gitIn(t, origin, "checkout", "-q", "-b", "side", "HEAD~1")
	if err := os.WriteFile(filepath.Join(origin, "b.txt"), []byte("side\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	gitIn(t, origin, "add", "-A")
	gitIn(t, origin, "commit", "-q", "-m", "side")
	side = gitIn(t, origin, "rev-parse", "HEAD")
	gitIn(t, origin, "checkout", "-q", "main")
	return dir, landed, side
}

func TestOriginURLNamesTheClonesOrigin(t *testing.T) {
	dir, _, _ := clone(t)
	want := gitIn(t, dir, "config", "remote.origin.url")
	if got, err := OriginURL(dir); err != nil || got != want {
		t.Fatalf("OriginURL = %q, %v, want %q", got, err, want)
	}
	if _, err := OriginURL(t.TempDir()); err == nil {
		t.Fatal("read an origin outside a clone")
	}
}

// A commit is reachable from the target only once a fetch has brought the
// target's tip, and a branch's commit the target does not reach never is.
func TestReachesReadsTheFetchedTarget(t *testing.T) {
	dir, landed, side := clone(t)
	if ok, err := Reaches(dir, landed, "main"); err != nil || ok {
		t.Fatalf("before the fetch, the merge commit reached main: %v, %v", ok, err)
	}
	if err := FetchBranch(dir, "main"); err != nil {
		t.Fatal(err)
	}
	if ok, err := Reaches(dir, landed, "main"); err != nil || !ok {
		t.Fatalf("after the fetch, the merge commit did not reach main: %v, %v", ok, err)
	}
	if err := FetchBranch(dir, "side"); err != nil {
		t.Fatal(err)
	}
	if ok, err := Reaches(dir, side, "main"); err != nil || ok {
		t.Fatalf("a commit main does not reach read as reachable: %v, %v", ok, err)
	}
	if err := FetchBranch(dir, "no such branch"); err == nil {
		t.Fatal("fetched a name that is no branch")
	}
	if err := FetchBranch(dir, "gone"); err == nil {
		t.Fatal("a fetch of a branch origin does not hold succeeded")
	}
}

// A local branch of the target's name, a replace ref and a grafts file each
// rewrite what a plain merge-base sees, and none of them stands in for the
// target origin holds.
func TestReachesIgnoresWhatRewritesHistory(t *testing.T) {
	dir, _, side := clone(t)
	if err := FetchBranch(dir, "side"); err != nil {
		t.Fatal(err)
	}
	if err := FetchBranch(dir, "main"); err != nil {
		t.Fatal(err)
	}
	gitIn(t, dir, "branch", "origin/main", side)
	gitIn(t, dir, "tag", "origin/main", side)
	main := gitIn(t, dir, "rev-parse", "refs/remotes/origin/main")
	gitIn(t, dir, "replace", "--graft", main, side)
	common := gitIn(t, dir, "rev-parse", "--git-common-dir")
	if !filepath.IsAbs(common) {
		common = filepath.Join(dir, common)
	}
	if err := os.MkdirAll(filepath.Join(common, "info"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(common, "info", "grafts"), []byte(main+" "+side+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if out, err := exec.Command("git", "-C", dir, "merge-base", "--is-ancestor", side, "origin/main").CombinedOutput(); err != nil {
		t.Fatalf("the rewrites do not fool a plain merge-base, so this case proves nothing: %v\n%s", err, out)
	}
	if ok, err := Reaches(dir, side, "main"); err != nil || ok {
		t.Fatalf("a rewritten history let a commit main does not reach stand as reachable: %v, %v", ok, err)
	}
}

func TestReachesReadsACommitTheCloneLacksAsUnreached(t *testing.T) {
	dir, _, _ := clone(t)
	if err := FetchBranch(dir, "main"); err != nil {
		t.Fatal(err)
	}
	if ok, err := Reaches(dir, strings.Repeat("1", 40), "main"); err != nil || ok {
		t.Fatalf("a commit the clone does not hold: %v, %v", ok, err)
	}
	if _, err := Reaches(dir, "HEAD", "main"); err == nil {
		t.Fatal("Reaches took a name that is no object id")
	}
}
