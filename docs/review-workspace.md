---
name: Review workspace
description: Where a review keeps its worktree and scratch on disk, and when that directory is removed. Read it before changing how a review runs its tests or how review leftovers in /tmp are reclaimed.
---

# Review workspace

A review runs the suites at its pinned commit in a detached worktree, and the
reviewer may also write logs, probe output, or a second worktree at the base.
All of it lives in one directory named for the review bead,
`<dir>/gc-review-<review-bead>`, where `<dir>` is `$TMPDIR`, or `/tmp` when
`TMPDIR` is unset. `assets/scripts/review-workspace.sh` owns that directory: it
makes the worktree, and it removes the directory when the review ends.

## Scope

**Mandate:** the directory a review works in on disk: where it lives, how a
review gets its worktree, and when and how the directory is removed.

**Boundaries:** the review method itself belongs to `formulas/mol-review.toml`
and `formulas/mol-review-quorum-signoff.toml`. A polecat's per-bead worktree is
worktree-reap's ([worktree-reclaim.md](worktree-reclaim.md)). Harness session
scratch, and the per-uid tmpfs quota that every tenant of `/tmp` counts
against, are described in [scratch-reclaim.md](scratch-reclaim.md).

## The directory belongs to the review

A reviewer works across many shells, so no single shell can own the worktree.
A teardown that runs when one shell exits either fires before the later shells
are done with the worktree, or never runs at all when the setup is split
across calls. Each checkout left behind counts against the tmpfs quota, and
exhausting that quota takes every agent's shell output down at once.

So the directory's path depends only on the review bead, and every shell
rebuilds it. `review-workspace.sh add --review-bead <id> --oid <commit>`
prints `<workspace>/wt`, a worktree detached at the commit. It makes the
worktree on the first call and returns the same one on every later call at
that commit, so a later block gets the worktree back by running the same line.
Shells that run it at the same moment take turns on a lock, so each of them
gets the one worktree. A worktree found at another commit is rebuilt at the one
asked for. The directory is mode 0700. A name that another user or a symlink
already holds is refused rather than used, because `/tmp` is shared.

## When it is removed

- **At the verdict step.** mol-review's `verdict-and-drain` and the quorum's
  `synthesize-and-signoff` run `review-workspace.sh remove` once the step chain
  is closed, just before they drain. A verdict that fails and returns the bead
  to the pool leaves the directory in place, so the reviewer who claims the bead
  next gets the same worktree back.
- **By the hourly reap.** `orders/review-workspace-reap.toml` runs
  `review-workspace.sh reap`, city scope, no LLM and no agent. It takes the
  directories of reviews that closed without reaching the verdict step, after
  a crash, a drain, or a close by another writer such as review-sweep.

The reap reads every `gc-review-*` entry this user owns directly under the temp
directory, and under `/tmp` as well. It removes an entry only when no process
has its working directory or an open file inside it, and one of these holds:

- The entry is named `gc-review-<id>` for a bead whose prefix is one of the
  city's bead prefixes, and that bead is closed. The bead is read from the store
  of the rig its prefix names.
- The entry names no such bead, or names one the ledger no longer has, and
  nothing inside it has changed for 24 hours. This is what takes scratch that a
  reviewer wrote outside the directory under an improvised `gc-review-` name.

A bead that is not closed holds its directory at any age, and so does a bead
whose status cannot be read, because an unreadable ledger is not a closed
review. An entry whose age cannot be read is held too. The process check is an
`lsof` listing of the working directory and open files of every process this
user can see, on Linux and on macOS, read fresh before each removal. A listing
that fails, or that names no file at all, not even the reaper's own, is a
broken probe rather than an idle host, so it holds everything. If the city's
rigs cannot be read, the pass removes nothing and exits 1.

## How a directory is removed

Each git worktree inside the directory is removed with `git worktree remove`,
so its registration goes with it, and then the directory is deleted.
`review-workspace.sh` never runs `git worktree prune`, because a prune is
repository-wide and would drop the admin `HEAD` of every other worktree whose
directory has gone before worktree-reap pins that `HEAD` with an archive tag.
