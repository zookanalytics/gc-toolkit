---
name: Observing a conflict on an anchor that has no PR
description: Why the merge cadence could not route a rebase child for a pre_open_gate anchor, why widening the enumeration the bug report named routes nothing, and what the merge-tree observer arm does instead.
---

# Observing a conflict on an anchor that has no PR

## The defect

An anchor at `merge_result=pull_request` whose branch has gone stale gets an
automatic rebase child: `pr-facts.sh`'s CONFLICTING arm classifies the head
branch, files one child per head into the fix pool, and stamps `prepare_mode`.
An otherwise identical anchor at `merge_result=pre_open_gate` gets nothing. Its
branch stays stale until something else moves it.

The cost is spent review. `gate-ensure.sh` dispatches a gate review pinned to
`reviewed_oid=<live head>`, and `signoff.sh` binds the verdict to that commit. A
branch that has to be rebased moves its head, so the verdict goes stale and the
review is re-dispatched at the new commit. Nothing is lost permanently — a
pre-open anchor eventually opens a PR, flips to `pull_request`, and becomes
visible to every arm — but until it does, the remedy is unreachable.

## Why the enumeration is not the bug

The bead named `reconcile-merged-prs.sh:460` and proposed widening it:

```bash
ANCHORS=$(gc bd list --status=open \
  --metadata-field merge_result=pull_request \
  --limit=200 --json 2>/dev/null)
```

That file no longer exists; #465 deleted it when it rewrote the merge cadence as
the `refinery-reconcile` order, and the surface it described is now spread over
four scripts. Auditing all of them for single-value `merge_result=`
enumerations, which the bead also asked for, finds this:

| site | enumerates | correct? |
|---|---|---|
| `gate-ensure.sh:296` | `pre_open_gate` **and** `pull_request`, in a loop | already wide |
| `pr-open.sh:253` | `pre_open_gate` | correct — it is the pre-open arm |
| `merge.sh:159`, `:317` | `pull_request` | correct — only a PR can be merged |
| `pr-facts.sh:204`, `:1040` | `pull_request` | correct — every arm reads PR facts |

So there is one narrow net left and widening it routes zero children. Nine lines
below `pr-facts.sh:204` sits

```bash
case "$num" in ''|*[!0-9]*) skipped=$((skipped + 1)); continue ;; esac
```

and a pre-open anchor has no `pr_number` by definition, so every one admitted by
a wider enumeration is dropped there before anything is read. Past that guard
the arm calls `gh pr view "$num"`, and everything it dispatches on —
`mergeable`, `mergeStateStatus`, `headRefOid`, `baseRefName` — is a fact about a
PR that does not exist yet. The narrow net is not a defect in those arms; it is
the honest statement of what they can answer.

The gap is that **no arm asks the conflict question of git**, which can answer it
for a branch with no PR.

## The remedy

`assets/scripts/pre-open-rebase.sh`, arm 1a, between `gate-ensure.sh` and
`pr-open.sh`. One fetch per pass mirrors every branch on origin into
`refs/gc-toolkit/pre-open-rebase/heads/*`. Then, for each open `pre_open_gate`
anchor carrying a branch: read both sides out of that namespace, probe
`git merge-tree --write-tree`, and on a conflict file the same rebase child
`pr-facts.sh` files for a PR anchor.

It runs before `pr-open.sh` because that arm ends its domain: once an anchor
carries a PR, `mergeable` answers the same question and `pr-facts.sh` owns the
dispatch.

### What is reused, and how the reuse is held

The dispatch is `pr-facts.sh`'s, restated where the observation differs:

- **The branch allowlist.** `polecat/*` rebases, every other shape merges, and a
  `graduation` merges whatever its branch is named. This is
  `mol-refinery-patrol.toml`'s `shared-branch-merge-mode` and `pr-facts.sh`'s
  `stale-base-dispatch-mode`, not a third classifier
  (`specs/tk-rvspf/dispatch-site-branch-classification.md`,
  `specs/tk-a0hva/branch-prepare-mode.md`). It is fenced as
  `pre-open-dispatch-mode`, and `pre-open-rebase.test.sh` extracts both copies
  and fails if they disagree — including if either fence is renamed away, since
  two missing blocks would otherwise compare equal.
