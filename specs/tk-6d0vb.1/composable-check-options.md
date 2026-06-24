# Composable-Check Options for the Keystone Close-Condition

> **Bead:** tk-6d0vb.1.4 (child of keystone tk-6d0vb.1) · **Kind:** formalization /
> options doc · **Status:** read-only analysis — proposes nothing for core or
> formulas, recommends a direction for the keystone's next round.

## 0. What this answers

The keystone **tk-6d0vb.1** adopts a *checks-vs-owned* convoy model: a convoy is
either **owned** (an operator/agent is the close-author and lands it when a
*composable close-CHECK-set* clears) or **non-owned** (core auto-closes it when
its children all reach a terminal state). The open question for the owned case is
**how the close-CHECK-set is expressed and evaluated**.

tk-6d0vb.5 found that gascity core already ships a *composable check seam*
(`gc.check_mode` / `check_path` / `check_timeout`; the convergence gate). This
doc deep-dives that seam, establishes **exactly what it can and cannot gate
today**, and lays out three implementation options (pure pack-side / ride the
core seam / hybrid) with a recommendation.

All citations are `path:line` against the trees read on 2026-06-24
(`rigs/gascity` @ `e03fa1b`, `rigs/gc-toolkit`, `~/.gc/system/packs/gastown`).

---

## 1. Existing documentation (Q1)

**There is no single doc that treats this seam as a convoy close-condition.** The
seam *is* documented, but only as two separate features (a graph.v2 step check,
and a convergence-loop gate), and never in connection with convoy lifecycle —
because, as §2.4 shows, it cannot gate a convoy today.

| Doc | Where | Covers | Treatment |
|---|---|---|---|
| `rigs/gascity/docs/reference/specs/formula-spec-v2.md` | §3.1 "Check" (line 652); `check.mode`/`check.path` (662–663) | The `[steps.check]` author surface → compiled `gc.kind=check` control bead, `mode=exec`/`path`/`timeout` | **Primary authority** for the check-kind control bead |
| `rigs/gascity/engdocs/design/inline-ralph-v0.md` | "Check attempt bead" (line 134), "Checker Lane" (line 218) | Metadata layout of a check bead and how the checker lane loads `gc.check_path`/`gc.check_timeout` | Design doc (Ralph v0) |
| `rigs/gascity/docs/reference/cli.md` | "gc converge" | Convergence-loop CLI: gate modes (manual/condition/hybrid), gate timeout/iteration | User-facing CLI ref for the **gate**, not the internal check execution |
| `rigs/gascity/docs/reference/config.md` | "ConvergenceConfig" | Convergence loop limits (`max_per_agent`, `max_total`) | Config schema only |
| `rigs/gascity/docs/reference/specs/formula-spec-v1.md` | "Validation" (~line 513) | Error-message pointer: bare `timeout` routes to `convergence.gate_timeout` | Passing mention |
| `rigs/gascity/engdocs/architecture/nine-concepts.md` | control-bead list | Names `check` among orchestrator control beads (check/retry/fanout/tally/drain/scope-check/workflow-finalize) | Passing mention |

- **gc-toolkit pack** (`rigs/gc-toolkit/docs`, `/specs`, briefs): **nothing** on
  check_mode / convergence gate / check-kind beads.
- **gastown system pack** (`~/.gc/system/packs/gastown`): **nothing**.

**Gap to fill (this doc):** no doc connects the check seam to a **convoy
close-condition**. The keystone needs that connection made explicitly, which is
what §2.4 + §3 do.

---

## 2. The check seam — deep dive (Q2)

The seam is **one primitive with two consumers**. Both consumers run the same
exec-check primitive; they differ only in *what transition the result gates*.

### 2.1 The shared primitive — `RunCondition` (exec check)

`internal/convergence/condition.go:269` `RunCondition(ctx, scriptPath, env,
timeout, retryBudget)` is the single script-execution primitive. It:

- resolves and runs an **executable script** (`exec.CommandContext`,
  `condition.go:319`), with the working dir set to the city / store / work dir
  (`condition.go:320–326`);
- bounds it by `timeout`, captures + truncates stdout/stderr;
- **maps the exit to an outcome** (`condition.go:371–403`):
  - **exit 0 → `GatePass`**
  - **non-zero exit → `GateFail`** (records `ExitCode`)
  - **deadline exceeded → `GateTimeout`**
  - **could-not-exec (not found / not executable) → `GateError`**.

Path resolution + the "must be a regular, executable file" guard live in the
same file (`ResolveConditionPath`, `condition.go:255–262`). Default timeout is
**5m** (`gate.go:11`).

This is the "runs a script, exit-0 = pass, pack-pluggable, zero core change"
primitive tk-6d0vb.5 identified. It is **synchronous** — a blocking subprocess.

