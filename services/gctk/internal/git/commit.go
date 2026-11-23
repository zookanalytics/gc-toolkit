package git

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// The reads of a commit a caller names, which the review domain's check index
// and its review run make: whether a clone holds the commit, the commit fetched
// by its id when it does not, a file's text at the commit, whether one commit
// is behind another, and the paths a change touches. The actions report reads
// the files at a rig's default branch that hold its mark, through Grep.

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

// Grep is each file at rev in the clone dir sits in, among those the pathspecs
// in paths name, whose text holds a line pattern matches, an extended regular
// expression, each path from the top of the tree, in git's order. Files at rev
// that hold no such line give none, which git grep answers with exit 1, and an
// error is a read that did not answer.
func Grep(dir, rev, pattern string, paths ...string) ([]string, error) {
	args := append([]string{"-C", dir, "grep", "-l", "-z", "-I", "--full-name", "-E", "-e", pattern, rev, "--"}, paths...)
	cmd := exec.Command("git", args...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	var ee *exec.ExitError
	msg := strings.TrimSpace(stderr.String())
	switch {
	case err == nil:
	case errors.As(err, &ee) && ee.ExitCode() == 1 && msg == "":
		return nil, nil
	case msg != "":
		return nil, fmt.Errorf("git grep: %s", msg)
	default:
		return nil, fmt.Errorf("git grep: %w", err)
	}
	var files []string
	for _, name := range strings.Split(string(out), "\x00") {
		if name != "" {
			files = append(files, strings.TrimPrefix(name, rev+":"))
		}
	}
	return files, nil
}

// IsAncestor reports whether commit a is b or an ancestor of b in the clone
// dir sits in, reading the history git stores, with replace refs and the
// grafts file ignored, since either rewrites what merge-base sees. An error is
// a read that did not answer, a commit the clone does not hold among them.
func IsAncestor(dir, a, b string) (bool, error) {
	if !IsObjectID(a) || !IsObjectID(b) {
		return false, fmt.Errorf("git merge-base: %q and %q must be full object names", a, b)
	}
	cmd := exec.Command("git", "--no-replace-objects", "-C", dir, "merge-base", "--is-ancestor", a, b)
	cmd.Env = append(os.Environ(), "GIT_GRAFT_FILE="+os.DevNull)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	err := cmd.Run()
	var ee *exec.ExitError
	switch {
	case err == nil:
		return true, nil
	case errors.As(err, &ee) && ee.ExitCode() == 1:
		return false, nil
	}
	if msg := strings.TrimSpace(stderr.String()); msg != "" {
		return false, fmt.Errorf("git merge-base: %s", msg)
	}
	return false, fmt.Errorf("git merge-base: %w", err)
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
