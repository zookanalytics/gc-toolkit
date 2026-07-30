---
name: Gas City routing model
description: How `gc sling`, direct assignee, `gc sling --reassign`, and the `--on <formula>` attach differ — and which fields each lane is supposed to set, per the PR #1736 ruling.
---

# Gas City routing model: sling vs assignee vs `--reassign` vs `--on`

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
| PR #3670 — `feat: add default_sling_targets for multi-target random dispatch` (merged 2026-07-03) | gastownhall/gascity | https://github.com/gastownhall/gascity/pull/3670; field at `rigs/gascity/internal/config/config.go:645`, resolver at `rigs/gascity/cmd/gc/cmd_sling.go:291`. Verified current at gascity/main `4ff645484`. | 2026-07-16 |
| Lane 4 formula-sling field contract (`--on` attach vs standalone launch) | gastownhall/gascity | Attach routes the source and leaves the wisp root unrouted: `rigs/gascity/internal/sling/sling_core.go:482` (`molecule_id` on source) and the rationale comment at `:488-497`, citing gastownhall/gascity#2848; pinned by `TestOnFormulaAttachesAndRoutes` (`rigs/gascity/cmd/gc/cmd_sling_test.go:4105`, asserting source `gc.routed_to=mayor` at `:4129` and wisp-root `gc.routed_to` empty at `:4151`). Standalone launch routes the root instead: `slingFormula` finalizes on `mResult.RootID` (`sling_core.go:373`). Flags are mutually exclusive at `rigs/gascity/cmd/gc/cmd_sling.go:158`; `AttachFormula` leaves `IsFormula` false (`internal/sling/sling.go:326`) while `LaunchFormula` sets it true (`:305-309`). Reassign gate `shouldReopenForReassign` at `sling_core.go:303-305` with its rationale at `:296-302`, and the `Reassign` field comment at `internal/sling/sling.go:273-279`. Graph.v2 attach returns before routing: `sling_core.go:477-481` → `doStartGraphWorkflow` (`:645-683`). Verified current at upstream/main `1dbf0731e`. | 2026-07-23 |
| Pool demand counts routed **and unassigned** | gastownhall/gascity | `bdReadyPoolDemandShell` at `rigs/gascity/internal/config/workquery.go:41-43` (`bd ready --metadata-field "gc.routed_to=$target" --unassigned --exclude-type=epic`); the jq form applies the same `assignee == ""` filter at `workquery.go:586`. Verified current at upstream/main `1dbf0731e`. | 2026-07-23 |

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

The lanes below are the resulting model. Lanes 1–3 are the ruling's
direct subject; Lane 4 (the formula attach) is the fourth delivery path
that the ruling did not address but that the same field contract has to
answer for.

## The four lanes

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

**One exception — a standalone formula launch.** The reassign reopen is
gated by `shouldReopenForReassign(opts) = opts.Reassign &&
!opts.IsFormula && !opts.DryRun`
(`rigs/gascity/internal/sling/sling_core.go:303`), so on a **standalone formula
launch** (`gc sling <target> <formula>`, Lane 4's second shape)
`--reassign` is a *guaranteed* no-op — not merely idempotent. That is
deliberate, and the guard's own comment
(`internal/sling/sling_core.go:296-302`) gives the reason: reassign
reopens `opts.BeadOrFormula`, which on a launch holds the *formula
name* rather than a bead ID, so honoring it would clear an unrelated
bead that happens to share the name, or fail the launch outright.
Passing `--reassign` unconditionally is still *safe* there; just don't
expect it to clear anything.

This exception does **not** extend to `--on`: an attach sets
`BeadOrFormula` to the real bead ID and leaves `IsFormula` false
(`internal/sling/sling.go:326`), so `--reassign` behaves exactly as it
does in Lane 3.

### Lane 4 — `gc sling <target> <bead> --on <formula>`: formula attach

- **When to use:** the bead needs a multi-step workflow (a *wisp*)
  driving it rather than a bare hand-off — the standard dispatch shape
  for `mol-polecat-work` and the doc-keeper audit formulas. `--on` and
  `--formula` are mutually exclusive
  (`rigs/gascity/cmd/gc/cmd_sling.go:158`); `--on` attaches a wisp to an **existing**
  bead, whereas `--formula` launches a formula that has no source bead.
- **Sets (classic, non-graph formula):** `metadata.molecule_id=<wisp-root>`
  on the **source bead**, then routes that **source bead** through
  exactly Lane 1's field contract (`gc.routed_to=<target>`, plus the
  singleton assignee stamp where the target is a named session). The
  **wisp root is deliberately left unrouted** so it is never
  independently claimed.
