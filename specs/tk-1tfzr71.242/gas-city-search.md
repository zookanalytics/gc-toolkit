---
name: Gas City search for the refinery's one item per session
description: The Gas City primitives read to run the refinery one item per session with no standing patrol wisp, covering what starts an on-demand named session, what ends it, how its claim is recorded and spared, where its work query runs, and the demand its search must match, each at a named upstream commit with the city's measurements. Read it when changing the refinery's lifecycle or its search, or how an on-demand named session finds its work, or when the arch check asks for the search.
---

# Gas City search for the refinery's one item per session

Read on 2026-11-25 at `gastownhall/gascity` main 33a7d167c8. The city runs build
13cdf670ca, a fork of upstream c377651cb3, and every symbol cited here reads the
same there except where a line says the build differs. Gas Town is read at
`gastownhall/gascity-packs` 44b9db7168. The measurements were taken in this city
on 2026-11-25.

## The need

A refinery session should start only when an item assigned to the refinery
waits, take that one item to its end and stop, so that no session starts with
nothing to do. Three answers must agree for that: what Gas City counts as the
refinery's demand, the one item a session takes, and the item Gas City records
as the session's work. Any bead Gas City counts as demand that the session does
not take starts a session that finds nothing, and the session's drain brings
the next one straight back for the same bead.

## The standing wisp

The refinery kept one patrol wisp assigned to itself and poured the next at the
end of each pass, as Gas Town's does. The change removes that lifecycle state:
the wisp's pour, its adoption at startup and its burn.

- **What Gas City does with it.** Gas City counts every open molecule root
  assigned to a session, ephemeral, no-history or `gc.kind=workflow` and not
  deferred, as that session's wake demand (`appendOpenAssignedMoleculeWorkUnique`
  and `isOpenAssignedMoleculeWork`, cmd/gc/build_desired_state.go). The reason
  Gas City gives is in the comment there: such a root is "the executable turn
  for on-demand named sessions such as the Gas Town refinery patrol". While a
  session holds such a root or a bead in progress, the pass skips the ready read
  for every identity of that session (`readyCapturedAssigneeSet`, the same
  file), so the refinery's other assigned beads neither woke it nor became its
  recorded work. The idle stop is a stop the next pass undoes while the row is
  still wanted (`armIdleTimeout`, cmd/gc/reconcile_arms_idle.go), and the wisp
  was that want.
- **What it cost here.** A census of the window 2026-11-18T11:37Z to
  2026-11-25T16:35Z, across the city's six rigs, read each refinery session's
  start and end from the city's event log and the writes on its session bead,
  and what it did from its transcript, by the step scripts it ran and their exit
  codes. It found 104 refinery sessions started. Every one was a restart: a
  fresh cycle, a cycle-recycle reset, an idle stop re-woken in the same second,
  a supervisor restart or a kill. None was a wake for waiting work, and 44 did
  nothing: 2 of 30 in gc-toolkit and 42 of 74 in the five other rigs. Each empty
  start cost about 260K processed tokens, about 43K of them new. The scripts and
  the full method are on the host at `/Users/gc/.cache/tk-j3x4yo5/` (census.md
  section 8, and census-rigs.md).
- **Why no fix at the source is owed.** The demand rule is no fault. It is how
  Gas City supports a pack that keeps a standing wisp, and its reason holds for
  such a pack. This pack keeps none. The wisp carried no merge state either:
  every refinery script reads the formula, never the wisp, and the
  patrol-summary step's record was never written.
- **The wisps the change finds.** Read at 2026-11-25T21:47Z with
  `gc bd --rig <rig> list --type=molecule --include-infra --status=open,in_progress`
  in each rig: every one of the six refineries held one patrol wisp, two open
  and four in progress. An open one stays demand once nothing adopts or burns
  it, and `gc runtime drain-ack` releases only work in progress
  (`releaseDrainAckClaims`, cmd/gc/session_beads.go), so each session it
  started would find nothing, drain, and be started again. The search closes
  a `mol-refinery-patrol` wisp assigned to the refinery, guarded on the status
  and assignee it read, and takes nothing from it. Nothing pours one now, so
  the clause goes once no store holds one open.

