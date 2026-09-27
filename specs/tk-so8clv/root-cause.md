---
name: Root cause — deferred-dispatch arms do not fire on epic children
description: Investigation record for tk-so8clv. Armed epic children whose own blocks-edges had all closed sat undispatched for hours-to-days. Root cause is H1 (the parent-child is_blocked cascade), not H2 (a dead reconcile order). deferred-dispatch reconcile delegated its dispatch decision to `bd list --ready`, which excludes a bead held only by a blocked ANCESTOR; the epic tk-6bji7k is blocked by an open human demand gate, so every child cascaded is_blocked and never entered --ready though its own blockers had closed. Fix dispatches an open arm on its OWN blocks-edges; a new doctor check surfaces a dispatch owed but not firing.
---

# Root cause — deferred-dispatch arms do not fire on epic children

- **Bead:** tk-so8clv — "deferred-dispatch arms do not fire: armed beads sat hours-to-days with every blocks-edge closed, list shows waiting-on-a-blocker"
- **Investigated:** 2026-09-27, city `/home/zook/loomington`, `bd` 1.3.0-rc.2, gc-toolkit at `d4f69823`.
- **Author:** gc-toolkit/gc-toolkit.polecat (claude provider)

## The question

Two hypotheses were on the table: **H1**, the readiness computation treats a
parent-child edge (or a blocked/held parent) as a blocker, so arms on epic
children can never fire; or **H2**, the reconcile order is not running (a
recurrence of the rig-scoped order-firing stall, tk-5v3k5y / PR #837). Both had
been observed on this epic before, so the load-bearing task was to establish
which one produced the tk-so8clv instances.

## Determination: H1, from live evidence

The reconcile order is firing. `gc doctor` reports `order-outcome-healthy: ok —
all scheduled orders succeeding`, so H2 is not the operative cause here (and
order-firing is already guarded by core `order-firing-current` and pack
`check-cadence-live`/I10).

The armed children are held out of `bd list --ready` by the parent-child
`is_blocked` cascade. `bd --ready` filters `status='open'` first, then
`is_blocked=0`, and `is_blocked` propagates DOWN parent-child edges from a
blocked ANCESTOR. The epic `tk-6bji7k` is `status:open` but blocked by an open
human demand gate `tk-21ssxq` (`issue_type: gate`, `dependency_type: blocks`,
`gc.routed_to: human`), so it is `is_blocked=1`, and every child inherits it.

Discriminating read on one armed child, `tk-6bji7k.9`:

- its own `blocks` edge, `tk-6bji7k.1`, is **closed** (`closed_at
  2026-09-27T00:11:04Z`);
- it is NOT in `bd list --ready`;
- `bd blocked` attributes it as `blocked_by: [tk-6bji7k]` — the parent epic, not
  any own blocker.

So the child's own work is ready, but the cascade keeps it unready, and
`deferred-dispatch reconcile` — which delegated its dispatch decision entirely
to `bd list --ready` — never slings it. `deferred-dispatch.sh list` reads the
same not-ready set and prints `[waiting on a blocker]`, indistinguishable from a
bead genuinely waiting on its own open blocker. The arm outlives the sitting
that placed it, so nobody notices for days.

The shape law already forbids the topology that triggers this
(`docs/component-model.md` §"I1 in full": a bead that will ever carry a `blocks`
edge must have no `parent-child` children — containers do not block; blockers do
not parent). The epic violates it: it is a container with children AND is blocked
by the demand gate. But the topology is converse's to set, and `deferred-dispatch`
cannot depend on every future epic honoring the shape law — so the durable fix is
in the dispatch predicate.

## Why the fix is shaped this way

The arm's contract is "sling once the thing this bead waits on lands." The thing
it waits on is the bead's OWN `blocks` blocker (every arm's `--reason` names one:
"waits for tk-XXX to land"). `bd --ready` answers a different question —
claimability by a worker right now — which additionally requires no blocked or
deferred ancestor. For an epic child those diverge: the epic is deliberately held
on a human gate; the child's implementation is not. The operator's demonstrated
intent confirms the direction: children of this epic were dispatched by hand
(.7/.9/.10) while the epic gate stayed open, and this bead's own ask is "an armed
bead whose blocks-edges are all closed dispatches within one reconcile cadence."

So `reconcile` now dispatches an **open** armed bead once **every one of its own
`blocks` edges is closed**, independent of the ancestor cascade. `bd --ready` stays
the fast path; a bead bd holds unready is asked one direct question (`gc bd dep
list <id>` → are all its own `blocks` edges closed?) and dispatched on a yes. The
answer is read fail-closed: a dep list that is not a JSON array leaves the arm
armed rather than slinging on a guess. Preserved unchanged: the `status=open` gate
(a non-open bead is a deliberate hold, never dispatched), the HELD guard (an
assignee still withholds), the two-state `slung` marker recovery, the
merge_result retire, and the sling-failure cap.

`gc.execution_routed_to` is deliberately not consulted — it is execution
provenance, not a dispatch, and an open bead carrying only it is exactly the
shape the arm remedy is meant to re-sling.

## Surfacing a silent stall: doctor/check-armed-dispatch-owed

The fix makes the cascade case dispatch, but a dispatch can still silently fail
to fire for another reason (the order stops, or a sling wedges). `check-cadence-live`
(I10) catches a dead order; nothing caught an individual owed dispatch while the
order was alive. The new check flags an armed bead whose own `blocks` edges have
all closed, that is open and unassigned and not mid-dispatch, and that has stayed
armed past `max(3×interval, 15m)` (the reconcile cadence's window) — and an arm
sitting at a non-open status `bd --ready` can never answer. It mirrors reconcile's
own exemptions (closed, delivered, mid-dispatch, HELD-by-assignee) so it does not
cry wolf, and it fails toward silence when a timestamp or a store cannot be read.
Verified as a positive control against the live store: it flagged `tk-6bji7k.9`
and `tk-6bji7k.7` (own blockers closed ~7.5h earlier, undispatched), and correctly
left `.5`/`.6` (still an open own-blocker) and the refinery-assigned `.7` variant
unflagged.

## What this does not change

The `bd` readiness computation itself is unchanged — `--ready` still excludes
cascade-blocked children, correctly, for the pool-offer path (a worker should not
claim a child under a held epic). Only the deferred-dispatch arm, an explicit
targeted intent, reads past the cascade. The topology violation on `tk-6bji7k`
(a blocked container) is left for the epic's owner to resolve; the fix removes the
dependence on it being resolved.
