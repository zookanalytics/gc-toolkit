---
name: Stale-branch triage — implementation decisions and divergences from the proposal
description: Why the sweep is modeled on worktree-reap rather than the recover-stranded-branches.sh the proposal names, which of the proposal's premises were stale against the current pack, and why introducing the pack's first direct origin ref mutation is sound.
---

# Stale-branch triage: what was built, and where it departs from the proposal

The proposal is `specs/tk-wfufb9/stale-branch-triage.md` (on the unmerged branch
`polecat/tk-wfufb9`). Its intent — classify origin branches with no live owner,
auto-dispose what is decidable, archive the rest reversibly, escalate only the
contested — is what shipped. Three of its concrete implementation anchors were
stale against the current pack, because it was written two days before the
workflow-shaped rewrite (#465) that removed them. Each was re-derived against the
code rather than trusted.

## Divergences from the proposal

- **Model: `worktree-reap.sh`, not `recover-stranded-branches.sh`.** The proposal
  names `recover-stranded-branches.sh` as the nearest sibling to copy; #465
  deleted it with the other healers. The current nearest sibling is
  `worktree-reap.sh`, which already implements the reversible pattern the
  proposal's disposition 2 needs — pin an annotated archive tag, verify it, then
  take the destructive-looking act — plus the fail-closed ledger read, the
  dry-run review surface, and the unit-separated fields. The sweep copies its
  rails from there.

- **Detection is not a dependency.** The proposal says detection already exists
  (`refinery-reconcile.sh` reporting `FRESH HANDOFF (branch pushed, no anchor)`).
  That string is gone post-rewrite. It did not matter: the sweep does its own
  enumeration (`git ls-remote --heads origin`, the `review-sweep.sh` shape), so
  it depends on no upstream detector. The "close the chore" step in the proposal
  assumed detectors pre-file chores; with none filing them, the sweep is
  self-contained — it records disposals in its own archive tags and summary, and
  files a finding only for the contested, through `patrol-finding.sh`.

- **Cold horizon.** The proposal cites `STALE_DAYS` as the board's constant; the
  rewrite moved that to the Go helm board's `stale_days` (default 14). The sweep
  keeps 14 as `STALE_BRANCH_COLD_DAYS`, matching the board's stale bump, and
  makes it an env knob.

- **Contested uses `patrol-finding.sh`, not `escalate.sh`.** The proposal says
  "escalate." A sweep's recurring, per-branch observation is a durable finding
  the first reaction triages — `patrol-finding.sh`'s own contract — not an
  ephemeral visit, which `escalate.sh` reserves for what only a human can answer
  and dedups to one open visit per situation. The three contested shapes (open
  PR, unreadable, protected name) each file a situation-keyed finding.

- **The "live session owns it" case folds into the ledger + horizon.** The
  proposal lists a live session owning the branch as a third contested shape.
  Tracked work that a session owns is named by a live bead (`metadata.branch` or
  `metadata.target`), which the ledger read already keeps; and a branch touched
  within the cold horizon is not abandoned. So no per-process `/proc` scan is
  needed — the two checks that keep a live branch cover it.

## The novel capability: direct origin ref mutation

The sweep is the pack's first script to mutate origin refs directly — delete a
branch, push an annotated tag. The pack otherwise never writes origin except
through `gh pr merge`, which lands commits and lets GitHub sign them. That
convention is about commits reaching a protected ref: the "commits must have
verified signatures" repository rule (GH013) fires on a pushed commit. A branch
delete adds no commit, and an annotated tag object is not a commit, so neither is
subject to it. The mutations go through the gh token the order is handed, via
`gh api` — the same house style (`gh api --hostname … -X METHOD repos/…`) every
other GitHub write in the pack uses, now reaching the git-data endpoints
(`git/tags`, `git/refs`) for the first time.

Safety rests on the same property as `worktree-reap`: the destructive act is
reversible. A cold branch's tip is pinned by `archive/<branch>@<sha>` and the tag
is read back on origin before the branch is deleted, so a branch is never deleted
against an archive that did not land. A delete also re-reads the branch's origin
tip and refuses unless it matches the tip the pass classified, so a commit that
arrived after classification — one the tag never pinned — stands the delete down.

## Identity source

Origin identity is read with `git config --get remote.origin.url`, not
`git remote get-url origin` as the merge-cadence scripts do. The slug parse is
the merge cadence's, verbatim; only the source differs. `get-url` applies a
transport-time `url.insteadOf` rewrite, which identity must not follow — who the
origin *is* is the declared URL, not a substituted transport path. In production,
with no `insteadOf`, the two are identical; the distinction only shows under the
hermetic test, which points transport at a bare repo while keeping the declared
origin a github slug.
