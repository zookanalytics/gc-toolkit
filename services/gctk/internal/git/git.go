// Package git is gctk's seam to the git CLI. Each call runs one git command
// in a directory the caller names, so no call depends on the process's working
// directory, and a failure carries git's own message.
package git

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"
	"time"
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

// PutBack returns the worktree to the commit Open read: every tracked file as
// HEAD holds it, staged or not, and no untracked file or nested repository
// that git does not ignore. Ignored files stay, other than one inside a nested
// repository it removes or in the way of a tracked file that goes back. A
// submodule stays as it is, whatever submodule.recurse says. A HEAD at another
// commit is not moved back, and PutBack then changes nothing. It returns what
// Dirty lists afterwards, which changes inside a submodule can leave.
func (c *Checkout) PutBack() (string, error) {
	head, err := Output(c.Top, "rev-parse", "--verify", "HEAD^{commit}")
	if err != nil {
		return "", fmt.Errorf("cannot read HEAD: %w", err)
	}
	if head = strings.TrimSpace(head); head != c.Commit {
		return "", fmt.Errorf("HEAD moved from %s to %s", c.Commit, head)
	}
	// submodule.recurse would also reset a submodule's files and HEAD.
	if _, err := Output(c.Top, "reset", "--hard", "--quiet", "--no-recurse-submodules", "HEAD"); err != nil {
		return "", err
	}
	// The second -f also removes an untracked nested repository.
	if _, err := Output(c.Top, "clean", "-ffd", "--quiet"); err != nil {
		return "", err
	}
	return c.Dirty()
}

// OriginURL reads the URL of the remote named origin in the clone dir sits in.
func OriginURL(dir string) (string, error) {
	out, err := Output(dir, "remote", "get-url", "origin")
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(out), nil
}

// OriginURLs lists the URLs of the remote named origin in the clone dir sits
// in as git resolves them, with every insteadOf and pushInsteadOf rewrite
// applied: fetch, the ones it fetches from, and push, the ones a push to
// origin goes to (`git remote get-url --all`, without and with --push).
func OriginURLs(dir string) (fetch, push []string, err error) {
	if fetch, err = remoteURLs(dir); err != nil {
		return nil, nil, err
	}
	if push, err = remoteURLs(dir, "--push"); err != nil {
		return nil, nil, err
	}
	return fetch, push, nil
}

// remoteURLs lists every URL `git remote get-url --all` prints for origin with
// flags, one a line.
func remoteURLs(dir string, flags ...string) ([]string, error) {
	out, err := Output(dir, append(append([]string{"remote", "get-url", "--all"}, flags...), "origin")...)
	if err != nil {
		return nil, err
	}
	var urls []string
	for _, l := range strings.Split(out, "\n") {
		if l = strings.TrimSpace(l); l != "" {
			urls = append(urls, l)
		}
	}
	return urls, nil
}

// ValidBranch reports whether name is a branch name git accepts.
func ValidBranch(name string) bool {
	if name == "" {
		return false
	}
	return exec.Command("git", "check-ref-format", "refs/heads/"+name).Run() == nil
}

// fetchStopGrace is how long a fetch that was stopped has to exit before git is
// killed outright. A variable so a test can shorten it.
var fetchStopGrace = 5 * time.Second

// Interrupted is a fetch that a SIGTERM or SIGINT to this process stopped. The
// signal went on to git's process group, and the caller ends this process with
// the status that signal gives, 128 plus its number.
type Interrupted struct{ Signal syscall.Signal }

func (e *Interrupted) Error() string { return fmt.Sprintf("git fetch: stopped by %s", e.Signal) }

// FetchBranch fetches branch from origin into refs/remotes/origin/<branch> in
// the clone dir sits in, forced, so the ref names the tip origin holds now.
// GIT_TERMINAL_PROMPT=0 makes a remote that asks for credentials fail the fetch
// instead of waiting on a terminal nobody is at.
//
// It stops when ctx ends. git leads a process group of its own, and the stop is
// a SIGTERM to that group. A fetch holds lock files in the clone, such as
// refs/remotes/origin/<branch>.lock, which git removes on SIGTERM and cannot on
// SIGKILL, and a lock left behind fails every later fetch of the branch there
// until a person deletes it. The ssh that carries the fetch is git's child, so
// the group is what reaches both. A git still running fetchStopGrace after the
// stop is killed outright. A stopped fetch returns an error that wraps the one
// that ended ctx.
//
// Its own group puts git out of reach of a signal sent to this process's group,
// which is how an order runner stops a run that outlives its timeout. So a
// SIGTERM or SIGINT that reaches this process during the fetch goes on to git's
// group, and the fetch returns *Interrupted once git has exited. A signal this
// process inherited as ignored stays ignored.
func FetchBranch(ctx context.Context, dir, branch string) error {
	if !ValidBranch(branch) {
		return fmt.Errorf("git fetch: %q is not a branch name", branch)
	}
	cmd := exec.CommandContext(ctx, "git", "-C", dir, "fetch", "--no-tags", "origin",
		"+refs/heads/"+branch+":refs/remotes/origin/"+branch)
	cmd.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=0")
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error { return syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM) }
	cmd.WaitDelay = fetchStopGrace
	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	stop := make(chan os.Signal, 1)
	for _, s := range []os.Signal{syscall.SIGTERM, syscall.SIGINT} {
		if !signal.Ignored(s) {
			signal.Notify(stop, s)
		}
	}
	defer signal.Stop(stop)
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("git fetch: %w", err)
	}
	waited := make(chan error, 1)
	go func() { waited <- cmd.Wait() }()
	var err error
	var got os.Signal
	select {
	case err = <-waited:
	case got = <-stop:
		_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM)
		select {
		case err = <-waited:
		case <-time.After(fetchStopGrace):
			_ = cmd.Process.Kill()
			err = <-waited
		}
	}
	// A signal that arrived as git finished is still this process's to take.
	if got == nil {
		select {
		case got = <-stop:
		default:
		}
	}
	if sig, ok := got.(syscall.Signal); ok {
		return &Interrupted{Signal: sig}
	}
	if err != nil {
		if ctx.Err() != nil {
			return fmt.Errorf("git fetch: origin/%s was stopped: %w", branch, ctx.Err())
		}
		if msg := strings.TrimSpace(stderr.String()); msg != "" {
			return fmt.Errorf("git fetch: %s", msg)
		}
		return fmt.Errorf("git fetch: %w", err)
	}
	return nil
}

