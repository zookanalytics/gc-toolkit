---
name: Lifecycle composition — the bead → PR → visit seam and how completion propagates back
description: How the pack's three lifecycles compose — the rule for recording a wait as a graph edge, who re-derives it, and how a finished piece of work propagates back to the conversation that asked for it. Read it when work crosses from one lifecycle into another, or when something finished without anyone noticing.
---

# Lifecycle composition

The pack runs three lifecycles, and each already has exactly one owner:

| Flow | Owner |
|---|---|
| bead | [work-bead-state-machine.md](work-bead-state-machine.md) |
| PR | [refinery-merge-cadence.md](refinery-merge-cadence.md) |
| visit | [gascity-human-engagement.md](gascity-human-engagement.md) |

This document owns none of them. It owns the **seam**: the place where a
conversation routes work out of a subject, that work becomes a bead, the bead
becomes a PR, the PR lands — and the result has to find its way back to the
subject that was waiting for it.

The seam is where the expensive failures live. Each of the three lifecycles
runs correctly on its own; what fails is the handoff between them, and it fails
the same way every time — a wait gets recorded once, in a form nothing can
re-evaluate, and then nothing ever re-asks the question. Before this document
there was nothing to correct when an instance was found, so each one was
rediscovered from the code.

## Scope

**Mandate.** The composition rule between the pack's lifecycles: how a wait
created in one lifecycle is recorded so another can act on it, which side
re-derives it, and how completion propagates back to the party that is waiting.
It speaks authoritatively on that rule and on the failure class that appears
when the rule is broken.

**Boundaries.** It does not restate the three lifecycles — each has one owner
above, and this doc defers to them rather than summarizing them. It is not a
fourth lifecycle narrative: it describes no state a bead, PR, or visit passes
through. It does not carry the board's rendering rules or the converse
sitting's procedure, which belong to
[gascity-human-engagement.md](gascity-human-engagement.md), nor the routing
mechanics, which belong to
[gascity-routing-model.md](gascity-routing-model.md).

## The rule

**A wait is a graph edge, re-derived on every read. A conclusion is prose,
stored once and never cleared. Never the reverse.**

Three clauses, each of which has been learned the expensive way:

### 1. Record the wait as an edge, not as a sentence

When a sitting routes work out of a subject and parks it, the sentence it
writes — *"holding, awaiting the fix"* — is for a human to read. It is not the
record of the wait. The record is an edge to the specific bead being waited on.

A sentence freezes at the moment it is written and is never true again. Two
subjects, one genuinely blocked and one entirely finished, produce
mechanically identical rows if the only difference between them is prose. The
board cannot tell them apart, so it shows both as wanting nothing, forever.

The mechanism: `gc-helm takeaway <bead> "<text>" --waiting-on <work-bead>`,
repeatable, writes a `blocks` edge beside the takeaway string
(`assets/scripts/gc-helm.sh`, `takeaway`). The prose still gets written — it is
the durable record of what the sitting concluded, and it is never cleared. The
edge is what makes the wait *machine-answerable*.

**This clause is now checked.** `doctor/check-wait-is-an-edge` (component-model
I1) reports an open bead whose prose says it is waiting on, blocked by or gated
on a named bead where no edge records it either way. Measured 2026-08-24: 16
across four rigs, and **13 of them named a bead that had already closed** —
which is this section's argument, measured. The check asserts the EDGE exists;
it never asks for the sentence to be removed, because the sentence is the
conclusion and the conclusion is prose.

### 2. The waiting side re-derives; it never trusts stored state

Whoever needs to know "has this landed yet?" asks the question fresh, at the
moment it needs the answer. It does not read a status field that something else
was supposed to have updated.

This is the clause that carries the most weight, because it is what makes the
rule robust against the rest of the system being imperfect. The board derives
`disposition_due` per render — parked, with a non-empty waiting set, all of
whose members have closed (`assets/scripts/gc-helm.sh`, mirrored in
`services/helm/internal/board/derive.go`). Nothing is stored, so nothing has to
be cleared later, and no cleanup path can be missed.

The same edges answer the same question for the two human-gated kinds, and there
the answer points the other way: a `decision` or `gc.routed_to=human` row whose
takeaway is recorded and whose waits have all landed stands DOWN out of the
attention band rather than up out of the parked floor, reading "ruled — close or
extend" (`tk-b3rga`, *Until it is answered* in `services/helm/README.md`). One
bead can be gathered under both readings, so `disposition_due` yields to the
stand-down on a human-gated subject: the two would otherwise band the same bead
two ways and the louder row would win the dedup.

Concretely: `tk-puh9d` (open since 2026-08-02) is the defect that a bead's
stored `blocked` status never auto-clears when its dependencies close. The edge
is right there and nothing re-derives from it. The board is unaffected by that
bug — not because it was fixed, but because the board never reads the stored
status in the first place. A re-derived answer routes around a stale stored one.

