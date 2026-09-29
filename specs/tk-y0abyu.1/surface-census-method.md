---
name: Operating-surface census — method and baseline reconciliation
description: The definitions assets/scripts/surface-census.sh measures the gc-toolkit operating surface by, and why the oracle's batch-1 numbers differ from the manual baseline the surface-shrink epic (tk-y0abyu) recorded.
---

# Operating-surface census

`assets/scripts/surface-census.sh` is the epic's oracle: run it for the current
surface numbers (`--json` for a machine object). This record fixes the
definitions it counts by, and reconciles its first reading with the manual
baseline in the epic body, so checkpoint 1 can re-aim the provisional targets
against a known method rather than re-deriving one.

## What each measure counts

- **source scripts** — `assets/scripts/*.sh` that are not `*.test.sh`, with
  their total line count. This is the shell operating surface; the oracle is one
  of them (it counts itself).
- **outside-startable** — source scripts whose filename is referenced from the
  execution surface outside `assets/scripts`: `formulas`, `doctor`, `services`,
  `tools`, `orders`, `agents`, `template-fragments`, `packs`, `lifecycle`,
  `overlays`, `.github`. A script named only in `docs`/`specs` is a
  documentation mention (**docs-only**), not an entry point; a script named
  nowhere outside the layer is **internal-only**. The three partition the source
  scripts exactly.
- **metadata keys** — distinct bead-metadata keys the executable operating
  surface (`assets/scripts` + `formulas` + `doctor`) reads or writes, via
  `--set-metadata` / `--unset-metadata` / `--metadata-field` flags and the jq
  accessors `.metadata.KEY`, `.metadata["KEY"]`, `.metadata."KEY"`,
  `metadata["KEY"]`. **bare** keys carry no dotted namespace; **single-use**
  keys appear in exactly one file. Three surfaces are held out on purpose:
  `*.test.sh` (fixture keys, not the contract), full-line comments (a key named
  in prose is documented, not used), and `services` (its Go/TS `.metadata` is a
  different, non-bead structure).
- **drifted helpers** — shell function names defined in three or more source
  scripts: copy-pasted helpers that have drifted or will.

## Reconciliation with the manual baseline

The epic body (visit tk-fw8w1w, 2026-09-29) recorded the surface manually. The
oracle at batch-1 landing reads:

| measure | manual baseline | oracle (this checkout) |
|---|---|---|
| source scripts | 88 (~32.4k lines) | 89 / 32665 — the +1 is the oracle itself |
| outside-startable | 72 of 88 | 71 |
| metadata keys | ~176 | 150 |
| — un-namespaced (bare) | 74 | 65 |
| — single-use | 45 | 76 |
| drifted helpers | 25 | 24 |

Source scripts, bare keys, outside-startable, and drifted helpers agree within a
script or two — the manual eyeball was close. Two gaps are method, not error:

- **metadata total (150 vs ~176)** — the manual `~176` counted test fixtures
  and prose mentions; the oracle holds both out, counting only the live contract
  the operating surface reads or writes.
- **single-use (76 vs 45)** — the precise per-file count finds more one-file
  keys than the manual estimate. This widens, not narrows, the consolidation
  target the epic is after.

The epic states the numeric targets are provisional until checkpoint 1 re-aims
them; the oracle is the method they re-aim against.
