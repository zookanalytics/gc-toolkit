---
name: Gas City search for the per-bead worktree's removal at hand-off
description: Why a polecat's per-bead worktree goes at the refinery hand-off by git and not by gc worktree, what the probe of gc worktree showed, and what reads work_dir once the tree is gone. Read it when judging the work formula's warrant, a proposal to move the per-bead tree onto gc worktree, or a change to what work-submit.sh removes.
---

# Gas City search for the per-bead worktree's removal at hand-off

Read on 2026-11-06 at `gastownhall/gascity` main 005135c33b1f and
`gastownhall/gascity-packs` main 796d7ecd73cf. The probe ran the city's deployed
`gc`, the fork's 1.4.3 at e03752646, in a scratch repository with a bare origin.

## What was decided

| The bead's part | Outcome |
|---|---|
| Remove the tree at hand-off | `work-submit.sh` removes the tree with `git worktree remove`, never forced, once the push is verified, the hand-off written and the step closed. It then deletes the local branch and clears `work_dir`. |
| Create it with `gc worktree ensure` and remove it with `gc worktree cleanup` | Does not fit. `cleanup` removes only a tree merged into the base it was made from, and at hand-off the branch is pushed but unmerged. `ensure` alone would move every tree out of the agent homes and write provenance that nothing reads. `work-setup.sh` keeps `git worktree add`, as core's own variants do. |
| The target page's row | Goes, with the schedule row, from `docs/built-once-target.md`. |

## What Gas City provides, and where it stops

**`gc worktree`** ([reference](https://docs.gascity.com/reference/cli#gc-worktree),
`internal/worktree/worktree.go`):

- `Cleanup` verifies the tree's provenance against the request
  (`verifyProvenance`), and the base ref is one of the fields compared, so
  `--base` must be the ref the tree was made from. It then refuses a HEAD that
  base does not contain (`CleanupErrorUnmerged`). A tree made from `origin/main`
  therefore goes only once its work has merged, and naming the work branch as the
  base fails the provenance check. Only naming the work branch as the base at
  creation would pass both, and that leaves the merged gate nothing to check.
- `Ensure` refuses a path inside any registered worktree
  (`rejectRegisteredWorktreeAncestor`), so a tree under an agent's home cannot be
  made. Every tree would move to a root of its own, such as
  `.gc/worktrees/<rig>/beads/<bead>`.
- `Ensure` returns evidence for the caller to publish on the bead. The controller
  reads the published keys (`worktreeSpecForBead` in
  `cmd/gc/pool_desired_state.go`) to start a pool session inside the tree
  (`verifiedPoolTriggerWorkDir` in `cmd/gc/build_desired_state.go`), and treats a
  bead that carries only `work_dir` and `gc.work_branch` as unmanaged. Publishing
  would change where a rework's session starts. Not publishing leaves the
  provenance in the tree's private git directory, where only `verify` and
  `cleanup` read it, and `cleanup` cannot run at hand-off.

**Core's variants.** `mol-polecat-base`'s `workspace-setup` is a placeholder
each variant overrides. `mol-polecat-commit` and `mol-scoped-work` cut their
trees with `git worktree add` and remove them with `git worktree remove` once the
work is pushed, then unset `work_dir`. They force the removal and fall back to
deleting the directory. The pack never forces it, because a path the push did
not carry is work only that tree holds. No core formula calls `gc worktree`.

**Gas Town's polecat** (`gastown/formulas/mol-polecat-work.toml` in
`gascity-packs`) detaches its tree at hand-off and deletes the local branch, as
the pack did until this change. Once a squash merge deletes origin's branch and a
fetch prunes the tracking ref, no ref reaches the detached tree's commits, and the
controller's closed-bead reaper (`reapClosedBeadWorktrees`) holds such a tree for
good.

## The probe

Each call ran in a scratch repository with the deployed binary, on a tree made
by `ensure` from `origin/main`, with one commit pushed to origin's branch:

| Call | Result |
|---|---|
| `cleanup --base origin/main` | refused, `unmerged_commits`: HEAD is not merged into `origin/main` |
| `cleanup --base origin/<branch>` | refused, `ownership_mismatch`: base ref is `origin/main`, want `origin/<branch>` |
| `ensure` for a second bead on a branch the first tree holds | refused, with git's own `is already used by worktree at '<path>'` on stderr, rolled back |
| `ensure` with a path under a registered worktree | refused, `is inside registered worktree` |
| `git worktree remove` of the pushed tree | removed |

## What reads `work_dir` once the tree is gone

- `work-setup.sh` makes a fresh tree when `work_dir` names none. A rework then
  tracks origin's branch, because the hand-off deleted the local one.
- `work-enter.sh`, `rig-checks.sh` and `self-review-check.sh` read it only inside
  a run, after `workspace-setup` has recorded the run's tree.
- `duplicate-sweep.sh`, `bead-rehome.sh` and `live-work.sh` read it as one of
  several marks of work done, and `branch` stays on the bead.
- The witness's salvage reads it for a bead whose owner died. A handed-off bead
  is the refinery's and open, so salvage does not reach it.
- In Gas City, the close's work-record gate runs git in `gc.work_dir`, never in
  `work_dir` (`RepoDirFor` in `internal/workrecord/repo_dir.go`). The hook claim
  skips a recorded tree that no longer resolves (`hookClaimWorkerTrees` in
  `cmd/gc/cmd_hook_claim.go`). The reaper holds a tree that a bead's `work_dir`
  names while the bead is open, and a cleared key holds nothing.
- The hook claim also reads the cleared key. On a bead that records no work
  checkout under either key, it writes the claiming session's directory as
  `gc.work_dir` (`hookClaimIdentityPatch` and `hookClaimRecordsNoWorkDir` in
  `cmd/gc/cmd_hook_claim.go`). No session hook-claims a handed-off bead: the
  refinery lists the work assigned to it, and a re-dispatched run's polecat
  claims the run's steps. tk-1tfzr71.12, handed off and merged on 2026-11-06,
  carries no `gc.claimed_at`. A bead a polecat claims itself, such as a rework
  child, already records no `work_dir` when it is claimed, and no bead claimed
  on this host that records a branch carries `gc.work_dir` (read 2026-11-06).

## The bead's other questions

- **The message `yield_to_tree` parses.** Creation stays on `git worktree add`, so
  nothing changes. The probe shows `ensure` would pass git's message through.
- **Whether a Codex session may write outside its home.** No tree moves, so the
  question does not arise.
- **The authority row.** `docs/authority-map.md` gives `work-submit.sh` the
  removal, with what it may never remove.
- **Trees on disk from earlier hand-offs.** No second path is needed, because
  `git worktree remove` needs no provenance. A rejection that resumes on such a
  tree reuses it, and its next hand-off removes it. A tree no run reuses stays
  detached as before, for the pack's reaper while it lasts.

## What it costs

A run dispatched again on the same bead, such as a rejected branch's resume, makes
a fresh checkout and runs the rig's setup command, where it used to reuse the
detached tree its last run left. A rework child, a bead of its own, already made
its own tree, because the anchor's detached tree held no branch to adopt. The
store-only exit and the `auto_push=false` halt keep
their trees: the halt's tree holds the unpushed work, and the store-only tree
holds a commit main already has, which the reaper takes once the bead closes.