**The join point is the bead closing, not the PR merging.** This is what makes
the PR lifecycle composable at all: the refinery is the single writer of merged
truth, and it closes a bead only after verifying the merge actually carried the
work (see [work-bead-state-machine.md](work-bead-state-machine.md), *Merge: one
writer of merged-truth*). So `closed` is the one signal that means *landed and
verified*, and the waiting side keys on it. A waiting party that watched
GitHub directly would be reading a different, earlier fact.

**Fail quiet, in the direction of not acting.** A blocker counts as landed only
on a positive `closed`. An id that cannot be answered for — a store in another
rig, an `external:` reference, a query that timed out — reads as *still open*
and the subject keeps waiting. This is deliberate and asymmetric: a missed
promotion costs a glance, while a false "this is finished, go dispose of it"
invites closing a subject whose work is still in flight.

### 3. Completion propagates as a push, not a colour change

Deriving the answer is not the same as delivering it. A board that turns a row
`ELEVATED` has computed the right thing and told nobody; it still depends on a
human opening the board and noticing. That is the operator's attention being
spent on discovery, which is the thing the pack exists to avoid.

So the terminal clause of the rule: when a subject's waiting set fully closes,
something must **file a visit back** to the conversation, rather than only
re-banding the row.

The intended shape is `tk-2cyxo` (in flight):

- **A sweep, not a render side effect.** Board renders stay read-only and
  idempotent; the actor cannot depend on anyone opening a board.
- **Scoped to operator-origin subjects** — the set where a human has a standing
  expectation of an answer.
- **A carve-out, not a removal.** A takeaway normally mutes the stall detector
  (`assets/scripts/detect-stalled-workflows.sh`), and that rule is correct in
  general: a takeaway means a human named the wait and owns it. It is wrong in
  exactly one case — a takeaway whose waiting set has *fully closed*, where the
  named wait has ended. Carve out that case; leave every other suppression
  intact. Removing the check outright floods.
- **Idempotent**, never filing a second visit while one is open for the subject.
- **Additive.** The takeaway is never cleared; the visit is filed beside it.
- **Self-describing.** The visit states its own premise — the subject, which
  blockers closed, and when — so the next sitting can cheaply kill it if the
  situation has changed.

## Two propagation paths, chosen by how the work was filed

The seam has two shapes, and which one applies is decided when the sitting files
the work — not later. Getting this wrong is the most common way a subject goes
dark.

- **Routed work filed as a `parent-child` CHILD of the subject** propagates by
  roll-up: the parent is banded by its open children rather than by the parked
  floor, because "wants nothing" is false while open work hangs under it.
- **Routed work filed as an independent bead** propagates by the `blocks` edge
  of clause 1 and the `disposition_due` derivation of clause 2.

These are not interchangeable, and the reason is a hard constraint rather than a
convention: `bd` refuses a `blocks` edge from a parent to its own descendant
(recorded in `assets/scripts/gc-helm.sh`'s kind-classification header). So work
filed as a child *cannot* be expressed as a `waiting_on` edge — the roll-up path
is the only one available to it. The canonical converse shape files routed work
as a child of the subject, which makes the roll-up path the common case and
`--waiting-on` the mechanism for everything else.

Both paths must be live for a subject to be visible. `tk-a9k0l` (landed
2026-08-23, PR #422) is what happens when one of them is broken: a parked row
hardcoded `children: []`, so a parked subject reported zero children and its
open children vanished from every surface — the roll-up path silently deleted.

## The failure class

One rule, discovered four times in four different surfaces. Listing them is the
point: individually each reads as a local bug, and only together do they show a
composition rule that was missing rather than four unrelated defects.

| Instance | Surface | Status |
|---|---|---|
| `tk-2plde` | A parked subject's wait was free text, so completion never propagated | Closed 2026-08-22 (PR #411) — the wait is now a `blocks` edge, re-derived per render |
| `tk-st143` | The liveness sweep filed visits about already-landed work | Closed 2026-08-22 |
| `tk-t4rlv` | A doc tracker outlived its file by 20 days | Closed 2026-08-22, disposed to a successor |
| `tk-puh9d` | `blocked` status never auto-clears when deps close | **Open** since 2026-08-02 — the one instance left |

The measured cost of a single miss: `tk-yps55` sat parked for 29 hours after
the work it was waiting on had merged, and cost a full converse sitting to
discover it was already finished. In a second incident, an audit that had
overturned its own commissioning premise sat in a merged file for 4h19m before
the operator found it by eye — nothing in the system had noticed
(`tk-16f29`, the operator-origin bead reporting the seam failing on the very
audit that produced this document).

One caveat applies to every fix in this class: the shell board and
`services/helm/` are separate implementations of the same derivation, so a fix
to one does not reach the other. Any change to shared derivation lands in both.

## The test for new work

When a change makes one part of the system wait on another, it has to answer
three questions, and a missing answer is the defect:

1. **What is the edge?** If the wait exists only as prose, a status field, or a
   convention, it is not recorded.
2. **Who re-derives it, and when?** If the answer is "whoever notices", nothing
   does. Prefer a derivation at the point of use over a stored flag that
   something else must remember to clear.
3. **Where does completion land?** If the answer is "the row changes colour",
   the work is only half done. A push, not a state a human has to go looking at.
