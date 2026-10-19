---
name: Gas City and human engagement (platform facts)
description: What Gas City offers for engaging a person, and how a session and its pane end, where upstream's docs leave it unsaid — human gates and the core orders that surface them, where a question surfaces, the gc-roles worker contract, the idle ladder, max age, manual sessions, the stop, the no-wake-reason drain and the backstops — each cited and dated. gc-toolkit's own model on these is human-engagement.md.
---

# Gas City and human engagement

This page states Gas City behavior only: the primitives a human
conversation can ride, and how a session and its pane end, where upstream's
docs do not already say it. Each section names its evidence and the date it
was read, and says where the city's gascity fork differs from upstream main.
gc-toolkit's own model on top of these — subjects, visits, converse
sittings, demands and the helm board — is
[human-engagement.md](human-engagement.md).

## Scope

**Mandate.** Gas City's primitives for engaging a person, and how a session
and its pane end, as far as upstream's docs do not state them: what each
does, and when it was read.

**Boundaries.** gc-toolkit's model on top of them is
[human-engagement.md](human-engagement.md). Routing and the claim predicate
are [gascity-routing-model.md](gascity-routing-model.md); agent variants and
session identity are [gascity-agents.md](gascity-agents.md). Upstream's
reference material is indexed by [gascity-reference.md](gascity-reference.md).
Facts here are dated; an undated claim is a bug.

## What upstream's docs already say

Read these first; this page does not restate them. Coverage checked
2026-10-19 against `gastownhall/gascity` at `1e05ae624`, and bd 1.3.1's docs.

