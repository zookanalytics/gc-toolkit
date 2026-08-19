---
name: Refinery merge cadence
description: What makes the refinery's reconcile passes run when no agent is awake — the exec order that owns the clock, the single-flight guarantee that keeps two merge writers off one anchor, and where a pass's output goes. Read it to know what drives the merge queue, and why nothing else may.
---

# Refinery merge cadence

`merge-skill.sh` fires only from this cadence. So the cadence *is* the merge
queue's clock: when it stops, APPROVED + CLEAN pull requests sit unlanded and
nothing about the city looks wrong — the rig is not suspended, the refinery is
configured, `gc doctor` is green, and the stall is found hours later by a human
noticing that approved work is not merging.

## Scope

This doc owns one question: **what drives the refinery's reconcile passes, and
under what guarantees.** It covers the order that supplies the cadence, the
single-flight property that keeps two writers off one anchor, the environment a
pass runs in, and where a pass's output can be read.

It does **not** cover what the individual passes do. Each pass's contract — what
it enumerates, what it refuses, what it stamps — belongs to
`formulas/mol-refinery-patrol.toml`'s find-work step, which remains their
specification; the lifecycle they move a bead through is
[work-bead-state-machine.md](work-bead-state-machine.md).

## Mechanism

Every 60s, per rig: `orders/refinery-reconcile.toml` (`trigger = "cooldown"`,
`scope = "rig"`) execs `assets/scripts/refinery-reconcile.sh`, which runs the
seven reconcile passes in the formula's order and exits.

| | |
|---|---|
| Cadence | `interval = "60s"`, tunable from city.toml `[[orders.overrides]]` |
| Scope | `scope = "rig"` — one registration per importing rig |
| Working directory | the rig's own root (`target.ScopeRoot`), so `git remote get-url origin` resolves |
| Environment | built by the controller: `GC_RIG`, `GC_RIG_ROOT`, `BEADS_DIR`, `GC_BEADS_PREFIX`, `PACK_DIR`, `GC_PACK_STATE_DIR`, the Dolt projection, and the `gh` token |
| Timeout | `300s`, deliberately under core `order-tracking-sweep`'s 10m stale window |
| Graduation target | this rig's own `origin/HEAD`, falling back to `main` |

One `[order.env]` serves all four registrations, so anything that must differ
per rig is derived inside the runner from `GC_RIG` / `GC_RIG_ROOT`: the refinery
identity (and, from it, both polecat pool addresses), the state directory, and
the convoy-graduation target. A constant in the order file would be exactly the
per-rig drift this replaced.

The refinery *agent* does not drive it. Its find-work step ends the turn when it
finds no work; the passes keep running whether or not any refinery in the city
is awake.

## Single-flight: why there is no lock

Two `merge-skill.sh` writers against the same anchors is the failure this
arrangement exists to prevent. The controller already prevents it:

- The tracking bead for a run is created **synchronously before** the run
  launches and closed in a `defer` **after** it returns.
- The dispatcher's first gate skips any order that has an open tracking bead.
- That gate keys on `ScopedName()`, which for a rig-scoped order is
  `refinery-reconcile:rig:<rig>` — so each rig has its own single-flight and
  co-tenant rigs never serialise against each other.

Two consequences worth stating explicitly, because both are easy to undo:

- **Never set `no_work_gate` on this order.** That flag opts an order out of
  both open-work gates, and the first of them is the guarantee above.
- **`timeout` must stay below `order-tracking-sweep --stale-after`** (10m in
  core). That sweep closes a tracking bead it judges stale, and an un-gated
  tracking bead is a second dispatch. Keeping the kill earlier than the sweep is
  what makes single-flight hold for a *wedged* pass and not merely a slow one.

## Reading what a pass did

The controller keeps an exec order's combined output only when the command exits
non-zero, folding a bounded tail into the `order.failed` event. The runner is
built around that:

- A pass that fails an unexpected way makes the runner exit 1, so the failing
  pass names reach `order.failed`.
- `check-set-heal.sh` rc=3 is a **designed hold**, not a fault — it holds
  `merge-skill.sh` for that tick. It is reported but does not fail the order; an
  approval-gated queue would otherwise raise `order.failed` every 60s.
- A healthy pass is readable in
  `<GC_PACK_STATE_DIR>/refinery-reconcile/<rig>/pass.log`, trimmed to
  `REFINERY_RECONCILE_LOG_KEEP` lines (2000 by default).

`gc order list` shows the order and its per-rig registrations.

## Why an order and not a daemon

Until 2026-08 the cadence was a hand-authored shell daemon per rig —
`/tmp/gc-refinery-idle-<rig>/idle-loop.sh`, arming itself into a transient
`systemd --user` unit — because the formula wrote the cadence as
`sleep {{event_timeout}}` and the harness blocks foreground `sleep`.

Four copies, already drifted apart, in tmpfs, outside the city: `gc` shutting
down did not stop them, `gc status` did not show them, and city.toml did not
declare them. A host reboot deleted all four at once (2026-08-19: ~47 minutes
with no merge cadence on any rig, and invisible to `gc doctor` by construction,
since a post-hoc probe cannot distinguish "never went down" from "went down and
came back").

The passes are mechanical shell — metadata and timer comparison, GitHub API
status decoding, no LLM judgment — on a fixed interval. That is what an exec
order is for. Moving them there is version-controlled and reviewed, lives and
dies with the city, survives reboot, and is tunable from city.toml. It also
retires an entire apparatus that existed only to keep a daemon alive: the arming
script, its doctor check, and the catalogue of liveness signals that read green
on a dead driver. That history is kept, as history, in
`specs/tk-agzpl/refinery-idle-driver-liveness.md`; the decision and the
controller evidence behind it are in `specs/tk-d83wm/exec-order-cadence.md`.

**Do not re-create an out-of-band driver.** A copy launched by hand is a second
`merge-skill.sh` writer that the controller's gate cannot see — the one thing
the old canonical lock was there to stop, reintroduced past the mechanism that
now enforces it.
