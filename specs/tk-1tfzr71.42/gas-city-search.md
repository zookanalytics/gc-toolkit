---
name: Gas City search and count for retiring the pack's worktree reaper
description: What tk-1tfzr71.42 read before deleting worktree-reap.sh. It covers what the controller's closed-bead reaper and core's prune-branches order cover, the count that dropped the pack's branch pass too, and the pins that let the controller take the trees handed off before the hand-off removed its own. Read it when judging whether the pack should delete polecat/<bead-id> branches, or when a tree the controller holds as unreachable turns up.
---

# Gas City search and count for retiring the pack's worktree reaper

Read on 2026-11-06 at `gastownhall/gascity` main bfd72756e. The census ran
read-only on the live city between 16:15Z and 16:40Z, with the pack at
3e478cff8, whose hand-off removes its own tree. The pins were written at
16:41:07Z, and a second pass at 17:01:17Z pinned the trees the first one left
out.

## What was decided

| The bead's part | Outcome |
|---|---|
| `worktree-reap.sh`, its test, its order | Deleted. The controller's closed-bead reaper, which tk-1tfzr71.41 turned on in this city, takes a closed bead's tree. Their rows leave `tools/deletion-plan.tsv` and `docs/built-once-target.md`. |
| The branch pass | Dropped with them, under the bead's own rule for a pass whose work is a handful a month. The branches it would have deleted stay, and `docs/worktree-reclaim.md` says so. |
| Trees handed off before the hand-off removed its own | Pinned with archive tags rather than waited out for 24 hours, so the controller takes each one once its bead closes, however late that is. |
| `docs/worktree-reclaim.md`, and the pages that named the script | Rewritten to what the controller does, what stays, and how to release or restore a tree. |
| tk-hf8o3h9's rows | `docs/authority-map.md` gains rows for the controller's reaper, for `work-setup.sh`'s removal of a tree it has just added, for `review-workspace.sh`, for `refinery-workspace.sh` and for the witness's orphan teardown. |
| tk-saq7vn5, a shellcheck finding in the script | Goes with the file. |

## What Gas City provides for the branches

- The controller's closed-bead reaper removes trees and no ref.
  `reapClosedBeadWorktrees` in `cmd/gc/bead_worktree_reaper.go` calls only
  `WorktreeRemove(worktreePath, false)`.
- Core's `prune-branches` order (`internal/bootstrap/packs/core/orders/prune-branches.toml`,
  every 6 hours) runs `assets/scripts/prune-branches.sh`. It lists only `gc/*`
  branches, and deletes one with `git branch -d` when origin's main contains it or
  its remote-tracking branch is gone. `git branch -d` refuses a branch that is not
  merged into its upstream or HEAD, and a squash-merged tip never is. So renaming
  the work branches to `gc/*` would not get them deleted either.

Nothing in Gas City deletes a `polecat/<bead-id>` branch, so a pass that does
would have to stay as pack code. The count below is why it does not stay.

## The count

The hand-off deletes its tree's local branch. So a branch the pass could still
delete is one left by a run that left its tree on its branch: a store-only exit,
a halt before the push, a run that ended before its hand-off, or a tree the
hand-off kept. The pass deletes only a closed bead's branch whose tip the default
branch contains, or whose bead id a commit subject there names.

- **Now.** The city's repositories hold 20 local `polecat/<bead-id>` branches, 14
  of them in this rig. 12 are checked out in a tree. Each of the other 8 is one
  the pass keeps: 7 name a closed bead whose tip the default branch neither
  contains nor names in a subject, and 1 names an open bead. The pass had nothing
  to delete.
- **The last 30 days.** The pack's archive tags record 19 trees removed while
  still on a `polecat/` branch, each of which left that branch for the pass. In 8
  of them a rework or rebase child stood on its predecessor's branch, a case
  `work-submit.sh` now cleans at the child's own hand-off. 15 beads filed since
  2026-10-07 carry `halt_reason=store_only`, 8 of them in this rig. 12 of those
  recorded a branch, and 11 of those were cut from the default branch.
- **What that leaves the pass.** A store-only exit leaves its branch at a commit
  the default branch already has, since `store-only-exit.sh` refuses a run with a
  commit ahead of its base. So the pass deletes that branch once the bead closes.
  The branch of a halt, or of a run that ended early, carries work that never
  landed, which the pass keeps. That leaves about 11 branches a month city-wide,
  6 of them in this rig, each one ref to a commit main already has.

That is a handful a month per rig, so the pass goes, and those refs stay. A ref
costs a few bytes, and one left by a run that never landed keeps the commits its
tree holds reachable, so the controller can still take the tree.

## Trees handed off before the hand-off removed its own

Until #1413 the hand-off detached its tree and deleted the local branch. Once
the PR squash-merges, origin deletes its branch, and the next `git fetch --prune`
drops the remote-tracking branch. `work-setup.sh` and core's `prune-branches`
both run one. Then no ref reaches the tree's commits, and the controller holds
the tree for good (`HasUnreachableCommitsResult` in `internal/git/git.go`).
`worktree-reap.sh` pinned such a tree with a tag and removed it 24 hours after
its bead closed. So the bead asked this change to land 24 hours after its
blockers, with one run by hand for what was left.

That wait covers only trees whose beads close within it. At 16:30Z, 20 trees in
five rigs belonged to open beads handed off before #1413, 13 of them in this rig.
Only `origin/polecat/<bead-id>` reached each of them, plus another remote ref for
a few. Their beads close whenever their PRs merge.

So at 16:41:07Z each per-bead tree whose HEAD no local branch or tag reached got
an annotated `archive/worktree/<bead>@<sha12>` tag, the tag `worktree-reap.sh`
wrote before each removal. That covered 37 trees in six rigs, 17 of them in this
rig. Remote-tracking refs alone reached 27 of them, and no ref reached the other
10: 8 dirty trees in a suspended rig, which both reapers hold anyway, and 2
closed beads' trees in this rig. The pins stay local, because no rig sets
`push.followTags` and no origin holds an `archive/worktree` tag.

That pass left out a detached tree that a local branch still reached, and the
hand-off now deletes such a branch. A rework child works the same
`polecat/<bead-id>` branch in a tree of its own, and its hand-off removes that
tree and deletes the branch, after which only origin reaches the old tree's
commits. By 17:01Z one tree in this rig had come to this, and 7 more were
reached only through a branch checked out in another bead's tree, whose hand-off
deletes it. So at 17:01:17Z every detached per-bead tree whose HEAD no tag
reached got the same pin: 8 trees in three rigs, 3 of them in this rig. A re-run
then found no detached per-bead tree without a pin. A tree on a branch needs
none, because git refuses to delete a branch that a tree has checked out. With
both passes in place, no tree depends on `worktree-reap.sh`, so the change can
land at any time.

The pins cannot cover a run whose submit step text predates #1393, because that
text still detaches the tree and deletes its branch. 3 such steps are open in
this rig, poured on 2026-10-10, and 4 in a suspended rig. If one of them runs,
the release recipe in `docs/worktree-reclaim.md` frees its tree.

## Limits of this record

- The pass's own output went to no log, so the 30 days are read from archive
  tags and store fields rather than from the deletions it made.
- One month is a short window. A month with many store-only exits would add more
  refs, at the same cost of a few bytes each.
