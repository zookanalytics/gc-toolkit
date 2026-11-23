---
name: Gas City search for sending a failure's tracker to be fixed
description: The search the arch check asks for before the tracker writer, preexisting-failure.sh file, slings each tracker it files to its rig's polecat pool and a first reaction's intake admits a tracker to a pool. What Gas City, bd and the Gas Town pack ship near that need, read at named upstream commits, why the change composes a sling that names no target, and why neither a create nor an order carries the send. Read it when checking whether the send can move onto a Gas City primitive, or for the operator's words on a failure held for placement.
---

# Gas City search for sending a failure's tracker to be fixed

A tracker is the bead `assets/scripts/preexisting-failure.sh file` files for a
failure a gate reproduced on a base branch, keyed by the `failure_key` stamp in
its create. This change makes the writer send each tracker it files to its rig's
polecat pool, and makes a first reaction's intake admit a tracker to a pool. So
the arch check asks what Gas City already ships for that need
([review-arch.md](../../docs/review-arch.md#the-checks), check 1). Gas City
ships the whole send: a sling that names no target goes to the rig's default
sling target on that agent's default formula. The change composes it, and adds
no command, key, kind, order or state.

## The need

In conversation tk-tkpw1d9 on 2026-11-22, a sitting told the operator that the
tracker of four board page tests failing on main waited in their queue of held
new work. The operator answered: "What's interesting, is that a failure on main
is held at all. That should just get fixed. So worth a follow-up".

The tracker writer filed each tracker as an unrouted P1 bug, and nothing sent it
on. Intake is off in the rig that tracker was filed in. Where intake runs, a
first reaction held a tracker for placement, because intake admitted only a
member of an epic, PR-finishing work and an emergency that a check on main
confirms. And the work skill had an agent hold every other bead it filed. On
2026-11-23 the city's stores held 42 live trackers, none slung to a pool or
assigned: 5 held for placement and 37 unrouted.

The need: a tracker goes to its rig's polecat pool on the pool's default formula
as soon as it is filed, whichever gate files it, with no placement hold and no
person's step between. A failure is sent once: a gate that finds the failure
tracked already files nothing, and sends nothing.

## The surface

- `preexisting-failure.sh file` slings the tracker it files, once its stamp
  reads back, with `gc sling <tracker>` and no target or formula. A bead it
  finds rather than files it does not sling. A sling that fails leaves the
  filing successful, and its warning names the sling to run. The script gains no
  verb, flag or output key: its stdout is still the tracker's id.
- `gctk reaction dispose` admits a bead that carries `failure_key` to a pool,
  beside a member of an epic, PR-finishing work and a confirmed emergency. It
  reads the key and writes none, so `services/gctk/reaction` declares it
  read-only.

## What Gas City and bd ship

1. **A sling that names no target.** Composed. `gc sling <bead>` with one
   argument resolves its target from the bead's rig: `inferSling1ArgTarget` in
   `cmd/gc/cmd_sling.go` (`gastownhall/gascity` 1f1f1289df) reads the bead's
   prefix, finds the rig with that prefix, and returns one of its
   `default_sling_targets` at random or its `default_sling_target`, or fails
   with `target_resolve_failed` when the rig sets neither. `DefaultSlingTarget`
   in `internal/config/config.go` at the same commit is "the agent qualified
   name used when gc sling is invoked with only a bead ID". With no `--on`, the
   sling pours the target's `default_sling_formula`, which `[agent_defaults]`
   gives every agent (`DefaultSlingFormula`, `internal/config/config.go`). The
   city sets each rig's `default_sling_target` to its polecat pool and
   `[agent_defaults]` to `mol-polecat-work`, so the sling is the need's
   destination with no pool named in the pack. A dry run on a live tracker,
   `gc sling --dry-run <tracker>` under gc 1.4.3, resolved to
   `gc sling gc-toolkit/gc-toolkit.polecat <tracker>` on the default formula
   `mol-polecat-work`.
2. **A create that dispatches.** None fits. `bd create` files a bead and routes
   nothing, and the pack dispatches only through `gc sling`, which pours the run
   a bead's work needs (the work skill, "One dispatch, never two").
   `gc sling <target> "<text>"`, and its `--stdin` form, create a task from text
   and route it in one call (`gc sling --help`), but they take no metadata. The
   `failure_key` stamp could not ride that create, and the next gate's lookup,
   which reads only the stamp, would file a second tracker. So the tracker is
   created with its stamp and then slung, two writes, and a sling that fails is
   warned.
3. **An order on the create.** Not used. A Gas City order can fire on an event,
   `on = "bead.created"` for one (`docs/tutorials/07-orders.md`, "Trigger
   types", `gastownhall/gascity` 1f1f1289df), and such an order could sling each
   new tracker. The pack owns the writer, and its rule is that a writer it owns
   settles in the same act, with an order only as the backstop for raw writes no
   writer sees
   ([gctk-architecture.md](../../docs/gctk-architecture.md#writes-stay-native-and-pack-logic-reacts)).
   A tracker is the writer's own create, so there is no raw write to back. The
   event order would also deliver at least once and spend the orders' shared
   dispatch budget (`orders.max_dispatches_per_tick`, the same page), for
   nothing the sling lacks.
4. **Gas City's and Gas Town's own pre-existing failure.** Each files it
   unrouted. Core's `mol-polecat-base`, in the step `preflight-tests`, files
   `gc bd create --title "Pre-existing failure: ..." --type bug --priority 1`
   and mails the escalation target
   (`internal/bootstrap/packs/core/formulas/mol-polecat-base.toml`,
   `gastownhall/gascity` 1f1f1289df). The Gas Town pack's refinery files the
   same P1 bug after a title search and goes on with the merge
   (`gastown/formulas/mol-refinery-patrol.toml`, "If pre-existing on target",
   `gastownhall/gascity-packs` 44b9db7168). Neither routes the bug. This city
   holds new work for the operator's placement instead, and the operator
   directed that a failure on main be fixed rather than placed, so the pack
   sends the tracker itself.
   [built-once-target.md](../../docs/built-once-target.md) names the difference.

## What the change leaves in place

- **A sling that fails.** The sling fails when the tracker's rig sets no
  default sling target, which every rig in the city sets, or when gc cannot
  reach the store that answered the create a moment before. It has not been
  seen, since the send is new. Its tracker stays filed and unsent, and the next
  gate that meets the failure finds the tracker and sends nothing. The warning
  names the sling to run, the work formula and the work skill tell the agent to
  run it, and where intake runs, a first reaction now routes the tracker.
- **Trackers filed before this lands.** None is sent: the 42 above stay held or
  unrouted until someone places, sends or closes each.
- **A failure seen only on an integration branch.** A tracker carries no base
  branch, so its run branches from the rig's default branch. None of the 70
  trackers that carry a `failure_key` in the city's stores on 2026-11-23 names
  an integration branch in its title or description.
