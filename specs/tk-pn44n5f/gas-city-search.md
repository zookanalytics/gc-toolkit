---
name: Gas City search for which bead a prep worktree holds
description: The search the arch check asks for before the pack adds surface of its own. What Gas City, the packs it publishes and bd ship for recording which bead and branch a worktree was set up for, read at named upstream commits, and why none of it covers the refinery's detached prep worktree, so the pack keeps its own staging record under a warrant. Read it when checking whether the refinery still needs that record.
---

# Gas City search for which bead a prep worktree holds

This change adds pack surface that records which bead and branch the
refinery's prep worktree was staged for, and reads that record back for the
steps that push or record the prepared head. So the arch check asks what Gas
City already ships for that need
([review-arch.md](../../docs/review-arch.md#the-checks), checks 1 and 2).

Gas City ships one owner that records which bead and branch a worktree belongs
to, `gc worktree`. It keeps that record only for a workspace that carries work
on a branch of its own, and its removal refuses the states the refinery
discards. Neither the packs Gas City publishes nor bd ship anything closer. The
pack keeps its own record, under the warrant this change adds to
[warrants.md](../../docs/warrants.md#prep-worktree-staging-record).

## The surface and the need

- `refinery-workspace.sh stage --work <bead>` records the bead and the branch
  it staged in a file in the prep worktree's private git dir,
  `gc-refinery-staged`.
- `refinery-workspace.sh held` prints the bead and the branch that record
  names, and `refinery-workspace.sh verify --work <bead> [--branch <branch>]`
  succeeds only when it names the bead, and the branch when one is given.
- The `prep-staged-work` block that opens `mol-refinery-patrol`'s merge-push
  step takes the bead and the branch the step acts for from `held`, and
  `direct-merge-push.sh` runs `verify` before it lands the prepared head.

The need is a record of which bead and branch the head in the prep worktree was
staged for, read by whatever pushes or records that head. The agent's shell
carries a `WORK` and a `BRANCH` of its own, while the prep worktree holds
whichever bead the rebase step staged last.

The prep worktree is one path that every iteration reuses,
`<rig git dir>/gc-refinery-prep`, inside the rig's main checkout, in its git
dir. The rebase step first removes whatever an earlier iteration left there,
whichever bead staged it. It then adds the worktree detached at
`origin/<branch>`, so staging creates and deletes no branch. A merge brings the
head current, and a conflicted merge is aborted. The gate runs its checks in
the worktree. The head is then pushed to the bead's branch, or onto the target
by commit id, or it is given up. The worktree is removed in whatever state the
iteration left it, at the end of the iteration or by the next stage.

## Where the search looked

All three were read on 2026-10-24:

- Gas City at main `47b36c3a0f1b`: its documentation, its engineering docs, the
  `core` pack it bundles, and the source of its worktree owner and of the
  controller and reaper code that reads worktrees. None of that has changed
  since `ba3ed611de71`, the commit the review cited.
- Every pack Gas City publishes, at `8a93f3d12d92`.
- bd at main `12c20a6e8170`.

The search covered worktree provisioning (`gc worktree`, `worktree add`), a
worktree's ownership record and provenance, and every flow that pushes a
prepared head (`push origin HEAD:`, `--force-with-lease`, `merge --ff-only`),
refinery and merge-queue flows included. Each part the search found was read.

## What Gas City ships near the need

### gc worktree

[`gc worktree`](https://docs.gascity.com/reference/cli#gc-worktree) is, in the
CLI reference's words, "the single transactional owner for workspace
provisioning". `ensure` creates a worktree and writes its provenance into the
worktree's private git dir: the bead it is bound to and that bead's store, the
branch, the base ref and commit, the creator, the owner, a generation, a
lifecycle state and an attempt id. `verify` succeeds only when that provenance
matches every field its caller names. That is the record this change needs.
The owner sets four conditions on a worktree it records, and the prep worktree
meets none of them.

- **An attached branch.** The worktree must have "the bead's uniquely named
  branch checked out on an attached HEAD (never detached)". The `worktree`
  package's `Verify` fails a detached HEAD. `Ensure` either creates the branch
  from the base or attaches an existing branch as it stands. The prep worktree
  is detached so that it stages `origin/<branch>` exactly. The bead's own local
  `polecat/<bead>` would be attached as it stands, which can be behind origin,
  and git refuses to check it out while a polecat's worktree has it. A branch of
  the refinery's own for each staging would be one more ref to create and to
  delete, and `cleanup` deletes no branch.
- **A path outside every working tree, under a per-rig root.** The path must be
  a direct child of the `--root` the caller names (`validateManagedPath`), and
  a path inside any registered worktree is refused
  (`rejectRegisteredWorktreeAncestor`). The rig's main checkout is a registered
  worktree, and the prep worktree lives in its git dir, so its path is refused.
  A path under `.gc/worktrees/<rig>/` is where Gas City's bead-worktree reaper
  (`reapClosedBeadWorktrees`) looks for per-bead worktrees to remove once their
  bead closes.
- **Removal only of clean, merged work.** `cleanup` "refuses dirty worktrees,
  commits reachable from no branch, tag, or remote-tracking ref, and commits not
  merged into --base", and "there is no force mode". The refinery removes its
  prep worktree after a gate whose checks can leave files in it, and after a
  head that landed on the target by commit id, which is not merged into the
  branch it was staged from. To make either removable, the pack would first
  reset and clean the tree itself, which is the force the owner withholds,
  done by hand.
- **Removal only by the attempt that created it.** `cleanup` needs the attempt
  id that the creating `ensure` returned, and every field the worktree was
  created with. The rebase step clears a leftover of an interrupted iteration
  without knowing which bead staged it. The only place that leftover's attempt
  id and fields are kept is the owner's private provenance file.

The owner's evidence also has one place on the work bead. `gc.work_dir` and the
`gc.worktree_*` keys describe one worktree, and the controller's
`worktreeSpecForBead` rebuilds one spec from them to verify the directory it
launches a pool session into. The bead the refinery prepares already names the
polecat's worktree in its `work_dir`, and `worktreeSpecForBead` refuses a bead
whose `gc.work_dir` and `work_dir` differ. So a prep worktree bound to the same
bead could not publish its evidence there.

### The core pack

No formula or order in `core` calls `gc worktree`. Its `mol-polecat-commit`
formula adds a polecat's worktree with `git worktree add --detach`, and removes
it with `git worktree remove --force`.

### Merge queues

The [Gastown command map](https://docs.gascity.com/reference/gastown-command-map)
gives a merge queue "no direct generic `gc` command", and says
"Gastown-style merge queue behavior lives in the pack and formulas, not a
generic platform namespace".

### The packs Gas City publishes

No published pack calls `gc worktree`.

- `gastown`'s `mol-refinery-patrol` stages each bead's branch as one local
  `temp` branch in the refinery's own checkout. It lands a direct merge through
  a temporary detached worktree, which it removes with `--force`. Nothing
  records which bead `temp` holds, so its push takes the branch from the
  agent's shell, as this pack's push did before this change.
- `gascity`'s `do-work` formula, which `gstack`, `compound-engineering`,
  `bmad` and `superpowers` extend, prepares each item's worktree at a path
  named for its source anchor. It adds the worktree detached at the remote
  default branch with plain git, and records the path in the anchor's
  `work_dir`. The path names the bead and not a branch, and the refinery's
  push needs both, so naming the prep worktree for its bead would not replace
  the record.
- `pr-review`'s `mol-adopt-pr` stages each pull request in a worktree at a path
  named for it. A re-run trusts a worktree it finds there only when the tree is
  clean and its checked-out branch is the expected one. That identity is the
  attached branch, which a detached prep worktree does not have.
- `github`'s `mol-github-fix-issue` and `discord`'s `mol-discord-fix-issue` add
  a detached worktree for one issue bead with plain git, and record its path and
  its fix branch on that bead, in `work_dir` and `branch`.
- The rest of the hits push or fast-forward the branch checked out where they
  run. `gastown`'s `mol-witness-patrol` salvages an orphaned worktree's work
  onto the branch that worktree has checked out, and refuses a detached one as
  an ambiguous push, so it too knows a worktree by its attached branch.
  `pr-review`'s `mol-adopt-pr` and `mol-pr-merge-only` push a rebased or
  squashed pull request branch with `--force-with-lease`. `gastown`'s
  `mol-polecat-work` and `worktree-setup.sh` fast-forward a local branch, and
  `gstack`'s skills fast-forward gstack's own checkout. gstack's `ship` skill
  pushes the agent's branch with a plain `git push`, never a force push.

### bd

bd's `worktree create` runs `git worktree add -b <branch>`, or checks out the
branch when it already exists, adds the path to `.gitignore` when it sits
inside the repository, and records no bead. Its
`worktree info` reports the path, the branch and the beads configuration.

## What the pack keeps

The pack keeps its record and the verbs that read it. The record is one file
in the worktree's private git dir, where `gc worktree` keeps the provenance of
a worktree it owns, and it names only the bead and the branch. git deletes it
with the worktree, so no record outlives the staging it describes. The warrant
names the trigger that moves the record's readers onto Gas City: an owner that
binds a detached worktree to a bead and removes its own attempt in whatever
state the iteration left it.
