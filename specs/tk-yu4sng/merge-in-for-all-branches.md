---
name: Every branch is brought current by merge, never rebase
description: Why the refinery brings every branch shape current by merging the target in rather than rebasing, which sites decide it, and what became of the rebase/force-push machinery.
---

# Every branch is brought current by merge, never rebase

## The decision

Operator ruling on `tk-v4ls3v` (accepted 2026-09-27): switch polecat
rework/bring-current to the force-push-free merge-in path. Every branch shape —
per-bead `polecat/*`, shared `integration/*`, a graduation bead — is brought
current with its target by `git merge --no-edit origin/<target>`, never by a
rebase. No branch shape is rewritten, so nothing force-pushes.

`main` is unaffected: `merge.sh` squashes at land (`gh pr merge --squash` is the
only landing verb), so history on `main` stays linear whether or not the branch
was rebased before merge. The rebase bought a linear *branch* view; a merge buys
a stable *review* view, and only the review view is read before land.

## Why merge, not rebase

A rebase rewrites the branch's commits and forces a `--force-with-lease` push to
publish them. On an open PR that push does two visible things:

- It resets GitHub's "changes since last review": the reviewed commits are gone
  from the branch, so the incremental diff a reviewer relies on no longer
  computes against them.
- It drifts every line-anchored inline review comment, because the commits the
  comments were pinned to no longer exist on the branch.

Merging the target in adds a merge commit and keeps the reviewed commits as
ancestors, so both survive. The win is cleanest when the rework *adds* commits;
merely bringing a branch up to date still pulls base changes that can shift some
line anchors, and that is expected. The goal is removing the force-push reset,
not perfect anchor stability.

## Where the choice is made

The classification was one allowlist (`polecat/*` rebases, everything else
merges) restated at four sites and performed at a fifth. All now choose merge
unconditionally:

- `assets/scripts/pre-open-rebase.sh` — `pre-open-dispatch-mode`: dispatches a
  bring-current child for a pre-open anchor whose branch went stale.
- `assets/scripts/pr-facts.sh` — `stale-base-dispatch-mode` (a conflicting PR),
  the feedback arm (a review-comment rework), and the red-check arm
  (`rc_prepare`): each dispatches a child that may first bring the branch
  current.
- `formulas/mol-refinery-patrol.toml` — `shared-branch-merge-mode`: the
  refinery's own prepare step, which *performs* the bring-current in a detached
  prep worktree before the merge/push.
- `formulas/mol-polecat-work.toml` — `rejected-branch-resume-mode`: the polecat
  resuming a rejected branch. It now merges unconditionally, and an absent
  `prepare_mode` resolves to merge, so a dropped stamp can never trigger a
  rewrite.

`prepare_mode` remains stamped on the rework bead (always `merge`): the resume
path reads it, and the read-back guards still confirm a child was fully stamped
before routing. `pre-open-rebase.test.sh` still asserts the two dispatch sites
agree — now by asserting neither classifies a branch `rebase` and both set
`merge`, rather than comparing an allowlist that no longer exists.

## The rebase/force-push machinery

- **The dispatch-side rebase instructions and titles are removed.** A child is
  told to merge the target in and push a fast-forward; the "Rebase … onto …" /
  `--force-with-lease` fix-instruction text is gone, because it would name a path
  the code no longer takes.
- **The refinery's `shared-branch-push-mode` push is kept.** It force-pushes only
  when the prepared head is *not* a descendant of `origin/<branch>` — derived
  from ancestry, not the branch name. A merge keeps `origin/<branch>` an ancestor
  of the result, so the push is always a fast-forward and the force arm never
  fires on the automatic path. It is left in place as an ancestry-guarded
  safe-push, not branch-name dead guidance: if history is ever rewritten by a
  hand off the automatic path, this still publishes it safely rather than with a
  plain `--force`.

## What this supersedes

The `polecat/*`-may-rebase allowlist from `tk-a0hva`
(`specs/tk-a0hva/branch-prepare-mode.md`) and its restatement at the dispatch
sites (`specs/tk-rvspf/dispatch-site-branch-classification.md`). Those records
describe the earlier policy; the live policy is the one here.
