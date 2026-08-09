---
name: Operator reactions — build-factory trial (increment 1)
description: Reactions against the five-point checklist in specs/2026-08-fresh-start/build-factory-trial.md, from the run of build-basic on tk-c31ou (workflow tk-6w436) in the existing city on the gc-toolkit rig, 2026-08-08.
---

# Reactions — build-factory trial

Run: brief `tk-c31ou` → workflow `tk-6w436` → artifacts in this directory.
Judged at the decompose gate, per the runbook. Recommendation: **ADAPT**.

## 1. Requirements fidelity

**Good, and deeper than the brief.** No drift. AC-1…AC-5 map one-to-one onto the
brief's five gate assertions; AC-0a/0b were added as the Phase 0 predicate.

It reframed correctly and unprompted: *"What is actually missing is proof, not
prose"* — recognizing the pack already carries `converse/`, `mol-nx-turn`, and the
`task_kind=conversation` reaper skip, so the work is closing an evidence gap, not
writing code. It separated the proven bit of Phase 0 (the `gc session rename`
command, `tools/gc-bead-host.sh:564`) from the unproven bit (pool-session
integration). That is the right read of tk-h9pq5.

Scope it added on its own: **AC-6** (held turn neither starves implementation nor
gets reaped) — fair, implied by brief clause (c). **AC-7** (vehicle neutrality) —
genuine invented scope, derived from an *uncommitted* findings file. It is a
constraint rather than extra work, and it is arguably the smartest idea in the
document, but it was not asked for.

Drift worth knowing: it assumed the gate runs on **signal-loom**, where the brief
said "in the gc-toolkit pack." It flagged this as an assumption rather than
burying it. The plan stage later turned that assumption into an argued decision.

It asked nothing. Six open questions, four resolved by "Assumption taken."

## 2. The tree

**Shape is right; I would not re-cut it.** 8 items, convoy `tk-uvpe5`:

```
W1 probe self-title ──> W2 choose mechanism ──> W3 delta form + drift ──> W4 notes primitive ──┐
W5 same-layer overlay patch ──────────────────────────────────────────────────────────────────┼──> W7 GATE
W6 pool/routing preflight ────────────────────────────────────────────────────────────────────┘
W5 ──> W8 stage-1 confirmations
```

What it got right that a naive cut gets wrong:

- **W7 is one item, not seven.** The seven ACs are one continuous session
  lifecycle (spawn → hold → record → warm vacuum → drain → cold reconstitute).
  Splitting them per-AC is the obvious wrong move and it explicitly refused,
  carrying "a failure inside S6 restarts at S6.1; do not patch the middle of a
  gate run."
- **Phase 0 genuinely sequenced first.** W1→W2 gates everything because the
  prompt's step-2 text depends on the answer. Correct, and easy to miss.
- **W5/W6 correctly parallel** — neither depends on the Phase 0 answer.
- **W4 promoted to its own bead** from a review finding (the unnamed notes
  primitive). That is the right call: it is a blocking gate-correctness gap.

Where I would differ, mildly: **W8 is thin** — it files confirmations rather than
resolving anything, and could fold into W5. And **W5 is on the critical path to
W7 but not to W1–W4**, so it could start immediately; the tree allows this but the
ordering prose de-emphasizes it.

Granularity is right for this work: 8 items, one attended, no bead smaller than a
session's worth of work. Not too fine, not too coarse.

## 3. The interaction — there is no approval mechanism to begin with

**Correction to an earlier framing: this is an absence, not a malfunction.**
`build-basic` ships **no approval gate of any kind**. Grepping every formula in
the pack for `approval_required`, `await_human`, `operator_gate` returns zero
hits. There is no step whose purpose is operator approval, and no "approval
menu" anywhere. (The runbook's phrase "preserves blocking questions and approval
menus" is the runbook's expectation, not an upstream contract. Note also that
`gc.run-operator` is a *role* — an agent — not a human operator; the name
invites the confusion.)

What upstream actually ships is one soft prompt line per stage — e.g. in
`assets/workflows/build-basic/requirements.md`:

> If `interaction_mode` is interactive or the user is present, ask only the
> minimum question needed to unblock the artifact.

That is model discretion, not a mechanism. Asking nothing is *compliant* with
"ask only the minimum needed." So the factory did not fail an interaction
contract; there was never one to fail.

The observable outcome stands: four stages, ~1.5 hours,
`interaction_mode=interactive`, **nothing asked**, 8 beads filed into the rig
with no human yes at any point.

