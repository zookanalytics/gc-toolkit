package git

import (
	"errors"
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"
)

// The reads of a commit a caller names, which the review domain's check index
// makes: whether a clone holds the commit, the commit fetched by its id when it
// does not, a file's text at the commit, and the paths a change touches.

// Toplevel is the top-level directory of the worktree dir sits in, and false
// when dir sits in none.
func Toplevel(dir string) (string, bool) {
	out, err := Output(dir, "rev-parse", "--show-toplevel")
	top := strings.TrimSpace(out)
	if err != nil || top == "" {
		return "", false
	}
	return top, true
}

// Store is the object store of the clone dir sits in: its git common
// directory with every symlink resolved, so the same directory named twice,
// and a worktree beside the checkout it was added to, read one store.
func Store(dir string) (string, error) {
	out, err := Output(dir, "rev-parse", "--path-format=absolute", "--git-common-dir")
	if err != nil {
		return "", err
	}
	common := strings.TrimSpace(out)
	if common == "" {
		return "", fmt.Errorf("git rev-parse: %s names no common directory", dir)
	}
	resolved, err := filepath.EvalSymlinks(common)
	if err != nil {
		return "", fmt.Errorf("git rev-parse: %w", err)
	}
	return resolved, nil
}

// HasCommit reports whether the clone dir sits in holds rev as a commit.
func HasCommit(dir, rev string) bool {
	return exec.Command("git", "-C", dir, "cat-file", "-e", rev+"^{commit}").Run() == nil
}

// FetchCommit fetches the commit oid names from origin by its id into the clone
// dir sits in. It fetches no tags and writes no FETCH_HEAD, so a reader of the
// last fetch's FETCH_HEAD still reads that fetch.
func FetchCommit(dir, oid string) error {
	if !IsObjectID(oid) {
		return fmt.Errorf("git fetch: %q is not a full object name", oid)
	}
	_, err := Output(dir, "fetch", "--quiet", "--no-tags", "--no-write-fetch-head", "origin", oid)
	return err
}

// FetchTip fetches branch from origin into refs/remotes/origin/<branch>,
// forced, so the ref names the tip origin holds now. Like FetchCommit it
// fetches no tags and writes no FETCH_HEAD.
func FetchTip(dir, branch string) error {
	if !ValidBranch(branch) {
		return fmt.Errorf("git fetch: %q is not a branch name", branch)
	}
	_, err := Output(dir, "fetch", "--quiet", "--no-tags", "--no-write-fetch-head", "origin",
		"+refs/heads/"+branch+":refs/remotes/origin/"+branch)
	return err
}

// FileAt is the text of path at rev in the clone dir sits in, as git stores
// it. held is false when rev carries no such path, and an error is a path rev
// carries whose text did not read.
func FileAt(dir, rev, path string) (text string, held bool, err error) {
	if exec.Command("git", "-C", dir, "cat-file", "-e", rev+":"+path).Run() != nil {
		return "", false, nil
	}
	text, err = Output(dir, "show", rev+":"+path)
	if err != nil {
		return "", true, err
	}
	return text, true, nil
}

// MergeBase is a best common ancestor of a and b.
func MergeBase(dir, a, b string) (string, error) {
	out, err := Output(dir, "merge-base", a, b)
	if err != nil {
		return "", err
	}
	base := strings.TrimSpace(out)
	if base == "" {
		return "", errors.New("git merge-base: no common ancestor")
	}
	return base, nil
}

// ChangedPaths lists every path the change from a to b touches, one each, in
// git's order. Rename detection is off, so a renamed file counts at the path
// it left as well as the one it lands at.
func ChangedPaths(dir, a, b string) ([]string, error) {
	out, err := Output(dir, "diff", "--no-renames", "--name-only", a, b)
	if err != nil {
		return nil, err
	}
	var paths []string
	for _, line := range strings.Split(out, "\n") {
		if line != "" {
			paths = append(paths, line)
		}
	}
	return paths, nil
}
