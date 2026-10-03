# Stale-branch triage

A merged PR deletes its own head branch; nothing deletes the branch of work that
never merged. Every abandoned attempt — a superseded retry, a cold research
branch, an unmerged spike — leaves its origin ref behind, and the list grows
without a ceiling. The only disposal available was a person's: land unassessed
work or delete it. Both are terminal, neither has a safe default, so the branch
waits for someone who feels like deciding, which is to say it waits forever.

`assets/scripts/stale-branch-triage.sh`, run by the `stale-branch-triage` order,
is that disposal. It replaces the irreversible default with a reversible one: a
cold unmerged branch is pinned by an annotated archive tag and only then deleted,
so nothing is destroyed and an agent may take the act without consent. That is
the whole mechanism — the branches did not stall because nobody understood them,
they stalled because the only act on offer was irreversible, and an irreversible
act needs a human by rule.

## What the sweep does

For each origin branch other than the default, with no live owner:

- **Superseded** — every commit is already reachable from the target, or (for a
  `polecat/<bead-id>` branch) the bead id rode a squash-merge commit subject onto
  the target. The work is on the target, so the branch is deleted with no
  archive; nothing can be lost.
- **Cold and unmerged** — the newest commit is older than the cold horizon and
  not on the target. The tip is pinned by an annotated tag
  `archive/<branch>@<short-sha>` carrying the classification, the tag is verified
  on origin, and only then is the branch deleted.
- **Contested** — an open PR heads the branch, or its tip or the target could not
  be read, or an operator-protected name matches. The branch is left untouched
  and a durable finding is filed through `patrol-finding.sh`, carrying the
  classification so the first reaction has the real question in front of it:
  archive this work, land it, or keep it.

A branch is kept silently when it is younger than the horizon, or when a live
(non-closed) bead names it in `metadata.branch` or targets it in
`metadata.target`. The live bead is the tracked form of "a session owns this";
an integration branch is a live convoy's landing ref and is named only as a
target, so both are read.

## Archiving is reversible, not gated

The archive tag is an annotated tag whose message records the classification and
the restore command. The tagged commit survives the branch deletion — a tag is a
ref, so its object is never GC-eligible — and the branch is one command back:

```
git fetch origin refs/tags/archive/<branch>@<sha>
git branch <branch> archive/<branch>@<sha>^{commit}
git push origin <branch>
```

Because restoring is cheap and certain, the sweep archives without asking. The
tag is verified on origin before the branch is deleted, so a branch is never
deleted against an archive that did not land.

## Mutating origin

This is the pack's only direct mutation of origin refs. The merge cadence lands
commits through `gh pr merge` and lets GitHub sign them, and nothing else writes
origin. That rule is about commits reaching a protected ref: a branch delete adds
no commit, and an annotated tag object is not a commit, so neither is subject to
the signed-commit requirement. Both go through the gh token the order is handed,
via `gh api` — the create-tag (`POST .../git/tags`), create-ref
(`POST .../git/refs`), and delete-ref (`DELETE .../git/refs/heads/<branch>`)
endpoints — the house style for every GitHub write in the pack.

A delete re-reads the branch's origin tip immediately before acting and refuses
unless it still matches the tip the pass classified. A commit that arrived after
classification is unpinned by the archive tag, so the delete stands down and the
next pass reclassifies against the new tip.

## What the reports mean

One summary line per pass:

```
stale-branch-triage.sh: <rig> (<repo>) — deleted N superseded, archived M cold, filed K contested; P kept
```

`deleted` and `archived` both removed a branch; `archived` pinned it first.
`filed` opened or refreshed a finding. `kept` is every branch the filters
protected — the number that proves the sweep is selecting, not emptying. A
`refused` line names dispositions left for the next pass: a tip that could not be
verified on origin, a moved tip, or a finding that could not be filed.

## Rails

Liveness is resolved first and every read fails closed. An unreadable bead
ledger, an unreadable open-PR list, an unreadable origin branch list, or an
unreadable default branch sweeps nothing that pass, because under any of them a
branch would read as unowned. A partial fetch is tolerated: a branch whose tip
object did not land reads as contested-unreadable and is never archived. A time
budget bounds the pass; a pass cut short leaves a consistent origin and the next
pass takes the rest.

## Operating it

The order runs hourly per rig. Tune it from `city.toml [[orders.overrides]]`,
not the order file.

- `--dry-run` reports the full plan and touches nothing. It is the review
  surface: run it to see exactly which branches a pass would delete, archive, or
  flag, before trusting the cadence.
- `STALE_BRANCH_COLD_DAYS` (default 14) — the horizon past which an unmerged
  branch is cold. 14 matches the helm board's own stale bump.
- `STALE_BRANCH_BUDGET` (seconds, default 300, 0 disables) — the per-pass time
  budget.
- `STALE_BRANCH_TAG_PREFIX` (default `archive`) — the archive tag namespace.
- `STALE_BRANCH_PROTECT` — space or newline separated glob patterns of branch
  names never deleted or archived. A matching branch that is otherwise cold and
  unmerged is reported contested instead, so a protected family (for example
  `integration/*`) reaches a person rather than the reaper.
- `STALE_BRANCH_TARGET` — override the default branch; the sweep otherwise reads
  `origin/HEAD`.

## What it does not touch

The default branch and `origin/HEAD`. Any branch a live bead names or targets.
Any branch younger than the cold horizon. A superseded or cold branch still under
an open PR, or matching a protected name — those become findings. The archive
tags themselves accumulate, far more slowly and far more cheaply than branches;
their own horizon is left for later.