Two things here are genuine defects rather than absences:

- **The review's verdict cannot gate.** `decompose` declares
  `needs = ["plan-review"]` and **nothing reads the artifact's `status`**, so
  `changes_required` is structurally advisory.
- **The decomposer mis-stated its own mode**, writing "Recorded rather than
  asked, **per the headless contract**" while the workflow was configured
  `interaction_mode=interactive`.

It was also *aware* of the questions and answered them itself:

- Requirements: 6 open questions, 4 self-resolved as "Assumption taken."
- Plan-review: verdict **`changes_required`**, explicitly *"5 items requiring a
  decision before decomposition"*, and for R3: *"needs an explicit operator
  ruling."*
- Decompose: **"Recorded rather than asked, per the headless contract"** — it
  invoked the *headless* contract while the workflow was configured
  `interaction_mode=interactive`. It then "**ruled by decomposition**" on R3 and
  R5, the two items the review had reserved for me.

Structural root cause, verified in `build-base.formula.toml`: `decompose` has
`needs = ["plan-review"]` and **nothing reads the artifact's `status`**. So
`changes_required` cannot gate anything. The review knew, and said so as its
reason for editing the plan in place instead of merely reporting:

> Closing this review therefore releases decomposition to read the plan exactly as
> written. A factually false survey finding left in place does not stay a
> documentation defect — it becomes an implementation bead.

Read against the foundation: *agents earn every interaction* is satisfied — it
never wasted my attention. But the inverse has no machinery behind it. **There is
no way for the factory to owe you an interaction**, because no edge in the graph
can wait on one. For a factory whose output is filed work, the approval point is
the product.

**This is why the fix is ADAPT and not configuration.** No var setting and no bug
fix produces a ratification gate, because the gate does not exist to be turned on.
It has to be added as a real dependency edge — which is exactly `mol-nx-plan`'s
shape: the turn blocks the reconcile step, so the tree cannot land unratified.

## 4. Cost

- **Wall-clock: ~1h26m** launch (23:11) → decomposition (01:37). Roughly: 15 min
  requirements, ~20 min dead air, 31 min plan, 22 min plan-review, 17 min decompose.
- **606 agent invocations** (city total 5065 → 5671) across four stages.
- **Dollars: unavailable.** Every invocation is unpriced in this city
  (`EST_USD 0.0000`, "5671 invocations had no pricing"). Cost must be read as
  tokens and wall-clock.
- The ~20 min of dead air between requirements closing and the plan stage
  dispatching is dispatcher latency (see the quarantine finding), not model time.

Order of magnitude: **hours, not minutes** — against a runbook framing of ~10 min
setup and ~15 min judgment. Fine for a one-off trial; it is the number that
matters if this becomes the default path.

## 5. The gap question — what mol-nx-plan promised and I did not get

**Both of the named things are absent, and they are the same absence.**

- **Ratification as a turn — missing entirely.** `mol-nx-plan` files a ratification
  turn on the brief (`turn: <brief> — ratify the plan (rev <rev>)`), and the tree
  lands *only* on `gc.outcome=ratified`. build-basic has no gate at all: it filed
  8 beads with no ratification, no rev, no stamp. The irony is sharp — the tree it
  filed unratified is the plan to *build the ratification mechanism*.
- **Desired-tree re-planning — missing.** `mol-nx-plan`'s plan block is always the
  **full desired tree**, written to the **brief bead's notes**, and filing is a
  **diff against live** — so re-planning is just re-running. build-basic's output
  is *files in `plans/`*, not the record. Re-running it re-files rather than
  reconciling; there is no rev head-pin, no retire-with-ratification, no
  hand-raised-bead protection, no one-brief-one-planning-conversation probe.

The deeper point: mol-nx-plan puts the plan **in the record** and the approval
**in a conversation**. build-basic puts the plan in **files** and the approval
**nowhere**. That is the architectural fork, and it is exactly what tk-h9pq5
Phases 0–1 exist to make possible.

## Recommendation: ADAPT

