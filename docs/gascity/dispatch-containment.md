---
name: Gas City graph.v2 dispatch containment (retired)
description: Retired page. A run poured before it should have been is ended through Gas City's run cancel; this page points to where that, the pack's decline, and withholding a dispatch are documented.
---

# Containing a graph.v2 dispatch already in flight (retired)

This page is retired. It held a hand-run procedure for clearing the delivery
keys on every record a premature pour created while leaving them open. Gas
City ends a run outright through its run cancel, and gc-toolkit's formulas
decline that way, so the procedure is gone.

## Scope

**Mandate.** Pointing a reader who followed a link here to where its topic is
documented now.

**Boundaries.** It states no facts of its own.

## Where the topic lives now

- **Ending a run that was poured too early** is Gas City's run cancel,
  `POST /v0/city/{city}/runs/{run_id}/cancel`, which closes the root and every
  member that is not closed:
  [gascity/packs.md](packs.md#a-run-is-cancelled-through-the-supervisor-api).
- **gc-toolkit's decline** records the wait on the work bead and then cancels
  the run through `assets/scripts/run-cancel.sh`; `mol-polecat-work`'s
  load-context step runs it when the work bead it claimed is still blocked:
  [pack-authoring.md](../pack-authoring.md#a-run-that-must-not-advance-is-cancelled-after-its-wait-is-recorded).
- **Why a `blocks` edge between work beads does not hold a formula dispatch**:
  [gascity/routing-model.md](routing-model.md#a-blocks-dep-between-work-beads-does-not-hold-a-graphv2-dispatch).
- **Withholding a dispatch until its blockers close**:
  [deferred-dispatch.md](../deferred-dispatch.md).
