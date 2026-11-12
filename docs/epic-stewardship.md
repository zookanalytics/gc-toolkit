---
name: Epic Stewardship — holding an epic open until its hypothesis is ruled closed
description: Use when you rule on or close an epic, close a Delivery, or extend the enforcement that holds an epic open until its hypothesis is ruled closed. The contract an epic carries is epics.md.
---

# Epic Stewardship

Epic stewardship holds an epic to its contract. An epic stays open until the
operator rules it closed and records the outcome, or until a disposition closes
it ([epics.md](epics.md)). The pack enforces that with a finalize-gate clause and
a doctor invariant. Neither holds a Delivery, the level under an epic that SAFe
calls a Feature, and the Epic Checkpoint closes it
([Closing a Delivery](#closing-a-delivery)). The pack does
not yet prompt the rulings themselves: the machinery that will is direction,
described at the end of this doc.

## Scope

**Mandate.** The enforcement that an epic closes only on a recorded close
ruling or a disposition: the ruling fields an epic carries, the finalize-gate
clause, the doctor invariant, and the direction the stewardship grows in.

**Boundaries.** Not the contract an epic carries or what each ruling means —
that is [epics.md](epics.md). Not how a bead becomes a member of an epic;
membership classification and repair are a separate concern. Not the finalize
gate's full contract ([finalize-gate.md](finalize-gate.md)) or the invariant
catalog ([component-model.md](component-model.md)).

## Recording a ruling

The operator rules at a review of the epic
([epics.md](epics.md#reviewing-an-epic)), and the ruling is recorded on the
epic bead as metadata: `epic_ruling` is `continue`, `shift`, or `close`, and
`epic_ruling_reason` says why. On a close ruling the reason is the outcome (the
hypothesis held, was disproven, cannot be met as stated, stalled, or ran past
its cost), and the close requires it. Each ruling overwrites the last, so the
epic carries its latest ruling, and a continue recorded at an earlier sitting
never stands in for the close.

```bash
gc bd update <epic> --set-metadata epic_ruling=close \
  --set-metadata epic_ruling_reason="<the outcome>" \
  --set-metadata epic_ruling_evidence=<the human gate the ruling cleared>
```

The fields are registered in
[`lifecycle/lifecycle.toml`](../lifecycle/lifecycle.toml)
`[metadata.epic_stewardship]`. The contract lands in the create that files an
epic, which
[`gctk epic create`](../services/gctk/internal/cli/epic.go) makes. It refuses an
epic with no hypothesis unless the epic's parent is an epic, which makes it a
Delivery. A field the filer writes is its proposal, and the epic's notes say
whose words each field is ([epics.md](epics.md#the-contract-an-epic-carries)).
After the filing, a contract field takes only words the operator stated or
approved, and the ruling's fields are stamped at a review when the operator
rules, with the review's block in the epic's notes as the dated record. No pack
script writes the ruling's fields. The finalize gate and the doctor check read
the hypothesis, the ruling, and its reason.

| Field | Meaning |
|---|---|
| `epic_handle` | the 3–5 word handle |
| `epic_hypothesis` | the one-sentence hypothesis — a floor field. An epic whose parent is an epic and that carries none is a Delivery, which the close requirement does not hold |
| `epic_boundaries` | the epic's boundaries |
| `epic_closure_condition` | the 3–6 operator-runnable closure checks |
| `epic_indicators` | the 1–3 leading indicators |
| `epic_ruling` | the latest ruling: `continue`, `shift`, or `close` |
| `epic_ruling_reason` | why the latest ruling was made; on `close`, the outcome |
| `epic_ruling_at` / `epic_ruling_by` / `epic_ruling_evidence` | when the operator ruled, who recorded it, and the human gate whose resolve carried the ruling |

## Closing an epic: the before-close enforcement

There is no automatic transition to intercept. No parent→child close cascade
exists for `parent-child` edges, and the only native auto-close is
convoy-scoped and cannot fire on an `issue_type=epic`. So the "never a last-unit
auto-close" discipline ([epics.md](epics.md)) is a guardrail against building
such a cascade, and an epic reaches closed only through an explicit act, such
as a bare `gc bd close` or `bead-rehome.sh`'s close-with-successor.

Two layers enforce the ruling, and they apply one predicate. An epic may close
only once it is ruled close with its outcome recorded. A continue or shift
ruling holds it as an absent ruling does. A disposed epic (its duplicates or
supersedes edge, written by `bead-rehome.sh`) carries a recorded terminal reason
and passes. A Delivery passes too ([Closing a Delivery](#closing-a-delivery)).
Any other epic with no hypothesis is an incomplete Epic, which is fixed by
recording its hypothesis ([epics.md](epics.md#the-contract-an-epic-carries)),
and both layers hold it until it is ruled close.

1. **The finalize-gate clause** (`finalize-gate.sh` `clause_epic_ruling_recorded`)
   refuses to finalize an epic the predicate holds, on every close path that
   runs the gate. A review of an epic runs it on each Delivery it closes and,
   once it has recorded the close ruling, on the epic. `merge.sh` finalizes
   merge anchors, and `bead-rehome.sh` asks the gate about the epic as its
   disposition will leave it (`--as-disposed`), before it writes anything and
   in its read-only `--check`, so `stand-down.sh` carries out a person's ruling
   that an epic will not go on. The clause is the precondition any
   gate-running close of an epic inherits, not a choke point on today's
   closes.
2. **The doctor invariant** (I15, `doctor/check-epic-closed-implies-ruled`) sees
   every close after the fact. A closed epic the predicate would have held is an
   error, whatever path closed it. A bare `gc bd close` is the ordinary way an
   epic closes, and I15 is what reports one closed without its ruling. Its
   remedy is to record the ruling on the closed epic, and an incomplete Epic's
   hypothesis with it, or to reopen the epic (`gc bd reopen`) when it should go
   on.

## Closing a Delivery

A Delivery ([epics.md](epics.md#deliveries-and-epic-checkpoints)) is an epic-typed
child of its epic that carries no hypothesis, so the finalize-gate clause and I15
never hold it. It carries no ruling of its own either. The ruling answers the
epic's hypothesis, and both layers read it on the epic.

The Epic Checkpoint closes a Delivery, as one of the ruling's writes, with the
ruling as the close reason. What stands in the way of that close is bd, which
refuses to close a bead with an open child or an open blocker such as a park
unless the close is forced, and the checkpoint does not force it. The sitting
also holds a landed Delivery's close with a human gate until the operator rules,
and the ruling answers that gate. So the Delivery closes once every Story under
it has closed, the ruling has answered its gate, and the sitting has released it
from any park. A child epic that carries a hypothesis of its own is an epic, not a
Delivery, and both layers hold it as one.

## Direction: the checkpoint's machinery

A review of an epic, the Epic Checkpoint among them, runs by hand, as a sitting
that follows the
[`converse-epic-review`](../skills/converse-epic-review/SKILL.md) skill
([epics.md](epics.md#reviewing-an-epic)). Machinery that does any of its work
is not built. It is designed from what those hand runs record.
Plausibly that is a formula that files the checkpoint sitting and gathers its
evidence when a Delivery lands, and one verb that makes the ruling's writes. It
is not a doctor check: doctor is already over-leveraged, and its role here stays
the after-the-fact invariant. The ruling the sitting records stays the one the
gate and I15 read.

Until it lands, nothing files the checkpoint sitting. A landed Delivery's row on
the helm board asks for the checkpoint, among the rows the operator owes, and the
operator calls the sitting from there. An epic with no Deliveries whose work has
landed is reviewed only when a review is called
([epics.md](epics.md#reviewing-an-epic)), so an answered or stalled epic stays
open until someone looks. A Delivery that stalls before it lands is
inspected only by such a sitting, and the machinery may add a nudge on a
Delivery's age.

Membership (re-homing work that drifted outside its epic) is a separate concern
with its own deferral, recorded in `specs/tk-isd5sa/design.md`.
