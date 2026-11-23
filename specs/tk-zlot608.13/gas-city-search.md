---
name: Gas City search for the distiller's once-per-city start (tk-zlot608.13)
description: The Gas City primitives searched for each need of starting the feedback distiller once for the city in the pack's home rig, with what each covers and why the gap is an exec order of city scope running gctk distiller start. Read it when reviewing the distiller's order or the distiller noun, as AGENTS.md asks of a change that adds an order and a gctk verb.
---

# Gas City search for the distiller's once-per-city start

This change replaces the distiller's rig-scoped formula order with an exec
order of city scope, `orders/feedback-distiller.toml`, which runs a new gctk
verb, `gctk distiller start`, in a new noun, `distiller`, that owns nothing
but the start's lock. It also grows the runtime adapter with a formula sling.
It adds no key and no bead kind. Each need below names the primitive searched,
by symbol at `gastownhall/gascity` main dc87c978a3 (2026-11-21). The behavior
checks ran on the city's gc, 1.4.3, through `services/gctk/distiller`'s
`TestCityAcceptance`.

## Register the order once, whatever rigs import the pack

**Covered: an order of city scope.** `orders.Order.Scope` in
`internal/orders/order.go` registers a `city` order "exactly once regardless of
how many rigs import the pack" and a `rig` order "once per importing rig"
(`IsCityScoped`). The acceptance test reads `gc order list --json` in a scratch
city whose two rigs import the pack, and finds the distiller once, for the city.

## Run the distiller in one rig only

**Not covered.** Nothing a pack ships picks the rigs an order runs in.
`orderDecode`, the fields `internal/orders/order.go` decodes from an order file,
holds no rig list, and `config.PackConfig` in `internal/config/pack.go` has no
field that limits an order to some rigs: its `PackPatches` patch agents alone.
Only the city's config picks rigs, through `[[orders.overrides]]`, whose
`Override.Rig` names one rig or `RigWildcard` every instance
(`internal/orders/override.go`), with `ApplyOverrides` and then `FilterEnabled`
(`internal/orders/filter.go`) turning a pack-disabled order on per rig. That is
per-rig city config, which the operator's ruling in conversation tk-azsaa28
removes: "ideally we remove the non-default city config". So the verb picks the
rig itself.

Gas City dispatches no order of a suspended rig
(`memoryOrderDispatcher.orderRigSuspended` in `cmd/gc/order_dispatch.go`), and
the verb keeps that rule for the home rig.

## Pour the run where the home rig's pool claims it

**Not covered by a formula order of city scope.** `resolveOrderStoreTarget` in
`cmd/gc/order_store.go` sends an order with no rig to the city's store before it
looks at the order's pool, so a city formula order pours its run into the
city's store even when its pool names a rig's agent. A rig's pool queries its
own rig's store first and the city's only as a best-effort second leg
(`hookWorkQueryStores` in `cmd/gc/hook_cross_store.go`), and two open issues
report the cross-store path failing: gastownhall/gascity#5857 (city-store rows
counted as a rig pool's demand that the rig seat never claims) and
gastownhall/gascity#9159 (a claim of a bead in another store fails "bead not
found").

**Covered: `gc sling <rig>/<pool> <formula> --formula`.** For a formula name,
`resolveSlingStoreRoot` in `cmd/gc/cmd_sling.go` takes the store from the target
agent's rig, `rigDirForAgent`, resolved by `resolveStoreScopeRoot`
(`cmd/gc/main.go`), and `openSlingStoreForSource` opens that store by its path.
An exec order of city scope runs with `BEADS_DIR` naming the city's store and
`GC_RIG` empty (`orderExecEnvWithError` in `cmd/gc/order_store.go`), and the
acceptance test's run of the order still pours the root in the home rig's store,
none in the city's or the other rig's, and the home rig's polecat pool claims it
with `gc hook --claim`. The sling also sets the formula's `binding_prefix` from
the pool's binding (`buildSlingFormulaVars` in `internal/sling/sling.go`).

## Start no second run while one is open

**Not covered.** The dispatcher holds an order back while its previous
dispatch is in flight: an open tracking bead, or a live root that carries the
order's `order-run` label, which a formula order's dispatch stamps on what it
pours (`orderTrackingSummary` and `openWorkGateShut` in
`cmd/gc/order_dispatch.go`). An exec order's tracking bead closes when the verb
exits, and the run it slings carries no such label, so the gate does not hold
the next pass while that run goes on. Stamping the label on the slung root
would write the dispatcher's own record of what it poured, and a start by hand
would still slip past it. `gc sling --formula` refuses a pour only when a source
bead already has a live workflow (`sourceworkflow.ConflictError`, printed by
`printSourceWorkflowConflict` in `cmd/gc/cmd_sling.go`), and a formula slung
with no bead has none. A mutant of the verb that skips its check pours a second
root on the acceptance test's second run.

So the verb reads the home rig's store first, for a live root Gas City stamped
at the pour as a workflow (`gc.kind`) of the distiller's formula
(`gc.formula_name`), the stamps `lifecycle/lifecycle.toml` lists under
`[metadata.runtime_owned]`, and slings nothing while one is there. It reads no
key of its own, so a run poured by any path holds the next start.

**Not covered either: two starts at once.** The dispatcher's gate keeps the
order's own passes apart, and nothing in Gas City keeps a `gc order run` or a
start by hand from overlapping a pass or each other. `gc order run` runs an
exec order with no check for a run in flight: `doOrderRunWithJSON` in
`cmd/gc/cmd_order.go` finds the order and calls `doOrderRunExecTracked`, which
records the run's tracking bead and runs the exec. A start by hand passes no
gate at all. So two starts can each read no root before either pours. Gas
City's flocks, such as `flockWithBoundedWait` in
`cmd/gc/beads_scope_ownership.go`, guard its own writes, and no `gc` command
takes a lock for its caller. So the verb takes a lock of its own without
waiting: a flock on `distiller-start.lock` in the city's
`.gc/runtime/packs/gc-toolkit`, where the pack's dispatch locks live, held from
before its read of the store to the sling's end. A start that finds it held
starts nothing. The acceptance test holds that lock and runs the order, which
pours nothing, and a mutant of the verb that takes no lock pours a root there.

## Find the home rig and its pool

**Not covered.** No field of Gas City names the rig whose checkout is a pack's
own. A rig's import (`[rigs.imports.<binding>]`) names where the city loads the
pack from, which can be a cache or a checkout that is no rig. So the verb reads
`gc rig list --json` and takes the one rig, the HQ aside, whose checkout holds a
`pack.toml` that names the gc-toolkit pack, the test the formula's load-and-gate
step made in every rig.

Gas City qualifies an order's bare `pool` with its pack's binding
(`qualifyOrderPool` in `cmd/gc/order_dispatch.go`), and an exec order has no
pool to qualify. So the verb takes the pool from `gc agent list --json`, the one
agent named `polecat` that it places in the home rig, as `gctk refinery stuck`
takes each rig's refinery.

## Why not a sub-pack that only the home rig imports

A pack under `packs/`, as `packs/gascity-keeper` is, could carry the distiller's
order with rig scope, and Gas City would register it in the one rig that
imports it, with no verb. It is not chosen because the import is itself a line
of city config for the home rig, `[rigs.imports.<binding>]` in the town's
`city.toml`, the per-rig config the ruling removes. A city that imports the pack
would also have to know to add it. It needs a cut-over across two
repositories as well: the order leaves the pack's `orders/` in one change, and
the import lands in the town's `city.toml` in another, so between the two
either the distiller runs in no rig or the city's config imports a pack that is
not there yet.
