package rig

import (
	"fmt"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/git"
)

// DiffScopeEmpty reports whether `git diff --name-only origin/<base>...HEAD`,
// the diff affected_tests_command selects its subset from, names no file.
func DiffScopeEmpty(c *git.Checkout, base string) (bool, error) {
	out, err := git.Output(c.Top, "diff", "--name-only", "origin/"+base+"...HEAD", "--")
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
func DefaultBase(c *git.Checkout, v Vars) string {
	if v.RigSets(VarBase) && v.Value(VarBase) != "" {
		return v.Value(VarBase)
	}
	if out, err := git.Output(c.Top, "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"); err == nil {
		if b := strings.TrimPrefix(strings.TrimSpace(out), "origin/"); b != "" && b != "HEAD" {
			return b
		}
	}
	if b := v.Value(VarBase); b != "" {
		return b
	}
	return "main"
}
