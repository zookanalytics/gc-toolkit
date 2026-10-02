---
name: epic-membership-mechanics
description: Design record for tk-xgj2ko — the four relationships a bead can have to an epic or subject (member, halt, hold-finalization, dependency), the mechanism and cascade each uses, how the helm board groups by them, and the create-time-parenting, repair, and scope-audit mechanics that keep membership correct.
---

# Epic membership mechanics

> **Bead:** tk-xgj2ko · **Epic:** tk-rctkrj · **Kind:** spec-first design record.
> **Builds on:** `docs/component-model.md` (I1 — the shape law, and
> `parent-child` as decomposition); `services/helm/internal/board/derive.go`
> and `services/helm/internal/source/beads.go` (the board's grouping climb);
> `docs/finalize-gate.md` (the track-only finalize-gate);
> `docs/gascity-human-engagement.md` (the gate shapes).

An epic groups the work that belongs to it on the helm board. A bead relates to
an epic or subject in exactly one of four ways, and each way has one mechanism
that means it. This unit names the four, states the mechanism and the cascade
each carries, records how the board groups by them, and defines the create-time,
repair, and audit mechanics that keep the edges correct. Those mechanics are
named here and tracked as their own beads.

## The four relationships

Use the mechanism that means the relationship. Do not reach for one mechanism to
express a different one.

| Relationship | Mechanism | Cascade |
|---|---|---|
| **is part of** — a story or task that decomposes the epic | a `parent-child` child (a member) | completion-wait is implicit; no `blocks` edge (beads refuses a parent→descendant one) |
| **halt this epic** — mis-scoped, stop all work | a `blocks` edge on the epic | yes, deliberately: it freezes the decomposition children |
| **hold finalization, let work run** — a gate or input the subject owes | the finalize-gate on the `tracks` edge | no: it holds only the subject's own finalization |
| **depends on** — needs it, does not contain it | a `blocks` edge, filed sibling (`S` blocks-on `W`) | yes |

The first relationship is membership. The other three are the ways a bead is
*not* a member: something that halts the epic, something that holds its
finalization, and something it merely depends on. The sections below define
membership, show how the board reads it, and place each non-member relationship
against it.

## What membership is

Membership is the `parent-child` edge, read at board-render time.
`docs/component-model.md` (I1) fixes its meaning: `parent-child` is
decomposition, and the child is part of the parent's work. An epic is the
parent; each member work bead is a child. Membership is not stored state —
nothing records "this bead's epic" beyond the edge itself, and the board derives
the family from the graph on each render. So membership is exactly as correct as
the edges are, which is why the mechanics below write and repair the edge rather
than a field.

## How the board groups: the climb

The helm board is the reader that makes membership visible.
`services/helm/internal/board/derive.go` `assignGroupRoots` stamps every tile's
group root by climbing to the top-most anchor along the edges each anchor
carries. It reads three, not `parent-child` alone:

- an anchor's **children** (`a.Children`), the preferred climb;
- the beads in its **`WaitingOn`** — the ones it blocks on by a `blocks` edge —
  which climb to it, so a subject that waits on a bead groups that bead under
  itself;
- a review or rework child's **`metadata.anchor_bead`**, which names its merge
  anchor directly and resolves the child even when the anchor's edge gather was
  partial.

What fills `a.Children` depends on the anchor's kind
(`services/helm/internal/source/beads.go`). `needsParentChildren` gathers
`parent-child` children for an epic, human, parked, or merge anchor; a convoy's
children are its `tracks` members instead. So across all anchors the climb reads
`parent-child`, `blocks` (through `WaitingOn`), `tracks` (through a convoy's
children), and `metadata.anchor_bead` — and the `parent-child` roll-up is
gathered only for epic, human, parked, and merge anchors. It never reads a
`relates-to` link: a unit filed `relates-to` an epic climbs no edge the board
reads, roots itself, and renders as its own one-row family. `relates-to` is a
prose link, not membership.

A climb along the `blocks` edge is board visibility, not membership. A tile
climbs to the anchor whose `WaitingOn` names it, and that anchor is waiting on
the tile, not containing it. A review or rework child, named in its merge
anchor's `WaitingOn`, renders under that anchor without being part of its work.

## The non-member relationships

### Halt: a `blocks` edge on the epic

A `blocks` edge on the epic halts it. `is_blocked` cascades down `parent-child`
edges (`docs/component-model.md`), so every decomposition child is marked blocked
and drops out of `bd ready`. That is the deliberate way to stop a mis-scoped epic
and everything under it, and it is why work cannot be parented under an epic that
carries such an edge until the halt is lifted — the member would inherit the
freeze.

### Hold finalization: the finalize-gate on the `tracks` edge

A gate of this kind holds the subject's finalization without blocking its work.
The finalize-gate reads the subject's incoming `tracks` edges and the visits
stamped with it, and holds the subject's own merge or close while any is open
(`docs/finalize-gate.md`, tk-p8svsz). A `tracks` edge is non-blocking, so the
gate never consults the bead's readiness and never reaches its children: a visit
on an epic holds the epic's own close and leaves every child free to move.

A **visit** takes this shape. `escalate.sh` attaches a visit with a `tracks`
edge, so it is not a blocker at all (`services/helm/internal/board/derive.go`);
it is parentless, and the finalize-gate is what holds the subject. A visit is
therefore distinct from a demand-gate below: a visit holds only finalization, a
demand holds the work.

### Depends on: a sibling `blocks` edge

A bead `S` that needs another bead `W` but does not contain it depends on it: `S`
blocks-on `W`, filed as a sibling. Two coordination sites write this shape:

- A **demand** — what a person owes before the work can proceed. `gc-helm.sh
  demand` files it as its own bead and blocks the gated work on it (`gated`
  blocked-by `demand`), re-homing the gate as the gated bead's sibling
  (parentless when the subject has no parent). The work depends on the demand.
- The **sign-off's wait-for-work**: `gc-helm.sh takeaway --waiting-on <work>`
  writes `subject` blocked-by `work` so the subject waits for the work it routed.
  This is the dependency shape only when the work is a sibling; when the work is
  a member, the edge must not be written (see below).

The `blocks` edge here is not redundant with the finalize-gate. The finalize-gate
holds only the subject's own finalization and never consults readiness, so it
cannot hold work out of the pool; after a sign-off closes a visit, a `blocks`
edge is the only thing that keeps dependent work unready. Halt and depends-on (a
`blocks` edge, which cascades and holds readiness) and hold-finalization (the
finalize-gate, which does neither) answer different questions, so one cannot stand
in for the other.

### Why a `blocks`-bearing gate or dependency is a sibling

A gate or dependency that carries a `blocks` edge is a sibling, not a child,
because beads refuses a `blocks` edge from a parent to its own descendant:

```
<subject> cannot be blocked by its descendant <work>: blocked status
cascades to descendants, so <work> would inherit the block and never close
```

Filed under the subject, the edge would run parent→descendant and be refused, so
the wait could never be carried (`assets/scripts/converse-parent.sh`, which reads
the subject's own parent for exactly this reason;
`services/helm/internal/board/derive.go`, which records it as the reason a demand
is a sibling). The constraint is beads' own guard, and it stays in place whatever
else changes.

## Create-time parenting: an advisory epic-context indicator

Create-time parenting is a default, not a law. It reads the subject's position in
the graph to surface the likely epic for the sitting: the subject itself when it
is an epic, otherwise the epic in the subject's ancestry. A sitting or visit on a
story under epic `E` is likely about `E`, so `E` is the likely parent; the signal
is not whether the subject is literally an epic. That likely epic is offered as
the default parent for work the sitting creates, becoming a real `parent-child`
member only when the created work genuinely decomposes it. The default is
overridable in every case and never forces parenting. Work that is not actually
part of the indicated epic is not filed under it; it is its own thing, or a
dependency filed as a sibling. When the subject has no epic in its ancestry, no
default surfaces. That is no suggestion rather than a prohibition, and the work is
classified on its own merits. Never turn a leaf into a container.

A member created this way carries no `blocks` edge back to that epic: the
completion-wait is implicit in containment, and beads refuses the
parent→descendant edge in any case. Work that is a dependency rather than a
member keeps the sibling `blocks` edge.

Parenting is owned by tk-9wojzh and blocked on tk-n18e15: until the cascading
demand is retired, parenting unstarted work under an epic that still carries one
would freeze it under the halt cascade. The mechanism changes the sites that file
routed work today — `assets/scripts/converse-parent.sh` and the converse prompt
and settle skill that read it as `$PARENT` — so that routed work defaults to a
member of the indicated epic while gates and demands keep the sibling shape.

## The sign-off's wait-for-work edge branches on the relationship

When a sitting signs off and routes work, it records the wait as an edge:
`gc-helm.sh takeaway --waiting-on <work>` writes `subject` blocked-by `work`
(`gc bd dep add <subject> <work> -t blocks`). Under the four relationships this
write branches on what the work is:

- **member work** (a `parent-child` child of the subject): no `blocks` edge. The
  completion-wait is implicit in containment, and beads refuses the
  parent→descendant edge, so writing it only degrades the wait to prose.
- **dependency work** (a sibling): the `subject` blocks-on `work` edge is correct
  and is what holds the subject until the work lands.

`gc-helm.sh takeaway` writes the edge whenever `--waiting-on` names a bead;
branching it on the relationship is the behavior this unit specifies. The code
change is a follow-up; this record fixes the design.

## The scattered-work case is narrow

Sibling-filed work is not generally scattered. The board already groups the
common cases: work that shares the subject's parent groups under that parent, and
work the subject waits on climbs to the subject through the `WaitingOn`/`blocks`
edge (`services/helm/internal/board/derive.go`). Scattering happens only in the
narrow case of a parentless subject with no wait edge, where neither climb
reaches an anchor. Create-time parenting and the repair primitive address that
case; they are not motivated by a general scattering that does not occur.

## Membership repair (tk-8bzuc2)

Re-homing misfiled work is one declarative call. A caller names the bead and the
epic and states the outcome it wants: this bead belongs to this epic. The
primitive validates the request, makes the change, and refuses what it cannot
honor. beads keeps one edge type per pair, so a bead already linked `relates-to`
its epic cannot also carry a `parent-child` edge to it; the primitive removes the
`relates-to` edge, then sets `parent-child`. It refuses when the target is not an
epic, or when the bead already belongs to a different epic and no reassignment was
asked for.

It **hard-refuses** the cascade-unsafe case: parenting unstarted work under a
deliberately-halted epic — one carrying an open cascading `blocks` demand — would
freeze that work under the halt cascade. A warning is not enough, because a
warning still performs the freezing write, and the audit that calls the primitive
(tk-isd5sa) is non-interactive, so no one reads the warning. The primitive
refuses.

Re-homing in-flight work does not strand it. Parenting an in-progress bead under a
halted epic makes it inherit `is_blocked` and drop out of `bd ready`, but that
inherited block does not prevent its close: `bd close` refuses only on a live
direct blocker (`internal/storage/issueops/close.go`, whose refuse predicate is
`blocked && len(blockers) > 0`), and a parent-cascade block produces no direct
blocker — `is_blocked` is set on the child as a column, with no edge of its own —
so the bead still closes when its PR merges. The cascade-unsafe case is therefore
unstarted dispatch, work the halt holds out of the pool before it is ever claimed,
which is what the hard-refuse covers.

The primitive re-parents, which no tool does today. `assets/scripts/bead-rehome.sh`
is a separate close-with-successor disposition — it drops the direct
origin→successor `blocks` edge before the close, because `bd close` refuses a
direct blocker — and the only write that sets a `parent-child` edge via `--parent`
in the coordination scripts is the demand-sibling re-home in `gc-helm.sh`.
Owned by tk-8bzuc2.

## The periodic scope-reading audit (tk-isd5sa)

A periodic audit that reads each epic's scope and re-homes misfiled work is the
backstop, and the only reach that work filed before create-time parenting has.
The audit is owned by tk-isd5sa — the central audit that runs on create and on a
queued schedule. This unit does not build a second audit; it supplies the two
inputs the audit reads: the membership definition and the four relationships above
(what "belongs" means), and the repair primitive (tk-8bzuc2) it calls to act.
Because the audit is non-interactive, the primitive it calls refuses rather than
warns.

## Reconciliation with adjacent work

- **tk-n18e15** owns the readiness-cascade fix: it stops filing the cascading
  `blocks` demand and relies on the track-only finalize-gate instead. That is the
  hold-finalization relationship, correct under this model and unaffected by it.
  The finalize-gate half (tk-p8svsz) is landed; tk-n18e15 is the
  stop-filing-the-demand half.
- **tk-c5atcz** owns `docs/epics.md`, the epic contract. Membership is a distinct
  topic; when `docs/epics.md` is written it should surface the four relationships
  and cite this record.
- **tk-isd5sa** owns the audit mechanism. This unit supplies its classification
  and repair inputs.

The reconciliation that produced this model — a post-merge review of PR 918 and
the resolution of its findings — is recorded in
[`pr918-review-reconciliation.md`](pr918-review-reconciliation.md).

## Deferred mechanics and the cost of waiting

This unit lands the definition; the mechanics are tracked, not dropped.

| Mechanic | Bead | Blocked on | Cost while deferred |
|---|---|---|---|
| Create-time parenting | tk-9wojzh | tk-n18e15 | Work routed under an epic subject is not parented as a member at creation, so a parentless-subject case renders outside its epic and needs manual re-homing. |
| Repair primitive | tk-8bzuc2 | none | Re-homing stays a manual, order-sensitive bead sequence, and the audit has nothing to call. |
| Scope-reading audit | tk-isd5sa | survey + contract | Misfiled work is not swept, and membership drifts as work is filed. |
