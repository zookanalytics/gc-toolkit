---
name: pool-slot-reap re-derived against Gas City's kill semantics — tk-1tfzr71.7
description: Why the pool-slot-reap order retired — what the controller now does with a killed or otherwise freeable pool seat, what the order's own record showed, and the residual shape it leaves to Gas City. Read it before reviving a pool-slot sweep.
---

# pool-slot-reap re-derived against Gas City's kill semantics

Bead: `tk-1tfzr71.7`. The order and its script were built on `tk-kwhll1p`
([specs/tk-kwhll1p/pool-slot-reap.md](../tk-kwhll1p/pool-slot-reap.md)).
Gas City was read on 2026-10-20 (UTC) in the city's installed `gc` (`b7da5db00`)
and at upstream main (`d9f45a182`). The pack was read at `e07af7197`.

## What the order stood in for

The order closed an asleep pool session bead that had held no runtime and no
work for 15 minutes. It named one cause: `gc session kill` sleeps a session
with `sleep_reason=killed`, which was not on the controller's slot-freeable
list, so a killed pool seat with no work kept its slot until something closed
its bead. The `tk-kwhll1p` spec records that gap and three live cases: a killed
polecat seat, three seats asleep on `config-drift`, and a canonical singleton
asleep on `idle` that nothing woke or closed for five days.

## What Gas City does now

- **A killed seat is freeable.** `isPoolSessionSlotFreeable` and its `Info`
  mirror (`cmd/gc/session_state_helpers.go`) free a slot for `idle`,
  `idle-timeout`, `city-stop`, `failed-create`, `runtime-missing`,
  `provider-terminal-error`, `max-session-age`, `config-drift` and `killed`,
  and for a drained bead or an empty reason with `slept_at` stamped. `killed`
  counts once no kill fence is honored. It arrived in upstream #7362
  (`4287ab1c2`, 2026-10-08), which both upstream main and `b7da5db00` carry.
- **The controller closes it.** The reconciler's pool-freeable close
  (`cmd/gc/session_reconciler.go`) closes a freeable pool seat that holds no
  assigned work, with its sleep reason as the close reason, so a kill closes
  as `killed` and the slot is free. What a kill does to the seat's claims and
  started work is stated in
  [gascity/agent-types.md](../../docs/gascity/agent-types.md), "Killing a pool
  session releases or restarts it".
- **`config-drift` is freeable too**, so the second `tk-kwhll1p` case is the
  controller's as well.

## What the order's own record shows

- Each close is a `cleanup` entry in the deacon's incident ledger. The ledger
  open since 2026-10-09 (`hq-9r5e4u`; the order landed 2026-10-08) holds three:
  `hq-wisp-e9yi1` (2026-10-10T03:44Z), `hq-wisp-utuji` (2026-10-10T13:33Z) and
  `hq-wisp-u134u` (2026-10-11T03:38Z). Each had slept 40 to 54 minutes with no
  sleep reason, a shape the controller has freed since upstream #6356
  (2026-09-14).
- There is none after 2026-10-11T03:38Z. The order kept firing about every
  five minutes (`gc order history pool-slot-reap`), so more than 2,000 passes
  found nothing to close.
- A dry run at 2026-10-20T00:24:54Z found one asleep session, the
  rig-b witness, a named session it never closes, and would close
  nothing.

## The residual shape, and where it goes

Two shapes remain that the order would close and the controller would not:

1. An asleep pool seat whose reason is neither freeable nor a deliberate hold.
   `no-wake-reason` and `assigned-work-exhausted` are the two reasons in
   `internal/session/sleep_reason.go` on neither list.
2. A seat on a freeable reason that the controller leaves behind, as it left
   the canonical singleton in the third `tk-kwhll1p` case and the three
   empty-reason seats above.

Neither has appeared since 2026-10-11T03:38Z, because the order would have
closed it. If either recurs, it is a question about Gas City: whether that
reason should free a slot, or why the controller left a slot its own rules
free. It goes to the gascity fork's bug route, not to a pack sweep, because
glue may not add semantics a native mechanism already expresses
(docs/foundation.md, Boundaries, test 3). One instance clears by hand with
`gc session close <id>`.
`gc session prune --state asleep --before <age>` is the native bulk verb, but
it reads neither assigned work nor named sessions, so it does not replace the
order's guards.

## What retired

`orders/pool-slot-reap.toml`, `assets/scripts/pool-slot-reap.sh` and its
test, and their rows in `docs/architecture.md` (the reactive paths),
`docs/authority-map.md` (powers over sessions) and `docs/component-model.md`
(two rows). The session-liveness member (`tk-1tfzr71.18`) re-derives its own
compensations against the same kill semantics.
