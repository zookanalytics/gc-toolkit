---
name: Worktree reclaim
description: The order that takes back the per-bead worktrees and local branches finished work leaves in a rig checkout — the two gates, why a closed bead outranks tip-reachability under squash-merge, and what holds a worktree.
---

# Worktree reclaim

A polecat pours a git worktree at `<session-worktree>/worktrees/<bead-id>` on
branch `polecat/<bead-id>`, pushes the branch, and drains. Nothing takes either
one back. GitHub's `delete_branch_on_merge` clears the remote branch and the
refinery closes the bead, so both ends of the work report finished while the
local clone keeps the scaffolding: one worktree and one branch per work item,
for as long as the rig has existed.

The worktrees are where the disk goes. A rig checkout carries a full tree per
worktree, so the directories outweigh the repository they came from by orders
of magnitude, and they accumulate at the rate the pool completes work.
Exhausting the disk is a city-wide outage rather than a rig-local one: the
Dolt data plane fails on ENOSPC, and `gc hook` then answers a false `no_work`
to every agent that asks.

## What the reaper does

`orders/worktree-reap.toml` runs `assets/scripts/worktree-reap.sh` hourly,
`scope = "city"`, no LLM and no agent. Each non-HQ rig gets one pass, bounded
by `WORKTREE_REAP_BUDGET` (480s). A pass skipped or cut short by its budget
costs only the reclaim the next pass takes instead.

Two gates, and their order is the point.

**A closed bead is the authority.** The refinery closes a work bead only from
merge-push, on a verified merge, so closure is the statement that the work
landed. **Tip-reachability from the default branch is the confirmation, not the
gate.** The merge is a squash, so the branch's own commits are never ancestors
of the default branch and a branch whose content is fully in `main` reads as
unmerged. A reaper gated on reachability alone refuses nearly everything it
should take.

## What holds a worktree

- The bead named by its directory is `open`, `in_progress` or `blocked`.
- It holds content that exists nowhere else — a modification, an addition, an
  untracked file, or an ignored file the working tree is the only copy of. git
  omits ignored files from status by default, so the check asks for them.
- A running process has its cwd inside it. `/proc` is read once per pass; the
  signal is one-directional, since a worktree nobody stands in owns no entry,
  so it only ever protects.
- The rig's ledger did not answer. A lookup that errors holds the rig, and so
  does an empty open-bead list: a store that is down answers in exactly that
  shape, and every bead would then read as closed.

A pure deletion does not hold a worktree. The content is in `HEAD`, so removing
the directory loses nothing, and holding on one costs the whole reclaim for
exactly the oldest trees: a file deleted from the default branch leaves every
worktree cut before that commit permanently dirty, and no later pass can ever
clear it. `git worktree remove` refuses a dirty tree either way, which is why
the removal passes `--force`; the gates above are what make that safe, since
git's own check cannot tell a deletion from an edit.

## What holds a branch

A branch checked out in a worktree is never touched — the worktree holding it
either survived a gate above or was never a candidate.

The branch pass owns one family: `polecat/<bead-id>`. A branch that names no
bead — an agent session branch (`gc-<agent>-<hash>`), a long-lived
`claude/research-*` or `roadmap` branch, a design-doc trio — is left alone
whatever its merge state.

A `polecat/<bead-id>` branch is held while its bead is `open`, `in_progress` or
`blocked`. A tip already an ancestor of the default branch does not override a
live bead: a resumable work item's local ref is not disposable because its
content happens to have reached `main`.

Once the bead is no longer live the branch goes — when its tip is an ancestor
of the default branch (git's own definition of merged, which discards no
commit), or when the bead id appears in a commit message on the default branch.
That squash commit is what "the content landed" looks like once the tip test
has stopped working, since the branch's own commits never become ancestors. A
closed bead with no such commit — folded into a sibling's PR, closed as a
duplicate, closed by hand — keeps its branch.

## Scope

The worktree pass takes exactly the shape `mol-polecat-work` pours: a directory
whose name parses as a bead id, directly inside a directory named `worktrees`.
An agent's own session worktree, a review worktree under `/tmp`, and the rig
checkout all fail that test and are never candidates. The branch pass takes
only `polecat/<bead-id>` branches — held while their bead is live, taken once
it is not; a branch that names no bead is left alone.

Origin-side cleanup is not the reaper's. `delete_branch_on_merge` covers the PR
path, and a pushed branch that never became a PR stays for a human.

`assets/scripts/worktree-reap.test.sh` is the regression suite, hermetic
against real git repositories in a tempdir and a stub `gc` — no city, no
network.

## Operating it

```bash
assets/scripts/worktree-reap.sh --dry-run          # the plan, every rig
assets/scripts/worktree-reap.sh --rig <name>       # one rig
assets/scripts/worktree-reap.sh                    # reap, one line per rig
```

`--dry-run` is the cruft report: in steady state it takes nothing. Every run
prints what it took and what it held, per rig and then in total, so a rig whose
ledger is refusing to answer is visible in the order log rather than only as an
absence of reclaim.
