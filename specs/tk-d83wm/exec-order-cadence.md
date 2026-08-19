# Replacing the /tmp refinery idle driver with a core exec order

Bead: tk-d83wm. Landed as `orders/refinery-reconcile.toml` +
`assets/scripts/refinery-reconcile.sh`. The standing description of the result
is [docs/refinery-merge-cadence.md](../../docs/refinery-merge-cadence.md); this
file is the determination behind it — in particular the answers to the two open
questions the bead said had to be settled before writing anything.

## Q1. Does the controller serialise cooldown orders?

The daemon held a per-rig `flock` so two `merge-skill.sh` writers could not race
the same anchors. The question was whether the order runner gives the same
guarantee.

**It does, and by a stronger mechanism.** Read in `rigs/gascity` at the pin this
work was done against:

- `cmd/gc/order_dispatch.go`, tick loop: before dispatching, an order is skipped
  when `trackingIndex.hasOpenTracking(...)` reports an open tracking bead for
  its scoped name. A second gate, `hasOpenWork`, checks the same flag and falls
  back to a per-order query.
- The tracking bead is created **synchronously in the tick loop** —
  `m.orderFrontDoorFor(store).CreateRun(a.ScopedName(), ...)` — *before* the
  dispatch goroutine launches. The comment at that site is explicit: "Create the
  tracking bead (which suppresses re-fire on the next tick)".
- `dispatchOne` closes it in a `defer` that runs after the exec returns:
  `closeOrderTrackingBead(ctx, m.ordersStoreFor(store), trackingID)`.

So the window in which a second dispatch could start is exactly the window in
which no run is in flight. That is the flock's guarantee, enforced one level up,
and it needs no on-disk artifact to survive a reboot.

**It is per rig, not per order.** `orders.Order.ScopedName()` returns
`<name>:rig:<rig>` for a rig-bound order (`internal/orders/order.go`), and every
gate, cooldown clock and tracking bead keys on that string. Four rigs get four
independent single-flights; a slow rig does not stall its co-tenants.

Two ways to lose the guarantee, both recorded in the order file and the doc:

1. `no_work_gate = true` opts out of **both** gates
   (`internal/orders/order.go`: "Setting NoWorkGate skips both gates"). This
   order must never set it.
2. Core's `order-tracking-sweep` closes tracking beads older than
   `--stale-after 10m`. A run that outlives that window has its own gate
   removed. `timeout = "300s"` keeps the controller's kill earlier than the
   sweep, so a *wedged* pass is bounded too, not just a slow one.

## Q2. Is `exec` + `scope = "rig"` supported?

**Yes.** Nothing in `orders.Validate` couples the two (`scope` is checked only
against `"" | "city" | "rig"`), and the rig-scoped exec path is fully wired:

- `internal/orderdiscovery/discovery.go` stamps `aa[i].Rig = rigName` for every
  non-city-scoped order found on a rig pass. The branch is not conditioned on
  exec vs formula.
- `cmd/gc/order_store.go` `resolveOrderStoreTarget` resolves `a.Rig` to that
  rig's path and returns `ScopeKind = "rig"`.
- `orderExecEnvWithError` then sets, **only on that branch**, `GC_RIG` and
  `GC_RIG_ROOT`, alongside a rig-scoped `BEADS_DIR` and `GC_BEADS_PREFIX`. Both
  keys are in `IsReservedExecEnvKey`, i.e. the runner owns them and an
  `[order.env]` cannot shadow them.
- The exec itself runs with `cmd.Dir = target.ScopeRoot` — the rig's own root.

That last point retires a footgun by construction rather than by instruction: a
`systemd --user` unit inherits `WorkingDirectory=!$HOME`, which is not a work
tree, so every pass that resolves the repository through
`git remote get-url origin` failed closed while the unit read active/running.
The arming script existed largely to remember `--working-directory`. The order
runner has no equivalent to forget.

Empirically, the pack already ships a rig-scoped order whose `check` runs through
this same env builder (`orders/liveness-sweep.toml`), and it stamps its state per
rig for exactly the reason below.

### Consequence: state must be keyed by rig

`GC_PACK_STATE_DIR` is CITY+PACK scoped (`citylayout.PackStateDir`), so all four
rigs share one directory. The runner keys its state dir by `GC_RIG` using the
same `state_key` sanitizer as `liveness-sweep-precheck.sh`. Unkeyed, one rig's
handoff dedup would suppress another rig's report.

The same reasoning applies to every other per-rig value, because one
`[order.env]` serves all four registrations. The refinery identity is discovered
from `gc agent list` and both polecat pool addresses are derived from *that one*
answer, so a rename cannot leave the script repairing beads for one identity
while dispatching children to another. The convoy-graduation target comes from
the rig's own `origin/HEAD`. The old drivers hardcoded all of these per copy,
which is how two of the four ended up missing passes the other two had.

## What was verified, and how

- **Registration.** Synthetic city (`gc order list --city`) built twice — once
  against a `git archive origin/main` export, once against this branch — with
  `city.toml`'s `[[orders.overrides]]` stripped, since they name rig-scoped
  orders and abort the listing in a city that lacks the builtin imports. The
  first attempt returned an empty diff *because both sides exited 1*; the
  stripped run is the real control. Diff: exactly four added rows,
  `refinery-reconcile exec cooldown 60s` on gascity, gc-toolkit,
  shutupandlisten and signal-loom, with identical stderr.
- **Execution.** The runner was run against the live city with the seven passes
  replaced by argv-recording stubs and the real `gc` and `git` — read-only, no
  writer ran — for the owning rig (gc-toolkit) and an importer rig
  (signal-loom). Both resolved `<rig>/gc-toolkit.refinery`, derived both pool
  addresses from it, and wrote a per-rig log.
- **Behaviour.** `assets/scripts/refinery-reconcile.test.sh`, 46 hermetic
  assertions, with a positive control (deleting a pass from the runner fails
  assertion 2).
- **The heal gate.** `check-set-heal.test.sh`'s run 6 extracted the real
  gating snippet from `mol-refinery-patrol.toml` and drove the real
  `check-set-heal.sh` into it against a merge-skill stub. That snippet moved
  here with the cadence, so the markers moved with it and the test now extracts
  from the runner: same fixtures, same guarantee (an unsafe heal HOLDS the merge
  in the same pass), asserted against the code that actually runs it.
- **Wiring.** `doctor/check-refinery-handoff-reconcile` was re-pointed from the
  formula to the order + runner, and both of its new arms were shown to fail
  when the wiring is cut.

## What is deliberately NOT here

- **The passes themselves.** Their contracts are unchanged; this bead moved the
  cadence, not the work. Whether the seven fork-invented reconcile passes should
  exist at all is a separate and much larger question (the bead's own scope
  note).
- **Runtime teardown.** Stopping the four live units and removing
  `/tmp/gc-refinery-idle-*` is the operator's, out of band. Nothing here touches
  a running driver: with both live, the passes would run twice per minute per
  rig, which is the pre-existing behaviour of an agent that ran them inline, not
  a new hazard — but the units should come down when this lands.
- **Delivering the fresh-handoff signal.** The runner keeps the daemon's
  detector (a pushed branch with no anchor, i.e. a lost MERGE_READY) and reports
  it on stdout and in the log — which the controller keeps only on a failing
  exit, exactly as the daemon's copy reached only journald. Making that signal
  actionable (a nudge to the rig's refinery) is a real improvement and a real
  behaviour change; it is filed separately as tk-vd5ph rather than folded in here.
