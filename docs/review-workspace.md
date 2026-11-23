---
name: Review workspace
description: Where a review keeps its worktree and scratch on disk, and when that directory is removed. Read it before changing where a review reads its pinned commit, runs a suite or writes its findings, or how review leftovers in /tmp are reclaimed.
---

# Review workspace

A review run keeps one directory for the whole run, named for the run's root,
`<dir>/gc-review-<root>`, where `<dir>` is `$TMPDIR`, or `/tmp` when `TMPDIR`
is unset. Its steps are claimed by different sessions, so each step that reads
the PR takes a part of the directory of its own, holding a worktree detached at
the head it judges: `triage`, one `lane-<check>` for each lane, and `repair`,
the run's one worktree, from which rule-and-repair pushes the round's fixes onto
the PR's branch under a lease on the head it judged. A lane writes its output
and its evidence beside its worktree, a capture among them, where the round
reads them before it rules, so lanes that build, test or capture never share a
tree. `review-workspace.sh add --root <root>` with `--triage`, `--lane <check>`
or `--repair` makes a part, triage's first, and the hourly reap removes the
directory once the run's root closes. A part read again at another head is
made again there, except the repair's, which holds the round's fixes: a
worktree there at the head the round judged or past it is kept as it stands,
with its commits and its uncommitted edits, which the repair's read prints, and
one at any other commit is refused and kept, which stops the run.

On the old review path, a review bead reads its pinned commit in a detached
worktree and runs there any suite its check calls for. It writes its verdict
body and its finding set beside the worktree, as `findings.md` and `findings.json`, and signoff.sh reads
them from there. A quorum lane writes no file: the block that stores its lane
output on its step bead takes the object inline. It needs no workspace, so a
lane whose gather failed before making one still records its `blocked` output.
The reviewer may also write logs, probe output, or a second worktree at the
base.
All of it lives in one directory named for the review bead,
`<dir>/gc-review-<review-bead>`. `assets/scripts/review-workspace.sh` owns that directory: it
makes the worktree, and it removes the directory when the review ends.
None of it goes in the agent's home, where a pool session's shell starts,
because a home that holds a file gc did not write fails its session's next
start (`assets/scripts/worktree-setup.sh`).

## Scope

**Mandate:** the directory a review works in on disk: where it lives, how a
review gets its worktree, and when and how the directory is removed.

**Boundaries:** the review lifecycle belongs to `formulas/mol-pr-review.toml`
and `formulas/mol-pr-review-lane.toml`, and on the old path to
`formulas/mol-review.toml` and `formulas/mol-review-quorum-signoff.toml`, and
what a review reads, runs and
judges to its check's method. A polecat's per-bead worktree goes at its
hand-off or to the controller's closed-bead reaper
([worktree-reclaim.md](worktree-reclaim.md)). Harness session
scratch, and the per-uid tmpfs quota that every tenant of `/tmp` counts
against, are described in [scratch-reclaim.md](scratch-reclaim.md).

## The directory belongs to the review

A reviewer works across many shells, so no single shell can own the worktree.
A teardown that runs when one shell exits either fires before the later shells
are done with the worktree, or never runs at all when the setup is split
across calls. Each checkout left behind counts against the tmpfs quota, and
exhausting that quota takes every agent's shell output down at once.

So the directory's path depends only on the run's root or the review bead, and
every shell rebuilds it. `review-workspace.sh add --review-bead <id> --oid <commit>`
prints `<workspace>/wt`, a worktree detached at the commit. It makes the
worktree on the first call and returns the same one on every later call at
that commit, so a later block gets the worktree back by running the same line.
Shells that run it at the same moment take turns on a lock, so each of them
gets the one worktree. A worktree found at another commit is rebuilt at the one
asked for. The directory is mode 0700. A name that another user or a symlink
already holds is refused rather than used, because `/tmp` is shared.

`mol-rig-demo` takes a workspace too, named for its demo-request bead, for the
worktree its app runs from, which holds what the rig commits at its HEAD, and
which the sandbox of a rig that keeps it allows where it refuses the rig's own
checkout (`assets/scripts/demo-engine-lib.sh`). It only adds one, and the hourly
reap removes it once the mol closes that bead.

## When it is removed

- **At the verdict step.** mol-review's `verdict-and-drain` and the quorum's
  `synthesize-and-signoff` run `review-workspace.sh remove` once the step chain
  is closed, just before they drain. A verdict that fails and returns the bead
  to the pool leaves the directory in place, so the reviewer who claims the bead
  next gets the same worktree back.
- **By the hourly reap.** `orders/review-workspace-reap.toml` runs
  `review-workspace.sh reap`, city scope, no LLM and no agent. It takes the
  directory of a review run once its root closes, however the run ended, so a
  lane's evidence stays readable until every finding is ruled, and those of
  reviews that closed without reaching the verdict
  step, after a crash, a drain, or a close by another writer such as
  review-sweep.

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
directory has gone, which for a detached worktree can be the only ref to its
commits.
