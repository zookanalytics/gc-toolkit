// Package git is gctk's seam to the git CLI. Each call runs one git command
// in a directory the caller names, so no call depends on the process's working
// directory, and a failure carries git's own message.
package git

import (
	"bytes"
	"errors"
	"fmt"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
)

// objectID is a full git object name, SHA-1 or SHA-256.
var objectID = regexp.MustCompile(`^[0-9a-f]{40}([0-9a-f]{24})?$`)

// IsObjectID reports whether s is a full git object name, SHA-1 or SHA-256.
func IsObjectID(s string) bool { return objectID.MatchString(s) }

// Output runs `git -C dir args...` and returns its stdout. A failure carries
// git's own stderr.
func Output(dir string, args ...string) (string, error) {
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

// Checkout is a worktree's place in its clone and the commit at its HEAD.
type Checkout struct {
	// Top is the worktree's top-level directory.
	Top string
	// Common is the clone's git common directory, which every worktree of the
	// clone shares.
	Common string
	// Commit and Tree are HEAD's full object names.
	Commit string
	Tree   string
}

// Open reads the checkout dir sits in, in one git call.
func Open(dir string) (*Checkout, error) {
	out, err := Output(dir, "rev-parse", "--path-format=absolute", "--show-toplevel", "--git-common-dir",
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
	if !IsObjectID(c.Commit) || !IsObjectID(c.Tree) {
		return nil, fmt.Errorf("HEAD %q or its tree %q is not a full object name", c.Commit, c.Tree)
	}
	return c, nil
}

// Dirty returns what `git status --porcelain` lists: tracked changes, staged
// or not, and untracked files that are not ignored. Empty means HEAD is
// exactly the tree in the worktree.
//
// Its flags overrule the config that would leave a change out of that list:
// status.showUntrackedFiles hides untracked files, and diff.ignoreSubmodules
// and submodule.<name>.ignore hide a submodule's changes. A file git is told
// to skip with update-index --assume-unchanged or --skip-worktree is still
// left out.
func (c *Checkout) Dirty() (string, error) {
	out, err := Output(c.Top, "status", "--porcelain", "--untracked-files=normal", "--ignore-submodules=none")
	if err != nil {
		return "", fmt.Errorf("cannot read the checkout's status: %w", err)
	}
	return strings.TrimRight(out, "\n"), nil
}

// Changes compares the checkout with the commit Open read. moved names HEAD
// at another commit, or else lists the tracked files that differ from it,
// staged or not, a submodule's own HEAD and tracked files included. When
// nothing moved, untracked lists what Dirty lists, all of which leaves the
// commit's files as they are: untracked files that are not ignored, and a
// submodule that holds only untracked content. Both lists are in Dirty's
// form, and a caller that found the checkout clean reads them as what changed
// since.
func (c *Checkout) Changes() (moved, untracked string, err error) {
	head, err := Output(c.Top, "rev-parse", "--verify", "HEAD^{commit}")
	if err != nil {
		return "", "", fmt.Errorf("cannot read HEAD: %w", err)
	}
	if head = strings.TrimSpace(head); head != c.Commit {
		return fmt.Sprintf("HEAD moved from %s to %s", c.Commit, head), "", nil
	}
	// --ignore-submodules=untracked leaves out a submodule's untracked content
	// alone, and overrules the config that would leave out more.
	tracked, err := Output(c.Top, "status", "--porcelain", "--untracked-files=no", "--ignore-submodules=untracked")
	if err != nil {
		return "", "", fmt.Errorf("cannot read the checkout's status: %w", err)
	}
	if tracked = strings.TrimRight(tracked, "\n"); tracked != "" {
		return tracked, "", nil
	}
	untracked, err = c.Dirty()
	return "", untracked, err
}
