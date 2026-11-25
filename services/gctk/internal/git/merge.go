package git

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"slices"
	"strings"
)

// The calls a merge into a checkout makes: the operation the checkout is in
// the middle of, the updates of origin's branch the clone recorded, the
// commits of that history a commit no longer holds, a best common ancestor
// that may not exist, a commit written from a tree, and the merge itself.

// input runs `git -C dir args...` with stdin on its standard input and returns
// its stdout. A failure carries git's own stderr.
func input(dir, stdin string, args ...string) (string, error) {
	cmd := exec.Command("git", append([]string{"-C", dir}, args...)...)
	cmd.Stdin = strings.NewReader(stdin)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		if msg := strings.TrimSpace(stderr.String()); msg != "" {
			return "", fmt.Errorf("git %s: %s", args[0], msg)
		}
		return "", fmt.Errorf("git %s: %w", args[0], err)
	}
	return string(out), nil
}

// operations are the files git keeps in a worktree's own git directory while
// an operation that stops for a person is unfinished, each with the
// operation's name. sequencer/todo holds the picks a cherry-pick or revert of
// several commits has still to make, after a commit resolved the one it
// stopped on.
var operations = []struct{ path, name string }{
	{"MERGE_HEAD", "merge"},
	{"CHERRY_PICK_HEAD", "cherry-pick"},
	{"REVERT_HEAD", "revert"},
	{"sequencer/todo", "cherry-pick or revert"},
	{"rebase-merge", "rebase"},
	{"rebase-apply", "rebase"},
	{"BISECT_START", "bisect"},
}

// InProgress names the operation the worktree dir sits in is in the middle
// of: a merge, a cherry-pick, a revert, a rebase or a bisect that was neither
// finished nor aborted. It is "" when there is none.
func InProgress(dir string) (string, error) {
	args := []string{"rev-parse", "--path-format=absolute"}
	for _, op := range operations {
		args = append(args, "--git-path", op.path)
	}
	out, err := Output(dir, args...)
	if err != nil {
		return "", err
	}
	paths := strings.Split(strings.TrimRight(out, "\n"), "\n")
	if len(paths) != len(operations) {
		return "", fmt.Errorf("git rev-parse answered %d paths, want %d: %q", len(paths), len(operations), out)
	}
	for i, p := range paths {
		if _, err := os.Lstat(p); err == nil {
			return operations[i].name, nil
		} else if !errors.Is(err, os.ErrNotExist) {
			return "", err
		}
	}
	return "", nil
}

// RefUpdate is one update a ref's reflog records: Old, the commit the ref
// named before it, and New, the commit it named after. Old is all zeros on the
// update that made the ref.
type RefUpdate struct{ Old, New string }

// Reflog lists the updates of refs/remotes/origin/<branch> the clone dir sits
// in recorded, newest first. It reads the ref's log, whose lines
// git-update-ref(1) lays out under LOGGING, the old object name first and the
// new one second, since `git reflog` prints only the new one. Every worktree of
// a clone shares that log, and a ref with no log has recorded no update.
func Reflog(dir, branch string) ([]RefUpdate, error) {
	if !ValidBranch(branch) {
		return nil, fmt.Errorf("git reflog: %q is not a branch name", branch)
	}
	path, err := Output(dir, "rev-parse", "--path-format=absolute", "--git-path", "logs/refs/remotes/origin/"+branch)
	if err != nil {
		return nil, err
	}
	data, err := os.ReadFile(strings.TrimSuffix(path, "\n"))
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	} else if err != nil {
		return nil, err
	}
	var updates []RefUpdate
	for _, line := range strings.Split(string(data), "\n") {
		if line == "" {
			continue
		}
		f := strings.SplitN(line, " ", 3)
		if len(f) != 3 || !IsObjectID(f[0]) || !IsObjectID(f[1]) {
			return nil, fmt.Errorf("the reflog of origin/%s holds a line that names no update: %q", branch, line)
		}
		updates = append(updates, RefUpdate{Old: f[0], New: f[1]})
	}
	slices.Reverse(updates)
	return updates, nil
}

// IsNull reports whether id is the object name git writes for no object, all
// zeros.
func IsNull(id string) bool { return IsObjectID(id) && strings.Trim(id, "0") == "" }

// NotHeld keeps those of commits that tip does not hold, in their order: each
// that is neither tip nor one of its ancestors. One rev-list reads them all.
func NotHeld(dir string, commits []string, tip string) ([]string, error) {
	if !IsObjectID(tip) {
		return nil, fmt.Errorf("git rev-list: %q is not a full object name", tip)
	}
	if len(commits) == 0 {
		return nil, nil
	}
	var in strings.Builder
	for _, c := range commits {
		if !IsObjectID(c) {
			return nil, fmt.Errorf("git rev-list: %q is not a full object name", c)
		}
		in.WriteString(c + "\n")
	}
	in.WriteString("^" + tip + "\n")
	out, err := input(dir, in.String(), "rev-list", "--stdin")
	if err != nil {
		return nil, err
	}
	beyond := map[string]bool{}
	for _, l := range strings.Split(out, "\n") {
		beyond[strings.TrimSpace(l)] = true
	}
	var kept []string
	for _, c := range commits {
		if beyond[c] {
			kept = append(kept, c)
		}
	}
	return kept, nil
}