// Contains reports whether commit contains ancestor: commit is ancestor, or
// descends from it, in the history the clone dir sits in stores. It reads that
// history as Reaches does, with replace refs and the grafts file ignored. A
// commit the clone does not hold contains nothing, and an ancestor it does not
// hold is in no history it holds, so neither contains the other. An error is a
// read that did not answer.
func Contains(dir, commit, ancestor string) (bool, error) {
	if !IsObjectID(commit) || !IsObjectID(ancestor) {
		return false, fmt.Errorf("git merge-base: %q or %q is not a full object name", commit, ancestor)
	}
	if commit == ancestor {
		return true, nil
	}
	cmd := exec.Command("git", "--no-replace-objects", "-C", dir, "merge-base", "--is-ancestor", ancestor, commit)
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
	case errors.As(err, &ee) && (strings.Contains(stderr.String(), "Not a valid commit name "+commit) ||
		strings.Contains(stderr.String(), "Not a valid commit name "+ancestor)):
		return false, nil
	}
	if msg := strings.TrimSpace(stderr.String()); msg != "" {
		return false, fmt.Errorf("git merge-base: %s", msg)
	}
	return false, fmt.Errorf("git merge-base: %w", err)
}

// Reaches reports whether commit is reachable from origin's branch as the clone
// dir sits in last fetched it, refs/remotes/origin/<branch> named in full, so a
// local branch or tag of the same name cannot stand in for it. It reads the
// history git stores, with replace refs and the grafts file ignored, since
// either rewrites what merge-base sees. A commit the clone does not hold is not
// reachable. An error is a read that did not answer.
func Reaches(dir, commit, branch string) (bool, error) {
	if !IsObjectID(commit) {
		return false, fmt.Errorf("git merge-base: %q is not a full object name", commit)
	}
	cmd := exec.Command("git", "--no-replace-objects", "-C", dir, "merge-base", "--is-ancestor", commit,
		"refs/remotes/origin/"+branch)
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
	case errors.As(err, &ee) && strings.Contains(stderr.String(), "Not a valid commit name "+commit):
		return false, nil
	}
	if msg := strings.TrimSpace(stderr.String()); msg != "" {
		return false, fmt.Errorf("git merge-base: %s", msg)
	}
	return false, fmt.Errorf("git merge-base: %w", err)
}

// DefaultBranch is the branch origin's HEAD names in the clone dir sits in,
// refs/remotes/origin/HEAD, which a clone sets to the branch origin checks out.
// A clone whose origin/HEAD names no branch of origin has none, an error.
func DefaultBranch(dir string) (string, error) {
	out, err := Output(dir, "symbolic-ref", "-q", "refs/remotes/origin/HEAD")
	if err != nil {
		return "", fmt.Errorf("origin/HEAD names no branch in the clone: %w", err)
	}
	ref := strings.TrimSpace(out)
	branch, ok := strings.CutPrefix(ref, "refs/remotes/origin/")
	if !ok || !ValidBranch(branch) {
		return "", fmt.Errorf("origin/HEAD names %q, which is no branch of origin", ref)
	}
	return branch, nil
}

// Tip is the commit origin's branch names as the clone dir sits in last fetched
// it, refs/remotes/origin/<branch> named in full, so a local branch or tag of
// the same name cannot stand in for it. A branch the clone never fetched has
// none, an error.
func Tip(dir, branch string) (string, error) {
	if !ValidBranch(branch) {
		return "", fmt.Errorf("git rev-parse: %q is not a branch name", branch)
	}
	out, err := Output(dir, "rev-parse", "--verify", "--quiet", "refs/remotes/origin/"+branch+"^{commit}")
	if err != nil {
		return "", fmt.Errorf("origin/%s names no commit in the clone: %w", branch, err)
	}
	return strings.TrimSpace(out), nil
}
