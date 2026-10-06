---
name: Close the asleep pool session beads that hold a slot with no runtime and no work — tk-kwhll1p
description: Why a pool session killed out of band holds its pool slot forever, what the pack can see of it, and the pool-slot-reap order that closes such beads. The design record for the pool-slot-reap order.
---

# Close the asleep pool session beads that hold a slot with no runtime and no work

Bead: `tk-kwhll1p`. Deliverable: `orders/pool-slot-reap.toml` +
`assets/scripts/pool-slot-reap.sh` (+ its co-located test), the component-index
rows, and the pool-session paragraph in `docs/gascity-agents.md`'s kill-vs-close
section.

## The gap

Read in the gascity fork at `92344d46d`, the build the city runs.

- **Every open pool session bead holds its slot.** `claimFreshPoolSlotInfo`
  (`cmd/gc/build_desired_state.go`) marks a slot occupied for every open session
  bead in the census except a failed-create row. A canonical singleton pool
  refuses a fresh create while any open bead identifies as the canonical
  identity.
- **The controller frees a slot for a fixed list of sleep reasons.**
  `isPoolSessionSlotFreeableInfo` (`cmd/gc/session_state_helpers.go`) admits
  idle, idle-timeout, city-stop, failed-create, runtime-missing,
  provider-terminal-error and max-session-age, plus drained and an empty reason
  with `slept_at` stamped. The reconciler's close of a dead pool session
  (`cmd/gc/session_reconciler.go`, the `poolFreeable` gate) requires that
  predicate.
- **`gc session kill` writes a reason outside that list.** It stamps
  `state=asleep`, `sleep_reason=killed` (`cmd/gc/cmd_session.go`,
  `internal/session/kill_fence.go`).
- **Nothing picks an asleep pool bead with no work back up.**
  `reusablePoolSessionInfo` (`cmd/gc/build_desired_state_pool_info.go`) reuses
  an asleep bead only for a one_shot pool. The demand requests that name an
  existing bead (`cmd/gc/pool_desired_state.go`) cover a bead holding assigned
  work, an awake bead inside its post-create window, and a bead mid-create.

So a killed pool session with no work keeps its slot, with no runtime, until its
bead is closed. The planner logs `has no free concrete slot (slot stalled on its
own runtime name; retrying next tick)` every tick, and nothing else reports it.

Core also runs `sweepUndesiredPoolSessionBeads` (`cmd/gc/city_runtime.go`), which
closes an undesired, not-running, unassigned ephemeral pool bead with close
reason `session swept: no assigned work in any rig`. It did close one killed
bead and five config-drift beads in the store's retained history, but its
candidate filter and its fail-closed work guard both skip silently (the sweep
passes no stderr), and it left the two live cases below in place for hours and
days. From outside the controller the pack cannot tell which filter skipped
them.

## Live cases

- **`lx-wisp-25frc`**, gc-toolkit polecat slot 2. Killed at 2026-10-05T06:37:20Z
  in a batch of thirteen, holding no work. The pool (cap 4) ran at most 3 until a
  hand-run `gc session close` closed the bead at 14:14Z, with no close reason.
- **Three gc-toolkit polecat beads on `sleep_reason=config-drift`**,
  2026-10-04 18:30-20:59Z. The undesired sweep closed them at 20:56Z.
- **`lx-wisp-hwfu2`**, the gascity rig's polecat pool, a canonical singleton
  (cap 1). Asleep on `sleep_reason=idle` since 2026-10-03T01:24:12Z, with an
  explicit wake request from 2026-10-04T02:33Z that nothing served. No open or
  in_progress bead in any store is assigned to its id, session name or alias.
  The supervisor log carries more than 5,000 `canonical pool
  template "gascity/gc-toolkit.polecat" is held by session lx-wisp-hwfu2` lines,
  still printing on 2026-10-06. A dry run of the reaper against the live city
  names it as the one bead it would close. Its reason is on the freeable list, so a predicate
  keyed on the reason alone would not catch it.

## What the pack can see

Everything the predicate needs is readable without core changes:

- `gc session list --state all --json` enumerates the sessions; its `state` is
  the runtime overlay, so `asleep` is a superset of the beads to read.
- `gc bd show <id> --json` returns the session bead with the metadata the
  controller reads: `state`, `sleep_reason`, `slept_at`, `wake_requested_at`,
  `pool_managed`, `session_origin`, `pool_slot`, `configured_named_session`,
  `held_until`, `quarantined_until`, `wait_hold`, `pin_awake`, `alias`,
  `alias_history`, `session_name`, `template`.
- `gc bd list --db <rig>/.beads --assignee <who> --status open,in_progress
  --include-infra --include-ephemeral --limit 0 --json`, once per store and
  identity, answers whether any work is assigned. The store roster comes from
  `gc rig list --json`. An exec order runs with the city root as its working
  directory and `GC_CITY` set (`orderExecEnvWithError` in
  `cmd/gc/order_store.go`, the `execRun` call in `cmd/gc/order_dispatch.go`),
  so the roster read resolves the city.
- `gc config show --json --city <path>` gives each configured agent's
  `Namepool`, `NamepoolNames` and `MaxActiveSessions`, which tell an ordinary
  numbered pool from a namepool or a canonical singleton. It leaves out the
  import binding (`BindingName` is `json:"-"`), so the pass matches a template
  to agents by dir and name.

Runtime liveness is the one fact the pack cannot read directly: the overlay
only downgrades an awake row whose runtime is gone, and never says whether an
asleep row's runtime is up. The controller's state heal supplies it instead.
`healStatePatchWithRollbackInfo` (`cmd/gc/session_reconcile.go`) moves a row
whose runtime it sees alive back to awake, and the kill fence suspends that heal
only while the kill's own teardown runs, for at most `KillPendingGrace` (five
minutes). A bead that has stayed asleep for the whole grace window has had no
runtime the controller could see for that long.