## What was searched

### Starting a session for an item that waits

- **Named and assigned demand.** `computeNamedSessionDemandOn`
  (cmd/gc/build_desired_state.go) marks an on-demand named session as wanted for
  a bead assigned to its qualified identity or its runtime name that is in
  progress, blocked or not, or open and ready, and reads a route as no named
  demand. `workBeadHasAwakeDemand` (cmd/gc/compute_awake_set.go) wakes a row for
  a bead assigned to it that is in progress and not blocked, or open and ready.
  Ready is `bd ready`, whose blocker verdict is bd's own. This covers the need:
  a hand-off's assignment of a ready bead starts a session. The change composes
  it and adds nothing to it.
- **An explicit wake.** `gc session wake` (`doSessionWake`,
  cmd/gc/cmd_session_wake.go) records a wake that starts a stopped session at
  the next pass, whatever the demand. A wake that finds the session running is
  satisfied by that run, and the pass clears it (`armSatisfiedWake`,
  cmd/gc/reconcile_arms_heals.go). The hand-offs and the landing order keep
  their wake and nudge as they are. The landing order's wake is the start for a
  PR's bead held only by a conversation or an ask on its PR, which bd does not
  read ready and the search takes.
- **What that leaves.** A bead held only by a conversation or an ask is no
  demand, so a session takes it only when a wake starts one for it. When the
  landing order hands one over while a session works another item, the wake is
  spent on that session, which takes only its own item. When a gate on one
  closes while its conversation still holds it, core's cascade nudge stays
  silent (`still_held`, in the core pack's
  assets/scripts/cascade-nudge-on-blocker-close.sh) and nothing wakes the
  refinery. Either way the bead is taken once its hold closes and bd reads it
  ready, or at the next start for another item, so the new head's checks run
  then rather than beside the hold. Its merge waits on the hold either way.
  Measured in the city's event log from 2026-11-18T19:05Z to 2026-11-25T21:43Z,
  by the queued nudges to a refinery whose text names a merge hold: one such
  hand-over in the six rigs.

### Ending a session

- **`gc runtime drain-ack`** (`runtimeDrainAck`, cmd/gc/cmd_runtime_drain.go)
  refuses the seat's own ack while a bead its claim record names is still in
  progress, with "continue it". It reopens, unassigned, every other bead in
  progress under the seat (`releaseDrainAckClaims`, cmd/gc/session_beads.go), and
  `armAck` (cmd/gc/reconcile_arms_drain.go) stops the session at once. The
  finalize leaves the row drained when nothing is assigned to it, and asleep when
  something is, so a ready bead starts the next session. The build differs here:
  upstream keeps a bead in progress under the configured named identity
  (`keepsNamedIdentity`, cmd/gc/work_release.go), and the build releases it.
- **Composed.** The end-session step puts a claim still in progress back to
  open under the refinery, guarded on the claim, then runs drain-ack. The search
  puts back to open every claim it leaves, so the release never meets a bead of
  the refinery's in either build.
- **`sleep_after_idle`**, Gas City's sleep-on-idle, is not used. A refinery
  session ends itself at drain-ack, so `idle_timeout` stays as a backstop that
  stops a session which stopped answering.

### Recording the item: the claim and the fresh cycle

- **The claim.** `gc hook --claim` runs the agent's `work_query` when one is set.
  `EffectiveWorkQuery` (internal/config/workquery.go) returns a custom query
  unchanged, and `hookWorkQuery` (cmd/gc/cmd_hook.go) expands its template. The
  claim adopts a row in progress assigned to one of the session's identities
  (`hookClaimExistingAssignment`, cmd/gc/cmd_hook_claim.go), or else claims the
  first open row assigned to one (`claimFirstReadyHookAssignment`), and records
  the claim on the session row, in its started work and its
  `current_claim_bead_id` (`stampHookSessionCurrentClaim`).
