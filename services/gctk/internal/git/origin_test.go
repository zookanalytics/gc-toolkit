package git

import (
	"os"
	"os/exec"
	"path/filepath"
	"slices"
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

// A remote's URL names its host and its repository in each form a remote
// takes, and names none in any other.
func TestRemoteRepositoryReadsEachFormARemoteTakes(t *testing.T) {
	for url, want := range map[string]string{
		"git@github.com:owner/repo-a.git":             "github.com owner/repo-a",
		"git@github.com:owner/repo-a":                 "github.com owner/repo-a",
		"https://github.com/owner/repo-a":             "github.com owner/repo-a",
		"https://github.com/owner/repo-a.git/":        "github.com owner/repo-a",
		"https://token@github.com/owner/repo-a.git":   "github.com owner/repo-a",
		"ssh://git@github.com/owner/repo-a.git":       "github.com owner/repo-a",
		"ssh://git@git.example.com:2222/owner/repo-a": "git.example.com owner/repo-a",
		"  https://github.com/owner/repo-a  ":         "github.com owner/repo-a",
		"https://github.com/owner":                    "",
		"https://github.com/owner/repo-a/tree/main":   "",
		"/srv/git/repo-a.git":                         "",
		"":                                            "",
	} {
		host, repo, ok := RemoteRepository(url)
		got := ""
		if ok {
			got = host + " " + repo
		}
		if got != want {
			t.Errorf("RemoteRepository(%q) = %q, want %q", url, got, want)
		}
	}
}

// OriginURLs lists what a fetch from origin and a push to it reach once git
// rewrites the remote's URLs: a pushurl and a pushInsteadOf move only the
// push, an insteadOf moves both, and every URL the remote carries is listed.
func TestOriginURLsListWhereAFetchAndAPushGo(t *testing.T) {
	const (
		real = "https://github.com/acme/widgets.git"
		fork = "git@github.com:fork/widgets.git"
	)
	for name, c := range map[string]struct {
		config      [][]string
		fetch, push []string
	}{
		"the remote's url":  {fetch: []string{real}, push: []string{real}},
		"a pushurl":         {config: [][]string{{"remote.origin.pushurl", fork}}, fetch: []string{real}, push: []string{fork}},
		"a pushInsteadOf":   {config: [][]string{{"url.git@github.com:fork/.pushInsteadOf", "https://github.com/acme/"}}, fetch: []string{real}, push: []string{fork}},
		"an insteadOf":      {config: [][]string{{"url.git@github.com:fork/.insteadOf", "https://github.com/acme/"}}, fetch: []string{fork}, push: []string{fork}},
		"two urls":          {config: [][]string{{"--add", "remote.origin.url", fork}}, fetch: []string{real, fork}, push: []string{real, fork}},
		"two pushurls kept": {config: [][]string{{"remote.origin.pushurl", real}, {"--add", "remote.origin.pushurl", fork}}, fetch: []string{real}, push: []string{real, fork}},
	} {
		t.Run(name, func(t *testing.T) {
			dir := repo(t)
			gitIn(t, dir, "remote", "add", "origin", real)
			for _, kv := range c.config {
				gitIn(t, dir, append([]string{"config"}, kv...)...)
			}
			fetch, push, err := OriginURLs(dir)
			if err != nil || !slices.Equal(fetch, c.fetch) || !slices.Equal(push, c.push) {
				t.Fatalf("OriginURLs = %q, %q, %v, want %q, %q", fetch, push, err, c.fetch, c.push)
			}
		})
	}
	if _, _, err := OriginURLs(repo(t)); err == nil {
		t.Fatal("a clone with no origin listed its URLs")
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

// The default branch is the one origin/HEAD names, which a clone sets, and a
// clone whose origin/HEAD is gone names none.
func TestDefaultBranchIsTheBranchOriginsHEADNames(t *testing.T) {
	dir, _, _ := clone(t)
	if got, err := DefaultBranch(dir); err != nil || got != "main" {
		t.Fatalf("DefaultBranch = %q, %v, want main", got, err)
	}
	if err := FetchBranch(dir, "side"); err != nil {
		t.Fatal(err)
	}
	gitIn(t, dir, "remote", "set-head", "origin", "side")
	if got, err := DefaultBranch(dir); err != nil || got != "side" {
		t.Fatalf("after set-head, DefaultBranch = %q, %v, want side", got, err)
	}
	gitIn(t, dir, "remote", "set-head", "origin", "--delete")
	if got, err := DefaultBranch(dir); err == nil {
		t.Fatalf("a clone with no origin/HEAD named %q", got)
	}
}

// The tip is origin's branch as the clone last fetched it, never a local
// branch or tag of the same name, and a branch the clone never fetched has
// none.
func TestTipIsTheBranchAsTheCloneLastFetchedIt(t *testing.T) {
	dir, landed, side := clone(t)
	before := gitIn(t, dir, "rev-parse", "refs/remotes/origin/main")
	if got, err := Tip(dir, "main"); err != nil || got != before {
		t.Fatalf("before the fetch, Tip = %q, %v, want the clone's %s", got, err, before)
	}
	for _, b := range []string{"main", "side"} {
		if err := FetchBranch(dir, b); err != nil {
			t.Fatal(err)
		}
	}
	gitIn(t, dir, "branch", "origin/main", side)
	gitIn(t, dir, "tag", "origin/main", side)
	if got, err := Tip(dir, "main"); err != nil || got != landed {
		t.Fatalf("after the fetch, Tip = %q, %v, want %s", got, err, landed)
	}
	if got, err := Tip(dir, "gone"); err == nil {
		t.Fatalf("a branch the clone never fetched has tip %q", got)
	}
	if _, err := Tip(dir, "no such branch"); err == nil {
		t.Fatal("Tip took a name that is no branch")
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
