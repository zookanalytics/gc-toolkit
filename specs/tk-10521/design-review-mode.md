---
name: Decision — a documents-only branch is reviewed as a design, not as code
description: Why tk-10521 was re-scoped from "spec beads need a lower convergence cap" to "the signoff method had no design-document mode", what was rejected (skipping the gate; a lower cap) and why, and an honest round-by-round replay of the seven-round case against the adopted rule.
---

# A design document has no bounded review surface

Work record for `tk-10521`. The change it produced is in
`skills/signoff-review/SKILL.md`; what is authoritative about the
resulting behavior is that file, not this one. This document records the
reasoning, including the two remedies that were rejected.

## The question, as re-scoped

The bead was filed as a process proposal: a spec/design bead "should
either not ride the code gate, or should carry a distinct (lower) cap
plus an explicit 'findings become implementation notes after round N'
rule."

The operator then narrowed it (2026-08-22): *"I'm not sure it's a hard
rule, just want to make sure we're using tokens efficiently."* The
measurement that followed, recorded in the bead's notes, closed off the
spend argument entirely:

- The six rework sessions on `polecat/sl-kg9z6.1.1` cost **$23.37** of
  Claude spend against **$1,896.27** city-wide in the same window —
  **1.2%**.
- The review side runs on a different provider (`codex` / `gpt-5.5`) and
  consumes **no Claude tokens at all**. Its recorded $0.00 means
  *unpriced in this sink*, not free.

So the bead's own instruction was: re-scope or close on **cycle time**
(the implementation bead `sl-9varn` sat blocked ~33h and Track 1 produced
zero code) and **operator attention** (each past-cap round needed a
manual re-gate authorization) — not on spend. This is the re-scope.

## Diagnosis: one mode, and it is a code mode

`skills/signoff-review/SKILL.md` is inlined verbatim into every
dispatched review bead by `assets/scripts/review-dispatch-body.sh`, so it
is the single authored instruction every reviewer receives. Every part of
it past §2 was calibrated for code: §3 mandates running the suites the
diff touches, §4's checklist is Correctness / Contract / Testing /
Readiness, and §5 grades **P1** as "wrong behavior on a reachable input"
— a blocking verdict.

Applied to a 770-line concurrency design, that scale has no terminus. A
competent reviewer can always find one more reachable interleaving or one
more platform fact the design did not anticipate, and each one is a P1 by
the wording, so each one forces another spec rework round.

The clearest evidence is the round-3 review bead `sl-0ek5f`, which graded
*"Convex scheduled actions execute at most once, with no retry on
transient failure"* as **P1** — and whose own verification line reads:

> `No vitest/tsc run: the branch changes only the spec document, and the
> blocking issue is a design-level failure path for scheduled actions
> rather than executable code.`

The reviewer graded correctly under the rule it was given. The rule is
what forced the round. That is a defect in the instruction, not in the
review — and the bead is right to insist the reviews were not the
problem: all seven rounds found something genuinely new and real.

What ended the loop was the operator hand-writing the missing rule on the
anchor: past this point a finding this narrow ships the spec and rides
with implementation `sl-9varn`. The round-7 reviewer read that note,
returned COMMENT, appended the remaining P2 to `sl-9varn`, and the gate
went green. The adopted change is that rule, made mechanical.

## Rejected: don't gate design branches

The bead's first option. Refuted by its own evidence — round 1
(`sl-zlx95`) found the serialization rule internally contradictory and a
source turn droppable. Skipping review would have shipped that. Design
review earns its place; only its severity calibration was wrong.

## Rejected: a lower convergence cap for spec beads

The bead's second option, and it makes the stated cost **worse**.

