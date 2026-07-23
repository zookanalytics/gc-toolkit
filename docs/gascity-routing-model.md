---
name: Gas City routing model
description: How `gc sling`, direct assignee, and `gc sling --reassign` differ — which fields each lane is supposed to set, per the PR #1736 ruling, and the claim predicate that reads those fields back.
---

# Gas City routing model: sling vs assignee vs `--reassign`

## Scope

**Mandate.** How work is routed to agents: how a bead reaches the worker
that will act on it, and — the doc's distinctive charge — which routing
field each delivery path is responsible for setting. It is the authority
on that field-level contract. That contract has a **read side** — the
claim predicate that decides which beads a worker is offered — and it is
documented here too: the fields mean only what the predicate makes them
mean.

**Boundaries.** This doc covers *how* work moves between agents, not
*who* the agents are — that's [gascity-agents.md](gascity-agents.md). It
defines the routing contract; it is not a command tutorial.

## Provenance

| Doc-type or artifact | Producer | Source location | Surveyed at |
| --- | --- | --- | --- |
| PR #1736 closing comment (maintainer ruling) | julianknutsen | https://github.com/gastownhall/gascity/pull/1736#issuecomment-4504727391 | 2026-05-21 |
| PR #1841 — `--reassign` flag (merged 2026-05-12) | gastownhall/gascity | https://github.com/gastownhall/gascity/pull/1841 (merge commit `44fcee6af60277f87aaa063f72dafeff7f705966`) | 2026-05-21 |
| `TestDoSling_Reassign_NoOpWhenAlreadyEmpty` | gastown source | `rigs/gascity/internal/sling/sling_test.go:3809` (added in `043e61ea6cb99a9f89657e292c9459be8620714c`, observed at upstream/main `19a0bb201eb6d1723a10eecdae20371bd8ceeb17`) | 2026-05-21 |
| Upstream tutorial `docs/tutorials/06-beads.md` — **superseded by PR #1736 ruling, not yet updated** | gastownhall/gascity | https://github.com/gastownhall/gascity/blob/19a0bb201eb6d1723a10eecdae20371bd8ceeb17/docs/tutorials/06-beads.md (last touched in `eac98595e701008087f7ee6acecbf55d5dca7794`) | 2026-05-21 |
| Upstream CLI reference (`--reassign` row only) | gastownhall/gascity | `rigs/gascity/docs/reference/cli.md:2789` at upstream/main `19a0bb201eb6d1723a10eecdae20371bd8ceeb17` | 2026-05-21 |
| `CrossStoreRouteError` cross-store route guard | gascity source | `rigs/gascity/internal/sling/sling_core.go:607` (`validateBuiltInRouteStoreReachable`), gated by `shouldValidateBuiltInRouteStoreReachable` (`sling_core.go:210`) — note its predicate omits the `!opts.Force` bypass that `shouldGuardCrossRig` (`sling_core.go:202`) carries, so `--force` does not relax it; error text at `internal/sling/sling.go:686`. Verified current at gascity/main `434d57656` (the singleton assignee-stamping change, last commit to touch the guard). | 2026-06-19 |
| PR #2779 — `gc.routed_to` made the sole persisted routing key; `gc.run_target` demoted to compile-time-only (merged 2026-06-01) | gastownhall/gascity | https://github.com/gastownhall/gascity/pull/2779 (commit `fb32be6941be7627aaf169809e31629f0baf6118`); definition in `engdocs/design/session-model-unification.md` | 2026-06-19 |
| PR #3670 — `feat: add default_sling_targets for multi-target random dispatch` (merged 2026-07-03) | gastownhall/gascity | https://github.com/gastownhall/gascity/pull/3670; field at `rigs/gascity/internal/config/config.go:645`, resolver at `rigs/gascity/cmd/gc/cmd_sling.go:291`. Verified current at gascity/main `4ff645484`. | 2026-07-16 |
| Claim predicate — `gc hook` tiers, `bd ready` semantics, built-in pool query | running `gc` binary + live city | Read off the **running implementation**, not from prose: `gc hook --help` ("Finds routed work using the agent's `work_query` config"); `gc bd ready --help` ("open issues with no active blockers", "Excludes in_progress, blocked, deferred, and hooked issues", `GetReadyWork` semantics); the built-in queries embedded in the `gc` binary — the assignee tier loops `for id in "$GC_SESSION_ID" "$GC_SESSION_NAME" "$GC_ALIAS"` around `bd ready … --assignee=<candidate> --exclude-type=epic --json --limit=…`, and the routed tier is `bd ready --metadata-field "gc.routed_to=<target>" --unassigned --exclude-type=epic --json --sort oldest --limit=…` (offer) with the same filter at `--limit 0` counted (demand); Go-side helper symbols `UnassignedRoutedWork` / `UnassignedInProgressPoolWork`. The routed-tier shape is corroborated by this rig's own `proactive` agent, whose `work_query`/`scale_check` in the resolved city config (`gc config show`) are that same filter, adding only a `--db` pin and an enablement guard. `hold:<value>` convention observed as the live `gc doctor` checks `hold-label-routed-to` and `hold-label-conventions:<scope>`. Binary build `salvage/gc-c05nr-89e2e699f`. | 2026-07-23 |