// CommonBase is a best common ancestor of commits a and b, as `git merge-base`
// answers, and ok is false when the two share no history.
func CommonBase(dir, a, b string) (base string, ok bool, err error) {
	if !IsObjectID(a) || !IsObjectID(b) {
		return "", false, fmt.Errorf("git merge-base: %q and %q must be full object names", a, b)
	}
	cmd := exec.Command("git", "-C", dir, "merge-base", a, b)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	var ee *exec.ExitError
	switch {
	case err == nil:
		if base = strings.TrimSpace(string(out)); IsObjectID(base) {
			return base, true, nil
		}
		return "", false, fmt.Errorf("git merge-base answered %q", out)
	case errors.As(err, &ee) && ee.ExitCode() == 1 && strings.TrimSpace(stderr.String()) == "":
		return "", false, nil
	}
	if msg := strings.TrimSpace(stderr.String()); msg != "" {
		return "", false, fmt.Errorf("git merge-base: %s", msg)
	}
	return "", false, fmt.Errorf("git merge-base: %w", err)
}

// TreeOf is the tree commit carries.
func TreeOf(dir, commit string) (string, error) {
	if !IsObjectID(commit) {
		return "", fmt.Errorf("git rev-parse: %q is not a full object name", commit)
	}
	out, err := Output(dir, "rev-parse", "--verify", commit+"^{tree}")
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(out), nil
}

// CommitTree writes a commit of tree with parents, in their order, and
// message, and returns it. It moves no ref. The commit is signed when the
// clone's commit.gpgSign says so, as a commit git commit makes there would
// be, since commit-tree itself does not read that setting.
func CommitTree(dir, tree string, parents []string, message string) (string, error) {
	sign := "--no-gpg-sign"
	out, err := Output(dir, "config", "--type=bool", "--default=false", "--get", "commit.gpgSign")
	if err != nil {
		return "", err
	}
	if strings.TrimSpace(out) == "true" {
		sign = "-S"
	}
	args := []string{"commit-tree", sign}
	for _, p := range parents {
		if !IsObjectID(p) {
			return "", fmt.Errorf("git commit-tree: %q is not a full object name", p)
		}
		args = append(args, "-p", p)
	}
	if !IsObjectID(tree) {
		return "", fmt.Errorf("git commit-tree: %q is not a full object name", tree)
	}
	out, err = input(dir, message, append(args, "-F", "-", tree)...)
	if err != nil {
		return "", err
	}
	commit := strings.TrimSpace(out)
	if !IsObjectID(commit) {
		return "", fmt.Errorf("git commit-tree answered %q", out)
	}
	return commit, nil
}

// Merge merges commit into the checkout dir sits in with message, as
// `git merge` does, so the merge takes git's own merge base and the
// repository's settings, signing among them. It commits the merge whatever a
// branch's merge options say, since `--no-commit` or `--squash` there would
// leave a clean merge uncommitted. When git stops on a conflict it leaves its
// merge state, MERGE_HEAD naming commit, for a person to finish, and
// conflicted lists the paths it left unmerged. Any other failure is an error
// carrying git's message.
func Merge(dir, commit, message string) (conflicted []string, err error) {
	if !IsObjectID(commit) {
		return nil, fmt.Errorf("git merge: %q is not a full object name", commit)
	}
	cmd := exec.Command("git", "-C", dir, "merge", "--no-edit", "--commit", "--no-squash", "-m", message, commit)
	var said bytes.Buffer
	cmd.Stdout = &said
	cmd.Stderr = &said
	if err := cmd.Run(); err == nil {
		return nil, nil
	}
	op, opErr := InProgress(dir)
	if opErr == nil && op == "merge" {
		out, uErr := Output(dir, "diff", "--name-only", "--diff-filter=U", "-z")
		if uErr != nil {
			return nil, uErr
		}
		for _, p := range strings.Split(out, "\x00") {
			if p != "" {
				conflicted = append(conflicted, p)
			}
		}
		if len(conflicted) > 0 {
			return conflicted, nil
		}
	}
	msg := strings.TrimSpace(said.String())
	if op == "merge" {
		msg += "\n(git left its merge state, with nothing unmerged: finish it with git commit, or undo it with git merge --abort)"
	}
	return nil, fmt.Errorf("git merge: %s", msg)
}
