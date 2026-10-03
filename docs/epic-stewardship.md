---
name: Epic Stewardship — the cadence that elaborates and advances epics
description: The epic-steward order and driver — how the city audits every open epic on a cadence, surfaces the floor contract, the rest of the contract, and the hypothesis ruling each epic owes as operator visits, and enforces that an epic closes only on a recorded ruling. Names the metadata fields an epic carries and the before-close trio. Read it to run, tune, or extend the steward; the contract an epic carries is epics.md.
---

# Epic Stewardship

The city has a natural tendency to elaborate and advance its epics: it reads
each one against its contract, surfaces the decision the epic now owes to the
operator, and holds an epic open until its hypothesis is ruled on. Epic
stewardship is the mechanism behind that tendency. It is the second steward in
the pack after the refinery and wears the same shape — a cadence that enumerates
the object it stewards, runs independent arms over each, and surfaces the
follow-up — applied to epics rather than pull requests.

It is deliberately not a doctor check. Doctor is already over-leveraged, so the
steward is an ordinary exec order; doctor's only role here is asserting that
order is live ([component-model.md](component-model.md) I10,
`check-cadence-live`) and that a closed epic was ruled (I14,
`check-epic-closed-implies-ruled`).

## Scope

**Mandate.** The mechanism that elaborates and advances epics: the cadence that
audits every open epic, the decisions it surfaces to the operator, the fields an
epic carries that it reads, and the enforcement that an epic closes only on a
recorded hypothesis ruling.