## The maintainer's ruling

From julianknutsen's PR #1736 closing comment, verbatim — the lead
sentence:

> `assignee` and `gc.routed_to` are not duplicates, and the default
> sling path should not generally stamp both.

And, verbatim, the decision list at the end of the same comment:

> - Do not merge this PR.
> - Keep `gc sling` as queue/template routing: `gc.routed_to=<target>`,
>   no `assignee` by default.
> - For named-session delivery, assign the named-session identity
>   directly: `bd update <bead> --assignee <named-session-identity>`.
> - Clean up the Gastown polecat/refinery formula and prompt text that
>   currently says to set both `assignee` and `gc.routed_to`; that is
>   bad hygiene and can become stale-route confusion later, even if the
>   current direct-assignee path still works.

The three lanes below are the resulting model.

## The three lanes

### Lane 1 — `gc sling <target> <bead>`: queue / template routing

- **When to use:** routing a bead to a pool, queue, or template — the
  cases where any worker matching the target is acceptable. This is
  the default sling path and the dispatch shape used by mayor,
  mechanik, deacon, and refinery when handing work back to the
  polecat pool.
- **Sets:** `metadata.gc.routed_to=<target>`. For a **pool target**
  (an agent that supports instance expansion) it leaves `assignee`
  empty. For a **singleton target** (a named session — no instance
  expansion) it *also* stamps `assignee=<target>`, because the
  singleton's hook skips the Tier 3 routed-pool query and would
  otherwise never surface the bead. That singleton stamp automates the
  ruling's own "assign the named-session identity directly" step, so it
  refines rather than contradicts the "no `assignee` by default"
  decision quoted above.
- **CLI example:**
  ```bash
  gc sling gc-toolkit/gc-toolkit.polecat tk-abcde    # pool: gc.routed_to only
  gc sling gc-toolkit/gc-toolkit.mechanik tk-abcde   # singleton: gc.routed_to + assignee
  ```
