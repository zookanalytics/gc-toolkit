---
name: Every branch is brought current by merge, never rebase
description: The refinery brings every branch shape current by merging its target in, never by rebasing. Why merge rather than rebase, which sites choose and perform it, and how the push stays a fast-forward.
---

# Every branch is brought current by merge, never rebase

Every branch shape — a per-bead `polecat/*` branch, a shared `integration/*`
branch, a graduation bead — is brought current with its target by
`git merge --no-edit origin/<target>`. No branch shape is rebased, so no branch
is rewritten and nothing force-pushes on the automatic path.

`main` stays linear on its own account: `merge.sh` lands every PR with
`gh pr merge --squash`, the only landing verb, so the squash collapses the
branch's history at land whatever shape the branch carries. The branch view is a
merge; the landed `main` view is a squash.

## Why merge, not rebase

A rebase rewrites the branch's commits and needs a `--force-with-lease` push to
publish them. On an open PR that push does two harmful things:

- It resets GitHub's "changes since last review": the rebase replaces the
  reviewed commits with rewritten copies, so the incremental diff a reviewer
  relies on has nothing to compute against.
- It drifts every line-anchored inline review comment, because the commits the
  comments are pinned to are not part of the rewritten branch.

Merging the target in adds a merge commit and keeps the reviewed commits as
ancestors, so the review delta and the inline comments both survive. Merging
still pulls base changes that can shift some line anchors, and that is expected:
the guarantee is that no force-push resets the review, not that anchors never
move.

## Where the choice is made and performed

Four sites carry the merge-in choice. Three dispatch a bring-current child,
classifying its `prepare_mode` as `merge` and handing it a merge-in
instruction; the fourth performs the merge itself:

- `assets/scripts/pre-open-rebase.sh` (`pre-open-dispatch-mode`) — for a
  pre-open anchor whose recorded branch conflicts with its target, files one
  child to bring the branch current.
- `assets/scripts/pr-facts.sh` — the conflicting-PR arm
  (`stale-base-dispatch-mode`), the review-comment feedback arm, and the
  red-check arm (`rc_prepare`) each dispatch a child that may first bring the
  branch current.
- `formulas/mol-refinery-patrol.toml` (`shared-branch-merge-mode`) — the
  refinery's prepare step, which merges `origin/<target>` into the branch in a
  detached prep worktree before the push.
- `formulas/mol-polecat-work.toml` (`rejected-branch-resume-mode`) — a polecat
  resuming a rejected branch merges `origin/<base>` in. An absent `prepare_mode`
  resolves to merge here too, so a dropped stamp cannot select a rewrite.

`prepare_mode` is stamped `merge` on the rework bead before the branch is
touched; the resume path reads it back, and a dispatch site routes a child only
once the stamp reads back on it. `pre-open-rebase.test.sh` holds the two
dispatch sites to the same choice: neither `pre-open-rebase.sh` nor
`pr-facts.sh` classifies any branch shape as `rebase`.

## The push

`shared-branch-push-mode` in `formulas/mol-refinery-patrol.toml` pushes the
prepared head from the prep worktree. It fast-forwards when `origin/<branch>` is
an ancestor of the prepared head and force-pushes with `--force-with-lease` when
it is not — an ancestry test, not a branch-name one. A merge keeps
`origin/<branch>` an ancestor of the result, so the automatic path is always a
fast-forward and the force arm never fires there. The force arm is an
ancestry-guarded safe-push, covering a history rewritten by hand off the
automatic path.
