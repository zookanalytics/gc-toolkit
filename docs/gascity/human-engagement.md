---
name: Gas City and human engagement (platform facts)
description: What Gas City offers for engaging a person, and how a session and its pane end, where upstream's docs leave it unsaid — human gates and the core orders that surface them, the primitives a conversation rides, where a question surfaces, the gc-roles worker contract, the idle ladder, max age, manual sessions, the stop, the no-wake-reason drain and the backstops — each cited and dated. gc-toolkit's own model on these is human-engagement.md.
---

# Gas City and human engagement

This page states Gas City behavior only: the primitives a human
conversation can ride, and how a session and its pane end, where upstream's
docs do not already say it. Each section names its evidence and the date it
was read, and says where the city's gascity fork differs from upstream main.
gc-toolkit's own model on top of these — subjects, human gates,
conversations and the converse sittings that hold them, and the helm board —
is [human-engagement.md](../human-engagement.md).

## Scope

**Mandate.** Gas City's primitives for engaging a person, and how a session
and its pane end, as far as upstream's docs do not state them: what each
does, and when it was read.

**Boundaries.** gc-toolkit's model on top of them is
[human-engagement.md](../human-engagement.md). Routing and the claim predicate
are [gascity/routing-model.md](routing-model.md); agent variants and
session identity are [gascity/agent-types.md](agent-types.md). Upstream's
reference material is indexed by [gascity/README.md](README.md).
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

`bd gate create --type=human --blocks <bead>` adds one `blocks` dependency
from the bead it names onto the gate, so that bead leaves `bd ready` until the
gate closes, and it takes no assignee or metadata at create. Another bead that
adds its own `blocks` edge onto the gate waits on it the same way.
`bd gate resolve <gate> --reason` closes the gate with that close reason,
skipping the close checks, so anyone may clear it. On a gate already closed it
changes nothing, keeps the first reason, and still reports success with exit
0, so a resolver learns it lost a race only by reading the gate back. It
refuses a bead whose type is not `gate`. `bd ready` excludes gates, and a plain
`bd list` hides them unless `--include-gates` or `--type gate` is given.
`bd dep list <bead> --type blocks --json` lists what the bead waits on,
closed blockers included, and each row carries the far bead's `issue_type`,
`status`, `await_type`, `await_id`, `assignee`, `title` and `close_reason`; with
`--direction=up` from a gate it lists the beads that wait on it.

*Evidence:* bd 1.3.1 `cmd/bd/gate.go` (create 340-437, resolve 559-574),
`internal/storage/issueops/close.go` 339-384, `cmd/bd/dep.go` 917-1052,
`internal/storage/sqlbuild/ready.go` 16-22 and `internal/workapi/list.go`
433-434; a live `gc bd dep list --type blocks --json` on 2026-10-22, whose row
for a closed human gate carried its `close_reason`.

## What a conversation rides

A conversation is an ordinary task, and every fact it rests on is a bd or Gas
City behavior that predates it.

- **Its two edges hold nothing.** `bd create --deps "tracks:<bead>"` makes the
  new task track the bead, and `tracks` never blocks, cascades nothing and is
  outside the cycle check. `bd dep add <task> <gate> --type replies-to` is bd's
  link for conversation threading, from the reply onto the original. It
  affects no ready work and no close, and bd stores it with the reply, so an
  edge onto a gate in another store keeps the gate's id. The task's own
  `bd list --id <task> --json` row carries each edge's `type` and
  `depends_on_id` whichever store holds the far bead, while `bd dep list` of
  one bead leaves an edge whose far bead is in another store out of its JSON
  and names it only on stderr. Nothing in Gas City outside its tests reads or
  writes `replies-to`.
- **The hook claim finds a task assigned to the session.** The default work
  query's first tier finds the session's in-progress work, its second
  (`bd ready --assignee`) its open assigned work, and its third offers routed
  work, which is closed to a manual session whose alias is not its template's
  name. `gc hook --claim` claims under the session's alias, which is also the
  session's bd actor, and returns work it already holds in progress. The
  assigned tiers read `bd list` and `bd ready`, which leave gates out. The
  claim itself (`bd update --claim`) is a compare-and-swap that sets
  `in_progress`, the assignee and a lease, is idempotent for its holder, and
  refuses a bead another actor holds.