**Boundaries.** Not the contract an epic carries or when it closes — that is
[epics.md](epics.md), which this mechanism reads and enforces. Not how a bead
becomes a member of an epic; membership classification and repair are a separate
concern (see [Membership](#membership-deferred)). Not the merge cadence
([refinery-merge-cadence.md](refinery-merge-cadence.md)), whose shape this
rhymes with. Not the invariant catalog or the finalize gate's full contract
([component-model.md](component-model.md), [finalize-gate.md](finalize-gate.md)).

## The audit

`orders/epic-steward.toml` runs `assets/scripts/epic-steward.sh` on a cadence
(`scope=rig`: an epic is a per-rig anchor). One pass enumerates every non-closed
`issue_type=epic` in the rig — `open`, `in_progress`, `blocked`, `deferred`,
`hooked`, and `pinned`, the same live set the finalize gate holds — and runs
three arms over each. Each
arm detects whether the epic owes a particular decision and, when it does, files
exactly one operator visit through `escalate.sh`, keyed by concern; when the
decision has since been made, it retracts the visit it filed. `escalate.sh`
dedups by (subject, key), so
a visit that is already open is refreshed, not duplicated, and its `tracks` edge
to the epic holds the epic's finalize until the conversation is answered. The
judgment each visit asks for is the operator's; the pass only detects what is
owed.

A per-rig flock serialises passes, so a long pass cannot overlap the next tick
and race `escalate.sh`'s find-or-file read. The lock lives in the shared
`assets/scripts/single-flight.sh`, so this order and the refinery's reconcile
cadence hold their passes the same way. The pass fails closed: with no usable
lock it runs no arm, and a lock held past the stall bound is reported as a wedged
pass rather than skipped silently every tick.

### Floor

An epic whose floor contract is incomplete — missing any of its handle
(`epic_handle`), its one-sentence hypothesis (`epic_hypothesis`), or its
boundaries (`epic_boundaries`) — cannot have work classified into it and cannot
be judged complete. The floor arm files a visit naming the missing field(s) and
asking the operator to draft and ratify them. This is the contract's own closure
condition that "the city proposes a contract for an epic that lacks one"
([epics.md](epics.md)). A rough hypothesis is enough to start; once all three
floor fields are recorded the arm retracts any floor visit it filed.

### Rest of the contract

Once an epic has a hypothesis but is missing its closure condition
(`epic_closure_condition`) or its leading indicators (`epic_indicators`), the
contract arm files a visit asking for whichever is absent. The floor is enough to
start work; the rest of the contract gives the epic an agreed test of done and an
in-flight signal to steer by. Once both are recorded the arm retracts the contract
visit.

### Hypothesis ruling

When every unit under an epic has landed (every `parent-child` child closed) and
no ruling is recorded (`epic_ruling` absent), the ruling arm files a visit: the
epic is complete but cannot close until its hypothesis is answered. An epic
closes by a ruling — persevere, pivot, or close — after a validation step, never
as a side effect of its last unit merging ([epics.md](epics.md)). A ruling
presupposes a hypothesis, so the arm stays silent on an epic that still owes its
floor. Once a ruling is recorded, the arm retracts the visit, releasing the
finalize hold so the epic can close.

### Membership (deferred)

Re-homing work that has drifted outside its epic — the periodic scope-reading
audit — is a designed fourth arm that is not yet built. It needs a repair
primitive that re-parents a bead and a scope classification the shell pass cannot
do; both are tracked separately with the membership mechanism. Until it lands,
membership drift is not swept. See `specs/tk-isd5sa/` for the deferral and its
cost.

## The fields an epic carries

An epic's contract ([epics.md](epics.md)) is recorded on the epic bead as
metadata, registered in [`lifecycle/lifecycle.toml`](../lifecycle/lifecycle.toml)
`[metadata.epic_stewardship]`. The fields are the operator's to ratify: they are
stamped when the operator confirms a floor or a ruling at the visit the steward
files, the dated decision [epics.md](epics.md) calls for. No pack script writes
them; the steward, the finalize gate, and the doctor check read them.

| Field | Meaning |
|---|---|
| `epic_handle` | the 3–5 word handle |
| `epic_hypothesis` | the one-sentence hypothesis — a floor field, and the trigger for the finalize gate's ruling requirement |
| `epic_boundaries` | the epic's boundaries |
| `epic_closure_condition` | the 3–6 operator-runnable closure checks |
| `epic_indicators` | the 1–3 leading indicators |
| `epic_ruling` | the hypothesis ruling: `persevere`, `pivot`, or `close` |
| `epic_ruling_at` / `epic_ruling_by` / `epic_ruling_evidence` | when, who, and the visit that carried the ruling |

## Closing an epic: the before-close enforcement

There is no automatic transition to intercept. No parent→child close cascade
exists for `parent-child` edges; the only native auto-close is convoy-scoped and
cannot fire on an `issue_type=epic`. So the "never a last-unit auto-close"
discipline ([epics.md](epics.md)) is a guardrail against building such a cascade,
and an epic reaches closed only through an explicit act: a bare `gc bd close`, a
`lifecycle.sh` transition, or `bead-rehome.sh`'s close-with-successor.

Three layers enforce the ruling, because no single one covers every close:

1. **The steward's ruling visit** surfaces the decision to the operator — the one
   who performs the close — and holds the finalize gate through its `tracks` edge.
2. **The finalize-gate clause** (`finalize-gate.sh` `clause_epic_ruling_recorded`)
   refuses to finalize an epic carrying no `epic_ruling`. It covers the close
   paths that run the gate: `bead-rehome.sh`, and `merge.sh` were an epic ever an
   anchor. A bare `gc bd close` runs neither, so the clause is not a universal
   choke point.
3. **The doctor invariant** (I14, `doctor/check-epic-closed-implies-ruled`) is the
   after-the-fact backstop: a closed epic with no `epic_ruling` and no explicit
   disposition (`gc.superseded_by`) is an error, whatever path closed it.

## Cadence and tuning

The interval is a heartbeat, not the cadence. Every arm is idempotent and every
visit is deduped, so a frequent pass re-files nothing; frequency only shortens
how long a newly created epic waits for its first audit — the create-time half,
which a short interval approximates until a dedicated create-time arm makes it
exact. Tune the interval from `city.toml` `[[orders.overrides]]`, not the order
file.

A pass audits the whole live set — epics are a coarse per-rig anchor, so there is
no per-pass cap; a cap taking the first N in a stable order would never advance to
the rest. The order's own `timeout` and the single-flight flock bound how long one
pass runs.

- `EPIC_STEWARD_STATE_DIR` overrides where the per-rig flock lives (tests isolate
  it here).
- `EPIC_STEWARD_LOCK_STALL_SECS` overrides the age past which a held lock reads as
  a wedged pass rather than a slow one (default 900).
- `GC_ESCALATE_TOOL` overrides the `escalate.sh` path (tests capture visits here).