- **Sets (graph.v2 formula):** *neither routing field, on either bead.*
  The graph launch path returns before the Lane 1 routing call
  (`internal/sling/sling_core.go:477-481` → `doStartGraphWorkflow`,
  `:645`), so the source bead gets `workflow_id` and **no
  `gc.routed_to` and no `assignee`**; the workflow root is promoted to
  `in_progress` in the **graph store** carrying `gc.source_bead_id`, and
  the per-step routing is stamped on the compiled recipe's steps
  (`internal/dispatch/control.go:1110`) rather than on the work bead.
- **CLI example:**
  ```bash
  gc sling gc-toolkit/gc-toolkit.polecat tk-abcde --on mol-polecat-work
  ```
- **Does NOT:** route the wisp root. This is the inverse of the
  standalone-launch shape below, and it is load-bearing rather than
  incidental — `TestOnFormulaAttachesAndRoutes`
  (`cmd/gc/cmd_sling_test.go:4105`) asserts both halves: the source bead
  ends with `gc.routed_to=<target>`, and the wisp root ends with
  `gc.routed_to` **empty**. The source comment is blunt about why
  (`internal/sling/sling_core.go:488-497`): the source "is the claimable
  unit of work, while the wisp root is deliberately left unrouted…
  Do not 'fix' this to wispRootID — it would orphan the work"
  (gastownhall/gascity#2848).

#### Reading a graph.v2 attach correctly — the duplicate-wisp trap

A work bead dispatched under a **graph.v2** formula shows `gc.routed_to`
absent *and* `assignee` null **while it is fully dispatched**. Per the
paragraph above that is the designed shape, not a stranded bead — so
"no routing fields" is not evidence that dispatch failed. Re-slinging on
that misreading pours a **second** wisp against the same bead, and the
two workers converge on one shared worktree.

To check whether such a bead is really dispatched, look at
`metadata.workflow_id` (graph.v2) or `metadata.molecule_id` (classic
attach) and resolve the wisp root it names — not the bead's own routing
fields.

#### Adjacent — standalone formula launch (`gc sling <target> <formula>`)

The other half of the `IsFormula` split, and the shape most often
confused with `--on`. Here there is no source bead, so the **wisp root
itself is the routed bead** — `slingFormula` finalizes on
`mResult.RootID` (`rigs/gascity/internal/sling/sling_core.go:373`), giving the root
`gc.routed_to=<target>` under Lane 1's contract. A wisp root carrying
`gc.routed_to`, with a title matching the formula name, is therefore
normal for a launch and wrong for an attach. Its graph.v2 variant
behaves like Lane 4's: the root is promoted in the graph store and no
`gc.routed_to` is written (`internal/sling/sling_core.go:363-368`).

#### Why assignee residue silently strands a routed bead

Pool demand does not count "routed" — it counts **routed *and*
unassigned**. The demand probe is
`bd ready --metadata-field "gc.routed_to=$target" --unassigned
--exclude-type=epic` (`rigs/gascity/internal/config/workquery.go:41-43`), and the jq
form applies the same `assignee == ""` filter
(`workquery.go:586`). So a bead that is correctly routed but still
carries a stale `assignee` is **invisible to `scale_check`**, and a
scale-from-zero pool never wakes for it. Nothing errors; the work just
sits. This is the field-contract reason Lane 3 exists — clearing the
assignee is not cosmetic tidying, it is what makes the bead countable
as demand.

### Adjacent — targetless sling resolution (`default_sling_target` / `default_sling_targets`)

All four lanes above name an explicit target. `gc sling <bead>` with
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
does not cover the broader four-lane model.
