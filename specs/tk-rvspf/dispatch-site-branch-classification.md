---
name: Classifying the branch a rewrite is DISPATCHED against
description: Why pr-facts.sh's CONFLICTING arm classifies the PR head branch before filing a rework child, how it reuses tk-a0hva's allowlist and prepare_mode carrier rather than inventing a second one, and which sites this still does not reach.
---

# Classifying the branch a rewrite is DISPATCHED against

## The defect

`assets/scripts/pr-facts.sh`'s CONFLICTING arm does not rebase a branch. It
**dispatches** a rebase. It resolves

```bash
fix_branch="${head_ref:-$branch}"          # the PR's LIVE head branch
```

and files a rework child into a live fix pool whose `rejection_reason` read,
verbatim:

> Rebase '$fix_branch' onto origin/$base, resolve, force-push with
> --force-with-lease.

`mol-polecat-work.toml`'s `rejected-branch-resume-mode` then acts on that child.
Since tk-a0hva round 2 that block is conditional on `metadata.prepare_mode`, but
this arm stamped no such key, and the block treats an absent mode as `rebase`. So
the dispatch resolved to `git rebase origin/main` against whatever shape the PR's
head branch happened to be, and the submit step's push then invited a force-push.

No branch-shape classification existed anywhere on that path. The arm's only
vetoes were the operator markers `merge_hold` and `rebase_hold`.

## Why this is the tk-a0hva defect

Rebase REWRITES commits. That is free on a disposable per-bead branch and
destructive on a branch other work already depends on. An owned convoy's
integration branch carries commits that are **already merged PRs**. Rewriting
them re-points those PRs at objects the branch no longer holds and leaves the
originals dangling and GC-eligible. That is the 2026-08-19 incident: convoy
`tk-t80p1`, PR #388, three merged PRs rewritten
(`specs/tk-a0hva/branch-prepare-mode.md`).

tk-a0hva fixed the refinery's **own** prepare step. Its allowlist cannot reach
here, because here the rewrite is handed to a polecat instead. That is a
different actor reaching the same destruction. A graduation PR is the reachable
case: PR #388's head branch was `integration/refinery-script-fixes`, and had it
gone CONFLICTING rather than merging, this arm would have dispatched the rewrite.

tk-a0hva named this site in its own self-review and deliberately left it, on the
grounds that it was a different file, a different actor, and a different test
suite. It filed `tk-rvspf` so a second, independently-invented classifier would
not land unreviewed beside the first. That document also states what the reuse
should be, and this change is it:

> `tk-rvspf`'s remedy is to classify once at that dispatch site and stamp
> `prepare_mode` on the rework child it files. The resume path already honors it.
> No third classifier, and no change to `mol-polecat-work.toml`.

## The remedy

One marker-fenced block, `stale-base-dispatch-mode`, in the CONFLICTING arm. It
applies the **same** allowlist as `mol-refinery-patrol.toml`'s
`shared-branch-merge-mode`, restated where the second actor is chosen:

```bash
case "$fix_branch" in
  polecat/*) prepare_mode=rebase ;;
  *)         prepare_mode=merge ;;
esac
if [ "$grad" = "true" ]; then prepare_mode=merge; fi
```

`graduation` is newly carried off the anchor row as `grad`.
`convoy-graduate.sh` stamps it when it hands an owned convoy over, and that same
bead is this anchor once its PR opens. It is load-bearing in exactly one case, a
graduation carried on a polecat-shaped branch, and it states the intent the
branch name only implies.

The mode then travels three ways, in descending order of how much it matters:

1. **`metadata.prepare_mode` on the child.** This is the carrier, and the only
   one that stops the rewrite. `rejected-branch-resume-mode` reads it and merges.
2. **`rejection_reason`, and the child's title.** Prose, for whoever works the
   bead by hand. A merge-mode child titled "Rebase PR#N" invites by hand exactly
   what the mode prevents, so the title names its own mode.
3. **The per-anchor log line**, which names the mode it dispatched.

### Why the route is stamped after the mode reads back

The arm used to stamp every field and the route in one `gc bd update` whose
failure was nonfatal. `prepare_mode` cannot ride that shape, for a sharper reason
than the other fields:

- a dropped `branch`, `pr_url`, or route leaves a child **nothing can act on**.
  That is the existing failure mode, "inert", and it is the safe side.
- a dropped `prepare_mode` leaves a child that is complete, routable, **and
  rewriting**, because absence resolves to `rebase` downstream.

So the one field whose loss is worse than total loss is exactly the one an exit
status cannot see. The write is now split: everything except the route, then a
read-back of `prepare_mode`, then the route. A child whose mode did not persist
is left unrouted and the fix pool is not woken. This is the shape `signoff.sh`
and the stale-gate arm in this same file already use.

### The no-pool arm needs nothing here

The predecessor of this arm also escalated to a human when no fix pool was
configured, and that mail told the operator to rebase and force-push the branch
it named, which is the same rewrite reached through a third actor. The successor
does not: an unresolvable branch or pool exits with "merge stays held (operator
must repair)" and names no remedy. There is nothing to classify.

