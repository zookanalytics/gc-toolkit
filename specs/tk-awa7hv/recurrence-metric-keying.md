---
name: Recurrence metric keying
description: Whether a slug-equality key can measure recurrence, answered against the live corpus, with the reporting change it forced.
bead: tk-awa7hv
---

# What key does learning-recurrence.sh compare on?

`assets/scripts/learning-recurrence.sh` is a shell script with no model
call. It compares observations on two literal string keys:

- **M1** groups on `obs.category`, a free-text slug the capturing agent
  mints when it files the observation. An event counts as a repeat when an
  earlier event carried the identical slug.
- **M2** groups on `obs.distilled`, the pattern-bead id the distiller stamps
  when it attributes an observation to an adopted rule.

Neither is a similarity comparison. Two observations describing the same
correction in different words share no key and never meet.

## Can slug equality measure recurrence?

No, not while the slug is minted per capture. The live corpus settles it.

At the time of writing the report reads 164 events after provenance dedup,
164 of them categorised, across 155 distinct categories. It counts 9
repeats, which is 5.5 percent.

Those numbers are not independent. Repeats are, by construction, the events
beyond the first in each category, so:

    repeats = categorised - distinct = 164 - 155 = 9

The measured 9 is exactly that difference. M1's numerator is fully
determined by how many distinct slugs capture minted, and carries no
information about whether corrections recurred. At 1.06 events per category
the key almost never fires, so the rate reports slug-minting behavior under
a label that reads as loop health.

This is the failure the script already guards against elsewhere. Its header
refuses to report on a partial city because a recurrence number computed
over part of the city "reads as improvement". A 5.5 percent repeat rate
printed beside the words "repeat feedback" reads the same way, and for the
same reason.

## What changed

The verdict now lives in the data rather than only in the prose. The report
carries `m1_category_repeat.key_discriminating`, true when the corpus
averages at least 1.5 events per category. When it is false:

- the text report prints `rate withheld` in place of a percentage, for both
  the current and the prior window;
- the `HIGH FRAGMENTATION` line states the identity above, so a reader can
  see why the rate was withheld rather than being asked to trust it.

The raw `rate` field stays in the JSON for anyone who wants it. Withholding
is a reporting decision, not a deletion of data. The 1.5 threshold now has
one home in the report object; the text renderer reads the verdict instead
of recomputing the comparison.

## What was deliberately not changed

The real fix is on the capture side: `obs.category` has to come from a
controlled vocabulary before equality on it can mean anything. That touches
every agent's observation-filing fragment and every consumer of the key, so
it is filed separately as tk-z3lwya rather than folded into this rework.

M2 needs no change. Pattern-bead ids are a controlled vocabulary, so
equality on `obs.distilled` is meaningful. M2 is limited by attribution
coverage, which the report already states, and only the distiller stamps it.

## A side effect worth naming

The inventory counts one row per carrier file, so a bullet adopted into two
role fragments produces two inventory rows and lifts `adopted_total` by one.
Moving the code-comments entry into both the polecat and mechanik conventions
fragments did exactly that. The count is adoptions per carrier file, which is
the granularity the cap check needs, so this is correct rather than a
miscount. It is recorded here because the total moved for a reason unrelated
to any new adoption.