### 2.2 Consumer A — the check-kind control bead (gates a **graph.v2 step**)

**Declared** by a v2 formula `[steps.check]` block, which the compiler
materializes into a *control bead* carrying:

```
gc.kind          = check                       # beadmeta/values.go:22 (KindCheck)
gc.check_mode    = exec                         # beadmeta/keys.go:46 (CheckModeMetadataKey)
gc.check_path    = <repo-relative-or-abs script># beadmeta/keys.go:47
gc.check_timeout = <duration>                   # beadmeta/keys.go:48
```

(`gc.check_mode`/`path`/`timeout` are engine-owned keys, `beadmeta/keys.go:46–48`;
authored surface documented in formula-spec-v2 §3.1.)

**Evaluated** by the **control dispatcher**, synchronously, when it processes the
open control bead: `internal/dispatch/runtime.go:99` `ProcessControl` switches on
`gc.kind` (`runtime.go:121`) and routes `KindCheck` → `processRalphCheck`
(`runtime.go:126–127`). `processRalphCheck` (`internal/dispatch/ralph.go:21`)
requires `check_mode == "exec"`, then `runRalphCheck` (`ralph.go:143`) resolves
the path and calls **`convergence.RunCondition`** (`ralph.go:242`) against a
*subject bead*. Outcome handling (`ralph.go:63…`):

- `GatePass` → close the check "pass", advance the step;
- attempt ≥ max-attempts → "fail";
- otherwise → retry (re-pour, bounded by `gc.max_attempts`).

This is **single-controller, synchronous** (`runtime.go:95–98` notes the runtime
assumes one controller per workflow root; it is *not* a CAS guard). It gates a
**graph.v2 / workflow STEP transition** — nothing larger.

> Sibling kinds on the same switch (`runtime.go:128–139`): `scope-check`
> (`processScopeCheck`) gates a *scope*, `workflow-finalize` finalizes a graph.v2
> root. Neither targets a convoy either.

### 2.3 Consumer B — the convergence gate (gates a **convergence-loop iteration**)

**Declared** as convergence metadata on a `type=convergence` root bead:
`ParseGateConfig` (`internal/convergence/gate.go:44`) reads `FieldGateMode`
(`manual`/`condition`/`hybrid`), `FieldGateCondition` (script path),
`FieldGateTimeout`, `FieldGateTimeoutAction` (`iterate`/`retry`/`manual`/
`terminate`).

**Evaluated** by the **convergence handler** when a wisp closes:
`HandleWispClosed` (`internal/convergence/handler.go:161`) → `ParseGateConfig`
(`handler.go:220`) → `evaluateGate` (`handler.go:327,729`), which for
`condition`/`hybrid` modes calls **`RunCondition`** (the same primitive). The
outcome decides loop control:

- `GatePass` → terminate the loop **approved**;
- `GateFail` (non-manual) → **iterate** (pour the next wisp) or fall to
  waiting_manual/waiting_trigger;
- `GateTimeout` → per `TimeoutAction` (iterate/retry/manual/terminate);
- `iteration ≥ max` → terminate **no-convergence**.

It gates **whether a convergence loop iterates or terminates** — again, nothing
larger. A convergence loop's root is a **freshly created `type=convergence`
bead** (`internal/convergence/create.go:79`), *not* a convoy.

### 2.4 What it can and cannot gate — the make-or-break boundary

| Transition | Gated by the check seam? | Evidence |
|---|---|---|
| graph.v2 / workflow **step** | ✅ yes (check-kind bead) | `runtime.go:126`, `dispatch/ralph.go:21,242` |
| graph.v2 **root finalize** | ✅ (separate `workflow-finalize` kind) | `runtime.go:138` |
| **scope** check | ✅ (separate `scope-check` kind) | `runtime.go:136` |
| convergence **loop iteration** | ✅ yes (convergence gate) | `handler.go:161,327` |
| **convoy close** | ❌ **no** | see below |
| **convoy land / graduate** | ❌ **no** | see below |

**`gc convoy land` is hard-coded membership-state, with no check/gate hook**
(`cmd/gc/cmd_convoy.go`, the land path ~1753–1810):

1. bead must be `type==convoy`;
2. **must carry the `owned` label** (`!hasLabel(convoy.Labels, "owned")` → reject);
3. idempotent if already terminal;
4. **every child must be terminal** (`openChildren > 0 && !--force` → reject);
5. then `closeConvoyWithReason(..., convoyLandCloseReason)` unconditionally.

Non-owned convoys auto-close on the same membership rule (all children terminal)
via the in-process autoclose path; **owned convoys are explicitly skipped** by
autoclose (tk-6d0vb.5; `cmd_convoy.go` doConvoyCheck / autocloseConvoyIfComplete).
There is no third "checks-gated" convoy mode in core.

