---
name: epic-membership-mechanics
description: Design record for tk-xgj2ko — what epic membership is (the parent-child edge the helm board groups by), the work-vs-gate carve-out, the readiness resolution that makes membership safe, and the deferred create-time-parenting, repair, and scope-audit mechanics.
---

# Epic membership mechanics

> **Bead:** tk-xgj2ko · **Epic:** tk-rctkrj · **Kind:** spec-first design record.
> **Builds on:** `docs/component-model.md` (I1 — the shape law, and
> `parent-child` as decomposition); `services/helm/README.md` and
> `services/helm/internal/board/derive.go` (the `group_root` grouping);
> `docs/gascity-human-engagement.md` (the sibling shape).

An epic groups the work that belongs to it on the helm board. A bead belongs
when a `parent-child` edge makes the epic its group root; a bead with no such
edge renders on its own, outside the epic. This unit defines that membership
edge, states which beads can carry it and which cannot, and records how
membership is kept from freezing the work it groups. The create-time, repair,
and audit mechanics that follow are named here and tracked as their own beads.

## What membership is

Membership is the `parent-child` edge, read at board-render time.
`docs/component-model.md` (I1) fixes its meaning: `parent-child` is
decomposition, and the child is part of the parent. An epic is the parent;
each member work bead is a child.

The helm board is the reader that makes membership visible.
`services/helm/internal/board/derive.go` `assignGroupRoots` stamps every tile's
`group_root` by climbing to the top-most tile along two edge kinds: the
`parent-child` edge (preferred) and the `blocks` edge (the anchor a tile waits
on). `services/helm/README.md` states `group_root` is the board's primary
grouping axis, and `board.GroupByFamily` renders one block per family, the root
as the header and its members beneath. A work bead whose `parent-child` chain
climbs to the epic renders under the epic.

The climb keys on `parent-child` and `blocks` alone: `assignGroupRoots`
follows a bead's children (`parent-child`) and the anchor it waits on
(`blocks`), never a `relates-to` link. A unit filed `relates-to` an epic
therefore climbs no edge the board reads, roots itself, and renders as its
own one-row family — the scattered-work symptom that opened epic tk-rctkrj.
`relates-to` is a prose link, not membership.

Membership is not stored state. Nothing records "this bead's epic" beyond the
edge itself; the board derives the family from the graph on each render. So
membership is exactly as correct as the edges are, which is why the mechanics
below write and repair the edge rather than a field.

## What cannot be a member: the work-vs-gate carve-out

Membership is decomposition, so the test for it is semantic: a bead is a member
when it is part of the epic's work, and a non-member when it is something the
epic waits on. A gate is the second kind. A demand `D` that gates a subject `S`
is not a piece of `S`'s work; it is what `S` waits for before it can finalize.
Filing `D` as a child of `S` would assert a containment that is not true. So a
gate is a sibling of what it gates, not a child. This is the I1 shape law in
`docs/component-model.md`: containers do not block, blockers do not parent,
because `parent-child` means the child is part of the parent's work.

beads enforces the sharpest case of that law directly. A demand carries the edge
"`S` blocked-by `D`", and were `D` a child of `S` the edge would run from a
parent to its own descendant, which beads refuses:

```
$ gc bd dep add <parent> <descendant> -t blocks
Error: <parent> cannot be blocked by its descendant <descendant>:
blocked status cascades to descendants, so <descendant> would inherit
the block and never close
```

That refusal is the enforcement, not the reason. The sibling shape is correct
even where no `blocks` edge is in play, because a gate is still not part of the
epic's work. The test holds for every gate kind, not the demand alone: a visit
(the conversation a person owes), a demand (`gc-helm.sh demand`, which reads the
subject's own parent and files the gate there,
`docs/gascity-human-engagement.md`), and an operator decision are all things the
epic waits on, so all are siblings. Work is the member; whatever gates the work
is the sibling. The shape misleads only when it is used for the other category —
routed work filed as a sibling reads as "not part of the epic" when it is, which
is the scattered-work symptom this epic corrects. That is the carve-out the
"every bead lands under an epic" goal needs.

## Why membership was hostile, and the resolution

The same `blocks` edge that keeps a gate out of the epic also freezes the
epic's members. `is_blocked` cascades down `parent-child` edges
(`docs/component-model.md`): a `blocks` edge on the epic marks every descendant
blocked, and a blocked bead drops out of `bd ready`, so the pool never offers
it. An epic with an open demand and `parent-child` members freezes all of them
from dispatch. This is finding tk-g6xcwi, the demand-cascade, and it is why
coordination work has been filed as a sibling rather than a child: a sibling
inherits no block, at the cost of not rendering under the epic.