## The predicate

`pool-slot-reap.sh` closes a bead with `gc session close` when all of these hold:

1. **Pool-managed, not named, not manual.** Core's own definitions:
   `session_origin=ephemeral`, `pool_managed=true` or a `pool_slot`; never
   `configured_named_session=true`, because a closed named bead keeps its alias
   reservation and blocks re-creation; never a manual session, which
   `converse-reap` owns.
2. **Persisted state asleep or drained.**
3. **No deliberate hold.** user-hold, wait-hold, quarantine, context-churn and
   rate_limit sleeps, a `held_until`, `quarantined_until` or `wait_hold` marker,
   and `pin_awake=true` all leave the bead alone. Core clears the timed ones
   itself, and a quarantine or rate limit is a throttle that a fresh session
   would only defeat.
4. **Past the grace window.** `slept_at`, and `wake_requested_at` when it is
   later, are older than `POOL_SLOT_REAP_GRACE_S` (900). Core frees a freeable
   bead on the tick its runtime goes, so the window gives core the first move,
   and a fresh `gc session wake` keeps a bead out of the pass.
5. **No work.** Nothing open or in_progress, in any store, under the bead's id,
   `session_name`, configured named identity, `alias` or any prior alias.
   Blocked work does not count, matching core's close gates: it is parked behind
   a hold a human or an edge releases. The numbered slot name (`agent_name`) is
   not searched. It passes to the slot's next holder, and core's guards never
   treat it as an owner. The same goes for the alias and prior aliases of a bead
   in an ordinary numbered pool, as the next section explains.
6. **Unchanged on a second read.** The work search takes seconds, so the bead is
   read again just before the close, and any change to its lifecycle facts keeps
   it.

The sleep reason is not part of the predicate beyond the holds in step 3. The
killed case motivated it, but `lx-wisp-hwfu2` shows a freeable reason can hold a
slot just as long. The grace window is what separates a bead core is about to
free from one it has left behind.

Each close is one `cleanup` entry in the incident ledger
(`gc-deacon-ledger.sh`, run from the roster's city path), naming the bead, its
slot, its sleep reason and when it fell asleep. A close the ledger could not
record exits 1 and names the bead on stderr, which the supervisor log keeps.

## Which aliases name the session

A pool member claims work under its alias when the alias is stable, and under
its session name otherwise. Core's close and drain guards decide which aliases
are stable in `stableAssignmentAliasForConfig` (`cmd/gc/session_beads.go`). An
alias counts unless the bead has a `pool_slot` and its configured agent rebinds
numbered slots or cannot be resolved. An agent rebinds numbered slots when it
has no namepool and a `max_active_sessions` other than 1
(`usesTransientPoolSlotIdentity`, `cmd/gc/build_desired_state.go`). A namepool
name (`rig/furiosa`) and a canonical singleton's name stay with the session, so
they count. A numbered slot (`rig/pack.polecat-2`) goes to the slot's next
holder, so it does not. `TestAssignmentGuardsIgnoreTransientPoolSlotAliases`
pins that rule for the older beads that still carry the slot as `alias`, with an
earlier slot in `alias_history`. Current pool beads of an ordinary numbered pool
carry no alias.

The reaper applies the same test. Where it reads more than core does, or cannot
be sure, it leans toward keeping the bead:

- It searches prior aliases (`alias_history`), which core's close and drain
  guards never do. The exception is a bead in an ordinary numbered pool: there
  it leaves out the alias and every prior alias, so it searches what core
  searches. The prior alias in core's regression fixture is an earlier slot.
- The template is matched to agents by dir and name, because the config read
  leaves out the binding. When two bindings give the same dir and name, every
  matching agent must rebind numbered slots before the aliases are left out.
- An alias the pass cannot place counts as an owner. That covers every alias
  when the config cannot be read, and the aliases of a template that matches no
  configured agent. Core drops the alias of an agent it cannot resolve. The
  pass keeps it, because the remedy's first constraint is never to close a
  session bead that holds assigned work, and keeping one costs at most the slot
  it holds.
- A config that `gc config show` reports invalid (`validation.ok` false) counts
  as unreadable. The controller's reload refuses a config that fails agent,
  service or webhook validation and keeps running the one it had
  (`cmd/gc/controller.go`), so the file on disk may not be the config in force.

Matching on the template, not on the alias's shape, is what keeps a namepool
member past the end of its name list safe. Its alias is `<template>-<slot>`,
the same shape as a numbered slot, and it is still the session's own name.

## Cost and cadence

The order runs every five minutes with a 300 s timeout. A pass with any asleep
row reads the rig roster and the agent config once, the config in under a
second. A bead that fails the cheap checks costs one `gc bd show`. An eligible
one costs one read per store and identity, plus the second read, the close and
the ledger write. Against the
live city that was about 25 s for `lx-wisp-hwfu2` across six stores and three
identities. Candidates left when `POOL_SLOT_REAP_BUDGET_S` (240) runs out are
deferred to the next pass. A killed ghost is therefore closed between 15 and
about 20 minutes after the kill.

## Residual risk

`gc session close` stops a runtime that is running. A `gc session attach` that
starts a ghost's runtime inside the same controller tick as the close, before
the heal marks the bead awake, would be stopped. The bead has been a ghost for
the whole grace window by then, and the pool spawns a fresh session for any
demand.

## Core alternative, not taken

The bead prefers a pack-side remedy to a core patch. The core change that closes
the killed case is adding `SleepReasonKilled` to both freeable predicates in
`cmd/gc/session_state_helpers.go`. It would not reach `lx-wisp-hwfu2`, whose
reason is already freeable.