**Keep:** the stage decomposition (requirements → plan → review → decompose), the
pooled per-stage sessions (each stage its own session, so interruption is genuinely
cheap — the runbook's claim held), and above all **the adversarial review stage**,
which caught a false finding that would have become a destructive bead (B1 below).

**Replace:** the approval model. Graft `mol-nx-plan`'s ratification turn onto the
decompose boundary, and move the tree from `plans/*.md` into the brief's notes as
a rev-pinned plan block so re-planning diffs instead of re-files.

**Fix before any durable use:** the artifact gate does not run here (below).

## Environment findings (upstream coexistence)

1. **The advertised artifact gate never runs in a split city/rig layout.**
   `build-base.formula.toml` sets `path = ".gc/scripts/checks/build-artifact-valid.sh"`
   — relative, resolved against the **rig root**. Upstream assumes city root ==
   rig root. Here `.gc/` is at `/Users/zook/Code/gc-next/.gc/`; the gc-toolkit rig
   root has only `settings.json` + `tmp`. Every stage was control-quarantined
   (`lstat …/gc-toolkit/.gc/scripts: no such file or directory`); the chain
   proceeded anyway. **All four artifacts passed ungated.** The runbook's "each
   artifact schema-checked (`gc.build.*.v1`, 3 attempts)" did not happen, and the
   3-attempt repair loop — much of the factory's claimed value — was inert.
   Compounding: the pack ships the script and its github-issue-fix workflow
   installs it (`cp -R {{pack_root}}/assets/scripts .gc/scripts`); **build-basic's
   prepare step never does.**
2. **The manual fallback validator is also broken here.**
   `validate_build_artifact.py` exits `error: PyYAML is required`; no python3 on
   this host has PyYAML. Caught by the review as N6 — the plan had *claimed* it ran.
3. **Roster coexistence is clean.** 12 roles as `gc-toolkit/gc.*`, `scope=rig`,
   `fallback=true`; roster 24 → 36, no renames, no displacement.
4. **`gc doctor` after import:** 99p/6w/1f → 98p/7w/1f. The new warning is
   `formula-requirements — 34`, all one class, all upstream formulas using the
   deprecated `contract = "graph.v2"` spelling. Warn-only. Version skew between
   gascity-packs 0.4.0 and this `gc`, not a collision.
5. **`gc import add` auto-pinned** to `^0.4` → `0.4.0` (`f69ec02`), satisfying the
   durable-imports house rule the runbook expected to violate. The rig roles import
   is still unpinned.
6. **The launch warning is misleading.** It says the bead description "is not
   carried into the formula's rendered context … the formula's brainstorm will not
   see them." The brief *did* arrive — via the auto-created input convoy `tk-9ddj1`.
   Trusting the warning invites the obvious correction `--var requirements_path=`,
   which would make the factory **reuse** that doc and **skip the requirements
   stage**. If the runbook is reused, pass `--var context_path=<dir>` instead.
7. **The workflow root is not a child of the brief.** `Attached workflow tk-6w436
   to tk-6w436`; `tk-c31ou` stayed OPEN and unrouted. The brief bead does not
   visibly own the work on the board.
8. **Roles run in the rig root** (`/Users/zook/Code/gc-toolkit`), not a worktree —
   the same checkout that is the live `gc-next` import source, against city.toml's
   own "workers build in `.gc/worktrees/`, never in the rig root". All artifacts
   landed as dirty state on `claude/gas-city-pack-architecture-1uyfq2`.

## What the factory caught that I would have missed

Worth recording, because it is the strongest argument for keeping the review stage:

- **B1 — the plan's "F2" was false, and its S4 would have deleted working config.**
  The plan asserted `packs/gc-next/assets/overlays/nx-cycle-recycle/` was an empty
  directory. It ships `.claude/settings.json` and a finished ~90-line
  `.claude/hooks/nx-cycle-recycle.sh` Stop hook. The plan was fooled because
  **`ls` without `-a` shows it empty** — the only child is the dotted `.claude/`.
  S4 said *"removing it is the correct move if the hook is not ready"*, which
  decomposes into a bead telling an implementer to delete a shipped, working hook.
  Verified independently.
- Two real bugs in `gc-next` surfaced by the plan stage and confirmed by review:
  **`gc-role-worker` has no provider on signal-loom** (it imports only `gc-next`,
  which declares no `[imports]`), and the **claim/drain command drift** (upstream
  `gc gc claim` / `--drain-ack` / `gc runtime drain-ack` vs. the prompt's bare
  `gc hook --claim --json`).
- **B2 — AC-6(ii) was vacuous as planned.** `work-health`'s orphan condition is
  unassigned-or-dead with no elapsed-time threshold, so during a live hold the
  `task_kind=conversation` skip is never reached; "not unassigned" would have been
  true whether or not the mechanism existed.
- The review **recomputed all nine `trace.upstream` hashes** and verified schema
  conformance by inspection, precisely because the validator could not run.