- **The demand discriminator.** `takeaway-hold-discriminator` is copied
  verbatim under the same fence name, and the same suite asserts the two copies
  are byte-identical.
- **The read-back split.** Everything but the route, then a read-back of
  `prepare_mode`, then the route, then a read-back of that. A dropped
  `prepare_mode` is the one loss worse than total loss, because the resume path
  treats an absent mode as `rebase`.
- **The vetoes.** `merge_hold` or `rebase_hold` on the anchor, a `rebase_hold`
  on any bead naming the branch, and a live demand — rebasing is routinely one
  horn of what a demand asks, so performing it answers the person by fait
  accompli.

### How the two arms avoid twinning

By construction rather than by a bookkeeping key. Both probe children on
`metadata.branch` across all statuses, and both write `head <oid>` into
`rejection_reason` in the phrasing the other matches. A live child on the branch
vetoes either arm, so whichever sees a branch first files and the other stands
down. An anchor is excluded from its own dedup by its `merge_result`, so the
`pull_request` anchor a pre-open bead becomes never dedups against itself.

The child differs from `pr-facts.sh`'s in one way: it carries no `pr_url`,
`pr_number` or `existing_pr`, because there is no PR. Its work order says so —
"Do NOT open a PR — anchor `<id>` opens its own once the branch is current" —
where the PR-anchor child says the opposite.

### One fetch, and what holds it honest

A fetch costs one network round trip whatever it carries — measured on this rig,
1.5s for two refspecs and 1.5s for all 153 branches. Per-anchor fetching would
spend that once per anchor: against the 38 pre-open anchors standing when this
was written, about 57s of a 60s pass, all of it inside the cadence's
single-flight lock and therefore merge latency for every anchor in the queue. One
glob refspec instead, `+refs/heads/*:$GATE_REF/heads/*`.

The glob also removes a failure mode a list of named refspecs has: git refuses
the whole fetch if any one named ref is gone (`couldn't find remote ref`, rc=128),
so one deleted branch would leave the pass observing nothing at all. Under the
glob a branch that is gone is simply a ref that is not there.

`--prune` is what keeps the namespace honest. Without it a branch deleted on
origin keeps its mirrored ref and the probe compares a commit nobody can push to,
dispatching a rebase for a branch that does not exist.

Two things then rest on the ref check that follows. `git merge-tree` exits 1 for
a ref it cannot resolve, with `not something we can merge`, exactly as it does
for a conflict; on the exit status alone a deleted branch is a permanent
conflict. And `head_oid`, read from the same place, is what the dedup matches on
and what the work order names. Refusing to probe unless both sides resolve is the
only thing between a missing branch and a bogus dispatch.

## What was deliberately not done

- **Widening `pr-facts.sh`'s enumeration**, the bead's own proposal. It routes
  zero children, for the reasons above, and it would break that arm's stated
  contract of sharing one enumeration and one pinned identity read with
  `merge.sh`.
- **Holding `pr-open.sh` on a conflicting branch.** Once the child is routed,
  publishing the PR buys nothing to stall: GitHub shows the conflict, the anchor
  flips to `pull_request` where the whole observer surface applies, and
  `pr-facts.sh` dedups against the live child rather than twinning it. Holding
  publication on a machine-fixable condition is the regression in automation
  `tk-rvspf` declined for the same reason.
- **Renumbering the cadence arms.** The numbers already disagree between
  `docs/refinery-merge-cadence.md`, `docs/state-machine.md` and the script
  headers; renumbering to insert one arm would touch every one of them and fix
  none of it. `1a` names the position without moving anything.

## The sibling this change does NOT cover

