---
name: Findings — build-factory trial (live run)
description: Findings relayed from the live build-factory trial run in the operator's city (brief bead tk-c31ou, conversation-spine brief). Numbering follows the trial session's own findings list; entries here are the ones relayed to the fresh-start branch so far. Verdict lands in gas-city-native.md when the run reaches the decompose judge point.
---

# Findings — build-factory trial (live run)

Run context: existing city, gc-toolkit rig; brief bead `tk-c31ou`
(conversation spine, per [build-factory-trial.md](build-factory-trial.md));
requirements stage bead `tk-ged72`. Numbering is the trial session's own;
gaps in the sequence are findings not yet relayed here.

## F4 — the launch warning is misleading, and the obvious correction is destructive

A warning at launch suggests the factory lacks context it in fact
receives: the **input convoy delivers the brief's referenced material even
though the rendered context does not show it** (observed: the
requirements-planner reading the converse prompt reference it could only
have found via the brief bead). The trap: an operator who trusts the
warning will over-correct, and the obvious correction —
`--var requirements_path=<doc>` — makes the factory **reuse that document
as the requirements artifact and skip the requirements stage entirely**,
silently destroying the trial's first checklist item (requirements
fidelity). The safe way to hand the factory extra context is
`--var context_path=<dir>`.

**Status:** real ergonomic trap, not fatal. **Upstream-PR candidate** (the
warning text should say the input convoy carries bead-referenced context,
and the var docs should distinguish `context_path` from the
stage-skipping `*_path` vars). Candidate recorded here per the
upstream-engagement doctrine; not yet filed.

## F8 — stage handoff is genuinely autonomous (the run's strongest positive so far)

`gc.run-operator` validated inputs, closed `prepare`, drained — and
`gc.requirements-planner` spawned on its own for the next stage, **no
keystroke between stages**. Each stage runs as a separate pooled session.
Two consequences:

- The runbook's "interrupt at decompose costs nothing" claim is
  **validated in practice**, not aspirational — stages are separate
  sessions over durable artifacts, so stopping between them is a clean
  boundary.
- This is the same demand-spawns-session mechanic the conversation spine
  bets on (turns as routed beads), observed working across a five-stage
  chain in production upstream code — indirect but real evidence for
  increment 2's core mechanism.

---

## Full-run record

The complete judgment lives in
[build-factory-trial-reactions.md](build-factory-trial-reactions.md)
(authored by the trial session at the decompose gate, forwarded by the
operator 2026-08-08). Verdict: **ADAPT** — keep stages, pooled sessions,
and the adversarial review; replace the approval model with
`mol-nx-plan`'s ratification turn and record-resident rev-pinned plan.
This file remains the ledger of the *derived* items below.

## Upstream-PR candidates (from the run)

1. **Misleading launch warning** (F4/env-6): says the bead description is
   not carried into the rendered context, while the auto-created input
   convoy delivers it; the warning invites the stage-destroying
   `requirements_path` correction.
2. **The artifact gate silently never runs in a split city/rig layout**
   (env-1): `[steps.check]` path `.gc/scripts/checks/build-artifact-valid.sh`
   is relative to the rig root; stages control-quarantine and proceed
   ungated. Compounding: `github-issue-fix` installs the scripts,
   `build-basic`'s prepare does not.
3. **`decompose` ignores the plan-review verdict** (§3): `needs =
   ["plan-review"]` with nothing reading the artifact's `status`, so
   `changes_required` is structurally advisory. (Upstream may consider
   this by design; the finding is that the verdict *looks* load-bearing
   and is not.)
4. **The decomposer invoked the headless contract under
   `interaction_mode=interactive`** (§3) — mode plumbing or prompt bug.
5. **Fallback validator requires PyYAML** with no dependency declaration
   (env-2).

## Carryovers into increment 2 (the conversation spine)

Banked here so the spine work inherits them:

- **The claim-command drift is live**: the converse prompt's delta must
  be expressed against upstream's current `gc gc claim` /
  `gc runtime drain-ack` contract, not the older `gc hook --claim`
  citations (confirmed as a real bug by the run's review).
- **`gc-role-worker` has no provider on signal-loom** as imported —
  provider wiring is part of W6's pool/routing preflight, not an
  afterthought.
- **B1 stands as a warning**: `nx-cycle-recycle` ships a working Stop
  hook that `ls` without `-a` hides; any bead touching that overlay must
  not treat it as empty.
- **AC-6(ii) as originally planned was vacuous** (orphan condition never
  reaches the skip during a live hold) — the gate assertion needs an
  elapsed-time-threshold-aware formulation.
- **Workflow root was not a child of the brief** (env-7): `tk-c31ou`
  stayed open and unrouted — the board cannot see the brief owning its
  work. The spine's turn-filing convention must not repeat this shape.

## Pre-implementation blockers (before the filed tree runs)

The 8-bead tree (convoy `tk-uvpe5`) is judged right-shaped, but three
things gate letting implementation beads actually run:

1. **Worktree hygiene** (env-8): roles ran in the rig root — the live
   quarry-branch checkout — leaving artifacts as dirty state on
   `claude/gas-city-pack-architecture-1uyfq2`, against the city's own
   workers-build-in-worktrees rule. Clean the checkout and enforce the
   worktree path before any W-bead executes.
2. **Apply the operator's tree amendments**: fold W8 into W5; note W5
   can start immediately (parallel to W1–W4).
3. **Ratification on the record**: the reactions doc is the de-facto
   ratification; stamp it (a note on `tk-c31ou` pointing at the
   reactions file) so the tree does not stand unratified — the exact
   defect the trial surfaced, not repeated on our own work.
