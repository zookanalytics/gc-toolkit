---
name: Merge-strategy resolution for a fold-into-a-PR-head target
description: Why a rework whose target is another bead's per-bead PR head resolves to direct, and why the filed "signoff.sh" locus and "target != default -> direct" rule were both wrong.
---

# Fold-into-a-PR-head resolves to direct

## The bug

A bead reaches the refinery with `metadata.target` set to another bead's
per-bead PR-head branch (`polecat/<id>`) and no `merge_strategy`. The intent
is to fold the work onto that PR's head, updating the open PR so its checks
re-review at the new head. But the refinery resolves an unset strategy to the
`default_merge_strategy` var (`mr` in gc-toolkit), and `pr-open.sh` then opens
a PR with `--base polecat/<id>` — a nested `polecat/<new> -> polecat/<id>` PR,
which a fold never wants. Nothing in the refinery detects the shape, so it
happens silently.

## Why the filed remedy was wrong

The bead was filed with a root cause ("resolved from the rig default whenever
the bead does not set it ... wrong where target is not the default branch")
and first-reaction-dispositioned onto `signoff.sh:845-847`, which stamps
`merge_strategy=mr` on every rework child. Both are off.

- `signoff.sh` is correct. Its rework child resumes the ANCHOR's own branch
  and either carries `existing_pr` (post-open, so `mr` re-reviews that exact
  PR) or stands branch-equal to its anchor (pre-open, folded in by the
  one-anchor hand-back guard). Its `mr` never opens a nested PR. The same
  holds for `pr-facts.sh` (sets `existing_pr`) and `pre-open-rebase.sh`
  (branch-equal to the anchor). No standard dispatcher produces the bad shape;
  per `lifecycle.toml`, every one that sets a non-default target also stamps
  `mr` explicitly. The bad target value originates upstream, from a manual or
  converse "fold this into PR N" dispatch that omits the strategy.

- "Target != default branch -> direct" is too broad. A convoy child targets
  `integration/<convoy>` and a graduation targets the default branch; both
  resolve to `mr` on purpose (a reviewed PR against the integration branch,
  then a reviewed graduation). A contribution to a long-lived named branch
  (e.g. a doc branch under its own PR) is the same. Resolving those to direct
  would fast-forward past the review gate. `convoy-graduate.sh` and the
  `integration/*` pipeline depend on `mr` for exactly these non-default
  targets.

## The discriminator

The distinguishing fact is not "non-default target" but "target is another
bead's per-bead PR head" — the `polecat/` branch namespace, which
`mol-polecat-work` mints per bead and which no convoy, graduation, or
named-branch workflow ever targets. So the refinery's one
`merge-strategy-resolve` block resolves a bead to `direct` when all hold:

- strategy is `mr` (unset-default or explicit), and
- the bead records no PR of its own (`existing_pr`/`pr_url`/`pr_number` all
  empty — a bead with its own PR reuses it), and
- `target` matches `polecat/*`, and
- `target` is not the bead's own branch.

It records `MS_FOLD_IN` so the rejection path's branch-keep decision agrees:
a fold-in branch is `direct` but must be KEPT on a rejection (it carries the
rework), unlike an ordinary direct branch with nothing PR-shaped, which is
deleted.

This lands in the refinery (the bead's option 2) rather than at sling time
(option 1, which is `gc sling` in gascity) because the refinery is the one
chokepoint every bead converges on, including a manually dispatched one that
never passed through a pack dispatcher.

## Blast radius

Only a bead whose `target` is a `polecat/*` branch with no PR of its own
changes behavior. Targets of the default branch, `integration/*`, and named
branches are untouched, as is any bead carrying its own PR. The
`merge-strategy-resolve` block stays byte-identical across its two call sites,
and the only new reads are of `target`/`branch`/`existing_pr`, not
`merge_strategy`.