- **The claim's identity.** `hookClaimAssigneeIdentity` (cmd/gc/cmd_hook.go)
  records a named session's claim under its alias. Measured on 2026-11-25 with
  `tmux show-environment` on the live gc-toolkit refinery: `GC_ALIAS`,
  `GC_AGENT` and `BEADS_ACTOR` each read `gc-toolkit/gc-toolkit.refinery`, the
  assignee every hand-off writes and every refinery script reads.
- **The fresh cycle.** `freshCycle` (cmd/gc/reconcile_arms_fresh_cycle.go)
  restarts a fresh-mode session whose anchor moved off the bead it records, and
  spares a row whose `current_claim_bead_id` equals the new anchor.
  `freshCycleDefers` (cmd/gc/reconcile_effect_fresh_cycle.go) defers the restart
  while the recorded bead is open. The anchor moving with each new wisp is how
  the fresh cycle cut refinery passes short.
- **Composed.** The find-work step is `gc hook --claim --json`, with the
  refinery's search as its work query. The item a session works is the one it
  claims, which Gas City records and the fresh cycle spares.

### The search's row and the hook's filter

The search accommodates the hook's filter, so this is its record.

- **The behavior.** `filterUnreadyHookCandidates` (cmd/gc/cmd_hook.go) strips a
  row whose `blocked_by` names an open dependency, and a row marked blocked,
  deferred or on a dispatch hold.
- **Gas City's reason**, from its comment: "The work_query is expected to gate
  these, but defensive filtering here prevents a single broken query from
  cascading into agent action on a bead it cannot progress."