### What was deliberately not done

- **Skip the arm and escalate on any non-`polecat/*` branch**, the bead's other
  offered remedy. It is safe, and it is a regression in automation. A
  shared-branch conflict is exactly as mechanically fixable as a polecat one, and
  stalling every such PR on a human buys no safety a merge-mode dispatch does not
  already buy.
- **A second classifier in `mol-polecat-work.toml`.** The carrier already exists
  and already works. A third copy of the `case` statement is a mirrored predicate
  free to drift. See `specs/tk-a0hva/branch-prepare-mode.md`, "Why the bead, and
  why on the happy path".
- **Widening `rebase_hold`.** Unchanged from tk-a0hva's reasoning: the operator
  gate already exists, and making the safety depend on someone setting it is the
  instruction-shaped fix that has now failed once in production.
- **Renaming the `reworked` summary counter.** It counts stale-base rework
  dispatches of either mode. The per-anchor log line, which is what an operator
  reads about one bead, names the mode instead.

## The sibling site this change does NOT cover

Sweeping every writer of `rejection_reason`, rather than only the sites the bead
named, turns up a fourth reachable route to the same destruction. It is filed as
`tk-4vi116` rather than fixed here, on the same grounds tk-a0hva split this bead
out: different file, different actor, different test suite.

`assets/scripts/signoff.sh`'s REQUEST_CHANGES dispatcher files a rework child
carrying `rejection_reason` and `branch`, and stamps no `prepare_mode`. A
graduation PR whose codex review requests changes lands there with
`branch=integration/<convoy-id>`.

This matters for a claim tk-a0hva makes. Its "Why absent means rebase" section
argues the default is safe because "every bead the refinery hands back has passed
through the stamp, and the stamp is fail-closed, so absence never means 'the
refinery declined to say'". That enumerated the writers known at the time. This
writer was not among them and does not pass through the stamp, so on that path
absence does mean what the section says it never means. The default is still
right, for the reasons given there, but the enumeration behind it needs the
fourth writer added, which `tk-4vi116` does.

## Where this fix was first written

It was written against `assets/scripts/reconcile-merged-prs.sh`'s stale-base arm,
which #465 deleted when it rewrote the merge cadence as the `refinery-reconcile`
order. The defect moved with the cadence into `pr-facts.sh`, arm 4 of five, and
is unchanged there: the same unconditional work order against the same
unclassified `head_ref`. The remedy was re-derived against the successor rather
than replayed, because the arm around it is not the same code. Three differences
are worth naming:

- the anchor row is the whole bead JSON here, so `grad` is read directly rather
  than added to a projection;
- the successor's no-pool exit names no remedy, so the escalation prose the
  original change also classified has no counterpart;
- the original stamped the mode and then verified it in a pre-arm read-back that
  already existed. Here there was no read-back, so the route is split out and the
  read-back added.

## Verification

`assets/scripts/pr-facts.test.sh`, the suite that already covers this arm's other
gates. gc-toolkit has no test auto-discovery, so a new `*.test.sh` would be a
regression nothing runs.

Control at this base: **61 passed / 1 failed**. With this change: **78 passed / 1
failed**. The one failure is pre-existing and unrelated, in the stale-gate case
("the review formula is attached by an explicit gc sling --on"); it fails
identically with and without this change.

Two fixtures were added, and `anchor`/`prview` gained an optional branch
parameter for them: `SB`/PR#28 (an `integration/*` head, PR #388's shape) and
`GD`/PR#29 (`graduation=true` on a polecat-shaped head). Both sides had to move
together, because the identity guard refuses any anchor whose recorded branch
disagrees with the PR's live head, so a shared-branch fixture left at the default
is held there and never reaches the arm under test.

| mutant | new failures |
|---|---|
| A. allowlist removed (every branch classified `rebase`, the pre-fix protocol) | 7 |
| B. `graduation` override removed | 2 |
| C. `prepare_mode` never stamped on the child | 8 |
| D. read-back removed (a dropped stamp still routes) | 3 |
| E. work order reverts to naming a force-push unconditionally, stamp intact | 6 |

C and D are the pair that matters. C proves the stamp reaches the child, D proves
it is verified rather than trusted. E isolates the prose from the carrier: all
six of its failures are prose assertions, and the `prepare_mode=merge` assertion
still passes.

Neighbouring suites at this commit, every one that references `pr-facts.sh`,
`prepare_mode`, or `graduation`: convoy-graduate 21/0, merge 49/0,
one-anchor-per-pr 14/0, refinery-reconcile 36/0, submit-branch-gate 50/0.

## Related

`tk-a0hva` and `specs/tk-a0hva/branch-prepare-mode.md` (the allowlist, the
`prepare_mode` carrier, and the incident), `tk-4vi116` (the fourth site above),
convoy `tk-t80p1`, PR #388, `docs/refinery-merge-cadence.md` (the five arms and
where this one sits), `docs/state-machine.md` (graduation).
