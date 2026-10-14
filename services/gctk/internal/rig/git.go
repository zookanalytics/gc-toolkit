package rig

import (
	"bytes"
	"errors"
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"
)

// Checkout is the git state a check is keyed on.
type Checkout struct {
	// Top is the worktree's top-level directory, where every command runs.
	Top string
	// Common is the clone's git common directory, which holds the records.
	Common string
	// Commit and Tree are HEAD's full object names.
	Commit string
	Tree   string
}

// Open reads the checkout dir sits in, in one git call.
func Open(dir string) (*Checkout, error) {
	out, err := gitOut(dir, "rev-parse", "--path-format=absolute", "--show-toplevel", "--git-common-dir",
		"HEAD^{commit}", "HEAD^{tree}")
	if err != nil {
		return nil, fmt.Errorf("not a checkout with a commit at HEAD: %w", err)
	}
	lines := strings.Split(strings.TrimRight(out, "\n"), "\n")
	if len(lines) != 4 {
		return nil, fmt.Errorf("git rev-parse answered %d lines, want 4: %q", len(lines), out)
	}
	c := &Checkout{
		Top:    lines[0],
		Common: filepath.Clean(lines[1]),
		Commit: lines[2],
		Tree:   lines[3],
	}
	if !objectID.MatchString(c.Commit) || !objectID.MatchString(c.Tree) {
		return nil, fmt.Errorf("HEAD %q or its tree %q is not a full object name", c.Commit, c.Tree)
	}
	return c, nil
}

// Dirty returns what `git status --porcelain` lists: tracked changes, staged
// or not, and untracked files that are not ignored. Empty means HEAD is
// exactly the tree a command would check.
func (c *Checkout) Dirty() (string, error) {
	out, err := gitOut(c.Top, "status", "--porcelain")
	if err != nil {
		return "", fmt.Errorf("cannot read the checkout's status: %w", err)
	}
	return strings.TrimRight(out, "\n"), nil
}

// DiffScopeEmpty reports whether `git diff --name-only origin/<base>...HEAD`,
// the diff affected_tests_command selects its subset from, names no file.
func (c *Checkout) DiffScopeEmpty(base string) (bool, error) {
	out, err := gitOut(c.Top, "diff", "--name-only", "origin/"+base+"...HEAD", "--")
	if err != nil {
		return false, fmt.Errorf("cannot diff HEAD against origin/%s: %w", base, err)
	}
	return strings.TrimSpace(out) == "", nil
}

// DefaultBase is the base the affected diff is taken against when the caller
// names none. A pour takes base_branch from the rig when the rig sets it, else
// from the bead's target, else from the rig's default branch. The gate reads no
// bead, so after the rig's own value it takes the branch the clone's origin/HEAD
// names, and the formula's default last.
func (c *Checkout) DefaultBase(v Vars) string {
	if v.RigSets(VarBase) && v.Value(VarBase) != "" {
		return v.Value(VarBase)
	}
	if out, err := gitOut(c.Top, "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"); err == nil {
		if b := strings.TrimPrefix(strings.TrimSpace(out), "origin/"); b != "" && b != "HEAD" {
			return b
		}
	}
	if b := v.Value(VarBase); b != "" {
		return b
	}
	return "main"
}

// gitOut runs one git command in dir and returns its stdout. A failure carries
// git's own stderr.
func gitOut(dir string, args ...string) (string, error) {
	cmd := exec.Command("git", append([]string{"-C", dir}, args...)...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		var ee *exec.ExitError
		if msg := strings.TrimSpace(stderr.String()); errors.As(err, &ee) && msg != "" {
			return "", fmt.Errorf("git %s: %s", args[0], msg)
		}
		return "", fmt.Errorf("git %s: %w", args[0], err)
	}
	return string(out), nil
}
