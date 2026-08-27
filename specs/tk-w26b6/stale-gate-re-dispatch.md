---
name: Stale gate markers — what closed tk-w26b6, and why there is no materiality skip
description: Disposition record for tk-w26b6. The stale-marker re-dispatch it asked for shipped with the #465 rewrite in two arms; read this before re-reporting a held green@old-sha anchor, and before building the inert-diff classifier the bead proposed as its Q2.
---

# Stale gate re-dispatch

tk-w26b6 was filed 2026-07-23 against `check-set-heal.sh` and
`merge-skill.sh`. Both scripts were deleted by the #465 rewrite (`9a6b86a`),
which replaced them with `gate-ensure.sh` and `pr-facts.sh`. The rewrite
implemented fix items 1 and 3 of the bead. This record pins that evidence and
decides item 2, the materiality skip, which the bead left open as Q2.

## What the bead reported

A gate marker binds a verdict to a commit: `check.codex=green@<oid>`.
`merge.sh` merges only when `<oid>` is the live branch head. When a commit
landed on an approved PR after codex had greened an earlier head, the old
`merge-skill.sh` detected the staleness and held the merge, and the old
`check-set-heal.sh` treated the green marker as satisfied without comparing
its oid to the head. Nothing owned "head moved, re-review". The gate held
until a human hand-dispatched the round. That happened twice: PR#30 and
PR#32.

## Item 1 shipped: a stale marker is re-dispatched

Two arms now classify a head-bound marker against the live head, and both
treat "advanced past `<oid>`" as needing a fresh review.

| Where | What it does |
|---|---|
| `assets/scripts/gate-ensure.sh:258-261` | Cadence arm 1. `green@<oid>` at a head other than `<oid>` falls through to the dispatch block at `:418-448`, which stamps `reviewed_oid=<live head>` and pours `mol-review` onto the review pool. |
| `assets/scripts/pr-facts.sh:324-421` | Cadence arm 4. For a PR-bearing anchor, a gate `green@` or `exception@` a stale head files one re-review child per head. Its comment at `:325` states the shared rule: both verbs bind a verdict to a commit, and a branch past either has had no look at its head. |

The behavior is pinned by `assets/scripts/gate-ensure.test.sh:115-126`, which
asserts a `green@old-oid` anchor at head `sha-c1` dispatches a review. The
suite passes 108/0.

It is also observable in production. On 2026-08-27 two gc-toolkit anchors
carried a green marker behind their branch head, and each already had a
re-review in flight pinned to the head that staled it:

| Anchor | Marker | Live head | Re-review |
|---|---|---|---|
| `tk-43chr6` | `green@d858c507` | `ef875077` | `tk-zwco4g`, `reviewed_oid=ef875077` |
| `tk-rbeq4f` | `green@a887c05f` | `a0bb62a9` | `tk-k7eb6i`, `reviewed_oid=a0bb62a9` |

Item 3, "the mayor drops out of the mechanical path", follows from item 1.
The rule is documented in `docs/state-machine.md`, in the gate table and
under *Re-gate on head move*.

## Item 2 declined: no materiality skip

The bead proposed skipping the re-dispatch when the diff between the green
oid and the live head is provably inert, classified by path: docs, comments,
whitespace, generated artifacts. Four things rule it out.

**A skip cannot clear the merge.** `merge.sh` requires
`green@<live head>`. Declining to dispatch leaves the anchor holding at
`green@<old oid>` with nothing driving it, which is the stall tk-w26b6
reported, reached by a different route. To be worth anything the skip must
advance the marker to the new head.

**Advancing a marker is writing a gate verdict.** Component invariant I7
(`docs/component-model.md:105`) makes `signoff.sh` the single writer of
`check.*`, and holds it by construction: no other component contains such a
write. A classifier in `gate-ensure.sh` that promotes a green to a new head
is a second writer, and it writes a verdict no reviewer produced.

**The inert path class is close to empty in this repo.** Comment text is
linted: `tools/lint-learned.d/constant-in-comment.sh` and
`stale-reference.sh` both find defects that exist only in comments, and
`tk-5alyev` is an open bead against exactly such a finding. Generated
artifacts are gated: `doctor/check-seed-audit-current` fails on a stale
`generated/seed-audit/`. Prose in `docs/` is reviewed as content: the gate
table this commit corrects was wrong about the green marker's re-gate,
which is the class of defect a re-review exists to catch. Each of the four
proposed inert classes carries reviewable material here.

**The rewrite already decided the question the other way.**
`docs/state-machine.md:120-121` states the rule as uniform: a head move
stales every verb at once, so a fixed branch re-evaluates fresh with no
manual reset. Uniformity is what makes the marker readable without knowing
which commits produced it.

The bead's own cost argument points the same way. A needless re-review costs
one codex round. A wrong skip merges code no one read.

If the codex spend on trivial fixups ever justifies revisiting this, the
change belongs in `signoff.sh` as a verdict it issues, not as a second writer
in the cadence, and it needs the design review the bead's scope asked for.

## Residue

The cap interaction is a separate defect and is already filed. At
`dispatch_count >= GC_MAX_REVIEW_ROUNDS`, `gate-ensure.sh:378-384` grants the
one dispatch a head move past an `exception@` earns, but refuses it for a
stale `green@`. An anchor approved on its last budgeted round and then
touched holds with no arm to catch it. That is `tk-n70xmm`, not this bead.
