---
name: Plan-to-beads — declare targets with a binding, check it before merge
description: Decision record for a right-sized plan-to-beads mechanism. A plan declares its targets in an explicit marked block, each row bound to a bead or a stated non-bead disposition, and a structural check on the pull-request test lane refuses a declared target with no binding. Chooses this over a merge-path gate, a patrol audit, and live store resolution; keeps convention-only as the fallback. Supersedes specs/tk-hnrind; tk-liq8xf implements after arch/pm review.
---

# Plan-to-beads: declare targets with a binding, check it before merge

## The decision

A plan declares its targets in an explicit, delimited block, and each target row
carries a binding: the bead that will build it, or a stated non-bead disposition
(`none — <reason>`, `landed — <what>`). A structural check runs on the existing
pull-request test lane and fails when a declared target row has no binding. No
gate is added to the merge path, no bead id is resolved against a live store, and
nothing lands in `docs/file-structure.md`.

This buys one guarantee and makes one question answerable. The guarantee: a plan
that opts in cannot merge with a declared target that has no bead. The question,
answerable by reading the block: what did this plan produce.

## The problem

A merged plan reads as done. Merging is instead the moment its targets should
become tracked work. A target can sit in a plan as a table row and a line of
prose intent, never become a bead, and merge with nothing noticing. That is what
happened to the helm-renderer target in the consolidation plan, whose target
table has no column for a bead and whose binding rule lives only as a sentence
under Boundaries. "What did this plan produce" has no answer to read.

## What any mechanism here can and cannot guarantee

Coverage equals declaration discipline. A mechanism can check that the targets a
plan *declares* each carry a binding. It cannot supply a target the author never
wrote down. The target that is never declared stays the author's and the
reviewer's to catch, and no check moves it.

This matters because it bounds what to claim. "Makes a plan's targets tracked
work" overreaches and is the framing to drop. What holds: a plan's *declared*
targets each carry a binding, checked before merge, and are queryable.

## How a file signals it is a plan

A file signals it is a plan by carrying an explicit targets marker, not by its
filename and not by its prose. Filename and prose are the wrong signal twice
over: a plan can be named `proposal.md`, a grounding doc can discuss "the plan,"
and deciding which sentences are targets by reading prose is the brittleness that
sank the earlier audit. So for this mechanism, plan-hood *is* the presence of a
declared, delimited targets block — the signal and the declaration are one act.
Resolving this is the point the superseded design left to implementation, and it
is settled here because it sets the mechanism's reach.

The cost of this answer: a plan that carries no marker is invisible to the check.
That is the opt-in limit — named and accepted, the same limit any
declaration-based mechanism carries, made explicit rather than papered over.

## The mechanism

**Declare.** A plan marks a targets block and binds each row. An explicit
delimiter lets a reader and a check find the block without guessing; the
`<!-- plan-targets -->` marker drafted in the earlier attempt is a fitting
primitive. Each row's binding cell holds a bead id, or `none — <reason>`, or
`landed — <what>`. This formalizes the standing "put the bead id in the row that
proposed it" convention and turns "what did this plan produce" into a grep. It
stands on its own with no check behind it.

**Check.** A structural check flags a target row, inside a marked block, whose
binding cell is empty or malformed. It runs at pull-request time on the existing
test lane, which stubs the ledger and runs with no city — all a structural check
needs, since it reads the file and not a store. A failing check is a red lane,
and the merge path already refuses a pull request with a red lane, so a bad merge
is blocked through machinery already on that path rather than a new gate. It is
reversible by deleting one test. Every finding it can produce is an unbound
declared target, so it meets the bar the pack holds its static checks to: every
finding is a defect, not a judgment call.

## Alternatives, and why not

**A gate in the merge path** (the superseded recommendation). The merge script is
large and load-bearing, and a durable gate there is heavier than a guarantee the
pull-request check already delivers before merge. The seed-audit merge gate shows
a path-gated probe there is *possible* safely; possible is not warranted when a
cheaper surface reaches the same failure at the same moment.

**Resolving the bound bead against a live store** (does the id exist, is it still
open). This needs a running ledger, so it cannot ride the hermetic pull-request
check; it forces a merge gate or a patrol. A mistyped or deleted id is rarer and
lower in severity than a missing binding, and it surfaces when someone follows
the link. Left as an optional later backstop a patrol could carry, outside the
core.

**A document-scanning patrol audit** (the tk-dks4kk approach). Ruled out by
constraint, and the objection holds: it reports after the branch is already
wrong, and when it infers targets from prose it is brittle. This design avoids
both — it reads an explicit marker rather than inferring, and it runs before
merge. What it keeps from that attempt is the marker primitive; what it drops is
the after-the-fact, store-resolving check.

**Authoring by construction** (a helper that files the bead and writes the bound
row in one step). It removes the unbound-row gap at the source, but only for rows
added through it, and plans here are written by hand. A complementary convenience
a later bead can add, not the mechanism.

**Convention only** (the marker and review, no check). It delivers the
queryability and makes the gap visible in review, and it is the honest cheaper
outcome if the check is judged too much. Not recommended: an earlier stop at
convention-only failed on the next plan, which is the evidence that the
declaration needs a check behind it.

## Lineage

Supersedes `specs/tk-hnrind`, whose merge-gate-plus-manifest design was sent back
as heavier than its guarantee with the plan-signal question deferred. Keeps the
marker primitive from the `tk-dks4kk` attempt while dropping its patrol and its
store resolution. A still-earlier stop deliberately halted at convention-only and
recorded that a real guarantee needs a gate chosen by the operator; this record
proposes the lightest gate that is still a gate.

## Left to implementation

`tk-liq8xf` builds this, after arch/pm review of this record. It settles the
marker grammar and the exact binding-cell forms; the home for the written
convention, which is not `docs/file-structure.md` but the work-quality fragment
that already carries "put the bead id in the row"; whether to also ship a
portable detector for rigs whose plans fall outside this repo's test lane; and
whether the optional store-resolution backstop earns a patrol.