- **Why the search's row carries no `blocked_by`.** The pack holds a PR's merge
  with a conversation or an ask on the PR, each through a `blocks` edge onto
  the PR's bead, and the refinery still validates a head such a bead moves to
  ([the hand-over's search](../tk-1tfzr71.165/gas-city-search.md), and
  [the waiting PR's assignee](../tk-1tfzr71.209/gas-city-search.md)). The
  refinery can progress such a bead, and its merge stays held. So the work query
  gates readiness itself, as the comment expects, and the filter's reason does
  not apply to such a row.
- **Why no fix at the source is owed.** The filter is defensive, it reads only
  what a row carries, and it is right for every query that does not gate.
- **The rate here.** Measured at 2026-11-25T20:53Z with `gctk bead holds` over
  the 19 beads assigned to the six rigs' refineries. 17 were held by `blocks`
  edges onto gates or tasks: landing beads that wait on their efforts, beads
  behind human gates, and the one bring-current hand-off. 2 were clear, and none
  was held only by a conversation or an ask.

### Where the hook runs the work query

- **The behavior.** For a rig-scoped agent, `hookWorkQueryStores`
  (cmd/gc/hook_cross_store.go) runs the query against the rig's store, then the
  store of the agent's own environment, then the city store as a best-effort
  leg. `bestStoreWithWork` runs the command on each leg and serves the best
  candidate. `hookStoresScopeToPrimary` never collapses a custom query onto one
  leg, because a custom query reads one store whatever the topology.
- **What the search does.** It runs against the rig store more than once on
  each claim, and against the city store once. Its writes hold across the
  repeated runs: a second run reads a bead's new edge as a hold, and a reopened
  claim as open, so it writes nothing again.
- **The rate here.** Measured at 2026-11-25T20:51Z: in the city store, no open,
  in-progress or blocked bead is assigned or routed to any of the six
  refineries.

### Demand the search does not take

- **Routed demand.** A ready, unassigned bead routed to the refinery's template
  wakes it, because a cap of 1 makes the template a canonical singleton
  (`UsesCanonicalSingletonPoolIdentity`, internal/config/session_capacity.go;
  `defaultScaleCheckCountsAndDemand`, cmd/gc/build_desired_state.go). The search
  reads only the beads assigned to the refinery. Nothing in the pack routes work
  to the refinery: the route row of [authority-map.md](../../docs/authority-map.md)
  refuses a route to a named agent that takes the assignee. Measured at
  2026-11-25T20:51Z: no open, in-progress or blocked bead in any of the six rig
  stores or the city store is routed to a refinery.
- **A `waits-for` edge.** bd judges one by its spawner's children, and the
  search holds a bead with one as unjudged (`waits.Unjudged`), so bd could read
  such a bead ready while the search leaves it. No pack writer makes a
  `waits-for` edge. Measured at 2026-11-25T20:51Z: the wait edges on the 19
  assigned beads were `blocks` and `parent-child` only.
- **A dispatch hold.** Gas City counts no open bead on a dispatch hold as demand.
  The search reads no hold label, as find-work did not. Measured at
  2026-11-25T20:54Z: no bead assigned to a refinery carries any `hold:` label.

## Gas Town's refinery

At `gastownhall/gascity-packs` 44b9db7168, `gastown/agents/refinery/agent.toml`
sets `mode = "on_demand"` through the pack's `[[named_session]]`,
`wake_mode = "fresh"`, `idle_timeout = "2h"`, a cap of 1 and no `work_query`.
Its prompt and `gastown/formulas/mol-refinery-patrol.toml` keep one standing
patrol wisp assigned to the refinery, poured before the current one burns: "There
is no 'session done' state for a refinery patrol — only 'next wisp poured' or
'wedged'". With no work, the session ends its turn and stays idle until
`idle_timeout` stops it, and the wisp starts the next session. This pack's
refinery departs from that: it keeps no wisp and ends after one item, as
[built-once-target.md](../../docs/built-once-target.md#merge) states.

## What the change composes and adds

- **Composed:** assigned-work demand, the explicit wake, `gc hook --claim` with a
  custom `work_query`, the fresh cycle's spare of a claimed item, and
  `gc runtime drain-ack`.
- **Added:** `gctk refinery next`, the refinery's search as its work query. No
  Gas City query covers what it does. It takes a bead past a hold on its PR's
  merge alone. It makes a bead whose branch another open bead writes wait on
  that bead, by a `blocks` edge bd reads, so the bead is no demand until the
  writer closes. It puts a claim it leaves back to open, so the claim is no
  demand either, and it closes a patrol wisp left assigned to the refinery
  ([the wisps the change finds](#the-standing-wisp)).
- **The edge bd refuses.** bd refuses a `blocks` edge that closes a cycle
  (`AddDependency` with `HasCycle`, internal/storage/domain/dependency.go, at
  `steveyegge/beads` v1.3.4, the city's bd). A writer that waits on the bead it
  writes for is such a case, and an edge onto it would wait for a close that
  cannot come first. The search makes the bead wait on the live runs that work
  that writer instead, whose ends end its writing. A writer of that kind that
  only a session's claim works, with no run, leaves no bead whose close ends
  the writing, so the search defers the bead an hour (`--defer=+1h` on bd's
  update). bd leaves a deferred bead out of its ready set and returns it to
  open on its first ready read after the date (`bd defer --help`, the city's
  bd), and Gas City reads demand from open beads by their raw status and
  from bd's ready set (the raw-open pass and `Ready()` in
  cmd/gc/build_desired_state.go, at upstream 887a253144d4), so the bead is no
  demand until bd wakes it, and the session it then starts looks again. The
  witness defers its next wisp the same way
  ([patrol-continue.md](../../docs/patrol-continue.md)). Gas City's hook
  strips a row whose `blocked_by` names an open wait
  (`filterUnreadyHookCandidates`), so such a
  claim needs its wait added after it was taken.
- **Added key:** `work_query` in agents/refinery/agent.toml, Gas City's own
  agent key.
- **Removed:** the standing patrol wisp's lifecycle (its pour, adoption, burn
  and rotation), `refinery-find-work.sh`, and the patrol-summary and
  next-iteration steps. `refinery-patrol.sh next` becomes `end`, which keeps only
  the teardown of the trees a session left.
