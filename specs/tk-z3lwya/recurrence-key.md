---
name: What the recurrence metric keys on (tk-z3lwya)
description: The corpus measurements behind keying the feedback-learning loop's success metric on the distiller's pattern and counting only recurrence after adoption, with no count of repeated capture categories. Read it before adding a count keyed on obs.category or on patterns, or to see why the miner names no correction slug.
---

# What the recurrence metric keys on

`assets/scripts/learning-recurrence.sh` counted two things. One was the
share of events whose `obs.category` an earlier event already carried. The
other, which it still counts, is the events the distiller attributed to an
adopted rule's pattern since adoption. The bead asked for the first count's
key to come from a controlled vocabulary, and named three ways: a fixed list
at capture, a category the distiller assigns, or dropping the count's claim
to measure recurrence. This records the corpus that decided it.

## The corpus

Read as of 2026-11-23T20:00Z from every store: 3,231 observations over 7
stores. The two windows are the 30 days before that moment and the 30 days
before those.

**The capture slug.** 2,104 events carried a slug, over 1,461 distinct
slugs, so the report withheld the rate as not discriminating. The share of
events repeating a slug fell from 44.6% (358 of 803) to 32.9% (247 of 750).
Nearly all of the fall is one automated capture: a triage review that files
the same slug on every review of one rig filed 128 events in the earlier
window, 127 of them repeats, and none after 2026-10-24. Without it the
earlier window reads 34.2% (231 of 675), 1.3 points above the later one. The
miner's captures add habit of their own: it was told to reuse a slug when one
fits, and 77% of its captures repeat a slug in both windows.

**The distiller's pattern.** The distiller stamps `obs.distilled` on 3,210
of the 3,231 observations, over 209 patterns. That is the category the
distiller assigns, and it needs no new key. Keyed on it, 93% of the later
window's events (947 of 1,022) and 95% of the earlier window's (1,266 of
1,334) repeat a pattern an earlier event drew. The share cannot fall while
the loop works, because a pattern draws repeats before the distiller
generalizes it: those repeats are the evidence it weighs. A fixed list at
capture lands in the same place, or splits as finely as the slugs, and adds
text to every agent's capture instructions.

**Recurrence after adoption.** Counted from the day after a rule's adoption
date, the events attributed to its pattern say whether a correction the city
acted on came back: 27 of the 29 adopted entries that carry a pattern
anchor drew events after adoption. Attribution covers 98% of the later
window's events.

## The call

No key makes a count of repeats of any earlier event measure the loop: a
key as fine as the slugs measures slug reuse, and a key as coarse as the
patterns saturates. The report counts recurrence after adoption alone. The
duplicate-capture collapse keys on the pattern instead of the slug, so a
self-report and the miner's reading of one post are one event whatever slug
each capture minted. The miner names no correction slug (`obs.correction`):
the report read it only for the dropped count and for the old collapse,
which swapped it in for the outside capture's category.

On the live count as of 2026-11-23T20:00Z, the new collapse leaves the same
27 of 29 entries recurring and changes two things. The summed count falls
from 687 to 668, where a post's two captures had counted as two events. One
entry's count rises from 8 to 9, where the old collapse kept one capture's
pattern and dropped the other's.

The build that carried this change made the call among the three ways, and
the operator's review of its pull request rules on it.