The resolution is settled, and this unit does not redesign it. Operator ruling
(visit tk-cwaxkt, on tk-g6xcwi): no beads change, no per-gate scope field, no
epic-membership reclassification. The demand's `blocks` edge is redundant for
gating, because the merge/close gating a hold needs is already provided by the
track-only finalize-gate on the `tracks` edge (tk-p8svsz, landed;
`docs/finalize-gate.md`). The `blocks` edge only cascades. So coordination
holds stop filing it: converse hold and sign-off rely on the finalize-gate
instead (tk-n18e15, in flight). Once an epic no longer carries a cascading
`blocks` demand, its members inherit no block, and work is safe to file as a
child.

Retiring the demand's `blocks` edge does not make the gate a member. The
finalize-gate reads the `tracks` edge, which is non-blocking and holds only the
subject's own finalization (`docs/finalize-gate.md`), so a gate needs no
particular parentage to do its job. The gate stays a sibling on the semantic
ground of the carve-out: it is not part of the epic's work. The shape is kept
for that reason, not because an edge forces it.

Membership therefore depends on the readiness fix, exactly as this unit's brief
states. That fix is owned by tk-n18e15, not built here: this unit defines
membership and the carve-out, and defers the cascade resolution to the bead
that owns it.

## Create-time parenting (tk-9wojzh, blocked on tk-n18e15)

Today a coordination role files the work it routes as a sibling of the subject:
it takes the subject's own parent, the same shape a gate takes. That is right
for a gate and wrong for work. The board groups by the `parent-child` climb, so
sibling work roots itself and renders scattered, outside the epic.

Create-time parenting changes the default for work alone. A role files routed
work as a `parent-child` child of the subject epic, so it renders as a member
from the moment it is created. Gates and demands keep the sibling shape, per the
carve-out.

The change touches the sites that carry the sibling rule:
`agents/converse/prompt.template.md` (the "everything a sitting files is a
sibling" rule and the route-a-formula step), `skills/converse-settle/SKILL.md`,
and `docs/gascity-human-engagement.md`. It is blocked on tk-n18e15: until the
cascading demand is retired, parenting unstarted work under an epic that still
carries one would freeze it. Filed as tk-9wojzh.

## Membership repair (tk-8bzuc2)

Re-homing misfiled work is one declarative call. A caller names the bead and the
epic and states the outcome it wants: this bead belongs to this epic. The
primitive reaches that outcome or rejects the request, and the caller touches no
edges. It validates the request, makes the change, and refuses what it cannot
honor: the target is not an epic, or the bead already belongs to a different epic
and no reassignment was asked for.

The ordered edge change is what the primitive hides. beads keeps one edge type
per pair, so a bead already linked `relates-to` its epic cannot also carry a
`parent-child` edge to it: beads rejects the `--parent` write and says to remove
the existing edge first. So the primitive removes the `relates-to` edge, then
sets `parent-child`. No tool re-homes by re-parenting today:
`assets/scripts/bead-rehome.sh` is a close-with-successor disposition, and the
only `--parent` write in the coordination scripts is the demand-sibling write in
`gc-helm.sh`. Filed as tk-8bzuc2.

Re-homing is safe for dispatched or closed work, and in-flight work keeps running
after a re-home. It is cascade-sensitive only for unstarted dispatch: parenting
an unstarted bead under an epic that carries an open cascading demand freezes it.
The primitive refuses or warns on that case, so it is safe to call before
tk-n18e15 lands.

## The periodic scope-reading audit (tk-isd5sa)

A periodic audit that reads each epic's scope and re-homes misfiled work is the
backstop for everything above, and the only reach coordination work filed
before create-time parenting has. That audit is the epic-stewardship mechanism,
owned by tk-isd5sa: the central audit that runs on create and on a queued
schedule, which already lists membership audit triggers among what it reasons
about. This unit does not build a second audit. It supplies the two inputs that
audit reads: the membership definition and carve-out above (what "belongs"
means), and the repair primitive (tk-8bzuc2) it calls to act.

## Reconciliation with adjacent work

- **tk-n18e15** owns the readiness-cascade fix (item 2 of this unit's brief), a
  live routed bead; this unit defers to it. The brief calls the finding
  "unlanded": tk-p8svsz (the finalize-gate half) is landed, and tk-n18e15 (the
  stop-filing-the-demand half) is in flight.
- **tk-c5atcz** owns `docs/epics.md`, the epic contract. Membership is a
  distinct topic from the contract; when `docs/epics.md` is written it should
  surface the membership model and cite this record.
- **tk-isd5sa** owns the audit mechanism (item 5). This unit supplies its
  classification and repair inputs.

## Deferred mechanics and the cost of waiting

This unit lands the definition; the mechanics are tracked, not dropped.

| Mechanic | Bead | Blocked on | Cost while deferred |
|---|---|---|---|
| Create-time parenting | tk-9wojzh | tk-n18e15 | Coordination-filed work renders scattered, not under its epic; each epic needs manual re-homing. |
| Repair primitive | tk-8bzuc2 | none | Re-homing stays a manual, order-sensitive bead sequence, and the audit has nothing to call. |
| Scope-reading audit | tk-isd5sa | survey + contract | Misfiled work is not swept, and membership drifts as work is filed. |
