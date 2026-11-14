---
name: Gas City search — the arm's verbs, its start and the order that runs it
description: The search behind the operational surface unit 1 of the deferred-dispatch effort (tk-1tfzr71.102) adds, as AGENTS.md requires. It is section 15 of specs/tk-1tfzr71.98/design.md, re-verified at gastownhall/gascity main 8d2fb3120c, and names for each piece the primitive searched and why none covers it. Read it to judge the unit's divergence from Gas City.
---

# Gas City search for tk-1tfzr71.102

Gas City is cited by symbol at `gastownhall/gascity` main 8d2fb3120c
(2026-11-13), the upstream this unit builds against. The search is the design's
section 15 ([design.md](../tk-1tfzr71.98/design.md#15-gas-city-facts-and-the-search-behind-the-surface-the-units-add)),
which read upstream at 3bcab243e and dba20336ed. Between dba20336ed and
8d2fb3120c the one file it cites that changed is `cmd/gc/cmd_sling.go`, in
`deliverSlingNudge`, which delivers a sling's nudge and decides none of the
facts below. The upstream issues were read on 2026-11-13: #7163 and #8832 are
open, and PR #8834, which closes #8832, is open and unmerged, no longer a draft.

The surface this unit adds:

- `gctk bead arm`, `gctk bead disarm` and `gctk bead start-armed`, with
  `start-armed`'s `--dry-run`.
- `orders/deferred-dispatch.toml`'s new `exec`, which runs the start.
- The dispatch lock, a flock(2) file per bead under the city's
  `.gc/runtime/packs/gc-toolkit`.
- The title token `arm:<bead>@<armed at>` on each root the start pours.
- The start's line per arm: what `gctk bead holds` answers for the bead, with
  what the pass did with its arm.

It adds no metadata key, bead kind or lifecycle state: the arm's keys keep the
spellings the script stored them under, and the record takes over their
declaration.

## What was searched, and what covers what

- **A pour on readiness.** No core order or script calls `gc sling`: in
  `internal/bootstrap/packs/core/assets` and `orders`, the command appears only
  in comments of `nudge-on-route`. `cascade-nudge-on-blocker-close.sh` re-reads
  the closes with `gc events --type bead.closed --since`, and nudges each
  dependent `still_held` reports free with `gc session nudge`. `gc sling` pours
  at once: `validateExistingBeadInQuerier` (`internal/sling/sling_core.go`)
  checks only that the bead exists, and no readiness read precedes a pour. So
  nothing covers the arm or the start, and the start composes `gc sling --on
  <formula> --title <title>` for each pour.
- **A launch kept for later, listed or decoded.** No command or order records a
  launch for a later pour, so none reports one, and bd's `list
  --has-metadata-key` selects the rows that carry a key and decodes no value.
  The start's line decodes the arm, a record only the pack keeps. Its hold half
  is `gctk bead holds`' answer, which the start prints as it is.
- **Which armed beads to start.** Gas City's pool serves by
  `PoolDemandServeRulesForQuery` (`internal/config/workquery.go`):
  `--unassigned`, `--exclude-type=epic`, and an `--exclude-label` for each of
  `beadmeta.DispatchHoldLabels` and `beadmeta.HumanLabel`, which are
  `hold:mayor`, `hold:external` and `human`. The start composes it as bd's
  `ready --has-metadata-key gc.dispatch_when_ready` with those flags, rather
  than a rule of its own. The hook drops a candidate carrying a dispatch hold
  in any case (`isHeldHookCandidate`, `cmd/gc/cmd_hook.go`, through
  `beadmeta.HasDispatchHold`), so the start holds one too. bd never holds a
  dependent on a cross-prefix target (`internal/readywork/crossstore.go`), and
  the city's `gc config show` names no class binding, so the start holds a wait
  edge into another store itself.
- **Sending each arm once.** `gc sling` exits 3 only for a
  `*sourceworkflow.ConflictError` (`cmd/gc/cmd_sling.go`), which
  `checkLegacySourceWorkflowConflict` (`internal/sling/sling_core.go`) raises
  for a live root of the same formula the bead's input convoy tracks, or of any
  formula naming the bead in `gc.source_bead_id`, and
  `printSourceWorkflowConflictLines` names each. The start reads that exit and
  its line. `liveConvoyTrackedWorkflowRoots`
  (`internal/sling/sling_attachment.go`) counts only roots that are not
  terminal, and `dryRunReportBlockingMolecule` reports the same check, so
  nothing reports a run that has finished. The title token covers that window:
  `--title` names a formula pour's root (`cmd/gc/cmd_sling.go`), and the start
  searches it with bd's `list --title-contains`.
- **A pour Gas City left unfinished.** `Instantiate`
  (`internal/molecule/molecule.go`) fences each bead it makes one at a time
  with `gc.instantiating`, typed as a gate (`fenceGraphWorkflowBead`), and
  `markFailed` stamps `molecule_failed=true` on a pour that fails part way. The
  launch check counts such a root while it is open and reads neither mark, so
  the start reads both, asks a person through the pack's human gate, and names
  Gas City's `gc convoy delete <root> --force` (`cmdWorkflowDelete`,
  `cmd/gc/cmd_convoy_dispatch.go`) as the close. It ends no run itself.
- **The lock.** Gas City's launch takes a per-bead lock for the length of one
  launch (`sourceworkflow.WithLock`, taken in `withSourceWorkflowLaunchLock`,
  `internal/sling/sling_core.go`), and no command takes it from outside a
  launch, so an arm or a disarm cannot share it. Accept's lock
  (`accept_take_lock`, `assets/scripts/gc-helm.sh`) is the pack's own, and the
  dispatch lock sits beside it in the directory Gas City sets aside for the
  pack's runtime state.
- **The order's exec.** An exec order runs its command through `sh -c` in a
  new process group, which its cancel ends whole (`shellExecRunner`,
  `cmd/gc/order_dispatch.go`), with `GC_CITY_PATH`, `GC_RIG_ROOT` and
  `PACK_DIR` in its environment (`orderExecEnvWithError`,
  `cmd/gc/order_store.go`). So the exec runs the city's gctk build with
  `--db "$GC_RIG_ROOT/.beads"`, and the start runs `gc sling` in that group, so
  the order's timeout ends a sling with the pass.

The fix that retires all of it is upstream's: #8832, with PR #8834, holds a
poured workflow's steps at ready, demand and claim until its input bead is
ready, and #7163 asks for the same gate. Once it lands, the arm becomes a plain
`gc sling` at arm time ([warrants.md](../../docs/warrants.md#deferred-dispatch-residual)).
