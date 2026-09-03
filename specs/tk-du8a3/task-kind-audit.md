---
name: task_kind audit — labels vs metadata as the kind discriminator
description: The pack-wide survey behind component-model I12, measured 2026-09-03 — every task_kind write and read site classified, the live-store census of kinds and label mirroring, the one reader that disagreed, and why uniform label mirroring was rejected.
---

# `task_kind`: what the audit found

The stance this produced is in
[component-model.md](../../docs/component-model.md#what-kind-of-bead-this-is);
that document says what is true now and is the thing to keep current. This file
is the measurement behind it, taken 2026-09-03 against the `gc-toolkit` store at
`63c8ac24`. The numbers date; the conclusions are what carried into `docs/`.

## Code sites

252 references to `task_kind` across the pack.

**Writes — 15 sites, one form.** Every one is
`--set-metadata task_kind=<kind>`, in `escalate.sh`, `gate-ensure.sh`,
`gc-helm.sh`, `liveness-sweep.sh`, `pr-facts.sh`, the proactive prompt, the
observation-filing fragment, and the deacon-patrol, feedback-distiller,
feedback-miner, first-reaction and visit formulas. No write puts the kind
anywhere but metadata.

**Reads — every kind branch reads `metadata.task_kind`.** The liveness sweeps
and precheck, `converse-claim.sh`, `duplicate-sweep.sh`, `gate-ensure.sh`,
`pr-facts.sh`, `pr-open.sh`, `review-sweep.sh`, `orphan-dispose.sh`, both
`doctor/check-gate-marker-provenance` and `doctor/check-one-anchor-per-pr`, and
`services/helm`'s `visitFilter`. Nothing reads a label to decide a kind.

**Label narrowings — 4 sites, 3 correct.** `mol-feedback-miner.toml:210`,
`mol-feedback-distiller.toml:150-162` and `learning-recurrence.sh:127-129` all
list with `-l observation`. The miner and the distiller then filter on
`task_kind == "observation"`; `learning-recurrence.sh` did not, so the label
was the sole discriminator for the feedback loop's own success metric. That is
the single code site the audit found in disagreement, and the one this bead
fixed. Its test fixture had encoded the same mistake — every fixture bead
carried the label and no `task_kind` — so the fix turned 14 assertions red
until the fixture was corrected to match what both real writers do.

## Live store

2039 beads carry a `task_kind`, across **16** distinct values:

| kind | beads | carry the matching label | written by pack code |
|---|---|---|---|
| `review` | 1249 | 1 | yes |
| `visit` | 327 | 0 | yes |
| `observation` | 283 | 283 | yes |
| `feedback-pattern` | 61 | 61 | yes |
| `doc-update` | 54 | 52 | no |
| `rework` | 20 | 0 | no |
| `research` | 16 | 0 | no |
| `prompt-update` | 10 | 10 | yes |
| `evaluation` | 6 | 0 | no |
| `triage-subject` | 4 | 0 | yes |
| `investigation` | 3 | 0 | no |
| `design` | 2 | 0 | no |
| `engineering`, `implementation`, `review_fixup`, `work` | 1 each | 0 | no |

Two facts fall out of this table.

**Mirroring is bimodal, not haphazard.** The three kinds a reader narrows by
label mirror it on every single bead (283/283, 61/61, 10/10). The kinds no
reader narrows carry no label at all. The pattern is a property of each kind's
writers, and it already matches what the readers need.

**The value vocabulary is open.** Ten of the sixteen kinds are written by
nothing in this pack. `lifecycle/lifecycle.toml` registers the `task_kind`
*key* under `[metadata.gates]` but declares no enum of values, so kinds
accumulate from outside it: `agents/` ships no doc-keeper, yet 52 of the 54
`doc-update` beads carry a `doc-keeper` label, and the rest are a long tail of
one-offs. Nothing in the pack reads those kinds either, so they are inert
rather than wrong.

**Divergent beads.** Four beads carry a `review` label with no
`task_kind=review`, and `tk-i21z7.1` carries a `doc-update` label with no
`task_kind` — all closed. Two open beads (`tk-pq67l`, `tk-k3qo7`) carry
`task_kind=doc-update` without the label. No reader narrows on a `doc-update`
or `review` label, so none of these is reachable by a query that matters, and
no bead needed repair.

## Why label mirroring stays optional per kind

The bead left one question open: make mirroring uniform across every kind, or
keep it per-kind. Per-kind won.

Uniform mirroring would mean back-filling labels onto 1249 `review` and 327
`visit` beads and adding label writes to their writers, to satisfy no reader —
a migration bought with no property. It would also not be self-maintaining: the
`review` label already exists on four beads that are not reviews, so a uniform
rule would have to police the converse direction too, on a key whose value
space is open.

The rule that does carry weight is narrower and matches the code as it already
stands: a label may narrow a query but never decide one, and a kind earns a
`-l` narrowing only once every writer of that kind sets the label. The second
half is the one that fails silently — narrow on a label some writer omits and
the listing is quietly short — and it is the unchecked half filed as
`tk-0i90x5`.