**Boundary proof.** A grep for any convoy reference to the seam returns
**nothing**:

```
$ grep -rn 'convergence|check_mode|CheckMode|RunCondition|ParseGateConfig' \
        internal/convoy/ cmd/gc/cmd_convoy.go   # (excluding _test.go)
(no matches)
```

**Conclusion:** the core check seam can gate a **graph.v2 step**, a **graph.v2
root finalize**, a **scope**, or a **convergence-loop iteration** — but it
**cannot gate a convoy's close or `gc convoy land` today**. Using it as the
keystone's *convoy* close-condition requires either (a) new core wiring (a
convoy-close evaluation point), or (b) a pack agent that drives the check itself
and is the convoy's close-author. This is the pivot the three options turn on.

> Caveat carried from tk-6d0vb.5: in-process autoclose fires on **every** bd
> close with **no disable seam**. So a pack agent cannot be the *sole* close
> author for **non-owned** convoys without a core change. For **owned** convoys
> (our case) autoclose already steps aside, so a pack close-author is unobstructed.

---

## 3. Options for the keystone close-condition (Q3)

Three ways to express "this owned convoy closes when its composable check-set
clears." The decisive column is the last one.

### Option A — Pure pack-side (the refinery formula evaluates checks)

The refinery (`rigs/gc-toolkit/formulas/mol-refinery-patrol.toml`) is already the
close-author for mr-mode work and convoys ("closes the bead once the PR is
verified", formula line 28). The **running rework, PR #163 (sibling
tk-6d0vb.1.1, "close-on-merge")**, keeps the work bead OPEN as a gating anchor
and lets a refinery reconcile pass close it when the PR merges — i.e. checks are
ordinary pack logic the refinery runs.

- **Zero core change?** ✅ Yes.
- **Who evaluates?** The refinery agent (pack).
- **Sync/async?** Async relative to work — evaluated on the refinery's idle
  reconcile cadence; convergent + idempotent.
- **Composability?** Whatever the formula expresses (deps, merge_result,
  reconcile scripts). Not a first-class "check object".
- **Durability?** Bead metadata + the reconcile backstop; no core-managed state.
- **Observability?** Bead notes / refinery trace. No core events for "check passed".
- **Gate a convoy close *today*?** ✅ **Yes** — the refinery already closes owned
  convoys; nothing in core obstructs it (autoclose skips owned).

### Option B — Ride the core seam (checks as check-kind beads / convergence gate)

Express each close-check as a core check-kind control bead (or a convergence
gate-condition) and let core evaluate it.

- **Zero core change?** ❌ **No.** The seam gates graph.v2 steps / convergence
  loops, never a convoy (§2.4). To gate a convoy *close* you must add a new core
  evaluation point (e.g. a convoy-close gate that runs `RunCondition` before
  `closeConvoyWithReason`, or a convoy "convergence root").
- **Who evaluates?** Core (control dispatcher / convergence handler).
- **Sync/async?** Check bead = sync, single-controller; convergence gate =
  loop-driven.
- **Composability?** **Highest** — each check is a first-class bead with uniform
  semantics (exit-0=pass, path resolution, timeout, output capture, retry).
- **Durability?** **Strongest** — core-managed bead lifecycle + events.
- **Observability?** **Best** — `gc.exit_code`, gate results, dispatcher trace.
- **Gate a convoy close *today*?** ❌ **No** — needs the new wiring above.

### Option C — Hybrid (core primitive, refinery orchestrates)

Reuse the **exec-check contract** from §2.1 (exit-0=pass, repo-relative script,
timeout, truncation) as the *definition* of a check, but let the **refinery**
materialize/drive the checks and act as the owned convoy's close-author. Either
the refinery shells the check scripts directly under the same contract, or it
pours check-kind control beads and reads their outcomes — without asking core to
gate the convoy.

- **Zero core change?** ✅ Yes (the refinery drives evaluation; core is unchanged).
  Becomes "low core change" only if you later choose to pour real check-kind beads
  and want core to dispatch them.
- **Who evaluates?** The exec-check primitive's contract, *invoked by the
  refinery*.
- **Sync/async?** Refinery-paced (async, convergent), each check sync.
- **Composability?** High — a check-set is a list of scripts honoring one
  contract; reuses core's semantics instead of reinventing them.
- **Durability?** Bead metadata + reconcile backstop; upgradeable to core-managed
  if checks become check-kind beads.
- **Observability?** Reuses the exec-check fields (exit code, stdout/stderr)
  surfaced via the refinery.
- **Gate a convoy close *today*?** ✅ **Yes** — close authority stays in the pack,
  where it already works for owned convoys.

### Side-by-side

