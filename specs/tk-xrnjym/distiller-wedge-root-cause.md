---
name: feedback-distiller wedge root cause and fix
description: Why the gc-toolkit feedback-distiller order stalled for 13 days in 2026-09, the one-line wedge behind it, and how the fix splits across the pack formula and the gascity engine.
---

# feedback-distiller wedge: root cause and fix

## Symptom

The `feedback-distiller` order stopped firing in the gc-toolkit rig after
2026-09-19. `check-cadence-live` (I10) flagged it: the order had not fired in
over 3× its interval. By 2026-10-02, 261 feedback observations (98 urgent) had
piled up undistilled, oldest from 2026-09-01, growing daily as the miner kept
filing. The learning/feedback pipeline for gc-toolkit was stopped; main city
work was unaffected.

## What happened, in order

1. **The order double-fired.** `gc order history feedback-distiller` shows two
   gc-toolkit pours 15 minutes apart on 2026-09-19 — `tk-55loqe` at 16:24:07Z and
   `tk-4zmgzl` at 16:39:24Z — both judging the same observation corpus. A 24h
   cooldown order must be single-flight; a second pour 15 min into the cooldown is
   a single-flight gate that failed to see the first run as in flight. The engine
   cause is filed as gascity **gc-2c1aw** (the gate under-reads an in-flight wisp
   root: the root is poured then labeled in a separate, non-atomic write).

2. **One worker ceded by blocking.** The `tk-55loqe` worker reached the terminal
   `file-and-dispatch` step, detected the live peer (`tk-4zmgzl`) judging the same
   corpus, and — on a compaction-degraded session — ceded to avoid double-filing.
   It ceded by setting its step `blocked` (`tk-t0c7js`, blocked_reason "ceding to
   the actively-working peer ... Releases when the peer completes or a human reaps
   this redundant pour"). The formula had no sanctioned cede path, so the worker
   improvised one.

3. **`blocked` wedged the molecule.** `mol-feedback-distiller.file-and-dispatch`
   is the terminal step; it closes last and unblocks `workflow-finalize`. Left
   `blocked`, it never closed, so `workflow-finalize` (`tk-12w2bh`) never became
   ready, so the molecule root `tk-55loqe` never finalized and stayed `open`.
   Contrast the sibling `tk-4zmgzl`: its `file-and-dispatch` ran to completion and
   the whole chain closed normally.

4. **An open root holds the cooldown gate shut.** The order's single-flight gate
   counts an open order-run molecule root with any non-closed descendant as a run
   still in flight (gascity `hasOpenWork` / `storeHasOpenDescendants`). So the gate
   stayed shut on every tick and the cooldown never re-armed.

5. **Nothing reaped it.** The gascity controller's automatic order-tracking
   watchdog sweeps only tracking beads (`includeWispSubtrees=false`), never
   molecule roots. The script reaper (`reaper.sh`) does target stale workflow
   roots, but its recursive CTE times out on the large tk store — gascity
   **gc-12tu6** — so it reaps nothing for gc-toolkit. The only cure was manual.

## The one-line root cause

A self-finalizing order molecule left a step `blocked`. An order run's whole
contract is to finalize; a blocked step breaks that silently, with no sweep able
to see it (a `blocked` step sits outside every readiness query) and no reaper
able to clear it (the root is open, so `dead-molecule-dispose.sh` refuses it and
the tk reaper times out).

## The fix, split by where each cause lives

The order config and the formula are gc-toolkit (`orders/feedback-distiller.toml`,
`formulas/mol-feedback-distiller.toml`). The dispatch engine, the single-flight
gate, and the reapers are gascity core (`github.com/zookanalytics/gascity`), which
a gc-toolkit polecat cannot push to.

**Pack-side (this branch), `formulas/mol-feedback-distiller.toml`:** the terminal
`file-and-dispatch` step now states and relies on one invariant — it MUST finalize
(close its bead and drain) on every path, and must never leave itself `open` or
`blocked`. The redundant-pour case the ceding worker hit is named explicitly: a
run whose corpus a concurrent peer already holds is redundant, not blocked — the
existing §6 dedup (judge-and-cluster) drops any proposal a peer filed, so a
redundant run reaches the terminal step with an empty survivor set and finalizes
as an ordinary no-op. A peer that races past the dedup costs at most one duplicate
prompt-update bead, which the operator's review and the next run's veto sweep
absorb; that cost is acceptable and a blocked step is not. After this change a
distiller run cannot wedge the cadence by blocking.

**Engine-side (gascity beads):**

- **gc-2c1aw** — the single-flight gate under-reads an in-flight wisp root and
  duplicate-dispatches the order (the double-fire in step 1). After the pack fix
  this is hygiene, not a stall cause, since a redundant pour now no-op-finalizes.
- **gc-12tu6** — `reaper.sh`'s stale-workflow-root CTE times out on the tk store,
  so a wedged root is never auto-reaped (step 5). A note on it records this
  distiller stall as a concrete high-impact consequence.

Detection already exists and worked: `check-cadence-live` flagged the stall. The
gap was recovery, which the two gascity beads own; the pack fix removes the
specific cause that produced this wedge.

## Clearing the instance

The wedged molecule was verified dead (no live session for any of its incident
sessions) and cleared with the sanctioned manual reaper:

    gc order sweep-tracking --include-wisps feedback-distiller

which force-closes stale order-run wisp subtrees for the named order. With the
root closed the cooldown gate re-arms and the next tick re-dispatches to drain the
backlog.
