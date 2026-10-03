---
name: Plan-to-beads — make a plan's targets tracked work at the moment it lands
description: Decision record for tk-hnrind. Recommends the mechanism that turns a landed plan's targets into tracked beads — a plan declares its targets in a structured manifest (each naming the bead that will build it, or marked dropped with a reason), and the merge writer refuses to land a plan whose declared targets do not all resolve, modeled on the render-seed-audit --check-merge gate merge.sh already runs. Argues against convention-only (tried in PR#455, failed on the next plan) and against a document-scanning doctor audit (tried as tk-dks4kk/PR#496, rejected as brittle and after-the-fact). Read it to accept or reject the mechanism before the implementation (tk-liq8xf, blocked on this) is built. Supersedes the tk-dks4kk attempt.
---

# Plan-to-beads: tracked at the moment a plan lands

## The decision

A plan proposes work as a list of targets. Turning each target into a tracked
bead is a manual step a person does after the plan merges, and when one is
missed nothing notices: the plan reads as done and the target is lost. The
consolidation plan (`specs/tk-z9nln/consolidation-plan.md`) lost its largest
target this way. The target was to reduce `gc-helm.sh` to a thin renderer, it
was never filed as a bead, and that file kept growing while no tracked work
pointed at the gap. "This plan landed, and these are the beads it produced" has
no answer a query can give, because nothing links a plan to the beads it names.

**Recommendation: make a plan declare its targets, and make the merge refuse a
plan whose declared targets are not all tracked.** Two small parts:

1. A plan lists its targets in a structured manifest, each naming the bead that
   will build it or marked dropped with a reason.
2. `merge.sh`, just before it lands a branch, reads any plan in that branch and
   holds the merge if a declared target names no resolvable bead. This reuses
   the gate the repo already runs for `generated/seed-audit`.

The alternatives, and what each costs:

| Option | What it costs | Why not |
|---|---|---|
| Gate plus declared manifest (recommended) | A small probe script, its hermetic test, a few lines in `merge.sh`, and one short convention note | — |
| Convention only, no watcher | Nothing to build | It is what we already have, and it is what failed. The rule to file each target as a bead was in force when the consolidation plan dropped one. A convention with no watcher is the status quo that produced the incident. |
| Document-scanning doctor audit | A doctor check that reads landed plans and reports gaps | Tried as tk-dks4kk (PR#496) and rejected: brittle, because it parses the prose target table, and after the fact, because it reports a plan only once the branch is already wrong. |

**What I am asking.** Accept or reject this mechanism before the implementation
is written. The build is tracked by tk-liq8xf, which is blocked by a dependency
edge on this bead and will not be offered as work until this decision lands. If
the ruling is convention-only, that bead's scope collapses to the convention
note, with no gate and no script.

## The problem, precisely

A plan in this repo is a committed markdown file under `specs/`. There is no
`plans/` directory and no formal plan type, and the few plans that exist use
different layouts. A plan's targets are rows in a prose table, and the
plan's own boundary states the contract: "Each surviving target should be filed
as its own bead from this document" (`specs/tk-z9nln/consolidation-plan.md`).
Nothing enforces that sentence. `docs/epics.md` frames the same gap from the
epic side — a spec that spans more than one unit is "an epic-level elaboration
artifact, and the units it describes are filed and land separately" — and also
names no mechanism that makes the filing happen.

The failure is quiet by construction. A plan merges like any document, and a
merged plan reads as finished. The filing of its targets is a separate act with
no tie to the merge, so a target that is never filed leaves no trace: there is
no bead to be open, no edge to dangle, no query that returns the gap. The
consolidation plan showed two shapes of the same failure: the largest target
was never filed, and a second target that was split into two beads had one half
go unfiled. A set can be most of the way converted and still look complete.

The cost of leaving this unsolved is not historical. It is paid again by the
next plan with more than one target, which can drop one the same way, and by
every reader who asks which beads a plan produced and finds the question has no
answer.

## Why convention alone is not enough

Convention-only is not a hypothetical cheaper path. It is the path already
taken, and it already failed. PR#455 measured this failure, stopped
deliberately at a documentation convention, and recorded that the real
guarantee would require a gate, a trade "to be made deliberately by [the
operator], not smuggled in" under a documentation change. The very next plan
dropped a target. The standing rule that a polecat must "put the bead id in the
row that proposed it" was in force the whole time. A rule with no point of
enforcement did not prevent the drop, and asking the same rule to try harder
will not either.

So the honest reading is that the operator's own earlier conclusion still
holds: closing this gap means a gate. The open question this proposal answers is
not whether to have a gate but where it fires and what it reads, because that is
exactly where the rejected attempt went wrong.

## Why the merge is the right moment

The rejected attempt reached for a gate too, then argued itself out of a
merge-time one. Its reasoning: when a plan merges its targets are not filed yet,
so a gate then could only ask the author to promise, which is what prose already
did, and the real drop happened in the hours after the merge, so a check should
read the claim back after the fact. That holds only while the filing stays after
the merge.

This proposal moves the filing before it. A plan names the bead for each target,
and the gate checks that each named bead resolves, so a plan cannot merge while
a target it names has no bead. That is not a promise; it is the tracked work
already existing. The failure the earlier design caught after the fact becomes
one that cannot land. It is prevention where that design chose detection, and it
matches the standing preference for a design in which the fault cannot recur
over a check that reports it once it has. The author does more up front, filing
a bead per target before the plan lands, which is the order the "put the bead id
in the row" rule already asks for: the plan is the pass that names the targets,
so it is where they should be filed.