- **Continuation groups at the claim**: the hook atomically claims one ready
  bead and preassigns its continuation siblings, held siblings excepted —
  [tutorial 06](https://docs.gascity.com/tutorials/06-beads), "How agents find
  work", and the
  [agent pools design](https://github.com/gastownhall/gascity/blob/main/engdocs/design/agent-pools.md),
  "Graph workflow continuity".
- **Blocking dependencies** hide blocked work from work queries — tutorial 06,
  and bd's `docs/core-concepts/dependencies.md`.
- **Human gates as bd commands** — `bd gate create`, `bd gate list`,
  `bd gate resolve --reason`, and a gated issue staying out of `bd ready`
  until the gate resolves — bd's `docs/cli-reference/gate.md`.
- **External messaging (`extmsg`)**: provider-neutral adapters registered per
  city, bindings to a session or a configured agent, `gc extmsg bind`,
  `handoff` and `unbind`, and the first turn of a conversation binding it —
  [connected clients](https://docs.gascity.com/guides/connected-clients) and
  the [CLI reference](https://docs.gascity.com/reference/cli), `gc extmsg`.
- **Pending interactions**: `GET /v0/city/{cityName}/pending` lists them and
  `POST /v0/city/{cityName}/session/{id}/respond` answers one —
  [API reference](https://docs.gascity.com/reference/api), "Pending
  Interactions".
- **Session config**: an empty `idle_timeout` disables idle checks;
  `assigned_work_defer_limit` caps the idle ladder's assigned-work defers;
  `max_session_age` is off when empty and idle-gated on a pending interaction
  or in-progress assigned work; `wake_mode = "resume"` reuses the provider's
  session key; `[daemon] wisp_ttl` purges closed wisps —
  [config reference](https://docs.gascity.com/reference/config), `Agent` and
  `DaemonConfig`.
- **`gc hook`'s flags** — `--claim`, `--drain-ack`, `--inject`, `--json`; no
  continuation-group filter — CLI reference, `gc hook`.
- **A `[[service]]` process is reverse-proxied under `/svc/{name}`** — config
  reference, `ServiceProcessConfig`, and the
  [pack spec](https://docs.gascity.com/reference/specs/pack-spec), §1.2.6.

## Human gates and the orders that surface them

A `type=human` gate is a bead with `await_type=human`. The core pack ships two
orders that surface open human gates, both looking only at open
`await_type=human` gates:

- `notify-on-human-gate-creation` fires on the `bead.created` event, with no
  cooldown, and notifies each gate once.
- `renudge-stale-human-gates` runs every 5 minutes, reminds a gate first once
  it has been open an hour (`GC_STALE_GATE_THRESHOLD`), then at most once an
  hour (`GC_STALE_GATE_RENUDGE_INTERVAL`).

Both resolve the recipient as the gate's assignee, then
`gc.deferred_assignee`, then `${GC_ESCALATION_RECIPIENT:-human}`, and send
`gc mail send --notify`: mail plus a nudge, the nudge skipped for `human`.

Nothing resolves a human gate but a person. The core gate sweep runs
`gc bd gate check` for `timer` and `gh` gates only, and bd's own gate
evaluation has no `human` case.

`gc.routed_to=human` has no core meaning: nothing claims or routes a bead
routed there, and the core nudge-on-route order simply fails to nudge a
target named `human`. The routed tier of the default work query excludes beads
*labeled* `human`, which is a different thing from that route. (The fork's
session-model doctor check exempts `gc.routed_to=human` from its stale-route
finding.)

*Evidence:* the core pack's `orders/notify-on-human-gate-creation.toml`,
`orders/renudge-stale-human-gates.toml` and their scripts,
`assets/scripts/gate-sweep.sh`, `assets/scripts/nudge-on-route.sh`;
`PoolDemandServeRulesForQuery` (`internal/config/workquery.go`); bd 1.3.1's
`evaluateGates` (`cmd/bd/gate.go`); read at upstream `1e05ae624` and the fork
`a319c2fd6` on 2026-10-19.

## Where a question surfaces

Gas City surfaces "a human is needed" at two tiers with different maturity:

- **A question inside a live session becomes a pending interaction.** The
  tmux runtime detects Claude Code's permission dialog in the pane, the API
  lists it per session and city-wide, and the dashboard ranks it: an
  attention queue with closed alert kinds (`pending-decision`,
  `run-needs-operator`, `run-thrashing`, `operator-mail`) and a "Needs you"
  section in the agents view, with a reason and a mapped action per row.
- **A human gate has no surface identity of its own.** No supervisor API
  object carries `await_type`, so no dashboard or API object represents a
  gate. A run blocked on a gate shows as "Blocked, awaiting operator", and the
  gate's mail surfaces as an `operator-mail` alert.

*Evidence:* `Tmux.Pending` (`internal/runtime/tmux/interaction.go`),
`humaHandleCityPending` and `humaHandleSessionRespond` (`internal/api`), the
dashboard's `web/shared/src/alert.ts`, `attention/agentNeedsYou.ts` and
`runs/blocked.ts`, and no `AwaitType` in the API or its OpenAPI schema; read at
upstream `1e05ae624` and the fork on 2026-10-19. The dashboard's ranking is in
no upstream doc.

## The `gc-roles` worker contract

The `gc-roles` pack in the gascity-packs registry ships a shared
`gc-role-worker` contract fragment. At the version both gascity refs pin in
`go.mod` (`33d3a430`), after a worker closes a claimed bead that had a
continuation group it continues only for work in that same continuation
group or with the same `gc.root_bead_id`, and otherwise drains. The roles
pack is absent from upstream's published docs.

*Evidence:* `gascity/roles/template-fragments/gc-role-worker.template.md` in
the gascity-packs module at `v0.3.1-0.20260617013242-33d3a430a67d`, read on
2026-10-19.

## A parent cannot be blocked by its own descendant

bd refuses a `blocks` (or `conditional-blocks`) edge from a bead onto its own
descendant, and onto its own ancestor:

```
Error: <parent> cannot be blocked by its descendant <descendant>:
blocked status cascades to descendants, so <descendant> would inherit
the block and never close
```

*Evidence:* `CheckBlockingHierarchyInTx` (`internal/storage/issueops/dependencies.go`)
and `DependencyHierarchyConflictError` (`internal/storage/issueops/errors.go`)
in bd 1.3.1, read on 2026-10-19. bd's docs name the error only in a design
note.

## `gc.session_affinity` gates the continuation backstop

`gc.session_affinity = "require"` is a necessary condition of the
controller's stalled-continuation backstop, which nudges a stalled graph.v2
continuation step back to the session already holding it; anything else
clears the pending nudge. Graph routing sets it only when a formula declares
a continuation group. The keys cleared together with it are
`gc.session_affinity`, `gc.continuation_group`, `gc.stranded`,
`gc.stranded_session` and `gc.stranded_assignee`
(`beadmeta.SessionAffinityMetadataKeys`), so clearing or rewriting the
affinity on a live step on its own silently disables the path that recovers
it. The keys' own doc comment still says nothing reads the affinity.

*Evidence:* `continuationRowCouldBeCandidate` (`cmd/gc/build_desired_state.go`),
the continuation backstop's revalidation (`cmd/gc/idle_nudge.go`),
`internal/graphroute/graphroute.go`, `internal/dispatch/drain.go`; read at
upstream `1e05ae624` and the fork on 2026-10-19.

## How a session ends

### The idle ladder

An agent whose `idle_timeout` is at or below zero is never registered with
the idle tracker, so its idle check answers false and the idle ladder never
runs for it. Named sessions with `mode = "always"` are exempt as well.

"Idle" means the terminal produced no output. For tmux the activity is the
latest `#{window_activity}`, minus the echo of gc's own `send-keys`; for
Claude on a non-ACP transport a content-based idle check can also fire. A
person reading a pane produces neither, so activity cannot tell attention
from abandonment.

When the idle timeout fires, `DecideIdleTimeout` walks its rungs in order.
Upstream's are: an active blocker, a pending interaction, assigned work, the
`min_active_sessions` floor, then stop. The city's fork adds an attachment
rung after the pending interaction: an attached terminal (`IsAttached`)
defers the stop, re-evaluated every tick, so a forgotten attached pane is not
immortal and a detached reader is still collected. Upstream's default
reconciler has no such rung; only the opt-in v2 reconciler's stop fence
checks attachment.

The assigned-work defer is capped: `assigned_work_defer_limit` (default 3)
consecutive defers on the same anchor bead, after which the next tick stops
the session with reason `assigned_work_exhausted`. At a 30-second patrol that
buys about 90 seconds.

After an idle-timeout or max-age kill the reconciler clears the pane's
scrollback (`ClearScrollback`), best-effort, after the kill; a drain-ack, a
close and other stops do not.

`[daemon] wisp_ttl` is unrelated to any of this: it purges closed wisp
records, never a session.

*Evidence:* `buildIdleTracker` (`cmd/gc/cmd_start.go`), `checkIdle`
(`cmd/gc/idle_tracker.go`), `rawSessionActivity` and `discountedActivity`
(`internal/runtime/tmux/tmux.go`), `DecideIdleTimeout`
(`internal/session/lifecycle_timers.go`), `defaultAssignedWorkDeferLimit`
(`cmd/gc/assigned_work_defer_tracker.go`), the stop path in
`cmd/gc/session_reconciler.go` and `cmd/gc/reconcile_effect_stop.go`,
`WispTTL` (`internal/config/config.go`) and `cmd/gc/wisp_gc.go`; read at
upstream `1e05ae624` and the fork on 2026-10-19.

### `max_session_age`

Only an agent with a positive `max_session_age` is registered with the
max-age tracker. `DecideMaxSessionAge` walks blocker, pending interaction and
assigned work, then stops; it has no attachment rung on either ref. So a
session whose only defer is its assigned work restarts on the first tick
after that work closes, whoever is attached.

*Evidence:* `buildMaxSessionAgeTracker` (`cmd/gc/cmd_start.go`) and
`DecideMaxSessionAge` (`internal/session/lifecycle_timers.go`), read at
upstream `1e05ae624` and the fork on 2026-10-19.

### A manual session stays up until it is closed

A session started with `gc session new` is manual. The awake set keeps a
manual session desired, under the reason `manual`, for as long as it is
neither closed nor drained and its template is still configured, so the
`no-wake-reason` drain never begins for one. `gc session new` checks no
session count, and the pool's scale-down drop paths skip manual sessions, so
`max_active_sessions` does not cap them. A manual session can still be
idle-slept by a `[chat_sessions]` idle timeout once its grace period ends, and
a hold or quarantine overrides it.

*Evidence:* `ComputeAwakeSet` (`cmd/gc/compute_awake_set.go`), `cmdSessionNew`
(`cmd/gc/cmd_session.go`), the drop paths in `cmd/gc/build_desired_state.go`;
read at upstream `1e05ae624` and the fork on 2026-10-19. Upstream's session
model says manual sessions may soft-exceed the cap.

### Stopping a session destroys its pane

`gc session close` stops the runtime before it marks the session closed. For
tmux, the stop runs `tmux kill-session` first and then sends SIGTERM, a
two-second grace and SIGKILL to the captured process tree as a fallback;
signals come first only for a close issued from inside the pane. Nothing is
typed into the pane: the interrupt that would send a `C-c` is not on this
path, and the reconciler's drain-ack stop says so in its own comment — it
"calls sp.Stop() for a clean SIGTERM/SIGKILL — no Ctrl-C keystroke injection
into the pane". So the pane and its scrollback go in one step, with whatever
is in its composer. City shutdown is a different path, which upstream's
controller doc says interrupts every session first.

Nothing on the stop or close path refuses a teardown because the pane holds
unsubmitted input. Buffered-input detection (`InputAreaState`) exists only on
a fork integration branch, behind `gc session input-area`.

*Evidence:* `Manager.CloseDetailed` (`internal/session/manager.go`),
`Provider.Stop` (`internal/runtime/tmux/adapter.go`),
`KillSessionWithProcessesExcluding` and `teardownSessionProcessPlan`
(`internal/runtime/tmux/tmux.go`), the drain-ack comment in
`cmd/gc/session_wake.go`; read at upstream `1e05ae624` and the fork on
2026-10-19.

### A pool session with no wake reason is drained

A live session with no wake reason left, and no live claim to veto it, is
drained with reason `no-wake-reason`. After one full tick the reconciler
acknowledges the drain on the agent's behalf — it sets
`GC_DRAIN_ACK_SOURCE=reconciler`, `GC_DRAIN_REASON`, `GC_DRAIN_GENERATION`
and `GC_DRAIN_ACK=1` — and the next tick stops the session with the event
message "drain acknowledged by agent", whether or not the agent ever ran
`gc runtime drain-ack`. Measured on this city on 2026-08-20, the stop came
about 58 seconds after the last wake reason went. A manual session keeps its
`manual` wake reason, so this drain does not reach one.

*Evidence:* the drain in `cmd/gc/session_reconciler.go` and
`setReconcilerDrainAckMetadata` (`cmd/gc/session_wake.go`), read at upstream
`1e05ae624` and the fork on 2026-10-19.

### The controller's backstops govern pool sessions only

The controller's three backstops — the pool-claim nudge, the continuation
nudge and the execution backstop — each govern only a session whose
`pool_managed` is `"true"`; a named or manual session gets none of them. For a
pool session with an empty `nudge` field they split: the pool-claim backstop
sends a default claim nudge and, once its attempts run out, drains the slot if
it is quiet and the trigger is still unclaimed; the continuation backstop's
last step is a no-op; and the execution backstop requests a tracked drain on
an unstarted claim and sends a default nudge on a started one.

Upstream also has `[daemon] work_ladder` (default on), which only the opt-in
v2 reconciler reads: there it replaces the three backstops with a per-seat
ladder over open pool seats. The default reconciler ignores it and runs the
three backstops, and the city's fork has no `work_ladder` at all.

*Evidence:* `governs()` in `cmd/gc/idle_nudge.go` and
`cmd/gc/execution_backstop.go`, `runNudgeBackstop`
(`cmd/gc/nudge_backstop.go`), `workLadder` (`cmd/gc/reconcile_steps_nudges.go`)
and `cmd/gc/work_ladder_lane.go` (upstream only); read at upstream
`1e05ae624` and the fork on 2026-10-19.

## Refresh procedure

Each section's evidence line names what it was read from and when. Before
building on a section, re-read its symbols at current upstream main and in
this city's fork, and update the date with the reading; a fork-only behavior
is re-checked against upstream too. When upstream's docs come to state a
section's fact, replace the section with a line in "What upstream's docs
already say".
