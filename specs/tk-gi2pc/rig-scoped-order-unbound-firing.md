---
name: Rig-Scoped Orders Fire Unbound at City Scope
description: Why a scope="rig" order with a bare pool also registers with no rig bound, strands an unclaimable workflow root every cooldown, and where the fire-time guard has to live.
---

# Rig-Scoped Orders Fire Unbound at City Scope

> **Bead:** tk-gi2pc. **Investigated:** 2026-08-09. **Author:** Polecat gc-toolkit.furiosa.
> Mayor's diagnosis (tk-gi2pc notes, 19:36Z) traced this to "a fire-time binding
> leak, not a missing decision" and was correct. This document names the leak's
> exact mechanism, corrects the one part of that note that does not survive
> contact with the code, and records why the durable guard cannot ship in this
> pack.

## Scope

**Mandate.** The mechanism behind the mol-liveness-sweep / mol-triage-recurrence
strand of 2026-08-09, the guard that closes it, and where each half of the fix
lands. Written for whoever implements the gascity-side guard.

**Boundaries.** Not a description of the sweep formulas themselves, and not a
record of the strand cleanup (already done; see the bead). Line references to
gascity are pinned to the fork at `rigs/gascity` as of 2026-08-09 — grep the
symbol names, which are stable, rather than trusting the numbers.

## Symptom

Two workflow roots sat open, unassigned, and unclaimable in the HQ (`lx`) store:

```
lx-dh2v  mol-liveness-sweep     gc.routed_to = "gc-toolkit.polecat"  (bare)
lx-3sik  mol-triage-recurrence  gc.routed_to = "gc-toolkit.polecat"  (bare)
```

`gc doctor` session-model reported both as blocking `stale-routed-config`
findings. The town's liveness sweep and triage recurrence had not run since the
strand began. Every configuration file involved was correct.

## The bare pool is correct; the binding is what leaked

`orders/liveness-sweep.toml` declares a **bare** pool deliberately, and says so
in its own header: a bare pool qualifies within each importing rig to that rig's
own polecat pool, with the wisp in that same rig's store, which is
self-consistent for every importer. `orders/doc-keeper-drift-audit.toml` carries
a longer version of the same reasoning. `doctor/check-liveness-sweep-wired`
asserts that shape is present and passes — correctly. **The wiring is sound.**

It is sound *when a rig is bound*. The leak is that a rig is not always bound,
and nothing notices.

## Mechanism

Order discovery scans this pack's `orders/` **twice**
(`gascity internal/orderdiscovery/discovery.go`, `ScanAll`):

1. **City pass** — `orders.ScanRoots(fsysImpl, CityOrderRoots(cityPath, cfg), …)`.
   The results keep `Rig == ""`.
2. **Rig pass** — once per rig, over that rig's *exclusive* layers. Each result
   is stamped `aa[i].Rig = rigName`.

`scope` is consulted **only on the rig pass**, and only to promote a
`scope = "city"` order back to a single city-wide registration
(`aa[i].IsCityScoped()`). On the city pass the field is never read. A pack
imported by rigs is nonetheless on the city layer list, so every order it ships
— rig-scoped or not — also gets one registration with `Rig == ""`.

That unbound copy then fails silently at every subsequent step:

- `qualifyPool` (`cmd/gc/order_dispatch.go`) returns a bare pool **unchanged**
  when `rig == ""`. With a rig it always produces a qualified name, worst case
  `rig + "/" + pool` — which is why every rig-bound copy works.
- `resolveOrderStoreTarget` (`cmd/gc/order_store.go`) takes the
  `strings.TrimSpace(a.Rig) == ""` branch and returns a **city**-scope store
  target, so the wisp is poured into the HQ store.
- Nothing at city scope can claim a bare rig-pool name. The root sits open,
  unassigned, unclaimable — until a human closes it.
- The order keeps its cooldown, so it **re-strands every interval**.

Observable today, before any fix:

```
$ gc order list --json | jq -r '.orders[] | select(.name=="liveness-sweep")
                                | [(.rig // "-"), .target] | @tsv'
-                gc-toolkit.polecat     <-- unbound: strands every 6h
gascity          gc-toolkit.polecat
gc-toolkit       gc-toolkit.polecat
shutupandlisten  gc-toolkit.polecat
signal-loom      gc-toolkit.polecat
```

## Why only these two orders

All four of this pack's rig-scoped orders have the exposure. Two of them do not
strand because `city.toml` carries a hand-written override that disables the
unbound copy specifically — an `[[orders.overrides]]` entry with
`enabled = false` and **no** `rig` key, for `doc-keeper-drift-audit` and
`doc-keeper-memory-audit`. `liveness-sweep` and `triage-recurrence` were added
later without one.