- **A guarded update moves a task between holders.**
  `bd update --if-assignee <holder>` applies only while the assignee still
  reads `<holder>`, checked inside the update's transaction, and a mismatch
  writes nothing and exits 13. An update that changes the holder, or moves the
  bead out of `in_progress`, drops the claim's lease.
  `gc bd release-if-current <id> <holder>` leaves the bead open and assigned to
  nobody.
- **An alias is a reservation.** `gc session new --alias <a>` reserves the
  alias under a city-wide lock, and refuses it while another session that is
  not closed holds it as its alias, its session name or its identity. A closed
  session does not reserve its alias, and a new session under it starts a fresh
  transcript and takes the in-progress work still assigned to the alias.
  `gc session close` releases no claim held under the alias, and
  `gc session list` leaves a closed session out whatever state it is asked for.
- **A task in a person's queue starts nothing.** Assigned work wakes only the
  session whose identity it carries, and an unassigned, unrouted bead wakes
  nothing, so a task assigned to `human`, which no session carries, starts no
  session. Core's orphan-sweep counts a bead `gc hook --claim` claimed in a
  manual session as unverifiable and leaves it, and an agent's default
  on_death runs for pool instances only.

*Evidence:* bd 1.3.1 `internal/types/types.go` 1259-1395,
`internal/storage/issueops/dependency_queries.go` 63-136 and 906-937,
`cmd/bd/create_deps.go` 145-153, `cmd/bd/dep.go` 370-411 and 1032-1046,
`internal/storage/issueops/claim.go` 91-352,
`internal/storage/issueops/update_cas.go` 34-59 and
`internal/storage/issueops/aggregate.go` 160-174; Gas City
`internal/config/workquery.go` 528-613 and 780-793, `cmd/gc/cmd_hook_claim.go`
502-512 and 797-910, `cmd/gc/cmd_session.go` 336-351 and 465-480,
`internal/session/names.go` 288-327 and 630-702,
`cmd/gc/build_desired_state.go` 1938-1950, `cmd/gc/assigned_work_scope.go`
382-431, `internal/beads/bdstore_conditional_release.go` 78-110 and core's
`orphan-sweep.sh`; read at upstream `1e05ae624` on 2026-10-20 and 2026-10-22
(specs/tk-0ur8r9p/design.md, "The platform this rides", records each line).

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
defers the stop on every tick it stays attached, and so does an attachment
probe that cannot tell. The defer has no cap, so an attached pane is never
idle-stopped; the ladder reaches its later rungs only once the terminal
detaches. Upstream's default reconciler has no such rung; only the opt-in v2
reconciler's stop fence checks attachment.

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
(`internal/session/lifecycle_timers.go`), `attachmentHolds`
(`cmd/gc/worker_handle.go`), `defaultAssignedWorkDeferLimit`
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

A session whose `session_origin` is `manual` stays desired: the awake set
keeps it, under the reason `manual`, for as long as it is neither closed nor
drained and its template is still configured, so the `no-wake-reason` drain
never begins for one. `gc session new` creates a manual session, with one
exception: for an unbound named session's own name without `--alias`, it
creates the canonical session, whose origin is `named`
([gascity/agent-types.md](agent-types.md#gc-session-new-and-the-canonical-session)).
That session gets no manual keepalive; the named-session arms decide whether
it stays desired. `gc session new` checks no session count, and the pool's
scale-down drop paths skip manual sessions, so `max_active_sessions` does not
cap them. A manual session can still be
idle-slept by a `[chat_sessions]` idle timeout once its grace period ends, and
a hold or quarantine overrides it.

*Evidence:* `ComputeAwakeSet` (`cmd/gc/compute_awake_set.go`),
`isManualSessionInfo` (`cmd/gc/session_sleep.go`), `cmdSessionNew` and
`sessionOriginForConfiguredNamed` (`cmd/gc/cmd_session.go`), the drop paths in
`cmd/gc/build_desired_state.go`;
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
