---
name: Epic Stewardship — holding an epic open until its hypothesis is ruled closed
description: How the pack holds an epic open until its hypothesis is ruled close with its outcome — the ruling fields an epic carries, the finalize-gate clause that holds a gate-running close, and the doctor invariant that reports a close made without the ruling — plus the Epic Checkpoint layer that is direction, not built. Read it to rule on or close an epic, or to extend the enforcement; the contract an epic carries is epics.md.
---

# Epic Stewardship

Epic stewardship holds an epic to its contract. An epic that carries a
hypothesis stays open until the operator rules it closed and records the
outcome ([epics.md](epics.md)). The pack enforces that with a finalize-gate
clause and a doctor invariant. It does not yet prompt the rulings themselves:
the Epic Checkpoint layer that will is direction, described at the end of this
doc and built by the follow-on epic *Epic Checkpoints & Features*.

## Scope

**Mandate.** The enforcement that an epic closes only on a recorded close
ruling: the ruling fields an epic carries, the finalize-gate clause, the doctor
invariant, and the direction the stewardship grows in.

**Boundaries.** Not the contract an epic carries or what each ruling means —
that is [epics.md](epics.md). Not how a bead becomes a member of an epic;
membership classification and repair are a separate concern. Not the finalize
gate's full contract ([finalize-gate.md](finalize-gate.md)) or the invariant
catalog ([component-model.md](component-model.md)).

## Recording a ruling

The operator rules at a sitting on the epic, and the ruling is recorded on the
epic bead as metadata: `epic_ruling` is `continue`, `shift`, or `close`, and
`epic_ruling_reason` says why. On a close ruling the reason is the outcome (the
hypothesis held, was disproven, cannot be met as stated, stalled, or ran past
its cost), and the close requires it. Each ruling overwrites the last, so the
epic carries its latest ruling, and a continue recorded at an earlier sitting
never stands in for the close.

```bash
gc bd update <epic> --set-metadata epic_ruling=close \
  --set-metadata epic_ruling_reason="<the outcome>" \
  --set-metadata epic_ruling_evidence=<visit bead of the sitting>
```

The fields are registered in
[`lifecycle/lifecycle.toml`](../lifecycle/lifecycle.toml)
`[metadata.epic_stewardship]`. They are the operator's: stamped when the
operator confirms a contract field or rules, the dated decision
[epics.md](epics.md) calls for. No pack script writes them; the finalize gate and
the doctor check read the hypothesis, the ruling, and its reason.

| Field | Meaning |
|---|---|
| `epic_handle` | the 3–5 word handle |
| `epic_hypothesis` | the one-sentence hypothesis — a floor field, and what brings an epic under the close requirement |
| `epic_boundaries` | the epic's boundaries |
| `epic_closure_condition` | the 3–6 operator-runnable closure checks |
| `epic_indicators` | the 1–3 leading indicators |
| `epic_ruling` | the latest ruling: `continue`, `shift`, or `close` |
| `epic_ruling_reason` | why the latest ruling was made; on `close`, the outcome |
| `epic_ruling_at` / `epic_ruling_by` / `epic_ruling_evidence` | when, who, and the visit of the sitting that carried the ruling |

## Closing an epic: the before-close enforcement

There is no automatic transition to intercept. No parent→child close cascade
exists for `parent-child` edges, and the only native auto-close is
convoy-scoped and cannot fire on an `issue_type=epic`. So the "never a last-unit
auto-close" discipline ([epics.md](epics.md)) is a guardrail against building
such a cascade, and an epic reaches closed only through an explicit act, such
as a bare `gc bd close` or `bead-rehome.sh`'s close-with-successor.

Two layers enforce the ruling, and they apply one predicate. An epic that
carries a hypothesis may close only once it is ruled close with its outcome
recorded. A continue or shift ruling holds it as an absent ruling does. An epic
with no hypothesis predates the model and is exempt, and a disposed epic
(`gc.superseded_by`, written by `bead-rehome.sh`) carries a recorded terminal
reason and passes.

1. **The finalize-gate clause** (`finalize-gate.sh` `clause_epic_ruling_recorded`)
   refuses to finalize an epic the predicate holds, on every close path that
   runs the gate. Neither path wired today reaches an undisposed epic:
   `merge.sh` finalizes merge anchors, and `bead-rehome.sh` records its
   disposition before it gates. The clause is the precondition any gate-running
   close of an epic inherits, not a choke point on today's closes.
2. **The doctor invariant** (I14, `doctor/check-epic-closed-implies-ruled`) sees
   every close after the fact. A closed epic the predicate would have held is an
   error, whatever path closed it. A bare `gc bd close` is the ordinary way an
   epic closes, and I14 is what reports one closed without its ruling. Its
   remedy is to record the ruling on the closed epic, or to reopen the epic
   (`gc bd reopen`) when it should go on.

## Direction: the Epic Checkpoint layer

Not built. The model is in [epics.md](epics.md#direction-features-and-epic-checkpoints):
after each Feature lands, an Epic Checkpoint rules continue, shift, or close.
The follow-on epic *Epic Checkpoints & Features* builds the layer that runs it.
When a Feature has landed and no checkpoint is open on its epic, a formula
gathers the evidence and analysis the ruling needs and files the checkpoint
sitting for the operator to judge. The ruling that sitting records is the one
the gate and I14 read. It is a formula, not a doctor check: doctor is already
over-leveraged, and its role here stays the after-the-fact invariant. The first
checkpoints run by hand, and the machinery is built from what they show.

Until it lands, nothing asks for a ruling. An epic whose work has landed waits
for the operator to call a sitting on it, so an answered or stalled epic stays
open until someone looks.

Membership (re-homing work that drifted outside its epic) is a separate concern
with its own deferral, recorded in `specs/tk-isd5sa/design.md`.