That is the whole story of the outage: the working configuration depended on
each new rig-scoped order remembering a workaround written down nowhere near
the order file. It is precisely the failure class the bead asks to remove — a
convention that fails **silently** when someone does not follow it.

## Correction to the filing note

The bead's 19:36Z note reads the evidence as "a `scope = "rig"` order produced a
wisp in the HQ store — i.e. it fired once in a context with no rig bound,
`GC_RIG` was empty, the `${GC_RIG:+…}` prefix collapsed". The conclusion (an
unbound fire) is right; the pathway is not. This is not a one-off fire from a
stray shell with an empty `GC_RIG`, and no shell parameter expansion is
involved: the unbound registration is **permanent and structural**, created on
every scan, and it will fire again on its own cooldown. Nothing about the
environment of any particular fire matters. That distinction is what makes an
environment-level guard ("always set `GC_RIG`") the wrong remedy and a
discovery-level one the right one.

## The fix, in two halves

### Half 1 — the guard (gascity Go; NOT this pack)

The bead's requirement 1 asks that a `scope = "rig"` order refuse to fire with
no rig bound, and prefers refusing over emit-then-detect. That guard belongs in
`ScanAll`, immediately after the city pass: drop any city-pass order that
**explicitly** declares `scope = "rig"`, and log it loudly.

Tracked as **`gc-xaqpf`** in the gascity rig (filed 2026-08-09 from this bead,
priority 1), which carries the mechanism, the patch site, and the test.

One detail decides whether that patch is correct or catastrophic:

> `Scope` defaults to `"rig"` when **empty**, but an empty field is not a
> declaration. The filter must key on the literal string `"rig"`, never on
> `!IsCityScoped()`. `IsCityScoped()` is `Scope == "city"`, so filtering on its
> negation would delete every city-local order that simply never mentions
> `scope` — which is most of them, including the builtin core order set.

A city-local order (one in the city's own `orders/` root) that declares
`scope = "rig"` is in no rig's exclusive layers, so the guard removes it
entirely and it runs nowhere. That is the correct outcome — it could only ever
have stranded — but it is a behavior change and is exactly why the drop must
log rather than be silent.

Belt and braces: `resolveOrderStoreTarget` can also refuse a declared-rig-scope
order whose `Rig` is empty, so a future discovery path cannot reintroduce the
strand.

Requirement 5's test lands here too, as a Go test: scan a fixture pack whose
order declares `scope = "rig"` with a bare pool, assert no `Rig == ""`
registration survives, and assert an order with no `scope` key is untouched.

### Half 2 — the backstop (this pack, shipped with this bead)

`doctor/check-rig-scoped-orders-bound` fails with an error for every **live**
registration that has no rig bound and whose order file declares
`scope = "rig"`. It judges an entry from that entry's own source file, so it
covers any order in the city with this exposure rather than only the four here;
it falls back to matching this pack's own order names when a listed source
cannot be read; and an unreadable or malformed listing **warns** instead of
reporting clean, because "could not tell" and "nothing wrong" are different
answers and collapsing them is the same fail-open the check exists to remove.

A disabled unbound copy does not appear in `gc order list`, so the two existing
`city.toml` overrides keep the doc-keeper pair green. Against the live city on
2026-08-09 the check reports exactly the two stranding orders and nothing else.

Once half 1 lands, this check is permanently green and becomes the regression
gate: it is what makes the strand impossible to reintroduce by adding a new
rig-scoped order.

## What was deliberately not done

- **No `city.toml` change.** Adding two more `enabled = false` overrides would
  clear today's strand and leave the next new order to strand exactly the same
  way. The operator ruled the city.toml path out of scope, and requirement 2
  rules out extending a convention that fails silently.
- **No HQ-scope pool.** Considered and rejected by the operator: `lx` does not
  need a liveness sweep.
- **No change to the bare-pool-at-rest convention.** Bare + `scope = "rig"` is
  correct and deliberate; late qualification per importing rig is the design.
- **The orders were not converted to `exec` orders.** A shared exec wrapper
  could refuse to sling with an empty `GC_RIG`, which would be a genuine
  fire-time guard shipped from this pack — but it would rebuild the working
  rig-side path on a different dispatch mechanism (no formula tracking bead, no
  single-flight gate, different var injection) to fix a case that only affects
  the broken unbound copy. The bead's reference explicitly requires the rig-side
  sweeps to keep working; that trade is not worth it.
