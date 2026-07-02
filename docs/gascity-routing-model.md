---
name: Gas City routing model
description: How `gc sling`, direct assignee, and `gc sling --reassign` differ — and which fields each lane is supposed to set, per the PR #1736 ruling.
---

# Gas City routing model: sling vs assignee vs `--reassign`

## Scope

**Mandate.** How work is routed to agents: how a bead reaches the worker
that will act on it, and — the doc's distinctive charge — which routing
field each delivery path is responsible for setting. It is the authority
on that field-level contract.

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
| PR #3670 — `feat: add default_sling_targets for multi-target random dispatch` (**OPEN + approved, NOT merged** at survey time; not in our deployed `gc`) | gastownhall/gascity | https://github.com/gastownhall/gascity/pull/3670 | 2026-07-02 |

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

### Adjacent — targetless sling resolution (`default_sling_target`)

All three lanes above name an explicit target. `gc sling <bead>` with
**no target argument** is also valid: `gc` resolves the target from the
bead's rig `default_sling_target` config (singular — a single target
string) in `city.toml`, then routes through **Lane 1**. The field
contract is therefore exactly Lane 1's — a **pool target** gets
`metadata.gc.routed_to=<target>` and no `assignee`; a **singleton
target** additionally gets `assignee=<target>` from the same
singleton-stamp rule. Resolution only chooses *which* target Lane 1
receives; it introduces no new field behavior.

This path is **live in our deployed `gc` today.** Every gc-toolkit rig
points `default_sling_target` at its own polecat pool in `city.toml`
(e.g. `default_sling_target = "gc-toolkit/gc-toolkit.polecat"`), so a
bare `gc sling <bead>` in any of our rigs lands the bead on that rig's
pool via `gc.routed_to`, where the pool's demand-driven scale_check
fans out an ephemeral polecat to pick it up.

- **CLI example:**
  ```bash
  gc sling tk-abcde    # no target → resolves default_sling_target, routes via Lane 1
  ```

> **Note: `default_sling_targets` (plural) is upstream-pending — not in
> our binary, and deliberately not adopted.** Upstream PR #3670 (`feat:
> add default_sling_targets for multi-target random dispatch`,
> gastownhall/gascity) adds a plural `default_sling_targets = ["rig/a",
> "rig/b"]` (a `[]string`): a targetless sling picks **one entry at
> uniform random** per dispatch, and the plural form takes **precedence
> over** the singular `default_sling_target` when both are set. As of
> 2026-07-02 that PR is **open and approved but unmerged**, so it is
> **not** a feature of our deployed `gc` — do not describe or rely on it
> as live. We have also **chosen not to adopt** it: the polecat pool
> already gives us demand-driven elasticity behind a *single* target
> (scale_check fans out ephemeral polecats to queue depth), whereas
> `default_sling_targets` is a *static, load- and health-blind*
> client-side fan-out across a fixed named set — no use case here. This
> note records the decision so a future reader asking "why don't we use
> random multi-target dispatch?" finds it.

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
