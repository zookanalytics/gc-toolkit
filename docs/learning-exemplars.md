---
name: Learning Exemplars
description: The adopted exemplar corpus — before/after pairs the feedback-learning loop promotes when a lesson is easier to show than to state. Resolved on demand by reviewers, never injected into a prompt.
---

# Learning Exemplars

A carrier for lessons that resist being written as a rule. Some corrections
are exact but not compressible: the difference between a decision brief that
leads with the ask and one that buries it is obvious side by side and
mushy in a sentence. Those promote here as a before/after pair instead of
becoming a bullet nobody can apply.

## Scope

**Mandate.** The adopted exemplar corpus: what an exemplar is, the shape each
entry takes, and the budget the corpus holds.

**Boundaries.** How an observation earns promotion into any carrier is the
`learning-distill` rubric's, and the loop's conventions are
`docs/feedback-learning.md`'s. Neither is restated here.

## What an exemplar is

An exemplar is a concrete pair — the shape that drew the correction, and the
shape that answers it — with one line naming the trigger that selects it.
The pair does the teaching; the line only says when to look.

An exemplar is **resolved on demand, never injected**. Reviewers read the
corpus while judging a diff (`formulas/mol-review.toml`, step `review`); no
prompt renders it on every turn. That is the whole reason the carrier
exists: a lesson that needs 20 lines to show cannot be paid for on every
turn of every agent, and compressing it to a bullet loses what made it
teachable.

An exemplar never substitutes for a mechanism. When a correction points at a
structural failure — a verification gap, a race, a missing check — the
remedy is an engineering bead, the same as it would be for a prose bullet.
What routes here is the case where an agent that intends the right thing
still cannot tell which shape is right until it sees both.

## Entry shape

Each entry is a `###` section preceded by its anchor, carrying the pattern
bead so recurrence stays attributable:

```
<!-- rule:<pattern-bead> src:<short provenance refs> adopted:<YYYY-MM-DD> -->
### <what the pair is about>

**Trigger.** <the recognizable situation that selects this exemplar>

**Instead of:**
<the shape that drew the correction>

**Write:**
<the shape that answers it>
```

Both halves are real: the "instead of" is drawn from what actually happened,
with identifiers scrubbed to the role. An invented bad example teaches an
invented lesson.

## Budget

The corpus holds at most **8** entries. It is read in full during a review,
so its cost is paid per review rather than per turn — real, and bounded by
this number. A promotion past the cap names the entry it displaces, the same
rule the always-injected fragments carry.

<!-- adopted exemplars follow; one anchor per entry, immediately above it. -->
<!-- rule:<pattern-bead> src:<refs> adopted:<date> -->
<!-- seeded empty: no exemplars adopted yet. The anchor comment above is the
     exact format each promotion PR copies. -->