Filed as `tk-8oiy0p`. This arm files the rebase child, which is what the bead
asked for, but it does not stop the review that the rebase will strand.
`gate-ensure.sh` runs before it and dispatches a gate review pinned to the live
head; nothing in that arm reads a pending rewrite. Its one dispatch refusal is
narrower — a head that a **closed request-changes verdict** already judged, whose
rework child is still open — so a rebase child does not trip it. The result is
one review round spent against a commit that is about to move.

The remedy is a veto in `gate-ensure.sh`: a live child naming this branch means
the head is about to move, so a verdict pinned to it can only be spent. It is
not folded in here on the grounds `tk-a0hva` used to split `tk-rvspf`, and
`tk-rvspf` used to split `tk-4vi116` — different file, different actor,
different test suite — and because that arm's dispatch decision already carries
a stranded/poured/backstop tree whose every branch would need fixtures for a
condition inserted above it. Adding a silent hold there without them is how an
anchor holds for good with nothing open to say why, which is the one failure
`gate-ensure.sh` is written to avoid.

## Verification

`assets/scripts/pre-open-rebase.test.sh`. gc-toolkit has no test
auto-discovery, so the suite is named for the script it covers and run by hand.

The suite runs **real git over a real fixture repository** and stubs only the
bead store. `test-harness.sh`'s git stub exits 0 for every command it does not
recognise, so under it `merge-tree` reads CLEAN for every anchor and the whole
suite would pass against a script that observes nothing. The fixture cuts four
branches from one base point, edits line 2 on each, then edits line 2 on `main`;
a fifth branch touches a different file and still merges. Three assertions pin
the premise directly: `merge-tree` exits 1 for a conflict, 1 for an unresolvable
ref, and 0 for a branch that still merges.

Control: **65 passed / 0 failed**.

| mutant | new failures |
|---|---|
| A. ref check removed (a branch that is gone reads as a conflict) | 3 |
| B. allowlist removed (every branch classified `rebase`) | 5 |
| C. `prepare_mode` never stamped on the child | 8 |
| D. route read-back removed (a dropped route still counts as dispatched) | 2 |
| E. `prepare_mode` read-back removed | 3 |
| F. `graduation` override removed | 2 |
| G. dedup removed (a second child races the first) | 3 |
| H. probe hardwired to CLEAN | 28 |
| I. `blocks` edge dropped | 1 |
| J. enumeration widened to `pull_request`, the bead's proposal | 35 |
| K. `--prune` dropped from the pass fetch | 2 |
| L. pass fetch skipped (the namespace is never refreshed) | 32 |

C and A are the pair that matters. C proves the stamp reaches the child rather
than the log line; A proves the arm refuses to dispatch against a question git
never answered. H and J bound the whole thing from the other side: H is an arm
that observes nothing and J is the bead's own proposed remedy applied on its
own — it enumerates no pre-open anchor at all — and each takes down roughly half
the suite.

## Live population when this was written

Measured against the loomington store on 2026-09-03, before the change: 38 open
anchors at `pre_open_gate` against 12 at `pull_request`. Probing each pre-open
anchor's branch against its target with the same `merge-tree` call this arm
makes, **12 of the 38 conflicted with `main`** and were receiving no rebase
child. Every one was on a `polecat/*` branch, so every one classifies `rebase`.

## Related

`tk-rvspf` and `specs/tk-rvspf/dispatch-site-branch-classification.md` (the
allowlist and the dispatch-site reuse this follows), `tk-a0hva` and
`specs/tk-a0hva/branch-prepare-mode.md` (the `prepare_mode` carrier and the
incident behind it), `tk-wsxd0` (the same class of gap in `check-set-heal`'s
net, which this one turned out not to share), `tk-lcv9a` (the cross-anchor
conflict tax, whose remedies this makes reachable for pre-open anchors),
`tk-8oiy0p` (the review-dispatch veto above),
`docs/refinery-merge-cadence.md` (the arms and where this one sits).
