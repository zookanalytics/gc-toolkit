---
name: Gas City search for landing a gascity rebase by the operator's push
description: The Gas City primitives searched for stopping a finished keeper rebase for the operator's force-push and checking that push once they answer, what each does at a named upstream commit, and why the change composes a human gate, the pack's arm and a one-step formula, and records Gas City's work record on the close. Read it when changing or reviewing mol-upstream-gc-rebase's landing, mol-upstream-gc-rebase-finish or rebase-landing.sh, or when the arch check asks for the search.
---

# Gas City search for landing a gascity rebase

Read on 2026-11-18 at `gastownhall/gascity` main 1bcfacdca309.

## The need

The operator force-pushes each keeper rebase onto the fork's main by hand, and
no agent force-pushes main (their ruling on tk-o5sl9im). So a finished rebase
stops and asks them. The ask has to wait until there is a branch to push, and
it has to carry the exact range-diff and push, with the lease pinned to the
pre-rebase tip, a sha the run learns only at its workspace-setup. Once they
answer, the push's result has to be read and recorded on the rebase bead: the
bead closes as landed, the operator is asked again when nothing was pushed, or
the bead goes back to the keeper when main moved after the rebase. The answer
can come hours later, and nothing should hold a run open while it waits.

## What was searched

- **`[steps.gate]`, a formula step's async wait**
  (`docs/reference/specs/formula-spec-v2.md`, the step-key table in 1.3 and
  "Gates and waits_for" in 2). It synthesizes a gate bead, titled
  `Gate: <type> <id>`, with the rest of the recipe at instantiation, and a
  `blocks` edge from the gated step onto it, "so the addressee can be asked
  before the gated step's `needs` finish". Section 4 adds that no bundled
  watcher resolves any gate type and no bundled formula uses one. It does not
  cover the need. The gate exists from the pour, before the rebase has a branch
  or the lease a sha. Its title is fixed when the formula compiles, so it cannot
  carry the commands. The gated step keeps the run open for as long as the
  operator takes.
- **An order with an `event` trigger** (`docs/tutorials/07-orders.md`,
  "Trigger types"). `on = "bead.closed"` fires whenever that event reaches the
  bus, at least once per close, and the order matches only an event type, with
  no bead to filter on (`Order.On` in `internal/orders/order.go`). Orders that
  fire share `orders.max_dispatches_per_tick`, 4 by default. It does not cover the
  need: the gate's close would reach a script that sorts the landing gates out
  of every close in the city, inside a dispatch budget every order shares.
- **A step Gas City runs with no agent** (`formula-spec-v2.md` 0.2: the
  orchestrator executes every control bead, and agents execute only plain work
  beads). A script runs without an agent only as a check loop's exit condition
  (3.1, where `check.mode = "exec"` is the only checker), after an iteration an
  agent closes, and its verdict decides whether the loop runs again. The landing
  check runs once and writes the outcome itself, so it is one agent step that
  makes one call.
- **`gc sling <target> <bead> --on <formula>`**, which the pack's arm runs when
  the gate clears. Its graph.v2 path passes the bead to `PrepareInvocation` as
  the target (`prepareGraphV2FormulaInvocation` in
  `internal/sling/sling_core.go`), which makes the bead the one member of the
  run's input convoy. A graph.v2 formula's `{{issue}}` is "tolerated as a
  deprecated one-release compat alias" for that member
  (`ValidateGraphV2ReservedSymbols` in `internal/formula/graphv2_validation.go`),
  so the new formula and the new call in `mol-upstream-gc-rebase` pass
  `{{convoy_id}}`, and the script reads the member with `gc convoy status`.
- **The typed work record** (ADR-0009: `Gated` and `ValidateOnClose` in
  `internal/workrecord/gate.go`, and `workRecordCloseTargets` in
  `cmd/gc/work_record_gate.go`). A close of a plain task bead, as `bd close` or
  as `bd update --status=closed`, must carry `gc.work_outcome`, and `shipped`
  needs `gc.work_commit` reachable on `gc.work_branch` in the bead's repository.
  The gate warns, and blocks the close only under `GC_WORK_RECORD_ENFORCE`.
  This covers the landing's record, so the landing check composes it.

## What the change composes

- bd's human gate, filed on the rebase bead through the pack's `human-gate.sh`
  under the key `rebase-landing`, then assigned to the operator, whose push it
  is. Its message carries the range-diff and the leased push, resolved to shas.
- The pack's arm, `gctk bead arm` through `await-ruling.sh`, which slings
  `mol-upstream-gc-rebase-finish` on the bead once the gate clears. Its warrant
  is [the deferred dispatch residual](../../docs/warrants.md#deferred-dispatch-residual).
- `gc sling`'s graph.v2 pour of that formula over the bead's input convoy.
- Gas City's work record on the close of a landed rebase: `gc.work_outcome=shipped`,
  `gc.work_commit` the landed tip, and `gc.work_branch` the branch it landed
  on, written with the close in one `gc bd update` after a fetch brought
  `origin/<target>` current in the rig checkout. The rebase bead's description
  asked for `merge_result=force_lease`, the record the retired refinery overlay
  wrote. It is not written, because the work record says what landed in Gas
  City's own terms, and the pack's registry gives `merge_result` one writer,
  `lifecycle.sh`, and values from the anchor lifecycle, where `force_lease` is
  not one (`lifecycle/lifecycle.toml`).

## What is new

- `mol-upstream-gc-rebase-finish`, one step, and
  `packs/gascity-keeper/assets/scripts/rebase-landing.sh`, with its `ask` and
  `finish` verbs. The script sits in the keeper sub-pack, not in gctk, because
  gctk holds the pack logic that survives the move onto Gas City
  ([gctk-architecture.md](../../docs/gctk-architecture.md)), and the built-once
  shape has no place for the keeper, which exists only while the city runs a
  fork ([built-once-target.md](../../docs/built-once-target.md#keeper-sub-pack)).
- `aborted_at=race-loss`, the keeper's hand-back when main moved, which
  replaces the overlay's `refinery-race-loss`, and `rig_update_result`, which
  the overlay already wrote. Both are keeper keys, and the keeper's prompt reads
  the first.