The cap's terminal action is to stop dispatching and route to a human
(`assets/scripts/signoff-round-cap.test.sh`: "the cap stops the SPAWN and
routes to a human, and it writes NOTHING under `check.`"). It is a
spawn-stopper, not a mode-changer. Capping a design branch *sooner*
therefore spends operator attention **earlier**, which is exactly the
cost the re-scope says to reduce. The observed run shows the mechanism:
the cap fired at round 3 and the remaining four rounds ran on
hand-authorized re-gates. The cap did not brake the loop; it converted it
from automated to manual.

A round-numbered rule also needs round counting, and `tk-vx2et` records
that the counting exists in only one of the two dispatchers.

## Adopted: classify the branch, not count the rounds

Added to `skills/signoff-review/SKILL.md`, at the end of §2 where the
reviewer has just read the diff and the classification is free:

- **Discriminator, derived from the diff.** `MODE=design` when every
  changed path is Markdown under `specs/` or `docs/`; anything else makes
  it `MODE=code`. The test reads as "is any path *not* a document", so it
  fails toward `code`, the stricter mode. An empty diff refuses outright
  rather than defaulting to `design`. No filer cooperation and no new
  metadata key — a `task_kind=spec` flag would have to be remembered at
  dispatch time, and a forgotten flag fails silently toward the wrong
  mode.
- **What still blocks** in design mode: self-contradiction, a false claim
  about what already exists, or a missing decision the document exists to
  make. These can only be fixed in the document.
- **What does not block**: an implementation discovery (a runtime,
  library, or platform fact an implementer meets in the first afternoon
  and settles with a test), and one-more-interleaving findings. Graded P2
  and appended to the **implementation bead** — the one the design anchor
  `blocks`, resolved with `gc bd dep list "$ANCHOR" --direction=up -t
  blocks`, which excludes the rework children (`parent-child`) and convoy
  trackers (`tracks`) that also point at the anchor. If that is ambiguous
  the finding stays in the verdict under `CARRY TO IMPLEMENTATION:`; a
  finding parked in a verdict is recoverable, one appended to the wrong
  bead is not.

The rule keys on a finding's **class, not its round number**, so it
applies from round 1 and needs no counting.

## Honest expected effect

Replaying the seven rounds against the adopted rule — this is the
measure, and it is not "7 → 1":

| Round | Review bead | Finding | Under the new rule |
|---|---|---|---|
| 1 | `sl-zlx95` | serialization rule internally contradictory; source turn droppable | **still blocks** — self-contradiction |
| 2 | `sl-dsu6a` | `openTurn` schedules unconditionally; `scheduler.cancel` race on queued | **note** — an interleaving plus a platform fact about `cancel` |
| 3 | `sl-0ek5f` | Convex scheduled actions run at-most-once ⇒ queue wedges before timeout | **note** — platform fact |
| 4 | `sl-n29by` | user message fed to the prompt twice (history + current) | **still blocks** — the document specifies behavior that is wrong as written |
| 5 | `sl-6ldna` | no per-turn record visibility cutoff for the worker prompt | **still blocks** — a missing decision |
| 6 | `sl-zko42` | cutoff keyed to attach time, not source arrival | **still blocks** — a stated decision that is wrong, not a missing one |
| 7 | `sl-gznnc` | FIFO vs coalescing (already COMMENT, by the operator's hand-written rule) | **note**, now without the hand-written rule |

Two of the six blocking rounds become non-blocking, and round 7's
outcome stops depending on an operator writing the rule by hand. The four
remaining blocks were genuine document defects and **should** block.

So the claim is not that the round count collapses. It is that the two
finding classes with **no natural terminus** — platform facts and
further interleavings — leave the blocking path, which is what made the
loop unbounded. The remaining blocking classes are finite: a document has
only so many self-contradictions and unmade decisions.

## What deliberately did not change

- **No gate mechanics.** No cap value, no dispatcher, no marker, no
  `check.` write. The change is reviewer guidance; the four duplicated
  cap arms are untouched.
- **No gate is released.** Design mode still blocks, on a smaller and
  finite set of defect classes. It cannot land a document nobody reviewed.
- **The cap stays the backstop** for a document that genuinely keeps
  producing real defects — which is the role it should have.
- `tk-vx2et` (the cap living in only one of two dispatchers) and
  `tk-j5wrs` (no canonical definition of an anchor's in-flight set) are
  separate defects in the same machinery and are not addressed here.

## Verification

`assets/scripts/review-dispatch-body.test.sh` — 49 assertions before,
**68 after**, 0 failed. The new arms:

- `(DESIGNMODE)` asserts the rule reaches the **generated review-bead
  body**, not merely the skill file — the mechanism is worthless if it
  does not arrive at the reviewer.
- `(CLASSIFY)` extracts the classifier verbatim from between the
  `review-mode-classify` markers in the skill and executes it against a
  fake `git`, following the same
  extract-the-shipped-snippet idiom as
  `assets/scripts/signoff-round-cap.test.sh`. 13 cases, including every
  fail-toward-`code` direction and the empty-diff refusal. A retyped copy
  of the logic would prove nothing about what reviewers are told.

Each arm was mutation-tested in a parallel tree: renaming the section
heading fails `(DESIGNMODE)` (1 failure); inverting the classifier's
`grep -qv` fails `(CLASSIFY)` in both directions (9 failures); deleting
the markers fails the extraction (1 failure). The tree returns to 68/0
when restored.
