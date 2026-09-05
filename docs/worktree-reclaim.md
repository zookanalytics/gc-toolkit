# Worktree reclaim

A polecat creates a git worktree per bead and records the path in
`metadata.work_dir`. Nothing removes it when the bead closes: the refinery
merges and moves on, the witness inventories and flags but does not delete,
and the polecat drains. Every checkout is a full working tree, so the
directories are a monotonic floor under the disk, and the only reclaim is an
operator noticing the pressure and doing it by hand.

The pressure arrives faster than anyone notices. On this city the registry
grew from 351 worktrees to 790 in five weeks, `.gc/worktrees/gc-toolkit` from
1.3G to 9.2G, and the disk reached 99% used with 3.2G free. A full disk kills
Dolt, which makes `bd` queries return false-empty results, so the failure
presents as a city with no work rather than as a disk alarm.

## What the reaper does

`orders/worktree-reap.toml` runs `assets/scripts/worktree-reap.sh` hourly,
`scope = "city"`, no LLM and no agent. It enumerates `git worktree list` over
every rig repo and the town repo, because a worktree living under one rig's
tree can be registered in another repo's git dir and only the registry knows
which.

A worktree is removed when all of these hold:

- some bead names its path in `metadata.work_dir`, and none of the beads
  naming that path is still live
- no live bead names its branch, and no open pull request has that branch as
  its head
- the newest close among the beads naming it is older than
  `WORKTREE_REAP_CLOSED_AFTER` (24h)
- `git status --porcelain` is empty
- it is not an agent home, a session `work_dir`, or a live process's cwd
- it is not locked, not the main worktree, and not the parent of another
  registered worktree

"Live" is read from the bead-status contract, not a list fixed in the reaper.
`gc bd statuses` sorts every status into a category, and one category, `done`,
means the work is finished and its checkout disposable. Every other status is
live: `deferred` is frozen for later, `pinned` stays open indefinitely,
`hooked` is on an agent's hook, and a checkout any of them names is still
someone's. The reaper asks each store for every non-`done` status it defines,
so a status added to `bd` or configured on a rig protects its worktrees the
day it exists. The reap side keys on `closed` alone — the one done status with
a defined close time — so a custom done status leaves a worktree unreaped
rather than reaped while live. A store whose contract cannot be read is skipped
whole, and if none can be read the pass refuses.

The identity chain is `metadata.work_dir`, so the reverse lookup is exact path
equality and no bead id is ever parsed out of a path or a branch name. The two
disagree in practice: a rework child stands on its predecessor's branch while
keeping its own directory, so `worktrees/tk-ok9t2` is checked out on
`polecat/tk-z4aka`, and either name alone resolves to the wrong bead.

Both branch questions are asked, for the same reason. The branch the checkout
is on and the branch its beads recorded are not always the same ref, and
either being live holds the tree. Asking the ledger for live beads on the
branch is what covers a branch in the pre-open codex gate, which is live work
carrying no pull request at all.

## Removal is reversible, not gated

Deleting a worktree is destructive-looking, and the reflex is to route it to a
human for confirmation. That reproduces the gap the reaper exists to close:
the reclaim still waits for someone to notice.

Instead every removal is pinned first. The tip is written as an annotated
`archive/worktree/<bead>@<sha>` tag carrying the path, the bead, the branch,
and the command that restores it. Restoring is
`git -C <repo> worktree add <path> <tag>`. If the tag cannot be written the
worktree is not removed — no pin, no removal.

The pin is load-bearing rather than ceremonial. Roughly half the registry is
detached-HEAD merge residue, and a detached worktree's HEAD is the only ref
reaching its commits, so removing the checkout would leave them unreachable.
Squash-merged work has the same shape from the other direction: the branch tip
is never an ancestor of the default branch, so landed work reads as unpushed.

