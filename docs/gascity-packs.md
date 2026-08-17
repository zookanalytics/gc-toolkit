---
name: Gas City pack & formula authoring (gc-toolkit supplement)
description: The non-obvious decisions and traps when authoring gc-toolkit's own pack and formulas on the base Gas City packs — read before adding or changing a formula or pack.toml construct.
---

# Gas City pack & formula authoring

A curated, **non-obvious** supplement for building gc-toolkit's own pack and
formulas on top of the base Gas City packs. It does **not** restate the
upstream specs — it links them and captures only what bites. The canonical,
authoritative sources are:

- Formula contracts — [understanding-formulas](https://docs.gascity.com/guides/understanding-formulas) (guide), [formula-spec-v1](https://docs.gascity.com/reference/specs/formula-spec-v1), [formula-spec-v2](https://docs.gascity.com/reference/specs/formula-spec-v2), [specs index](https://docs.gascity.com/reference/specs)
- Packs — [understanding-packs](https://docs.gascity.com/guides/understanding-packs) (guide), [pack-spec](https://docs.gascity.com/reference/specs/pack-spec)

Read this in ~5 minutes, avoid every trap below, then follow the links for depth.

## Scope

**Mandate.** The non-obvious rules for authoring gc-toolkit's own pack and
formulas against the base Gas City packs — how to choose a formula contract,
how to opt into v2, and the `pack.toml` and pack-layering traps that bite —
synthesized from the canonical Gas City specs so a gc-toolkit builder is
guided to the right call.

**Boundaries.** Curated synthesis, not a copy of the specs: those are linked
and remain authoritative for the full format. This brief does not carry local
fixes against `gascity` *source* — that lifecycle is
[gascity-local-patching.md](gascity-local-patching.md) — and it does not index
the canonical documentation, which is
[gascity-reference.md](gascity-reference.md). It governs *how we author*, not
what any individual formula or pack *does*.

## 1. v1 and v2 are peers, not a ladder

This is the misconception to unlearn first, because it has already produced a
real mis-build here: treating formula **v2** as "newer / better / where we must
head" and **v1** as "legacy." It is not a version ladder. Upstream is explicit:
"v1 and v2 are peer contracts; both are supported. v1 is the **default**"
(formula-spec-v1, intro) and "they are peers, not a version ladder — each makes
a different thing the engine" (understanding-formulas, *Choosing a Compiler
Contract*).

Choose by **what the formula does**, not by version number:

- **v1** — the molecule is *data an agent works through* in its own session;
  the engine is the agent you sling to. Steps resolve at apply and then go
  inert; there is no runtime control flow. This is the right shape for
  prompt-driven coordination and patrol loops where one agent reads the steps
  and self-pours the next cycle.
- **v2** — a runtime-orchestrated **graph of independently-routable step beads**;
  the engine is the orchestrator. It buys `check` / `retry` / `drain` /
  `on_complete` / `timeout`, scope checks, a `workflow-finalize` sink, and
  per-step routing (`gc.run_target`) to many agents and scale-from-zero pools.

**For new orchestration work — default v2** (understanding-formulas, *Choosing a
Compiler Contract*): fan-out over a runtime-discovered set, multi-lane review
loops, orchestrator-driven check-until-pass, cross-agent step routing. For a
self-poured patrol loop, v1 is correct and v2's engine buys it nothing — which
is what gc-toolkit's patrol-style formulas are. The trap is reaching for v2
because it sounds more advanced; if no step ever needs to be independently
routed or re-checked by the engine, v2 is the wrong tool.

Two v1-only edges remain (neither a reason to *start* on v1): `gc converge`
accepts only v1 formulas, and v1 container-dependency semantics have a v2 gap
([gascity#3451](https://github.com/gastownhall/gascity/issues/3451)) — under v2,
enumerate the children you depend on explicitly in `needs`.

## 2. The v2 opt-in is `[requires] formula_compiler = ">=2.0.0"`

The canonical v2 declaration is exactly:

```toml
[requires]
formula_compiler = ">=2.0.0"
```

The older `contract = "graph.v2"` still parses but is **deprecated** — `gc
doctor` warns and tells you to switch (formula-spec-v2, *Conformance →
Opt-in surface* / *Deprecated surfaces*). No `[requires]` table at all means
**v1** (the default).

Graph-only constructs — `check`, `retry`, `drain`, `on_complete`, `timeout`, and
reserved `gc.*` step metadata — require the v2 declaration; a formula that uses
them without it fails to compile. `formula_compiler` is the only `[requires]`
axis; an unknown axis is a hard error.

## 3. `phase = "vapor"` / root-only is legacy v1 — never pair it with v2

`phase` is "**legacy v1 materialization mechanics, not a v2 authoring
choice** … accepted for compatibility and **must not be used to design new
formulas**" (formula-spec-v2, *Top-Level Keys*). `phase = "vapor"` without a
pour compiles a **root-only** recipe: the step beads are never materialized.

So `[requires] formula_compiler = ">=2.0.0"` **on a `phase = "vapor"` /
root-only formula is self-contradictory** — you opt into the orchestrator and
then tell it to materialize only the root, so there are no step beads and no
`workflow-finalize` bead for the engine to run, and the workflow root never
self-closes through the engine's native path. (gc-toolkit hit exactly this: an
audit formula that declared the v2 compiler while keeping `phase = "vapor"`
re-hooked a polecat every cycle, because its root-only recipe had no
`workflow-finalize` bead for the engine to close. The fix is to drop the vapor
line and keep the v2 compiler — not the reverse.)

The reason the legacy hack existed: routing to a scale-from-zero pool needs a
**Ready-visible** surface, and a v1 molecule-container root is not Ready-visible
(`gc sling` rejects it), so `phase="vapor"`/root-only was the v1 workaround. A
**v2 workflow instead materializes independently routable, Ready-visible *step*
beads** that wake the pool without vapor; the workflow root itself depends on
`workflow-finalize` and stays blocked — **not** Ready-visible — while the
workflow runs.
Migrating to v2 is upstream's recommended remedy; the `phase="vapor"` alternative
named in the same error text is the legacy path, not a v2 option
(formula-spec-v2, *Conformance → Differences from v1*).

## 4. A v2 step advances by **closing its own step bead**, not by `drain-ack`

§3 gets you onto the v2 compiler; it does not say what the resulting step
*bodies* must then do. That is where a v1 author's habits break, because the
correct v1 ending is the incorrect v2 ending.

**Every step body closes its own step bead on its way out.** Materialized step
beads are ordinary beads wired together by `blocks` edges, so closing one is
precisely what makes its dependents Ready. Nothing else advances the graph. The
close carries the outcome:

```bash
--set-metadata gc.outcome=pass --status=closed
# failure: gc.outcome=fail + gc.failure_class=transient|hard + gc.failure_reason
```

The base `core` pack's canonical bodies split that idiom across two files:
`assets/prompts/graph-worker.md` carries the full outcome set verbatim — pass,
plus `gc.outcome=fail` with `gc.failure_class=transient|hard` and a
`gc.failure_reason`; `formulas/mol-do-work.toml` carries only the
`gc.outcome=pass` + `--status=closed` closure and the terminal
close-then-drain-ack ordering below (its `drain` step), and never names a
failure class at all.

**Mirror the outcome set, not the target: neither upstream body's `$GC_BEAD_ID`
nor `$GC_TRIGGER_BEAD_ID` names the bead your step is executing.** This is the
one place to deviate from the canonical bodies, because both spellings have been
observed writing to the wrong bead — or to none:

| spelling | what happens | how it fails |
|---|---|---|
| `$GC_BEAD_ID` | unset in the step-execution environment (tk-7w69a) | CLOSED — a guarded close short-circuits, the bead is never closed, and the graph re-offers the step forever at exit 0 |
| `$GC_TRIGGER_BEAD_ID` | not refreshed by `gc hook --claim` (tk-niu2f), so it still names the session's spawn bead | OPEN — the close succeeds against *another live session's* in-progress step |

Close through `assets/scripts/step-close.sh --step <formula>.<step-id>` instead.
It resolves the target from the store by (`assignee`, `metadata."gc.step_ref"`)
— a pair that names exactly one bead and cannot go stale across a claim — and
refuses to write at all when it cannot prove which bead is yours. The pack's
`doctor/check-step-close-owns-bead` holds the line.

**`gc runtime drain-ack` is a session verb, not a step verb.** It tells the
reconciler this session is finished; it closes no bead. So a step body that
drain-acks while still holding its open, assigned step bead is *stranding work*,
and the reconciler reads it exactly that way: it emits
`session.drain_acked_with_assigned_work`, and once the episode ages past the
confirmation grace it **unassigns and reopens the stranded bead** so the pool can
reclaim it (`recordDrainAckAssignedWorkEvent` in
`cmd/gc/session_reconciler.go`, `repairStrandedPoolWorkerBead` in
`cmd/gc/session_beads.go`). The step returns to the pool, a fresh worker
claims it, and the workflow respawn-loops at its entry step indefinitely. It
presents as a routing or pool bug; it is a missing `--status=closed`.

**Terminal steps close, then drain-ack** — in that order.

**The v1 asymmetry is what sets the trap.** Root-only v1 wisps *correctly*
drain-ack without closing anything, so the habit transfers and silently breaks.
A root-only in-session wisp runs every formula step in one worker session and
therefore materializes no step beads and no `workflow-finalize` bead at all; its
root is reaped off the *work issue's* closure instead, by walking
`gc.input_convoy_id` back to the tracking convoy
(`collectInputConvoyWorkflowRoots`, `cmd/gc/wisp_autoclose.go`). A materialized
graph has no such backstop — each step bead is a gate only its own body opens.

**`workflow-finalize` is dispatcher-processed, not self-firing.** The
`gc.kind = workflow-finalize` bead is a control bead: it sits inert until a `gc
convoy control --serve` loop picks it up and runs `processWorkflowFinalize`,
which closes the workflow root first and the finalize bead second
(`internal/dispatch/runtime.go`). No serve loop ticking → the root never closes,
however correct the graph is. **A Ready finalize bead with no dispatcher running
is an operational hold, not a wiring bug** — diagnose it as such before editing
the formula. Do not take `gc agent list` as evidence either way: it derives
status purely from config, so `active` means *configured and not suspended*
(`cmd/gc/cmd_agent.go`), never *serving*.

The evidence that settles it is a ready-query. `gc sling` creates the finalize
bead **unassigned**, routed by `gc.routed_to = control-dispatcher` (the bare
`config.ControlDispatcherAgentName`), so an assignee-only query misses it — the
serve loop's own ready query tries both arms:

```bash
# routed arm — how a sling-created finalize bead is actually picked up
bd ready --metadata-field "gc.routed_to=control-dispatcher" --unassigned --json
# assignee arm — only for a control bead carrying an explicit assignee
bd ready --assignee=<rig>--control-dispatcher --json
```

If the finalize bead comes back in that Ready set, the wiring is fine and the
workflow is purely dispatcher-gated: start the loop.

The mechanics above are source- and pack-level contracts rather than
spec-documented ones, so re-check them against the fork tip before relying on
the details (same caveat as §6). Verified against fork `origin/main` at
`c0571088c`.

## 5. `until` loops (and friends) do not re-execute — "Accepted But Inert"

An `until` loop **runs exactly one iteration**. The compiler validates the
condition and writes a `loop:` label on the first body step, but **nothing in
the current runtime consumes it** — neither the v1 cook path nor the v2 control
dispatcher (formula-spec-v2, *Loops* and *Accepted But Inert*). For
orchestrator-driven re-execution, use a v2 `check` step (*Runtime → Check*) —
and route its iterations to a pool (§6). gc-toolkit's patrols re-run by
**self-pouring the next cycle**, not by `until`.

Treat the whole *Accepted But Inert* section as "parses, but no behavior" — do
not design around it:

- **gate `type` vocabulary** (`gh:run`, `gh:pr`, `timer`, `human`, `mail`) is
  doc-comment vocabulary only; no bundled watcher acts on it.
- **`waits_for` gate modes** — the `all-children` / `any-children` distinction
  is recorded but not interpreted by any dispatcher.
- **`vars.<name>.type`** (`string` / `int` / `bool`) is parsed but never
  enforced; only `required`, `enum`, and `pattern` are validated.

(Also note `until` does not use the `{{var}} == value` step-condition syntax —
it uses the runtime condition grammar, e.g. `probe.status == 'complete'`.)

## 6. `[steps.check]` is fresh-context per iteration **only if pool-routed**

The reason to reach for a check step over an in-session loop is that each
iteration starts in a **fresh context**. That property is **conditional on how
the iterations are routed** — a requirement the spec never states
(formula-spec-v2, *Runtime → Check* documents the run/check machinery only) and
one that **fails silently** when unmet. So: **route a check loop's iterations to
a pool** — sling the formula at a pool target, or set the step's
`gc.run_target` to one. A `check` step cannot carry its own `assignee` (the
compiler forbids combining the two), so routing is the only lever you have.

The mechanism is a source-level contract, not a documented one — re-check it
against the fork tip before relying on the details:

- The predicate is `beadUsesMetadataPoolRouteWithConfig`
  (`internal/dispatch/control.go`): true when the attempt's routed target
  (`gc.execution_routed_to`, else `gc.routed_to`) resolves to a **multi-session**
  agent — one whose config supports instance expansion, i.e. a pool — or the bead
  still carries a legacy `pool:` label.
- A check loop's control bead is `gc.kind = ralph` (upstream display text
  externalizes "ralph" as **check loop**). On a failed iteration the control
  handler clones the next one through `retryPreservedAssigneeWithConfig`
  (`internal/dispatch/ralph.go`): **pool-routed → assignee `""`**, session
  affinity cleared and pool labels stripped, so a *different* pooled worker
  claims it; **otherwise → the prior assignee is preserved** and the same session
  takes iteration N+1 with iteration N still in its context window.
- **Nothing errors or warns on the named-agent path**, and nothing validates it
  at compile time — the misconfiguration is invisible both when you author the
  formula and when it runs. It surfaces only as a loop that gets slower and less
  coherent each iteration.

Because the failure is silent, make pool routing an **acceptance criterion** of
any check-loop formula rather than a preference, and verify it on the first
failed iteration:

```bash
# Iteration beads carry ref <step>.iteration.N. Compare consecutive ones:
# iteration N+1 must NOT come back with iteration N's assignee.
gc bd show <iteration-N-bead> --json   | jq -r '.[0].assignee'
gc bd show <iteration-N+1-bead> --json | jq -r '.[0].assignee'
```

Two adjacent facts worth keeping straight:

- **`[steps.retry]` is a different path with a different failure mode.** Its
  `retry-eval` control (`internal/dispatch/retry.go`) gates an explicit *session
  recycle* on the same predicate, and there the pooled path fails **loudly** — a
  missing `RecycleSession` callback or a pooled subject with an empty assignee
  are hard errors — recording `gc.retry_session_recycled = true` on success. Do
  not look for that marker on a check loop: the ralph path never sets it, and
  each clone strips it.
- **Loop state is crash-safe either way.** A dispatcher restart mid-append
  re-attaches to the iteration beads already created instead of cloning a second
  set (ralph resolves an existing partial attempt first; `[steps.retry]` walks an
  explicit `gc.retry_state` of `spawning` → `spawned`). That is the durable
  property this pack's hand-rolled re-pour loops never had, and why
  `mol-upstream-gc-rebase` — gc-toolkit's first check-loop adoption — replaced
  its file-a-rework-bead-and-re-pour loop with a native one.

## 7. Don't shadow base-pack artifact names

Pack artifacts resolve by **layer**: a higher-priority layer (your pack) with a
formula, prompt fragment, or asset of the **same name** as one in a base pack
**shadows** it (pack-spec, *Per-Directory Breakdown → `formulas/`* describes the
asset/formula layer resolution; *Loader → Naming And Collisions* covers agents).
The cost is silent: a shadowing copy **freezes the base pack's version of that
artifact**, so future upstream fixes to it are masked.

- **Audit by basename collision across layers**, not by reading `pack.toml` —
  an accidental same-name override does not appear in the manifest.
- **Agents are stricter than a shadow:** two agents that resolve to the same
  qualified name on the same surface **fail loading** outright — there is no
  fallback (pack-spec, *Naming And Collisions*). Imported agents are addressed
  by their binding-qualified name (`gastown.mayor`), not the bare local name.
- Most gc-toolkit formulas are authored under pack-distinct `mol-*` names and
  shadow nothing. Preserve that: check the basename against the base packs
  before adding any formula, fragment, or script. Five artifacts are the
  deliberate exception, listed below.

### 7a. The deliberate mirrors, and what to preserve when reconciling them

Five gc-toolkit artifacts *do* shadow a gastown base artifact of the same name.
Each carries a local delta that base does not, so each has to be re-reconciled
by hand whenever base advances. **The delta is the reason the mirror exists** —
a reconciliation that takes base's version wholesale silently restores the
defect the mirror was written to close, and in every case below the restored
defect is one that reports nothing when it fires.

- **`assets/scripts/worktree-setup.sh`** — base + a whitespace-safe
  branch-create argv. Base built the worktree-add invocation as an unquoted
  command string, splitting rig/worktree paths containing whitespace; the mirror
  builds argv via `set --` instead. Native gc-toolkit `polecat-codex` /
  `_polecat-gemini` agents reference
  `{{.ConfigDir}}/assets/scripts/worktree-setup.sh`, and `ConfigDir` does not
  fall through to imported packs.

- **`formulas/mol-deacon-patrol.toml`** — base + cycle-recycle + `gc doctor
  --json` deltas (validated 2026-05-27), plus the dolt-health manifest-mtime
  backup verification (tk-hef7t, 2026-08-01). Base keys its backup verdict off
  `backups.dolt_stale`, which renders absent backup data as `dolt_stale=false`
  and so reads false-clean straight through a TOTAL backup outage. The mirror
  verifies manifest mtime on disk instead (Step 2a) and reads the backup dog's
  failure mail as a second channel (Step 2b). Preserve both — do not restore a
  `dolt_stale`-keyed threshold row. Step 2a carries **six** load-bearing arms,
  and dropping any one restores a false-clean path:
  1. the scan is driven by `databases[].name` (`EXPECTED_DBS`), **not** by a
     walk of `$BACKUP_ROOT/*/` — a database with no backup dir at all is
     invisible to a dir-walk and would emit no verdict;
  2. missing/empty `$BACKUP_ROOT` and an empty database list are explicit
     FLAG-ROOT findings that NAME the affected databases;
  3. the RECHECK grace window keeps a normal in-flight sync from flagging, but
     is bypassed once the manifest is itself stale (a run in flight cannot
     explain a 40 h-old manifest);
  4. backup dirs with no live database are INFO/advisory, never a verdict;
  5. the loop seeds `newest` with the manifest so an equal-second
     manifest/chunk mtime tie resolves to the manifest (tk-40mlc) — `stat`
     reports whole seconds and Dolt commits the manifest LAST, so a tie is a
     fast healthy sync; only a STRICTLY newer file is torn;
  6. the directory scan's exit status is captured and checked, and an
     enumeration that fails (or returns nothing while the manifest is readable)
     is RECHECK/FLAG, never OK — the seed in (5) makes an unreadable directory
     with a fresh manifest look healthy otherwise.

  `assets/scripts/dolt-backup-manifest-check.test.sh` executes the shipped Step
  2a snippet and asserts over the shipped step text; run it after any
  reconciliation of this formula.

- **`formulas/mol-polecat-work.toml`** — base + two `submit-and-exit` deltas
  that stop the step from spending `{{base_branch}}` on a question it does not
  answer (tk-3yj8g, 2026-08-17). `{{base_branch}}` is *what the worktree was
  poured from*; `metadata.target` is *where the work lands*. On a rework child
  those are deliberately different — the signoff dispatch slings the child with
  `--var base_branch=<the reviewed branch>` so the worktree has the PR-only
  files (tk-qqgeo), while `metadata.target` already holds `REVIEW_BASE`. Base
  conflates them twice over, and both misreads fire on the same bead:
  1. **Branch gate (step 1).** Base rebuilds the branch name as
     `polecat/<bead-id>` and fails closed on a mismatch — unreachable for a
     rework child, whose `metadata.branch` names the reviewed branch and whose
     `workspace-setup` step 3 calls that value AUTHORITATIVE and checks it out.
     The mirror gates on the invariant the handoff actually needs,
     `CURRENT_BRANCH == metadata.branch`, and keeps the `polecat/<bead-id>`
     rule for the fresh-work case where `metadata.branch` is unset — so the
     skipped-workspace-setup case base was written to catch is still caught.
     Obeying base here is worse than stalling: cutting `polecat/<bead-id>` from
     the reviewed branch forks it, orphans the pre-open review bead's
     `review_branch` pin, and offers the refinery a second branch to land
     independently of the unopened PR for the first.
  2. **Target resolution (new step 1b).** Base writes
     `--set-metadata target={{base_branch}}` at two sites, rendering
     `target=<the branch being pushed>` on a rework — a self-merge, and a
     strand indistinguishable from a missing merge target. The mirror resolves
     `$LANDING_TARGET` once, before the push: a caller-set `metadata.target`
     always wins, `base_branch` fills in only for fresh work, and a bead that
     can name neither halts with nothing pushed. Both consumers (the
     `auto_push=false` halt arm and the step-5 handoff) read that one variable
     so they cannot disagree.

  The mirror also writes `--append-notes` at both sites where base writes
  `--notes`. That is not a new opinion — `template-fragments/` already tells
  every polecat to make exactly that substitution in this step, because
  `--notes` REPLACES and silently erases the mayor's dispatch note at the
  moment the bead reaches the refinery (tk-6kf6r). The formula now says it
  where the polecat reads it.

  Preserve all three. `assets/scripts/submit-branch-gate.test.sh` executes the
  shipped snippets (extracted between the `submit-branch-gate`,
  `submit-target-resolve` and `submit-target-consume` markers) across the
  fresh, rework, detached-HEAD and malformed-work-order shapes; run it after
  any reconciliation of this formula.
  Take extra care here: this is the formula *every polecat in the city* runs,
  and per §8 a directory-imported pack is live from the working tree, so a
  half-finished edit at this path is deployed before any PR merges.

- **`formulas/mol-refinery-patrol.toml`** — base + `default_merge_strategy` +
  `auto_ff_rig_main` + `check_set` (merge-gate check-set, retiring `review_gate`
  + `signoff_head`) + protected-branch auto-promote + integration-branch INFO
  deltas, plus the pre-existing-failure dedup probe (tk-277aj, 2026-08-10). Base
  tells `handle-failures` to dedup with `bd list --search`, which is not a flag
  — `bd` rejects it on stderr with an EMPTY stdout, the step reads that as "no
  duplicate", and every patrol hitting a pre-existing target failure files
  another P1 for it. The mirror probes with the real flag (`--title-contains`),
  shape-validates the result so an unreadable `bd` cannot masquerade as "no
  match", and reuses one `FAIL_TOKEN` for both the probe and the filed title so
  consecutive patrols actually match. Preserve all three.
  `assets/scripts/preexisting-failure-dedup.test.sh` executes the shipped
  snippet; run it after any reconciliation of this formula.

- **`formulas/mol-witness-patrol.toml`** — base + cycle-recycle + snake_case
  session-list jq + `.work_dir` metadata + completed-workflow quiesce step
  (tk-p9ji9) + stranded-branch recovery step (tk-f69ay) deltas. The
  stranded-branch step is a whole extra link in the patrol chain, so a
  reconciliation that takes base's step list wholesale drops it **and** rewires
  `check-refinery` back onto `recover-orphaned-beads`. Preserve both: the step
  itself and `needs = ["recover-stranded-branches"]` on `check-refinery`. It
  covers the case base has no detector for — work that is committed and PUSHED,
  so every salvage case correctly reports "nothing at risk", while the bead is
  unassigned, unrouted and carries no PR, so no other pass can see it either.
  `doctor/check-stranded-branch-recovery` guards the wiring and
  `assets/scripts/recover-stranded-branches.test.sh` the behavior; run it after
  any reconciliation of this formula.

**Keep this list narrow.** Adding an entry means the rig takes on the cost of
re-reconciling that artifact every time base advances, forever.

**Reconciling a mirror.** Diff the local copy against the base pack's copy,
decide which base advances to fold in, re-apply the local deltas above, run the
named test for that artifact, and commit.

**No automated guard.** `gc-toolkit:check-base-artifact-collision` used to
enforce this section mechanically — ERROR on an un-allowlisted basename
collision, ERROR on a `{{ define "name" }}` in `template-fragments/` whose name
also exists in base (the template engine resolves defines by name, not by file,
so a redefined block silently replaces the base block at render time), and WARN
when base advanced past a frozen snapshot of an allowlisted mirror. It was
retired on 2026-08-15 (tk-3w7p7): it could not locate the base pack under the
import-cache model and had reported `skipped` on every run for roughly two
months, and its reconnection path was a `gc import path` subcommand that was
never merged. Auditing this section is a human step until something replaces it.

## 8. A directory-imported pack is live from the **working tree**, not from a merge

Section 7 is shadowing between pack *layers*. This is the other shadowing —
between the *committed* and the *working* copy of the same path — and it is the
one that makes a green PR a lie. `city.toml` can import a pack by directory:

```toml
[rigs.imports.gc-toolkit]
source = "rigs/gc-toolkit"   # a path: no ref, no version
```

A URL import can be pinned to a commit with `version = "sha:…"`. A directory
import has no such knob at all: the pack's orders, formulas, prompts and
scripts are read from that rig checkout's **working tree**. No git ref is
consulted, so nothing about a merge to `origin/main` changes what is live.
Two silent failure modes follow, and a landing pack-content PR usually trips
both at once:

- **The rig root is behind `origin/main`** — the merged content simply is not
  there. Every git-side check reports success while the live pack is older:
  `git ls-tree origin/main`, the anchor's `merge_result` / `merged_sha`, the PR
  state. `reconcile-rig-checkouts` ff-s each checkout forward on a 15m cooldown
  ([rig-checkout-reconciler.md](rig-checkout-reconciler.md)), so the window is
  usually minutes — but it is open exactly when you go to confirm the landing.
- **An untracked draft shadows the committed artifact** — a file authored in
  place at the destination path and never committed is still sitting there
  after the merge, and it is what the pack reads. It also blocks its own
  repair: `git merge --ff-only` refuses to clobber untracked files, so the
  reconciler cannot advance the checkout and escalates to the mayor instead,
  leaving the rig behind *and* holding the stale draft. The general form is
  worth stating plainly — because the working tree is the deployment, an
  untracked file **is** a deployed artifact, committed or not.

**So verify the DEPLOYED artifact, not the merged one.** In the rig root:

```bash
git rev-list --count origin/main..HEAD   # 0 = nothing local at risk
git status --short                       # ?? at a landed path = a shadowing draft
# remove superseded drafts (back them up first), then:
git merge --ff-only origin/main
diff <(git show origin/main:<path>) <path>   # deployed copy == merged copy
```

Then confirm the executable bit survived and that the artifact registered.
`gc order list` and `gc config show` re-parse **disk**, so they prove the file
is on disk and parses — not that the live supervisor picked it up.

**The convention directories are hot-watched, so an in-place edit is live
surgery.** A config watcher covers the pack's `agents`, `commands`, `doctor`,
`formulas`, `orders`, `template-fragments`, `skills` and `mcp` directories
(`internal/config/revision.go`, `conventionDiscoveryDirNames`); a file event
pokes a rescan that diffs the order set by signature and logs `orders
reloaded: added|changed|removed <name>` (`cmd/gc/city_runtime.go`,
`rescanOrderDispatcher` / `orderSetChangeSummary`). A reload that lands
mid-sync observes the intermediate state, not your intent: deleting a draft
before the ff-merge logs `removed <name>` and leaves the order absent from the
live supervisor while HEAD is already correct and every git check reads clean.
Sequence the change so **one** reload observes the final state, then confirm
re-registration in the supervisor log (`added <name>`) rather than on disk.

## 9. `pack.toml` authoring traps

Use the constructs in pack-spec's *Authoring Summary*; the ones that bite:

- **`schema = 2`, exact.** `[pack].schema` must be `2` for this pack format
  (pack-spec, *`[pack]`*).
- **Durable imports use `source` + `version`.** Declare dependencies as
  `[imports.<binding>]` with a `source` (required) and an optional `version`
  constraint/pin; durable identity is `source` + `version`. **Never** use
  `path`, `ref`, `commit`, or `hash` inside a public import table (invalid
  durable import TOML), and never persist a registry handle like `main:gascity`
  as `source` — handles are command-time lookups only (pack-spec,
  *`[imports.<binding>]`* / *Authoring Summary*).
- **Builtin imports resolve from a binary-seeded cache — so a builtin `version`
  pin is not yours to bump.** Builtin packs are never materialized into the
  city. They compose through the same explicit `[imports.<binding>]`
  declarations, but their sources resolve from a **user-global repo cache** that
  the running `gc` pre-seeds with its own **embedded** copy of each pack at that
  pack's **canonical pin** — which is why they resolve offline, and why the
  retired per-city `.gc/system/packs` tree is pruned on sight rather than
  repopulated (an empty `.gc/system/` is correct, not a broken install). Three
  consequences bite:
  - **Builtin pins track the gc binary's build revision, not upstream HEAD.**
    They advance only when a newer `gc` is installed, so a builtin pin sitting
    behind upstream is expected — not drift to chase.
  - **Hand-bumping a builtin pin silently demotes it to a remote import.**
    `config.IsBundledSourceAtCanonicalPin` gates every synthetic-cache call
    site, so a bundled source pinned at *any* other commit "is an ordinary
    remote import and is fetched for real" — trading offline resolution for a
    network fetch of a tree the binary cannot supply. Advance builtin packs by
    installing a newer `gc` and letting **`gc doctor --fix`** re-pin: its
    `packv2-import-state` check rewrites superseded bundled pins for you
    (`rewriteSupersededBundledPinsFS`). **`gc import install` does not re-pin** —
    it collects the declared imports, syncs `packs.lock` and installs what is
    locked, leaving the declared pin untouched; against a superseded pin it
    fetches that exact superseded commit over the network. That is why the
    not-cached remediation leads with the doctor and keeps `gc import install`
    only as the fallback. The cache marker is a content hash bound to
    the running binary and every production config load routes through
    `ensureBuiltinPacksForConfigLoad`, so a cold or evicted cache self-heals on
    the next command after an upgrade.
  - **`core` and `gastown` are different packs from different repos.** `core` is
    the bundled builtin — `gc-*` skills, default prompts, core formulas, orders,
    doctor checks, provider overlays — and **ships no crew agents**, but it is
    not agentless: it also contributes the scope-local `control-dispatcher`
    lane (qualified `core.control-dispatcher`), a deterministic
    `prompt_mode = "none"` worker that runs `gc convoy control --serve` over
    formula-v2 control beads. So don't go looking in `gastown` for the
    formula-v2 dispatcher: the **crew** (`mayor`, `deacon`, `polecat`,
    `refinery`, `witness`, `dog`, `boot`) is the `gastown` pack, while the
    control lane ships with `core`. `core`, `bd` and `dolt` address subpaths
    of the gascity main repo; `gastown` also publishes from the gascity-packs
    registry.

  Don't read `gc pack list` as evidence here: "No remote packs configured"
  describes the legacy remote-registry mechanism, is orthogonal to `[imports]`,
  and does not mean no packs are loaded. (`cmd/gc/embed_builtin_packs.go`;
  `internal/builtinpacks/registry.go`, `MaterializeSyntheticRepo` /
  `publicSubpathForPack`; `cmd/gc/import_state_doctor_check.go`. Pack contents
  from `internal/bootstrap/packs/core/` — its `pack.toml`, the `all:agents`
  embed in `embed.go`, and `agents/control-dispatcher/agent.toml` — and the
  `gastown` roster from the `gascity-packs` module the binary embeds. Verified
  against `gc 1.4.1`, built from fork `origin/main` at `3983cc049`, 2026-08-13.)
- **`[[patches.agent]]` modifies, never creates.** A patch targets an existing
  agent by its bare local `name` (`dir = ""` in `pack.toml` matches by name
  before rig stamping) and **fails loading if the target doesn't exist**. That
  bare-name tolerance is specific to *agent* patches:
  `[[patches.named_session]]` has no such fallback and matches only
  import-qualified identities (`gc-toolkit.boot`), so reusing this block's
  targeting style there hits nothing and hard-fails the whole `city.toml` load —
  see [gascity-agents.md](gascity-agents.md), Variant A → Lifecycle. Append
  to list fields with the `_append` variants — `inject_fragments_append`,
  `session_setup_append`, `pre_start_append`, etc. — never by re-declaring the
  agent (pack-spec, *`[[patches.agent]]`* / *Loader → Patches*).
- **Private files live under `assets/`.** Scripts, prompt fragments, and overlay
  trees referenced by a definition go under `assets/` (the loader resolves them
  only when referenced). There is **no top-level `scripts/`** directory — `gc
  doctor`'s `v2-scripts-layout` check flags one (pack-spec, *`assets/`*).
- **Banned / replaced in `pack.toml`** (the loader or `gc doctor` rejects these
  — see pack-spec, *Authoring Summary*):

  | Don't write | Use instead |
  |---|---|
  | `[[agent]]` (inline table) | `agents/<name>/agent.toml` + colocated prompt files |
  | `[formulas].dir` | the well-known `formulas/` directory |
  | `[pack].includes` | `[imports.<binding>]` |
  | `[agents]`, `[defaults.rig.imports]`, `[[patches.rigs]]`, `[[patches.providers]]` | city-level only (`city.toml`), not `pack.toml` |

## 10. `{{ .ConfigDir }}` resolves in prompts but is inert in formula bodies

Gas City expands `{{...}}` through **two different engines**, and writing the
prompt form in a formula silently no-ops the formula. Know which surface you
are authoring:

- **Prompts and template-fragments** (`*.template.md`, plus `session_setup` /
  `pre_start` commands) render through Go `text/template` with a populated
  context, so **dotted tokens resolve**: `{{.ConfigDir}}`, `{{.RigRoot}}`,
  `{{.WorkDir}}`. The `pre_start` example in
  [gascity-agents.md](gascity-agents.md)
  (`{{.ConfigDir}}/assets/scripts/worktree-setup.sh …`) relies on exactly this.
- **Formula / molecule step bodies** (`formulas/*.toml` `description`, and a
  step's `title` / `condition` / metadata) are expanded by **plain string
  substitution over a strict `{{name}}` pattern** — `[a-zA-Z_][a-zA-Z0-9_]*`,
  **no leading dot, no spaces** — with **no `text/template` pass at all**.
  Formula vars are that no-dot form (`{{base_branch}}`, `{{binding_prefix}}`,
  `{{event_timeout}}`). A step's `id` is **not** substituted — it is used
  verbatim as the bead's `Ref` / `gc.step_ref`, so it must be a literal.

So a dotted `{{ .ConfigDir }}` in a formula body never matches the var pattern:
it **survives literally and silently no-ops**. An
`[ -x "{{ .ConfigDir }}/assets/scripts/foo.sh" ]` guard written in a formula is
always false, and the script never runs.

**To call a pack script from a formula body, resolve at shell runtime via
exported env — never the token:**

```bash
"$GC_RIG_ROOT/assets/scripts/foo.sh"               # owning rig only (repo == pack)
"$GC_CITY_PATH/rigs/<pack>/assets/scripts/foo.sh"  # also resolves for importer rigs
```

`$GC_RIG_ROOT` points at the agent's own rig checkout, so it finds the script
only for the **owning** rig; the `$GC_CITY_PATH/rigs/<pack>/…` form is the
portable one, because every agent shares `$GC_CITY_PATH` (the city root) and the
script lives in the owning pack's tree under it. Do **not** reach for
`$GC_PACK_DIR` or `$GC_CONFIG_DIR` — they are populated only for order/command
execution and are **not exported to agent or worker sessions**, so a formula
that references them resolves an empty path.