| Criterion | A · Pure pack-side | B · Ride core seam | C · Hybrid |
|---|---|---|---|
| Zero core change | ✅ | ❌ (new convoy-gate wiring) | ✅ |
| Evaluator | refinery | core dispatcher/handler | exec-check contract, refinery-driven |
| Sync vs async | async/convergent | sync (check) / loop (gate) | async/convergent, each check sync |
| Composability | formula-level | highest (first-class beads) | high (shared contract) |
| Durability | bead + reconcile | core-managed | bead + reconcile (upgradeable) |
| Observability | bead notes | core events/trace | reused exec-check fields |
| **Gate convoy close *today*** | ✅ yes | ❌ no | ✅ yes |
| Reinvents check semantics? | yes (ad-hoc) | no | **no (reuses §2.1)** |

---

## 4. Recommendation + minimal path (Q4)

**Recommend Option C (hybrid), with Option A's PR #163 as the already-shipping
baseline it grows out of. Do not adopt Option B for the close-condition now.**

Rationale:

1. **Only A and C can gate an owned convoy's close today** (§2.4). B needs new
   core wiring to reach a convoy at all, so it cannot be the near-term answer and
   would couple the keystone to a core change the keystone explicitly avoids.
2. **C keeps the keystone's locality-of-truth** — the pack stays the close-author
   for owned convoys (the model tk-6d0vb.1 already adopts) — **while not
   reinventing check semantics**: it borrows core's exec-check contract (exit-0=
   pass, path resolution, timeout, truncation, `gc.exit_code`). A is the same
   close-author but spends ad-hoc formula logic where a uniform contract is
   cheaper and more legible.
3. **B remains the principled long-term shape** *if* checks ever need to be
   core-durable, async, or operator-observable as first-class beads. The hybrid
   leaves that door open (C can graduate to pouring real check-kind beads) without
   paying the core-change cost now.

**Minimal path:**

1. **Keep PR #163** (close-on-merge / gating-anchor) as the convoy close-author
   mechanism — it is the running baseline and already valid pack-side. The
   composable check-set layers *onto* it, it does not replace it.
2. **Define a check-set contract in the pack** that mirrors §2.1: an ordered list
   of repo-relative executable scripts, **exit-0 = pass**, per-check timeout,
   captured output. Reuse the exact semantics so a future migration to core
   check-kind beads is a re-wiring, not a redesign.
3. **Have the refinery evaluate the check-set** on its idle reconcile pass before
   closing/landing the owned convoy (convergent + idempotent, like the existing
   reconcile passes); a failed check leaves the convoy open with the failing
   check recorded on the anchor.
4. **Do not touch core.** Treat a core convoy-close gate (Option B) as a *deferred
   follow-up*, filed only if/when checks must be core-durable or async — and note
   the `owned`-skip + no-autoclose-disable-seam constraints from tk-6d0vb.5 as
   preconditions for that work.

### Appendix — file:line index

| Fact | Citation |
|---|---|
| Check metadata keys (engine-owned) | `rigs/gascity/internal/beadmeta/keys.go:46–48` |
| `KindCheck = "check"` | `rigs/gascity/internal/beadmeta/values.go:22` |
| Control-bead dispatch switch (`KindCheck`→`processRalphCheck`) | `rigs/gascity/internal/dispatch/runtime.go:99,121,126` |
| Check bead runs the exec primitive | `rigs/gascity/internal/dispatch/ralph.go:21,143,242` |
| Shared exec primitive `RunCondition` | `rigs/gascity/internal/convergence/condition.go:269` |
| Exit→outcome mapping (0=pass) | `rigs/gascity/internal/convergence/condition.go:371–403` |
| Gate config parse (modes/timeout) | `rigs/gascity/internal/convergence/gate.go:44` |
| Convergence gate evaluation | `rigs/gascity/internal/convergence/handler.go:161,327,729` |
| Convergence root is `type=convergence` | `rigs/gascity/internal/convergence/create.go:79` |
| `gc convoy land` precondition (owned + children terminal) | `rigs/gascity/cmd/gc/cmd_convoy.go:1667` (cmd), `:1753` (owned-label reject), `:1774` (open-children reject) |
| Convoy↔seam boundary (empty grep) | `internal/convoy/`, `cmd/gc/cmd_convoy.go` — no convergence/check_mode refs |
| Primary author doc (check) | `rigs/gascity/docs/reference/specs/formula-spec-v2.md` §3.1 (line 652) |
| Design doc (check attempt bead) | `rigs/gascity/engdocs/design/inline-ralph-v0.md:134,218` |
| Pack close-author (refinery) | `rigs/gc-toolkit/formulas/mol-refinery-patrol.toml:28` |
| Running baseline (close-on-merge) | PR #163 / tk-6d0vb.1.1 |