## The mechanism

### A plan declares its targets

A plan carries a structured manifest the gate can read without parsing prose.
Each entry either names the bead that will build that target, or marks the
target dropped with a reason. A target split across more than one bead names
each of them, and the gate verifies every named bead, so a split cannot hide an
unfiled half, which is the shape that let one target slip before. The
human-facing target table stays as it is; the manifest is the machine-readable
twin, kept small and fixed in format so a shell probe reads it with a line match
rather than a table parser. Frontmatter is the natural home, since every spec
already carries frontmatter, but the exact field is an implementation choice.
The binding is a reference the gate resolves, not a `parent-child` edge: a
`parent-child` edge would place the targets under the plan in dispatch
readiness, and a tracking link should not change what the pool serves.

The "dropped, with a reason" case matters: plans legitimately discard targets on
measurement, and a dropped target with a stated reason is tracked, while a blank
entry is the failure the gate catches. This mirrors the pattern `docs/epics.md`
already ratifies — a unit is either a member or "explicitly recorded as
standalone with a reason; no work is a silent orphan."

A plan opts in by carrying the manifest. A file that carries one is held to it:
every entry must resolve to a real bead or carry a drop reason. A plan that
carries no manifest at all is the one case the gate cannot see, and that is
addressed under the honest limit below.

### The merge refuses an unresolved plan

The enforcement point is `assets/scripts/merge.sh`, the single writer of merged
truth, in the block that runs just before the squash. This is the one place that
sees what a branch would land before it lands, and it already hosts exactly this
shape of check for `generated/seed-audit`: it builds the merge result in memory
with `git merge-tree --write-tree`, calls `render-seed-audit.sh --check-merge`
to inspect that result, and holds the merge with an escalation to a human visit
when the result is wrong. The seed-audit gate's own comment draws the
distinction this proposal rests on: the after-the-fact doctor check "reports it
only once the landing branch is already wrong," so the merge gate exists to
catch it before.

The plan-targets gate is a sibling probe called from the same block. When the
merge result contains a plan that declares a manifest, the probe resolves each
declared bead against the stores the refinery can read and confirms each dropped
target carries a reason. If any entry resolves to nothing, the merge is held and
a visit is filed, with the offending plan and entry named, the same hold-and-
escalate contract the seed-audit gate uses. The probe is inert on every merge
that lands no plan, so it costs a path check on the common case and a few store
lookups on the rare one.

## Why this is not the approach that was rejected

The rejected attempt and this one share an intent. They differ on each point
the operator's objections named.

- **Not after the fact.** It fires at the merge, not on a later patrol. The
  reasoning is in "Why the merge is the right moment" above.
- **Not document-scanning.** The rejected attempt parsed the prose target
  table, which is where its brittleness lived: skipping fenced code blocks,
  verifying a bead in each cell, counting rows. A structured manifest removes
  every one of those. The probe reads a declared list and checks referential
  integrity, the same shape as a foreign-key check, with no table parser and no
  inference about which prose is a target.
- **Nothing in `docs/file-structure.md`.** The convention for how a plan
  declares its targets belongs where plans and epics are defined, not in the
  high-level document that says only what kinds of documents exist and where
  they go. The mechanism's operating detail lives in the probe script and this
  spec.
- **No embedded counts.** The manifest is a list, and the probe counts its
  entries at run time. No count of targets or checks is written into any prose
  document, so nothing goes stale.

## Cost, risk, and the honest limit

The build is a probe script, a hermetic test beside it in the style every
doctor check and merge helper follows, a few lines wiring it into the merge
block, and a short note documenting the convention. It is not the scale of the
rejected attempt, and it reuses an existing harness rather than adding a new one.

The real risk is that the enforcement lives in `merge.sh`, which is load-bearing
and careful. That risk is bounded by precedent: the seed-audit gate is the same
shape in the same block, path-gated so it is inert unless specific files land,
and its failure mode is a hold with a human visit rather than any change to what
merges. A false hold blocks a plan's merge until a person clears it, which is a
safe failure, not a corruption. The probe should be written to the same
standard: it asks the fetched refs, not a working tree, and an undetermined
result holds rather than merging blind.

The honest limit is the opt-in. A plan that never declares a manifest is a plan
the gate cannot see, because the only way to catch it would be to infer plan-
hood from prose, which is the brittle inference this proposal rules out. That
gap is narrower than today's, where nothing is checked at all, and it is bounded
by review: the arch and pm checks can confirm that a plan-shaped document
carries its manifest. The mechanism makes the existing convention enforceable at
the moment it matters; it does not claim to detect a plan that hides what it is.

## What this defers to implementation

Accepting this decides that enforcement fires at the merge and reads a declared
manifest, not that every detail is settled. Left to tk-liq8xf: the exact
manifest format and field, how a file signals it is a plan, how a declared bead
is resolved across stores, and whether the plan-targets property is also
registered as an invariant in `docs/component-model.md` with the merge gate as
its named checker. A redundant after-the-fact doctor mirror is deliberately not
recommended, since that is the form the operator rejected. Nothing in the
implementation lands in `docs/file-structure.md`.