The same pin guards registry litter. A worktree whose directory was deleted out
from under git leaves an admin `HEAD` behind, and `git worktree prune` reclaims
that entry by dropping the `HEAD` — for a detached entry the only ref its
commits have, dropped immediately with no expiry to make it safe. So each
prunable tip is pinned by an `archive/worktree` tag before the prune runs, and
a dry run prunes nothing at all.

## What the reports mean

Reclaim is reported as a count of removals plus the free space on the
filesystem holding the first repo. That figure moves for every other writer on
the host too, so it is labelled as the filesystem's rather than as the pass's
yield.

The count is honest because each removal is asserted on disk afterwards.
`git worktree remove` can return success and leave the directory standing;
those are counted as failures and named, because a pass that freed nothing
would otherwise print the same summary as one that freed everything.

Removal itself runs without `--force`, so git's own dirty check is the last
gate and it runs after the status probe rather than instead of it.

## Rails

An agent home is never removed. It is created by `worktree-setup.sh` at the
agent's configured `work_dir` before any session exists and it outlives every
session that runs in it, so a stopped pool member still owns its home and no
liveness probe can see that. The roster states the shape as a path template,
which becomes an anchored regex whose substitutions widen to one path
*segment*. A shell glob cannot express that: `*` crosses `/`, so
`.gc/worktrees/*/polecats/*` would also match every per-bead worktree nested
under a home, and the reaper would protect the whole population it exists to
take.

Live processes are read with `find /proc -maxdepth 2 -name cwd -type l
-printf '%l\n'`, and a live cwd protects every worktree containing it, not
only an exact path match. A shell glob over `/proc` is not an acceptable
substitute: it stats every candidate and drops what it cannot read, and
passing the survivors to `readlink` in bulk drops more still. Measured here,
`find` reported around 360 cwds on every sample while the pair returned
between 27 and 180, and the pair missed a process started a moment earlier in
3 of 15 trials where `find` missed none in 42.

A repo whose open-pull-request listing fails is held whole for the next pass
rather than reaped without the check. That gate is the backstop for a ledger
that already disagrees with reality, so failing open would drop it exactly
where it earns its place. A ledger that answers nothing anywhere, or a
registry that enumerates nothing, is treated the same way: a broken lookup is
not an empty city, and every path would otherwise read as unclaimed.

Nested worktrees drain leaf-first. A worktree that is the parent of another
registered worktree is held, so the child goes this pass and the parent
becomes eligible on the next.

`assets/scripts/worktree-reap.test.sh` is the regression suite, hermetic
against a synthetic city in a tempdir: real git and a real filesystem, with
only `gc` and `gh` stubbed. Every keep is asserted alongside a take in the
same run, because a pass that filtered everything and a pass that filtered
nothing print the same summary.

## Operating it

```bash
assets/scripts/worktree-reap.sh --dry-run   # the full plan, every path
assets/scripts/worktree-reap.sh             # reap, one summary line per repo
```

`--dry-run` prints every path it would take rather than a sample: it is the
operator's review surface, and a truncated list is not something anyone can
approve.

`WORKTREE_REAP_CLOSED_AFTER` (seconds, default 24h) is the grace after a
bead's close. `WORKTREE_REAP_BUDGET` (default 420s) bounds the pass; what it
yields is reported as untaken and the next pass takes it.
`WORKTREE_REAP_TAG_PREFIX` (default `archive/worktree`) names the pin
namespace, and `WORKTREE_REAP_REPOS` overrides the rig list with explicit repo
paths.

To restore a reaped worktree, read the tag and run the command in it:

```bash
git -C <repo> tag -l 'archive/worktree/*'
git -C <repo> cat-file -p archive/worktree/<bead>@<sha>
git -C <repo> worktree add <path> archive/worktree/<bead>@<sha>
```

## What it does not touch

The reaper removes checkouts, not refs. A branch is left as it stands, which
is what makes an attached worktree restorable without consulting a tag at all.
Harness scratch is `scratch-reap`'s (docs/scratch-reclaim.md); the two are
separate tenants of separate roots and neither reclaims the other's.