- **Does NOT:** set `assignee` **for pool targets** — the reconciler
  picks an available worker from the pool by matching `gc.routed_to`.
  (Singleton targets are the exception just described: sling stamps
  the assignee so the named session's own hook surfaces the work.)
- **Cross-store boundary:** sling routes only *within a single bead
  store*. It refuses to route a bead that lives in one rig's `.beads`
  store to a target (pool or agent) in a *different* rig's store —
  failing with `gc sling: refusing cross-store route: …` — because Gas
  City keeps per-rig isolated Dolt stores. **`--force` does not override
  this:** that flag relaxes only the cross-*rig* name guard, not the
  cross-*store* reachability guard. To hand work to another rig's pool,
  re-file (create) the bead in the *destination* rig's store and sling
  it there; a cross-store sling left unguarded would silently wedge the
  target pool.

### Lane 2 — `bd update <bead> --assignee <named-session>`: direct named-session delivery

- **When to use:** the work must land on one specific named session
  (e.g., a polecat resuming its own bead, mechanik claiming its own
  wisp, mail addressed to a specific identity). When you write the
  named session's identity, you're saying "this work, this agent,
  no fan-out."
- **Sets:** `assignee=<named-session-identity>`. Leaves
  `gc.routed_to` empty.
- **CLI example:**
  ```bash
  bd update tk-abcde --assignee gc-toolkit/gc-toolkit.mechanik
  ```
- **Does NOT:** set `gc.routed_to`. The named session's hook query
  finds the work via assignee, not via routed metadata.

### Lane 3 — `gc sling <target> <bead> --reassign`: combined unassign + route

- **When to use:** park-then-handoff transitions — a human or named
  session was working on the bead, the work is now bouncing back to a
  pool. The single flag clears the prior assignee and routes in one
  step so the bead is never momentarily double-stamped. Added in
  PR #1841 (merged 2026-05-12) to make this transition atomic from
  the caller's perspective.
- **Sets:** `metadata.gc.routed_to=<target>` and clears the prior
  `assignee`. For a **pool target** the assignee stays empty after
  the clear. For a **singleton target** the Lane 1 singleton stamp
  still runs *after* the clear, so the net effect is "prior assignee
  cleared, `assignee=<target>` set."
- **CLI example:**
  ```bash
  gc sling gc-toolkit/gc-toolkit.polecat tk-abcde --reassign   # pool: clear, then gc.routed_to only
  ```
- **Does NOT:** re-assign to a *third party*. `--reassign` itself only
  ever clears the prior assignee — it never names a new one. For pool
  targets the result is *clear* + *route* with no assignee; for
  singleton targets the new `assignee=<target>` comes from the Lane 1
  singleton-stamp rule (the sling target itself), not from
  `--reassign`.

#### `--reassign` idempotency

`TestDoSling_Reassign_NoOpWhenAlreadyEmpty`
(`rigs/gascity/internal/sling/sling_test.go:3809`) pins the
contract: when `assignee` is already empty, `--reassign` is a no-op
on the assignee field — no error, no spurious update. Callers that
don't know the bead's prior state can pass `--reassign`
unconditionally and trust the routing call to be safe.

### Adjacent — targetless sling resolution (`default_sling_target` / `default_sling_targets`)

All three lanes above name an explicit target. `gc sling <bead>` with
**no target argument** is also valid: `gc` resolves the target from the
bead's rig config and routes it through **Lane 1**. Two config fields
feed this resolution, and the plural takes precedence:

- **`default_sling_targets`** (plural, `[]string`) — if non-empty, `gc`
  picks **one entry at uniform random** per dispatch and routes that
  single target via Lane 1 (detail below).
- **`default_sling_target`** (singular, string) — used only when
  `default_sling_targets` is empty.

Whichever field resolves, the target's field contract is exactly
Lane 1's — a **pool target** gets `metadata.gc.routed_to=<target>` and no
`assignee`; a **singleton target** additionally gets `assignee=<target>`
from the same singleton-stamp rule. Resolution only chooses *which*
target Lane 1 receives; it introduces no new field behavior.

The typical configuration points a rig's `default_sling_target` at that
rig's own polecat pool in `city.toml` — e.g. `default_sling_target =
"gc-toolkit/gc-toolkit.polecat"`, the shape the `binding_prefix`
defaults in gc-toolkit's doc-keeper audit formulas assume of every
importing rig. A bare `gc sling <bead>` then lands the bead on the
owning rig's pool via `gc.routed_to`, where the pool's demand-driven
scale_check fans out an ephemeral polecat to pick it up.

- **CLI example:**
  ```bash
  gc sling tk-abcde    # no target → resolves default_sling_target(s), routes via Lane 1
  ```

#### `default_sling_targets` (plural) — random multi-target dispatch

`default_sling_targets` was added by upstream PR #3670 (`feat: add
default_sling_targets for multi-target random dispatch`,
gastownhall/gascity, merged 2026-07-03); the field is
`default_sling_targets = ["rig/a", "rig/b"]` (`[]string`,
`rigs/gascity/internal/config/config.go:645`).

Behavior, read from the resolver
(`rigs/gascity/cmd/gc/cmd_sling.go:291`, verified at gascity/main
`4ff645484`):

- **Precedence over the singular.** The resolver tests
  `default_sling_targets` **first** and falls back to the singular
  `default_sling_target` only when the plural is empty — so when both are
  set, **the plural wins**.
- **Uniform-random pick.** When the plural is non-empty, `gc` selects
  **one** entry uniformly at random per dispatch
  (`rand.Intn(len(rig.DefaultSlingTargets))`) and routes that single
  target through Lane 1; each entry is resolved exactly as a singular
  `default_sling_target` would be.
- **Empty-entry guard.** An empty string entry in the list is a hard
  error (`gc sling: rig %q has an empty entry in default_sling_targets`).

**When to reach for the plural.** A polecat pool already provides
demand-driven elasticity behind a *single* target — scale_check fans
out ephemeral polecats to queue depth — so the plural's static,
client-side random fan-out adds nothing for capacity behind one pool.
It earns its place only when dispatches should be spread across
*distinct named targets* (separate pools, or a mix of pools and named
sessions). Remember the precedence rule: a non-empty plural silently
supersedes a configured singular.

### Adjacent — `gc.run_target` (deprecated wire field; compile-time authoring hint)

`gc.run_target` still appears as metadata on individual template
steps inside graph.v2 formula files — e.g. `mol-review-quorum.toml`
sets it on each review lane and the synthesis step — so you *will*
see it there. But it is **not** a live, parallel routing field, and
it does not route anything at runtime. Upstream PR #2779
(`ga-eld2x`, merged 2026-06-01) made `gc.routed_to` the sole
*persisted* routing key that every runtime demand / claim / scale
reader consults, and demoted `gc.run_target` to a compile-time
recipe-authoring hint: it declares a step's intended config/pool
target for the steps where `assignee` can't be used (check and
control-dispatch steps), and the stampers resolve it **into**
`gc.routed_to` before the bead is persisted. So `gc.run_target` is
an authoring-time precursor to `gc.routed_to`, not a sibling routing
key alongside it — don't conflate the two when you see
`gc.run_target` in formula files. A bare `gc.run_target` left on a
stored bead is inert authoring provenance; `gc doctor --fix`
backfills `gc.routed_to` for any pre-migration workflow root that
still carries only the old field.

## The read side: the claim predicate

The three lanes above are the **write** side — which field each delivery
path sets. This is the **read** side: the predicate that decides which
beads a worker is actually offered. It belongs in this doc because the
routing fields mean only what this predicate makes them mean.

`gc hook` "finds routed work using the agent's `work_query` config"
(`gc hook --help`). The built-in query runs in tiers, and the tiers map
onto the lanes:

- **Tiers 1–2 — assignee match** (the read side of **Lane 2**).
  `bd ready … --assignee=<candidate> --exclude-type=epic`, run for each
  of `$GC_SESSION_ID`, `$GC_SESSION_NAME`, `$GC_ALIAS` in order until one
  matches. A named session finds its own work here, by `assignee` —
  never by `gc.routed_to`.
- **Tier 3 — routed pool** (the read side of **Lanes 1 and 3**).
  `bd ready --metadata-field "gc.routed_to=$target" --unassigned
  --exclude-type=epic`. A pool worker finds work here, and only here.

`bd ready` supplies the rest: it shows "open issues with no active
blockers" and "excludes in_progress, blocked, deferred, and hooked
issues" (`gc bd ready --help`). Spelled out, a bead is offered to a
**pool** worker when **all** of the following hold:

| Term | Requirement |
| --- | --- |
| status | `open` — `in_progress`, `blocked`, `deferred`, `hooked` are excluded |
| blockers | no active blocker (dependency-aware `GetReadyWork` semantics) |
| `gc.routed_to` | equals the pool target |
| `assignee` | empty (`--unassigned`) |
| type | not `epic` (`--exclude-type=epic`) |

### Offer and demand are one predicate, read two ways

The same predicate backs both halves of the pool loop. They differ in
the *shape* of the answer, not in the terms:

- **Offer** (`work_query`) returns the matching beads as a sorted,
  limited list — what `gc hook` hands a live worker.
- **Demand** (`scale_check`) runs the identical filter at `--limit 0`
  and counts the rows — what the pool reconciler scales on.

So "is this bead claimable?" and "does this bead create pool demand?"
have the same answer by construction — do not model them as two
predicates that happen to agree.
[work-bead-state-machine.md](work-bead-state-machine.md) relies on
exactly this when it detaches a gating bead from both queues in one
move (`assignee=""` **and** `gc.routed_to=""`).

### Metadata is not enforcement

Exactly one metadata key participates in the predicate: `gc.routed_to`,
matched via `--metadata-field`. No other key is read, and nothing scans
for a key whose *name* merely sounds like a hold.

The consequence is the non-obvious part. A bespoke park flag —
`rebase_hold=true`, `hold_reason="waiting on the rebase"`, and friends —
is **documentation, not enforcement**. A bead carrying one is still
`open`, still routed, still unassigned; it is therefore still offered,
and a hooked worker can still claim it. The metadata *explains* a hold.
It never *imposes* one.

The failure mode is silent and asymmetric, which is why it is worth
stating here rather than leaving implicit: stamping the flag produces no
error, so the agent that stamped it believes the bead is parked. The
only party who learns otherwise is the next worker — by claiming the
bead and starting the very work the flag was meant to prevent.

### How to actually hold a bead

Remove it from the predicate. The terms are a conjunction, so falsifying
any one is sufficient — but pick a term that covers the tier you care
about:

- **`gc.routed_to=""`** drops the bead out of Tier 3, so it is neither
  offered to the pool nor counted as demand. It does **not** cover
  Tiers 1–2: an `assignee` left behind still surfaces the bead to that
  named session, so clear `assignee` too.
- **Status off `open`** (`blocked`, or `deferred` for a timed park)
  drops the bead out of `bd ready` itself, and therefore out of *every*
  tier at once.

Two combinations are idiomatic, and they differ in intent:

- **`assignee=""` + `gc.routed_to=""`, status still `open`** — detached
  from both queues while still counting as unlanded work. This is the
  gating pattern in
  [work-bead-state-machine.md](work-bead-state-machine.md).
- **Clear `gc.routed_to` *and* set `status=blocked`** — the
  belt-and-braces park, for when the bead should not read as ready work
  at all.

Keep the explanatory metadata either way: a `hold_reason` is genuinely
useful *alongside* a real hold. It is only dangerous as a *substitute*
for one.

There is also a recognized label convention worth preferring over an
invented key — `hold:<value>` labels, which `gc doctor` checks against
the routing fields (`hold-label-routed-to`,
`hold-label-conventions:<scope>`). That those checks exist at all makes
the same point: the label records the intent, the routing fields do the
work, and the two have to be changed together.

## Note: upstream tutorial wording

`docs/tutorials/06-beads.md` (upstream) still says, at line ~389:

> Work is routed to an agent (via assignee or `gc.routed_to`
> metadata)

This conflates Lanes 1 and 2 as parallel routing paths. It is
superseded by the PR #1736 ruling and is expected to be updated by
upstream on its own schedule. Per the gc-toolkit
`upstream-engagement` posture, we do not pre-empt that update; this
local doc is authoritative inside gc-toolkit until upstream catches
up. The upstream `docs/reference/cli.md` already covers the
mechanical `--reassign` flag (one table row at `cli.md:2789`); it
does not cover the broader three-lane model.
