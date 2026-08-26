---
name: Operator-Profile Audit
description: The city-wide feedback audit that populated the operator profile — the corpus read, the clusters judged, the seven entries adopted, and the clusters deliberately left out.
---

# Operator-Profile Audit

The operator profile is meant to hold what the operator values, derived from
what they have actually said. Before this audit it held three entries, all
from one PR review conversation. This is the record of the audit that
populated it to ten.

## The corpus

Every observation bead in the city, read 2026-08-26 across all five stores
(`gc bd -C <path> list -l observation --status=closed --limit=0`):

| store | observations |
|---|---|
| gc-toolkit | 73 |
| signal-loom | 53 |
| gascity | 16 |
| shutupandlisten | 13 |
| loomington (HQ) | 2 |
| **total** | **157** |

Of those, 65 carry `obs.source=operator` and 29 carry
`obs.endorsed=operator`. 150 events remain after deduplicating on
`obs.provenance`. The span is 2026-08-11 to 2026-08-24.

The audit read only the operator-sourced set. The profile states what the
operator values, so a miner-mined reviewer comment or a self-reported
correction is evidence for a *convention*, not for the profile. Every entry
below rests entirely on `obs.source=operator` observations.

## Method

The `learning-distill` rubric, applied by hand because the distiller order is
disabled (see [The distiller is off](#the-distiller-is-off)). Judgment 1
(standing or diff), judgment 2 (has it earned generalization), judgment 3
(adjudicate against what exists), judgment 5 (how the entry is written). The
two promotion gates were checked on every cluster:

- **Gate 1, source diversity.** `distinct_sources=1` on every cluster —
  every observation is `obs.source=operator`. The rubric's clearing key is
  `obs.endorsed=operator`, and the gate exists to stop a self-report →
  self-promote → self-inject loop with no external check. An all-operator
  cluster is the opposite case: the external check is the only source. Gate 1
  passes on that reading, and the operator's review of this PR is the same
  gate the rubric names.
- **Gate 2, remedy class.** Each entry states a concrete behavior on a
  recognizable trigger. Two candidate clusters failed this gate and were
  dropped; they are recorded under [Left out](#left-out).

Thirty feedback-pattern beads already existed, clustered by distiller runs
before 2026-08-15. Their rollups are stale — `tk-vglpm` records
`evidence_count=5, last_seen=2026-08-13`, and the same theme drew eight more
operator corrections through 2026-08-24. The audit reused an existing row
wherever one covered the cluster and seeded a new one otherwise, rather than
filing a parallel set.

## What was adopted

Each entry's anchor names its pattern bead, which is the bucket the
recurrence report attributes against.

| # | anchor | entry | evidence |
|---|---|---|---|
| 1 | `tk-vglpm` (existing) | Lead with the decision | tk-589ps, tk-638qo, tk-xrvfa, tk-ag4eb, tk-87zfxj, tk-p2dr0k, sl-t6if4, sl-vhw9n |
| 2 | `tk-3znt49` (new) | The operator's queues are state | tk-rlhkd, lx-6jjw, tk-1r0sv, tk-f0s4q2, tk-nv0z5m, tk-4l0ai, su-fr08x |
| 3 | `tk-uzkg2c` (new) | Derive a load-bearing claim | sl-xd9ta, tk-ztjtx, tk-awau8, sl-11vqf, sl-lcyh3, gc-gj2ri, sl-tgsdl |
| 4 | `tk-b80kkz` (new) | A rename is not a fix | tk-5d7q4, tk-zejs0, tk-exqf5, tk-6emwu, sl-vq0y2, sl-pzm2x |
| 5 | `tk-lz8mpv` (new) | Read a ruling for its intent | tk-5kezf, tk-0lapo, gc-xi5hg, tk-ladzj |
| 6 | `tk-tketyk` (new) | File work in the pass that names it | tk-yg0ndg, tk-odvidd, su-sw64, gc-y8vad |
| 7 | `tk-xgaeo` (existing) | Documentation is present-tense | sl-399cu, sl-kbn84, sl-24xpi, tk-9b68m, su-6yf70, sl-u1voc |

Entries 1 and 2 are adjacent and were nearly written as one. They stay
separate because their triggers differ: entry 1 fires while composing
something the operator will read, entry 2 fires while deciding whether to
put anything in front of them at all. `tk-vglpm`'s own body separates the
same two rules, and its residual list records that the second had no home
fragment. Entry 2 gets its own ledger row so the recurrence report can
attribute the two independently.

Entry 3 widens `tk-nr2ii`, which scopes the same failure to converse. The
evidence here spans an architecture doc, a mechanik measurement, and a gate
costing, so the row is new and cites `tk-nr2ii` as the narrower ancestor.

Entry 7 is an ADD against `tk-xgaeo`, not a duplicate of the two adopted
`#465` entries beside it. Those cover self-referential prose and sentence
shape; this covers tense and venue, which `tk-xgaeo` names and neither
adopted entry reaches.

The profile now holds 10 of its 12 entries. The two remaining slots are
deliberate headroom: a surface filled to its cap forces the next promotion
to displace before the operator has seen it once.

## Left out

Recorded so a later run does not re-derive them from scratch.

- **Prefer the standard path over a bespoke one** (tk-p3e1e, sl-8y4hr,
  tk-mjjqo). Four occurrences, genuinely recurring, but the three
  instances resolve differently — reuse an existing PR, reach for the
  standard remedy, own a full copy rather than an override. They rhyme;
  they do not fail the same way. Judgment 2, shared cause, not met.
- **The cost model is idle spin, not headcount** (tk-ds9mf, tk-0rg0p,
  tk-4l0ai, tk-t7rzf). Real and operator-sourced, but the remedy is a
  measurement question rather than a behavior on a trigger. Gate 2 routes
  this to engineering, and `tk-ueuij` already carries the pattern.
- **Enumerate the full set before declaring done** (`tk-48ru7`,
  evidence_count=6). Already carries `remedy_class=structural` and
  `promotion_hold=gate1-and-gate2-pending-tk-lv6q5`. The rubric's own
  worked example for Gate 2. Left where it is.

## What the audit did not do

The 44 operator observations behind these entries were **not** stamped
`obs.distilled`. Stamping marks an observation consumed so it never counts
toward the cadence gate again, and these entries are proposals until this PR
merges. Consuming the evidence for an unadopted promotion would hide it from
the run that should judge it.

The consequence is the designed one: the distiller's next run reads them as
pending, judges them against a profile that already carries the rule, and
NOOPs — which is judgment 3's stated path for an already-covered pattern
("Stamp the observations consumed and stop").

## The distiller is off

`feedback-distiller` is disabled on all four rigs by the 2026-08-15
tooling-spend overrides in the city's `city.toml`. The gate is lossless by
design: observations keep accumulating as beads, and a release processes the
backlog.

This audit is what that pause costs and what it does not. It does not cost
the record — 157 observations were waiting and readable. It costs the
conversion: the profile sat at three entries while 65 operator corrections
accumulated, and the pattern-bead rollups drifted a fortnight stale.

The recurrence report added alongside this audit
(`assets/scripts/learning-recurrence.sh`) is deliberately runnable without
the distiller, and reports its own coverage rather than a flattering zero.
Read on the corpus above it says: category repeat rate 5.3% over 142 distinct
categories for 150 events, and 38.7% attribution coverage. Both numbers are
floored by the distiller being off, and the report says so on both lines.
That is the honest input to a re-enable decision; the decision itself is the
operator's and is not part of this work.
