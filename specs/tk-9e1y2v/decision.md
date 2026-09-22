---
name: tk-9e1y2v decision record
description: What the dispatching-work doc documents and why it diverges from the filing bead's stated mechanism; and why the gascity core gc-sling warn/refuse/dry-run change is not carried as a local patch.
---

# tk-9e1y2v — dispatch-pattern doc: decisions and premise reconciliation

Bead: tk-9e1y2v. Provenance: hit during the PR#809 double-dispatch
remediation (mechanik), 2026-09-22.

## What shipped

`docs/dispatching-work.md` — the command-level convention for handing work
to a pool: route a plain work bead with the raw stamp
(`gc bd update <bead> --set-metadata gc.routed_to=<pool>`, or the identical
`gc sling <pool> <bead> --no-formula`); `gc sling` with a formula pours a
molecule and routes the workflow root, not the bead; a bare formula name with
no bead leaves no work bead at all. Cross-referenced from the dispatch
doctrine (`docs/gascity-routing-model.md`, Boundaries).

## Divergence from the bead's stated mechanism (for operator review)

The bead asked to document two claims that the evidence does not support, so
the doc states the accurate convention instead:

1. **"`--on` / `gc formula cook --attach` … not a pool."** `--on <formula>`
   at a pool is the pack's standard molecule dispatch — `signoff.sh:641`,
   `gate-ensure.sh:558/724/821`, `first-reaction-dispose.sh:383` all sling
   `--on` at pools, and `docs/gascity-routing-model.md` Lane 4 documents it.
   (`gc formula cook --attach` is a graft that adds a blocking dep and routes
   nothing; it has no call sites in this repo.) So the axis is not pool vs
   single-session; it is *route a work bead* (raw stamp) vs *pour a specific
   molecule on a bead* (`--on`). The doc is written on that axis.

2. **"Silently creates a DETACHED workflow root NOT attached to `<bead>`."**
   The store shows the opposite. The two roots the incident reaped —
   `tk-pn7l8i`, `tk-pn8c1w` — are `mol-polecat-work` workflow roots each with
   its own synthetic input convoy that *does* track a work bead:
   `tk-goct6q` → `tk-1zdljf`, and `tk-rqk3ip` → `tk-01kbfi` (the bead
   `tk-1zdljf` supersedes). The pour attaches via convoy exactly as the
   routing doctrine describes. The real problem was a double-dispatch of
   supersede-linked beads, each pouring its own `mol-polecat-work` — redundant
   molecules, not detached ones. The durable remedy is the raw-route
   convention (idempotent, one claimable unit), which the doc states without
   asserting a detachment that did not happen.

## Secondary: gascity core `gc sling` change — not carried

The bead flags a `gascity` core change (warn/refuse the pool-formula shape,
fix the `--dry-run` messaging) as optional, to carry as a local patch per
`docs/gascity-local-patching.md` only if taken, and not to file upstream.

Decision: **not carried.** The pack doc resolves the pack-side need, and
`docs/gascity-local-patching.md` says to default to waiting — every local
patch is a tax on rebase and review — unless the bug is hot and unavoidable.
It is avoidable here:

- The raw-route convention sidesteps the whole shape for plain work beads.
- The running `gc sling --help` already documents the pool-formula rule
  (a multi-session formula sling must compile a Ready-visible root; a
  convoy-referencing v2 formula requires a target convoy).
- The binary already refuses a second pour over a live workflow for the same
  bead (`checkLiveInputConvoyWorkflowConflict`, exit 3).

The one genuinely misleading surface is `--dry-run`, which prints an
attach-to-bead the pool run does not perform; the doc names that trap and
tells the reader not to confirm a pool dispatch from the dry-run. If the
dry-run wording is later judged worth a fork patch, it is a standalone change
against `gascity` core, not gated on this bead.
